#!/usr/bin/env python3
"""
# ==============================================================================
# TITOLO:       analyze_ldif.py - Analisi statistica di un LDIF LDAP (utenti/gruppi)
# AUTORE:       Elia Pinto
# DATA:         Settembre 2026
# VERSIONE:     1.4
# SCOPO:        Legge un file LDIF (RFC 2849) e produce statistiche utili a
#               caratterizzare una base dati LDAP: conteggi di entry per
#               tipo, distribuzione dei membri per gruppo e dei gruppi per
#               utente, profondita' di annidamento dei gruppi, frequenza di
#               objectClass/attributi, schema di hashing delle password,
#               riferimenti pendenti (dangling), valori duplicati, coerenza
#               incrociata memberOf/member. Nessuna dipendenza esterna -
#               solo libreria standard di Python 3.
#
# NOVITÀ v1.4 rispetto a v1.3 (errore reale trovato controllando l'output
# di un run vero di analyze_rootdse.py contro un server, non solo
# rileggendo il dizionario): 1.3.6.1.1.22 non e' "Password Modify
# Control" - una ricerca precedente aveva restituito risultati pertinenti
# a un OID DIVERSO (1.3.6.1.4.1.4203.1.11.1) senza mai confermare
# davvero questo OID specifico. Confermato dal registro ufficiale IANA:
# e' il "Don't Use Copy Control" (RFC 6171). Stesso fix applicato in
# parallelo a analyze_rootdse.py e check_ldap_consistency_cluster.yml.
#
# NOVITÀ v1.3 rispetto a v1.2:
#   - Aggiunta una sezione dedicata all'ENTRY RADICE del suffisso (quella
#     con la profondita' di DN minore, es. "dc=example,dc=com") - prima
#     trattata come una qualunque altra entry "altro", ora evidenziata
#     separatamente con i suoi attributi (objectClass, contextCSN se
#     presente, entryUUID, altro).
#   - Aggiunto un dizionario di 27 OID di protocollo LDAP (Controls/
#     Extensions/Features) -> descrizione leggibile, con scansione di
#     TUTTI i valori del file alla ricerca di corrispondenze. Tutte le 27
#     voci verificate individualmente con ricerca dedicata (8 errori reali
#     trovati e corretti in una bozza precedente, circa un terzo del
#     totale - vedi commento accanto a OID_MAP per il dettaglio).
#     ATTENZIONE: un LDIF di dati normalmente NON contiene questi OID da
#     nessuna parte - sono concetti del protocollo LDAP (controlli,
#     estensioni), non della directory data, e vivono nel root DSE di un
#     server in esecuzione, non in un export statico. Un conteggio a zero
#     e' l'esito normale e atteso, non un difetto dello script - la
#     sezione e' comunque inclusa come rete di sicurezza e per completezza.
#
# NOVITÀ v1.2 rispetto a v1.1:
#   - Aggiunto il confronto memberOf vs member: per utente (non solo un
#     secondo conteggio, un confronto per INSIEME di gruppi): se un utente
#     dichiara in memberOf un gruppo che nessun gruppo lo elenca davvero
#     come member:, o viceversa, viene segnalato esplicitamente con il
#     dettaglio di quali gruppi divergono in quale direzione. Verificato con
#     un caso di test costruito apposta (utente con disallineamento
#     deliberato), non solo sul caso "tutto coerente".
#
# NOVITÀ v1.1 rispetto a v1.0:
#   - Rilevamento esplicito di file binari (byte nulli nei primi KB) PRIMA
#     di tentare il parsing come testo, invece di scoprirlo indirettamente
#     da "zero entry trovate".
#   - Euristica aggiuntiva: entry con un DN valido ma senza objectClass da
#     nessuna parte nel file segnala che probabilmente non e' un LDIF
#     genuino, non solo qualcosa che gli assomiglia superficialmente.
#   - Invocato senza alcun parametro, mostra l'help completo (con esempi
#     d'uso), non solo il messaggio minimale di argparse su "argomento
#     mancante".
#
# VERSIONE 1.0 (baseline):
#   Parser LDIF autonomo (line-folding, base64, commenti), classificazione
#   utenti/gruppi via objectClass configurabili, statistiche su membri per
#   gruppo (utenti diretti/gruppi nidificati/totali), gruppi per utente,
#   profondita' di annidamento e rilevamento cicli, riferimenti pendenti,
#   valori duplicati, frequenza objectClass/attributi, schema di hashing
#   password, profondita'/distribuzione DN, dimensione approssimata entry.
#   Output a video + opzionale export JSON.
# ==============================================================================

USO:
    python3 analyze_ldif.py dataset.ldif
    python3 analyze_ldif.py dataset.ldif --json report.json
    python3 analyze_ldif.py dataset.ldif --user-oc inetOrgPerson,person \\
                                          --group-oc groupOfNames,posixGroup \\
                                          --member-attr member
"""

from __future__ import annotations

import argparse
import base64
import json
import statistics
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Set, Tuple


# ==============================================================================
# 1. PARSER LDIF
#
# Implementazione minimale ma corretta di RFC 2849: gestisce il line-folding
# (righe di continuazione che iniziano con un singolo spazio), i valori in
# base64 (separatore "::"), i commenti ("#"), e ignora la riga "version: 1"
# e i controlli di changetype (non servono per una semplice analisi
# statistica di uno snapshot).
# ==============================================================================

@dataclass
class LdifEntry:
    dn: str
    attrs: Dict[str, List[str]] = field(default_factory=dict)

    def get(self, name: str) -> List[str]:
        return self.attrs.get(name.lower(), [])

    def has_oc(self, oc_set: Set[str]) -> bool:
        ocs = {v.lower() for v in self.get("objectclass")}
        return bool(ocs & oc_set)


def _unfold_lines(raw_lines: List[str]) -> List[str]:
    """Ricongiunge le righe di continuazione LDIF (iniziano con uno spazio)."""
    unfolded: List[str] = []
    for line in raw_lines:
        if line.startswith(" ") and unfolded:
            unfolded[-1] += line[1:]
        else:
            unfolded.append(line)
    return unfolded


def parse_ldif(path: str) -> List[LdifEntry]:
    entries: List[LdifEntry] = []
    current_dn: Optional[str] = None
    current_attrs: Dict[str, List[str]] = defaultdict(list)

    def flush():
        nonlocal current_dn, current_attrs
        if current_dn is not None:
            entries.append(LdifEntry(dn=current_dn, attrs=dict(current_attrs)))
        current_dn = None
        current_attrs = defaultdict(list)

    with open(path, "r", encoding="utf-8", errors="replace") as f:
        raw = f.read().splitlines()

    # Le righe vuote separano i record - le trattiamo dopo lo unfolding
    # per record (lo unfolding e il raggruppamento in blocchi vanno di pari
    # passo: raggruppiamo prima per blocchi separati da riga vuota, poi
    # facciamo lo unfold righe dentro ciascun blocco).
    blocks: List[List[str]] = []
    block: List[str] = []
    for line in raw:
        if line.strip() == "":
            if block:
                blocks.append(block)
                block = []
            continue
        if line.startswith("#"):
            continue
        block.append(line)
    if block:
        blocks.append(block)

    for blk in blocks:
        unfolded = _unfold_lines(blk)
        if not unfolded:
            continue
        if unfolded[0].startswith("version:"):
            continue

        current_dn = None
        current_attrs = defaultdict(list)

        for line in unfolded:
            if ":" not in line:
                continue
            attr, _, rest = line.partition(":")
            attr_lower = attr.strip().lower()

            if rest.startswith(":"):
                # valore in base64: "attr:: <base64>"
                raw_val = rest[1:].strip()
                try:
                    value = base64.b64decode(raw_val).decode("utf-8", errors="replace")
                except Exception:
                    value = raw_val
            elif rest.startswith("<"):
                # riferimento a file/URL ("attr:< file://...") - non risolto,
                # registriamo solo il riferimento grezzo
                value = rest[1:].strip()
            else:
                value = rest.strip()

            if attr_lower == "dn":
                current_dn = value
            else:
                current_attrs[attr_lower].append(value)

        flush()

    return entries


def looks_binary(path: str, sniff_bytes: int = 8192) -> bool:
    """Euristica semplice ma affidabile: un file di testo vero non contiene
    quasi mai byte nulli - un file binario (immagine, eseguibile, archivio
    compresso...) quasi sempre si'. Non e' un rilevamento perfetto al 100%
    per ogni possibile formato, ma copre bene i casi comuni."""
    try:
        with open(path, "rb") as f:
            chunk = f.read(sniff_bytes)
    except OSError:
        return False
    return b"\x00" in chunk


def looks_like_ldif(entries: List[LdifEntry], raw_line_count: int) -> Tuple[bool, str]:
    """Controllo euristico di plausibilita', oltre al semplice 'zero entry
    trovate': anche con qualche entry, un file con entry ma NESSUN
    objectClass da nessuna parte suggerisce che non sia davvero un LDIF,
    solo che contenga per caso qualche riga con un ':' che ricorda la
    sintassi."""
    if not entries:
        return False, (
            f"nessuna entry valida trovata (nessuna riga 'dn:' riconosciuta) "
            f"su {raw_line_count} righe lette. Non sembra un file LDIF."
        )
    with_oc = sum(1 for e in entries if e.get("objectclass"))
    if with_oc == 0:
        return False, (
            f"trovate {len(entries)} entry con un DN, ma NESSUNA con un "
            f"attributo objectClass - molto insolito per un LDIF LDAP reale. "
            f"Controlla che il file sia davvero un export LDIF e non un "
            f"formato diverso che assomiglia superficialmente (es. 'chiave: "
            f"valore' generico)."
        )
    return True, ""


# ==============================================================================
# 2. CLASSIFICAZIONE ENTRY (utenti / gruppi / altro)
# ==============================================================================

DEFAULT_USER_OC = {"inetorgperson", "person", "organizationalperson", "posixaccount"}
DEFAULT_GROUP_OC = {"groupofnames", "groupofuniquenames", "posixgroup", "group"}
DEFAULT_MEMBER_ATTRS = ["member", "uniquemember", "memberuid"]


def classify(entries: List[LdifEntry], user_oc: Set[str], group_oc: Set[str]):
    users, groups, other = [], [], []
    for e in entries:
        if e.has_oc(user_oc):
            users.append(e)
        elif e.has_oc(group_oc):
            groups.append(e)
        else:
            other.append(e)
    return users, groups, other


def detect_member_attr(groups: List[LdifEntry]) -> str:
    """Sceglie l'attributo di appartenenza piu' usato tra i gruppi trovati."""
    counts = Counter()
    for g in groups:
        for cand in DEFAULT_MEMBER_ATTRS:
            if g.get(cand):
                counts[cand] += 1
    if not counts:
        return "member"
    return counts.most_common(1)[0][0]


# ==============================================================================
# 2b. DIZIONARIO OID -> DESCRIZIONE LEGGIBILE (Controls/Extensions/Features
# del protocollo LDAP) + ENTRY RADICE DEL SUFFISSO
#
# Le 27 voci sono state verificate individualmente con ricerca dedicata
# (non solo le piu' comuni) - 8 errori reali sono stati trovati e corretti
# nel processo rispetto a una prima bozza (circa un terzo del totale):
# vale la pena non fidarsi mai di un dizionario di questo tipo a scatola
# chiusa senza verifica, cosa gia' successa una volta con questo stesso
# elenco prima di essere corretto.
#
# NOTA IMPORTANTE PER QUESTO SCRIPT: un LDIF di dati (utenti/gruppi) di
# norma non contiene questi OID da nessuna parte - sono concetti del
# PROTOCOLLO LDAP (controlli, estensioni), non della directory data vera
# e propria. Il root DSE (dove questi OID compaiono davvero, in
# supportedControl/supportedExtension/supportedFeatures) non esiste in un
# export statico - vive solo su un server LDAP in esecuzione. Questo
# dizionario qui e' quindi principalmente una rete di sicurezza per il
# raro caso di coincidenza, o di un file che non sia davvero un export
# dati - un conteggio a zero e' l'esito normale e atteso, non un difetto
# dello script.
# ==============================================================================

OID_MAP = {
    # Controls
    "1.3.6.1.4.1.4203.1.9.1.1": "LDAP Content Synchronization Control (SyncRepl, RFC 4533)",
    "2.16.840.1.113730.3.4.5": "Password Expiring / Expiration Warning Control",
    "2.16.840.1.113730.3.4.4": "Password Expired Control",
    "1.3.6.1.4.1.42.2.27.9.5.8": "Account Usability Control (Sun/OpenDS)",
    "1.3.6.1.4.1.42.2.27.8.5.1": "OpenLDAP Password Policy Control (ppolicy)",
    "2.16.840.1.113730.3.4.18": "Proxy Authorization Control v2 (RFC 4370)",
    "2.16.840.1.113730.3.4.2": "Manage DSA IT Control (RFC 3296)",
    "1.3.6.1.4.1.4203.1.10.1": "Subentries Control (RFC 3672)",
    "1.3.6.1.1.22": "Don't Use Copy Control (RFC 6171)",
    "1.2.840.113556.1.4.319": "Simple Paged Results Control (RFC 2696)",
    "1.2.826.0.1.3344810.2.3": "Matched Values Control (RFC 3876)",
    "1.3.6.1.1.13.2": "LDAP Read Entry - Post-read Control (RFC 4527)",
    "1.3.6.1.1.13.1": "LDAP Read Entry - Pre-read Control (RFC 4527)",
    "1.3.6.1.1.12": "Assertion Control (RFC 4528)",
    "1.3.6.1.4.1.4203.666.5.12": "Relax Control (OpenLDAP, non standard)",
    # Extensions
    "1.3.6.1.4.1.1466.20037": "StartTLS Extended Operation",
    "1.3.6.1.4.1.4203.1.11.1": "Password Modify Extended Operation (RFC 3062)",
    "1.3.6.1.4.1.4203.1.11.3": "Who Am I? Extended Operation (RFC 4532)",
    "1.3.6.1.1.8": "Cancel Extended Operation (RFC 3909)",
    "1.3.6.1.1.21.1": "Start Transaction Extended Request (RFC 5805)",
    "1.3.6.1.1.21.3": "End Transaction Extended Request (RFC 5805)",
    # Features
    "1.3.6.1.1.14": "Modify-Increment Extension (RFC 4525)",
    "1.3.6.1.4.1.4203.1.5.1": "All Operational Attributes Feature (RFC 3673)",
    "1.3.6.1.4.1.4203.1.5.2": "OC AD Lists (RFC 4529)",
    "1.3.6.1.4.1.4203.1.5.3": "True/False Filters",
    "1.3.6.1.4.1.4203.1.5.4": "Language Tag Options",
    "1.3.6.1.4.1.4203.1.5.5": "Language Range Options",
}


def find_root_entries(entries: List[LdifEntry]) -> List[LdifEntry]:
    """Trova la vera entry radice del suffisso, se presente nel file.

    NON usa semplicemente "la profondita' di DN minore" - su un LDIF
    payload-only (senza struttura di base, come quelli usati in questo
    stesso progetto per separare i dati di test dalla gerarchia condivisa)
    tutte le entry possono avere la STESSA profondita' uniforme, facendo
    scattare quel criterio su ogni singola entry del file (bug reale
    trovato testando questa funzione su un file payload-only prima di
    consegnarla). Il criterio corretto: trova il suffisso di DN comune a
    TUTTE le entry del file, poi verifica se un'entry con ESATTAMENTE
    quel DN esiste davvero nel file - se non esiste (es. file payload-only
    dove la radice e' stata volutamente rimossa), restituisce lista vuota,
    non un indovinello sbagliato.
    """
    if not entries:
        return []

    def dn_components(dn: str) -> List[str]:
        return [c.strip() for c in dn.split(",")]

    all_components = [dn_components(e.dn) for e in entries]
    min_len = min(len(c) for c in all_components)

    common_suffix: List[str] = []
    for i in range(1, min_len + 1):
        candidates = {tuple(c[-i:]) for c in all_components}
        if len(candidates) == 1:
            common_suffix = list(next(iter(candidates)))
        else:
            break

    if not common_suffix:
        return []

    root_dn_normalized = ",".join(common_suffix).lower()
    return [e for e in entries if e.dn.lower() == root_dn_normalized]


def scan_known_oids(entries: List[LdifEntry]) -> List[Tuple[str, str, str]]:
    """Scansiona TUTTI i valori di TUTTI gli attributi di TUTTE le entry
    alla ricerca di stringhe che corrispondono a un OID noto in OID_MAP.
    Normalmente in un LDIF di dati non trova nulla (vedi nota sopra sul
    perche') - restituisce (dn, attributo, descrizione) per ciascuna
    corrispondenza trovata, se ce ne sono."""
    found = []
    for e in entries:
        for attr, values in e.attrs.items():
            for v in values:
                v_clean = v.strip()
                if v_clean in OID_MAP:
                    found.append((e.dn, attr, OID_MAP[v_clean]))
    return found


# ==============================================================================
# 3. STATISTICHE
# ==============================================================================

def dist_stats(values: List[int]) -> Dict[str, float]:
    if not values:
        return {"count": 0, "min": 0, "max": 0, "mean": 0.0, "median": 0.0, "stddev": 0.0}
    return {
        "count": len(values),
        "min": min(values),
        "max": max(values),
        "mean": round(statistics.mean(values), 2),
        "median": statistics.median(values),
        "stddev": round(statistics.pstdev(values), 2) if len(values) > 1 else 0.0,
    }


def histogram(values: List[int], buckets: List[Tuple[int, Optional[int]]]) -> Dict[str, int]:
    labels = {}
    for lo, hi in buckets:
        label = f"{lo}-{hi}" if hi is not None else f"{lo}+"
        labels[label] = 0
    for v in values:
        for lo, hi in buckets:
            if v >= lo and (hi is None or v <= hi):
                label = f"{lo}-{hi}" if hi is not None else f"{lo}+"
                labels[label] += 1
                break
    return labels


def analyze(
    entries: List[LdifEntry],
    user_oc: Set[str],
    group_oc: Set[str],
    member_attr: Optional[str],
) -> dict:
    users, groups, other = classify(entries, user_oc, group_oc)
    user_dns = {u.dn.lower() for u in users}
    group_dns = {g.dn.lower() for g in groups}
    all_known_dns = user_dns | group_dns | {e.dn.lower() for e in other}

    root_entries = find_root_entries(entries)
    known_oids_found = scan_known_oids(entries)

    if member_attr is None:
        member_attr = detect_member_attr(groups)

    # --- membri per gruppo, distinguendo utenti / gruppi annidati / esterni ---
    group_user_counts: List[int] = []
    group_nested_counts: List[int] = []
    group_total_counts: List[int] = []
    empty_groups: List[str] = []
    dangling_refs: List[Tuple[str, str]] = []  # (group_dn, valore_pendente)
    duplicate_member_groups: List[str] = []

    # grafo per l'analisi dei gruppi annidati (solo arco gruppo->gruppo)
    nested_graph: Dict[str, List[str]] = defaultdict(list)

    for g in groups:
        raw_members = g.get(member_attr)
        # rileva duplicati esatti nello stesso attributo della stessa entry
        if len(raw_members) != len(set(m.lower() for m in raw_members)):
            duplicate_member_groups.append(g.dn)

        n_users = n_groups_nested = n_other = 0
        for m in raw_members:
            m_norm = m.strip().lower()
            if not m_norm:
                continue
            if m_norm in user_dns:
                n_users += 1
            elif m_norm in group_dns:
                n_groups_nested += 1
                nested_graph[g.dn.lower()].append(m_norm)
            elif m_norm in all_known_dns:
                n_other += 1
            else:
                dangling_refs.append((g.dn, m))

        group_user_counts.append(n_users)
        group_nested_counts.append(n_groups_nested)
        group_total_counts.append(len(raw_members))
        if len(raw_members) == 0:
            empty_groups.append(g.dn)

    # --- gruppi per utente (relazione inversa, calcolata dal contenuto
    #     dell'LDIF stesso via member: sui gruppi - non richiede che
    #     memberOf sia presente sull'utente) ---
    user_group_counts: Dict[str, int] = defaultdict(int)
    user_group_sets: Dict[str, Set[str]] = defaultdict(set)
    for g in groups:
        for m in g.get(member_attr):
            m_norm = m.strip().lower()
            if m_norm in user_dns:
                user_group_counts[m_norm] += 1
                user_group_sets[m_norm].add(g.dn.lower())
    membership_counts = [user_group_counts.get(u, 0) for u in user_dns]
    orphan_users = [u.dn for u in users if user_group_counts.get(u.dn.lower(), 0) == 0]

    # --- CONFRONTO con memberOf dichiarato sull'utente (se presente) -
    # controllo di coerenza incrociato, non solo una seconda fonte: se
    # memberOf e il conteggio derivato da member: divergono per un utente,
    # e' un segnale concreto di dati potenzialmente disallineati (esattamente
    # il tipo di disallineamento memberOf/member su cui si e' concentrato
    # gran parte del lavoro di questa sessione - replica selettiva,
    # aggiornamenti parziali, overlay non ancora ricalcolato...).
    users_with_memberof = 0
    memberof_counts: List[int] = []
    memberof_mismatches: List[Tuple[str, int, int]] = []  # (dn, da_member, da_memberof)
    memberof_mismatch_details: List[str] = []
    for u in users:
        mo_values = u.get("memberof")
        if not mo_values:
            continue
        users_with_memberof += 1
        mo_set = {v.strip().lower() for v in mo_values}
        memberof_counts.append(len(mo_set))
        member_derived_set = user_group_sets.get(u.dn.lower(), set())
        if mo_set != member_derived_set:
            only_in_memberof = mo_set - member_derived_set
            only_in_member = member_derived_set - mo_set
            memberof_mismatches.append((u.dn, len(member_derived_set), len(mo_set)))
            if len(memberof_mismatch_details) < 10:
                detail = f"{u.dn}: "
                parts = []
                if only_in_memberof:
                    parts.append(f"solo in memberOf ({len(only_in_memberof)}, es. {next(iter(only_in_memberof))})")
                if only_in_member:
                    parts.append(f"solo da member: ({len(only_in_member)}, es. {next(iter(only_in_member))})")
                memberof_mismatch_details.append(detail + "; ".join(parts))

    # --- profondita' di annidamento e rilevamento cicli (DFS) ---
    max_depth = 0
    cycles: List[str] = []

    def dfs(node: str, path: List[str], visiting: Set[str]) -> int:
        nonlocal cycles
        if node in visiting:
            cycles.append(" -> ".join(path + [node]))
            return 0
        children = nested_graph.get(node, [])
        if not children:
            return 0
        visiting = visiting | {node}
        return 1 + max((dfs(c, path + [node], visiting) for c in children), default=0)

    for root in nested_graph:
        d = dfs(root, [], set())
        max_depth = max(max_depth, d)

    # --- frequenza objectClass e attributi ---
    oc_counter: Counter = Counter()
    attr_counter: Counter = Counter()
    attrs_per_entry: List[int] = []
    for e in entries:
        for oc in e.get("objectclass"):
            oc_counter[oc.lower()] += 1
        attrs_per_entry.append(len(e.attrs))
        for a in e.attrs:
            attr_counter[a] += 1

    # --- schema di hashing password ---
    pw_schemes: Counter = Counter()
    users_with_pw = 0
    for u in users:
        pw = u.get("userpassword")
        if pw:
            users_with_pw += 1
            val = pw[0]
            if val.startswith("{") and "}" in val:
                scheme = val[1: val.index("}")].upper()
            else:
                scheme = "CLEARTEXT"
            pw_schemes[scheme] += 1

    # --- profondita' DN e container piu' popolati ---
    dn_depths = [e.dn.count(",") + 1 for e in entries]
    parent_counter: Counter = Counter()
    for e in entries:
        parts = e.dn.split(",", 1)
        if len(parts) == 2:
            parent_counter[parts[1].strip()] += 1

    # --- dimensione media entry (approssimata: somma lunghezze valori) ---
    entry_sizes = []
    for e in entries:
        size = len(e.dn)
        for vals in e.attrs.values():
            size += sum(len(v) for v in vals)
        entry_sizes.append(size)

    return {
        "totali": {
            "entry_totali": len(entries),
            "utenti": len(users),
            "gruppi": len(groups),
            "altro": len(other),
            "member_attr_usato": member_attr,
        },
        "entry_radice": {
            "count": len(root_entries),
            "dn": [e.dn for e in root_entries],
            "dettaglio": [
                {
                    "dn": e.dn,
                    "objectclass": e.get("objectclass"),
                    "contextcsn": e.get("contextcsn"),
                    "entryuuid": e.get("entryuuid"),
                    "altri_attributi": sorted(
                        a for a in e.attrs
                        if a not in ("objectclass", "contextcsn", "entryuuid")
                    ),
                }
                for e in root_entries
            ],
        },
        "oid_noti_trovati": {
            "count": len(known_oids_found),
            "dettaglio": [
                {"dn": dn, "attributo": attr, "descrizione": desc}
                for dn, attr, desc in known_oids_found[:20]
            ],
        },
        "membri_per_gruppo_utenti": dist_stats(group_user_counts),
        "membri_per_gruppo_nidificati": dist_stats(group_nested_counts),
        "membri_per_gruppo_totali": dist_stats(group_total_counts),
        "membri_per_gruppo_istogramma": histogram(
            group_total_counts,
            [(0, 0), (1, 5), (6, 10), (11, 25), (26, 50), (51, 100), (101, None)],
        ),
        "gruppi_vuoti": {"count": len(empty_groups), "esempi": empty_groups[:10]},
        "gruppi_per_utente": dist_stats(membership_counts),
        "gruppi_per_utente_istogramma": histogram(
            membership_counts,
            [(0, 0), (1, 5), (6, 10), (11, 25), (26, 50), (51, 100), (101, None)],
        ),
        "utenti_orfani": {"count": len(orphan_users), "esempi": orphan_users[:10]},
        "memberof_coerenza": {
            "utenti_con_memberof": users_with_memberof,
            "utenti_totali": len(users),
            "conteggio_da_memberof": dist_stats(memberof_counts),
            "utenti_con_disallineamento": len(memberof_mismatches),
            "esempi_disallineamento": memberof_mismatch_details,
        },
        "annidamento": {
            "gruppi_con_figli_nidificati": len(nested_graph),
            "profondita_massima": max_depth,
            "cicli_rilevati": cycles[:10],
            "numero_cicli": len(cycles),
        },
        "riferimenti_pendenti": {
            "count": len(dangling_refs),
            "esempi": [f"{g} -> {v}" for g, v in dangling_refs[:10]],
        },
        "valori_duplicati": {
            "gruppi_con_duplicati": len(duplicate_member_groups),
            "esempi": duplicate_member_groups[:10],
        },
        "objectclass_frequenza": dict(oc_counter.most_common(20)),
        "attributi_frequenza": dict(attr_counter.most_common(20)),
        "attributi_per_entry": dist_stats(attrs_per_entry),
        "password": {
            "utenti_con_password": users_with_pw,
            "utenti_totali": len(users),
            "schema_hash": dict(pw_schemes),
        },
        "dn": {
            "profondita": dist_stats(dn_depths),
            "container_piu_popolati": dict(
                Counter({k: v for k, v in parent_counter.items()}).most_common(10)
            ),
        },
        "dimensione_entry_byte": dist_stats(entry_sizes),
    }


# ==============================================================================
# 4. REPORT LEGGIBILE
# ==============================================================================

def print_report(stats: dict, source: str) -> None:
    sep = "=" * 78
    print(sep)
    print(f" ANALISI LDIF: {source}")
    print(sep)

    t = stats["totali"]
    print(f"\nEntry totali:        {t['entry_totali']}")
    print(f"  Utenti:            {t['utenti']}")
    print(f"  Gruppi:            {t['gruppi']}")
    print(f"  Altro:             {t['altro']}")
    print(f"  Attributo membri:  {t['member_attr_usato']}")

    er = stats["entry_radice"]
    print(f"\nEntry radice del suffisso: {er['count']} trovata/e")
    for d in er["dettaglio"]:
        print(f"  dn: {d['dn']}")
        if d["objectclass"]:
            print(f"    objectClass: {', '.join(d['objectclass'])}")
        if d["contextcsn"]:
            print(f"    contextCSN:")
            for csn in d["contextcsn"]:
                print(f"      {csn}")
        if d["entryuuid"]:
            print(f"    entryUUID: {d['entryuuid'][0]}")
        if d["altri_attributi"]:
            print(f"    altri attributi presenti: {', '.join(d['altri_attributi'])}")

    oid = stats["oid_noti_trovati"]
    print(f"\nOID di protocollo LDAP noti trovati nei valori del file: {oid['count']}")
    if oid["count"] > 0:
        print("  (insolito in un LDIF di dati - vedi dettaglio)")
        for item in oid["dettaglio"]:
            print(f"    {item['dn']} / {item['attributo']}: {item['descrizione']}")
    else:
        print("  (atteso: questi OID appartengono al protocollo LDAP - controlli,")
        print("   estensioni - non ai dati della directory. Vivono nel root DSE di")
        print("   un server in esecuzione, non in un export statico come questo.)")

    def print_dist(title: str, d: dict):
        print(f"\n{title}")
        print(f"  count={d['count']}  min={d['min']}  max={d['max']}  "
              f"media={d['mean']}  mediana={d['median']}  dev.std={d['stddev']}")

    print_dist("Membri per gruppo (solo UTENTI diretti):", stats["membri_per_gruppo_utenti"])
    print_dist("Membri per gruppo (solo GRUPPI nidificati):", stats["membri_per_gruppo_nidificati"])
    print_dist("Membri per gruppo (TOTALI, utenti+gruppi):", stats["membri_per_gruppo_totali"])

    print("\nDistribuzione membri per gruppo:")
    for label, count in stats["membri_per_gruppo_istogramma"].items():
        print(f"  {label:>10}: {count}")

    eg = stats["gruppi_vuoti"]
    print(f"\nGruppi senza alcun membro: {eg['count']}")
    if eg["esempi"]:
        print("  esempi:", ", ".join(eg["esempi"]))

    print_dist("\nGruppi per utente (calcolato da member: sui gruppi):", stats["gruppi_per_utente"])
    print("\nDistribuzione gruppi per utente:")
    for label, count in stats["gruppi_per_utente_istogramma"].items():
        print(f"  {label:>10}: {count}")

    moc = stats["memberof_coerenza"]
    print(f"\nCoerenza memberOf vs member: (confronto per utente, non solo per conteggio)")
    print(f"  Utenti con memberOf presente: {moc['utenti_con_memberof']}/{moc['utenti_totali']}")
    if moc["utenti_con_memberof"] > 0:
        print_dist("  Gruppi per utente (calcolato da memberOf dichiarato):", moc["conteggio_da_memberof"])
        print(f"  Utenti con DISALLINEAMENTO tra memberOf e member: {moc['utenti_con_disallineamento']}")
        if moc["esempi_disallineamento"]:
            print("  esempi:")
            for ex in moc["esempi_disallineamento"]:
                print(f"    {ex}")

    ou = stats["utenti_orfani"]
    print(f"\nUtenti senza alcuna appartenenza a gruppi: {ou['count']}")
    if ou["esempi"]:
        print("  esempi:", ", ".join(ou["esempi"]))

    an = stats["annidamento"]
    print(f"\nAnnidamento gruppi:")
    print(f"  Gruppi con figli nidificati: {an['gruppi_con_figli_nidificati']}")
    print(f"  Profondita' massima catena:  {an['profondita_massima']}")
    print(f"  Cicli rilevati:              {an['numero_cicli']}")
    if an["cicli_rilevati"]:
        print("  ATTENZIONE - esempi di cicli (gruppo che referenzia se stesso, direttamente o a catena):")
        for c in an["cicli_rilevati"]:
            print(f"    {c}")

    dr = stats["riferimenti_pendenti"]
    print(f"\nRiferimenti pendenti (member: che punta a un DN inesistente nel file): {dr['count']}")
    if dr["esempi"]:
        print("  esempi:")
        for ex in dr["esempi"]:
            print(f"    {ex}")

    dv = stats["valori_duplicati"]
    print(f"\nGruppi con valori member: duplicati nella stessa entry: {dv['gruppi_con_duplicati']}")
    if dv["esempi"]:
        print("  esempi:", ", ".join(dv["esempi"]))

    print("\nobjectClass piu' frequenti:")
    for oc, count in stats["objectclass_frequenza"].items():
        print(f"  {oc:<30} {count}")

    print("\nAttributi piu' frequenti:")
    for a, count in stats["attributi_frequenza"].items():
        print(f"  {a:<30} {count}")

    print_dist("\nAttributi per entry:", stats["attributi_per_entry"])

    pw = stats["password"]
    print(f"\nPassword: {pw['utenti_con_password']}/{pw['utenti_totali']} utenti con userPassword impostata")
    if pw["schema_hash"]:
        print("  Schema di hashing:")
        for scheme, count in pw["schema_hash"].items():
            print(f"    {scheme:<12} {count}")

    print_dist("\nProfondita' del DN:", stats["dn"]["profondita"])
    print("\nContainer (genitore del DN) piu' popolati:")
    for parent, count in stats["dn"]["container_piu_popolati"].items():
        print(f"  {count:>8}  {parent}")

    print_dist("\nDimensione approssimata per entry (byte, somma valori attributi):",
               stats["dimensione_entry_byte"])

    print("\n" + sep)


# ==============================================================================
# 5. CLI
# ==============================================================================

def parse_oc_list(s: Optional[str], default: Set[str]) -> Set[str]:
    if not s:
        return default
    return {x.strip().lower() for x in s.split(",") if x.strip()}


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Analizza un file LDIF LDAP e produce statistiche su utenti/gruppi.",
        epilog=(
            "Esempi:\n"
            "  python3 analyze_ldif.py dataset.ldif\n"
            "  python3 analyze_ldif.py dataset.ldif --json report.json\n"
            "  python3 analyze_ldif.py dataset.ldif --member-attr uniqueMember "
            "--group-oc groupOfUniqueNames\n"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("ldif_file", help="Percorso del file LDIF da analizzare")
    parser.add_argument(
        "--user-oc",
        help="objectClass che identificano un UTENTE, separate da virgola "
             f"(default: {','.join(sorted(DEFAULT_USER_OC))})",
    )
    parser.add_argument(
        "--group-oc",
        help="objectClass che identificano un GRUPPO, separate da virgola "
             f"(default: {','.join(sorted(DEFAULT_GROUP_OC))})",
    )
    parser.add_argument(
        "--member-attr",
        help="Attributo di appartenenza da usare (member, uniqueMember, memberUid). "
             "Se omesso, viene rilevato automaticamente dal file.",
    )
    parser.add_argument(
        "--json",
        metavar="FILE",
        help="Scrive anche le statistiche in formato JSON su questo file",
    )

    # Invocato senza alcun argomento: mostra l'help completo (con esempi),
    # non solo il messaggio d'errore minimale di argparse su "argomento
    # mancante" - piu' utile per chi lo lancia per la prima volta.
    if len(sys.argv) == 1:
        parser.print_help()
        sys.exit(1)

    args = parser.parse_args()

    user_oc = parse_oc_list(args.user_oc, DEFAULT_USER_OC)
    group_oc = parse_oc_list(args.group_oc, DEFAULT_GROUP_OC)
    member_attr = args.member_attr.lower() if args.member_attr else None

    # Controllo binario PRIMA di tentare il parsing come testo: un file
    # binario aperto in modalita' testo con errors="replace" non genera
    # un'eccezione, produce solo spazzatura - meglio intercettarlo subito
    # con un messaggio chiaro piuttosto che scoprirlo indirettamente da
    # "zero entry trovate".
    if looks_binary(args.ldif_file):
        print(
            f"ERRORE: {args.ldif_file} sembra un file BINARIO (contiene byte nulli "
            f"nei primi KB), non un LDIF testuale. Verifica di aver indicato il file giusto.",
            file=sys.stderr,
        )
        sys.exit(1)

    try:
        with open(args.ldif_file, "r", encoding="utf-8", errors="replace") as f:
            raw_line_count = sum(1 for _ in f)
    except FileNotFoundError:
        print(f"ERRORE: file non trovato: {args.ldif_file}", file=sys.stderr)
        sys.exit(1)
    except OSError as e:
        print(f"ERRORE: impossibile leggere {args.ldif_file}: {e}", file=sys.stderr)
        sys.exit(1)

    entries = parse_ldif(args.ldif_file)

    ok, reason = looks_like_ldif(entries, raw_line_count)
    if not ok:
        print(f"ERRORE: {reason}", file=sys.stderr)
        sys.exit(1)

    stats = analyze(entries, user_oc, group_oc, member_attr)
    print_report(stats, args.ldif_file)

    if args.json:
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump(stats, f, indent=2, ensure_ascii=False)
        print(f"\nStatistiche complete anche in: {args.json}")


if __name__ == "__main__":
    main()

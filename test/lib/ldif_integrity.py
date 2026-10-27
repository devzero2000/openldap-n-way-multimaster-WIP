#!/usr/bin/python3 -I
# ==============================================================================
# TITOLO:       ldif_integrity.py
# AUTORE:       Elia Pinto
# DATA:         27 Ottobre 2026
# SCOPO:        Confronta il CONTENUTO del DIT fra i nodi del cluster partendo
#               dai dump slapcat di ciascun nodo, e verifica la coerenza
#               member/memberOf su ogni nodo. Usato da assert_data_integrity.yml.
#
# PERCHE' NON BASTANO I CONTEGGI: i test esistenti contano le entry di un
# namespace (grep -c "^dn:"). Due nodi con lo stesso numero di entry ma con
# valori diversi (un attributo non replicato, un member in piu', un entryUUID
# diverso) risultano "convergenti". Qui ogni entry viene normalizzata e
# confrontata attributo per attributo.
#
# NORMALIZZAZIONE: righe di continuazione LDIF riunite, attributi con nome in
# minuscolo, valori ordinati, entry ordinate per DN (in minuscolo). slapcat non
# garantisce lo stesso ordine di entry/attributi fra i nodi (verificato il
# 2026-10-27: stessi dati, ordine diverso fra master e replica).
# Gli attributi in --ignore-attr non si confrontano mai: contextCSN su
# disco viene aggiornato solo ai checkpoint di syncprov (olcSpCheckpoint), quindi
# differisce fra i nodi anche a cluster fermo e allineato.
#
# DIFFERENZE NOTE (--known): "dn|attr1,attr2|nodo1,nodo2" - differenze reali
# ma gia' note e fuori dallo scopo del test chiamante. Non bloccano, ma vengono
# SEMPRE stampate (KNOWN_DIFF), per non nasconderle.
#
# COERENZA DELLE APPARTENENZE (--member-scope REGEX, sul DN in minuscolo), per
# ogni nodo separatamente e solo sui gruppi/entry che corrispondono:
#   - DANGLING_MEMBER: un gruppo ha member verso un DN che sul nodo non esiste;
#   - MISSING_MEMBEROF: X e' member di G ma X non ha memberOf: G;
#   - ORPHAN_MEMBEROF: X ha memberOf: G ma G non esiste o non ha member: X.
# slapcat legge i valori MEMORIZZATI: il memberOf dei gruppi annidati che
# nestgroup calcola a runtime non compare, ed e' corretto cosi' (si verifica
# quello che memberof ha scritto, non una vista calcolata).
#
# USCITA: 0 = nodi identici e appartenenze coerenti; 1 = divergenza o
# incoerenza (dettagli su stdout); 2 = errore d'uso o di lettura dei dump.
# Marcatori su stdout: INTEGRITY_OK / INTEGRITY_FAIL / INTEGRITY_ERROR.
#
# ESCLUSIONI (--exclude-dn REGEX, sul DN in minuscolo): entry non confrontate
# ne' contate. Servono per i namespace che cambiano di continuo durante il
# test (le entry della sonda di servizio): un'istantanea non li trova mai
# identici su tutti i nodi, e la loro durabilita' e' verificata a parte.
#
# VERSIONE:     1.1
# CHANGELOG:
#   1.1 - 2026-10-27 - --exclude-dn: con la sonda di servizio attiva il
#                      confronto non riusciva mai (entry svcprobe.* sempre in
#                      volo fra i nodi al momento del dump): baseline di
#                      test_partition_referential_integrity.yml in timeout.
#   1.0 - 2026-10-27 - prima versione.
# ==============================================================================

import argparse
import base64
import hashlib
import re
import sys


def parse_ldif(path):
    """Restituisce {dn_minuscolo: (dn_originale, {attr: [valori ordinati]})}."""
    with open(path, encoding="utf-8", errors="surrogateescape") as fh:
        raw = fh.read().split("\n")
    lines = []
    for line in raw:
        if line.startswith(" ") and lines:
            lines[-1] += line[1:]
        else:
            lines.append(line)
    entries = {}
    current = []
    for line in lines + [""]:
        if line == "":
            if current:
                dn, attrs = build_entry(current, path)
                key = dn.lower()
                if key in entries:
                    raise ValueError(f"{path}: DN duplicato {dn}")
                entries[key] = (dn, attrs)
                current = []
            continue
        if line.startswith("#"):
            continue
        current.append(line)
    return entries


def build_entry(lines, path):
    dn = None
    attrs = {}
    for line in lines:
        name, sep, value = line.partition(":")
        if not sep:
            raise ValueError(f"{path}: riga LDIF non valida: {line[:80]}")
        if value.startswith(":"):
            # "attr:: base64" - si confronta la forma codificata, identica
            # fra i nodi perche' prodotta dallo stesso slapcat
            value = "b64:" + value[1:].strip()
        elif value.startswith(" "):
            value = value[1:]
        if name.lower() == "dn":
            # Due "dn:" nello stesso record = riga vuota mancante fra due
            # record nel dump: non si sceglie in silenzio uno dei due DN
            if dn is not None:
                raise ValueError(f"{path}: record con piu' DN ({dn} / {value})")
            if value.startswith("b64:"):
                value = base64.b64decode(value[4:]).decode("utf-8", "replace")
            dn = value
            continue
        attrs.setdefault(name.lower(), []).append(value)
    if dn is None:
        raise ValueError(f"{path}: record senza dn")
    return dn, {k: sorted(v) for k, v in attrs.items()}


def entry_digest(attrs):
    h = hashlib.sha256()
    for name in sorted(attrs):
        for value in attrs[name]:
            h.update(f"{name}\0{value}\n".encode("utf-8", "surrogateescape"))
    return h.hexdigest()


def strip_attrs(attrs, ignore):
    return {k: v for k, v in attrs.items() if k not in ignore}


def parse_known(specs):
    known = []
    for spec in specs:
        parts = spec.split("|")
        if len(parts) != 3:
            raise ValueError(f"--known non valido (atteso dn|attr,..|nodo,..): {spec}")
        dn, attrs, nodes = parts
        known.append((dn.strip().lower(),
                      {a.strip().lower() for a in attrs.split(",") if a.strip()},
                      {n.strip() for n in nodes.split(",") if n.strip()}))
    return known


def known_attrs_for(known, dn_key, node):
    result = set()
    for kdn, kattrs, knodes in known:
        if kdn == dn_key and node in knodes:
            result |= kattrs
    return result


def compare_nodes(dumps, ref_node, ignore, known, max_details):
    """Confronta ogni nodo con il nodo di riferimento. Ritorna (problemi, note)."""
    problems = []
    notes = []
    ref = dumps[ref_node]
    for node, entries in dumps.items():
        if node == ref_node:
            continue
        missing = sorted(set(ref) - set(entries))
        extra = sorted(set(entries) - set(ref))
        for key in missing[:max_details]:
            problems.append(f"MISSING_ENTRY {node}: {ref[key][0]} (presente su {ref_node})")
        for key in extra[:max_details]:
            problems.append(f"EXTRA_ENTRY {node}: {entries[key][0]} (assente su {ref_node})")
        if len(missing) > max_details or len(extra) > max_details:
            problems.append(f"... {node}: {len(missing)} entry mancanti e {len(extra)} in piu' in totale")
        shown = 0
        for key in sorted(set(ref) & set(entries)):
            a = strip_attrs(ref[key][1], ignore)
            b = strip_attrs(entries[key][1], ignore)
            if a == b:
                continue
            differing = sorted(n for n in set(a) | set(b) if a.get(n) != b.get(n))
            tolerated = known_attrs_for(known, key, node) | known_attrs_for(known, key, ref_node)
            real = [n for n in differing if n not in tolerated]
            if not real:
                notes.append(f"KNOWN_DIFF {node}: {ref[key][0]} attributi {','.join(differing)}")
                continue
            if shown < max_details:
                for name in real:
                    problems.append(
                        f"VALUE_DIFF {node}: {ref[key][0]} {name}: "
                        f"{ref_node}={a.get(name, [])} {node}={b.get(name, [])}")
            shown += 1
        if shown > max_details:
            problems.append(f"... {node}: {shown} entry con valori diversi in totale")
    return problems, notes


def membership_problems(node, entries, scope, max_details):
    problems = []
    rx = re.compile(scope)
    groups = {k: v for k, v in entries.items()
              if "groupofnames" in [o.lower() for o in v[1].get("objectclass", [])]}
    for gkey, (gdn, gattrs) in groups.items():
        if not rx.search(gkey):
            continue
        for member in gattrs.get("member", []):
            mkey = member.lower()
            if mkey not in entries:
                problems.append(f"DANGLING_MEMBER {node}: {gdn} member={member}")
                continue
            memberof = [m.lower() for m in entries[mkey][1].get("memberof", [])]
            if gkey not in memberof:
                problems.append(f"MISSING_MEMBEROF {node}: {member} e' member di {gdn} ma senza memberOf")
    for key, (dn, attrs) in entries.items():
        if not rx.search(key):
            continue
        for group in attrs.get("memberof", []):
            gkey = group.lower()
            if gkey not in entries:
                problems.append(f"ORPHAN_MEMBEROF {node}: {dn} memberOf={group} (gruppo inesistente)")
                continue
            members = [m.lower() for m in entries[gkey][1].get("member", [])]
            if key not in members:
                problems.append(f"ORPHAN_MEMBEROF {node}: {dn} memberOf={group} ma il gruppo non lo ha come member")
    if len(problems) > max_details:
        extra = len(problems) - max_details
        problems = problems[:max_details] + [f"... {node}: altre {extra} incoerenze di appartenenza"]
    return problems


def main():
    parser = argparse.ArgumentParser(
        description="Confronto del DIT fra i nodi e coerenza member/memberOf")
    parser.add_argument("--dump", action="append", required=True, metavar="NODO=FILE",
                        help="dump slapcat di un nodo; il primo e' il riferimento")
    parser.add_argument("--ignore-attr", action="append", default=[])
    parser.add_argument("--known", action="append", default=[])
    parser.add_argument("--exclude-dn", action="append", default=[],
                        help="regex sul DN (minuscolo) delle entry da non confrontare")
    parser.add_argument("--member-scope", default="",
                        help="regex sul DN (minuscolo); vuota = nessun controllo")
    parser.add_argument("--max-details", type=int, default=20)
    args = parser.parse_args()

    try:
        dumps = {}
        for item in args.dump:
            node, sep, path = item.partition("=")
            if not sep:
                raise ValueError(f"--dump non valido: {item}")
            dumps[node] = parse_ldif(path)
            if not dumps[node]:
                raise ValueError(f"{node}: dump vuoto ({path}) - slapcat non riuscito?")
        known = parse_known(args.known)
        excludes = [re.compile(rx) for rx in args.exclude_dn]
    except (OSError, ValueError, re.error) as exc:
        print(f"INTEGRITY_ERROR: {exc}")
        return 2

    if excludes:
        for node, entries in list(dumps.items()):
            kept = {k: v for k, v in entries.items() if not any(rx.search(k) for rx in excludes)}
            print(f"EXCLUDED {node}: {len(entries) - len(kept)} entry ({', '.join(args.exclude_dn)})")
            dumps[node] = kept
    ignore = {a.lower() for a in args.ignore_attr}
    ref_node = args.dump[0].partition("=")[0]
    for node, entries in dumps.items():
        h = hashlib.sha256()
        for key in sorted(entries):
            h.update(key.encode("utf-8", "surrogateescape"))
            h.update(entry_digest(strip_attrs(entries[key][1], ignore)).encode())
        print(f"DIGEST {node}: entry={len(entries)} sha256={h.hexdigest()[:16]}")

    problems, notes = compare_nodes(dumps, ref_node, ignore, known, args.max_details)
    if args.member_scope:
        for node, entries in dumps.items():
            problems += membership_problems(node, entries, args.member_scope, args.max_details)
    for line in notes + problems:
        print(line)
    if problems:
        print(f"INTEGRITY_FAIL: {len(problems)} problemi (riferimento {ref_node})")
        return 1
    print(f"INTEGRITY_OK: {len(dumps)} nodi con contenuto identico"
          + (" e appartenenze coerenti" if args.member_scope else "")
          + (f" ({len(notes)} differenze note)" if notes else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())

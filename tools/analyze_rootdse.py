#!/usr/bin/env python3
"""
# ==============================================================================
# TITOLO:       analyze_rootdse.py - Decodifica del root DSE di un server LDAP
# AUTORE:       Elia Pinto
# DATA:         Settembre 2026
# VERSIONE:     1.2
# SCOPO:        Interroga il root DSE (DN vuoto) di uno slapd in esecuzione via
#               ldapi:///+SASL EXTERNAL, e decodifica gli OID di protocollo
#               LDAP noti (Controls/Extensions/Features) in descrizioni
#               leggibili. Complementare a analyze_ldif.py: quello analizza
#               export statici di DATI (utenti/gruppi), questo interroga il
#               root DSE di un server VIVO - i due concetti non si
#               sovrappongono (il root DSE non esiste in un export statico).
#
# NOVITÀ v1.2 rispetto a v1.1 (errore reale trovato controllando l'output
# di un run vero contro il server, su richiesta esplicita dell'utente di
# ricontrollare con attenzione): 1.3.6.1.1.22 non e' "Password Modify
# Control" - la mia ricerca precedente aveva restituito risultati
# pertinenti a un OID DIVERSO (1.3.6.1.4.1.4203.1.11.1) senza mai
# confermare davvero questo specifico OID, un falso senso di verifica non
# notato allora. Confermato ora dal registro ufficiale IANA (ldap-
# parameters.xml): e' il "Don't Use Copy Control" (RFC 6171).
#
# NOVITÀ v1.1 rispetto a v1.0 (bug reali trovati e corretti):
#   - Dizionario OID_MAP interamente rifatto: su 27 voci originarie, 8 erano
#     sbagliate (~30%) - verificate una per una con ricerca dedicata invece
#     di fidarsi della bozza iniziale. Esempi: 1.3.6.1.4.1.4203.1.10.1 non
#     e' "Content Voting/Paged Results" (e' Subentries Control, RFC 3672);
#     2.16.840.1.113730.3.4.4/.4.5 non sono VLV/Persistent Search (sono
#     Password Expired/Expiring Control); Password Modify e Who Am I
#     (1.3.6.1.4.1.4203.1.11.1/.11.3) erano invertiti; 1.3.6.1.1.8 non e'
#     "Notice of Disconnection" (e' Cancel Extended Operation, RFC 3909).
#   - Filtro di ricerca corretto: "objectClass=*" senza parentesi non e' una
#     sintassi di filtro LDAP valida (RFC 4515) - ora "(objectClass=*)".
#   - Aggiunta la gestione del line-folding LDIF (righe lunghe spezzate da
#     ldapsearch su piu' righe fisiche) - senza, un valore andato a capo a
#     meta' non avrebbe mai combaciato con OID_MAP, fallendo in silenzio.
#   - Aggiunta la gestione dei valori in base64 ("attributo:: valore") -
#     prima trattati come stringa grezza, rompendo il confronto se mai
#     comparsi.
#   - Uso di -LLL (LDIFv1 minimale) invece di affidarsi solo al filtro
#     manuale dei commenti - piu' pulito e meno fragile.
#   - Aggiunto un controllo esplicito se ldapsearch non e' nel PATH, e un
#     parametro -H opzionale per l'URI (default ldapi:///, coerente con
#     l'uso amministrativo locale di questo progetto).
#
# USO:
#   python3 analyze_rootdse.py
#   python3 analyze_rootdse.py -H ldaps://nodo.example.com/
# ==============================================================================
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from typing import List, Optional

# ==============================================================================
# DIZIONARIO OID -> DESCRIZIONE LEGGIBILE (Controls/Extensions/Features)
#
# Tutte le 27 voci verificate individualmente con ricerca dedicata (non
# solo le piu' comuni). Sulla bozza originale di questo stesso script,
# 8 voci risultavano sbagliate (~30% del totale) - vedi changelog sopra
# per gli esempi piu' significativi.
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


def _unfold_lines(raw_lines: List[str]) -> List[str]:
    """Ricongiunge le righe di continuazione LDIF (iniziano con uno spazio)
    - senza, un valore lungo andato a capo a meta' da ldapsearch non
    combacerebbe mai con OID_MAP."""
    unfolded: List[str] = []
    for line in raw_lines:
        if line.startswith(" ") and unfolded:
            unfolded[-1] += line[1:]
        else:
            unfolded.append(line)
    return unfolded


def run_ldapsearch(ldap_uri: str) -> str:
    if shutil.which("ldapsearch") is None:
        print("ERRORE: 'ldapsearch' non trovato nel PATH.", file=sys.stderr)
        sys.exit(1)

    cmd = [
        "ldapsearch", "-H", ldap_uri, "-Y", "EXTERNAL",
        "-LLL", "-s", "base", "-b", "", "(objectClass=*)", "+",
    ]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
    except subprocess.CalledProcessError as e:
        print(f"ERRORE nell'esecuzione di ldapsearch (rc={e.returncode}):", file=sys.stderr)
        print(e.stderr, file=sys.stderr)
        sys.exit(1)
    return result.stdout


def decode_root_dse(raw_output: str) -> None:
    raw_lines = raw_output.splitlines()
    lines = _unfold_lines(raw_lines)

    print("=== ROOT DSE DECODIFICATO ===\n")

    for line in lines:
        if not line or line.startswith("dn:"):
            continue
        if ":" not in line:
            continue

        attr, sep, rest = line.partition(":")
        attr = attr.strip()

        if rest.startswith(":"):
            # valore in base64 ("attr:: <base64>") - non decodificato in
            # chiaro qui (non serve per il confronto con OID_MAP, che sono
            # sempre stringhe ASCII in chiaro), ma segnalato esplicitamente
            # invece di essere trattato per errore come testo grezzo.
            print(f"  {attr}: [valore base64, non decodificato - {rest[1:].strip()[:40]}...]")
            continue

        val = rest.strip()
        if val in OID_MAP:
            print(f"  {attr}: {val}")
            print(f"    -> [Significato]: {OID_MAP[val]}")
        else:
            print(f"  {attr}: {val}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Interroga e decodifica il root DSE di un server LDAP in esecuzione."
    )
    parser.add_argument(
        "-H", "--uri", default="ldapi:///",
        help="URI del server LDAP (default: ldapi:/// - amministrazione locale via SASL EXTERNAL)",
    )
    args = parser.parse_args()

    raw_output = run_ldapsearch(args.uri)
    decode_root_dse(raw_output)


if __name__ == "__main__":
    main()

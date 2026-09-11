#!/usr/bin/env python3
import subprocess
import sys

# Dizionario esteso per OID di OpenLDAP (Controls, Extensions, Features)
OID_MAP = {
    # Controls
    "1.3.6.1.4.1.4203.1.9.1.1": "LDAP Content Synchronization Control (SyncRepl)",
    "2.16.840.1.113730.3.4.5": "Persistent Search Control",
    "2.16.840.1.113730.3.4.4": "Virtual List View (VLV) Control",
    "1.3.6.1.4.1.42.2.27.9.5.8": "OpenLDAP Authz / Proxy Control",
    "1.3.6.1.4.1.42.2.27.8.5.1": "OpenLDAP Password Policy Control (ppolicy)",
    "2.16.840.1.113730.3.4.18": "Proxy Authorization Control",
    "2.16.840.1.113730.3.4.2": "Manage DSA IT Control",
    "1.3.6.1.4.1.4203.1.10.1": "Content Voting / Paged Results variant",
    "1.3.6.1.1.22": "Password Modify Control (RFC 3062)",
    "1.2.840.113556.1.4.319": "Simple Paged Results Control (RFC 2696)",
    "1.2.826.0.1.3344810.2.3": "OpenLDAP paged results / sorting extension",
    "1.3.6.1.1.13.2": "LDAP Read Entry - Pre-read Control (RFC 4527)",
    "1.3.6.1.1.13.1": "LDAP Read Entry - Post-read Control (RFC 4527)",
    "1.3.6.1.1.12": "Assertion Control (RFC 4528)",
    
    # Extensions
    "1.3.6.1.4.1.1466.20037": "StartTLS Extended Operation",
    "1.3.6.1.4.1.4203.1.11.1": "Who Am I? Extended Operation (RFC 4532)",
    "1.3.6.1.4.1.4203.1.11.3": "Cancel Extended Operation (RFC 3909)",
    "1.3.6.1.1.8": "Notice of Disconnection",
    "1.3.6.1.1.21.3": "LDAP Transactions Extended Operation (RFC 5805)",
    "1.3.6.1.1.21.1": "LDAP Start Transaction",

    # Features
    "1.3.6.1.1.14": "Subtree Modification Feature (RFC 3672)",
    "1.3.6.1.4.1.4203.1.5.1": "All-OpAttrs Feature",
    "1.3.6.1.4.1.4203.1.5.2": "Mandatory Access Control Feature",
    "1.3.6.1.4.1.4203.1.5.3": "X.500 Directory Access Protocol (DAP) feature",
    "1.3.6.1.4.1.4203.1.5.4": "Subschema Subentry Feature",
    "1.3.6.1.4.1.4203.1.5.5": "UTF-8 Validation Feature"
}

def main():
    cmd = ["ldapsearch", "-H", "ldapi:///", "-Y", "EXTERNAL", "-s", "base", "-b", "", "objectClass=*", "+"]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
    except subprocess.CalledProcessError as e:
        print(f"Errore nell'esecuzione di ldapsearch: {e}", file=sys.stderr)
        sys.exit(1)

    print("=== ROOTDSE OPENLDAP DECODIFICATO ===\n")
    
    for line in result.stdout.splitlines():
        # Ignora righe vuote o commenti di ldapsearch
        if not line or line.startswith("#") or line.startswith("search:") or line.startswith("result:"):
            continue
            
        if ":" in line:
            parts = line.split(":", 1)
            key = parts[0].strip()
            val = parts[1].strip() if len(parts) > 1 else ""
            
            # Se il valore è un OID presente nel dizionario, aggiungi la descrizione
            if val in OID_MAP:
                print(f"  {key}: {val}")
                print(f"    -> [Significato]: {OID_MAP[val]}")
            else:
                print(f"  {key}: {val}")

if __name__ == "__main__":
    main()
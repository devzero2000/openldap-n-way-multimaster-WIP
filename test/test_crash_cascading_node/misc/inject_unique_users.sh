#!/bin/bash
# ==============================================================================
# TITOLO:       inject_unique_users.sh
# SCOPO:        Inietta N utenti con un prefisso UNIVOCO per ogni esecuzione
#               (basato su timestamp), mai usato in run precedenti - stesso
#               ritmo e struttura di inject_2000_crash_users.sh, ma pensato
#               apposta per escludere (o confermare) l'ipotesi del riuso del
#               namespace crash.user.* come causa delle entry mancanti in
#               replica.
#
# USO:          Da eseguire DIRETTAMENTE sul master di scrittura (node1),
#               non via Ansible.
#                 ./inject_unique_users.sh [numero_utenti] [pausa_secondi]
#               Esempi:
#                 ./inject_unique_users.sh            # 1000 utenti, 5ms
#                 ./inject_unique_users.sh 2000        # 2000 utenti, 5ms
#                 ./inject_unique_users.sh 1000 0.050  # 1000 utenti, 50ms
#
# IMPORTANTE:   Ogni esecuzione genera un prefisso NUOVO (uidtest<epoch>) -
#               non serve alcuna cancellazione preliminare, dato che il
#               namespace non è mai stato usato prima. Il comando di
#               cleanup mirato a QUESTA esecuzione è stampato alla fine.
# ==============================================================================

set -euo pipefail

# --- Parametri (adattare se necessario) ---
LDAP_BASEDN="dc=example,dc=com"
LDAP_ADMIN_DN="cn=admin,${LDAP_BASEDN}"
LDAP_ADMIN_PASS="openldap"   # <-- sostituire con la password reale
LDAP_URI="ldaps://127.0.0.1:636"
TOTAL_USERS="${1:-1000}"
SLEEP_BETWEEN="${2:-0.005}"

# Prefisso univoco: mai esistito prima, non riusabile per un run successivo
PREFIX="uidtest$(date +%s)"

echo "Prefisso di questa esecuzione: ${PREFIX}"
echo "Iniezione di ${TOTAL_USERS} utenti uid=${PREFIX}.N su ${LDAP_URI} (pausa ${SLEEP_BETWEEN}s/entry)..."
START=$(date +%s)

export LDAPTLS_REQCERT=never

for i in $(seq 1 "${TOTAL_USERS}"); do
  cat <<ENTRY
dn: uid=${PREFIX}.${i},ou=People,${LDAP_BASEDN}
objectClass: top
objectClass: inetOrgPerson
uid: ${PREFIX}.${i}
cn: Unique Test User ${i}
sn: UniqueTest
userPassword: {SSHA}demoPass123!

ENTRY
  sleep "${SLEEP_BETWEEN}"
done | ldapadd -x -H "${LDAP_URI}" -D "${LDAP_ADMIN_DN}" -w "${LDAP_ADMIN_PASS}" -c

END=$(date +%s)
echo "Fatto in $((END - START))s."
echo ""
echo "Per contare quante ne sono arrivate su un nodo (adattare l'host):"
echo "  ssh <host> \"sudo slapcat -b '${LDAP_BASEDN}' -a '(uid=${PREFIX}.*)' | grep -c '^dn: '\""
echo ""
echo "Per rimuoverle a fine test:"
echo "  ldapsearch -x -H \"${LDAP_URI}\" -D \"${LDAP_ADMIN_DN}\" -w \"${LDAP_ADMIN_PASS}\" \\"
echo "    -b \"ou=People,${LDAP_BASEDN}\" \"(uid=${PREFIX}.*)\" dn -LLL \\"
echo "    | grep '^dn:' | sed 's/^dn: //' \\"
echo "    | ldapdelete -x -H \"${LDAP_URI}\" -D \"${LDAP_ADMIN_DN}\" -w \"${LDAP_ADMIN_PASS}\""

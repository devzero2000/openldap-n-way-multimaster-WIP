#!/bin/bash
# ==============================================================================
# TITOLO:       inject_2000_crash_users.sh
# SCOPO:        Inietta 2000 utenti uid=crash.user.N - stesso naming, stessa
#               classe (inetOrgPerson) e stesso ritmo (5ms/entry) usati dalla
#               FASE 1 di test_crash_cascading_node.yml, ma come script
#               standalone: per riprodurre lo stesso carico di scrittura
#               senza far girare l'intero crash test, es. per indagare il
#               comportamento delle sessioni syncrepl in isolamento.
#
# USO:          Da eseguire DIRETTAMENTE sul master di scrittura (node1),
#               non via Ansible. Gli utenti creati vanno rimossi a mano
#               dopo l'uso (vedi comando di cleanup in fondo a questo file).
# ==============================================================================

set -euo pipefail

# --- Parametri (adattare se necessario) ---
LDAP_BASEDN="dc=example,dc=com"
LDAP_ADMIN_DN="cn=admin,${LDAP_BASEDN}"
LDAP_ADMIN_PASS="openldap"   # <-- sostituire con la password reale
LDAP_URI="ldaps://127.0.0.1:636"
TOTAL_USERS=1000
#SLEEP_BETWEEN="0.005"        # 5ms, stesso ritmo della FASE 1 del crash test
SLEEP_BETWEEN="0.05"        # 5ms, stesso ritmo della FASE 1 del crash test

echo "Iniezione di ${TOTAL_USERS} utenti uid=crash.user.N su ${LDAP_URI}..."
START=$(date +%s)

export LDAPTLS_REQCERT=never

for i in $(seq 1 "${TOTAL_USERS}"); do
  cat <<ENTRY
dn: uid=crash.user.${i},ou=People,${LDAP_BASEDN}
objectClass: top
objectClass: inetOrgPerson
uid: crash.user.${i}
cn: Crash User ${i}
sn: CrashTest
userPassword: {SSHA}demoPass123!

ENTRY
  sleep "${SLEEP_BETWEEN}"
done | ldapadd -x -H "${LDAP_URI}" -D "${LDAP_ADMIN_DN}" -w "${LDAP_ADMIN_PASS}" -c

END=$(date +%s)
echo "Fatto in $((END - START))s."

# --- Per rimuovere questi utenti dopo l'uso ---
#   ldapsearch -x -H "${LDAP_URI}" -D "${LDAP_ADMIN_DN}" -w "${LDAP_ADMIN_PASS}" \
#     -b "ou=People,${LDAP_BASEDN}" "(uid=crash.user.*)" dn -LLL \
#     | grep '^dn:' | sed 's/^dn: //' \
#     | ldapdelete -x -H "${LDAP_URI}" -D "${LDAP_ADMIN_DN}" -w "${LDAP_ADMIN_PASS}"

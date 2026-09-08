#!/bin/bash
set -e

MASTER="ubuntu24lts1.example.com"
READONLY="ubuntu24lts4.example.com"
BASE="dc=example,dc=com"
ADMIN_DN="cn=admin,dc=example,dc=com"
ADMIN_PW="openldap"
TEST_DN="cn=testuser,ou=People,dc=example,dc=com"
TEST_PW="TestForwardUpdates123!"

echo "=== 1. Pulizia utente di test residuo (se esiste) ==="
ldapdelete -x -D "$ADMIN_DN" -w "$ADMIN_PW" -H "ldap://$MASTER/" "$TEST_DN" 2>/dev/null || echo "(non esisteva, ok)"

echo
echo "=== 2. Crea l'utente di test su $MASTER ==="
ldapadd -x -D "$ADMIN_DN" -w "$ADMIN_PW" -H "ldap://$MASTER/" << EOF
dn: $TEST_DN
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
cn: testuser
sn: Test
userPassword: $TEST_PW
EOF

echo
echo "=== 3. Attesa 2s per la replica verso $READONLY ==="
sleep 2

echo
echo "=== 4. UN bind SBAGLIATO su $READONLY (quello che vogliamo tracciare) ==="
ldapsearch -H "ldap://$READONLY/" -D "$TEST_DN" -w "PasswordSbagliataErrata!" -b "$BASE" "(objectClass=*)" || echo "(fallito come atteso)"

echo
echo "=== 5. Attesa 3s ==="
sleep 3

echo
echo "=== 6. Attributi COMPLETI (utente + operazionali) su $READONLY ==="
ldapsearch -x -D "$ADMIN_DN" -w "$ADMIN_PW" -H "ldap://$READONLY/" -LLL -b "$TEST_DN" -s base "*" "+"

echo
echo "=== 7. Stesso, su $MASTER, per confronto ==="
ldapsearch -x -D "$ADMIN_DN" -w "$ADMIN_PW" -H "ldap://$MASTER/" -LLL -b "$TEST_DN" -s base "*" "+"

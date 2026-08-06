#!/bin/bash

# Configurazione
BASE_DN="dc=example,dc=com"
USER_DN="cn=sync-test-user,ou=users,$BASE_DN"
PASS_V1="OldPassword123!"
PASS_V2="NewPassword456!"

# Genera l'hash SSHA della password iniziale
PASS_V1_HASH=$(slappasswd -s "$PASS_V1")

echo "[*] Step 1: Creo l'utente di test sul Nodo 1 (ubuntu24lts1)..."
ldapadd -H ldaps://ubuntu24lts1.example.com:636 \
  -D "cn=admin,$BASE_DN" -w "openldap" \
  -o tls_cacert=/etc/ldap/sasl2/ca.crt <<EOF
dn: $USER_DN
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
cn: sync-test-user
sn: SyncTest
userPassword: $PASS_V1_HASH
EOF

echo "[*] Step 2: Attendo 5 secondi la propagazione syncrepl..."
sleep 5

echo "[*] Step 3: Verifico il bind con la password iniziale sugli altri nodi..."
for node in ubuntu24lts2.example.com ubuntu24lts3.example.com; do
  echo -n "  -> Controllo su $node... "
  ldapsearch -H ldaps://$node:636 -D "$USER_DN" -w "$PASS_V1" -b "$USER_DN" -s base dn \
    -o tls_cacert=/etc/ldap/sasl2/ca.crt >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    echo "OK (Propagato)"
  else
    echo "FALLITO (Non ancora sincronizzato)"
  fi
done

echo "[*] Step 4: Cambio password dell'utente direttamente sul Nodo 2 (ubuntu24lts2)..."
ldappasswd -H ldaps://ubuntu24lts2.example.com:636 \
  -D "$USER_DN" -w "$PASS_V1" -s "$PASS_V2" \
  -o tls_cacert=/etc/ldap/sasl2/ca.crt

echo "[*] Step 5: Attendo 5 secondi per il sync inverso della nuova password..."
sleep 5

echo "[*] Step 6: Verifico la NUOVA password sul Nodo 1 e Nodo 3..."
for node in ubuntu24lts1.example.com ubuntu24lts3.example.com; do
  echo -n "  -> Controllo login con nuova password su $node... "
  ldapsearch -H ldaps://$node:636 -D "$USER_DN" -w "$PASS_V2" -b "$USER_DN" -s base dn \
    -o tls_cacert=/etc/ldap/sasl2/ca.crt >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    echo "OK (Sync bidirezionale funzionante)"
  else
    echo "FALLITO"
  fi
done

echo "[*] Step 7: Pulizia finale dell'utente di test..."
ldapdelete -H ldaps://ubuntu24lts1.example.com:636 \
  -D "cn=admin,$BASE_DN" -w "openldap" \
  -o tls_cacert=/etc/ldap/sasl2/ca.crt "$USER_DN" >/dev/null 2>&1

echo "[*] Test completato."

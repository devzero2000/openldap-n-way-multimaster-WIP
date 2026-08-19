#!/bin/bash
# ==============================================================================
# SCRIPT:       ldap_schema_discovery.sh (Aggiornato con Bind Autenticato)
# DESCRIZIONE:  Interroga lo schema OpenLDAP evitando il blocco anonymous bind
# ==============================================================================

# Parametri di connessione (modificabili o personalizzabili via ambiente)
LDAP_URI="${LDAP_URI:-ldap://localhost}"
LDAP_BIND_DN="${LDAP_BIND_DN:-cn=admin,dc=example,dc=com}"
LDAP_PASSWORD="${LDAP_PASSWORD:-openldap}"
LDAP_BASE="${LDAP_BASE:-dc=example,dc=com}"

echo "=== 1. Ricerca della subschemaSubentry per: ${LDAP_BASE} ==="
ldapsearch -x -H "${LDAP_URI}" -D "${LDAP_BIND_DN}" -w "${LDAP_PASSWORD}" \
  -LLL -b "${LDAP_BASE}" -s base subschemaSubentry

echo -e "\n=== 2. Estrazione dello Schema completo da cn=Subschema ==="
# Sfrutta la forma breve (RFC 3673) supportata dai server moderni
ldapsearch -x -H "${LDAP_URI}" -D "${LDAP_BIND_DN}" -w "${LDAP_PASSWORD}" \
  -LLL -b "cn=Subschema" -s base '(objectClass=subschema)' +

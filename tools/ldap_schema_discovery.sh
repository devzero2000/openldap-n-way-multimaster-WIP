#!/bin/bash
# ==============================================================================
# SCRIPT:       ldap_schema_discovery.sh
# DESCRIZIONE:  Interroga lo schema OpenLDAP (subschemaSubentry + cn=Subschema)
#               usando un bind autenticato, evitando il blocco dell'anonymous
#               bind tipico dei server in produzione.
# AUTORE:       Elia Pinto
# VERSIONE:     2.0
# DATA:         2026-09-11
#
# CHANGELOG:
#   2.0  (2026-09-11) - Aggiunti: header professionale con changelog, help
#                        (-h/--help), controllo dipendenza 'ldapsearch',
#                        validazione parametri, gestione errori (set -eu,
#                        exit code distinti), output strutturato a sezioni
#                        numerate coerente con lo stile degli altri script
#                        del progetto.
#   1.0  (2025-08-28) - Versione iniziale: due ldapsearch (subschemaSubentry
#                        e dump completo dello schema da cn=Subschema) con
#                        bind autenticato invece di anonymous bind.
#
# SCOPO:
#   Estrarre lo schema effettivo pubblicato da un server OpenLDAP:
#     1) individua la subschemaSubentry per la base DN indicata
#     2) scarica il dump completo dello schema da cn=Subschema (RFC 3673)
#
# PARAMETRI (variabili d'ambiente, tutte opzionali):
#   LDAP_URI        URI del server LDAP            (default: ldap://localhost)
#   LDAP_BIND_DN    DN per il bind autenticato      (default: cn=admin,dc=example,dc=com)
#   LDAP_PASSWORD   Password per il bind            (default: openldap)
#   LDAP_BASE       Base DN da interrogare          (default: dc=example,dc=com)
#
# USO:
#   ./ldap_schema_discovery.sh [-h|--help]
#
#   Esempio con parametri personalizzati:
#     LDAP_URI="ldap://ldap01.example.com" \
#     LDAP_BIND_DN="cn=admin,dc=example,dc=com" \
#     LDAP_PASSWORD="secret" \
#     LDAP_BASE="dc=example,dc=com" \
#     ./ldap_schema_discovery.sh
#
# EXIT CODE:
#   0  successo
#   1  parametri/uso non validi
#   2  dipendenza mancante (ldapsearch non trovato)
#   3  errore durante l'interrogazione LDAP
# ==============================================================================

set -eu

# ------------------------------------------------------------------------------
# 0. Help
# ------------------------------------------------------------------------------
if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    sed -n '2,40p' "$0"
    exit 0
fi

# ------------------------------------------------------------------------------
# 1. Parametri di connessione (modificabili via ambiente)
# ------------------------------------------------------------------------------
LDAP_URI="${LDAP_URI:-ldap://localhost}"
LDAP_BIND_DN="${LDAP_BIND_DN:-cn=admin,dc=example,dc=com}"
LDAP_PASSWORD="${LDAP_PASSWORD:-openldap}"
LDAP_BASE="${LDAP_BASE:-dc=example,dc=com}"

# ------------------------------------------------------------------------------
# 2. Controllo dipendenze
# ------------------------------------------------------------------------------
if ! command -v ldapsearch >/dev/null 2>&1; then
    printf "[ERRORE] Comando 'ldapsearch' non trovato (pacchetto ldap-utils).\n" >&2
    exit 2
fi

# ------------------------------------------------------------------------------
# 3. Ricerca della subschemaSubentry per la base DN indicata
# ------------------------------------------------------------------------------
printf "=== [1/2] Ricerca della subschemaSubentry per: %s ===\n" "${LDAP_BASE}"
if ! ldapsearch -x -H "${LDAP_URI}" -D "${LDAP_BIND_DN}" -w "${LDAP_PASSWORD}" \
     -LLL -b "${LDAP_BASE}" -s base subschemaSubentry; then
    printf "[ERRORE] Interrogazione subschemaSubentry fallita (bind o rete?).\n" >&2
    exit 3
fi

# ------------------------------------------------------------------------------
# 4. Estrazione dello schema completo da cn=Subschema (RFC 3673)
# ------------------------------------------------------------------------------
printf "\n=== [2/2] Estrazione dello schema completo da cn=Subschema ===\n"
if ! ldapsearch -x -H "${LDAP_URI}" -D "${LDAP_BIND_DN}" -w "${LDAP_PASSWORD}" \
     -LLL -b "cn=Subschema" -s base '(objectClass=subschema)' +; then
    printf "[ERRORE] Estrazione dello schema da cn=Subschema fallita.\n" >&2
    exit 3
fi

printf "\n[OK] Discovery dello schema completata con successo.\n"

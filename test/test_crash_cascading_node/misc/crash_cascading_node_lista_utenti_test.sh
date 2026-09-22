#!/bin/sh
# ==============================================================================
# SCRIPT:       crash_cascading_node_lista_utenti_test.sh
# AUTORE:       Elia Pinto
# DATA:         15 Settembre 2026
# VERSIONE:     2.0
# SCOPO:        Tool manuale di emergenza per test_crash_cascading_node.yml -
#               elenca gli utenti di test residui (uid=*crash*) creati da
#               quel playbook, in caso il cleanup automatico del playbook
#               non sia arrivato a completamento (es. crash test interrotto
#               a meta', nodo rimasto giu' per una corruzione reale). Non
#               e' un tool general-purpose - il pattern di ricerca e il
#               nome sono specifici a quel test.
#
# NOVITÀ v2.0 rispetto a v1.0: passato da ldap:// in chiaro con password
# sulla riga di comando (-w, visibile sia in transito sia nella process
# list di chiunque altro sulla macchina) a ldaps:// con password letta da
# variabile d'ambiente (non finisce mai negli argomenti del processo).
#
# USO:
#   export LDAP_ADMIN_PASSWORD='openldap'
#   ./crash_cascading_node_lista_utenti_test.sh
#   (scrive utenti_da_cancellare.txt - poi usalo con lo script di
#   cancellazione gemello, crash_cascading_node_cancella_utenti_test.sh)
# ==============================================================================

set -eu

if [ -z "${LDAP_ADMIN_PASSWORD:-}" ]; then
    printf -- "[ERRORE] Imposta la password prima di lanciare lo script:\n" >&2
    printf -- "  export LDAP_ADMIN_PASSWORD='...'\n" >&2
    exit 2
fi

ldapsearch -x -H ldaps://localhost -D "cn=admin,dc=example,dc=com" \
    -w "$LDAP_ADMIN_PASSWORD" \
    -b "ou=People,dc=example,dc=com" -s one "(uid=*crash*)" dn \
    | grep "^dn:" | sed 's/^dn: //' > utenti_da_cancellare.txt

COUNT=$(wc -l < utenti_da_cancellare.txt)
printf -- "Trovati %s utenti residui del test crash_cascading_node - elenco in utenti_da_cancellare.txt\n" "$COUNT"

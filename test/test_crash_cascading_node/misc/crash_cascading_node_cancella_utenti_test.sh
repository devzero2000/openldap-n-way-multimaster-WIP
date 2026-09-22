#!/bin/sh
# ==============================================================================
# SCRIPT:       crash_cascading_node_cancella_utenti_test.sh
# AUTORE:       Elia Pinto
# DATA:         15 Settembre 2026
# VERSIONE:     2.0
# SCOPO:        Tool manuale di emergenza per test_crash_cascading_node.yml -
#               cancella gli utenti di test elencati dallo script gemello
#               crash_cascading_node_lista_utenti_test.sh, in caso il
#               cleanup automatico del playbook non sia arrivato a
#               completamento. Non e' un tool general-purpose.
#
# NOVITÀ v2.0 rispetto a v1.0: passato da ldap:// in chiaro con password
# sulla riga di comando a ldaps:// con password letta da variabile
# d'ambiente.
#
# USO:
#   export LDAP_ADMIN_PASSWORD='openldap'
#   ./crash_cascading_node_lista_utenti_test.sh        # genera l'elenco
#   ./crash_cascading_node_cancella_utenti_test.sh      # cancella
# ==============================================================================

set -eu

if [ -z "${LDAP_ADMIN_PASSWORD:-}" ]; then
    printf -- "[ERRORE] Imposta la password prima di lanciare lo script:\n" >&2
    printf -- "  export LDAP_ADMIN_PASSWORD='...'\n" >&2
    exit 2
fi

if [ ! -f utenti_da_cancellare.txt ]; then
    printf -- "[ERRORE CRITICO] utenti_da_cancellare.txt non trovato.\n" >&2
    printf -- "Lancia prima crash_cascading_node_lista_utenti_test.sh.\n" >&2
    exit 2
fi

ldapdelete -x -H ldaps://localhost -D "cn=admin,dc=example,dc=com" \
    -w "$LDAP_ADMIN_PASSWORD" -f utenti_da_cancellare.txt

rm -f utenti_da_cancellare.txt
printf -- "Cancellazione completata.\n"

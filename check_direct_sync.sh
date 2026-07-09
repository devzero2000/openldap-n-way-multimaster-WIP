#!/bin/sh
# ==============================================================================
# SCRIPT: check_direct_sync.sh
# DESCRIPTION: Verifica la sincronizzazione del Nodo 2 e Nodo 3 rispetto al Nodo 1.
# ==============================================================================

set -eu

BASE_DN="dc=example,dc=com"
ADMIN_DN="cn=admin,dc=example,dc=com"
ADMIN_PW="openldap"
SCRIPT_PERL="./check_ldap_syncrepl_status.pl"

if [ ! -f "$SCRIPT_PERL" ]; then
    printf -- "[ERRORE CRITICO] Componente %s non trovato.\n" "$SCRIPT_PERL" >&2
    exit 2
fi

# Variabile di stato per tracciare il successo complessivo
CLUSTER_OK=0

printf -- "--- VERIFICA DIRETTA NODO 2 <-- NODO 1 ---\n"
# -I "001" estrae il CSN del Nodo 1 sul database del Nodo 2 e lo confronta con il Nodo 1 originale
if "$SCRIPT_PERL" -H "ldaps://ubuntu24lts2.example.com" -U "ldaps://ubuntu24lts1.example.com" -D "$ADMIN_DN" -P "$ADMIN_PW" -S "$BASE_DN" -I "001" -w 10 -c 15 > /dev/null 2>&1; then
    printf -- "[OK] Nodo 2 è in sync con Nodo 1.\n"
else
    printf -- "[ERR] Nodo 2 NON è in sync con Nodo 1.\n"
    CLUSTER_OK=1
fi

printf -- "\n--- VERIFICA DIRETTA NODO 3 <-- NODO 1 ---\n"
# CORRETTO: Cambiato da -I "002" a -I "001" per tracciare sempre la propagazione del Nodo 1
if "$SCRIPT_PERL" -H "ldaps://ubuntu24lts3.example.com" -U "ldaps://ubuntu24lts1.example.com" -D "$ADMIN_DN" -P "$ADMIN_PW" -S "$BASE_DN" -I "001" -w 10 -c 15 > /dev/null 2>&1; then
    printf -- "[OK] Nodo 3 è in sync con Nodo 1.\n"
else
    printf -- "[ERR] Nodo 3 NON è in sync con Nodo 1.\n"
    CLUSTER_OK=1
fi

printf -- "\n=====================================================================\n"
if [ "$CLUSTER_OK" -eq 0 ]; then
    printf -- "[STATUS FINALE] CLUSTER ALLINEATO: Tutti i nodi sono in sync con il Nodo 1.\n"
    exit 0
else
    printf -- "[STATUS FINALE] CLUSTER DISALLINEATO: Sincronizzazione ancora in corso o fallita.\n"
    exit 1
fi

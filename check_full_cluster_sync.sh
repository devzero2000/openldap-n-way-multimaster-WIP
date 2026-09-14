#!/bin/sh
# ==============================================================================
# SCRIPT:       check_full_cluster_sync.sh
# AUTORE:       Elia Pinto
# DATA:         Settembre 2026
# VERSIONE:     1.0
# SCOPO:        Verifica la convergenza COMPLETA e OMNIDIREZIONALE del cluster
#               OpenLDAP N-Way Multi-Master: ogni master viene verificato
#               rispetto a CIASCUN altro master (non solo rispetto a un unico
#               nodo di riferimento), e ogni read-only viene verificata
#               rispetto a TUTTI e tre i master.
#
# SOSTITUISCE:  check_direct_sync.sh e check_direct_sync_readonlyreplica.sh
#               (erano due script quasi identici, mantenuti a mano in
#               parallelo, che verificavano la sincronizzazione SOLO rispetto
#               a un unico nodo di riferimento (-I "001", sempre e solo
#               Node1) - un nodo poteva risultare "in sync" pur essendo
#               indietro sulle scritture originate da un master diverso da
#               quello di riferimento. Consolidati in un solo controllo
#               genuinamente completo, su richiesta esplicita dell'utente
#               ("ha senso verificare l'intero cluster, master fra loro E
#               master/read-only, con un solo script?").
#
# BUG CORRETTO (trovato e verificato empiricamente prima di questa
# consegna): con "set -e" attivo, "VAR=$(comando_che_fallisce)" termina
# lo script PRIMA di poter leggere "$?" - a differenza di un comando
# dentro un "if", l'assegnazione non e' esente da errexit. Corretto
# disattivando temporaneamente errexit ("set +e" / "set -e") solo
# attorno alla sottoshell che cattura l'output, non altrove.
#
# CONFIGURAZIONE DEL CLUSTER (in cima al file, unico punto da modificare
# se cambia la topologia):
#   MASTERS: coppie "fqdn:sid" di ciascun master (sid = olcServerID)
#   READONLY: fqdn di ciascuna read-only (nessun sid proprio - consumer puro)
#
# USO:
#   ./check_full_cluster_sync.sh
# ==============================================================================

set -eu

BASE_DN="dc=example,dc=com"
ADMIN_DN="cn=admin,dc=example,dc=com"
ADMIN_PW="openldap"
SCRIPT_PERL="./check_ldap_syncrepl_status.pl"

# Un master per riga: "fqdn:sid"
MASTERS="ubuntu24lts1.example.com:001
ubuntu24lts2.example.com:002
ubuntu24lts3.example.com:003"

# Una read-only per riga (nessun sid proprio)
READONLY="ubuntu24lts4.example.com"

if [ ! -f "$SCRIPT_PERL" ]; then
    printf -- "[ERRORE CRITICO] Componente %s non trovato.\n" "$SCRIPT_PERL" >&2
    exit 2
fi

CLUSTER_OK=0

check_one() {
    # $1 = fqdn target, $2 = fqdn upstream, $3 = sid upstream
    target="$1"
    upstream="$2"
    sid="$3"

    printf -- "--- VERIFICA %s <-- %s (SID %s) ---\n" "$target" "$upstream" "$sid"

    set +e
    perl_output=$("$SCRIPT_PERL" -H "ldaps://$target" -U "ldaps://$upstream" \
        -D "$ADMIN_DN" -P "$ADMIN_PW" -S "$BASE_DN" -I "$sid" -w 10 -c 15 2>&1)
    perl_rc=$?
    set -e

    if [ "$perl_rc" -eq 0 ]; then
        printf -- "[OK] %s è in sync con %s per il SID %s.\n\n" "$target" "$upstream" "$sid"
    else
        printf -- "[ERR] %s NON è in sync con %s per il SID %s (dettaglio sotto):\n" "$target" "$upstream" "$sid"
        printf -- "%s\n" "$perl_output" | sed 's/^/    /'
        printf -- "\n"
        CLUSTER_OK=1
    fi
}

printf -- "=====================================================================\n"
printf -- " VERIFICA CONVERGENZA COMPLETA E OMNIDIREZIONALE DEL CLUSTER\n"
printf -- "=====================================================================\n\n"

printf -- "*** MASTER FRA LORO ***\n\n"
# Ogni master viene verificato rispetto a CIASCUN altro master (non solo
# rispetto a un unico nodo di riferimento fisso).
OLD_IFS="$IFS"
IFS='
'
for target_line in $MASTERS; do
    target_fqdn="${target_line%%:*}"
    for upstream_line in $MASTERS; do
        upstream_fqdn="${upstream_line%%:*}"
        upstream_sid="${upstream_line##*:}"
        if [ "$target_fqdn" != "$upstream_fqdn" ]; then
            check_one "$target_fqdn" "$upstream_fqdn" "$upstream_sid"
        fi
    done
done

if [ -n "$READONLY" ]; then
    printf -- "*** READ-ONLY RISPETTO A TUTTI I MASTER ***\n\n"
    for ro_fqdn in $READONLY; do
        for upstream_line in $MASTERS; do
            upstream_fqdn="${upstream_line%%:*}"
            upstream_sid="${upstream_line##*:}"
            check_one "$ro_fqdn" "$upstream_fqdn" "$upstream_sid"
        done
    done
fi
IFS="$OLD_IFS"

printf -- "=====================================================================\n"
if [ "$CLUSTER_OK" -eq 0 ]; then
    printf -- "[STATUS FINALE] CLUSTER PIENAMENTE CONVERGENTE: ogni nodo è allineato con ogni master, su tutti i SID.\n"
    exit 0
else
    printf -- "[STATUS FINALE] CLUSTER NON ANCORA CONVERGENTE: vedi i dettagli [ERR] sopra.\n"
    exit 1
fi

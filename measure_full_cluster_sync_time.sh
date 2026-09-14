#!/bin/sh
# ==============================================================================
# SCRIPT:       measure_full_cluster_sync_time.sh
# AUTORE:       Elia Pinto
# DATA:         Settembre 2026
# VERSIONE:     1.0
# DESCRIZIONE:  Misura il tempo di convergenza COMPLETA e OMNIDIREZIONALE del
#               cluster OpenLDAP N-Way Multi-Master (master fra loro E ogni
#               read-only rispetto a tutti i master), sfruttando
#               check_full_cluster_sync.sh.
#
# SOSTITUISCE:  measure_cluster_recovery_time.sh e
#               measure_cluster_readonly_recovery_time.sh - con un solo
#               script di verifica ora genuinamente completo
#               (check_full_cluster_sync.sh), non serve piu' distinguere fra
#               una misurazione "solo master" e una "master+read-only": lo
#               script unico le copre entrambe sempre.
#
# USO: ./measure_full_cluster_sync_time.sh <timeout_in_secondi>
#      Esempio: ./measure_full_cluster_sync_time.sh 300
# ==============================================================================

set -u

SCRIPT_DIR=$(dirname -- "$0")

if [ "${1:-}" = "" ]; then
    printf -- "Uso: %s <timeout_in_secondi>\n" "$0" >&2
    printf -- "Esempio: %s 300\n" "$0" >&2
    exit 2
fi

exec "$SCRIPT_DIR/_measure_sync_common.sh" "$SCRIPT_DIR/check_full_cluster_sync.sh" "Cluster completo (master + read-only, tutte le direzioni)" "$1"

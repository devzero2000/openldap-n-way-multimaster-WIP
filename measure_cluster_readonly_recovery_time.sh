#!/bin/sh
# ==============================================================================
# SCRIPT:       measure_cluster_recovery_time.sh
# AUTORE:       Elia Pinto
# DESCRIPTION:  Misura il tempo di sincronizzazione e convergenza del cluster
#               e delle repliche readonly
#               OpenLDAP Multi-Master sfruttando il validatore check_direct_sync.sh
# ==============================================================================

set -u

CHECK_SCRIPT="./check_direct_sync_readonlyreplica.sh"
POLL_INTERVAL=1      # Intervallo in secondi tra un controllo e l'altro

# Validazione preventiva della dipendenza principale
if [ ! -f "$CHECK_SCRIPT" ]; then
    printf -- "[ERRORE CRITICO] Script di controllo %s non trovato nella directory corrente.\n" "$CHECK_SCRIPT" >&2
    exit 2
fi

# Gestione del timeout tramite argomento da riga di comando (obbligatorio)
if [ "${1:-}" = "" ]; then
    printf -- "Uso: %s <timeout_in_secondi>\n" "$0" >&2
    printf -- "Esempio: %s 300\n" "$0" >&2
    exit 2
fi

TIMEOUT="$1"
case "$TIMEOUT" in
    *[!0-9]*|0)
        printf -- "[ERRORE] Il timeout specificato ('%s') non è un numero intero valido.\n" "$TIMEOUT" >&2
        exit 2
        ;;
esac

ELAPSED=0

# Creazione sicura di un file temporaneo univoco per i log di stato
TEMP_LOG=$(mktemp /tmp/cluster_sync_status.XXXXXX.log)

# Funzione di pulizia per i file temporanei
# shellcheck disable=SC2317
cleanup() {
    if [ -f "$TEMP_LOG" ]; then
        rm -f "$TEMP_LOG"
    fi
}

# Configurazione del trap per la rimozione del file temporaneo
trap cleanup EXIT INT TERM

printf -- "=====================================================================\n"
printf -- " [CRONOMETRO SYNCREPL] Inizio monitoraggio recupero cluster...\n"
printf -- " Test in corso su intervalli di %ds (Timeout massimo: %ds)\n" "$POLL_INTERVAL" "$TIMEOUT"
printf -- "=====================================================================\n"

START_TIME=$(date +%s)

while [ "$ELAPSED" -lt "$TIMEOUT" ]; do
    if "$CHECK_SCRIPT" > "$TEMP_LOG" 2>&1; then
        END_TIME=$(date +%s)
        ELAPSED=$((END_TIME - START_TIME))
        printf -- "\n[SUCCESSO] Cluster e repliche readonly completamente allineate in %d secondi!\n" "$ELAPSED"
        printf -- "---------------------------------------------------------------------\n"
        cat "$TEMP_LOG"
        exit 0
    else
        printf -- "."
        sleep "$POLL_INTERVAL"
        CURRENT_TIME=$(date +%s)
        ELAPSED=$((CURRENT_TIME - START_TIME))
    fi
done

printf -- "\n\n[TIMEOUT] Il cluster non readonly NON si è allineato entro il limite di %d secondi.\n" "$TIMEOUT"
cat "$TEMP_LOG"
exit 1

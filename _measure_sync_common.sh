#!/bin/sh
# ==============================================================================
# SCRIPT:       _measure_sync_common.sh
# AUTORE:       Elia Pinto
# DATA:         Settembre 2026
# VERSIONE:     1.0
# SCOPO:        Logica condivisa di misurazione del tempo di convergenza,
#               parametrizzata su quale script di controllo usare e come
#               etichettare l'output. Non va lanciato direttamente - e'
#               richiamato da measure_cluster_recovery_time.sh e
#               measure_cluster_readonly_recovery_time.sh, che sono ora
#               piccoli wrapper su questa unica logica condivisa (prima
#               erano due copie quasi identiche, mantenute a mano in
#               parallelo - rischio di manutenzione reale: un fix in una
#               copia poteva facilmente essere dimenticato nell'altra).
#
# NOVITÀ v1.0 rispetto agli script originali separati:
#   - Consolidamento in un'unica logica condivisa (vedi sopra).
#   - Riportato il tempo trascorso IN TEMPO REALE mentre si attende, non
#     solo alla fine - prima si vedeva solo una sequenza di punti (".")
#     senza alcun numero, bisognava aspettare il risultato finale per
#     sapere quanto tempo fosse passato. Ora un contatore live aggiornato
#     ogni secondo sulla stessa riga (tramite \r), leggibile in ogni
#     momento durante l'attesa - proprio l'obiettivo dichiarato di questi
#     script.
#   - Tempo formattato in "Xm Ys" oltre ai secondi grezzi, piu' leggibile
#     per risultati sull'ordine dei minuti (il caso tipico osservato).
#   - Verifica esplicita che lo script di controllo sia anche eseguibile
#     (chmod +x), non solo presente - un file non eseguibile dava prima
#     un errore di permessi poco chiaro solo al primo tentativo di lancio.
# ==============================================================================

set -u

POLL_INTERVAL=1

# --------------------------------------------------------------------------
# Argomenti: script di controllo, etichetta descrittiva, timeout
# --------------------------------------------------------------------------

if [ $# -lt 3 ]; then
    printf -- "Uso interno: %s <check_script> <etichetta> <timeout_in_secondi>\n" "$0" >&2
    exit 2
fi

CHECK_SCRIPT="$1"
LABEL="$2"
TIMEOUT="$3"

if [ ! -f "$CHECK_SCRIPT" ]; then
    printf -- "[ERRORE CRITICO] Script di controllo %s non trovato nella directory corrente.\n" "$CHECK_SCRIPT" >&2
    exit 2
fi

if [ ! -x "$CHECK_SCRIPT" ]; then
    printf -- "[ERRORE CRITICO] Script di controllo %s trovato ma non eseguibile (chmod +x %s).\n" "$CHECK_SCRIPT" "$CHECK_SCRIPT" >&2
    exit 2
fi

case "$TIMEOUT" in
    *[!0-9]*|0)
        printf -- "[ERRORE] Il timeout specificato ('%s') non è un numero intero valido.\n" "$TIMEOUT" >&2
        exit 2
        ;;
esac

# --------------------------------------------------------------------------
# Formatta un numero di secondi come "Xm Ys" (o solo "Ys" sotto il minuto)
# --------------------------------------------------------------------------

format_duration() {
    secs="$1"
    mins=$((secs / 60))
    rem=$((secs % 60))
    if [ "$mins" -gt 0 ]; then
        printf "%dm %ds" "$mins" "$rem"
    else
        printf "%ds" "$rem"
    fi
}

TEMP_LOG=$(mktemp /tmp/cluster_sync_status.XXXXXX.log)

# shellcheck disable=SC2317
cleanup() {
    if [ -f "$TEMP_LOG" ]; then
        rm -f "$TEMP_LOG"
    fi
}
trap cleanup EXIT INT TERM

printf -- "=====================================================================\n"
printf -- " [CRONOMETRO SYNCREPL] Inizio monitoraggio recupero: %s\n" "$LABEL"
printf -- " Script di controllo: %s\n" "$CHECK_SCRIPT"
printf -- " Intervallo di polling: %ds - Timeout massimo: %s\n" "$POLL_INTERVAL" "$(format_duration "$TIMEOUT")"
printf -- "=====================================================================\n\n"

START_TIME=$(date +%s)
ELAPSED=0

while [ "$ELAPSED" -lt "$TIMEOUT" ]; do
    if "$CHECK_SCRIPT" > "$TEMP_LOG" 2>&1; then
        END_TIME=$(date +%s)
        ELAPSED=$((END_TIME - START_TIME))
        printf -- "\r%-70s\r" " "
        printf -- "[SUCCESSO] %s allineato in %s (%d secondi).\n" "$LABEL" "$(format_duration "$ELAPSED")" "$ELAPSED"
        printf -- "---------------------------------------------------------------------\n"
        cat "$TEMP_LOG"
        exit 0
    fi
    sleep "$POLL_INTERVAL"
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    printf -- "\rTempo trascorso: %-10s (timeout: %s)  " "$(format_duration "$ELAPSED")" "$(format_duration "$TIMEOUT")"
done

printf -- "\r%-70s\r" " "
printf -- "\n[TIMEOUT] %s NON si è allineato entro il limite di %s.\n" "$LABEL" "$(format_duration "$TIMEOUT")"
cat "$TEMP_LOG"
exit 1

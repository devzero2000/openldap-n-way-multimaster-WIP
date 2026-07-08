#!/bin/sh
# ==============================================================================
# SCRIPT: monitor_sync_loop.sh
# DESCRIPTION: Loop di monitoraggio temporizzato (30 min max, intervalli di 3 min).
# ==============================================================================

set -u

SCRIPT_CHECK="./check_direct_sync.sh"
SLEEP_TIME=180      # 3 minuti in secondi
MAX_ATTEMPTS=10     # 10 tentativi * 3 minuti = 30 minuti
START_TIME=$(date +%s)

if [ ! -f "$SCRIPT_CHECK" ]; then
    printf "[ERRORE CRITICO] Script %s non trovato.\n" "$SCRIPT_CHECK" >&2
    exit 2
fi

chmod +x "$SCRIPT_CHECK"

printf "Avvio del loop di monitoraggio della sincronizzazione (Max 30 minuti)...\n\n"

attempt=1
while [ "$attempt" -le "$MAX_ATTEMPTS" ]; do
    printf "[Tentativo %d/%d] Esecuzione controllo stato del cluster...\n" "$attempt" "$MAX_ATTEMPTS"
    
    # Esegue lo script di verifica diretta nascondendo l'output parziale
    if "$SCRIPT_CHECK" > /dev/null 2>&1; then
        END_TIME=$(date +%s)
        ELAPSED_SECONDS=$((END_TIME - START_TIME))
        ELAPSED_MINUTES=$((ELAPSED_SECONDS / 60))
        
        printf "\n=====================================================================\n"
        printf "[SUCCESSO] Sincronizzazione completata con successo!\n"
        printf "Tempo impiegato: %d minuti (%d secondi).\n" "$ELAPSED_MINUTES" "$ELAPSED_SECONDS"
        printf "=====================================================================\n"
        exit 0
    fi
    
    # Se non è l'ultimo tentativo, si mette in pausa
    if [ "$attempt" -lt "$MAX_ATTEMPTS" ]; then
        printf "[INFO] Cluster non ancora sincronizzato. Prossimo controllo tra 3 minuti...\n\n"
        sleep "$SLEEP_TIME"
    fi
    
    attempt=$((attempt + 1))
done

printf "\n=====================================================================\n"
printf "[ERRORE] I limiti di tempo (30 minuti) sono stati superati.\n"
printf "La sincronizzazione NON è stata effettuata o i nodi sono rimasti disallineati.\n"
printf "=====================================================================\n"
exit 1

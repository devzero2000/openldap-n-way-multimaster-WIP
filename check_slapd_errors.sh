#!/bin/sh
# ==============================================================================
# SCRIPT: check_slapd_errors.sh
# SCOPO:  Verifica rapida se slapd, su QUESTO nodo, sta producendo errori o e'
#         in stato anomalo - da lanciare localmente su ciascun nodo (o via ssh
#         in loop). Riassume: stato systemd, stato processo (R/S/D/Z), errori
#         recenti nel log, connessioni di rete attive verso i peer.
#         COMPATIBILE POSIX (dash/sh).
# USO:    sudo sh check_slapd_errors.sh [minuti_indietro]
#         (default: ultimi 15 minuti di log)
# ==============================================================================
set -eu

MINUTES="${1:-15}"

printf "=====================================================================\n"
printf "   CONTROLLO ERRORI SLAPD SU: %s\n" "$(hostname)"
printf "   Finestra di log analizzata: ultimi %s minuti\n" "$MINUTES"
printf "=====================================================================\n\n"

# ------------------------------------------------------------------------------
# 1. STATO SYSTEMD
# ------------------------------------------------------------------------------
printf "[1/5] Stato del servizio (systemd)...\n"
SVC_STATE=$(systemctl is-active slapd 2>/dev/null || true)
SVC_SUBSTATE=$(systemctl show slapd -p SubState --value 2>/dev/null || true)
printf "  -> is-active: %s | sub-state: %s\n" "$SVC_STATE" "$SVC_SUBSTATE"

if [ "$SVC_STATE" != "active" ]; then
    printf "  -> [ATTENZIONE] Il servizio non risulta 'active'.\n"
fi
printf "\n"

# ------------------------------------------------------------------------------
# 2. STATO DEL PROCESSO (R/S run/sleep normali, D = bloccato su I/O, Z = zombie)
# ------------------------------------------------------------------------------
printf "[2/5] Stato del processo slapd...\n"
SLAPD_PID=$(pgrep -x slapd | head -n1 || true)

if [ -z "$SLAPD_PID" ]; then
    printf "  -> [CRITICO] Nessun processo slapd trovato in esecuzione.\n\n"
else
    PROC_STATE=$(awk '{print $3}' "/proc/${SLAPD_PID}/stat" 2>/dev/null || echo "?")
    printf "  -> PID: %s | Stato: %s\n" "$SLAPD_PID" "$PROC_STATE"
    case "$PROC_STATE" in
        D)
            printf "  -> [ATTENZIONE] Processo in stato D (uninterruptible sleep) - possibile stallo su I/O/lock.\n"
            ;;
        Z)
            printf "  -> [CRITICO] Processo zombie.\n"
            ;;
        R|S)
            printf "  -> Stato normale.\n"
            ;;
    esac
    printf "\n"
fi

# ------------------------------------------------------------------------------
# 3. ERRORI RECENTI NEL LOG (pattern noti da problemi gia' incontrati)
# ------------------------------------------------------------------------------
printf "[3/5] Scansione log recenti per pattern di errore noti...\n"

LOG_WINDOW=$(sudo journalctl -u slapd --since "-${MINUTES}min" --no-pager 2>/dev/null || true)

if [ -z "$LOG_WINDOW" ]; then
    printf "  -> Nessuna riga di log nella finestra analizzata (o journalctl non disponibile).\n\n"
else
    # Pattern che abbiamo gia' visto causare problemi reali su questo cluster
    for pattern in \
        "rc -100" \
        "quitting" \
        "slapd stopped" \
        "Can't contact LDAP server" \
        "ldap_sasl_interactive_bind" \
        "illegal server ID" \
        "must appear after syncrepl" \
        "core dumped" \
        "Segmentation fault" \
        "backend_startup_one failed" \
        "config error" \
        "abandon" \
        "timeout" \
        "TLS.*error" \
        "attribute type undefined"
    do
        COUNT=$(printf "%s\n" "$LOG_WINDOW" | grep -ci -- "$pattern" 2>/dev/null || true)
        COUNT=${COUNT:-0}
        if [ "$COUNT" -gt 0 ]; then
            printf "  -> [TROVATO x%s] pattern: \"%s\"\n" "$COUNT" "$pattern"
            printf "%s\n" "$LOG_WINDOW" | grep -i -- "$pattern" | tail -n 3 | sed 's/^/       /'
        fi
    done

    # err=0 significa successo su OGNI operazione LDAP riuscita - "err"
    # da solo compare quindi migliaia di volte anche su un log sano. Qui
    # estraiamo invece SOLO le occorrenze di "err=N" con N diverso da
    # zero: un segnale strutturato e affidabile (ogni operazione fallita
    # lo riporta esattamente cosi'), non una stima indicativa.
    REAL_ERR_OPS=$(printf "%s\n" "$LOG_WINDOW" | grep -oE "err=[1-9][0-9]*" | sort | uniq -c | sort -rn)
    REAL_ERR_COUNT=$(printf "%s\n" "$LOG_WINDOW" | grep -cE "err=[1-9][0-9]*" 2>/dev/null || true)
    REAL_ERR_COUNT=${REAL_ERR_COUNT:-0}

    if [ "$REAL_ERR_COUNT" -gt 0 ]; then
        printf "  -> [TROVATE %s operazioni con err= diverso da zero, per codice]:\n" "$REAL_ERR_COUNT"
        printf "%s\n" "$REAL_ERR_OPS" | sed 's/^/       /'
    else
        printf "  -> Nessuna operazione con err= diverso da zero nella finestra analizzata.\n"
    fi

    # "fail"/"critical" a parola intera (non sottostringa) - riduce il
    # rischio di falsi positivi da termini benigni (es. "critical" nel
    # contesto delle estensioni X.509 di un certificato TLS)
    TOTAL_ERR=$(printf "%s\n" "$LOG_WINDOW" | grep -ciE "\bfailed\b|\bfailure\b|\bcritical\b" 2>/dev/null || true)
    TOTAL_ERR=${TOTAL_ERR:-0}
    printf "  -> Righe con 'failed'/'failure'/'critical' come parola intera: %s\n\n" "$TOTAL_ERR"
fi

# ------------------------------------------------------------------------------
# 4. CONNESSIONI DI RETE ATTIVE (verso i peer di replica, porta 636)
# ------------------------------------------------------------------------------
printf "[4/5] Connessioni TCP attive su porta 636 (LDAPS)...\n"
if command -v ss >/dev/null 2>&1; then
    CONNS=$(sudo ss -tn state established '( sport = :636 or dport = :636 )' 2>/dev/null | tail -n +2 || true)
    if [ -z "$CONNS" ]; then
        printf "  -> [ATTENZIONE] Nessuna connessione LDAPS attiva trovata.\n"
    else
        printf "%s\n" "$CONNS" | sed 's/^/  /'
    fi
else
    printf "  -> comando 'ss' non disponibile, salto questo controllo.\n"
fi
printf "\n"

# ------------------------------------------------------------------------------
# 5. slapd risponde davvero su ldapi:/// ?
# ------------------------------------------------------------------------------
printf "[5/5] Verifica risposta effettiva su ldapi:///...\n"
if timeout 5 sudo ldapsearch -Y EXTERNAL -H ldapi:/// -b cn=config -s base dn >/dev/null 2>&1; then
    printf "  -> OK: slapd risponde correttamente su ldapi:///\n\n"
else
    printf "  -> [CRITICO] slapd NON risponde su ldapi:/// entro 5 secondi.\n\n"
fi

printf "=====================================================================\n"
printf "[FINE CONTROLLO] %s\n" "$(hostname)"
printf "=====================================================================\n"

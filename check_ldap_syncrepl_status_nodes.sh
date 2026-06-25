#!/bin/sh

# ==============================================================================
# SCRIPT: check_ldap_syncrepl_status_nodes.sh
# DESCRIPTION: Ring-Check di monitoraggio deterministico della latenza di replica
#              e dello stato di sincronizzazione del cluster Multi-Master N-Way.
#              COMPATIBILE STANDARD POSIX (DASH/SH) - CLEAN OUTPUT
# AUTHOR: Elia Pinto
# DATE: 2026-06-25
# ==============================================================================
# ANALISI ARCHITETTURALE & MECCANISMO DI VERIFICA (DESCRIZIONE OPERATIVA):
#
# 1. VALUTAZIONE DETERMINISTICA AD ANELLO (RING-CHECK)
#    Lo script esegue un controllo incrociato circolare tra i tre nodi per
#    intercettare istantaneamente eventuali partizionamenti di rete (split-brain)
#    o asimmetrie di replica, validando l'intero perimetro del cluster.
#
# 2. ESTRAZIONE E ISOLAMENTO DEI VETTORI OPERATIVI (CSN PARSING)
#    L'utility Perl sottostante interroga contemporaneamente i due nodi di ciascuna
#    coppia ed estrae l'attributo operativo 'contextCSN'.
#    - Dal server di confronto (-U) preleva il timestamp nativo.
#    - Dal server sotto analisi (-H) individua specificamente il vettore che
#      corrisponde al Replica ID passato tramite l'opzione -I.
#
# 3. TRADUZIONE EPOCH E VERIFICA DELLA LATENZA TEMPORALE (DELTA COMPUTATION)
#    Lo script depura le stringhe LDIF isolando la sola componente temporale
#    (Anno, Mese, Giorno, Ora, Minuto, Secondo), scartando i microsecondi e i
#    modificatori finali del server ID. Gli orari vengono convertiti in formato
#    standard Epoch/Unix (secondi trascorsi dal 1/1/1970) per calcolare in modo
#    lineare la distanza matematica (Delta = Tempo_Master - Tempo_Slave).
#
# 4. SOGLIE DI MONITORAGGIO & EXIT CODES (SLA ENFORCEMENT)
#    - Delta < 10s (-w 10): Ritorna Exit Code 0 (OK). Lo stato dei dati è coerente.
#    - 10s <= Delta <= 15s: Ritorna Exit Code 1 (WARNING). La replica accumula lag.
#    - Delta > 15s (-c 15) o Fallimento: Ritorna Exit Code 2 (CRITICAL).
#      Cluster desincronizzato o canale di comunicazione interrotto.
# ==============================================================================

set -eu

# Definizioni delle variabili di configurazione per centralizzare la manutenzione
BASE_DN="dc=example,dc=com"
ADMIN_DN="cn=admin,dc=example,dc=com"
ADMIN_PW="openldap"
SCRIPT_PERL="./check_ldap_syncrepl_status.pl"

# Controllo preventivo dell'esistenza dello script Perl dipendente
if [ ! -f "$SCRIPT_PERL" ]; then
    printf "[ERRORE CRITICO] Componente dipendente %s non trovato nel path.\n" "$SCRIPT_PERL" >&2
    exit 2
fi

printf "=====================================================================\n"
printf "   AVVIO MONITORAGGIO CIRCOLARE DELLA REPLICA (N-WAY RING CHECK)     \n"
printf "=====================================================================\n\n"

# ------------------------------------------------------------------------------
# TEST 1: Verifica accoppiata Nodo 2 rispetto al Nodo 1 (Replica ID: 002)
# ------------------------------------------------------------------------------
printf "[TEST 1/3] Verifica consistenza: ubuntu24lts2 <-- ubuntu24lts1...\n"
"$SCRIPT_PERL" \
    -H "ldap://ubuntu24lts2.example.com" \
    -U "ldap://ubuntu24lts1.example.com" \
    -D "$ADMIN_DN" \
    -P "$ADMIN_PW" \
    -S "$BASE_DN" \
    -I "002" -w 10 -c 15

# ------------------------------------------------------------------------------
# TEST 2: Verifica accoppiata Nodo 3 rispetto al Nodo 2 (Replica ID: 003)
# ------------------------------------------------------------------------------
printf "[TEST 2/3] Verifica consistenza: ubuntu24lts3 <-- ubuntu24lts2...\n"
"$SCRIPT_PERL" \
    -H "ldap://ubuntu24lts3.example.com" \
    -U "ldap://ubuntu24lts2.example.com" \
    -D "$ADMIN_DN" \
    -P "$ADMIN_PW" \
    -S "$BASE_DN" \
    -I "003" -w 10 -c 15

# ------------------------------------------------------------------------------
# TEST 3: Verifica accoppiata Nodo 1 rispetto al Nodo 3 (Replica ID: 001)
# ------------------------------------------------------------------------------
printf "[TEST 3/3] Verifica consistenza: ubuntu24lts1 <-- ubuntu24lts3...\n"
"$SCRIPT_PERL" \
    -H "ldap://ubuntu24lts1.example.com" \
    -U "ldap://ubuntu24lts3.example.com" \
    -D "$ADMIN_DN" \
    -P "$ADMIN_PW" \
    -S "$BASE_DN" \
    -I "001" -w 10 -c 15

printf "\n=====================================================================\n"
printf "[OK] Ciclo di monitoraggio completato. Tutti i nodi sono coerenti.\n"

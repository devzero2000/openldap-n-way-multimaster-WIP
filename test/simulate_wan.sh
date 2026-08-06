#!/bin/sh

# ==============================================================================
# SCRIPT: simulate_wan.sh
# DESCRIPTION: Simulazione di WAN geografica ad alta latenza interstatale
#              applicata ESCLUSIVAMENTE alle porte LDAP (389) e LDAPS (636).
#              COMPATIBILE STANDARD POSIX (DASH/SH) - FIX FILTER SYNTAX
# AUTHOR: Elia Pinto
# DATE: 2026-06-25
# ==============================================================================
set -eu

# CONFIGURAZIONE INTERFACCIA E PARAMETRI METRICHE WAN
IFACE="eth1"
LATENCY="120ms"      # Latenza tipica tra stati/coast remoti
JITTER="15ms"       # Fluttuazione della latenza (varianza)
LOSS="0.5%"         # Percentuale di pacchetti persi (instabilità WAN)
#LOSS="5%"         # Percentuale di pacchetti persi (instabilità WAN) # molto alta
BANDWIDTH="10mbit"  # Strozzatura della banda per simulare link saturo

# Funzione di pulizia per resettare le regole in modo sicuro
clean_rules() {
    printf "[*] Rimozione configurazioni tc/iptables precedenti su %s...\n" "$IFACE"
    
    sudo iptables -t mangle -D POSTROUTING -p tcp --dport 389 -j MARK --set-mark 10 2>/dev/null || true
    sudo iptables -t mangle -D POSTROUTING -p tcp --dport 636 -j MARK --set-mark 10 2>/dev/null || true
    sudo tc qdisc del dev "$IFACE" root 2>/dev/null || true
}

# Se l'utente passa l'argomento "stop", eseguiamo la pulizia e usciamo subito
if [ "${1:-}" = "stop" ]; then
    clean_rules
    printf "[OK] Simulazione WAN disattivata. Rete ripristinata a regime LAN.\n"
    exit 0
fi

# =====================================================================
# SEZIONE DI AVVIO (START DI DEFAULT)
# =====================================================================
printf "=====================================================================\n"
printf "   ATTIVAZIONE SIMULAZIONE WAN SELETTIVA (PORTE 389 / 636)           \n"
printf "=====================================================================\n"

# 1. Reset preventivo dello stato delle code
clean_rules

# 2. Configurazione TC (Traffic Control) - Creazione della radice HTB
sudo tc qdisc add dev "$IFACE" root handle 1: htb default 1

# Creazione di una classe specifica per il traffico LDAP limitato in banda
sudo tc class add dev "$IFACE" parent 1: classid 1:10 htb rate "$BANDWIDTH"

# Applicazione del modulo netem (latenza, jitter e perdita) alla classe 1:10
sudo tc qdisc add dev "$IFACE" parent 1:10 handle 10: netem delay "$LATENCY" "$JITTER" loss "$LOSS"

# FIX: Sostituito 'fwmark' con 'fw' per conformità con i filtri nativi iproute2
sudo tc filter add dev "$IFACE" protocol ip parent 1:0 prio 1 handle 10 fw flowid 1:10

# 3. Marcatura dei pacchetti tramite iptables (Tabella Mangle)
printf "[+] Marcatura traffico TCP in uscita verso porta 389 (LDAP)...\n"
sudo iptables -t mangle -A POSTROUTING -p tcp --dport 389 -j MARK --set-mark 10

printf "[+] Marcatura traffico TCP in uscita verso porta 636 (LDAPS)...\n"
sudo iptables -t mangle -A POSTROUTING -p tcp --dport 636 -j MARK --set-mark 10

printf "=====================================================================\n"
printf "[OK] WAN simulata con successo su %s: %s (+/-%s), Loss: %s, Cap: %s\n" \
    "$IFACE" "$LATENCY" "$JITTER" "$LOSS" "$BANDWIDTH"
printf "=====================================================================\n"

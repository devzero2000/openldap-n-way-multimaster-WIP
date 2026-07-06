#!/sh

# ==============================================================================
# SCRIPT:       simulate_wan.sh
# DESCRIZIONE:  Simulazione di WAN geografica aziendale su circuito MPLS protetto
#               da tunnel IPSec (Cifratura AES-GCM). Applicata ESCLUSIVAMENTE
#               alle porte del cluster LDAP (389) e LDAPS (636).
#               COMPATIBILE STANDARD POSIX (DASH/SH)
# AUTORE:       Elia Pinto
# DATA:         Luglio 2026
# VERSIONE:     2.0
# ==============================================================================
set -eu

# CONFIGURAZIONE INTERFACCIA E PARAMETRI METRICHE WAN (MPLS + IPSEC)
IFACE="eth1"

# 1. METRICHE FISICHE DELLA TRATTA MPLS
LATENCY="50ms"       # Latenza tipica inter-region su dorsale MPLS Enterprise dedicata
JITTER="2ms"         # Jitter minimo (tipico di MPLS con Quality of Service garantita)
LOSS="0.1%"         # Packet loss estremamente ridotto grazie agli SLA dei carrier MPLS

# 2. CAPACITÀ DEL LINK DI SEDE / FILIALE
BANDWIDTH="45mbit"   # Strozzatura simmetrica (es. circuito standard T3/E3 o link business)

# 3. OVERHEAD IPSEC (CRITTOGRAFIA & INCAPSULAMENTO)
# L'incapsulamento IPSec ESP aggiunge circa 56-72 byte di overhead. Per simulare la 
# potenziale frammentazione dei payload LDAP massivi (30k gruppi), limitiamo la 
# dimensione dei pacchetti in coda forzando un collo di bottiglia simulato.
# ==============================================================================

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
printf "   ATTIVAZIONE SIMULAZIONE WAN MPLS + IPSEC (PORTE 389 / 636)        \n"
printf "=====================================================================\n"

# 1. Reset preventivo dello stato delle code
clean_rules

# 2. Configurazione TC (Traffic Control) - Creazione della radice HTB (Hierarchical Token Bucket)
sudo tc qdisc add dev "$IFACE" root handle 1: htb default 1

# Creazione di una classe specifica (1:10) per il traffico LDAP limitato alla banda MPLS allocata
sudo tc class add dev "$IFACE" parent 1: classid 1:10 htb rate "$BANDWIDTH"

# Applicazione del modulo netem (network emulator) alla classe 1:10
# Configura latenza costante, jitter stretto e perdita pacchetti tipica di linee business stabili
sudo tc qdisc add dev "$IFACE" parent 1:10 handle 10: netem delay "$LATENCY" "$JITTER" loss "$LOSS"

# Associazione del filtro iproute2 per intercettare il traffico marcato '10' (fw) e dirottarlo nella coda WAN
sudo tc filter add dev "$IFACE" protocol ip parent 1:0 prio 1 handle 10 fw flowid 1:10

# 3. Marcatura del traffico LDAP/LDAPS tramite iptables (Tabella Mangle)
# I pacchetti diretti ai nodi del cluster sulle porte di sincronizzazione e autenticazione 
# vengono taggati con il flag '10' prima di lasciare la scheda di rete.
printf "[+] Marcatura traffico TCP in uscita verso porta 389 (LDAP MPLS/IPSec)...\n"
sudo iptables -t mangle -A POSTROUTING -p tcp --dport 389 -j MARK --set-mark 10

printf "[+] Marcatura traffico TCP in uscita verso porta 636 (LDAPS MPLS/IPSec)...\n"
sudo iptables -t mangle -A POSTROUTING -p tcp --dport 636 -j MARK --set-mark 10

printf "=====================================================================\n"
printf "[OK] WAN MPLS+IPSec simulata su %s:\n" "$IFACE"
printf "     Latenza d'Infrastruttura: %s (+/-%s)\n" "$LATENCY" "$JITTER"
printf "     Perdita Pacchetti (Loss): %s\n" "$LOSS"
printf "     Banda Canale Allocato   : %s\n" "$BANDWIDTH"
printf "=====================================================================\n"

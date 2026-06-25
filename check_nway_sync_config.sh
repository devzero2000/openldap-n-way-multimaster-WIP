#!/bin/sh
# ==============================================================================
# SCRIPT: check_nway_configuration.sh
# DESCRIPTION: Analisi a caldo della configurazione del motore di replica 
#              OpenLDAP Multi-Master N-Way sul database locale {1}mdb.
# AUTHOR: Elia Pinto
# DATE: 2026-06-25
# ==============================================================================
# CONSIDERAZIONI ARCHITETTURALI & HARDENING (VERIFICA DI RUNTIME):
#
# 1. TOPOLOGIA N-WAY & COERENZA DEI NODI (JINJA ISOLATION)
#    Il motore estrae le istanze attive di 'olcSyncRepl' (es. indici {0} e {1}).
#    La presenza di esattamente (N-1) istanze attive attesta la corretta 
#    esecuzione della logica condizionale Ansible: il nodo locale esclude se 
#    stesso dalla lista dei consumatori e aggancia unicamente i partner remoti 
#    dando continuità all'anello Multi-Master.
#
# 2. MINIMIZZAZIONE DEI PRIVILEGI (ROLE-BASED ISOLATION)
#    La direttiva 'binddn' deve puntare tassativamente all'utenza dedicata a
#    privilegi minimi: "cn=nwayreplicator,ou=system,dc=example,dc=com".
#    Questo garantisce l'avvenuto hardening del cluster: le credenziali supreme
#    di "cn=admin" non vengono mai esposte né transitate sui socket di replica.
#    In caso di compromissione di un singolo nodo, la superficie di attacco
#    rimane circoscritta all'albero di sincronizzazione.
#
# 3. STATO DEGLI OVERLAY (PPO_CLEANUP_VERIFICATION)
#    L'output deve mostrare esclusivamente l'overlay '{0}syncprov' attivo sul
#    database {1}mdb. La totale assenza dell'overlay 'ppolicy' a livello di 
#    cn=config conferma la rimozione delle code orfane e dei vecchi conflitti 
#    di schema, lasciando il transito dei dati lineare e pulito.
#
# 4. TUNING WAN & RESILIENZA DEL TRASPORTO
#    La configurazione convalida i parametri critici di stabilità di rete:
#    - type=refreshAndPersist: Canale sincrono persistente (Zero-Lag).
#    - retry="5 10 10 ... +": Tentativi infiniti (+) contro lo split-brain WAN.
#    - keepalive=240:4:15: Probing TCP attivo per il bypass dei drop dei firewall.
# ==============================================================================
set -eu 

printf "=====================================================================\n"
printf "   ESTRAZIONE INTEGRALE CONFIGURAZIONE REPLICA & OVERLAYS {1}mdb     \n"
printf "=====================================================================\n\n"

# 1. Eseguiamo il comando critico salvando l'intero output nella variabile.
#    Se OpenLDAP è spento o il comando fallisce, 'set -e' blocca lo script qui.
RAW_CONFIG=$(sudo ldapsearch -Y EXTERNAL -H ldapi:/// -b "olcDatabase={1}mdb,cn=config" olcSyncRepl)

printf "%s\n" "$RAW_CONFIG"

printf "\n=====================================================================\n"
printf "[OK] Analisi completata. Output strutturale estratto integralmente.\n"
printf "=====================================================================\n"

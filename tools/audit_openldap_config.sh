#!/usr/bin/env bash
# ==============================================================================
# SCRIPT:       audit_openldap_config.sh
# AUTORE:       Elia Pinto
# DATA:         Luglio 2026
# SCOPO:        Audit ed enumerazione completa delle configurazioni di OpenLDAP 
#               (cn=config) ed estrazione degli attributi operativi/CSN.
# ==============================================================================

set -euo pipefail

# --- VARIABILI GLOBALI E COLORI ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

URI="ldapi:///"
BASE_CONFIG="cn=config"

check_prerequisites() {
    if [[ $EUID -ne 0 ]]; then
        printf "${RED}[ERROR] Eseguire come root (o via sudo) per accedere a ldapi:///${NC}\n" >&2
        exit 1
    fi

    if ! command -v ldapsearch &> /dev/null; then
        printf "${RED}[ERROR] Comando 'ldapsearch' non trovato.${NC}\n" >&2
        exit 1
    fi
}

# ldapsearch con estrazione sia degli attributi ordinari (*) che operativi (+)
exec_ldapsearch_full() {
    local base_dn="$1"
    local scope="$2"
    local filter="$3"
    shift 3
    ldapsearch -Y EXTERNAL -H "$URI" -o ldif-wrap=no -b "$base_dn" -s "$scope" "$filter" "*" "+" "$@" 2>/dev/null
}

log_section() { printf -- "\n${BOLD}${CYAN}=== %s ===${NC}\n" "$1"; }

# --- SEZIONI DI AUDIT ---

audit_global_config() {
    log_section "1. CONFIGURAZIONE GLOBALE ENGINE (cn=config)"
    exec_ldapsearch_full "$BASE_CONFIG" base "(objectClass=*)" | \
        grep -v -E "^(SASL|search:|result:|#|numResponses:|numEntries:)" || true
}

audit_replication_topology() {
    log_section "2. DETTAGLIO TOPOLOGIA REPLICA N-WAY MULTI-MASTER"
    
    printf "  ${BOLD}${YELLOW}[Server ID Cluster (olcServerID)]${NC}\n"
    exec_ldapsearch_full "$BASE_CONFIG" base "(olcServerID=*)" | \
        grep "^olcServerID:" | sed 's/^/    /' || printf "    ${RED}Nessun olcServerID trovato.${NC}\n"

    local dbs
    dbs=$(exec_ldapsearch_full "$BASE_CONFIG" sub "(objectClass=olcDatabaseConfig)" | grep "^dn:" | cut -d' ' -f2 || true)

    for db_dn in $dbs; do
        local syncrepl_check
        syncrepl_check=$(exec_ldapsearch_full "$db_dn" base "(objectClass=*)" | grep -E "^(olcSyncrepl|olcMultiProvider):" || true)
        
        if [[ -n "$syncrepl_check" ]]; then
            printf "\n  ${BOLD}${GREEN}[Target Database: %s]${NC}\n" "$db_dn"
            echo "$syncrepl_check" | while read -r line; do
                if [[ "$line" =~ ^olcMultiProvider: ]]; then
                    printf "    ${BOLD}Multi-Master Mode:${NC} %s\n" "${line#olcMultiProvider: }"
                elif [[ "$line" =~ ^olcSyncrepl: ]]; then
                    printf "\n    ${BOLD}Direttiva SyncRepl:${NC}\n"
                    echo "${line#olcSyncrepl: }" | sed 's/ /\n      /g' | sed 's/^/      /'
                fi
            done
        fi
    done
}

audit_context_csn() {
    log_section "3. STATO VETTORI DI REPLICA (contextCSN e entryCSN)"
    
    # 1. contextCSN sul DIT Dati (Suffix principale)
    local suffix
    suffix=$(exec_ldapsearch_full "$BASE_CONFIG" sub "(olcSuffix=*)" | grep "^olcSuffix:" | head -n 1 | cut -d' ' -f2 || true)

    if [[ -n "$suffix" ]]; then
        printf "  ${BOLD}${YELLOW}[contextCSN del DIT Dati (%s)]${NC}\n" "$suffix"
        exec_ldapsearch_full "$suffix" base "(objectClass=*)" | grep "^contextCSN:" | sed 's/^/    /' || printf "    ${RED}Nessun contextCSN presente.${NC}\n"
    fi

    # 2. contextCSN sulla radice cn=config
    printf "\n  ${BOLD}${YELLOW}[contextCSN del DIT Configurazione (cn=config)]${NC}\n"
    exec_ldapsearch_full "$BASE_CONFIG" base "(objectClass=*)" | grep "^contextCSN:" | sed 's/^/    /' || printf "    ${RED}Nessun contextCSN di configurazione presente.${NC}\n"
}

audit_loaded_modules() {
    log_section "4. MODULI DINAMICI CARICATI (cn=module*)"
    local modules
    modules=$(exec_ldapsearch_full "$BASE_CONFIG" sub "(objectClass=olcModuleList)" | grep "^olcModuleLoad:" || true)
    
    if [[ -n "$modules" ]]; then
        echo "$modules" | sed 's/olcModuleLoad: //' | while read -r mod; do
            printf "  ${BOLD}• Modulo:${NC} %s\n" "$mod"
        done
    fi
}

audit_overlays() {
    log_section "5. OVERLAY PRESENTI ED ATTIVI (olcOverlay=*)"

    local overlays
    overlays=$(exec_ldapsearch_full "$BASE_CONFIG" sub "(objectClass=olcOverlayConfig)" | grep "^dn:" | cut -d' ' -f2 || true)

    for ov_dn in $overlays; do
        local ov_name
        ov_name=$(echo "$ov_dn" | sed -n 's/.*olcOverlay={\?[0-9]*}\?\([^,]*\),.*/\1/p')
        
        printf "\n  ${BOLD}${GREEN}✔ Overlay Rilevato:${NC} ${BOLD}%s${NC}\n" "$ov_name"
        printf "    ${BLUE}DN:${NC} %s\n" "$ov_dn"
        printf "    ${BOLD}Configurazione estesa:${NC}\n"
        
        exec_ldapsearch_full "$ov_dn" base "(objectClass=*)" | \
            grep -v -E "^(SASL|search:|result:|#|numResponses:|numEntries:|dn:|objectClass:|structuralObjectClass:|creatorsName:|createTimestamp:|modifiersName:|modifyTimestamp:)" | \
            sed 's/^/      /' || true
    done
}

audit_mdb_full_dump() {
    log_section "6. DUMP COMPLETO CONFIGURAZIONE olcDatabase={1}mdb,cn=config"

    exec_ldapsearch_full "olcDatabase={1}mdb,cn=config" base "(objectClass=*)" | \
        grep -v -E "^(SASL|search:|result:|#|numResponses:|numEntries:)" || true
}

main() {
    clear
    printf "${BOLD}${BLUE}"
    printf "======================================================================\n"
    printf "          OPENLDAP CONFIGURATION & OVERLAY AUDIT REPORT               \n"
    printf "======================================================================\n"
    printf "${NC}"
    printf "Data Esecuzione : %s\n" "$(date)"
    printf "Host Name       : %s\n" "$(hostname -f)"

    check_prerequisites
    audit_global_config
    audit_replication_topology
    audit_context_csn
    audit_loaded_modules
    audit_overlays
    audit_mdb_full_dump

    printf "\n${GREEN}[INFO] Audit completato con successo.${NC}\n\n"
}

main "$@"

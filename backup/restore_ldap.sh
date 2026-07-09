#!/usr/bin/env bash
# ==============================================================================
# TITOLO:       Restore Parametrizzato OpenLDAP (cn=config + MDB)
# AUTORE:       Elia Pinto
# DATA:         Luglio 2026
# SCOPO:        Ripristina configurazione e dati. Gestisce in sicurezza sia il
#               rientro standard nel cluster che il Disaster Recovery totale.
# ==============================================================================

set -euo pipefail
IFS=$'\n\t'

# --- CONFIGURAZIONE VARIABILI ---
LDAP_BASE_DN="dc=example,dc=com"
TMP_RESTORE_DIR="/tmp/ldap_restore_unpack"
DR_MODE=false
BACKUP_FILE=""

# --- FUNZIONE HELP ---
usage() {
    echo "Uso: $0 [OPZIONI] -f <file_backup.tar.gz>"
    echo "Opzioni:"
    echo "  -f, --file      Percorso assoluto del file di backup .tar.gz"
    echo "  --force-disaster-recovery"
    echo "                  Abilita la sorgente della verità assoluta."
    echo "                  Usa questo flag SOLO se l'intero cluster è compromesso"
    echo "                  e vuoi forzare tutti i nodi a tornare indietro nel tempo."
    echo "  -h, --help      Mostra questo aiuto"
    exit 1
}

# --- PARSING DEI PARAMETRI ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--file)
            BACKUP_FILE="$2"
            shift 2
            ;;
        --force-disaster-recovery)
            DR_MODE=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "[-] Opzione sconosciuta: $1" >&2
            usage
            ;;
    esac
done

# --- VERIFICHE PRELIMINARI ---
if [[ ${EUID} -ne 0 ]]; then
    echo "[-] ERRORE: Questo script deve essere eseguito come root." >&2
    exit 1
fi

if [[ -z "${BACKUP_FILE}" ]]; then
    echo "[-] ERRORE: Parametro -f/--file obbligatorio." >&2
    usage
fi

if [[ ! -f "${BACKUP_FILE}" ]]; then
    echo "[-] ERRORE: Il file di backup ${BACKUP_FILE} non esiste." >&2
    exit 1
fi

# --- STAMPA DELLO STATO OPERATIVO ---
echo "======================================================================"
echo "[+] AVVIO PROCEDURA DI RESTORE"
echo "[+] File di backup: ${BACKUP_FILE}"
if [ "${DR_MODE}" = true ]; then
    echo "[!] MODALITÀ: DISASTER RECOVERY (Sorgente della verità forzata)"
    echo "[!] Nota: I vecchi metadati contextCSN verranno rigenerati al timestamp attuale."
else
    echo "[+] MODALITÀ: STANDARD CLUSTER JOIN (Conservativa)"
    echo "[+] Nota: Il nodo si riallineerà alle transazioni più recenti dei peer."
fi
echo "======================================================================"

read -rp "[?] Sei sicuro di voler procedere? (y/N): " CONFIRM
if [[ "${CONFIRM}" != "y" && "${CONFIRM}" != "Y" ]]; then
    echo "[-] Operazione annullata dall'utente."
    exit 0
fi

# --- FASE 1: DECOMPRESSIONE ---
echo "[+] Decompressione del pacchetto di backup..."
rm -rf "${TMP_RESTORE_DIR}"
mkdir -p "${TMP_RESTORE_DIR}"
tar -xzf "${BACKUP_FILE}" -C "${TMP_RESTORE_DIR}"

INNER_DIR=$(find "${TMP_RESTORE_DIR}" -mindepth 1 -maxdepth 1 -type d | head -n 1)
if [[ -z "${INNER_DIR}" ]]; then
    echo "[-] ERRORE: Struttura del backup non valida." >&2
    exit 1
fi

# --- FASE 2: STOP DEL SERVIZIO ---
echo "[+] Arresto del servizio slapd..."
systemctl stop slapd

# --- FASE 3: RIPRISTINO CONFIGURAZIONE (/etc/ldap) ---
if [[ -f "${INNER_DIR}/etc_ldap_assets.tar.gz" ]]; then
    echo "[+] Ripristino dei file in /etc/ldap..."
    rm -rf /etc/ldap
    tar -xzf "${INNER_DIR}/etc_ldap_assets.tar.gz" -C /etc
fi

echo "[+] Svuotamento della configurazione slapd.d corrente..."
rm -rf /etc/ldap/slapd.d/*

echo "[+] Importazione di cn=config..."
slapadd -F /etc/ldap/slapd.d -b "cn=config" -l "${INNER_DIR}/cn_config.ldif"

# --- FASE 4: RIPRISTINO DATI MDB ---
echo "[+] Svuotamento del database MDB corrente (/var/lib/ldap)..."
find /var/lib/ldap -type f -name "*.mdb" -delete

if [ "${DR_MODE}" = true ]; then
    echo "[!] Modifica LDIF per Disaster Recovery: Rimozione vecchi contextCSN..."
    grep -v -i "contextCSN:" "${INNER_DIR}/data_mdb.ldif" > "${INNER_DIR}/data_mdb_dr.ldif" || true
    
    echo "[+] Importazione dei dati MDB (Generazione nuovo contesto di replica con -w)..."
    slapadd -F /etc/ldap/slapd.d -b "${LDAP_BASE_DN}" -l "${INNER_DIR}/data_mdb_dr.ldif" -w
else
    echo "[+] Importazione dei dati MDB (Preservando contesto di replica del backup con -w)..."
    slapadd -F /etc/ldap/slapd.d -b "${LDAP_BASE_DN}" -l "${INNER_DIR}/data_mdb.ldif" -w
fi

# --- FASE 5: PERMESSI DI SICUREZZA ---
echo "[+] Ripristino dei permessi di sicurezza..."
chown -R openldap:openldap /etc/ldap/slapd.d
chmod -R 750 /etc/ldap/slapd.d
chown -R openldap:openldap /var/lib/ldap
chmod -R 700 /var/lib/ldap

# --- FASE 6: AVVIO SERVIZIO E PULIZIA ---
echo "[+] Avvio del servizio slapd..."
systemctl start slapd

echo "[+] Rimozione dei file temporanei..."
rm -rf "${TMP_RESTORE_DIR}"

echo "[+] VERIFICA: Stato del servizio slapd:"
systemctl is-active slapd || echo "[-] ATTENZIONE: slapd non è partito correttamente."

echo "[+] Procedura terminata."

#!/usr/bin/env bash
# ==============================================================================
# TITOLO:       Backup Totale OpenLDAP (cn=config + MDB)
# AUTORE:       Elia Pinto
# DATA:         Luglio 2026
# SCOPO:        Esegue il dump atomico e coerente di configurazione e dati
#               di un singolo nodo OpenLDAP, gestendo la ritenzione dei file.
# ==============================================================================

# --- CONFIGURAZIONE RIGIDA (Stile Strict Mode) ---
set -euo pipefail
IFS=$'\n\t'

# --- VARIABILI DI AMBIENTE ---
BACKUP_DIR="/var/backups/ldap"
RETENTION_DAYS=7
HOSTNAME=$(hostname -f)
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_NAME="${HOSTNAME}_ldap_${TIMESTAMP}"
TARGET_DIR="${BACKUP_DIR}/${BACKUP_NAME}"

# --- VERIFICA PRIVILEGI ---
if [[ ${EUID} -ne 0 ]]; then
    echo "[-] ERRORE: Questo script deve essere eseguito come root." >&2
    exit 1
fi

# --- VERIFICA COMPONENTI ---
if ! command -v slapcat &> /dev/null; then
    echo "[-] ERRORE: 'slapcat' non trovato. Verificare l'installazione di OpenLDAP." >&2
    exit 1
fi

# --- ESECUZIONE BACKUP ---
echo "[+] Inizio procedura di backup per il nodo: ${HOSTNAME}"
echo "[+] Creazione directory di destinazione: ${TARGET_DIR}"
mkdir -p "${TARGET_DIR}"
chmod 700 "${TARGET_DIR}"

echo "[+] Dump della configurazione globale (cn=config)..."
if ! slapcat -b "cn=config" -l "${TARGET_DIR}/cn_config.ldif" 2>/dev/null; then
    echo "[-] ERRORE: Fallito il dump di cn=config" >&2
    exit 1
fi

echo "[+] Dump del database principale (DIT)..."
if ! slapcat -b "dc=example,dc=com" -l "${TARGET_DIR}/data_mdb.ldif" 2>/dev/null; then
    echo "[-] ERRORE: Fallito il dump dei dati MDB" >&2
    exit 1
fi

# Copia di sicurezza dei file di configurazione del demone OS
if [[ -d "/etc/ldap" ]]; then
    echo "[+] Copia della directory /etc/ldap..."
    tar -czf "${TARGET_DIR}/etc_ldap_assets.tar.gz" -C /etc ldap
fi

# --- COMPRESSIONE E MESSA IN SICUREZZA ---
echo "[+] Compressione dell'intero set di backup..."
tar -czf "${BACKUP_DIR}/${BACKUP_NAME}.tar.gz" -C "${BACKUP_DIR}" "${BACKUP_NAME}"

# Pulizia directory temporanea di scompattamento
rm -rf "${TARGET_DIR}"

# Protezione del file tar.gz finale
chmod 600 "${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"
chown openldap:openldap "${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"

echo "[+] Backup completato con successo: ${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"

# --- ROTAZIONE AUTOMATICA (RITENZIONE) ---
echo "[+] Verifica ed eliminazione dei vecchi backup (Ritenzione: ${RETENTION_DAYS} giorni)..."
find "${BACKUP_DIR}" -type f -name "${HOSTNAME}_ldap_*.tar.gz" -mtime +"${RETENTION_DAYS}" -exec rm -f {} \;

echo "[+] Procedura terminata."

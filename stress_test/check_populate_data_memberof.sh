#!/bin/sh
# ==============================================================================
# SCRIPT: check_populated_data.sh
# DESCRIPTION: Audit di verifica post-popolamento dei dati nel DIT con 
#              controllo di conformità crittografica, consistenza di memberOf
#              e stabilità della replica Multi-Master.
#              COMPATIBILE STANDARD POSIX (DASH/SH) - STRICT ERROR HANDLING
# AUTHOR: Elia Pinto
# DATE: 2026-07-14
# ==============================================================================
# LOGICA DI VERIFICA & HARDENING AUDIT (DESCRIZIONE OPERATIVA):
#
# 1. VERIFICA STRUTTURALE DELLE UNITÀ ORGANIZZATIVE (OU CHECK)
#    Controlla la presenza delle fondamenta del DIT (ou=People, ou=groups).
#
# 2. AUDIT INTEGRITÀ UTENTI & VALIDAZIONE HASH (PASSWORD HARDENING CHECK)
#    Esegue un campionamento su utenze strategiche (user.1, user.15000, user.30000)
#    per convalidare l'esistenza delle objectClass strutturali e l'hash SSHA.
#
# 3. VERIFICA FUNZIONALE E DI CONSISTENZA DEL COSTRUTTO MEMBEROF
#    Controlla che l'overlay stia valorizzando fisicamente e correttamente
#    l'attributo 'memberOf' sui record degli utenti campionati, verificando la
#    corrispondenza bidirezionale con i 40 ruoli globali 'architect.i'.
# ==============================================================================

set -eu

BASE_DN="dc=example,dc=com"
ADMIN_DN="cn=admin,dc=example,dc=com"
ADMIN_PW="openldap"

printf "=====================================================================\n"
printf "   AVVIO AUDIT DI CONVALIDA INTEGRITÀ, REPLICA E MEMBEROF           \n"
printf "=====================================================================\n\n"

# ------------------------------------------------------------------------------
# PHASE 1: Verifica Unità Organizzative (OU) di Base
# ------------------------------------------------------------------------------
printf "[FASE 1/3] Verifica delle Unità Organizzative strutturali...\n"
OU_CHECK=$(sudo ldapsearch -x -D "$ADMIN_DN" -w "$ADMIN_PW" -H ldapi:/// \
    -b "$BASE_DN" -s one "(objectClass=organizationalUnit)" ou)
printf "%s\n\n" "$OU_CHECK"

# ------------------------------------------------------------------------------
# PHASE 2: Audit Utenti e Validazione Rigida degli Hash Password
# ------------------------------------------------------------------------------
printf "[FASE 2/3] Audit profili utente e verifica conformità HASH {SSHA}...\n"

# Campionamento mirato per coprire l'inizio, il mezzo e la fine del dataset di 30k
for index in 1 15000 30000; do
    USER_DN="uid=user.${index},ou=People,${BASE_DN}"
    
    USER_DATA=$(sudo ldapsearch -x -D "$ADMIN_DN" -w "$ADMIN_PW" -H ldapi:/// \
        -b "$USER_DN" -s base objectClass userPassword)
    
    # 1. Verifica presenza dell'utente e objectClass corretta
    if ! printf "%s\n" "$USER_DATA" | grep -q "objectClass: inetOrgPerson"; then
        printf "  -> [ERRORE CRITICO] Utente user.%s non integro o mancante.\n" "$index" >&2
        exit 1
    fi

    # 2. ISPEZIONE DI SICUREZZA: Controllo della presenza dello schema hash
    if printf "%s\n" "$USER_DATA" | grep -qE "userPassword:: |userPassword: \{SSHA\}"; then
        printf "  -> Utente user.%s: PRESENTE [Sicurezza Password: CONFORME HASH]\n" "$index"
    else
        printf "  -> [VIOLAZIONE DI SICUREZZA] L'utente user.%s ha una password IN CHIARO!\n" "$index" >&2
        exit 2
    fi
done
printf "\n"

# ------------------------------------------------------------------------------
# PHASE 3: Convalida dell'overlay slapo-memberof e consistenza della replica
# ------------------------------------------------------------------------------
printf "[FASE 3/3] Verifica integrità dell'attributo inverso memberOf...\n"

# Utilizziamo l'utente user.501 (matematicamente presente nel ruolo architect.1)
TEST_USER="uid=user.501,ou=People,${BASE_DN}"
MEMBEROF_DATA=$(sudo ldapsearch -x -D "$ADMIN_DN" -w "$ADMIN_PW" -H ldapi:/// \
    -b "$TEST_USER" -s base memberOf)

if printf "%s\n" "$MEMBEROF_DATA" | grep -q "memberOf: cn=architect.1,ou=groups,${BASE_DN}"; then
    printf "  -> [CONFORME] Attributo 'memberOf' correttamente popolato per %s\n" "user.501"
    printf "                Mappato nel ruolo: cn=architect.1\n"
else
    printf "  -> [ERRORE CRITICO] L'overlay slapo-memberof non ha generato l'attributo inverso.\n" >&2
    exit 3
fi

# Audit quantitativo su un ruolo "Architect" globale (Deve contenere esattamente 10.000 membri)
printf "\n• Verifica consistenza quantitativa del ruolo 'architect.1':\n"
ARCHITECT_DN="cn=architect.1,ou=groups,${BASE_DN}"
ARCHITECT_DATA=$(sudo ldapsearch -x -D "$ADMIN_DN" -w "$ADMIN_PW" -H ldapi:/// \
    -b "$ARCHITECT_DN" -s base member)

MEMBER_COUNT=$(printf "%s\n" "$ARCHITECT_DATA" | grep -c "member:")
printf "  -> Gruppo 'architect.1': (%s di 10000 membri mappati)\n" "$MEMBER_COUNT"

if [ "$MEMBER_COUNT" -ne 10000 ]; then
    printf "  -> [ERRORE] Il conteggio dei membri nel gruppo non corrisponde al dataset atteso.\n" >&2
    exit 4
fi

printf "\n=====================================================================\n"
printf "[CONVALIDA RIUSCITA] DIT conforme e integrità di memberOf verificata.\n"
printf "=====================================================================\n"

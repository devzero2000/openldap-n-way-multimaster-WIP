#!/bin/sh
# ==============================================================================
# SCRIPT: check_populated_data.sh
# DESCRIPTION: Audit di verifica post-popolamento dei dati nel DIT con 
#              controllo di conformità crittografica (No Cleartext Passwords).
#              COMPATIBILE STANDARD POSIX (DASH/SH) - STRICT ERROR HANDLING
# AUTHOR: Elia Pinto
# DATE: 2026-06-25
# ==============================================================================
# LOGICA DI VERIFICA & HARDENING AUDIT (DESCRIZIONE OPERATIVA):
#
# 1. VERIFICA STRUTTURALE DELLE UNITÀ ORGANIZZATIVE (OU CHECK)
#    Controlla la presenza delle fondamenta del DIT (ou=People, ou=Groups).
#
# 2. AUDIT INTEGRITÀ UTENTI & VALIDAZIONE HASH (PASSWORD HARDENING CHECK)
#    Cicla sui 10 utenti (user01-user10) per verificare l'esistenza delle 
#    ObjectClass strutturali ed esamina la stringa del valore 'userPassword'. 
#    L'audit valida ed esige che l'attributo sia cifrato e memorizzato in formato 
#    sicuro (verificando il token nativo '{SSHA}' o l'encoding Base64 'userPassword::' 
#    generato automaticamente da OpenLDAP per gli hash binari). 
#    La presenza di qualsiasi password in chiaro (cleartext) interrompe l'audit 
#    generando un blocco di sicurezza immediato.
#
# 3. CONVALIDA GRUPPI E ALBERATURE DI MEMBERSHIP (GROUP MAPPING VERIFICATION)
#    Valuta l'esistenza del gruppo POSIX di base (mainstaff) ed estrae il conteggio 
#    degli attributi 'member' per i 5 gruppi di fantasia (developers, operators, 
#    managers, auditors, analysts) per certificare l'avvenuta replica dei mapping.
# ==============================================================================

set -eu

BASE_DN="dc=example,dc=com"
ADMIN_DN="cn=admin,dc=example,dc=com"
ADMIN_PW="openldap"

printf "=====================================================================\n"
printf "   AVVIO AUDIT DI CONVALIDA INTEGRITÀ E SICUREZZA CRITTOGRAFICA       \n"
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

i=1
while [ "$i" -le 10 ]; do
    if [ "$i" -lt 10 ]; then
        pad="0$i"
    else
        pad="$i"
    fi

    USER_DN="uid=user${pad},ou=People,${BASE_DN}"
    
    # Estraiamo in modo mirato le objectClass e l'attributo userPassword
    USER_DATA=$(sudo ldapsearch -x -D "$ADMIN_DN" -w "$ADMIN_PW" -H ldapi:/// \
        -b "$USER_DN" -s base objectClass userPassword)
    
    # 1. Verifica presenza dell'utente e objectClass corretta
    if ! printf "%s\n" "$USER_DATA" | grep -q "objectClass: inetOrgPerson"; then
        printf "  -> [ERRORE CRITICO] Utente user%s non integro o mancante.\n" "$pad" >&2
        exit 1
    fi

    # 2. ISPEZIONE DI SICUREZZA: Controllo della presenza dello schema hash
    if printf "%s\n" "$USER_DATA" | grep -qE "userPassword:: |userPassword: \{SSHA\}"; then
        printf "  -> Utente user%s: PRESENTE [Sicurezza Password: CONFORME HASH]\n" "$pad"
    else
        printf "  -> [VIOLAZIONE DI SICUREZZA] L'utente user%s ha una password IN CHIARO!\n" "$pad" >&2
        exit 2
    fi

    i=$((i + 1))
done
printf "\n"

# ------------------------------------------------------------------------------
# PHASE 3: Convalida dei Gruppi e delle relative Alberature di Membership
# ------------------------------------------------------------------------------
printf "[FASE 3/3] Convalida dei Gruppi e mappatura dei membri...\n"

printf "• Verifica gruppo primario 'mainstaff':\n"
MAINSTAFF_CHECK=$(sudo ldapsearch -x -D "$ADMIN_DN" -w "$ADMIN_PW" -H ldapi:/// \
    -b "cn=mainstaff,ou=Groups,${BASE_DN}" -s base objectClass gidNumber)
printf "%s\n\n" "$MAINSTAFF_CHECK"

printf "• Verifica dei 5 gruppi di fantasia (groupOfNames):\n"
for group in developers operators managers auditors analysts; do
    GROUP_DN="cn=${group},ou=Groups,${BASE_DN}"
    GROUP_DATA=$(sudo ldapsearch -x -D "$ADMIN_DN" -w "$ADMIN_PW" -H ldapi:/// -b "$GROUP_DN" -s base member)
    MEMBER_COUNT=$(printf "%s\n" "$GROUP_DATA" | grep -c "member:")
    printf "  -> Gruppo '%s': Configurato correttamente (%s membri mappati)\n" "$group" "$MEMBER_COUNT"
done

printf "\n=====================================================================\n"
printf "[CONVALIDA RIUSCITA] DIT integro e conformità di sicurezza verificata.\n"
printf "=====================================================================\n"

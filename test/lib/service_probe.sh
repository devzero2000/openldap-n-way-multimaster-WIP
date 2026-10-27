#!/bin/bash
# ==============================================================================
# TITOLO:       service_probe.sh
# AUTORE:       Elia Pinto
# DATA:         27 Ottobre 2026
# SCOPO:        Sonda di servizio eseguita in background su un nodo LDAP
#               durante un test di resilienza (avviata e fermata da
#               service_probe.yml). A ogni giro fa una lettura e, in modalita'
#               "rw", una scrittura sullo slapd LOCALE (ldaps://127.0.0.1) e
#               registra esito e latenza di ogni operazione.
#
# PERCHE' LOCALE: in uno scenario geografico i client stanno nel sito del
# proprio nodo; la domanda e' se OGNI sito continua a servire durante il
# guasto, non se il nodo di controllo raggiunge gli altri attraverso la WAN.
#
# SCRITTURE: ogni scrittura crea una entry univoca
# cn=svcprobe.<run>.<etichetta>.<seq>,ou=people,<base>. Quelle confermate
# (rc=0) sono la base della verifica di durabilita': a fine test devono
# esistere su tutti i nodi (service_probe_report.py).
#
# FORMATO DEL LOG (una riga per operazione, campi separati da spazio):
#   <R|W> <seq> <inizio_epoch_ms> <rc> <latenza_ms> [<dn>]
# rc=124: operazione interrotta dal timeout (slapd fermo o bloccato).
#
# ARRESTO: termina al giro successivo alla comparsa del file "stop" nella
# directory del log, oppure con SIGTERM.
#
# USO: service_probe.sh RUN_ID rw|ro INTERVALLO_S TIMEOUT_S BASEDN BINDDN \
#                       FILE_PASSWORD FILE_LOG ETICHETTA
#
# VERSIONE:     1.0
# CHANGELOG:
#   1.0 - 2026-10-27 - prima versione.
# ==============================================================================

set -u

if [ "$#" -ne 9 ]; then
  echo "uso: $0 RUN_ID rw|ro INTERVALLO_S TIMEOUT_S BASEDN BINDDN FILE_PASSWORD FILE_LOG ETICHETTA" >&2
  exit 2
fi

RUN_ID="$1"
MODE="$2"
INTERVAL="$3"
OP_TIMEOUT="$4"
BASEDN="$5"
BINDDN="$6"
PWFILE="$7"
LOGFILE="$8"
LABEL="$9"
STOPFILE="$(dirname "$LOGFILE")/stop"
URI="ldaps://127.0.0.1:636"
export LDAPTLS_REQCERT=never

trap 'exit 0' TERM INT

now_ms() { date +%s%3N; }

SEQ=0
while [ ! -e "$STOPFILE" ]; do
  SEQ=$((SEQ + 1))

  T0=$(now_ms)
  timeout -k 1 "$OP_TIMEOUT" ldapsearch -x -LLL -o nettimeout="$OP_TIMEOUT" \
    -H "$URI" -D "$BINDDN" -y "$PWFILE" -b "$BASEDN" -s base 1.1 >/dev/null 2>&1
  RC=$?
  T1=$(now_ms)
  echo "R $SEQ $T0 $RC $((T1 - T0))" >> "$LOGFILE"

  if [ "$MODE" = "rw" ]; then
    CN="svcprobe.${RUN_ID}.${LABEL}.${SEQ}"
    DN="cn=${CN},ou=people,${BASEDN}"
    T0=$(now_ms)
    printf 'dn: %s\nobjectClass: organizationalRole\ncn: %s\n' "$DN" "$CN" \
      | timeout -k 1 "$OP_TIMEOUT" ldapadd -x -o nettimeout="$OP_TIMEOUT" \
          -H "$URI" -D "$BINDDN" -y "$PWFILE" >/dev/null 2>&1
    RC=$?
    T1=$(now_ms)
    echo "W $SEQ $T0 $RC $((T1 - T0)) $DN" >> "$LOGFILE"
  fi

  sleep "$INTERVAL"
done
exit 0

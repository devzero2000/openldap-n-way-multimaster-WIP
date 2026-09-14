#!/bin/sh
# ==============================================================================
# SCRIPT:       run_analyze_ldif_all.sh
# AUTORE:       Elia Pinto
# DATA:         Settembre 2026
# VERSIONE:     2.0
# SCOPO:        Trova ricorsivamente tutti i file *.ldif a partire dalla
#               directory corrente, esegue analyze_ldif.py --markdown su
#               ciascuno, e salva il risultato come analyze_<nomeldif>.md
#               (Markdown nativo - intestazioni e tabelle vere, non testo
#               avvolto in un blocco di codice) nella STESSA cartella del
#               file LDIF di origine. Nessun file intermedio (.txt o
#               altro): l'output va diretto in .md, pronto per essere
#               pubblicato (es. su GitHub).
#
# NOVITÀ v2.0 rispetto a v1.0: analyze_ldif.py ora supporta nativamente
# l'opzione --markdown (intestazioni "#"/"##" e tabelle Markdown vere,
# non testo con allineamento a colonne) - questo script non avvolge piu'
# l'output in un blocco di codice, scrive direttamente quello che il tool
# produce. Risultato piu' leggibile una volta pubblicato (tabelle
# renderizzate da GitHub, non testo preformattato).
#
# USO:
#   ./run_analyze_ldif_all.sh
#   (lanciato dalla cartella che contiene le sottocartelle con i file .ldif -
#   analyze_ldif.py va cercato in ../tools/ rispetto a QUESTO script, non
#   rispetto alla cartella da cui lo lanci - vedi TOOLS_DIR sotto se la tua
#   struttura e' diversa)
# ==============================================================================

set -eu

SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
TOOLS_DIR="$SCRIPT_DIR/../tools"
ANALYZE_PY="$TOOLS_DIR/analyze_ldif.py"

if [ ! -f "$ANALYZE_PY" ]; then
    printf -- "[ERRORE CRITICO] %s non trovato.\n" "$ANALYZE_PY" >&2
    printf -- "Atteso in ../tools/ rispetto alla posizione di questo script (%s).\n" "$SCRIPT_DIR" >&2
    exit 2
fi

# find + while read (delimitato da newline, non NUL): "read -d ''" per
# input delimitato da NUL e' un'estensione di bash, non disponibile nel
# vero /bin/sh POSIX (dash) - scoperto lanciando lo script per davvero,
# non solo scrivendolo a occhio. Sufficientemente robusto per nomi di
# file senza newline al loro interno (il caso comune, incluso questo).
find ../stress_test -name "*.ldif" | while IFS= read -r LDIF_FILE; do
    DIR=$(dirname -- "$LDIF_FILE")
    BASE=$(basename -- "$LDIF_FILE" .ldif)
    OUT_FILE="$DIR/analyze_${BASE}.md"

    printf -- "Analisi: %s -> %s\n" "$LDIF_FILE" "$OUT_FILE"

    python3 "$ANALYZE_PY" "$LDIF_FILE" --markdown > "$OUT_FILE"
done

printf -- "\nCompletato.\n"

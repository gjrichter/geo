#!/usr/bin/env bash
# fetch_all_years.sh — Processa tutti gli anni ISTAT da file ZIP locali
#
# Uso:
#   ./fetch_all_years.sh [directory_con_zip]
#
# Supporta due naming convention ISTAT:
#   Limiti0101{ANNO}_g.zip  (formato standard, es. Limiti01012024_g.zip)
#   Limiti{ANNO}_g.zip      (formato alternativo, es. Limiti2011_g.zip)
#
# Gli anni diversi dall'ultimo vengono processati in LITE mode
# (senza municipalities full + 100m GeoJSON, per contenere le dimensioni del repo).
# L'anno più recente aggiorna anche il flat boundaries/ e il symlink latest.
#
# Esempio:
#   mkdir -p italy/sources
#   # copia qui i file Limiti*_g.zip scaricati da ISTAT
#   bash italy/fetch_all_years.sh /Users/gjrichter/italy/sources/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCES_DIR="${1:-$SCRIPT_DIR/sources}"

if [[ ! -d "$SOURCES_DIR" ]]; then
  echo "Errore: directory non trovata: $SOURCES_DIR" >&2
  exit 1
fi

# ── raccogli zip e anni ───────────────────────────────────────────────────────
# Usa file temporaneo per sortare per anno (bash 3.2 compat, no array associativi)

TMPFILE="$(mktemp)"
trap 'rm -f "$TMPFILE"' EXIT

extract_year() {
  local fname="$1"
  local year
  if [[ "$fname" == Limiti0101????_g.zip ]]; then
    year="${fname#Limiti0101}"; year="${year%_g.zip}"
  elif [[ "$fname" == Limiti????_g.zip ]]; then
    year="${fname#Limiti}"; year="${year%_g.zip}"
  else
    return 1
  fi
  [[ "$year" =~ ^[0-9]{4}$ ]] && echo "$year" || return 1
}

for zip in "$SOURCES_DIR"/Limiti0101????_g.zip "$SOURCES_DIR"/Limiti????_g.zip; do
  [[ -f "$zip" ]] || continue
  fname="$(basename "$zip")"
  year="$(extract_year "$fname")" || continue
  echo "${year}|${zip}" >> "$TMPFILE"
done

if [[ ! -s "$TMPFILE" ]]; then
  echo "Nessun file Limiti*_g.zip trovato in $SOURCES_DIR" >&2
  echo "I file devono chiamarsi Limiti0101{ANNO}_g.zip o Limiti{ANNO}_g.zip" >&2
  exit 1
fi

sort -o "$TMPFILE" "$TMPFILE"

YEARS=()
ZIPS=()
while IFS='|' read -r year zip; do
  YEARS+=("$year")
  ZIPS+=("$zip")
done < "$TMPFILE"

# ── elabora ogni anno ─────────────────────────────────────────────────────────

n=$((${#YEARS[@]} - 1))
LATEST_YEAR="${YEARS[$n]}"

echo "Anni trovati: ${YEARS[*]}"
echo "Anno più recente (latest): $LATEST_YEAR"
echo ""

i=0
while [[ $i -lt ${#YEARS[@]} ]]; do
  year="${YEARS[$i]}"
  zip="${ZIPS[$i]}"
  i=$((i + 1))

  echo "════════════════════════════════════════"
  echo "  Anno: $year  ($zip)"
  echo "════════════════════════════════════════"

  if [[ "$year" -eq "$LATEST_YEAR" ]]; then
    LITE=false LATEST=true bash "$SCRIPT_DIR/update_boundaries.sh" "$year" "$zip"
  else
    LITE=true LATEST=false bash "$SCRIPT_DIR/update_boundaries.sh" "$year" "$zip"
  fi
  echo ""
done

echo "✓ Tutti gli anni processati."
echo "  Symlink: boundaries/latest → $LATEST_YEAR"

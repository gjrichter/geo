#!/usr/bin/env bash
# fetch_all_years.sh — Processa tutti gli anni ISTAT da file ZIP locali
#
# Uso:
#   ./fetch_all_years.sh [directory_con_zip]
#
# La directory deve contenere file nominati: Limiti01012{ANNO}_g.zip
# Default: ./sources/
#
# Gli anni diversi dall'ultimo vengono processati in LITE mode
# (senza municipalities full + 100m GeoJSON, per contenere le dimensioni del repo).
# L'anno più recente viene trattato come "latest" e aggiorna anche il flat boundaries/.
#
# Esempio:
#   mkdir -p italy/sources
#   # copia qui i file Limiti01012*.zip scaricati da ISTAT
#   bash italy/fetch_all_years.sh italy/sources/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCES_DIR="${1:-$SCRIPT_DIR/sources}"

if [[ ! -d "$SOURCES_DIR" ]]; then
  echo "Errore: directory non trovata: $SOURCES_DIR" >&2
  echo "Crea la directory e inserisci i file Limiti01012{ANNO}_g.zip" >&2
  exit 1
fi

# Raccoglie tutti gli anni disponibili
YEARS=()
for zip in "$SOURCES_DIR"/Limiti0101????_g.zip; do
  [[ -f "$zip" ]] || continue
  fname="$(basename "$zip")"
  year="${fname#Limiti0101}"
  year="${year%_g.zip}"
  if [[ "$year" =~ ^[0-9]{4}$ ]]; then
    YEARS+=("$year")
  fi
done

if [[ ${#YEARS[@]} -eq 0 ]]; then
  echo "Nessun file Limiti01012{ANNO}_g.zip trovato in $SOURCES_DIR" >&2
  exit 1
fi

# Ordina gli anni
IFS=$'\n' YEARS=($(printf '%s\n' "${YEARS[@]}" | sort)); unset IFS
LATEST_YEAR="${YEARS[${#YEARS[@]}-1]}"

echo "Anni trovati: ${YEARS[*]}"
echo "Anno più recente (latest): $LATEST_YEAR"
echo ""

for year in "${YEARS[@]}"; do
  zip="$SOURCES_DIR/Limiti01012${year}_g.zip"
  echo "════════════════════════════════════════"
  echo "  Anno: $year"
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

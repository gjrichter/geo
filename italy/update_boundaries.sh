#!/usr/bin/env bash
# update_boundaries.sh — Aggiorna i confini amministrativi ISTAT per l'Italia
#
# Uso:
#   ./update_boundaries.sh <anno> [percorso_o_url_zip_g]
#
# Esempi:
#   ./update_boundaries.sh 2026
#   ./update_boundaries.sh 2026 /path/to/Limiti01012026_g.zip
#   ./update_boundaries.sh 2026 https://github.com/gjrichter/geo/raw/main/Limiti01012026_g.zip
#
# Il file _g è la versione generalizzata (semplificata) di ISTAT, molto più
# compatta di quella dettagliata. Se non viene fornito un percorso/URL, lo
# script tenta di scaricarlo direttamente dal sito ISTAT.
#
# Output: italy/boundaries/italy_istat_*_4326{,_100m,_500m,_1km}.{geojson,topojson}
#
# Dipendenze: npx mapshaper, curl, unzip

set -euo pipefail

YEAR="${1:-}"
ZIP_SOURCE="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$SCRIPT_DIR/boundaries"
ISTAT_URL_TEMPLATE="https://www.istat.it/storage/cartografia/confini_amministrativi/generalizzati/{YEAR}/Limiti01012{YEAR}_g.zip"

# ── validazione ──────────────────────────────────────────────────────────────

if [[ -z "$YEAR" ]]; then
  echo "Uso: $0 <anno> [percorso_o_url_zip_g]"
  echo "Esempio: $0 2026"
  exit 1
fi

if ! [[ "$YEAR" =~ ^[0-9]{4}$ ]]; then
  echo "Errore: anno non valido '$YEAR'" >&2
  exit 1
fi

if ! command -v npx &>/dev/null; then
  echo "Errore: npx non trovato. Installare Node.js." >&2
  exit 1
fi

if ! npx mapshaper --version &>/dev/null; then
  echo "Errore: mapshaper non trovato. Eseguire: npm install -g mapshaper" >&2
  exit 1
fi

# ── download / copia ─────────────────────────────────────────────────────────

WORK_DIR="$(mktemp -d)"
ZIP_LOCAL="$WORK_DIR/Limiti01012${YEAR}_g.zip"
trap 'rm -rf "$WORK_DIR"' EXIT

if [[ -n "$ZIP_SOURCE" ]]; then
  if [[ "$ZIP_SOURCE" =~ ^https?:// ]]; then
    echo "→ Scarico da URL: $ZIP_SOURCE"
    curl -L --fail --show-error -o "$ZIP_LOCAL" "$ZIP_SOURCE"
  else
    echo "→ Uso file locale: $ZIP_SOURCE"
    cp "$ZIP_SOURCE" "$ZIP_LOCAL"
  fi
else
  ISTAT_URL="${ISTAT_URL_TEMPLATE//\{YEAR\}/$YEAR}"
  echo "→ Scarico da ISTAT: $ISTAT_URL"
  if ! curl -L --fail --show-error -o "$ZIP_LOCAL" "$ISTAT_URL"; then
    echo ""
    echo "Il sito ISTAT potrebbe bloccare i download automatici."
    echo "Scarica manualmente il file e richiama lo script con il percorso:"
    echo "  $0 $YEAR /path/to/Limiti01012${YEAR}_g.zip"
    exit 1
  fi
fi

echo "→ Estraggo in $WORK_DIR"
unzip -q "$ZIP_LOCAL" -d "$WORK_DIR/shp"

# ── helper: converti un layer ────────────────────────────────────────────────
# Argomenti: <file_shp> <base_output> <rename_fields> <filter_fields>

convert_layer() {
  local shp="$1"
  local base="$2"
  local rename="$3"
  local keep="$4"

  echo "  [full]  $base"
  npx mapshaper "$shp" encoding=utf-8 \
    -proj crs=EPSG:4326 \
    -rename-fields "$rename" \
    -filter-fields "$keep" \
    -o format=geojson "${base}.geojson" \
    -o format=topojson "${base}.topojson" 2>&1 | grep -E "^\[o\]|Error" || true

  for interval in 100 500 1000; do
    local suffix
    if [[ "$interval" -lt 1000 ]]; then
      suffix="${interval}m"
    else
      suffix="1km"
    fi
    echo "  [${suffix}]  ${base}_${suffix}"
    npx mapshaper "${base}.geojson" \
      -simplify interval=$interval keep-shapes \
      -o format=geojson "${base}_${suffix}.geojson" \
      -o format=topojson "${base}_${suffix}.topojson" 2>&1 | grep -E "^\[o\]|Error" || true
  done
}

# ── find shapefiles ───────────────────────────────────────────────────────────

find_shp() {
  local pattern="$1"
  find "$WORK_DIR/shp" -name "$pattern" | head -1
}

SHP_COM="$(find_shp "Com*_g_WGS84.shp")"
SHP_PROV="$(find_shp "ProvCM*_g_WGS84.shp")"
SHP_REG="$(find_shp "Reg*_g_WGS84.shp")"
SHP_RIP="$(find_shp "RipGeo*_g_WGS84.shp")"

for f in "$SHP_COM" "$SHP_PROV" "$SHP_REG" "$SHP_RIP"; do
  if [[ -z "$f" ]]; then
    echo "Errore: shapefile non trovato nello ZIP. Struttura inattesa?" >&2
    echo "Contenuto: $(ls "$WORK_DIR/shp")" >&2
    exit 1
  fi
done

mkdir -p "$OUT_DIR"

# ── comuni ────────────────────────────────────────────────────────────────────
echo "── Comuni ──────────────────────────────────────────────────"
convert_layer "$SHP_COM" \
  "$OUT_DIR/italy_istat_municipalities_4326" \
  "name=COMUNE,name_alt=COMUNE_A,com_istat_code=PRO_COM_T,com_istat_code_num=PRO_COM,reg_istat_code_num=COD_REG,prov_istat_code_num=COD_PROV,cm_istat_code_num=COD_CM,uts_istat_code_num=COD_UTS,rip_istat_code_num=COD_RIP,cc_uts=CC_UTS" \
  "name,name_alt,com_istat_code,com_istat_code_num,prov_istat_code_num,cm_istat_code_num,uts_istat_code_num,reg_istat_code_num,rip_istat_code_num,cc_uts"

# ── province / città metropolitane ───────────────────────────────────────────
echo "── Province / CM ───────────────────────────────────────────"
convert_layer "$SHP_PROV" \
  "$OUT_DIR/italy_istat_provinces_4326" \
  "name=DEN_UTS,prov_name=DEN_PROV,cm_name=DEN_CM,prov_acr=SIGLA,type=TIPO_UTS,uts_istat_code_num=COD_UTS,prov_istat_code_num=COD_PROV,cm_istat_code_num=COD_CM,reg_istat_code_num=COD_REG,rip_istat_code_num=COD_RIP" \
  "name,prov_name,cm_name,prov_acr,type,uts_istat_code_num,prov_istat_code_num,cm_istat_code_num,reg_istat_code_num,rip_istat_code_num"

# ── regioni ───────────────────────────────────────────────────────────────────
echo "── Regioni ─────────────────────────────────────────────────"
convert_layer "$SHP_REG" \
  "$OUT_DIR/italy_istat_regions_4326" \
  "name=DEN_REG,reg_istat_code_num=COD_REG,rip_istat_code_num=COD_RIP" \
  "name,reg_istat_code_num,rip_istat_code_num"

# ── ripartizioni geografiche ──────────────────────────────────────────────────
echo "── Ripartizioni ────────────────────────────────────────────"
convert_layer "$SHP_RIP" \
  "$OUT_DIR/italy_istat_macro_regions_4326" \
  "name=DEN_RIP,rip_istat_code_num=COD_RIP" \
  "name,rip_istat_code_num"

# ── riepilogo ─────────────────────────────────────────────────────────────────
echo ""
echo "✓ Aggiornamento completato — anno $YEAR"
echo "  File generati in: $OUT_DIR"
echo ""
echo "  Layer        | Features | File full"
echo "  -------------|----------|----------"
for base in municipalities provinces regions macro_regions; do
  f="$OUT_DIR/italy_istat_${base}_4326.geojson"
  features=$(python3 -c "import json; d=json.load(open('$f')); print(len(d['features']))" 2>/dev/null || echo "?")
  size=$(du -sh "$f" 2>/dev/null | cut -f1)
  printf "  %-12s | %8s | %s\n" "$base" "$features" "$size"
done

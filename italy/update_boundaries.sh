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
# Variabili d'ambiente:
#   LITE=true      Non genera municipalities full + 100m GeoJSON (per anni storici)
#   FORCE=true     Rigenera anche se l'anno esiste già
#   LATEST=true    Copia i file anche nel root boundaries/ (default: auto se anno più recente)
#
# Output:
#   italy/boundaries/{anno}/italy_istat_*_4326{,_100m,_500m,_1km}.{geojson,topojson}
#   italy/boundaries/italy_istat_*   (flat, solo se anno più recente o LATEST=true)
#   italy/boundaries/latest          (symlink → anno più recente)
#
# Dipendenze: npx mapshaper, curl, unzip

set -euo pipefail

YEAR="${1:-}"
ZIP_SOURCE="${2:-}"
LITE="${LITE:-false}"
FORCE="${FORCE:-false}"
LATEST="${LATEST:-auto}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOUNDARIES_DIR="$SCRIPT_DIR/boundaries"
OUT_DIR="$BOUNDARIES_DIR/$YEAR"
ISTAT_URL="https://www.istat.it/storage/cartografia/confini_amministrativi/generalizzati/${YEAR}/Limiti01012${YEAR}_g.zip"

# ── validazione ──────────────────────────────────────────────────────────────

if [[ -z "$YEAR" ]]; then
  echo "Uso: $0 <anno> [percorso_o_url_zip_g]"
  echo "Esempio: $0 2026"
  exit 1
fi

if ! [[ "$YEAR" =~ ^[0-9]{4}$ ]]; then
  echo "Errore: anno non valido '$YEAR'" >&2; exit 1
fi

if ! command -v npx &>/dev/null; then
  echo "Errore: npx non trovato. Installare Node.js." >&2; exit 1
fi

if ! npx mapshaper --version &>/dev/null 2>&1; then
  echo "Errore: mapshaper non trovato. Eseguire: npm install -g mapshaper" >&2; exit 1
fi

# ── skip se già processato ────────────────────────────────────────────────────

if [[ "$FORCE" != "true" ]] && [[ -f "$OUT_DIR/italy_istat_municipalities_4326.geojson" || \
    ( "$LITE" == "true" && -f "$OUT_DIR/italy_istat_municipalities_4326_500m.geojson" ) ]]; then
  echo "→ $YEAR già processato (usa FORCE=true per rigenerare)"
  exit 0
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

# ── campi per anno ────────────────────────────────────────────────────────────
# Pre-2015: niente Città Metropolitane (COD_CM, COD_UTS, CC_UTS, DEN_UTS, TIPO_UTS assenti)
# Pre-2017: PRO_COM_T assente (mapshaper ignora silenziosamente rinomina di campi mancanti)

get_com_rename() {
  echo "name=COMUNE,name_alt=COMUNE_A,com_istat_code=PRO_COM_T,com_istat_code_num=PRO_COM,reg_istat_code_num=COD_REG,prov_istat_code_num=COD_PROV,cm_istat_code_num=COD_CM,uts_istat_code_num=COD_UTS,rip_istat_code_num=COD_RIP,cc_uts=CC_UTS"
}

get_com_keep() {
  local base="area_km2,name,name_alt,com_istat_code,com_istat_code_num,prov_istat_code_num,reg_istat_code_num,rip_istat_code_num"
  if [[ "$YEAR" -ge 2015 ]]; then
    echo "${base},cm_istat_code_num,uts_istat_code_num,cc_uts"
  else
    echo "$base"
  fi
}

get_prov_rename() {
  if [[ "$YEAR" -ge 2015 ]]; then
    echo "name=DEN_UTS,prov_name=DEN_PROV,cm_name=DEN_CM,prov_acr=SIGLA,type=TIPO_UTS,uts_istat_code_num=COD_UTS,prov_istat_code_num=COD_PROV,cm_istat_code_num=COD_CM,reg_istat_code_num=COD_REG,rip_istat_code_num=COD_RIP"
  else
    echo "name=DEN_PROV,prov_acr=SIGLA,prov_istat_code_num=COD_PROV,reg_istat_code_num=COD_REG,rip_istat_code_num=COD_RIP"
  fi
}

get_prov_keep() {
  if [[ "$YEAR" -ge 2015 ]]; then
    echo "area_km2,name,prov_name,cm_name,prov_acr,type,uts_istat_code_num,prov_istat_code_num,cm_istat_code_num,reg_istat_code_num,rip_istat_code_num"
  else
    echo "area_km2,name,prov_name,prov_acr,prov_istat_code_num,reg_istat_code_num,rip_istat_code_num"
  fi
}

# ── trova shapefile ───────────────────────────────────────────────────────────

find_shp() {
  # cerca prima versione generalizzata (_g_WGS84), poi versione completa (_WGS84)
  local result
  result="$(find "$WORK_DIR/shp" -name "${1}_g_WGS84.shp" | head -1)"
  [[ -z "$result" ]] && result="$(find "$WORK_DIR/shp" -name "${1}_WGS84.shp" | head -1)"
  echo "$result"
}

SHP_COM="$(find_shp "Com*")"
SHP_PROV="$(find_shp "ProvCM*")"
[[ -z "$SHP_PROV" ]] && SHP_PROV="$(find_shp "Prov*")"   # pre-2016
SHP_REG="$(find_shp "Reg*")"
SHP_RIP="$(find_shp "RipGeo*")"

for f in "$SHP_COM" "$SHP_PROV" "$SHP_REG" "$SHP_RIP"; do
  if [[ -z "$f" ]]; then
    echo "Errore: shapefile non trovato nello ZIP. Struttura inattesa?" >&2
    ls "$WORK_DIR/shp" >&2
    exit 1
  fi
done

mkdir -p "$OUT_DIR"

# ── helper: converti un layer ─────────────────────────────────────────────────
# Argomenti: <shp> <base_output> <rename> <keep>

convert_layer() {
  local shp="$1" base="$2" rename="$3" keep="$4"
  local is_municipalities=false
  [[ "$base" == *municipalities* ]] && is_municipalities=true

  echo "  [full]  $(basename $base)"
  npx mapshaper "$shp" encoding=utf-8 \
    -proj crs=EPSG:4326 \
    -each "area_km2=Math.round(this.area/1e6*100)/100" \
    -rename-fields "$rename" \
    -filter-fields "$keep" \
    -o format=geojson "${base}.geojson" \
    -o format=topojson "${base}.topojson" 2>&1 | grep -E "^\[o\]|Error" || true

  # In LITE mode rimuovi full GeoJSON municipalities (>30MB, inutile per anni storici)
  if [[ "$LITE" == "true" ]] && [[ "$is_municipalities" == "true" ]]; then
    rm -f "${base}.geojson"
    echo "  [lite] rimosso ${base##*/}.geojson"
  fi

  for interval in 100 500 1000; do
    local suffix; [[ "$interval" -lt 1000 ]] && suffix="${interval}m" || suffix="1km"
    echo "  [${suffix}]  $(basename ${base}_${suffix})"
    # In LITE mode per municipalities usa il topojson come sorgente (il geojson è stato rimosso)
    local src="${base}.geojson"
    [[ ! -f "$src" ]] && src="${base}.topojson"
    npx mapshaper "$src" \
      -simplify interval=$interval keep-shapes \
      -each "area_km2=Math.round(this.area/1e6*100)/100" \
      -o format=geojson "${base}_${suffix}.geojson" \
      -o format=topojson "${base}_${suffix}.topojson" 2>&1 | grep -E "^\[o\]|Error" || true

    # In LITE mode rimuovi anche 100m GeoJSON municipalities
    if [[ "$LITE" == "true" ]] && [[ "$is_municipalities" == "true" ]] && [[ "$suffix" == "100m" ]]; then
      rm -f "${base}_${suffix}.geojson"
      echo "  [lite] rimosso ${base##*/}_${suffix}.geojson"
    fi
  done
}

# ── converti tutti i layer ────────────────────────────────────────────────────

echo "── Comuni ($YEAR) ──────────────────────────────────────────"
convert_layer "$SHP_COM" "$OUT_DIR/italy_istat_municipalities_4326" \
  "$(get_com_rename)" "$(get_com_keep)"

echo "── Province / CM ($YEAR) ───────────────────────────────────"
convert_layer "$SHP_PROV" "$OUT_DIR/italy_istat_provinces_4326" \
  "$(get_prov_rename)" "$(get_prov_keep)"

echo "── Regioni ($YEAR) ─────────────────────────────────────────"
convert_layer "$SHP_REG" "$OUT_DIR/italy_istat_regions_4326" \
  "name=DEN_REG,reg_istat_code_num=COD_REG,rip_istat_code_num=COD_RIP" \
  "area_km2,name,reg_istat_code_num,rip_istat_code_num"

echo "── Ripartizioni ($YEAR) ────────────────────────────────────"
convert_layer "$SHP_RIP" "$OUT_DIR/italy_istat_macro_regions_4326" \
  "name=DEN_RIP,rip_istat_code_num=COD_RIP" \
  "area_km2,name,rip_istat_code_num"

# ── aggiorna flat boundaries/ e symlink latest ───────────────────────────────

# Determina se questo anno è il più recente
CURRENT_LATEST=""
if [[ -L "$BOUNDARIES_DIR/latest" ]]; then
  CURRENT_LATEST="$(readlink "$BOUNDARIES_DIR/latest")"
fi

SHOULD_UPDATE_FLAT=false
if [[ "$LATEST" == "true" ]]; then
  SHOULD_UPDATE_FLAT=true
elif [[ "$LATEST" == "auto" ]] && [[ "$YEAR" -ge "${CURRENT_LATEST:-0}" ]]; then
  SHOULD_UPDATE_FLAT=true
fi

if [[ "$SHOULD_UPDATE_FLAT" == "true" ]]; then
  echo "→ Aggiorno flat boundaries/ → anno $YEAR"
  cp "$OUT_DIR"/italy_istat_*.geojson "$BOUNDARIES_DIR/" 2>/dev/null || true
  cp "$OUT_DIR"/italy_istat_*.topojson "$BOUNDARIES_DIR/" 2>/dev/null || true
  # Aggiorna symlink latest (rimuovi prima per evitare ln -sf su directory)
  rm -f "$BOUNDARIES_DIR/latest"
  ln -s "$YEAR" "$BOUNDARIES_DIR/latest"
  echo "→ Symlink: boundaries/latest → $YEAR"
fi

# ── riepilogo ─────────────────────────────────────────────────────────────────

echo ""
echo "✓ Anno $YEAR completato$([[ "$LITE" == "true" ]] && echo " (lite mode)" || true)"
echo "  Directory: $OUT_DIR"
echo "  File: $(ls "$OUT_DIR" | wc -l)"
echo ""
printf "  %-14s | %8s | %s\n" "Layer" "Features" "File full"
echo "  ---------------|----------|----------"
for layer in municipalities provinces regions macro_regions; do
  f="$OUT_DIR/italy_istat_${layer}_4326.geojson"
  if [[ -f "$f" ]]; then
    features=$(python3 -c "import json; d=json.load(open('$f')); print(len(d['features']))" 2>/dev/null || echo "?")
    size=$(du -sh "$f" | cut -f1)
  else
    features="(lite)"
    size="$(du -sh "$OUT_DIR/italy_istat_${layer}_4326.topojson" 2>/dev/null | cut -f1 || echo '?') topo"
  fi
  printf "  %-14s | %8s | %s\n" "$layer" "$features" "$size"
done

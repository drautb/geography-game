#!/usr/bin/env bash
# Shared pipeline for a regional country pack: filter Natural Earth 1:50m countries
# to a continent, project, and emit areas.geojson + points.geojson (capitals).
#
# Usage: make_region.sh <pack-dir> <region> <proj> [exclude_a3_csv] [clip_bbox] [field]
#   <pack-dir>   e.g. packs/south-america   (output written here)
#   <region>     value to match, e.g. "South America" or "Caribbean"
#   <proj>       mapshaper projection, e.g. robin, lcc, laea, etc.
#   exclude_a3   optional comma-separated ADM0_A3 codes to drop (territories)
#   clip_bbox    optional lon/lat bbox "W,S,E,N" to cut overseas territories
#   field        Natural Earth field to match <region> against (default CONTINENT;
#                use SUBREGION for e.g. "Caribbean")
#
# areas:  code=ADM0_A3, name=NAME, projected polygons
# points: code=country ADM0_A3, name=country NAME, capital=city, projected points
#         (national capitals only: FEATURECLA == "Admin-0 capital")
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"   # geography-game/
RAW="$ROOT/packs/_natural_earth/raw"

PACK_DIR="$1"
CONTINENT="$2"
PROJ="$3"
EXCLUDE="${4:-}"
CLIP_BBOX="${5:-}"   # optional lon/lat bbox "W,S,E,N" to cut overseas territories
FIELD="${6:-CONTINENT}"   # NE field to match <region> against (CONTINENT or SUBREGION)

cd "$ROOT/$PACK_DIR"

exclude_expr="true"
if [ -n "$EXCLUDE" ]; then
  # Build a JS array membership test from the CSV, e.g. !["x","y"].includes(ADM0_A3)
  arr=$(printf '"%s",' $(echo "$EXCLUDE" | tr ',' ' ') | sed 's/,$//')
  exclude_expr="![$arr].includes(ADM0_A3)"
fi

# Optional geographic clip (applied before projecting) to drop far-flung overseas
# parts of a country (e.g. French Guiana) that would blow out the map's bbox.
clip_cmd=""
pt_clip_cmd=""
if [ -n "$CLIP_BBOX" ]; then
  clip_cmd="-clip bbox=$CLIP_BBOX"
  pt_clip_cmd="-clip bbox=$CLIP_BBOX"
fi

# Areas: continent countries, minus excluded territories.
npx -y mapshaper@latest "$RAW/ne_50m_admin_0_countries.shp" \
  -filter "$FIELD=='$CONTINENT' && $exclude_expr" \
  $clip_cmd \
  -simplify visvalingam 10% keep-shapes \
  -proj "$PROJ" \
  -each 'code=ADM0_A3, name=NAME' \
  -filter-fields code,name \
  -o areas.geojson format=geojson precision=1

# Capitals: national capitals of those countries, projected the same way. We carry
# the country's ADM0_A3 as the join code; a tiny post-step keeps one per country.
npx -y mapshaper@latest "$RAW/ne_50m_populated_places.shp" \
  -filter "ADM0CAP==1 && FEATURECLA=='Admin-0 capital'" \
  $pt_clip_cmd \
  -proj "$PROJ" \
  -each 'code=ADM0_A3, name=ADM0NAME, capital=NAME' \
  -filter-fields code,name,capital \
  -o points_all.geojson format=geojson precision=1

echo "wrote $PACK_DIR/areas.geojson and points_all.geojson"

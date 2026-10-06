#!/usr/bin/env bash
# Build the world-continents areas GeoJSON from Natural Earth 1:110m countries.
#
# Pipeline:
#   1. Read the Natural Earth admin-0 countries shapefile (has a CONTINENT field)
#   2. Drop the "Seven seas (open ocean)" bucket (scattered islands, not a continent)
#   3. Dissolve countries into one polygon per continent
#   4. Simplify for a clean kids' map
#   5. Project with the Natural Earth projection (classic rounded world map)
#   6. Assign a short code + display name per continent, keep only code/name
#
# Output: packs/world-continents/areas.geojson (projected planar coords, Y-up)
set -euo pipefail

cd "$(dirname "$0")/.."

RAW="pipeline/raw/ne_110m_admin_0_countries.shp"
OUT="areas.geojson"

# CONTINENT -> short code lookup, applied in a mapshaper -each expression.
CODES='{"Africa":"AF","Antarctica":"AN","Asia":"AS","Europe":"EU","North America":"NA","Oceania":"OC","South America":"SA"}'

npx -y mapshaper@latest "$RAW" \
  -filter 'CONTINENT != "Seven seas (open ocean)"' \
  -dissolve CONTINENT \
  -simplify visvalingam 8% keep-shapes \
  -proj natearth \
  -each "name=CONTINENT, code=($CODES)[CONTINENT]" \
  -filter-fields code,name \
  -o "$OUT" format=geojson precision=1

echo "wrote $OUT"

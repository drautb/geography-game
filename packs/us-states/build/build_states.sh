#!/usr/bin/env bash
# Build the projected US states GeoJSON from the Census cartographic boundary shapefile.
#
# Pipeline:
#   1. Read the 1:20m Census state shapefile (build/raw/cb_2024_us_state_20m.shp)
#   2. Drop non-state territories (PR, GU, VI, AS, MP) — keep the 50 states + DC
#   3. Simplify geometry (Visvalingam, keep ~12% of vertices) for a clean kids' map
#   4. Project with the composite "albersusa" projection: Albers Equal-Area for the
#      lower 48, with Alaska scaled/inset and Hawaii repositioned (classic classroom layout)
#   5. Rename fields to a compact schema and export GeoJSON
#
# Output: areas.geojson (lat/lon replaced by projected planar coords in meters)
set -euo pipefail

cd "$(dirname "$0")/.."

RAW="build/raw/cb_2024_us_state_20m.shp"
OUT="areas.geojson"

# FIPS codes for the five territories we exclude (keep 50 states + DC = 51 features).
# 60=AS, 66=GU, 69=MP, 72=PR, 78=VI
TERRITORIES='"60","66","69","72","78"'

npx -y mapshaper@latest "$RAW" \
  -filter "![$TERRITORIES].includes(STATEFP)" \
  -simplify visvalingam 12% keep-shapes \
  -proj albersusa \
  -rename-fields code=STUSPS,name=NAME,fips=STATEFP \
  -filter-fields code,name,fips \
  -o "$OUT" format=geojson precision=1

# Enlarge DC and move it to an ocean callout (keeps it a clickable quiz target).
python3 "$(dirname "$0")/inset_dc.py"

# Tag each state with its Census region (for the region-focus checkboxes).
python3 "$(dirname "$0")/add_regions.py"

echo "wrote $OUT"

#!/usr/bin/env bash
# Project the state capitals (lat/lon CSV) through the SAME albersusa projection used
# for the state polygons, so capital pins align with the projected map.
#
# Input:  pipeline/raw/capitals.csv  (state_code,state_name,capital,lat,lon)
# Output: capitals.geojson  (points in projected planar meters)
set -euo pipefail

cd "$(dirname "$0")/.."

npx -y mapshaper@latest "pipeline/raw/capitals.csv" \
  -points x=lon y=lat \
  -proj albersusa \
  -rename-fields code=state_code,name=state_name \
  -filter-fields code,name,capital \
  -o "capitals.geojson" format=geojson precision=1

echo "wrote capitals.geojson"

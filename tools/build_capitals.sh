#!/usr/bin/env bash
# Project the state capitals (lat/lon CSV) through the SAME albersusa projection used
# for the state polygons, so capital pins align with the projected map.
#
# Input:  data/raw/capitals.csv  (state_code,state_name,capital,lat,lon)
# Output: data/capitals.geojson  (points in projected planar meters)
set -euo pipefail

cd "$(dirname "$0")/.."

npx -y mapshaper@latest "data/raw/capitals.csv" \
  -points x=lon y=lat \
  -proj albersusa \
  -rename-fields code=state_code,name=state_name \
  -filter-fields code,name,capital \
  -o "data/capitals.geojson" format=geojson precision=1

echo "wrote data/capitals.geojson"

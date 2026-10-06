#!/usr/bin/env python3
"""Finalize a regional pack's capitals: keep only capitals whose country code is in
the pack's areas, one per country, written as points.geojson.

Usage: finalize_points.py <pack-dir-abs>
Reads <pack>/areas.geojson and <pack>/points_all.geojson, writes <pack>/points.geojson
and removes points_all.geojson.
"""
import json
import sys
from pathlib import Path

pack = Path(sys.argv[1])
areas = json.loads((pack / "areas.geojson").read_text())
codes = {f["properties"]["code"] for f in areas["features"]}

allpts = json.loads((pack / "points_all.geojson").read_text())
seen = set()
kept = []
for f in allpts["features"]:
    c = f["properties"].get("code", "")
    if c in codes and c not in seen:
        seen.add(c)
        kept.append(f)

out = {"type": "FeatureCollection", "features": kept}
(pack / "points.geojson").write_text(json.dumps(out))
(pack / "points_all.geojson").unlink()

missing = sorted(codes - seen)
print("points.geojson: %d capitals for %d areas" % (len(kept), len(codes)))
if missing:
    print("  no capital matched for codes: %s" % ", ".join(missing), file=sys.stderr)

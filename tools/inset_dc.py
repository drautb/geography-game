#!/usr/bin/env python3
"""Post-process us_states.geojson to turn DC into a clickable callout.

DC is ~0.4% of the map width at true scale and position, far too small to click.
This scales DC's polygon up around its centroid and translates it into open ocean
off the mid-Atlantic coast (same albersusa coordinate space), and records the
original centroid so the game can draw a leader line from DC's true location to
the enlarged callout.

Run after tools/build_states.sh. Idempotent-ish: it keys off a marker property so
re-running does not compound the transform.
"""
import json
import sys
from pathlib import Path

GEOJSON = Path(__file__).resolve().parent.parent / "data/us_states.geojson"

SCALE = 8.0
# Target centroid for the callout: east of the coastline, near DC's latitude.
# Map bbox x maxes ~2.26M; land near DC ends ~1.75M, so this sits in open ocean.
TARGET_CX = 2080000.0
TARGET_CY = 230000.0


def main() -> int:
    data = json.loads(GEOJSON.read_text())
    dc = next((f for f in data["features"] if f["properties"].get("code") == "DC"), None)
    if dc is None:
        print("DC feature not found", file=sys.stderr)
        return 1
    if dc["properties"].get("inset"):
        print("DC already inset; skipping")
        return 0

    # Compute DC's true centroid from its polygon points.
    pts = []

    def walk(c):
        if isinstance(c[0], (int, float)):
            pts.append(c)
        else:
            for s in c:
                walk(s)

    walk(dc["geometry"]["coordinates"])
    cx = sum(p[0] for p in pts) / len(pts)
    cy = sum(p[1] for p in pts) / len(pts)

    # Scale around the true centroid, then translate so the scaled centroid lands
    # at the target ocean location.
    dx = TARGET_CX - cx
    dy = TARGET_CY - cy

    def transform(coords):
        if isinstance(coords[0], (int, float)):
            nx = (coords[0] - cx) * SCALE + cx + dx
            ny = (coords[1] - cy) * SCALE + cy + dy
            return [round(nx, 1), round(ny, 1)]
        return [transform(c) for c in coords]

    dc["geometry"]["coordinates"] = transform(dc["geometry"]["coordinates"])
    # Use a friendlier display name than the Census "District of Columbia".
    dc["properties"]["name"] = "Washington D.C."
    # Record provenance so the game can draw a leader line and we stay idempotent.
    dc["properties"]["inset"] = True
    dc["properties"]["origin"] = [round(cx, 1), round(cy, 1)]
    dc["properties"]["callout"] = [TARGET_CX, TARGET_CY]

    GEOJSON.write_text(json.dumps(data))
    print(
        "DC inset: scaled %gx, moved from (%.0f,%.0f) to (%.0f,%.0f)"
        % (SCALE, cx, cy, TARGET_CX, TARGET_CY)
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

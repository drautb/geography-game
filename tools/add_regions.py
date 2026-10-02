#!/usr/bin/env python3
"""Add a Census 'region' property to each state in us_states.geojson.

The four standard U.S. Census Bureau regions (Northeast, Midwest, South, West).
DC is placed in the South, consistent with Census practice. Run after
tools/build_states.sh (and inset_dc.py); idempotent.
"""
import json
import sys
from pathlib import Path

GEOJSON = Path(__file__).resolve().parent.parent / "data/us_states.geojson"

# Postal code -> Census region.
REGION = {
    # Northeast
    "CT": "Northeast", "ME": "Northeast", "MA": "Northeast", "NH": "Northeast",
    "RI": "Northeast", "VT": "Northeast", "NJ": "Northeast", "NY": "Northeast",
    "PA": "Northeast",
    # Midwest
    "IL": "Midwest", "IN": "Midwest", "MI": "Midwest", "OH": "Midwest",
    "WI": "Midwest", "IA": "Midwest", "KS": "Midwest", "MN": "Midwest",
    "MO": "Midwest", "NE": "Midwest", "ND": "Midwest", "SD": "Midwest",
    # South (DC included here, per Census)
    "DE": "South", "FL": "South", "GA": "South", "MD": "South", "NC": "South",
    "SC": "South", "VA": "South", "WV": "South", "DC": "South", "AL": "South",
    "KY": "South", "MS": "South", "TN": "South", "AR": "South", "LA": "South",
    "OK": "South", "TX": "South",
    # West
    "AZ": "West", "CO": "West", "ID": "West", "MT": "West", "NV": "West",
    "NM": "West", "UT": "West", "WY": "West", "AK": "West", "CA": "West",
    "HI": "West", "OR": "West", "WA": "West",
}


def main() -> int:
    data = json.loads(GEOJSON.read_text())
    missing = []
    for f in data["features"]:
        code = f["properties"].get("code", "")
        region = REGION.get(code)
        if region is None:
            missing.append(code)
            continue
        f["properties"]["region"] = region
    if missing:
        print("No region mapping for: %s" % ", ".join(missing), file=sys.stderr)
        return 1
    GEOJSON.write_text(json.dumps(data))
    print("Added region to %d states" % len(data["features"]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

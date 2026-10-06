# Map Pack Format

A **map pack** is a self-contained dataset the geography game plays over. The engine
(`scripts/`) is pack-agnostic: it loads a pack's `pack.json` manifest plus its GeoJSON
data and drives the whole game from that. Adding a new region of the world (continents,
countries, Africa, …) means authoring a new pack, not changing engine code.

A pack lives in `packs/<pack-id>/` and contains:

```
packs/us-states/
  pack.json        manifest (this document)
  areas.geojson    the clickable regions (states / countries / continents)
  points.geojson   optional capital/city points (omit for an areas-only pack)
  build.sh         the data pipeline that regenerates the GeoJSON (optional at runtime)
```

## Coordinate space

Both GeoJSON files hold **flat, pre-projected planar coordinates** (Y-up), already run
through whatever projection suits the pack (`albersusa` for the US, something else for a
world or regional pack). The engine never projects — it fits the bbox to the viewport with
a uniform scale and a Y-flip. **Projection is a per-pack build-time choice**, so a pack's
`build.sh` owns it and the engine stays generic.

`areas.geojson` features carry these properties:

| Property | Required | Description |
|----------|----------|-------------|
| `code`   | yes | Stable id, unique within the pack (e.g. `TX`, `FRA`, `AF`). Used for clicks, grouping, callouts. |
| `name`   | yes | Display name (`Texas`, `France`, `Africa`). |
| `group`  | no  | Group id this area belongs to (a Census region, a continent, …). Enables the group filter + coloring. Omit for an ungrouped pack. |
| `origin` + `callout` | no | For an *inset* area (like DC): `origin` is its true projected `[x,y]`, `callout` its relocated `[x,y]`. The engine draws a leader line between them. |

`points.geojson` features carry `code` (matching an area's `code`), `name`, and `capital`
(the city name), with a Point geometry in the same coordinate space.

## pack.json manifest

```json
{
  "schema": 1,
  "name": "United States",
  "areas": "areas.geojson",
  "points": "capitals.geojson",

  "area_noun": "State",
  "point_noun": "Capital",

  "left_inset": 175,

  "groups": [
    { "id": "Northeast", "name": "Northeast", "color": "#6b8cb8" },
    { "id": "Midwest",   "name": "Midwest",   "color": "#75a88f" },
    { "id": "South",     "name": "South",     "color": "#c29e70" },
    { "id": "West",      "name": "West",      "color": "#a880a8" }
  ],

  "callouts": {
    "VT": [975, 72],
    "NH": [1085, 55],
    "MA": [1168, 150],
    "RI": [1168, 192],
    "CT": [1168, 228],
    "NJ": [1168, 276],
    "DE": [1168, 312],
    "MD": [1120, 356]
  }
}
```

| Field | Required | Description |
|-------|----------|-------------|
| `schema` | yes | Manifest version (currently `1`). |
| `name` | yes | Pack display name, shown in the pack picker. |
| `areas` | yes | Filename of the areas GeoJSON, relative to the pack dir. |
| `points` | no | Filename of the points/capitals GeoJSON. Presence enables the capitals mode. |
| `area_noun` | no | Singular noun for an area (`State`, `Country`, `Continent`). Drives the prompt text `"<noun>: <name>"` and the mode toggle. Defaults to `Area`. |
| `point_noun` | no | Singular noun for a point (`Capital`). Defaults to `Capital`. |
| `left_inset` | no | Pixels reserved on the left for the control panel so the map clears it. Defaults to 0; the US pack uses the value tuned for its layout. |
| `groups` | no | Ordered list of groups. Each has an `id` (matches an area's `group`), a display `name`, and a `color` (hex `#rrggbb`). Drives the group-filter checkboxes, the color legend, and the per-area fill color. Omit for an ungrouped pack (areas use a single default fill, no group UI). |
| `callouts` | no | Map of area `code` → `[x, y]` label position (in the 1280×720 design space) for small/crowded areas that need a leader-line callout instead of an on-map label. Areas not listed get a centered on-map label. |

## Design notes

- **All logic is in the engine; all per-region tuning is in the pack.** Callout positions
  for tiny areas are irreducibly bespoke (as the US Northeast showed), so they live in the
  manifest as data, hand-tuned against the 1280×720 design space — never in engine code.
- **Modes are implied by data.** A pack with `points` supports both areas and capitals
  modes; a pack without it is areas-only (e.g. a continents pack).
- **Groups are optional and generic.** The US pack's "regions" are just groups; a world
  pack's groups would be continents. Same UI, same coloring, different data.

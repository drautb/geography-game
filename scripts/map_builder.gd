extends RefCounted
class_name MapBuilder
## Builds the interactive map node tree from a pack's projected areas GeoJSON.
##
## Pack-agnostic: colors, groups, and callout overrides all come from the loaded
## Pack (see docs/PACK_FORMAT.md), not from constants here. The GeoJSON holds flat
## pre-projected planar coordinates (Y-up); we fit the bbox to a target rectangle
## with a uniform scale and a Y-flip (Godot is Y-down), preserving aspect ratio.
##
## For each area we build:
##   Area2D (named by code, holds "code"/"name"/"group"/"label_pos" metadata)
##   ├── Polygon2D       (fill, one per geometry part)
##   ├── Line2D          (border outline, one per ring)
##   ├── CollisionPolygon2D (hit region, one per geometry part)
##   └── CollisionShape2D   (supplementary circular hit zone, tiny areas only)

const FILL_CORRECT := Color(0.36, 0.72, 0.42)
const FILL_WRONG := Color(0.82, 0.36, 0.33)
const FILL_HIGHLIGHT := Color(0.95, 0.78, 0.35)
const BORDER_COLOR := Color(0.12, 0.17, 0.24)
const BORDER_WIDTH := 1.5
const CAPITAL_COLOR := Color(0.98, 0.85, 0.4)
const CAPITAL_RING := Color(0.2, 0.16, 0.1)

## Group name applied to every area's fill polygons, so set_fill() can recolor a
## whole area (including multipolygon parts) by its code.
const FILL_GROUP_PREFIX := "fill_"

## Design width used to keep callout labels on screen.
const DESIGN_WIDTH := 1280.0

## Minimum clickable radius (screen px) for a tiny area. An area whose largest
## part is smaller than a disc of this radius gets a supplementary circular hit
## zone centered on its anchor, so sub-pixel islands/atolls stay clickable. The
## visible polygon is unchanged; this only enlarges the Area2D's hit region.
const MIN_HIT_RADIUS := 14.0


## Recolor every fill polygon belonging to `code` within `root`'s tree.
static func set_fill(root: Node, code: String, color: Color) -> void:
    root.get_tree().call_group(FILL_GROUP_PREFIX + code, "set_color", color)


## Reset every area under `map_root` to its group base color, dimming areas whose
## group is not enabled. `enabled_groups` is a {group: true} set; empty means all.
static func apply_group_colors(map_root: Node, pack, enabled_groups: Dictionary) -> void:
    for child in map_root.get_children():
        if not (child is Area2D) or not child.has_meta("base_color"):
            continue
        set_fill(map_root, String(child.name), area_base_fill(child, pack, enabled_groups))


## The base fill for one area's Area2D: its stored distinct color (ungrouped pack)
## or its group color, dimmed when that group is disabled.
static func area_base_fill(area: Area2D, pack, enabled_groups: Dictionary) -> Color:
    if not pack.has_groups():
        return area.get_meta("base_color")
    var group := String(area.get_meta("group"))
    var on: bool = enabled_groups.is_empty() or enabled_groups.get(group, false)
    return pack.group_color(group, on)


## Read the list of {code, name, group} for every feature in an areas GeoJSON.
static func load_area_list(geojson_path: String) -> Array:
    var out: Array = []
    var text := FileAccess.get_file_as_string(geojson_path)
    if text.is_empty():
        push_error("MapBuilder: could not read %s" % geojson_path)
        return out
    var data = JSON.parse_string(text)
    if data == null or not data.has("features"):
        return out
    for feature in data["features"]:
        var props: Dictionary = feature.get("properties", {})
        out.append(
            {
                "code": props.get("code", ""),
                "name": props.get("name", ""),
                "group": props.get("group", "")
            }
        )
    return out


## Read the points list as [{code, name, capital}] from a points GeoJSON.
static func load_point_list(geojson_path: String) -> Array:
    var out: Array = []
    var text := FileAccess.get_file_as_string(geojson_path)
    if text.is_empty():
        push_error("MapBuilder: could not read %s" % geojson_path)
        return out
    var data = JSON.parse_string(text)
    if data == null or not data.has("features"):
        return out
    for feature in data["features"]:
        var props: Dictionary = feature.get("properties", {})
        out.append(
            {
                "code": props.get("code", ""),
                "name": props.get("name", ""),
                "capital": props.get("capital", "")
            }
        )
    return out


## Draw a dot marker for each point under `parent`, using the SAME transform the
## areas were built with. Pins are plain Node2D visuals with no Area2D, so clicks
## pass through to the area beneath. Returns the pin container (toggleable).
static func build_points(parent: Node2D, geojson_path: String, t: Transform) -> Node2D:
    var container := Node2D.new()
    container.name = "PointPins"
    var text := FileAccess.get_file_as_string(geojson_path)
    if text.is_empty():
        push_error("MapBuilder: could not read %s" % geojson_path)
        parent.add_child(container)
        return container
    var data = JSON.parse_string(text)
    if data == null or not data.has("features"):
        parent.add_child(container)
        return container

    var pin_positions := {}
    for feature in data["features"]:
        var coords = feature.get("geometry", {}).get("coordinates", null)
        if coords == null:
            continue
        var pos := t.apply(coords[0], coords[1])
        var code := String(feature.get("properties", {}).get("code", ""))
        pin_positions[code] = pos
        container.add_child(_make_pin(pos))
    container.set_meta("pin_positions", pin_positions)
    parent.add_child(container)
    return container


## Build a persistent name label for every area, under a single toggleable
## container. Areas listed in the pack's callouts get a leader-line callout at the
## pack-specified position; everyone else gets a centered on-map label.
static func build_name_labels(parent: Node2D, area_root: Node, pack) -> Node2D:
    var container := Node2D.new()
    container.name = "AreaNameLabels"
    for child in area_root.get_children():
        if not (child is Area2D) or not child.has_meta("label_pos"):
            continue
        var code := String(child.get_meta("code"))
        var name_str := String(child.get_meta("name"))
        var anchor: Vector2 = child.get_meta("label_pos")
        if pack.callouts.has(code):
            _draw_callout(container, anchor, pack.callouts[code], name_str)
        else:
            container.add_child(_make_name_label(name_str, anchor))
    parent.add_child(container)
    return container


## Draw one leader-line callout: the full-name label CENTERED on label_pos (the
## callout point), and a thin line from the area anchor to the nearest point on
## the label's box. The callout point is authoritative — no clamping — so a
## position set in the label editor renders identically here (WYSIWYG).
static func _draw_callout(
    container: Node2D, anchor: Vector2, label_pos: Vector2, name_str: String
) -> void:
    var box_size := label_box_size(name_str)
    var top_left := label_pos - box_size * 0.5
    var label := _make_name_label(name_str, label_pos)
    var attach := _nearest_point_on_box(top_left, top_left + box_size, anchor)
    var line := Line2D.new()
    line.points = PackedVector2Array([anchor, attach])
    line.width = 1.0
    line.default_color = Color(0.7, 0.75, 0.82, 0.7)
    line.antialiased = true
    container.add_child(line)
    container.add_child(label)


## Shared label box estimate (font size 13). Used by both the game and the label
## editor so a callout point means the same thing in both.
static func label_box_size(text: String) -> Vector2:
    return Vector2(text.length() * 7.0, 18.0)


## Point on the axis-aligned box [tl, br] nearest to p (p clamped to the box edge).
static func _nearest_point_on_box(tl: Vector2, br: Vector2, p: Vector2) -> Vector2:
    return Vector2(clampf(p.x, tl.x, br.x), clampf(p.y, tl.y, br.y))


## A name label CENTERED on `center`, using the shared box estimate so its center
## is exactly `center` (matching the editor's chip center).
static func _make_name_label(text: String, center: Vector2) -> Label:
    var label := Label.new()
    label.text = text
    label.add_theme_font_size_override("font_size", 13)
    label.add_theme_color_override("font_color", Color(1, 1, 1))
    label.add_theme_color_override("font_outline_color", Color(0.1, 0.12, 0.16))
    label.add_theme_constant_override("outline_size", 5)
    label.position = center - label_box_size(text) * 0.5
    return label


## A small star/dot capital marker: a filled circle with a thin dark outline.
static func _make_pin(pos: Vector2) -> Node2D:
    var pin := Node2D.new()
    pin.position = pos
    var r := 3.5
    var pts := PackedVector2Array()
    for i in 12:
        var a := TAU * i / 12.0
        pts.append(Vector2(cos(a), sin(a)) * r)
    var fill := Polygon2D.new()
    fill.polygon = pts
    fill.color = CAPITAL_COLOR
    pin.add_child(fill)
    var ring := Line2D.new()
    var loop := pts.duplicate()
    loop.append(pts[0])
    ring.points = loop
    ring.width = 1.0
    ring.default_color = CAPITAL_RING
    ring.antialiased = true
    pin.add_child(ring)
    return pin


class Transform:
    var scale: float
    var offset: Vector2
    var size: Vector2

    func apply(x: float, y: float) -> Vector2:
        # Y-flip: GeoJSON is Y-up, Godot is Y-down.
        return Vector2(x * scale + offset.x, -y * scale + offset.y)


## Compute a uniform scale + offset that fits the GeoJSON bbox into target_size
## (with padding). `left_inset` reserves space on the left (for the control panel)
## so the map is centered in the region to the right of it.
static func _compute_transform(
    features: Array, target_size: Vector2, padding: float, left_inset: float
) -> Transform:
    var min_x := INF
    var min_y := INF
    var max_x := -INF
    var max_y := -INF
    for feature in features:
        var geom = feature.get("geometry")
        if geom == null:
            continue
        for pt in _iter_points(geom):
            min_x = minf(min_x, pt.x)
            min_y = minf(min_y, pt.y)
            max_x = maxf(max_x, pt.x)
            max_y = maxf(max_y, pt.y)

    var span_x := max_x - min_x
    var span_y := max_y - min_y
    if target_size.x < 1.0 or target_size.y < 1.0:
        target_size = Vector2(1280, 720)
    var region := Vector2(target_size.x - left_inset, target_size.y)
    var avail := region - Vector2(padding, padding) * 2.0
    var scale := minf(avail.x / span_x, avail.y / span_y)

    var t := Transform.new()
    t.scale = scale
    var drawn := Vector2(span_x, span_y) * scale
    var margin := (region - drawn) * 0.5
    t.offset = Vector2(left_inset + margin.x - min_x * scale, margin.y + max_y * scale)
    t.size = target_size
    return t


## Yield every [x,y] point in a geometry as a Vector2 (Polygon or MultiPolygon).
static func _iter_points(geom: Dictionary) -> Array:
    var out: Array = []
    for part in _iter_parts(geom):
        for ring in part:
            for p in ring:
                out.append(Vector2(p[0], p[1]))
    return out


## Normalize a geometry into a list of "parts", each part being a list of rings,
## each ring a list of [x,y]. Polygon -> one part; MultiPolygon -> many.
static func _iter_parts(geom: Dictionary) -> Array:
    if geom["type"] == "Polygon":
        return [geom["coordinates"]]
    elif geom["type"] == "MultiPolygon":
        return geom["coordinates"]
    return []


## Load the pack's areas GeoJSON and build all area nodes under `parent`.
## Returns the Transform used (so points can be placed in the same space).
static func build(parent: Node2D, pack, target_size: Vector2, padding := 40.0) -> Transform:
    var text := FileAccess.get_file_as_string(pack.areas_path)
    if text.is_empty():
        push_error("MapBuilder: could not read %s" % pack.areas_path)
        return null
    var data = JSON.parse_string(text)
    if data == null or not data.has("features"):
        push_error("MapBuilder: invalid GeoJSON at %s" % pack.areas_path)
        return null

    var features: Array = data["features"]
    var t := _compute_transform(features, target_size, padding, pack.left_inset)

    var index := 0
    for feature in features:
        var geom = feature.get("geometry")
        if geom == null:
            continue
        var props: Dictionary = feature.get("properties", {})
        # Draw a leader line from an inset area's true location to its callout,
        # under the area fill so the polygon sits on top of the line's end.
        if props.has("origin") and props.has("callout"):
            _build_leader(parent, props["origin"], props["callout"], t)
        _build_area(parent, geom, props, t, pack, index)
        index += 1
    return t


## Thin leader from an inset area's true location to its relocated callout.
static func _build_leader(parent: Node2D, origin: Array, callout: Array, t: Transform) -> void:
    var line := Line2D.new()
    line.points = PackedVector2Array(
        [t.apply(origin[0], origin[1]), t.apply(callout[0], callout[1])]
    )
    line.width = 1.0
    line.default_color = Color(0.55, 0.62, 0.72, 0.8)
    line.antialiased = true
    parent.add_child(line)
    var dot := Line2D.new()
    var o := t.apply(origin[0], origin[1])
    dot.points = PackedVector2Array([o + Vector2(-2, 0), o + Vector2(2, 0)])
    dot.width = 4.0
    dot.default_color = Color(0.85, 0.78, 0.45)
    parent.add_child(dot)


static func _build_area(
    parent: Node2D, geom: Dictionary, props: Dictionary, t: Transform, pack, index: int
) -> void:
    var code := String(props.get("code", "??"))
    var group := String(props.get("group", ""))
    var area := Area2D.new()
    area.name = code
    area.set_meta("code", code)
    area.set_meta("name", props.get("name", ""))
    area.set_meta("group", group)
    area.input_pickable = true
    area.input_event.connect(_on_area_input.bind(code))

    # Grouped packs color by group; ungrouped packs give each area a distinct color.
    var base_color: Color = (
        pack.group_color(group, true) if pack.has_groups() else pack.distinct_color(index)
    )
    area.set_meta("base_color", base_color)
    var best_anchor := Vector2.ZERO
    var best_area := -1.0

    for part in _iter_parts(geom):
        for ring_index in part.size():
            var ring: Array = part[ring_index]
            var points := PackedVector2Array()
            for p in ring:
                points.append(t.apply(p[0], p[1]))
            if points.size() > 1 and points[0] == points[points.size() - 1]:
                points.remove_at(points.size() - 1)

            if ring_index == 0:
                var fill := Polygon2D.new()
                fill.polygon = points
                fill.color = base_color
                fill.add_to_group(FILL_GROUP_PREFIX + code)
                area.add_child(fill)

                var col := CollisionPolygon2D.new()
                col.polygon = points
                area.add_child(col)

                var a := _ring_area(points)
                if a > best_area:
                    best_area = a
                    best_anchor = _ring_centroid(points)

            var line := Line2D.new()
            var loop := points.duplicate()
            if loop.size() > 0:
                loop.append(loop[0])
            line.points = loop
            line.width = BORDER_WIDTH
            line.default_color = BORDER_COLOR
            line.antialiased = true
            area.add_child(line)

    area.set_meta("label_pos", best_anchor)

    # Tiny areas (atolls, micro-states) can shrink to a sub-pixel polygon that is
    # effectively unclickable. If the largest part is smaller than a disc of
    # MIN_HIT_RADIUS, add a circular hit zone of that radius on the anchor. Give
    # smaller areas a higher pick priority so an enlarged circle that overlaps a
    # big neighbor still resolves to the small area the player is aiming at.
    if best_area >= 0.0:
        var min_disc := PI * MIN_HIT_RADIUS * MIN_HIT_RADIUS
        if best_area < min_disc:
            var circle := CircleShape2D.new()
            circle.radius = MIN_HIT_RADIUS
            var hit := CollisionShape2D.new()
            hit.shape = circle
            hit.position = best_anchor
            area.add_child(hit)
            area.priority = int(clampf(min_disc - best_area, 1.0, 1000.0))

    parent.add_child(area)


## Shoelace area (absolute) of a screen-space ring, for picking the largest part.
static func _ring_area(pts: PackedVector2Array) -> float:
    var a := 0.0
    var n := pts.size()
    for i in n:
        var p := pts[i]
        var q := pts[(i + 1) % n]
        a += p.x * q.y - q.x * p.y
    return absf(a) * 0.5


## Area-weighted centroid of a screen-space ring (falls back to vertex mean).
static func _ring_centroid(pts: PackedVector2Array) -> Vector2:
    var n := pts.size()
    var cx := 0.0
    var cy := 0.0
    var a := 0.0
    for i in n:
        var p := pts[i]
        var q := pts[(i + 1) % n]
        var cross := p.x * q.y - q.x * p.y
        cx += (p.x + q.x) * cross
        cy += (p.y + q.y) * cross
        a += cross
    if absf(a) < 0.0001:
        var mean := Vector2.ZERO
        for p in pts:
            mean += p
        return mean / maxf(1.0, n)
    a *= 0.5
    return Vector2(cx / (6.0 * a), cy / (6.0 * a))


## Emit EventBus.area_clicked on a left-click release within an area.
static func _on_area_input(
    _viewport: Node, event: InputEvent, _shape_idx: int, code: String
) -> void:
    if event is InputEventMouseButton:
        var mb := event as InputEventMouseButton
        if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
            EventBus.area_clicked.emit(code)

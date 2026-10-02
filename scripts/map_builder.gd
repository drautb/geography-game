extends RefCounted
class_name MapBuilder
## Builds the interactive US map node tree from a projected GeoJSON file.
##
## The GeoJSON (data/build/us_states.geojson) holds albersusa-projected planar
## coordinates in meters, Y-up. We fit them to a target pixel rectangle with a
## uniform scale and a Y-flip (Godot is Y-down), preserving aspect ratio.
##
## For each state we build:
##   Area2D (named by postal code, holds "state_code"/"state_name" metadata)
##   ├── Polygon2D       (fill, one per geometry part)
##   ├── Line2D          (border outline, one per ring)
##   └── CollisionPolygon2D (hit region, one per geometry part)

const FILL_COLOR := Color(0.42, 0.55, 0.68)
const FILL_CORRECT := Color(0.36, 0.72, 0.42)
const FILL_WRONG := Color(0.82, 0.36, 0.33)
const FILL_HIGHLIGHT := Color(0.95, 0.78, 0.35)
const BORDER_COLOR := Color(0.12, 0.17, 0.24)
const BORDER_WIDTH := 1.5

## Group name applied to every state's fill polygons, so set_fill() can recolor a
## whole state (including multipolygon parts) by its postal code.
const FILL_GROUP_PREFIX := "fill_"


## Recolor every fill polygon belonging to `state_code` within `root`'s tree.
static func set_fill(root: Node, state_code: String, color: Color) -> void:
    root.get_tree().call_group(FILL_GROUP_PREFIX + state_code, "set_color", color)


## Read the list of {code, name} for every feature in a GeoJSON file.
static func load_state_list(geojson_path: String) -> Array:
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
        out.append({"code": props.get("code", ""), "name": props.get("name", "")})
    return out


class Transform:
    var scale: float
    var offset: Vector2
    var size: Vector2

    func apply(x: float, y: float) -> Vector2:
        # Y-flip: GeoJSON is Y-up, Godot is Y-down.
        return Vector2(x * scale + offset.x, -y * scale + offset.y)


## Compute a uniform scale + offset that fits the GeoJSON bbox into target_size
## (with padding), centered.
static func _compute_transform(features: Array, target_size: Vector2, padding: float) -> Transform:
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
    # Guard against a degenerate target (e.g. a web canvas reporting size 0 before
    # layout). Fall back to a sane default so geometry is never drawn off-screen.
    if target_size.x < 1.0 or target_size.y < 1.0:
        target_size = Vector2(1280, 720)
    var avail := target_size - Vector2(padding, padding) * 2.0
    var scale := minf(avail.x / span_x, avail.y / span_y)

    var t := Transform.new()
    t.scale = scale
    # Center the scaled map within target_size. Y uses the flipped convention:
    # geo max_y maps to the top (smallest screen Y).
    var drawn := Vector2(span_x, span_y) * scale
    var margin := (target_size - drawn) * 0.5
    t.offset = Vector2(margin.x - min_x * scale, margin.y + max_y * scale)
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


## Load the GeoJSON and build all state nodes under `parent`.
## Returns the Transform used (so capitals can be placed in the same space).
static func build(
    parent: Node2D, geojson_path: String, target_size: Vector2, padding := 40.0
) -> Transform:
    var text := FileAccess.get_file_as_string(geojson_path)
    if text.is_empty():
        push_error("MapBuilder: could not read %s" % geojson_path)
        return null
    var data = JSON.parse_string(text)
    if data == null or not data.has("features"):
        push_error("MapBuilder: invalid GeoJSON at %s" % geojson_path)
        return null

    var features: Array = data["features"]
    var t := _compute_transform(features, target_size, padding)

    for feature in features:
        var geom = feature.get("geometry")
        if geom == null:
            continue
        var props: Dictionary = feature.get("properties", {})
        # Draw a leader line from an inset state's true location to its callout,
        # under the state fill so the polygon sits on top of the line's end.
        if props.has("origin") and props.has("callout"):
            _build_leader(parent, props["origin"], props["callout"], t)
        _build_state(parent, geom, props, t)
    return t


## Thin dashed-looking leader from an inset state's true location to its callout.
static func _build_leader(parent: Node2D, origin: Array, callout: Array, t: Transform) -> void:
    var line := Line2D.new()
    line.points = PackedVector2Array(
        [t.apply(origin[0], origin[1]), t.apply(callout[0], callout[1])]
    )
    line.width = 1.0
    line.default_color = Color(0.55, 0.62, 0.72, 0.8)
    line.antialiased = true
    parent.add_child(line)
    # A small dot at the true location so the origin reads clearly.
    var dot := Line2D.new()
    var o := t.apply(origin[0], origin[1])
    dot.points = PackedVector2Array([o + Vector2(-2, 0), o + Vector2(2, 0)])
    dot.width = 4.0
    dot.default_color = Color(0.85, 0.78, 0.45)
    parent.add_child(dot)


static func _build_state(parent: Node2D, geom: Dictionary, props: Dictionary, t: Transform) -> void:
    var code := String(props.get("code", "??"))
    var area := Area2D.new()
    area.name = code
    area.set_meta("state_code", code)
    area.set_meta("state_name", props.get("name", ""))
    area.input_pickable = true
    area.input_event.connect(_on_area_input.bind(code))

    for part in _iter_parts(geom):
        # part = list of rings; ring 0 is the outer boundary, rest are holes.
        for ring_index in part.size():
            var ring: Array = part[ring_index]
            var points := PackedVector2Array()
            for p in ring:
                points.append(t.apply(p[0], p[1]))
            # GeoJSON rings repeat the first point as the last; drop it for Godot polys.
            if points.size() > 1 and points[0] == points[points.size() - 1]:
                points.remove_at(points.size() - 1)

            # Fill + collision only for the outer ring of each part (holes left simple
            # for a kids' map; the 1:20m data has no meaningful interior holes).
            if ring_index == 0:
                var fill := Polygon2D.new()
                fill.polygon = points
                fill.color = FILL_COLOR
                fill.add_to_group(FILL_GROUP_PREFIX + code)
                area.add_child(fill)

                var col := CollisionPolygon2D.new()
                col.polygon = points
                area.add_child(col)

            # Border outline for every ring (closed loop).
            var line := Line2D.new()
            var loop := points.duplicate()
            if loop.size() > 0:
                loop.append(loop[0])
            line.points = loop
            line.width = BORDER_WIDTH
            line.default_color = BORDER_COLOR
            line.antialiased = true
            area.add_child(line)

    parent.add_child(area)


## Emit EventBus.state_clicked on a left-click release within a state's area.
static func _on_area_input(
    _viewport: Node, event: InputEvent, _shape_idx: int, code: String
) -> void:
    if event is InputEventMouseButton:
        var mb := event as InputEventMouseButton
        if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
            EventBus.state_clicked.emit(code)

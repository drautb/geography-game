extends CanvasLayer
## Start screen: a clickable world map. Hovering a continent highlights it and
## shows its name; clicking either launches that continent's pack directly or, for
## a continent with sub-regions (North America), zooms into a sub-map with generous
## circular hit zones. A plain button offers the whole-world "Continents" quiz.
## Emits pack_chosen(id).

signal pack_chosen(pack_id: String)

const PackScript := preload("res://scripts/pack.gd")
const MapBuilderScript := preload("res://scripts/map_builder.gd")
const DESIGN_SIZE := Vector2(1280, 720)

## Which world-continents area code maps to which pack(s). A single id launches
## directly; a dict with a "zoom" entry opens a zoomed-in sub-map with generous
## clickable hit zones. Continents absent here (Antarctica) are shown but inert.
const CONTINENT_PACKS := {
    "AF": "africa",
    "AS": "asia",
    "EU": "europe",
    "SA": "south-america",
    "OC": "oceania",
    "NA":
    {
        "zoom": "north-america",  # pack whose map is the zoom-in backdrop
        # Hit zones anchored to the backdrop's own areas (by code) so they track
        # the map wherever it renders, with a pixel offset + generous radius.
        # "Caribbean" has no drawn area here, so it uses an absolute center in the
        # ocean east of Central America where the islands actually are.
        "zones":
        [
            {"name": "United States", "id": "us-states", "anchor": "USA", "radius": 78},
            {
                "name": "North America",
                "id": "north-america",
                "anchor": "CAN",
                "offset": [0, -20],
                "radius": 82
            },
            {"name": "Caribbean", "id": "caribbean", "center": [965, 470], "radius": 86},
        ],
    },
}

const HOVER_COLOR := Color(0.95, 0.78, 0.35)
const INERT_COLOR := Color(0.17, 0.2, 0.25)

var _map_root: Node2D
var _base_color := {}  # code -> its resting fill
var _name_by_code := {}
var _hover_label: Label
var _drill: Control


func _ready() -> void:
    var bg := ColorRect.new()
    bg.color = Color(0.1, 0.12, 0.15)
    bg.set_anchors_preset(Control.PRESET_FULL_RECT)
    bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(bg)

    var title := Label.new()
    title.text = "Geography Game"
    title.add_theme_font_size_override("font_size", 36)
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.set_anchors_preset(Control.PRESET_TOP_WIDE)
    title.offset_top = 10
    title.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(title)

    var subtitle := Label.new()
    subtitle.text = "Click a region on the map"
    subtitle.add_theme_font_size_override("font_size", 18)
    subtitle.add_theme_color_override("font_color", Color(0.72, 0.78, 0.86))
    subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    subtitle.set_anchors_preset(Control.PRESET_TOP_WIDE)
    subtitle.offset_top = 56
    subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(subtitle)

    _build_map()

    # Floating label that follows the hovered continent's name.
    _hover_label = Label.new()
    _hover_label.add_theme_font_size_override("font_size", 24)
    _hover_label.add_theme_color_override("font_color", HOVER_COLOR)
    _hover_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _hover_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
    _hover_label.offset_top = 86
    _hover_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _hover_label.visible = false
    add_child(_hover_label)

    # A plain button for the whole-world continents quiz (it IS the map, so it
    # can't be a region on it).
    var continents := Button.new()
    continents.text = "World — Continents quiz"
    continents.add_theme_font_size_override("font_size", 18)
    continents.custom_minimum_size = Vector2(260, 44)
    continents.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
    continents.offset_left = -130
    continents.offset_top = -58
    continents.pressed.connect(func(): pack_chosen.emit("world-continents"))
    add_child(continents)


func _build_map() -> void:
    var pack = PackScript.load_pack("world-continents")
    if pack == null:
        push_error("pack_picker: world-continents pack missing")
        return
    _map_root = Node2D.new()
    add_child(_map_root)
    # Reserve a header band (title/subtitle/hover name) and a footer band (quiz
    # button) by building the map into a shorter rectangle and shifting it down.
    var top_band := 118.0
    var bottom_band := 76.0
    var map_h := DESIGN_SIZE.y - top_band - bottom_band
    MapBuilderScript.build(_map_root, pack, Vector2(DESIGN_SIZE.x, map_h), 24.0)
    _map_root.position.y = top_band

    var sel_index := 0
    for area in _map_root.get_children():
        if not (area is Area2D):
            continue
        var code := String(area.name)
        var selectable: bool = CONTINENT_PACKS.has(code)
        var fill: Color = INERT_COLOR
        if selectable:
            fill = pack.distinct_color(sel_index)
            sel_index += 1
        _base_color[code] = fill
        MapBuilderScript.set_fill(_map_root, code, fill)
        _name_by_code[code] = area.get_meta("name", code)
        if selectable:
            area.mouse_entered.connect(_on_hover.bind(code, true))
            area.mouse_exited.connect(_on_hover.bind(code, false))
            area.input_event.connect(_on_area_input.bind(code))
        else:
            area.input_pickable = false


func _on_hover(code: String, entered: bool) -> void:
    if _drill != null:
        return
    MapBuilderScript.set_fill(_map_root, code, HOVER_COLOR if entered else _base_color[code])
    if entered:
        _hover_label.text = String(_name_by_code.get(code, code))
        _hover_label.visible = true
    else:
        _hover_label.visible = false


func _on_area_input(_vp: Node, event: InputEvent, _idx: int, code: String) -> void:
    if _drill != null:
        return
    if event is InputEventMouseButton:
        var mb := event as InputEventMouseButton
        if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
            _choose(code)


## Launch directly for a single-pack continent, or open a zoomed sub-map for a
## continent that maps to several packs.
func _choose(code: String) -> void:
    var target = CONTINENT_PACKS[code]
    if target is String:
        pack_chosen.emit(target)
    elif target is Dictionary and target.has("zoom"):
        _open_zoom(String(_name_by_code.get(code, code)), target)


## Zoom into a continent: show its backdrop map full-bleed with generous circular
## hit zones for each sub-pack. Hovering a zone highlights it and shows its name;
## clicking launches that pack. The awkward targets (US over the continent, the
## offshore Caribbean) get big discs so they are easy to hit.
func _open_zoom(continent_name: String, spec: Dictionary) -> void:
    _hover_label.visible = false
    var veil := Control.new()
    veil.set_anchors_preset(Control.PRESET_FULL_RECT)
    # A full-rect Control defaults to MOUSE_FILTER_STOP, which would sit in front
    # of the Area2D hit zones and swallow every click before picking reaches them.
    # Make it transparent to the mouse so clicks fall through to the zones; the
    # Back button is a child Control with its own filter, so it still works.
    veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(veil)
    _drill = veil

    var bg := ColorRect.new()
    bg.color = Color(0.1, 0.12, 0.15)
    bg.set_anchors_preset(Control.PRESET_FULL_RECT)
    bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
    veil.add_child(bg)

    var top_band := 118.0
    var bottom_band := 76.0

    # Backdrop: the continent's own pack map, dimmed so the hit discs read on top.
    var zoom_root := Node2D.new()
    veil.add_child(zoom_root)
    var anchor_pos := {}  # area code -> screen-space center of that area
    var pack = PackScript.load_pack(String(spec["zoom"]))
    if pack != null:
        var map_h := DESIGN_SIZE.y - top_band - bottom_band
        MapBuilderScript.build(zoom_root, pack, Vector2(DESIGN_SIZE.x, map_h), 24.0)
        zoom_root.position.y = top_band
        var i := 0
        for a in zoom_root.get_children():
            if a is Area2D:
                a.input_pickable = false  # the discs own the clicks, not the map
                MapBuilderScript.set_fill(zoom_root, String(a.name), pack.distinct_color(i))
                i += 1
                var lp: Vector2 = a.get_meta("label_pos")
                anchor_pos[String(a.name)] = lp + zoom_root.position

    var heading := Label.new()
    heading.text = continent_name
    heading.add_theme_font_size_override("font_size", 28)
    heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    heading.set_anchors_preset(Control.PRESET_TOP_WIDE)
    heading.offset_top = 16
    heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
    veil.add_child(heading)

    var hint := Label.new()
    hint.text = "Click a region — or Back"
    hint.add_theme_font_size_override("font_size", 16)
    hint.add_theme_color_override("font_color", Color(0.72, 0.78, 0.86))
    hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    hint.set_anchors_preset(Control.PRESET_TOP_WIDE)
    hint.offset_top = 56
    hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
    veil.add_child(hint)

    # Generous circular hit zones. Each is an Area2D (circle) carrying a visible
    # translucent disc and a label; hover brightens the disc. A zone's center
    # comes from its anchor area on the backdrop (so it tracks the map) plus an
    # optional offset, or from an absolute center when it anchors to no area.
    var zone_layer := Node2D.new()
    veil.add_child(zone_layer)
    for z in spec["zones"]:
        var c: Vector2
        if z.has("anchor") and anchor_pos.has(String(z["anchor"])):
            c = anchor_pos[String(z["anchor"])]
        else:
            var ctr: Array = z["center"]
            c = Vector2(float(ctr[0]), float(ctr[1]))
        if z.has("offset"):
            var off: Array = z["offset"]
            c += Vector2(float(off[0]), float(off[1]))
        _add_zone(zone_layer, String(z["name"]), String(z["id"]), c, float(z["radius"]))

    var back := Button.new()
    back.text = "Back"
    back.add_theme_font_size_override("font_size", 18)
    back.custom_minimum_size = Vector2(160, 44)
    back.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
    back.offset_left = -80
    back.offset_top = -58
    back.pressed.connect(_close_drill)
    veil.add_child(back)


## One generous circular hit zone: a translucent disc (Polygon2D), a centered
## label, and an Area2D+CircleShape2D for clicks. Hover brightens the disc.
func _add_zone(parent: Node2D, zone_name: String, id: String, c: Vector2, radius: float) -> void:
    var disc := Polygon2D.new()
    var ring := PackedVector2Array()
    for k in 32:
        var ang := TAU * float(k) / 32.0
        ring.append(c + Vector2(cos(ang), sin(ang)) * radius)
    disc.polygon = ring
    var rest := Color(0.95, 0.78, 0.35, 0.22)
    var hot := Color(0.95, 0.78, 0.35, 0.5)
    disc.color = rest
    parent.add_child(disc)

    var label := Label.new()
    label.text = zone_name
    label.add_theme_font_size_override("font_size", 20)
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.size = Vector2(radius * 2.0, 26)
    label.position = c - Vector2(radius, 13)
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    parent.add_child(label)

    var area := Area2D.new()
    area.position = c
    var shape := CollisionShape2D.new()
    var circle := CircleShape2D.new()
    circle.radius = radius
    shape.shape = circle
    area.add_child(shape)
    area.mouse_entered.connect(func(): disc.color = hot)
    area.mouse_exited.connect(func(): disc.color = rest)
    area.input_event.connect(
        func(_vp: Node, e: InputEvent, _i: int):
            if e is InputEventMouseButton:
                var mb := e as InputEventMouseButton
                if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
                    pack_chosen.emit(id)
    )
    parent.add_child(area)


func _close_drill() -> void:
    if _drill != null:
        _drill.queue_free()
        _drill = null

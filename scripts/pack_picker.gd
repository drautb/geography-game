extends CanvasLayer
## Start screen: a clickable world map. Hovering a continent highlights it and
## shows its name; clicking either launches that continent's pack directly or, for
## a continent with sub-regions (North America), opens a small drill-down menu.
## A plain button offers the whole-world "Continents" quiz. Emits pack_chosen(id).

signal pack_chosen(pack_id: String)

const PackScript := preload("res://scripts/pack.gd")
const MapBuilderScript := preload("res://scripts/map_builder.gd")
const DESIGN_SIZE := Vector2(1280, 720)

## Which world-continents area code maps to which pack(s). A single id launches
## directly; a list opens a drill-down menu (label/id pairs). Continents absent
## here (Antarctica) are shown but inert.
const CONTINENT_PACKS := {
    "AF": "africa",
    "AS": "asia",
    "EU": "europe",
    "SA": "south-america",
    "OC": "oceania",
    "NA":
    [
        {"name": "North America", "id": "north-america"},
        {"name": "United States", "id": "us-states"},
        {"name": "Caribbean", "id": "caribbean"},
    ],
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


## Launch directly for a single-pack continent, or open a drill-down menu for a
## continent that maps to several packs.
func _choose(code: String) -> void:
    var target = CONTINENT_PACKS[code]
    if target is String:
        pack_chosen.emit(target)
    elif target is Array:
        _open_drill(String(_name_by_code.get(code, code)), target)


func _open_drill(continent_name: String, options: Array) -> void:
    _hover_label.visible = false
    var veil := ColorRect.new()
    veil.color = Color(0.0, 0.0, 0.0, 0.55)
    veil.set_anchors_preset(Control.PRESET_FULL_RECT)
    # Clicking the dark veil (outside the menu) cancels the drill-down.
    veil.gui_input.connect(
        func(e: InputEvent):
            if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
                _close_drill()
    )
    add_child(veil)
    _drill = veil

    var center := CenterContainer.new()
    center.set_anchors_preset(Control.PRESET_FULL_RECT)
    center.mouse_filter = Control.MOUSE_FILTER_IGNORE
    veil.add_child(center)

    var col := VBoxContainer.new()
    col.add_theme_constant_override("separation", 12)
    center.add_child(col)

    var heading := Label.new()
    heading.text = continent_name
    heading.add_theme_font_size_override("font_size", 26)
    heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    col.add_child(heading)

    for opt in options:
        var id := String(opt["id"])
        var button := Button.new()
        button.text = String(opt["name"])
        button.add_theme_font_size_override("font_size", 20)
        button.custom_minimum_size = Vector2(300, 48)
        button.pressed.connect(func(): pack_chosen.emit(id))
        col.add_child(button)

    var cancel := Button.new()
    cancel.text = "Back"
    cancel.add_theme_font_size_override("font_size", 16)
    cancel.custom_minimum_size = Vector2(300, 36)
    cancel.pressed.connect(_close_drill)
    col.add_child(cancel)


func _close_drill() -> void:
    if _drill != null:
        _drill.queue_free()
        _drill = null

extends Node2D
## Desktop label editor (NOT shipped in the WASM game). Loads a pack, renders its
## map, and overlays a draggable name label per area. Drag a label to give that
## area a manual callout (a leader line follows from the area's centroid). Save
## writes only the areas you moved into the pack's pack.json "callouts" block,
## preserving every other manifest field.
##
## Run from the Godot editor (open tools/label_editor.tscn and play it) or via CLI:
##   godot --path . tools/label_editor.tscn
## Pick a pack from the dropdown; drag labels; press Ctrl+S or click Save.

const PackScript := preload("res://scripts/pack.gd")
const MapBuilderScript := preload("res://scripts/map_builder.gd")
const DESIGN_SIZE := Vector2(1280, 720)

# Chip (draggable label) background colors by state.
const CHIP_IDLE := Color(0.18, 0.21, 0.27, 0.72)
const CHIP_HOVER := Color(0.28, 0.34, 0.42, 0.9)
const CHIP_GRABBED := Color(0.95, 0.78, 0.35, 0.95)

var _pack
var _world: Node2D  # holds map + overlay; scaled/translated for zoom/pan
var _map_root: Node2D
var _overlay: Node2D  # leader lines + draggable labels live here
var _anchors := {}  # code -> centroid Vector2 (on-map area anchor), world coords
var _labels := {}  # code -> chip (Panel) node
var _moved := {}  # code -> true once dragged (becomes a callout on save)
var _dragging: Control = null
var _hovered: Control = null
var _drag_offset := Vector2.ZERO
var _zoom := 1.0
var _pan := Vector2.ZERO
var _panning := false
var _pan_last := Vector2.ZERO
var _status: Label
var _pack_dropdown: OptionButton
var _pack_ids := []

const MIN_ZOOM := 0.5
const MAX_ZOOM := 8.0


func _ready() -> void:
    RenderingServer.set_default_clear_color(Color(0.1, 0.12, 0.15))
    _build_toolbar()
    var packs := PackScript.list_packs()
    for p in packs:
        _pack_ids.append(String(p["id"]))
        _pack_dropdown.add_item(String(p["name"]))
    if not _pack_ids.is_empty():
        _load_pack(_pack_ids[0])


func _build_toolbar() -> void:
    var layer := CanvasLayer.new()
    add_child(layer)
    var bar := HBoxContainer.new()
    bar.position = Vector2(12, 10)
    bar.add_theme_constant_override("separation", 10)
    layer.add_child(bar)

    _pack_dropdown = OptionButton.new()
    _pack_dropdown.item_selected.connect(_on_pack_selected)
    bar.add_child(_pack_dropdown)

    var save := Button.new()
    save.text = "Save callouts (Ctrl+S)"
    save.pressed.connect(_save)
    bar.add_child(save)

    var reset := Button.new()
    reset.text = "Reset dragged"
    reset.pressed.connect(_reset_moved)
    bar.add_child(reset)

    _status = Label.new()
    _status.add_theme_color_override("font_color", Color(0.75, 0.85, 0.75))
    bar.add_child(_status)


func _on_pack_selected(index: int) -> void:
    if index >= 0 and index < _pack_ids.size():
        _load_pack(_pack_ids[index])


func _load_pack(pack_id: String) -> void:
    # Clear any previous world (map + overlay).
    if _world != null:
        _world.queue_free()
    _anchors.clear()
    _labels.clear()
    _moved.clear()
    _dragging = null
    _hovered = null
    _zoom = 1.0
    _pan = Vector2.ZERO

    _pack = PackScript.load_pack(pack_id)
    if _pack == null:
        _set_status("failed to load pack '%s'" % pack_id)
        return

    # Everything that zooms/pans lives under _world.
    _world = Node2D.new()
    add_child(_world)
    _map_root = Node2D.new()
    _world.add_child(_map_root)
    MapBuilderScript.build(_map_root, _pack, DESIGN_SIZE)

    _overlay = Node2D.new()
    _world.add_child(_overlay)

    # One draggable label per area, started at its callout (if any) or centroid.
    for child in _map_root.get_children():
        if not (child is Area2D) or not child.has_meta("label_pos"):
            continue
        var code := String(child.get_meta("code"))
        var name_str := String(child.get_meta("name"))
        var anchor: Vector2 = child.get_meta("label_pos")
        _anchors[code] = anchor
        var start := anchor
        if _pack.callouts.has(code):
            start = _pack.callouts[code]
            _moved[code] = true
        _labels[code] = _make_label(code, name_str, start)
        _overlay.add_child(_labels[code])

    _apply_transform()
    _redraw_leaders()
    _set_status("%s — scroll=zoom, middle-drag=pan, drag labels, Ctrl+S=save" % _pack.name)


## Apply the current zoom/pan to the world node.
func _apply_transform() -> void:
    if _world != null:
        _world.scale = Vector2(_zoom, _zoom)
        _world.position = _pan


## Screen (viewport) point -> world point under the current zoom/pan.
func _to_world(screen: Vector2) -> Vector2:
    return (screen - _pan) / _zoom


## A draggable "chip": a rounded panel sized to the text, with the name label on
## top. The chip's background changes on hover and while grabbed, cueing that it is
## draggable. `pos` is the chip's visual center.
func _make_label(code: String, text: String, pos: Vector2) -> Control:
    var pad := Vector2(10, 4)
    var text_size := Vector2(text.length() * 7.0, 16.0)
    var chip := Panel.new()
    chip.custom_minimum_size = text_size + pad * 2.0
    chip.size = chip.custom_minimum_size
    chip.mouse_filter = Control.MOUSE_FILTER_IGNORE  # hit-testing is manual (world-space)
    chip.set_meta("code", code)
    _style_chip(chip, CHIP_IDLE)

    var label := Label.new()
    label.text = text
    label.add_theme_font_size_override("font_size", 13)
    label.add_theme_color_override("font_color", Color(1, 1, 1))
    label.add_theme_color_override("font_outline_color", Color(0.1, 0.12, 0.16))
    label.add_theme_constant_override("outline_size", 4)
    label.set_anchors_preset(Control.PRESET_FULL_RECT)
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    chip.add_child(label)

    _place_label(chip, pos)
    return chip


func _style_chip(chip: Control, color: Color) -> void:
    var sb := StyleBoxFlat.new()
    sb.bg_color = color
    sb.set_corner_radius_all(5)
    sb.border_color = Color(0.6, 0.66, 0.74, 0.5)
    sb.set_border_width_all(1)
    chip.add_theme_stylebox_override("panel", sb)


## Position a chip so `pos` is its visual center, and record that center.
func _place_label(chip: Control, pos: Vector2) -> void:
    chip.position = pos - chip.size * 0.5
    chip.set_meta("center", pos)


func _label_center(chip: Control) -> Vector2:
    return chip.get_meta("center")


func _hover_chip(chip: Control, on: bool) -> void:
    if chip == _dragging:
        return
    _style_chip(chip, CHIP_HOVER if on else CHIP_IDLE)


func _input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and event.keycode == KEY_S and event.ctrl_pressed:
        _save()
        return

    if event is InputEventMouseButton:
        var mb := event as InputEventMouseButton
        # Scroll wheel: zoom centered on the cursor.
        if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
            _zoom_at(mb.position, 1.1)
            return
        if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
            _zoom_at(mb.position, 1.0 / 1.1)
            return
        # Middle button: pan.
        if mb.button_index == MOUSE_BUTTON_MIDDLE:
            _panning = mb.pressed
            _pan_last = mb.position
            return
        # Left button: grab / release a chip.
        if mb.button_index == MOUSE_BUTTON_LEFT:
            if mb.pressed:
                _try_grab(_to_world(mb.position))
            elif _dragging != null:
                _style_chip(_dragging, CHIP_IDLE)
                _dragging = null
        return

    if event is InputEventMouseMotion:
        var mm := event as InputEventMouseMotion
        if _panning:
            _pan += mm.position - _pan_last
            _pan_last = mm.position
            _apply_transform()
            return
        var world := _to_world(mm.position)
        if _dragging != null:
            _place_label(_dragging, world + _drag_offset)
            _moved[String(_dragging.get_meta("code"))] = true
            _redraw_leaders()
        else:
            _update_hover(world)


## Zoom by `factor` keeping the world point under `screen` fixed (cursor-centered).
func _zoom_at(screen: Vector2, factor: float) -> void:
    var new_zoom := clampf(_zoom * factor, MIN_ZOOM, MAX_ZOOM)
    if is_equal_approx(new_zoom, _zoom):
        return
    var world_before := _to_world(screen)
    _zoom = new_zoom
    # Keep world_before under the same screen point: screen = world*zoom + pan.
    _pan = screen - world_before * _zoom
    _apply_transform()


## Manual hover (chips are mouse-ignoring, so we hit-test in world coords).
func _update_hover(world: Vector2) -> void:
    var hit: Control = _chip_at(world)
    if hit == _hovered:
        return
    if _hovered != null:
        _hover_chip(_hovered, false)
    _hovered = hit
    if _hovered != null:
        _hover_chip(_hovered, true)


func _chip_at(world: Vector2) -> Control:
    # Topmost chip whose world-space rect contains the point.
    for code in _labels:
        var chip: Control = _labels[code]
        if Rect2(chip.position, chip.size).has_point(world):
            return chip
    return null


func _try_grab(world: Vector2) -> void:
    var chip := _chip_at(world)
    if chip != null:
        _dragging = chip
        _drag_offset = _label_center(chip) - world
        _style_chip(chip, CHIP_GRABBED)


## Draw a leader line from each MOVED area's centroid to the nearest point on its
## chip's box (matching the game's MapBuilder._draw_callout anchoring, so what you
## tune here is what ships).
func _redraw_leaders() -> void:
    for child in _overlay.get_children():
        if child is Line2D:
            child.queue_free()
    for code in _moved:
        if not _labels.has(code) or not _anchors.has(code):
            continue
        var chip: Control = _labels[code]
        var anchor: Vector2 = _anchors[code]
        var attach := _nearest_point_on_box(chip.position, chip.position + chip.size, anchor)
        var line := Line2D.new()
        line.points = PackedVector2Array([anchor, attach])
        line.width = 1.0
        line.default_color = Color(0.7, 0.75, 0.82, 0.7)
        line.antialiased = true
        _overlay.add_child(line)
        _overlay.move_child(line, 0)  # keep lines under the labels


## Point on the axis-aligned box [tl, br] nearest to p (clamped to the box).
func _nearest_point_on_box(tl: Vector2, br: Vector2, p: Vector2) -> Vector2:
    return Vector2(clampf(p.x, tl.x, br.x), clampf(p.y, tl.y, br.y))


func _reset_moved() -> void:
    for code in _moved.keys():
        _place_label(_labels[code], _anchors[code])
    _moved.clear()
    _redraw_leaders()
    _set_status("reset — all labels back to auto position")


## Write the moved labels as the pack's "callouts", preserving other fields.
func _save() -> void:
    if _pack == null:
        return
    var disk_path := ProjectSettings.globalize_path(_pack.dir + "/pack.json")
    var text := FileAccess.get_file_as_string(_pack.dir + "/pack.json")
    var manifest = JSON.parse_string(text)
    if typeof(manifest) != TYPE_DICTIONARY:
        _set_status("ERROR: could not read manifest")
        return

    var callouts := {}
    for code in _moved:
        var c := _label_center(_labels[code])
        callouts[code] = [roundf(c.x), roundf(c.y)]
    if callouts.is_empty():
        manifest.erase("callouts")
    else:
        manifest["callouts"] = callouts

    var f := FileAccess.open(disk_path, FileAccess.WRITE)
    if f == null:
        _set_status("ERROR: cannot write %s" % disk_path)
        return
    f.store_string(JSON.stringify(manifest, "  "))
    f.close()
    _set_status("saved %d callouts -> %s" % [callouts.size(), disk_path])


func _set_status(msg: String) -> void:
    if _status != null:
        _status.text = msg
    print("[label_editor] ", msg)

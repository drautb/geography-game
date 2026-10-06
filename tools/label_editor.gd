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

var _pack
var _map_root: Node2D
var _overlay: Node2D  # leader lines + draggable labels live here
var _anchors := {}  # code -> centroid Vector2 (on-map area anchor)
var _labels := {}  # code -> Label node
var _moved := {}  # code -> true once dragged (becomes a callout on save)
var _dragging: Label = null
var _drag_offset := Vector2.ZERO
var _status: Label
var _pack_dropdown: OptionButton
var _pack_ids := []


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
    # Clear any previous map/overlay.
    if _map_root != null:
        _map_root.queue_free()
    if _overlay != null:
        _overlay.queue_free()
    _anchors.clear()
    _labels.clear()
    _moved.clear()
    _dragging = null

    _pack = PackScript.load_pack(pack_id)
    if _pack == null:
        _set_status("failed to load pack '%s'" % pack_id)
        return

    _map_root = Node2D.new()
    add_child(_map_root)
    MapBuilderScript.build(_map_root, _pack, DESIGN_SIZE)

    _overlay = Node2D.new()
    add_child(_overlay)

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

    _redraw_leaders()
    _set_status("%s — drag labels, then Save" % _pack.name)


func _make_label(code: String, text: String, pos: Vector2) -> Label:
    var label := Label.new()
    label.text = text
    label.add_theme_font_size_override("font_size", 13)
    label.add_theme_color_override("font_color", Color(1, 1, 1))
    label.add_theme_color_override("font_outline_color", Color(0.1, 0.12, 0.16))
    label.add_theme_constant_override("outline_size", 5)
    label.mouse_filter = Control.MOUSE_FILTER_STOP
    label.set_meta("code", code)
    _place_label(label, pos)
    return label


## Position a label so `pos` is its visual center (matches the game's centering).
func _place_label(label: Label, pos: Vector2) -> void:
    label.position = pos - Vector2(label.text.length() * 3.3, 7)
    label.set_meta("center", pos)


func _label_center(label: Label) -> Vector2:
    return label.get_meta("center")


func _input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and event.keycode == KEY_S and event.ctrl_pressed:
        _save()
        return
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        if event.pressed:
            _try_grab(event.position)
        elif _dragging != null:
            _dragging = null
    elif event is InputEventMouseMotion and _dragging != null:
        var mm := event as InputEventMouseMotion
        var center: Vector2 = mm.position + _drag_offset
        _place_label(_dragging, center)
        _moved[String(_dragging.get_meta("code"))] = true
        _redraw_leaders()


func _try_grab(mouse_pos: Vector2) -> void:
    # Grab the topmost label whose rect contains the cursor.
    for code in _labels:
        var label: Label = _labels[code]
        var rect := Rect2(label.position, label.size)
        if rect.has_point(mouse_pos):
            _dragging = label
            _drag_offset = _label_center(label) - mouse_pos
            return


## Draw a leader line from each MOVED area's centroid to its label.
func _redraw_leaders() -> void:
    for child in _overlay.get_children():
        if child is Line2D:
            child.queue_free()
    for code in _moved:
        if not _labels.has(code) or not _anchors.has(code):
            continue
        var line := Line2D.new()
        line.points = PackedVector2Array([_anchors[code], _label_center(_labels[code])])
        line.width = 1.0
        line.default_color = Color(0.7, 0.75, 0.82, 0.7)
        line.antialiased = true
        _overlay.add_child(line)
        _overlay.move_child(line, 0)  # keep lines under the labels


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

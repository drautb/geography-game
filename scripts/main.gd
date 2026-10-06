extends Node2D
## Entry point and round coordinator. Loads a map pack and drives the map,
## GameManager, and HUD from it. Pack-agnostic: the US is just one pack.
##
## The map is built at a fixed design resolution (stretch mode canvas_items keeps
## the logical viewport constant, so the browser canvas size never affects layout).

const PackScript := preload("res://scripts/pack.gd")
const MapBuilderScript := preload("res://scripts/map_builder.gd")
const GameManagerScript := preload("res://scripts/game_manager.gd")
const GameUiScript := preload("res://scripts/game_ui.gd")
const PackPickerScript := preload("res://scripts/pack_picker.gd")
const DESIGN_SIZE := Vector2(1280, 720)
const AUTO_ADVANCE_DELAY := 1.0

var _pack
var _picker: CanvasLayer
var _map_root: Node2D
var _game
var _ui: CanvasLayer
var _name_by_code := {}
var _group_by_code := {}
var _enabled_groups := {}
var _advance_token := 0
var _last_answer_code := ""
var _wrong_code := ""
var _pins: Node2D
var _labels: Node2D
var _name_labels: Node2D
var _capital_by_code := {}
var _pin_pos := {}
var _points_mode := false


func _ready() -> void:
    RenderingServer.set_default_clear_color(Color(0.1, 0.12, 0.15))
    # EventBus connections are made once and persist across pack loads; the
    # handlers guard on _game/_ui so they are inert while the picker is shown.
    EventBus.round_advanced.connect(_on_round_advanced)
    EventBus.answer_resolved.connect(_on_answer_resolved)
    _show_picker()


## Show the start screen. Any running game is torn down first.
func _show_picker() -> void:
    _teardown_game()
    _picker = PackPickerScript.new()
    _picker.pack_chosen.connect(_on_pack_chosen)
    add_child(_picker)


func _on_pack_chosen(pack_id: String) -> void:
    if _picker != null:
        _picker.queue_free()
        _picker = null
    _load_pack(pack_id)


## Remove all game nodes/state so a fresh pack (or the picker) starts clean.
func _teardown_game() -> void:
    if _game != null:
        # Disconnect its EventBus handler, then drop the reference so it frees.
        _game.dispose()
        _game = null
    if _map_root != null:
        _map_root.queue_free()
        _map_root = null
    if _ui != null:
        _ui.queue_free()
        _ui = null
    _pack = null
    _pins = null
    _labels = null
    _name_labels = null
    _name_by_code = {}
    _group_by_code = {}
    _capital_by_code = {}
    _pin_pos = {}
    _enabled_groups = {}
    _last_answer_code = ""
    _wrong_code = ""
    _points_mode = false
    _advance_token += 1  # invalidate any pending auto-advance timer


func _load_pack(pack_id: String) -> void:
    _pack = PackScript.load_pack(pack_id)
    if _pack == null:
        push_error("main: failed to load pack '%s'" % pack_id)
        _show_picker()
        return

    _map_root = Node2D.new()
    _map_root.name = "MapRoot"
    add_child(_map_root)
    var t = MapBuilderScript.build(_map_root, _pack, DESIGN_SIZE)

    var areas := MapBuilderScript.load_area_list(_pack.areas_path)
    for a in areas:
        _name_by_code[String(a["code"])] = String(a["name"])
        _group_by_code[String(a["code"])] = String(a["group"])
    var points := []
    if _pack.has_points():
        points = MapBuilderScript.load_point_list(_pack.points_path)
        for p in points:
            _capital_by_code[String(p["code"])] = String(p["capital"])
        _pins = MapBuilderScript.build_points(_map_root, _pack.points_path, t)
        _pins.visible = false
        _pin_pos = _pins.get_meta("pin_positions", {})

    _labels = Node2D.new()
    _labels.name = "MapLabels"
    _map_root.add_child(_labels)

    _name_labels = MapBuilderScript.build_name_labels(_map_root, _map_root, _pack)
    _name_labels.visible = false

    _ui = GameUiScript.new()
    _ui.pack = _pack
    add_child(_ui)
    _ui.mode_toggled.connect(_on_mode_toggled)
    _ui.groups_changed.connect(_on_groups_changed)
    _ui.show_names_toggled.connect(_on_show_names_toggled)
    _ui.menu_requested.connect(_show_picker)

    _game = GameManagerScript.new(areas, points)
    _game.start()


## An area's base fill: its group color, dimmed if the group is disabled.
func _base_fill(code: String) -> Color:
    var group := String(_group_by_code.get(code, ""))
    var on: bool = _enabled_groups.is_empty() or _enabled_groups.get(group, false)
    return _pack.group_color(group, on)


## At game over, any left-click restarts. Rounds auto-advance after a delay, so
## clicks are not needed to continue mid-game.
func _unhandled_input(event: InputEvent) -> void:
    if _game == null:
        return
    if event is InputEventMouseButton:
        var mb := event as InputEventMouseButton
        if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed and _game.is_awaiting_restart():
            _game.continue_game()


func _on_round_advanced(code: String) -> void:
    if _game == null or _ui == null:
        return
    # A new round is live; invalidate any pending auto-advance timer.
    _advance_token += 1
    if _last_answer_code != "":
        MapBuilderScript.set_fill(self, _last_answer_code, _base_fill(_last_answer_code))
        _last_answer_code = ""
    if _wrong_code != "":
        MapBuilderScript.set_fill(self, _wrong_code, _base_fill(_wrong_code))
        _wrong_code = ""
    _clear_labels()
    _ui.set_prompt_name(_game.prompt_label())
    _ui.set_score(_game.score(), _game.total())


func _on_answer_resolved(clicked_code: String, correct: bool) -> void:
    if _game == null or _ui == null:
        return
    if correct:
        if _wrong_code != "" and _wrong_code != clicked_code:
            MapBuilderScript.set_fill(self, _wrong_code, _base_fill(_wrong_code))
        _wrong_code = ""
        MapBuilderScript.set_fill(self, clicked_code, MapBuilderScript.FILL_CORRECT)
        _last_answer_code = clicked_code
        # Auto-advance after a brief pause (unless this correct answer ended the game).
        if _game.is_awaiting_advance():
            _schedule_auto_advance()
    else:
        if _wrong_code != "":
            MapBuilderScript.set_fill(self, _wrong_code, _base_fill(_wrong_code))
        MapBuilderScript.set_fill(self, clicked_code, MapBuilderScript.FILL_WRONG)
        _wrong_code = clicked_code
        _last_answer_code = clicked_code
    _show_click_label(clicked_code, correct)
    _ui.set_score(_game.score(), _game.total())


## Advance to the next prompt ~1s after a correct answer. A token guards against a
## stale timer firing after the game state changed (mode/group switch, restart).
func _schedule_auto_advance() -> void:
    _advance_token += 1
    var token := _advance_token
    var timer := get_tree().create_timer(AUTO_ADVANCE_DELAY)
    timer.timeout.connect(
        func():
            if token == _advance_token and _game.is_awaiting_advance():
                _game.continue_game()
    )


## Show the clicked area's name over it (areas mode) or its point near the pin
## (points mode). Only one on-map label at a time, so clear first.
func _show_click_label(code: String, correct: bool) -> void:
    _clear_labels()
    var text := ""
    var pos := Vector2.ZERO
    if _points_mode:
        text = _capital_by_code.get(code, "")
        if _pin_pos.has(code):
            pos = _pin_pos[code] + Vector2(0, -14)
        else:
            pos = _area_label_pos(code)
    else:
        text = _name_by_code.get(code, code)
        pos = _area_label_pos(code)
    if text == "":
        return
    _labels.add_child(_make_label(text, pos, correct))


func _area_label_pos(code: String) -> Vector2:
    var area := _map_root.get_node_or_null(NodePath(code))
    if area != null and area.has_meta("label_pos"):
        return area.get_meta("label_pos")
    return DESIGN_SIZE * 0.5


func _make_label(text: String, pos: Vector2, correct: bool) -> Label:
    var label := Label.new()
    label.text = text
    label.add_theme_font_size_override("font_size", 16)
    var col := Color(0.1, 0.35, 0.12) if correct else Color(0.45, 0.1, 0.08)
    label.add_theme_color_override("font_color", Color(1, 1, 1))
    label.add_theme_color_override("font_outline_color", col)
    label.add_theme_constant_override("outline_size", 6)
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.set_anchors_preset(Control.PRESET_TOP_LEFT)
    label.pivot_offset = Vector2.ZERO
    # Rough centering: shift left by an estimate of half the text width.
    label.position = pos - Vector2(text.length() * 4.0, 8)
    return label


func _clear_labels() -> void:
    for child in _labels.get_children():
        child.queue_free()


func _on_mode_toggled(points_mode: bool) -> void:
    _points_mode = points_mode
    if _pins != null:
        _pins.visible = points_mode
    _enabled_groups = _ui.enabled_groups()
    _reset_all_fills()
    _game.set_mode(GameManagerScript.Mode.POINTS if points_mode else GameManagerScript.Mode.AREAS)
    _game.set_groups(_enabled_groups)
    _game.start()


func _on_groups_changed(enabled: Dictionary) -> void:
    _enabled_groups = enabled
    _reset_all_fills()
    _game.set_groups(enabled)
    _game.start()


func _on_show_names_toggled(show: bool) -> void:
    _name_labels.visible = show


func _reset_all_fills() -> void:
    MapBuilderScript.apply_group_colors(_map_root, _pack, _enabled_groups)
    _last_answer_code = ""
    _wrong_code = ""
    _clear_labels()

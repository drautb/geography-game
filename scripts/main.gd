extends Node2D
## Entry point and round coordinator for the "find the state" game.
##
## Builds the map at a fixed design resolution (stretch mode canvas_items keeps the
## logical viewport constant, so the browser canvas size never affects layout), then
## wires the GameManager and HUD together through EventBus.

const MapBuilderScript := preload("res://scripts/map_builder.gd")
const GameManagerScript := preload("res://scripts/game_manager.gd")
const GameUiScript := preload("res://scripts/game_ui.gd")
const STATES_GEOJSON := "res://data/us_states.geojson"
const CAPITALS_GEOJSON := "res://data/capitals.geojson"
const DESIGN_SIZE := Vector2(1280, 720)
const AUTO_ADVANCE_DELAY := 1.0

var _map_root: Node2D
var _game
var _ui: CanvasLayer
var _name_by_code := {}
var _region_by_code := {}
var _enabled_regions := {}
var _advance_token := 0
var _last_answer_code := ""
var _wrong_code := ""
var _pins: Node2D
var _labels: Node2D
var _name_labels: Node2D
var _capital_by_code := {}
var _pin_pos := {}
var _capital_mode := false


func _ready() -> void:
    RenderingServer.set_default_clear_color(Color(0.1, 0.12, 0.15))

    _map_root = Node2D.new()
    _map_root.name = "MapRoot"
    add_child(_map_root)
    var t = MapBuilderScript.build(_map_root, STATES_GEOJSON, DESIGN_SIZE)

    var states := MapBuilderScript.load_state_list(STATES_GEOJSON)
    for s in states:
        _name_by_code[String(s["code"])] = String(s["name"])
        _region_by_code[String(s["code"])] = String(s["region"])
    var capitals := MapBuilderScript.load_capital_list(CAPITALS_GEOJSON)
    for c in capitals:
        _capital_by_code[String(c["code"])] = String(c["capital"])

    # Capital pins share the states' transform. Hidden until capitals mode is on.
    _pins = MapBuilderScript.build_capitals(_map_root, CAPITALS_GEOJSON, t)
    _pins.visible = false
    _pin_pos = _pins.get_meta("pin_positions", {})

    # On-map feedback labels live above the map, below the UI.
    _labels = Node2D.new()
    _labels.name = "MapLabels"
    _map_root.add_child(_labels)

    # Persistent state-name labels (optional, toggled via the UI).
    _name_labels = MapBuilderScript.build_name_labels(_map_root, _map_root)
    _name_labels.visible = false

    _ui = GameUiScript.new()
    add_child(_ui)
    _ui.set_name_lookup(_name_by_code)
    _ui.mode_toggled.connect(_on_mode_toggled)
    _ui.regions_changed.connect(_on_regions_changed)
    _ui.show_names_toggled.connect(_on_show_names_toggled)

    EventBus.round_advanced.connect(_on_round_advanced)
    EventBus.answer_resolved.connect(_on_answer_resolved)

    _game = GameManagerScript.new(states, capitals)
    _game.start()


## A state's base fill: its region color, dimmed if the region is disabled.
func _base_fill(code: String) -> Color:
    var region := String(_region_by_code.get(code, ""))
    var on: bool = _enabled_regions.is_empty() or _enabled_regions.get(region, false)
    return MapBuilderScript.region_color(region, on)


## At game over, any left-click restarts. Rounds now auto-advance after a delay,
## so clicks are not needed to continue mid-game.
func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        var mb := event as InputEventMouseButton
        if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed and _game.is_awaiting_restart():
            _game.continue_game()


func _on_round_advanced(code: String) -> void:
    # A new round is live; invalidate any pending auto-advance timer.
    _advance_token += 1
    # Reset the previous round's coloring and labels, then show the new prompt.
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
    if correct:
        if _wrong_code != "" and _wrong_code != clicked_code:
            MapBuilderScript.set_fill(self, _wrong_code, _base_fill(_wrong_code))
        _wrong_code = ""
        MapBuilderScript.set_fill(self, clicked_code, MapBuilderScript.FILL_CORRECT)
        _last_answer_code = clicked_code
        # Auto-advance after a brief pause (unless this correct answer ended the
        # game, which waits for a click to restart).
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
## stale timer firing after the game state changed (mode/region switch, restart).
func _schedule_auto_advance() -> void:
    _advance_token += 1
    var token := _advance_token
    var timer := get_tree().create_timer(AUTO_ADVANCE_DELAY)
    timer.timeout.connect(
        func():
            if token == _advance_token and _game.is_awaiting_advance():
                _game.continue_game()
    )


## Show the clicked state's name over it (states mode) or its capital near the pin
## (capitals mode). Only one on-map label at a time, so clear first.
func _show_click_label(code: String, correct: bool) -> void:
    _clear_labels()
    var text := ""
    var pos := Vector2.ZERO
    if _capital_mode:
        # Name the clicked state's capital, placed just above its pin.
        text = _capital_by_code.get(code, "")
        if _pin_pos.has(code):
            pos = _pin_pos[code] + Vector2(0, -14)
        else:
            pos = _state_label_pos(code)
    else:
        text = _name_by_code.get(code, code)
        pos = _state_label_pos(code)
    if text == "":
        return
    _labels.add_child(_make_label(text, pos, correct))


func _state_label_pos(code: String) -> Vector2:
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
    # Center the label on the anchor point.
    label.position = pos
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.set_anchors_preset(Control.PRESET_TOP_LEFT)
    label.pivot_offset = Vector2.ZERO
    # Rough centering: shift left by an estimate of half the text width.
    label.position = pos - Vector2(text.length() * 4.0, 8)
    return label


func _clear_labels() -> void:
    for child in _labels.get_children():
        child.queue_free()


func _on_mode_toggled(capital_mode: bool) -> void:
    _capital_mode = capital_mode
    _pins.visible = capital_mode
    _enabled_regions = _ui.enabled_regions()
    _reset_all_fills()
    _game.set_mode(GameManagerScript.Mode.CAPITAL if capital_mode else GameManagerScript.Mode.STATE)
    _game.set_regions(_enabled_regions)
    _game.start()


func _on_regions_changed(enabled: Dictionary) -> void:
    _enabled_regions = enabled
    _reset_all_fills()
    _game.set_regions(enabled)
    _game.start()


func _on_show_names_toggled(show: bool) -> void:
    _name_labels.visible = show


func _reset_all_fills() -> void:
    # Repaint every state to its region base color, dimming disabled regions.
    MapBuilderScript.apply_region_colors(_map_root, _enabled_regions)
    _last_answer_code = ""
    _wrong_code = ""
    _clear_labels()

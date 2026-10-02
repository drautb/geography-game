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

var _map_root: Node2D
var _game
var _ui: CanvasLayer
var _name_by_code := {}
var _last_answer_code := ""
var _wrong_code := ""
var _pins: Node2D


func _ready() -> void:
    RenderingServer.set_default_clear_color(Color(0.1, 0.12, 0.15))

    _map_root = Node2D.new()
    _map_root.name = "MapRoot"
    add_child(_map_root)
    var t = MapBuilderScript.build(_map_root, STATES_GEOJSON, DESIGN_SIZE)

    var states := MapBuilderScript.load_state_list(STATES_GEOJSON)
    for s in states:
        _name_by_code[String(s["code"])] = String(s["name"])
    var capitals := MapBuilderScript.load_capital_list(CAPITALS_GEOJSON)

    # Capital pins share the states' transform. Hidden until capitals mode is on.
    _pins = MapBuilderScript.build_capitals(_map_root, CAPITALS_GEOJSON, t)
    _pins.visible = false

    _ui = GameUiScript.new()
    add_child(_ui)
    _ui.set_name_lookup(_name_by_code)
    _ui.next_requested.connect(_on_next_requested)
    _ui.mode_toggled.connect(_on_mode_toggled)

    EventBus.round_advanced.connect(_on_round_advanced)
    EventBus.answer_resolved.connect(_on_answer_resolved)
    EventBus.game_over.connect(_on_game_over)

    _game = GameManagerScript.new(states, capitals)
    _game.start()


var _is_over := false


func _on_game_over(_score: int, _total: int) -> void:
    _is_over = true


func _on_round_advanced(code: String) -> void:
    # Reset the previous round's coloring and show the new prompt.
    if _last_answer_code != "":
        MapBuilderScript.set_fill(self, _last_answer_code, MapBuilderScript.FILL_COLOR)
        _last_answer_code = ""
    if _wrong_code != "":
        MapBuilderScript.set_fill(self, _wrong_code, MapBuilderScript.FILL_COLOR)
        _wrong_code = ""
    _ui.set_prompt_name(_game.prompt_label())
    _ui.set_score(_game.score(), _game.total())


func _on_answer_resolved(clicked_code: String, correct: bool) -> void:
    if correct:
        # Clear any lingering wrong-guess red from this round, then color the
        # correct pick green.
        if _wrong_code != "" and _wrong_code != clicked_code:
            MapBuilderScript.set_fill(self, _wrong_code, MapBuilderScript.FILL_COLOR)
        _wrong_code = ""
        MapBuilderScript.set_fill(self, clicked_code, MapBuilderScript.FILL_CORRECT)
        _last_answer_code = clicked_code
    else:
        # Clear the previous wrong guess's red (player keeps guessing on this
        # round), then redden the new one. Never reveal the correct state.
        if _wrong_code != "":
            MapBuilderScript.set_fill(self, _wrong_code, MapBuilderScript.FILL_COLOR)
        MapBuilderScript.set_fill(self, clicked_code, MapBuilderScript.FILL_WRONG)
        _wrong_code = clicked_code
        _last_answer_code = clicked_code
    _ui.set_score(_game.score(), _game.total())


func _on_next_requested() -> void:
    if _is_over:
        _is_over = false
        _reset_all_fills()
        _game.start()
    else:
        _game.next()


func _on_mode_toggled(capital_mode: bool) -> void:
    _pins.visible = capital_mode
    _is_over = false
    _reset_all_fills()
    _game.set_mode(GameManagerScript.Mode.CAPITAL if capital_mode else GameManagerScript.Mode.STATE)
    _game.start()


func _reset_all_fills() -> void:
    for code in _name_by_code.keys():
        MapBuilderScript.set_fill(self, code, MapBuilderScript.FILL_COLOR)
    _last_answer_code = ""
    _wrong_code = ""

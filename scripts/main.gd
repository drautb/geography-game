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
const DESIGN_SIZE := Vector2(1280, 720)

var _map_root: Node2D
var _game
var _ui: CanvasLayer
var _name_by_code := {}
var _last_answer_code := ""


func _ready() -> void:
    RenderingServer.set_default_clear_color(Color(0.1, 0.12, 0.15))

    _map_root = Node2D.new()
    _map_root.name = "MapRoot"
    add_child(_map_root)
    MapBuilderScript.build(_map_root, STATES_GEOJSON, DESIGN_SIZE)

    var states := MapBuilderScript.load_state_list(STATES_GEOJSON)
    for s in states:
        _name_by_code[String(s["code"])] = String(s["name"])

    _ui = GameUiScript.new()
    add_child(_ui)
    _ui.set_name_lookup(_name_by_code)
    _ui.next_requested.connect(_on_next_requested)

    EventBus.round_advanced.connect(_on_round_advanced)
    EventBus.answer_resolved.connect(_on_answer_resolved)
    EventBus.game_over.connect(_on_game_over)

    _game = GameManagerScript.new(states)
    _game.start()


var _is_over := false


func _on_game_over(_score: int, _total: int) -> void:
    _is_over = true


func _on_round_advanced(code: String) -> void:
    # Reset the previous answer's coloring and show the new prompt.
    if _last_answer_code != "":
        MapBuilderScript.set_fill(self, _last_answer_code, MapBuilderScript.FILL_COLOR)
        _last_answer_code = ""
    _ui.set_prompt_name(_name_by_code.get(code, code))
    _ui.set_score(_game.score(), _game.total())


func _on_answer_resolved(clicked_code: String, correct: bool) -> void:
    if correct:
        MapBuilderScript.set_fill(self, clicked_code, MapBuilderScript.FILL_CORRECT)
    else:
        # Only mark the wrong click red — do NOT reveal the correct state, so the
        # player still has to find it when it comes back around.
        MapBuilderScript.set_fill(self, clicked_code, MapBuilderScript.FILL_WRONG)
    _last_answer_code = clicked_code
    _ui.set_score(_game.score(), _game.total())


func _on_next_requested() -> void:
    if _is_over:
        _is_over = false
        _reset_all_fills()
        _game.start()
    else:
        _game.next()


func _reset_all_fills() -> void:
    for code in _name_by_code.keys():
        MapBuilderScript.set_fill(self, code, MapBuilderScript.FILL_COLOR)
    _last_answer_code = ""

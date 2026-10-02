extends Node2D
## Headless harness: builds the map + capital pins, switches to CAPITAL mode, and
## screenshots so we can verify pins render and the prompt shows a capital name.

const MapBuilderScript := preload("res://scripts/map_builder.gd")
const GameManagerScript := preload("res://scripts/game_manager.gd")
const GameUiScript := preload("res://scripts/game_ui.gd")
const STATES_GEOJSON := "res://data/us_states.geojson"
const CAPITALS_GEOJSON := "res://data/capitals.geojson"
const DESIGN_SIZE := Vector2(1280, 720)

var _frames := 0
var _game
var _ui: CanvasLayer


func _ready() -> void:
    RenderingServer.set_default_clear_color(Color(0.1, 0.12, 0.15))
    var map_root := Node2D.new()
    add_child(map_root)
    var t = MapBuilderScript.build(map_root, STATES_GEOJSON, DESIGN_SIZE)
    var states := MapBuilderScript.load_state_list(STATES_GEOJSON)
    var capitals := MapBuilderScript.load_capital_list(CAPITALS_GEOJSON)
    MapBuilderScript.build_capitals(map_root, CAPITALS_GEOJSON, t)

    _ui = GameUiScript.new()
    add_child(_ui)
    _ui.set_name_lookup({})
    _ui.set_capital_mode(true)
    EventBus.round_advanced.connect(func(_c): _ui.set_prompt_name(_game.prompt_label()))

    _game = GameManagerScript.new(states, capitals)
    _game.set_mode(GameManagerScript.Mode.CAPITAL)
    _game.start()


func _process(_delta: float) -> void:
    _frames += 1
    if _frames == 3:
        var p: Dictionary = _game.current_prompt()
        print(
            (
                "capital-mode prompt: capital=%s code=%s total=%d"
                % [p.get("capital"), p.get("code"), _game.total()]
            )
        )
    if _frames == 6:
        var image := get_viewport().get_texture().get_image()
        if image:
            image.save_png("/project/test_screenshot.png")
            print("Screenshot saved!")
        get_tree().quit()

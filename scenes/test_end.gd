extends Node2D
## Headless harness: plays through ALL prompts to reach the end screen, then
## screenshots the "Done! / Play again" state. Verifies game_over handling.

const MapBuilderScript := preload("res://scripts/map_builder.gd")
const GameManagerScript := preload("res://scripts/game_manager.gd")
const GameUiScript := preload("res://scripts/game_ui.gd")
const STATES_GEOJSON := "res://data/assets/us_states.geojson"
const DESIGN_SIZE := Vector2(1280, 720)

var _frames := 0
var _game
var _ui: CanvasLayer
var _prompt_code := ""
var _over := false


func _ready() -> void:
    RenderingServer.set_default_clear_color(Color(0.1, 0.12, 0.15))
    var map_root := Node2D.new()
    add_child(map_root)
    MapBuilderScript.build(map_root, STATES_GEOJSON, DESIGN_SIZE)
    var states := MapBuilderScript.load_state_list(STATES_GEOJSON)

    _ui = GameUiScript.new()
    add_child(_ui)
    EventBus.round_advanced.connect(func(code): _prompt_code = code)
    EventBus.game_over.connect(func(_s, _t): _over = true)

    _game = GameManagerScript.new(states)
    _game.start()


func _process(_delta: float) -> void:
    _frames += 1
    # Each frame: answer the current prompt correctly, then advance, until game over.
    if _frames >= 2 and not _over:
        EventBus.state_clicked.emit(_prompt_code)
        _game.next()
    if _over and _frames > 2:
        # Let the UI paint the end screen, then capture.
        await get_tree().process_frame
        await get_tree().process_frame
        var image := get_viewport().get_texture().get_image()
        if image:
            image.save_png("/project/test_screenshot.png")
            print("END SCREEN captured; final score %d/%d" % [_game.score(), _game.total()])
        get_tree().quit()

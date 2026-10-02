extends Node2D
## Headless gameplay harness: builds the real game, simulates clicks via EventBus,
## and screenshots the feedback state. Verifies map coloring + GameManager wiring.

const MapBuilderScript := preload("res://scripts/map_builder.gd")
const GameManagerScript := preload("res://scripts/game_manager.gd")
const GameUiScript := preload("res://scripts/game_ui.gd")
const STATES_GEOJSON := "res://data/build/us_states.geojson"
const DESIGN_SIZE := Vector2(1280, 720)

var _frames := 0
var _map_root: Node2D
var _game
var _ui: CanvasLayer
var _prompt_code := ""


func _ready() -> void:
    RenderingServer.set_default_clear_color(Color(0.1, 0.12, 0.15))
    _map_root = Node2D.new()
    add_child(_map_root)
    MapBuilderScript.build(_map_root, STATES_GEOJSON, DESIGN_SIZE)
    var states := MapBuilderScript.load_state_list(STATES_GEOJSON)

    _ui = GameUiScript.new()
    add_child(_ui)

    EventBus.round_advanced.connect(func(code): _prompt_code = code)
    EventBus.round_advanced.connect(
        func(code):
            _ui.set_prompt_name(code)
            _ui.set_score(_game.score(), _game.total())
    )
    EventBus.answer_resolved.connect(
        func(clicked, correct):
            if correct:
                MapBuilderScript.set_fill(self, clicked, MapBuilderScript.FILL_CORRECT)
    )

    _game = GameManagerScript.new(states)
    _game.start()


func _process(_delta: float) -> void:
    _frames += 1
    if _frames == 3:
        # Simulate a CORRECT click on the current prompt state.
        print("prompt is: ", _prompt_code)
        EventBus.state_clicked.emit(_prompt_code)
        print("score after correct click: ", _game.score())
    if _frames == 7:
        var image := get_viewport().get_texture().get_image()
        if image:
            image.save_png("/project/test_screenshot.png")
            print("Screenshot saved!")
        get_tree().quit()

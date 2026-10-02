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
    var lookup := {}
    for s in states:
        lookup[String(s["code"])] = String(s["name"])

    _ui = GameUiScript.new()
    add_child(_ui)
    _ui.set_name_lookup(lookup)

    EventBus.round_advanced.connect(func(code): _prompt_code = code)
    EventBus.round_advanced.connect(
        func(code):
            _ui.set_prompt_name(lookup.get(code, code))
            _ui.set_score(_game.score(), _game.total())
    )
    EventBus.answer_resolved.connect(
        func(clicked, correct):
            if correct:
                MapBuilderScript.set_fill(self, clicked, MapBuilderScript.FILL_CORRECT)
            else:
                MapBuilderScript.set_fill(self, clicked, MapBuilderScript.FILL_WRONG)
    )

    _game = GameManagerScript.new(states)
    _game.start()


func _process(_delta: float) -> void:
    _frames += 1
    if _frames == 3:
        # Simulate a WRONG click: pick any state that is not the prompt.
        var wrong := "TX" if _prompt_code != "TX" else "CA"
        print("prompt is: %s, clicking wrong: %s" % [_prompt_code, wrong])
        EventBus.state_clicked.emit(wrong)
    if _frames == 7:
        var image := get_viewport().get_texture().get_image()
        if image:
            image.save_png("/project/test_screenshot.png")
            print("Screenshot saved!")
        get_tree().quit()

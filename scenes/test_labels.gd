extends Node
## Drives the REAL main scene to verify the no-Next-button flow: answer correctly,
## confirm the game latches "awaiting advance", then a click on EMPTY space advances.

const MainScene := preload("res://scenes/main.tscn")

var _frames := 0
var _main: Node
var _prompt_code := ""
var _prompt_count := 0


func _ready() -> void:
    _main = MainScene.instantiate()
    add_child(_main)
    EventBus.round_advanced.connect(
        func(code):
            _prompt_code = code
            _prompt_count += 1
    )


func _process(_delta: float) -> void:
    _frames += 1
    if _frames == 4:
        _prompt_code = String(_main._game.current_prompt().get("code", ""))
        print("round1 prompt=%s" % _prompt_code)
        EventBus.state_clicked.emit(_prompt_code)
    if _frames == 6:
        print("after correct: is_waiting=%s" % _main._game.is_waiting())
    if _frames == 8:
        # Click EMPTY ocean (no state) via a raw mouse event to the viewport.
        var ev := InputEventMouseButton.new()
        ev.button_index = MOUSE_BUTTON_LEFT
        ev.position = Vector2(60, 680)  # bottom-left ocean
        ev.pressed = true
        Input.parse_input_event(ev)
        var up := InputEventMouseButton.new()
        up.button_index = MOUSE_BUTTON_LEFT
        up.position = Vector2(60, 680)
        up.pressed = false
        Input.parse_input_event(up)
    if _frames == 12:
        print(
            (
                "after empty click: prompt_count=%d is_waiting=%s"
                % [_prompt_count, _main._game.is_waiting()]
            )
        )
        var image := get_viewport().get_texture().get_image()
        if image:
            image.save_png("/project/test_screenshot.png")
            print("Screenshot saved!")
        get_tree().quit()

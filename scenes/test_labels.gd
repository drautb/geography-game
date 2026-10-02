extends Node
## Verify auto-advance: answer correctly, then WITHOUT any click confirm the game
## advances to a new prompt after the ~1s delay.

const MainScene := preload("res://scenes/main.tscn")

var _frames := 0
var _main: Node
var _first_code := ""
var _elapsed := 0.0
var _phase := 0


func _ready() -> void:
    _main = MainScene.instantiate()
    add_child(_main)


func _process(delta: float) -> void:
    _frames += 1
    if _phase == 0 and _frames == 4:
        _first_code = String(_main._game.current_prompt().get("code", ""))
        print("round1=%s; answering correctly" % _first_code)
        EventBus.state_clicked.emit(_first_code)
        print("after correct: is_awaiting_advance=%s" % _main._game.is_awaiting_advance())
        _phase = 1
    elif _phase == 1:
        # Wait past the auto-advance delay WITHOUT clicking.
        _elapsed += delta
        if _elapsed > 1.4:
            var now := String(_main._game.current_prompt().get("code", ""))
            print(
                (
                    "after %.1fs no click: prompt now=%s advanced=%s"
                    % [_elapsed, now, now != _first_code]
                )
            )
            get_tree().quit()

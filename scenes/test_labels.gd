extends Node
## Drives the REAL main scene: instances main.tscn, waits, simulates clicks via
## EventBus, and screenshots — so on-map feedback labels are verified in the actual
## game flow (not a reimplementation). Set MODE_CAPITAL to test capitals mode.

const MainScene := preload("res://scenes/main.tscn")
const CAP := false  # flip in a second harness for capitals mode

var _frames := 0
var _main: Node
var _prompt_code := ""


func _ready() -> void:
    _main = MainScene.instantiate()
    add_child(_main)
    EventBus.round_advanced.connect(func(code): _prompt_code = code)


func _process(_delta: float) -> void:
    _frames += 1
    if _frames == 2 and CAP:
        # Switch the real game into capitals mode via its UI signal path.
        _main._on_mode_toggled(true)
    if _frames == 4:
        var wrong := "TX" if _prompt_code != "TX" else "CA"
        print("prompt=%s wrong=%s cap=%s" % [_prompt_code, wrong, CAP])
        EventBus.state_clicked.emit(wrong)
    if _frames == 10:
        var image := get_viewport().get_texture().get_image()
        if image:
            image.save_png("/project/test_screenshot.png")
            print("Screenshot saved!")
        get_tree().quit()

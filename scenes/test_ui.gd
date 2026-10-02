extends Node
## Screenshot the real main scene, then disable the West region to verify dimming.

const MainScene := preload("res://scenes/main.tscn")
var _frames := 0
var _main: Node


func _ready() -> void:
    _main = MainScene.instantiate()
    add_child(_main)


func _process(_delta: float) -> void:
    _frames += 1
    if _frames == 4:
        # Disable West via the real signal path (uncheck + emit).
        var ui = _main._ui
        ui._region_checks["West"].set_pressed_no_signal(false)
        ui.regions_changed.emit(ui.enabled_regions())
    if _frames == 8:
        var image := get_viewport().get_texture().get_image()
        if image:
            image.save_png("/project/test_screenshot.png")
            print("Screenshot saved!")
        get_tree().quit()

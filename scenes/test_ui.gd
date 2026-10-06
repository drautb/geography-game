extends Node
## Screenshot the real main scene with "Show state names" enabled (in capitals
## mode) to verify persistent state-name labels render across the map.

const MainScene := preload("res://scenes/main.tscn")
var _frames := 0
var _main: Node


func _ready() -> void:
    _main = MainScene.instantiate()
    add_child(_main)


func _process(_delta: float) -> void:
    _frames += 1
    if _frames == 4:
        var ui = _main._ui
        # Switch to points (capitals) mode and turn on area names via the real signals.
        ui._points_radio.button_pressed = true
        ui._names_check.button_pressed = true
    if _frames == 8:
        var image := get_viewport().get_texture().get_image()
        if image:
            image.save_png("/project/test_screenshot.png")
            print("Screenshot saved!")
        get_tree().quit()

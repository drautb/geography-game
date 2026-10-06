extends Node
## Drive the real main scene through the pack picker: screenshot the picker, pick
## the US pack, enable area names, and screenshot the loaded game.

const MainScene := preload("res://scenes/main.tscn")
var _frames := 0
var _main: Node


func _ready() -> void:
    _main = MainScene.instantiate()
    add_child(_main)


func _process(_delta: float) -> void:
    _frames += 1
    if _frames == 3:
        # Picker is up; capture it.
        var image := get_viewport().get_texture().get_image()
        if image:
            image.save_png("/project/test_picker.png")
            print("Picker screenshot saved!")
        # Choose the US pack via the picker's signal.
        _main._picker.pack_chosen.emit("us-states")
    if _frames == 7:
        var ui = _main._ui
        ui._names_check.button_pressed = true
        if ui._points_radio != null:
            ui._points_radio.button_pressed = true
    if _frames == 11:
        var image := get_viewport().get_texture().get_image()
        if image:
            image.save_png("/project/test_screenshot.png")
            print("Game screenshot saved!")
        get_tree().quit()

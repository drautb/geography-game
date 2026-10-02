extends Node
## Screenshot the real main scene so the radio buttons + region checkboxes are
## visible for verification.

const MainScene := preload("res://scenes/main.tscn")
var _frames := 0


func _ready() -> void:
    add_child(MainScene.instantiate())


func _process(_delta: float) -> void:
    _frames += 1
    if _frames == 6:
        var image := get_viewport().get_texture().get_image()
        if image:
            image.save_png("/project/test_screenshot.png")
            print("Screenshot saved!")
        get_tree().quit()

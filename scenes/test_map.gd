extends Node2D
## Headless screenshot harness for verifying the US map renders correctly.
## Run via Docker + Xvfb (see docs). Builds the map, waits for layout, captures a
## PNG to /project/test_screenshot.png, then quits.

const MapBuilderScript := preload("res://scripts/map_builder.gd")
const GEOJSON := "res://data/build/us_states.geojson"
const VIEWPORT := Vector2(1280, 720)

var _frames := 0
var _built := false


func _ready() -> void:
    # Dark background so the map fill stands out in the screenshot.
    RenderingServer.set_default_clear_color(Color(0.1, 0.12, 0.15))


func _process(_delta: float) -> void:
    _frames += 1
    if _frames == 2 and not _built:
        _built = true
        var t = MapBuilderScript.build(self, GEOJSON, VIEWPORT)
        if t == null:
            push_error("map build failed")
            get_tree().quit()
            return
        print("built %d state areas" % get_child_count())
    if _frames == 6:
        var image := get_viewport().get_texture().get_image()
        if image:
            image.save_png("/project/test_screenshot.png")
            print("Screenshot saved!")
        else:
            print("ERROR: Could not get viewport image")
        get_tree().quit()

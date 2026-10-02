extends Node2D
## Entry point. Builds the interactive US map at a fixed design resolution.
##
## The project uses stretch mode "canvas_items" with a 1280x720 base, so the
## logical viewport is always DESIGN_SIZE regardless of the browser canvas size.
## Building against a constant size (rather than the live viewport) avoids a
## web-specific failure where the canvas reports size 0 during the first frames,
## which produced a blank screen.

const MapBuilderScript := preload("res://scripts/map_builder.gd")
const GEOJSON := "res://data/build/us_states.geojson"
const DESIGN_SIZE := Vector2(1280, 720)


func _ready() -> void:
    RenderingServer.set_default_clear_color(Color(0.1, 0.12, 0.15))
    var map_root := Node2D.new()
    map_root.name = "MapRoot"
    add_child(map_root)
    MapBuilderScript.build(map_root, GEOJSON, DESIGN_SIZE)

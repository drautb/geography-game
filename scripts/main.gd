extends Node2D
## Entry point. Builds the interactive US map fit to the current viewport.
## Game logic (prompts, scoring, capitals) will layer on top of this.

const MapBuilderScript := preload("res://scripts/map_builder.gd")
const GEOJSON := "res://data/build/us_states.geojson"

var _map_root: Node2D


func _ready() -> void:
    RenderingServer.set_default_clear_color(Color(0.1, 0.12, 0.15))
    _build_map()
    get_tree().get_root().size_changed.connect(_on_viewport_resized)


func _build_map() -> void:
    if _map_root != null:
        _map_root.queue_free()
    _map_root = Node2D.new()
    _map_root.name = "MapRoot"
    add_child(_map_root)
    var size := Vector2(get_viewport().get_visible_rect().size)
    MapBuilderScript.build(_map_root, GEOJSON, size)


func _on_viewport_resized() -> void:
    _build_map()

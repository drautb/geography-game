extends Node
## Headless verification for the label editor: load it on a pack, confirm labels
## built, simulate moving one label, save, and check pack.json got the callout
## without losing other fields. Restores pack.json afterward.

const EditorScene := preload("res://tools/label_editor.tscn")

var _frames := 0
var _editor: Node2D
var _manifest_backup := ""
var _pack_path := "res://packs/south-america/pack.json"


func _ready() -> void:
    _manifest_backup = FileAccess.get_file_as_string(_pack_path)
    _editor = EditorScene.instantiate()
    add_child(_editor)


func _process(_delta: float) -> void:
    _frames += 1
    if _frames == 4:
        _editor._load_pack("south-america")
    if _frames == 8:
        var n_labels: int = _editor._labels.size()
        print("labels built: %d" % n_labels)
        # Zoom in and pan, then simulate a drag using the SAME screen->world path the
        # input handler uses, to confirm the saved callout is correct design-space.
        _editor._zoom = 3.0
        _editor._pan = Vector2(-500, -300)
        _editor._apply_transform()
        var lbl = _editor._labels.get("CHL")
        if lbl != null:
            # Grab at the chip's current world center (projected to screen), then
            # move the cursor so the chip's world center lands at (300,400).
            var screen_grab: Vector2 = _editor._label_center(lbl) * _editor._zoom + _editor._pan
            _editor._try_grab(_editor._to_world(screen_grab))
            var screen_target: Vector2 = Vector2(300, 400) * _editor._zoom + _editor._pan
            _editor._place_label(lbl, _editor._to_world(screen_target) + _editor._drag_offset)
            _editor._moved["CHL"] = true
            _editor._redraw_leaders()
            print(
                (
                    "zoom=%.1f; moved CHL -> world %s; leader lines: %d"
                    % [_editor._zoom, str(_editor._label_center(lbl)), _count_lines()]
                )
            )
        _editor._save()
    if _frames == 12:
        # Read back the manifest and check.
        var text := FileAccess.get_file_as_string(_pack_path)
        var m = JSON.parse_string(text)
        print(
            (
                "after save: name=%s has_areas=%s callouts=%s"
                % [m.get("name"), m.has("areas"), JSON.stringify(m.get("callouts"))]
            )
        )
        # Restore original manifest.
        var f := FileAccess.open(_pack_path, FileAccess.WRITE)
        f.store_string(_manifest_backup)
        f.close()
        print("restored pack.json")
        get_tree().quit()


func _count_lines() -> int:
    var n := 0
    for c in _editor._overlay.get_children():
        if c is Line2D:
            n += 1
    return n

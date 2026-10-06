extends CanvasLayer
## Start screen: a title and one button per available pack (from packs/index.json).
## Emits pack_chosen(id) when the player picks one. Built in code, like GameUI.

signal pack_chosen(pack_id: String)

const PackScript := preload("res://scripts/pack.gd")


func _ready() -> void:
    var center := CenterContainer.new()
    center.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(center)

    var col := VBoxContainer.new()
    col.add_theme_constant_override("separation", 16)
    center.add_child(col)

    var title := Label.new()
    title.text = "Geography Game"
    title.add_theme_font_size_override("font_size", 40)
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    col.add_child(title)

    var subtitle := Label.new()
    subtitle.text = "Choose a map"
    subtitle.add_theme_font_size_override("font_size", 18)
    subtitle.add_theme_color_override("font_color", Color(0.72, 0.78, 0.86))
    subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    col.add_child(subtitle)

    col.add_child(_spacer(8))

    for entry in PackScript.list_packs():
        var id := String(entry["id"])
        var button := Button.new()
        button.text = String(entry["name"])
        button.add_theme_font_size_override("font_size", 22)
        button.custom_minimum_size = Vector2(320, 52)
        button.pressed.connect(func(): pack_chosen.emit(id))
        col.add_child(button)


func _spacer(h: int) -> Control:
    var c := Control.new()
    c.custom_minimum_size = Vector2(0, h)
    return c

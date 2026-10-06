extends CanvasLayer
## Game HUD: prompt, score, feedback, mode radios, group-focus checkboxes, and a
## names toggle. Purely presentational — reads EventBus signals and emits user
## choices. Pack-driven: nouns, groups, and colors come from the loaded Pack. No
## Next button: after a correct answer any click advances.
##
## Set `pack` before adding this node to the tree (the UI is built in _ready).

signal mode_toggled(points_mode: bool)
signal groups_changed(enabled: Dictionary)
signal show_names_toggled(show: bool)
signal menu_requested

var pack

var _prompt_label: Label
var _score_label: Label
var _feedback_label: Label
var _areas_radio: CheckBox
var _points_radio: CheckBox
var _group_checks := {}
var _names_check: CheckBox

var _prompt_name := ""
var _points_mode := false


func _ready() -> void:
    _prompt_label = Label.new()
    _prompt_label.add_theme_font_size_override("font_size", 28)
    _prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _prompt_label.anchor_left = 0.0
    _prompt_label.anchor_right = 1.0
    _prompt_label.offset_top = 16
    _prompt_label.offset_bottom = 56
    add_child(_prompt_label)

    _score_label = Label.new()
    _score_label.add_theme_font_size_override("font_size", 20)
    _score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    _score_label.anchor_left = 0.0
    _score_label.anchor_right = 1.0
    _score_label.offset_top = 16
    _score_label.offset_right = -20
    add_child(_score_label)

    _feedback_label = Label.new()
    _feedback_label.add_theme_font_size_override("font_size", 20)
    _feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _feedback_label.anchor_left = 0.0
    _feedback_label.anchor_right = 1.0
    _feedback_label.offset_top = 60
    _feedback_label.offset_bottom = 90
    add_child(_feedback_label)

    _build_control_panel()
    _build_options_panel()
    _build_menu_button()

    EventBus.round_advanced.connect(_on_round_advanced)
    EventBus.answer_resolved.connect(_on_answer_resolved)
    EventBus.game_over.connect(_on_game_over)


## A small "Menu" button (bottom-right) to return to the pack picker.
func _build_menu_button() -> void:
    var button := Button.new()
    button.text = "☰ Menu"
    button.anchor_left = 1.0
    button.anchor_right = 1.0
    button.anchor_top = 1.0
    button.anchor_bottom = 1.0
    button.offset_left = -108
    button.offset_right = -16
    button.offset_top = -48
    button.offset_bottom = -16
    button.pressed.connect(func(): menu_requested.emit())
    add_child(button)


## Top-left panel: mode radios (only when the pack has points) + group checkboxes
## with a color-swatch legend (only when the pack has groups).
func _build_control_panel() -> void:
    # Nothing to show if the pack has neither a points mode nor groups.
    if not pack.has_points() and not pack.has_groups():
        return
    var panel := PanelContainer.new()
    panel.position = Vector2(16, 14)
    panel.add_theme_stylebox_override("panel", _panel_style())
    add_child(panel)

    var margin := _panel_margin()
    panel.add_child(margin)
    var col := VBoxContainer.new()
    col.add_theme_constant_override("separation", 6)
    margin.add_child(col)

    if pack.has_points():
        col.add_child(_section_title("Mode"))
        var group := ButtonGroup.new()
        _areas_radio = CheckBox.new()
        _areas_radio.text = _plural(pack.area_noun)
        _areas_radio.button_group = group
        _areas_radio.button_pressed = true
        _areas_radio.toggled.connect(_on_areas_radio_toggled)
        col.add_child(_areas_radio)
        _points_radio = CheckBox.new()
        _points_radio.text = _plural(pack.point_noun)
        _points_radio.button_group = group
        _points_radio.toggled.connect(_on_points_radio_toggled)
        col.add_child(_points_radio)

    if pack.has_points() and pack.has_groups():
        col.add_child(HSeparator.new())

    if pack.has_groups():
        col.add_child(_section_title(pack.group_noun))
        for g in pack.group_order:
            var gid := String(g["id"])
            var row := HBoxContainer.new()
            row.add_theme_constant_override("separation", 6)
            var swatch := ColorRect.new()
            swatch.color = pack.group_colors.get(gid, Color.WHITE)
            swatch.custom_minimum_size = Vector2(14, 14)
            swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
            row.add_child(swatch)
            var cb := CheckBox.new()
            cb.text = String(g["name"])
            cb.button_pressed = true
            cb.toggled.connect(_on_group_toggled)
            row.add_child(cb)
            col.add_child(row)
            _group_checks[gid] = cb


## Bottom-left panel: the "<Area> Names" display toggle.
func _build_options_panel() -> void:
    var panel := PanelContainer.new()
    panel.add_theme_stylebox_override("panel", _panel_style())
    panel.anchor_top = 1.0
    panel.anchor_bottom = 1.0
    panel.offset_left = 16
    panel.offset_top = -80
    panel.offset_bottom = -24
    add_child(panel)

    var margin := _panel_margin()
    panel.add_child(margin)
    var col := VBoxContainer.new()
    col.add_theme_constant_override("separation", 6)
    margin.add_child(col)

    col.add_child(_section_title("Options"))
    _names_check = CheckBox.new()
    _names_check.text = "%s Names" % pack.area_noun
    _names_check.toggled.connect(_on_names_toggled)
    col.add_child(_names_check)


func _panel_margin() -> MarginContainer:
    var margin := MarginContainer.new()
    for side in ["left", "right", "top", "bottom"]:
        margin.add_theme_constant_override("margin_" + side, 12)
    return margin


## A subtle translucent panel with a thin border and rounded corners.
func _panel_style() -> StyleBoxFlat:
    var sb := StyleBoxFlat.new()
    sb.bg_color = Color(0.14, 0.17, 0.22, 0.85)
    sb.border_color = Color(0.42, 0.48, 0.56, 0.7)
    sb.set_border_width_all(1)
    sb.set_corner_radius_all(6)
    sb.set_content_margin_all(4)
    return sb


## A small, slightly muted section heading.
func _section_title(text: String) -> Label:
    var label := Label.new()
    label.text = text
    label.add_theme_font_size_override("font_size", 13)
    label.add_theme_color_override("font_color", Color(0.72, 0.78, 0.86))
    return label


## Naive English plural for a mode noun ("State" -> "States").
func _plural(noun: String) -> String:
    return noun + "s"


## main.gd supplies the display label; the prefix is the current mode's noun.
func set_prompt_name(label: String) -> void:
    _prompt_name = label
    var noun: String = pack.point_noun if _points_mode else pack.area_noun
    _prompt_label.text = "%s: %s" % [noun, label]


func set_score(score: int, total: int) -> void:
    _score_label.text = "Score: %d / %d" % [score, total]


## The set of enabled group ids (empty dict means all groups).
func enabled_groups() -> Dictionary:
    var out := {}
    for gid in _group_checks:
        if _group_checks[gid].button_pressed:
            out[gid] = true
    return out


func _on_areas_radio_toggled(pressed: bool) -> void:
    if pressed:
        _points_mode = false
        mode_toggled.emit(false)


func _on_points_radio_toggled(pressed: bool) -> void:
    if pressed:
        _points_mode = true
        mode_toggled.emit(true)


func _on_names_toggled(pressed: bool) -> void:
    show_names_toggled.emit(pressed)


func _on_group_toggled(_pressed: bool) -> void:
    # Never allow zero groups selected: re-check all if the last was turned off.
    var any := false
    for gid in _group_checks:
        if _group_checks[gid].button_pressed:
            any = true
            break
    if not any:
        for gid in _group_checks:
            _group_checks[gid].set_pressed_no_signal(true)
    groups_changed.emit(enabled_groups())


func _on_round_advanced(_code: String) -> void:
    _feedback_label.text = ""


func _on_answer_resolved(_code: String, correct: bool) -> void:
    if correct:
        _feedback_label.text = "Correct!"
        _feedback_label.add_theme_color_override("font_color", Color(0.4, 0.85, 0.45))
    else:
        _feedback_label.text = "Keep looking"
        _feedback_label.add_theme_color_override("font_color", Color(0.9, 0.5, 0.45))


func _on_game_over(score: int, total: int) -> void:
    _prompt_label.text = "Done!"
    _feedback_label.text = "Final score: %d / %d — click anywhere to play again" % [score, total]
    _feedback_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.6))

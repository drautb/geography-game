extends CanvasLayer
## Game HUD: prompt, score, feedback, mode radio buttons, and region-focus
## checkboxes. Purely presentational — reads EventBus signals and emits user
## choices. No Next button: after a correct answer any click advances.

signal mode_toggled(capital_mode: bool)
signal regions_changed(enabled: Dictionary)
signal show_names_toggled(show: bool)

const MapBuilderScript := preload("res://scripts/map_builder.gd")
const REGIONS := ["Northeast", "Midwest", "South", "West"]

var _prompt_label: Label
var _score_label: Label
var _feedback_label: Label
var _state_radio: CheckBox
var _capital_radio: CheckBox
var _region_checks := {}
var _names_check: CheckBox

var _prompt_name := ""
var _name_by_code := {}
var _capital_mode := false


func _ready() -> void:
    var font_big := 28
    var font_med := 20

    _prompt_label = Label.new()
    _prompt_label.add_theme_font_size_override("font_size", font_big)
    _prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _prompt_label.anchor_left = 0.0
    _prompt_label.anchor_right = 1.0
    _prompt_label.offset_top = 16
    _prompt_label.offset_bottom = 56
    add_child(_prompt_label)

    _score_label = Label.new()
    _score_label.add_theme_font_size_override("font_size", font_med)
    _score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    _score_label.anchor_left = 0.0
    _score_label.anchor_right = 1.0
    _score_label.offset_top = 16
    _score_label.offset_right = -20
    add_child(_score_label)

    _feedback_label = Label.new()
    _feedback_label.add_theme_font_size_override("font_size", font_med)
    _feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _feedback_label.anchor_left = 0.0
    _feedback_label.anchor_right = 1.0
    _feedback_label.offset_top = 60
    _feedback_label.offset_bottom = 90
    add_child(_feedback_label)

    # Grouped control panel (top-left): Mode radios + Focus-region checkboxes
    # inside a single subtly-bordered panel.
    var panel := PanelContainer.new()
    panel.position = Vector2(16, 14)
    panel.add_theme_stylebox_override("panel", _panel_style())
    add_child(panel)

    var margin := MarginContainer.new()
    for side in ["left", "right", "top", "bottom"]:
        margin.add_theme_constant_override("margin_" + side, 12)
    panel.add_child(margin)

    var col := VBoxContainer.new()
    col.add_theme_constant_override("separation", 6)
    margin.add_child(col)

    # Mode section.
    col.add_child(_section_title("Mode"))
    var group := ButtonGroup.new()
    _state_radio = CheckBox.new()
    _state_radio.text = "States"
    _state_radio.button_group = group
    _state_radio.button_pressed = true
    _state_radio.toggled.connect(_on_state_radio_toggled)
    col.add_child(_state_radio)
    _capital_radio = CheckBox.new()
    _capital_radio.text = "Capitals"
    _capital_radio.button_group = group
    _capital_radio.toggled.connect(_on_capital_radio_toggled)
    col.add_child(_capital_radio)

    col.add_child(HSeparator.new())

    # Regions section. Each row is a color swatch (the legend) + a checkbox.
    col.add_child(_section_title("Regions"))
    for region in REGIONS:
        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 6)
        var swatch := ColorRect.new()
        swatch.color = MapBuilderScript.REGION_COLORS.get(region, Color.WHITE)
        swatch.custom_minimum_size = Vector2(14, 14)
        swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        row.add_child(swatch)
        var cb := CheckBox.new()
        cb.text = region
        cb.button_pressed = true
        cb.toggled.connect(_on_region_toggled)
        row.add_child(cb)
        col.add_child(row)
        _region_checks[region] = cb

    _build_options_panel()

    EventBus.round_advanced.connect(_on_round_advanced)
    EventBus.answer_resolved.connect(_on_answer_resolved)
    EventBus.game_over.connect(_on_game_over)


## A separate panel anchored to the bottom-left holding display options.
func _build_options_panel() -> void:
    var panel := PanelContainer.new()
    panel.add_theme_stylebox_override("panel", _panel_style())
    panel.anchor_top = 1.0
    panel.anchor_bottom = 1.0
    panel.offset_left = 16
    panel.offset_top = -80
    panel.offset_bottom = -24
    add_child(panel)

    var margin := MarginContainer.new()
    for side in ["left", "right", "top", "bottom"]:
        margin.add_theme_constant_override("margin_" + side, 12)
    panel.add_child(margin)

    var col := VBoxContainer.new()
    col.add_theme_constant_override("separation", 6)
    margin.add_child(col)

    col.add_child(_section_title("Options"))
    _names_check = CheckBox.new()
    _names_check.text = "State Names"
    _names_check.toggled.connect(_on_names_toggled)
    col.add_child(_names_check)


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


## main.gd supplies the display label; the prefix reflects the current mode.
func set_prompt_name(label: String) -> void:
    _prompt_name = label
    if _capital_mode:
        _prompt_label.text = "Capital: %s" % label
    else:
        _prompt_label.text = "State: %s" % label


func set_name_lookup(lookup: Dictionary) -> void:
    _name_by_code = lookup


func set_score(score: int, total: int) -> void:
    _score_label.text = "Score: %d / %d" % [score, total]


## The set of enabled region names (empty dict means all regions).
func enabled_regions() -> Dictionary:
    var out := {}
    for region in _region_checks:
        if _region_checks[region].button_pressed:
            out[region] = true
    return out


func _on_state_radio_toggled(pressed: bool) -> void:
    if pressed:
        _capital_mode = false
        mode_toggled.emit(false)


func _on_capital_radio_toggled(pressed: bool) -> void:
    if pressed:
        _capital_mode = true
        mode_toggled.emit(true)


func _on_names_toggled(pressed: bool) -> void:
    show_names_toggled.emit(pressed)


func _on_region_toggled(_pressed: bool) -> void:
    # Never allow zero regions selected: re-check the last one turned off.
    var any := false
    for region in _region_checks:
        if _region_checks[region].button_pressed:
            any = true
            break
    if not any:
        # Re-enable all so the quiz is never empty.
        for region in _region_checks:
            _region_checks[region].set_pressed_no_signal(true)
    regions_changed.emit(enabled_regions())


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

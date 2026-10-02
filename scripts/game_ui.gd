extends CanvasLayer
## Game HUD for "find the state": prompt, score, feedback, and a Next control.
## Purely presentational — reads EventBus signals and tells the GameManager to
## advance. Built in code (no .tscn) to keep the UI versioned as a single script.

signal next_requested
signal mode_toggled(capital_mode: bool)

var _prompt_label: Label
var _score_label: Label
var _feedback_label: Label
var _next_button: Button
var _mode_button: Button

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

    _next_button = Button.new()
    _next_button.text = "Next"
    _next_button.anchor_left = 0.5
    _next_button.anchor_right = 0.5
    _next_button.anchor_top = 1.0
    _next_button.anchor_bottom = 1.0
    _next_button.offset_left = -50
    _next_button.offset_right = 50
    _next_button.offset_top = -56
    _next_button.offset_bottom = -20
    _next_button.visible = false
    _next_button.pressed.connect(_on_next_pressed)
    add_child(_next_button)

    _mode_button = Button.new()
    _mode_button.text = "Mode: States"
    _mode_button.offset_left = 20
    _mode_button.offset_top = 16
    _mode_button.offset_right = 180
    _mode_button.offset_bottom = 48
    _mode_button.pressed.connect(_on_mode_pressed)
    add_child(_mode_button)

    EventBus.round_advanced.connect(_on_round_advanced)
    EventBus.answer_resolved.connect(_on_answer_resolved)
    EventBus.game_over.connect(_on_game_over)


## main.gd supplies the display label for each prompt (state name, or capital in
## capitals mode). The instruction prefix reflects the current mode.
func set_prompt_name(label: String) -> void:
    _prompt_name = label
    if _capital_mode:
        _prompt_label.text = "Which state's capital is %s?" % label
    else:
        _prompt_label.text = "Find: %s" % label


## Supply the code -> full name map so wrong-answer feedback can name the clicked state.
func set_name_lookup(lookup: Dictionary) -> void:
    _name_by_code = lookup


func set_capital_mode(on: bool) -> void:
    _capital_mode = on
    if _mode_button != null:
        _mode_button.text = "Mode: Capitals" if on else "Mode: States"


func set_score(score: int, total: int) -> void:
    _score_label.text = "Score: %d / %d" % [score, total]


func _on_round_advanced(_code: String) -> void:
    _feedback_label.text = ""
    _next_button.visible = false


func _on_answer_resolved(code: String, correct: bool) -> void:
    if correct:
        _feedback_label.text = "Correct!"
        _feedback_label.add_theme_color_override("font_color", Color(0.4, 0.85, 0.45))
        _next_button.visible = true
    else:
        # Wrong guess: name what they clicked and invite another try. The round
        # stays open, so no Next button yet.
        var clicked_name: String = _name_by_code.get(code, code)
        _feedback_label.text = "That's %s — keep looking" % clicked_name
        _feedback_label.add_theme_color_override("font_color", Color(0.9, 0.5, 0.45))


func _on_game_over(score: int, total: int) -> void:
    _prompt_label.text = "Done!"
    _feedback_label.text = "Final score: %d / %d" % [score, total]
    _feedback_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.6))
    _next_button.text = "Play again"
    _next_button.visible = true


func _on_next_pressed() -> void:
    _next_button.text = "Next"
    next_requested.emit()


func _on_mode_pressed() -> void:
    set_capital_mode(not _capital_mode)
    mode_toggled.emit(_capital_mode)

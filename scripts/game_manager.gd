extends RefCounted
class_name GameManager
## State / capital quiz logic. Pure state + rules, no scene-tree coupling.
##
## Two modes:
##   STATE   — prompt a state name; click that state.
##   CAPITAL — prompt a capital city; click the state it is the capital of.
## In both modes the answer is a STATE click. Capital mode quizzes only the 50
## states that have capital data (DC has none). The player keeps guessing until
## correct; a round resolves only on a correct click; a point is awarded only for
## a first-try solve. Communicates outward only through EventBus signals.

enum Mode { STATE, CAPITAL }

var _states: Array[Dictionary] = []
var _capitals: Array[Dictionary] = []
var _region_by_code := {}
var _enabled_regions := {}  # region name -> true; empty means "all"
var _mode: int = Mode.STATE
var _queue: Array = []
var _index := -1
var _score := 0
var _total := 0
var _awaiting_advance := false
var _awaiting_restart := false
var _missed_this_round := false
var _solved := {}


## states: [{code, name, region}]; capitals: [{code, name, capital}].
func _init(states: Array, capitals: Array = []) -> void:
    for s in states:
        var region := String(s.get("region", ""))
        _states.append({"code": String(s["code"]), "name": String(s["name"]), "region": region})
        _region_by_code[String(s["code"])] = region
    for c in capitals:
        _capitals.append(
            {"code": String(c["code"]), "name": String(c["name"]), "capital": String(c["capital"])}
        )
    EventBus.state_clicked.connect(_on_state_clicked)


func set_mode(mode: int) -> void:
    _mode = mode


func mode() -> int:
    return _mode


## Set the enabled region names (e.g. {"West": true}). Empty = all regions.
func set_regions(regions: Dictionary) -> void:
    _enabled_regions = regions.duplicate()


func _region_enabled(code: String) -> bool:
    if _enabled_regions.is_empty():
        return true
    return _enabled_regions.get(_region_by_code.get(code, ""), false)


func start() -> void:
    var source: Array = _capitals if _mode == Mode.CAPITAL else _states
    _queue = []
    for item in source:
        if _region_enabled(String(item["code"])):
            _queue.append(item.duplicate(true))
    # Safety: never start an empty quiz (e.g. all regions unchecked). Fall back to all.
    if _queue.is_empty():
        for item in source:
            _queue.append(item.duplicate(true))
    _queue.shuffle()
    _total = _queue.size()
    _index = -1
    _score = 0
    _awaiting_advance = false
    _awaiting_restart = false
    _missed_this_round = false
    _solved = {}
    _advance()


func current_prompt() -> Dictionary:
    if _index < 0 or _index >= _queue.size():
        return {}
    return _queue[_index]


## Text to display for the current prompt: the capital in CAPITAL mode, else the
## state name.
func prompt_label() -> String:
    var p := current_prompt()
    if p.is_empty():
        return ""
    if _mode == Mode.CAPITAL:
        return String(p.get("capital", ""))
    return String(p.get("name", ""))


func score() -> int:
    return _score


func total() -> int:
    return _total


func _on_state_clicked(state_code: String) -> void:
    # While waiting to advance/restart, state clicks are ignored here; any click
    # (including empty space) advances via continue_game(), driven by main.gd.
    if _awaiting_advance or _awaiting_restart:
        return
    if _index < 0 or _index >= _queue.size():
        return
    var prompt: Dictionary = _queue[_index]
    var correct: bool = state_code == String(prompt["code"])
    if correct:
        # Award a point only for a first-try solve (no wrong guesses this round),
        # counted once per state. The player keeps guessing until correct, so an
        # unconditional point would make every score a perfect score.
        if not _missed_this_round and not _solved.has(String(prompt["code"])):
            _solved[String(prompt["code"])] = true
            _score += 1
        # Resolved: the next click anywhere advances to the next prompt.
        _awaiting_advance = true
    else:
        # Wrong guess: give feedback but stay on this state — do NOT lock or advance.
        _missed_this_round = true
    EventBus.answer_resolved.emit(state_code, correct)


## True when a correct answer or game-over is latched, waiting for any click.
func is_waiting() -> bool:
    return _awaiting_advance or _awaiting_restart


## Consume the "any click" that advances to the next prompt (or restarts after
## game over). Called by main.gd for clicks anywhere, including empty space.
func continue_game() -> void:
    if _awaiting_restart:
        _awaiting_restart = false
        start()
    elif _awaiting_advance:
        _awaiting_advance = false
        _advance()


func _advance() -> void:
    _index += 1
    _missed_this_round = false
    if _index >= _queue.size():
        _awaiting_restart = true
        EventBus.game_over.emit(_score, _total)
        return
    EventBus.round_advanced.emit(_queue[_index]["code"])

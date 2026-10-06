extends RefCounted
class_name GameManager
## Area / point quiz logic. Pure state + rules, no scene-tree coupling.
##
## Two modes:
##   AREAS  — prompt an area name; click that area.
##   POINTS — prompt a point (e.g. a capital city); click the area it belongs to.
## In both modes the answer is an AREA click. POINTS mode quizzes only areas that
## have point data. The player keeps guessing until correct; a round resolves only
## on a correct click; a point is awarded only for a first-try solve. Communicates
## outward only through EventBus signals.

enum Mode { AREAS, POINTS }

var _areas: Array[Dictionary] = []
var _points: Array[Dictionary] = []
var _group_by_code := {}
var _enabled_groups := {}  # group id -> true; empty means "all"
var _mode: int = Mode.AREAS
var _queue: Array = []
var _index := -1
var _score := 0
var _total := 0
var _awaiting_advance := false
var _awaiting_restart := false
var _missed_this_round := false
var _solved := {}


## areas: [{code, name, group}]; points: [{code, name, capital}].
func _init(areas: Array, points: Array = []) -> void:
    for a in areas:
        var group := String(a.get("group", ""))
        _areas.append({"code": String(a["code"]), "name": String(a["name"]), "group": group})
        _group_by_code[String(a["code"])] = group
    for p in points:
        _points.append(
            {"code": String(p["code"]), "name": String(p["name"]), "capital": String(p["capital"])}
        )
    EventBus.area_clicked.connect(_on_area_clicked)


## Disconnect from EventBus so this manager can be freed (RefCounted won't be
## released while a signal connection holds a reference to it).
func dispose() -> void:
    if EventBus.area_clicked.is_connected(_on_area_clicked):
        EventBus.area_clicked.disconnect(_on_area_clicked)


func set_mode(mode: int) -> void:
    _mode = mode


func mode() -> int:
    return _mode


## Set the enabled group ids (e.g. {"West": true}). Empty = all groups.
func set_groups(groups: Dictionary) -> void:
    _enabled_groups = groups.duplicate()


func _group_enabled(code: String) -> bool:
    if _enabled_groups.is_empty():
        return true
    return _enabled_groups.get(_group_by_code.get(code, ""), false)


func start() -> void:
    var source: Array = _points if _mode == Mode.POINTS else _areas
    _queue = []
    for item in source:
        if _group_enabled(String(item["code"])):
            _queue.append(item.duplicate(true))
    # Safety: never start an empty quiz (e.g. all groups unchecked). Fall back to all.
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


## Text to display for the current prompt: the point/capital in POINTS mode, else
## the area name.
func prompt_label() -> String:
    var p := current_prompt()
    if p.is_empty():
        return ""
    if _mode == Mode.POINTS:
        return String(p.get("capital", ""))
    return String(p.get("name", ""))


func score() -> int:
    return _score


func total() -> int:
    return _total


func _on_area_clicked(area_code: String) -> void:
    # While waiting to advance/restart, area clicks are ignored here; any click
    # (including empty space) advances via continue_game(), driven by main.gd.
    if _awaiting_advance or _awaiting_restart:
        return
    if _index < 0 or _index >= _queue.size():
        return
    var prompt: Dictionary = _queue[_index]
    var correct: bool = area_code == String(prompt["code"])
    if correct:
        # Award a point only for a first-try solve (no wrong guesses this round),
        # counted once per area. The player keeps guessing until correct, so an
        # unconditional point would make every score a perfect score.
        if not _missed_this_round and not _solved.has(String(prompt["code"])):
            _solved[String(prompt["code"])] = true
            _score += 1
        # Resolved: the next click anywhere advances to the next prompt.
        _awaiting_advance = true
    else:
        # Wrong guess: give feedback but stay on this area — do NOT lock or advance.
        _missed_this_round = true
    EventBus.answer_resolved.emit(area_code, correct)


## True when a correct answer or game-over is latched, waiting for any click.
func is_waiting() -> bool:
    return _awaiting_advance or _awaiting_restart


## True only when a correct answer is latched (round auto-advances); false at
## game over, which waits for a click to restart.
func is_awaiting_advance() -> bool:
    return _awaiting_advance


## True only at game over, waiting for a click to restart.
func is_awaiting_restart() -> bool:
    return _awaiting_restart


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

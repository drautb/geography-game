extends RefCounted
class_name GameManager
## "Find the state" game logic. Pure state + rules, no scene-tree coupling.
##
## Owns a shuffled queue of prompt states. The player keeps guessing until they
## click the correct state; a round resolves only on a correct click. A point is
## awarded only for a first-try solve. Communicates outward only through EventBus
## signals so the UI and map stay decoupled.

var _states: Array[Dictionary] = []
var _queue: Array = []
var _index := -1
var _score := 0
var _total := 0
var _answered := false
var _missed_this_round := false
var _solved := {}


## states: Array of {code, name} dictionaries (from MapData / the GeoJSON properties).
func _init(states: Array) -> void:
    for s in states:
        _states.append({"code": String(s["code"]), "name": String(s["name"])})
    _total = _states.size()
    EventBus.state_clicked.connect(_on_state_clicked)


func start() -> void:
    _queue = _states.duplicate(true)
    _queue.shuffle()
    _index = -1
    _score = 0
    _answered = false
    _solved = {}
    _advance()


func current_prompt() -> Dictionary:
    if _index < 0 or _index >= _queue.size():
        return {}
    return _queue[_index]


func score() -> int:
    return _score


func total() -> int:
    return _total


func _on_state_clicked(state_code: String) -> void:
    if _answered or _index < 0 or _index >= _queue.size():
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
        _answered = true
    else:
        # Wrong guess: give feedback but stay on this state — do NOT lock or advance.
        _missed_this_round = true
    EventBus.answer_resolved.emit(state_code, correct)


## Called by the UI (after showing feedback) to move to the next prompt.
func next() -> void:
    _advance()


func _advance() -> void:
    _index += 1
    _answered = false
    _missed_this_round = false
    if _index >= _queue.size():
        EventBus.game_over.emit(_score, _total)
        return
    EventBus.round_advanced.emit(_queue[_index]["code"])

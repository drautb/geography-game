extends RefCounted
class_name GameManager
## "Find the state" game logic. Pure state + rules, no scene-tree coupling.
##
## Owns a shuffled queue of prompt states. On each EventBus.state_clicked, resolves
## the answer against the current prompt, updates the score, and advances. Communicates
## outward only through EventBus signals so the UI and map stay decoupled.

var _queue: Array[Dictionary] = []
var _index := -1
var _score := 0
var _total := 0
var _answered := false


## states: Array of {code, name} dictionaries (from MapData / the GeoJSON properties).
func _init(states: Array) -> void:
    for s in states:
        _queue.append({"code": String(s["code"]), "name": String(s["name"])})
    _queue.shuffle()
    _total = _queue.size()
    EventBus.state_clicked.connect(_on_state_clicked)


func start() -> void:
    _index = -1
    _score = 0
    _answered = false
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
        _score += 1
    _answered = true
    EventBus.answer_resolved.emit(state_code, correct)


## Called by the UI (after showing feedback) to move to the next prompt.
func next() -> void:
    _advance()


func _advance() -> void:
    _index += 1
    _answered = false
    if _index >= _queue.size():
        EventBus.game_over.emit(_score, _total)
        return
    EventBus.round_advanced.emit(_queue[_index]["code"])

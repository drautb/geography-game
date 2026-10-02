extends Node
## Drives the REAL main scene to verify region filtering: enable only "West",
## restart via the game, and confirm every queued prompt is a West state.

const MainScene := preload("res://scenes/main.tscn")

var _frames := 0
var _main: Node
var _west := ["AZ", "CO", "ID", "MT", "NV", "NM", "UT", "WY", "AK", "CA", "HI", "OR", "WA"]


func _ready() -> void:
    _main = MainScene.instantiate()
    add_child(_main)


func _process(_delta: float) -> void:
    _frames += 1
    if _frames == 4:
        # Restrict to the West region only, then restart.
        _main._game.set_regions({"West": true})
        _main._game.start()
    if _frames == 6:
        # Walk the whole queue, verifying every entry is a West state.
        var all_west := true
        var codes := []
        var g = _main._game
        # Peek the internal queue via current_prompt + advance (non-destructive-ish).
        var seen := {}
        for i in 60:
            var p = g.current_prompt()
            if p.is_empty():
                break
            var code = String(p.get("code"))
            if seen.has(code):
                break
            seen[code] = true
            codes.append(code)
            if not _west.has(code):
                all_west = false
            g._awaiting_advance = true
            g.continue_game()
        print("queued=%d all_west=%s codes=%s" % [codes.size(), all_west, str(codes)])
        get_tree().quit()

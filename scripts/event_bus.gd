extends Node
## Global event bus for decoupled communication between game systems.
## Autoloaded as "EventBus".

## Emitted when the player clicks an area. Payload: the area's code (e.g. "TX").
signal area_clicked(area_code: String)

## Emitted by the GameManager when a round's answer is resolved.
signal answer_resolved(area_code: String, correct: bool)

## Emitted when the GameManager advances to a new prompt. Payload: the prompt area code.
signal round_advanced(prompt_area_code: String)

## Emitted when the current game is over (all prompts exhausted). Payload: final score.
signal game_over(score: int, total: int)

extends Node
## Global event bus for decoupled communication between game systems.
## Autoloaded as "EventBus".

## Emitted when the player clicks a state region. Payload: the state's postal code (e.g. "TX").
signal state_clicked(state_code: String)

## Emitted by the GameManager when a round's answer is resolved.
signal answer_resolved(state_code: String, correct: bool)

## Emitted when the GameManager advances to a new prompt.
signal round_advanced(prompt_state_code: String)

## Emitted when the current game is over (all prompts exhausted). Payload: final score.
signal game_over(score: int, total: int)

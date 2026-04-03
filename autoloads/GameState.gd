extends Node

## Autoload: GameState
## Global state for the interrogation: tracks revealed clues (RF16) and detected lies (RF17).
## Communicates state changes via signals so any scene can react without direct coupling.

## Emitted when a new clue is revealed by the NPC. (RF16)
signal clue_added(clue_text: String)
## Emitted when the AI flags a lie in the NPC's dialogue. (RF17)
signal lie_detected

## All clues revealed so far in the current interrogation session.
var revealed_clues: Array[String] = []

## Total number of lies detected in the current session. (RF17)
var lies_detected_count: int = 0

## True if at least one lie has been detected this session. (RF17)
var any_lie_detected: bool = false


## Processes an AIResponse and updates global state accordingly.
## Call this after receiving a validated response from AIManager.
func process_response(response: RefCounted) -> void:
	_check_clue(response)
	_check_lie(response)


## Resets all state for a new interrogation session.
func reset() -> void:
	revealed_clues.clear()
	lies_detected_count = 0
	any_lie_detected = false
	print("GameState: Session reset.")


## Returns a formatted summary of all clues revealed so far.
func get_clues_summary() -> String:
	if revealed_clues.is_empty():
		return "No clues revealed yet."
	var lines: Array[String] = []
	for i: int in range(revealed_clues.size()):
		lines.append("- %s" % revealed_clues[i])
	return "\n".join(lines)


## Checks if a new clue was revealed and registers it. (RF16)
func _check_clue(response: RefCounted) -> void:
	var clue: Variant = response.get("clue_revealed")
	if clue == null or not clue is String:
		return
	var clue_text: String = clue as String
	if clue_text.is_empty():
		return
	if clue_text in revealed_clues:
		return

	revealed_clues.append(clue_text)
	print("GameState: New clue revealed — '%s'." % clue_text)
	clue_added.emit(clue_text)


## Checks if the NPC lied and increments the counter. (RF17)
func _check_lie(response: RefCounted) -> void:
	var lied: Variant = response.get("lies_detected")
	if not lied is bool:
		return
	if not (lied as bool):
		return

	lies_detected_count += 1
	any_lie_detected = true
	print("GameState: Lie detected (total: %d)." % lies_detected_count)
	lie_detected.emit()

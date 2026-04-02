extends RefCounted

## Data class representing one validated response from the AI NPC. (RF15)
## All fields map directly to the keys defined in response_schema.json.

## The NPC's spoken dialogue to display in the chat history.
var dialogue: String = ""

## The NPC's emotional state, used to drive sprite/animation changes.
## Valid values: "neutral", "confident", "nervous", "angry", "defensive", "afraid"
var emotion_state: String = "neutral"

## True if the NPC's dialogue contains a direct lie.
var lies_detected: bool = false

## A short description of the clue revealed, or null if none was revealed.
var clue_revealed: Variant = null


## Creates and returns an AIResponse from a validated Dictionary.
## Returns null if the dictionary is missing required fields.
static func from_dict(data: Dictionary) -> RefCounted:
	var response: RefCounted = new()
	response.dialogue = data.get("dialogue", "") as String
	response.emotion_state = data.get("emotion_state", "neutral") as String
	response.lies_detected = data.get("lies_detected", false) as bool
	response.clue_revealed = data.get("clue_revealed", null)
	return response


## Prints all fields to the Godot console for Sprint 1 verification.
func debug_print() -> void:
	print("--- AIResponse ---")
	print("  dialogue:       ", dialogue)
	print("  emotion_state:  ", emotion_state)
	print("  lies_detected:  ", lies_detected)
	print("  clue_revealed:  ", clue_revealed if clue_revealed != null else "(none)")
	print("------------------")

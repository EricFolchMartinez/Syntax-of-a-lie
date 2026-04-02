extends Node

func _ready() -> void:
	var response = await AIManager.send_message("Where were you the night Eleanor disappeared?")
	if response == null:
		print("TEST: Request failed.")
		return

	print("TEST OK")
	print("dialogue: ", response.dialogue)
	print("emotion_state: ", response.emotion_state)
	print("lies_detected: ", response.lies_detected)
	print("clue_revealed: ", response.clue_revealed)
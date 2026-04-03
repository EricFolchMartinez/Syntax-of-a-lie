extends Control

## MainGame: root script for the main interrogation scene.
## Handles the chat UI: player input (RF01), chat history display (RF02),
## and wires up signals from AIManager.

# --- Node references (assigned via @export or found in _ready) ---
@export var chat_history: RichTextLabel
@export var input_field: LineEdit
@export var send_button: Button
@export var thinking_label: Label
@export var npc_texture: TextureRect
@export var typewriter: Node
@export var emotion_mapper: Node


func _ready() -> void:
	# If the player selected Local mode, make sure the local server is up.
	if ModeManager.is_local():
		if not LocalServerManager.is_running():
			LocalServerManager.start_server()
		await LocalServerManager.wait_for_server()

	# Connect the send button and LineEdit submit to the same handler.
	send_button.pressed.connect(_on_send_pressed)
	input_field.text_submitted.connect(_on_text_submitted)

	# Connect AIManager signals for UI state.
	AIManager.request_started.connect(_on_request_started)
	AIManager.request_ended.connect(_on_request_ended)
	AIManager.response_received.connect(_on_response_received)

	# Connect GameState signals to notify player of clues and lies. (RF16, RF17)
	GameState.clue_added.connect(_on_clue_added)
	GameState.lie_detected.connect(_on_lie_detected)

	# Hide the thinking indicator initially.
	thinking_label.visible = false

	# Show a welcome line in the history.
	_append_to_history("SYSTEM", "Interrogation started. Viktor Hale is waiting.")


## Called when the player presses Enter in the LineEdit (RF01).
func _on_text_submitted(text: String) -> void:
	_submit_input(text)


## Called when the player clicks the Send button (RF01).
func _on_send_pressed() -> void:
	_submit_input(input_field.text)


func _submit_input(text: String) -> void:
	var trimmed: String = text.strip_edges()
	if trimmed.is_empty():
		return
	_append_to_history("YOU", trimmed)
	input_field.clear()
	AIManager.send_message(trimmed)


## Appends a formatted line to the chat history and scrolls to the bottom (RF02).
func _append_to_history(speaker: String, text: String) -> void:
	chat_history.append_text("[b]%s:[/b] %s\n" % [speaker, text])
	# Scroll to the last line so the latest message is always visible (RF02).
	await get_tree().process_frame
	chat_history.scroll_to_line(chat_history.get_line_count() - 1)


## Disables input and starts the thinking animation while the AI processes. (RF03)
func _on_request_started() -> void:
	input_field.editable = false
	send_button.disabled = true
	thinking_label.start()


## Re-enables input and stops the thinking animation once the AI has responded. (RF03)
func _on_request_ended() -> void:
	input_field.editable = true
	send_button.disabled = false
	thinking_label.stop()
	input_field.grab_focus()


## Notifies the player that a new clue has been found. (RF16)
func _on_clue_added(clue_text: String) -> void:
	_append_to_history("CLUE FOUND", "[ %s ]" % clue_text)


## Notifies the player that a lie was detected. (RF17)
func _on_lie_detected() -> void:
	_append_to_history("SYSTEM", "Inconsistency detected in Viktor's statement.")


## Receives the validated AIResponse, updates the NPC sprite and types the dialogue. (RF04 + Typewriter)
func _on_response_received(response: RefCounted) -> void:
	var dialogue: String = response.get("dialogue") as String
	var emotion: String = response.get("emotion_state") as String

	# Update NPC sprite based on emotion_state. (RF04)
	if emotion_mapper != null:
		emotion_mapper.set_emotion(emotion)

	# Update global game state (clues, lies). (RF16, RF17)
	GameState.process_response(response)

	# Type dialogue character by character with SFX.
	if typewriter != null:
		typewriter.type_text(dialogue, "VIKTOR")
	else:
		_append_to_history("VIKTOR", dialogue)

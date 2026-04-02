extends Node

## Autoload: ContextBuilder
## Assembles the full API payload: System Prompt + clue state flags + sliding memory window.
## Accesses FileLoader via the node tree to avoid cross-autoload static-scope issues.

## Maximum number of conversation turns (user + assistant pairs) to keep in memory.
## Each turn = 2 messages. 10 turns = 20 messages max in the sliding window.
const MAX_MEMORY_TURNS: int = 10

## Holds the conversation history as an array of message dictionaries.
## Each entry: { "role": "user"|"assistant", "content": String }
var _message_history: Array[Dictionary] = []

## Current clue flags. Keys are clue identifiers, values are booleans.
## Add new clues here as the game progresses.
var clue_flags: Dictionary = {
	"basement_visit_mentioned": false,
	"director_caldwell_mentioned": false,
	"documents_destroyed_mentioned": false,
	"incinerator_mentioned": false,
}

# Reference to FileLoader resolved at runtime via the scene tree.
var _file_loader: Node = null


func _ready() -> void:
	_file_loader = get_node("/root/FileLoader")


## Appends a new user message to the history and trims if needed.
func add_user_message(content: String) -> void:
	_message_history.append({"role": "user", "content": content})
	_trim_history()


## Appends a new assistant message to the history and trims if needed.
func add_assistant_message(content: String) -> void:
	_message_history.append({"role": "assistant", "content": content})
	_trim_history()


## Sets a clue flag to true when it has been revealed.
func set_clue_flag(clue_key: String) -> void:
	if clue_flags.has(clue_key):
		clue_flags[clue_key] = true
	else:
		push_warning("ContextBuilder: Unknown clue key '%s'." % clue_key)


## Builds and returns the full messages array ready to be sent to the API.
## Structure: [system message] + [conversation history]
func build_payload() -> Array[Dictionary]:
	var system_content: String = _build_system_content()

	var payload: Array[Dictionary] = []
	payload.append({"role": "system", "content": system_content})
	payload.append_array(_message_history)
	return payload


## Clears the entire conversation history (e.g. when starting a new interrogation).
func clear_history() -> void:
	_message_history.clear()


## Returns the number of messages currently in memory.
func get_history_size() -> int:
	return _message_history.size()


## Builds the system message content by combining the base prompt with active clue flags.
func _build_system_content() -> String:
	var base_prompt: String = _file_loader.get("system_prompt") as String

	var active_flags: Array[String] = []
	for key: String in clue_flags:
		if clue_flags[key]:
			active_flags.append(key)

	if active_flags.is_empty():
		return base_prompt

	var flags_block: String = "\n\nCURRENT INVESTIGATION STATE (clues already revealed to the player):\n"
	for flag: String in active_flags:
		flags_block += "- %s\n" % flag.replace("_", " ").capitalize()

	return base_prompt + flags_block


## Trims the history to stay within MAX_MEMORY_TURNS conversation turns.
## Removes the oldest user+assistant pairs first.
func _trim_history() -> void:
	var max_messages: int = MAX_MEMORY_TURNS * 2
	while _message_history.size() > max_messages:
		_message_history.pop_front()

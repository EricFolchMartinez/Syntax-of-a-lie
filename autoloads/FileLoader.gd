extends Node

## Autoload: FileLoader
## Reads and exposes the System Prompt and JSON response schema from local files.
## Must be registered in Project Settings > Autoload before use.

const SYSTEM_PROMPT_PATH: String = "res://data/system_prompt.txt"
const RESPONSE_SCHEMA_PATH: String = "res://data/response_schema.json"

var system_prompt: String = ""
var response_schema: Dictionary = {}

## Emitted once both files are loaded successfully on _ready.
signal files_loaded
## Emitted if any file fails to load, with the path that failed.
signal file_load_failed(path: String)


func _ready() -> void:
	_load_system_prompt()
	_load_response_schema()


func _load_system_prompt() -> void:
	if not FileAccess.file_exists(SYSTEM_PROMPT_PATH):
		push_error("FileLoader: System prompt not found at '%s'" % SYSTEM_PROMPT_PATH)
		file_load_failed.emit(SYSTEM_PROMPT_PATH)
		return

	var file: FileAccess = FileAccess.open(SYSTEM_PROMPT_PATH, FileAccess.READ)
	if file == null:
		push_error("FileLoader: Could not open system prompt. Error: %s" % FileAccess.get_open_error())
		file_load_failed.emit(SYSTEM_PROMPT_PATH)
		return

	system_prompt = file.get_as_text().strip_edges()
	file.close()
	print("FileLoader: System prompt loaded (%d chars)." % system_prompt.length())


func _load_response_schema() -> void:
	if not FileAccess.file_exists(RESPONSE_SCHEMA_PATH):
		push_error("FileLoader: Response schema not found at '%s'" % RESPONSE_SCHEMA_PATH)
		file_load_failed.emit(RESPONSE_SCHEMA_PATH)
		return

	var file: FileAccess = FileAccess.open(RESPONSE_SCHEMA_PATH, FileAccess.READ)
	if file == null:
		push_error("FileLoader: Could not open response schema. Error: %s" % FileAccess.get_open_error())
		file_load_failed.emit(RESPONSE_SCHEMA_PATH)
		return

	var raw_text: String = file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(raw_text)
	if parsed == null or not parsed is Dictionary:
		push_error("FileLoader: Response schema is not valid JSON.")
		file_load_failed.emit(RESPONSE_SCHEMA_PATH)
		return

	response_schema = parsed as Dictionary
	print("FileLoader: Response schema loaded (%d fields)." % response_schema.get("properties", {}).size())

	files_loaded.emit()


## Returns true only if both files were loaded successfully.
func is_ready() -> bool:
	return system_prompt.length() > 0 and not response_schema.is_empty()

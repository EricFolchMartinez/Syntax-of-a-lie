extends Node

# Explicit preload needed because Autoloads are compiled before class_name globals are registered.
const AIResponse: GDScript = preload("res://scripts/AIResponse.gd")

## Autoload: AIManager
## Manages all communication with the Cloud AI API.
## Uses HTTPRequest with await + signals to guarantee zero freezing of the main thread (RNF01).
## Depends on FileLoader and ContextBuilder being registered as Autoloads before this one.

const CONFIG_PATH: String = "res://config/api_config.cfg"
const SECRETS_PATH: String = "res://config/secrets.cfg"

## Emitted when a full, successful AI response is received, validated, and mapped. (RF15)
signal response_received(response: AIResponse)
## Emitted when any unrecoverable error occurs (network, timeout, etc.).
signal request_failed(error_message: String)
## Emitted when a request starts, so the UI can show a "thinking" indicator.
signal request_started
## Emitted when a request ends (success or failure), so the UI can hide the indicator.
signal request_ended

var _http_request: HTTPRequest
var _api_endpoint: String = ""
var _api_model: String = ""
var _api_key: String = ""
var _is_requesting: bool = false

# Reference to ContextBuilder resolved at runtime via the scene tree.
var _context_builder: Node = null


func _ready() -> void:
	_context_builder = get_node("/root/ContextBuilder")
	_load_config()
	_setup_http_request()


func _load_config() -> void:
	var config: ConfigFile = ConfigFile.new()
	var err: Error = config.load(CONFIG_PATH)
	if err != OK:
		push_error("AIManager: Could not load config file at '%s'. Error: %d" % [CONFIG_PATH, err])
		return

	_api_endpoint = config.get_value("api", "endpoint", "")
	_api_model = config.get_value("api", "model", "")

	if _api_endpoint.is_empty():
		push_error("AIManager: API endpoint is not configured in '%s'." % CONFIG_PATH)

	_load_secrets()

	# Never print the API key, even partially.
	print("AIManager: Config loaded. Endpoint: %s | Model: %s" % [_api_endpoint, _api_model])


func _load_secrets() -> void:
	var secrets: ConfigFile = ConfigFile.new()
	var err: Error = secrets.load(SECRETS_PATH)
	if err != OK:
		push_error("AIManager: secrets.cfg not found at '%s'. Copy secrets.cfg.example and fill in your key." % SECRETS_PATH)
		return

	_api_key = secrets.get_value("secrets", "api_key", "")

	if _api_key.is_empty():
		push_warning("AIManager: API key is empty in secrets.cfg. Requests will fail.")


func _setup_http_request() -> void:
	_http_request = HTTPRequest.new()
	_http_request.timeout = 30.0
	add_child(_http_request)


## Public entry point. Sends the player's message to the AI and awaits the response.
## Returns a populated AIResponse on success, or null on failure. (RF15)
func send_message(player_input: String) -> AIResponse:
	if _is_requesting:
		push_warning("AIManager: A request is already in progress. Ignoring new request.")
		return null

	if _api_endpoint.is_empty() or _api_key.is_empty():
		var err_msg: String = "AIManager: Cannot send request — endpoint or API key is missing."
		push_error(err_msg)
		request_failed.emit(err_msg)
		return null

	_is_requesting = true
	request_started.emit()

	_context_builder.add_user_message(player_input)
	var messages: Array[Dictionary] = _context_builder.build_payload()

	var raw_data: Dictionary = await _perform_request(messages)

	var ai_response: AIResponse = null
	if not raw_data.is_empty():
		ai_response = AIResponse.from_dict(raw_data)
		_context_builder.add_assistant_message(ai_response.dialogue)
		ai_response.debug_print()
		response_received.emit(ai_response)
	else:
		request_failed.emit("AIManager: Request returned empty or invalid data.")

	_is_requesting = false
	request_ended.emit()
	return ai_response


## Performs the actual async HTTP POST request and returns the raw parsed JSON body.
func _perform_request(messages: Array[Dictionary]) -> Dictionary:
	var headers: PackedStringArray = PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer %s" % _api_key,
	])

	# response_format forces the API to return pure JSON with no surrounding text.
	# This is the "Structured Outputs / JSON Mode" supported by OpenAI and Groq.
	var body: Dictionary = {
		"model": _api_model,
		"messages": messages,
		"response_format": {"type": "json_object"},
	}

	var body_json: String = JSON.stringify(body)
	var err: Error = _http_request.request(
		_api_endpoint,
		headers,
		HTTPClient.METHOD_POST,
		body_json
	)

	if err != OK:
		push_error("AIManager: Failed to initiate HTTP request. Error: %d" % err)
		return {}

	var response: Array = await _http_request.request_completed

	var result_code: int = response[0]
	var http_code: int = response[1]
	var body_bytes: PackedByteArray = response[3]

	if result_code != HTTPRequest.RESULT_SUCCESS:
		push_error("AIManager: HTTP request failed. Result code: %d" % result_code)
		return {}

	if http_code < 200 or http_code >= 300:
		push_error("AIManager: API returned HTTP %d." % http_code)
		return {}

	var raw_body: String = body_bytes.get_string_from_utf8()
	return _extract_content_from_response(raw_body)


## Extracts the message content string from the raw OpenAI-compatible API response envelope,
## then strictly validates and parses the inner JSON payload from the AI. (RF14)
func _extract_content_from_response(raw_body: String) -> Dictionary:
	var envelope: Variant = JSON.parse_string(raw_body)
	if envelope == null or not envelope is Dictionary:
		push_error("AIManager: Could not parse API response envelope.")
		return {}

	var choices: Variant = envelope.get("choices", null)
	if choices == null or not choices is Array or (choices as Array).is_empty():
		push_error("AIManager: API response has no 'choices'.")
		return {}

	var first_choice: Variant = (choices as Array)[0]
	if not first_choice is Dictionary:
		push_error("AIManager: 'choices[0]' is not a Dictionary.")
		return {}

	var message: Variant = (first_choice as Dictionary).get("message", null)
	if not message is Dictionary:
		push_error("AIManager: 'choices[0].message' is not a Dictionary.")
		return {}

	var content: Variant = (message as Dictionary).get("content", null)
	if not content is String:
		push_error("AIManager: 'choices[0].message.content' is not a String.")
		return {}

	return _validate_ai_response(content as String)


## Strictly parses and validates the AI's inner JSON payload. (RF14)
## Returns a validated Dictionary on success, or an empty Dictionary on any validation failure.
func _validate_ai_response(content: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(content)

	if parsed == null:
		push_error("AIManager: AI response content is not valid JSON. Raw: %s" % content)
		return {}

	if not parsed is Dictionary:
		push_error("AIManager: AI response JSON is not an object. Got: %s" % typeof(parsed))
		return {}

	var data: Dictionary = parsed as Dictionary

	# Validate required field: dialogue (String)
	if not data.has("dialogue") or not data["dialogue"] is String:
		push_error("AIManager: Missing or invalid 'dialogue' field in AI response.")
		return {}

	# Validate required field: emotion_state (String)
	if not data.has("emotion_state") or not data["emotion_state"] is String:
		push_error("AIManager: Missing or invalid 'emotion_state' field in AI response.")
		return {}

	# Validate required field: lies_detected (bool)
	if not data.has("lies_detected") or not data["lies_detected"] is bool:
		push_error("AIManager: Missing or invalid 'lies_detected' field in AI response.")
		return {}

	# Validate required field: clue_revealed (String or null)
	if not data.has("clue_revealed"):
		push_error("AIManager: Missing 'clue_revealed' field in AI response.")
		return {}
	var clue: Variant = data["clue_revealed"]
	if clue != null and not clue is String:
		push_error("AIManager: 'clue_revealed' must be a String or null. Got: %s" % typeof(clue))
		return {}

	print("AIManager: JSON validated successfully.")
	return data


## Allows runtime injection of the API key (used in Sprint 4 for secure key entry).
func set_api_key(key: String) -> void:
	_api_key = key

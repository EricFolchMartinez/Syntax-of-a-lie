extends Node

## Autoload: ModelDownloader
## Downloads the .GGUF model file from a remote URL to the user's local storage.
## Uses HTTPRequest.download_file to write directly to disk — never to RAM.
## This is critical: a 1.5-2GB model loaded into RAM would crash on low-end machines.

const LOCAL_CONFIG_PATH: String = "res://config/local_config.cfg"

## Emitted repeatedly during download with current progress values.
signal download_progress(bytes_downloaded: int, total_bytes: int)
## Emitted once the model file has been fully saved to disk.
signal download_completed(save_path: String)
## Emitted if the download fails for any reason.
signal download_failed(error_message: String)

var _http_request: HTTPRequest = null
var _model_url: String = ""
var _model_local_path: String = ""
var _is_downloading: bool = false


func _ready() -> void:
	_load_config()


func _load_config() -> void:
	var config: ConfigFile = ConfigFile.new()
	var err: Error = config.load(LOCAL_CONFIG_PATH)
	if err != OK:
		push_error("ModelDownloader: Could not load local config. Error: %d" % err)
		return
	_model_url = config.get_value("model", "download_url", "")
	_model_local_path = config.get_value("model", "local_path", "user://models/model.gguf")


## Returns true if the model file already exists on disk.
func is_model_downloaded() -> bool:
	return FileAccess.file_exists(_model_local_path)


## Returns the absolute filesystem path where the model is (or will be) saved.
func get_model_path() -> String:
	return ProjectSettings.globalize_path(_model_local_path)


## Starts downloading the model. Does nothing if a download is already running.
## Connect to download_progress, download_completed, and download_failed before calling.
func start_download() -> void:
	if _is_downloading:
		push_warning("ModelDownloader: A download is already in progress.")
		return

	if _model_url.is_empty():
		var msg: String = "ModelDownloader: No download URL configured in local_config.cfg."
		push_error(msg)
		download_failed.emit(msg)
		return

	_ensure_model_directory()

	_http_request = HTTPRequest.new()
	add_child(_http_request)

	# CRITICAL: assign download_file so Godot streams bytes directly to disk.
	# Without this, the full file is buffered in RAM before saving, crashing low-end PCs.
	_http_request.download_file = _model_local_path
	_http_request.use_threads = true

	_http_request.request_completed.connect(_on_request_completed)

	var err: Error = _http_request.request(_model_url)
	if err != OK:
		push_error("ModelDownloader: Failed to start HTTP request. Error: %d" % err)
		_cleanup()
		download_failed.emit("Failed to initiate download request.")
		return

	_is_downloading = true
	print("ModelDownloader: Download started from '%s' -> '%s'" % [_model_url, _model_local_path])


## Cancels an in-progress download and removes the partial file.
func cancel_download() -> void:
	if not _is_downloading:
		return
	_http_request.cancel_request()
	_cleanup()
	if FileAccess.file_exists(_model_local_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_model_local_path))
	print("ModelDownloader: Download cancelled.")


## Called every frame to report progress. Connect the UI to download_progress signal instead.
func _process(_delta: float) -> void:
	if not _is_downloading or _http_request == null:
		return
	var downloaded: int = _http_request.get_downloaded_bytes()
	var total: int = _http_request.get_body_size()
	if total > 0:
		download_progress.emit(downloaded, total)


func _on_request_completed(result: int, http_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_is_downloading = false

	if result != HTTPRequest.RESULT_SUCCESS:
		var msg: String = "ModelDownloader: Download failed. Result code: %d" % result
		push_error(msg)
		_cleanup()
		download_failed.emit(msg)
		return

	if http_code < 200 or http_code >= 300:
		var msg: String = "ModelDownloader: Server returned HTTP %d." % http_code
		push_error(msg)
		_cleanup()
		download_failed.emit(msg)
		return

	_cleanup()
	print("ModelDownloader: Download complete. Model saved at '%s'." % _model_local_path)
	download_completed.emit(_model_local_path)


func _cleanup() -> void:
	_is_downloading = false
	if _http_request != null and is_instance_valid(_http_request):
		_http_request.queue_free()
		_http_request = null


func _ensure_model_directory() -> void:
	var dir_path: String = _model_local_path.get_base_dir()
	var abs_path: String = ProjectSettings.globalize_path(dir_path)
	if not DirAccess.dir_exists_absolute(abs_path):
		DirAccess.make_dir_recursive_absolute(abs_path)

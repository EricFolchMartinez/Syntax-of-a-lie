extends Node

## Autoload: LocalServerManager
## Manages the full lifecycle of the local llama-server process:
## launch (RF08), OS path resolution (RNF11), RAM flags (RNF03),
## health-check (RF09), and shutdown on game close (RF10).

const LOCAL_CONFIG_PATH: String = "res://config/local_config.cfg"

## Emitted when llama-server has passed the health-check and is ready to accept requests.
signal server_ready
## Emitted if the server fails to start or never passes the health-check.
signal server_failed(error_message: String)
## Emitted when the server process is stopped.
signal server_stopped

## PID of the running llama-server process. -1 means no process is active.
var _server_pid: int = -1
var _model_path: String = ""
var _server_args: PackedStringArray = PackedStringArray()
var _health_check_url: String = ""
var _health_check_timeout_sec: float = 60.0
var _health_check_interval_sec: float = 2.0

# Reference to ModelDownloader for the model file path.
var _model_downloader: Node = null


func _ready() -> void:
	_model_downloader = get_node("/root/ModelDownloader")
	_load_config()
	# Enable receiving window close notifications so we can kill the server. (RF10)
	get_tree().set_auto_accept_quit(false)


## Intercepts window close to perform a clean shutdown of llama-server. (RF10)
## Without this, the process would keep running in the background after the game closes,
## consuming RAM and VRAM until the user manually kills it.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if is_running():
			print("LocalServerManager: Game closing — killing llama-server (PID %d)." % _server_pid)
			stop_server()
		get_tree().quit()


func _load_config() -> void:
	var config: ConfigFile = ConfigFile.new()
	var err: Error = config.load(LOCAL_CONFIG_PATH)
	if err != OK:
		push_error("LocalServerManager: Could not load local config. Error: %d" % err)
		return
	_health_check_url = config.get_value("local_server", "health_check_url", "http://127.0.0.1:8080/health")
	_health_check_timeout_sec = config.get_value("local_server", "health_check_timeout_sec", 60.0)
	_health_check_interval_sec = config.get_value("local_server", "health_check_interval_sec", 2.0)


## Returns true if a llama-server process is currently running.
func is_running() -> bool:
	return _server_pid != -1


## Launches llama-server pointing at the downloaded model.
## Resolves the binary path dynamically based on the host OS. (RNF11 + RF08)
## Flags are pre-configured to limit RAM usage to under 4GB. (RNF03)
func start_server() -> void:
	if is_running():
		push_warning("LocalServerManager: Server is already running (PID %d)." % _server_pid)
		return

	var binary_path: String = _resolve_binary_path()
	if binary_path.is_empty():
		var msg: String = "LocalServerManager: llama-server binary not found for this OS."
		push_error(msg)
		server_failed.emit(msg)
		return

	_model_path = _model_downloader.get_model_path()
	if not FileAccess.file_exists(_model_path):
		var msg: String = "LocalServerManager: Model file not found at '%s'. Download it first." % _model_path
		push_error(msg)
		server_failed.emit(msg)
		return

	_server_args = _build_server_args(_model_path)

	print("LocalServerManager: Launching '%s' with args: %s" % [binary_path, str(_server_args)])
	_server_pid = OS.create_process(binary_path, _server_args)

	if _server_pid == -1:
		var msg: String = "LocalServerManager: OS.create_process failed. Check binary path and permissions."
		push_error(msg)
		server_failed.emit(msg)
		return

	print("LocalServerManager: llama-server launched with PID %d." % _server_pid)


## Waits asynchronously until llama-server passes its health-check or times out. (RF09)
## Call this with 'await' after start_server(). Emits server_ready or server_failed.
func wait_for_server() -> void:
	if not is_running():
		server_failed.emit("LocalServerManager: wait_for_server called but server is not running.")
		return

	var ping_http: HTTPRequest = HTTPRequest.new()
	add_child(ping_http)

	var elapsed: float = 0.0
	var success: bool = false

	print("LocalServerManager: Waiting for server health-check at '%s'..." % _health_check_url)

	while elapsed < _health_check_timeout_sec:
		var err: Error = ping_http.request(_health_check_url)
		if err == OK:
			var response: Array = await ping_http.request_completed
			var http_code: int = response[1]
			if http_code == 200:
				success = true
				break

		# Wait before next ping.
		await get_tree().create_timer(_health_check_interval_sec).timeout
		elapsed += _health_check_interval_sec
		print("LocalServerManager: Health-check pending... (%.0fs / %.0fs)" % [elapsed, _health_check_timeout_sec])

	ping_http.queue_free()

	if success:
		print("LocalServerManager: Server is ready.")
		server_ready.emit()
	else:
		var msg: String = "LocalServerManager: Server did not respond after %.0f seconds." % _health_check_timeout_sec
		push_error(msg)
		server_failed.emit(msg)


## Stops the running llama-server process cleanly.
func stop_server() -> void:
	if not is_running():
		return
	OS.kill(_server_pid)
	print("LocalServerManager: Killed llama-server process (PID %d)." % _server_pid)
	_server_pid = -1
	server_stopped.emit()


## Resolves the llama-server binary path for the current operating system. (RNF11)
func _resolve_binary_path() -> String:
	var base_dir: String = OS.get_executable_path().get_base_dir()

	var binary_name: String = ""
	match OS.get_name():
		"Windows":
			binary_name = "llama-server.exe"
		"macOS":
			binary_name = "llama-server-mac"
		"Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD":
			binary_name = "llama-server"
		_:
			push_error("LocalServerManager: Unsupported OS '%s'." % OS.get_name())
			return ""

	var candidate_paths: Array[String] = [
		base_dir.path_join("ai").path_join("binaries").path_join(binary_name),
		ProjectSettings.globalize_path("res://ai/binaries/" + binary_name),
	]

	for path: String in candidate_paths:
		if FileAccess.file_exists(path):
			print("LocalServerManager: Found binary at '%s'." % path)
			return path

	push_error("LocalServerManager: Binary '%s' not found in any of: %s" % [binary_name, str(candidate_paths)])
	return ""


## Builds the argument list for llama-server. (RF08)
## Flags are tuned for < 4GB RAM usage (RNF03) — configured in local_config.cfg.
func _build_server_args(model_path: String) -> PackedStringArray:
	var config: ConfigFile = ConfigFile.new()
	config.load(LOCAL_CONFIG_PATH)

	var ctx_size: int = config.get_value("llama_flags", "ctx_size", 2048)
	var threads: int = config.get_value("llama_flags", "threads", 4)
	var n_gpu_layers: int = config.get_value("llama_flags", "n_gpu_layers", 0)
	var host: String = config.get_value("llama_flags", "host", "127.0.0.1")
	var port: int = config.get_value("llama_flags", "port", 8080)

	return PackedStringArray([
		"--model", model_path,
		"--ctx-size", str(ctx_size),
		"--threads", str(threads),
		"--n-gpu-layers", str(n_gpu_layers),
		"--host", host,
		"--port", str(port),
	])

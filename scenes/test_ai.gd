extends Node

func _ready() -> void:
	ModeManager.set_mode(ModeManager.Mode.LOCAL)
	LocalServerManager.server_ready.connect(_on_ready)
	LocalServerManager.server_failed.connect(_on_failed)
	LocalServerManager.start_server()
	await LocalServerManager.wait_for_server()

func _on_failed(msg: String) -> void:
	print("=== SERVER FAILED: ", msg, " ===")

func _on_ready() -> void:
	print("=== SERVER READY ===")
	var response = await AIManager.send_message("Where were you that night?")
	if response:
		response.debug_print()
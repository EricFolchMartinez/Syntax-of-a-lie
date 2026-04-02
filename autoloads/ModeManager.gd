extends Node

## Autoload: ModeManager
## Manages the player's choice between Cloud AI and Local AI mode.
## Persists the selection to disk so it survives game restarts.

enum Mode { CLOUD, LOCAL }

const PREFS_PATH: String = "user://mode_prefs.cfg"

## The currently active inference mode. Defaults to CLOUD.
var current_mode: Mode = Mode.CLOUD

## Emitted whenever the mode changes. Connect in the UI to update buttons/labels.
signal mode_changed(new_mode: Mode)


func _ready() -> void:
	_load_mode()
	print("ModeManager: Active mode is '%s'." % mode_to_string(current_mode))


## Sets the active mode and persists it to disk.
func set_mode(new_mode: Mode) -> void:
	if new_mode == current_mode:
		return
	current_mode = new_mode
	_save_mode()
	mode_changed.emit(current_mode)
	print("ModeManager: Mode changed to '%s'." % mode_to_string(current_mode))


## Returns true if the game is currently configured to use local inference.
func is_local() -> bool:
	return current_mode == Mode.LOCAL


## Returns true if the game is currently configured to use cloud inference.
func is_cloud() -> bool:
	return current_mode == Mode.CLOUD


## Returns a human-readable string for the given mode.
func mode_to_string(mode: Mode) -> String:
	match mode:
		Mode.CLOUD:
			return "Cloud"
		Mode.LOCAL:
			return "Local"
		_:
			return "Unknown"


func _load_mode() -> void:
	var config: ConfigFile = ConfigFile.new()
	var err: Error = config.load(PREFS_PATH)
	if err != OK:
		return
	var saved: int = config.get_value("prefs", "mode", Mode.CLOUD)
	current_mode = saved as Mode


func _save_mode() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("prefs", "mode", current_mode)
	var err: Error = config.save(PREFS_PATH)
	if err != OK:
		push_error("ModeManager: Failed to save mode preference. Error: %d" % err)

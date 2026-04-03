extends Node

## TypewriterController: writes text character by character into a RichTextLabel,
## playing a random keyboard SFX on each visible character. (Sprint 3 - Game Feel)
## Add as a child node of MainGame.tscn and assign via @export.

## Seconds between each character reveal. Adjust for faster/slower typing feel.
const CHAR_INTERVAL_SEC: float = 0.03

## Play a sound every N characters to avoid overwhelming the audio bus.
const SOUND_EVERY_N_CHARS: int = 1

## Paths to the keyboard click sound files (CC0, placed in res://audio/sfx/).
const SFX_PATHS: Array[String] = [
	"res://audio/sfx/key_01.ogg",
	"res://audio/sfx/key_02.ogg",
	"res://audio/sfx/key_03.ogg",
]

## Emitted when the typewriter finishes printing the full text.
signal typing_finished

@export var target_label: RichTextLabel

var _audio_players: Array[AudioStreamPlayer] = []
var _sfx_streams: Array[AudioStream] = []
var _is_typing: bool = false


func _ready() -> void:
	_load_sfx()
	_setup_audio_players()


func _load_sfx() -> void:
	for path: String in SFX_PATHS:
		if ResourceLoader.exists(path):
			var stream: AudioStream = load(path) as AudioStream
			if stream != null:
				_sfx_streams.append(stream)
	if _sfx_streams.is_empty():
		push_warning("TypewriterController: No SFX files found in res://audio/sfx/. Typing will be silent.")


func _setup_audio_players() -> void:
	# Use a small pool of AudioStreamPlayers so rapid sounds don't cut each other off.
	for i: int in range(3):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.volume_db = -6.0
		add_child(player)
		_audio_players.append(player)


## Starts typing the given text into the target RichTextLabel.
## If already typing, queues the new text after the current one finishes.
func type_text(full_text: String, prefix: String = "") -> void:
	if _is_typing:
		await typing_finished
	_is_typing = true
	await _run_typewriter(full_text, prefix)
	_is_typing = false
	typing_finished.emit()


func _run_typewriter(full_text: String, prefix: String) -> void:
	if target_label == null:
		push_error("TypewriterController: target_label is not assigned.")
		return

	# Write the speaker prefix immediately (bold, not typed character by character).
	if not prefix.is_empty():
		target_label.append_text("[b]%s:[/b] " % prefix)

	var char_count: int = 0
	for i: int in range(full_text.length()):
		var ch: String = full_text[i]
		target_label.append_text(ch)
		char_count += 1

		# Play SFX only on printable (non-space) characters every N chars.
		if ch.strip_edges() != "" and char_count % SOUND_EVERY_N_CHARS == 0:
			_play_random_sfx()

		# Scroll to bottom after each character so the latest text is always visible.
		target_label.scroll_to_line(target_label.get_line_count() - 1)

		await get_tree().create_timer(CHAR_INTERVAL_SEC).timeout

	# Add a newline at the end.
	target_label.append_text("\n")
	target_label.scroll_to_line(target_label.get_line_count() - 1)


func _play_random_sfx() -> void:
	if _sfx_streams.is_empty():
		return

	# Find a free player in the pool (one not currently playing).
	var player: AudioStreamPlayer = _get_free_player()
	var stream_index: int = randi() % _sfx_streams.size()
	player.stream = _sfx_streams[stream_index]
	player.play()


func _get_free_player() -> AudioStreamPlayer:
	for player: AudioStreamPlayer in _audio_players:
		if not player.playing:
			return player
	# All players are busy: reuse the first one (oldest sound gets cut off).
	return _audio_players[0]

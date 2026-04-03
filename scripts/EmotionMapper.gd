extends Node

## EmotionMapper: maps the emotion_state string from AIResponse to the correct
## Viktor sprite and updates the TextureRect in the scene. (RF04)
## Add as a child node of MainGame.tscn and assign npc_texture via @export.

## Folder where all viktor_*.png sprites live.
const SPRITES_BASE_PATH: String = "res://assets/characters/viktor/"

## Maps each valid emotion_state value (from system_prompt.txt) to its PNG filename.
const EMOTION_TO_FILE: Dictionary = {
	"neutral":    "viktor_neutral.png",
	"confident":  "viktor_confident.png",
	"nervous":    "viktor_nervous.png",
	"angry":      "viktor_angry.png",
	"defensive":  "viktor_defensive.png",
	"afraid":     "viktor_afraid.png",
}

## Fallback placeholder colors used when a sprite file is not yet available.
## Each color visually represents the emotion so development can continue without art.
const EMOTION_PLACEHOLDER_COLOR: Dictionary = {
	"neutral":    Color(0.6, 0.6, 0.6),   # grey
	"confident":  Color(0.2, 0.5, 0.9),   # blue
	"nervous":    Color(0.9, 0.8, 0.2),   # yellow
	"angry":      Color(0.9, 0.2, 0.2),   # red
	"defensive":  Color(0.6, 0.3, 0.8),   # purple
	"afraid":     Color(0.9, 0.5, 0.1),   # orange
}

@export var npc_texture: TextureRect

## Placeholder ColorRect shown when no PNG is available yet.
var _placeholder_rect: ColorRect = null
var _current_emotion: String = "neutral"


func _ready() -> void:
	_setup_placeholder()
	set_emotion("neutral")


func _setup_placeholder() -> void:
	_placeholder_rect = ColorRect.new()
	_placeholder_rect.color = EMOTION_PLACEHOLDER_COLOR.get("neutral", Color.GRAY)
	_placeholder_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_placeholder_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if npc_texture != null:
		npc_texture.add_child(_placeholder_rect)


## Updates the NPC visual based on the emotion_state field from the AI JSON. (RF04)
func set_emotion(emotion: String) -> void:
	if emotion == _current_emotion:
		return
	_current_emotion = emotion

	if not EMOTION_TO_FILE.has(emotion):
		push_warning("EmotionMapper: Unknown emotion '%s', defaulting to 'neutral'." % emotion)
		_current_emotion = "neutral"

	_apply_emotion(_current_emotion)


func _apply_emotion(emotion: String) -> void:
	if npc_texture == null:
		push_error("EmotionMapper: npc_texture is not assigned.")
		return

	var file_name: String = EMOTION_TO_FILE.get(emotion, "viktor_neutral.png") as String
	var full_path: String = SPRITES_BASE_PATH + file_name

	if ResourceLoader.exists(full_path):
		var tex: Texture2D = load(full_path) as Texture2D
		npc_texture.texture = tex
		if _placeholder_rect != null:
			_placeholder_rect.visible = false
	else:
		# Sprite not found: show the placeholder color so dev can continue without art.
		npc_texture.texture = null
		if _placeholder_rect != null:
			var fallback_color: Color = EMOTION_PLACEHOLDER_COLOR.get(emotion, Color.GRAY) as Color
			_placeholder_rect.color = fallback_color
			_placeholder_rect.visible = true
		push_warning("EmotionMapper: Sprite not found at '%s'. Showing placeholder." % full_path)

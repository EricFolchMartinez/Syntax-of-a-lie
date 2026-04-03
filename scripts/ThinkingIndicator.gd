extends Label

## ThinkingIndicator: animates a "Viktor is thinking..." label with cycling dots. (RF03)
## Attach this script to the ThinkingLabel node in MainGame.tscn.
## Automatically starts/stops animation when visibility changes.

const BASE_TEXT: String = "Viktor is thinking"
const DOT_CYCLE: Array[String] = [".", "..", "..."]
const INTERVAL_SEC: float = 0.4

var _dot_index: int = 0
var _timer: Timer = null


func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = INTERVAL_SEC
	_timer.autostart = false
	_timer.timeout.connect(_on_timer_tick)
	add_child(_timer)

	visible = false


func _on_timer_tick() -> void:
	_dot_index = (_dot_index + 1) % DOT_CYCLE.size()
	text = BASE_TEXT + DOT_CYCLE[_dot_index]


## Call this to start the animation and show the indicator.
func start() -> void:
	_dot_index = 0
	text = BASE_TEXT + DOT_CYCLE[0]
	visible = true
	_timer.start()


## Call this to stop the animation and hide the indicator.
func stop() -> void:
	_timer.stop()
	visible = false

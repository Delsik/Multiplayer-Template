extends CanvasLayer

@onready var label: Label = $Root/Label

var _dot_count := 0
var _timer: Timer


func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = 0.4
	_timer.timeout.connect(_on_timer_timeout)
	add_child(_timer)
	_timer.start()


func _on_timer_timeout() -> void:
	_dot_count = (_dot_count + 1) % 4
	label.text = "Завантаження" + ".".repeat(_dot_count)

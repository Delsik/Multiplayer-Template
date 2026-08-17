extends Control

## Gameplay touch HUD для спільного InputMap.
## TouchScreenButton напряму натискає move_* actions, тому ця сцена нічого
## не знає про ENet, peer ID або avatar. passby_press дозволяє провести
## утримуваний палець на сусідній напрямок без попереднього відпускання.

const BUTTON_SIZE := Vector2(72.0, 72.0)
const BUTTON_GAP := 8.0
const EDGE_MARGIN := 20.0
const LABEL_FONT_SIZE := 28

const BUTTON_CONFIGS := [
	{"node_name": "MoveForward", "label": "▲", "action": "move_forward"},
	{"node_name": "MoveLeft", "label": "◀", "action": "move_left"},
	{"node_name": "MoveRight", "label": "▶", "action": "move_right"},
	{"node_name": "MoveBack", "label": "▼", "action": "move_back"},
]

var _buttons_by_action: Dictionary = {}
var _centers_by_action: Dictionary = {}


func _ready() -> void:
	# У release desktop build HUD прихований. У debug build він видимий,
	# щоб перевірити його розміщення без Android export.
	visible = OS.has_feature("mobile") or OS.is_debug_build()
	if not visible:
		return

	# Сам Control не ловить gameplay input. Його дочірні TouchScreenButton
	# мають власні Shape2D для hit detection.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_create_touch_buttons()
	resized.connect(_layout_touch_buttons)
	_layout_touch_buttons()


func _exit_tree() -> void:
	# Якщо сцена закривається, поки палець утримує напрямок, не залишаємо
	# synthetic InputMap action натиснутою для наступної сесії.
	for button_config in BUTTON_CONFIGS:
		Input.action_release(str(button_config["action"]))


func _create_touch_buttons() -> void:
	for button_config in BUTTON_CONFIGS:
		var action: String = str(button_config["action"])
		var touch_button := TouchScreenButton.new()
		touch_button.name = str(button_config["node_name"])
		touch_button.action = action
		touch_button.passby_press = true
		touch_button.visibility_mode = TouchScreenButton.VISIBILITY_ALWAYS
		touch_button.shape = _make_hit_shape()
		touch_button.shape_visible = false
		add_child(touch_button)
		_buttons_by_action[action] = touch_button


func _make_hit_shape() -> RectangleShape2D:
	var hit_shape := RectangleShape2D.new()
	hit_shape.size = BUTTON_SIZE
	return hit_shape


func _layout_touch_buttons() -> void:
	# TouchControls заповнює Content всередині SafeArea. Отже нижня межа size.y
	# уже не містить Android gesture area, iPhone home indicator чи display cutout.
	# Усі чотири центри лишаються всередині цієї області.
	var left_x := EDGE_MARGIN + BUTTON_SIZE.x * 0.5
	var middle_x := left_x + BUTTON_SIZE.x + BUTTON_GAP
	var right_x := middle_x + BUTTON_SIZE.x + BUTTON_GAP
	var lower_y := size.y - EDGE_MARGIN - BUTTON_SIZE.y * 0.5
	var upper_y := lower_y - BUTTON_SIZE.y - BUTTON_GAP

	_set_button_center("move_forward", Vector2(middle_x, upper_y))
	_set_button_center("move_left", Vector2(left_x, lower_y))
	_set_button_center("move_right", Vector2(right_x, lower_y))
	_set_button_center("move_back", Vector2(middle_x, lower_y))
	queue_redraw()


func _set_button_center(action: String, center: Vector2) -> void:
	var touch_button := _buttons_by_action[action] as TouchScreenButton
	touch_button.position = center
	_centers_by_action[action] = center


func _draw() -> void:
	if not visible:
		return

	var font := ThemeDB.fallback_font
	for button_config in BUTTON_CONFIGS:
		var action: String = str(button_config["action"])
		var center: Vector2 = _centers_by_action.get(action, Vector2.ZERO)
		var touch_button := _buttons_by_action.get(action) as TouchScreenButton
		var is_pressed := touch_button != null and touch_button.is_pressed()
		var fill_color := Color("#0F172AE8") if is_pressed else Color("#334155B8")

		draw_circle(center, BUTTON_SIZE.x * 0.5, fill_color)
		draw_arc(center, BUTTON_SIZE.x * 0.5, 0.0, TAU, 32, Color("#FFFFFF55"), 1.0)

		var label: String = str(button_config["label"])
		var label_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE)
		var label_position := center + Vector2(-label_size.x * 0.5, label_size.y * 0.34)
		draw_string(font, label_position, label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, Color.WHITE)

extends Control

## Мінімальний touch HUD для кросплатформного network test.
## Кнопки не знають нічого про ENet, peer ID або avatar: вони лише натискають
## ті самі InputMap actions, які на desktop приходять від клавіатури.

const BUTTON_SIZE := Vector2(72.0, 72.0)
const BUTTON_GAP := 8.0
const EDGE_MARGIN := 20.0

const BUTTON_CONFIGS := [
	{"node_name": "MoveForward", "label": "▲", "action": "move_forward"},
	{"node_name": "MoveLeft", "label": "◀", "action": "move_left"},
	{"node_name": "MoveRight", "label": "▶", "action": "move_right"},
	{"node_name": "MoveBack", "label": "▼", "action": "move_back"},
]

var _buttons_by_action: Dictionary = {}


func _ready() -> void:
	# У release desktop build touch HUD не показується. У debug build він
	# видимий і на ПК, щоб тестувати кнопки мишею без Android export.
	visible = OS.has_feature("mobile") or OS.is_debug_build()
	if not visible:
		return

	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_create_buttons()
	resized.connect(_layout_buttons)
	_layout_buttons()


func _exit_tree() -> void:
	# Якщо scene закривається в момент натиснутої кнопки, не залишаємо
	# InputMap action у pressed-стані для наступної сесії.
	for button_config in BUTTON_CONFIGS:
		Input.action_release(str(button_config["action"]))


func _create_buttons() -> void:
	for button_config in BUTTON_CONFIGS:
		var action: String = str(button_config["action"])
		var button := Button.new()
		button.name = str(button_config["node_name"])
		button.text = str(button_config["label"])
		button.custom_minimum_size = BUTTON_SIZE
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		button.add_theme_font_size_override("font_size", 28)
		button.add_theme_stylebox_override("normal", _make_button_style(Color("#334155B8")))
		button.add_theme_stylebox_override("hover", _make_button_style(Color("#475569D8")))
		button.add_theme_stylebox_override("pressed", _make_button_style(Color("#0F172AE8")))

		button.button_down.connect(_on_direction_pressed.bind(action))
		button.button_up.connect(_on_direction_released.bind(action))
		add_child(button)
		_buttons_by_action[action] = button


func _layout_buttons() -> void:
	# TouchControls є дочірнім Control усередині SafeArea, тож `size`
	# уже не включає виріз екрана, rounded corners або нижню gesture area.
	var bottom_y := size.y - EDGE_MARGIN - BUTTON_SIZE.y
	var center_x := EDGE_MARGIN + BUTTON_SIZE.x + BUTTON_GAP

	_get_button("move_forward").position = Vector2(center_x, bottom_y - BUTTON_SIZE.y - BUTTON_GAP)
	_get_button("move_left").position = Vector2(EDGE_MARGIN, bottom_y)
	_get_button("move_right").position = Vector2(center_x + BUTTON_SIZE.x + BUTTON_GAP, bottom_y)
	_get_button("move_back").position = Vector2(center_x, bottom_y + BUTTON_SIZE.y + BUTTON_GAP)


func _get_button(action: String) -> Button:
	return _buttons_by_action[action] as Button


func _on_direction_pressed(action: String) -> void:
	Input.action_press(action)


func _on_direction_released(action: String) -> void:
	Input.action_release(action)


func _make_button_style(background_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.corner_radius_top_left = 18
	style.corner_radius_top_right = 18
	style.corner_radius_bottom_right = 18
	style.corner_radius_bottom_left = 18
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color("#FFFFFF55")
	return style

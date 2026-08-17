extends Control

## Аналоговий mobile joystick, який подає значення до наявного InputMap.
## Він не має залежностей від мережі, peer ID чи avatar: Input.get_vector()
## у GameWorld читає ті самі move_* actions на ПК і на телефоні.

const BASE_RADIUS := 78.0
const THUMB_RADIUS := 32.0
const EDGE_MARGIN := 24.0
const DEAD_ZONE_RATIO := 0.18

var _active_touch_index := -1
var _mouse_drag_active := false
var _thumb_offset := Vector2.ZERO


func _ready() -> void:
	# На телефоні joystick завжди видимий. У debug він також є на ПК,
	# щоб легко перевірити відчуття joystick мишею без нового Android export.
	visible = OS.has_feature("mobile") or OS.is_debug_build()
	if not visible:
		return

	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_on_resized)
	queue_redraw()


func _exit_tree() -> void:
	_release_all_move_actions()


func _on_resized() -> void:
	# Якщо орієнтація або розмір вікна змінились посеред drag, безпечніше
	# завершити попередній gesture, ніж залишати рух від старих координат.
	_stop_drag()
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		if touch_event.pressed:
			_try_start_touch_drag(touch_event.index, touch_event.position)
		elif touch_event.index == _active_touch_index:
			_stop_drag()
		return

	if event is InputEventScreenDrag and event.index == _active_touch_index:
		var drag_event := event as InputEventScreenDrag
		_update_drag(touch_event_to_local(drag_event.position))
		return

	# У debug build підтримуємо мишу: це не впливає на Android/iOS input.
	if event is InputEventMouseButton:
		var mouse_button_event := event as InputEventMouseButton
		if mouse_button_event.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse_button_event.pressed:
			_try_start_mouse_drag(mouse_button_event.position)
		elif _mouse_drag_active:
			_stop_drag()
		return

	if event is InputEventMouseMotion and _mouse_drag_active:
		var mouse_motion_event := event as InputEventMouseMotion
		_update_drag(mouse_motion_event.position)


func _try_start_touch_drag(touch_index: int, screen_position: Vector2) -> void:
	# Лівий joystick бере перший touch лише тоді, коли той почався в його base.
	# Інші пальці не чіпаємо: вони знадобляться майбутнім action-кнопкам.
	if _active_touch_index != -1:
		return

	var local_position := touch_event_to_local(screen_position)
	if not _is_inside_base(local_position):
		return

	_active_touch_index = touch_index
	_update_drag(local_position)


func _try_start_mouse_drag(local_position: Vector2) -> void:
	if not _is_inside_base(local_position):
		return

	_mouse_drag_active = true
	_update_drag(local_position)


func _update_drag(local_position: Vector2) -> void:
	var raw_offset := local_position - _get_base_center()
	_thumb_offset = raw_offset.limit_length(BASE_RADIUS - THUMB_RADIUS)

	var normalized_input := _thumb_offset / (BASE_RADIUS - THUMB_RADIUS)
	_apply_move_vector(normalized_input)
	queue_redraw()


func _stop_drag() -> void:
	_active_touch_index = -1
	_mouse_drag_active = false
	_thumb_offset = Vector2.ZERO
	_release_all_move_actions()
	queue_redraw()


func _apply_move_vector(raw_input: Vector2) -> void:
	# Dead zone прибирає випадковий рух, коли палець близько до центру.
	# Поза dead zone сила плавно масштабується від 0 до 1.
	var input_length := raw_input.length()
	if input_length <= DEAD_ZONE_RATIO:
		_release_all_move_actions()
		return

	var direction := raw_input / input_length
	var strength := inverse_lerp(DEAD_ZONE_RATIO, 1.0, minf(input_length, 1.0))

	_set_action_strength("move_left", maxf(-direction.x, 0.0) * strength)
	_set_action_strength("move_right", maxf(direction.x, 0.0) * strength)
	_set_action_strength("move_forward", maxf(-direction.y, 0.0) * strength)
	_set_action_strength("move_back", maxf(direction.y, 0.0) * strength)


func _set_action_strength(action: String, strength: float) -> void:
	if strength > 0.0:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _release_all_move_actions() -> void:
	Input.action_release("move_left")
	Input.action_release("move_right")
	Input.action_release("move_forward")
	Input.action_release("move_back")


func _get_base_center() -> Vector2:
	return Vector2(EDGE_MARGIN + BASE_RADIUS, size.y - EDGE_MARGIN - BASE_RADIUS)


func _is_inside_base(local_position: Vector2) -> bool:
	return local_position.distance_to(_get_base_center()) <= BASE_RADIUS


func touch_event_to_local(screen_position: Vector2) -> Vector2:
	# Touch position приходить у координатах viewport. TouchControls — Control
	# на весь Content усередині SafeArea, тому переводимо координати в local.
	return get_global_transform_with_canvas().affine_inverse() * screen_position


func _draw() -> void:
	if not visible:
		return

	var center := _get_base_center()
	var thumb_center := center + _thumb_offset

	# Base: напівпрозоре коло, яке показує допустиму область першого торкання.
	draw_circle(center, BASE_RADIUS, Color("#0F172A88"))
	draw_arc(center, BASE_RADIUS, 0.0, TAU, 48, Color("#FFFFFF55"), 2.0)

	# Thumb: фактичне положення пальця, обмежене внутрішнім радіусом joystick.
	draw_circle(thumb_center, THUMB_RADIUS, Color("#475569DD"))
	draw_arc(thumb_center, THUMB_RADIUS, 0.0, TAU, 32, Color("#FFFFFFAA"), 2.0)

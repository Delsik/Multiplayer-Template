extends Control

@onready var name_edit: LineEdit = $CenterContainer/VBoxContainer/NameEdit
@onready var ip_edit: LineEdit = $CenterContainer/VBoxContainer/IPEdit
@onready var solo_button: Button = $CenterContainer/VBoxContainer/SoloButton
@onready var host_button: Button = $CenterContainer/VBoxContainer/HostButton
@onready var join_button: Button = $CenterContainer/VBoxContainer/JoinButton
@onready var error_label: Label = $CenterContainer/VBoxContainer/ErrorLabel
@onready var scan_button: Button = $CenterContainer/VBoxContainer/ScanButton
@onready var host_list: ItemList = $CenterContainer/VBoxContainer/HostList
@onready var cancel_button: Button = $CenterContainer/VBoxContainer/CancelButton
@onready var quit_button: Button = $CenterContainer/VBoxContainer/QuitButton

var _status_timer: Timer
var _status_base_text: String = ""
var _dot_count := 0


func _ready() -> void:
	Network.connection_failed.connect(_on_connection_failed)
	Network.connection_succeeded.connect(_on_connection_succeeded)
	Network.game_ended.connect(_on_game_ended)
	Network.host_found.connect(_on_host_found)
	Network.scan_finished.connect(_on_scan_finished)
	Network.reconnecting.connect(_on_reconnecting)
	Network.reconnect_failed.connect(_on_reconnect_failed)
	Network.connection_cancelled.connect(_on_connection_cancelled)

	scan_button.pressed.connect(_on_scan_button_pressed)
	host_list.item_selected.connect(_on_host_list_item_selected)
	cancel_button.pressed.connect(_on_cancel_button_pressed)
	quit_button.pressed.connect(_on_quit_button_pressed)
	solo_button.pressed.connect(_on_solo_button_pressed)
	host_button.pressed.connect(_on_host_button_pressed)
	join_button.pressed.connect(_on_join_button_pressed)

	# Apple Human Interface Guidelines прямо забороняють кнопку виходу
	# в iOS-застосунках — користувач сам закриває через системний жест.
	# На решті платформ (Windows/Mac/Linux/Android) це нормальна практика.
	if OS.get_name() == "iOS":
		quit_button.visible = false

	# Числова клавіатура на мобільних — IP простіше вводити без букв.
	ip_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER

	# Підставляємо ім'я, яке Network згенерував за замовчуванням (Player123).
	name_edit.text = Network.player_name


func _on_solo_button_pressed() -> void:
	if not _validate_name():
		return
	Network.host_game(name_edit.text)
	# Соло: одразу стартуємо гру, без очікування в лобі.
	Network.begin_game()
	# Соло за замовчуванням приватне — ніхто не повинен випадково
	# приєднатись до твоєї одиночної сесії, знаючи IP.
	Network.peer.refuse_new_connections = true
	hide()


func _on_host_button_pressed() -> void:
	if not _validate_name():
		return
	Network.host_game(name_edit.text)
	# На відміну від Solo — Host має "світитись" для сканерів мережі.
	Network.start_lan_discovery_server()
	_enter_lobby()


func _on_join_button_pressed() -> void:
	if not _validate_name():
		return
	if not ip_edit.text.is_valid_ip_address():
		error_label.text = "Невірна IP-адреса"
		return
	_join(ip_edit.text)


func _join(ip_address: String) -> void:
	_set_form_visible(false)
	cancel_button.visible = true
	_show_status("Підключення")
	Network.join_game(ip_address, name_edit.text)


func _on_scan_button_pressed() -> void:
	if not _validate_name():
		return
	host_list.clear()
	scan_button.disabled = true
	scan_button.text = "Шукаю..."
	Network.scan_for_hosts()


func _on_host_found(host_name: String, ip: String) -> void:
	var idx := host_list.add_item("%s (%s)" % [host_name, ip])
	host_list.set_item_metadata(idx, ip)


func _on_scan_finished() -> void:
	scan_button.disabled = false
	scan_button.text = "Шукати ігри поблизу"
	if host_list.item_count == 0:
		error_label.text = "Нічого не знайдено поблизу"


func _on_host_list_item_selected(index: int) -> void:
	var ip: String = host_list.get_item_metadata(index)
	_join(ip)


func _on_reconnecting(attempt: int, max_attempts: int) -> void:
	# Показуємо Menu поверх того, що лишилось (GameWorld вже прибрано
	# всередині _on_server_disconnected() у Network). Ховаємо ВСЮ форму —
	# лишається лише статус, щоб гравець не міг натиснути Solo/Host/Join
	# і зламати стан, поки триває спроба перепідключення.
	show()
	_set_form_visible(false)
	cancel_button.visible = true
	_show_status("Перепідключення (%d/%d)" % [attempt, max_attempts])


func _on_reconnect_failed() -> void:
	_hide_status()
	cancel_button.visible = false
	error_label.text = "Не вдалось перепідключитись"


func _on_connection_succeeded() -> void:
	# Спрацьовує лише в клієнта, коли join_game() успішно з'єднався із сервером
	# (включно з успішним перепідключенням — далі спрацює звичайний late-join потік).
	_hide_status()
	cancel_button.visible = false
	_enter_lobby()


func _on_connection_failed() -> void:
	_hide_status()
	cancel_button.visible = false
	_set_form_visible(true)
	error_label.text = "Не вдалось підключитись до сервера"


func _on_connection_cancelled() -> void:
	_hide_status()
	cancel_button.visible = false
	_set_form_visible(true)
	error_label.text = ""


func _on_cancel_button_pressed() -> void:
	Network.cancel_connecting()


func _on_quit_button_pressed() -> void:
	get_tree().quit()


func _on_game_ended() -> void:
	# Network.end_game() завжди повертає нас сюди — і після соло, і після мультиплеєра.
	show()
	_hide_status()
	cancel_button.visible = false
	_set_form_visible(true)
	host_button.disabled = false
	join_button.disabled = false
	scan_button.disabled = false
	scan_button.text = "Шукати ігри поблизу"
	host_list.clear()
	error_label.text = ""


func _validate_name() -> bool:
	if name_edit.text.strip_edges() == "":
		error_label.text = "Введи ім'я"
		return false
	error_label.text = ""
	return true


## Ховає/показує всю інтерактивну частину форми, лишаючи лише error_label
## (там, де ми показуємо статус на кшталт "Перепідключення..."). Це надійніше
## за дизейбл кожної кнопки окремо — нема шансу забути якусь нову, яку
## додаси в майбутньому, і нема шансу натиснути щось приховане.
func _set_form_visible(should_be_visible: bool) -> void:
	name_edit.visible = should_be_visible
	solo_button.visible = should_be_visible
	host_button.visible = should_be_visible
	scan_button.visible = should_be_visible
	host_list.visible = should_be_visible
	ip_edit.visible = should_be_visible
	join_button.visible = should_be_visible
	quit_button.visible = should_be_visible and OS.get_name() != "iOS"


## Показує в error_label текст, що "живе" — крапки після нього циклічно
## додаються/зникають (Підключення → Підключення. → Підключення.. → ...).
## Дешевий, зрозумілий індикатор активності без потреби в окремій текстурі
## спінера чи AnimationPlayer.
func _show_status(base_text: String) -> void:
	_status_base_text = base_text
	_dot_count = 0
	error_label.text = base_text

	if not _status_timer:
		_status_timer = Timer.new()
		_status_timer.wait_time = 0.4
		_status_timer.timeout.connect(_on_status_timer_timeout)
		add_child(_status_timer)
	_status_timer.start()


func _on_status_timer_timeout() -> void:
	_dot_count = (_dot_count + 1) % 4
	error_label.text = _status_base_text + ".".repeat(_dot_count)


func _hide_status() -> void:
	if _status_timer:
		_status_timer.stop()


func _enter_lobby() -> void:
	var lobby: Control = load("res://ui/lobby/lobby.tscn").instantiate()
	lobby.name = "Lobby"
	get_tree().get_root().add_child(lobby)
	hide()

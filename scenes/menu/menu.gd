extends Control

@onready var name_edit: LineEdit = $CenterContainer/VBoxContainer/NameEdit
@onready var ip_edit: LineEdit = $CenterContainer/VBoxContainer/IPEdit
@onready var host_button: Button = $CenterContainer/VBoxContainer/HostButton
@onready var join_button: Button = $CenterContainer/VBoxContainer/JoinButton
@onready var error_label: Label = $CenterContainer/VBoxContainer/ErrorLabel


func _ready() -> void:
	Network.connection_failed.connect(_on_connection_failed)
	Network.connection_succeeded.connect(_on_connection_succeeded)
	Network.game_ended.connect(_on_game_ended)

	# Підставляємо ім'я, яке Network згенерував за замовчуванням (Player123).
	name_edit.text = Network.player_name


func _on_solo_button_pressed() -> void:
	if not _validate_name():
		return
	Network.host_game(name_edit.text)
	# Соло: одразу стартуємо гру, без очікування в лобі.
	Network.begin_game()
	hide()


func _on_host_button_pressed() -> void:
	if not _validate_name():
		return
	Network.host_game(name_edit.text)
	_enter_lobby()


func _on_join_button_pressed() -> void:
	if not _validate_name():
		return
	if not ip_edit.text.is_valid_ip_address():
		error_label.text = "Невірна IP-адреса"
		return

	error_label.text = ""
	host_button.disabled = true
	join_button.disabled = true
	Network.join_game(ip_edit.text, name_edit.text)


func _on_connection_succeeded() -> void:
	# Спрацьовує лише в клієнта, коли join_game() успішно з'єднався із сервером.
	_enter_lobby()


func _on_connection_failed() -> void:
	host_button.disabled = false
	join_button.disabled = false
	error_label.text = "Не вдалось підключитись до сервера"


func _on_game_ended() -> void:
	# Network.end_game() завжди повертає нас сюди — і після соло, і після мультиплеєра.
	show()
	host_button.disabled = false
	join_button.disabled = false
	error_label.text = ""


func _validate_name() -> bool:
	if name_edit.text.strip_edges() == "":
		error_label.text = "Введи ім'я"
		return false
	error_label.text = ""
	return true


func _enter_lobby() -> void:
	var lobby: Control = load("res://scenes/lobby/lobby.tscn").instantiate()
	lobby.name = "Lobby"
	get_tree().get_root().add_child(lobby)
	hide()

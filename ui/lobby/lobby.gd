extends Control

@onready var player_list: ItemList = $CenterContainer/VBoxContainer/PlayerList
@onready var start_button: Button = $CenterContainer/VBoxContainer/StartButton
@onready var leave_button: Button = $CenterContainer/VBoxContainer/LeaveButton


func _ready() -> void:
	Network.player_list_changed.connect(refresh_player_list)
	Network.game_error.connect(_on_game_error)

	start_button.pressed.connect(_on_start_button_pressed)
	leave_button.pressed.connect(_on_leave_button_pressed)

	# Тільки сервер може почати гру.
	start_button.disabled = not multiplayer.is_server()

	refresh_player_list()


func refresh_player_list() -> void:
	player_list.clear()

	# end_game() очищує registry і відправляє signal, коли Lobby ще може
	# існувати до кінця поточного кадру, але ENet peer уже звільнений.
	# У такому стані не можна викликати multiplayer.get_unique_id().
	if not multiplayer.has_multiplayer_peer():
		return

	var local_peer_id := multiplayer.get_unique_id()
	for player in Network.get_players():
		var peer_id: int = int(player["peer_id"])
		var player_name: String = str(player["player_name"])
		var suffix := " (ти)" if peer_id == local_peer_id else ""
		player_list.add_item(player_name + suffix)


func _on_start_button_pressed() -> void:
	Network.begin_game()


func _on_leave_button_pressed() -> void:
	Network.leave_game()


func _on_game_error(what: String) -> void:
	# V1: мінімальна реакція на помилку — просто повертаємось у Menu.
	# Пізніше тут можна показати діалог з текстом `what`.
	print("Мережева помилка: ", what)

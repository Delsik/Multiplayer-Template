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
	# Себе показуємо окремо — Network.players нас не містить (див. пояснення раніше).
	player_list.add_item("%s (ти)" % Network.player_name)
	for id: int in Network.players:
		player_list.add_item(Network.players[id])


func _on_start_button_pressed() -> void:
	Network.begin_game()


func _on_leave_button_pressed() -> void:
	Network.end_game()


func _on_game_error(what: String) -> void:
	# V1: мінімальна реакція на помилку — просто повертаємось у Menu.
	# Пізніше тут можна показати діалог з текстом `what`.
	print("Мережева помилка: ", what)

extends Node

## Порт за замовчуванням для сервера. 1024–49151, поза списком зареєстрованих портів.
const DEFAULT_PORT := 10567

## Максимальна кількість гравців (включно з хостом).
const MAX_PLAYERS := 8

## Шлях до сцени ігрового світу. У V1 це просто сцена з падаючими кубиками.
const GAME_WORLD_SCENE := "res://scenes/game/game_world.tscn"

## Мережевий peer. Існує лише поки триває хост/клієнт-сесія.
var peer: ENetMultiplayerPeer

## Ім'я локального гравця.
var player_name: String = "Player%d" % (randi() % 1000)

## Зареєстровані гравці: {peer_id: player_name}. НЕ включає себе самого.
var players: Dictionary = {}

# --- Сигнали для UI (Menu/Lobby слухають їх) ---
signal player_list_changed()
signal connection_failed()
signal connection_succeeded()
signal game_ended()
signal game_error(what: String)


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# --- Колбеки сигналів multiplayer ---

func _on_peer_connected(id: int) -> void:
	# Спрацьовує і на сервері, і на клієнтах, коли будь-хто новий приєднався.
	# Тут ми (незалежно від того, сервер ми чи клієнт) представляємось новому peer.
	register_player.rpc_id(id, player_name)


func _on_peer_disconnected(id: int) -> void:
	# Хтось (крім сервера — той обробляється окремо через _on_server_disconnected)
	# вийшов або втратив з'єднання. Гра для решти триває, просто прибираємо його
	# зі списку гравців. У V1 немає гравцевих об'єктів у GameWorld, тому більше
	# нічого чистити не треба — коли з'явиться гравцева сцена, тут буде місце
	# для деспавну персонажа цього id.
	unregister_player(id)


func _on_connected_ok() -> void:
	# Спрацьовує ЛИШЕ в клієнта: успішно з'єднались із сервером.
	connection_succeeded.emit()


func _on_connected_fail() -> void:
	multiplayer.multiplayer_peer = null
	connection_failed.emit()


func _on_server_disconnected() -> void:
	game_error.emit("Сервер розірвав з'єднання")
	end_game()


# --- Реєстрація гравців у лобі ---

@rpc("any_peer")
func register_player(new_player_name: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	players[id] = new_player_name
	player_list_changed.emit()


func unregister_player(id: int) -> void:
	players.erase(id)
	player_list_changed.emit()


func get_player_list() -> Array:
	return players.values()


# --- Старт мережі ---

func host_game(new_player_name: String) -> void:
	player_name = new_player_name
	peer = ENetMultiplayerPeer.new()
	peer.create_server(DEFAULT_PORT, MAX_PLAYERS)
	multiplayer.multiplayer_peer = peer


func join_game(ip_address: String, new_player_name: String) -> void:
	player_name = new_player_name
	peer = ENetMultiplayerPeer.new()
	peer.create_client(ip_address, DEFAULT_PORT)
	multiplayer.multiplayer_peer = peer


## Повністю завершує мережеву сесію: знищує Lobby/GameWorld, рве peer, веде в Menu.
## Викликається і при штатному завершенні гри, і при виході з лобі, і при помилках з'єднання.
func end_game() -> void:
	if has_node(^"/root/GameWorld"):
		get_node(^"/root/GameWorld").queue_free()

	var lobby := get_tree().get_root().get_node_or_null(^"Lobby")
	if lobby:
		lobby.queue_free()

	if peer:
		peer.close()
		peer = null
	multiplayer.multiplayer_peer = null

	players.clear()
	game_ended.emit()


# --- Перехід лобі → гра ---

## call_local: серверу теж треба виконати цей самий код у себе, а не лише розіслати клієнтам.
@rpc("call_local", "reliable")
func load_world() -> void:
	var world: Node3D = load(GAME_WORLD_SCENE).instantiate()
	world.name = "GameWorld"
	get_tree().get_root().add_child(world)

	var lobby := get_tree().get_root().get_node_or_null(^"Lobby")
	if lobby:
		lobby.hide()


func begin_game() -> void:
	assert(multiplayer.is_server(), "begin_game() can only be called by the server")
	load_world.rpc()
	# Гра вже почалась — нових гравців більше не приймаємо (late join не підтримуємо).
	# Той, хто спробує Join зараз, отримає звичайний connection_failed.
	if peer:
		peer.refuse_new_connections = true

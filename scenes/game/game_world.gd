extends Node3D

const FALLING_CUBE_SCENE := "res://objects/falling_cube/falling_cube.tscn"
const PLAYER_AVATAR_SCENE := "res://objects/player_avatar/player_avatar.tscn"
const PLAYER_SPAWN_POSITIONS := [
	Vector3(-3.0, 1.2, -3.0),
	Vector3(3.0, 1.2, -3.0),
	Vector3(-3.0, 1.2, 3.0),
	Vector3(3.0, 1.2, 3.0),
	Vector3(0.0, 1.2, -3.0),
	Vector3(0.0, 1.2, 3.0),
	Vector3(-3.0, 1.2, 0.0),
	Vector3(3.0, 1.2, 0.0),
]

@onready var cube_spawner: MultiplayerSpawner = $CubeSpawner
@onready var players: Node3D = $Players
@onready var player_spawner: MultiplayerSpawner = $PlayerSpawner
@onready var spawn_timer: Timer = $SpawnTimer
@onready var leave_button: Button = $UI/SafeArea/Content/LeaveButton


func _ready() -> void:
	leave_button.pressed.connect(_on_leave_button_pressed)

	# spawn_function викликається і локально (на тому, хто зве .spawn()),
	# і автоматично реплікується на решту peer — саме так, як у демці.
	cube_spawner.spawn_function = _spawn_cube
	# PlayerSpawner створює avatar однаково на server і на кожному client.
	player_spawner.spawn_function = _spawn_player
	Network.player_list_changed.connect(_sync_player_avatars)

	if multiplayer.is_server():
		spawn_timer.timeout.connect(_on_spawn_timer_timeout)

	# Навіть server не запускає таймер у _ready(). Він чекатиме явного
	# begin_simulation() після world_ready від усіх стартових peer.
	spawn_timer.stop()


## Викликається лише після стартового loading barrier.
func begin_simulation() -> void:
	if not multiplayer.is_server():
		return

	# Спершу server створює avatar для всіх peer із канонічного roster,
	# а вже потім запускає старий cube smoke test.
	_sync_player_avatars()
	spawn_timer.start()


func _on_leave_button_pressed() -> void:
	# Спрацьовує однаково для сервера, клієнта і соло-режиму:
	# Network.leave_game() сам розбереться, кого й що треба звільнити,
	# і позначить цей вихід як свідомий (без спроб перепідключення).
	Network.leave_game()


## Викликається Network() одразу, як тільки late-join гравець підтвердив
## готовність (world_ready). На відміну від _spawn_cube(), яка показує лише
## МАЙБУТНІ кубики, ця функція ретроактивно показує все, що вже існує —
## новачок бачить те саме, що й ті, хто грає давно.
func grant_visibility_to_late_joiner(peer_id: int) -> void:
	var cubes := get_node(^"Cubes")
	for cube in cubes.get_children():
		var cube_synchronizer: MultiplayerSynchronizer = cube.get_node(^"MultiplayerSynchronizer")
		cube_synchronizer.set_visibility_for(peer_id, true)

	for avatar in players.get_children():
		var avatar_synchronizer: MultiplayerSynchronizer = avatar.get_node(^"MultiplayerSynchronizer")
		avatar_synchronizer.set_visibility_for(peer_id, true)


## Приводить server-side avatar nodes до канонічного Network roster.
## Викликається при старті світу, при новому підключенні та після disconnect.
func _sync_player_avatars() -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return

	var session_peer_ids: Array[int] = []
	for player_profile in Network.get_players():
		var peer_id: int = int(player_profile["peer_id"])
		session_peer_ids.append(peer_id)

		if _get_player_avatar(peer_id):
			continue
		player_spawner.spawn(player_profile)

	for avatar in players.get_children():
		var avatar_peer_id := int(str(avatar.name).trim_prefix("Player_"))
		if session_peer_ids.has(avatar_peer_id):
			continue
		player_spawner.despawn(avatar)


## spawn_function викликається локально на server і автоматично на всіх peer.
func _spawn_player(player_profile: Dictionary) -> Node:
	var peer_id: int = int(player_profile["peer_id"])
	var display_name: String = str(player_profile["player_name"])
	var avatar: CharacterBody3D = load(PLAYER_AVATAR_SCENE).instantiate()

	avatar.configure(peer_id, display_name)
	avatar.position = PLAYER_SPAWN_POSITIONS[(peer_id - 1) % PLAYER_SPAWN_POSITIONS.size()]

	if multiplayer.is_server():
		var synchronizer: MultiplayerSynchronizer = avatar.get_node(^"MultiplayerSynchronizer")
		for connected_peer_id in multiplayer.get_peers():
			if Network.is_peer_ready(connected_peer_id):
				synchronizer.set_visibility_for(connected_peer_id, true)

	return avatar


func _get_player_avatar(peer_id: int) -> CharacterBody3D:
	return players.get_node_or_null(NodePath("Player_%d" % peer_id)) as CharacterBody3D


## Локальний peer читає platform-neutral InputMap. На ПК це вже WASD;
## у наступному кроці touch controls натискатимуть ці самі actions.
func _physics_process(_delta: float) -> void:
	var move_intent := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if multiplayer.is_server():
		_set_player_move_intent(1, move_intent)
	else:
		submit_move_intent.rpc_id(1, move_intent)


## Клієнт надсилає intent, а не готову позицію. Server визначає sender ID,
## нормалізує значення і змінює тільки avatar відповідного peer.
@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func submit_move_intent(move_intent: Vector2) -> void:
	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	_set_player_move_intent(sender_id, move_intent)


func _set_player_move_intent(peer_id: int, move_intent: Vector2) -> void:
	var avatar := _get_player_avatar(peer_id)
	if not avatar or not avatar.has_method("set_move_intent"):
		return

	# Input.get_vector() уже повертає довжину до 1, але server все одно
	# обмежує RPC payload, бо клієнтським даним не можна довіряти.
	avatar.set_move_intent(move_intent.limit_length(1.0))


func _on_spawn_timer_timeout() -> void:
	var spawn_pos := Vector3(randf_range(-3.0, 3.0), 6.0, randf_range(-3.0, 3.0))
	cube_spawner.spawn(spawn_pos)


## Викликається MultiplayerSpawner-ом і на сервері, і (через реплікацію) на кожному клієнті.
## Аргумент spawn_pos — те саме значення, що передали в .spawn() на сервері.
func _spawn_cube(spawn_pos: Vector3) -> Node:
	var cube: RigidBody3D = load(FALLING_CUBE_SCENE).instantiate()
	cube.position = spawn_pos

	# Виставляємо visibility ТУТ, а не через сигнал spawned — це офіційно
	# задокументований патерн (виставляти видимість синхронно, до того як
	# спавнер розішле репліковані пакети далі). Виконується лише на сервері:
	# на клієнтах ця сама функція теж викликається (як частина spawn_function),
	# але там немає сенсу й немає прав керувати чужою видимістю.
	if multiplayer.is_server():
		var sync: MultiplayerSynchronizer = cube.get_node(^"MultiplayerSynchronizer")
		for peer_id in multiplayer.get_peers():
			if Network.is_peer_ready(peer_id):
				sync.set_visibility_for(peer_id, true)

	return cube

extends Node3D

const FALLING_CUBE_SCENE := "res://objects/falling_cube/falling_cube.tscn"

@onready var cube_spawner: MultiplayerSpawner = $CubeSpawner
@onready var spawn_timer: Timer = $SpawnTimer
@onready var leave_button: Button = $UI/SafeArea/Content/LeaveButton


func _ready() -> void:
	leave_button.pressed.connect(_on_leave_button_pressed)

	# spawn_function викликається і локально (на тому, хто зве .spawn()),
	# і автоматично реплікується на решту peer — саме так, як у демці.
	cube_spawner.spawn_function = _spawn_cube

	if multiplayer.is_server():
		spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	else:
		# Тільки сервер вирішує, коли і де з'являється новий кубик.
		spawn_timer.stop()


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
		var sync: MultiplayerSynchronizer = cube.get_node(^"MultiplayerSynchronizer")
		sync.set_visibility_for(peer_id, true)


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

extends Node3D

const FALLING_CUBE_SCENE := "res://objects/falling_cube/falling_cube.tscn"

@onready var cube_spawner: MultiplayerSpawner = $CubeSpawner
@onready var spawn_timer: Timer = $SpawnTimer
@onready var leave_button: Button = $UI/LeaveButton


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
	# Network.end_game() сам розбереться, кого й що треба звільнити.
	Network.end_game()


func _on_spawn_timer_timeout() -> void:
	var spawn_pos := Vector3(randf_range(-3.0, 3.0), 6.0, randf_range(-3.0, 3.0))
	cube_spawner.spawn(spawn_pos)


## Викликається MultiplayerSpawner-ом і на сервері, і (через реплікацію) на кожному клієнті.
## Аргумент spawn_pos — те саме значення, що передали в .spawn() на сервері.
func _spawn_cube(spawn_pos: Vector3) -> Node:
	var cube: RigidBody3D = load(FALLING_CUBE_SCENE).instantiate()
	cube.position = spawn_pos
	return cube

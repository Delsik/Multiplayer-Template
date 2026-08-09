extends RigidBody3D


func _enter_tree() -> void:
	# Сервер (id=1) — єдиний, хто рахує фізику цього кубика.
	set_multiplayer_authority(1)


func _ready() -> void:
	if not is_multiplayer_authority():
		# Клієнти НЕ симулюють фізику самі, інакше кожен матиме власну,
		# розсинхронізовану версію падіння. Вони лише відображають позицію,
		# яку присилає MultiplayerSynchronizer від сервера.
		freeze = true

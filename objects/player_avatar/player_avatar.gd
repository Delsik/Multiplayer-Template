extends CharacterBody3D

## Мінімальний server-authoritative avatar для network test.
## Це не жанровий персонаж: у ньому немає ані анімацій, ані inventory,
## ані combat. Його єдина ціль — перевірити lifecycle, ownership,
## input intent і реплікацію між повноцінними Godot-клієнтами.

const MOVE_SPEED := 4.0
const GRAVITY := 20.0
const PLAYER_COLORS := [
	Color("#5B8CFF"),
	Color("#FF6B9A"),
	Color("#F2C94C"),
	Color("#6FCF97"),
	Color("#BB6BD9"),
	Color("#56CCF2"),
	Color("#F2994A"),
	Color("#EB5757"),
]

var player_peer_id := 0
var _player_name := ""
var _move_intent := Vector2.ZERO

@onready var body_mesh: MeshInstance3D = $MeshInstance3D
@onready var name_label: Label3D = $NameLabel


## Викликається GameWorld до add_child(). Зберігаємо лише дані;
## вузли MeshInstance3D та Label3D будуть доступні в _ready().
func configure(peer_id: int, display_name: String) -> void:
	player_peer_id = peer_id
	_player_name = display_name
	name = "Player_%d" % peer_id


func _ready() -> void:
	name_label.text = _player_name

	var material := StandardMaterial3D.new()
	material.albedo_color = PLAYER_COLORS[player_peer_id % PLAYER_COLORS.size()]
	material.roughness = 0.65
	body_mesh.material_override = material


## Викликається виключно server-ом через GameWorld після перевірки sender ID.
func set_move_intent(move_intent: Vector2) -> void:
	_move_intent = move_intent.limit_length(1.0)


func _physics_process(delta: float) -> void:
	# Лише server симулює CharacterBody3D. Клієнти отримують готову position
	# через MultiplayerSynchronizer і не мають права самостійно рухати avatar.
	if not multiplayer.is_server():
		return

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	var horizontal_velocity := Vector3(_move_intent.x, 0.0, _move_intent.y) * MOVE_SPEED
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z
	move_and_slide()

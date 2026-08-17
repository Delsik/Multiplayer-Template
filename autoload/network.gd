extends Node

## Порт за замовчуванням для сервера. 1024–49151, поза списком зареєстрованих портів.
const DEFAULT_PORT := 10567

## Загальний ліміт гравців у сесії, включно з хостом.
const MAX_TOTAL_PLAYERS := 8
## ENet create_server() очікує лише кількість віддалених клієнтів.
const MAX_REMOTE_CLIENTS := MAX_TOTAL_PLAYERS - 1

## Шлях до сцени ігрового світу. У V1 це просто сцена з падаючими кубиками.
const GAME_WORLD_SCENE := "res://scenes/game/game_world.tscn"
const LOADING_SCREEN_SCENE := "res://ui/loading/loading_screen.tscn"

## Мережевий peer. Існує лише поки триває хост/клієнт-сесія.
var peer: ENetMultiplayerPeer

## Ім'я локального гравця.
var player_name: String = "Player%d" % (randi() % 1000)

## Канонічний список усіх гравців поточної сесії:
## {peer_id: player_name}. У listen-server режимі завжди включає host з peer_id = 1.
## Кожен клієнт має локальну синхронізовану копію цього реєстру.
var players_by_peer_id: Dictionary = {}

## Id гравців, які зараз "приєднуються на льоту" й ще не підтвердили,
## що GameWorld у них локально готовий. Поки peer тут — йому НЕ показуємо
## жодних нових об'єктів (див. is_peer_ready() і game_world.gd).
var _pending_late_joiners: Array[int] = []

# --- LAN-виявлення (щоб не вводити IP вручну на мобільних) ---
const DISCOVERY_PORT := 10568
const DISCOVERY_REQUEST := "MP_TEMPLATE_DISCOVER"
const DISCOVERY_RESPONSE_PREFIX := "MP_TEMPLATE_HOST:"

var _discovery_server: PacketPeerUDP  # активний лише на хості — відповідає на запити
var _discovery_client: PacketPeerUDP  # активний лише під час сканування
var _discovery_scan_timer: Timer

signal host_found(host_name: String, ip: String)
signal scan_finished()

# --- Автоматичне перепідключення (для мобільних: згортання застосунку,
# дзвінок, перемикання Wi-Fi↔мобільний інтернет тощо) ---
const MAX_RECONNECT_ATTEMPTS := 5
const RECONNECT_DELAY := 2.0

var _last_join_ip: String = ""
var _intentional_disconnect := false
var _is_reconnecting := false
var _reconnect_attempts := 0
var _reconnect_timer: Timer

## attempt/max_attempts — для UI ("Перепідключення... 2/5").
signal reconnecting(attempt: int, max_attempts: int)
signal reconnect_failed()
signal connection_cancelled()

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


func _process(_delta: float) -> void:
	# Хост відповідає на запити "чи є тут гра?" від сканерів у мережі.
	if _discovery_server:
		while _discovery_server.get_available_packet_count() > 0:
			var packet := _discovery_server.get_packet().get_string_from_utf8()
			if packet == DISCOVERY_REQUEST:
				var sender_ip := _discovery_server.get_packet_ip()
				var sender_port := _discovery_server.get_packet_port()
				_discovery_server.set_dest_address(sender_ip, sender_port)
				_discovery_server.put_packet((DISCOVERY_RESPONSE_PREFIX + player_name).to_utf8_buffer())

	# Клієнт, що сканує мережу, збирає відповіді від усіх хостів навколо.
	if _discovery_client:
		while _discovery_client.get_available_packet_count() > 0:
			var packet := _discovery_client.get_packet().get_string_from_utf8()
			if packet.begins_with(DISCOVERY_RESPONSE_PREFIX):
				var found_name := packet.substr(DISCOVERY_RESPONSE_PREFIX.length())
				var ip := _discovery_client.get_packet_ip()
				host_found.emit(found_name, ip)


# --- Колбеки сигналів multiplayer ---

func _on_peer_connected(id: int) -> void:
	# Спрацьовує і на сервері, і на клієнтах, коли будь-хто новий приєднався.
	# Тут ми (незалежно від того, сервер ми чи клієнт) представляємось новому peer.
	# Тільки сервер тримає канонічний roster. Новий peer спершу отримує
	# повний snapshot усіх, хто вже є в сесії, включно з host.
	if multiplayer.is_server():
		sync_player_registry.rpc_id(id, players_by_peer_id)

	# Late join: якщо гра вже триває, лише сервер наздоганяє новачка світом.
	# Доки peer не підтвердив готовність (world_ready), він у _pending_late_joiners
	# і не отримує видимість жодних нових об'єктів — див. game_world.gd.
	if multiplayer.is_server() and has_node(^"/root/GameWorld"):
		_pending_late_joiners.append(id)
		load_world_for_late_joiner.rpc_id(id)


func _on_peer_disconnected(id: int) -> void:
	# Сервер є єдиним джерелом правди про склад сесії. Він прибирає peer
	# і розсилає новий snapshot усім, хто залишився підключеним.
	if multiplayer.is_server():
		unregister_player(id)
		_publish_player_registry()

	_pending_late_joiners.erase(id)


func _on_connected_ok() -> void:
	# Спрацьовує лише в клієнта: успішно з’єднались із сервером
	# (включно з успішним перепідключенням після розриву).
	_is_reconnecting = false

	# Локально додаємо себе відразу, щоб Lobby не показував порожній список,
	# а потім server поверне повний канонічний snapshot через sync_player_registry.
	_upsert_player(multiplayer.get_unique_id(), player_name)
	register_player.rpc_id(1, player_name)
	connection_succeeded.emit()


func _on_connected_fail() -> void:
	multiplayer.multiplayer_peer = null
	if _is_reconnecting:
		# Ця конкретна спроба не вдалась — пробуємо ще раз (або здаємось,
		# якщо вичерпали ліміт спроб — це вирішує сама _try_reconnect()).
		_try_reconnect()
		return
	connection_failed.emit()


func _on_server_disconnected() -> void:
	if _intentional_disconnect:
		# Гравець сам натиснув "Вийти" — це очікувано, перепідключатись не треба.
		_intentional_disconnect = false
		game_error.emit("Сервер розірвав з'єднання")
		end_game()
		return

	# Неочікуваний розрив (застосунок згорнули, дзвінок, мережа моргнула) —
	# не викидаємо одразу в Menu, а пробуємо тихо перепідключитись.
	_cleanup_local_scene()
	_is_reconnecting = true
	_reconnect_attempts = 0
	_try_reconnect()


## Викликай це з UI (кнопка "Вийти"), а НЕ end_game() напряму — так ми знаємо,
## що розрив свідомий, і НЕ намагаємось перепідключитись після нього.
func leave_game() -> void:
	_intentional_disconnect = true
	end_game()


func _try_reconnect() -> void:
	_reconnect_attempts += 1
	if _reconnect_attempts > MAX_RECONNECT_ATTEMPTS:
		_is_reconnecting = false
		reconnect_failed.emit()
		end_game()
		return

	reconnecting.emit(_reconnect_attempts, MAX_RECONNECT_ATTEMPTS)

	# Невелика пауза перед спробою — одразу після повернення з фону мережа
	# на пристрої зазвичай ще не готова, миттєва спроба майже завжди провалиться.
	if _reconnect_timer:
		_reconnect_timer.queue_free()
	_reconnect_timer = Timer.new()
	_reconnect_timer.wait_time = RECONNECT_DELAY
	_reconnect_timer.one_shot = true
	_reconnect_timer.timeout.connect(_on_reconnect_timer_timeout)
	add_child(_reconnect_timer)
	_reconnect_timer.start()


func _on_reconnect_timer_timeout() -> void:
	join_game(_last_join_ip, player_name)


## Скидає тільки локальний transient state перед новим Host або Join.
## Тут НЕ викликаємо end_game(): Menu вже керує тим, коли попередня сесія
## завершена, а нова спроба не повинна штучно запускати game_ended/UI cleanup.
func _prepare_for_new_session() -> void:
	_intentional_disconnect = false
	_is_reconnecting = false
	_reconnect_attempts = 0

	if _reconnect_timer:
		_reconnect_timer.stop()
		_reconnect_timer.queue_free()
		_reconnect_timer = null


## Додає або оновлює один профіль у локальній копії session player registry.
## У V1 профіль містить лише ім’я; пізніше сюди природно додадуться
## колір, avatar, ready та інші спільні дані гравця.
func _upsert_player(peer_id: int, new_player_name: String) -> void:
	players_by_peer_id[peer_id] = new_player_name
	player_list_changed.emit()


## Сервер розсилає канонічний roster усім peer після зміни складу сесії.
func _publish_player_registry() -> void:
	if not multiplayer.is_server():
		return
	sync_player_registry.rpc(players_by_peer_id)


## Застосовує повний snapshot, який надійшов тільки від server authority.
## call_local важливий: після publish server теж проходить через той самий
## шлях оновлення registry, що й клієнти.
@rpc("authority", "call_local", "reliable")
func sync_player_registry(server_players_by_peer_id: Dictionary) -> void:
	players_by_peer_id = server_players_by_peer_id.duplicate()
	player_list_changed.emit()


# --- Реєстрація гравців у лобі ---

## RPC надходить від конкретного ENet peer. Ідентичність беремо не з даних,
## які надсилає клієнт, а з remote sender ID, який призначив сервер/ENet.
@rpc("any_peer", "reliable")
func register_player(new_player_name: String) -> void:
	# Клієнт надсилає лише власне ім’я. Сам peer_id беремо з ENet sender,
	# тому клієнт не може зареєструватися під ID іншого гравця.
	if not multiplayer.is_server():
		return

	var peer_id := multiplayer.get_remote_sender_id()
	_upsert_player(peer_id, new_player_name)
	_publish_player_registry()


func unregister_player(peer_id: int) -> void:
	if not players_by_peer_id.erase(peer_id):
		return
	player_list_changed.emit()


## Повертає стабільний snapshot усіх session players.
## Host (peer_id = 1) завжди йде першим; решта peer впорядковані за ID.
func get_players() -> Array[Dictionary]:
	var peer_ids: Array[int] = []
	for peer_id: int in players_by_peer_id:
		peer_ids.append(peer_id)
	peer_ids.sort()

	var registered_players: Array[Dictionary] = []
	for peer_id in peer_ids:
		registered_players.append({
			"peer_id": peer_id,
			"player_name": str(players_by_peer_id[peer_id]),
		})

	return registered_players
# --- Старт мережі ---

## Створює ENet-сервер. Повертає true лише коли peer успішно запущено.
func host_game(new_player_name: String) -> bool:
	_prepare_for_new_session()
	player_name = new_player_name
	_last_join_ip = ""
	peer = ENetMultiplayerPeer.new()

	var error := peer.create_server(DEFAULT_PORT, MAX_REMOTE_CLIENTS)
	if error != OK:
		peer = null
		game_error.emit("Не вдалося створити сервер: %s" % error_string(error))
		return false

	multiplayer.multiplayer_peer = peer
	_upsert_player(1, player_name)
	return true


## Починає підключення ENet-клієнта. Повертає false лише якщо peer не можна
## створити синхронно. Помилка недоступного сервера далі прийде стандартним
## сигналом connection_failed.
func join_game(ip_address: String, new_player_name: String) -> bool:
	_prepare_for_new_session()
	player_name = new_player_name
	peer = ENetMultiplayerPeer.new()

	var error := peer.create_client(ip_address, DEFAULT_PORT)
	if error != OK:
		peer = null
		game_error.emit("Не вдалося почати підключення: %s" % error_string(error))
		return false

	_last_join_ip = ip_address
	multiplayer.multiplayer_peer = peer
	return true


## Перериває поточну спробу підключення чи перепідключення (наприклад,
## гравець натиснув "Скасувати"). На відміну від leave_game(), тут немає
## активної гри, яку треба звільняти — лише незавершене з'єднання.
func cancel_connecting() -> void:
	_is_reconnecting = false
	if _reconnect_timer:
		_reconnect_timer.stop()
	if peer:
		peer.close()
		peer = null
	multiplayer.multiplayer_peer = null
	connection_cancelled.emit()


## Викликається з Menu ЛИШЕ для Host (не для Solo) — щоб соло-сесія
## не "світилась" у сканерах мережі, попри те що вона технічно теж сервер.
func start_lan_discovery_server() -> void:
	_discovery_server = PacketPeerUDP.new()
	_discovery_server.bind(DISCOVERY_PORT)


func stop_lan_discovery_server() -> void:
	if _discovery_server:
		_discovery_server.close()
		_discovery_server = null


## Розсилає запит по локальній мережі й ~2 секунди збирає відповіді.
## Кожен знайдений хост — окремий сигнал host_found(ім'я, ip).
func scan_for_hosts() -> void:
	_discovery_client = PacketPeerUDP.new()
	_discovery_client.set_broadcast_enabled(true)
	_discovery_client.bind(0)
	_discovery_client.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	_discovery_client.put_packet(DISCOVERY_REQUEST.to_utf8_buffer())

	if _discovery_scan_timer:
		_discovery_scan_timer.queue_free()
	_discovery_scan_timer = Timer.new()
	_discovery_scan_timer.wait_time = 2.0
	_discovery_scan_timer.one_shot = true
	_discovery_scan_timer.timeout.connect(_on_scan_timeout)
	add_child(_discovery_scan_timer)
	_discovery_scan_timer.start()


func _on_scan_timeout() -> void:
	if _discovery_client:
		_discovery_client.close()
		_discovery_client = null
	scan_finished.emit()


## Повністю завершує мережеву сесію: знищує Lobby/GameWorld, рве peer, веде в Menu.
## Викликається і при штатному завершенні гри, і при виході з лобі, і коли
## перепідключення остаточно не вдалось (вичерпано MAX_RECONNECT_ATTEMPTS).
func end_game() -> void:
	stop_lan_discovery_server()
	_cleanup_local_scene()

	if peer:
		peer.close()
		peer = null
	multiplayer.multiplayer_peer = null

	players_by_peer_id.clear()
	player_list_changed.emit()
	game_ended.emit()


func _cleanup_local_scene() -> void:
	if has_node(^"/root/GameWorld"):
		get_node(^"/root/GameWorld").queue_free()

	var lobby := get_tree().get_root().get_node_or_null(^"Lobby")
	if lobby:
		lobby.queue_free()


# --- Перехід лобі → гра ---

## call_local: серверу теж треба виконати цей самий код у себе, а не лише розіслати клієнтам.
## Використовується лише для СИНХРОННОГО старту гри — коли всі поточні гравці
## переходять у GameWorld одночасно (begin_game(), .rpc() без адресата).
@rpc("call_local", "reliable")
func load_world() -> void:
	await _create_world()


## Без call_local: викликається сервером через .rpc_id(id) ЛИШЕ для гравця,
## що приєднався до вже запущеної гри. Якби тут був call_local, сервер створив
## би собі другий GameWorld при кожному новому підключенні — саме тому ця
## функція окрема, а не повторне використання load_world().
@rpc("reliable")
func load_world_for_late_joiner() -> void:
	await _create_world()
	# Повідомляємо сервер: "у мене вже є GameWorld, можна відновлювати спавн".
	world_ready.rpc_id(1)


## Клієнт, що щойно приєднався, підтверджує готовність. Виконує щось лише
## на сервері — на клієнтах ця RPC просто ніколи не буде викликана з їхнього боку.
@rpc("any_peer", "reliable")
func world_ready() -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	_pending_late_joiners.erase(id)

	# Гравець тепер "готовий" — показуємо йому все, що вже відбувається
	# в грі, а не лише те, що з'явиться після цього моменту.
	var world := get_tree().get_root().get_node_or_null(^"GameWorld")
	if world and world.has_method("grant_visibility_to_late_joiner"):
		world.grant_visibility_to_late_joiner(id)


## Чи можна показувати цьому peer нові репліковані об'єкти прямо зараз.
## Використовується в game_world.gd при видачі visibility новоствореним кубикам.
func is_peer_ready(id: int) -> bool:
	return not _pending_late_joiners.has(id)


func _create_world() -> void:
	var loading_screen: CanvasLayer = load(LOADING_SCREEN_SCENE).instantiate()
	get_tree().get_root().add_child(loading_screen)

	# Потокове завантаження — не блокує кадр, на відміну від звичайного load().
	# Для нашої крихітної тестової сцени різниця непомітна, але для реального
	# наповнення GameWorld (текстури, моделі) саме це запобігає "заморозці".
	ResourceLoader.load_threaded_request(GAME_WORLD_SCENE)

	var status := ResourceLoader.load_threaded_get_status(GAME_WORLD_SCENE)
	while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
		status = ResourceLoader.load_threaded_get_status(GAME_WORLD_SCENE)

	if status != ResourceLoader.THREAD_LOAD_LOADED:
		push_error("Не вдалось завантажити GameWorld: статус %d" % status)
		loading_screen.queue_free()
		return

	var world_scene: PackedScene = ResourceLoader.load_threaded_get(GAME_WORLD_SCENE)
	var world: Node3D = world_scene.instantiate()
	world.name = "GameWorld"
	get_tree().get_root().add_child(world)

	var lobby := get_tree().get_root().get_node_or_null(^"Lobby")
	if lobby:
		lobby.hide()

	loading_screen.queue_free()


func begin_game() -> void:
	assert(multiplayer.is_server(), "begin_game() can only be called by the server")
	load_world.rpc()

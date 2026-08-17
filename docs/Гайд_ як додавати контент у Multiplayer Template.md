# Гайд: як додавати контент у Multiplayer Template

Цей гайд показує, як перетворити `Multiplayer Template v0.1` на основу конкретної гри, не ламаючи Host/Join, Android-клієнт, loading barrier або late join.

> **Починай з маленького end-to-end vertical slice.** Не роби одразу inventory, crafting, combat і відкритий світ. Спочатку додай одну server-authoritative механіку, перевір її на Windows + Android, а потім нарощуй гру навколо вже підтвердженого циклу.

## 1. Найкоротший шлях до власної гри

Якщо тобі не потрібні test куби та test avatar, найпростіший шлях такий:

```text
1. Зробити копію scenes/game/game_world.tscn → scenes/game/my_game_world.tscn.
2. Прибрати з копії тестову підлогу, куби, camera та avatar лише тоді,
   коли маєш власну мінімальну заміну.
3. Встановити шлях нової сцени у GAME_WORLD_SCENE в autoload/network.gd.
4. Додати одну маленьку server-authoritative механіку.
5. Пройти тест Windows Host + Android Client.
```

На самому початку **не переписуй `Network`**. У більшості майбутніх ігор достатньо змінити лише scene path і весь gameplay додавати до власного world script.

## 2. Мінімальна власна GameWorld-сцена

Створи, наприклад:

```text
scenes/game/coin_arena.tscn
scenes/game/coin_arena.gd
```

Root node має бути `Node3D`. Додай хоча б `Camera3D`, `DirectionalLight3D`, `WorldEnvironment` за потреби та `CanvasLayer` для свого UI.

У `autoload/network.gd` знайди константу, яка зараз вказує на demo world, наприклад:

```gdscript
const GAME_WORLD_SCENE := "res://scenes/game/game_world.tscn"
```

і заміни лише шлях:

```gdscript
const GAME_WORLD_SCENE := "res://scenes/game/coin_arena.tscn"
```

`Network` сам надасть root node runtime-ім’я `GameWorld`, тому не треба називати файл або root node саме так у редакторі.

Мінімальний `coin_arena.gd`:

```gdscript
extends Node3D

## Викликається Network лише після того, як усі гравці стартового Lobby
## завершили local loading цієї сцени.
func begin_simulation() -> void:
	if not multiplayer.is_server():
		return

	print("Матч стартував; тут запускаються правила конкретної гри")


## Потрібно лише тоді, коли в грі вже є об’єкти, створені до late join.
## Поки таких об’єктів немає, можна лишити порожнім.
func grant_visibility_to_late_joiner(peer_id: int) -> void:
	pass
```

Перший тест: Windows Host і Android Client повинні дійти до цієї порожньої сцени після Start. Це вже доводить, що ти безпечно замінив demo world.

## 3. Ментальна модель: де писати новий код

| Потреба | Правильне місце |
|---|---|
| Кнопка Menu, IP, LAN scan, reconnect | `ui/menu/` або `autoload/network.gd`, але не GameWorld. |
| Lobby UI, Ready/Start UI | `ui/lobby/`. |
| Правило раунду, score, таймер, spawn предметів | Script твоєї GameWorld або окремий GameMode node усередині неї. |
| Новий object у світі | `objects/<назва>/` + його scene/script. |
| Мобільна action-кнопка | `ui/touch_controls/`; вона має подавати InputMap action, а не RPC. |
| Перевірка client action | Server RPC у GameWorld або у вузькому server-side gameplay controller. |
| Збереження profile/settings | Окремий future autoload; не змішуй із `Network`. |

## 4. Мініприклад: server-authoritative collectable

Приклад не призначений для копіювання «цілим блоком» у будь-яку гру. Його мета — показати межу відповідальності: client просить взаємодію, server перевіряє і змінює світ.

### Крок A. Сцена предмета

Створи `objects/coin/coin.tscn` з root `Area3D`, `MeshInstance3D` і `CollisionShape3D`. Постав root node у group `collectables`.

Створи `objects/coin/coin.gd`:

```gdscript
extends Area3D

@export var value := 1

func collect() -> void:
	# Цей метод має викликати лише server після власної перевірки.
	queue_free()
```

### Крок B. Server створює предмет

У `coin_arena.gd` зберігай references до предметів або використай `MultiplayerSpawner`. Для першого маленького тесту можна створити предмет server-ом на старті:

```gdscript
const COIN_SCENE := preload("res://objects/coin/coin.tscn")

func begin_simulation() -> void:
	if not multiplayer.is_server():
		return

	var coin := COIN_SCENE.instantiate()
	coin.position = Vector3(0.0, 0.5, 0.0)
	add_child(coin)
```

Коли предмет має бути видимим і існувати у всіх peer, перетвори цей простий spawn на `MultiplayerSpawner` за тим самим патерном, який зараз використовують test куби.

### Крок C. Client просить interaction, server перевіряє

```gdscript
@rpc("any_peer", "call_remote", "reliable")
func request_collect(coin_path: NodePath) -> void:
	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	var coin := get_node_or_null(coin_path) as Area3D
	var player := _get_server_player_node(sender_id)
	if not coin or not player:
		return

	if player.global_position.distance_to(coin.global_position) > 2.0:
		return

	coin.collect()
	# Тут же можна збільшити server score відповідного peer.
```

Ключова ідея: client не має права надіслати `score += 1` або `queue_free()` для предмета. Client надсилає тільки прохання; server перевіряє відстань і сам вносить зміну.

## 5. Мініприклад: кнопка мобільної дії без окремої мережевої логіки

Virtual joystick у template вже перетворює touch на InputMap actions. Для нової дії роби те саме.

### Крок A. Створи action

У **Project → Project Settings → Input Map** додай:

```text
interact
```

Для ПК прив’яжи, наприклад, `E`.

### Крок B. Mobile UI подає той самий action

У touch HUD створи візуальну кнопку `InteractButton`. Її задача лише така:

```gdscript
func _on_interact_button_down() -> void:
	Input.action_press("interact")

func _on_interact_button_up() -> void:
	Input.action_release("interact")
```

### Крок C. GameWorld читає action і звертається до server

```gdscript
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return

	if multiplayer.is_server():
		_try_interact_for_peer(1)
	else:
		request_interact.rpc_id(1)
```

Тепер клавіатура та touch UI обидва активують один gameplay path. Не створюй окремі RPC `mobile_interact` і `desktop_interact`.

## 6. Мініприклад: простий раундовий таймер

Правила раунду мають бути server-authoritative. Client може бачити час, але не має його визначати.

```gdscript
var round_seconds_left := 60.0
var round_running := false

func begin_simulation() -> void:
	if not multiplayer.is_server():
		return

	round_seconds_left = 60.0
	round_running = true

func _process(delta: float) -> void:
	if not multiplayer.is_server() or not round_running:
		return

	round_seconds_left = maxf(round_seconds_left - delta, 0.0)
	if is_zero_approx(round_seconds_left):
		round_running = false
		finish_round()

func finish_round() -> void:
	# Server вирішує результат; далі можна RPC-ом показати score screen.
	print("Раунд завершено")
```

Коли з’явиться UI таймера, реплікуй лише необхідний state або час завершення раунду, а не окремо запускай незалежні client timers як джерело правди.

## 7. Як правильно додавати реплікований object

Якщо механіка створює object, що мають бачити всі гравці, використовуй цей чеклист:

| Питання | Рішення |
|---|---|
| Хто має право створити object? | Зазвичай тільки server. |
| Як object з’являється на peer? | `MultiplayerSpawner` у твій GameWorld. |
| Який state реплікується? | Тільки мінімально потрібні property через `MultiplayerSynchronizer`. |
| Хто змінює state? | Authority, зазвичай server. |
| Що робити з late join? | `Public Visibility = false`; server відкриває visibility тільки після `world_ready`. |
| Як знищити object? | Server викликає `queue_free()` на об’єкті, створеному через Spawner. |

Не надсилай кожен visual detail через RPC. Реплікуй стан; локальний client сам відтворює звук, частинки, анімацію та UI на основі цього стану.

## 8. Типовий порядок роботи над новою грою

1. Зроби копію repo або створи нову гілку для конкретної гри.
2. Збережи `Network`, Menu, Lobby, Loading і Android export як основу.
3. Створи власну GameWorld-сцену та переконайся, що Host + Android Client доходять до неї.
4. Додай одну базову interaction-механіку.
5. Зроби її server-authoritative.
6. Додай візуальний feedback на PC і mobile.
7. Пройди test checklist нижче.
8. Лише після цього додавай наступну систему.

## 9. Checklist після кожної механіки

| Сценарій | Очікуваний результат |
|---|---|
| Solo | Механіка працює без мережевих errors. |
| Windows Host + Windows Client | Обидва peer бачать той самий authoritative результат. |
| Windows Host + Android Client | Touch і клавіатура запускають той самий gameplay path. |
| Client відправляє неправильний RPC payload | Server відкидає/нормалізує його без crash. |
| Client виходить | Його network objects прибираються без console errors. |
| Client приєднується під час матчу | Він бачить об’єкти, які мають бути видимими. |
| Ручний IP Join | Працює незалежно від LAN scan. |

## 10. Коли варто змінювати core template

Змінюй `Network` лише якщо потреба справді однакова для майбутніх ігор: наприклад, нова транспортна стратегія, універсальна profile system, ready state в lobby, host migration або online relay.

Не клади в `Network` те, що належить одній грі: `coin_score`, карта, правила перемоги, биоми, зброя, блоки, craft recipes, вороги. Ці речі мають жити в GameWorld/GameMode конкретної гри.

## 11. Перший крок для Minecraft/Terraria-подібної гри

Для великого світу не починай із terrain generation або десятків чанків. Найкращий vertical slice:

```text
1. Маленька плоска arena.
2. Один server-spawned block або ресурс.
3. Одна дія «поставити» чи «зібрати».
4. Server validation відстані.
5. Replication object для всіх peer.
6. Windows Host + Android Client test.
```

Якщо цей slice працює, тоді вже можна впевнено додавати chunk system, інвентар, damage, biome generation та оптимізацію. Якщо почати з великих систем, помилки network authority буде дуже складно відокремити від проблем gameplay.

# Архітектура Multiplayer Template v0.1

Цей репозиторій — **не гра**, а перевикористовуваний Godot 4.7 шаблон для майбутніх повноцінних мультиплеєрних ігор, у яких Windows/desktop та Android-пристрої запускають однаковий Godot-клієнт, бачать спільний світ і грають разом.

> **Призначення template:** дати робочий session lifecycle, PC + mobile input, базовий server-authoritative мережевий test harness і Android debug deployment. Конкретні правила, жанр, персонажі, інвентар, combat, будівництво та UI гри свідомо не входять до ядра.

## 1. Що вже гарантує template

| Напрям | Стан v0.1 |
|---|---|
| Платформи | Windows/Desktop і Android native Godot-клієнти; mobile renderer, safe area та virtual joystick. |
| Підключення | Solo, Host, Join за IP, LAN scan, ручний IP fallback, скасування з’єднання, зрозумілі помилки. |
| Сесія | Menu → Lobby → GameWorld, єдиний roster із host, керований Start, вихід і reconnect. |
| Спільний світ | Loading barrier для початкових гравців, late join, server-controlled visibility для вже існуючих реплікованих node. |
| Test harness | Server-authoritative placeholder avatar, input intent, spawn/despawn, тестова підлога й куби. |
| Android deployment | Runnable debug preset, Android package ID, базові LAN permissions, safe build artifacts у `.gitignore`. |

## 2. Дерево активних сцен

Усі три екрани є окремими прямими дітьми root. Вони не перемикаються через `change_scene_to_file()`.

```text
root
├── Menu       головна сцена: Solo / Host / Join / LAN scan
├── Lobby      створюється після Host або успішного Join
└── GameWorld  створюється після Start або у Solo
```

`Network` створює `GameWorld` вручну й додає до root. Це дає lifecycle-коду точний момент, коли world уже є в scene tree, що важливо для мережевих spawn-повідомлень і late join.

## 3. Межі відповідальності

| Компонент | За що відповідає | Чого не повинен робити |
|---|---|---|
| `autoload/network.gd` | ENet peer, Host/Join, roster, GameWorld loading, loading barrier, late join, reconnect і завершення сесії. | Зберігати правила конкретної гри, score, inventory, combat або map logic. |
| `ui/menu/` | Ввід імені/IP, запуск Solo/Host/Join, показ статусу й LAN hosts. | Самостійно створювати peer або змінювати roster. |
| `ui/lobby/` | Показ повного roster, Start для host, Leave. | Визначати, коли клієнт готовий до World. |
| `scenes/game/game_world.*` | Поточний demo world, test object lifecycle, input test harness та майбутні rules конкретної гри. | Вирішувати, кого ENet підключає або як працює reconnect. |
| `objects/` | Сцени конкретних реплікованих об’єктів: avatar, ресурс, ворог, projectile тощо. | Напряму керувати Menu/Lobby або створювати свої peer. |
| `ui/touch_controls/` | Перетворити mobile touch у звичайні InputMap actions. | Відправляти RPC або знати peer ID. |

> Просте правило: **Network відповідає за сесію; GameWorld відповідає за гру.** Якщо правило має сенс тільки в певному жанрі, воно не повинно жити в `Network`.

## 4. Канонічний roster

`Network` тримає один канонічний реєстр гравців. Host є в ньому таким самим гравцем, як і кожен client, і завжди має `peer_id = 1`.

```text
players_by_peer_id
├── 1  → Host
├── 482771  → Client A
└── 901554  → Client B
```

UI, player spawn і майбутні правила повинні використовувати загальний roster через публічний API `Network`, а не створювати окремий «список remote clients». Технічні ENet callbacks можуть не включати локального host, але **логічний список гравців завжди включає його**.

## 5. Життєвий цикл сесії

### Solo

Solo — це звичайний Host із нулем підключених clients. Відокремленої гілки gameplay немає.

```text
Solo → host_game() → begin_game() → GameWorld
```

### Host і Join

```text
Host → host_game() → Lobby → begin_game() → GameWorld
Join → join_game() → Lobby → очікує Start host → GameWorld
```

Host є server authority. Client не надсилає готову позицію або стан світу — він надсилає тільки свій input intent, а server вирішує, що з ним робити.

### Loading barrier

Після Start server робить snapshot гравців, що вже є у Lobby. `GameWorld` створюється на кожному з них; кожен peer підтверджує готовність. Лише коли готові всі гравці стартового snapshot, server запускає першу спільну симуляцію.

```text
Host натискає Start
  → всі стартові peer створюють GameWorld
  → кожен надсилає world_ready
  → server бачить готовність усіх
  → start_world_simulation
```

Гравець, який зайшов **після** Start, не блокує матч. Він проходить окремий late-join flow: спершу локально створює GameWorld, потім підтверджує готовність, і лише тоді server відкриває йому видимість об’єктів.

## 6. Контракт майбутньої GameWorld-сцени

Файл сцени може мати будь-яку назву. `Network` після instantiate усе одно дає створеному root node ім’я `GameWorld`.

Мінімальна нова сцена може бути просто `Node3D` із камерою, світлом і твоїми об’єктами. Щоб зберегти повну функціональність template, дотримуйся цього контракту:

| Елемент | Обов’язковість | Призначення |
|---|---:|---|
| Root `Node3D` | Так | Корінь майбутньої гри. `Network` додає його до root як `GameWorld`. |
| `begin_simulation()` | Рекомендовано | Server hook після завершення loading barrier: запуск round, таймерів, NPC, spawner тощо. |
| `grant_visibility_to_late_joiner(peer_id)` | Потрібно, якщо є репліковані node, створені до late join | Показати новачку вже існуючі об’єкти server-авторитетно. |
| `Players` + `PlayerSpawner` | Потрібно лише якщо залишаєш demo avatar harness | Контейнер та `MultiplayerSpawner` для placeholder avatar. |
| `CubeSpawner`, `SpawnTimer`, `Cubes` | Ні | Це лише demo-контент, який можна видалити. |

`Network` безпечно перевіряє наявність `begin_simulation()` та `grant_visibility_to_late_joiner()`. Якщо у твоїй першій грі немає pre-existing replicated objects, ці methods можуть бути порожніми або взагалі відсутніми. Але коли додаси replicated items, NPC, building blocks чи projectiles, implement late-join visibility одразу.

## 7. Реплікація та авторитет

Поточний placeholder avatar — **test harness server authority**. Він доводить, що input з ПК та touch з Android доходить до server, server рухає object, а всі peer бачать спільний результат.

| Тип майбутнього об’єкта | Рекомендований авторитет | Приклади |
|---|---|---|
| Світ і правила | Server (`peer_id = 1`) | День/ніч, раунд, loot spawn, damage rules, NPC AI. |
| Спільний фізичний object | Server | Куб, м’яч, ресурс, враг, будівельний блок. |
| Player-controlled entity | Визначається жанром | У v0.1 test harness — server-authoritative; prediction або client authority додаються лише коли це потрібно конкретній грі. |
| Локальна візуальна річ | Локальний peer | Частинки, камера, підсвітка, локальний UI. |

Не відправляй із client RPC на кшталт `set_position(new_position)`. Надсилай намір (`move`, `use_item`, `place_block`), а server перевіряє його й змінює authoritative state.

## 8. Що вільно видаляти або замінювати

| Можна замінити | Чому це безпечно |
|---|---|
| Підлогу, світло, `TempCamera` у `game_world.tscn` | Це visual demo world. |
| `falling_cube.*`, `Cubes`, `CubeSpawner`, `SpawnTimer` | Це test реплікації та physics. |
| `player_avatar.*` і `Players` / `PlayerSpawner` | Після того як конкретна гра має власний player/entity system. |
| Visual стиль TouchControls | Він торкається лише InputMap, не Network. |

Перед видаленням test harness переконайся, що ти вже маєш інший маленький end-to-end test своєї гри: Host + Android Join + Start + late join + leave/rejoin.

## 9. Що не потрібно ламати без конкретної причини

| Контракт | Чому |
|---|---|
| Публічний API та signals `Network` | Menu, Lobby і lifecycle-код спираються на них. Розширювати можна; видаляти або змінювати сигнатури — лише усвідомлено. |
| Ручний `GameWorld` instantiate/add_child | Це робить порядок loading та network spawn передбачуваним. |
| `world_ready` і loading barrier | Прибирає race condition між load scene та network spawn. |
| `Public Visibility = false` + явна visibility для late join | Це надійний шлях показати новачку вже існуючі репліковані object. |
| Ручний IP Join | Це надійний fallback, навіть якщо LAN broadcast на конкретному роутері чи Android-host не працює. |

## 10. Відомі межі v0.1

| Межа | Практичний наслідок |
|---|---|
| Немає host migration | Якщо host остаточно зник, матч завершується для всіх. |
| Немає online relay/matchmaking | Інтернет-гра потребує порт forwarding або окремого backend/relay. |
| Android-host LAN scan не гарантується | Ручний IP Join лишається fallback. ПК-host → Android scan пройшов тест. |
| Немає profile save | Ім’я та майбутні налаштування поки не зберігаються між запусками. |
| Немає конкретної gameplay системи | Це свідомо: template чекає на жанр майбутньої гри. |

## 11. Мінімальна перевірка перед змінами

Після зміни gameplay-контенту пройди щонайменше:

1. Solo запускається, виходить і запускається повторно.
2. Windows Host + Windows Client доходять до GameWorld.
3. Windows Host + Android Client доходять до GameWorld.
4. Усі peer бачать однаковий результат server-authoritative механіки.
5. Client виходить і повторно приєднується без console errors.
6. Ручний IP Join працює, навіть якщо LAN scan не знайшов host.

Якщо ці шість сценаріїв проходять, нова механіка не зламала foundation template.

## 12. Повернення до проєкту в новому чаті

Прикріпи щонайменше цей файл, `autoload/network.gd` та свою майбутню `GameWorld`/mechanics-сцену. Опиши жанр і бажану механіку, а також додай:

```text
Це Godot 4.7 Multiplayer Template v0.1.
Працює за схемою Solo/Host/Join → Lobby → GameWorld.
Network тримає session lifecycle; GameWorld тримає gameplay.
Прочитай ARCHITECTURE.md перед пропозиціями змін.
Хочу додати: [твоя конкретна механіка].
```

Цього достатньо, щоб майбутня робота починалася з коректного контексту, а не з повторного розбору мережевого ядра.

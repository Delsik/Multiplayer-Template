extends MarginContainer

## Прикріпи цей скрипт до MarginContainer, який обгортає весь UI-вміст
## екрана (наприклад, CenterContainer у Menu/Lobby). Автоматично рахує
## відступи під виїмки/чубчики/індикатор Home на мобільних, і сам
## перераховує їх при зміні орієнтації екрана.


func _ready() -> void:
	get_tree().root.size_changed.connect(_update_safe_area)
	_update_safe_area()


func _update_safe_area() -> void:
	# "Виріз/чубчик" — суто мобільне поняття. На ПК спроба вирахувати його
	# геометрично (порівнюючи safe_area з розміром монітора) ненадійна:
	# Windows/macOS зменшують "корисну" область екрана під панель задач/
	# док, і safe_area це враховує так само, як враховував би справжній
	# виріз — код думав, що знайшов виріз, хоча то просто панель задач.
	# Тому на ПК просто НІЧОГО не рахуємо — відступи завжди нуль.
	if not OS.has_feature("mobile"):
		add_theme_constant_override("margin_left", 0)
		add_theme_constant_override("margin_top", 0)
		add_theme_constant_override("margin_right", 0)
		add_theme_constant_override("margin_bottom", 0)
		return

	# На мобільних вікно завжди = весь екран, тож координати safe_area
	# і вікна збігаються без додаткових перетворень.
	var window_size := DisplayServer.window_get_size()
	var safe_area := DisplayServer.get_display_safe_area()
	add_theme_constant_override("margin_left", safe_area.position.x)
	add_theme_constant_override("margin_top", safe_area.position.y)
	add_theme_constant_override("margin_right", window_size.x - safe_area.end.x)
	add_theme_constant_override("margin_bottom", window_size.y - safe_area.end.y)

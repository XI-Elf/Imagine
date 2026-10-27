extends SceneTree
## Обучение (tutorial/tutorial.gd): справка F1, подсказки по ходу игры, пропуск, город и бой через Worlds.
## godot --path game --rendering-driver opengl3 -s res://tests/tutorial_checks.gd -- [папка_для_снимков]

var fails: int = 0
var checks: int = 0
var shots: String = ""


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
	print("ok: " if cond else "FAIL: ", what)


func frames(n: int) -> void:
	for i in n:
		await process_frame


func key(code: Key) -> void:
	var k := InputEventKey.new()
	k.physical_keycode = code
	k.keycode = code
	k.pressed = true
	Input.parse_input_event(k)
	await frames(2)


func shot(name_: String) -> void:
	if shots != "":
		await frames(2)
		root.get_viewport().get_texture().get_image().save_png(shots.path_join(name_))


## Ждать, пока покажется подсказка id (не дольше sec реальных секунд)
func wait_hint(T: Node, id: String, sec: float = 6.0) -> bool:
	var end: int = Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < end:
		if T._current.get("id", "") == id:
			return true
		await process_frame
	return T._current.get("id", "") == id


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	shots = args[0] if args.size() > 0 else ""
	_run()


func _run() -> void:
	var T: Node = root.get_node("Tutorial")
	var W: Node = root.get_node("Worlds")
	T.restart()
	ok(T.enabled and T.seen.is_empty(), "обучение сброшено и включено")

	# Справка в меню (игры нет): открывается и закрывается
	await key(KEY_F1)
	ok(T.is_help_open() and paused, "F1 без игры — справка, пауза")
	await key(KEY_ESCAPE)
	ok(not T.is_help_open() and not paused, "Esc закрывает справку, пауза снята")

	Engine.set_meta("aw_load", "")
	var game: Node2D = load("res://game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.ready_done:
		await process_frame
	ok(T.context() == "map", "контекст — карта")
	ok(await wait_hint(T, "welcome"), "первая подсказка — приветствие (G — герой)")
	await shot("t01_welcome.png")

	# F1 поверх игры: пауза, вкладка по месту, клавиши не уходят в игру
	await key(KEY_F1)
	ok(T.is_help_open() and paused and T._tabs.current_tab == 0, "F1 на карте — справка, вкладка «Карта»")
	await shot("t02_help_map.png")
	var had_hero: bool = not game.cast.hero.is_empty()
	await key(KEY_G)
	ok(game.cast.hero.is_empty() == not had_hero, "пока открыта справка, G не доходит до игры")
	T._tabs.current_tab = 4
	await shot("t03_help_mechanics.png")
	await key(KEY_F1)
	ok(not T.is_help_open() and not paused, "F1 ещё раз — закрыть")

	# G — герой: приветствие уходит, дальше «Герой»
	await key(KEY_G)
	# С веткой «Создание персонажа» G открывает экран создания — создаём героя случайно
	var cr: Variant = game.cast.get("_creator")
	if cr != null:
		cr.randomize_all()
		cr._on_create()
		await frames(3)
	ok(not game.cast.hero.is_empty() and game.cast.controls_hero, "G создаёт героя")
	# Новый герой у ворот сразу видит выбор «Войти» (world/settlements.gd) — пока проходим мимо
	if game.get("settlements") != null and not game.settlements.prompt_for.is_empty():
		game.settlements.choose_continue()
	await create_timer(T.MIN_SHOW_S + 0.3).timeout
	ok(T.seen.has("welcome"), "приветствие закрылось само, когда герой появился")
	ok(await wait_hint(T, "walk", T.GAP_S + 2.0), "подсказка «Герой» (WASD, Shift)")
	await shot("t04_walk.png")
	T.dismiss()
	ok(T.seen.has("walk") and not T._card.visible, "«Понятно» закрывает подсказку")
	ok(await wait_hint(T, "status", T.GAP_S + 2.0), "дальше — строка состояния и окно героя I")
	await key(KEY_I)
	await create_timer(T.MIN_SHOW_S + 0.3).timeout
	ok(T.seen.has("status"), "окно героя открыто — подсказка закрылась")
	await key(KEY_I)

	# Нужды: жажда
	var a: Actor = game.cast.hero["actor"]
	a.res["thirst"] = 30.0
	ok(await wait_hint(T, "thirst", T.GAP_S + 2.0), "мало воды — подсказка про E у реки")
	a.res["thirst"] = 60.0
	await create_timer(T.MIN_SHOW_S + 0.3).timeout
	ok(T.seen.has("thirst"), "напился — подсказка закрылась")

	# Справка по месту: герой под управлением — вкладка «Герой»
	await key(KEY_F1)
	ok(T._tabs.current_tab == 1, "с героем справка открывается на «Герой»")
	await shot("t05_help_hero.png")
	await key(KEY_F1)

	# Бой: подсказка боя поверх сцены боя, справка на вкладке «Бой»
	T._gap_t = 0.0
	W.start_battle({})   # отладочной K больше нет (Q07): бой как от случайного нападения
	await process_frame
	while W.busy:
		await process_frame
	ok(W.is_battle() and T.context() == "battle", "бой, контекст боя")
	ok(await wait_hint(T, "battle", T.GAP_S + 3.0), "подсказка пошагового боя")
	await create_timer(1.0).timeout
	await shot("t06_battle_hint.png")
	await key(KEY_F1)
	ok(T._tabs.current_tab == 3, "в бою справка открывается на «Бой»")
	await shot("t07_help_battle.png")
	await key(KEY_F1)
	ok(W.is_battle(), "F1 и Esc справки не выводят из боя")
	W.current_node().battle_finished.emit({"outcome": "win", "game_minutes": 1.0, "dead": []})
	while W.busy or W.is_battle():
		await process_frame

	# Город: подсказка города
	T._gap_t = 0.0
	if T._card.visible:
		T.dismiss()
	T._gap_t = 0.0
	ok(await W.enter_city("s001", {"return_pos": game.cast.hero["pos"]}), "вход в Чёрнославль")
	while W.busy:
		await process_frame
	ok(T.context() == "city", "контекст — город")
	ok(await wait_hint(T, "city", T.GAP_S + 3.0), "подсказка города (E, Tab, M)")
	await shot("t08_city_hint.png")
	T.dismiss()
	await W.leave()
	while W.busy or W.is_away():
		await process_frame

	# Пропуск: подсказок больше нет, справка работает; состояние сохраняется в user://
	T.skip_all()
	a.res["hunger"] = 20.0
	await create_timer(T.GAP_S + 1.5).timeout
	ok(not T._card.visible and not T.seen.has("hunger"), "после «Пропустить обучение» подсказок нет")
	await key(KEY_F1)
	ok(T.is_help_open() and not T._toggle.button_pressed, "справка работает, переключатель подсказок выключен")
	await key(KEY_F1)
	var cf := ConfigFile.new()
	ok(cf.load(T.SAVE_PATH) == OK and cf.get_value("tutorial", "enabled", true) == false and "walk" in cf.get_value("tutorial", "seen", []), "выбор и показанные подсказки сохранены в user://tutorial.cfg")
	T.set_enabled(true)
	await create_timer(T.GAP_S + 1.5).timeout
	ok(await wait_hint(T, "hunger"), "включить снова в справке — подсказки вернулись (голод)")
	T.restart()
	ok(T.seen.is_empty(), "«Начать обучение заново» очищает показанное")

	print("TUTORIAL CHECKS: %d/%d" % [checks - fails, checks])
	quit(1 if fails > 0 else 0)

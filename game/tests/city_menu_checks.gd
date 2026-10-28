extends SceneTree
## Вход в город как в Day R (видео Huzzah 2026-10-23): у ворот панель места (Искать, Набрать воды),
## «Войти» открывает экран города с карточками услуг, пешая карта — по кнопке, Esc — назад в меню.
## godot --path game --rendering-driver opengl3 -s res://tests/city_menu_checks.gd -- [папка_для_снимков]

const Growth := preload("res://city/city_growth.gd")
const Trade := preload("res://city/trade.gd")

var fails: int = 0
var checks: int = 0
var shots: String = ""


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("FAIL: ", what)
	else:
		print("ok: ", what)


func frames(n: int) -> void:
	for i in n:
		await process_frame


func shot(name: String) -> void:
	if shots == "":
		return
	await frames(4)
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(shots.path_join(name))


func key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(1)
	var up: InputEventKey = ev.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	await frames(1)


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	shots = args[0] if args.size() > 0 else ""
	_run()


func card(city: Node, kind: String, npc_id: String = "") -> Dictionary:
	for c in city.menu._cards:
		if c["kind"] == kind and (npc_id == "" or String(c["n"]["def"]["id"]) == npc_id):
			return c
	return {}


func _run() -> void:
	var W: Node = root.get_node_or_null("Worlds")
	Engine.set_meta("aw_load", "")
	var t: Node = root.get_node_or_null("Tutorial")
	if t != null:
		t.enabled = false
	var game: Node2D = load("res://game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	var t0: int = Time.get_ticks_msec()
	while not game.ready_done and Time.get_ticks_msec() - t0 < 120000:
		await process_frame
	await frames(3)
	if t != null:
		for c in t.get_children():
			if c is CanvasItem or c is CanvasLayer:
				c.visible = false
	game.show_clouds = false
	# Полдень: жители на работе, ворота открыты
	game.clock.paused = true
	game.clock.total_seconds = floorf(game.clock.total_seconds / 86400.0) * 86400.0 + 86400.0 + 12.0 * 3600.0
	var st: Node = game.settlements
	game.cast.spawn_hero(st.spawn_point())
	await frames(4)
	var hero: Dictionary = game.cast.hero
	var a: Actor = hero["actor"]

	# Панель места у ворот
	ok(st.prompt_kind == "gate", "у ворот открылась панель места")
	ok(st._pic.texture != null and st._pic.texture == st.medallion_texture(st.dev_level(st.list[0])), "на панели картинка поселения — тот же медальон")
	ok(st._search_btn.visible and st._water_btn.visible and not st._search_btn.disabled, "кнопки «Искать» и «Набрать воды»")
	game.zoom = 0.6
	game.cam_pos = hero["pos"]
	await shot("cm01_panel_mesta.png")

	# Искать: время идёт, раз в сутки
	var bag: Dictionary = W.inventory
	var before: float = game.clock.total_seconds
	st.choose_search()
	ok(absf(game.clock.total_seconds - before - st.SEARCH_MIN * 60.0) < 1.0, "поиск занял %d мин" % int(st.SEARCH_MIN))
	ok(st._search_btn.disabled and st._result.visible and st._result.text.begins_with("Обыскал"), "итог поиска показан, второй раз нельзя: %s" % st._result.text)
	var t1: float = game.clock.total_seconds
	await key(KEY_F)
	ok(game.clock.total_seconds == t1, "F по обысканному месту время не тратит")
	await shot("cm02_iskat.png")

	# Набрать воды
	a.res["thirst"] = 20.0
	var fl: int = Trade.count(bag, "water_flask")
	await key(KEY_R)
	ok(float(a.res["thirst"]) > 90.0, "напился у колодца: вода %d" % int(a.res["thirst"]))
	ok(Trade.count(bag, "water_flask") == mini(fl + 1, maxi(fl, 2)), "фляга наполнена (не больше двух)")

	# Войти: экран города, а не пешая карта
	await key(KEY_E)
	t0 = Time.get_ticks_msec()
	while W.current_kind() != "city" and Time.get_ticks_msec() - t0 < 20000:
		await process_frame
	await frames(30)
	var city: Node = W.current_node()
	ok(city != null and city.has_method("open_menu"), "вошёл в город")
	ok(not city.walking and city.menu.visible, "вход через ворота открыл экран города")
	ok(city._menu_blocked(), "в меню герой не ходит")
	if t != null:
		for c in t.get_children():
			if c is CanvasItem or c is CanvasLayer:
				c.visible = false
	ok(city.menu._name.text == city.display_name and city.menu._sub.text.contains("Форт"), "шапка: имя и этап «%s»" % city.menu._sub.text)
	ok(city.menu._info.text.contains("Гость") and city.menu._info.text.contains("Поручений сдано: 0"), "шапка: статус и поручения")
	ok(city.menu._pic.texture != null and city.menu._pic.texture.resource_path.ends_with("m1_ostrog.png"), "картинка шапки — Форт, как на карте")
	var kinds: Array = city.menu._cards.map(func(c): return c["kind"])
	ok(kinds.has("quests") and kinds.has("walk") and kinds.has("leave") and kinds.has("sleep"), "карточки: поручения, ночлег, прогулка, выход: %s" % [kinds])
	for id in ["posadnik", "healer", "tanner"]:
		ok(not card(city, "npc", id).is_empty(), "карточка жителя %s" % id)
	ok(card(city, "npc", "tanner")["note"].text.begins_with("Работает"), "кожевник в полдень работает: %s" % card(city, "npc", "tanner")["note"].text)
	ok(card(city, "npc", "posadnik")["note"].text.contains("Есть работа"), "у главы есть работа")
	await shot("cm03_ekran_goroda.png")

	# Карточка кожевника: разговор поверх меню, торговля без поиска на улице
	city.menu.press(card(city, "npc", "tanner"))
	await frames(2)
	ok(city._panel.visible and city._panel_kind == "talk", "карточка открыла разговор")
	var labels: Array = city._tab_buttons.map(func(b): return b.text)
	ok(labels.has("Разговор") and labels.has("Торговля") and labels.has("Мастерская") and labels.any(func(s): return s.begins_with("Поручения")), "Q34: вкладки разговора у кожевника: %s" % [labels])
	ok(city._tab_buttons[0].button_pressed and city._tabs.visible, "Q34: открыта вкладка «Разговор»")
	var vp: Vector2 = city.get_viewport().get_visible_rect().size
	ok(absf(city._panel.position.x + city._panel.size.x * 0.5 - vp.x * 0.5) < 4.0, "окно разговора по центру экрана")
	await shot("cm04_kozhevnik.png")
	for b in city._tab_buttons:
		if b.text == "Торговля":
			b.emit_signal("pressed")
	await frames(2)
	ok(city._panel_kind == "trade" and city._tab_buttons.filter(func(b): return b.button_pressed).map(func(b): return b.text) == ["Торговля"], "торговля открылась на своей вкладке")
	for b in city._tab_buttons:
		if b.text == "Мастерская":
			b.emit_signal("pressed")
	await frames(2)
	ok(city._panel_kind == "craft" and city._buttons.size() > 0, "Q34: вкладка «Мастерская» без прокрутки разговора")
	for b in city._tab_buttons:
		if b.text == "Торговля":
			b.emit_signal("pressed")
	await frames(2)
	await shot("cm05_torgovlya.png")
	await key(KEY_ESCAPE)
	ok(not city._panel.visible and city.menu.visible and W.current_kind() == "city", "Esc закрыл окно, экран города на месте")

	# Поручение главы из карточки
	city.menu.press(card(city, "npc", "posadnik"))
	await frames(2)
	for b in city._tab_buttons:
		if b.text.begins_with("Поручения"):
			b.emit_signal("pressed")
	await frames(2)
	labels = city._buttons.map(func(b): return b.text)
	ok(city._panel_kind == "quests" and labels.any(func(s): return s.contains("Работа:")), "у главы на вкладке «Поручения» есть работа")
	city._close_panel()
	city.menu.press(card(city, "quests"))
	await frames(2)
	ok(city._panel.visible and city._panel_text.text.contains("Форт"), "«Поручения» — доска объявлений")
	city._close_panel()

	# Ночлег в лачуге
	city.menu.press(card(city, "sleep"))
	ok(a.sleeping, "«Ночлег» — сон на лежанке")
	city.menu.refresh(false)
	ok(card(city, "sleep")["note"].text.begins_with("Проснуться"), "карточка ночлега предлагает проснуться")
	city.menu.press(card(city, "sleep"))
	ok(not a.sleeping, "проснулся из меню")

	# Пройтись по городу и назад
	city.menu.press(card(city, "walk"))
	await frames(2)
	ok(city.walking and not city.menu.visible and not city._menu_blocked(), "«Пройтись по городу» — пешая карта")
	await shot("cm06_progulka.png")
	await key(KEY_ESCAPE)
	ok(not city.walking and city.menu.visible, "Esc на улице вернул экран города")
	ok(W.current_kind() == "city" and not game.menu_open, "меню паузы не открылось")

	# Сохранение: в меню — снова меню, на улице — на улице
	var d: Dictionary = city.to_dict()
	ok(d.has("walking") and not bool(d["walking"]), "состояние помнит, что открыт экран города")

	# Город вырос — карточки новых жителей появились
	var g: Dictionary = city.growth
	for k in 30:
		if Growth.stage(city.full_def, g) >= 1:
			break
		for n in city.npcs:
			var q: Dictionary = Growth.current(city.full_def, g, String(n["def"]["id"]))
			if not q.is_empty() and Growth.stage(city.full_def, g) < 1:
				g["done"].append(q["id"])
	city._rebuild_stage()
	city.menu.refresh(false)
	ok(not card(city, "npc", "smith").is_empty() and city.menu._sub.text.contains("Деревня"), "Деревня: карточка кузнеца, этап в шапке")
	ok(city.menu._pic.texture.resource_path.ends_with("m2_sloboda.png"), "картинка шапки выросла вместе с городом")
	await shot("cm07_sloboda.png")

	# Ночью ворота заперты: выпускает привратник за плату
	game.clock.total_seconds = floorf(game.clock.total_seconds / 86400.0) * 86400.0 + 86400.0 + 23.5 * 3600.0
	for i in 3:
		city._process(0.05)
	city.menu.press(card(city, "leave"))
	await frames(2)
	ok(W.current_kind() == "city" and city._panel.visible and city._panel_text.text.begins_with("Ворота заперты"), "ночью не выйти без привратника: %s" % city._panel_text.text)
	city._close_panel()

	# Днём — «Покинуть город» выводит к воротам на карте
	game.clock.total_seconds += 9.0 * 3600.0
	for i in 3:
		city._process(0.05)
	city.menu.press(card(city, "leave"))
	t0 = Time.get_ticks_msec()
	while W.current_kind() != "overworld" and Time.get_ticks_msec() - t0 < 20000:
		await process_frame
	await frames(10)
	ok(W.current_kind() == "overworld", "«Покинуть город» — на общую карту")
	ok(game.cast.hero["pos"].distance_to(st.exit_point(String(st.list[0]["id"]))) < 60.0, "герой у ворот")

	# Пробрался через стену — сразу на улице, меню нет
	var s: Dictionary = st.list[0].duplicate()
	s["entry"] = "sneak"
	s["side"] = "north"
	W._on_enter_requested(s)
	t0 = Time.get_ticks_msec()
	while W.current_kind() != "city" and Time.get_ticks_msec() - t0 < 20000:
		await process_frame
	await frames(10)
	city = W.current_node()
	ok(city.walking and not city.menu.visible, "пролез через стену — на улице, без экрана города")
	await key(KEY_ESCAPE)
	ok(city.walking, "чужак не уходит в меню по Esc")

	print("city_menu_checks: %d/%d" % [checks - fails, checks])
	quit(1 if fails > 0 else 0)

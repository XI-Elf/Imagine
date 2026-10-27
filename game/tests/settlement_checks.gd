extends SceneTree
## Проверка города на общей карте в настоящей сцене (нужен экран: под xvfb, --rendering-driver opengl3).
## Щиток издали и очерк вблизи, вход у ворот, проникновение у стены, стена не пропускает героя.
## godot --path game --rendering-driver opengl3 -s res://tests/settlement_checks.gd -- [папка_для_снимков]

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
	await frames(3)
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


func walk(dir: Vector2) -> void:
	Input.action_press("ui_right", maxf(dir.x, 0.0))
	Input.action_press("ui_left", maxf(-dir.x, 0.0))
	Input.action_press("ui_down", maxf(dir.y, 0.0))
	Input.action_press("ui_up", maxf(-dir.y, 0.0))


func stop() -> void:
	for a in ["ui_right", "ui_left", "ui_down", "ui_up"]:
		Input.action_release(a)


# Перенос героя в точку без «скачка» у самого города: сначала далеко, потом ближе шагами
func place(hero: Dictionary, to: Vector2, from_dir: Vector2) -> void:
	for d in [900.0, 750.0, 600.0, 450.0, 300.0, 150.0, 0.0]:
		hero["pos"] = to + from_dir * d
		await frames(2)


# Идти к цели, пока не всплывёт выбор (или не выйдет время)
func walk_until_prompt(st: Node, hero: Dictionary, target: Vector2, limit_s: float = 60.0) -> void:
	var t1: int = Time.get_ticks_msec()
	while st.prompt_for.is_empty() and Time.get_ticks_msec() - t1 < limit_s * 1000.0:
		walk((target - hero["pos"]).normalized())
		await process_frame
	stop()
	await frames(1)


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	shots = args[0] if args.size() > 0 else ""
	_run()


func _run() -> void:
	var game: Node2D = load("res://game.tscn").instantiate()
	root.add_child(game)
	var t0: int = Time.get_ticks_msec()
	while not game.ready_done and Time.get_ticks_msec() - t0 < 120000:
		await process_frame
	ok(game.ready_done, "карта загрузилась")
	var st: Node2D = game.settlements
	var cast: Node2D = game.cast
	ok(st != null and st.list.size() == 1, "один город в реестре: %d" % (st.list.size() if st else -1))
	var city: Dictionary = st.list[0]
	ok(city["_cells"].size() == int(st.sizes[city["size"]]["cells"]), "%s %s: %d клеток по размеру" % [st.size_name(city), city["name"], city["_cells"].size()])
	ok(city.has("emblem") and city["walled"] and city["_road"].size() >= 10, "есть эмблема, стена и дорога (%d точек)" % city["_road"].size())
	# Город целиком в одной области и одном регионе: по клеткам с запасом 20 м границ нет
	var regs := {}
	var provs := {}
	for k in city["_cells"]:
		for i in 11:
			for j in 11:
				var q: Vector2 = Vector2(k) * st.cell_m + Vector2(i, j) * (st.cell_m + 40.0) / 10.0 - Vector2(20, 20)
				regs[game.region_at(q)] = true
				provs[game.province_at(q)] = true
	ok(regs.size() == 1 and provs.size() == 1 and int(regs.keys()[0]) == int(city["region"]) and int(provs.keys()[0]) == int(city["province"]),
		"город в одной области и регионе: области %s, регионы %s" % [provs.keys(), regs.keys()])
	ok(game.region_at(city["_gate"]) == int(city["region"]), "ворота в том же регионе")
	var road_ok: bool = true
	for q in city["_road"]:
		if game.biome_at(q) <= 1 or st.blocks(q):
			road_ok = false
	ok(road_ok, "дорога по суше и вне города")
	ok(game.cam_pos.distance_to(st.spawn_point()) < 1.0, "новая игра: камера над городом")
	var ex: Vector2 = st.exit_point(city["id"])
	ok(ex != Vector2.INF and st.settlement_at(ex).is_empty() and game.biome_at(ex) > 1, "точка выхода на суше вне клеток: %s" % ex)
	ok(st.zone_of(city, ex) == "gate", "точка выхода — у ворот")

	# Снимки: издали щиток, вблизи очерк
	game.cam_pos = Vector2(20812.5, 18000.0)
	await shot("s01_world.png")
	for z in [0.03, 0.08, 0.15, 0.4]:
		game.zoom = z
		game.cam_pos = city["_center"] + Vector2(0, 150)
		await shot("s02_zoom_%s.png" % str(z).replace(".", "_"))

	# Новый герой у ворот, выбор сразу не спрашивается
	# Новый герой появляется у ворот (с веткой создания персонажа G открывает экран создания,
	# а готовый герой ставится туда же — spawn_point)
	cast.spawn_hero(st.spawn_point())
	await frames(3)
	var hero: Dictionary = cast.hero
	var a: Actor = hero["actor"]
	ok(not hero.is_empty() and hero["pos"].distance_to(ex) < 60.0, "герой у ворот: %s" % hero.get("pos"))
	ok(st.prompt_kind == "gate", "новый герой у ворот сразу видит «Войти»")
	await key(KEY_ESCAPE)
	ok(st.prompt_for.is_empty() and not st._quiet_zone().is_empty(), "Esc закрыл выбор, у героя подсказка «E — войти»")
	await shot("s05_gate_hint.png")
	await key(KEY_E)
	ok(st.prompt_kind == "gate", "E у ворот снова открыл выбор")
	await key(KEY_ESCAPE)
	game.zoom = 0.4

	# По дороге к воротам: «Войти»
	var road: PackedVector2Array = city["_road"]
	await place(hero, road[6], (road[12] - road[6]).normalized())
	ok(st.prompt_for.is_empty(), "на дороге в %.0f м от ворот выбора нет" % road[6].distance_to(city["_gate"]))
	await walk_until_prompt(st, hero, city["_gate"])
	ok(st.prompt_kind == "gate", "по дороге у ворот всплыл выбор «Войти»")
	ok(cast.hold_hero, "герой стоит, пока игрок выбирает")
	var p0: Vector2 = hero["pos"]
	Input.action_press("ui_up")
	await create_timer(0.7).timeout
	Input.action_release("ui_up")
	ok(hero["pos"].distance_to(p0) < 0.5, "держание клавиши не сдвигает героя")
	await shot("s03_gate_prompt.png")
	await key(KEY_ESCAPE)
	ok(st.prompt_for.is_empty() and not cast.hold_hero and not game.menu_open, "Esc — продолжить путь, меню паузы не открылось")

	# Стена не пропускает: идём в центр города
	var before: float = st.distance_to(city, hero["pos"])
	walk((city["_center"] - hero["pos"]).normalized())
	await create_timer(3.0).timeout
	stop()
	ok(not st.blocks(hero["pos"]), "в город сквозь стену не пройти (%.0f → %.0f м от стены)" % [before, st.distance_to(city, hero["pos"])])
	if not st.prompt_for.is_empty():
		await key(KEY_ESCAPE)

	# К северной стене: «Попытаться проникнуть»
	var r: Rect2 = city["_rect"]
	var north: Vector2 = st.nearest_on_cells(city, Vector2(city["_center"].x, r.position.y - 400.0))
	await place(hero, north + Vector2(0, -150), Vector2(0, -1))
	await walk_until_prompt(st, hero, north)
	ok(st.prompt_kind == "wall" and st.prompt_side == "north", "у северной стены выбор «проникнуть» (%s, %s)" % [st.prompt_kind, st.prompt_side])
	ok(st._act_btn.text.begins_with("Попытаться проникнуть"), "кнопка: %s" % st._act_btn.text)
	ok(st._info.text.contains("Шанс"), "шанс показан: %s" % st._info.text)
	await shot("s04_wall_prompt.png")

	# Шанс зависит от характеристик, ночи, груза, травм
	var env: Dictionary = {"night": false}
	var c0: float = st.sneak_chance(a, env)
	a.set_stat("agi", int(a.stat("agi")) + 3)
	var c_agi: float = st.sneak_chance(a, env)
	var c_night: float = st.sneak_chance(a, {"night": true})
	a.carried_kg = 60.0
	var c_heavy: float = st.sneak_chance(a, env)
	a.carried_kg = 0.0
	a.add_condition("broken_leg")
	var c_hurt: float = st.sneak_chance(a, env)
	a.remove_condition("broken_leg")
	a.set_stat("agi", int(a.stat("agi")) - 3)
	ok(c_agi > c0 and c_night > c_agi and c_heavy < c_agi and c_hurt < c_agi, "шанс: %.2f, ловкость+3 %.2f, ночь %.2f, груз 60 кг %.2f, сломана нога %.2f" % [c0, c_agi, c_night, c_heavy, c_hurt])
	a.mount = "horse"
	ok(st.sneak_chance(a, env) == 0.0, "верхом через стену нельзя")
	a.mount = ""
	# Частота успеха совпадает с шансом
	var wins: int = 0
	for i in 400:
		st.alert_until.clear()
		a.res["stamina"] = a.max_of("stamina")
		for c in a.conditions.duplicate():
			a.remove_condition(c["id"])
		if st.try_sneak(city, a, env) == "sneak":
			wins += 1
	for c in a.conditions.duplicate():
		a.remove_condition(c["id"])
	ok(absf(wins / 400.0 - c0) < 0.08, "из 400 попыток пролез %d (шанс %.2f)" % [wins, c0])
	st.alert_until.clear()
	a.res["stamina"] = a.max_of("stamina")
	a.res["health"] = a.max_of("health")

	# Неудача без поимки: стража настороже, кнопка неактивна
	var saved: Dictionary = st.sneak_rules.duplicate()
	st.sneak_rules["min"] = 0.0
	st.sneak_rules["max"] = 0.0001
	st.sneak_rules["caught_day"] = 0.0
	st.sneak_rules["caught_night"] = 0.0
	st.sneak_rules["fall_chance"] = 0.0
	await frames(2)
	await key(KEY_E)
	ok(game.event_text.contains("Не удалось"), "неудача: %s" % game.event_text)
	ok(st.alert_left_s(city) > 0.0, "стража настороже %.0f мин" % (st.alert_left_s(city) / 60.0))
	await place(hero, north + Vector2(0, -150), Vector2(0, -1))
	await walk_until_prompt(st, hero, north)
	ok(st._act_btn.disabled and st._info.text.contains("настороже"), "пока стража настороже, проникнуть нельзя: %s" % st._info.text)
	await key(KEY_ESCAPE)
	st.alert_until.clear()

	# Успех: сигнал с entry "sneak" и стороной
	var got: Array = []
	st.enter_requested.connect(func(s: Dictionary) -> void: got.append(s))
	st.sneak_rules["min"] = 1.0
	st.sneak_rules["max"] = 1.0
	await place(hero, north + Vector2(0, -150), Vector2(0, -1))
	await walk_until_prompt(st, hero, north)
	var wm: Node = root.get_node_or_null("Worlds")
	await key(KEY_E)
	ok(got.size() == 1 and got[0]["entry"] == "sneak" and got[0]["side"] == "north" and got[0]["city_id"] == city["city_id"], "проникновение: entry %s, side %s" % [got[0].get("entry") if got.size() else "-", got[0].get("side") if got.size() else "-"])
	if wm != null:
		await create_timer(1.0).timeout
		ok(wm.current_kind() == "city", "менеджер миров открыл город")
		wm.leave()
		await create_timer(1.0).timeout
		ok(hero["pos"].distance_to(ex) < 60.0 and st.prompt_for.is_empty(), "вышел к воротам, выбор не всплыл")

	# Поймали: entry "caught"
	st.sneak_rules["min"] = 0.0
	st.sneak_rules["max"] = 0.0001
	st.sneak_rules["caught_day"] = 1.0
	st.sneak_rules["caught_night"] = 1.0
	st.sneak_rules["per_agi_caught"] = 0.0
	await place(hero, north + Vector2(0, -150), Vector2(0, -1))
	await walk_until_prompt(st, hero, north)
	await key(KEY_E)
	ok(got.size() == 2 and got[1]["entry"] == "caught", "заметили: entry %s" % (got[1].get("entry") if got.size() > 1 else "-"))
	if wm != null:
		await create_timer(1.0).timeout
		wm.leave()
		await create_timer(1.0).timeout
	st.sneak_rules = saved

	# Вход через ворота: entry "gate"
	await place(hero, road[6], (road[12] - road[6]).normalized())
	await walk_until_prompt(st, hero, city["_gate"])
	await key(KEY_E)
	ok(got.size() == 3 and got[2]["entry"] == "gate", "ворота: entry %s" % (got[2].get("entry") if got.size() > 2 else "-"))
	if wm != null:
		await create_timer(1.0).timeout
		wm.leave()
		await create_timer(1.0).timeout

	ok(game.place_line(city["_center"]).contains(city["name"]), "подсказка: %s" % game.place_line(city["_center"]))
	print("ИТОГ: %d/%d" % [checks - fails, checks])
	quit(1 if fails > 0 else 0)

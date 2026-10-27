extends SceneTree
## Проверка героя и НПС в настоящей сцене карты (нужен экран: под xvfb, --rendering-driver opengl3).
## godot --path game --rendering-driver opengl3 -s res://tests/cast_game_checks.gd -- [папка_для_снимков]

const WorldSave := preload("res://world_save.gd")

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
	await frames(2)
	root.get_viewport().get_texture().get_image().save_png(shots.path_join(name))


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
	var cast: Node2D = game.cast
	ok(cast != null, "персонажи подключены")

	# Герой на суше у центра карты, рядом НПС
	game.cam_pos = Vector2(20812.0, 18000.0)
	cast.spawn_hero(game.cam_pos)
	var hero: Dictionary = cast.hero
	ok(not hero.is_empty() and cast._land(hero["pos"]), "герой на суше: %s" % hero.get("pos"))
	ok(cast.bodies.size() == 1, "НПС снаружи города не появляются (их %d)" % (cast.bodies.size() - 1))
	ok(is_equal_approx(game.clock.current_rate(), 96.0 * GameClock.GAME_SPEED) or not game.clock.active, "часы ×%d" % int(game.clock.current_rate()))
	# Для проверки распорядка НПС — восемь вручную, по тем же правилам; знахарь пятый
	var R := preload("res://characters/actor_rules.gd")
	var sk: Array = R.skills().keys()
	for i in 8:
		var na := Actor.new("npc_%d" % i, "НПС %d" % i, true, 100 + i)
		na.add_xp(sk[i % sk.size()], 300.0)
		cast.spawn_npc(na, cast._find_land(hero["pos"] + Vector2.from_angle(i * 0.8) * 200.0, 3000.0, true), cast.all_remedies() if sk[i % sk.size()] == "medicine" else [])
	game.zoom = 0.4
	await frames(5)
	await shot("c01_hero_spawn.png")

	# Идёт вправо 3 секунды
	var start: Vector2 = hero["pos"]
	Input.action_press("ui_right")
	await create_timer(3.0).timeout
	Input.action_release("ui_right")
	var moved: float = hero["pos"].distance_to(start)
	ok(moved > 5.0, "герой прошёл %.0f м за 3 с" % moved)
	ok(game.cam_pos.distance_to(hero["pos"]) < 1.0, "камера идёт за героем")
	await shot("c02_hero_walked.png")

	# Бег быстрее
	start = hero["pos"]
	Input.action_press("ui_left")
	Input.action_press("ui_accept")   # не мешает
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_SHIFT
	ev.keycode = KEY_SHIFT
	ev.pressed = true
	Input.parse_input_event(ev)
	await create_timer(2.0).timeout
	Input.action_release("ui_left")
	Input.action_release("ui_accept")
	ev.pressed = false
	Input.parse_input_event(ev)
	print("бег: %.0f м за 2 с, силы %d" % [hero["pos"].distance_to(start), int(hero["actor"].res["stamina"])])

	# НПС живут: время идёт, нужды падают, кто-то ходит
	var npc_start: Array = cast.bodies.filter(func(b): return not b["hero"]).map(func(b): return b["pos"])
	game.clock.speed_index = 1
	await create_timer(6.0).timeout
	var npcs: Array = cast.bodies.filter(func(b): return not b["hero"])
	var walked: int = 0
	for i in npcs.size():
		if npcs[i]["pos"].distance_to(npc_start[i]) > 3.0:
			walked += 1
	ok(walked > 0, "НПС ходят: %d из %d" % [walked, npcs.size()])
	ok(npcs.all(func(b): return b["actor"].alive), "НПС живы")
	for b in npcs:
		print("  %s: план %s, голод %d, жажда %d, энергия %d" % [b["actor"].display_name, b["plan"], int(b["actor"].res["hunger"]), int(b["actor"].res["thirst"]), int(b["actor"].res["energy"])])
	ok(hero["actor"].res["thirst"] < 80.0, "у героя растёт жажда: %.1f" % hero["actor"].res["thirst"])

	# Лист персонажа
	cast.window.open("stats")
	game.zoom = 1.0
	await frames(5)
	await shot("c03_sheet_npcs.png")
	ok(cast.window.visible and cast.sheet_visible, "окно героя (лист персонажа)")
	cast.window.close()

	# Сохранение и загрузка
	var d: Dictionary = WorldSave.build(game)
	ok(d.has("cast") and d["cast"]["bodies"].size() == cast.bodies.size(), "в сохранении персонажи")
	var hero_pos: Vector2 = hero["pos"]
	cast.load_dict(d["cast"])
	ok(not cast.hero.is_empty() and cast.hero["pos"].distance_to(hero_pos) < 0.01, "загрузка: герой на месте")
	ok(cast.bodies.size() == 1, "НПС с общей карты из сохранения не грузятся")
	# Знахарь для проверки лечения — снова вручную
	var hk := Actor.new("healer_t", "Знахарь", true, 77)
	hk.add_xp("medicine", 300.0)
	cast.spawn_npc(hk, cast.hero["pos"] + Vector2(300, 0), cast.all_remedies())

	# Вода: герой у воды может пить, в воде плывёт
	var w: Vector2 = cast._nearest_water(cast.hero["pos"])
	if w == Vector2.INF:
		w = cast._nearest_water(Vector2(20812.0, 14000.0))
	ok(w != Vector2.INF, "вода найдена рядом")
	if w != Vector2.INF:
		cast.hero["pos"] = w
		await frames(3)
		var env: Dictionary = preload("res://characters/world_env.gd").sample(game, w)
		ok(cast.hero["actor"].is_swimming(env), "в воде герой плывёт")
		ok(cast._water_near(w), "можно пить")
		game.zoom = 2.0
		await frames(3)
		await shot("c04_swimming.png")

	# Знахарь лечит героя (клавиша T) и любой НПС по тем же правилам
	var healer: Dictionary = cast._nearest_healer(cast.hero)
	ok(not healer.is_empty(), "среди НПС есть знахарь: %s" % healer.get("actor", Actor.new()).display_name)
	if not healer.is_empty():
		cast.hero["pos"] = healer["pos"] + Vector2(5, 0)
		cast.hero["actor"].add_condition("laceration")
		var healed := false
		for i in 30:
			var key := InputEventKey.new()
			key.physical_keycode = KEY_T
			key.keycode = KEY_T
			key.pressed = true
			Input.parse_input_event(key)
			await frames(2)
			key.pressed = false
			Input.parse_input_event(key)
			await frames(1)
			if not cast.hero["actor"].has_condition("laceration"):
				healed = true
				break
		ok(healed, "знахарь вылечил рану героя: " + game.event_text)
		ok(healer["actor"].skills["medicine"]["xp"] > 0.0, "знахарь получил опыт")

	# Жаркие горы (ветка terrain): температура из карты, жажда в жару быстрее
	if game.has_method("is_hot"):
		var hot := Vector2(30359.0, 8769.0)
		var henv: Dictionary = preload("res://characters/world_env.gd").sample(game, hot)
		ok(game.is_hot(hot) and float(henv["temp_c"]) > 35.0, "жаркие горы: %.0f °C" % henv["temp_c"])
		var ah := Actor.new("hot", "Жара")
		var ac := Actor.new("cool", "Тень")
		ah.tick(3600.0, henv)
		ac.tick(3600.0, preload("res://characters/world_env.gd").sample(game, cast.hero["pos"]))
		ok(ah.res["thirst"] < ac.res["thirst"], "в жарких горах жажда быстрее")

	print("cast_game_checks: %d/%d ok" % [checks - fails, checks])
	quit(1 if fails > 0 else 0)

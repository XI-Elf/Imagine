extends SceneTree
## Гибель героя и новый персонаж (characters/hero_death.gd, вопросы Q06 и Q27, Huzzah 2026-10-24):
## смерть в городе, в бою и в сохранении открывает экран со случайным новым героем; «Продолжить» оставляет
## прогресс поселений и мира, но не деньги, вещи, навыки, победы, взятые поручения и план города; «Начать заново» —
## экран создания и новый мир.
## godot --path game --rendering-driver opengl3 -s res://tests/hero_death_checks.gd -- [папка_для_снимков]

const P := preload("res://characters/hero_profile.gd")
const Growth := preload("res://city/city_growth.gd")
const Trade := preload("res://city/trade.gd")
const HeroDeath := preload("res://characters/hero_death.gd")

var fails: int = 0
var checks: int = 0
var shots: String = ""
var W: Node


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


func key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = true
	root.get_viewport().push_input(ev)
	ev = ev.duplicate()
	ev.pressed = false
	root.get_viewport().push_input(ev)


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	shots = args[0] if args.size() > 0 else ""
	_run()


func wait_game(game: Node2D) -> void:
	var t0: int = Time.get_ticks_msec()
	while not game.ready_done and Time.get_ticks_msec() - t0 < 120000:
		await process_frame
	await frames(3)


func load_game(slot: String = "") -> Node2D:
	Engine.set_meta("aw_load", slot)
	var game: Node2D = load("res://game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await wait_game(game)
	return game


func wait_free() -> void:
	for i in 600:
		if not W.busy:
			break
		await process_frame
	await frames(2)


# Ждём, пока экран гибели откроется (из города он сначала выводит на карту)
func wait_death(cast: Node2D) -> void:
	for i in 600:
		if cast.death.active:
			break
		await process_frame
	await frames(2)


func _run() -> void:
	W = root.get_node_or_null("Worlds")
	W.test_doubles = {"city": load("res://tests/doubles/city_stub.gd"), "battle": load("res://tests/doubles/battle_stub.gd")}
	var game: Node2D = await load_game()
	var cast: Node2D = game.cast
	ok(cast.death != null and not cast.death.active, "экран гибели есть и закрыт")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	cast.create_hero(P.random_params(rng))
	await frames(3)
	var a: Actor = cast.hero["actor"]
	ok(a.alive and not cast.death.active, "живой герой — экрана нет")
	var gate: Vector2 = cast.hero["pos"]

	# ---- Прогресс в городе: сданное и взятое поручения, деньги, вещи, победы, навыки
	ok(await W.enter_city("s001", {"return_pos": gate}), "в город s001")
	await frames(5)
	var city: Node = W.current_node()
	var q: Dictionary = Growth.current(city.full_def, city.growth, "posadnik")
	city.take_quest(city.npcs.filter(func(n): return String(n["def"]["id"]) == "posadnik")[0], q)
	city.growth["done"].append("test_done")
	var hq: Dictionary = Growth.current(city.full_def, city.growth, "healer")
	Growth.take(city.growth, hq, city.hero_km(), city.battles_won())
	city.discovered["test_place"] = true
	city.paid_gate["south"] = game.clock.total_seconds + 99999.0
	W.inventory["money"] = 77
	Trade.add(W.inventory, "scrap", 5)
	W.battles_won = 3
	a.add_xp("medicine", 500.0)
	var t_before: float = game.clock.total_seconds
	cast.ruins_looted["1:1"] = 10.0

	# ---- Смерть в городе: выход к воротам, экран со случайным героем
	a.die("thirst")
	await wait_death(cast)
	ok(W.current_kind() == "overworld", "погиб в городе — вышли на общую карту")
	ok(cast.death.active and cast.death._layer.visible, "экран гибели открыт")
	ok(cast.death._title.text.begins_with(a.display_name) and cast.death._cause.text.contains("жажда"), "имя и причина: %s / %s" % [cast.death._title.text, cast.death._cause.text])
	var p: Dictionary = cast.death.params
	ok(String(p.get("name", "")) != "" and P.alloc_valid(p["alloc"]) and P.traits_valid(p["traits"]) == "", "новый персонаж случайный и по правилам: %s" % p.get("name", ""))
	ok(cast.death._bio.text == P.biography(p) and cast.death._stats.text.contains("Удача"), "биография и характеристики на экране")
	await shot("d01_death_screen.png")
	var st: Dictionary = W.city_states.get("s001", {})
	ok(Array(st.get("growth", {}).get("done", [])).has("test_done"), "город запомнил сданное поручение")

	# ---- Клавиши героя и G не работают, пока экран открыт
	key(KEY_G)
	await frames(3)
	ok(cast._creator == null and cast.death.active, "G не открывает старое создание героя")
	game._toggle_menu()
	await frames(2)
	ok(not cast.death._layer.visible, "меню паузы поверх: экран спрятан")
	game._toggle_menu()
	await frames(2)
	ok(cast.death._layer.visible, "меню закрыто: экран снова виден")

	# ---- Продолжить (Enter): новый герой у ворот, мир прежний, всё прежнего героя — нет
	var new_name: String = String(p["name"])
	key(KEY_ENTER)
	await frames(3)
	var b: Actor = cast.hero["actor"]
	ok(not cast.death.active and b != a and b.alive and b.display_name == new_name, "Enter — играем за %s" % b.display_name)
	ok(cast.bodies.filter(func(x): return x["hero"]).size() == 1, "на карте один герой, тело прежнего убрано")
	ok(cast.controls_hero, "управление у нового героя")
	var spawn: Vector2 = game.settlements.spawn_point()
	ok(cast.hero["pos"].distance_to(spawn) < 200.0, "появился у ворот города")
	ok(W.inventory == W.start_inventory(), "сумка как в новой игре: деньги и лом пропали")
	ok(W.battles_won == 0, "счётчик побед сброшен")
	ok(b.skill_level("medicine") == int(P.skill_levels(p).get("medicine", 0)), "навыки прежнего героя не перешли")
	ok(game.clock.total_seconds >= t_before, "время мира не сброшено")
	ok(cast.ruins_looted.has("1:1"), "обысканные руины помнятся")
	st = W.city_states.get("s001", {})
	ok(Array(st["growth"]["done"]).has("test_done"), "сданные поручения остались")
	ok(st["growth"]["taken"].is_empty(), "взятые поручения прежнего героя сняты")
	ok(st["paid_gate"].is_empty() and float(st["intruder_until"]) < 0.0, "оплаченный проход и метка чужака сняты")
	ok(not st.has("fog") and st["discovered"].is_empty(), "план города забыт")
	await shot("d02_new_hero.png")

	# ---- Город с новым героем: рост на месте, поручение можно взять заново
	ok(await W.enter_city("s001", {"return_pos": cast.hero["pos"]}), "новый герой входит в город")
	await frames(5)
	city = W.current_node()
	ok(city.hero == b, "в городе новый герой")
	ok(city.growth["done"].has("test_done") and not Growth.taken(city.growth, q), "в городе: сданное есть, взятого нет")
	ok(not city.discovered.has("test_place"), "в городе: находки на плане забыты")
	await W.leave()
	await wait_free()

	# ---- Смерть в бою (заглушка): бой заканчивается, экран на карте
	await W.start_battle({"stub": true, "enemies": [Actor.new("wolf", "Волк", true, 3)]})
	W.current_node().battle_finished.emit({"outcome": "lose", "game_minutes": 5.0, "dead": ["hero"]})
	await wait_death(cast)
	ok(W.current_kind() == "overworld" and not b.alive and cast.death.active, "гибель в бою — экран на карте")
	ok(cast.death._cause.text.contains("раны"), "причина — раны")

	# ---- Сохранение с погибшим героем: после загрузки экран открывается снова
	ok(game.save_world(true), "сохранение с погибшим героем")
	var slot: String = preload("res://world_save.gd").latest_slot()
	game.queue_free()
	await frames(3)
	game = await load_game(slot)
	cast = game.cast
	await wait_death(cast)
	ok(not cast.hero.is_empty() and not cast.hero["actor"].alive and cast.death.active, "загрузка: погибший герой — экран гибели")

	# ---- Начать заново: экран создания, Esc — назад, «Создать» — новый мир
	cast.death.start_over()
	await frames(3)
	ok(cast.death._creator != null and not cast.death._layer.visible, "«Начать заново» — экран создания героя")
	cast.death._creator.finished.emit({})
	await frames(3)
	ok(cast.death._creator == null and cast.death.active and cast.death._layer.visible, "Esc — назад к экрану гибели")
	cast.death.start_over()
	await frames(2)
	cast.death._creator.randomize_all()
	var fresh_name: String = String(cast.death._creator.params()["name"])
	W.battles_won = 5
	cast.death._creator._on_create()
	var old: Node2D = game
	for i in 300:
		if current_scene != null and current_scene != old and is_instance_valid(current_scene) and current_scene.get("ready_done") == true:
			break
		await process_frame
	game = current_scene
	await wait_game(game)
	await frames(5)
	ok(game != old and game.scene_file_path == "res://game.tscn", "новый мир открыт")
	ok(not game.cast.hero.is_empty() and game.cast.hero["actor"].alive and game.cast.hero["actor"].display_name == fresh_name, "новый герой: %s" % fresh_name)
	ok(W.city_states.is_empty() and W.battles_won == 0 and W.inventory == W.start_inventory(), "новый мир: города, победы и сумка с нуля")
	ok(not game.cast.death.active, "в новом мире экрана нет")

	# ---- forget_hero без Worlds не падает
	HeroDeath.forget_hero(null)
	ok(true, "forget_hero(null) без ошибок")

	print("hero_death_checks: %d/%d" % [checks - fails, checks])
	quit(1 if fails > 0 else 0)

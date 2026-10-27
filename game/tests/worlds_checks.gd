extends SceneTree
## Проверка переходов общая карта ↔ город ↔ бой (worlds/worlds.gd) на заглушках города и боя.
## Нужен экран: под xvfb, --rendering-driver opengl3.
## godot --path game --rendering-driver opengl3 -s res://tests/worlds_checks.gd -- [папка_для_снимков]

const WorldSave := preload("res://world_save.gd")

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


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	shots = args[0] if args.size() > 0 else ""
	_run()


func load_game(slot: String = "") -> Node2D:
	Engine.set_meta("aw_load", slot)
	var game: Node2D = load("res://game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	var t0: int = Time.get_ticks_msec()
	while not game.ready_done and Time.get_ticks_msec() - t0 < 120000:
		await process_frame
	await frames(3)
	return game


func _run() -> void:
	W = root.get_node_or_null("Worlds")
	# Заглушки города и боя — только в тестах (вопрос Q07)
	W.test_doubles = {"city": load("res://tests/doubles/city_stub.gd"), "battle": load("res://tests/doubles/battle_stub.gd")}
	ok(W != null, "автозагрузка Worlds есть")
	var game: Node2D = await load_game()
	ok(game.ready_done and W.game == game, "Worlds подключился к общей карте")
	ok(W.current_kind() == "overworld", "начало на общей карте")
	var cast: Node2D = game.cast
	game.cam_pos = Vector2(20812.0, 18000.0)
	cast.spawn_hero(game.cam_pos)
	var hb: Dictionary = cast.hero
	var hero: Actor = hb["actor"]
	var start: Vector2 = hb["pos"]
	# Один НПС рядом — союзник в бою
	# НПС снаружи города сами не появляются (OVERWORLD_NPCS = false): ставим одного вручную
	var npc: Dictionary = cast.spawn_npc(Actor.new("npc_t", "Проверочный", true, 5), start + Vector2(20, 0))
	npc["pos"] = start + Vector2(20, 0)
	npc["target"] = npc["pos"]
	npc["actor"].set_sleep(false)
	game.zoom = 0.4
	await frames(3)

	# ---- Вход в город
	var gate: Vector2 = start + Vector2(120.0, 40.0)
	await W.enter_city("t1", {"return_pos": gate, "settlement": {"id": "t1", "name": "Проверочный"}, "stub": true})
	ok(W.current_kind() == "city" and W.current_id() == "t1", "вошли в город")
	var city: Node = W.current_node()
	ok(city != null and city.city_name == "Проверочный" and city.hero == hero, "город получил героя и имя")
	ok(city.ctx.get("inventory") == W.inventory, "город получил инвентарь по ссылке")
	ok(not game.terrain_layer.visible and not game.hud_panel.visible, "карта и подсказка спрятаны")
	ok(not cast.visible and not cast.controls_hero and cast.hero_away, "персонажи карты спрятаны, героем cast не управляет")
	var clk0: float = game.clock.total_seconds
	var hunger0: float = hero.res["hunger"]
	var p0: Vector2 = hb["pos"]
	var cpos0: Vector2 = city.pos
	Input.action_press("ui_right")
	await create_timer(2.0).timeout
	Input.action_release("ui_right")
	ok(game.clock.total_seconds > clk0, "время в городе идёт (+%.0f с игровых)" % (game.clock.total_seconds - clk0))
	ok(hero.res["hunger"] < hunger0, "голод героя в городе идёт: %.3f → %.3f" % [hunger0, hero.res["hunger"]])
	ok(hb["pos"] == p0, "герой на общей карте не сдвинулся от клавиш")
	ok(city.pos.x > cpos0.x + 50.0, "в городе герой идёт (%.0f px)" % (city.pos.x - cpos0.x))
	await shot("w01_city_stub.png")

	# Esc в городе открывает меню игры
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	Input.parse_input_event(esc)
	await frames(3)
	ok(game.menu_open and game.pause_panel.visible, "Esc в городе — меню паузы")
	await shot("w02_city_menu.png")
	game._toggle_menu()
	await frames(2)

	# ---- Бой в городе
	await W.start_battle({"return_pos": city.pos, "stub": true,
		"enemies": [Actor.new("bandit_1", "Разбойник", true, 7)]})
	ok(W.current_kind() == "battle", "бой начался")
	var battle: Node = W.current_node()
	ok(battle.req["origin"] == "city:t1", "бой знает, что начат в городе")
	ok(game.clock.paused, "часы мира в бою стоят")
	ok(city.process_mode == Node.PROCESS_MODE_DISABLED and not city.visible, "город спрятан и выключен")
	ok(battle.req["allies"] == [hero], "в городе союзник только герой")
	ok(battle.req["inventory"] == W.inventory, "бой получил инвентарь")
	await create_timer(1.0).timeout
	await shot("w03_battle_in_city.png")
	# Сохранение посреди боя в городе
	ok(WorldSave.write(game, true), "сохранение в бою записано")
	var slot: String = WorldSave.latest_slot()
	var saved: Dictionary = WorldSave.read(slot)
	ok(saved.get("worlds", {}).get("stack", []).size() == 2, "в сейве город и бой")
	ok(WorldSave.list()[0].get("place", "") == "Город: Проверочный", "в списке сохранений видно, где герой")
	var clk1: float = game.clock.total_seconds
	battle.elapsed_s = 600.0
	battle.finish("win")
	while W.busy or W.current_kind() == "battle":
		await process_frame
	ok(W.current_kind() == "city", "после боя — снова в городе")
	ok(not game.clock.paused, "часы снова идут")
	ok(game.clock.total_seconds - clk1 >= 600.0, "бой занял 10 игровых минут: +%.0f с" % (game.clock.total_seconds - clk1))
	ok(city.visible and city.process_mode == Node.PROCESS_MODE_INHERIT, "город снова виден")

	# ---- Выход из города
	city.pos = Vector2(450, 560)   # к воротам
	while W.busy or W.current_kind() == "city":
		await process_frame
	ok(W.current_kind() == "overworld", "вышли на общую карту через ворота")
	ok(hb["pos"] == gate and game.cam_pos.distance_to(gate) < 1.0, "герой у ворот города: %s" % hb["pos"])
	ok(game.terrain_layer.visible and game.hud_panel.visible and cast.visible, "карта снова видна")
	ok(cast.controls_hero and not cast.hero_away, "управление героем вернулось")
	ok(W.city_states.get("t1", {}).get("visits", 0) == 1, "город запомнил своё состояние")
	await frames(3)
	await shot("w04_back_on_map.png")

	# ---- Бой на общей карте: союзник-НПС, возврат на место, гибель героя
	npc["pos"] = hb["pos"] + Vector2(15, 0)
	await W.start_battle({"stub": true, "enemies": [Actor.new("wolf", "Волк", true, 3)]})
	battle = W.current_node()
	ok(battle.req["origin"] == "overworld" and battle.req["allies"].has(npc["actor"]), "бой на карте, НПС рядом — союзник")
	ok(battle.req["terrain"] == W.TERRAIN_KEYS[game.biome_at(hb["pos"])], "местность боя: %s" % battle.req["terrain"])
	await shot("w05_battle_on_map.png")
	battle.battle_finished.emit({"outcome": "lose", "game_minutes": 5.0, "dead": ["hero"]})
	while W.busy or W.current_kind() == "battle":
		await process_frame
	ok(W.current_kind() == "overworld" and not hero.alive, "гибель героя в бою дошла до карты")
	ok(hb["pos"] == gate, "после боя герой там же, где бой начался")

	# ---- Город с повторным визитом помнит состояние
	await W.enter_city("t1", {"return_pos": gate, "stub": true})
	ok(W.current_node().visits == 2, "второй визит: город помнит первый")
	await W.leave()

	# ---- Загрузка сохранения, сделанного в бою в городе
	game.queue_free()
	await frames(3)
	ok(W.game == null and W.stack.is_empty(), "карта выгружена — миры сброшены")
	game = await load_game(slot)
	ok(W.current_kind() == "battle", "после загрузки — снова бой")
	ok(W.stack.size() == 2 and W.stack[0]["kind"] == "city", "под боем — город")
	battle = W.current_node()
	ok(battle.req["enemies"].size() == 1 and battle.req["enemies"][0].display_name == "Разбойник", "враги восстановлены")
	ok(battle.req["allies"].size() == 1 and battle.req["allies"][0] == game.cast.hero["actor"], "герой восстановлен как союзник")
	ok(game.clock.paused and not game.terrain_layer.visible, "часы стоят, карта спрятана")
	battle.finish("flee")
	while W.busy or W.current_kind() == "battle":
		await process_frame
	await W.leave()
	ok(W.current_kind() == "overworld" and game.cast.hero["pos"] == gate, "из загруженного города — к воротам")
	ok(not game.clock.paused, "часы идут")

	# ---- Выход в меню из города
	await W.enter_city("t2", {"return_pos": gate, "stub": true})
	var c2: Node = W.current_node()
	game._on_exit_pressed()
	await frames(5)
	ok(W.game == null and not is_instance_valid(c2), "выход в меню из города убирает город")
	await frames(5)
	print("WORLDS CHECKS: %d/%d" % [checks - fails, checks])
	quit(1 if fails > 0 else 0)

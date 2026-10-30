extends SceneTree
## Бій гілки «Бойова сцена» (battle/battle.tscn) через Worlds: вхід, збереження, завантаження, повернення.
## godot --path game --rendering-driver opengl3 -s res://tests/worlds_battle_checks.gd -- [тека_для_знімків]

const WorldSave := preload("res://world_save.gd")
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


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	shots = args[0] if args.size() > 0 else ""
	_run()


func load_game(slot: String = "") -> Node2D:
	Engine.set_meta("aw_load", slot)
	var game: Node2D = load("res://game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.ready_done:
		await process_frame
	await frames(3)
	return game


func _esc() -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_ESCAPE
	ev.keycode = KEY_ESCAPE
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(2)
	var up: InputEventKey = ev.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	await frames(2)


func _run() -> void:
	var W: Node = root.get_node("Worlds")
	var game: Node2D = await load_game()
	game.cast.spawn_hero(Vector2(20812.0, 18000.0))
	var hb: Dictionary = game.cast.hero
	var here: Vector2 = hb["pos"]
	await frames(3)
	# Налагоджувальної K більше немає (Q07): бій як від випадкового нападу, вороги — з encounters.gd
	W.start_battle({})
	await frames(2)
	while W.busy:
		await process_frame
	var b: Node = W.current_node()
	ok(W.is_battle() and b.get_script().resource_path == "res://battle/battle_scene.gd", "бой из ветки «Боевая сцена»")
	ok(game.clock.paused, "часы стоят")
	await create_timer(2.0).timeout
	if shots != "":
		root.get_viewport().get_texture().get_image().save_png(shots.path_join("w06_real_battle.png"))
	# Esc у бою (Huzzah 2026-10-30): вибрана атака — скасувати; далі — меню паузи; ще раз — закрити
	b.phase = "battle"
	b.mode = "attack"
	await _esc()
	ok(b.mode == "move" and not game.menu_open, "Esc в бою сначала отменяет выбор атаки")
	await _esc()
	ok(game.menu_open and game.pause_panel.visible, "Esc в бою открывает меню паузы")
	await _esc()
	ok(not game.menu_open, "Esc ещё раз закрывает меню")
	ok(WorldSave.write(game, true), "сохранение в бою")
	var slot: String = WorldSave.latest_slot()
	var t0: float = game.clock.total_seconds
	b.battle_finished.emit({"outcome": "win", "game_minutes": 3.0, "dead": []})
	while W.busy or W.is_battle():
		await process_frame
	ok(W.current_kind() == "overworld" and hb["pos"] == here, "возврат на карту на то же место")
	ok(game.clock.total_seconds - t0 >= 180.0, "к часам прибавлены минуты боя")
	game.queue_free()
	await frames(3)
	game = await load_game(slot)
	ok(W.is_battle() and W.current_node().get_script().resource_path == "res://battle/battle_scene.gd", "загрузка сейва — снова бой")
	await create_timer(1.0).timeout
	W.current_node().battle_finished.emit({"outcome": "flee", "game_minutes": 1.0, "dead": []})
	while W.busy or W.is_battle():
		await process_frame
	ok(W.current_kind() == "overworld" and not game.clock.paused, "после загруженного боя — карта, часы идут")
	print("WORLDS BATTLE CHECKS: %d/%d" % [checks - fails, checks])
	quit(1 if fails > 0 else 0)

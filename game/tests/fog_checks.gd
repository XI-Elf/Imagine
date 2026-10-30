extends SceneTree
## Туман війни (Huzzah 2026-10-29): модель world/fog.gd, шар world/fog_layer.gd на загальній карті, M, збереження.
## Потрібен екран: під xvfb, --rendering-driver opengl3.
## godot --path game --rendering-driver opengl3 -s res://tests/fog_checks.gd -- [тека_для_знімків]

const Fog := preload("res://world/fog.gd")
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
	await frames(4)
	root.get_viewport().get_texture().get_image().save_png(shots.path_join(name))


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	shots = args[0] if args.size() > 0 else ""
	_run.call_deferred()


func _run() -> void:
	model_checks()
	await game_checks()
	print("fog_checks: %d/%d" % [checks - fails, checks])
	quit(1 if fails > 0 else 0)


func model_checks() -> void:
	var f := Fog.new()
	ok(f.opened == 0 and not f.known(Vector2(1000, 1000)), "новый мир закрыт туманом")
	var fresh: int = f.reveal(Vector2(1000, 1000))
	ok(fresh > 0 and f.opened == fresh and f.version == 1, "герой открывает круг (%d клеток)" % fresh)
	ok(f.known(Vector2(1000, 1000)) and f.known(Vector2(1000 + Fog.VISION_M - 60.0, 1000)), "внутри радиуса открыто")
	ok(not f.known(Vector2(1000 + Fog.VISION_M + 80.0, 1000)), "за радиусом закрыто")
	ok(f.reveal(Vector2(1000, 1000)) == 0 and f.version == 1, "повторный обход ничего не открывает")
	var near: Fog = Fog.new()
	near.reveal(Vector2(10, 10))
	ok(near.known(Vector2(10, 10)) and not near.known(Vector2(-5, 10)) and not near.known(Vector2(1e6, 1e6)), "угол карты и точки вне карты — без падения")
	# Швидкий рух: шлях між кроками відкритий без прогалин
	var w := Fog.new()
	w.walk_to(Vector2(2000, 2000))
	w.walk_to(Vector2(2000 + 1200, 2000))
	ok(w.known(Vector2(2600, 2000)) and w.known(Vector2(2600, 2000 + 300)), "длинный шаг открывает путь целиком")
	var j := Fog.new()
	j.walk_to(Vector2(2000, 2000))
	j.walk_to(Vector2(30000, 20000))
	ok(not j.known(Vector2(16000, 11000)), "скачок (переход по координатам) путь не открывает")
	w.forget_last()
	w.walk_to(Vector2(20000, 20000))
	ok(not w.known(Vector2(12000, 12000)), "после выхода в город линия от старой точки не тянется")
	# Збереження
	var back := Fog.new()
	back.load_dict(w.to_dict())
	ok(back.opened == w.opened and back.known(Vector2(2600, 2000)) and not back.known(Vector2(12000, 12000)), "to_dict / load_dict: открытое то же")
	var old := Fog.new()
	old.reveal(Vector2(500, 500))
	old.load_dict({})
	ok(old.opened == 0, "сохранение без тумана (старое) — карта закрыта")
	var other := Fog.new(Vector2(10000, 10000))
	other.load_dict(w.to_dict())
	ok(other.opened == 0, "сохранение с другой сеткой не читается")
	ok(w.fraction() > 0.0 and w.fraction() < 0.01, "доля открытого мира мала: %.4f" % w.fraction())


func game_checks() -> void:
	var game: Node2D = load("res://game.tscn").instantiate()
	root.add_child(game)
	var t0: int = Time.get_ticks_msec()
	while not game.ready_done and Time.get_ticks_msec() - t0 < 120000:
		await process_frame
	ok(game.ready_done, "карта загрузилась")
	game.physics.travel_weather = false
	game.clock.paused = true
	var fog: CanvasLayer = game.fog
	ok(fog != null and fog.layer < 10 and fog.layer > 0, "слой тумана над миром, под интерфейсом")
	ok(fog.model.opened == 0 and not fog._rect.visible, "пока героя нет — тумана нет, карта не закрыта")
	var cast: Node2D = game.cast
	var st: Node2D = game.settlements
	var city: Dictionary = st.list[0]
	var ex: Vector2 = st.exit_point(city["id"])
	cast.spawn_hero(ex)
	await frames(4)
	if cast.get("_creator") != null:
		var esc := InputEventKey.new()
		esc.keycode = KEY_ESCAPE
		esc.pressed = true
		Input.parse_input_event(esc)
		await frames(3)
	var hero: Dictionary = cast.hero
	ok(fog._rect.visible and fog.model.known(hero["pos"]), "герой на старте: вокруг открыто, туман на экране")
	var far: Vector2 = hero["pos"] + Vector2(3000, 0)
	ok(not fog.known(far), "далёкая точка в тумане")
	game.zoom = 1.0
	game.cam_pos = hero["pos"]
	await shot("f01_local_start.png")
	# Герой іде: крок за кроком відкриває нове
	var before: int = fog.model.opened
	var dir := Vector2(1, 0)
	for i in 600:
		cast._step(hero, dir, true, 1.0 / 30.0)
		if i % 20 == 0:
			await process_frame
	await frames(3)
	ok(fog.model.opened > before, "прогулка открыла новые клетки (%d → %d)" % [before, fog.model.opened])
	game.cam_pos = hero["pos"]
	game.zoom = 0.5
	await shot("f02_local_walk.png")
	# Глобальна карта
	game.toggle_global_map()
	await frames(4)
	ok(game.global_map and fog._mat.get_shader_parameter("global_mode") == 1.0, "M: глобальная карта, режим тумана — общий")
	await shot("f03_global_map.png")
	game.toggle_global_map()
	await frames(2)
	ok(fog._mat.get_shader_parameter("global_mode") == 0.0, "выход из M — туман снова локальный")
	# Збереження
	var d: Dictionary = WorldSave.build(game)
	ok(d.has("fog") and d["fog"]["cols"] == fog.model.cols, "в сохранении есть открытая часть мира")
	var opened: int = fog.model.opened
	fog.model.cells.fill(0)
	fog.model.opened = 0
	fog.load_dict(d["fog"])
	ok(fog.model.opened == opened and fog.model.known(hero["pos"]), "загрузка возвращает открытое (%d клеток)" % opened)
	WorldSave.apply_late(game, {"cam_pos": game.cam_pos, "zoom": game.zoom, "cast": d["cast"]})
	ok(fog.model.opened == 0 or fog.model.known(hero["pos"]), "старое сохранение без тумана читается без ошибок")
	# Герой у місті — туману немає
	cast.hero_away = true
	await frames(3)
	ok(not fog._rect.visible and fog.known(far), "герой в городе — туман не рисуется")
	cast.hero_away = false

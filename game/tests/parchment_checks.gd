extends SceneTree
## Карта героя на M (Huzzah 2026-10-30): ластик стирає ділянку, розпізнавання й доведення намальованого за Умом і Восприятием,
## окремий аркуш на кожну область з пунктиром краю, нова область — новий аркуш, збереження й старі збереження.
## godot --path game --rendering-driver opengl3 -s res://tests/parchment_checks.gd -- [тека_для_знімків]

const Parchment := preload("res://world/parchment.gd")

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
	var wm: Node = root.get_node_or_null("Worlds")
	if wm != null:
		wm.idle_attacks = false
	var cast: Node2D = game.cast
	cast.spawn_hero(Vector2(20812.0, 18000.0))
	var hero: Dictionary = cast.hero
	var pm: CanvasLayer = cast.parchment
	var a0: int = game.province_at(hero["pos"])
	ok(a0 > 0, "герой в области %d" % a0)
	ok(not pm.has_method("begin_stroke") and not pm.has_method("cut_circle"), "рисования и ластика нет")

	cast.window.open("map")
	await frames(3)
	ok(pm.is_open() and pm.area == a0 and pm.areas == [a0], "лист открыт на текущей области")
	var loops: Array = pm.area_loops(a0)
	var b: Rect2 = pm.area_bounds(a0)
	ok(not loops.is_empty() and loops[0].size() > 20, "край области обведён")
	ok(b.has_point(pm.view_c) and pm.view_z > 0.03, "лист показывает всю область")

	# Пройденное: пусто → открыли кусок → кусок виден на картинке; подробность по Интеллекту
	var fm: Variant = game.fog.model
	hero["actor"].set_stat("int", 9)
	fm.reveal(hero["pos"], 800.0)
	pm.build_known()
	var img: Image = pm._known_tex.get_image()
	var cx: int = int(hero["pos"].x / pm.TEX_STEP_M)
	var cy: int = int(hero["pos"].y / pm.TEX_STEP_M)
	ok(img.get_pixel(cx, cy).a > 0.9, "пройденное место нарисовано")
	ok(img.get_pixel(cx + 60, cy).a == 0.0, "непройденное чистое")
	await shot("p01_known_high_int.png")
	hero["actor"].set_stat("int", 2)
	pm.build_known()
	ok(pm._known_tex.get_image().get_pixel(cx, cy).a < 0.7, "Интеллект 2: лишь смутное пятно")
	ok(pm.detail_tier() == 0 and pm._known_tier == 0, "ступень подробности 0")
	await shot("p02_known_low_int.png")
	hero["actor"].set_stat("int", 5)
	ok(pm.detail_tier() == 1, "Интеллект 5 — очертания")
	ok(pm._fog_changed(), "смена Интеллекта перестраивает картинку")
	cast.window.close()
	ok(not pm.is_open(), "окно закрыто — лист отцеплен")

	# Соседняя область — новый лист с обводом
	var other: Vector2 = Vector2.INF
	for k in 200:
		var p: Vector2 = hero["pos"] + Vector2.from_angle(k * 0.37) * (2000.0 + k * 60.0)
		var id: int = game.province_at(p)
		if id > 0 and id != a0 and game.biome_at(p) > 1:
			other = p
			break
	ok(other != Vector2.INF, "нашлась соседняя область")
	var a1: int = game.province_at(other)
	hero["pos"] = other
	pm._area_t = 1.0
	pm._process(0.1)
	ok(pm.areas == [a0, a1], "зашёл в область %d — у неё появился лист" % a1)
	cast.window.open("map")
	await frames(3)
	ok(pm.area == a1 and not pm.area_loops(a1).is_empty(), "на карте — лист новой области с обводом")
	ok(pm._area_pick.item_count == 2 and not pm._area_pick.disabled, "листы переключаются")
	await shot("p03_new_area.png")
	cast.window.close()

	# Сохранение и старые сохранения (штрихи отбрасываются)
	var d: Dictionary = cast.to_dict()
	var back: Dictionary = str_to_var(var_to_str(d))
	pm.clear()
	ok(pm.areas.is_empty(), "clear: чистая карта")
	cast.load_dict(back)
	ok(pm.areas == [a0, a1], "листы областей пережили сохранение")
	pm.load_dict({"strokes": [{"c": "black", "w": 3.0, "pts": [1.0, 1.0, 5.0, 5.0]}], "sheets": {str(a0): {"strokes": [{"pts": [1.0, 2.0]}], "view": [100.0, 200.0, 0.05]}},
		"areas": [a0], "fragments": [{"x": 1.0, "y": 2.0, "r": 3.0}], "area": a0})
	ok(pm.areas == [a0] and pm.fragments.size() == 1 and not pm.sheets[str(a0)].has("strokes"), "старое сохранение: штрихи отброшены, обрывки целы")

	print("PARCHMENT CHECKS: %d/%d" % [checks - fails, checks])
	quit(1 if fails > 0 else 0)

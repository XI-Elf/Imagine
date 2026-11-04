extends SceneTree
## Правки 2D 07 patch 01 (Huzzah 2026-10-23): сон у халупі й пробудження, анімація фігурок у місті,
## обладунок бою з удягненого на «Тіло». Потрібен екран (xvfb, --rendering-driver opengl3):
## godot --path game --rendering-driver opengl3 -s res://tests/p01_checks.gd -- [тека_для_знімків]

const Core := preload("res://battle/battle_core.gd")
const Trade := preload("res://city/trade.gd")

var fails: int = 0
var checks: int = 0
var dir: String = ""


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("FAIL: ", what)
	else:
		print("ok: ", what)


func shot(name: String) -> void:
	for i in 4:
		await process_frame
	if dir != "":
		root.get_viewport().get_texture().get_image().save_png(dir.path_join(name))


func _initialize() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	dir = a[0] if a.size() > 0 else ""
	_run()


func _run() -> void:
	var city: Node2D = load("res://city/city_world.tscn").instantiate()
	root.add_child(city)
	city.enter("s001", null, {})
	city.clock.paused = true
	await process_frame
	var bed: Dictionary = {}
	for p in city.def.get("places", []):
		if String(p.get("kind", "")) == "bed":
			bed = p
	ok(not bed.is_empty(), "в лачуге есть лежанка")
	city.hero_pos = city._place_pos(bed)
	city.cam.zoom = Vector2(3, 3)
	city.cam.position_smoothing_enabled = false
	city.use_place(bed)
	ok(city.hero.sleeping, "лёг спать")
	for i in 5:
		city._process(0.05)
	ok(city.hero.sleeping, "без шага спит дальше")
	await shot("p01_sleep.png")
	var env: Dictionary = city.env_at(city.hero_pos)
	var start: Vector2 = city.hero_pos
	city.move_hero(Vector2.LEFT, false, 0.1, env)
	ok(not city.hero.sleeping, "первый шаг будит")
	city.move_hero(Vector2.LEFT, false, 0.1, env)
	ok(city.hero_pos != start, "после пробуждения идёт")
	# Виспався — встає сам
	city.hero.set_sleep(true)
	city.hero.res["energy"] = 100.0
	city.move_hero(Vector2.ZERO, false, 0.1, env)
	ok(city.hero.sleeping, "только лёг — не вскакивает")
	city.hero.sleep_h = 2.0
	city.move_hero(Vector2.ZERO, false, 0.1, env)
	ok(not city.hero.sleeping, "с полной энергией встаёт сам")
	# Анімація: стоячи дихає, на ходу крокує — кадри різняться
	var g: Dictionary = city.def["gates"][0]
	city.hero_pos = Vector2(g["spawn"][0], g["spawn"][1]) * city.map.cell_m + Vector2(0, -3)
	city._process(0.05)
	var moved: int = 0
	var imgs: Array = []
	for k in 3:
		for i in 3:
			var before: Vector2 = city.hero_pos
			city.move_hero(Vector2.UP, false, 0.02, env)
			if city.hero_pos != before:
				moved += 1
			city.art_time += 0.04
		city.art_moving = true
		city._actors.queue_redraw()
		city._roofs.queue_redraw()
		await process_frame
		await process_frame
		imgs.append(root.get_viewport().get_texture().get_image())
		if k == 1 and dir != "":
			imgs[-1].save_png(dir.path_join("p02_walk.png"))
	ok(moved > 0, "герой идёт от ворот")
	ok(imgs[0].get_data() != imgs[1].get_data(), "кадры шага отличаются")
	ok(Core.worn_armor({"items": {}, "equipped": {}}) == "none", "без одежды — без доспеха")
	var inv: Dictionary = {"items": {"leather_jacket": 1}, "equipped": {"body": "leather_jacket"}}
	ok(Core.worn_armor(inv) == "leather", "кожаная куртка на «Тело» — кожаный доспех в бою")
	inv["equipped"] = {"body": "linen_shirt"}
	ok(Core.worn_armor(inv) == "none", "рубаха — не доспех")
	print("p01_checks: %d/%d" % [checks - fails, checks])
	quit(1 if fails > 0 else 0)

extends SceneTree
## Тёмный мир и техно-артефакты (Q31 B): фильтр ui/world_grade.gd на карте, в городе и в бою (интерфейс —
## без фильтра), руины машин (characters/cast.gd), сигнальные вышки (storybook/world_decor.gd), вышка и остов
## машины в Эшвике (data/cities/s001.json). Нужен экран: под xvfb, --rendering-driver opengl3.
## godot --path game --rendering-driver opengl3 -s res://tests/dark_world_checks.gd -- [папка_для_снимков]

const WorldGrade := preload("res://ui/world_grade.gd")
const Ruins := preload("res://world/ruins.gd")
const Art := preload("res://storybook/art.gd")
const CityMap := preload("res://city/city_map.gd")

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


func lum(c: Color) -> float:
	return c.r * 0.299 + c.g * 0.587 + c.b * 0.114


## Средняя яркость кадра (по сетке точек)
func frame_lum() -> float:
	var img: Image = root.get_viewport().get_texture().get_image()
	var s: float = 0.0
	var n: int = 0
	for y in range(40, img.get_height() - 120, 37):
		for x in range(40, img.get_width() - 40, 41):
			s += lum(img.get_pixel(x, y))
			n += 1
	return s / maxf(n, 1)


func _run() -> void:
	# ---- спрайты
	for k in ["tech_wreck", "tech_tower", "tech_dome"]:
		var t: Texture2D = Art.tex(k)
		ok(t != null and t.get_height() >= 256, "спрайт %s есть" % k)
	# ---- город: вышка и остов машины стоят на свободной земле и непроходимы
	var f := FileAccess.open("res://data/cities/s001.json", FileAccess.READ)
	var def: Dictionary = JSON.parse_string(f.get_as_text())
	var m := CityMap.new()
	m.build(def)
	var tech: Array = def["props"].filter(func(p): return String(p["kind"]).begins_with("tech_"))
	ok(tech.size() == 2, "в Эшвике 2 техно-артефакта")
	var solid: bool = true
	for p in tech:
		for c in p["cells"]:
			solid = solid and m.solid(int(c[0]), int(c[1])) and m.bld[int(c[1]) * m.w + int(c[0])] == -1
	ok(solid, "артефакты в городе — препятствие и не в домах")
	var ids: Array = []
	for st in def["growth"]["stages"]:
		ids.append_array(st.get("props", []))
	ok(not ids.has(def["props"].size() - 1) and not ids.has(def["props"].size() - 2), "артефакты стоят с самого начала (не этап роста)")

	# ---- главное меню: фильтра нет
	var skin: Node = root.get_node_or_null("ComicSkin")
	ok(skin != null and skin.grade != null, "слой фильтра держит ComicSkin")
	Engine.set_meta("aw_intro_done", true)
	var menu: Control = load("res://main_menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	await frames(3)
	ok(not skin.grade.visible, "в главном меню фильтра нет")
	menu.queue_free()
	await frames(2)

	# ---- общая карта
	Engine.set_meta("aw_load", "")
	var game: Node2D = load("res://game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	var t0: int = Time.get_ticks_msec()
	while not game.ready_done and Time.get_ticks_msec() - t0 < 120000:
		await process_frame
	await frames(3)
	ok(skin.grade.visible and skin.grade.layer < 10, "на карте фильтр включён и стоит под интерфейсом")
	game.clock.paused = true
	game.clock.total_seconds = floorf(game.clock.total_seconds / 86400.0) * 86400.0 + 12.0 * 3600.0
	game.physics.set("travel_weather", false)
	# руины машин: ищем ближайшие к городу
	var start := Vector2(20812.0, 18000.0)
	var sites: Array = Ruins.in_rect(game, Rect2(start - Vector2(6000, 6000), Vector2(12000, 12000)))
	ok(not sites.is_empty(), "руины машин на карте есть (%d в 12×12 км)" % sites.size())
	if not sites.is_empty():
		sites.sort_custom(func(a, b): return a["pos"].distance_to(start) < b["pos"].distance_to(start))
		game.cam_pos = sites[0]["pos"] + Vector2(0, -4)
		game.zoom = 6.0
		await frames(6)
		skin.grade.visible = false
		skin.set_process(false)
		await frames(4)
		await shot("d01_ruin_before.png")
		var before: float = frame_lum()
		skin.grade.visible = true
		await frames(4)
		await shot("d02_ruin_after.png")
		var after: float = frame_lum()
		skin.set_process(true)
		ok(after < before * 0.85, "мир заметно темнее: яркость %.2f → %.2f" % [before, after])
	# вышки: ищем в данных декора
	var decor: Node = null
	for n in game.get_children():
		if n.get_script() != null and String(n.get_script().resource_path).ends_with("world_decor.gd"):
			decor = n
	ok(decor != null and decor.KEYS.has("tech_tower") and decor._uv.has("tech_tower"), "вышка в атласе декора")
	var tower_at := Vector2.INF
	if decor != null:
		var c0 := Vector2i(int(start.x / decor.CHUNK), int(start.y / decor.CHUNK))
		for r in range(0, 40):
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if tower_at != Vector2.INF or (absi(dx) != r and absi(dy) != r):
						continue
					var k := c0 + Vector2i(dx, dy)
					for e in decor._chunk_data(k)["big"]:
						if e[1] == "tech_tower":
							tower_at = Vector2(k) * decor.CHUNK + e[0]
			if tower_at != Vector2.INF:
				break
	ok(tower_at != Vector2.INF, "сигнальная вышка недалеко от города: %s" % str(tower_at))
	if tower_at != Vector2.INF:
		game.cam_pos = tower_at + Vector2(0, -8)
		game.zoom = 9.0
		await frames(8)
		await shot("d03_tower.png")
		game.zoom = 1.2
		await frames(8)
		await shot("d04_map_far.png")
	# ночь
	game.clock.total_seconds = floorf(game.clock.total_seconds / 86400.0) * 86400.0 + 23.0 * 3600.0
	game.cam_pos = start
	game.zoom = 3.0
	await frames(8)
	skin.set_process(false)
	skin.grade.visible = false
	await frames(4)
	var n_before: float = frame_lum()
	skin.set_process(true)
	await frames(4)
	await shot("d05_map_night.png")
	var n_after: float = frame_lum()
	ok(n_after >= n_before * 0.8, "ночью фильтр слабее и не прячет дорогу: %.3f → %.3f" % [n_before, n_after])
	ok(is_equal_approx(WorldGrade.strength_at(12.0), WorldGrade.STRENGTH) and WorldGrade.strength_at(0.0) < 0.5, "сила фильтра: полдень полная, полночь слабая")

	# ---- город
	var W: Node = root.get_node("Worlds")
	game.cast.spawn_hero(start)
	game.clock.total_seconds = floorf(game.clock.total_seconds / 86400.0) * 86400.0 + 12.0 * 3600.0
	ok(await W.enter_city("s001", {"return_pos": game.cast.hero["pos"]}), "вошли в Эшвик")
	await frames(4)
	var city: Node = W.current_node()
	ok(skin.grade.visible, "в городе фильтр включён")
	city.clock.paused = true
	city.hero_pos = Vector2(23.0, 58.5)
	for i in 3:
		city._process(0.05)
	skin.set_process(false)
	skin.grade.visible = false
	await frames(4)
	var c_before: float = frame_lum()
	skin.grade.visible = true
	await frames(4)
	var c_after: float = frame_lum()
	skin.set_process(true)
	ok(c_after < c_before * 0.85, "город заметно темнее: %.2f → %.2f" % [c_before, c_after])
	await shot("d06_city_tower.png")
	city.hero_pos = Vector2(46.5, 69.0)
	for i in 3:
		city._process(0.05)
	await shot("d07_city_wreck.png")
	await frames(2)

	# ---- бой: фильтр между полем и панелями
	var b: CanvasLayer = load("res://battle/battle.tscn").instantiate()
	root.add_child(b)
	await frames(2)
	var g: Node = b.get_node_or_null("WorldGrade")
	ok(g != null and g.get_index() == b.view.get_index() + 1 and b.hud.get_index() > g.get_index(), "в бою фильтр после поля и до панелей")
	b.queue_free()
	await frames(2)
	print("dark_world_checks: %d/%d" % [checks - fails, checks])
	quit(1 if fails > 0 else 0)

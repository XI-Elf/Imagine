extends SceneTree
## Протоптанные дороги (Huzzah 2026-10-28): готовой дороги к городу нет; тропа — от 50 проходов через участок,
## ступени до грунтовой дороги, зарастание, сохранение; общая карта (world/trails_layer.gd, characters/cast.gd,
## путь мышью characters/hero_route.gd) и город (city/city_world.gd: герой и жители).
## Нужен экран: под xvfb, --rendering-driver opengl3.
## godot --path game --rendering-driver opengl3 -s res://tests/trails_checks.gd -- [папка_для_снимков]

const Trails := preload("res://world/trails.gd")
const WorldSave := preload("res://world_save.gd")
const CityMap := preload("res://city/city_map.gd")
const Trade := preload("res://city/trade.gd")
const DAY: float = 86400.0

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


## Ходок key туда-обратно между a и b (метры) trips раз, шагами step метров
func shuttle(t: RefCounted, key: Variant, a: Vector2, b: Vector2, trips: int, now: float, step: float = 2.0) -> void:
	var n: int = maxi(int(a.distance_to(b) / step), 1)
	for k in trips:
		for i in n + 1:
			t.walk(key, a.lerp(b, float(i) / n), now)
		for i in n + 1:
			t.walk(key, b.lerp(a, float(i) / n), now)


func _run() -> void:
	model_checks()
	await overworld_checks()
	await city_checks()
	print("trails_checks: %d/%d" % [checks - fails, checks])
	quit(1 if fails > 0 else 0)


# ---------------------------------------------------------------- модель
func model_checks() -> void:
	var t := Trails.new(10.0)
	var c := Vector2i(3, 0)
	for i in 49:
		t.add_pass(c, 0.0)
	ok(t.stage_of.get(c, 0) == 0 and t.count_of(c, 0.0) == 49.0, "49 проходов — ещё не тропа")
	t.add_pass(c, 0.0)
	ok(t.stage_of.get(c, 0) == 1 and t.stage_name_at(t.center_of(c)) == "тропинка", "50-й проход — тропинка")
	ok(Trails.stage_for(119) == 1 and Trails.stage_for(120) == 2 and Trails.stage_for(250) == 3 and Trails.stage_for(500) == 4,
		"ступени 50 / 120 / 250 / 500: тропинка, тропа, просёлок, грунтовая дорога")
	ok(Trails.STAGE_NAMES[4] == "грунтовая дорога" and Trails.SPEED[4] > Trails.SPEED[1] and Trails.SPEED[1] > 1.0, "по дороге шаг быстрее, чем по тропинке")

	# Проход — вход в клетку: стоять и топтаться внутри клетки не считается, скачок тоже
	var w := Trails.new(10.0)
	for i in 30:
		w.walk("hero", Vector2(5 + i * 0.1, 5), 0.0)
	ok(w.cells.is_empty(), "шаги внутри одной клетки — не проход")
	w.walk("hero", Vector2(15, 5), 0.0)
	ok(w.count_of(Vector2i(1, 0), 0.0) == 1.0, "переход в соседнюю клетку — один проход")
	w.walk("hero", Vector2(500, 5), 0.0)
	ok(w.count_of(Vector2i(50, 0), 0.0) == 0.0, "скачок (загрузка, вход в город) — не проход")
	w.walk("hero", Vector2(530, 5), 0.0)
	ok(w.count_of(Vector2i(51, 0), 0.0) == 1.0 and w.count_of(Vector2i(52, 0), 0.0) == 1.0 and w.count_of(Vector2i(53, 0), 0.0) == 1.0,
		"длинный шаг через три клетки — проход по каждой")
	w.clear()
	shuttle(w, "hero", Vector2(5, 5), Vector2(95, 5), 25, 0.0)
	ok(w.stage_of.get(Vector2i(5, 0), 0) == 1 and w.count_of(Vector2i(5, 0), 0.0) == 50.0, "25 раз туда и обратно — 50 проходов, тропинка")
	shuttle(w, "npc", Vector2(5, 5), Vector2(95, 5), 225, 0.0)
	ok(w.stage_of.get(Vector2i(5, 0), 0) == 4, "НПС тем же путём — грунтовая дорога (%d проходов)" % w.count_of(Vector2i(5, 0), 0.0))

	# Зарастание: 3 суток без проходов — как было, дальше −5 проходов в сутки
	var d := Trails.new(10.0)
	d.add_pass(c, 0.0, 60.0)
	ok(d.count_of(c, 3.0 * DAY) == 60.0, "3 игровых дня без проходов — тропа как была")
	ok(is_equal_approx(d.count_of(c, 5.0 * DAY), 50.0), "ещё 2 дня — минус 10 проходов")
	d.refresh(6.0 * DAY)
	ok(d.stage_of.get(c, 0) == 0 and d.cells.has(c), "заросла до следов: ступени нет, клетка помнится")
	d.refresh(40.0 * DAY)
	ok(not d.cells.has(c), "совсем заросла — клетка забыта")
	d.add_pass(c, 0.0, 600.0)
	d.refresh(30.0 * DAY)
	ok(d.stage_of.get(c, 0) == 3, "грунтовка за месяц без хождения — просёлок (%.0f)" % d.count_of(c, 30.0 * DAY))
	d.decay_per_day = 0.0
	ok(d.count_of(c, 900.0 * DAY) == 600.0, "decay_per_day = 0 — не зарастает")
	d.decay_per_day = 5.0
	ok(d.decay_min_stage == 3 and d.count_of(c, 900.0 * DAY) == 250.0, "по умолчанию (решение Huzzah): дорога не зарастает ниже просёлка")
	d.refresh(900.0 * DAY)
	ok(d.stage_of.get(c, 0) == 3, "через 900 дней без хождения — всё ещё просёлок")
	d.add_pass(c, 900.0 * DAY)
	d.refresh(2000.0 * DAY)
	ok(d.stage_of.get(c, 0) == 3, "проход по заросшему до просёлка — снова не ниже просёлка")
	d.decay_min_stage = 0
	ok(d.count_of(c, 4000.0 * DAY) == 0.0, "decay_min_stage = 0 — зарастает целиком")
	var tp := Trails.new(10.0)
	tp.add_pass(c, 0.0, 200.0)
	tp.refresh(60.0 * DAY)
	ok(not tp.cells.has(c), "тропа (200 проходов) за 2 месяца без хождения заросла совсем")
	d.add_pass(Vector2i(9, 9), 0.0, 10.0)
	ok(d.count_of(Vector2i(9, 9), 31.0 * DAY) == 0.0, "одиночные следы забываются через 30 дней")

	# Сохранение
	var s := Trails.new(10.0)
	s.add_pass(Vector2i(2, -3), 100.0, 130.0)
	s.add_pass(Vector2i(-4, 7), 200.0, 7.0)
	var back := Trails.new(10.0)
	back.load_dict(s.to_dict())
	ok(back.cells.size() == 2 and back.stage_of.get(Vector2i(2, -3), 0) == 2 and back.count_of(Vector2i(-4, 7), 200.0) == 7.0,
		"to_dict / load_dict: проходы и ступени те же")
	var other := Trails.new(12.0)
	other.load_dict(s.to_dict())
	ok(other.cells.is_empty(), "сохранение с другой клеткой не читается")


# ---------------------------------------------------------------- общая карта
func overworld_checks() -> void:
	var game: Node2D = load("res://game.tscn").instantiate()
	root.add_child(game)
	var t0: int = Time.get_ticks_msec()
	while not game.ready_done and Time.get_ticks_msec() - t0 < 120000:
		await process_frame
	ok(game.ready_done, "карта загрузилась")
	game.physics.travel_weather = false
	game.clock.paused = true
	var st: Node2D = game.settlements
	var city: Dictionary = st.list[0]
	ok(not city.has("road") and not city.has("_road") and not st.has_method("_draw_road"), "готовой дороги к городу нет")
	var tl: Node2D = game.trails
	ok(tl != null and tl.get_index() < st.get_index() and tl.get_index() < game.cast.get_index(), "тропы рисуются под поселением и персонажами")
	ok(tl.model.cells.is_empty(), "новая игра — троп нет")

	var cast: Node2D = game.cast
	var ex: Vector2 = st.exit_point(city["id"])
	cast.spawn_hero(ex)
	await frames(3)
	await _key_escape()
	var hero: Dictionary = cast.hero
	var out_dir: Vector2 = (city["_gate"] - city["_center"]).normalized()
	# Настоящие шаги героя (cast._step) считают проходы
	var cells_before: int = tl.model.cells.size()
	for i in 240:
		cast._step(hero, out_dir, false, 1.0 / 30.0)
	ok(tl.model.cells.size() > cells_before, "шаги героя по карте протаптывают клетки (%d)" % tl.model.cells.size())

	# От ворот наружу и обратно: 25 раз — тропинка, 250 — грунтовая дорога
	var now: float = game.clock.total_seconds
	var a: Vector2 = ex
	var b: Vector2 = ex + out_dir * 180.0
	var key: Actor = hero["actor"]
	tl.model.clear()
	shuttle(tl.model, key, a, b, 24, now)
	var mid: Vector2 = a.lerp(b, 0.5)
	ok(tl.model.stage_at(mid) == 0, "48 проходов от ворот — тропы ещё нет")
	shuttle(tl.model, key, a, b, 1, now)
	ok(tl.model.stage_at(mid) == 1, "50 проходов — тропинка")
	game.zoom = 0.4
	game.cam_pos = mid
	await shot("t01_path_zoom04.png")
	shuttle(tl.model, key, a, b, 225, now)
	ok(tl.model.stage_at(mid) == 4, "500 проходов — грунтовая дорога")
	ok(is_equal_approx(tl.speed_mult(mid), Trails.SPEED[4]), "на грунтовой дороге шаг быстрее: ×%.2f" % tl.speed_mult(mid))
	await shot("t02_road_zoom04.png")
	game.zoom = 0.08
	await shot("t03_road_zoom008.png")
	game.zoom = 1.5
	await frames(30)
	await shot("t04_road_zoom15.png")
	var decor: Node = null
	for ch in game.get_children():
		if ch.has_method("_chunk_data"):
			decor = ch
	var on_road: int = 0
	var k := Vector2i(floori(mid.x / decor.CHUNK), floori(mid.y / decor.CHUNK))
	var dd: Dictionary = decor._chunk_data(k)
	for e in dd["big"] + dd["small"]:
		if tl.trodden(Vector2(k) * decor.CHUNK + e[0]):
			on_road += 1
	ok(decor != null and on_road == 0, "на дороге нет деревьев и кустов декора (%d)" % on_road)

	# Путь мышью сворачивает на тропу: дорога-крюк дешевле прямой по целине
	var p0: Vector2 = ex + out_dir * 900.0
	var side: Vector2 = Vector2(-out_dir.y, out_dir.x)
	var p1: Vector2 = p0 + side * 600.0
	var bend: Vector2 = p0.lerp(p1, 0.5) + out_dir * 150.0
	var land: bool = true
	for q in [p0, p1, bend]:
		land = land and game.biome_at(q) > 1 and game.biome_at(q) != 7 and game.biome_at(q) != 8 and game.biome_at(q) != 9
	ok(land, "место для пути по суше без проклятья")
	cast.route._plan(p0, p1)
	var straight_far: float = _far_from(cast.route.points, bend)
	tl.model.clear()
	for seg in [[p0, bend], [bend, p1]]:
		var n: int = int(seg[0].distance_to(seg[1]) / 4.0)
		for i in n + 1:
			tl.model.add_pass(tl.model.cell_at(seg[0].lerp(seg[1], float(i) / n)), now, 500.0)
	cast.route._plan(p0, p1)
	var trail_far: float = _far_from(cast.route.points, bend)
	ok(trail_far < 40.0 and straight_far > 80.0, "путь мышью идёт по дороге: у изгиба %.0f м (без дороги %.0f м)" % [trail_far, straight_far])
	cast.route.cancel()

	# Зарастание по часам игры (раз в игровой час)
	tl.model.clear()
	tl.model.add_pass(tl.model.cell_at(mid), now, 55.0)
	# Нужды героя за 8 дней не считаются: cast на это время выключен
	cast.set_process(false)
	game.clock.total_seconds = now + 8.0 * DAY
	tl._refreshed_at = -1.0
	await frames(2)
	ok(tl.model.stage_at(mid) == 0, "8 игровых дней без хождения — тропинка заросла")
	game.clock.total_seconds = now
	await frames(1)
	cast.set_process(true)

	# Сохранение мира
	tl.model.clear()
	shuttle(tl.model, key, a, b, 70, now)
	var saved: Dictionary = WorldSave.build(game)
	ok(saved.has("trails"), "в сохранении мира есть тропы")
	var n_cells: int = tl.model.stage_of.size()
	tl.model.clear()
	WorldSave.apply_late(game, saved)
	ok(tl.model.stage_of.size() == n_cells and tl.model.stage_at(mid) == 2, "после загрузки тропа на месте (%d клеток, ступень %d)" % [n_cells, tl.model.stage_at(mid)])
	var old: Dictionary = saved.duplicate()
	old.erase("trails")
	WorldSave.apply_late(game, old)
	ok(tl.model.cells.is_empty(), "старое сохранение без троп — дорог нет")
	game.queue_free()
	await frames(3)


func _far_from(points: PackedVector2Array, q: Vector2) -> float:
	var best: float = INF
	for i in points.size():
		best = minf(best, points[i].distance_to(q))
		if i > 0:
			best = minf(best, Geometry2D.get_closest_point_to_segment(q, points[i - 1], points[i]).distance_to(q))
	return best


func _key_escape() -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_ESCAPE
	ev.keycode = KEY_ESCAPE
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(1)
	var up: InputEventKey = ev.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	await frames(1)


# ---------------------------------------------------------------- город
func city_checks() -> void:
	var city: Node2D = load("res://city/city_world.tscn").instantiate()
	root.add_child(city)
	var hero := Actor.new("hero", "Герой", false, 7)
	city.enter("s001", hero, {"inventory": Trade.new_bag(60), "gate": "south"})
	await frames(5)
	city.menu.close()
	city.walking = true
	ok(city.trails.cell_m == city.map.cell_m, "в городе клетка тропы = клетка карты (%.1f м)" % city.map.cell_m)
	# Жители ходят по распорядку и сами протаптывают землю
	# Жители стоят на службе с утра; вечером идут домой
	city.clock.total_seconds = city.clock.total_seconds - fposmod(city.clock.total_seconds, DAY) + 20.0 * 3600.0
	for i in 300:
		await process_frame
	ok(city.trails.cells.size() > 0, "жители протаптывают город (%d клеток)" % city.trails.cells.size())
	# Трава у героя: туда-обратно 50 раз
	var g: Vector2i = Vector2i(-1, -1)
	var hc: Vector2i = city.map.cell_of(city.hero_pos)
	for r in range(1, 20):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c: Vector2i = hc + Vector2i(dx, dy)
				if g == Vector2i(-1, -1) and city.map.at(c.x, c.y) == CityMap.T.GRASS and city.map.at(c.x + 1, c.y) == CityMap.T.GRASS \
						and city.map.at(c.x + 2, c.y) == CityMap.T.GRASS and not city._sprite_cell(c.x, c.y):
					g = c
	ok(g != Vector2i(-1, -1), "трава рядом с героем: %s" % g)
	var now: float = city.clock.total_seconds
	var a: Vector2 = city.map.center_of(g)
	var b: Vector2 = city.map.center_of(g + Vector2i(2, 0))
	var before: float = city.ground_speed(city.map.center_of(g + Vector2i(1, 0)))
	city.trails.clear()
	shuttle(city.trails, hero, a, b, 25, now, 0.25)
	var mid: Vector2 = city.map.center_of(g + Vector2i(1, 0))
	ok(city.trails.stage_at(mid) == 1, "в городе 50 проходов по траве — тропинка")
	shuttle(city.trails, hero, a, b, 225, now, 0.25)
	ok(city.trails.stage_at(mid) == 4 and city.ground_speed(mid) > before, "грунтовка по траве: шаг ×%.2f → ×%.2f" % [before, city.ground_speed(mid)])
	city.hero_pos = mid + Vector2(0, 1.5)
	city._ground.queue_redraw()
	await shot("t05_city_trail.png")
	# Состояние города: тропы помнятся между визитами
	var state: Dictionary = city.to_dict()
	ok(state.has("trails"), "в состоянии города есть тропы")
	city.queue_free()
	await frames(2)
	var again: Node2D = load("res://city/city_world.tscn").instantiate()
	root.add_child(again)
	state["left"] = true
	again.enter("s001", hero, {"inventory": Trade.new_bag(60), "gate": "south", "state": state})
	await frames(3)
	ok(again.trails.stage_at(mid) == 4, "новый визит — дорога на месте")
	again.queue_free()
	await frames(2)

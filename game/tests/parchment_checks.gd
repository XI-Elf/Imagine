extends SceneTree
## Карта героя на M (Huzzah 2026-10-30): ластик стирає ділянку, розпізнавання й доведення намальованого за Умом і Чутьём,
## окремий аркуш на кожну область з пунктиром краю, нова область — новий аркуш, збереження й старі збереження.
## godot --path game --rendering-driver opengl3 -s res://tests/parchment_checks.gd -- [тека_для_знімків]

const Parchment := preload("res://world/parchment.gd")
const Sketch := preload("res://world/map_sketch.gd")

var fails: int = 0
var checks: int = 0
var shots: String = ""


## Вигадана місцевість: ліс ліворуч від x = 5000, смуга води y 900..1100, одне поселення
class FakeLand extends RefCounted:
	var settlements: FakeTowns = FakeTowns.new()

	func biome_at(p: Vector2) -> int:
		if absf(p.y - 1000.0) < 100.0:
			return 1
		return 3 if p.x < 5000.0 else 4

	func water_at(p: Vector2) -> float:
		return 1.0 if absf(p.y - 1000.0) < 100.0 else 0.0


class FakeTowns extends RefCounted:
	var list: Array = [{"_center": Vector2(20000, 20000), "name": "Эшвик"}]


class FakeActor extends RefCounted:
	var v: float = 5.0

	func _init(x: float) -> void:
		v = x

	func stat(_s: String) -> float:
		return v


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
	_pure()
	_run()


func _circle(c: Vector2, r: float, n: int, wobble: float, seed: int) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var p := PackedVector2Array()
	for i in n + 1:
		p.append(c + Vector2.from_angle(TAU * i / n) * (r + rng.randf_range(-wobble, wobble)))
	return p


func _max_shift(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var worst: float = 0.0
	for v in b:
		var best: float = INF
		for u in a:
			best = minf(best, u.distance_to(v))
		worst = maxf(worst, best)
	return worst


# Без сцени: ластик, якість, розпізнавання, доведення
func _pure() -> void:
	var line: Array = []
	for i in 11:
		line.append(i * 10.0)
		line.append(0.0)
	var cut: Array = Parchment.cut_circle(line, Vector2(50, 0), 10.0)
	ok(cut.size() == 2, "ластик посреди линии: два куска (%d)" % cut.size())
	if cut.size() == 2:
		ok(is_equal_approx(cut[0][-2], 40.0) and is_equal_approx(cut[1][0], 60.0), "стёрт только участок 40..60 м")
		ok(is_equal_approx(cut[0][0], 0.0) and is_equal_approx(cut[1][-2], 100.0), "концы линии на месте")
	ok(Parchment.cut_circle(line, Vector2(100, 0), 15.0).size() == 1, "ластик на конце: линия короче, одна")
	ok(Parchment.cut_circle(line, Vector2(50, 50), 10.0)[0].size() == line.size(), "ластик мимо: линия цела")
	ok(Parchment.cut_circle([0.0, 0.0, 1.0, 0.0], Vector2(0.5, 0), 5.0).is_empty(), "ластик целиком: точка исчезла")

	ok(Sketch.quality(FakeActor.new(1.0)) == 0.0 and Sketch.quality(FakeActor.new(9.0)) == 1.0, "Ум и Чутьё 1 — 0, по 9 — 1")
	ok(absf(Sketch.quality(FakeActor.new(5.0)) - 0.5) < 0.01, "средний герой — половина")

	var land := FakeLand.new()
	var z: float = 0.03
	# Замкнений обрис у лісі
	var ring: PackedVector2Array = _circle(Vector2(2500, 3000), 1500.0, 40, 120.0, 3)
	var info: Dictionary = Sketch.classify(ring, z, "black", land)
	ok(info["k"] == "forest" and info["closed"], "обвёл лес — лес (%s)" % info["k"])
	var low: Dictionary = Sketch.tidy(ring, info, 0.0, z, land, 1)
	ok(low["pts"] == ring and low["m"].is_empty(), "Ум и Чутьё низкие: рисунок как есть")
	var high: Dictionary = Sketch.tidy(ring, info, 1.0, z, land, 1)
	ok(high["m"].size() >= 3 and high["m"][0]["k"] == "tree", "высокие: домалёваны деревца (%d)" % high["m"].size())
	var shift_px: float = _max_shift(ring, high["pts"]) * z
	ok(shift_px <= Sketch.MAX_SHIFT_PX + 8.0, "рисунок узнаваем: сдвиг не больше %.0f px (%.1f)" % [Sketch.MAX_SHIFT_PX + 8.0, shift_px])
	var mid: Dictionary = Sketch.tidy(ring, info, 0.5, z, land, 1)
	ok(mid["m"].size() < high["m"].size(), "средние: знаков меньше (%d < %d)" % [mid["m"].size(), high["m"].size()])
	# Лінія вздовж води — річка, притягується до води
	var river := PackedVector2Array()
	for i in 30:
		river.append(Vector2(6000 + i * 300.0, 1250.0 + sin(i * 0.9) * 40.0))
	var ri: Dictionary = Sketch.classify(river, z, "black", land)
	ok(ri["k"] == "river" and not ri["closed"], "линия вдоль воды — река (%s)" % ri["k"])
	var rt: Dictionary = Sketch.tidy(river, ri, 1.0, z, land, 2)
	var d0: float = 0.0
	for v in river:
		d0 += absf(v.y - 1000.0)
	var d1: float = 0.0
	for v in rt["pts"]:
		d1 += absf(v.y - 1000.0)
	ok(d1 / rt["pts"].size() < d0 / river.size() - 50.0, "река прижалась к воде: %.0f → %.0f м" % [d0 / river.size(), d1 / rt["pts"].size()])
	ok(rt["m"].size() > 0 and rt["m"][0]["k"] == "wave", "у реки волны")
	var dry := PackedVector2Array([Vector2(6000, 8000), Vector2(9000, 8400), Vector2(12000, 8000)])
	ok(Sketch.classify(dry, z, "black", land)["k"] == "line", "линия в пустоши — просто линия")
	ok(Sketch.classify(dry, z, "blue", land)["k"] == "line", "синяя линия без воды — не река")
	# Позначка й поселення
	var dot := PackedVector2Array([Vector2(100, 100), Vector2(130, 100)])
	var di: Dictionary = Sketch.classify(dot, z, "black", land)
	ok(di["k"] == "mark", "короткий штрих — пометка")
	ok(Sketch.tidy(dot, di, 0.7, z, land, 3)["m"][0]["k"] == "cross", "умный герой ставит крестик")
	var town: PackedVector2Array = _circle(Vector2(20300, 19800), 900.0, 30, 150.0, 4)
	var ti: Dictionary = Sketch.classify(town, z, "black", land)
	ok(ti["k"] == "settlement", "обвёл город — поселение (%s)" % ti["k"])
	var tt: Dictionary = Sketch.tidy(town, ti, 0.8, z, land, 4)
	var named: bool = false
	for m in tt["m"]:
		named = named or (m["k"] == "label" and m["t"] == "Эшвик")
	ok(named, "Ум высокий: подписал Эшвик")
	var tl: Dictionary = Sketch.tidy(town, ti, 0.3, z, land, 4)
	var named_low: bool = false
	for m in tl["m"]:
		named_low = named_low or m["k"] == "label"
	ok(not named_low, "Ум низкий: без подписи")


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

	var tm: int = Time.get_ticks_msec()
	pm.open()
	await frames(3)
	print("  первое открытие: %d мс" % (Time.get_ticks_msec() - tm))
	ok(pm.is_open() and pm.area == a0 and pm.areas == [a0], "лист открыт на текущей области")
	var loops: Array = pm.area_loops(a0)
	var b: Rect2 = pm.area_bounds(a0)
	ok(not loops.is_empty() and loops[0].size() > 20, "край области обведён: %d линий, %d точек" % [loops.size(), loops[0].size() if not loops.is_empty() else 0])
	var inside_box: bool = true
	for p in loops[0]:
		inside_box = inside_box and b.grow(200.0).has_point(p)
	ok(inside_box and b.size.x < game.MAP_SIZE.x * 0.6, "лист — область, а не весь материк (%.0f×%.0f км)" % [b.size.x / 1000.0, b.size.y / 1000.0])
	ok(b.has_point(pm.view_c) and pm.view_z > 0.03, "лист показывает всю область")
	await shot("p01_area_sheet.png")

	# Ластик стирає ділянку
	pm.begin_stroke(Vector2(200, 300))
	for i in 30:
		pm.stroke_to(Vector2(210 + i * 10, 300))
	pm._finish_stroke()
	ok(pm.strokes.size() == 1 and pm.strokes[0].has("k"), "штрих распознан: %s" % pm.strokes[0].get("k", "?"))
	ok(pm._hint.text.begins_with(I18n.t("Похоже на: %s").get_slice("%", 0)), "подсказка: %s" % pm._hint.text)
	pm.erase_at(Vector2(350, 300))
	ok(pm.strokes.size() == 2, "ластик стёр участок посреди линии: %d куска" % pm.strokes.size())
	pm.erase_at(Vector2(350, 300))
	ok(pm.strokes.size() == 2, "второй раз там же — без изменений")
	# Обрис і доведення в сцені
	hero["actor"].set_stat("int", 9)
	hero["actor"].set_stat("per", 9)
	var c: Vector2 = Vector2(600, 330)
	pm.begin_stroke(c + Vector2(90, 0))
	for i in range(1, 41):
		pm.stroke_to(c + Vector2.from_angle(TAU * i / 40.0) * (90.0 + sin(i * 1.7) * 8.0))
	pm._finish_stroke()
	var last: Dictionary = pm.strokes[-1]
	ok(String(last.get("k", "")) != "line" and float(last.get("q", 0)) >= 0.99, "круг узнан как %s, Ум и Чутьё 9" % last.get("k", "?"))
	await shot("p02_tidy.png")

	# Сусідня область — новий аркуш з обрисом
	var other: Vector2 = Vector2.INF
	for k in 200:
		var p: Vector2 = hero["pos"] + Vector2.from_angle(k * 0.37) * (2000.0 + k * 60.0)
		var id: int = game.province_at(p)
		if id > 0 and id != a0 and game.biome_at(p) > 1:
			other = p
			break
	ok(other != Vector2.INF, "нашлась соседняя область")
	pm.close()
	var a1: int = game.province_at(other)
	hero["pos"] = other
	pm._area_t = 1.0
	pm._process(0.1)
	ok(pm.areas == [a0, a1], "зашёл в область %d — у неё появился лист" % a1)
	pm.open()
	await frames(3)
	ok(pm.area == a1 and pm.strokes.is_empty(), "на M — лист новой области, он чистый")
	ok(not pm.area_loops(a1).is_empty(), "у новой области свой обвод")
	ok(pm._area_pick.item_count == 2 and not pm._area_pick.disabled, "листы переключаются: %d" % pm._area_pick.item_count)
	await shot("p03_new_area.png")
	pm.show_area(a0)
	ok(pm.strokes.size() == 3, "вернулся к первому листу: рисунок на месте")

	# Збереження
	var d: Dictionary = cast.to_dict()
	var back: Dictionary = str_to_var(var_to_str(d))
	pm.close()
	pm.clear()
	ok(pm.areas.is_empty() and pm.strokes.is_empty(), "clear: чистый пергамент")
	cast.load_dict(back)
	ok(pm.areas == [a0, a1] and pm.sheets[str(a0)]["strokes"].size() == 3, "листы областей пережили сохранение")
	var marks_ok: bool = false
	for s in pm.sheets[str(a0)]["strokes"]:
		marks_ok = marks_ok or s.has("k")
	ok(marks_ok, "виды штрихов сохранились")
	# Старе збереження: один аркуш на весь світ
	var hp: Vector2 = Vector2(20812.0, 18000.0)
	pm.load_dict({"strokes": [{"c": "black", "w": 3.0, "pts": [hp.x, hp.y, hp.x + 500.0, hp.y]}, {"c": "red", "w": 3.0, "pts": [other.x, other.y, other.x + 400.0, other.y]}],
		"fragments": [], "view": [hp.x, hp.y, 0.05]})
	ok(pm.areas.size() == 2 and pm.sheets[str(a0)]["strokes"].size() == 1 and pm.sheets[str(a1)]["strokes"].size() == 1,
		"старое сохранение: штрихи разошлись по листам областей")

	print("PARCHMENT CHECKS: %d/%d" % [checks - fails, checks])
	quit(1 if fails > 0 else 0)

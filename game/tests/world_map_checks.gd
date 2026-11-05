extends SceneTree
## Рівень даних світу (world/world_map.gd) і слід героя по областях (world/region_tracker.gd), Huzzah 2026-11-05.
## xvfb-run godot --path game --rendering-driver opengl3 -s res://tests/world_map_checks.gd

const WorldMap := preload("res://world/world_map.gd")
const Fog := preload("res://world/fog.gd")
const WorldSave := preload("res://world_save.gd")

var fails: int = 0
var checks: int = 0


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


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game: Node2D = (load("res://game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await frames(8)
	var rt: Node = game.region_tracker
	ok(rt != null and game.fog.model.world_map == rt.map, "трекер створений, туман підключено до рівня даних")
	var guard: int = 0
	while not rt.map.is_ready and guard < 400:
		await process_frame
		guard += 1
	ok(rt.map.is_ready, "таблиця областей збудована покроково за %d кадрів" % guard)
	var m: RefCounted = rt.map
	ok(m.ids().size() == 31, "31 область у дескрипторах: %d" % m.ids().size())
	var total: int = 0
	for id in m.ids():
		total += m.cells_total(id)
	ok(total > 100000, "сума клітинок областей розумна: %d" % total)
	# Збіг із шаром гри: таблиця в клітинках 50 м, шар у пікселях ~27 м — розбіжність можлива лише на самій межі
	var mism: int = 0
	var n_pts: int = 3000
	for i in n_pts:
		var p := Vector2(randf() * game.MAP_SIZE.x, randf() * game.MAP_SIZE.y)
		if m.province_at(p) != game.province_at(p):
			mism += 1
	ok(mism < n_pts / 50, "province_at таблиці збігається з шаром гри (розбіжностей %d із %d, межа)" % [mism, n_pts])
	var a: int = m.ids()[0]
	var nb: Array = m.neighbors(a)
	ok(nb.size() >= 1 and m.neighbors(int(nb[0])).has(a), "сусідство симетричне: %d ↔ %d" % [a, nb[0] if nb.size() else -1])
	# Дослідженість тече з туману
	var fm = game.fog.model
	var home: Vector2 = m.bbox(a).get_center()
	var pid: int = m.province_at(home)
	var before: int = m.explored_cells(pid)
	fm.reveal(home, 300.0)
	fm.reveal(home, 2500.0)
	ok(m.explored_cells(pid) > before, "відкриття туману збільшує лічильник області")
	var sum_cells: int = 0
	for id in m.ids():
		sum_cells += m.explored_cells(id)
	ok(sum_cells == fm.opened - _sea_cells(m, fm), "лічильники = відкрите (без моря)")
	# Повний перерахунок збігається з інкрементальним
	var snap: Array = []
	for id in m.ids():
		snap.append(m.explored_cells(id))
	m.sync_explored(fm.cells)
	var same: bool = true
	for i in m.ids().size():
		if m.explored_cells(m.ids()[i]) != snap[i]:
			same = false
	ok(same, "sync_explored дає ті самі числа")
	ok(m.explored_fraction(pid) > 0.0 and m.explored_fraction(pid) <= 1.0, "частка досліджено в 0..1")
	# Перехід: підтвердження гасить тремтіння на межі
	var other: int = int(nb[0])
	var pa: Vector2 = _point_in(m, a)
	var pb: Vector2 = _point_in(m, other)
	var seen: Array = []
	rt.region_changed.connect(func(n: int, o: int) -> void: seen.append([n, o]))
	rt.current = 0
	rt.observe(pa)
	ok(rt.current == a and seen.size() == 1 and m.is_visited(a), "перша вибірка задає область і відвідану")
	rt.observe(pb)
	rt.observe(pa)
	rt.observe(pb)
	ok(rt.current == a and seen.size() == 1, "тремтіння на межі не змінює область")
	rt.observe(pb)
	rt.observe(pb)
	ok(rt.current == other and seen.size() == 2 and seen[1] == [other, a] and m.is_visited(other), "два підряд у новій області — перехід")
	rt.observe(Vector2(-10, -10))
	ok(rt.current == other, "поза картою область не міняється")
	# Збереження: visited туди-назад; старе без ключа — здогад із туману
	var d: Dictionary = WorldSave.build(game)
	ok(d.has("world_map") and d["world_map"]["visited"].has(a), "збереження містить world_map.visited")
	var visited_before: Array = m.visited.keys()
	m.visited.clear()
	rt.load_dict(d["world_map"])
	ok(m.visited.size() == visited_before.size(), "visited відновлено зі збереження")
	rt.load_dict(null)
	ok(m.is_visited(pid), "старе збереження: відвідана область виводиться з туману")
	# Огляд регіону вивантажується через час і відкривається знову
	var rv: CanvasLayer = game.region_view
	rv.open(a)
	await frames(2)
	ok(rv._root != null, "огляд відкрито")
	rv.close()
	rv._closed_t = rv.RELEASE_S
	await frames(2)
	ok(rv._root == null and rv.art.atlas == null, "закритий огляд вивантажив вузли й атлас")
	rv.open(a)
	await frames(2)
	ok(rv._root != null and rv.art.atlas != null and rv.is_open, "огляд відкривається знову після вивантаження")
	rv.close()
	print("world_map_checks: %d/%d" % [checks - fails, checks])
	quit(1 if fails > 0 else 0)


func _sea_cells(m: RefCounted, fm: RefCounted) -> int:
	var n: int = 0
	for i in fm.cells.size():
		if fm.cells[i] != 0 and m.table[i] == 0:
			n += 1
	return n


## Клітинка області, глибоко всередині (шукаємо від центра габаритів)
func _point_in(m: RefCounted, id: int) -> Vector2:
	var bb: Rect2 = m.bbox(id)
	for i in 4000:
		var p := Vector2(bb.position.x + randf() * bb.size.x, bb.position.y + randf() * bb.size.y)
		if m.province_at(p) == id:
			return p
	return bb.get_center()

extends RefCounted
## Рівень даних світу (Huzzah 2026-11-05, ТЗ «Динамічна ініціалізація та стрімінг регіонів»).
## Легка структура в пам'яті: для кожної області (31) — дескриптор {id, назва, габарити, площа в клітинках, сусіди},
## таблиця «клітинка сітки туману → область» і лічильники дослідженого. Жодних картинок, вузлів чи фізики:
## 2D-світ — одна неперервна карта, тому «візуальний» рівень (огляд регіону V, місто) уже створюється лише на вимогу.
## Сітка та сама, що в туману війни (world/fog.gd, клітинка 50 м): дослідження ведеться там, тут лише підрахунок.
## Будується покроково (build_step) за кілька кадрів, щоб запуск не гальмував. Зберігається лише visited
## (ключ "world_map" у world_save.gd); лічильники дослідженого виводяться з туману, тож старі збереження читаються.

signal built

const Fog := preload("res://world/fog.gd")

const ROWS_PER_STEP: int = 48
const VISITED_GUESS: float = 0.02    # старе збереження без ключа: область з відкритим понад 2% вважаємо відвіданою

var map_size: Vector2
var cols: int
var rows: int
var is_ready: bool = false
var table: PackedByteArray            # клітинка (y*cols+x) -> id області, 0 — море
var explored: PackedInt32Array        # id -> скільки клітинок області відкрито
var visited: Dictionary = {}          # id -> true: герой справді був в області
var guess_pending: bool = false       # збереження без ключа visited, а таблиця ще не готова
var _desc: Dictionary = {}            # id -> {id, cells, bbox, neighbors}
var _names: Dictionary = {}
var _img: Image
var _data: PackedByteArray
var _row: int = 0
var _w: int = 0
var _h: int = 0
var _bounds: Dictionary = {}          # id -> [x0, y0, x1, y1] у клітинках


func _init(size: Vector2 = Vector2(41625.0, 36000.0)) -> void:
	map_size = size
	cols = int(ceil(size.x / Fog.CELL_M))
	rows = int(ceil(size.y / Fog.CELL_M))
	table = PackedByteArray()
	table.resize(cols * rows)
	explored = PackedInt32Array()
	explored.resize(256)


## province_img — шар областей гри (game.province_img); names — game.map_names["provinces"]
func setup(province_img: Image, names: Dictionary) -> void:
	_img = province_img
	_names = names
	_w = province_img.get_width()
	_h = province_img.get_height()
	var fmt: int = province_img.get_format()
	_data = province_img.get_data() if fmt == Image.FORMAT_L8 or fmt == Image.FORMAT_R8 else PackedByteArray()
	_row = 0
	is_ready = false
	_desc.clear()
	_bounds.clear()


func _id_px(x: int, y: int) -> int:
	if _data.size() > 0:
		return _data[y * _w + x]
	return int(round(_img.get_pixel(x, y).r * 255.0))


## Один крок будови: ROWS_PER_STEP рядків сітки. true — таблиця готова.
func build_step(max_rows: int = ROWS_PER_STEP) -> bool:
	if is_ready:
		return true
	if _img == null:
		return false
	var end: int = mini(_row + max_rows, rows)
	for y in range(_row, end):
		var py: int = clampi(int((y + 0.5) * Fog.CELL_M / map_size.y * _h), 0, _h - 1)
		var base: int = y * cols
		for x in cols:
			var px: int = clampi(int((x + 0.5) * Fog.CELL_M / map_size.x * _w), 0, _w - 1)
			var id: int = _id_px(px, py)
			table[base + x] = id
			if id == 0:
				continue
			var b: Array = _bounds.get(id, [])
			if b.is_empty():
				_bounds[id] = [x, y, x, y, 1]
			else:
				if x < b[0]: b[0] = x
				if x > b[2]: b[2] = x
				if y > b[3]: b[3] = y
				b[4] += 1
			# Сусіди: ліва й верхня клітинка вже заповнені
			if x > 0:
				_touch(id, table[base + x - 1])
			if y > 0:
				_touch(id, table[base - cols + x])
	_row = end
	if _row < rows:
		return false
	_finish()
	return true


func _touch(a: int, b: int) -> void:
	if b == 0 or a == b:
		return
	_link(a, b)
	_link(b, a)


func _link(a: int, b: int) -> void:
	var d: Dictionary = _desc.get(a, {})
	if d.is_empty():
		d = {"id": a, "neighbors": {}}
		_desc[a] = d
	d["neighbors"][b] = int(d["neighbors"].get(b, 0)) + 1


func _finish() -> void:
	for id in _bounds:
		var b: Array = _bounds[id]
		var d: Dictionary = _desc.get(id, {})
		if d.is_empty():
			d = {"id": id, "neighbors": {}}
			_desc[id] = d
		d["cells"] = b[4]
		d["bbox"] = Rect2(Vector2(b[0], b[1]) * Fog.CELL_M, Vector2(b[2] - b[0] + 1, b[3] - b[1] + 1) * Fog.CELL_M)
	is_ready = true
	built.emit()


## Побудувати все одразу (тести, інструменти)
func build_all() -> void:
	while not build_step(rows):
		pass


# ---------------------------------------------------------------------
# Запити
# ---------------------------------------------------------------------
func ids() -> Array:
	var a: Array = _desc.keys()
	a.sort()
	return a


func descriptor(id: int) -> Dictionary:
	return _desc.get(id, {})


func region_name(id: int) -> String:
	return String(_names.get(str(id), {}).get("name", ""))


func bbox(id: int) -> Rect2:
	return _desc.get(id, {}).get("bbox", Rect2())


func cells_total(id: int) -> int:
	return int(_desc.get(id, {}).get("cells", 0))


## Сусіди області, найдовша спільна межа першою
func neighbors(id: int) -> Array:
	var n: Dictionary = _desc.get(id, {}).get("neighbors", {})
	var a: Array = n.keys()
	a.sort_custom(func(p: int, q: int) -> bool: return n[p] > n[q] or (n[p] == n[q] and p < q))
	return a


func cell_index(p: Vector2) -> int:
	if p.x < 0.0 or p.y < 0.0 or p.x >= map_size.x or p.y >= map_size.y:
		return -1
	return int(p.y / Fog.CELL_M) * cols + int(p.x / Fog.CELL_M)


## Область у точці (метри карти); 0 — море, поза картою або таблиця ще будується
func province_at(p: Vector2) -> int:
	var i: int = cell_index(p)
	return 0 if i < 0 or not is_ready else table[i]


# ---------------------------------------------------------------------
# Дослідження (рахується з туману; жодного власного стану, крім visited)
# ---------------------------------------------------------------------
## Туман відкрив клітинку idx (викликає Fog.reveal). До готовності таблиці не діє: sync_explored порахує все разом.
func cell_opened(idx: int) -> void:
	if is_ready:
		explored[table[idx]] += 1


## Перерахунок з масиву клітинок туману (після будови таблиці і після завантаження збереження)
func sync_explored(fog_cells: PackedByteArray) -> void:
	explored.fill(0)
	if not is_ready or fog_cells.size() != table.size():
		return
	for i in table.size():
		if fog_cells[i] != 0:
			explored[table[i]] += 1


func explored_cells(id: int) -> int:
	return explored[id] if id >= 0 and id < 256 else 0


func explored_fraction(id: int) -> float:
	var total: int = cells_total(id)
	return float(explored_cells(id)) / float(total) if total > 0 else 0.0


func mark_visited(id: int) -> void:
	if id > 0:
		visited[id] = true


func is_visited(id: int) -> bool:
	return visited.has(id)


func to_dict() -> Dictionary:
	var v: Array = visited.keys()
	v.sort()
	return {"visited": v}


## Немає ключа (старе збереження) — visited виводиться з туману за VISITED_GUESS
func load_dict(d: Variant) -> void:
	visited.clear()
	guess_pending = false
	if d is Dictionary and d.get("visited") is Array:
		for v in d["visited"]:
			mark_visited(int(v))
	elif is_ready:
		guess_visited()
	else:
		guess_pending = true


func guess_visited() -> void:
	guess_pending = false
	for id in ids():
		if explored_fraction(id) >= VISITED_GUESS:
			mark_visited(id)

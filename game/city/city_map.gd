extends RefCounted
## Карта города: сетка клеток из описания data/cities/<id>.json (дороги, площади, дома с дверью,
## частокол с воротами, деревья, лотки, колодец). Проходимость, скорость по клетке, поиск пути для НПС.
## Координаты мира города — метры от левого верхнего угла; клетка = cell_m метров.
## План "radial" (Huzzah 2026-10-23: города радиальные, как в средневековье): стена — кольцо шириной
## 2 клетки на радиусе wall_r вокруг center (клетки), дальше — земля за стеной (OUTSIDE, не пройти);
## площадь может быть кругом ("circle": [cx, cy, r]). Без "plan" — прежний частокол по краю карты.

enum T { GRASS, ROAD, SQUARE, PALISADE, WALL, FLOOR, DOOR, WELL, GATE, FIELD, TREE, STALL, RUBBLE, OUTSIDE }

const SOLID: Array = [T.PALISADE, T.WALL, T.WELL, T.TREE, T.STALL, T.OUTSIDE]
# Множитель шага по клетке [ВРЕМЕННО]
const SPEED: Dictionary = {
	T.GRASS: 0.9, T.ROAD: 1.0, T.SQUARE: 1.0, T.FLOOR: 1.0, T.DOOR: 1.0, T.GATE: 1.0,
	T.FIELD: 0.7, T.RUBBLE: 0.6,
}

var data: Dictionary = {}
var w: int = 0
var h: int = 0
var cell_m: float = 2.0
var tiles: PackedByteArray = PackedByteArray()
var bld: PackedInt32Array = PackedInt32Array()    # индекс дома для клеток внутри (пол, стены, дверь), иначе -1
var buildings: Array = []                           # описания домов из JSON + "floor": [Vector2i]
var gate_of: Dictionary = {}                        # Vector2i -> id ворот
var closed_gates: Dictionary = {}                   # id -> true, пока ворота заперты
var astar := AStarGrid2D.new()


func build(d: Dictionary) -> void:
	data = d
	w = int(d["size"][0])
	h = int(d["size"][1])
	cell_m = float(d.get("cell_m", 2.0))
	tiles.resize(w * h)
	tiles.fill(T.GRASS)
	bld.resize(w * h)
	bld.fill(-1)
	for f in d.get("fields", []):
		_fill(f["rect"], T.FIELD)
	for r in d.get("roads", []):
		_road(Vector2i(r["from"][0], r["from"][1]), Vector2i(r["to"][0], r["to"][1]), int(r.get("w", 1)))
	for s in d.get("squares", []):
		if s.has("circle"):
			_circle(s["circle"], T.SQUARE)
		else:
			_fill(s["rect"], T.SQUARE)
	if radial():
		var c := Vector2(d["center"][0], d["center"][1])
		var r: float = float(d["wall_r"])
		for y in h:
			for x in w:
				var k: float = (Vector2(x, y) + Vector2(0.5, 0.5)).distance_to(c)
				if k >= r + 1.0:
					_put(x, y, T.OUTSIDE)
				elif k >= r - 1.0 and String(d.get("wall", "palisade")) != "":
					_put(x, y, T.PALISADE)
	elif String(d.get("wall", "palisade")) != "":
		for x in w:
			_put(x, 0, T.PALISADE)
			_put(x, h - 1, T.PALISADE)
		for y in h:
			_put(0, y, T.PALISADE)
			_put(w - 1, y, T.PALISADE)
	for g in d.get("gates", []):
		for c in g["cells"]:
			var v := Vector2i(c[0], c[1])
			_put(v.x, v.y, T.GATE)
			gate_of[v] = g["id"]
	buildings.clear()
	for i in d.get("buildings", []).size():
		_building(d["buildings"][i], i)
	for p in d.get("props", []):
		# техно-артефакты (tech_*, Q31 B) — препятствие, как лоток
		var t: int = {"stall": T.STALL, "well": T.WELL, "tree": T.TREE}.get(p["kind"], T.STALL if String(p["kind"]).begins_with("tech_") else T.GRASS)
		# Деревья только на траве; лотки и колодцы — на траве и площади
		var allowed: Array = [T.GRASS] if t == T.TREE else [T.GRASS, T.SQUARE]
		for c in p["cells"]:
			if at(c[0], c[1]) in allowed:
				_put(c[0], c[1], t)
	_build_astar()


func radial() -> bool:
	return String(data.get("plan", "")) == "radial"


## Центр города в метрах (радиальный план — центр стены, иначе середина карты)
func center_m() -> Vector2:
	if radial():
		return Vector2(data["center"][0], data["center"][1]) * cell_m
	return size_m() * 0.5


func _circle(c: Array, t: int) -> void:
	var o := Vector2(c[0], c[1])
	for y in h:
		for x in w:
			if (Vector2(x, y) + Vector2(0.5, 0.5)).distance_to(o) <= float(c[2]):
				_put(x, y, t)


func _put(x: int, y: int, t: int) -> void:
	if x >= 0 and y >= 0 and x < w and y < h:
		tiles[y * w + x] = t


func at(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= w or y >= h:
		return T.OUTSIDE if radial() else T.PALISADE
	return tiles[y * w + x]


func _fill(r: Array, t: int) -> void:
	for y in range(r[1], r[1] + r[3]):
		for x in range(r[0], r[0] + r[2]):
			_put(x, y, t)


func _road(a: Vector2i, b: Vector2i, width: int) -> void:
	var n: int = maxi(absi(b.x - a.x), absi(b.y - a.y))
	for i in n + 1:
		var p: Vector2i = a + Vector2i((Vector2(b - a) * (float(i) / maxf(n, 1))).round())
		for dy in width:
			for dx in width:
				_put(p.x + dx, p.y + dy, T.ROAD)


# Дом: стены по краю, пол внутри, дверь в стене. Развалины: часть стен обвалилась, внутри завал, без крыши
func _building(b: Dictionary, idx: int) -> void:
	var r: Array = b["rect"]
	var ruins: bool = b.get("kind", "") == "ruins"
	var floor_cells: Array = []
	for y in range(r[1], r[1] + r[3]):
		for x in range(r[0], r[0] + r[2]):
			var edge: bool = x == r[0] or y == r[1] or x == r[0] + r[2] - 1 or y == r[1] + r[3] - 1
			if edge:
				# Обвал: каждая третья клетка стены развалин проходима (детерминированно от координат)
				_put(x, y, T.RUBBLE if ruins and (x * 7 + y * 13) % 3 == 0 else T.WALL)
			else:
				_put(x, y, T.RUBBLE if ruins else T.FLOOR)
				floor_cells.append(Vector2i(x, y))
			bld[y * w + x] = idx
	_put(b["door"][0], b["door"][1], T.DOOR)
	var e: Dictionary = b.duplicate()
	e["floor"] = floor_cells
	e["index"] = idx
	buildings.append(e)


func solid(x: int, y: int) -> bool:
	var t: int = at(x, y)
	if t == T.GATE:
		return closed_gates.has(gate_of.get(Vector2i(x, y), ""))
	return t in SOLID


func _build_astar() -> void:
	astar.region = Rect2i(0, 0, w, h)
	astar.cell_size = Vector2(cell_m, cell_m)
	astar.offset = Vector2(cell_m, cell_m) * 0.5
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for y in h:
		for x in w:
			var t: int = at(x, y)
			# НПС через ворота не ходят: за ними другой мир
			astar.set_point_solid(Vector2i(x, y), t in SOLID or t == T.GATE)
			astar.set_point_weight_scale(Vector2i(x, y), 1.0 / SPEED.get(t, 1.0))


# =====================================================================
# МЕТРЫ ↔ КЛЕТКИ
# =====================================================================
func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / cell_m), floori(p.y / cell_m))


func center_of(c: Vector2i) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * cell_m


func size_m() -> Vector2:
	return Vector2(w, h) * cell_m


func tile_at(p: Vector2) -> int:
	var c: Vector2i = cell_of(p)
	return at(c.x, c.y)


## Индекс дома, внутри которого точка (пол, дверь), иначе -1
func building_at(p: Vector2) -> int:
	var c: Vector2i = cell_of(p)
	if c.x < 0 or c.y < 0 or c.x >= w or c.y >= h:
		return -1
	var t: int = at(c.x, c.y)
	if t != T.FLOOR and t != T.DOOR and t != T.RUBBLE:
		return -1
	return bld[c.y * w + c.x]


func building_by_id(id: String) -> Dictionary:
	for b in buildings:
		if b["id"] == id:
			return b
	return {}


func speed_at(p: Vector2) -> float:
	return float(SPEED.get(tile_at(p), 1.0))


## Свободна ли точка для тела радиуса rad (проверка четырёх углов)
func is_free(p: Vector2, rad: float = 0.35) -> bool:
	for o in [Vector2(-rad, -rad), Vector2(rad, -rad), Vector2(-rad, rad), Vector2(rad, rad)]:
		var c: Vector2i = cell_of(p + o)
		if solid(c.x, c.y):
			return false
	return true


## Ворота под точкой, "" — нет
func gate_at(p: Vector2) -> String:
	return String(gate_of.get(cell_of(p), ""))


## Путь в метрах (центры клеток) от a до b; пусто — не дойти
func path(a: Vector2, b: Vector2) -> PackedVector2Array:
	var ca: Vector2i = cell_of(a).clamp(Vector2i.ZERO, Vector2i(w - 1, h - 1))
	var cb: Vector2i = cell_of(b).clamp(Vector2i.ZERO, Vector2i(w - 1, h - 1))
	if astar.is_point_solid(cb):
		return PackedVector2Array()
	return astar.get_point_path(ca, cb, true)

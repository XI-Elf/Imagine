extends RefCounted
## Сетка боя: клетки по 5 футов. Препятствия (дерево — укрытие ¾, камень — ½, скала — полное),
## трудная местность (движение ×2), возвышенности (подъём ×2, высота даёт преимущество стрелку),
## проклятые клетки. Путь — Дейкстра с диагоналями по 5 футов (как в 5e), углы не срезаются.

const Data := preload("res://battle/battle_data.gd")

var size: Vector2i = Vector2i(24, 16)
var cell_ft: int = 5
var obstacle: Dictionary = {}      # Vector2i -> "tree" | "rock" | "cliff"
var difficult: Dictionary = {}     # Vector2i -> true
var high: Dictionary = {}          # Vector2i -> высота в футах (10)
var hazard: Dictionary = {}        # Vector2i -> true (проклятье)
var rng := RandomNumberGenerator.new()


func setup(arena_key: String, seed_value: int, cfg: BattleConfig) -> void:
	size = cfg.grid_size
	cell_ft = cfg.cell_ft
	rng.seed = seed_value
	var a: Dictionary = cfg.arena.get(arena_key, cfg.arena.get("wasteland", {}))
	var keep: Array = _start_zones()
	# числа в arena — на поле 24×16; на другом поле — по площади
	var k: float = float(size.x * size.y) / 384.0
	# холмы — пятна 2×2..3×3
	for i in int(round(a.get("hills", 0) * k)):
		var c := Vector2i(rng.randi_range(4, size.x - 6), rng.randi_range(1, size.y - 4))
		var w: int = rng.randi_range(2, 3)
		var h: int = rng.randi_range(2, 3)
		for x in w:
			for y in h:
				var p: Vector2i = c + Vector2i(x, y)
				if in_bounds(p) and not _near(p, keep, 1):
					high[p] = 10
	for i in int(round(a.get("trees", 0) * k)):
		_place("tree", keep)
	for i in int(round(a.get("rocks", 0) * k)):
		_place("cliff" if rng.randf() < 0.2 else "rock", keep)
	for i in int(round(a.get("difficult", 0) * k)):
		var p := Vector2i(rng.randi_range(0, size.x - 1), rng.randi_range(0, size.y - 1))
		for d in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1)]:
			if in_bounds(p + d) and not obstacle.has(p + d):
				difficult[p + d] = true
	for i in int(round(a.get("glow", 0) * k)):
		var p := Vector2i(rng.randi_range(2, size.x - 3), rng.randi_range(0, size.y - 1))
		if not _near(p, keep, 2) and not obstacle.has(p):
			hazard[p] = true


func _start_zones() -> Array:
	return [Vector2i(3, size.y / 2), Vector2i(size.x - 4, size.y / 2)]


func _near(p: Vector2i, list: Array, r: int) -> bool:
	for k in list:
		if absi(p.x - k.x) <= r + 2 and absi(p.y - k.y) <= r + 2:
			return true
	return false


func _place(kind: String, keep: Array) -> void:
	for tries in 20:
		var p := Vector2i(rng.randi_range(1, size.x - 2), rng.randi_range(0, size.y - 1))
		if obstacle.has(p) or _near(p, keep, 0):
			continue
		obstacle[p] = kind
		return


func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < size.x and p.y < size.y


func walkable(p: Vector2i) -> bool:
	return in_bounds(p) and not obstacle.has(p)


func elevation(p: Vector2i) -> int:
	return int(high.get(p, 0))


## Расстояние по сетке 5e: max(dx, dy) клеток × 5 футов
func dist_ft(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y)) * cell_ft


## Цена шага в клетку b из a: 5 футов, трудная местность и подъём — вдвое
func step_cost(a: Vector2i, b: Vector2i) -> int:
	var c: int = cell_ft
	if difficult.has(b) or elevation(b) > elevation(a):
		c *= 2
	return c


## Все клетки, куда можно дойти за budget футов. blocked — занятые врагами (не пройти),
## occupied — занятые кем угодно (пройти можно мимо своих, но не остановиться)
## Ответ: {cell: {cost, prev}}; остановиться можно только на клетках без occupied
func reachable(from: Vector2i, budget: int, blocked: Dictionary, occupied: Dictionary) -> Dictionary:
	var best: Dictionary = {from: {"cost": 0, "prev": from}}
	var open: Array = [from]
	while not open.is_empty():
		var bi: int = 0
		for i in open.size():
			if int(best[open[i]]["cost"]) < int(best[open[bi]]["cost"]):
				bi = i
		var cur: Vector2i = open.pop_at(bi)
		var cc: int = int(best[cur]["cost"])
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				if dx == 0 and dy == 0:
					continue
				var n: Vector2i = cur + Vector2i(dx, dy)
				if not walkable(n) or blocked.has(n):
					continue
				# по диагонали нельзя срезать угол препятствия
				if dx != 0 and dy != 0 and (not walkable(cur + Vector2i(dx, 0)) or not walkable(cur + Vector2i(0, dy))):
					continue
				var nc: int = cc + step_cost(cur, n)
				if nc > budget:
					continue
				if not best.has(n) or nc < int(best[n]["cost"]):
					best[n] = {"cost": nc, "prev": cur}
					if not open.has(n):
						open.append(n)
	for k in best.keys():
		if occupied.has(k) and k != from:
			best[k]["pass_only"] = true
	return best


## Самый доступный и простой путь до клетки (просьба Huzzah): среди клеток reach, по порядку важности —
## 1) меньше футов; 2) меньше опасностей (светящиеся клетки; шаг из-под удара врага — атака по возможности;
## threat — клетки рядом с врагами, кто может ударить вслед); 3) проще: повороты + TURN_VS_LINE × уход от прямой
## начало–цель (без зигзагов и без широких крюков в обход препятствий).
func path_to(reach: Dictionary, to: Vector2i, threat: Dictionary = {}) -> Array:
	if not reach.has(to):
		return []
	var start: Vector2i = to
	for k in reach:
		if reach[k]["prev"] == k:
			start = k
			break
	if start == to:
		return [to]
	var a := Vector2(start)
	var line: Vector2 = Vector2(to) - a
	var ln: float = maxf(line.length(), 0.001)
	# состояние — клетка и направление прихода (повороты считаются по смене направления)
	var best: Dictionary = {}
	var prev: Dictionary = {}
	var s0 := Vector3i(start.x, start.y, -1)
	best[s0] = [0, 0, 0.0]
	var open: Array = [s0]
	var done: Dictionary = {}
	var goal = null
	while not open.is_empty():
		var bi: int = 0
		for i in range(1, open.size()):
			if _less(best[open[i]], best[open[bi]]):
				bi = i
		var st: Vector3i = open.pop_at(bi)
		if done.has(st):
			continue
		done[st] = true
		var cur := Vector2i(st.x, st.y)
		if cur == to:
			goal = st
			break
		var key: Array = best[st]
		for d in 8:
			var dir: Vector2i = DIRS[d]
			var n: Vector2i = cur + dir
			if not reach.has(n):
				continue
			if dir.x != 0 and dir.y != 0 and (not walkable(cur + Vector2i(dir.x, 0)) or not walkable(cur + Vector2i(0, dir.y))):
				continue
			var ft: int = int(key[0]) + step_cost(cur, n)
			if ft > int(reach[to]["cost"]):
				continue
			var danger: int = int(key[1]) + (1 if hazard.has(n) else 0) + (1 if threat.has(cur) and not threat.has(n) else 0)
			var simple: float = float(key[2]) + (1.0 if st.z >= 0 and st.z != d else 0.0) + TURN_VS_LINE * absf(line.cross(Vector2(n) - a)) / ln
			var ns := Vector3i(n.x, n.y, d)
			var nk: Array = [ft, danger, simple]
			if not best.has(ns) or _less(nk, best[ns]):
				best[ns] = nk
				prev[ns] = st
				open.append(ns)
	if goal == null:
		# запасной путь — по дереву reach
		var out: Array = [to]
		var c: Vector2i = to
		while reach[c]["prev"] != c:
			c = reach[c]["prev"]
			out.push_front(c)
		return out
	var path: Array = []
	var s = goal
	while s != null:
		path.push_front(Vector2i(s.x, s.y))
		s = prev.get(s, null)
	return path


const TURN_VS_LINE: float = 0.5
const DIRS: Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]


static func _less(x: Array, y: Array) -> bool:
	for i in x.size():
		if x[i] != y[i]:
			return x[i] < y[i]
	return false


## Укрытие цели от атакующего: "none" | "half" | "three_quarters" | "full".
## Препятствия вплотную к атакующему не считаются (выглядывает из-за них), существа между — половинное
func cover(from: Vector2i, to: Vector2i, creatures: Dictionary) -> String:
	var a := Vector2(from) + Vector2(0.5, 0.5)
	var b := Vector2(to) + Vector2(0.5, 0.5)
	var n: int = int(ceil(a.distance_to(b) * 4.0))
	var rank: int = 0
	var seen: Dictionary = {}
	for i in range(1, n):
		var p: Vector2 = a.lerp(b, float(i) / n)
		var c := Vector2i(floori(p.x), floori(p.y))
		if c == from or c == to or seen.has(c):
			continue
		seen[c] = true
		var adj_att: bool = maxi(absi(c.x - from.x), absi(c.y - from.y)) <= 1
		if obstacle.has(c) and not adj_att:
			match obstacle[c]:
				"cliff":
					rank = maxi(rank, 3)
				"tree":
					rank = maxi(rank, 2)
				_:
					rank = maxi(rank, 1)
		elif creatures.has(c):
			rank = maxi(rank, 1)
	# стрелок выше цели не видит её укрытие за камнем (кроме скал и деревьев)
	if elevation(from) > elevation(to) and rank == 1:
		rank = 0
	return ["none", "half", "three_quarters", "full"][rank]


func edge(p: Vector2i) -> bool:
	return p.x == 0 or p.y == 0 or p.x == size.x - 1 or p.y == size.y - 1


func to_dict() -> Dictionary:
	return {"size": size, "obstacle": obstacle, "difficult": difficult, "high": high, "hazard": hazard}

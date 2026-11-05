extends RefCounted
## Поселення на загальній карті, «вписане в місцевість» (Huzzah 2026-11-05: місто виглядало як наліплена
## текстура-медальйон). Замість круглої картинки поселення складається з шарів, що ростуть разом з ним:
##   пасовиська й ниви (нерівна пляма + смужки ріллі) → витоптана земля → стежки до околиць →
##   частокіл / кам'яна стіна з брамою → будинки (ті самі спрайти, що в світі) й сади.
## Усе задано в метрах від точки міста й виводиться в масштабі max(zoom, мінімум): здалеку це купка
## будинків у плямі витоптаної землі, зблизька — справжній розмір, а дерева довкола розступаються
## (near_dot у settlements.gd). Форма детермінована від id і рівня розвитку (0 стоянка … 5 велике місто),
## тож не мерехтить і не залежить від кадру.
const Art := preload("res://storybook/art.gd")

const RADIUS_M: Array = [8.0, 11.0, 15.0, 20.0, 26.0, 32.0]    # радіус забудови за рівнем
const HOUSES: Array = [3, 5, 9, 14, 20, 28]
const EARTH := Color(0.42, 0.31, 0.18)
const EARTH_DARK := Color(0.24, 0.17, 0.10)
const FIELD := Color(0.50, 0.42, 0.24)
const FIELD_GREEN := Color(0.30, 0.38, 0.17)
const KINDS: Array = ["house", "house", "house", "house", "inn", "smithy", "stall", "house", "temple", "well"]
const KIND_H: Dictionary = {"house": 5.2, "inn": 6.6, "smithy": 5.6, "stall": 3.6, "temple": 8.4, "well": 2.6, "hall": 9.0}
const BLOB_LAYERS: int = 5
const EDGE_STEPS: int = 40


static func radius_m(level: int) -> float:
	return RADIUS_M[clampi(level, 0, RADIUS_M.size() - 1)]


## Радіус, у якому ліс відступає від міста (метри; з нерівним краєм — див. clear_edge), за рівнем
static func clear_m(level: int) -> float:
	return radius_m(level) * 1.9


## Нерівний край галявини: множник радіуса від кута (той самий для всіх розрахунків)
static func clear_edge(seed_v: int, ang: float) -> float:
	var a: float = float(seed_v % 628) * 0.01
	return 1.0 + 0.16 * sin(3.0 * ang + a) + 0.09 * sin(5.0 * ang + a * 1.7)


## Нерівна пляма: список точок (від центру, метри), радіус R * (1 + хвилі + дрібний шум)
static func _blob(rng: RandomNumberGenerator, seed_v: int, r: float, rough: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in EDGE_STEPS:
		var ang: float = TAU * float(i) / float(EDGE_STEPS)
		var rr: float = r * clear_edge(seed_v, ang) * (1.0 + rng.randf_range(-rough, rough))
		pts.append(Vector2.from_angle(ang) * rr * Vector2(1.0, 0.86))
	return pts


## План поселення: усе в метрах від його точки. gate_dir — одиничний напрям до брами.
static func plan(id: String, level: int, gate_dir: Vector2) -> Dictionary:
	level = clampi(level, 0, RADIUS_M.size() - 1)
	var seed_v: int = absi(hash(id)) + level * 977
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var R: float = radius_m(level)
	var gd: Vector2 = gate_dir.normalized() if gate_dir.length() > 0.01 else Vector2(0, 1)
	var out: Dictionary = {"level": level, "R": R, "seed": seed_v, "gate": gd}
	out["pasture"] = _blob(rng, seed_v, R * 2.0, 0.05)
	out["trodden"] = _blob(rng, seed_v + 3, R * 1.3, 0.06)
	# Ріллі: смужки по краю пасовиська, з рівня 2
	var fields: Array = []
	if level >= 2:
		for i in 3 + level:
			var a: float = rng.randf() * TAU
			if Vector2.from_angle(a).dot(gd) > 0.75:
				continue    # проти брами лишається дорога
			var c: Vector2 = Vector2.from_angle(a) * R * rng.randf_range(1.45, 1.8) * Vector2(1.0, 0.86)
			fields.append({"c": c, "w": R * rng.randf_range(0.34, 0.5), "h": R * rng.randf_range(0.2, 0.3), "rot": a + PI * 0.5 + rng.randf_range(-0.3, 0.3),
				"green": rng.randf() < 0.5})
	out["fields"] = fields
	# Стежки: до брами — найдовша й найширша, решта розходяться, між ними кут не менший
	var roads: Array = []
	var n_roads: int = 2 + level / 2
	var angs: Array = [gd.angle()]
	for i in n_roads:
		var a2: float = gd.angle() + TAU * float(i + 1) / float(n_roads + 1) + rng.randf_range(-0.35, 0.35)
		angs.append(a2)
	for i in angs.size():
		var a3: float = angs[i]
		var length: float = R * (3.6 if i == 0 else rng.randf_range(2.4, 3.2))
		var pts := PackedVector2Array()
		var wob: float = rng.randf() * TAU
		var steps: int = 14
		for k in steps + 1:
			var t: float = float(k) / float(steps)
			var d: float = lerpf(R * 0.25, length, t)
			var side: float = sin(t * 5.0 + wob) * R * 0.07 * t
			var dir := Vector2.from_angle(a3)
			pts.append((dir * d + Vector2(-dir.y, dir.x) * side) * Vector2(1.0, 0.86))
		roads.append({"pts": pts, "w": R * (0.15 if i == 0 else 0.1)})
	out["roads"] = roads
	# Стіна: з рівня 1 частокіл, з рівня 3 — камінь із вежами
	out["wall"] = 0 if level < 1 else (1 if level < 3 else 2)
	# Будівлі: зал у центрі, решта — спіраллю від центру (золотий кут), з відступом від доріг до брами
	var bld: Array = [{"key": "hall", "p": Vector2.ZERO, "h": KIND_H["hall"] * (0.7 + 0.08 * float(level))}]
	if level == 0:
		bld[0]["key"] = "house"
		bld[0]["h"] = KIND_H["house"]
	var n_b: int = HOUSES[level]
	var golden: float = 2.39996
	for i in n_b:
		var rr: float = R * 0.82 * sqrt((float(i) + 0.8) / float(n_b + 1)) + R * 0.12
		var a4: float = float(i) * golden + rng.randf_range(-0.2, 0.2)
		var v: Vector2 = Vector2.from_angle(a4)
		if v.dot(gd) > 0.93 and rr > R * 0.3 and rr < R * 1.0:
			a4 += 0.35    # не ставимо на головну дорогу
			v = Vector2.from_angle(a4)
		var kind: String = KINDS[rng.randi() % KINDS.size()]
		if kind == "temple" and (level < 3 or bld.size() > 3 and bld.any(func(b): return b["key"] == "temple")):
			kind = "house"
		if kind == "inn" and level < 2:
			kind = "house"
		bld.append({"key": kind, "p": v * rr * Vector2(1.0, 0.86), "h": KIND_H[kind] * rng.randf_range(0.85, 1.12)})
	# Сади й дерева біля краю
	for i in 2 + level * 2:
		var a5: float = rng.randf() * TAU
		if Vector2.from_angle(a5).dot(gd) > 0.85:
			continue
		bld.append({"key": "tree_oak" if rng.randf() < 0.65 else "tree_crooked", "p": Vector2.from_angle(a5) * R * rng.randf_range(1.12, 1.5) * Vector2(1.0, 0.86),
			"h": rng.randf_range(6.0, 9.0)})
	bld.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["p"].y < b["p"].y)
	out["buildings"] = bld
	return out


## Масштаб виводу: не менший за zoom (тоді розмір справжній), а здалеку — щоб поселення займало min_px
static func scale_for(level: int, zoom: float, min_px: float) -> float:
	return maxf(zoom, min_px / (radius_m(level) * 1.3))


static func _fan(node: Node2D, pts: PackedVector2Array, c0: Vector2, k: float, scale_in: float, col: Color) -> void:
	var sp := PackedVector2Array()
	for q in pts:
		sp.append(c0 + q * scale_in * k)
	node.draw_colored_polygon(sp, col)


## Малювання. alpha — загальна прозорість (для виділення/зникання), hl — золота пунктирна обводка
static func paint(node: Node2D, p: Dictionary, c0: Vector2, k: float, hl: bool) -> void:
	var R: float = p["R"]
	# 1. Пасовиська: плавне розчинення в землі (багато слабких шарів)
	for i in BLOB_LAYERS:
		_fan(node, p["pasture"], c0, k, 1.0 - 0.16 * float(i), Color(FIELD.r, FIELD.g, FIELD.b, 0.045))
	for f in p["fields"]:
		var col: Color = FIELD_GREEN if f["green"] else FIELD
		var rot: float = f["rot"]
		var ex := Vector2.from_angle(rot) * float(f["w"]) * k
		var ey := Vector2.from_angle(rot + PI * 0.5) * float(f["h"]) * k
		var c: Vector2 = c0 + Vector2(f["c"]) * k
		node.draw_colored_polygon(PackedVector2Array([c - ex - ey, c + ex - ey, c + ex + ey, c - ex + ey]), Color(col.r, col.g, col.b, 0.32))
		for s in 4:   # борозни
			var t: float = (float(s) + 0.5) / 4.0 * 2.0 - 1.0
			node.draw_line(c - ex + ey * t, c + ex + ey * t, Color(EARTH_DARK.r, EARTH_DARK.g, EARTH_DARK.b, 0.28), maxf(1.0, k * 0.5), true)
	# 2. Витоптана земля: щільніша в середині, край розмитий
	for i in BLOB_LAYERS:
		_fan(node, p["trodden"], c0, k, 1.0 - 0.17 * float(i), Color(EARTH.r, EARTH.g, EARTH.b, 0.17))
	# 3. Стежки, що розтікаються від поселення й тануть у місцевості
	for rd in p["roads"]:
		var pts: PackedVector2Array = rd["pts"]
		var w: float = float(rd["w"]) * k
		for i in pts.size() - 1:
			var fade: float = 1.0 - float(i) / float(pts.size())
			var a: Vector2 = c0 + pts[i] * k
			var b: Vector2 = c0 + pts[i + 1] * k
			node.draw_line(a, b, Color(EARTH.r, EARTH.g, EARTH.b, 0.50 * fade + 0.06), maxf(1.5, w * (0.6 + 0.6 * fade)), true)
			node.draw_line(a, b, Color(EARTH_DARK.r, EARTH_DARK.g, EARTH_DARK.b, 0.22 * fade), maxf(0.8, w * 0.18), true)
	# 4. Стіна з проламом для брами
	var wall: int = p["wall"]
	if wall > 0:
		var gd: Vector2 = p["gate"]
		var wr: float = R * 1.02
		var seg: int = 28
		var col: Color = Color(0.30, 0.21, 0.12) if wall == 1 else Color(0.55, 0.52, 0.46)
		var wd: float = maxf(1.4, k * (1.1 if wall == 1 else 1.9))
		var prev: Vector2 = Vector2.INF
		for i in seg + 1:
			var ang: float = TAU * float(i) / float(seg)
			var v: Vector2 = Vector2.from_angle(ang)
			var q: Vector2 = c0 + v * wr * Vector2(1.0, 0.86) * k
			var in_gate: bool = v.dot(gd) > 0.965
			if prev != Vector2.INF and not in_gate:
				node.draw_line(prev + Vector2(0, 1.2), q + Vector2(0, 1.2), Color(0, 0, 0, 0.25), wd + 1.0, true)
				node.draw_line(prev, q, col, wd, true)
				if wall == 1 and i % 2 == 0:   # загострені палі
					node.draw_line(q, q + Vector2(0, -wd * 1.4), col.lightened(0.12), maxf(1.0, wd * 0.55), true)
			if wall == 2 and i % 4 == 0 and not in_gate:
				node.draw_rect(Rect2(q - Vector2(wd, wd * 1.6), Vector2(wd * 2.0, wd * 2.2)), col.lightened(0.1))
				node.draw_rect(Rect2(q - Vector2(wd, wd * 1.6), Vector2(wd * 2.0, wd * 2.2)), Color(0, 0, 0, 0.45), false, 1.0)
			prev = q
		for sgn in [-1.0, 1.0]:   # стовпи брами
			var gp: Vector2 = c0 + (gd.rotated(0.2 * sgn)) * wr * Vector2(1.0, 0.86) * k
			node.draw_rect(Rect2(gp - Vector2(wd * 0.8, wd * 1.8), Vector2(wd * 1.6, wd * 2.4)), Color(0.22, 0.15, 0.09))
	# 5. Будинки, дерева — за y
	for b in p["buildings"]:
		Art.sprite(node, String(b["key"]), c0 + Vector2(b["p"]) * k, float(b["h"]) * k)
	# Виділення: золотий пунктир по краю витоптаної землі
	if hl:
		var arcs: int = 24
		for i in arcs:
			var a0: float = TAU * float(i) / float(arcs)
			node.draw_arc(c0, R * 1.35 * k, a0, a0 + TAU / float(arcs) * 0.55, 4, Color(1.0, 0.85, 0.4, 0.85), 2.0, true)

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
## Намальовані текстури (art/textures_ai): ключ плану -> файл. Будинки за рівнем розвитку: house_s0..s4.
const AI_DIR := "res://art/textures_ai/"
const AI_KEY: Dictionary = {
	"hall": "bld_hall_s2", "inn": "bld_inn_s2", "smithy": "bld_smithy_s2", "temple": "bld_temple_s2", "stall": "out_market_stall",
	"well": "out_well", "hay": "out_haystack", "cart": "out_cart", "wood": "out_woodpile", "crates": "out_crates_barrels",
	"hut": "out_hut_a", "shed": "out_hut_b", "fence": "out_fence_seg", "garden": "out_garden_beds", "firewood": "out_firewood",
}
const PROP_KINDS: Array = ["hay", "cart", "wood", "crates", "hut", "shed", "fence", "garden", "firewood"]
const PROP_H: Dictionary = {"hay": 3.6, "cart": 3.2, "wood": 2.4, "crates": 2.6, "hut": 4.6, "shed": 4.0, "fence": 2.0, "garden": 3.4, "firewood": 2.2}
const SCUFFS: Array = ["edge_scuff_01", "edge_scuff_02", "edge_scuff_03", "edge_scuff_04", "edge_scuff_05", "edge_scuff_06"]
const LITTER: Array = ["edge_straw_01", "edge_straw_02", "edge_pebbles_01", "edge_puddle_01", "edge_puddle_02"]
const BLOB_LAYERS: int = 5
static var _tex_cache: Dictionary = {}


## Текстура з art/textures_ai за іменем файлу (без .png); null — файлу немає, діє стара заглушка
static func ai_tex(name: String) -> Texture2D:
	if name == "":
		return null
	if not _tex_cache.has(name):
		var p: String = AI_DIR + name + ".png"
		_tex_cache[name] = load(p) if ResourceLoader.exists(p) else null
	return _tex_cache[name] as Texture2D


## Файл для ключа будівлі плану: будинок — за рівнем розвитку, решта — за таблицею
static func ai_name(key: String, level: int) -> String:
	if key == "house":
		return "bld_house_s%d" % clampi(level, 0, 4)
	return String(AI_KEY.get(key, ""))


## Малювання намальованої картинки: опора — низ по центру (поле 4 %), висота h. Своєї тіні в картинці немає — м'яка ковзна тінь тут
static func draw_ai(node: Node2D, tex: Texture2D, foot: Vector2, h: float, tint: Color = Color.WHITE) -> void:
	var size := Vector2(tex.get_size()) * (h / float(tex.get_height()))
	node.draw_set_transform(foot + Vector2(0, 1.5), 0.0, Vector2(1, 0.28))
	node.draw_circle(Vector2.ZERO, size.x * 0.34, Color(0.10, 0.08, 0.06, 0.22 * tint.a))
	node.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	node.draw_texture_rect(tex, Rect2(foot + Vector2(-size.x * 0.5, -size.y * 0.96), size), false, tint)


## Плоска декаль (вид згори) з центром у c, шириною w, поворотом rot
static func draw_decal(node: Node2D, tex: Texture2D, c: Vector2, w: float, rot: float, tint: Color) -> void:
	var size := Vector2(tex.get_size()) * (w / float(tex.get_width()))
	node.draw_set_transform(c, rot, Vector2.ONE)
	node.draw_texture_rect(tex, Rect2(-size * 0.5, size), false, tint)
	node.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
const EDGE_STEPS: int = 40


static func radius_m(level: int) -> float:
	return RADIUS_M[clampi(level, 0, RADIUS_M.size() - 1)]


## Радіус, у якому ліс відступає від міста (метри; з нерівним краєм — див. clear_edge), за рівнем
static func clear_m(level: int) -> float:
	return radius_m(level) * 1.9


## Нерівний край галявини: множник радіуса від кута (той самий для всіх розрахунків)
static func clear_edge(seed_v: int, ang: float) -> float:
	var a: float = float(seed_v % 628) * 0.01
	var b: float = float((seed_v / 7) % 628) * 0.01
	var c: float = float((seed_v / 31) % 628) * 0.01
	# Низькі гармоніки дають витягнуту, «з затоками» форму, а не коло
	return clampf(1.0 + 0.24 * sin(2.0 * ang + a) + 0.17 * sin(3.0 * ang + b) + 0.11 * sin(5.0 * ang + c) + 0.07 * sin(8.0 * ang + a * 2.0), 0.55, 1.65)


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
	var gaps: Array = []
	for i in 32:
		gaps.append(rng.randf() < (0.3 if level < 3 else 0.12))   # прогалини: частокіл не замкнений
	out["wall_gaps"] = gaps
	# Будівлі: зал у центрі, решта — спіраллю від центру (золотий кут), з відступом від доріг до брами
	var bld: Array = [{"key": "hall", "p": Vector2.ZERO, "h": KIND_H["hall"] * (0.7 + 0.08 * float(level))}]
	if level == 0:
		bld[0]["key"] = "house"
		bld[0]["h"] = KIND_H["house"]
	var n_b: int = HOUSES[level]
	var placed: Array = [Vector2.ZERO]
	var tries: int = 0
	while bld.size() - 1 < n_b and tries < 400:
		tries += 1
		var v: Vector2
		if rng.randf() < 0.55 and not roads.is_empty():
			# вздовж стежки: дім збоку від дороги (стрічкова забудова)
			var rd: Dictionary = roads[rng.randi() % mini(roads.size(), 3)]
			var pts: PackedVector2Array = rd["pts"]
			var idx: int = rng.randi_range(1, mini(pts.size() - 1, 7))
			var tang: Vector2 = (pts[idx] - pts[idx - 1]).normalized()
			var side: float = (1.0 if rng.randf() < 0.5 else -1.0) * R * rng.randf_range(0.16, 0.34)
			v = pts[idx] + Vector2(-tang.y, tang.x) * side
		else:
			var ang: float = rng.randf() * TAU
			v = Vector2.from_angle(ang) * R * sqrt(rng.randf()) * 0.95 * clear_edge(seed_v, ang) * Vector2(1.0, 0.86)
		var ok_pos: bool = true
		for q in placed:
			if v.distance_to(q) < R * 0.2:
				ok_pos = false
				break
		if not ok_pos:
			continue
		placed.append(v)
		var kind: String = KINDS[rng.randi() % KINDS.size()]
		if kind == "temple" and (level < 3 or bld.any(func(b): return b["key"] == "temple")):
			kind = "house"
		if kind == "inn" and level < 2:
			kind = "house"
		bld.append({"key": kind, "p": v, "h": KIND_H[kind] * rng.randf_range(0.85, 1.12)})
	# Сади й дерева біля краю
	for i in 2 + level * 2:
		var a5: float = rng.randf() * TAU
		if Vector2.from_angle(a5).dot(gd) > 0.85:
			continue
		bld.append({"key": "tree_oak" if rng.randf() < 0.65 else "tree_crooked", "p": Vector2.from_angle(a5) * R * rng.randf_range(1.0, 1.4) * clear_edge(seed_v, a5) * Vector2(1.0, 0.86),
			"h": rng.randf_range(6.0, 9.0)})
	# Господарські дрібниці (копиця, віз, дрова…): окремий rng — основна послідовність плану не змінюється
	var rp := RandomNumberGenerator.new()
	rp.seed = seed_v + 4417
	for i in 1 + level * 2:
		var a6: float = rp.randf() * TAU
		if Vector2.from_angle(a6).dot(gd) > 0.8:
			continue
		var pk: String = PROP_KINDS[rp.randi() % PROP_KINDS.size()]
		if pk == "garden" and level < 1:
			pk = "hay"
		var pv: Vector2 = Vector2.from_angle(a6) * R * rp.randf_range(0.95, 1.5) * clear_edge(seed_v, a6) * Vector2(1.0, 0.86)
		bld.append({"key": pk, "p": pv, "h": float(PROP_H[pk]) * rp.randf_range(0.9, 1.15), "prop": true})
	var litter: Array = []
	for i in 3 + level * 2:   # солома, камінці, калюжі: дрібні декалі на витоптаній землі й біля стежок
		var a7: float = rp.randf() * TAU
		var lk: String = LITTER[rp.randi() % LITTER.size()]
		litter.append({"tex": lk, "p": Vector2.from_angle(a7) * R * rp.randf_range(0.2, 1.5) * clear_edge(seed_v, a7) * Vector2(1.0, 0.86),
			"w": R * rp.randf_range(0.18, 0.34), "rot": rp.randf() * TAU})
	out["litter"] = litter
	out["scuff"] = [rp.randi() % SCUFFS.size(), rp.randi() % SCUFFS.size(), rp.randf() * TAU, rp.randf() * TAU]
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
	# 0. Рвані декалі витоптаної трави (намальовані): ховають шов і дають справжню фактуру краю
	var sc: Array = p.get("scuff", [])
	if sc.size() == 4:
		var t1: Texture2D = ai_tex(SCUFFS[int(sc[0])])
		var t2: Texture2D = ai_tex(SCUFFS[int(sc[1])])
		if t1 != null:
			draw_decal(node, t1, c0, R * 4.4 * k, float(sc[2]) * 0.15, Color(0.92, 0.88, 0.80, 0.78))
		if t2 != null:
			draw_decal(node, t2, c0, R * 2.9 * k, float(sc[3]) * 0.15, Color(0.95, 0.90, 0.82, 0.70))
	# 1. Пасовиська: плавне розчинення в землі (багато слабких шарів)
	for i in BLOB_LAYERS:
		_fan(node, p["pasture"], c0, k, 1.0 - 0.16 * float(i), Color(FIELD.r, FIELD.g, FIELD.b, 0.045))
	for f in p["fields"]:
		var col: Color = FIELD_GREEN if f["green"] else FIELD
		var rot: float = f["rot"]
		var ex := Vector2.from_angle(rot) * float(f["w"]) * k
		var ey := Vector2.from_angle(rot + PI * 0.5) * float(f["h"]) * k
		var c: Vector2 = c0 + Vector2(f["c"]) * k
		var ft: Texture2D = ai_tex("out_field_strip_b" if f["green"] else "out_field_strip_a")
		if ft != null:
			draw_decal(node, ft, c, float(f["w"]) * 1.5 * k, rot * 0.35, Color(1, 0.97, 0.92, 0.95))
			continue
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
	# 3б. Дрібні декалі (солома, камінці, калюжі)
	for lt in p.get("litter", []):
		var lx: Texture2D = ai_tex(String(lt["tex"]))
		if lx != null:
			draw_decal(node, lx, c0 + Vector2(lt["p"]) * k, float(lt["w"]) * k, float(lt["rot"]) * 0.2, Color(0.95, 0.92, 0.86, 0.92))
	# 4. Стіна з проламом для брами
	var wall: int = p["wall"]
	if wall > 0:
		var gd: Vector2 = p["gate"]
		var seg: int = 32
		var gaps: Array = p["wall_gaps"]
		var col: Color = Color(0.30, 0.21, 0.12) if wall == 1 else Color(0.55, 0.52, 0.46)
		var wd: float = maxf(1.4, k * (1.1 if wall == 1 else 1.9))
		var sd: int = int(p["seed"])
		var prev: Vector2 = Vector2.INF
		for i in seg + 1:
			var ang: float = TAU * float(i % seg) / float(seg)
			var v: Vector2 = Vector2.from_angle(ang)
			var q: Vector2 = c0 + v * R * 0.9 * clear_edge(sd, ang) * Vector2(1.0, 0.86) * k
			var in_gate: bool = v.dot(gd) > 0.95
			if prev != Vector2.INF and not in_gate and not bool(gaps[(i - 1) % seg]):
				node.draw_line(prev + Vector2(0, 1.2), q + Vector2(0, 1.2), Color(0, 0, 0, 0.25), wd + 1.0, true)
				node.draw_line(prev, q, col, wd, true)
				if wall == 1 and i % 2 == 0:   # загострені палі
					node.draw_line(q, q + Vector2(0, -wd * 1.4), col.lightened(0.12), maxf(1.0, wd * 0.55), true)
			if wall == 2 and i % 5 == 0 and not in_gate and not bool(gaps[i % seg]):
				node.draw_rect(Rect2(q - Vector2(wd, wd * 1.6), Vector2(wd * 2.0, wd * 2.2)), col.lightened(0.1))
				node.draw_rect(Rect2(q - Vector2(wd, wd * 1.6), Vector2(wd * 2.0, wd * 2.2)), Color(0, 0, 0, 0.45), false, 1.0)
			prev = q
		for sgn in [-1.0, 1.0]:   # стовпи брами
			var ga: float = gd.angle() + 0.17 * sgn
			var gp: Vector2 = c0 + Vector2.from_angle(ga) * R * 0.9 * clear_edge(sd, ga) * Vector2(1.0, 0.86) * k
			node.draw_rect(Rect2(gp - Vector2(wd * 0.8, wd * 1.8), Vector2(wd * 1.6, wd * 2.4)), Color(0.22, 0.15, 0.09))
	# 5. Будинки, дерева — за y
	for b in p["buildings"]:
		var bt: Texture2D = ai_tex(ai_name(String(b["key"]), int(p["level"])))
		if bt != null:
			var hk: float = float(b["h"]) * k * (2.0 if not bool(b.get("prop", false)) else 1.6)
			draw_ai(node, bt, c0 + Vector2(b["p"]) * k, hk, Color(0.96, 0.93, 0.88))
		elif not bool(b.get("prop", false)):
			Art.sprite(node, String(b["key"]), c0 + Vector2(b["p"]) * k, float(b["h"]) * k)
	# Виділення: золотий пунктир по краю витоптаної землі
	if hl:
		var sd2: int = int(p["seed"])
		var prevh: Vector2 = Vector2.INF
		for i in 49:
			var ang2: float = TAU * float(i % 48) / 48.0
			var qh: Vector2 = c0 + Vector2.from_angle(ang2) * R * 1.2 * clear_edge(sd2, ang2) * Vector2(1.0, 0.86) * k
			if prevh != Vector2.INF and i % 2 == 0:
				node.draw_line(prevh, qh, Color(1.0, 0.85, 0.4, 0.85), 2.0, true)
			prevh = qh

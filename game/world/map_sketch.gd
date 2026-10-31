extends RefCounted
## Розпізнавання намальованого на пергаменті (Huzzah 2026-10-30): що це — річка, дорога, ліс, озеро, поселення, позначка,
## і легке «доведення» штриха до вигляду карти. Скільки підправити, вирішують Ум і Чутьё героя (характеристики «int» і «per»;
## окремої «мудрості» в грі немає, її роль грає Чутьё): за низьких — майже нічого, за високих — згладжено, притягнуто
## до справжньої місцевості поруч і домальовано знаки (деревця, хвилі, вершини, хатки, назва поселення).
## Зсув точок обмежено кількома пікселями аркуша, щоб малюнок гравця лишався впізнаваним.
## terrain — вузол гри: biome_at(p), water_at(p), необов'язково settlements.list і trails.trodden(p). Числа [ВРЕМЕННО].

const SPACING_PX: float = 6.0       # крок точок після доведення, пікселів аркуша
const MAX_SHIFT_PX: float = 18.0    # найбільший зсув точки за найвищих Ум і Чутья
const MARK_PX: float = 18.0         # коротший за це штрих — позначка
const CLOSE_PX: float = 34.0        # кінці ближче за це — замкнена фігура
const B_WATER := 1
const B_FOREST := 3
const B_SWAMP := 5
const B_MOUNTAINS := 6
const B_CURSED_FOREST := 7
const B_CURSED_SWAMP := 9


## Наскільки герой підправляє малюнок: 0 (Ум і Чутьё по 1) … 1 (по 9 і вище)
static func quality(actor: Object) -> float:
	if actor == null or not actor.has_method("stat"):
		return 0.0
	return clampf((actor.stat("int") + actor.stat("per") - 2.0) / 16.0, 0.0, 1.0)


static func kind_name(k: String) -> String:
	match k:
		"mark": return I18n.t("пометка")
		"road": return I18n.t("дорога")
		"river": return I18n.t("река")
		"forest": return I18n.t("лес")
		"lake": return I18n.t("озеро")
		"mountains": return I18n.t("горы")
		"swamp": return I18n.t("болото")
		"settlement": return I18n.t("поселение")
		"area": return I18n.t("место")
	return I18n.t("линия")


# =====================================================================
# РОЗПІЗНАВАННЯ
# =====================================================================
## Що намальовано. pts — точки штриха в метрах, z — пікселів аркуша на метр під час малювання.
## Повертає {k: вид, closed: bool, s: поселення або {}}
static func classify(pts: PackedVector2Array, z: float, color: String, terrain: Object) -> Dictionary:
	var out: Dictionary = {"k": "line", "closed": false, "s": {}}
	var length: float = _length(pts)
	if pts.size() < 2 or length * z < MARK_PX:
		out["k"] = "mark"
		return out
	var box: Rect2 = _bounds(pts)
	var gap_px: float = pts[0].distance_to(pts[-1]) * z
	var area: float = absf(_signed_area(pts))
	var closed: bool = (gap_px < CLOSE_PX or gap_px < length * z * 0.15) and length * z > 60.0 \
		and area > 0.04 * box.size.length_squared()
	out["closed"] = closed
	if terrain == null:
		return out
	if closed:
		var st: Dictionary = _settlement_inside(pts, terrain)
		if not st.is_empty():
			out["k"] = "settlement"
			out["s"] = st
			return out
		var votes: Dictionary = {}
		var inside: Array = _inside_samples(pts, box, 7)
		for p in inside:
			var b: int = _biome(terrain, p)
			votes[b] = int(votes.get(b, 0)) + 1
		var n: float = maxf(1.0, inside.size())
		if float(votes.get(B_WATER, 0)) / n >= 0.4:
			out["k"] = "lake"
		elif float(int(votes.get(B_FOREST, 0)) + int(votes.get(B_CURSED_FOREST, 0))) / n >= 0.4:
			out["k"] = "forest"
		elif float(votes.get(B_MOUNTAINS, 0)) / n >= 0.4:
			out["k"] = "mountains"
		elif float(int(votes.get(B_SWAMP, 0)) + int(votes.get(B_CURSED_SWAMP, 0))) / n >= 0.4:
			out["k"] = "swamp"
		else:
			out["k"] = "area"
		return out
	# Відкрита лінія: уздовж води — річка, уздовж стежок або між поселеннями — дорога
	var near_m: float = maxf(60.0, 8.0 / z)
	var wet: int = 0
	var trod: int = 0
	var along: PackedVector2Array = resample(pts, length / 20.0)
	for p in along:
		if _near(terrain, p, near_m, "water"):
			wet += 1
		if _near(terrain, p, near_m, "trail"):
			trod += 1
	var m: float = maxf(1.0, along.size())
	var ends_in_towns: bool = not _settlement_near(pts[0], terrain, 2.0 * near_m).is_empty() \
		and not _settlement_near(pts[-1], terrain, 2.0 * near_m).is_empty()
	if wet / m >= 0.5 or (color == "blue" and wet / m >= 0.2):
		out["k"] = "river"
	elif trod / m >= 0.4 or ends_in_towns:
		out["k"] = "road"
	return out


# =====================================================================
# ДОВЕДЕННЯ
# =====================================================================
## Підправити штрих за видом і якістю q (0..1). Повертає {pts: PackedVector2Array, m: [знаки]}
static func tidy(pts: PackedVector2Array, info: Dictionary, q: float, z: float, terrain: Object, seed: int) -> Dictionary:
	var kind: String = String(info.get("k", "line"))
	var closed: bool = bool(info.get("closed", false))
	var marks: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var mark_m: float = 10.0 / z
	if kind == "mark" or q <= 0.05:
		if kind == "mark" and q >= 0.5 and pts.size() > 0:
			marks.append({"k": "cross", "x": pts[0].x, "y": pts[0].y, "s": mark_m})
		return {"pts": pts, "m": marks}
	var shift_m: float = MAX_SHIFT_PX * q / z
	# 1) рівний крок і згладжування: що вищий Ум, то менше тремтіння руки
	var p: PackedVector2Array = pts.duplicate()
	if closed:
		p.append(p[0])
	p = resample(p, SPACING_PX / z)
	p = smooth(p, int(round(1.0 + q * 3.0)), q, closed)
	# 2) притягнути до справжньої місцевості (Чутьё: герой пам'ятає, де що бачив)
	if terrain != null and q >= 0.15:
		match kind:
			"river":
				p = _snap_to(p, terrain, "water", shift_m, q * 0.85, closed)
			"road":
				p = _snap_to(p, terrain, "trail", shift_m, q * 0.7, closed)
				p = _snap_ends_to_towns(p, terrain, shift_m * 2.0, q)
			"lake", "forest", "mountains", "swamp":
				p = _snap_edge(p, terrain, kind, shift_m, q * 0.8)
			"settlement":
				p = _round_settlement(p, info.get("s", {}), q)
		p = smooth(p, 1, q * 0.6, closed)
	# 3) знаки карти: їх більше, що вищі характеристики
	var box: Rect2 = _bounds(p)
	match kind:
		"forest", "lake", "mountains", "swamp":
			var sym: String = {"forest": "tree", "lake": "wave", "mountains": "peak", "swamp": "tuft"}[kind]
			var room: float = absf(_signed_area(p)) * z * z / 900.0
			var want: int = int(floor(q * clampf(room, 1.0, 14.0)))
			var tries: int = want * 12
			while marks.size() < want and tries > 0:
				tries -= 1
				var c := Vector2(rng.randf_range(box.position.x, box.end.x), rng.randf_range(box.position.y, box.end.y))
				if not Geometry2D.is_point_in_polygon(c, p) or _too_close(marks, c, mark_m * 1.6):
					continue
				if q >= 0.5 and terrain != null and not _is(terrain, c, kind):
					continue   # розумний герой ставить деревця лише там, де справді ліс
				marks.append({"k": sym, "x": c.x, "y": c.y, "s": mark_m})
		"river":
			var every: float = 140.0 / z
			var want_r: int = int(floor(q * _length(p) / every))
			for i in want_r:
				var c: Vector2 = _point_at(p, (i + 0.5) * every)
				marks.append({"k": "wave", "x": c.x, "y": c.y, "s": mark_m * 0.8})
		"settlement":
			var st: Dictionary = info.get("s", {})
			var sc: Vector2 = st.get("_center", box.get_center()) if q >= 0.3 else box.get_center()
			var houses: int = 1 + int(round(q * 3.0))
			for i in houses:
				var off: Vector2 = Vector2.ZERO if i == 0 else Vector2.from_angle(TAU * i / maxf(1.0, houses - 1) + 0.4) * mark_m * 1.3
				marks.append({"k": "house", "x": sc.x + off.x, "y": sc.y + off.y, "s": mark_m})
			if q >= 0.5 and String(st.get("name", "")) != "":
				marks.append({"k": "label", "x": sc.x, "y": box.end.y, "s": mark_m, "t": String(st["name"])})
	return {"pts": p, "m": marks}


# =====================================================================
# ГЕОМЕТРІЯ
# =====================================================================
static func _length(p: PackedVector2Array) -> float:
	var l: float = 0.0
	for i in range(1, p.size()):
		l += p[i - 1].distance_to(p[i])
	return l


static func _bounds(p: PackedVector2Array) -> Rect2:
	if p.is_empty():
		return Rect2()
	var r := Rect2(p[0], Vector2.ZERO)
	for v in p:
		r = r.expand(v)
	return r


static func _signed_area(p: PackedVector2Array) -> float:
	var a: float = 0.0
	for i in p.size():
		var u: Vector2 = p[i]
		var v: Vector2 = p[(i + 1) % p.size()]
		a += u.x * v.y - v.x * u.y
	return a * 0.5


static func _point_at(p: PackedVector2Array, dist: float) -> Vector2:
	var left: float = dist
	for i in range(1, p.size()):
		var d: float = p[i - 1].distance_to(p[i])
		if left <= d and d > 0.0:
			return p[i - 1].lerp(p[i], left / d)
		left -= d
	return p[-1]


## Ламана з рівним кроком step (кінці зберігаються)
static func resample(p: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if p.size() < 2 or step <= 0.0:
		return p.duplicate()
	out.append(p[0])
	var carry: float = 0.0
	for i in range(1, p.size()):
		var a: Vector2 = p[i - 1]
		var b: Vector2 = p[i]
		var d: float = a.distance_to(b)
		var t: float = step - carry
		while t <= d:
			out.append(a.lerp(b, t / d))
			t += step
		carry = d - (t - step)
	if out[-1].distance_to(p[-1]) > step * 0.3:
		out.append(p[-1])
	else:
		out[-1] = p[-1]
	return out


## Ковзне середнє на k сусідів, змішане з початковим на силу amount; кінці відкритої лінії на місці
static func smooth(p: PackedVector2Array, k: int, amount: float, closed: bool) -> PackedVector2Array:
	var n: int = p.size()
	if n < 3 or k <= 0 or amount <= 0.0:
		return p
	var out := PackedVector2Array()
	out.resize(n)
	var ring: int = n - 1 if closed else n   # у замкненій останні точка = перша
	for i in n:
		if not closed and (i == 0 or i == n - 1):
			out[i] = p[i]
			continue
		var s := Vector2.ZERO
		var c: int = 0
		for j in range(-k, k + 1):
			var idx: int = i + j
			if closed:
				idx = posmod(idx, ring)
			elif idx < 0 or idx >= n:
				continue
			s += p[idx]
			c += 1
		out[i] = p[i].lerp(s / c, amount)
	if closed:
		out[n - 1] = out[0]
	return out


static func _too_close(marks: Array, c: Vector2, d: float) -> bool:
	for m in marks:
		if Vector2(m["x"], m["y"]).distance_to(c) < d:
			return true
	return false


## Точки всередині фігури на сітці g×g
static func _inside_samples(p: PackedVector2Array, box: Rect2, g: int) -> Array:
	var out: Array = []
	for i in g:
		for j in g:
			var c: Vector2 = box.position + Vector2((i + 0.5) / g * box.size.x, (j + 0.5) / g * box.size.y)
			if Geometry2D.is_point_in_polygon(c, p):
				out.append(c)
	return out


# =====================================================================
# МІСЦЕВІСТЬ
# =====================================================================
static func _biome(t: Object, p: Vector2) -> int:
	return int(t.biome_at(p)) if t.has_method("biome_at") else 0


static func _is(t: Object, p: Vector2, what: String) -> bool:
	match what:
		"water", "lake":
			return t.has_method("water_at") and float(t.water_at(p)) >= 0.5
		"trail":
			var tr: Object = t.get("trails")
			return tr != null and tr.has_method("trodden") and bool(tr.trodden(p))
		"forest":
			var b: int = _biome(t, p)
			return b == B_FOREST or b == B_CURSED_FOREST
		"mountains":
			return _biome(t, p) == B_MOUNTAINS
		"swamp":
			var b2: int = _biome(t, p)
			return b2 == B_SWAMP or b2 == B_CURSED_SWAMP
	return false


static func _near(t: Object, p: Vector2, r: float, what: String) -> bool:
	if _is(t, p, what):
		return true
	for k in 8:
		if _is(t, p + Vector2.from_angle(k * TAU / 8.0) * r, what):
			return true
	return false


## Найближча точка потрібної місцевості в межах r (кільця по 12 напрямків) або INF
static func _nearest(t: Object, p: Vector2, r: float, what: String) -> Vector2:
	if _is(t, p, what):
		return p
	for ring in 4:
		var d: float = r * (ring + 1) / 4.0
		var best := Vector2.INF
		for k in 12:
			var c: Vector2 = p + Vector2.from_angle(k * TAU / 12.0) * d
			if _is(t, c, what) and (best == Vector2.INF or c.distance_to(p) < best.distance_to(p)):
				best = c
		if best != Vector2.INF:
			return best
	return Vector2.INF


static func _snap_to(p: PackedVector2Array, t: Object, what: String, r: float, pull: float, closed: bool) -> PackedVector2Array:
	var offs := PackedVector2Array()
	offs.resize(p.size())
	for i in p.size():
		var n: Vector2 = _nearest(t, p[i], r, what)
		if n != Vector2.INF:
			offs[i] = (n - p[i]) * pull
	return _shifted(p, offs, closed)


## Зсуви сусідніх точок усереднюються, щоб притягування не давало зубців
static func _shifted(p: PackedVector2Array, offs: PackedVector2Array, closed: bool) -> PackedVector2Array:
	var o: PackedVector2Array = smooth(offs, 3, 1.0, closed)
	var out := p.duplicate()
	for i in out.size():
		out[i] += o[i]
	if closed and out.size() > 1:
		out[-1] = out[0]
	return out


## Край лісу, озера, гір: шукаємо межу місцевості вздовж нормалі до штриха й підсуваємо точку до неї
static func _snap_edge(p: PackedVector2Array, t: Object, what: String, r: float, pull: float) -> PackedVector2Array:
	var n: int = p.size()
	if n < 4:
		return p.duplicate()
	var offs := PackedVector2Array()
	offs.resize(n)
	var steps: int = 6
	for i in n - 1:
		var a: Vector2 = p[posmod(i - 1, n - 1)]
		var b: Vector2 = p[(i + 1) % (n - 1)]
		var nrm: Vector2 = (b - a).orthogonal().normalized()
		if nrm == Vector2.ZERO:
			continue
		var here: bool = _is(t, p[i], what)
		var best: float = INF
		for s in range(1, steps + 1):
			for sgn in [-1.0, 1.0]:
				var d: float = sgn * r * s / steps
				if _is(t, p[i] + nrm * d, what) != here and absf(d) < absf(best):
					best = d
			if best != INF:
				break
		if best != INF:
			offs[i] = nrm * best * pull
	offs[n - 1] = offs[0]
	return _shifted(p, offs, true)


## Поселення: обрис стає охайнішим колом довкола справжнього центру
static func _round_settlement(p: PackedVector2Array, st: Dictionary, q: float) -> PackedVector2Array:
	var box: Rect2 = _bounds(p)
	var c: Vector2 = box.get_center().lerp(st.get("_center", box.get_center()), q * 0.6)
	var rad: float = 0.0
	for v in p:
		rad += v.distance_to(c)
	rad /= maxf(1.0, p.size())
	var out := p.duplicate()
	for i in out.size():
		var d: Vector2 = out[i] - c
		if d != Vector2.ZERO:
			out[i] = out[i].lerp(c + d.normalized() * rad, q * 0.7)
	out[-1] = out[0]
	return out


static func _snap_ends_to_towns(p: PackedVector2Array, t: Object, r: float, q: float) -> PackedVector2Array:
	if q < 0.4 or p.size() < 2:
		return p
	var out := p.duplicate()
	for idx in [0, out.size() - 1]:
		var st: Dictionary = _settlement_near(out[idx], t, r)
		if not st.is_empty():
			out[idx] = out[idx].lerp(st["_center"], q)
	return out


static func _towns(t: Object) -> Array:
	var st: Object = t.get("settlements")
	if st == null:
		return []
	var l: Variant = st.get("list")
	return l if l is Array else []


static func _settlement_inside(p: PackedVector2Array, t: Object) -> Dictionary:
	for s in _towns(t):
		if s is Dictionary and s.has("_center") and Geometry2D.is_point_in_polygon(s["_center"], p):
			return s
	return {}


static func _settlement_near(v: Vector2, t: Object, r: float) -> Dictionary:
	var best: Dictionary = {}
	var bd: float = r
	for s in _towns(t):
		if s is Dictionary and s.has("_center"):
			var d: float = v.distance_to(s["_center"])
			if d <= bd:
				bd = d
				best = s
	return best

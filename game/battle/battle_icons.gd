extends RefCounted
## Малюнки бою без картинок: портрети в кружечках, зброя, дії, типи шкоди.
## Усе малюється векторно на будь-якому CanvasItem — підмінити на текстури можна тут-таки.

const INK := Color(0.13, 0.11, 0.09)
const PARCH := Color(0.86, 0.8, 0.66)
const PARCH_DARK := Color(0.7, 0.63, 0.48)
const STEEL := Color(0.78, 0.8, 0.82)
const STEEL_DARK := Color(0.42, 0.45, 0.48)
const WOOD := Color(0.55, 0.36, 0.18)
const WOOD_DARK := Color(0.33, 0.2, 0.1)
const TYPE_COLORS: Dictionary = {"fire": Color(0.92, 0.25, 0.12), "radiation": Color(0.7, 0.42, 0.94), "poison": Color(0.35, 0.8, 0.25),
	"slashing": Color(0.75, 0.75, 0.78), "piercing": Color(0.6, 0.75, 0.9), "bludgeoning": Color(0.7, 0.55, 0.35), "cold": Color(0.6, 0.85, 1.0)}


static func _poly(ci: CanvasItem, pts: Array, o: Vector2, s: float, col: Color) -> void:
	var p := PackedVector2Array()
	for q in pts:
		p.append(o + Vector2(q[0], q[1]) * s)
	ci.draw_colored_polygon(p, col)


static func _line(ci: CanvasItem, a: Array, b: Array, o: Vector2, s: float, col: Color, w: float) -> void:
	ci.draw_line(o + Vector2(a[0], a[1]) * s, o + Vector2(b[0], b[1]) * s, col, maxf(1.0, w * s), true)


# =====================================================================
# ПОРТРЕТИ (у кружечку радіуса r; координати фігур — у частках r від центру)
# =====================================================================
static func portrait(ci: CanvasItem, kind: String, c: Vector2, r: float, dim: bool = false) -> void:
	ci.draw_circle(c, r, PARCH.darkened(0.35) if dim else PARCH)
	ci.draw_circle(c + Vector2(0, r * 0.25), r * 0.8, Color(PARCH_DARK, 0.35))
	var ink: Color = Color(0.25, 0.22, 0.2) if dim else INK
	match kind:
		"wolf", "hound", "dog":
			_beast(ci, kind, c, r, ink)
		"boar":
			_boar(ci, c, r, ink)
		_:
			_human(ci, kind, c, r, ink)


static func _human(ci: CanvasItem, kind: String, c: Vector2, r: float, ink: Color) -> void:
	# плечі
	_poly(ci, [[-0.78, 0.95], [-0.62, 0.52], [-0.25, 0.36], [0.25, 0.36], [0.62, 0.52], [0.78, 0.95]], c, r, ink)
	# голова
	ci.draw_circle(c + Vector2(0, -0.12) * r, r * 0.34, ink)
	var face: Color = PARCH.darkened(0.15)
	match kind:
		"hero":
			# довге волосся, обличчя, борода
			_poly(ci, [[-0.4, 0.3], [-0.42, -0.2], [-0.32, -0.5], [0, -0.62], [0.32, -0.5], [0.42, -0.2], [0.4, 0.3], [0.26, 0.1], [0.27, -0.3], [-0.27, -0.3], [-0.26, 0.1]], c, r, ink)
			_poly(ci, [[-0.26, -0.34], [0.0, -0.4], [0.26, -0.34], [0.27, 0.0], [0.16, 0.2], [-0.16, 0.2], [-0.27, 0.0]], c, r, face)
			_poly(ci, [[-0.27, -0.04], [-0.1, 0.02], [0.1, 0.02], [0.27, -0.04], [0.2, 0.22], [0, 0.34], [-0.2, 0.22]], c, r, ink)
			_poly(ci, [[-0.08, 0.06], [0.08, 0.06], [0.05, 0.11], [-0.05, 0.11]], c, r, face.darkened(0.3))
			_line(ci, [-0.19, -0.24], [-0.05, -0.22], c, r, ink, 0.05)
			_line(ci, [0.05, -0.22], [0.19, -0.24], c, r, ink, 0.05)
			ci.draw_circle(c + Vector2(-0.11, -0.15) * r, r * 0.04, ink)
			ci.draw_circle(c + Vector2(0.11, -0.15) * r, r * 0.04, ink)
			_line(ci, [0.0, -0.14], [0.03, -0.04], c, r, face.darkened(0.35), 0.04)
		"bandit", "archer", "bandit_archer":
			# каптур
			_poly(ci, [[-0.46, 0.3], [-0.42, -0.25], [0, -0.66], [0.42, -0.25], [0.46, 0.3], [0.24, 0.12], [-0.24, 0.12]], c, r, ink)
			_poly(ci, [[-0.2, -0.22], [0.2, -0.22], [0.18, 0.06], [0, 0.14], [-0.18, 0.06]], c, r, face)
			_poly(ci, [[-0.2, -0.06], [0.2, -0.06], [0.18, 0.06], [0, 0.14], [-0.18, 0.06]], c, r, Color(0.35, 0.12, 0.1))
			ci.draw_circle(c + Vector2(-0.08, -0.13) * r, r * 0.035, ink)
			ci.draw_circle(c + Vector2(0.08, -0.13) * r, r * 0.035, ink)
			if kind != "bandit":
				_line(ci, [0.55, -0.6], [0.75, 0.2], c, r, WOOD_DARK, 0.06)
		"chief", "bandit_chief":
			# шолом із наносником
			_poly(ci, [[-0.4, -0.12], [-0.36, -0.42], [0, -0.6], [0.36, -0.42], [0.4, -0.12]], c, r, STEEL_DARK)
			_line(ci, [0, -0.2], [0, 0.0], c, r, STEEL_DARK, 0.07)
			_poly(ci, [[-0.2, -0.12], [-0.04, -0.12], [-0.04, 0.12], [-0.18, 0.06]], c, r, face)
			_poly(ci, [[0.04, -0.12], [0.2, -0.12], [0.18, 0.06], [0.04, 0.12]], c, r, face)
			_poly(ci, [[-0.2, 0.04], [0.2, 0.04], [0.12, 0.26], [-0.12, 0.26]], c, r, ink)
		_:
			# НПС: коротке волосся, обличчя
			_poly(ci, [[-0.36, -0.12], [-0.34, -0.42], [0, -0.56], [0.34, -0.42], [0.36, -0.12], [0.26, -0.28], [-0.26, -0.28]], c, r, ink)
			_poly(ci, [[-0.22, -0.28], [0.22, -0.28], [0.22, 0.0], [0.1, 0.16], [-0.1, 0.16], [-0.22, 0.0]], c, r, face)
			ci.draw_circle(c + Vector2(-0.09, -0.12) * r, r * 0.035, ink)
			ci.draw_circle(c + Vector2(0.09, -0.12) * r, r * 0.035, ink)


static func _beast(ci: CanvasItem, kind: String, c: Vector2, r: float, ink: Color) -> void:
	# морда в три чверті: лоб, вуха, витягнутий ніс праворуч-униз
	var ears: Array = [[-0.42, -0.2], [-0.36, -0.68], [-0.12, -0.36], [0.06, -0.72], [0.18, -0.3]] if kind != "dog" else [[-0.44, -0.1], [-0.5, -0.5], [-0.2, -0.4], [0.1, -0.5], [0.2, -0.3]]
	_poly(ci, ears, c, r, ink)
	_poly(ci, [[-0.5, 0.0], [-0.42, -0.32], [0.0, -0.42], [0.3, -0.3], [0.62, 0.02], [0.72, 0.14], [0.6, 0.3], [0.2, 0.34], [-0.1, 0.62], [-0.46, 0.5]], c, r, ink)
	if kind == "dog":
		_poly(ci, [[-0.5, -0.4], [-0.66, 0.1], [-0.42, 0.06]], c, r, ink)
	var eye: Color = Color(0.7, 1.0, 0.2) if kind == "hound" else PARCH
	ci.draw_circle(c + Vector2(0.06, -0.14) * r, r * 0.07, eye)
	ci.draw_circle(c + Vector2(0.72, 0.13) * r, r * 0.06, PARCH.darkened(0.6))
	# вищир
	_poly(ci, [[0.24, 0.26], [0.3, 0.38], [0.36, 0.26], [0.42, 0.37], [0.48, 0.25]], c, r, PARCH)
	if kind == "hound":
		for p in [[-0.3, 0.3], [-0.1, 0.1], [0.2, -0.1]]:
			ci.draw_circle(c + Vector2(p[0], p[1]) * r, r * 0.05, Color(0.7, 1.0, 0.2, 0.9))


static func _boar(ci: CanvasItem, c: Vector2, r: float, ink: Color) -> void:
	_poly(ci, [[-0.6, 0.5], [-0.66, -0.1], [-0.4, -0.45], [-0.3, -0.7], [-0.12, -0.45], [0.2, -0.42], [0.5, -0.1], [0.72, 0.1], [0.72, 0.36], [0.4, 0.42], [0.1, 0.62], [-0.3, 0.7]], c, r, ink)
	ci.draw_circle(c + Vector2(0.62, 0.22) * r, r * 0.12, PARCH.darkened(0.55))
	ci.draw_circle(c + Vector2(0.12, -0.15) * r, r * 0.06, Color(0.9, 0.3, 0.2))
	# ікла
	_poly(ci, [[0.38, 0.38], [0.5, 0.1], [0.46, 0.4]], c, r, PARCH)
	_poly(ci, [[0.2, 0.44], [0.3, 0.16], [0.28, 0.46]], c, r, PARCH)
	# щетина
	for i in 5:
		_line(ci, [-0.5 + i * 0.12, -0.44 - (0.12 if i % 2 == 0 else 0.0)], [-0.42 + i * 0.12, -0.3], c, r, ink, 0.05)


# =====================================================================
# ЗБРОЯ (у квадраті rect)
# =====================================================================
static func weapon(ci: CanvasItem, kind: String, rect: Rect2, dim: bool = false) -> void:
	var o: Vector2 = rect.get_center()
	var s: float = minf(rect.size.x, rect.size.y) * 0.5
	var st: Color = STEEL if not dim else STEEL.darkened(0.4)
	var sd: Color = STEEL_DARK if not dim else STEEL_DARK.darkened(0.4)
	var wd: Color = WOOD if not dim else WOOD.darkened(0.4)
	var wdd: Color = WOOD_DARK if not dim else WOOD_DARK.darkened(0.4)
	match kind:
		"knife":
			_poly(ci, [[-0.72, 0.72], [-0.5, 0.42], [-0.36, 0.56]], o, s, wdd)
			_poly(ci, [[-0.42, 0.5], [-0.2, 0.22], [-0.1, 0.32], [-0.32, 0.6]], o, s, wd)
			_line(ci, [-0.3, 0.12], [0.0, 0.42], o, s, sd, 0.08)
			_poly(ci, [[-0.14, 0.28], [0.62, -0.62], [0.74, -0.74], [0.6, -0.44], [-0.04, 0.38]], o, s, st)
			_line(ci, [-0.08, 0.32], [0.66, -0.66], o, s, sd, 0.03)
		"sword":
			_poly(ci, [[-0.78, 0.78], [-0.62, 0.56], [-0.56, 0.62]], o, s, wdd)
			_line(ci, [-0.66, 0.66], [-0.4, 0.4], o, s, wd, 0.12)
			_line(ci, [-0.56, 0.22], [-0.22, 0.56], o, s, sd, 0.1)
			_poly(ci, [[-0.42, 0.34], [0.66, -0.74], [0.8, -0.8], [0.74, -0.66], [-0.34, 0.42]], o, s, st)
		"axe", "cleaver":
			_line(ci, [-0.7, 0.75], [0.35, -0.55], o, s, wd, 0.13)
			if kind == "axe":
				_poly(ci, [[0.08, -0.5], [0.3, -0.78], [0.72, -0.5], [0.6, -0.08], [0.32, -0.18]], o, s, st)
				_line(ci, [0.3, -0.78], [0.72, -0.5], o, s, Color(1, 1, 1, 0.6), 0.04)
			else:
				_poly(ci, [[-0.1, -0.3], [0.2, -0.75], [0.8, -0.55], [0.55, 0.05], [0.25, -0.05]], o, s, Color(0.6, 0.45, 0.35) if not dim else sd)
				ci.draw_circle(o + Vector2(0.45, -0.35) * s, s * 0.1, Color(0.7, 1.0, 0.2))
		"club":
			_poly(ci, [[-0.74, 0.62], [-0.62, 0.74], [0.5, -0.3], [0.7, -0.62], [0.62, -0.72], [0.3, -0.56]], o, s, wd)
			for p in [[0.3, -0.35], [0.5, -0.5], [0.15, -0.15]]:
				ci.draw_circle(o + Vector2(p[0], p[1]) * s, s * 0.05, wdd)
		"mace":
			_line(ci, [-0.7, 0.7], [0.25, -0.25], o, s, wd, 0.12)
			ci.draw_circle(o + Vector2(0.38, -0.38) * s, s * 0.3, st)
			for a in 8:
				var v := Vector2.from_angle(a * TAU / 8.0)
				_poly(ci, [[0.38 + v.x * 0.25 - v.y * 0.08, -0.38 + v.y * 0.25 + v.x * 0.08], [0.38 + v.x * 0.45, -0.38 + v.y * 0.45], [0.38 + v.x * 0.25 + v.y * 0.08, -0.38 + v.y * 0.25 - v.x * 0.08]], o, s, sd)
		"spear":
			_line(ci, [-0.8, 0.8], [0.45, -0.45], o, s, wd, 0.08)
			_poly(ci, [[0.3, -0.42], [0.82, -0.82], [0.42, -0.3]], o, s, st)
		"sling":
			ci.draw_arc(o + Vector2(0.0, 0.1) * s, s * 0.6, PI * 0.15, PI * 1.05, 20, wdd, maxf(1.5, s * 0.06), true)
			ci.draw_circle(o + Vector2(-0.05, 0.68) * s, s * 0.2, wd)
			ci.draw_circle(o + Vector2(-0.05, 0.62) * s, s * 0.1, Color(0.6, 0.6, 0.6))
		"bow":
			ci.draw_arc(o + Vector2(-0.45, 0.45) * s, s * 1.0, -PI * 0.5, 0.0, 24, wd, maxf(2.0, s * 0.1), true)
			_line(ci, [-0.45, -0.55], [0.55, 0.45], o, s, Color(0.9, 0.9, 0.85), 0.025)
			_line(ci, [-0.6, 0.6], [0.45, -0.45], o, s, wdd, 0.04)
			_poly(ci, [[0.35, -0.5], [0.6, -0.6], [0.5, -0.35]], o, s, sd)
		"torch":
			_line(ci, [-0.6, 0.75], [0.15, -0.2], o, s, wd, 0.14)
			_line(ci, [0.0, -0.05], [0.22, -0.28], o, s, wdd, 0.2)
			_poly(ci, [[0.05, -0.3], [0.3, -0.85], [0.42, -0.5], [0.62, -0.62], [0.52, -0.2], [0.3, -0.08]], o, s, Color(0.95, 0.5, 0.1) if not dim else sd)
			_poly(ci, [[0.18, -0.28], [0.32, -0.6], [0.45, -0.3], [0.32, -0.18]], o, s, Color(1.0, 0.85, 0.3) if not dim else st)
		"fist":
			_poly(ci, [[-0.45, 0.7], [-0.5, -0.05], [-0.3, -0.42], [0.35, -0.5], [0.55, -0.3], [0.5, 0.2], [0.25, 0.7]], o, s, Color(0.85, 0.66, 0.5) if not dim else sd)
			for i in 3:
				_line(ci, [-0.25 + i * 0.22, -0.48], [-0.25 + i * 0.22, -0.15], o, s, Color(0.5, 0.35, 0.25), 0.04)
			_line(ci, [-0.5, 0.0], [0.1, 0.05], o, s, Color(0.5, 0.35, 0.25), 0.04)
		"bite", "tusk":
			_poly(ci, [[-0.7, -0.3], [0.7, -0.3], [0.5, 0.0], [-0.5, 0.0]], o, s, INK if not dim else sd)
			_poly(ci, [[-0.7, 0.3], [0.7, 0.3], [0.5, 0.6], [-0.5, 0.6]], o, s, INK if not dim else sd)
			for i in 5:
				var x: float = -0.5 + i * 0.25
				_poly(ci, [[x - 0.1, -0.05], [x, 0.22], [x + 0.1, -0.05]], o, s, Color(0.95, 0.92, 0.85))
				_poly(ci, [[x - 0.1, 0.35], [x, 0.08], [x + 0.1, 0.35]], o, s, Color(0.95, 0.92, 0.85))
		_:
			ci.draw_circle(o, s * 0.4, sd)


# =====================================================================
# ДІЇ Й ЗДІБНОСТІ (у квадраті rect)
# =====================================================================
static func action(ci: CanvasItem, kind: String, rect: Rect2, col: Color) -> void:
	var o: Vector2 = rect.get_center()
	var s: float = minf(rect.size.x, rect.size.y) * 0.5
	match kind:
		"move":
			# людина, що біжить, і стрілка
			ci.draw_circle(o + Vector2(-0.3, -0.62) * s, s * 0.14, col)
			_line(ci, [-0.32, -0.45], [-0.42, 0.05], o, s, col, 0.14)
			_line(ci, [-0.42, 0.05], [-0.15, 0.35], o, s, col, 0.12)
			_line(ci, [-0.15, 0.35], [-0.25, 0.72], o, s, col, 0.12)
			_line(ci, [-0.42, 0.05], [-0.72, 0.4], o, s, col, 0.12)
			_line(ci, [-0.35, -0.3], [-0.05, -0.15], o, s, col, 0.1)
			_line(ci, [-0.35, -0.3], [-0.68, -0.15], o, s, col, 0.1)
			_line(ci, [0.12, 0.0], [0.58, 0.0], o, s, col, 0.14)
			_poly(ci, [[0.5, -0.24], [0.82, 0.0], [0.5, 0.24]], o, s, col)
		"dash":
			for dx in [-0.45, 0.05]:
				_poly(ci, [[dx, -0.45], [dx + 0.42, 0.0], [dx, 0.45], [dx + 0.12, 0.0]], o, s, col)
		"disengage":
			_line(ci, [0.5, 0.0], [-0.35, 0.0], o, s, col, 0.14)
			_poly(ci, [[-0.25, -0.3], [-0.65, 0.0], [-0.25, 0.3]], o, s, col)
			_line(ci, [0.62, -0.5], [0.62, 0.5], o, s, col, 0.08)
		"dodge", "shield":
			_poly(ci, [[-0.5, -0.55], [0.5, -0.55], [0.48, 0.1], [0.0, 0.62], [-0.48, 0.1]], o, s, col)
			_poly(ci, [[-0.32, -0.38], [0.32, -0.38], [0.3, 0.05], [0.0, 0.4], [-0.3, 0.05]], o, s, Color(0, 0, 0, 0.35))
		"help":
			_poly(ci, [[-0.5, 0.6], [-0.55, -0.05], [-0.35, -0.1], [-0.3, -0.6], [-0.15, -0.62], [-0.1, -0.15], [0.0, -0.7], [0.15, -0.7], [0.18, -0.12], [0.3, -0.6], [0.45, -0.55], [0.4, 0.1], [0.62, -0.05], [0.66, 0.1], [0.3, 0.6]], o, s, col)
		"hide":
			ci.draw_arc(o, s * 0.55, PI * 0.15, PI * 0.85, 16, col, maxf(2.0, s * 0.12), true)
			for i in 4:
				var x: float = -0.4 + i * 0.27
				_line(ci, [x, 0.42], [x - 0.08, 0.62], o, s, col, 0.08)
			_line(ci, [-0.6, -0.6], [0.6, 0.6], o, s, col, 0.1)
		"potion", "salve", "healing_salve":
			_poly(ci, [[-0.12, -0.7], [0.12, -0.7], [0.12, -0.35], [0.45, 0.0], [0.45, 0.6], [-0.45, 0.6], [-0.45, 0.0], [-0.12, -0.35]], o, s, col)
			_poly(ci, [[-0.38, 0.1], [0.38, 0.1], [0.38, 0.52], [-0.38, 0.52]], o, s, Color(0.85, 0.15, 0.15))
		"ready":
			ci.draw_arc(o, s * 0.6, 0.0, TAU, 24, col, maxf(2.0, s * 0.1), true)
			_line(ci, [0, 0], [0, -0.42], o, s, col, 0.1)
			_line(ci, [0, 0], [0.3, 0.15], o, s, col, 0.1)
		"flee":
			_poly(ci, [[-0.6, -0.7], [0.0, -0.7], [0.0, 0.7], [-0.6, 0.7]], o, s, Color(col, 0.35))
			_line(ci, [-0.4, 0.0], [0.45, 0.0], o, s, col, 0.14)
			_poly(ci, [[0.35, -0.3], [0.75, 0.0], [0.35, 0.3]], o, s, col)
		"second_wind", "heal":
			_poly(ci, [[0.0, 0.62], [-0.62, 0.0], [-0.6, -0.36], [-0.3, -0.58], [0.0, -0.32], [0.3, -0.58], [0.6, -0.36], [0.62, 0.0]], o, s, Color(0.85, 0.2, 0.2))
			_line(ci, [0, -0.22], [0, 0.3], o, s, col, 0.12)
			_line(ci, [-0.26, 0.04], [0.26, 0.04], o, s, col, 0.12)
		"fire_flask":
			_poly(ci, [[-0.12, -0.5], [0.12, -0.5], [0.12, -0.25], [0.4, 0.05], [0.4, 0.65], [-0.4, 0.65], [-0.4, 0.05], [-0.12, -0.25]], o, s, col)
			_poly(ci, [[-0.05, -0.5], [0.1, -0.9], [0.25, -0.6], [0.15, -0.45]], o, s, Color(1.0, 0.55, 0.1))
			_poly(ci, [[-0.32, 0.2], [0.32, 0.2], [0.32, 0.55], [-0.32, 0.55]], o, s, Color(1.0, 0.45, 0.1))
		"poison_dart":
			_line(ci, [-0.6, 0.6], [0.45, -0.45], o, s, col, 0.08)
			_poly(ci, [[0.3, -0.5], [0.75, -0.75], [0.5, -0.3]], o, s, Color(0.4, 0.9, 0.3))
			_poly(ci, [[-0.65, 0.35], [-0.45, 0.45], [-0.35, 0.65], [-0.6, 0.65]], o, s, col)
		"war_cry", "howl":
			_poly(ci, [[-0.6, -0.2], [-0.3, -0.2], [0.1, -0.55], [0.1, 0.55], [-0.3, 0.2], [-0.6, 0.2]], o, s, col)
			for i in 3:
				ci.draw_arc(o + Vector2(0.1, 0) * s, s * (0.3 + i * 0.2), -PI * 0.25, PI * 0.25, 8, col, maxf(1.5, s * 0.07), true)
		"net":
			for i in 4:
				var t: float = -0.6 + i * 0.4
				_line(ci, [t, -0.6], [t, 0.6], o, s, col, 0.06)
				_line(ci, [-0.6, t], [0.6, t], o, s, col, 0.06)
		"swap":
			_line(ci, [-0.5, -0.25], [0.4, -0.25], o, s, col, 0.1)
			_poly(ci, [[0.3, -0.45], [0.65, -0.25], [0.3, -0.05]], o, s, col)
			_line(ci, [0.5, 0.25], [-0.4, 0.25], o, s, col, 0.1)
			_poly(ci, [[-0.3, 0.05], [-0.65, 0.25], [-0.3, 0.45]], o, s, col)
		"log":
			for i in 4:
				_line(ci, [-0.5, -0.45 + i * 0.3], [0.5 - (0.3 if i == 3 else 0.0), -0.45 + i * 0.3], o, s, col, 0.09)
		_:
			ci.draw_circle(o, s * 0.4, col)


## Кружечок типу шкоди (як червона крапля вогню на картці зразка)
static func damage_type(ci: CanvasItem, dtype: String, c: Vector2, r: float) -> void:
	var col: Color = TYPE_COLORS.get(dtype, Color(0.7, 0.7, 0.7))
	ci.draw_circle(c, r + 1.5, Color(0.05, 0.05, 0.05))
	ci.draw_circle(c, r, Color(0.95, 0.92, 0.85))
	match dtype:
		"fire":
			_poly(ci, [[0.0, -0.75], [0.5, 0.1], [0.35, 0.55], [0.0, 0.7], [-0.35, 0.55], [-0.5, 0.1]], c, r, col)
		"radiation":
			# прокляття (Huzzah 2026-10-23: замість знака радіації)
			preload("res://characters/inventory_view.gd").curse_icon(ci, c, r)
		"slashing":
			_line(ci, [-0.5, 0.5], [0.5, -0.5], c, r, Color(0.3, 0.3, 0.35), 0.22)
		"piercing":
			_poly(ci, [[0.0, -0.7], [0.35, 0.0], [0.1, 0.0], [0.1, 0.6], [-0.1, 0.6], [-0.1, 0.0], [-0.35, 0.0]], c, r, Color(0.25, 0.35, 0.5))
		_:
			ci.draw_circle(c, r * 0.45, col.darkened(0.3))


## Годинничок-«очко дії»: повний — є, порожній — витрачено
static func pip(ci: CanvasItem, c: Vector2, r: float, full: bool, letter: String, font: Font) -> void:
	ci.draw_circle(c, r, Color(0.94, 0.62, 0.15) if full else Color(0.12, 0.13, 0.1))
	ci.draw_arc(c, r, 0.0, TAU, 20, Color(0.94, 0.62, 0.15), 1.5, true)
	ci.draw_string(font, c + Vector2(-r, r * 0.45), letter, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, int(r * 1.15), Color(0.12, 0.09, 0.05) if full else Color(0.94, 0.62, 0.15))

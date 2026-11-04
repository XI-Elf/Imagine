extends RefCounted
## Дошка-шестикутник пласкою стороною вгору 41625 x 36000 м: форма й розмір ігрової карти.
## Підключається за шляхом: preload("res://board.gd"). Координати карти X Y у метрах дошки.
## Малюнок і шар біомів переносяться на дошку інструментом tools/make_new_map.py.
## to_src / to_board (колишня розгортка S 36000 x 18000) залишено для tools/board_proj.py:
## за ними інструмент розкладає суходіл нової карти для моделі атмосфери.

const SRC := Vector2(36000.0, 18000.0)
const SIZE := Vector2(41625.0, 36000.0)
const CENTER := Vector2(20812.5, 18000.0)
const APO: float = 18000.0
const C30: float = 0.8660254037844386
# Растри дошки (art/board/*.png): 4736 x 4096, клітинка 8,7890625 м
const RAS_NX: int = 4736
const RAS_NY: int = 4096
const RAS_M: float = 8.7890625


static func _smooth(t: float) -> float:
	var u: float = clampf((t - 0.5) * 2.0, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)


static func _dsmooth(t: float) -> float:
	var u: float = clampf((t - 0.5) * 2.0, 0.0, 1.0)
	return 12.0 * u * (1.0 - u)


static func _hex_c(u: Vector2) -> float:
	return maxf(absf(u.y), maxf(absf(C30 * u.x + 0.5 * u.y), absf(-C30 * u.x + 0.5 * u.y)))


# «Шестикутна довжина» вектора: APO на краю дошки
static func hex_norm(v: Vector2) -> float:
	return maxf(absf(v.y), maxf(absf(C30 * v.x + 0.5 * v.y), absf(-C30 * v.x + 0.5 * v.y)))


static func inside(p: Vector2, margin: float = 0.0) -> bool:
	return hex_norm(p - CENTER) <= APO - margin


# Точка дошки, втягнута всередину гекса (з відступом margin від краю)
static func clamp_inside(p: Vector2, margin: float = 0.0) -> Vector2:
	var v: Vector2 = p - CENTER
	var hn: float = hex_norm(v)
	var lim: float = APO - margin
	if hn <= lim or hn < 0.001:
		return p
	return CENTER + v * (lim / hn)


# S (колишня розгортка) -> P (дошка)
static func to_board(s: Vector2) -> Vector2:
	var t: float = clampf(s.y / SRC.y, 0.0, 1.0)
	var lam: float = (s.x - SRC.x * 0.5) / SRC.x * TAU
	var u := Vector2(sin(lam), cos(lam))
	var rho: float = APO * t / (1.0 - _smooth(t) * (1.0 - _hex_c(u)))
	return CENTER + u * rho


# Частка шляху від Північного полюса до Південного (0..1, за краєм більше 1)
static func colat_t(p: Vector2) -> float:
	var v: Vector2 = p - CENTER
	var rho: float = v.length()
	if rho < 0.001:
		return 0.0
	var c: float = _hex_c(v / rho)
	var t: float = rho / APO
	for _i in 6:
		var f: float = APO * t - rho * (1.0 - _smooth(t) * (1.0 - c))
		var fp: float = APO + rho * (1.0 - c) * _dsmooth(t)
		t = clampf(t - f / fp, 0.0, 1.5)
	return t


# P (дошка) -> S (колишня розгортка)
static func to_src(p: Vector2) -> Vector2:
	var v: Vector2 = p - CENTER
	if v.length() < 0.001:
		return Vector2(SRC.x * 0.5, 0.0)
	var lam: float = atan2(v.x, v.y)
	var sx: float = fposmod(SRC.x * 0.5 + lam / TAU * SRC.x, SRC.x)
	return Vector2(sx, clampf(colat_t(p), 0.0, 1.0) * SRC.y)


# Місцеві напрямки на дошці: південь (від центру) і схід (проти годинникової стрілки)
static func south_dir(p: Vector2) -> Vector2:
	var v: Vector2 = p - CENTER
	if v.length() < 0.001:
		return Vector2(0.0, 1.0)
	return v.normalized()


static func east_dir(p: Vector2) -> Vector2:
	var s: Vector2 = south_dir(p)
	return Vector2(s.y, -s.x)


# Вектор у місцевих осях (схід, північ) -> вектор на дошці
static func en_to_board(p: Vector2, east: float, north: float) -> Vector2:
	return east_dir(p) * east - south_dir(p) * north


# Напрямок x схід, y південь, z угору (як WorldPhysics._dir_enu) -> осі дошки (x, y екрана, z угору)
static func enu_to_board(p: Vector2, d: Vector3) -> Vector3:
	var xy: Vector2 = east_dir(p) * d.x + south_dir(p) * d.y
	return Vector3(xy.x, xy.y, d.z)

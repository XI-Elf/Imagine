extends RefCounted
## Кукла героя для инвентаря: фигура в полный рост спереди, рисуется кодом слоями
## (контур тушью, плоский цвет, одна жёсткая тень — как в комиксе). Без одежды — база:
## майка и короткие бриджи, босые ноги (Huzzah 2026-10-23). Надетые вещи (bag.equipped,
## slot -> id; вид — items.json wear.look/color) рисуются поверх в своём порядке.
## Координаты фигуры: 100 × 200, ноги внизу по центру; draw() вписывает её в rect.

const INK := Color("1d1915")
const SKIN := Color("e0b48c")
const HAIR_M := Color("5a3a24")
const HAIR_F := Color("8a3e22")
const TANK := Color("ece6d6")
const SHORTS := Color("8a6a46")
const SHADE := Color(0.12, 0.08, 0.15, 0.22)

## Слоты в порядке показа: id, подпись
static var SLOTS: Array = [["head", I18n.t("Голова")], ["body", I18n.t("Тело")], ["back", I18n.t("Плащ")], ["hands", I18n.t("Руки")], ["legs", I18n.t("Ноги")], ["feet", I18n.t("Обувь")]]

var _ci: CanvasItem
var _o: Vector2
var _s: float


## looks: slot -> {"look": String, "color": Color}
func draw(ci: CanvasItem, rect: Rect2, female: bool, looks: Dictionary) -> void:
	_ci = ci
	_s = minf(rect.size.y / 200.0, rect.size.x / 100.0)
	_o = Vector2(rect.get_center().x - 50.0 * _s, rect.end.y - 200.0 * _s)
	var cloak: Dictionary = looks.get("back", {})
	if not cloak.is_empty():
		_cloak_back(cloak["color"])
	_legs(looks.get("legs", {}), looks.get("feet", {}))
	_torso(looks.get("body", {}))
	_arms(looks.get("body", {}), looks.get("hands", {}))
	_head(female, looks.get("head", {}))
	if not cloak.is_empty():
		_cloak_front(cloak["color"])


# ---------------------------------------------------------------------
func _p(a: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in a:
		out.append(_o + Vector2(q[0], q[1]) * _s)
	return out


func _mirror(a: Array) -> Array:
	var out: Array = []
	for i in range(a.size() - 1, -1, -1):
		out.append([100.0 - a[i][0], a[i][1]])
	return out


## Плоская заливка + контур; shade — тень справа (полоса от x)
func _shape(a: Array, col: Color, shade_from: float = -1.0) -> void:
	var pts: PackedVector2Array = _p(a)
	_ci.draw_colored_polygon(pts, col)
	if shade_from >= 0.0:
		for sp in Geometry2D.intersect_polygons(pts, _p([[shade_from, -10], [110, -10], [110, 210], [shade_from, 210]])):
			_ci.draw_colored_polygon(sp, SHADE)
	pts.append(pts[0])
	_ci.draw_polyline(pts, INK, maxf(1.5, _s * 1.1), true)


func _both(a: Array, col: Color, shade: bool = false) -> void:
	_shape(a, col)
	_shape(_mirror(a), col, 50.0 if shade else -1.0)


func _line(a: Array, b: Array, w: float = 0.8, col: Color = INK) -> void:
	_ci.draw_line(_o + Vector2(a[0], a[1]) * _s, _o + Vector2(b[0], b[1]) * _s, col, maxf(1.0, w * _s))


func _ellipse(c: Array, rx: float, ry: float, col: Color, outline: bool = true) -> void:
	var pts: Array = []
	for i in 24:
		var t: float = TAU * i / 24.0
		pts.append([c[0] + cos(t) * rx, c[1] + sin(t) * ry])
	if outline:
		_shape(pts, col)
	else:
		_ci.draw_colored_polygon(_p(pts), col)


# ---------------------------------------------------------------------
# НОГИ: кожа, бриджи до колен или штаны, ступни или сапоги
const LEG := [[37, 98], [49.5, 98], [48, 130], [47, 176], [39, 176], [36.5, 130]]
const FOOT := [[38, 174], [48, 174], [49, 184], [47.5, 187], [33, 187], [33.5, 182]]
const SHORTS_L := [[36, 92], [50, 92], [50, 106], [49.5, 133], [36, 133], [35.5, 104]]
const TROUSERS_L := [[36, 92], [50, 92], [50, 106], [48.5, 178], [38, 178], [35.5, 104]]
const BOOT_L := [[37.5, 150], [48.5, 150], [48.5, 176], [50, 188], [32, 188], [32.5, 181], [37.5, 176]]


func _legs(legs: Dictionary, feet: Dictionary) -> void:
	_both(LEG, SKIN, true)
	_both(FOOT, SKIN)
	if legs.is_empty():
		_both(SHORTS_L, SHORTS, true)
		_line([43, 128], [43, 133], 0.6)
		_line([57, 128], [57, 133], 0.6)
	else:
		_both(TROUSERS_L, legs["color"], true)
		_line([43, 140], [42.5, 170], 0.5, Color(INK, 0.5))
		_line([57, 140], [57.5, 170], 0.5, Color(INK, 0.5))
	if not feet.is_empty():
		_both(BOOT_L, feet["color"], true)
		_line([37.5, 156], [48.5, 156], 0.8)
		_line([51.5, 156], [62.5, 156], 0.8)


# ---------------------------------------------------------------------
# ТУЛОВИЩЕ: майка или рубаха/куртка
const TORSO := [[35, 42], [65, 42], [64, 70], [62, 94], [38, 94], [36, 70]]


func _torso(body: Dictionary) -> void:
	_shape(TORSO, SKIN, 52.0)
	match String(body.get("look", "")):
		"":
			# майка на узких лямках
			_shape([[39, 44], [43, 44], [44, 53], [56, 53], [57, 44], [61, 44], [63, 70], [62, 96], [38, 96], [37, 70]], TANK, 52.0)
			_line([40, 80], [44, 82], 0.5, Color(INK, 0.4))
		"shirt":
			_shape([[34, 41], [45, 40], [50, 47], [55, 40], [66, 41], [65, 70], [64, 100], [36, 100], [35, 70]], body["color"], 52.0)
			_line([50, 47], [50, 62], 0.7)
			_line([44, 98], [46, 92], 0.5, Color(INK, 0.4))
		"jacket":
			_shape([[33, 40], [45, 39], [50, 52], [55, 39], [67, 40], [66, 70], [66, 104], [34, 104], [34, 70]], body["color"], 52.0)
			_shape([[45, 39], [50, 52], [47, 58], [42, 42]], Color(body["color"]).darkened(0.25))
			_shape([[55, 39], [50, 52], [53, 58], [58, 42]], Color(body["color"]).darkened(0.25))
			_line([50, 52], [50, 104], 0.9)
			for y in [64, 76, 88]:
				_ellipse([52.5, y], 1.1, 1.1, Color("c9a24b"), false)
			_shape([[34, 92], [66, 92], [66, 96], [34, 96]], Color(body["color"]).darkened(0.4))


# ---------------------------------------------------------------------
# РУКИ: голые, рукава рубахи/куртки, рукавицы
const ARM := [[35, 43], [29, 47], [26, 74], [25, 100], [31, 101], [33, 76], [37, 56]]
const SLEEVE := [[35, 41], [28, 46], [25, 74], [24, 99], [32, 100], [34, 76], [38, 56]]
const HAND := [[24, 100], [32, 100], [32.5, 108], [29, 112], [24.5, 110], [23.5, 104]]
const GLOVE := [[23.5, 97], [32.5, 97], [33, 108], [29, 113], [24, 111], [23, 104]]


func _arms(body: Dictionary, hands: Dictionary) -> void:
	_both(ARM, SKIN, true)
	if not body.is_empty():
		var c: Color = body["color"]
		_both(SLEEVE, c, true)
		_line([24, 96], [32, 97], 0.8)
		_line([68, 97], [76, 96], 0.8)
	_both(HAND, SKIN)
	if not hands.is_empty():
		_both(GLOVE, hands["color"])
		_line([23.5, 101], [32.5, 101], 0.6)
		_line([67.5, 101], [76.5, 101], 0.6)


# ---------------------------------------------------------------------
# ГОЛОВА: шея, лицо, волосы, головной убор
func _head(female: bool, head: Dictionary) -> void:
	_shape([[45.5, 30], [54.5, 30], [55, 43], [45, 43]], SKIN, 51.0)
	var hair: Color = HAIR_F if female else HAIR_M
	_ellipse([50, 22], 10.5, 12.5, SKIN)
	_ci.draw_colored_polygon(_p([[51, 10], [60.5, 18], [60, 30], [55, 33]]), SHADE)
	# лицо
	_ellipse([46, 23], 1.1, 1.3, INK, false)
	_ellipse([54, 23], 1.1, 1.3, INK, false)
	_line([43.5, 19.5], [47.5, 19], 0.7)
	_line([52.5, 19], [56.5, 19.5], 0.7)
	_line([50, 24], [49, 28], 0.6)
	_line([47.5, 30.5], [52.5, 30.5], 0.6)
	var look: String = String(head.get("look", ""))
	if look != "cap":
		if female:
			_shape([[38.5, 30], [39, 12], [50, 8], [61, 12], [61.5, 30], [59.5, 31], [58.5, 16], [50, 13], [41.5, 16], [40.5, 31]], hair)
			_ellipse([50, 8], 4.5, 3.5, hair)
		else:
			_shape([[39.5, 21], [40, 13], [46, 9], [55, 9], [60, 13], [60.5, 21], [57, 15], [52, 16], [47, 13], [43, 16]], hair)
	match look:
		"straw_hat":
			_ellipse([50, 13], 22, 4.5, head["color"])
			_shape([[41, 13], [44, 4], [50, 1.5], [56, 4], [59, 13]], head["color"], 52.0)
			_shape([[41.5, 10], [58.5, 10], [58.8, 12.5], [41.2, 12.5]], Color("9a3a2a"))
		"cap":
			_shape([[38.5, 18], [39, 10], [45, 4.5], [55, 4.5], [61, 10], [61.5, 18], [50, 16]], head["color"], 52.0)
			_line([39.5, 15], [60.5, 15], 0.6, Color(INK, 0.5))


# ---------------------------------------------------------------------
# ПЛАЩ: полотнище за спиной и накидка на плечах
func _cloak_back(c: Color) -> void:
	_shape([[33, 40], [67, 40], [76, 120], [80, 168], [66, 165], [50, 170], [34, 165], [20, 168], [24, 120]], Color(c).darkened(0.2))


func _cloak_front(c: Color) -> void:
	_shape([[33, 39], [42, 37], [50, 44], [58, 37], [67, 39], [71, 52], [64, 58], [56, 54], [50, 58], [44, 54], [36, 58], [29, 52]], c, 56.0)
	_ellipse([50, 45], 2.2, 2.2, Color("c9a24b"))

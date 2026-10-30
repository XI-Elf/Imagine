extends CanvasLayer
## Карта героя на M (пункт 11, Huzzah 2026-10-29): у кожного персонажа є лист пергаменту й вуглик (Trade.KIT).
## Пергамент — основа карти: гравець малює на ньому мишею сам (ЛКМ — вуглик, Shift+ЛКМ або «Ластик» — стерти),
## а куплені в торговців «Отрывки карты» прикладаються до пергаменту: шматок топографічної карти довкола героя.
## Набір кольорових вугликів (купується) дає кольори. Позначку героя видно лише за Картографії вище SELF_MARK_SKILL.
## ПКМ — тягнути аркуш, колесо — масштаб, M або Esc — закрити. Поки карта відкрита, час стоїть.
## Стан (to_dict) зберігається разом із героєм (cast.gd): штрихи й обривки в метрах дошки, тож намальоване
## збігається з місцями. Числа [ВРЕМЕННО].
## Huzzah 2026-10-30: ластик стирає лише ділянку під собою; намальоване розпізнається й за Умом і Чутьём героя
## підправляється до вигляду карти (world/map_sketch.gd); окремий аркуш на кожну область, де герой побував,
## край області — легкий пунктир (world/area_outline.gd); у новій області з'являється її обрис.

const Trade := preload("res://city/trade.gd")
const Sketch := preload("res://world/map_sketch.gd")
const Outline := preload("res://world/area_outline.gd")

const SELF_MARK_SKILL: int = 50
const FRAGMENT_R_M: float = 6000.0
const FRAGMENT_JITTER_M: float = 1500.0
const MAX_POINTS: int = 60000           # межа точок у всіх штрихах (розмір збереження)
const ZOOM_MIN: float = 0.004           # пікселів на метр
const ZOOM_MAX: float = 0.4
const COLORS: Dictionary = {
	"black": Color(0.12, 0.1, 0.09), "red": Color(0.62, 0.16, 0.12), "ochre": Color(0.72, 0.5, 0.16),
	"green": Color(0.2, 0.42, 0.22), "blue": Color(0.18, 0.3, 0.55)}
const PAPER := Color(0.86, 0.78, 0.62)
const PAPER_DARK := Color(0.62, 0.5, 0.34)
const BORDER := Color(0.35, 0.25, 0.15, 0.55)
const ERASE_PX: float = 10.0
const AREA_CHECK_S: float = 0.5

signal area_added(id: int)

signal closed

var game: Node2D
var strokes: Array = []      # штрихи поточного аркуша: {c: колір, w: товщина px, pts: [x0, y0, …] метри, k: вид, q: доведення, m: знаки}
var fragments: Array = []    # {x, y, r} — прикладені обривки карти
var sheets: Dictionary = {}  # "номер області" -> {strokes: [...], view: [x, y, z]}; "0" — аркуш без області
var areas: Array = []        # області, де герой побував, у порядку відвідин
var area: int = 0            # чий аркуш зараз розгорнуто
var view_c := Vector2.INF    # центр аркуша в метрах
var view_z: float = 0.03
var color: String = "black"
var width: float = 3.0
var erasing: bool = false

var _root: Control
var _sheet: Control
var _bar: HBoxContainer
var _hint: Label
var _color_btns: Dictionary = {}
var _cur: Array = []         # штрих, що зараз малюється
var _drawing: bool = false
var _panning: bool = false
var _was_paused: bool = false
var _topo: Texture2D
var _area_pick: OptionButton
var _area_t: float = 0.0


func setup(g: Node2D) -> void:
	game = g
	layer = 30
	visible = false
	_build()
	show_area(0)


func is_open() -> bool:
	return visible


func _hero() -> Dictionary:
	if game == null or game.get("cast") == null:
		return {}
	return game.cast.hero


func _bag() -> Dictionary:
	return game.cast._inventory() if game != null and game.get("cast") != null else {}


func has_colors() -> bool:
	return Trade.count(_bag(), "color_charcoals") > 0


func cartography() -> int:
	var h: Dictionary = _hero()
	return int(h["actor"].skill("cartography")) if not h.is_empty() else 0


func shows_self() -> bool:
	return cartography() > SELF_MARK_SKILL


func open() -> void:
	var bag: Dictionary = _bag()
	Trade.ensure_kit(bag)
	var h: Dictionary = _hero()
	var at: Vector2 = h["pos"] if not h.is_empty() else game.cam_pos
	note_area(at)
	var here: int = area_at(at)
	if here > 0 or areas.is_empty():
		show_area(here)
	if view_c == Vector2.INF:
		view_c = at
	var added: int = apply_fragments(at)
	if game.clock != null:
		_was_paused = game.clock.paused
		game.clock.paused = true
	if game.get("cast") != null:
		game.cast.hold_hero = true
	visible = true
	_refresh_areas()
	_refresh_bar()
	if added > 0:
		_hint.text = I18n.t("Приложил к пергаменту отрывков карты: %d") % added
	_sheet.queue_redraw()


func close() -> void:
	if not visible:
		return
	_finish_stroke()
	visible = false
	if game.clock != null:
		game.clock.paused = _was_paused
	if game.get("cast") != null:
		game.cast.hold_hero = false
	closed.emit()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


## Куплені обривки з сумки лягають на пергамент довкола місця, де герой зараз
func apply_fragments(at: Vector2) -> int:
	var bag: Dictionary = _bag()
	var n: int = Trade.count(bag, "map_fragment")
	if n <= 0:
		return 0
	var rng := RandomNumberGenerator.new()
	rng.seed = int(at.x) * 7919 + int(at.y) + fragments.size()
	for i in n:
		var off := Vector2.from_angle(rng.randf() * TAU) * rng.randf() * FRAGMENT_JITTER_M * (1.0 + i)
		fragments.append({"x": at.x + off.x, "y": at.y + off.y, "r": FRAGMENT_R_M * rng.randf_range(0.8, 1.15), "seed": rng.randi()})
	Trade.add(bag, "map_fragment", -n)
	return n


# =====================================================================
# ОБЛАСТІ Й АРКУШІ
# =====================================================================
func area_at(p: Vector2) -> int:
	return int(game.province_at(p)) if game != null and game.has_method("province_at") else 0


func area_name(id: int) -> String:
	var n: String = String(game.province_name(id)) if id > 0 and game != null and game.has_method("province_name") else ""
	return n if n != "" else I18n.t("Без области")


## Герой зайшов в область — на пергаменті з'являється її аркуш з обрисом краю. true, якщо область нова
func note_area(p: Vector2) -> bool:
	var id: int = area_at(p)
	if id <= 0 or id in areas:
		return false
	areas.append(id)
	_sheet_of(id)
	area_added.emit(id)
	return true


func _sheet_of(id: int) -> Dictionary:
	var k: String = str(id)
	if not sheets.has(k):
		sheets[k] = {"strokes": [], "view": []}
	return sheets[k]


## Розгорнути аркуш області id: свої штрихи, свій вигляд; уперше — уся область на аркуші
func show_area(id: int) -> void:
	_finish_stroke()
	if sheets.has(str(area)) and view_c != Vector2.INF:
		sheets[str(area)]["view"] = [view_c.x, view_c.y, view_z]
	area = id
	var sh: Dictionary = _sheet_of(id)
	strokes = sh["strokes"]
	var v: Array = sh.get("view", [])
	if v.size() == 3:
		view_c = Vector2(float(v[0]), float(v[1]))
		view_z = clampf(float(v[2]), ZOOM_MIN, ZOOM_MAX)
	else:
		fit_area()
	if _sheet != null:
		_refresh_areas()
		_sheet.queue_redraw()


func area_bounds(id: int) -> Rect2:
	if id <= 0 or game == null or game.get("province_img") == null:
		return Rect2()
	return Outline.bounds(game.province_img, id, game.MAP_SIZE)


func area_loops(id: int) -> Array:
	if id <= 0 or game == null or game.get("province_img") == null:
		return []
	return Outline.loops(game.province_img, id, game.MAP_SIZE)


func _sheet_size() -> Vector2:
	if _sheet != null and _sheet.size.x > 10.0:
		return _sheet.size
	var vs: Vector2 = get_viewport().get_visible_rect().size if get_viewport() != null else Vector2(1280, 720)
	return vs - Vector2(96, 130)


## Уся область на аркуші з невеликим полем
func fit_area() -> void:
	var b: Rect2 = area_bounds(area)
	if b.size.x <= 0.0:
		return
	var ss: Vector2 = _sheet_size()
	view_c = b.get_center()
	view_z = clampf(minf(ss.x / b.size.x, ss.y / b.size.y) * 0.9, ZOOM_MIN, ZOOM_MAX)


func _refresh_areas() -> void:
	if _area_pick == null:
		return
	_area_pick.clear()
	var ids: Array = areas.duplicate()
	if (ids.is_empty() or area == 0) and not (0 in ids):
		ids.push_front(0)
	for id in ids:
		_area_pick.add_item(area_name(id), id)
		if id == area:
			_area_pick.select(_area_pick.item_count - 1)
	_area_pick.disabled = _area_pick.item_count < 2


func _on_area_picked(idx: int) -> void:
	show_area(_area_pick.get_item_id(idx))
	_refresh_bar()


func _process(delta: float) -> void:
	_area_t += delta
	if _area_t < AREA_CHECK_S:
		return
	_area_t = 0.0
	var h: Dictionary = _hero()
	if not h.is_empty() and note_area(h["pos"]) and visible:
		_refresh_areas()


func point_count() -> int:
	var n: int = 0
	for s in strokes:
		n += s["pts"].size() / 2
	return n


# =====================================================================
# ЕКРАН
# =====================================================================
func _sheet_rect() -> Rect2:
	return Rect2(Vector2.ZERO, _sheet.size)


func to_screen(p: Vector2) -> Vector2:
	return (p - view_c) * view_z + _sheet.size * 0.5


func to_world(sp: Vector2) -> Vector2:
	return view_c + (sp - _sheet.size * 0.5) / view_z


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.04, 0.03, 0.85)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	_sheet = Control.new()
	_sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sheet.offset_left = 48
	_sheet.offset_top = 40
	_sheet.offset_right = -48
	_sheet.offset_bottom = -90
	_sheet.clip_contents = true
	_sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	_sheet.draw.connect(_draw_sheet)
	_sheet.gui_input.connect(_on_sheet_input)
	_root.add_child(_sheet)
	_bar = HBoxContainer.new()
	_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_bar.offset_top = -80
	_bar.offset_bottom = -44
	_bar.offset_left = 48
	_bar.offset_right = -48
	_bar.add_theme_constant_override("separation", 8)
	_root.add_child(_bar)
	_area_pick = OptionButton.new()
	_area_pick.custom_minimum_size = Vector2(180, 36)
	_area_pick.tooltip_text = I18n.t("Лист области: на каждую область, где побывал герой, свой лист")
	_area_pick.item_selected.connect(_on_area_picked)
	_bar.add_child(_area_pick)
	for k in COLORS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(44, 36)
		b.tooltip_text = I18n.t("Уголёк") if k == "black" else I18n.t("Цветной уголь (нужен набор цветных углей)")
		var sb := StyleBoxFlat.new()
		sb.bg_color = COLORS[k]
		sb.set_corner_radius_all(4)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.pressed.connect(func(): color = k; erasing = false; _refresh_bar())
		_bar.add_child(b)
		_color_btns[k] = b
	_bar.add_child(_mk_btn(I18n.t("Тонко"), func(): width = 2.0; _refresh_bar()))
	_bar.add_child(_mk_btn(I18n.t("Жирно"), func(): width = 5.0; _refresh_bar()))
	_bar.add_child(_mk_btn(I18n.t("Ластик"), func(): erasing = not erasing; _refresh_bar()))
	_bar.add_child(_mk_btn(I18n.t("К герою"), _center_on_hero))
	_bar.add_child(_mk_btn(I18n.t("Закрыть  [M]"), close))
	_hint = Label.new()
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -40
	_hint.offset_left = 48
	_hint.add_theme_color_override("font_color", Color(0.9, 0.82, 0.62))
	_hint.add_theme_font_size_override("font_size", 15)
	_root.add_child(_hint)


func _mk_btn(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(0, 36)
	b.pressed.connect(cb)
	return b


func _refresh_bar() -> void:
	var col: bool = has_colors()
	for k in _color_btns:
		var b: Button = _color_btns[k]
		b.disabled = k != "black" and not col
		b.modulate = Color(1, 1, 1, 1.0 if not b.disabled else 0.3)
		b.text = "●" if k == color and not erasing else ""
	if color != "black" and not col:
		color = "black"
	var tips: PackedStringArray = [area_name(area), I18n.t("ЛКМ — рисовать углём, Shift+ЛКМ — стереть, ПКМ — двигать лист, колесо — масштаб")]
	if not col:
		tips.append(I18n.t("цветные угли продаёт торговец"))
	tips.append(I18n.t("Картография %d") % cartography() + ("" if shows_self() else I18n.t(" (выше %d — видно, где вы)") % SELF_MARK_SKILL))
	_hint.text = "   ·   ".join(tips) + (I18n.t("   ·   ЛАСТИК") if erasing else "")


func _center_on_hero() -> void:
	var h: Dictionary = _hero()
	if not h.is_empty():
		var id: int = area_at(h["pos"])
		if id != area and (id in areas):
			show_area(id)
		view_c = h["pos"]
	_refresh_bar()
	_sheet.queue_redraw()


# =====================================================================
# МАЛЮВАННЯ МИШЕЮ
# =====================================================================
func _on_sheet_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if erasing or mb.shift_pressed:
					erase_at(mb.position)
				else:
					begin_stroke(mb.position)
			else:
				_finish_stroke()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_panning = mb.pressed
		elif mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var before: Vector2 = to_world(mb.position)
			view_z = clampf(view_z * (1.25 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 0.8), ZOOM_MIN, ZOOM_MAX)
			view_c += before - to_world(mb.position)
			_sheet.queue_redraw()
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		if _panning:
			view_c -= mm.relative / view_z
			_sheet.queue_redraw()
		elif _drawing:
			stroke_to(mm.position)
		elif (erasing or mm.shift_pressed) and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			erase_at(mm.position)


func begin_stroke(sp: Vector2) -> void:
	if point_count() >= MAX_POINTS:
		_hint.text = I18n.t("На пергаменте нет места: сотрите лишнее")
		return
	_drawing = true
	var w: Vector2 = to_world(sp)
	_cur = [w.x, w.y]
	strokes.append({"c": color, "w": width, "pts": _cur})
	_sheet.queue_redraw()


func stroke_to(sp: Vector2) -> void:
	if not _drawing:
		return
	var w: Vector2 = to_world(sp)
	var last := Vector2(_cur[-2], _cur[-1])
	if (w - last).length() * view_z < 3.0:
		return   # точки ближче 3 px не пишемо
	_cur.append(w.x)
	_cur.append(w.y)
	_sheet.queue_redraw()


func _finish_stroke() -> void:
	if not _drawing:
		return
	_drawing = false
	if _cur.size() < 4:
		_cur.append(_cur[0] + 1.0 / view_z)
		_cur.append(_cur[1])
	# Малювання вчить картографії: що довший штрих, то більше досвіду
	var h: Dictionary = _hero()
	if not h.is_empty():
		h["actor"].add_xp("cartography", minf(_cur.size() / 40.0, 1.0) * 0.2)
	var s: Dictionary = strokes[-1] if not strokes.is_empty() and strokes[-1]["pts"] == _cur else {}
	_cur = []
	if not s.is_empty():
		var said: String = refine(s, Sketch.quality(h["actor"]) if not h.is_empty() else 0.0)
		if _hint != null and said != "":
			_hint.text = said
	_sheet.queue_redraw()


## Розпізнати штрих і підправити його за якістю q (Ум і Чутьё). Повертає підказку для гравця
func refine(s: Dictionary, q: float) -> String:
	var raw := PackedVector2Array()
	var p: Array = s["pts"]
	for i in range(0, p.size() - 1, 2):
		raw.append(Vector2(p[i], p[i + 1]))
	var info: Dictionary = Sketch.classify(raw, view_z, String(s.get("c", "black")), game)
	var res: Dictionary = Sketch.tidy(raw, info, q, view_z, game, raw.size() * 31 + int(raw[0].x))
	var flat: Array = []
	for v in res["pts"]:
		flat.append(v.x)
		flat.append(v.y)
	if flat.size() >= 4:
		s["pts"] = flat
	s["k"] = String(info["k"])
	s["q"] = snappedf(q, 0.01)
	s["m"] = res["m"]
	var a: Object = _hero()["actor"] if not _hero().is_empty() else null
	var nm: String = Sketch.kind_name(String(info["k"]))
	if q < 0.2 or a == null:
		return I18n.t("Похоже на: %s") % nm
	return I18n.t("Похоже на: %s — рука подправила (Ум %d, Чутьё %d)") % [nm, int(a.stat("int")), int(a.stat("per"))]


func erase_at(sp: Vector2) -> void:
	if erase_world(to_world(sp), ERASE_PX / view_z):
		_sheet.queue_redraw()


## Ластик стирає лише ділянку в колі r довкола w: штрих розпадається на шматки поза колом, знаки в колі зникають
func erase_world(w: Vector2, r_m: float) -> bool:
	var out: Array = []
	var changed: bool = false
	for s in strokes:
		var marks: Array = []
		for m in s.get("m", []):
			if Vector2(m["x"], m["y"]).distance_to(w) > r_m:
				marks.append(m)
		var pieces: Array = cut_circle(s["pts"], w, r_m)
		if pieces.size() == 1 and pieces[0].size() == s["pts"].size() and marks.size() == s.get("m", []).size():
			out.append(s)
			continue
		changed = true
		for i in pieces.size():
			var piece: Dictionary = s.duplicate()
			piece["pts"] = pieces[i]
			piece["m"] = marks if i == 0 else []
			out.append(piece)
		if pieces.is_empty() and not marks.is_empty():
			var rest: Dictionary = s.duplicate()
			rest["pts"] = []
			rest["m"] = marks
			out.append(rest)
	if changed:
		strokes.clear()
		strokes.append_array(out)
	return changed


## Ламана [x0, y0, x1, y1, …] без ділянки всередині кола: масив шматків (кожен щонайменше 2 точки)
static func cut_circle(p: Array, c: Vector2, r: float) -> Array:
	var pieces: Array = []
	var cur: Array = []
	var n: int = p.size() / 2
	if n == 0:
		return pieces
	var a := Vector2(p[0], p[1])
	if a.distance_to(c) > r:
		cur = [a.x, a.y]
	if n == 1:
		return [cur] if not cur.is_empty() else []
	for i in range(1, n):
		var b := Vector2(p[i * 2], p[i * 2 + 1])
		var hit: Vector2 = _circle_span(a, b, c, r)   # частка відрізка [t0, t1] у колі, або (-1, -1)
		if hit.x < 0.0:
			if cur.is_empty():
				cur = [a.x, a.y]
			cur.append(b.x)
			cur.append(b.y)
		else:
			if hit.x > 0.0:
				if cur.is_empty():
					cur = [a.x, a.y]
				var e: Vector2 = a.lerp(b, hit.x)
				cur.append(e.x)
				cur.append(e.y)
			if cur.size() >= 4:
				pieces.append(cur)
			cur = []
			if hit.y < 1.0:
				var f: Vector2 = a.lerp(b, hit.y)
				cur = [f.x, f.y, b.x, b.y]
		a = b
	if cur.size() >= 4:
		pieces.append(cur)
	return pieces


static func _circle_span(a: Vector2, b: Vector2, c: Vector2, r: float) -> Vector2:
	var d: Vector2 = b - a
	var f: Vector2 = a - c
	var A: float = d.dot(d)
	if A <= 0.0:
		return Vector2(0.0, 1.0) if f.length() <= r else Vector2(-1, -1)
	var B: float = 2.0 * f.dot(d)
	var C: float = f.dot(f) - r * r
	var disc: float = B * B - 4.0 * A * C
	if disc <= 0.0:
		return Vector2(-1, -1)
	var sq: float = sqrt(disc)
	var t0: float = (-B - sq) / (2.0 * A)
	var t1: float = (-B + sq) / (2.0 * A)
	if t1 <= 0.0 or t0 >= 1.0:
		return Vector2(-1, -1)
	return Vector2(maxf(t0, 0.0), minf(t1, 1.0))


# =====================================================================
# МАЛЮНОК АРКУША
# =====================================================================
func _draw_sheet() -> void:
	var r: Rect2 = _sheet_rect()
	_sheet.draw_rect(r, PAPER)
	# плями й волокна пергаменту (стабільні: зерно від розміру аркуша)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in 90:
		var c := Vector2(rng.randf() * r.size.x, rng.randf() * r.size.y)
		_sheet.draw_circle(c, rng.randf_range(20.0, 120.0), Color(PAPER_DARK, rng.randf_range(0.03, 0.08)))
	for f in fragments:
		_draw_fragment(f)
	for loop in area_loops(area):
		_draw_dashed(loop)
	for s in strokes:
		_draw_stroke(s)
		for m in s.get("m", []):
			_draw_mark(m)
	if shows_self():
		var h: Dictionary = _hero()
		if not h.is_empty() and (area == 0 or area_at(h["pos"]) == area):
			var hp: Vector2 = to_screen(h["pos"])
			_sheet.draw_circle(hp, 7.0, Color(0.55, 0.1, 0.08))
			_sheet.draw_arc(hp, 11.0, 0.0, TAU, 24, Color(0.55, 0.1, 0.08), 2.0)
	# обпалений край
	for k in 6:
		_sheet.draw_rect(r.grow(-k * 4.0), Color(0.3, 0.2, 0.1, 0.18 - k * 0.025), false, 5.0)


## Легкий пунктир краю області
func _draw_dashed(loop: PackedVector2Array) -> void:
	var dash: float = 9.0
	var gap: float = 7.0
	var on: bool = true
	var left: float = dash
	var r: Rect2 = _sheet_rect().grow(20.0)
	for i in range(1, loop.size()):
		var a: Vector2 = to_screen(loop[i - 1])
		var b: Vector2 = to_screen(loop[i])
		var d: float = a.distance_to(b)
		if not r.has_point(a) and not r.has_point(b) and d < 400.0:
			continue
		var t: float = 0.0
		while t < d:
			var step: float = minf(left, d - t)
			if on:
				_sheet.draw_line(a.lerp(b, t / d), a.lerp(b, (t + step) / d), BORDER, 1.5, true)
			t += step
			left -= step
			if left <= 0.0:
				on = not on
				left = dash if on else gap


## Знак карти, домальований рукою героя (world/map_sketch.gd)
func _draw_mark(m: Dictionary) -> void:
	var c: Vector2 = to_screen(Vector2(float(m["x"]), float(m["y"])))
	if not _sheet_rect().grow(30.0).has_point(c):
		return
	var k: float = clampf(float(m.get("s", 300.0)) * view_z, 4.0, 22.0) * 0.5
	var ink := Color(0.14, 0.11, 0.09, 0.85)
	match String(m.get("k", "")):
		"tree":
			_sheet.draw_line(c, c + Vector2(0, k), ink, 1.5)
			_sheet.draw_arc(c - Vector2(0, k * 0.3), k * 0.7, 0.0, TAU, 12, ink, 1.5)
		"wave":
			for row in 2:
				var o := Vector2(-k, row * k * 0.6)
				var pts := PackedVector2Array()
				for i in 7:
					pts.append(c + o + Vector2(i * k / 3.0, sin(i * PI / 3.0) * k * 0.25))
				_sheet.draw_polyline(pts, Color(COLORS["blue"], 0.8), 1.3, true)
		"peak":
			_sheet.draw_polyline(PackedVector2Array([c + Vector2(-k, k * 0.6), c + Vector2(0, -k * 0.7), c + Vector2(k, k * 0.6)]), ink, 1.6, true)
			_sheet.draw_line(c + Vector2(0, -k * 0.7), c + Vector2(k * 0.3, k * 0.6), Color(ink, 0.4), 1.0)
		"tuft":
			for i in 3:
				_sheet.draw_line(c + Vector2((i - 1) * k * 0.4, k * 0.4), c + Vector2((i - 1) * k * 0.7, -k * 0.4), ink, 1.2)
		"house":
			_sheet.draw_rect(Rect2(c - Vector2(k * 0.6, k * 0.2), Vector2(k * 1.2, k * 0.8)), ink, false, 1.4)
			_sheet.draw_polyline(PackedVector2Array([c + Vector2(-k * 0.8, -k * 0.1), c + Vector2(0, -k * 0.8), c + Vector2(k * 0.8, -k * 0.1)]), ink, 1.4)
		"cross":
			_sheet.draw_line(c - Vector2(k, k), c + Vector2(k, k), COLORS["red"], 2.0)
			_sheet.draw_line(c + Vector2(-k, k), c + Vector2(k, -k), COLORS["red"], 2.0)
		"label":
			var font: Font = ThemeDB.fallback_font
			var t: String = String(m.get("t", ""))
			var wdt: float = font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			_sheet.draw_string(font, c + Vector2(-wdt * 0.5, 16), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ink)


func _draw_stroke(s: Dictionary) -> void:
	var p: Array = s["pts"]
	if p.size() < 4:
		return
	var line := PackedVector2Array()
	for i in range(0, p.size(), 2):
		line.append(to_screen(Vector2(p[i], p[i + 1])))
	var col: Color = COLORS.get(String(s.get("c", "black")), COLORS["black"])
	_sheet.draw_polyline(line, Color(col, 0.9), float(s.get("w", 3.0)), true)


func _topo_tex() -> Texture2D:
	if _topo == null and game.get("topo_rect") != null:
		_topo = game.topo_rect.texture
	return _topo


## Обривок: шматок топографічної карти з рваним краєм, міста — крапки з назвами
func _draw_fragment(f: Dictionary) -> void:
	var tex: Texture2D = _topo_tex()
	var c := Vector2(float(f["x"]), float(f["y"]))
	var rr: float = float(f["r"])
	var rng := RandomNumberGenerator.new()
	rng.seed = int(f.get("seed", 1))
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var n: int = 40
	for i in n:
		var a: float = TAU * i / n
		var wp: Vector2 = c + Vector2.from_angle(a) * rr * rng.randf_range(0.82, 1.0)
		pts.append(to_screen(wp))
		uvs.append(Vector2(wp.x / game.MAP_SIZE.x, wp.y / game.MAP_SIZE.y))
	if tex != null:
		_sheet.draw_colored_polygon(pts, Color(1.0, 0.94, 0.82, 0.92), uvs, tex)
	else:
		_sheet.draw_colored_polygon(pts, Color(0.8, 0.72, 0.55))
	pts.append(pts[0])
	_sheet.draw_polyline(pts, Color(0.35, 0.25, 0.15, 0.7), 2.0)
	var st: Node = game.get("settlements")
	if st == null:
		return
	var font: Font = ThemeDB.fallback_font
	for s in st.list:
		var sc: Vector2 = s["_center"]
		if sc.distance_to(c) > rr * 0.8:
			continue
		var sp: Vector2 = to_screen(sc)
		_sheet.draw_circle(sp, 5.0, Color(0.15, 0.1, 0.08))
		_sheet.draw_string(font, sp + Vector2(8, 5), String(s.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.15, 0.1, 0.08))


# =====================================================================
# КЛАВІШІ
# =====================================================================
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_M or event.is_action_pressed("ui_cancel"):
			close()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and not (event.physical_keycode in [KEY_F1, KEY_F10]):
		get_viewport().set_input_as_handled()   # поки відкрито — герой не ходить; F1 і F10 працюють


# =====================================================================
# ЗБЕРЕЖЕННЯ
# =====================================================================
func to_dict() -> Dictionary:
	if visible and view_c != Vector2.INF:
		_sheet_of(area)["view"] = [view_c.x, view_c.y, view_z]
	return {"sheets": sheets.duplicate(true), "areas": areas.duplicate(), "area": area, "fragments": fragments.duplicate(true)}


func load_dict(d: Dictionary) -> void:
	sheets = {}
	areas = []
	for id in d.get("areas", []):
		if int(id) > 0 and not (int(id) in areas):
			areas.append(int(id))
	var src: Dictionary = d.get("sheets", {}) if d.get("sheets", {}) is Dictionary else {}
	for k in src:
		var sh: Dictionary = src[k] if src[k] is Dictionary else {}
		var v: Array = sh.get("view", []) if sh.get("view", []) is Array else []
		_sheet_of(int(k))["strokes"] = _clean_strokes(sh.get("strokes", []))
		sheets[str(int(k))]["view"] = v.duplicate()
	# Збереження до 2026-10-30: один аркуш на весь світ — штрихи розходяться по аркушах своїх областей
	if d.has("strokes"):
		for s in _clean_strokes(d.get("strokes", [])):
			var p: Array = s["pts"]
			var id: int = area_at(Vector2(p[0], p[1])) if p.size() >= 2 else 0
			_sheet_of(id)["strokes"].append(s)
			if id > 0 and not (id in areas):
				areas.append(id)
	fragments = d.get("fragments", []).duplicate(true)
	area = -1
	var want: int = int(d.get("area", areas[0] if not areas.is_empty() else 0))
	var old_view: Array = d.get("view", [])
	if old_view.size() == 3 and not d.has("sheets"):
		_sheet_of(want)["view"] = old_view.duplicate()
	view_c = Vector2.INF
	show_area(want)


static func _clean_strokes(src: Variant) -> Array:
	var out: Array = []
	if not (src is Array):
		return out
	for s in src:
		if s is Dictionary and s.get("pts", []) is Array:
			var st: Dictionary = {"c": String(s.get("c", "black")), "w": float(s.get("w", 3.0)), "pts": Array(s["pts"])}
			if s.has("k"):
				st["k"] = String(s["k"])
				st["q"] = float(s.get("q", 0.0))
			var marks: Array = []
			for m in s.get("m", []):
				if m is Dictionary and m.has("x") and m.has("y"):
					marks.append(m.duplicate())
			st["m"] = marks
			out.append(st)
	return out


func clear() -> void:
	sheets = {}
	areas = []
	area = -1
	fragments = []
	view_c = Vector2.INF
	show_area(0)

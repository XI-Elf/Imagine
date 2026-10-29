extends CanvasLayer
## Карта героя на M (пункт 11, Huzzah 2026-10-29): у кожного персонажа є лист пергаменту й вуглик (Trade.KIT).
## Пергамент — основа карти: гравець малює на ньому мишею сам (ЛКМ — вуглик, Shift+ЛКМ або «Ластик» — стерти),
## а куплені в торговців «Отрывки карты» прикладаються до пергаменту: шматок топографічної карти довкола героя.
## Набір кольорових вугликів (купується) дає кольори. Позначку героя видно лише за Картографії вище SELF_MARK_SKILL.
## ПКМ — тягнути аркуш, колесо — масштаб, M або Esc — закрити. Поки карта відкрита, час стоїть.
## Стан (to_dict) зберігається разом із героєм (cast.gd): штрихи й обривки в метрах дошки, тож намальоване
## збігається з місцями. Числа [ВРЕМЕННО].

const Trade := preload("res://city/trade.gd")

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

signal closed

var game: Node2D
var strokes: Array = []      # {c: колір, w: товщина px, pts: [x0, y0, x1, y1, …] метри}
var fragments: Array = []    # {x, y, r} — прикладені обривки карти
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


func setup(g: Node2D) -> void:
	game = g
	layer = 30
	visible = false
	_build()


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
	if view_c == Vector2.INF:
		view_c = at
	var added: int = apply_fragments(at)
	if game.clock != null:
		_was_paused = game.clock.paused
		game.clock.paused = true
	if game.get("cast") != null:
		game.cast.hold_hero = true
	visible = true
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
	var tips: PackedStringArray = [I18n.t("ЛКМ — рисовать углём, Shift+ЛКМ — стереть, ПКМ — двигать лист, колесо — масштаб")]
	if not col:
		tips.append(I18n.t("цветные угли продаёт торговец"))
	tips.append(I18n.t("Картография %d") % cartography() + ("" if shows_self() else I18n.t(" (выше %d — видно, где вы)") % SELF_MARK_SKILL))
	_hint.text = "   ·   ".join(tips) + (I18n.t("   ·   ЛАСТИК") if erasing else "")


func _center_on_hero() -> void:
	var h: Dictionary = _hero()
	if not h.is_empty():
		view_c = h["pos"]
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
	_cur = []


func erase_at(sp: Vector2) -> void:
	var r_m: float = 10.0 / view_z
	var w: Vector2 = to_world(sp)
	var keep: Array = []
	for s in strokes:
		var hit: bool = false
		var p: Array = s["pts"]
		for i in range(0, p.size() - 2, 2):
			var a := Vector2(p[i], p[i + 1])
			var q := Vector2(p[i + 2], p[i + 3])
			if Geometry2D.get_closest_point_to_segment(w, a, q).distance_to(w) <= r_m:
				hit = true
				break
		if not hit:
			keep.append(s)
	if keep.size() != strokes.size():
		strokes = keep
		_sheet.queue_redraw()


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
	for s in strokes:
		_draw_stroke(s)
	if shows_self():
		var h: Dictionary = _hero()
		if not h.is_empty():
			var hp: Vector2 = to_screen(h["pos"])
			_sheet.draw_circle(hp, 7.0, Color(0.55, 0.1, 0.08))
			_sheet.draw_arc(hp, 11.0, 0.0, TAU, 24, Color(0.55, 0.1, 0.08), 2.0)
	# обпалений край
	for k in 6:
		_sheet.draw_rect(r.grow(-k * 4.0), Color(0.3, 0.2, 0.1, 0.18 - k * 0.025), false, 5.0)


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
	if event is InputEventKey:
		get_viewport().set_input_as_handled()   # поки відкрито — герой не ходить


# =====================================================================
# ЗБЕРЕЖЕННЯ
# =====================================================================
func to_dict() -> Dictionary:
	return {"strokes": strokes.duplicate(true), "fragments": fragments.duplicate(true),
		"view": [view_c.x, view_c.y, view_z] if view_c != Vector2.INF else []}


func load_dict(d: Dictionary) -> void:
	strokes = []
	for s in d.get("strokes", []):
		if s is Dictionary and s.get("pts", []) is Array:
			strokes.append({"c": String(s.get("c", "black")), "w": float(s.get("w", 3.0)), "pts": Array(s["pts"])})
	fragments = d.get("fragments", []).duplicate(true)
	var v: Array = d.get("view", [])
	if v.size() == 3:
		view_c = Vector2(float(v[0]), float(v[1]))
		view_z = clampf(float(v[2]), ZOOM_MIN, ZOOM_MAX)
	else:
		view_c = Vector2.INF


func clear() -> void:
	strokes = []
	fragments = []
	view_c = Vector2.INF

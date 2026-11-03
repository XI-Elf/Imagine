extends CanvasLayer
## Карта героя — раздел единого меню (I → «Карта»), п.8–9 правок Huzzah 2026-11-03.
## Рисовать вручную больше нельзя: карта заполняется сама по мере исследования (fog — модель пройденного).
## Подробность зависит от Интеллекта героя: низкий — смутные пятна пройденного, средний — очертания местности,
## высокий — местность с названиями поселений. Метка героя видна всегда. Купленные «Отрывки карты» по-прежнему
## ложатся на лист куском топографической карты. ПКМ — двигать лист, колесо — масштаб.
## Узел остаётся CanvasLayer-хранилищем состояния; лист (_sheet) прикрепляется к окну героя через mount(host).
## Состояние (to_dict): области, где герой побывал, обрывки карты, текущая область. Старые штрихи при загрузке отбрасываются.

const Trade := preload("res://city/trade.gd")
const Outline := preload("res://world/area_outline.gd")

const FRAGMENT_R_M: float = 6000.0
const FRAGMENT_JITTER_M: float = 1500.0
const ZOOM_MIN: float = 0.004           # пикселей на метр
const ZOOM_MAX: float = 0.4
const PAPER := Color(0.86, 0.78, 0.62)
const PAPER_DARK := Color(0.62, 0.5, 0.34)
const BORDER := Color(0.35, 0.25, 0.15, 0.55)
const AREA_CHECK_S: float = 0.5
const TEX_STEP_M: float = 200.0         # метров на пиксель кэш-картинки пройденного
const REBUILD_S: float = 1.0
const INT_VAGUE: int = 4                # Интеллект ниже — только смутные пятна
const INT_DETAIL: int = 7               # Интеллект от — ещё и названия поселений

signal area_added(id: int)

signal closed

var game: Node2D
var fragments: Array = []    # {x, y, r} — приложенные обрывки карты
var sheets: Dictionary = {}  # "номер области" -> {view: [x, y, z]}; "0" — лист без области
var areas: Array = []        # области, где герой побывал, в порядке посещения
var area: int = 0            # чей лист сейчас развёрнут
var view_c := Vector2.INF    # центр листа в метрах
var view_z: float = 0.03

var mounted: bool = false
var _sheet: Control
var _bar: HBoxContainer
var _hint: Label
var _host: Control
var _col: VBoxContainer
var _topo: Texture2D
var _topo_img: Image
var _known_tex: ImageTexture
var _known_ver: int = -1
var _known_tier: int = -1
var _rebuild_t: float = 0.0
var _panning: bool = false
var _area_pick: OptionButton
var _area_t: float = 0.0


func setup(g: Node2D) -> void:
	game = g
	layer = 30
	visible = false
	show_area(0)


func is_open() -> bool:
	return mounted


func _hero() -> Dictionary:
	if game == null or game.get("cast") == null:
		return {}
	return game.cast.hero


func _bag() -> Dictionary:
	return game.cast._inventory() if game != null and game.get("cast") != null else {}


func intellect() -> int:
	var h: Dictionary = _hero()
	return int(h["actor"].stat("int")) if not h.is_empty() else 5


## Ступень подробности по Интеллекту: 0 — смутные пятна, 1 — очертания местности, 2 — ещё и названия
func detail_tier() -> int:
	var i: int = intellect()
	return 0 if i < INT_VAGUE else (1 if i < INT_DETAIL else 2)


func tier_word() -> String:
	return [I18n.t("смутно"), I18n.t("в общих чертах"), I18n.t("подробно")][detail_tier()]


## Прикрепить лист карты к host (раздел «Карта» окна героя); пока прикреплён — карта «открыта»
func mount(host: Control) -> void:
	if mounted:
		unmount()
	_host = host
	var h: Dictionary = _hero()
	var at: Vector2 = h["pos"] if not h.is_empty() else (game.cam_pos if game != null else Vector2.ZERO)
	note_area(at)
	var here: int = area_at(at)
	if here > 0 or areas.is_empty():
		show_area(here)
	if view_c == Vector2.INF:
		view_c = at
	apply_fragments(at)
	_build(host)
	mounted = true
	visible = true
	_refresh_areas()
	_refresh_hint()
	_sheet.queue_redraw()


func unmount() -> void:
	if not mounted:
		return
	_save_view()
	mounted = false
	visible = false
	_panning = false
	if is_instance_valid(_col):
		_col.get_parent().remove_child(_col)
		_col.free()
	_col = null
	_sheet = null
	_bar = null
	_hint = null
	_area_pick = null
	closed.emit()


func _save_view() -> void:
	if view_c != Vector2.INF:
		_sheet_of(area)["view"] = [view_c.x, view_c.y, view_z]


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
		sheets[k] = {"view": []}
	return sheets[k]


## Розгорнути аркуш області id: свої штрихи, свій вигляд; уперше — уся область на аркуші
func show_area(id: int) -> void:
	if sheets.has(str(area)) and view_c != Vector2.INF:
		sheets[str(area)]["view"] = [view_c.x, view_c.y, view_z]
	area = id
	var sh: Dictionary = _sheet_of(id)
	var v: Array = sh.get("view", [])
	if v.size() == 3:
		view_c = Vector2(float(v[0]), float(v[1]))
		view_z = clampf(float(v[2]), ZOOM_MIN, ZOOM_MAX)
	else:
		fit_area()
	if _sheet != null:
		_refresh_areas()
		_refresh_hint()
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
	_refresh_hint()


func _process(delta: float) -> void:
	_rebuild_t += delta
	if mounted and _sheet != null and _rebuild_t >= REBUILD_S:
		_rebuild_t = 0.0
		if _fog_changed():
			_sheet.queue_redraw()
	_area_t += delta
	if _area_t < AREA_CHECK_S:
		return
	_area_t = 0.0
	var h: Dictionary = _hero()
	if not h.is_empty() and note_area(h["pos"]) and mounted:
		_refresh_areas()


# =====================================================================
# ЛИСТ
# =====================================================================
func _sheet_rect() -> Rect2:
	return Rect2(Vector2.ZERO, _sheet.size)


func to_screen(p: Vector2) -> Vector2:
	return (p - view_c) * view_z + _sheet.size * 0.5


func to_world(sp: Vector2) -> Vector2:
	return view_c + (sp - _sheet.size * 0.5) / view_z


func _build(host: Control) -> void:
	var col := VBoxContainer.new()
	_col = col
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 6)
	host.add_child(col)
	_bar = HBoxContainer.new()
	_bar.add_theme_constant_override("separation", 8)
	col.add_child(_bar)
	_area_pick = OptionButton.new()
	_area_pick.custom_minimum_size = Vector2(180, 32)
	_area_pick.tooltip_text = I18n.t("Лист области: на каждую область, где побывал герой, свой лист")
	_area_pick.item_selected.connect(_on_area_picked)
	_bar.add_child(_area_pick)
	var b := Button.new()
	b.text = I18n.t("К герою")
	b.custom_minimum_size = Vector2(0, 32)
	b.pressed.connect(_center_on_hero)
	_bar.add_child(b)
	_hint = Label.new()
	_hint.add_theme_color_override("font_color", Color(0.9, 0.82, 0.62))
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bar.add_child(_hint)
	_sheet = Control.new()
	_sheet.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sheet.custom_minimum_size = Vector2(300, 200)
	_sheet.clip_contents = true
	_sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	_sheet.draw.connect(_draw_sheet)
	_sheet.gui_input.connect(_on_sheet_input)
	_sheet.resized.connect(_sheet.queue_redraw)
	col.add_child(_sheet)


func _refresh_hint() -> void:
	if _hint == null:
		return
	_hint.text = "%s  ·  %s  ·  %s" % [area_name(area), I18n.t("Интеллект %d: %s") % [intellect(), tier_word()],
		I18n.t("карта заполняется сама · ПКМ — двигать, колесо — масштаб")]


func _center_on_hero() -> void:
	var h: Dictionary = _hero()
	if not h.is_empty():
		var id: int = area_at(h["pos"])
		if id != area and (id in areas):
			show_area(id)
		view_c = h["pos"]
	if _sheet != null:
		_sheet.queue_redraw()


func _on_sheet_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_LEFT:
			_panning = mb.pressed
		elif mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var before: Vector2 = to_world(mb.position)
			view_z = clampf(view_z * (1.25 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 0.8), ZOOM_MIN, ZOOM_MAX)
			view_c += before - to_world(mb.position)
			_sheet.queue_redraw()
	elif event is InputEventMouseMotion and _panning:
		view_c -= (event as InputEventMouseMotion).relative / view_z
		_sheet.queue_redraw()


# =====================================================================
# ПРОЙДЕННОЕ: кэш-картинка по туману войны
# =====================================================================
func _fog() -> Variant:
	var l: Variant = game.get("fog") if game != null else null
	return l.model if l != null and l.get("model") != null else l


func _fog_changed() -> bool:
	var f: Variant = _fog()
	if f == null:
		return false
	return f.version != _known_ver or detail_tier() != _known_tier


## Картинка пройденного: один пиксель — TEX_STEP_M метров. Ступень 0 — плоские пятна, выше — цвета местности
func build_known() -> void:
	var f: Variant = _fog()
	if f == null:
		return
	var w: int = int(ceil(f.map_size.x / TEX_STEP_M))
	var h: int = int(ceil(f.map_size.y / TEX_STEP_M))
	var tier: int = detail_tier()
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var topo: Image = _topo_image(w, h) if tier > 0 else null
	var step: int = maxi(int(TEX_STEP_M / f.CELL_M), 1)
	for y in h:
		for x in w:
			var cx: int = clampi(x * step + step / 2, 0, f.cols - 1)
			var cy: int = clampi(y * step + step / 2, 0, f.rows - 1)
			if f.cells[cy * f.cols + cx] == 0:
				continue
			var c: Color = PAPER_DARK
			if topo != null:
				c = topo.get_pixel(x, y)
				if tier == 1:
					var g: float = (c.r + c.g + c.b) / 3.0
					c = c.lerp(Color(g, g * 0.92, g * 0.75), 0.6)
			img.set_pixel(x, y, Color(c, 0.95 if tier > 0 else 0.55))
	_known_tex = ImageTexture.create_from_image(img)
	_known_ver = f.version
	_known_tier = tier


func _topo_image(w: int, h: int) -> Image:
	if _topo_img == null or _topo_img.get_width() != w:
		var tex: Texture2D = _topo_tex()
		var src: Image = tex.get_image() if tex != null else null
		if src == null or src.is_empty():
			return null
		if src.is_compressed():
			src.decompress()
		src.convert(Image.FORMAT_RGBA8)
		src.resize(w, h, Image.INTERPOLATE_BILINEAR)
		_topo_img = src
	return _topo_img


# =====================================================================
# РИСУНОК ЛИСТА
# =====================================================================
func _draw_sheet() -> void:
	var r: Rect2 = _sheet_rect()
	_sheet.draw_rect(r, PAPER)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in 90:
		var c := Vector2(rng.randf() * r.size.x, rng.randf() * r.size.y)
		_sheet.draw_circle(c, rng.randf_range(20.0, 120.0), Color(PAPER_DARK, rng.randf_range(0.03, 0.08)))
	if _fog() != null and (_known_tex == null or _fog_changed()):
		build_known()
	if _known_tex != null and _fog() != null:
		var f: Variant = _fog()
		var o: Vector2 = to_screen(Vector2.ZERO)
		_sheet.draw_texture_rect(_known_tex, Rect2(o, f.map_size * view_z), false)
	for fr in fragments:
		_draw_fragment(fr)
	for loop in area_loops(area):
		_draw_dashed(loop)
	if detail_tier() >= 2:
		_draw_known_towns()
	var h: Dictionary = _hero()
	if not h.is_empty():
		var hp: Vector2 = to_screen(h["pos"])
		_sheet.draw_circle(hp, 7.0, Color(0.55, 0.1, 0.08))
		_sheet.draw_arc(hp, 11.0, 0.0, TAU, 24, Color(0.55, 0.1, 0.08), 2.0)
	for k in 6:
		_sheet.draw_rect(r.grow(-k * 4.0), Color(0.3, 0.2, 0.1, 0.18 - k * 0.025), false, 5.0)


## Названия поселений на пройденной местности (только при высоком Интеллекте)
func _draw_known_towns() -> void:
	var st: Node = game.get("settlements") if game != null else null
	var f: Variant = _fog()
	if st == null or f == null:
		return
	var font: Font = ThemeDB.fallback_font
	for s in st.list:
		var sc: Vector2 = s["_center"]
		if not f.known(sc):
			continue
		var sp: Vector2 = to_screen(sc)
		if not _sheet_rect().grow(20.0).has_point(sp):
			continue
		_sheet.draw_circle(sp, 5.0, Color(0.15, 0.1, 0.08))
		_sheet.draw_string(font, sp + Vector2(8, 5), String(s.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.15, 0.1, 0.08))


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
# СОХРАНЕНИЕ
# =====================================================================
func to_dict() -> Dictionary:
	if mounted:
		_save_view()
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
		sheets[str(int(k))] = {"view": v.duplicate()}   # штрихи старых сохранений отбрасываются (рисования больше нет)
	fragments = d.get("fragments", []).duplicate(true)
	area = -1
	var want: int = int(d.get("area", areas[0] if not areas.is_empty() else 0))
	view_c = Vector2.INF
	show_area(want)


func clear() -> void:
	sheets = {}
	areas = []
	area = -1
	fragments = []
	view_c = Vector2.INF
	_known_tex = null
	_known_ver = -1
	show_area(0)

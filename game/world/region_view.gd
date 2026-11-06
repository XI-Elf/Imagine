extends CanvasLayer
## Огляд регіону — топографічний аркуш (Huzzah 2026-11-06: «карта регіону в топографічному стилі; дані з Місцевості
## переносити на неї вже в топографічній моделі»; до цього був 2.5D-малюнок із деревами й горами-спрайтами).
## Регіон (область з кольоровою межею, map_provinces.png) — на один екран, строго згори. Основа — затверджена топокарта світу
## (art/map/map_topo_clean.png = map_topo.png без запечених підписів, tools/make_topo_clean.py), дані гри її уточнюють:
##  • рельєф -> горизонталі (звичайні тонкі, основні потовщені й підписані), гіпсометричне забарвлення, світлотінь,
##    висотні відмітки на вершинах (world/region_topo.gd: SHADER і розрахунок відміток) — висоти ті самі, що ведуть героя в гору;
##  • вода -> берегова лінія, мілина, ріки; біоми -> умовні знаки (дерево листяне/хвойне, купини болота, крапки пустки),
##    штрих проклятих земель, червоний штрих спекотних гір;
##  • поселення -> як на справжніх топокартах: узагальнений знак забудови в реальних метрах плану міста на поточному етапі росту
##    (чорні квартали, вулиці, стіна частоколом чи каменем, вежі, брама, городи), органічна основа з settlement_ground.gd,
##    будинки наступного етапу — пунктиром (будівництво); на загальному плані знак лише збільшується до читабельного розміру;
##  • дороги й тропи -> протоптані стежки героя (trails) тонкою бордовою лінією; руїни, сигнальні вежі й техноостови — умовні знаки;
##  • туман війни -> «біла пляма»: невідоме не малюється взагалі (ні горизонталей, ні знаків), а не закрите хмарами зверху;
##  • рамка листа з кілометровою сіткою, масштабна лінійка, легенда умовних знаків (L).
## Живе: місто росте разом зі станом міста (кожне зідане завдання — нові будинки), руїни після обшуку тьмяніють, тропи
## протоптуються, біла пляма відступає там, де пройшов герой, знак героя — де він зараз. Стан перевіряється раз на CHECK_S
## секунд, перебудова — лише коли щось змінилося; закритий огляд не коштує нічого, через RELEASE_S секунд усе вивантажується.
## Відкрити: V на загальній карті (game.gd) або просмотрщик регіонів (region_viewer.tscn).
## Керування: колесо — масштаб до курсора, ЛКМ-перетягування або стрілки — зсув, клік по сусідньому (приглушеному)
## регіону — перейти туди, PgUp/PgDn — попередній/наступний регіон, L — легенда, Esc або V — закрити.
## Сюжетні мітки кампанії тут навмисно не малюються.

const RegionArt := preload("res://world/region_art.gd")
const Topo := preload("res://world/region_topo.gd")
const Ruins := preload("res://world/ruins.gd")
const Growth := preload("res://city/city_growth.gd")
const Art := preload("res://storybook/art.gd")

const LAYER: int = 6               # над світом, туманом карти (1) і фільтром світу (5); під інтерфейсом (10+)
const GRADE: float = 0.22          # слабкий фільтр темного світу: лист лишається читабельним, настрій той самий
const MARGIN: float = 1.1          # запас довкола регіону при вписуванні в екран
const MAX_ZOOM: float = 4.0
const RELEASE_S: float = 90.0       # стільки секунд закритий огляд тримає в пам'яті текстури й вузли
const CHECK_S: float = 1.0         # як часто перевіряти, чи змінився світ
const REBUILD_MIN_S: float = 5.0   # не частіше перебудова через тропи й туман (місто й руїни — одразу)
const TOP_PX: float = 96.0         # згори екрана — панель часу й табличка: регіон вписується нижче
const GEO_STEP_M: float = 70.0     # крок сітки висот для відміток і підписів горизонталей
const SPOT_MIN_H: float = 140.0    # нижче цієї висоти (над низиною) відміток не ставимо
const SPOT_LIMIT: int = 22
const LABEL_LIMIT: int = 26

# Палітра аркуша (затверджена топокарта світу: art/map/map_topo.png)
const INK := Color(0.22, 0.13, 0.08)
const MAROON := Color(0.38, 0.10, 0.10)
const CREAM := Color(0.93, 0.88, 0.72)
const CYAN := Color(0.09, 0.50, 0.58)
const VIOLET := Color(0.34, 0.20, 0.44)

var game: Node2D
var art := RegionArt.new()
var region_id: int = 0
var is_open: bool = false
var standalone: bool = false        # просмотрщик регіонів: туман війни можна вимкнути, тексти інші
var fog_enabled: bool = true
var legend_on: bool = true
var build_ms: float = 0.0           # скільки тривала остання перебудова (для замірів і тесту)
var stats: Dictionary = {}          # скільки чого розставлено (тест, панель)
var fog_on: bool = false            # біла пляма зараз діє (є герой і туман війни)

var _root: Control
var _ground: ColorRect
var _ground_mat := ShaderMaterial.new()
var _static: Node2D                 # усе нерухоме: поселення, тропи, умовні знаки, рамка — у «базових» пікселях
var _live: Node2D                   # знак героя — щокадру
var _fog_tex: ImageTexture
var _fog_blank: ImageTexture
var _fog_version: int = -1
var _hud: Node2D                    # підписи, відмітки, сітка, лінійка, легенда (не масштабуються)
var _grade: ColorRect
var _info: Label
var _title: Label
var _hint: Label
var _plate: TextureRect

var _bbox := Rect2()                # регіон у метрах
var _center := Vector2.ZERO
var _fitz: float = 0.1              # пікселів на метр, коли видно весь регіон
var _uz: float = 1.0                # наближення понад це
var _cam := Vector2.ZERO            # центр огляду, метри
var _s: float = 1.0                 # масштаб значків: висота екрана / 1080

var _ops: Array = []                # що малювати в _static (у порядку шарів)
var _marks: Array = []              # знаки на місцевості: [вид, точка (метри), обшукано]
var _spots: Array = []              # висотні відмітки {pos, h}
var _clabels: Array = []            # підписи основних горизонталей {pos, angle, h}
var _labels: Array = []             # [точка (метри), назва, друга рядок, радіус стіни (метри)]
var _cities: Array = []             # {c: центр (метри), ops: знаки у метрах від центру, r: радіус стіни}
var _city_node: Node2D              # знаки поселень: власний масштаб (справжній або збільшений до мінімуму)
var _city_z: float = 0.0
var _geo: Dictionary = {}           # регіон -> {grid, spots, labels: {крок: [...]}} — рельєф не змінюється, рахується раз
var _contour: Array = [40.0, 5]
var _trails_tex: ImageTexture
var _trails_rect := Rect2()
var _trails_img: Image
var _trails_c0 := Vector2i.ZERO
var _trails_cm: float = 12.0
var _sig: String = ""
var _sig_quick: String = ""
var _check_t: float = 0.0
var _last_build_t: float = -100.0
var _dragging: bool = false
var _drag_from := Vector2.ZERO
var _drag_moved: bool = false
var _held_hero: bool = false
var _prev_hold: bool = false


func _init() -> void:
	layer = LAYER
	visible = false


func setup(g: Node2D) -> void:
	game = g


## Текстури й вузли — при першому відкритті (запуск гри не повільнішає)
func _ensure_built() -> void:
	if _root != null:
		return
	art.load_all(false)   # лише плоскі текстури (табличка); спрайтів і атласу топокарта не потребує
	_build_nodes()


func _build_nodes() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_ground = ColorRect.new()
	_ground.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ground.color = Color(0.1, 0.1, 0.1)
	_root.add_child(_ground)
	_static = Node2D.new()
	_static.draw.connect(_draw_static)
	_root.add_child(_static)
	_city_node = Node2D.new()
	_city_node.draw.connect(_draw_cities)
	_root.add_child(_city_node)
	_live = Node2D.new()
	_live.draw.connect(_draw_live)
	_root.add_child(_live)
	# Свій фільтр темного світу (той самий шейдер, слабший): огляд лежить над фільтром карти
	var WorldGrade: GDScript = load("res://ui/world_grade.gd")
	_grade = WorldGrade.rect()
	WorldGrade.set_strength(_grade, GRADE)
	_root.add_child(_grade)
	_hud = Node2D.new()
	_hud.draw.connect(_draw_hud)
	_root.add_child(_hud)
	# Табличка з назвою регіону
	_plate = TextureRect.new()
	_plate.texture = art.textures.get("title_plate")
	_plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_plate.stretch_mode = TextureRect.STRETCH_SCALE
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_plate)
	_title = _label(30, Color("e9d6a2"))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint = _label(13, Color("cfc6ae"))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info = _label(15, Color("e8dcb0"))
	_info.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM


func _label(size: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.92))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(l)
	return l


# =====================================================================
# ВІДКРИТИ / ЗАКРИТИ
# =====================================================================
## Регіон, у якому зараз герой (або камера карти)
func current_region() -> int:
	var p: Vector2 = game.cam_pos
	var cast: Node = game.get("cast")
	if cast != null and not cast.hero.is_empty():
		p = cast.hero["pos"]
	var id: int = game.province_at(p)
	return id if id > 0 else 7


func region_ids() -> Array:
	var ids: Array = []
	for k in game.map_names.get("provinces", {}):
		ids.append(int(k))
	ids.sort()
	return ids


func region_name(id: int) -> String:
	return game.province_name(id)


func open(id: int = -1) -> void:
	if id <= 0:
		id = current_region()
	_ensure_built()
	region_id = id
	is_open = true
	visible = true
	_uz = 1.0
	_ensure_ground()
	_fit()
	_cam = _center
	_rebuild()
	if game.terrain_layer != null:
		game.terrain_layer.visible = false
	var cast: Node = game.get("cast")
	if cast != null and not _held_hero:
		_prev_hold = cast.hold_hero
		cast.hold_hero = true
		_held_hero = true


func close() -> void:
	if _root == null:
		return
	is_open = false
	visible = false
	_dragging = false
	_closed_t = 0.0
	if game.terrain_layer != null:
		game.terrain_layer.visible = true
	var cast: Node = game.get("cast")
	if cast != null and _held_hero:
		cast.hold_hero = _prev_hold
		_held_hero = false


## Вивантажити все важке (стан гри не чіпає): наступний open() збирає заново
func release() -> void:
	if _root == null or is_open:
		return
	_root.queue_free()
	_root = null
	_ground = null
	_static = null
	_city_node = null
	_cities.clear()
	_live = null
	_hud = null
	_grade = null
	_info = null
	_title = null
	_hint = null
	_plate = null
	_ground_mat = ShaderMaterial.new()
	_fog_tex = null
	_fog_blank = null
	_fog_version = -1
	_trails_tex = null
	_trails_img = null
	_ops.clear()
	_marks.clear()
	_spots.clear()
	_clabels.clear()
	_labels.clear()
	_geo.clear()
	_sig = ""
	_sig_quick = ""
	_applied = -1
	art = RegionArt.new()
	_closed_t = 0.0


func toggle() -> void:
	if is_open:
		close()
	else:
		open()


func step_region(d: int) -> void:
	var ids: Array = region_ids()
	if ids.is_empty():
		return
	var i: int = ids.find(region_id)
	open(int(ids[posmod(i + d, ids.size())]))


# Межі регіону в метрах — за шаром областей (одна прохідка по картинці, кеш)
var _bbox_cache: Dictionary = {}
func region_rect(id: int) -> Rect2:
	if _bbox_cache.is_empty():
		var img: Image = game.province_img
		var w: int = img.get_width()
		var h: int = img.get_height()
		var data: PackedByteArray = img.get_data()
		var mins: Dictionary = {}
		for y in h:
			var row: int = y * w
			for x in w:
				var v: int = data[row + x]
				if v == 0:
					continue
				if not mins.has(v):
					mins[v] = [x, y, x, y]
				else:
					var m: Array = mins[v]
					if x < m[0]: m[0] = x
					if x > m[2]: m[2] = x
					if y > m[3]: m[3] = y
		var sx: float = game.MAP_SIZE.x / float(w)
		var sy: float = game.MAP_SIZE.y / float(h)
		for v in mins:
			var m: Array = mins[v]
			_bbox_cache[v] = Rect2(Vector2(m[0] * sx, m[1] * sy), Vector2((m[2] - m[0] + 1) * sx, (m[3] - m[1] + 1) * sy))
	return _bbox_cache.get(id, Rect2(Vector2.ZERO, game.MAP_SIZE))


func _fit() -> void:
	var vp: Vector2 = _root.get_viewport_rect().size
	_bbox = region_rect(region_id)
	_center = _bbox.get_center()
	_s = vp.y / 1080.0
	_fitz = minf(vp.x / (_bbox.size.x * MARGIN), (vp.y - TOP_PX * _s) / (_bbox.size.y * MARGIN))


func _zoom() -> float:
	return _fitz * _uz


## Центр огляду на екрані: трохи нижче середини (згори — панель часу й табличка)
func _sc(vp: Vector2) -> Vector2:
	return Vector2(vp.x * 0.5, (vp.y + TOP_PX * _s) * 0.5)


# =====================================================================
# ЗЕМЛЯ ЛИСТА: топошейдер читає ті самі шари, що й гра (висоти, вода, біоми, спека, області)
# =====================================================================
func _ensure_ground() -> void:
	if _ground_mat.shader != null:
		_ground.material = _ground_mat
		return
	var sh := Shader.new()
	sh.code = Topo.SHADER
	_ground_mat.shader = sh
	var rm: ShaderMaterial = game.render_mat
	for n in ["noise_tex", "height_tex", "water_tex", "biome_tex", "hot_tex", "province_tex"]:
		_ground_mat.set_shader_parameter(n, rm.get_shader_parameter(n))
	_ground_mat.set_shader_parameter("map_size", game.MAP_SIZE)
	_ground_mat.set_shader_parameter("height_max", Topo.HEIGHT_MAX_M)
	var tp: String = "res://art/map/map_topo_clean.png" if ResourceLoader.exists("res://art/map/map_topo_clean.png") else "res://art/map/map_topo.png"
	_ground_mat.set_shader_parameter("topo_tex", load(tp))
	var blank := Image.create(1, 1, false, Image.FORMAT_R8)
	blank.fill(Color(1, 1, 1, 1))
	_fog_blank = ImageTexture.create_from_image(blank)
	_ground_mat.set_shader_parameter("fog_mask", _fog_blank)
	_ground.material = _ground_mat


var _applied: int = -1
var _closed_t: float = 0.0
func _process(delta: float) -> void:
	if not is_open or game == null:
		# Закритий огляд довго не потрібен — віддаємо пам'ять (текстури, вузли); V відбудує за мить
		if _root != null and not standalone and game != null:
			_closed_t += delta
			if _closed_t >= RELEASE_S:
				release()
		return
	var vp: Vector2 = _root.get_viewport_rect().size
	var z: float = _zoom()
	var cam_c: Vector2 = _cam - (_sc(vp) - vp * 0.5) / z   # точка карти в середині екрана (для шейдера)
	_ground_mat.set_shader_parameter("cam_pos", cam_c)
	_ground_mat.set_shader_parameter("zoom", z)
	_ground_mat.set_shader_parameter("view_px", vp)
	_ground_mat.set_shader_parameter("region_id", float(region_id))
	var cs: Array = Topo.contour_steps(_uz)
	if cs != _contour:
		_contour = cs
		_refresh_labels()
	_ground_mat.set_shader_parameter("contour_m", float(cs[0]))
	_ground_mat.set_shader_parameter("index_every", float(cs[1]))
	_ground_mat.set_shader_parameter("sym_m", Topo.CELL_PX * _s / _fitz)
	_update_fog()
	# Значки — у «базових» пікселях огляду цілого регіону; зсув і наближення — лише перетворення
	var off: Vector2 = _sc(vp) + (_center - _cam) * z
	for n in [_static, _live]:
		n.position = off
		n.scale = Vector2(_uz, _uz)
	_city_node.position = off
	if absf(z - _city_z) > _city_z * 0.02:
		_city_z = z
		_city_node.queue_redraw()
	var hour: float = game.clock.hour_of_day() if game.clock != null else 12.0
	_grade.get_material().set_shader_parameter("strength", GRADE * load("res://ui/world_grade.gd").strength_at(hour))
	_live.queue_redraw()
	_hud.queue_redraw()
	_layout_hud(vp)
	_check_t += delta
	if _check_t >= CHECK_S:
		_check_t = 0.0
		_refresh_if_changed()


## Біла пляма: маска відкритого героєм (клітинки туману війни) йде в шейдер як дані, а не окремим шаром
func _update_fog() -> void:
	var fl: Node = game.get("fog")
	fog_on = fog_enabled and fl != null and fl.has_method("active") and fl.active()
	_ground_mat.set_shader_parameter("fog_on", 1.0 if fog_on else 0.0)
	if not fog_on:
		return
	if _fog_tex == null or _fog_version != fl.model.version:
		var img := Image.create_from_data(fl.model.cols, fl.model.rows, false, Image.FORMAT_R8, fl.model.cells)
		if _fog_tex == null:
			_fog_tex = ImageTexture.create_from_image(img)
			_ground_mat.set_shader_parameter("fog_mask", _fog_tex)
		else:
			_fog_tex.update(img)
		_fog_version = fl.model.version


# =====================================================================
# ЖИВЕ: що змінилось у світі
# =====================================================================
func _signature(full: bool) -> String:
	var parts: Array = [region_id]
	var st: Node = game.get("settlements")
	if st != null:
		for s in st.list:
			if not _bbox.has_point(s["_center"]):
				continue
			var plan: Dictionary = s.get("_plan", {})
			parts.append("%s:%d" % [s["id"], Growth.points(st._growth_of(s)) if Growth.has_growth(plan) else -1])
	var cast: Node = game.get("cast")
	if cast != null:
		var now: float = game.clock.total_seconds
		var k: int = 0
		for key in cast.ruins_looted:
			if Ruins.looted_now(cast.ruins_looted, key, now):
				k += 1
		parts.append("r%d" % k)
	if full:
		var tl: Node = game.get("trails")
		if tl != null:
			parts.append("t%d" % tl.model.version)
		var fl: Node = game.get("fog")
		if fl != null and fog_enabled and fl.active():
			parts.append("f%d" % fl.model.opened)
	return ",".join(parts)


func _refresh_if_changed() -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	var quick: String = _signature(false)
	# місто й руїни — одразу; тропи й біла пляма — не частіше REBUILD_MIN_S
	if quick != _sig_quick:
		_rebuild()
	elif _signature(true) != _sig and now - _last_build_t >= REBUILD_MIN_S:
		_rebuild()


## Перебудувати весь аркуш (поселення, тропи, знаки, відмітки висот)
func _rebuild() -> void:
	var t0: int = Time.get_ticks_usec()
	_fit()
	_ops.clear()
	_marks.clear()
	_labels.clear()
	stats = {"cities": 0, "buildings": 0, "scaffolds": 0, "ruins": 0, "towers": 0, "spots": 0, "contour_labels": 0, "walls": "", "contour_m": 0.0}
	_contour = Topo.contour_steps(_uz)
	_ensure_geo()
	_frame_ops()
	_place_trails()
	var blocked: Array = _place_settlements()
	_place_ruins(blocked)
	_refresh_labels()
	_sig = _signature(true)
	_sig_quick = _signature(false)
	_last_build_t = Time.get_ticks_msec() / 1000.0
	build_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	_static.queue_redraw()
	_city_z = _zoom()
	_city_node.queue_redraw()
	_update_info()


## Точка карти (метри) -> базові пікселі огляду (0 — центр регіону)
func _b(p: Vector2) -> Vector2:
	return (p - _center) * _fitz


func _inside(p: Vector2) -> bool:
	return game.province_at(p) == region_id


## Під білою плямою руїн, веж і відміток не показуємо (не підказуємо, де що)
func _seen(p: Vector2) -> bool:
	var fl: Node = game.get("fog")
	return not fog_enabled or fl == null or not fl.has_method("known") or fl.known(p)


# ---------------------------------------------------------------------
# РЕЛЬЄФ: висотні відмітки й місця підписів горизонталей (раз на регіон)
# ---------------------------------------------------------------------
func _ensure_geo() -> void:
	if _geo.has(region_id):
		return
	var step: float = maxf(GEO_STEP_M, maxf(_bbox.size.x, _bbox.size.y) / 150.0)
	var grid: Dictionary = Topo.height_grid(game, _bbox, region_id, step)
	_geo[region_id] = {
		"grid": grid,
		"spots": Topo.spot_heights(grid, SPOT_MIN_H, 1100.0, SPOT_LIMIT),
		"labels": {},
	}


## Підписи основних горизонталей для поточного кроку (кеш за кроком); під білою плямою — не показуються
func _refresh_labels() -> void:
	if not _geo.has(region_id):
		return
	var g: Dictionary = _geo[region_id]
	var idx_m: float = float(_contour[0]) * float(_contour[1])
	if not g["labels"].has(idx_m):
		g["labels"][idx_m] = Topo.contour_labels(g["grid"], idx_m, maxf(900.0, idx_m * 5.0), LABEL_LIMIT)
	_clabels = (g["labels"][idx_m] as Array).filter(func(l): return _seen(l["pos"]))
	_spots = (g["spots"] as Array).filter(func(s): return _seen(s["pos"]))
	stats["spots"] = _spots.size()
	stats["contour_labels"] = _clabels.size()
	stats["contour_m"] = float(_contour[0])


# ---------------------------------------------------------------------
# РАМКА ЛИСТА
# ---------------------------------------------------------------------
func _frame_ops() -> void:
	var r: Rect2 = _bbox.grow(minf(_bbox.size.x, _bbox.size.y) * 0.03)
	var a: Vector2 = _b(r.position)
	var c: Vector2 = _b(r.end)
	_ops.append(["frame", Rect2(a, c - a)])


# ---------------------------------------------------------------------
# ПОСЕЛЕННЯ: як на справжніх топокартах — узагальнений знак забудови в реальних розмірах (метри плану міста), без
# збільшеного «плану на пів-регіону». На загальному плані, де справжній розмір менший за ~CITY_MIN_PX, знак лише
# збільшується до цього розміру навколо тієї самої точки; з наближенням він стає справжнім (_ppm()).
# Усередині знака: забудова чорними кварталами за планом поточного етапу росту, вулиці світлими лініями, стіна
# (частокіл — точки, камінь — суцільна лінія), ворота, вежі, городи й витоптана земля; будівництво — пунктиром.
# ---------------------------------------------------------------------
const CITY_MIN_PX: float = 34.0    # найменший радіус забудови на екрані 1080 px

func _place_settlements() -> Array:
	var blocked: Array = []
	_cities.clear()
	var st: Node = game.get("settlements")
	if st == null:
		return blocked
	for s in st.list:
		var c: Vector2 = s["_center"]
		if not _inside(c):
			continue
		stats["cities"] += 1
		var plan: Dictionary = s.get("_plan", {})
		var wall_r: float = float(plan.get("wall_r", 40.0)) * float(plan.get("cell_m", 1.0))
		var ops: Array = []
		var stage: int = 0
		var sname: String = ""
		var progress: String = ""
		if Growth.has_growth(plan):
			var g: Dictionary = st._growth_of(s)
			stage = Growth.stage(plan, g)
			var view: Dictionary = Growth.view(plan, stage)
			sname = Growth.stage_name(plan, stage)
			var nxt: int = Growth.next_points(plan, stage)
			if nxt > 0:
				progress = I18n.t("до «%s»: %d из %d заданий") % [Growth.stage_name(plan, stage + 1), Growth.points(g), nxt]
			_plan_ops(ops, view, plan, stage, g)
		elif not plan.is_empty():
			_plan_ops(ops, plan, plan, 0, {})
		else:
			ops.append(["house", Rect2(Vector2(-2, -2), Vector2(4, 4)), "house"])
		blocked.append([c, maxf(_ppm_at(wall_r), _fitz) * wall_r / _fitz * 1.3])
		var name_line: String = String(s.get("name", ""))
		if sname != "":
			name_line += " · " + sname
		_cities.append({"c": c, "ops": ops, "r": wall_r})
		_labels.append([c, name_line, progress, wall_r])
	return blocked


## Пікселів на метр у знаку поселення: справжній масштаб, але не менше, ніж щоб стіна мала CITY_MIN_PX
func _ppm_at(wall_r: float) -> float:
	return maxf(_zoom(), CITY_MIN_PX * _s / maxf(wall_r, 1.0))


## Знак поселення, як на справжніх топокартах: без кіл, стін, променів і городів — лише забудова. Світла пляма «квартали» під
## будинками (будинки, збільшені на пару метрів, зливаються в нерівну суцільну площу) і самі будинки чорними прямокутниками;
## чим більший етап росту, тим більше будинків. Будівництво наступного етапу — порожні прямокутники пунктиром.
func _plan_ops(ops: Array, view: Dictionary, plan: Dictionary, stage: int, g: Dictionary) -> void:
	var cm: float = float(plan.get("cell_m", 1.0))
	var wall_r: float = float(plan.get("wall_r", 40.0))
	var pc: Array = plan.get("center", [wall_r, wall_r])
	var pcv := Vector2(float(pc[0]), float(pc[1]))
	var to_m := func(q: Vector2) -> Vector2: return (q - pcv) * cm
	var rects: Array = []
	for b in view.get("buildings", []):
		var rr: Array = b["rect"]
		rects.append([Rect2(to_m.call(Vector2(rr[0], rr[1])), Vector2(rr[2], rr[3]) * cm), String(b.get("kind", "house"))])
		stats["buildings"] += 1
	for r in rects:
		ops.append(["halo", (r[0] as Rect2).grow(3.5 * cm)])
	for r in rects:
		ops.append(["house", r[0], r[1]])
	# Будівництво: будинки наступного етапу, поки до нього йдуть завдання (частка = прогрес) — пунктиром
	if Growth.has_growth(plan) and not g.is_empty():
		var stages: Array = plan["growth"]["stages"]
		if stage + 1 < stages.size():
			var p0: int = int(stages[stage].get("points", 0))
			var p1: int = int(stages[stage + 1].get("points", 1))
			var frac: float = clampf(float(Growth.points(g) - p0) / float(maxi(1, p1 - p0)), 0.0, 1.0)
			var next_ids: Array = stages[stage + 1].get("buildings", [])
			var n: int = ceili(frac * next_ids.size()) if frac > 0.0 else 0
			var by_id: Dictionary = {}
			for b in plan.get("buildings", []):
				by_id[b["id"]] = b
			for i in mini(n, next_ids.size()):
				var b: Dictionary = by_id.get(next_ids[i], {})
				if b.is_empty():
					continue
				var rr: Array = b["rect"]
				ops.append(["scaffold", Rect2(to_m.call(Vector2(rr[0], rr[1])), Vector2(rr[2], rr[3]) * cm)])
				stats["scaffolds"] += 1
	stats["walls"] = "stone" if String(view.get("wall", "palisade")) == "stone" else "palisade"   # стіна на карті не малюється (дані — для перевірок)


# ---------------------------------------------------------------------
# РУЇНИ, ВЕЖІ
# ---------------------------------------------------------------------
func _place_ruins(blocked: Array) -> void:
	var cast: Node = game.get("cast")
	var now: float = game.clock.total_seconds if game.clock != null else 0.0
	for site in Ruins.in_rect(game, _bbox):
		var p: Vector2 = site["pos"]
		if not _inside(p) or not _seen(p):
			continue
		var c: Vector2i = Vector2i(floori(p.x / Ruins.GRID_M), floori(p.y / Ruins.GRID_M))
		var roll: float = Art.seed_at(c.x, c.y, 31)
		var b: int = game.biome_at(p)
		var kind: String = "ruin"
		if b == 8:
			kind = "tech_dome" if roll > 0.68 else "tech_wreck"
		var looted: bool = cast != null and Ruins.looted_now(cast.ruins_looted, site["key"], now)
		_marks.append([kind, p, looted])
		stats["ruins"] += 1
	# Сигнальні вежі — ті самі точки, що в декорі карти (storybook/world_decor.gd tower_near)
	var s: float = 64.0
	for y in range(floori(_bbox.position.y / s), floori(_bbox.end.y / s) + 1):
		for x in range(floori(_bbox.position.x / s), floori(_bbox.end.x / s) + 1):
			var n: float = Art.seed_at(x, y, 5)
			if n <= 0.993:
				continue
			var q := (Vector2(x, y) + Vector2(0.15 + n * 0.7, 0.15 + Art.seed_at(x, y, 14) * 0.7)) * s
			if not _inside(q) or not game.biome_at(q) in [2, 3, 4, 7, 8] or _blocked(q, blocked) or not _seen(q):
				continue
			_marks.append(["tower", q, false])
			stats["towers"] += 1


func _blocked(p: Vector2, blocked: Array, mult: float = 1.0) -> bool:
	for b in blocked:
		if p.distance_to(b[0]) < b[1] * mult:
			return true
	return false


## Протоптані тропи регіону — одна картинка (клітинка троп = піксель), розтягнута на регіон; тонкою бордовою лінією
func _place_trails() -> void:
	var tl: Node = game.get("trails")
	_trails_tex = null
	_trails_img = null
	if tl == null:
		return
	# Клітинка стежки (12 м) на огляді менша за піксель: групуємо по g клітинок, щоб тропу було видно (~2,5 px)
	var g: int = maxi(1, ceili(2.5 * _s / (tl.model.cell_m * _fitz)))
	var cm: float = tl.model.cell_m * float(g)
	var c0 := Vector2i(floori(_bbox.position.x / cm), floori(_bbox.position.y / cm))
	var c1 := Vector2i(floori(_bbox.end.x / cm), floori(_bbox.end.y / cm))
	var w: int = c1.x - c0.x + 1
	var h: int = c1.y - c0.y + 1
	var img: Image = null
	var n: int = 0
	for c in tl.model.stage_of:
		var stg: int = int(tl.model.stage_of[c])
		if stg <= 0:
			continue
		var cg := Vector2i(floori(float(c.x) / g), floori(float(c.y) / g))
		if cg.x < c0.x or cg.y < c0.y or cg.x > c1.x or cg.y > c1.y:
			continue
		if img == null:
			img = Image.create(w, h, false, Image.FORMAT_RGBA8)
			img.fill(Color(0, 0, 0, 0))
		var a: float = [0.0, 0.55, 0.7, 0.85, 1.0][stg]
		if img.get_pixel(cg.x - c0.x, cg.y - c0.y).a < a:
			img.set_pixel(cg.x - c0.x, cg.y - c0.y, Color(MAROON.r, MAROON.g, MAROON.b, a))
		n += 1
	stats["trail_cells"] = n
	if img == null:
		return
	_trails_img = img
	_trails_c0 = c0
	_trails_cm = cm
	_trails_tex = ImageTexture.create_from_image(img)
	_trails_rect = Rect2(_b(Vector2(c0) * cm), Vector2(w, h) * cm * _fitz)


# =====================================================================
# МАЛЮВАННЯ ЗНАКІВ (у базових пікселях; масштаб і зсув — перетворенням вузла)
# =====================================================================
## Штрихова лінія: on/off — довжини штриха й проміжку в одиницях вузла
func _dashed(node: Node2D, pts: PackedVector2Array, col: Color, w: float, on: float, off: float) -> void:
	var run: float = 0.0
	var draw_on: bool = true
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var len: float = a.distance_to(b)
		if len < 0.0001:
			continue
		var dir: Vector2 = (b - a) / len
		var t: float = 0.0
		while t < len:
			var lim: float = (on if draw_on else off) - run
			var step: float = minf(lim, len - t)
			if draw_on:
				node.draw_line(a + dir * t, a + dir * (t + step), col, w)
			t += step
			run += step
			if run >= (on if draw_on else off) - 0.0001:
				run = 0.0
				draw_on = not draw_on


func _draw_static() -> void:
	for o in _ops:
		if o[0] == "frame":
			var r: Rect2 = o[1]
			_static.draw_rect(r, Color(0.20, 0.12, 0.08, 0.9), false, 2.2)
			_static.draw_rect(r.grow(-3.0), Color(0.20, 0.12, 0.08, 0.5), false, 0.8)
	if _trails_tex != null:
		# Кремовий підклад під тропою, потім сама тропа
		_static.draw_texture_rect(_trails_tex, Rect2(_trails_rect.position + Vector2(0.7, 0.7), _trails_rect.size), false, Color(CREAM.r, CREAM.g, CREAM.b, 0.7))
		_static.draw_texture_rect(_trails_tex, _trails_rect, false, Color.WHITE)
	for m in _marks:
		_draw_mark(m)


## Знаки поселень: координати — метри від центру, розміри ліній і значків — у пікселях (ділимо на масштаб знака)
func _draw_cities() -> void:
	var z: float = _zoom()
	for city in _cities:
		var ppm: float = _ppm_at(city["r"])
		var u: float = 1.0 / ppm
		var n: Node2D = _city_node
		n.draw_set_transform((city["c"] - _center) * z, 0.0, Vector2(ppm, ppm))
		for o in city["ops"]:
			match o[0]:
				"poly":
					if (o[1] as PackedVector2Array).size() >= 3:
						n.draw_colored_polygon(o[1], o[2])
				"pline":
					var pts: PackedVector2Array = o[1]
					if pts.size() >= 2:
						if o[4]:
							_dashed(n, pts, o[2], o[3] * u, 2.6 * u, 2.2 * u)
						else:
							n.draw_polyline(pts, o[2], o[3] * u, true)
				"line":
					n.draw_line(o[1], o[2], o[4], maxf(o[3] * u, 0.0), true)
				"circle":
					n.draw_circle(o[1], o[2], o[3])
					n.draw_arc(o[1], o[2], 0.0, TAU, 24, o[4], o[5] * u, true)
				"tri":
					var sz: float = o[2]
					var c: Vector2 = o[1]
					var tri := PackedVector2Array([c + Vector2(0, -sz), c + Vector2(sz * 0.9, sz * 0.7), c + Vector2(-sz * 0.9, sz * 0.7)])
					n.draw_colored_polygon(tri, o[3])
				"diamond":
					var c2: Vector2 = o[1]
					var sz2: float = o[2]
					n.draw_colored_polygon(PackedVector2Array([c2 + Vector2(0, -sz2), c2 + Vector2(sz2, 0), c2 + Vector2(0, sz2), c2 + Vector2(-sz2, 0)]), o[3])
				"post":
					var hs: float = o[2] * 0.5
					n.draw_rect(Rect2(o[1] - Vector2(hs, hs), Vector2(hs, hs) * 2.0), o[3])
					n.draw_rect(Rect2(o[1] - Vector2(hs, hs), Vector2(hs, hs) * 2.0), o[4], false, 0.8 * u)
				"halo":
					n.draw_rect(o[1], Color(0.74, 0.62, 0.50, 0.9))
				"house":
					_draw_house(n, o[1], o[2], u)
				"scaffold":
					var sr: Rect2 = o[1]
					n.draw_rect(sr, Color(CREAM.r, CREAM.g, CREAM.b, 0.55))
					_dashed(n, PackedVector2Array([sr.position, sr.position + Vector2(sr.size.x, 0), sr.end, sr.position + Vector2(0, sr.size.y), sr.position]), Color(0.78, 0.44, 0.10), 1.0 * u, 2.0 * u, 1.6 * u)
	_city_node.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Квартал на топокарті: суцільний чорний (з темним відтінком за призначенням); храм — світлий хрест; руїна — порожній контур
func _draw_house(n: Node2D, rc: Rect2, kind: String, u: float) -> void:
	var r: Rect2 = rc
	var min_m: float = 2.6 * u
	if r.size.x < min_m or r.size.y < min_m:
		var c0: Vector2 = r.get_center()
		var sz0 := Vector2(maxf(r.size.x, min_m), maxf(r.size.y, min_m))
		r = Rect2(c0 - sz0 * 0.5, sz0)
	if kind == "ruins":
		n.draw_rect(r, Color(INK.r, INK.g, INK.b, 0.18))
		n.draw_rect(r, INK, false, 0.8 * u)
		return
	var fill: Color = INK
	match kind:
		"hall":
			fill = Color(0.30, 0.12, 0.10)
		"temple":
			fill = Color(0.28, 0.20, 0.34)
		"inn", "shop", "smithy", "healer":
			fill = Color(0.26, 0.15, 0.08)
	n.draw_rect(r, fill)
	if kind == "temple" and minf(r.size.x, r.size.y) * (1.0 / u) > 6.0:
		var c: Vector2 = r.get_center()
		var q: float = minf(r.size.x, r.size.y) * 0.3
		n.draw_line(c - Vector2(0, q), c + Vector2(0, q), CREAM, 0.8 * u)
		n.draw_line(c - Vector2(q, 0), c + Vector2(q, 0), CREAM, 0.8 * u)


func _draw_mark(m: Array) -> void:
	var c: Vector2 = _b(m[1])
	var dim: float = 0.45 if m[2] else 1.0
	var sz: float = 4.4 * _s
	match String(m[0]):
		"ruin":
			var col := Color(VIOLET.r, VIOLET.g, VIOLET.b, dim)
			# руїна: квадрат без верхньої стіни й уламок поряд
			_static.draw_polyline(PackedVector2Array([c + Vector2(-sz, -sz * 0.2), c + Vector2(-sz, sz), c + Vector2(sz, sz), c + Vector2(sz, -sz * 0.2)]), col, 1.4, true)
			_static.draw_line(c + Vector2(-sz, -sz * 0.2), c + Vector2(-sz * 0.4, -sz * 0.9), col, 1.4, true)
			_static.draw_line(c + Vector2(sz, -sz * 0.2), c + Vector2(sz * 0.3, -sz * 0.6), col, 1.4, true)
			_static.draw_circle(c + Vector2(sz * 1.5, sz * 0.9), 0.9, col)
		"tech_wreck", "tech_dome":
			var tc := Color(CYAN.r, CYAN.g, CYAN.b, dim)
			var dm := PackedVector2Array([c + Vector2(0, -sz * 1.1), c + Vector2(sz * 1.1, 0), c + Vector2(0, sz * 1.1), c + Vector2(-sz * 1.1, 0), c + Vector2(0, -sz * 1.1)])
			_static.draw_colored_polygon(dm.slice(0, 4), Color(tc.r, tc.g, tc.b, 0.25 * dim))
			_static.draw_polyline(dm, tc, 1.4, true)
			if String(m[0]) == "tech_dome":
				_static.draw_arc(c, sz * 0.5, PI, TAU, 10, tc, 1.2, true)
			else:
				_static.draw_circle(c, 1.1, tc)
		"tower":
			var vc := Color(CYAN.r, CYAN.g, CYAN.b, dim)
			var tri := PackedVector2Array([c + Vector2(0, -sz * 1.2), c + Vector2(sz, sz * 0.8), c + Vector2(-sz, sz * 0.8), c + Vector2(0, -sz * 1.2)])
			_static.draw_polyline(tri, vc, 1.4, true)
			_static.draw_circle(c + Vector2(0, sz * 0.15), 1.1, vc)


func _draw_live() -> void:
	var t: float = Time.get_ticks_msec() / 1000.0
	var cast: Node = game.get("cast")
	if cast != null and not cast.hero.is_empty() and not cast.hero_away:
		var hp: Vector2 = cast.hero["pos"]
		if _bbox.grow(200.0).has_point(hp):
			var foot: Vector2 = _b(hp)
			var pulse: float = 0.5 + 0.5 * sin(t * 3.0)
			var u: float = 1.0 / _uz
			_live.draw_arc(foot, (9.0 + 6.0 * pulse) * _s * u, 0.0, TAU, 32, Color(0.95, 0.62, 0.10, 0.75 * (1.0 - pulse * 0.6)), 2.0 * u)
			# знак героя: золотий ромб із чорною обводкою й крапкою
			var d: float = 5.0 * _s * u
			var dm := PackedVector2Array([foot + Vector2(0, -d * 1.3), foot + Vector2(d, 0), foot + Vector2(0, d * 1.3), foot + Vector2(-d, 0)])
			_live.draw_colored_polygon(dm, Color(0.98, 0.78, 0.18))
			_live.draw_polyline(PackedVector2Array([dm[0], dm[1], dm[2], dm[3], dm[0]]), Color(0.16, 0.09, 0.04), 1.6 * u, true)
			_live.draw_circle(foot, 1.3 * u, Color(0.16, 0.09, 0.04))


# =====================================================================
# ЕКРАННІ ПІДПИСИ: назви, висоти, сітка, лінійка, легенда
# =====================================================================
func _text(font: Font, pos: Vector2, s: String, fs: int, col: Color, halo: Color = Color(CREAM.r, CREAM.g, CREAM.b, 0.85)) -> void:
	_hud.draw_string_outline(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(3, fs / 4), halo)
	_hud.draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _draw_hud() -> void:
	var font: Font = ThemeDB.fallback_font
	var vp: Vector2 = _root.get_viewport_rect().size
	var z: float = _zoom()
	var view := Rect2(Vector2.ZERO, vp).grow(40.0)
	# Кілометрова сітка: підписи по краях (кілометри від початку карти)
	var gs: float = 1000.0
	var gpx: float = gs * z
	if gpx >= 34.0 * _s:
		var fsg: int = int(12 * _s)
		var top_left: Vector2 = _cam + (Vector2(0, 0) - _sc(vp)) / z
		var bot_right: Vector2 = _cam + (vp - _sc(vp)) / z
		for kx in range(ceili(top_left.x / gs), floori(bot_right.x / gs) + 1):
			var sx: float = _sc(vp).x + (float(kx) * gs - _cam.x) * z
			if sx > 90.0 and sx < vp.x - 90.0:
				_text(font, Vector2(sx + 3.0, vp.y - 6.0), str(kx), fsg, Color(0.18, 0.28, 0.40), Color(CREAM.r, CREAM.g, CREAM.b, 0.7))
		for ky in range(ceili(top_left.y / gs), floori(bot_right.y / gs) + 1):
			var sy: float = _sc(vp).y + (float(ky) * gs - _cam.y) * z
			if sy > TOP_PX * _s + 20.0 and sy < vp.y - 30.0:
				_text(font, Vector2(4.0, sy - 3.0), str(ky), fsg, Color(0.18, 0.28, 0.40), Color(CREAM.r, CREAM.g, CREAM.b, 0.7))
	# Підписи основних горизонталей: уздовж лінії
	var fsc: int = int(11 * _s)
	if _uz >= 0.99:
		for l in _clabels:
			var sp: Vector2 = _sc(vp) + (l["pos"] - _cam) * z
			if not view.has_point(sp):
				continue
			var txt: String = str(int(l["h"]))
			var w: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsc).x
			_hud.draw_set_transform(sp, float(l["angle"]), Vector2.ONE)
			_hud.draw_string_outline(font, Vector2(-w * 0.5, fsc * 0.35), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsc, 5, Color(0.80, 0.70, 0.52, 0.85))
			_hud.draw_string(font, Vector2(-w * 0.5, fsc * 0.35), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsc, Color(0.32, 0.18, 0.09))
		_hud.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Висотні відмітки: трикутник і число
	var fsh: int = int(12 * _s)
	for s in _spots:
		var sp2: Vector2 = _sc(vp) + (s["pos"] - _cam) * z
		if not view.has_point(sp2):
			continue
		var d: float = 3.4 * _s
		var tri := PackedVector2Array([sp2 + Vector2(0, -d), sp2 + Vector2(d * 0.95, d * 0.7), sp2 + Vector2(-d * 0.95, d * 0.7)])
		_hud.draw_colored_polygon(tri, Color(0.28, 0.14, 0.08))
		_text(font, sp2 + Vector2(d + 2.0, d * 0.7), str(int(roundf(s["h"]))), fsh, Color(0.22, 0.11, 0.06))
	# Назви поселень
	for l in _labels:
		var sp3: Vector2 = _sc(vp) + (l[0] - _cam) * z + Vector2(0, _ppm_at(float(l[3])) * float(l[3]) * 1.25 + 12.0 * _s)
		var fs: int = int(18 * _s)
		var w3: float = font.get_string_size(l[1], HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
		_text(font, sp3 - Vector2(w3 * 0.5, 0), l[1], fs, Color(0.14, 0.08, 0.04), Color(CREAM.r, CREAM.g, CREAM.b, 0.92))
		if String(l[2]) != "":
			var fs2: int = int(13 * _s)
			var w2: float = font.get_string_size(l[2], HORIZONTAL_ALIGNMENT_CENTER, -1, fs2).x
			_text(font, sp3 + Vector2(-w2 * 0.5, fs * 1.1), l[2], fs2, Color(0.30, 0.18, 0.08), Color(CREAM.r, CREAM.g, CREAM.b, 0.85))
	_draw_scale_bar(font, vp, z)
	if legend_on:
		_draw_legend(font, vp)


## Масштабна лінійка зі штрихами й підписом, під серединою листа
func _draw_scale_bar(font: Font, vp: Vector2, z: float) -> void:
	var sb: Array = Topo.scale_bar(z, 150.0 * _s)
	var len_px: float = sb[1]
	var x0: float = vp.x * 0.5 - len_px * 0.5
	var y: float = vp.y - 26.0 * _s
	_hud.draw_rect(Rect2(x0 - 8.0, y - 20.0 * _s, len_px + 16.0, 36.0 * _s), Color(0.07, 0.06, 0.05, 0.62))
	var fsb: int = int(12 * _s)
	_hud.draw_line(Vector2(x0, y), Vector2(x0 + len_px, y), CREAM, 2.0)
	for i in 5:
		var xx: float = x0 + len_px * float(i) / 4.0
		_hud.draw_line(Vector2(xx, y - (6.0 if i % 2 == 0 else 3.5) * _s), Vector2(xx, y), CREAM, 1.5)
	var txt: String = Topo.length_text(float(sb[0]), I18n.t("км"), I18n.t("м"))
	_hud.draw_string(font, Vector2(x0, y + 14.0 * _s), "0", HORIZONTAL_ALIGNMENT_LEFT, -1, fsb, CREAM)
	var w: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsb).x
	_hud.draw_string(font, Vector2(x0 + len_px - w, y + 14.0 * _s), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsb, CREAM)


## Легенда умовних знаків (L — свернуть)
func _draw_legend(font: Font, vp: Vector2) -> void:
	var rows: Array = [
		["contour", I18n.t("Горизонталь, шаг %d м") % int(_contour[0])],
		["index", I18n.t("Основная горизонталь, подпись — высота, м")],
		["spot", I18n.t("Высотная отметка (вершина), м")],
		["water", I18n.t("Море, озеро, река")],
		["forest", I18n.t("Лес: лиственный, хвойный")],
		["swamp", I18n.t("Болото")],
		["cursed", I18n.t("Проклятые земли")],
		["hot", I18n.t("Жаркие горы")],
		["city", I18n.t("Поселение (застройка)")],
		["trail", I18n.t("Тропа, протоптанная героем")],
		["ruin", I18n.t("Руины")],
		["tech", I18n.t("Техноостов, сигнальная вышка")],
		["border", I18n.t("Граница региона")],
		["blank", I18n.t("Не исследовано (белое пятно)")],
	]
	var fs: int = int(12 * _s)
	var row_h: float = 18.0 * _s
	var w: float = 270.0 * _s
	var h: float = row_h * float(rows.size()) + 12.0 * _s
	var x0: float = 12.0 * _s
	var y0: float = vp.y - 52.0 * _s - h
	_hud.draw_rect(Rect2(Vector2(x0, y0), Vector2(w, h)), Color(0.07, 0.06, 0.05, 0.74))
	_hud.draw_rect(Rect2(Vector2(x0, y0), Vector2(w, h)), Color(0.55, 0.45, 0.28, 0.8), false, 1.0)
	for i in rows.size():
		var cy: float = y0 + 6.0 * _s + row_h * (float(i) + 0.5)
		var sx: float = x0 + 22.0 * _s
		_legend_sign(String(rows[i][0]), Vector2(sx, cy))
		_hud.draw_string(font, Vector2(x0 + 46.0 * _s, cy + 4.0 * _s), rows[i][1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("e8dcb0"))


func _legend_sign(kind: String, c: Vector2) -> void:
	var u: float = _s
	match kind:
		"contour":
			_hud.draw_line(c + Vector2(-14, 2) * u, c + Vector2(14, -2) * u, Color(0.62, 0.40, 0.24), 1.0 * u)
		"index":
			_hud.draw_line(c + Vector2(-14, 2) * u, c + Vector2(14, -2) * u, Color(0.78, 0.50, 0.28), 2.2 * u)
		"spot":
			_hud.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -4) * u, c + Vector2(4, 3) * u, c + Vector2(-4, 3) * u]), Color(0.78, 0.50, 0.28))
		"water":
			_hud.draw_rect(Rect2(c - Vector2(13, 5) * u, Vector2(26, 10) * u), Color(0.34, 0.54, 0.68))
			_hud.draw_line(c + Vector2(-13, 5) * u, c + Vector2(13, 5) * u, Color(0.62, 0.22, 0.20), 1.2 * u)
		"forest":
			_hud.draw_rect(Rect2(c - Vector2(13, 5) * u, Vector2(26, 10) * u), Color(0.55, 0.64, 0.36))
			_hud.draw_arc(c + Vector2(-5, 0) * u, 3.4 * u, 0.0, TAU, 14, Color(0.16, 0.30, 0.14), 1.2 * u, true)
			_hud.draw_polyline(PackedVector2Array([c + Vector2(5, 3) * u, c + Vector2(8, -3) * u, c + Vector2(11, 3) * u, c + Vector2(5, 3) * u]), Color(0.16, 0.30, 0.14), 1.2 * u, true)
		"swamp":
			_hud.draw_rect(Rect2(c - Vector2(13, 5) * u, Vector2(26, 10) * u), Color(0.46, 0.58, 0.42))
			for k in [-3.0, 0.0, 3.0]:
				_hud.draw_line(c + Vector2(-6, k) * u, c + Vector2(6, k) * u, Color(0.20, 0.38, 0.40), 1.1 * u)
		"cursed":
			_hud.draw_rect(Rect2(c - Vector2(13, 5) * u, Vector2(26, 10) * u), Color(0.49, 0.53, 0.47))
			for k in range(-12, 14, 5):
				_hud.draw_line(c + Vector2(float(k), 5) * u, c + Vector2(float(k) + 5.0, -5) * u, Color(0.46, 0.27, 0.58), 1.1 * u)
		"hot":
			_hud.draw_rect(Rect2(c - Vector2(13, 5) * u, Vector2(26, 10) * u), Color(0.74, 0.55, 0.40))
			for k in range(-12, 14, 5):
				_hud.draw_line(c + Vector2(float(k), 5) * u, c + Vector2(float(k) + 5.0, -5) * u, Color(0.62, 0.20, 0.14), 1.1 * u)
		"city":
			_hud.draw_rect(Rect2(c - Vector2(10, 6) * u, Vector2(20, 12) * u), Color(0.74, 0.62, 0.50))
			for q in [Vector2(-6, -3), Vector2(1, -3), Vector2(-3, 2), Vector2(4, 2), Vector2(7, -2)]:
				_hud.draw_rect(Rect2(c + q * u, Vector2(3, 3) * u), INK)
		"trail":
			_hud.draw_line(c + Vector2(-14, 0) * u, c + Vector2(14, 0) * u, MAROON, 1.6 * u)
		"ruin":
			var col := VIOLET
			_hud.draw_polyline(PackedVector2Array([c + Vector2(-5, -1) * u, c + Vector2(-5, 5) * u, c + Vector2(5, 5) * u, c + Vector2(5, -1) * u]), col, 1.4 * u)
			_hud.draw_line(c + Vector2(-5, -1) * u, c + Vector2(-2, -5) * u, col, 1.4 * u)
		"tech":
			_hud.draw_polyline(PackedVector2Array([c + Vector2(-9, 0) * u, c + Vector2(-6, -5) * u, c + Vector2(-3, 0) * u, c + Vector2(-6, 5) * u, c + Vector2(-9, 0) * u]), CYAN, 1.4 * u)
			_hud.draw_polyline(PackedVector2Array([c + Vector2(3, 5) * u, c + Vector2(7, -5) * u, c + Vector2(11, 5) * u, c + Vector2(3, 5) * u]), CYAN, 1.4 * u)
		"border":
			for k in range(-14, 12, 7):
				_hud.draw_line(c + Vector2(float(k), 0) * u, c + Vector2(float(k) + 4.0, 0) * u, Color(0.65, 0.20, 0.22), 1.8 * u)
		"blank":
			_hud.draw_rect(Rect2(c - Vector2(13, 5) * u, Vector2(26, 10) * u), Color(0.76, 0.71, 0.58))
			for k in range(-12, 14, 6):
				_hud.draw_line(c + Vector2(float(k), 5) * u, c + Vector2(float(k) + 5.0, -5) * u, Color(0.50, 0.42, 0.30), 0.8 * u)


func _layout_hud(vp: Vector2) -> void:
	var pw: float = minf(420.0 * _s, vp.x * 0.4)
	var ph: float = pw * 192.0 / 1024.0
	_plate.position = Vector2(14.0 * _s, 58.0 * _s)   # ліворуч під верхньою панеллю (показники героя, час)
	_plate.size = Vector2(pw, ph)
	_title.position = _plate.position
	_title.size = Vector2(pw, ph)
	_title.text = region_name(region_id)
	_hint.position = Vector2(_plate.position.x + 6.0, _plate.position.y + ph + 2.0)
	_hint.size = Vector2(vp.x * 0.45, 40)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_hint.text = (I18n.t("регион %d · PgUp/PgDn или клик по соседнему — другой регион · колесо — масштаб · перетащить — сдвиг · L — легенда · %s — закрыть") % [region_id,
		"Esc" if standalone else "V / Esc"]) + ("" if not standalone else I18n.t(" · F — туман войны · G — город растёт"))
	_info.position = Vector2(vp.x * 0.5 - 16.0, vp.y - 190.0 * _s)
	_info.size = Vector2(vp.x * 0.5, 170.0 * _s)
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _update_info() -> void:
	var lines: Array = []
	var st: Node = game.get("settlements")
	if st != null:
		for s in st.list:
			if not _inside(s["_center"]):
				continue
			var plan: Dictionary = s.get("_plan", {})
			if Growth.has_growth(plan):
				var g: Dictionary = st._growth_of(s)
				var stg: int = Growth.stage(plan, g)
				lines.append(I18n.t("%s — %s: домов %d, строится %d") % [s.get("name", ""), Growth.stage_name(plan, stg), stats["buildings"], stats["scaffolds"]])
	var rt: Node = game.get("region_tracker")
	if rt != null and rt.map.is_ready and rt.map.cells_total(region_id) > 0:
		lines.append(I18n.t("Исследовано: %d%%") % int(round(rt.map.explored_fraction(region_id) * 100.0)))
	var cast: Node = game.get("cast")
	var looted: int = 0
	if cast != null:
		var now: float = game.clock.total_seconds
		for site in Ruins.in_rect(game, _bbox):
			if _inside(site["pos"]) and Ruins.looted_now(cast.ruins_looted, site["key"], now):
				looted += 1
	lines.append(I18n.t("Руин: %d (обысканы недавно: %d), сигнальных вышек: %d") % [stats["ruins"], looted, stats["towers"]])
	if int(stats.get("trail_cells", 0)) > 0:
		lines.append(I18n.t("Протоптано троп: %.1f км") % (float(stats["trail_cells"]) * 12.0 / 1000.0))
	lines.append(I18n.t("Горизонтали через %d м; высоты — над низиной") % int(_contour[0]))
	_info.text = "\n".join(lines)


# =====================================================================
# КЕРУВАННЯ
# =====================================================================
func _input(event: InputEvent) -> void:
	if not is_open:
		return
	var vp: Vector2 = _root.get_viewport_rect().size
	if event is InputEventKey and event.pressed:
		var k: int = event.physical_keycode
		if k == KEY_F1:
			return   # довідка працює і тут
		if standalone and k == KEY_ESCAPE:
			return   # у просмотрщику Esc — вихід (region_viewer.gd)
		if not event.echo and (k == KEY_ESCAPE or (k == KEY_V and not standalone)):
			close()
		elif not event.echo and k == KEY_L:
			legend_on = not legend_on
		elif not event.echo and k == KEY_PAGEDOWN:
			step_region(1)
		elif not event.echo and k == KEY_PAGEUP:
			step_region(-1)
		elif k in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
			var d := Vector2(float(k == KEY_RIGHT) - float(k == KEY_LEFT), float(k == KEY_DOWN) - float(k == KEY_UP))
			_cam += d * 60.0 / _zoom()
			_clamp()
		elif k == KEY_EQUAL or k == KEY_KP_ADD:
			_zoom_at(_sc(vp), 1.25)
		elif k == KEY_MINUS or k == KEY_KP_SUBTRACT:
			_zoom_at(_sc(vp), 0.8)
		elif not event.echo and standalone and k == KEY_F:
			fog_enabled = not fog_enabled
			_rebuild()
		elif standalone:
			return   # решту клавіш обробляє просмотрщик (region_viewer.gd)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(event.position, 1.2)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(event.position, 1.0 / 1.2)
		elif event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				_dragging = true
				_drag_moved = false
				_drag_from = event.position
			else:
				if _dragging and not _drag_moved and event.button_index == MOUSE_BUTTON_LEFT:
					_click(event.position)
				_dragging = false
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		if _dragging:
			if event.position.distance_to(_drag_from) > 4.0:
				_drag_moved = true
			_cam -= event.relative / _zoom()
			_clamp()
		get_viewport().set_input_as_handled()


func _zoom_at(sp: Vector2, f: float) -> void:
	var vp: Vector2 = _root.get_viewport_rect().size
	var before: Vector2 = _cam + (sp - _sc(vp)) / _zoom()
	_uz = clampf(_uz * f, 1.0, MAX_ZOOM)
	_cam = before - (sp - _sc(vp)) / _zoom()
	_clamp()


func _clamp() -> void:
	var half: Vector2 = _bbox.size * 0.5 * (1.0 - 1.0 / _uz) + _bbox.size * 0.05
	_cam = _cam.clamp(_center - half, _center + half)


## Клік по сусідньому (приглушеному) регіону — відкрити його
func _click(sp: Vector2) -> void:
	var vp: Vector2 = _root.get_viewport_rect().size
	var p: Vector2 = _cam + (sp - _sc(vp)) / _zoom()
	var id: int = game.province_at(p)
	if id > 0 and id != region_id:
		open(id)


## Для тестів і знімків: перебудувати зараз
func rebuild_now() -> void:
	_rebuild()

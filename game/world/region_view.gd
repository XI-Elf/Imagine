extends CanvasLayer
## Огляд регіону (Huzzah 2026-11-04): окремий режим «як на мальованій карті» — увесь регіон (область із
## кольоровою межею, map_provinces.png) на один екран. Земля — строго згори (той самий шейдер карти, що й гра),
## а дерева, гори, руїни, техноруїни й будинки стоять «вгору» в ракурсі 3/4 з однією тінню (світло зліва згори),
## дальнє за ближнім (сортування за ногами). Довкола регіону — затемнення й рамка гір, над болотами й проклятими
## землями пливе туман, неісследоване закрите хмарами туману війни.
##
## Живе: місто на огляді — той самий план, що в світі міста (data/cities/<id>.json, city/city_growth.gd view),
## тобто з кожним зданим завданням з'являються нові будинки, стіна з частоколу стає камінною, а будинки
## наступного етапу стоять у риштованні, поки до нього йдуть завдання. Руїни після обшуку темніють, тропи
## протоптуються, туман розходиться там, де пройшов герой; знак героя — де він зараз. Стан перевіряється
## раз на CHECK_S секунд, перебудова — лише коли щось змінилося.
##
## Картинки — world/region_art.gd (art/region/manifest.json, заміна з теки region_art/ без правки коду).
## Відкрити: V на загальній карті (game.gd) або просмотрщик регіонів (region_viewer.tscn).
## Керування: колесо — масштаб до курсора, ЛКМ-перетягування або стрілки — зсув, клік по сусідньому регіону
## (затемненому) — перейти туди, PgUp/PgDn — попередній/наступний регіон, Esc або V — закрити.
## Сюжетні мітки кампанії тут навмисно не малюються.

const RegionArt := preload("res://world/region_art.gd")
const Ruins := preload("res://world/ruins.gd")
const Growth := preload("res://city/city_growth.gd")
const Art := preload("res://storybook/art.gd")

const LAYER: int = 6               # над світом, туманом карти (1) і фільтром світу (5): огляд має свій, м'якший фільтр; під інтерфейсом (10+)
const GRADE: float = 0.55           # сила темного фільтра світу на огляді (ui/world_grade.gd): стиль той самий, але видно деталі
const STEP_PX: float = 9.0         # крок розстановки дерев на екрані 1080 px при огляді всього регіону
const MOUNTAIN_STEP: float = 2.8   # гори — рідша сітка (у кроках STEP_PX)
const FRAME_CELLS: int = 2         # товщина рамки гір довкола регіону (у кроках гір)
const MARGIN: float = 1.1          # запас довкола регіону при вписуванні в екран
const MAX_ZOOM: float = 4.0
const RELEASE_S: float = 90.0       # стільки секунд закритий огляд тримає в пам'яті картинки й вузли
const CHECK_S: float = 1.0         # як часто перевіряти, чи змінився світ
const REBUILD_MIN_S: float = 5.0   # не частіше перебудова через тропи й туман (місто й руїни — одразу)
const CITY_R_PX: Dictionary = {"hamlet": 52.0, "village": 70.0, "town": 90.0, "city": 125.0, "capital": 145.0}
const TOP_PX: float = 96.0         # згори екрана — панель часу й табличка: регіон вписується нижче
const MIST_MAX: int = 240
const SHADOW_DX: float = 0.16      # тінь зсунута вправо на частку ширини (світло зліва згори)

const OUTSIDE_SHADER := """
shader_type canvas_item;
render_mode unshaded;
uniform sampler2D province_tex : filter_nearest, repeat_disable;
uniform vec2 map_size = vec2(41625.0, 36000.0);
uniform vec2 cam_pos = vec2(0.0);
uniform vec2 view_px = vec2(1280.0, 720.0);
uniform float zoom = 1.0;
uniform float region_id = 0.0;
uniform float feather_m = 90.0;
float inside_at(vec2 P) {
	vec2 Q = P / map_size;
	if (Q.x < 0.0 || Q.y < 0.0 || Q.x > 1.0 || Q.y > 1.0) return 0.0;
	return step(abs(texture(province_tex, Q).r * 255.0 - region_id), 0.5);
}
void fragment() {
	vec2 P = cam_pos + (UV - vec2(0.5)) * view_px / zoom;
	float f = feather_m;
	float k = inside_at(P) * 0.36;
	k += (inside_at(P + vec2(f, 0.0)) + inside_at(P - vec2(f, 0.0)) + inside_at(P + vec2(0.0, f)) + inside_at(P - vec2(0.0, f))) * 0.1;
	k += (inside_at(P + vec2(f, f)) + inside_at(P - vec2(f, f)) + inside_at(P + vec2(f, -f)) + inside_at(P + vec2(-f, f))) * 0.06;
	float out_a = 1.0 - smoothstep(0.25, 0.75, k);
	float edge = smoothstep(0.15, 0.5, k) * (1.0 - smoothstep(0.5, 0.85, k));
	// за межею — темна мальована «поза картою», на самій межі — тонка чорнильна лінія
	vec2 sc = UV - vec2(0.5);
	float vign = smoothstep(0.35, 0.75, length(sc * vec2(1.0, view_px.y / view_px.x) * 1.4));
	vec3 col = mix(vec3(0.05, 0.055, 0.065), vec3(0.02, 0.02, 0.03), vign);
	float a = max(out_a * 0.74, edge * 0.55) + vign * 0.25;
	COLOR = vec4(col, clamp(a, 0.0, 0.92));
}
"""

const FOG_SHADER := """
shader_type canvas_item;
render_mode unshaded;
uniform sampler2D mask : filter_linear, repeat_disable;
uniform sampler2D clouds : filter_linear_mipmap, repeat_enable;
uniform sampler2D province_tex : filter_linear, repeat_disable;
uniform float region_id = 0.0;
uniform vec2 map_size = vec2(41625.0, 36000.0);
uniform vec2 cam_pos = vec2(0.0);
uniform vec2 view_px = vec2(1280.0, 720.0);
uniform float zoom = 1.0;
uniform float anim = 0.0;
uniform float cloud_m = 2600.0;
void fragment() {
	vec2 P = cam_pos + (UV - vec2(0.5)) * view_px / zoom;
	vec2 Q = P / map_size;
	vec2 px = vec2(110.0) / map_size;
	float known = texture(mask, Q).r * 0.4 + (texture(mask, Q + vec2(px.x, 0.0)).r + texture(mask, Q - vec2(px.x, 0.0)).r
		+ texture(mask, Q + vec2(0.0, px.y)).r + texture(mask, Q - vec2(0.0, px.y)).r) * 0.15;
	// два шари тієї самої бесшовної картинки з різним масштабом і поворотом — повтор не видно
	vec2 R = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * P;
	float c1 = texture(clouds, P / cloud_m + vec2(anim * 0.004, anim * 0.0015)).a;
	float c2 = texture(clouds, R / (cloud_m * 0.61) + vec2(-anim * 0.006, anim * 0.003) + 0.37).a;
	float c = c1 * 0.6 + c2 * 0.4;
	float a = 1.0 - smoothstep(0.35, 0.7, known + (c - 0.5) * 0.55);
	// мальовані хмари темного світу: світліші верхівки, холодні сірі низи; крізь тонкі місця ледь видно землю
	vec3 col = mix(vec3(0.16, 0.17, 0.21), vec3(0.60, 0.60, 0.66), smoothstep(0.2, 0.9, c));
	// лише над самим регіоном: довкола вже темна «поза картою»
	float ins = 1.0 - smoothstep(0.0, 1.5, abs(texture(province_tex, Q).r * 255.0 - region_id));
	COLOR = vec4(col, a * mix(0.8, 0.96, c) * ins);
}
"""

var game: Node2D
var art := RegionArt.new()
var region_id: int = 0
var is_open: bool = false
var standalone: bool = false        # просмотрщик регіонів: туман війни можна вимкнути, тексти інші
var fog_enabled: bool = true
var build_ms: float = 0.0           # скільки тривала остання перебудова (для замірів і тесту)
var stats: Dictionary = {}          # скільки чого розставлено (тест, панель)

var _root: Control
var _ground: ColorRect
var _ground_mat: ShaderMaterial
var _outside: ColorRect
var _outside_mat := ShaderMaterial.new()
var _static: Node2D                 # усе нерухоме: плоске (тропи, місто), тіні, спрайти — один список за y
var _live: Node2D                   # туман над болотами й знак героя — щокадру
var _fog: ColorRect
var _fog_mat := ShaderMaterial.new()
var _fog_tex: ImageTexture
var _fog_version: int = -1
var _hud: Node2D                    # підписи (не масштабуються)
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
var _s: float = 1.0                 # масштаб спрайтів: висота екрана / 1080

var _flats: Array = []              # [тип, дані] — плоске під тінями
var _items: Array = []              # [y, ключ, Rect2, Color] — спрайти
var _shadows: Array = []            # Rect2
var _mist: Array = []               # [точка (базові px), розмір, фаза, колір]
var _labels: Array = []             # [точка (метри), текст, розмір шрифту]
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


## Картинки й вузли — при першому відкритті (запуск гри не повільнішає)
func _ensure_built() -> void:
	if _root != null:
		return
	art.load_all()
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
	_outside = ColorRect.new()
	_outside.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_outside.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = OUTSIDE_SHADER
	_outside_mat.shader = sh
	_outside.material = _outside_mat
	_root.add_child(_outside)
	_static = Node2D.new()
	_static.draw.connect(_draw_static)
	_root.add_child(_static)
	_live = Node2D.new()
	_live.draw.connect(_draw_live)
	_root.add_child(_live)
	_fog = ColorRect.new()
	_fog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fs := Shader.new()
	fs.code = FOG_SHADER
	_fog_mat.shader = fs
	if art.textures.has("fog_clouds"):
		var ci: Image = art.textures["fog_clouds"].get_image()
		ci.generate_mipmaps()
		_fog_mat.set_shader_parameter("clouds", ImageTexture.create_from_image(ci))
	_fog.material = _fog_mat
	_root.add_child(_fog)
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
	_outside = null
	_static = null
	_live = null
	_fog = null
	_hud = null
	_grade = null
	_info = null
	_title = null
	_hint = null
	_plate = null
	_ground_mat = null
	_fog_tex = null
	_fog_version = -1
	_trails_tex = null
	_trails_img = null
	_flats.clear()
	_items.clear()
	_shadows.clear()
	_mist.clear()
	_labels.clear()
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
# ЗЕМЛЯ: той самий шейдер, що й карта, власна камера; террейни можна підмінити з region_art/terrain/
# =====================================================================
func _ensure_ground() -> void:
	if _ground_mat != null:
		return
	_ground_mat = game.render_mat.duplicate() as ShaderMaterial
	_ground_mat.set_shader_parameter("show_clouds", 0.0)
	_ground_mat.set_shader_parameter("border_mode", 0)
	_ground_mat.set_shader_parameter("overview_flat", 1.0)   # рівна земля без намальованих гір, лісу й рельєфу (map_shaders.gd)
	var imgs: Array[Image] = []
	var any: bool = false
	for n in game.TERRAIN_FILES:
		var img: Image = art.terrain_override(n)
		if img != null:
			any = true
		else:
			var path: String = "res://art/terrain/%s.png" % n
			if not ResourceLoader.exists(path):
				imgs.clear()
				break
			img = (load(path) as Texture2D).get_image()
			if img.is_compressed():
				img.decompress()
		img.convert(Image.FORMAT_RGB8)
		if img.get_width() != 512 or img.get_height() != 512:
			img.resize(512, 512, Image.INTERPOLATE_LANCZOS)
		img.generate_mipmaps()
		imgs.append(img)
	if any and imgs.size() == game.TERRAIN_FILES.size():
		var arr := Texture2DArray.new()
		arr.create_from_images(imgs)
		_ground_mat.set_shader_parameter("terrain_tex", arr)
		_ground_mat.set_shader_parameter("use_textures", true)
	_ground.material = _ground_mat
	if game.province_img != null:
		var pt := ImageTexture.create_from_image(game.province_img)
		_outside_mat.set_shader_parameter("province_tex", pt)
		_fog_mat.set_shader_parameter("province_tex", pt)
	_outside_mat.set_shader_parameter("map_size", game.MAP_SIZE)
	_fog_mat.set_shader_parameter("map_size", game.MAP_SIZE)


var _applied: int = -1
var _closed_t: float = 0.0
func _process(delta: float) -> void:
	if not is_open or game == null:
		# Закритий огляд довго не потрібен — віддаємо пам'ять (атлас, текстури землі, вузли); V відбудує за мить
		if _root != null and not standalone and game != null:
			_closed_t += delta
			if _closed_t >= RELEASE_S:
				release()
		return
	var vp: Vector2 = _root.get_viewport_rect().size
	var z: float = _zoom()
	if game.physics != null and game.physics.version != _applied:
		_applied = game.physics.version
		game.physics.apply_to(_ground_mat)
	var t: float = fposmod(Time.get_ticks_msec() / 1000.0, 86400.0)
	var cam_c: Vector2 = _cam - (_sc(vp) - vp * 0.5) / z   # точка карти в середині екрана (для шейдерів)
	for m in [_ground_mat, _outside_mat, _fog_mat]:
		m.set_shader_parameter("cam_pos", cam_c)
		m.set_shader_parameter("zoom", z)
		m.set_shader_parameter("view_px", vp)
	_ground_mat.set_shader_parameter("anim", t)
	_ground_mat.set_shader_parameter("flow_phase", game.physics.flow_phase if game.physics != null else 0.0)
	_outside_mat.set_shader_parameter("region_id", float(region_id))
	_fog_mat.set_shader_parameter("region_id", float(region_id))
	_outside_mat.set_shader_parameter("feather_m", 6.0 / z)
	_fog_mat.set_shader_parameter("anim", t)
	_update_fog()
	# Спрайти — у «базових» пікселях огляду цілого регіону; зсув і наближення — лише перетворення
	var off: Vector2 = _sc(vp) + (_center - _cam) * z
	for n in [_static, _live]:
		n.position = off
		n.scale = Vector2(_uz, _uz)
	var hour: float = game.clock.hour_of_day() if game.clock != null else 12.0
	var daylight: float = clampf(sin((hour - 6.0) / 12.0 * PI) * 1.4, 0.0, 1.0)
	var light: Color = Color(0.45, 0.5, 0.62).lerp(Color.WHITE, daylight)
	_static.modulate = light
	_live.modulate = light
	_grade.get_material().set_shader_parameter("strength", GRADE * load("res://ui/world_grade.gd").strength_at(hour))
	_live.queue_redraw()
	_hud.queue_redraw()
	_layout_hud(vp)
	_check_t += delta
	if _check_t >= CHECK_S:
		_check_t = 0.0
		_refresh_if_changed()


func _update_fog() -> void:
	var fl: Node = game.get("fog")
	var on: bool = fog_enabled and fl != null and fl.has_method("active") and fl.active()
	_fog.visible = on
	if not on:
		return
	if _fog_tex == null or _fog_version != fl.model.version:
		var img := Image.create_from_data(fl.model.cols, fl.model.rows, false, Image.FORMAT_R8, fl.model.cells)
		if _fog_tex == null:
			_fog_tex = ImageTexture.create_from_image(img)
			_fog_mat.set_shader_parameter("mask", _fog_tex)
		else:
			_fog_tex.update(img)
		_fog_version = fl.model.version
	_fog_mat.set_shader_parameter("cloud_m", maxf(_bbox.size.x, _bbox.size.y) * 0.7)


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
	# місто й руїни — одразу; тропи — не частіше REBUILD_MIN_S
	if quick != _sig_quick:
		_rebuild()
	elif _signature(true) != _sig and now - _last_build_t >= REBUILD_MIN_S:
		_rebuild()


## Перебудувати весь регіон (місто, ліс, гори, руїни, тропи, туман над болотами)
func _rebuild() -> void:
	var t0: int = Time.get_ticks_usec()
	_fit()
	_flats.clear()
	_items.clear()
	_shadows.clear()
	_mist.clear()
	_labels.clear()
	stats = {"trees": 0, "mountains": 0, "frame": 0, "ruins": 0, "towers": 0, "buildings": 0, "scaffolds": 0, "mist": 0, "cities": 0}
	var blocked: Array = _place_settlements()
	_place_trails()
	_place_nature(blocked)
	_place_ruins(blocked)
	_items.sort_custom(func(a, b): return a[0] < b[0])
	_sig = _signature(true)
	_sig_quick = _signature(false)
	_last_build_t = Time.get_ticks_msec() / 1000.0
	build_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	_static.queue_redraw()
	_update_info()


## Точка карти (метри) -> базові пікселі огляду (0 — центр регіону)
func _b(p: Vector2) -> Vector2:
	return (p - _center) * _fitz


func _add(key: String, foot_m: Vector2, h: float, tint: Color = Color.WHITE, by_width: bool = false) -> void:
	if not art.has(key):
		return
	var foot: Vector2 = _b(foot_m)
	var r: Rect2 = art.rect_for_width(key, foot, h) if by_width else art.rect_for(key, foot, h)
	_items.append([foot.y, key, r, tint])
	if art.has("shadow"):
		var w: float = r.size.x * 0.92
		_shadows.append(Rect2(foot + Vector2(-w * 0.5 + w * SHADOW_DX, -w * 0.13), Vector2(w, w * 0.3)))


func _inside(p: Vector2) -> bool:
	return game.province_at(p) == region_id


## Під туманом війни руїн, веж і туману над болотами не показуємо (не підказуємо, де що)
func _seen(p: Vector2) -> bool:
	var fl: Node = game.get("fog")
	return not fog_enabled or fl == null or not fl.has_method("known") or fl.known(p)


# ---------------------------------------------------------------------
# ПОСЕЛЕННЯ: план міста на поточному етапі росту, стіна за етапом, риштування наступного етапу
# ---------------------------------------------------------------------
func _place_settlements() -> Array:
	var blocked: Array = []
	var st: Node = game.get("settlements")
	if st == null:
		return blocked
	for s in st.list:
		var c: Vector2 = s["_center"]
		if not _inside(c):
			continue
		stats["cities"] += 1
		var r_px: float = float(CITY_R_PX.get(String(s.get("size", "town")), 66.0)) * _s
		var r_m: float = r_px / _fitz
		blocked.append([c, r_m * 1.25])
		var plan: Dictionary = s.get("_plan", {})
		var stage: int = 0
		var sname: String = ""
		var view: Dictionary = plan
		var progress: String = ""
		if Growth.has_growth(plan):
			var g: Dictionary = st._growth_of(s)
			stage = Growth.stage(plan, g)
			view = Growth.view(plan, stage)
			sname = Growth.stage_name(plan, stage)
			var nxt: int = Growth.next_points(plan, stage)
			if nxt > 0:
				progress = I18n.t("до «%s»: %d из %d заданий") % [Growth.stage_name(plan, stage + 1), Growth.points(g), nxt]
			_place_plan(c, r_m, view, plan, stage, g)
		elif not plan.is_empty():
			_place_plan(c, r_m, plan, plan, 0, {})
		else:
			_add("bld_house", c, r_px * 0.9, Color.WHITE, true)
		var name_line: String = String(s.get("name", ""))
		if sname != "":
			name_line += " · " + sname
		_labels.append([c + Vector2(0, r_m * 1.12), name_line, progress])
	return blocked


func _place_plan(c: Vector2, r_m: float, view: Dictionary, plan: Dictionary, stage: int, g: Dictionary) -> void:
	var wall_r: float = float(plan.get("wall_r", 40.0))
	var pc: Array = plan.get("center", [wall_r, wall_r])
	var pcv := Vector2(float(pc[0]), float(pc[1]))
	var k: float = r_m / wall_r                     # метрів огляду на клітинку плану
	var kp: float = k * _fitz                       # пікселів на клітинку плану
	var to_m := func(q: Vector2) -> Vector2: return c + (q - pcv) * k
	# Плоске: утоптана земля в межах стіни, поля, вулиці, площа
	_flats.append(["disc", _b(c), r_m * _fitz * 1.04, Color(0.33, 0.29, 0.23, 0.92)])
	for f in view.get("fields", []):
		var rr: Array = f["rect"]
		var a: Vector2 = _b(to_m.call(Vector2(rr[0], rr[1])))
		_flats.append(["tile", Rect2(a, Vector2(rr[2], rr[3]) * kp), "field"])
	for rd in view.get("roads", []):
		_flats.append(["line", _b(to_m.call(Vector2(rd["from"][0], rd["from"][1]) + Vector2(0.5, 0.5))),
			_b(to_m.call(Vector2(rd["to"][0], rd["to"][1]) + Vector2(0.5, 0.5))), maxf(1.0, float(rd.get("w", 1)) * kp * 0.8), Color(0.47, 0.4, 0.3, 0.9)])
	for sq in view.get("squares", []):
		var ci: Array = sq.get("circle", [])
		if ci.size() >= 3:
			_flats.append(["disc", _b(to_m.call(Vector2(ci[0], ci[1]))), float(ci[2]) * kp, Color(0.5, 0.45, 0.36, 0.95)])
	# Будинки поточного етапу (вид за етапом, якщо є картинка етапу)
	for b in view.get("buildings", []):
		var rr: Array = b["rect"]
		var foot: Vector2 = to_m.call(Vector2(rr[0] + rr[2] * 0.5, rr[1] + rr[3]))
		var kind: String = String(b.get("kind", "house"))
		var key: String = "bld_ruin" if kind == "ruins" else "bld_" + kind
		if not art.has(key):
			key = "bld_house"
		_add(art.stage_key(key, stage), foot, maxf(float(rr[2]) * kp * 1.25, 7.0 * _s), Color.WHITE, true)
		stats["buildings"] += 1
	for pr in view.get("props", []):
		var cells: Array = pr.get("cells", [])
		if cells.is_empty():
			continue
		var q := Vector2.ZERO
		for cc in cells:
			q += Vector2(cc[0], cc[1])
		q = q / float(cells.size()) + Vector2(0.5, 1.0)
		var pk: String = {"stall": "prop_stall", "well": "prop_well", "tech_tower": "tech_tower", "tech_wreck": "tech_wreck", "tree": "tree_broad"}.get(String(pr.get("kind", "")), "")
		if pk != "":
			var w: float = maxf(float(cells.size()) * kp * 1.6, 6.0 * _s)
			if pk == "tree_broad" or pk == "tech_tower":
				_add(pk, to_m.call(q), (24.0 if pk == "tree_broad" else 30.0) * _s)
			else:
				_add(pk, to_m.call(q), w, Color.WHITE, true)
	# Риштування: будинки наступного етапу, поки до нього йдуть завдання (частка = прогрес)
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
				_add("scaffold", to_m.call(Vector2(rr[0] + rr[2] * 0.5, rr[1] + rr[3])), maxf(float(rr[2]) * kp * 1.2, 7.0 * _s), Color.WHITE, true)
				stats["scaffolds"] += 1
	# Стіна: частокіл або камінь за етапом; брама там, де в плані
	var stone: bool = String(view.get("wall", "palisade")) == "stone"
	var seg: String = "wall_stone" if stone else "wall_palisade"
	var tower: String = "tower_stone" if stone else "tower_wood"
	var gate: String = "gate_stone" if stone else "gate_wood"
	var gate_dirs: Array = []
	for gt in plan.get("gates", []):
		var gs: Array = gt.get("cells", [])
		if gs.is_empty():
			continue
		var q := Vector2.ZERO
		for cc in gs:
			q += Vector2(cc[0], cc[1]) + Vector2(0.5, 0.5)
		q /= float(gs.size())
		gate_dirs.append((q - pcv).angle())
	var r_px: float = r_m * _fitz
	var seg_px: float = 11.0 * _s
	var n_seg: int = maxi(12, int(TAU * r_px / seg_px))
	for i in n_seg:
		var ang: float = TAU * float(i) / float(n_seg)
		var near_gate: bool = false
		for ga in gate_dirs:
			if absf(angle_difference(ang, ga)) < 0.2:
				near_gate = true
		if near_gate:
			continue
		_add(seg, c + Vector2(cos(ang), sin(ang)) * r_m, seg_px * 1.15, Color.WHITE, true)
	for ga in gate_dirs:
		_add(gate, c + Vector2(cos(ga), sin(ga)) * r_m, seg_px * 2.4, Color.WHITE, true)
	for tw in plan.get("towers", []):
		var q: Vector2 = (Vector2(tw[0], tw[1]) + Vector2(0.5, 0.5) - pcv)
		_add(tower, c + q.normalized() * r_m, seg_px * 0.95, Color.WHITE, true)


# ---------------------------------------------------------------------
# ПРИРОДА: ліс, болота, пустки, гори, рамка гір довкола регіону, туман над болотами
# ---------------------------------------------------------------------
func _place_nature(blocked: Array) -> void:
	var step_m: float = STEP_PX * _s / _fitz
	var decor: Node = game.get("decor")
	var tl: Node = game.get("trails")
	var r0 := Rect2(_bbox.position - _bbox.size * 0.06, _bbox.size * 1.12)
	var nx: int = ceili(r0.size.x / step_m)
	var ny: int = ceili(r0.size.y / step_m)
	var tree_h: float = 24.0 * _s
	for y in ny:
		for x in nx:
			var n: float = Art.seed_at(x + 9000, y + 4000, 41)
			var p := r0.position + (Vector2(x, y) + Vector2(0.15 + 0.7 * n, 0.15 + 0.7 * Art.seed_at(x, y, 43))) * step_m
			if not _inside(p) or _blocked(p, blocked):
				continue
			var b: int = game.biome_at(p)
			if b <= 1 or b == 6:
				continue
			if _on_trail(p):
				continue   # на протоптаній тропі дерев немає (як на карті гри)
			var hv: float = 0.82 + 0.36 * Art.seed_at(x, y, 47)
			match b:
				3:
					var glade: bool = decor != null and decor.has_method("glade") and decor.glade(p, b)
					if glade and n < 0.9:
						continue
					var m: float = Art.seed_at(floori(p.x / 900.0), floori(p.y / 900.0), 51)
					var key: String = "tree_pine" if n < 0.35 + m * 0.5 else ("tree_broad" if n < 0.9 else "tree_light")
					_add(key, p, tree_h * hv)
					stats["trees"] += 1
				7:
					_add("tree_cursed" if n < 0.78 else "tree_dead", p, tree_h * hv, Color(0.92, 0.86, 1.0))
					stats["trees"] += 1
				5, 9:
					if n > 0.55:
						_add("reed", p, 9.0 * _s * hv, Color(0.85, 0.8, 0.95) if b == 9 else Color.WHITE)
					elif n > 0.47:
						_add("tree_dead", p, tree_h * 0.8 * hv)
						stats["trees"] += 1
				4, 8:
					if n > 0.93:
						_add("rock", p, 9.0 * _s * hv, Color(0.86, 0.82, 0.92) if b == 8 else Color.WHITE)
					elif n > 0.88:
						_add("tree_dead", p, tree_h * 0.75 * hv)
						stats["trees"] += 1
				2:
					if n > 0.8:
						_add("tree_broad", p, tree_h * 0.9 * hv)
						stats["trees"] += 1
					elif n > 0.74:
						_add("rock", p, 7.0 * _s)
	_place_mountains(blocked)
	_place_mist()


func _blocked(p: Vector2, blocked: Array, mult: float = 1.0) -> bool:
	for b in blocked:
		if p.distance_to(b[0]) < b[1] * mult:
			return true
	return false


## Гори всередині регіону (біом 6) і рамка гір по суші одразу за межею — як рамка мальованої карти
func _place_mountains(blocked: Array) -> void:
	var step_m: float = STEP_PX * MOUNTAIN_STEP * _s / _fitz
	var pad: float = step_m * float(FRAME_CELLS + 1)
	var r0 := Rect2(_bbox.position - Vector2(pad, pad), _bbox.size + Vector2(pad, pad) * 2.0)
	var nx: int = ceili(r0.size.x / step_m)
	var ny: int = ceili(r0.size.y / step_m)
	var inside := PackedByteArray()
	inside.resize(nx * ny)
	var pts: Array = []
	pts.resize(nx * ny)
	for y in ny:
		for x in nx:
			var n: float = Art.seed_at(x + 300, y + 700, 61)
			var p := r0.position + (Vector2(x, y) + Vector2(0.2 + 0.6 * n, 0.2 + 0.6 * Art.seed_at(x, y, 63))) * step_m
			pts[y * nx + x] = p
			inside[y * nx + x] = 1 if _inside(p) else 0
	# Відстань до регіону в клітинках (хвиля від клітинок регіону, не далі FRAME_CELLS)
	var dist := PackedInt32Array()
	dist.resize(nx * ny)
	dist.fill(99)
	var q: Array = []
	for i in nx * ny:
		if inside[i] == 1:
			dist[i] = 0
			q.append(i)
	var head: int = 0
	while head < q.size():
		var i: int = q[head]
		head += 1
		if dist[i] >= FRAME_CELLS:
			continue
		var cx: int = i % nx
		var cy: int = i / nx
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
			var xx: int = cx + o.x
			var yy: int = cy + o.y
			if xx < 0 or yy < 0 or xx >= nx or yy >= ny:
				continue
			var j: int = yy * nx + xx
			if dist[j] > dist[i] + 1:
				dist[j] = dist[i] + 1
				q.append(j)
	for i in nx * ny:
		var p: Vector2 = pts[i]
		var x: int = i % nx
		var y: int = i / nx
		var n: float = Art.seed_at(x, y, 67)
		var up: float = clampf(game.height_at(p) / game.HEIGHT_MAX_M, 0.0, 1.0)
		if inside[i] == 1:
			if game.biome_at(p) != 6 or _blocked(p, blocked, 1.2):
				continue
			var hot: bool = game.is_hot(p)
			var key: String = (["mountain_hot", "mesa_hot", "mountain_hot"][int(n * 7.0) % 3] if hot
				else ("mountain_b" if up > 0.6 and n > 0.35 else ["mountain_a", "mountain_a", "ridge", "mountain_b"][int(n * 11.0) % 4]))
			_add(key, p, 62.0 * _s * (0.7 + 0.55 * up) * (0.85 + 0.3 * n))
			stats["mountains"] += 1
		elif dist[i] >= 1 and dist[i] <= FRAME_CELLS:
			var b: int = game.biome_at(p)
			if b <= 1:
				continue
			var key2: String = "mountain_b" if n > 0.6 else ("mountain_a" if n > 0.15 else "ridge")
			var hh: float = 66.0 * _s * (0.8 + 0.15 * float(dist[i])) * (0.85 + 0.3 * n)
			_add(key2, p, hh, Color(0.78, 0.8, 0.86))
			stats["frame"] += 1


## Клуби туману над болотами й проклятими землями (пливуть у _draw_live)
func _place_mist() -> void:
	var step_m: float = STEP_PX * 5.0 * _s / _fitz
	var nx: int = ceili(_bbox.size.x / step_m)
	var ny: int = ceili(_bbox.size.y / step_m)
	for y in ny:
		for x in nx:
			if _mist.size() >= MIST_MAX:
				break
			var n: float = Art.seed_at(x + 77, y + 55, 71)
			var p := _bbox.position + (Vector2(x, y) + Vector2(n, Art.seed_at(x, y, 73))) * step_m
			if not _inside(p):
				continue
			var b: int = game.biome_at(p)
			var cursed: bool = b >= 7
			if not (b == 5 or cursed) or n < (0.25 if cursed else 0.5) or not _seen(p):
				continue
			var col: Color = Color(0.72, 0.52, 0.95, 0.42) if cursed else Color(0.74, 0.82, 0.74, 0.32)
			_mist.append([_b(p), 70.0 * _s * (0.8 + 0.6 * n), n * TAU, col])
	stats["mist"] = _mist.size()


# ---------------------------------------------------------------------
# РУЇНИ, ВЕЖІ, ТРОПИ
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
		var key: String = "ruin_temple"
		if b == 7:
			key = "ruin_hall" if roll > 0.55 else "ruin_temple"
		elif b == 8:
			key = "tech_dome" if roll > 0.68 else "tech_wreck"
		var looted: bool = cast != null and Ruins.looted_now(cast.ruins_looted, site["key"], now)
		_add(key, p, float(art.heights.get(key, 28.0)) * _s, Color(0.55, 0.55, 0.6) if looted else Color.WHITE)
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
			_add("tech_tower", q, float(art.heights.get("tech_tower", 46.0)) * _s)
			stats["towers"] += 1


## Чи лежить точка на протоптаній тропі (з сусідніми клітинками групи — дерево ширше за тропу)
func _on_trail(p: Vector2) -> bool:
	if _trails_img == null:
		return false
	var c := Vector2i(floori(p.x / _trails_cm), floori(p.y / _trails_cm)) - _trails_c0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var q := c + Vector2i(dx, dy)
			if q.x >= 0 and q.y >= 0 and q.x < _trails_img.get_width() and q.y < _trails_img.get_height() and _trails_img.get_pixel(q.x, q.y).a > 0.6:
				return true
	return false


## Протоптані тропи регіону — одна картинка (клітинка троп = піксель), розтягнута на регіон
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
			img.set_pixel(cg.x - c0.x, cg.y - c0.y, Color(0.70, 0.58, 0.40, a))
		n += 1
	stats["trail_cells"] = n
	if img == null:
		return
	# Тропа вужча за клітинку на огляді — розширюємо на піксель, щоб її було видно
	_trails_img = img
	_trails_c0 = c0
	_trails_cm = cm
	_trails_tex = ImageTexture.create_from_image(img)
	_trails_rect = Rect2(_b(Vector2(c0) * cm), Vector2(w, h) * cm * _fitz)


# =====================================================================
# МАЛЮВАННЯ
# =====================================================================
func _draw_static() -> void:
	var tex: Texture2D = art.atlas
	for f in _flats:
		match f[0]:
			"disc":
				_static.draw_circle(f[1], f[2], f[3])
			"line":
				_static.draw_line(f[1], f[2], f[4], f[3])
			"tile":
				var t: Texture2D = art.textures.get(f[2])
				if t != null:
					_static.draw_texture_rect(t, f[1], true, Color(0.9, 0.9, 0.85))
	if _trails_tex != null:
		# Тінь-обведення під тропою, потім сама тропа (з кроком у пів пікселя для ширини)
		for o in [Vector2(0.8, 0.8)]:
			_static.draw_texture_rect(_trails_tex, Rect2(_trails_rect.position + o, _trails_rect.size), false, Color(0.1, 0.08, 0.05, 0.6))
		_static.draw_texture_rect(_trails_tex, _trails_rect, false, Color(1, 0.95, 0.85, 1))
	if tex == null:
		return
	var sh: Rect2 = art.regions.get("shadow", Rect2())
	if sh.size.x > 0.0:
		for r in _shadows:
			_static.draw_texture_rect_region(tex, r, sh, Color(1, 1, 1, 0.55))
	for it in _items:
		_static.draw_texture_rect_region(tex, it[2], art.regions[it[1]], it[3])


func _draw_live() -> void:
	var tex: Texture2D = art.atlas
	if tex == null:
		return
	var t: float = Time.get_ticks_msec() / 1000.0
	var mr: Rect2 = art.regions.get("mist", Rect2())
	if mr.size.x > 0.0:
		for m in _mist:
			var p: Vector2 = m[0] + Vector2(sin(t * 0.07 + m[2]) * 10.0, cos(t * 0.05 + m[2]) * 4.0) * _s
			var w: float = m[1] * (1.0 + 0.08 * sin(t * 0.2 + m[2]))
			var col: Color = m[3]
			col.a *= 0.75 + 0.25 * sin(t * 0.3 + m[2] * 2.0)
			_live.draw_texture_rect_region(tex, Rect2(p - Vector2(w, w * 0.75) * 0.5, Vector2(w, w * 0.75)), mr, col)
	# Знак героя
	var cast: Node = game.get("cast")
	if cast != null and not cast.hero.is_empty() and not cast.hero_away and art.has("hero"):
		var hp: Vector2 = cast.hero["pos"]
		if _bbox.grow(200.0).has_point(hp):
			var foot: Vector2 = _b(hp)
			var pulse: float = 0.5 + 0.5 * sin(t * 3.0)
			_live.draw_arc(foot, (10.0 + 6.0 * pulse) * _s / _uz, 0.0, TAU, 32, Color(1.0, 0.7, 0.2, 0.7 * (1.0 - pulse * 0.6)), 2.0 / _uz)
			var h: float = art.heights.get("hero", 30.0) * _s / sqrt(_uz)
			_live.draw_texture_rect_region(tex, art.rect_for("hero", foot, h), art.regions["hero"])


func _draw_hud() -> void:
	var font: Font = ThemeDB.fallback_font
	var vp: Vector2 = _root.get_viewport_rect().size
	var z: float = _zoom()
	for l in _labels:
		var sp: Vector2 = _sc(vp) + (l[0] - _cam) * z
		var fs: int = int(18 * _s)
		var w: float = font.get_string_size(l[1], HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
		_hud.draw_string_outline(font, sp - Vector2(w * 0.5, 0), l[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0, 0, 0, 0.9))
		_hud.draw_string(font, sp - Vector2(w * 0.5, 0), l[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("f0d9a0"))
		if String(l[2]) != "":
			var fs2: int = int(14 * _s)
			var w2: float = font.get_string_size(l[2], HORIZONTAL_ALIGNMENT_CENTER, -1, fs2).x
			var p2: Vector2 = sp + Vector2(-w2 * 0.5, fs * 1.1)
			_hud.draw_string_outline(font, p2, l[2], HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, 5, Color(0, 0, 0, 0.9))
			_hud.draw_string(font, p2, l[2], HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, Color("d8cfb6"))


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
	_hint.text = (I18n.t("регион %d · PgUp/PgDn или клик по соседнему — другой регион · колесо — масштаб · перетащить — сдвиг · %s — закрыть") % [region_id,
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


## Клік по сусідньому (затемненому) регіону — відкрити його
func _click(sp: Vector2) -> void:
	var vp: Vector2 = _root.get_viewport_rect().size
	var p: Vector2 = _cam + (sp - _sc(vp)) / _zoom()
	var id: int = game.province_at(p)
	if id > 0 and id != region_id:
		open(id)


## Для тестів і знімків: перебудувати зараз
func rebuild_now() -> void:
	_rebuild()

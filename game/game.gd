extends Node2D
## Головна сцена гри: плоская 2D-карта мира, камера, підказка, меню паузи.
## Карта нарисована (art/map/map_color.png); биомы, области и регионы — отдельные слои
## (art/map/map_biomes.png, map_provinces.png, map_regions.png, названия в map_names.json).
## Вода (море, озёра, реки) — по рисунку: art/map/map_water.png, сглаженная маска вдвое мельче доски.
## Жаркие горы (оранжевые на рисунке) — art/map/map_hot.png: там всегда на HOT_BONUS_C жарче.
## Текстуры биомов вблизи — art/terrain/*.png (слои TEX_* в map_shaders.gd).
## Все растры выровнены по доске-шестиугольнику инструментом tools/make_new_map.py.
## Мир плоский: координаты X Y в метрах, одно время суток на всю карту. Облака и дождь
## — простая погода по сезону и биому (world_physics.tscn, weather/simple_weather.gd) в окне ATM_ORIGIN / ATM_SPAN.
## Шейдер карты в map_shaders.gd.

const Board := preload("res://board.gd")
const ComicUI := preload("res://ui/comic_ui.gd")
const MENU_SCENE := "res://main_menu.tscn"
const MAP_COLOR_FILE := "res://art/map/map_color.png"
const MAP_BIOMES_FILE := "res://art/map/map_biomes.png"
const MAP_WATER_FILE := "res://art/map/map_water.png"
const MAP_PROVINCES_FILE := "res://art/map/map_provinces.png"
const MAP_REGIONS_FILE := "res://art/map/map_regions.png"
const MAP_NAMES_FILE := "res://art/map/map_names.json"
const MAP_HOT_FILE := "res://art/map/map_hot.png"
const MAP_HEIGHT_FILE := "res://art/map/map_height.png"
const HEIGHT_MAX_M: float = 900.0      # высота белого в map_height.png [Q19: не баланс, оставлено]; шейдер рисует светотень с превышением ×2
# Текстуры биомов, по порядку слоёв массива terrain_tex (последний — маски свечения)
const TERRAIN_FILES: Array = ["t00_water", "t01_coast", "t02_forest", "t03_field1", "t04_field2",
	"t05_wasteland", "t06_swamp", "t07_mountains", "t08_hot_mountains", "t09_rad_forest",
	"t10_rad_wasteland", "t11_rad_swamp", "t12_glow"]
# Жаркие горы: насколько там теплее, чем обычно для этого места
const HOT_BONUS_C: float = 40.0
# Фон екрана завантаження
const LOADING_BG := "res://art/menu_bg.jpg"
const WorldSave := preload("res://world_save.gd")
const AUTOSAVE_SEC: float = 300.0

const ClockScene := preload("res://game_clock.tscn")
const PhysicsScene := preload("res://world_physics.tscn")
# Персонажи: герой и НПС на общих правилах (characters/)
const CastScript := preload("res://characters/cast.gd")
const SettlementsScript := preload("res://world/settlements.gd")
const TrailsScript := preload("res://world/trails_layer.gd")

# Прежняя развёртка 36000 x 18000 м: в ней живёт модель атмосферы
const SRC_SIZE := Vector2(36000.0, 18000.0)
# Игровая карта: доска-шестиугольник плоской стороной вверх (board.gd)
const MAP_SIZE := Vector2(41625.0, 36000.0)
# Широта плоского мира для солнца и окно модели атмосферы (те же числа в map_shaders.gd)
const MAP_LAT_DEG: float = 45.0
const ATM_ORIGIN := Vector2(13900.0, 2000.0)
const ATM_SPAN := Vector2(8200.0, 5000.0)

# Найбільше наближення: 40 пікселів на метр
const MAX_ZOOM := 40.0
const ZOOM_STEP := 1.25
const CAMERA_SPEED := 500.0

# Биомы слоя map_biomes.png (номер = значение пикселя)
static var BIOME_NAMES := [I18n.t("за краем мира"), I18n.t("вода"), I18n.t("берег"), I18n.t("лес"), I18n.t("пустошь"), I18n.t("болото"), I18n.t("горы"),
	I18n.t("проклятый лес"), I18n.t("проклятая пустошь"), I18n.t("проклятое болото")]

# Камера в метрах і масштаб у пікселях на метр
var cam_pos := Vector2(20812.5, 18000.0)
var zoom: float = 0.04
var min_zoom: float = 0.03
var noise_image: Image                 # шум шейдера (noise_tex): декор читает те же поляны, что рисует шейдер
var global_map: bool = false           # M: обзор всего мира, камера не следует за героем
var _gm_zoom: float = 1.0
var _gm_cam := Vector2.ZERO
var show_clouds: bool = true
var clock: GameClock
var physics: WorldPhysics
var event_text: String = ""
var event_timer: float = 0.0

var render_mat := ShaderMaterial.new()
var biome_img: Image
var water_img: Image
var hot_img: Image
var height_img: Image
var province_img: Image
var region_img: Image
var map_names: Dictionary = {}   # {"provinces": {id: {name, regions}}, "regions": {id: {province, code}}}
# Границы на карте (клавиша B): 0 нет, 1 области, 2 области и регионы
var border_mode: int = 0
static var BORDER_NAMES := [I18n.t("скрыты"), I18n.t("области"), I18n.t("области и регионы")]
var frame_count: int = 0
var applied_version: int = -1

var hud_label: Label
var hud_panel: PanelContainer
var hud_scroll: ScrollContainer
var details_visible: bool = false
var pointer_in_window: bool = true
var pause_panel: Control
var menu_open := false
# Екран завантаження і стан запуску
var ready_done: bool = false
var loading_root: Control
var loading_bar: ProgressBar
var loading_label: Label
var loading_pct: Label
var missing_files: Array = []
# Маркер у центрі екрана: дані панелі для нього, а не під курсором (клавіша O)
var observer_mode: bool = false
var observer_marker: Node2D
var terrain_layer: CanvasLayer
var _save_data: Dictionary = {}
var _autosave_t: float = 0.0
var typing: bool = false
var goto_panel: PanelContainer
var goto_edit: LineEdit
var goto_status: Label
var cast: Node2D
var settlements: Node2D     # города и поселения на общей карте (world/settlements.gd)
var trails: Node2D          # протоптанные дороги (world/trails_layer.gd): появляются там, где ходят


func _ready() -> void:
	_build_loading_screen()
	await get_tree().process_frame
	await _startup()


# Оновлює смугу завантаження
func _set_progress(frac: float, text: String) -> void:
	loading_bar.value = frac * 100.0
	loading_pct.text = "%d %%" % int(frac * 100.0)
	loading_label.text = text


# Запуск світу по етапах. Між етапами кадр малюється, тому смуга рухається
func _startup() -> void:
	_set_progress(0.05, I18n.t("Часы и погода"))
	await get_tree().process_frame
	clock = ClockScene.instantiate()
	add_child(clock)
	# Поки світ вантажиться, ігровий час стоїть
	clock.paused = true
	physics = PhysicsScene.instantiate()
	add_child(physics)
	# «Продолжить» в главном меню: время и погода из сохранения ставятся до запуска физики
	if Engine.has_meta("aw_load") and String(Engine.get_meta("aw_load")) != "":
		var slot: String = String(Engine.get_meta("aw_load"))
		Engine.set_meta("aw_load", "")
		_save_data = WorldSave.read(slot)
		if not _save_data.is_empty():
			WorldSave.apply_early(self, _save_data)
	physics.game = self
	physics.setup(clock, SRC_SIZE.x, SRC_SIZE.y)
	clock.season_changed.connect(_on_season_changed)

	# Масштаб, при якому видно всю карту
	var view_size: Vector2 = get_viewport_rect().size
	var fit: float = minf(view_size.x / MAP_SIZE.x, view_size.y / MAP_SIZE.y)
	min_zoom = fit * 0.9
	zoom = fit * 0.97

	_set_progress(0.15, I18n.t("Карта мира"))
	await get_tree().process_frame
	_build_map()
	_build_ui()
	# Протоптанные дороги — под деревьями, поселениями и персонажами
	trails = TrailsScript.new()
	trails.game = self
	add_child(trails)
	var decor := preload("res://storybook/world_decor.gd").new()
	decor.game = self
	add_child(decor)
	# Поселения рисуются под персонажами
	settlements = SettlementsScript.new()
	add_child(settlements)
	cast = CastScript.new()
	add_child(cast)
	cast.setup(self)
	settlements.setup(self)
	# Два кадри: шейдер компілюється при першому малюванні
	await get_tree().process_frame
	await get_tree().process_frame

	clock.paused = false

	_set_progress(1.0, I18n.t("Мир готов"))
	await get_tree().create_timer(0.3).timeout
	var tw := create_tween()
	tw.tween_property(loading_root, "modulate:a", 0.0, 0.5)
	await tw.finished
	loading_root.get_parent().queue_free()
	ready_done = true
	if not _save_data.is_empty():
		WorldSave.apply_late(self, _save_data)
		_save_data = {}
		event_text = I18n.t("Мир загружен")
		event_timer = 5.0


func _process(delta: float) -> void:
	if not ready_done:
		return
	frame_count += 1
	if event_timer > 0.0:
		event_timer -= delta
	_autosave_t += delta
	if _autosave_t >= AUTOSAVE_SEC:
		_autosave_t = 0.0
		save_world()
	# Поки меню відкрите, камера стоїть. Час іде далі: світ не завмирає
	# Пока героем управляет игрок, камера идёт за ним (characters/cast.gd)
	if not menu_open and not typing and not (cast != null and cast.controls_hero):
		var dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		if Input.is_physical_key_pressed(KEY_A): dir.x -= 1
		if Input.is_physical_key_pressed(KEY_D): dir.x += 1
		if Input.is_physical_key_pressed(KEY_W): dir.y -= 1
		if Input.is_physical_key_pressed(KEY_S): dir.y += 1
		dir = dir.limit_length(1.0)
		if dir != Vector2.ZERO:
			# Швидкість в метрах залежить від масштабу, щоб на екрані вона була однакова
			cam_pos += dir * CAMERA_SPEED / zoom * delta
			_clamp_camera()
	_send_to_shaders()
	_update_hud()


# Будує екран завантаження: фон, назва, смуга прогресу, поточний етап
func _build_loading_screen() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	loading_root = Control.new()
	loading_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loading_root.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(loading_root)

	var back := ColorRect.new()
	back.color = Color("14110e")
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loading_root.add_child(back)
	if ResourceLoader.exists(LOADING_BG):
		var pic := TextureRect.new()
		pic.texture = load(LOADING_BG)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		loading_root.add_child(pic)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loading_root.add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loading_root.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(560, 0)
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)

	var title := Label.new()
	title.text = "Ambers World"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color("d8cfb0"))
	box.add_child(title)
	var sub := Label.new()
	sub.text = I18n.t("Создание мира")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", Color("8a8470"))
	box.add_child(sub)

	loading_bar = ProgressBar.new()
	loading_bar.custom_minimum_size = Vector2(560, 20)
	loading_bar.max_value = 100.0
	loading_bar.show_percentage = false
	loading_bar.custom_minimum_size.y = 28.0
	ComicUI.bar_styles(loading_bar)
	box.add_child(loading_bar)

	var row := HBoxContainer.new()
	box.add_child(row)
	loading_label = Label.new()
	loading_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	loading_label.add_theme_color_override("font_color", Color("d8cfb0"))
	row.add_child(loading_label)
	loading_pct = Label.new()
	loading_pct.add_theme_color_override("font_color", Color("d8cfb0"))
	row.add_child(loading_pct)
	_set_progress(0.0, I18n.t("Запуск"))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and ready_done:
		save_world()
	if what == NOTIFICATION_WM_MOUSE_EXIT:
		pointer_in_window = false
	elif what == NOTIFICATION_WM_MOUSE_ENTER:
		pointer_in_window = true


func _input(event: InputEvent) -> void:
	if not ready_done:
		return
	# Latin H switches details even when the pause menu is open.
	# Coordinate text entry retains ordinary typing.
	if not typing and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_H:
		details_visible = not details_visible
		_update_hud()
		get_viewport().set_input_as_handled()


func _pointer_over_map() -> bool:
	return pointer_in_window and get_viewport_rect().has_point(get_viewport().get_mouse_position()) and get_viewport().gui_get_hovered_control() == null


func _unhandled_input(event: InputEvent) -> void:
	if not ready_done:
		return
	# Поки відкрите поле координат, Esc закриває його, інші клавіші йдуть у поле
	if typing:
		if event.is_action_pressed("ui_cancel"):
			_close_goto()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		_toggle_menu()
		return
	if menu_open:
		return

	# Колесо миші: зум до курсора
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(event.position, ZOOM_STEP)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(event.position, 1.0 / ZOOM_STEP)

	if event is InputEventKey and event.pressed:
		# Клавіші + і -: зум до центру екрана
		var center: Vector2 = get_viewport_rect().size / 2.0
		if event.keycode == KEY_EQUAL or event.keycode == KEY_KP_ADD:
			_zoom_at(center, ZOOM_STEP)
		if event.keycode == KEY_MINUS or event.keycode == KEY_KP_SUBTRACT:
			_zoom_at(center, 1.0 / ZOOM_STEP)
		if event.echo:
			return
		# Керування часом
		if event.keycode == KEY_P:
			clock.paused = not clock.paused
		if event.physical_keycode == KEY_BRACKETRIGHT:
			clock.change_speed(1)
		if event.physical_keycode == KEY_BRACKETLEFT:
			clock.change_speed(-1)
		# Маркер у центрі екрана
		if event.physical_keycode == KEY_O:
			observer_mode = not observer_mode
			observer_marker.visible = observer_mode
		# M — глобальная карта (весь мир), ещё раз — назад к герою; Shift+M — переход по координатам X Y
		if event.physical_keycode == KEY_M:
			if event.shift_pressed:
				_open_goto()
			else:
				toggle_global_map()
		# Швидкість погоди
		if event.physical_keycode == KEY_PERIOD:
			physics.change_weather_speed(1)
		if event.physical_keycode == KEY_COMMA:
			physics.change_weather_speed(-1)
		# Хмари згори
		if event.physical_keycode == KEY_C:
			show_clouds = not show_clouds
		# Границы областей и регионов
		if event.physical_keycode == KEY_B:
			border_mode = (border_mode + 1) % BORDER_NAMES.size()
			event_text = I18n.t("Границы: ") + BORDER_NAMES[border_mode]
			event_timer = 3.0


# Точка, для якої пишуться дані в панелі: центр екрана з маркером, інакше курсор
func _probe_world() -> Vector2:
	if observer_mode:
		return cam_pos
	return _mouse_world()


# Номер из слоя-растра в точке карты (0 — за краем или нет слоя)
func _id_at(img: Image, p: Vector2) -> int:
	if img == null or not Board.inside(p):
		return 0
	var x: int = clampi(int(p.x / MAP_SIZE.x * img.get_width()), 0, img.get_width() - 1)
	var y: int = clampi(int(p.y / MAP_SIZE.y * img.get_height()), 0, img.get_height() - 1)
	return int(round(img.get_pixel(x, y).r * 255.0))


# Высота над низиной в метрах (art/map/map_height.png, билинейно, как в шейдере)
func height_at(p: Vector2) -> float:
	return _soft_at(height_img, p) * HEIGHT_MAX_M


# Вода в точке: маска map_water.png, читается билинейно, как в шейдере (water_at); 0,5 и выше — вода
func water_at(p: Vector2) -> float:
	return _soft_at(water_img, p)


# Жаркие горы в точке: маска map_hot.png так же, как вода; на воде зоны нет
func is_hot(p: Vector2) -> bool:
	return _soft_at(hot_img, p) >= 0.5 and water_at(p) < 0.5


# Температура в точке, °C: модель погоды для этого места, в жарких горах на HOT_BONUS_C выше
func temperature_at(p: Vector2) -> float:
	var ll: Vector2 = atm_latlon(p)
	var t: float = physics.temperature_at(ll.x, ll.y)
	if is_nan(t):
		return t
	return t + (HOT_BONUS_C if is_hot(p) else 0.0)


# Строка температуры для подсказки
func temperature_line(p: Vector2) -> String:
	var t: float = temperature_at(p)
	if is_nan(t):
		return ""
	var s: String = "%+d °C" % int(round(t))
	var wn: String = str(physics.weather_here(p).get("name", ""))
	if wn != "":
		s += ", " + wn
	if is_hot(p):
		s += I18n.t("   жаркие горы (+%d °C)") % int(HOT_BONUS_C)
	return s


# Сглаженная маска (L8) в точке, билинейно, как textureLod с filter_linear в шейдере
func _soft_at(img: Image, p: Vector2) -> float:
	if img == null:
		return 0.0
	var w: int = img.get_width()
	var h: int = img.get_height()
	var q: Vector2 = Vector2(p.x / MAP_SIZE.x * w, p.y / MAP_SIZE.y * h) - Vector2(0.5, 0.5)
	var x0: int = clampi(int(floor(q.x)), 0, w - 1)
	var y0: int = clampi(int(floor(q.y)), 0, h - 1)
	var x1: int = mini(x0 + 1, w - 1)
	var y1: int = mini(y0 + 1, h - 1)
	var fx: float = clampf(q.x - floor(q.x), 0.0, 1.0)
	var fy: float = clampf(q.y - floor(q.y), 0.0, 1.0)
	var top: float = lerpf(img.get_pixel(x0, y0).r, img.get_pixel(x1, y0).r, fx)
	var bot: float = lerpf(img.get_pixel(x0, y1).r, img.get_pixel(x1, y1).r, fx)
	return lerpf(top, bot, fy)


# Биом в точке карты (номер из BIOME_NAMES): вода по рисунку, иначе слой суши map_biomes.png
func biome_at(p: Vector2) -> int:
	var b: int = _id_at(biome_img, p)
	if b == 0:
		return 0
	if water_at(p) >= 0.5:
		return 1
	return b


# Область (1..31) и регион (1..117) в точке карты; 0 — море
func province_at(p: Vector2) -> int:
	return _id_at(province_img, p)


func region_at(p: Vector2) -> int:
	return _id_at(region_img, p)


func province_name(id: int) -> String:
	return String(map_names.get("provinces", {}).get(str(id), {}).get("name", ""))


func region_code(id: int) -> String:
	return String(map_names.get("regions", {}).get(str(id), {}).get("code", ""))


# Подпись места: «Область, R007» или пусто над морем
func place_line(p: Vector2) -> String:
	var pr: int = province_at(p)
	if settlements != null:
		var st: Dictionary = settlements.settlement_at(p)
		if not st.is_empty():
			return "%s %s, %s" % [settlements.size_name(st), st["name"], province_name(pr)]
	if pr == 0:
		return ""
	return I18n.t("%s, регион %s") % [province_name(pr), region_code(region_at(p))]


# Точка карты -> точка модели атмосферы (прежняя развёртка S), как в map_shaders.gd
func atm_of(p: Vector2) -> Vector2:
	return ATM_ORIGIN + p / MAP_SIZE * ATM_SPAN


# Широта и долгота модели атмосферы для точки карты, радианы
func atm_latlon(p: Vector2) -> Vector2:
	var s: Vector2 = atm_of(p)
	return Vector2(physics.lat_of(s.y), physics.lon_of(s.x))


# Реакція на сигнал годинника: приклад того, як на нього підключаються алгоритми
func _on_season_changed(season: int) -> void:
	event_text = I18n.t("Наступила пора года: %s") % GameClock.SEASON_NAMES[season]
	event_timer = 4.0


# Змінює зум так, щоб точка під курсором лишалась на місці
func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var new_zoom: float = clampf(zoom * factor, min_zoom, MAX_ZOOM)
	if is_equal_approx(new_zoom, zoom):
		return
	var offset: Vector2 = screen_pos - get_viewport_rect().size / 2.0
	var world_point: Vector2 = cam_pos + offset / zoom
	zoom = new_zoom
	cam_pos = world_point - offset / zoom
	_clamp_camera()


# Камера не уходит за край мира (за краем космос)
func _clamp_camera() -> void:
	cam_pos = Board.clamp_inside(cam_pos)


func _mouse_world() -> Vector2:
	return _screen_world(get_viewport().get_mouse_position())


# Точка земли под точкой экрана
func _screen_world(sp: Vector2) -> Vector2:
	var offset: Vector2 = sp - get_viewport_rect().size / 2.0
	return cam_pos + offset / zoom


# Точка карты (метры) -> пиксели экрана
func world_to_screen(p: Vector2) -> Vector2:
	return (p - cam_pos) * zoom + get_viewport_rect().size * 0.5


# Відкриває поле для переходу за координатами X Y
## M: показать весь мир; повторно — вернуть прежний масштаб (камера снова у героя)
func toggle_global_map() -> void:
	global_map = not global_map
	if global_map:
		_gm_zoom = zoom
		_gm_cam = cam_pos
		var vs: Vector2 = get_viewport_rect().size
		zoom = clampf(minf(vs.x / MAP_SIZE.x, vs.y / MAP_SIZE.y) * 0.97, min_zoom, MAX_ZOOM)
		cam_pos = MAP_SIZE * 0.5
		event_text = I18n.t("Глобальная карта · M — назад")
	else:
		zoom = _gm_zoom
		cam_pos = _gm_cam
		event_text = ""
	event_timer = 3.0
	_clamp_camera()


func _open_goto() -> void:
	typing = true
	goto_edit.text = ""
	goto_status.text = I18n.t("X и Y в метрах через пробел: от 0 до %d и от 0 до %d") % [int(MAP_SIZE.x), int(MAP_SIZE.y)]
	goto_panel.visible = true
	goto_edit.grab_focus()


func _close_goto() -> void:
	typing = false
	goto_panel.visible = false
	goto_edit.release_focus()


# Enter у полі: розбирає X Y (метри карты) і переносить камеру
func _on_goto_submitted(text: String) -> void:
	var parts: PackedStringArray = text.strip_edges().replace(",", " ").replace(";", " ").split(" ", false)
	if parts.size() != 2 or not parts[0].is_valid_float() or not parts[1].is_valid_float():
		goto_status.text = I18n.t("Нужно два числа: X Y, например 20812 18000")
		return
	var p := Vector2(parts[0].to_float(), parts[1].to_float())
	if not Board.inside(p):
		goto_status.text = I18n.t("Точка %d, %d за краем мира") % [int(p.x), int(p.y)]
		return
	cam_pos = p
	zoom = clampf(8.0, min_zoom, MAX_ZOOM)
	_clamp_camera()
	_close_goto()


# Гарний запис числа метрів
func _fmt(v: float) -> String:
	if v >= 10.0:
		return str(int(v))
	return "%.2f" % v


# Передає камеру, масштаб і (коли вони змінились) значення фізики в шейдер
func _send_to_shaders() -> void:
	if physics.version != applied_version:
		applied_version = physics.version
		physics.apply_to(render_mat)
	render_mat.set_shader_parameter("zoom", zoom)
	render_mat.set_shader_parameter("anim", fposmod(Time.get_ticks_msec() / 1000.0, 86400.0))
	render_mat.set_shader_parameter("flow_phase", physics.flow_phase)
	render_mat.set_shader_parameter("cam_pos", cam_pos)
	render_mat.set_shader_parameter("view_px", get_viewport_rect().size)
	render_mat.set_shader_parameter("show_clouds", 1.0 if show_clouds else 0.0)
	render_mat.set_shader_parameter("border_mode", border_mode)


# Нарисованная карта и слой биомов -> шейдер на весь экран
func _build_map() -> void:
	var shader := Shader.new()
	shader.code = MapShaders.SHADER
	render_mat.shader = shader
	var noise_tex: ImageTexture = _make_noise_texture()
	render_mat.set_shader_parameter("noise_tex", noise_tex)
	render_mat.set_shader_parameter("rand_tex", noise_tex)
	render_mat.set_shader_parameter("map_size", MAP_SIZE)
	if ResourceLoader.exists(MAP_COLOR_FILE):
		render_mat.set_shader_parameter("map_tex", load(MAP_COLOR_FILE))
	else:
		missing_files.append(MAP_COLOR_FILE)
	biome_img = _load_id_layer(MAP_BIOMES_FILE, "biome_tex")
	water_img = _load_id_layer(MAP_WATER_FILE, "water_tex")
	hot_img = _load_id_layer(MAP_HOT_FILE, "hot_tex")
	height_img = _load_id_layer(MAP_HEIGHT_FILE, "height_tex")
	render_mat.set_shader_parameter("height_max", HEIGHT_MAX_M * 2.2)
	_load_terrain_textures()
	province_img = _load_id_layer(MAP_PROVINCES_FILE, "province_tex")
	region_img = _load_id_layer(MAP_REGIONS_FILE, "region_tex")
	if FileAccess.file_exists(MAP_NAMES_FILE):
		var parsed: Variant = I18n.tree(JSON.parse_string(FileAccess.get_file_as_string(MAP_NAMES_FILE)))
		if parsed is Dictionary:
			map_names = parsed
	else:
		missing_files.append(MAP_NAMES_FILE)
	_send_to_shaders()
	# Шар за інтерфейсом, на ньому прямокутник на весь екран з шейдером
	terrain_layer = CanvasLayer.new()
	terrain_layer.layer = -1
	add_child(terrain_layer)
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = render_mat
	terrain_layer.add_child(rect)


# Текстуры биомов -> массив слоёв для шейдера (одинакового размера, с мипмапами, повтор задаёт шейдер)
func _load_terrain_textures() -> void:
	var imgs: Array[Image] = []
	for n in TERRAIN_FILES:
		var path: String = "res://art/terrain/%s.png" % n
		if not ResourceLoader.exists(path):
			missing_files.append(path)
			render_mat.set_shader_parameter("use_textures", false)
			return
		var tex: Texture2D = load(path)
		var img: Image = tex.get_image()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGB8)
		if img.get_width() != 512 or img.get_height() != 512:
			img.resize(512, 512, Image.INTERPOLATE_LANCZOS)
		img.generate_mipmaps()
		imgs.append(img)
	var arr := Texture2DArray.new()
	arr.create_from_images(imgs)
	render_mat.set_shader_parameter("terrain_tex", arr)
	render_mat.set_shader_parameter("use_textures", true)


# Слой номеров (L8, без сжатия) -> картинка для игры и текстура шейдера
func _load_id_layer(path: String, uniform_name: String) -> Image:
	if not ResourceLoader.exists(path):
		missing_files.append(path)
		return null
	var tex: Texture2D = load(path)
	var img: Image = tex.get_image()
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_L8:
		img.convert(Image.FORMAT_L8)
	render_mat.set_shader_parameter(uniform_name, ImageTexture.create_from_image(img))
	return img


# Текст у куті: дата, час, біом під курсором; H — подробности (погода, X Y)
func _update_hud() -> void:
	var hour: float = clock.hour_of_day()
	var hh: int = int(hour)
	var mm: int = int((hour - float(hh)) * 60.0)
	var compact: String = "%d %s %d   %02d:%02d\n%s" % [clock.day_of_month(), GameClock.MONTH_NAMES[clock.month()], clock.year(), hh, mm, GameClock.SEASON_NAMES[clock.season()]]
	var m: Vector2 = _probe_world()
	var over: bool = (observer_mode or _pointer_over_map()) and Board.inside(m)
	if over:
		compact += "\n%s   X %d  Y %d" % [BIOME_NAMES[biome_at(m)], int(m.x), int(m.y)]
		var tl: String = temperature_line(m)
		if tl != "":
			compact += "\n" + tl
		var place: String = place_line(m)
		if place != "":
			compact += "\n" + place
	if not details_visible:
		if event_timer > 0.0:
			compact += "\n" + event_text
		hud_label.text = compact
		_layout_hud()
		return
	var text: String = compact + "\n\nFPS %d\n" % Engine.get_frames_per_second()
	var speed_txt: String = GameClock.SPEED_NAMES[clock.speed_index]
	if clock.paused:
		speed_txt = I18n.t("ПАУЗА ВРЕМЕНИ")
	text += I18n.t("Время: %s\n") % speed_txt
	text += I18n.t("Луна: %s (освещено %d%%)\n") % [physics.moon_name(), int(physics.moon_illum * 100.0)]
	text += physics.status_text() + "\n"
	var lat: float = deg_to_rad(MAP_LAT_DEG)
	var sun_el: float = physics.sun_elevation_deg_at(lat, 0.0)
	var sun_state: String = I18n.t("ночь")
	if sun_el > 0.0:
		sun_state = I18n.t("день")
	if sun_el <= 0.0 and sun_el > -12.0:
		sun_state = I18n.t("сумерки")
	text += I18n.t("Солнце: %d° над горизонтом (%s)   Длина дня %.1f ч\n") % [int(sun_el), sun_state, physics.day_length_at(lat)]
	if event_timer > 0.0:
		text += event_text + "\n"
	text += "\n"
	text += I18n.t("Данные для центра экрана\n") if observer_mode else I18n.t("Данные под курсором\n")
	if Board.inside(m):
		text += "X %d   Y %d\n" % [int(m.x), int(m.y)]
		text += I18n.t("Биом: %s\n") % BIOME_NAMES[biome_at(m)]
		var tl2: String = temperature_line(m)
		if tl2 != "":
			text += I18n.t("Температура: %s\n") % tl2
		var pl: String = place_line(m)
		if pl != "":
			text += I18n.t("Область: %s\n") % pl
		var ll: Vector2 = atm_latlon(m)
		var wnd: Vector2 = physics.wind_at(ll.x, ll.y)
		text += I18n.t("Ветер %.1f м/с, с %s   Давление %d гПа\n") % [wnd.length(), physics.wind_from_name(wnd), int(physics.pressure_at(ll.x, ll.y))]
		text += I18n.t("Осадков в этом году: %d мм\n") % int(physics.rain_year_at(ll.x, ll.y))
	else:
		text += I18n.t("За краем мира\n")
	text += I18n.t("Центр экрана: X %d   Y %d   1 пиксель = %s м\n") % [int(cam_pos.x), int(cam_pos.y), _fmt(1.0 / zoom)]
	text += _hint_line()
	for mf in missing_files:
		text += I18n.t("\nНет файла ") + String(mf).replace("res://", "")
	hud_label.text = text
	_layout_hud()


func _hint_line() -> String:
	return I18n.t("WASD/стрелки камера, колесо масштаб, P пауза, [ ] скорость времени, C облака, B границы, M переход к X Y, O маркер в центре, H подробности, , . скорость погоды; G герой, Shift бег, Z сон, E пить, F еда, T лечиться у лекаря, I лист персонажа; у поселения E войти, Esc мимо")


# Випадкова текстура 256 x 256: з неї будується весь шум
func _make_noise_texture() -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var base := PackedFloat32Array()
	base.resize(256 * 256)
	for i in 256 * 256:
		base[i] = rng.randf()
	var noise_img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	for y in 256:
		for x in 256:
			var r: float = base[y * 256 + x]
			# Канал G це канал R зі зсувом (37, 17): з нього виходить тривимірний шум на кулі
			var gg: float = base[((y + 17) % 256) * 256 + (x + 37) % 256]
			noise_img.set_pixel(x, y, Color(r, gg, rng.randf(), rng.randf()))
	noise_image = noise_img
	return ImageTexture.create_from_image(noise_img)


func _layout_hud() -> void:
	if observer_marker != null:
		observer_marker.position = get_viewport_rect().size * 0.5
	if hud_panel == null:
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var width: float = minf(350.0 if not details_visible else 800.0, maxf(viewport_size.x - 28.0, 160.0))
	var compact_h: float = 160.0
	var height: float = minf(compact_h if not details_visible else 560.0, maxf(viewport_size.y - 28.0, 80.0))
	hud_panel.custom_minimum_size = Vector2.ZERO
	hud_panel.size = Vector2(width, height)
	hud_panel.position = Vector2(maxf(14.0, viewport_size.x - width - 14.0), 14.0)


# Будує інтерфейс: текст у куті і меню паузи
func _build_ui() -> void:
	var ui_layer := CanvasLayer.new()
	ui_layer.layer = 10
	add_child(ui_layer)

	hud_panel = PanelContainer.new()
	hud_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	hud_panel.add_theme_stylebox_override("panel", ComicUI.panel(18.0, 0.92))
	ui_layer.add_child(hud_panel)
	hud_scroll = ScrollContainer.new()
	hud_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hud_panel.add_child(hud_scroll)
	hud_label = Label.new()
	hud_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud_label.add_theme_font_size_override("font_size", 15)
	hud_label.add_theme_color_override("font_color", Color("d8cfb0"))
	hud_scroll.add_child(hud_label)
	_layout_hud()

	# Маркер спостерігача: кільце з точкою в центрі екрана
	observer_marker = Node2D.new()
	observer_marker.visible = false
	ui_layer.add_child(observer_marker)
	var ring := Line2D.new()
	ring.width = 2.0
	ring.default_color = Color(1.0, 0.92, 0.55, 0.95)
	ring.closed = true
	for s in 28:
		var ang: float = TAU * float(s) / 28.0
		ring.add_point(Vector2(cos(ang), sin(ang)) * 13.0)
	observer_marker.add_child(ring)
	var dot := Line2D.new()
	dot.width = 5.0
	dot.default_color = Color(1.0, 0.92, 0.55, 0.95)
	dot.add_point(Vector2(-0.5, 0.0))
	dot.add_point(Vector2(0.5, 0.0))
	observer_marker.add_child(dot)

	# Поле для переходу за координатами X Y (клавіша M)
	goto_panel = PanelContainer.new()
	goto_panel.position = Vector2(400, 14)
	goto_panel.custom_minimum_size = Vector2(520, 0)
	goto_panel.visible = false
	ui_layer.add_child(goto_panel)
	var gbox := VBoxContainer.new()
	goto_panel.add_child(gbox)
	var glabel := Label.new()
	glabel.text = I18n.t("Перейти к точке X Y (Enter, Esc отмена)")
	gbox.add_child(glabel)
	goto_edit = LineEdit.new()
	goto_edit.placeholder_text = "20812 18000"
	goto_edit.text_submitted.connect(_on_goto_submitted)
	gbox.add_child(goto_edit)
	goto_status = Label.new()
	goto_status.add_theme_font_size_override("font_size", 13)
	gbox.add_child(goto_status)

	pause_panel = Control.new()
	pause_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_panel.visible = false
	ui_layer.add_child(pause_panel)

	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_panel.add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_panel.add_child(center)

	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", ComicUI.panel(34.0))
	ComicUI.tech_plate(frame)
	center.add_child(frame)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	frame.add_child(box)

	var title := Label.new()
	title.text = I18n.t("Меню")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	box.add_child(title)

	_add_menu_button(box, I18n.t("Продолжить"), _toggle_menu)
	_add_menu_button(box, I18n.t("Сохранить"), func() -> void:
		var ok: bool = save_world(true)
		event_text = I18n.t("Мир сохранён") if ok else I18n.t("Не удалось сохранить мир")
		event_timer = 4.0
		_toggle_menu())
	_add_menu_button(box, I18n.t("В меню"), _on_exit_pressed)


# Створює кнопку меню
func _add_menu_button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(240, 48)
	button.add_theme_font_size_override("font_size", 20)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


# Показує або ховає меню. Час при цьому НЕ зупиняється
func _toggle_menu() -> void:
	menu_open = not menu_open
	pause_panel.visible = menu_open


# Тільки ця кнопка виходить у головне меню
func _on_exit_pressed() -> void:
	# Выход в главное меню всегда сохраняет мир в автосохранение
	save_world()
	get_tree().change_scene_to_file(MENU_SCENE)


func pointer_over_map() -> bool:
	return _pointer_over_map()


# Сохранение мира: время, погода и камера (world_save.gd)
func save_world(manual: bool = false) -> bool:
	if not ready_done or clock == null:
		return false
	return WorldSave.write(self, manual)

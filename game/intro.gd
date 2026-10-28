extends Control
## Заставка перед главным меню (только синематик и проверка целостности, остальной проект не затрагивается).
## Пока идёт ролик, игра проверяется (скрипты, сцены, карты и данные), а большие файлы читаются в фоне,
## чтобы при запуске мира они уже лежали в кэше диска. Всё найденное пишется в user://integrity_log.txt.
## Ролик можно пропустить (Esc, Пробел, Enter или щелчок), проверка при этом дойдёт до конца.
## Критическая ошибка: игра не запускается, показывается отчёт. Предупреждения (например, нет необязательного
## файла): отчёт с кнопкой «Продолжить». Если ошибок нет, сразу открывается главное меню.
## Заставка ничего не оставляет в памяти после себя и не требует других изменений в проекте.

const VIDEO_FILE := "res://video/intro.ogv"
const MENU_SCENE := "res://main_menu.tscn"
const LOG_FILE := "user://integrity_log.txt"

# Скрипты и сцены: путь, критично ли отсутствие
const SCRIPTS: Array = [
	["res://game.gd", true], ["res://game_clock.gd", true], ["res://world_physics.gd", true],
	["res://weather/simple_weather.gd", true], ["res://map_shaders.gd", true], ["res://main_menu.gd", true],
	["res://world_save.gd", true], ["res://board.gd", true],
	# Автозагрузки (project.godot [autoload]) и то, без чего мир не строится: если они не компилируются,
	# игра падает уже в меню или на загрузке карты
	["res://worlds/worlds.gd", true], ["res://tutorial/tutorial.gd", true], ["res://characters/actor.gd", true],
	["res://characters/cast.gd", true], ["res://world/settlements.gd", true], ["res://characters/hero_create.gd", true],
	["res://city/city_world.gd", true], ["res://battle/battle_scene.gd", true],
]
const SCENES: Array = [
	["res://main_menu.tscn", true], ["res://game.tscn", true], ["res://game_clock.tscn", true],
	["res://world_physics.tscn", true], ["res://city/city_world.tscn", true], ["res://battle/battle.tscn", true],
]
# Глобальные классы (class_name): их список лежит в game/.godot/global_script_class_cache.cfg.
# Нет кэша (архив без game/.godot) — скрипты не компилируются: так не запустилась сборка 2D 07
const CLASSES: Array = ["Actor", "GameClock", "DiceRoller", "BattleConfig", "BattleWeapon", "BattleCreature"]
# Файлы данных JSON: путь, критично ли
const JSONS: Array = [
	["res://data/cities/items.json", true], ["res://data/cities/s001.json", true], ["res://data/world/settlements.json", true],
	["res://data/characters/characteristics.json", true], ["res://data/characters/conditions.json", true],
	["res://data/characters/skills.json", true], ["res://data/characters/movement.json", true],
	["res://data/characters/creation.json", true], ["res://data/characters/rules.json", true],
	["res://data/characters/names.json", false], ["res://art/map/map_names.json", false],
	["res://data/weather/weather.json", true],
]
# Картинки данных: путь, ширина, высота (0: любой размер), критично ли отсутствие
const IMAGES: Array = [
	# Карта мира и слой биомов на доске (tools/make_new_map.py)
	["res://art/map/map_color.png", 2368, 2048, true],
	["res://art/map/map_biomes.png", 2368, 2048, true],
	["res://art/map/map_water.png", 4736, 4096, true],
	["res://art/map/map_provinces.png", 2368, 2048, true],
	["res://art/map/map_regions.png", 2368, 2048, true],
	# Жаркие горы (+40 °C), та же доска
	["res://art/map/map_hot.png", 2368, 2048, false],
	# Текстуры биомов вблизи (tools/make_terrain_textures.py), слои как TEX_* в map_shaders.gd
	["res://art/terrain/t00_water.png", 512, 512, false],
	["res://art/terrain/t01_coast.png", 512, 512, false],
	["res://art/terrain/t02_forest.png", 512, 512, false],
	["res://art/terrain/t03_field1.png", 512, 512, false],
	["res://art/terrain/t04_field2.png", 512, 512, false],
	["res://art/terrain/t05_wasteland.png", 512, 512, false],
	["res://art/terrain/t06_swamp.png", 512, 512, false],
	["res://art/terrain/t07_mountains.png", 512, 512, false],
	["res://art/terrain/t08_hot_mountains.png", 512, 512, false],
	["res://art/terrain/t09_rad_forest.png", 512, 512, false],
	["res://art/terrain/t10_rad_wasteland.png", 512, 512, false],
	["res://art/terrain/t11_rad_swamp.png", 512, 512, false],
	["res://art/terrain/t12_glow.png", 512, 512, false],
	["res://art/menu_bg.jpg", 0, 0, false],
]
# Двоичные файлы: путь, точный размер, критично ли
const BINS: Array = [
]

var lines: Array = []
var fatal: Array = []
var warns: Array = []
var preload_res: Dictionary = {}
var preload_raw: Dictionary = {}

var video: VideoStreamPlayer
var status_label: Label
var bar: ProgressBar
var hint_label: Label
var report_panel: PanelContainer
var report_text: Label
var report_title: Label
var go_button: Button

var _jobs: Array = []
var _job_i: int = 0
var _checks_done: bool = false
var _video_done: bool = false
var _decided: bool = false
var _thread: Thread
var _t0: int = 0
var _video_t0: int = 0


func _ready() -> void:
	_t0 = Time.get_ticks_msec()
	Engine.set_meta("aw_intro_done", true)   # главное меню не будет запускать заставку второй раз
	_build_ui()
	_say(I18n.t("Amber World, проверка игры. Godot %s, %s, видеокарта: %s") % [Engine.get_version_info().get("string", "?"), OS.get_name(), RenderingServer.get_video_adapter_name()])
	# Картинки данных читаем в фоне сразу
	for it in IMAGES:
		if ResourceLoader.exists(it[0]):
			ResourceLoader.load_threaded_request(it[0])
	# Задачи проверки
	_jobs.append({"kind": "classes"})
	for sp in SCRIPTS:
		_jobs.append({"kind": "script", "path": sp[0], "critical": sp[1]})
	for sc in SCENES:
		_jobs.append({"kind": "scene", "path": sc[0], "critical": sc[1]})
	for it2 in IMAGES:
		_jobs.append({"kind": "image", "path": it2[0], "w": it2[1], "h": it2[2], "critical": it2[3]})
	for js in JSONS:
		_jobs.append({"kind": "json", "path": js[0], "critical": js[1]})
	_jobs.append({"kind": "raw"})
	_jobs.append({"kind": "log"})
	# Ролик
	if ResourceLoader.exists(VIDEO_FILE):
		var stream: VideoStream = load(VIDEO_FILE) as VideoStream
		if stream != null:
			video.stream = stream
			video.finished.connect(_on_video_finished)
			video.play()
			_video_t0 = Time.get_ticks_msec()
			_say(I18n.t("Ролик запущен: %s") % VIDEO_FILE)
		else:
			_warn(I18n.t("Ролик не открывается: ") + VIDEO_FILE)
			_video_done = true
	else:
		_warn(I18n.t("Нет файла ролика: ") + VIDEO_FILE)
		_video_done = true
	if _video_done:
		hint_label.visible = false


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var back := ColorRect.new()
	back.color = Color.BLACK
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	video = VideoStreamPlayer.new()
	video.expand = true
	video.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(video)

	hint_label = Label.new()
	hint_label.text = I18n.t("Пропустить: Esc, Пробел или щелчок")
	hint_label.add_theme_font_size_override("font_size", 14)
	hint_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	hint_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	hint_label.offset_left = -330.0
	hint_label.offset_top = 10.0
	hint_label.offset_right = -14.0
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(hint_label)
	hint_label.visible = false
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 14)
	status_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	status_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	status_label.offset_left = 16.0
	status_label.offset_top = -48.0
	status_label.offset_right = 700.0
	status_label.offset_bottom = -24.0
	add_child(status_label)

	bar = ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = 100.0
	bar.custom_minimum_size = Vector2(0, 4)
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -6.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.08)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("c9a24b")
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	add_child(bar)

	report_panel = PanelContainer.new()
	report_panel.visible = false
	report_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	report_panel.custom_minimum_size = Vector2(760, 0)
	add_child(report_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	report_panel.add_child(box)
	report_title = Label.new()
	report_title.add_theme_font_size_override("font_size", 24)
	box.add_child(report_title)
	report_text = Label.new()
	report_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	report_text.custom_minimum_size = Vector2(720, 0)
	box.add_child(report_text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	go_button = Button.new()
	go_button.text = I18n.t("Продолжить")
	go_button.pressed.connect(_go_to_menu)
	row.add_child(go_button)
	var quit_button := Button.new()
	quit_button.text = I18n.t("Выйти")
	quit_button.pressed.connect(func() -> void: get_tree().quit())
	row.add_child(quit_button)


# ---------------------------------------------------------------------
# ЖУРНАЛ
# ---------------------------------------------------------------------
func _say(text: String) -> void:
	lines.append(I18n.t("[%5.1f с] %s") % [float(Time.get_ticks_msec() - _t0) / 1000.0, text])


func _err(text: String) -> void:
	fatal.append(text)
	lines.append(I18n.t("[%5.1f с] ОШИБКА: %s") % [float(Time.get_ticks_msec() - _t0) / 1000.0, text])


func _miss(text: String, critical: bool) -> void:
	if critical:
		_err(text)
	else:
		_warn(text)


func _warn(text: String) -> void:
	warns.append(text)
	lines.append(I18n.t("[%5.1f с] ПРЕДУПРЕЖДЕНИЕ: %s") % [float(Time.get_ticks_msec() - _t0) / 1000.0, text])


# ---------------------------------------------------------------------
# ПРОВЕРКА (по несколько мелких шагов за кадр, чтобы ролик не дёргался)
# ---------------------------------------------------------------------
func _process(_delta: float) -> void:
	# Ролик не пошёл (например, этот Godot не читает Theora): отмечаем и не ждём его
	if not _video_done and video.stream != null and not video.is_playing() and Time.get_ticks_msec() - _video_t0 > 1500:
		_warn(I18n.t("Ролик не воспроизводится (проверьте файл video/intro.ogv и первые строки вывода Godot)"))
		_on_video_finished(true)
	if not _checks_done:
		var budget: int = 2
		while budget > 0 and _job_i < _jobs.size():
			if not _run_job(_jobs[_job_i]):
				break
			_job_i += 1
			budget -= 1
		bar.value = 100.0 * float(_job_i) / float(maxi(_jobs.size(), 1))
		if _job_i < _jobs.size():
			status_label.text = I18n.t("Проверка игры: %s") % _job_name(_jobs[_job_i])
		else:
			_checks_done = true
			status_label.text = I18n.t("Проверка завершена")
	if _checks_done and _video_done and not _decided:
		_decided = true
		_decide()


func _job_name(job: Dictionary) -> String:
	match String(job["kind"]):
		"script", "scene", "image", "json":
			return String(job["path"]).get_file()
		"raw":
			return I18n.t("файлы данных")
		"classes":
			return I18n.t("классы скриптов")
	return I18n.t("журнал")


# Возвращает true, когда задача выполнена. false: ждём фоновое чтение
func _run_job(job: Dictionary) -> bool:
	var kind: String = job["kind"]
	if kind == "classes":
		var known: Dictionary = {}
		for c in ProjectSettings.get_global_class_list():
			known[String(c["class"])] = true
		var lost: Array = CLASSES.filter(func(n): return not known.has(n))
		if not lost.is_empty():
			_err(I18n.t("Нет кэша классов скриптов (папка game/.godot): %s. Распакуйте архив целиком или запустите Start_HEX.cmd — он заново импортирует проект") % ", ".join(PackedStringArray(lost)))
		return true
	if kind == "json":
		var jpath: String = job["path"]
		if not FileAccess.file_exists(jpath):
			_miss(I18n.t("Нет файла данных: ") + jpath, job["critical"])
		elif not (JSON.parse_string(FileAccess.get_file_as_string(jpath)) is Dictionary):
			_miss(I18n.t("Файл данных не читается как JSON: ") + jpath, job["critical"])
		return true
	if kind == "script":
		var path: String = job["path"]
		var res: Resource = null
		if ResourceLoader.exists(path):
			res = load(path)
		if res == null or not (res is Script):
			_miss(I18n.t("Скрипт не найден или не открывается: ") + path, job["critical"])
		elif not (res as Script).can_instantiate():
			_miss(I18n.t("Скрипт не компилируется: ") + path, job["critical"])
		return true
	if kind == "scene":
		var spath: String = job["path"]
		var ps: PackedScene = null
		if ResourceLoader.exists(spath):
			ps = load(spath) as PackedScene
		if ps == null or not ps.can_instantiate():
			_miss(I18n.t("Сцена не найдена или не открывается: ") + spath, job["critical"])
		return true
	if kind == "image":
		return _check_image(job)
	if kind == "raw":
		return _check_raw()
	# журнал
	_say(I18n.t("Критических ошибок: %d, предупреждений: %d") % [fatal.size(), warns.size()])
	_say(I18n.t("Память процесса: %d МБ") % int(OS.get_static_memory_usage() / 1048576.0))
	var f := FileAccess.open(LOG_FILE, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines) + "\n")
		f.close()
	# Прочитанное лежит в кэше диска; ссылки на большие картинки отпускаем, чтобы они не занимали память
	preload_res.clear()
	preload_raw.clear()
	return true


func _check_image(job: Dictionary) -> bool:
	var path: String = job["path"]
	var critical: bool = job["critical"]
	if not ResourceLoader.exists(path):
		if critical:
			_err(I18n.t("Нет файла данных: ") + path)
		else:
			_warn(I18n.t("Нет файла (необязательного): ") + path)
		return true
	var st: int = ResourceLoader.load_threaded_get_status(path)
	if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return false
	if st != ResourceLoader.THREAD_LOAD_LOADED:
		if critical:
			_err(I18n.t("Файл данных не читается: ") + path)
		else:
			_warn(I18n.t("Файл не читается: ") + path)
		return true
	var res: Resource = ResourceLoader.load_threaded_get(path)
	preload_res[path] = res
	var tex := res as Texture2D
	if tex == null:
		_err(I18n.t("Файл данных не является картинкой: ") + path)
		return true
	var w: int = job["w"]
	var h: int = job["h"]
	if w > 0 and (tex.get_width() != w or tex.get_height() != h):
		var msg: String = I18n.t("Неверный размер %s: %d x %d, ожидалось %d x %d") % [path, tex.get_width(), tex.get_height(), w, h]
		if critical:
			_err(msg)
		else:
			_warn(msg)
	else:
		_say(I18n.t("Файл в порядке: %s (%d x %d)") % [path.get_file(), tex.get_width(), tex.get_height()])
	return true


# Двоичные файлы и кэш деревьев читает отдельный поток
func _check_raw() -> bool:
	if _thread == null:
		_thread = Thread.new()
		_thread.start(_read_raw_files)
		return false
	if _thread.is_alive():
		return false
	var got: Dictionary = _thread.wait_to_finish()
	_thread = null
	for it in BINS:
		var path: String = it[0]
		var want: int = it[1]
		var b: PackedByteArray = got.get(path, PackedByteArray())
		if b.size() == 0:
			_warn(I18n.t("Нет файла данных: ") + path)
		elif b.size() != want:
			_warn(I18n.t("Неверный размер %s: %d, ожидалось %d") % [path, b.size(), want])
		else:
			preload_raw[path] = b
			_say(I18n.t("Файл в порядке: %s (%d байт)") % [path.get_file(), b.size()])
	return true


func _read_raw_files() -> Dictionary:
	var out: Dictionary = {}
	for it in BINS:
		var path: String = it[0]
		if FileAccess.file_exists(path):
			out[path] = FileAccess.get_file_as_bytes(path)
	return out


# ---------------------------------------------------------------------
# ЗАВЕРШЕНИЕ
# ---------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if _video_done:
		return
	var skip: bool = false
	if event is InputEventKey and event.pressed and not event.echo:
		var ke := event as InputEventKey
		if ke.keycode == KEY_ESCAPE or ke.keycode == KEY_SPACE or ke.keycode == KEY_ENTER or ke.keycode == KEY_KP_ENTER:
			skip = true
	if event is InputEventMouseButton and event.pressed:
		skip = true
	if skip:
		video.stop()
		_on_video_finished(true)


func _on_video_finished(skipped: bool = false) -> void:
	if not skipped and Time.get_ticks_msec() - _video_t0 < 3000:
		_warn(I18n.t("Ролик закончился почти сразу: он не воспроизвёлся"))
	_video_done = true
	hint_label.visible = false


func _decide() -> void:
	if fatal.is_empty() and warns.is_empty():
		_go_to_menu()
		return
	var txt: String = ""
	if not fatal.is_empty():
		report_title.text = I18n.t("Игра не может запуститься")
		txt = I18n.t("Найдены критические проблемы:\n- ") + "\n- ".join(fatal)
		go_button.visible = false
	else:
		report_title.text = I18n.t("Игра запустится, но есть предупреждения")
		txt = "- " + "\n- ".join(warns)
		go_button.visible = true
	txt += I18n.t("\n\nПодробный журнал: ") + ProjectSettings.globalize_path(LOG_FILE)
	report_text.text = txt
	report_panel.visible = true


func _go_to_menu() -> void:
	set_process(false)
	var err: Error = get_tree().change_scene_to_file(MENU_SCENE)
	if err != OK:
		set_process(true)
		report_title.text = I18n.t("Игра не может запуститься")
		report_text.text = I18n.t("Не открывается главное меню %s (%s).\n\nПодробный журнал: %s") % [MENU_SCENE, error_string(err), ProjectSettings.globalize_path(LOG_FILE)]
		go_button.visible = false
		report_panel.visible = true

extends RefCounted
## Сохранения мира в user://saves/<ячейка>.dat, чтобы после закрытия игры продолжить с того же места.
## Ячейки: "autosave" (выход в меню, закрытие окна, раз в 5 минут) и ручные "manual_<время>" (меню паузы).
## Сохраняются: время и скорость часов, скорость погоды и состояние атмосферы, камера карты,
## герой и НПС (characters/cast.gd; в старых сохранениях их нет — тогда мир без персонажей),
## в каком мире герой — город или бой поверх общей карты (worlds/worlds.gd, ключ "worlds"),
## протоптанные дороги общей карты (world/trails_layer.gd, ключ "trails"; дороги в городах — в состоянии города).
## Ландшафт и климатические таблицы в игре не меняются и не сохраняются.
## В файле сначала заголовок (для списка загрузки), потом данные.

const DIR: String = "user://saves/"
const LEGACY_PATH: String = "user://world_save.dat"   # первая версия: одна ячейка без заголовка
# 5: карта 2D 04 (постапокалиптический вид, области и регионы).
# 6: 2D 07 patch 01 — маленький радиальный город (клетка 1 м), рост с запасными поручениями, куртка на герое.
# Сохранения другой версии удаляются при первом обращении к списку (вопрос Q05, Huzzah 2026-10-24)
const VERSION: int = 6
const AUTOSAVE: String = "autosave"
const MANUAL_KEEP: int = 10


static func path_of(slot: String) -> String:
	return LEGACY_PATH if slot == "legacy" else DIR + slot + ".dat"


# Список сохранений, новые первыми: {slot, title, saved_at, unix, char_name, game_date}
static func list() -> Array:
	var out: Array = []
	var dir := DirAccess.open(DIR)
	if dir != null:
		for f in dir.get_files():
			if not f.ends_with(".dat"):
				continue
			var slot: String = f.get_basename()
			var h: Dictionary = _header(path_of(slot))
			if h.is_empty() or int(h.get("version", 0)) != VERSION:
				# От другой сборки — удалить: загрузить его всё равно нельзя (Q05)
				push_warning("world_save: удалено сохранение другой версии %s" % path_of(slot))
				DirAccess.remove_absolute(path_of(slot))
				continue
			h["slot"] = slot
			out.append(h)
	# Старая ячейка LEGACY_PATH лежит вне DIR и без заголовка — тоже удаляется (версии 1–4 не читаются)
	if FileAccess.file_exists(LEGACY_PATH):
		DirAccess.remove_absolute(LEGACY_PATH)
	for h in out:
		h["title"] = "Автосохранение" if h["slot"] == AUTOSAVE else "Сохранение"
	out.sort_custom(func(a, b): return int(a["unix"]) > int(b["unix"]))
	return out


static func exists() -> bool:
	return not list().is_empty()


static func latest_slot() -> String:
	var l: Array = list()
	return String(l[0]["slot"]) if not l.is_empty() else ""


static func _header(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var h: Variant = f.get_var(false)
	f.close()
	if not (h is Dictionary) or not h.has("header"):
		return {}
	return h


static func read(slot: String = "") -> Dictionary:
	if slot == "":
		slot = latest_slot()
	if slot == "":
		return {}
	var f := FileAccess.open(path_of(slot), FileAccess.READ)
	if f == null:
		push_warning("world_save: не открыть %s (%s)" % [path_of(slot), error_string(FileAccess.get_open_error())])
		return {}
	var first: Variant = f.get_var(false)
	var d: Variant = first
	if first is Dictionary and first.has("header"):
		d = f.get_var(false)
	f.close()
	if not (d is Dictionary):
		push_warning("world_save: %s повреждено — нет данных мира" % path_of(slot))
		return {}
	if int(d.get("version", 0)) != VERSION:
		push_warning("world_save: %s версии %d, игра читает только %d" % [path_of(slot), int(d.get("version", 0)), VERSION])
		return {}
	return d


static func delete(slot: String) -> void:
	var p: String = path_of(slot)
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)


# Состояние атмосферы берётся, когда фоновый поток свободен (ждём до 2 с)
static func atmosphere_bytes(physics: Node) -> PackedByteArray:
	var bytes: PackedByteArray = physics.export_state()
	var tries: int = 0
	while bytes.is_empty() and tries < 200 and physics.model != null:
		OS.delay_msec(10)
		bytes = physics.export_state()
		tries += 1
	return bytes


static func build(game: Node) -> Dictionary:
	var d: Dictionary = {"version": VERSION, "saved_at": Time.get_datetime_string_from_system()}
	d["clock_total"] = game.clock.total_seconds
	d["clock_speed"] = game.clock.speed_index
	d["weather_speed"] = game.physics.weather_speed
	d["atmosphere"] = atmosphere_bytes(game.physics)
	d["cam_pos"] = game.cam_pos
	d["zoom"] = game.zoom
	if game.get("cast") != null:
		d["cast"] = game.cast.to_dict()
	if game.get("trails") != null:
		d["trails"] = game.trails.to_dict()
	var worlds: Node = _worlds(game)
	if worlds != null:
		d["worlds"] = worlds.to_dict()
	return d


static func _worlds(game: Node) -> Node:
	return game.get_tree().root.get_node_or_null("Worlds") if game.is_inside_tree() else null


# Записать мир в ячейку. manual: новая ручная ячейка (старые ручные сверх 10 удаляются)
static func write(game: Node, manual: bool = false) -> bool:
	DirAccess.make_dir_recursive_absolute(DIR)
	var slot: String = AUTOSAVE
	if manual:
		# Миллисекунды: две ручные записи в одну секунду не затирают друг друга
		slot = "manual_%d" % int(Time.get_unix_time_from_system() * 1000.0)
	var d: Dictionary = build(game)
	var header: Dictionary = {
		"header": true, "version": VERSION, "saved_at": d["saved_at"], "unix": int(Time.get_unix_time_from_system()),
		"game_date": GameClock.date_text(game.clock.total_seconds),
	}
	# Имя героя для списка сохранений (main_menu.gd)
	var cast: Node = game.get("cast")
	if cast != null and not cast.hero.is_empty():
		header["char_name"] = cast.hero["actor"].display_name
	var worlds: Node = _worlds(game)
	if worlds != null and worlds.place_text() != "":
		header["place"] = worlds.place_text()
	var path: String = path_of(slot)
	var tmp: String = path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("world_save: не записать %s (%s)" % [tmp, error_string(FileAccess.get_open_error())])
		return false
	f.store_var(header, false)
	f.store_var(d, false)
	var werr: Error = f.get_error()
	f.close()
	if werr != OK:
		push_error("world_save: ошибка записи %s (%s)" % [tmp, error_string(werr)])
		DirAccess.remove_absolute(tmp)
		return false
	# Старая ячейка сначала уходит в .bak: если переименование не удастся, она возвращается на место
	var bak: String = path + ".bak"
	if FileAccess.file_exists(bak):
		DirAccess.remove_absolute(bak)
	if FileAccess.file_exists(path):
		DirAccess.rename_absolute(path, bak)
	var err: Error = DirAccess.rename_absolute(tmp, path)
	var ok: bool = err == OK
	if ok:
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(bak)
	else:
		push_error("world_save: не переименовать %s -> %s (%s)" % [tmp, path, error_string(err)])
		if FileAccess.file_exists(bak) and not FileAccess.file_exists(path):
			DirAccess.rename_absolute(bak, path)
	if manual:
		var manuals: Array = list().filter(func(h): return String(h["slot"]).begins_with("manual_"))
		for k in range(MANUAL_KEEP, manuals.size()):
			delete(String(manuals[k]["slot"]))
	return ok


# Раньше всего (до запуска физики): время и погода
static func apply_early(game: Node, d: Dictionary) -> void:
	game.clock.total_seconds = float(d.get("clock_total", game.clock.total_seconds))
	game.clock._sync_last()
	# Индекс скорости из сохранения — в пределах нынешнего списка GameClock.SPEEDS
	game.clock.speed_index = clampi(int(d.get("clock_speed", game.clock.speed_index)), 0, GameClock.SPEEDS.size() - 1)
	game.physics.weather_speed = float(d.get("weather_speed", game.physics.weather_speed))
	var atmo: Variant = d.get("atmosphere", PackedByteArray())
	if atmo is PackedByteArray and not atmo.is_empty():
		game.physics.preload_state = atmo


# После загрузки карты: камера
static func apply_late(game: Node, d: Dictionary) -> void:
	var cam: Variant = d.get("cam_pos", game.cam_pos)
	if cam is Vector2:
		game.cam_pos = cam
	game.zoom = clampf(float(d.get("zoom", game.zoom)), game.min_zoom, game.MAX_ZOOM)
	game._clamp_camera()
	if game.get("cast") != null and d.get("cast") is Dictionary:
		game.cast.load_dict(d["cast"])
	if game.get("trails") != null:
		game.trails.load_dict(d.get("trails", {}))
	var worlds: Node = _worlds(game)
	if worlds != null and d.get("worlds") is Dictionary:
		worlds.load_dict(d["worlds"])

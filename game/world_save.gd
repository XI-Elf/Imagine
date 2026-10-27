extends RefCounted
## Сохранения мира в user://saves/<ячейка>.dat, чтобы после закрытия игры продолжить с того же места.
## Ячейки: "autosave" (выход в меню, закрытие окна, раз в 5 минут) и ручные "manual_<время>" (меню паузы).
## Сохраняются: время и скорость часов, скорость погоды и состояние атмосферы, камера карты,
## герой и НПС (characters/cast.gd; в старых сохранениях их нет — тогда мир без персонажей),
## в каком мире герой — город или бой поверх общей карты (worlds/worlds.gd, ключ "worlds").
## Ландшафт и климатические таблицы в игре не меняются и не сохраняются.
## В файле сначала заголовок (для списка загрузки), потом данные.

const DIR: String = "user://saves/"
const LEGACY_PATH: String = "user://world_save.dat"   # первая версия: одна ячейка без заголовка
# 5: карта 2D 04 (постапокалиптический вид, области и регионы). Сохранения версий 1–4 не загружаются
const VERSION: int = 5
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
				continue
			h["slot"] = slot
			out.append(h)
	for h in out:
		var kind: String = "Автосохранение" if h["slot"] == AUTOSAVE else ("Старое сохранение" if h["slot"] == "legacy" else "Сохранение")
		h["title"] = kind
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
		return {}
	var first: Variant = f.get_var(false)
	var d: Variant = first
	if first is Dictionary and first.has("header"):
		d = f.get_var(false)
	f.close()
	if not (d is Dictionary) or int(d.get("version", 0)) != VERSION:
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
		slot = "manual_%d" % int(Time.get_unix_time_from_system())
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
		return false
	f.store_var(header, false)
	f.store_var(d, false)
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var ok: bool = DirAccess.rename_absolute(tmp, path) == OK
	if manual:
		var manuals: Array = list().filter(func(h): return String(h["slot"]).begins_with("manual_"))
		for k in range(MANUAL_KEEP, manuals.size()):
			delete(String(manuals[k]["slot"]))
	return ok


# Раньше всего (до запуска физики): время и погода
static func apply_early(game: Node, d: Dictionary) -> void:
	game.clock.total_seconds = float(d.get("clock_total", game.clock.total_seconds))
	game.clock._sync_last()
	game.clock.speed_index = int(d.get("clock_speed", game.clock.speed_index))
	game.physics.weather_speed = float(d.get("weather_speed", game.physics.weather_speed))
	var atmo: PackedByteArray = d.get("atmosphere", PackedByteArray())
	if not atmo.is_empty():
		game.physics.preload_state = atmo


# После загрузки карты: камера
static func apply_late(game: Node, d: Dictionary) -> void:
	game.cam_pos = d.get("cam_pos", game.cam_pos)
	game.zoom = clampf(float(d.get("zoom", game.zoom)), game.min_zoom, game.MAX_ZOOM)
	game._clamp_camera()
	if game.get("cast") != null and d.has("cast"):
		game.cast.load_dict(d["cast"])
	var worlds: Node = _worlds(game)
	if worlds != null and d.has("worlds"):
		worlds.load_dict(d["worlds"])

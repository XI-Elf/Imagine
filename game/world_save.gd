extends RefCounted
## Збереження світу в user://saves/<комірка>.dat, щоб після закриття гри продовжити з того самого місця.
## Комірки: "autosave" (вихід у меню, закриття вікна, раз на 5 хвилин) і ручні "manual_<час>" (меню паузи).
## Зберігаються: час і швидкість годинника, швидкість погоди й стан атмосфери, камера карти,
## герой і НПС (characters/cast.gd; у старих збереженнях їх немає — тоді світ без персонажів),
## у якому світі герой — місто чи бій поверх загальної карти (worlds/worlds.gd, ключ "worlds"),
## протоптані дороги загальної карти (world/trails_layer.gd, ключ "trails"; дороги в містах — у стані міста),
## досліджена частина світу — туман війни (world/fog_layer.gd, ключ "fog"; без нього — відкрито лише навколо героя).
## Ландшафт і кліматичні таблиці в грі не змінюються й не зберігаються.
## У файлі спершу заголовок (для списку завантаження), потім дані.

const DIR: String = "user://saves/"
const LEGACY_PATH: String = "user://world_save.dat"   # перша версія: одна комірка без заголовка
# 5: карта 2D 04 (постапокаліптичний вигляд, області й регіони).
# 6: 2D 07 patch 01 — маленьке радіальне місто (клітинка 1 м), ріст із запасними дорученнями, куртка на герої.
# Збереження іншої версії видаляються під час першого звернення до списку (питання Q05, Huzzah 2026-10-24)
const VERSION: int = 6
const AUTOSAVE: String = "autosave"
const MANUAL_KEEP: int = 10


static func path_of(slot: String) -> String:
	return LEGACY_PATH if slot == "legacy" else DIR + slot + ".dat"


# Список збережень, нові першими: {slot, title, saved_at, unix, char_name, game_date}.
# ВАЖНО: просмотр списка никогда не удаляет и не переписывает файлы. Сохранения
# неизвестной версии и старый legacy-файл остаются на диске до явного решения игрока.
static func list() -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	var dir := DirAccess.open(DIR)
	if dir != null:
		for f in dir.get_files():
			var is_backup: bool = f.ends_with(".dat.bak")
			if not f.ends_with(".dat") and not is_backup:
				continue
			var slot: String = f.trim_suffix(".bak").trim_suffix(".dat") if is_backup else f.get_basename()
			if seen.has(slot):
				continue
			var primary: String = path_of(slot)
			var backup: String = primary + ".bak"
			var chosen: String = _valid_save_path(primary)
			if chosen == "":
				chosen = _valid_save_path(backup)
			if chosen == "":
				# Повреждённые/чужие версии сохраняем, но не предлагаем к загрузке.
				continue
			var h: Dictionary = _header(chosen)
			h["slot"] = slot
			h["recovered_from_backup"] = chosen == backup
			seen[slot] = true
			out.append(h)
	for h in out:
		h["title"] = I18n.t("Автосохранение") if h["slot"] == AUTOSAVE else I18n.t("Сохранение")
	out.sort_custom(func(a, b): return int(a.get("unix", 0)) > int(b.get("unix", 0)))
	return out


# Возвращает путь только к сохранению с поддерживаемым заголовком и версией.
static func _valid_save_path(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var h: Variant = f.get_var(false)
	var payload: Variant = f.get_var(false) if h is Dictionary and h.has("header") else null
	f.close()
	if not (h is Dictionary) or not h.has("header") or not (payload is Dictionary):
		return ""
	if int(h.get("version", 0)) != VERSION or int(payload.get("version", 0)) != VERSION:
		return ""
	return path


# Старые файлы намеренно не удаляются: они могут пригодиться для мигратора.
static func legacy_save_exists() -> bool:
	return FileAccess.file_exists(LEGACY_PATH)


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
	var path: String = path_of(slot)
	var chosen: String = _valid_save_path(path)
	if chosen == "":
		chosen = _valid_save_path(path + ".bak")
	if chosen == "":
		push_warning("world_save: %s отсутствует, повреждено или имеет неподдерживаемую версию; файл сохранён без изменений" % path)
		return {}
	var f := FileAccess.open(chosen, FileAccess.READ)
	if f == null:
		push_warning("world_save: не открыть %s (%s)" % [chosen, error_string(FileAccess.get_open_error())])
		return {}
	var first: Variant = f.get_var(false)
	var d: Variant = f.get_var(false) if first is Dictionary and first.has("header") else first
	f.close()
	if not (d is Dictionary):
		push_warning("world_save: %s повреждено — нет данных мира" % chosen)
		return {}
	if int(d.get("version", 0)) != VERSION:
		# Дополнительная проверка: заголовок и payload обязаны иметь ту же версию.
		push_warning("world_save: %s содержит данные версии %d, ожидается %d" % [chosen, int(d.get("version", 0)), VERSION])
		return {}
	if chosen.ends_with(".bak"):
		push_warning("world_save: используется резервная копия %s; основное сохранение не перезаписано" % chosen)
	return d


static func delete(slot: String) -> void:
	var p: String = path_of(slot)
	for candidate in [p, p + ".bak", p + ".tmp"]:
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)


# Стан атмосфери береться, коли фоновий потік вільний (чекаємо до 2 с)
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
	if game.get("fog") != null:
		d["fog"] = game.fog.to_dict()
	if game.get("region_tracker") != null:
		d["world_map"] = game.region_tracker.to_dict()
	var worlds: Node = _worlds(game)
	if worlds != null:
		d["worlds"] = worlds.to_dict()
	return d


static func _worlds(game: Node) -> Node:
	return game.get_tree().root.get_node_or_null("Worlds") if game.is_inside_tree() else null


# Записати світ у комірку. manual: нова ручна комірка (старі ручні понад 10 видаляються)
static func write(game: Node, manual: bool = false) -> bool:
	DirAccess.make_dir_recursive_absolute(DIR)
	var slot: String = AUTOSAVE
	if manual:
		# Мілісекунди: два ручні записи в одну секунду не затирають один одного
		slot = "manual_%d" % int(Time.get_unix_time_from_system() * 1000.0)
	var d: Dictionary = build(game)
	var header: Dictionary = {
		"header": true, "version": VERSION, "saved_at": d["saved_at"], "unix": int(Time.get_unix_time_from_system()),
		"game_date": GameClock.date_text(game.clock.total_seconds),
	}
	# Ім'я героя для списку збережень (main_menu.gd)
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
	# Стара комірка спершу йде в .bak: якщо перейменування не вдасться, вона повертається на місце
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


# Найперше (до запуску фізики): час і погода
static func apply_early(game: Node, d: Dictionary) -> void:
	game.clock.total_seconds = float(d.get("clock_total", game.clock.total_seconds))
	game.clock._sync_last()
	# Індекс швидкості зі збереження — у межах теперішнього списку GameClock.SPEEDS
	game.clock.speed_index = clampi(int(d.get("clock_speed", game.clock.speed_index)), 0, GameClock.SPEEDS.size() - 1)
	game.physics.weather_speed = float(d.get("weather_speed", game.physics.weather_speed))
	var atmo: Variant = d.get("atmosphere", PackedByteArray())
	if atmo is PackedByteArray and not atmo.is_empty():
		game.physics.preload_state = atmo


# Після завантаження карти: камера
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
	if game.get("fog") != null:
		game.fog.load_dict(d.get("fog", {}))
	if game.get("region_tracker") != null:
		game.region_tracker.load_dict(d.get("world_map"))
	var worlds: Node = _worlds(game)
	if worlds != null and d.get("worlds") is Dictionary:
		worlds.load_dict(d["worlds"])

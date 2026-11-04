extends RefCounted
## Данные правил персонажа: пак (характеристики-ресурсы, состояния, навыки) и правила Амбера
## (местность, движение, лечение, характеристики 09). Читаются один раз из res://data/characters/.
## Логика (actor.gd) берёт числа только отсюда.

const DIR := "res://data/characters/"

static var _cache: Dictionary = {}


static func _load(file: String) -> Dictionary:
	if _cache.has(file):
		return _cache[file]
	var d: Dictionary = {}
	var f := FileAccess.open(DIR + file, FileAccess.READ)
	if f != null:
		var v: Variant = I18n.tree(JSON.parse_string(f.get_as_text()))
		if v is Dictionary:
			d = v
	if d.is_empty():
		push_error("actor_rules: не прочитан " + DIR + file)
	_cache[file] = d
	return d


static func characteristics() -> Dictionary:
	return _load("characteristics.json").get("characteristics", {})


static func traumas() -> Dictionary:
	return _load("conditions.json").get("traumas", {})


static func diseases() -> Dictionary:
	return _load("conditions.json").get("diseases", {})


static func buffs() -> Dictionary:
	return _load("conditions.json").get("positive_effects", {})


## Навыки — 18 навыков (sheet.json) в виде {ключ: {name_ru, description, max_level}}.
## Старые навыки пака (skills.json) — только справка: их ключи переводит Sheet.canon
static func skills() -> Dictionary:
	if _cache.has("_skills"):
		return _cache["_skills"]
	var out: Dictionary = {}
	var sp: Dictionary = _load("sheet.json").get("skills", {})
	for k in sp:
		out[k] = {"name_ru": String(sp[k].get("name", k)), "name_en": k,
			"description": String(sp[k].get("desc", "")), "group": String(sp[k].get("group", "")), "max_level": 10}
	_cache["_skills"] = out
	return out


static func pack_skills() -> Dictionary:
	return _load("skills.json").get("skills", {})


# Переміщення з пакета: базова швидкість і транспорт (км/год)
static func pack_movement() -> Dictionary:
	return _load("movement.json").get("movement", {})


# Швидкість пішки або на транспорті, км/год: "" — пішки, "horse", "cart"
static func base_kmh(mount: String = "") -> float:
	var m: Dictionary = pack_movement()
	if mount == "":
		return float(m.get("base_speed_kmh", 3.0))
	return float(m.get("medieval_adaptation", {}).get(mount, m.get("base_speed_kmh", 3.0)))


# Кінь і віз (data/characters/transport.json, питання Q16): вантаж, місцевість, їзда
static func transport() -> Dictionary:
	return _load("transport.json")


# Множник місцевості для транспорту: віз грузне в болоті й не лізе в гори; пішки — 1
static func mount_terrain(mount: String, biome: int) -> float:
	if mount == "":
		return 1.0
	return float(transport().get(mount, {}).get("terrain", {}).get(str(biome), 1.0))


# Створення героя: походження, професії, риси характеру, біографія (правила 09)
static func creation() -> Dictionary:
	return _load("creation.json")


# Риса характеру за ключем; {} — такої немає
static func trait_def(id: String) -> Dictionary:
	return creation().get("traits", {}).get(id, {})


static func rules() -> Dictionary:
	return _load("rules.json")


static func section(key: String) -> Dictionary:
	return rules().get(key, {})


static func num(sect: String, key: String, default: float = 0.0) -> float:
	return float(section(sect).get(key, default))


# Травма або хвороба за ключем; {} — такої немає
static func condition(id: String) -> Dictionary:
	if traumas().has(id):
		return traumas()[id]
	return diseases().get(id, {})


static func is_trauma(id: String) -> bool:
	return traumas().has(id)


# Правила місцевості для біома (номер із game.gd BIOME_NAMES)
static func terrain(biome: int) -> Dictionary:
	return section("terrain").get(str(biome), section("terrain").get("4", {}))


# Таблиця досвіду навички: у навичок без своєї таблиці — таблиця Виживання [Q19: не баланс, залишено]
static func xp_table(skill: String) -> Array:
	var s: Dictionary = pack_skills().get(skill, {})
	if s.has("xp_table"):
		return s["xp_table"]
	return pack_skills().get("survival", {}).get("xp_table", [])

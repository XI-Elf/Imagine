extends RefCounted
## Загрузка ресурсов боя из res://data/battle/<вид>/<id>.tres с кэшем. Отсутствующий id — ошибка в лог и null:
## по Combat_Formulas недостающие данные надо называть явно, а не подменять своими числами.

const DIR := "res://data/battle/"

static var _cache: Dictionary = {}
static var missing: Array = []


static func _res(kind: String, id: String) -> Resource:
	var key: String = kind + "/" + id
	if _cache.has(key):
		return _cache[key]
	var path: String = DIR + key + ".tres"
	var r: Resource = load(path) if ResourceLoader.exists(path) else null
	if r == null and id != "":
		if not missing.has(key):
			missing.append(key)
			push_warning("battle_data: нет %s" % path)
	_cache[key] = r
	return r


static func weapon(id: String) -> BattleWeapon:
	return _res("weapons", id) as BattleWeapon


static func armor(id: String) -> BattleArmor:
	return _res("armor", id) as BattleArmor


static func effect(id: String) -> BattleEffect:
	return _res("effects", id) as BattleEffect


static func ability(id: String) -> BattleAbility:
	return _res("abilities", id) as BattleAbility


static func creature(id: String) -> BattleCreature:
	return _res("creatures", id) as BattleCreature


static func config() -> BattleConfig:
	var key: String = "config"
	if not _cache.has(key):
		var r: Resource = load(DIR + "config.tres") if ResourceLoader.exists(DIR + "config.tres") else null
		_cache[key] = r if r != null else BattleConfig.new()
	return _cache[key]


static func list(kind: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var d := DirAccess.open(DIR + kind)
	if d == null:
		return out
	for f in d.get_files():
		var n: String = f.trim_suffix(".remap")
		if n.ends_with(".tres"):
			out.append(n.trim_suffix(".tres"))
	return out

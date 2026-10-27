extends RefCounted
## Имена НПС: балтийские, эссекские, норвежские, ирландские (решение автора; список — data/characters/names.json).
## pick() — случайное имя с учётом пола и культуры; used — имена, которые уже заняты (не повторяются, пока есть свободные).

const FILE := "res://data/characters/names.json"
const CULTURES: Array = ["baltic", "essex", "norse", "irish"]

static var _data: Dictionary = {}
static var _read: bool = false


static func data() -> Dictionary:
	if not _read:
		_read = true
		var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE)) if FileAccess.file_exists(FILE) else null
		_data = v.get("cultures", {}) if v is Dictionary else {}
		if _data.is_empty():
			push_error("npc_names: не прочитан " + FILE)
	return _data


## Все имена: gender "male" / "female" / "" (оба), culture — ключ из CULTURES или "" (все)
static func all(gender: String = "", culture: String = "") -> Array:
	var out: Array = []
	for c in CULTURES:
		if culture != "" and c != culture:
			continue
		for g in ["male", "female"]:
			if gender == "" or gender == g:
				out.append_array(data().get(c, {}).get(g, []))
	return out


static func pick(rng: RandomNumberGenerator, gender: String = "", culture: String = "", used: Array = []) -> String:
	var pool: Array = all(gender, culture)
	var free: Array = pool.filter(func(n): return not used.has(n))
	if free.is_empty():
		free = pool
	if free.is_empty():
		return "Безымянный"
	return free[rng.randi() % free.size()]


## Культура имени: ключ из CULTURES или ""
static func culture_of(name: String) -> String:
	var first: String = name.get_slice(" ", name.get_slice_count(" ") - 1)
	for c in CULTURES:
		for g in ["male", "female"]:
			if data().get(c, {}).get(g, []).has(first):
				return c
	return ""

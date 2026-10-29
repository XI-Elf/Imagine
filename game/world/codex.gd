extends RefCounted
## Кодекс світу: записки з data/lore/notes.json (канон lore/canon.md). Знаходяться при обшуку руїн (src ruins)
## і схованок міста (src city), збираються в «Щоденник» героя (вкладка вікна героя). Знайдене лежить у Worlds.codex
## {id записки -> ігрові секунди}: це знання про світ, воно переживає героя й скидається лише новою грою.

const FILE := "res://data/lore/notes.json"

static var _cache: Dictionary = {}


static func data() -> Dictionary:
	if _cache.is_empty():
		var f := FileAccess.open(FILE, FileAccess.READ)
		if f != null:
			var v: Variant = I18n.tree(JSON.parse_string(f.get_as_text()))
			if v is Dictionary:
				_cache = v
		if _cache.is_empty():
			push_error("codex: не прочитано " + FILE)
	return _cache


static func notes() -> Array:
	return data().get("entries", [])


static func chapters() -> Array:
	return data().get("chapters", [])


static func note(id: String) -> Dictionary:
	for n in notes():
		if String(n["id"]) == id:
			return n
	return {}


## Скільки знайдено з усіх: {found, total}
static func progress(found: Dictionary) -> Dictionary:
	var n: int = 0
	for e in notes():
		if found.has(String(e["id"])):
			n += 1
	return {"found": n, "total": notes().size()}


## Ненайдені записки джерела src ("ruins" / "city")
static func unfound(found: Dictionary, src: String) -> Array:
	var out: Array = []
	for e in notes():
		if String(e.get("src", "")) == src and not found.has(String(e["id"])):
			out.append(e)
	return out


## Знахідка при обшуку: з шансом chance[src] випадкова ненайдена записка джерела src. Записує її в found.
## Повертає записку або {} (шанс не спрацював чи все знайдено)
static func find(found: Dictionary, src: String, rng: RandomNumberGenerator, now: float) -> Dictionary:
	var left: Array = unfound(found, src)
	if left.is_empty() or rng.randf() >= float(data().get("chance", {}).get(src, 0.0)):
		return {}
	var pick: Dictionary = left[rng.randi() % left.size()]
	found[String(pick["id"])] = now
	return pick

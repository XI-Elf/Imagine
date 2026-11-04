extends RefCounted
## Кампания «Пепел помнит имена». Состояние хранится в Worlds и сериализуется вместе с миром.
const FILE := "res://data/story/campaign.json"
static var _data: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(FILE, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_data = parsed
	return _data

static func fresh() -> Dictionary:
	return {"version": 1, "chapter": 0, "progress": 0, "flags": {}, "decisions": {}, "effects": {}, "completed": [], "bosses": [], "history": []}

## Міграція збереженого стану: 2D 11 (ключа немає) і проміжні збірки з іншою схемою (без version=1) — кампанія з початку.
## Невідомі поля відкидаються, відсутні — доповнюються з fresh(), щоб старі файли не ламали record()/choose().
static func migrate(raw: Variant) -> Dictionary:
	var base: Dictionary = fresh()
	if not (raw is Dictionary) or int(raw.get("version", 0)) != 1:
		return base
	for k in base:
		if not raw.has(k):
			continue
		if base[k] is int and (raw[k] is int or raw[k] is float):  # JSON віддає числа як float
			base[k] = int(raw[k])
		elif typeof(raw[k]) == typeof(base[k]):
			base[k] = raw[k].duplicate(true) if (raw[k] is Dictionary or raw[k] is Array) else raw[k]
	base["awaiting_choice"] = bool(raw.get("awaiting_choice", false))
	base["chapter"] = clampi(int(base["chapter"]), 0, chapters().size())
	return base

static func chapters() -> Array:
	return data().get("chapters", [])

static func current(state: Dictionary) -> Dictionary:
	var all: Array = chapters()
	var i: int = int(state.get("chapter", 0))
	return all[i] if i >= 0 and i < all.size() else {}

static func is_complete(state: Dictionary) -> bool:
	return int(state.get("chapter", 0)) >= chapters().size()

static func objective(state: Dictionary) -> Dictionary:
	return current(state).get("objective", {})

static func record(state: Dictionary, event: String, target: String = "", amount: int = 1) -> bool:
	if is_complete(state) or amount <= 0:
		return false
	var obj: Dictionary = objective(state)
	if String(obj.get("event", "")) != event:
		return false
	var expected: String = String(obj.get("target", ""))
	if expected != "" and expected != target:
		return false
	state["progress"] = int(state.get("progress", 0)) + amount
	var need: int = maxi(1, int(obj.get("count", 1)))
	if int(state["progress"]) >= need:
		state["progress"] = need
		state["awaiting_choice"] = current(state).has("choice")
		if not bool(state["awaiting_choice"]):
			_advance(state)
	return true

static func choose(state: Dictionary, option_id: String) -> Dictionary:
	var ch: Dictionary = current(state)
	var choice: Dictionary = ch.get("choice", {})
	if choice.is_empty() or not bool(state.get("awaiting_choice", false)):
		return {}
	for option in choice.get("options", []):
		if String(option.get("id", "")) != option_id:
			continue
		var key: String = String(choice.get("id", ch.get("id", "choice")))
		if not (state.get("decisions") is Dictionary): state["decisions"] = {}
		state["decisions"][key] = option_id
		var flag: String = String(option.get("flag", ""))
		if flag != "":
			if not (state.get("flags") is Dictionary): state["flags"] = {}
			state["flags"][flag] = true
		if not (state.get("effects") is Dictionary): state["effects"] = {}
		for effect in option.get("effects", {}):
			state["effects"][effect] = int(state["effects"].get(effect, 0)) + int(option["effects"][effect])
		if not (state.get("history") is Array): state["history"] = []
		state["history"].append({"chapter": ch.get("id", ""), "choice": key, "option": option_id})
		_advance(state)
		if key == "ending" and String(current(state).get("id", "")) == "epilogue":
			_advance(state)
		return option
	return {}

static func _advance(state: Dictionary) -> void:
	var old: Dictionary = current(state)
	var done: Array = state.get("completed", [])
	var id: String = String(old.get("id", ""))
	if id != "" and not done.has(id): done.append(id)
	state["completed"] = done
	state["chapter"] = int(state.get("chapter", 0)) + 1
	state["progress"] = 0
	state["awaiting_choice"] = false

static func boss_unlocked(state: Dictionary, boss_id: String) -> bool:
	var bosses: Array = data().get("bosses", [])
	for b in bosses:
		if String(b.get("id", "")) == boss_id:
			var loc_id: String = String(b.get("location", ""))
			for loc in data().get("locations", []):
				if String(loc.get("id", "")) == loc_id:
					var unlock: String = String(loc.get("unlock_chapter", ""))
					for c in chapters():
						if String(c.get("id", "")) == unlock:
							return state.get("completed", []).has(unlock) or String(current(state).get("id", "")) == unlock
	return false

static func boss(boss_id: String) -> Dictionary:
	for b in data().get("bosses", []):
		if String(b.get("id", "")) == boss_id: return b
	return {}

static func location(location_id: String) -> Dictionary:
	for loc in data().get("locations", []):
		if String(loc.get("id", "")) == location_id: return loc
	return {}

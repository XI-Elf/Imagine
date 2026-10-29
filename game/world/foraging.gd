extends RefCounted
## Пошук у полі (F, пункт 16 Huzzah 2026-10-29): звідки беруться їжа й матеріали поза містом.
## Пошук займає годину гри й сили; знайдене показується у вікні «Найдено» (world/loot_window.gd), гравець бере, що
## унесе, решта лишається на місці stash_h годин. Інструменти в сумці (forage.json tools) і факел уночі дають більше. Що можна знайти — за біомом (data/world/forage.json),
## шанс множиться на search_efficiency (Чутьё, Виживання, дари). Обшукане місце (клітина cell_m)
## порожнє regrow_h годин. Сумнівні гриби трапляються героям із низьким Чуттям.
## Числа [ВРЕМЕННО]. Пошук шумить: після нього Worlds кидає перевірку нападу (battle/encounters.gd).

const Trade := preload("res://city/trade.gd")
const FILE := "res://data/world/forage.json"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(FILE, FileAccess.READ)
		if f != null:
			var v: Variant = JSON.parse_string(f.get_as_text())
			if v is Dictionary:
				_data = v
		if _data.is_empty():
			push_error("foraging: не прочитан " + FILE)
			_data = {"biomes": {}}
	return _data


static func num(k: String, def: float) -> float:
	return float(data().get(k, def))


## Ключ клітини, яку обшукали
static func cell_key(p: Vector2) -> String:
	var c: float = num("cell_m", 400.0)
	return "%d:%d" % [int(floor(p.x / c)), int(floor(p.y / c))]


## Скільки секунд гри місце ще порожнє (0 — можна шукати)
static func depleted_left(searched: Dictionary, p: Vector2, now: float) -> float:
	return maxf(float(searched.get(cell_key(p), -1.0)) - now, 0.0)


## Що в біомі можна знайти: {id: [шанс, від, до]}
static func table(biome: int) -> Dictionary:
	return data().get("biomes", {}).get(str(biome), {})


## Інструменти в сумці: множники шансу для речей (пошук, як у виживанні: з топором — хмиз, з ножем — трави)
static func tool_mult(id: String, bag: Dictionary, night: bool) -> float:
	var m: float = 1.0
	var tools: Dictionary = data().get("tools", {})
	for t in tools:
		if Trade.count(bag, t) > 0:
			m *= float(tools[t].get(id, 1.0))
	if night:
		m *= 1.0 if Trade.count(bag, "torch") > 0 else num("night_mult", 0.6)
	return m


## Пошук. searched — пам'ять обшуканих клітин, bag — сумка (інструменти). Знайдене НЕ кладеться в сумку:
## гравець сам вибирає у вікні «Найдено» (world/loot_window.gd), решта лишається на місці (stash).
## Повертає {ok, found: {id: n}, text, minutes}. ok = false: шукати тут не можна (вода, обшукано, немає сил)
static func search(a: Actor, biome: int, p: Vector2, now: float, searched: Dictionary, bag: Dictionary, rng: RandomNumberGenerator, night: bool = false) -> Dictionary:
	var out: Dictionary = {"ok": false, "found": {}, "text": "", "minutes": 0.0}
	var t: Dictionary = table(biome)
	if t.is_empty():
		out["text"] = I18n.t("Здесь искать нечего")
		return out
	var left: float = depleted_left(searched, p, now)
	if left > 0.0:
		out["text"] = I18n.t("Здесь уже всё обшарено: загляните через %d ч") % int(ceil(left / 3600.0))
		return out
	var cost: float = num("stamina", 8.0)
	if a.res["stamina"] < cost:
		out["text"] = I18n.t("Нет сил шарить по кустам: отдохните")
		return out
	out["ok"] = true
	out["minutes"] = num("minutes", 60.0)
	a.add_res("stamina", -cost)
	searched[cell_key(p)] = now + num("regrow_h", 72.0) * 3600.0
	var eff: float = float(a.derived()["search_efficiency"])
	var found: Dictionary = out["found"]
	for id in t:
		var l: Array = t[id]
		if rng.randf() >= minf(float(l[0]) * eff * tool_mult(String(id), bag, night), 0.95):
			continue
		var n: int = rng.randi_range(int(l[1]), int(l[2]))
		var got: String = String(id)
		# Чутьё нижче порогу: частину грибів не відрізнити від поганок
		if got == "mushrooms" and a.stat("per") < num("toadstool_below_per", 5.0) and rng.randf() < num("toadstool_chance", 0.35):
			got = "toadstool"
		found[got] = int(found.get(got, 0)) + n
	a.add_xp("survival", 1.0 + 0.5 * found.size())
	out["text"] = I18n.t("Обшарил округу (%d мин): %s") % [int(out["minutes"]), I18n.t("ничего") if found.is_empty() else found_text(found)]
	return out


static func found_text(found: Dictionary) -> String:
	var parts: PackedStringArray = []
	for id in found:
		parts.append("%s ×%d" % [Trade.item_name(id), int(found[id])])
	return ", ".join(parts)


## Що лишилося на місці після вибору (stash: клітина -> {until, items}); з'єднується з новою знахідкою
static func take_stash(stash: Dictionary, p: Vector2, now: float) -> Dictionary:
	var k: String = cell_key(p)
	var e: Dictionary = stash.get(k, {})
	stash.erase(k)
	if e.is_empty() or float(e.get("until", 0.0)) <= now:
		return {}
	return e.get("items", {})


static func leave_stash(stash: Dictionary, p: Vector2, now: float, items: Dictionary) -> void:
	var rest: Dictionary = {}
	for id in items:
		if int(items[id]) > 0:
			rest[id] = int(items[id])
	if rest.is_empty():
		stash.erase(cell_key(p))
	else:
		stash[cell_key(p)] = {"until": now + num("stash_h", 72.0) * 3600.0, "items": rest}


## Для збереження: прибрати клітини, що вже відросли
static func prune(searched: Dictionary, now: float, stash: Dictionary = {}) -> void:
	for k in searched.keys():
		if float(searched[k]) <= now:
			searched.erase(k)
	for k in stash.keys():
		if float(stash[k].get("until", 0.0)) <= now:
			stash.erase(k)

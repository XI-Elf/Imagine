extends RefCounted
## Пошук у полі (F, пункт 16 Huzzah 2026-10-29): звідки беруться їжа й матеріали поза містом.
## Пошук займає час і сили, знахідки йдуть у сумку героя. Що можна знайти — за біомом (data/world/forage.json),
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


## Пошук. searched — пам'ять обшуканих клітин (зберігається з героєм), bag — сумка.
## Повертає {ok, found: {id: n}, text, minutes}. ok = false: шукати тут не можна (вода, обшукано, немає сил)
static func search(a: Actor, biome: int, p: Vector2, now: float, searched: Dictionary, bag: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
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
	out["minutes"] = num("minutes", 30.0)
	a.add_res("stamina", -cost)
	searched[cell_key(p)] = now + num("regrow_h", 24.0) * 3600.0
	var eff: float = float(a.derived()["search_efficiency"])
	var found: Dictionary = out["found"]
	for id in t:
		var l: Array = t[id]
		if rng.randf() >= minf(float(l[0]) * eff, 0.95):
			continue
		var n: int = rng.randi_range(int(l[1]), int(l[2]))
		var got: String = String(id)
		# Чутьё нижче порогу: частину грибів не відрізнити від поганок
		if got == "mushrooms" and a.stat("per") < num("toadstool_below_per", 5.0) and rng.randf() < num("toadstool_chance", 0.35):
			got = "toadstool"
		found[got] = int(found.get(got, 0)) + n
	for id in found:
		Trade.add(bag, id, int(found[id]))
	a.add_xp("survival", 1.0 + 0.5 * found.size())
	var parts: PackedStringArray = []
	for id in found:
		parts.append("%s ×%d" % [Trade.item_name(id), int(found[id])])
	out["text"] = I18n.t("Обшарил округу (%d мин): %s") % [int(out["minutes"]), I18n.t("ничего") if parts.is_empty() else ", ".join(parts)]
	return out


## Для збереження: прибрати клітини, що вже відросли
static func prune(searched: Dictionary, now: float) -> void:
	for k in searched.keys():
		if float(searched[k]) <= now:
			searched.erase(k)

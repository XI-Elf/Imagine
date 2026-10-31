extends RefCounted
## Пошук у полі (F, пункт 16 Huzzah 2026-10-29; переробка 2026-10-30 за ідеєю «пошуку на час» із виживалок, свої числа):
## гравець вибирає, скільки шукати (15 хв – 2 год), пошук іде обходами по round_min хвилин, кожен обхід коштує сил
## і показує знахідки у вікні (world/loot_window.gd) одразу. Місце має запас (richness): кожен обхід вибирає його,
## тож перший обхід найщедріший, а обшарене місце відростає regrow_h годин. Що можна знайти — за біомом
## (data/world/forage.json), шанс множиться на search_efficiency (Чутьё, Виживання, дари), інструменти й факел уночі.
## Не взяте лишається на місці stash_h годин. Сумнівні гриби трапляються героям із низьким Чуттям.
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


## Скільки в місці ще лишилося: 1 — нетронуте, 0 — обшарене до нитки. searched[клітина] = коли місце відросте повністю;
## кожен обхід забирає round_drain, а відростає місце рівно за regrow_h (старі збереження з тим самим числом читаються так само)
static func richness(searched: Dictionary, p: Vector2, now: float) -> float:
	var full_at: float = float(searched.get(cell_key(p), -1.0))
	if full_at <= now:
		return 1.0
	return clampf(1.0 - (full_at - now) / (num("regrow_h", 72.0) * 3600.0), 0.0, 1.0)


static func _drain(searched: Dictionary, p: Vector2, now: float, amount: float) -> void:
	var r: float = maxf(richness(searched, p, now) - amount, 0.0)
	searched[cell_key(p)] = now + (1.0 - r) * num("regrow_h", 72.0) * 3600.0


## Слово про місце для вікна пошуку
static func richness_word(r: float) -> String:
	if r >= 0.95:
		return I18n.t("нетронутое место")
	if r >= 0.6:
		return I18n.t("здесь уже кто-то шарил")
	if r >= num("min_richness", 0.15):
		return I18n.t("почти всё собрано")
	return I18n.t("обшарено до нитки")


## Чи можна шукати тут зараз: "" — так, інакше причина
static func check(a: Actor, biome: int, p: Vector2, now: float, searched: Dictionary) -> String:
	if table(biome).is_empty():
		return I18n.t("Здесь искать нечего")
	var r: float = richness(searched, p, now)
	if r < num("min_richness", 0.15):
		var regrow_s: float = num("regrow_h", 72.0) * 3600.0
		var wait_s: float = (float(searched[cell_key(p)]) - now) - (1.0 - num("min_richness", 0.15) * 2.0) * regrow_s
		return I18n.t("Здесь уже всё обшарено: загляните через %d ч") % maxi(int(ceil(wait_s / 3600.0)), 1)
	if a.res["stamina"] < num("round_stamina", 2.5):
		return I18n.t("Нет сил шарить по кустам: отдохните")
	return ""


## Один обхід (round_min хвилин гри, round_stamina сил): кожна річ біому кидається з шансом
## шанс × search_efficiency × інструменти × round_k × скільки лишилося в місці. Знайдене НЕ кладеться в сумку.
## Повертає {ok, found: {id: n}, text, minutes, richness (після обходу)}
static func search_round(a: Actor, biome: int, p: Vector2, now: float, searched: Dictionary, bag: Dictionary, rng: RandomNumberGenerator, night: bool = false) -> Dictionary:
	var out: Dictionary = {"ok": false, "found": {}, "text": check(a, biome, p, now, searched), "minutes": 0.0, "richness": richness(searched, p, now)}
	if String(out["text"]) != "":
		return out
	out["ok"] = true
	out["minutes"] = num("round_min", 15.0)
	a.add_res("stamina", -num("round_stamina", 2.5))
	var k: float = num("round_k", 0.35) * float(out["richness"])
	var eff: float = float(a.derived()["search_efficiency"])
	var t: Dictionary = table(biome)
	var found: Dictionary = out["found"]
	for id in t:
		var l: Array = t[id]
		if rng.randf() >= minf(float(l[0]) * eff * tool_mult(String(id), bag, night) * k, 0.9):
			continue
		var n: int = rng.randi_range(int(l[1]), int(l[2]))
		var got: String = String(id)
		# Чутьё нижче порогу: частину грибів не відрізнити від поганок
		if got == "mushrooms" and a.stat("per") < num("toadstool_below_per", 5.0) and rng.randf() < num("toadstool_chance", 0.35):
			got = "toadstool"
		found[got] = int(found.get(got, 0)) + n
	_drain(searched, p, now, num("round_drain", 0.25))
	out["richness"] = richness(searched, p, now)
	a.add_xp("survival", 0.25 + 0.15 * found.size())
	out["text"] = found_text(found) if not found.is_empty() else I18n.t("пусто")
	return out


## Пошук одним махом (rounds обходів, за замовчуванням minutes / round_min): для тестів і швидких викликів.
## Повертає {ok, found, text, minutes}; ok = false, якщо не вдався вже перший обхід
static func search(a: Actor, biome: int, p: Vector2, now: float, searched: Dictionary, bag: Dictionary, rng: RandomNumberGenerator, night: bool = false, rounds: int = -1) -> Dictionary:
	if rounds < 0:
		rounds = int(num("minutes", 60.0) / num("round_min", 15.0))
	var out: Dictionary = {"ok": false, "found": {}, "text": "", "minutes": 0.0}
	for i in rounds:
		var r: Dictionary = search_round(a, biome, p, now + float(out["minutes"]) * 60.0, searched, bag, rng, night)
		if not bool(r["ok"]):
			if i == 0:
				out["text"] = r["text"]
				return out
			break
		out["ok"] = true
		out["minutes"] = float(out["minutes"]) + float(r["minutes"])
		for id in r["found"]:
			out["found"][id] = int(out["found"].get(id, 0)) + int(r["found"][id])
	out["text"] = I18n.t("Обшарил округу (%d мин): %s") % [int(out["minutes"]), I18n.t("ничего") if out["found"].is_empty() else found_text(out["found"])]
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

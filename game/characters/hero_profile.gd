extends RefCounted
## Создание героя по правилам сборки 09 (character.gd / character_balance.gd / character_biography.gd),
## переложенным на общий класс Actor: 10 очков на 7 характеристик (база 4), пол, возраст, происхождение,
## профессия (сумма их поправок в пределах ±5, Удача −5…+2), до 10 черт характера без противоположностей
## (скрытая Удача из баланса черт, не больше ±10), мировоззрение из черт, биография.
## Навыки — уровни навыков пака (0–10). Все данные — res://data/characters/creation.json.
## params: {name, gender, age, origin, profession, alloc: {stat: очки}, traits: [id]}

const R := preload("res://characters/actor_rules.gd")


static func C() -> Dictionary:
	return R.creation()


static func stats_list() -> Array:
	return ["str", "agi", "int", "end", "per", "wis", "cha"]


static func stat_name(s: String) -> String:
	return String(R.section("stats").get("names", {}).get(s, s))


static func default_params() -> Dictionary:
	var alloc: Dictionary = {}
	for s in stats_list():
		alloc[s] = 0
	return {"name": "", "gender": "female", "age": 25, "origin": C()["origins"].keys()[0],
		"profession": C()["professions"].keys()[0], "alloc": alloc, "traits": []}


# =====================================================================
# ПОПРАВКИ
# =====================================================================
static func _add(into: Dictionary, src: Dictionary, k: float = 1.0) -> void:
	for s in src:
		into[s] = int(into.get(s, 0)) + int(round(float(src[s]) * k))


## Происхождение + профессия: сумма по каждой характеристике в пределах ±5, Удача −5…+2 (правило 09)
static func background_mods(o: String, p: String) -> Dictionary:
	var lim: Dictionary = C().get("background_limits", {})
	var od: Dictionary = C()["origins"].get(o, {})
	var pd: Dictionary = C()["professions"].get(p, {})
	var st: Dictionary = {}
	_add(st, od.get("stats", {}))
	_add(st, pd.get("stats", {}))
	for s in st.keys():
		st[s] = clampi(int(st[s]), int(lim.get("min", -5)), int(lim.get("max", 5)))
		if int(st[s]) == 0:
			st.erase(s)
	var luck: int = clampi(int(od.get("luck", 0)) + int(pd.get("luck", 0)), int(lim.get("luck_min", -5)), int(lim.get("luck_max", 2)))
	return {"stats": st, "luck": luck}


static func age_mods(age: int) -> Dictionary:
	for g in C().get("age_groups", []):
		if age >= int(g[0]) and age <= int(g[1]):
			return g[2]
	return {}


static func trait_mods(list: Array) -> Dictionary:
	var st: Dictionary = {}
	for t in list:
		_add(st, R.trait_def(t).get("stats", {}))
	return st


# =====================================================================
# ЧЕРТЫ
# =====================================================================
## "" — набор годится; иначе причина
static func traits_valid(list: Array) -> String:
	if list.size() > int(C().get("trait_max", 10)):
		return I18n.t("не больше %d черт") % int(C().get("trait_max", 10))
	var seen: Dictionary = {}
	for t in list:
		if R.trait_def(t).is_empty():
			return I18n.t("нет такой черты")
		if seen.has(t):
			return I18n.t("черта повторяется")
		seen[t] = true
	for t in list:
		var opp: String = String(R.trait_def(t).get("opp", ""))
		if opp != "" and seen.has(opp):
			return I18n.t("«%s» и «%s» несовместимы") % [R.trait_def(t)["title"], R.trait_def(opp)["title"]]
	return ""


static func traits_cost(list: Array) -> Dictionary:
	var pos: int = 0
	var neg: int = 0
	for t in list:
		var c: int = int(R.trait_def(t).get("cost", 0))
		if c > 0:
			pos += c
		else:
			neg -= c
	return {"positive": pos, "negative": neg}


## Скрытая поправка Удачи: негативные черты её добавляют, позитивные отнимают (правило 09)
static func hidden_luck(list: Array) -> int:
	var c: Dictionary = traits_cost(list)
	var lim: int = int(C().get("trait_luck_limit", 10))
	return clampi(int(c["negative"]) - int(c["positive"]), -lim, lim)


static func random_traits(r: RandomNumberGenerator) -> Array:
	var keys: Array = C()["traits"].keys()
	var want: int = r.randi_range(2, 6)
	var out: Array = []
	var guard: int = 0
	while out.size() < want and guard < 200:
		guard += 1
		var test: Array = out.duplicate()
		test.append(keys[r.randi() % keys.size()])
		if traits_valid(test) == "":
			out = test
	return out


## Описание черты одной строкой: что даёт и сколько стоит
static func trait_text(t: String) -> String:
	var d: Dictionary = R.trait_def(t)
	var parts: Array = []
	for k in d.get("stats", {}):
		parts.append("%s %+d" % [stat_name(k), int(d["stats"][k])])
	for k in d.get("skills", {}):
		parts.append(I18n.t("%s %+d ур.") % [R.skills().get(k, {}).get("name_ru", k), int(d["skills"][k])])
	for k in d.get("effects", {}):
		parts.append(effect_text(k, float(d["effects"][k])))
	if d.has("moral") or d.has("order"):
		parts.append(I18n.t("мировоззрение"))
	var s: String = "%s — %s" % [d.get("title", t), d.get("text", "")]
	if not parts.is_empty():
		s += " (%s)" % ", ".join(parts)
	return s + "."


static var EFFECT_NAMES: Dictionary = {
	"power": I18n.t("сила удара"), "speed": I18n.t("скорость"), "loot": I18n.t("поиск"), "xp": I18n.t("опыт навыков"),
	"disease_chance": I18n.t("шанс заболеть"), "fall_chance": I18n.t("травмы в пути"), "food_water_chance": I18n.t("болезни от еды и сырой воды"),
	"sneak": I18n.t("шанс проникнуть в город"), "sleep_energy": I18n.t("отдых во сне"),
}


static func effect_text(k: String, v: float) -> String:
	match k:
		"health_regen":
			return I18n.t("здоровье %+.1f/ч") % v
		"hunger":
			return I18n.t("голод %+.1f/ч") % (v * 100.0)
		"energy_decay":
			return I18n.t("энергия %+.1f/ч") % (-v * 100.0)
		"cold_resist_c":
			return I18n.t("холод на %d °C позже") % int(v)
		"heat_resist_c":
			return I18n.t("жара на %d °C позже") % int(v)
	return "%s %+d %%" % [EFFECT_NAMES.get(k, k), int(round(v * 100.0))]


# =====================================================================
# МИРОВОЗЗРЕНИЕ
# =====================================================================
static func alignment(list: Array) -> Dictionary:
	var a: Dictionary = C().get("alignment", {})
	var k: float = float(a.get("per_point", 20.0))
	var moral: float = 0.0
	var order: float = 0.0
	for t in list:
		moral += float(R.trait_def(t).get("moral", 0.0))
		order += float(R.trait_def(t).get("order", 0.0))
	return {"moral": clampf(moral * k, -100.0, 100.0), "order": clampf(order * k, -100.0, 100.0)}


static func _axis(v: float) -> int:
	var th: float = float(C().get("alignment", {}).get("threshold", 34.0))
	return 2 if v >= th else (0 if v <= -th else 1)


static func alignment_name(al: Dictionary) -> String:
	var names: Dictionary = C().get("alignment", {}).get("names", {})
	return String(names.get("%d,%d" % [_axis(float(al.get("order", 0.0))), _axis(float(al.get("moral", 0.0)))], I18n.t("Нейтральный")))


# =====================================================================
# ИТОГ
# =====================================================================
static func points_spent(alloc: Dictionary) -> int:
	var n: int = 0
	for s in alloc:
		n += int(alloc[s])
	return n


static func alloc_valid(alloc: Dictionary) -> bool:
	for s in alloc:
		if not stats_list().has(s) or int(alloc[s]) < 0:
			return false
	return points_spent(alloc) == int(C().get("points", 10))


## Характеристики по частям: {stat: {base, gender, background, age, traits, total}}; luck: {background, hidden, total}
static func stat_parts(p: Dictionary) -> Dictionary:
	var base: int = int(C().get("stat_base", 4))
	var mn: int = int(C().get("stat_min", 4))
	var bg: Dictionary = background_mods(String(p.get("origin", "")), String(p.get("profession", "")))
	var gm: Dictionary = C()["genders"].get(String(p.get("gender", "female")), {}).get("stats", {})
	var am: Dictionary = age_mods(int(p.get("age", 25)))
	var tm: Dictionary = trait_mods(p.get("traits", []))
	var out: Dictionary = {}
	for s in stats_list():
		var e: Dictionary = {"base": base + int(p.get("alloc", {}).get(s, 0)), "gender": int(gm.get(s, 0)),
			"background": int(bg["stats"].get(s, 0)), "age": int(am.get(s, 0)), "traits": int(tm.get(s, 0))}
		e["total"] = maxi(mn, int(e["base"]) + int(e["gender"]) + int(e["background"]) + int(e["age"]) + int(e["traits"]))
		out[s] = e
	var hl: int = hidden_luck(p.get("traits", []))
	out["luck"] = {"background": int(bg["luck"]), "hidden": hl, "total": int(bg["luck"]) + hl}
	return out


## Начальные уровни навыков пака от происхождения, профессии и черт
static func skill_levels(p: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	_add(out, C()["origins"].get(String(p.get("origin", "")), {}).get("skills", {}))
	_add(out, C()["professions"].get(String(p.get("profession", "")), {}).get("skills", {}))
	for t in p.get("traits", []):
		_add(out, R.trait_def(t).get("skills", {}))
	for k in out.keys():
		if not R.skills().has(k) or int(out[k]) <= 0:
			out.erase(k)
	return out


static func years(n: int) -> String:
	if n % 100 >= 11 and n % 100 <= 14:
		return I18n.t("лет")
	if n % 10 == 1:
		return I18n.t("год")
	if n % 10 >= 2 and n % 10 <= 4:
		return I18n.t("года")
	return I18n.t("лет")


## Биография коротко (Huzzah 2026-10-23: «меньше текста»): 2–3 предложения —
## кто и откуда с ремеслом, одна черта (самая короткая из выбранных), мировоззрение.
## Одинаковый выбор — одинаковый текст. Полные тексты 09 остались в creation.json.
static func biography(p: Dictionary) -> String:
	var data: Dictionary = C().get("biography", {})
	var nm: String = String(p.get("name", "")).strip_edges()
	var male: bool = String(p.get("gender", "female")) == "male"
	if nm == "":
		nm = I18n.t("Безымянный путник") if male else I18n.t("Безымянная путница")
	var o: String = String(p.get("origin", ""))
	var pr: String = String(p.get("profession", ""))
	var sel: Array = p.get("traits", [])
	var age: int = int(p.get("age", 25))
	var out: PackedStringArray = []
	out.append(I18n.t("%s, %d %s. %s, ремесло — %s.") % [nm, age, years(age),
		String(data.get("origins_short", {}).get(o, I18n.t("Родом издалека"))), String(data.get("professions_short", {}).get(pr, I18n.t("своё")))])
	var best: String = ""
	for k in C()["traits"]:
		if sel.has(k):
			var t: String = String(data.get("traits", {}).get(k, R.trait_def(k).get("text", "")))
			var first: String = t.split(":")[0].split(";")[0].split(".")[0].strip_edges()
			if first != "" and (best == "" or first.length() < best.length()):
				best = first
	if best != "":
		out.append(best + ".")
	out.append(I18n.t("Мировоззрение: «%s».") % alignment_name(alignment(sel)))
	return " ".join(out)


static func random_params(r: RandomNumberGenerator) -> Dictionary:
	var p: Dictionary = default_params()
	p["gender"] = "male" if r.randi() % 2 == 0 else "female"
	var names: Array = C()["names"][p["gender"]]
	p["name"] = names[r.randi() % names.size()]
	p["age"] = r.randi_range(int(C().get("age_min", 18)), int(C().get("age_max", 60)))
	var o: Array = C()["origins"].keys()
	var pr: Array = C()["professions"].keys()
	p["origin"] = o[r.randi() % o.size()]
	p["profession"] = pr[r.randi() % pr.size()]
	for _i in int(C().get("points", 10)):
		var s: String = stats_list()[r.randi() % stats_list().size()]
		p["alloc"][s] = int(p["alloc"][s]) + 1
	p["traits"] = random_traits(r)
	return p


## Записать выбор в персонажа: имя, характеристики, Удача, черты, навыки, профиль для окна героя
static func apply(a: Actor, p: Dictionary) -> void:
	var parts: Dictionary = stat_parts(p)
	for s in stats_list():
		a.set_stat(s, int(parts[s]["total"]))
	a.set_stat("luck", int(parts["luck"]["total"]))
	var tl: Array = p.get("traits", [])
	a.traits = tl.duplicate() if traits_valid(tl) == "" else []
	var lv: Dictionary = skill_levels(p)
	for k in lv:
		a.set_skill_level(k, int(lv[k]))
	var nm: String = String(p.get("name", "")).strip_edges()
	if nm != "":
		a.display_name = nm
	var mods: Dictionary = {}
	for s in stats_list():
		mods[s] = parts[s].duplicate()
	a.profile = {
		"gender": String(p.get("gender", "female")), "age": int(p.get("age", 25)),
		"origin": String(p.get("origin", "")), "profession": String(p.get("profession", "")),
		"alignment": alignment(a.traits), "biography": biography(p), "stat_parts": mods,
	}

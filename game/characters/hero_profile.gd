extends RefCounted
## Создание героя. Кто он — по правилам сборки 09 (пол, возраст, происхождение, профессия, до 10 черт
## характера без противоположностей, мировоззрение, биография). Характеристики и навыки —
## characters/sheet.gd: характеристики от 5, 5 свободных очков, можно опустить до 1; 3 отмеченных навыка
## (профессия предлагает свои); до 2 особенностей. Черты характера меняют характеристики (stats, ±1), прошлое — нет; «skills»
## (уровни старых навыков пака) дают +5 % за уровень к навыку. Данные — creation.json, sheet.json.
## params: {name, gender, age, origin, profession, alloc: {stat: от 5}, tags: [навык], quirks: [id], traits: [id]}

const R := preload("res://characters/actor_rules.gd")
const S := preload("res://characters/sheet.gd")


static func C() -> Dictionary:
	return R.creation()


static func stats_list() -> Array:
	return S.stats_list()


static func stat_name(s: String) -> String:
	return S.stat_name(s)


static func profession_tags(p: String) -> Array:
	return C()["professions"].get(p, {}).get("tags", []).duplicate()


static func default_params() -> Dictionary:
	var alloc: Dictionary = {}
	for s in stats_list():
		alloc[s] = 0
	var pr: String = C()["professions"].keys()[0]
	return {"name": "", "gender": "female", "age": 25, "origin": C()["origins"].keys()[0],
		"profession": pr, "alloc": alloc, "tags": profession_tags(pr), "quirks": [], "traits": []}


# =====================================================================
# ПОПРАВКИ
# =====================================================================
static func _add(into: Dictionary, src: Dictionary, k: float = 1.0) -> void:
	for s in src:
		into[s] = int(into.get(s, 0)) + int(round(float(src[s]) * k))


## Поправки підвиду людей (дані creation.json, числа [ВРЕМЕННО]); порожній ключ чи невідомий підвид: {}
static func subspecies_mods(sub: String) -> Dictionary:
	return C().get("subspecies", {}).get(sub, {}).get("stats", {})


# =====================================================================
# РИСИ
# =====================================================================
## "" — набір годиться; інакше причина
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


## Опис риси одним рядком: що дає й скільки коштує
static func trait_text(t: String) -> String:
	var d: Dictionary = R.trait_def(t)
	var parts: Array = []
	for k in d.get("stats", {}):
		parts.append("%s %+d" % [S.stat_name(k), int(d["stats"][k])])
	for k in d.get("skills", {}):
		parts.append("%s %+d %%" % [S.skill_name(k), int(d["skills"][k]) * legacy_pct()])
	for k in d.get("effects", {}):
		parts.append(effect_text(k, float(d["effects"][k])))
	if d.has("moral") or d.has("order"):
		parts.append(I18n.t("мировоззрение"))
	var s: String = "%s — %s" % [d.get("title", t), d.get("text", "")]
	if not parts.is_empty():
		s += " (%s)" % ", ".join(parts)
	return s + "."


static var EFFECT_NAMES: Dictionary = {
	"power": I18n.t("сила удара"), "speed": I18n.t("скорость"), "loot": I18n.t("поиск"), "xp": I18n.t("опыт"),
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
			return (I18n.t("холод на %d °C позже") % int(v)) if v >= 0.0 else (I18n.t("холод на %d °C раньше") % int(-v))
		"heat_resist_c":
			return (I18n.t("жара на %d °C позже") % int(v)) if v >= 0.0 else (I18n.t("жара на %d °C раньше") % int(-v))
	return "%s %+d %%" % [EFFECT_NAMES.get(k, k), int(round(v * 100.0))]


# =====================================================================
# СВІТОГЛЯД
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
# ПІДСУМОК
# =====================================================================
static func points_spent(alloc: Dictionary) -> int:
	var n: int = 0
	for s in alloc:
		n += int(alloc[s])
	return n


static func alloc_valid(alloc: Dictionary) -> bool:
	return S.alloc_valid(alloc) == ""


static func legacy_pct() -> int:
	return int(S.data().get("legacy_level_pct", 5))


## Временный герой из выбора — чтобы посчитать характеристики с особенностями и навыки
static func preview_actor(p: Dictionary) -> Actor:
	var a := Actor.new("preview", String(p.get("name", "")), false, 1)
	a.profile = {"subspecies": String(p.get("subspecies", ""))}
	S.apply_creation(a, p.get("alloc", {}), p.get("tags", []), p.get("quirks", []))
	var tl: Array = p.get("traits", [])
	a.traits = tl.duplicate() if traits_valid(tl) == "" else []
	var b: Dictionary = skill_bonus(p)
	for k in b:
		a.skills[k]["bonus"] = int(b[k])
	return a


## Характеристики по частям: {stat: {base (5 + очки), subspecies (підвид), traits (черты характера и особенности), total}}
static func stat_parts(p: Dictionary) -> Dictionary:
	var a: Actor = preview_actor(p)
	var out: Dictionary = {}
	for s in stats_list():
		var base: int = int(S.data().get("base", 5)) + int(p.get("alloc", {}).get(s, 0))
		var tot: int = S.stat_value(a, s)
		var sub: int = int(subspecies_mods(String(p.get("subspecies", ""))).get(s, 0))
		out[s] = {"base": base, "subspecies": sub, "traits": tot - base - sub, "total": tot}
	return out


## Добавка к навыкам от происхождения, профессии и черт характера: {навык: %}
static func skill_bonus(p: Dictionary) -> Dictionary:
	var lv: Dictionary = {}
	_add(lv, C()["origins"].get(String(p.get("origin", "")), {}).get("skills", {}))
	_add(lv, C()["professions"].get(String(p.get("profession", "")), {}).get("skills", {}))
	for t in p.get("traits", []):
		_add(lv, R.trait_def(t).get("skills", {}))
	var out: Dictionary = {}
	for k in lv:
		var nk: String = S.canon(String(k))
		if S.skills().has(nk) and int(lv[k]) > 0:
			out[nk] = int(out.get(nk, 0)) + int(lv[k]) * legacy_pct()
	return out


## Начальные навыки в процентах: {навык: значение}
static func skill_values(p: Dictionary) -> Dictionary:
	var a: Actor = preview_actor(p)
	var out: Dictionary = {}
	for k in S.skill_list():
		out[k] = S.skill_value(a, k)
	return out


static func years(n: int) -> String:
	if n % 100 >= 11 and n % 100 <= 14:
		return I18n.t("лет")
	if n % 10 == 1:
		return I18n.t("год")
	if n % 10 >= 2 and n % 10 <= 4:
		return I18n.t("года")
	return I18n.t("лет")


## Біографія коротко (Huzzah 2026-10-23: «менше тексту»): 2–3 речення —
## хто й звідки з ремеслом, одна риса (найкоротша з обраних), світогляд.
## Однаковий вибір — однаковий текст. Повні тексти 09 лишилися в creation.json.
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
	var sub: String = String(data.get("subspecies_short", {}).get(String(p.get("subspecies", "")), ""))
	out.append(I18n.t("%s, %d %s. %s, ремесло — %s.") % [nm, age, years(age),
		String(data.get("origins_short", {}).get(o, I18n.t("Родом издалека"))), String(data.get("professions_short", {}).get(pr, I18n.t("своё")))])
	if sub != "":
		out[0] = sub + ". " + out[0]
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
	p["tags"] = profession_tags(p["profession"])
	var guard: int = 0
	while S.alloc_left(p["alloc"]) > 0 and guard < 100:
		guard += 1
		var s: String = stats_list()[r.randi() % stats_list().size()]
		if int(p["alloc"][s]) + int(S.data().get("base", 5)) < int(S.data().get("max", 10)):
			p["alloc"][s] = int(p["alloc"][s]) + 1
	var ft: Array = S.traits().keys()
	p["quirks"] = [] if r.randi() % 3 == 0 else [ft[r.randi() % ft.size()]]
	p["traits"] = random_traits(r)
	# підвид тягнеться останнім: попередні випадкові вибори не зсуваються
	var sk: Array = C().get("subspecies", {}).keys()
	if not sk.is_empty():
		p["subspecies"] = sk[r.randi() % sk.size()]
	return p


## Записать выбор в персонажа: имя, характеристики, отмеченные навыки, особенности и черты характера, добавки
## к навыкам от прошлого, профиль для окна героя
static func apply(a: Actor, p: Dictionary) -> void:
	var tl: Array = p.get("traits", [])
	a.traits = tl.duplicate() if traits_valid(tl) == "" else []
	var tags: Array = p.get("tags", [])
	if S.tags_valid(tags) != "":
		tags = profession_tags(String(p.get("profession", "")))
	S.apply_creation(a, p.get("alloc", {}), tags, p.get("quirks", []))
	var b: Dictionary = skill_bonus(p)
	for k in a.skills:
		a.skills[k]["bonus"] = int(b.get(k, 0))
	var nm: String = String(p.get("name", "")).strip_edges()
	if nm != "":
		a.display_name = nm
	var parts: Dictionary = stat_parts(p)
	var mods: Dictionary = {}
	for s in stats_list():
		mods[s] = parts[s].duplicate()
	a.profile = {
		"gender": String(p.get("gender", "female")), "age": int(p.get("age", 25)),
		"origin": String(p.get("origin", "")), "profession": String(p.get("profession", "")),
		"alignment": alignment(a.traits), "biography": biography(p), "stat_parts": mods,
		"subspecies": String(p.get("subspecies", "")),
	}

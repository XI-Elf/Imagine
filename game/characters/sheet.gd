extends RefCounted
## Система персонажа (запрос Huzzah 2026-10-28): характеристики 1–10, производные параметры
## по формулам, 18 навыков в процентах (стартовые формулы, отмеченные навыки, лестница цены
## очков), уровни по таблице опыта, очки навыков 5 + 2×ИНТ за уровень, особенности (не больше двух)
## и перки раз в 3 уровня. Всё — статические функции над Actor; числа — data/characters/sheet.json и perks.json.
## В Actor хранится только выбор игрока: stats (база характеристик), skills {k: {pts, bonus}}, tags, quirks,
## perks {id: ранг}, level, xp, skill_points, perk_picks. Остальное считается здесь.

const DIR := "res://data/characters/"
const COMBAT_SKILLS: Array = ["bows", "heavy", "relic", "unarmed", "melee", "throwing"]

static var _cache: Dictionary = {}


static func _load(file: String) -> Dictionary:
	if _cache.has(file):
		return _cache[file]
	var d: Dictionary = {}
	var f := FileAccess.open(DIR + file, FileAccess.READ)
	if f != null:
		var v: Variant = JSON.parse_string(f.get_as_text())
		if v is Dictionary:
			d = v
	if d.is_empty():
		push_error("sheet: не прочитан " + DIR + file)
	_cache[file] = d
	return d


static func data() -> Dictionary:
	return _load("sheet.json")


static func sect(k: String) -> Dictionary:
	return data().get(k, {})


static func num(s: String, k: String, def: float = 0.0) -> float:
	return float(sect(s).get(k, def))


static func stats_list() -> Array:
	return data().get("stats", ["str", "per", "end", "cha", "int", "agi", "luck"])


static func stat_name(s: String) -> String:
	return String(sect("names").get(s, s))


static func stat_short(s: String) -> String:
	return String(sect("short").get(s, s))


static func stat_level_name(v: int) -> String:
	var l: Array = data().get("stat_levels", [])
	return String(l[clampi(v, 0, l.size() - 1)]) if not l.is_empty() else ""


static func skills() -> Dictionary:
	return sect("skills")


static func skill_list() -> Array:
	return skills().keys()


static func skill_name(k: String) -> String:
	return String(skills().get(canon(k), {}).get("name", k))


## Старый ключ навыка пака (survival, medicine…) → навык; новый ключ — как есть
static func canon(k: String) -> String:
	if skills().has(k):
		return k
	return String(sect("legacy_skills").get(k, k))


## Черты характера сборки 09 (creation.json): их stats добавляются к характеристикам
static func char_traits() -> Dictionary:
	return _load("creation.json").get("traits", {})


static func traits() -> Dictionary:
	return sect("traits")


static func perks() -> Dictionary:
	return _load("perks.json").get("perks", {})


static func perk_def(id: String) -> Dictionary:
	return perks().get(id, {})


# =====================================================================
# ЭФФЕКТЫ особенностей и перков (перк — × ранг)
# =====================================================================
static func eff(a: Actor, key: String) -> float:
	if a == null:
		return 0.0
	var t: float = 0.0
	for id in a.quirks:
		t += float(traits().get(id, {}).get("effects", {}).get(key, 0.0))
	for id in a.perks:
		t += float(perk_def(id).get("effects", {}).get(key, 0.0)) * int(a.perks[id])
	return t


static func has(a: Actor, key: String) -> bool:
	return eff(a, key) != 0.0


## Все эффекты черт и перков списком [{ключ: значение}] — для общих множителей Actor.mult()
static func effect_dicts(a: Actor) -> Array:
	var out: Array = []
	for id in a.quirks:
		out.append(traits().get(id, {}).get("effects", {}))
	for id in a.perks:
		var e: Dictionary = perk_def(id).get("effects", {})
		var rk: int = int(a.perks[id])
		if rk == 1:
			out.append(e)
		else:
			var m: Dictionary = {}
			for k in e:
				m[k] = float(e[k]) * rk if (e[k] is float or e[k] is int) else e[k]
			out.append(m)
	return out


# =====================================================================
# ХАРАКТЕРИСТИКИ
# =====================================================================
## Действующее значение: база + черты характера (creation.json, stats) + особенности и перки
## («Громила», «Развить…») + ночь для «Ночного создания»; 1–10
static func stat_value(a: Actor, s: String) -> int:
	var v: float = float(a.stats.get(s, int(data().get("base", 5))))
	v += eff(a, "stat_" + s) + eff(a, "stats_all")
	for t in a.traits:
		v += float(char_traits().get(t, {}).get("stats", {}).get(s, 0))
	if has(a, "night_person") and (s == "int" or s == "per"):
		v += 1.0 if bool(a.last_env.get("night", false)) else -1.0
	return clampi(int(v), int(data().get("min", 1)), int(data().get("max", 10)))


## Харизма и Интеллект в разговоре (черта «Привлекательность», перк «Сладкоречивый»)
static func talk_cha(a: Actor) -> int:
	return stat_value(a, "cha") + int(eff(a, "talk_cha"))


static func talk_int(a: Actor) -> int:
	return stat_value(a, "int") + int(eff(a, "talk_int"))


static func dumb(a: Actor) -> bool:
	return talk_int(a) <= int(sect("dialogue").get("dumb_max_int", 3))


static func smart(a: Actor) -> bool:
	return talk_int(a) >= int(sect("dialogue").get("smart_min_int", 7))


# =====================================================================
# ПРОИЗВОДНЫЕ
# =====================================================================
static func d(k: String, def: float = 0.0) -> float:
	return num("derived", k, def)


static func hp_per_level(a: Actor) -> int:
	return int(d("hp_level_base", 2)) + int(floor(stat_value(a, "end") / maxf(d("hp_level_end_div", 2), 1.0))) + int(eff(a, "hp_per_level"))


static func hp_max(a: Actor) -> int:
	var hp: int = int(d("hp_base", 15)) + int(d("hp_per_str", 1)) * stat_value(a, "str") + int(d("hp_per_end", 2)) * stat_value(a, "end")
	return hp + (a.level - 1) * hp_per_level(a) + int(eff(a, "hp_bonus"))


static func ap(a: Actor) -> int:
	return maxi(1, int(d("ap_base", 5)) + int(floor(stat_value(a, "agi") / maxf(d("ap_agi_div", 2), 1.0))) + int(eff(a, "ap")))


static func armor_class(a: Actor) -> int:
	return 0 if has(a, "no_agi_ac") else stat_value(a, "agi")


static func carry_lb(a: Actor) -> float:
	var per: float = d("carry_lb_per_str", 25) + eff(a, "carry_lb_per_str")
	return d("carry_lb_base", 25) + per * stat_value(a, "str") + eff(a, "carry_lb")


static func carry_kg(a: Actor) -> float:
	return carry_lb(a) * d("lb_to_kg", 0.4536) + eff(a, "carry_kg")


static func melee_damage(a: Actor) -> int:
	return maxi(int(d("melee_min", 1)), stat_value(a, "str") + int(d("melee_base", -5))) + int(eff(a, "melee_dmg"))


static func poison_resist(a: Actor) -> int:
	if has(a, "poison_resist_zero"):
		return int(eff(a, "poison_resist"))
	return clampi(int(d("poison_per_end", 5)) * stat_value(a, "end") + int(eff(a, "poison_resist")), 0, int(d("resist_max", 90)))


static func rad_resist(a: Actor) -> int:
	if has(a, "rad_resist_zero"):
		return clampi(int(eff(a, "rad_resist")), 0, int(d("resist_max", 90)))
	return clampi(int(d("rad_per_end", 2)) * stat_value(a, "end") + int(eff(a, "rad_resist")), 0, int(d("resist_max", 90)))


static func sequence(a: Actor) -> int:
	return int(d("sequence_per_per", 2)) * stat_value(a, "per") + int(eff(a, "sequence"))


static func healing_rate(a: Actor) -> int:
	return maxi(int(d("healing_min", 1)), int(floor(stat_value(a, "end") / maxf(d("healing_end_div", 3), 1.0)))) + int(eff(a, "healing_rate"))


static func crit_pct(a: Actor) -> int:
	return stat_value(a, "luck") + int(eff(a, "crit_pct"))


static func skill_points_per_level(a: Actor) -> int:
	return maxi(0, int(d("skill_points_base", 5)) + int(d("skill_points_per_int", 2)) * stat_value(a, "int") + int(eff(a, "skill_points")))


static func perk_rate(a: Actor) -> int:
	var r: int = int(eff(a, "perk_rate"))
	return r if r > 0 else int(sect("levels").get("perk_every", 3))


static func party_limit(a: Actor) -> int:
	return int(floor(stat_value(a, "cha") / maxf(float(sect("party").get("cha_div", 2)), 1.0))) + int(eff(a, "party"))


static func derived(a: Actor) -> Dictionary:
	return {"hp": hp_max(a), "hp_level": hp_per_level(a), "ap": ap(a), "ac": armor_class(a), "carry_kg": carry_kg(a),
		"melee": melee_damage(a), "poison": poison_resist(a), "rad": rad_resist(a), "sequence": sequence(a),
		"healing": healing_rate(a), "crit": crit_pct(a), "skill_points": skill_points_per_level(a), "party": party_limit(a)}


# =====================================================================
# НАВЫКИ
# =====================================================================
## Стартовое значение по формуле: база + множитель × сумма характеристик
static func skill_base(a: Actor, k: String) -> int:
	var s: Dictionary = skills().get(k, {})
	var sum: int = 0
	for st in s.get("stats", []):
		sum += stat_value(a, String(st))
	return int(s.get("base", 0)) + int(s.get("mult", 1)) * sum


static func is_tag(a: Actor, k: String) -> bool:
	return a.tags.has(canon(k))


static func skill_value(a: Actor, k: String) -> int:
	k = canon(k)
	if not skills().has(k):
		return 0
	var v: int = skill_base(a, k)
	if is_tag(a, k):
		v += int(data().get("tag_bonus", 20))
	var e: Dictionary = a.skills.get(k, {})
	v += int(e.get("pts", 0)) + int(e.get("bonus", 0))
	v += int(eff(a, "skill_" + k) + eff(a, "skills_all"))
	if COMBAT_SKILLS.has(k):
		v += int(eff(a, "skills_combat"))
	return clampi(v, 0, int(data().get("skill_max", 300)))


## Уровень 0–10 для старых правил (мастера, рецепты, лечение): навык % / 10
static func level_equiv(a: Actor, k: String) -> int:
	return clampi(int(floor(skill_value(a, k) / 10.0)), 0, 10)


## Мастеру-НПС или по старому сохранению: поставить навык на уровень (значение = уровень × 10 + 5)
static func set_level_equiv(a: Actor, k: String, lv: int) -> void:
	k = canon(k)
	if not skills().has(k):
		return
	var e: Dictionary = a.skills.get(k, {"pts": 0, "bonus": 0})
	e["bonus"] = 0
	a.skills[k] = e
	var want: int = clampi(lv, 0, 10) * 10 + (5 if lv > 0 else 0)
	e["bonus"] = maxi(0, want - skill_value(a, k))


## Цена следующего 1 % (лестница цены)
static func skill_cost(a: Actor, k: String) -> int:
	var v: int = skill_value(a, k)
	for t in data().get("cost_tiers", [[100, 1]]):
		if v < int(t[0]):
			return int(t[1])
	return 0


static func can_raise(a: Actor, k: String) -> bool:
	var c: int = skill_cost(a, k)
	return c > 0 and a.skill_points >= c and skill_value(a, k) < int(data().get("skill_max", 300))


## Потратить очки на +1 % (отмеченный — +2 %). false — не хватает очков или предел
static func raise(a: Actor, k: String) -> bool:
	k = canon(k)
	if not can_raise(a, k):
		return false
	a.skill_points -= skill_cost(a, k)
	var e: Dictionary = a.skills.get(k, {"pts": 0, "bonus": 0})
	e["pts"] = int(e.get("pts", 0)) + (2 if is_tag(a, k) else 1)
	e["spent"] = int(e.get("spent", 0)) + 1
	a.skills[k] = e
	return true


## Вернуть последний 1 % (в окне героя до закрытия): очки назад по цене предыдущей ступени
static func lower(a: Actor, k: String, floor_pts: int = 0) -> bool:
	k = canon(k)
	var e: Dictionary = a.skills.get(k, {})
	var step: int = 2 if is_tag(a, k) else 1
	if int(e.get("pts", 0)) - step < floor_pts or int(e.get("spent", 0)) <= 0:
		return false
	e["pts"] = int(e["pts"]) - step
	e["spent"] = int(e["spent"]) - 1
	a.skill_points += skill_cost(a, k)
	return true


## Урок или книга: +pct к навыку (бонус), не выше cap (значение навыка)
static func train(a: Actor, k: String, pct: int, cap: int = 1 << 20) -> int:
	k = canon(k)
	if not skills().has(k):
		return 0
	var before: int = skill_value(a, k)
	var add: int = mini(pct, maxi(0, cap - before))
	if add <= 0:
		return 0
	var e: Dictionary = a.skills.get(k, {"pts": 0, "bonus": 0})
	e["bonus"] = int(e.get("bonus", 0)) + add
	a.skills[k] = e
	return skill_value(a, k) - before


static func empty_skills() -> Dictionary:
	var out: Dictionary = {}
	for k in skill_list():
		out[k] = {"pts": 0, "bonus": 0}
	return out


# =====================================================================
# УРОВНИ И ОПЫТ
# =====================================================================
## Сколько опыта всего нужно для уровня n (n×(n−1)/2 × 1000)
static func xp_for_level(n: int) -> int:
	return n * (n - 1) / 2 * int(sect("levels").get("xp_step", 1000))


static func xp_to_next(a: Actor) -> int:
	return xp_for_level(a.level + 1)


## Опыт с учётом перка «Быстро учится» и множителей черт характера. Ответ — сколько уровней взято
static func gain_xp(a: Actor, amount: float) -> int:
	if a == null or amount <= 0.0:
		return 0
	a.xp += amount * (1.0 + eff(a, "xp_mult"))
	var n: int = 0
	var mx: int = int(sect("levels").get("max_level", 30))
	while a.level < mx and a.xp >= float(xp_for_level(a.level + 1)):
		level_up(a)
		n += 1
	return n


## Новый уровень: очки навыков, перк каждые perk_rate уровней (ОЗ растут сами — hp_max от уровня)
static func level_up(a: Actor) -> void:
	a.level += 1
	a.skill_points += skill_points_per_level(a)
	if a.level % perk_rate(a) == 0:
		a.perk_picks += 1
	a.leveled_up.emit(a.level)


# =====================================================================
# ПЕРКИ
# =====================================================================
## "" — можно взять; иначе причина
static func perk_blocker(a: Actor, id: String) -> String:
	var p: Dictionary = perk_def(id)
	if p.is_empty():
		return "нет такого перка"
	if int(a.perks.get(id, 0)) >= int(p.get("ranks", 1)):
		return "взят полностью"
	if a.level < int(p.get("level", 1)):
		return "нужен уровень %d" % int(p.get("level", 1))
	var r: Dictionary = p.get("req", {})
	for s in r:
		if stat_value(a, s) < int(r[s]):
			return "нужно: %s %d" % [stat_short(s), int(r[s])]
	var mx: Dictionary = p.get("max_stat", {})
	for s in mx:
		if stat_value(a, s) > int(mx[s]):
			return "%s должна быть не выше %d" % [stat_short(s), int(mx[s])]
	var sk: Dictionary = p.get("req_skill", {})
	for k in sk:
		if skill_value(a, k) < int(sk[k]):
			return "нужно: %s %d %%" % [skill_name(k), int(sk[k])]
	return ""


static func available_perks(a: Actor) -> Array:
	return perks().keys().filter(func(id): return perk_blocker(a, id) == "")


## Взять перк за одно из накопленных право выбора. "" — взят
static func take_perk(a: Actor, id: String) -> String:
	if a.perk_picks <= 0:
		return "перк пока не положен"
	var why: String = perk_blocker(a, id)
	if why != "":
		return why
	a.perk_picks -= 1
	a.perks[id] = int(a.perks.get(id, 0)) + 1
	var e: Dictionary = perk_def(id).get("effects", {})
	if e.has("levels"):
		# «Здесь и сейчас»: опыта ровно до следующего уровня
		a.xp = maxf(a.xp, float(xp_for_level(a.level + 1)))
		gain_xp(a, 0.001)
	if e.has("mutate"):
		a.mutate_left += 1
	if e.has("tags"):
		a.tag_left += int(e["tags"])
	return ""


## «Ещё один конёк»: отметить навык (+20 % сразу, дальше +2 % за очко)
static func add_tag(a: Actor, k: String) -> String:
	k = canon(k)
	if a.tag_left <= 0:
		return "отметка не положена"
	if not skills().has(k) or a.tags.has(k):
		return "этот навык уже отмечен" if a.tags.has(k) else "нет такого навыка"
	a.tags.append(k)
	a.tag_left -= 1
	return ""


static func perk_text(id: String) -> String:
	var p: Dictionary = perk_def(id)
	var req: Array = ["ур. %d" % int(p.get("level", 1))]
	for s in p.get("req", {}):
		req.append("%s %d" % [stat_short(s), int(p["req"][s])])
	for s in p.get("max_stat", {}):
		req.append("%s ≤ %d" % [stat_short(s), int(p["max_stat"][s])])
	for k in p.get("req_skill", {}):
		req.append("%s %d %%" % [skill_name(k), int(p["req_skill"][k])])
	var rk: String = " (рангов: %d)" % int(p.get("ranks", 1)) if int(p.get("ranks", 1)) > 1 else ""
	return "%s%s — %s Требует: %s." % [p.get("title", id), rk, p.get("text", ""), ", ".join(PackedStringArray(req))]


# =====================================================================
# ЧЕРТЫ FALLOUT (особенности)
# =====================================================================
static func traits_valid(list: Array) -> String:
	if list.size() > int(data().get("traits_max", 2)):
		return "не больше %d особенностей" % int(data().get("traits_max", 2))
	var seen: Dictionary = {}
	for t in list:
		if not traits().has(t):
			return "нет такой особенности"
		if seen.has(t):
			return "особенность повторяется"
		seen[t] = true
	return ""


static func trait_text(id: String) -> String:
	var t: Dictionary = traits().get(id, {})
	return "%s — %s" % [t.get("title", id), t.get("text", "")]


## «Мутация»: убрать черту или взять новую (один раз за перк)
static func mutate(a: Actor, remove_id: String, add_id: String) -> String:
	if a.mutate_left <= 0:
		return "мутации нет"
	var test: Array = a.quirks.duplicate()
	if remove_id != "":
		test.erase(remove_id)
	if add_id != "":
		test.append(add_id)
	var why: String = traits_valid(test)
	if why != "":
		return why
	a.quirks = test
	a.mutate_left -= 1
	return ""


# =====================================================================
# СОЗДАНИЕ: распределение характеристик (от 5, свободных 5, можно опускать до 1), 3 отмеченных навыка
# =====================================================================
static func alloc_left(alloc: Dictionary) -> int:
	var n: int = int(data().get("points", 5))
	for s in alloc:
		n -= int(alloc[s])
	return n


static func alloc_valid(alloc: Dictionary) -> String:
	for s in alloc:
		if not stats_list().has(s):
			return "нет такой характеристики"
		var v: int = int(data().get("base", 5)) + int(alloc[s])
		if v < int(data().get("min", 1)) or v > int(data().get("max", 10)):
			return "%s вне 1–10" % stat_name(s)
	var left: int = alloc_left(alloc)
	if left != 0:
		return "распределите очки (%d)" % left if left > 0 else "лишние очки (%d)" % -left
	return ""


static func tags_valid(list: Array, extra: int = 0) -> String:
	var need: int = int(data().get("tags", 3)) + extra
	var seen: Dictionary = {}
	for k in list:
		if not skills().has(k) or seen.has(k):
			return "неверный навык"
		seen[k] = true
	if list.size() != need:
		return "отметьте навыков: %d (сейчас %d)" % [need, list.size()]
	return ""


## Записать в Actor: база характеристик, отмеченные навыки, особенности. Уровень 1, очков навыков 0
static func apply_creation(a: Actor, alloc: Dictionary, tag_list: Array, trait_list: Array) -> void:
	for s in stats_list():
		a.stats[s] = clampi(int(data().get("base", 5)) + int(alloc.get(s, 0)), int(data().get("min", 1)), int(data().get("max", 10)))
	a.tags = tag_list.filter(func(k): return skills().has(k)).slice(0, int(data().get("tags", 3)))
	a.quirks = trait_list.duplicate() if traits_valid(trait_list) == "" else []
	a.level = 1
	a.xp = 0.0
	a.skill_points = 0
	a.perk_picks = 0
	a.perks = {}
	for k in skill_list():
		a.skills[k] = {"pts": 0, "bonus": int(a.skills.get(k, {}).get("bonus", 0))}


# =====================================================================
# ТОРГОВЛЯ, ПОРУЧЕНИЯ
# =====================================================================
## Бонус цены в пользу героя: разница навыков Торговли героя и торговца, перки «Купец», «Культ личности»
static func trade_bonus(hero: Actor, trader: Actor = null, buying: bool = true) -> float:
	var t: Dictionary = sect("trade")
	var tb: float = float(skill_value(trader, "barter")) if trader != null else float(t.get("trader_default", 40))
	var hb: float = float(skill_value(hero, "barter")) if hero != null else tb
	# «Привлекательность»: +2 ХАР в торговле = +8 % Торговли (4 × ХАР)
	if hero != null:
		hb += 4.0 * eff(hero, "talk_cha")
	var b: float = clampf((hb - tb) * float(t.get("per_point", 0.003)), float(t.get("min", -0.15)), float(t.get("max", 0.3)))
	if hero != null:
		b += eff(hero, "trade")
		if buying:
			b += eff(hero, "trade_buy") * 0.6
	return b


## Добавка к денежной награде за поручение: Красноречие и перки
static func quest_bonus(hero: Actor) -> float:
	if hero == null:
		return 0.0
	var s: Dictionary = sect("speech")
	var b: float = (skill_value(hero, "speech") - float(s.get("ref", 25))) * float(s.get("per_point", 0.004))
	return clampf(b, 0.0, float(s.get("max", 0.5))) + eff(hero, "quest_bonus")


# =====================================================================
# СТАРЫЕ СОХРАНЕНИЯ: 7 характеристик 09 (база 4, Мудрость) и навыки пака уровнями
# =====================================================================
static func is_legacy(d: Dictionary) -> bool:
	if d.has("sheet"):
		return false
	return d.get("stats", {}).has("wis") or not d.has("level")


## Перевод старого персонажа: характеристика − 4 + 5 (в пределах 1–10), Мудрость уходит, Удача 5 + старая;
## уровни старых навыков — как уровень навыка (значение ≈ уровень × 10 + 5), опыт навыков → опыт героя
static func migrate(a: Actor, d: Dictionary) -> void:
	var st: Dictionary = d.get("stats", {})
	for s in stats_list():
		if s == "luck":
			a.stats[s] = clampi(5 + int(st.get("luck", 0)), 1, 10)
		else:
			a.stats[s] = clampi(int(st.get(s, 4)) + 1, 1, 10)
	# В старом сохранении прибавки черт характера уже внутри stats — вычесть, их добавит special()
	for t in d.get("traits", []):
		var ts: Dictionary = char_traits().get(String(t), {}).get("stats", {})
		for s in ts:
			if a.stats.has(s):
				a.stats[s] = clampi(int(a.stats[s]) - int(ts[s]), 1, 10)
	a.skills = empty_skills()
	var xp: float = 0.0
	var best: Dictionary = {}
	for k in d.get("skills", {}):
		var e: Dictionary = d["skills"][k]
		xp += float(e.get("xp", 0.0))
		var nk: String = canon(String(k))
		best[nk] = maxi(int(best.get(nk, 0)), int(e.get("level", 0)))
	for k in best:
		if int(best[k]) > 0:
			set_level_equiv(a, k, int(best[k]))
	a.level = 1
	a.xp = 0.0
	gain_xp(a, xp * num("xp", "use_mult", 3.0))

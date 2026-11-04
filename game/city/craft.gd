extends RefCounted
## Крафт в мастерских (вопрос Q18, Huzzah 2026-10-24): кожевник и кузнец делают снаряжение из шкур и лома.
## Заказ — мастер делает из ваших материалов за плату, если сам умеет (его навык ≥ уровня рецепта).
## Своими руками — нужен свой навык, тратится выносливость, есть шанс неудачи, за работу идёт опыт навыка.
## Урок — +10 % к навыку (Ремесло) за деньги, но не выше навыка мастера. Опыт за работу идёт герою
## (уровни и очки навыков, characters/sheet.gd). Рецепты и числа — res://data/cities/recipes.json.

const Trade := preload("res://city/trade.gd")
const Sheet := preload("res://characters/sheet.gd")
const RECIPES_FILE := "res://data/cities/recipes.json"

static var _data: Dictionary = {}
static var _read: bool = false


static func data() -> Dictionary:
	if not _read:
		_read = true
		var f := FileAccess.open(RECIPES_FILE, FileAccess.READ)
		if f != null:
			var v: Variant = I18n.tree(JSON.parse_string(f.get_as_text()))
			if v is Dictionary:
				_data = v
		if _data.get("recipes", {}).is_empty():
			push_error("craft: не прочитан " + RECIPES_FILE)
	return _data


static func recipe(id: String) -> Dictionary:
	return data().get("recipes", {}).get(id, {})


## Навичка майстерні за роллю НПС ("" — у цієї ролі майстерні немає)
static func skill_of(role: String) -> String:
	return String(data().get("workshops", {}).get(role, {}).get("skill", ""))


static func workshop_name(role: String) -> String:
	return String(data().get("workshops", {}).get(role, {}).get("name", I18n.t("Мастерская")))


## Рецепти майстерні: id за рівнем, потім за назвою речі
static func recipes_for(role: String) -> Array:
	var all: Dictionary = data().get("recipes", {})
	var out: Array = all.keys().filter(func(id): return String(all[id].get("master", "")) == role)
	out.sort_custom(func(a, b):
		var la: int = int(all[a].get("level", 0))
		var lb: int = int(all[b].get("level", 0))
		return la < lb if la != lb else Trade.item_name(String(all[a]["out"])) < Trade.item_name(String(all[b]["out"])))
	return out


## Яких матеріалів бракує: ["Шкура 1/3", …]; порожньо — усе є
static func missing(bag: Dictionary, r: Dictionary) -> Array:
	var out: Array = []
	var need: Dictionary = r.get("in", {})
	for id in need:
		if Trade.count(bag, id) < int(need[id]):
			out.append("%s %d/%d" % [Trade.item_name(id), Trade.count(bag, id), int(need[id])])
	return out


## Матеріали рядком: «Шкура ×3, Мотузка»
static func inputs_text(r: Dictionary) -> String:
	var parts: PackedStringArray = []
	var need: Dictionary = r.get("in", {})
	for id in need:
		parts.append(Trade.item_name(id) if int(need[id]) == 1 else "%s ×%d" % [Trade.item_name(id), int(need[id])])
	return ", ".join(parts)


static func _take(bag: Dictionary, r: Dictionary, share: float) -> void:
	var need: Dictionary = r.get("in", {})
	for id in need:
		Trade.add(bag, id, -int(ceil(float(need[id]) * share)))


## Замовлення в майстра. Відповідь: текст помилки, "" — річ у сумці
static func order(bag: Dictionary, r: Dictionary, master: Actor) -> String:
	if r.is_empty():
		return I18n.t("Нет такого рецепта")
	var sk: String = skill_of(String(r["master"]))
	if master != null and master.skill_level(sk) < int(r.get("level", 0)):
		return I18n.t("Мастер такого не умеет")
	if not missing(bag, r).is_empty():
		return I18n.t("Не хватает материалов")
	var fee: int = int(r.get("fee", 0))
	if int(bag["money"]) < fee:
		return I18n.t("Не хватает денег")
	bag["money"] = int(bag["money"]) - fee
	_take(bag, r, 1.0)
	Trade.add(bag, String(r["out"]))
	return ""


## Шанс зробити самому; 0 — навички бракує
static func chance(r: Dictionary, hero: Actor) -> float:
	var lv: int = hero.skill_level(skill_of(String(r.get("master", "")))) if hero != null else 0
	var need: int = int(r.get("level", 0))
	if lv < need:
		return 0.0
	var s: Dictionary = data().get("self", {})
	return minf(float(s.get("base", 0.7)) + float(s.get("per_level", 0.1)) * (lv - need), float(s.get("max", 0.95)))


## Чому не можна зробити самому ("" — можна спробувати)
static func self_blocker(bag: Dictionary, r: Dictionary, hero: Actor) -> String:
	if r.is_empty() or hero == null:
		return I18n.t("Нет такого рецепта")
	if chance(r, hero) <= 0.0:
		return I18n.t("Нужен навык %d") % int(r.get("level", 0))
	if not missing(bag, r).is_empty():
		return I18n.t("Не хватает материалов")
	if hero.res["stamina"] < float(r.get("work", 0)):
		return I18n.t("Слишком устали: нужно %d выносливости") % int(r.get("work", 0))
	return ""


## Зробити самому. Відповідь: {"ok": bool, "text": String}; у разі невдачі пропадає частина матеріалів
static func make(bag: Dictionary, r: Dictionary, hero: Actor, rng: RandomNumberGenerator) -> Dictionary:
	var err: String = self_blocker(bag, r, hero)
	if err != "":
		return {"ok": false, "text": err}
	var sk: String = skill_of(String(r["master"]))
	var s: Dictionary = data().get("self", {})
	hero.add_res("stamina", -float(r.get("work", 0)))
	var name: String = Trade.item_name(String(r["out"]))
	if rng.randf() < chance(r, hero):
		_take(bag, r, 1.0)
		Trade.add(bag, String(r["out"]))
		hero.add_xp(sk, float(r.get("xp", 0)))
		return {"ok": true, "text": I18n.t("Готово: %s") % name}
	_take(bag, r, float(s.get("fail_loss", 0.5)))
	hero.add_xp(sk, float(r.get("xp", 0)) * float(s.get("fail_xp", 0.5)))
	return {"ok": false, "text": I18n.t("Не вышло (%s): работа испорчена, часть материалов пропала") % name}


static func lesson_fee(hero: Actor, sk: String) -> int:
	var l: Dictionary = data().get("lesson", {})
	return int(l.get("fee", 10)) + int(l.get("fee_per_level", 5)) * hero.skill_level(sk)


## Урок у майстра: досвід за гроші, поки герой нижче за майстра. Відповідь: текст помилки, "" — урок пройдено
static func lesson(bag: Dictionary, hero: Actor, master: Actor, sk: String) -> String:
	if sk == "" or hero == null or master == null:
		return I18n.t("Здесь не учат")
	if hero.skill(sk) >= master.skill(sk):
		return I18n.t("Мастеру больше нечему вас учить")
	var fee: int = lesson_fee(hero, sk)
	if int(bag["money"]) < fee:
		return I18n.t("Не хватает денег")
	bag["money"] = int(bag["money"]) - fee
	# Выше мастера урок не поднимает; дар «Вдумчивость» — урок на 50 % больше
	var pct: int = int(round(float(data().get("lesson", {}).get("pct", 10)) * (1.0 + Sheet.eff(hero, "lesson_mult"))))
	Sheet.train(hero, sk, pct, master.skill(sk))
	hero.add_xp(sk, float(data().get("lesson", {}).get("xp", 40)) * 0.25)
	return ""

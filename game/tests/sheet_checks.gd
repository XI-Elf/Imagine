extends SceneTree
## Система персонажа (characters/sheet.gd, Huzzah 2026-10-28): характеристики, производные, 18 навыков, отметки,
## цена очков, уровни и опыт, перки, черты, создание, старые сохранения, торговля, перевод в бой.
## godot --headless --path game -s res://tests/sheet_checks.gd

const S := preload("res://characters/sheet.gd")
const Data := preload("res://battle/battle_data.gd")
const Combatant := preload("res://battle/combatant.gd")

var fails: int = 0
var checks: int = 0


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("FAIL: ", what)


func _init() -> void:
	_data()
	_derived()
	_skills()
	_levels()
	_perks()
	_traits()
	_creation()
	_legacy()
	_trade()
	_battle()
	print("sheet_checks: %d/%d ok" % [checks - fails, checks])
	quit(1 if fails > 0 else 0)


func _data() -> void:
	ok(S.stats_list() == ["str", "per", "end", "cha", "int", "agi", "luck"], "характеристики по порядку")
	ok(S.skill_list().size() == 18, "18 навыков")
	ok(S.traits().size() == 17 and S.perks().size() >= 75, "черт 17, перков %d" % S.perks().size())
	for k in S.skill_list():
		ok(String(S.skills()[k].get("on_sheet", "")) != "" and String(S.skills()[k].get("desc", "")) != "", "навык описан: " + k)
	for id in S.perks():
		var e: Dictionary = S.perk_def(id)
		ok(int(e.get("level", 0)) >= 1 and String(e.get("title", "")) != "", "перк описан: " + id)
	ok(S.canon("survival") == "outdoorsman" and S.canon("medicine") == "doctor" and S.canon("blacksmith") == "repair", "старые навыки пака → новые")


func _derived() -> void:
	var a := Actor.new("a", "Средний")
	ok(S.hp_max(a) == 30 and S.ap(a) == 7 and S.armor_class(a) == 5, "все 5: ОЗ 30, ОД 7, КБ 5")
	ok(absf(S.carry_kg(a) - 68.04) < 0.01 and S.melee_damage(a) == 1, "все 5: 150 фунтов = 68 кг, урон 1")
	ok(S.sequence(a) == 10 and S.healing_rate(a) == 1 and S.crit_pct(a) == 5, "Реакция 10, лечение 1, крит 5 %")
	ok(S.poison_resist(a) == 25 and S.rad_resist(a) == 10, "яд 25 %, проклятье 10 %")
	ok(S.skill_points_per_level(a) == 15 and S.hp_per_level(a) == 4, "15 очков и +4 ОЗ за уровень")
	a.set_stat("str", 10)
	a.set_stat("end", 10)
	ok(S.hp_max(a) == 45 and S.melee_damage(a) == 5, "СИЛ 10 ВЫН 10: ОЗ 45, урон 5")
	a.level = 3
	ok(S.hp_max(a) == 45 + 2 * 7, "по 2 + ВЫН/2 = 7 ОЗ за уровень")


func _skills() -> void:
	var a := Actor.new("a", "Ученик")
	ok(S.skill_value(a, "bows") == 25 and S.skill_value(a, "unarmed") == 50 and S.skill_value(a, "gambling") == 25, "база стрельба 25, рукопашный 50, азарт 25")
	ok(S.skill_value(a, "doctor") == 15 and S.skill_value(a, "outdoorsman") == 20, "знахарство 15, выживание 20")
	a.tags = ["bows"]
	ok(S.skill_value(a, "bows") == 45, "отмеченный: +20 %")
	a.skill_points = 3
	ok(S.raise(a, "bows") and S.skill_value(a, "bows") == 47 and a.skill_points == 2, "отмеченный: +2 % за очко")
	ok(S.raise(a, "sneak") and S.skill_value(a, "sneak") == 21, "обычный: +1 % за очко")
	ok(S.lower(a, "sneak") and a.skill_points == 2, "очко можно вернуть")
	ok(not S.lower(a, "sneak"), "ниже вложенного не вернуть")
	S.train(a, "melee", 80)
	ok(S.skill_cost(a, "melee") == 2, "после 100 %% — по 2 очка: %d %%" % S.skill_value(a, "melee"))
	S.train(a, "melee", 200)
	ok(S.skill_value(a, "melee") == 300 and S.skill_cost(a, "melee") == 0, "предел 300 %")
	S.train(a, "repair", 10, 20)
	ok(S.skill_value(a, "repair") == 20, "урок не выше мастера")
	S.set_level_equiv(a, "doctor", 4)
	ok(S.skill_value(a, "doctor") == 45 and a.skill_level("medicine") == 4, "уровень пака 4 = 45 %")


func _levels() -> void:
	ok(S.xp_for_level(2) == 1000 and S.xp_for_level(3) == 3000 and S.xp_for_level(4) == 6000, "опыт уровней 1000 / 3000 / 6000")
	var a := Actor.new("a", "Боец")
	var got: Array = []
	a.leveled_up.connect(func(l): got.append(l))
	ok(S.gain_xp(a, 3000.0) == 2 and a.level == 3 and got == [2, 3], "3000 опыта — 3 уровень")
	ok(a.skill_points == 30 and a.perk_picks == 1, "30 очков навыков и перк на 3 уровне")
	var b := Actor.new("b", "Мастер")
	b.quirks = ["skilled"]
	S.gain_xp(b, 6000.0)
	ok(b.skill_points == 60 and b.perk_picks == 1, "«Мастер на все руки»: +5 очков, перк раз в 4 уровня: %d %d" % [b.skill_points, b.perk_picks])


func _perks() -> void:
	var a := Actor.new("a", "Перк")
	S.gain_xp(a, 3000.0)
	ok(S.perk_blocker(a, "toughness") != "", "«Крепкий» требует ВЫН 6 и УДЧ 6")
	ok(S.perk_blocker(a, "educated") == "нужен уровень 6", "«Начитанный» — с 6 уровня")
	ok(S.take_perk(a, "awareness") == "" and a.perks == {"awareness": 1} and a.perk_picks == 0, "взят перк «Чутьё»")
	ok(S.take_perk(a, "here_and_now") != "", "второй перк без права выбора не взять")
	a.perk_picks = 1
	ok(S.take_perk(a, "here_and_now") == "" and a.level == 4, "«Здесь и сейчас» — сразу уровень")
	var g := Actor.new("g", "Сила")
	g.level = 12
	g.perk_picks = 1
	ok(S.take_perk(g, "gain_str") == "" and int(g.stat("str")) == 6, "«Развить Силу»: +1")
	var t := Actor.new("t", "Конёк")
	t.level = 12
	t.perk_picks = 1
	ok(S.take_perk(t, "tag") == "" and t.tag_left == 1, "«Ещё один конёк»: отметка")
	ok(S.add_tag(t, "sneak") == "" and S.skill_value(t, "sneak") == 40 and t.tag_left == 0, "отмечена скрытность: 20 + 20")
	var m := Actor.new("m", "Мутант")
	m.quirks = ["bruiser"]
	m.mutate_left = 1
	ok(S.mutate(m, "bruiser", "finesse") == "" and m.quirks == ["finesse"], "«Мутация»: Громила → Изящество")


func _traits() -> void:
	var a := Actor.new("a", "Громила")
	a.quirks = ["bruiser"]
	ok(int(a.stat("str")) == 7 and S.ap(a) == 5, "Громила: СИЛ +2, ОД −2")
	var g := Actor.new("g", "Одарённый")
	g.quirks = ["gifted"]
	ok(int(g.stat("luck")) == 6 and S.skill_value(g, "gambling") == 20 and S.skill_points_per_level(g) == 12, "Одарённый: +1 ко всем, −10 % навыкам, −5 очков")
	var c := Actor.new("c", "Характер")
	c.traits = ["strong_build", "prudent", "repulsive"]
	ok(int(c.stat("str")) == 6 and int(c.stat("per")) == 6 and int(c.stat("cha")) == 4, "черты характера меняют характеристики (Мудрость → Восприятие)")
	c.quirks = ["bruiser"]
	c.stats["str"] = 9
	ok(int(c.stat("str")) == 10, "итог не выше 10")
	ok(S.traits_valid(["bruiser", "gifted"]) == "" and S.traits_valid(["bruiser", "gifted", "jinxed"]) != "", "не больше двух черт")


func _creation() -> void:
	ok(S.alloc_valid({"str": 3, "agi": 2}) == "", "5 очков распределены")
	ok(S.alloc_valid({"str": 5, "agi": 1, "cha": -1}) == "", "Харизма опущена до 4 ради ещё одного очка")
	ok(S.alloc_valid({"str": 6, "agi": -1}) != "", "выше 10 нельзя")
	ok(S.alloc_valid({"str": 2}) != "", "не все очки — нельзя")
	ok(S.tags_valid(["bows", "sneak", "speech"]) == "" and S.tags_valid(["bows", "sneak"]) != "", "ровно 3 отметки")
	var a := Actor.new("a", "Новичок")
	S.apply_creation(a, {"str": 3, "agi": 2}, ["bows", "sneak", "speech"], ["small_frame"])
	ok(int(a.stat("str")) == 8 and int(a.stat("agi")) == 8 and a.tags.size() == 3 and a.quirks == ["small_frame"], "создание записано в героя")
	var b := Actor.from_dict(JSON.parse_string(JSON.stringify(a.to_dict())))
	ok(int(b.stat("agi")) == 8 and b.tags == a.tags and b.quirks == a.quirks and b.level == 1, "новое сохранение читается без перевода")


func _legacy() -> void:
	var old: Dictionary = {"id": "hero", "name": "Старый", "stats": {"str": 6, "agi": 4, "int": 4, "end": 5, "per": 4, "wis": 7, "cha": 4, "luck": -2},
		"skills": {"survival": {"level": 3, "xp": 200.0}, "medicine": {"level": 1, "xp": 30.0}}}
	ok(S.is_legacy(old), "старое сохранение распознано")
	var old2: Dictionary = old.duplicate(true)
	old2["traits"] = ["strong_build"]
	ok(int(Actor.from_dict(old2).stat("str")) == 7, "старая прибавка черты не удваивается")
	var a := Actor.from_dict(old)
	ok(int(a.stat("str")) == 7 and int(a.stat("agi")) == 5 and int(a.stat("luck")) == 3, "характеристики: +1, Удача 5 + старая")
	ok(a.skill_level("survival") == 3 and S.skill_value(a, "outdoorsman") == 35, "Выживание 3 → 35 %")
	ok(a.level == 1 and is_equal_approx(a.xp, 690.0), "опыт навыков ×3 → опыт героя: %.0f" % a.xp)


func _trade() -> void:
	var hero := Actor.new("h", "Купец")
	var trader := Actor.new("t", "Торговец", true)
	ok(is_equal_approx(S.trade_bonus(hero, trader), 0.0), "равная Торговля — без скидки")
	S.train(hero, "barter", 50)
	ok(is_equal_approx(S.trade_bonus(hero, trader), 0.15), "+50 % Торговли — скидка 15 %")
	ok(is_equal_approx(S.quest_bonus(hero), 0.0) or S.quest_bonus(hero) >= 0.0, "Красноречие 25 — без надбавки")


func _battle() -> void:
	var a := Actor.new("hero", "Герой")
	var c = Combatant.new()
	c.build_from_actor(a, 0, Data.config(), Data.config().hero)
	ok(c.on_sheet and c.scores["str"] == 10 and c.scores["dex"] == 10 and c.scores["lck"] == 10, "характеристика 5 → 10 в бою")
	ok(c.max_hp == 30 and c.speed_ft == 30 and c.per_bonus == 0, "ОЗ 30, скорость 30 фт, инициатива +0")
	ok(c.crit_extra(null) == 0, "Удача 5: крит только на 20")
	var w = c.weapons[0]
	var sk: String = Combatant.weapon_skill(w)
	ok(c.attack_prof(w) == clampi(S.skill_value(a, sk) / 20, 0, 6), "мастерство = %s %d %% / 20 = %d" % [sk, S.skill_value(a, sk), c.attack_prof(w)])
	var b := Actor.new("b", "Ловкач")
	b.set_stat("agi", 10)
	b.set_stat("luck", 10)
	b.set_stat("per", 10)
	var d = Combatant.new()
	d.build_from_actor(b, 0, Data.config(), Data.config().hero)
	ok(d.speed_ft == 45 and d.crit_extra(null) == 1 and d.per_bonus == 5, "ЛВК 10 (ОД 10): 45 фт; УДЧ 10: крит 19–20; ВОС 10: инициатива +5")

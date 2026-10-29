extends SceneTree
## Перевірки спільних правил персонажа (characters/actor.gd).
## Запуск: godot --headless --path game -s res://tests/actor_checks.gd

const R := preload("res://characters/actor_rules.gd")
const WorldEnv := preload("res://characters/world_env.gd")

var fails: int = 0
var checks: int = 0


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("FAIL: ", what)


# Выживание стартует с 2×(СТО+УМ) = 20 % — уже «2 уровень» пака. Для эталонных
# скоростей пака — путник с Выживанием 4 % (уровень 0)
func plain(id: String, name: String) -> Actor:
	var a := Actor.new(id, name)
	a.set_stat("end", 1)
	a.set_stat("int", 1)
	return a


func env(biome: int, temp: float = 15.0) -> Dictionary:
	return {"biome": biome, "water": 1.0 if biome == 1 else 0.0, "temp_c": temp, "rain": 0.0, "night": false}


func _init() -> void:
	_data()
	_needs()
	_terrain_speed()
	_swimming()
	_radiation()
	_conditions_and_treatment()
	_skills()
	_stats()
	_same_rules_for_npc()
	_save_load()
	_world_env()
	print("actor_checks: %d/%d ok" % [checks - fails, checks])
	quit(1 if fails > 0 else 0)


func _data() -> void:
	ok(R.characteristics().size() == 6, "6 ресурсов пака")
	ok(R.traumas().size() == 8 and R.diseases().size() == 10 and R.buffs().size() == 5, "состояния пака")
	ok(R.skills().size() == 18, "18 навыков")
	ok(R.pack_skills().size() == 7, "7 навыков пака остались для таблиц опыта")
	for id in R.traumas().keys() + R.diseases().keys():
		ok(R.section("treatments").has(id), "лечение описано: " + id)
	for b in range(10):
		ok(not R.terrain(b).is_empty(), "местность для биома %d" % b)


func _needs() -> void:
	var a := Actor.new("p", "Тест")
	a.tick(3600.0 * 10.0, env(4))
	ok(is_equal_approx(a.res["hunger"], 80.0 - 12.0), "голод 1,2 в час (пак)")
	ok(is_equal_approx(a.res["thirst"], 80.0 - 15.0), "жажда 1,5 в час (пак)")
	ok(is_equal_approx(a.res["energy"], 100.0 - 8.0), "энергия 0,8 в час (пак)")
	# Спека: спрага швидша
	var h := Actor.new("h", "Жара")
	h.tick(3600.0, env(4, 40.0))
	ok(h.res["thirst"] < 80.0 - 1.5 - 0.5, "в жару жажда быстрее")
	# Без води помирає від спраги
	var d := Actor.new("d", "Сухой")
	d.res["thirst"] = 0.0
	d.res["hunger"] = 100.0
	d.tick(3600.0 * 48.0, env(4))
	ok(not d.alive and d.death_cause == "thirst", "смерть от жажды: " + d.death_cause)
	# Сон відновлює енергію й дає «Відпочилий»
	var s := Actor.new("s", "Сон")
	s.res["energy"] = 20.0
	s.set_sleep(true)
	s.tick(3600.0 * 8.0, env(3))
	s.set_sleep(false)
	ok(s.res["energy"] > 99.0 and s.has_buff("rested"), "сон 8 ч: энергия и отдых")


func _terrain_speed() -> void:
	var a := plain("p", "Ходок")
	var waste: float = a.travel_speed(env(4))
	ok(is_equal_approx(a.calculate_speed(env(4)), 3.0), "пешком 3 км/ч (пак)")
	ok(is_equal_approx(waste, 3.0 / 3.6 * 8.0 * GameClock.GAME_SPEED), "пустошь: 3 км/ч × 8 × скорость игры = %.2f м/с доски" % waste)
	ok(a.travel_speed(env(5)) < a.travel_speed(env(3)) and a.travel_speed(env(3)) < waste, "болото < лес < пустошь")
	ok(a.travel_speed(env(4), true) > waste * 2.0, "бег быстрее вдвое")
	ok(a.travel_speed(env(0)) == 0.0, "за край мира не пройти")
	a.add_condition("broken_leg")
	ok(is_equal_approx(a.travel_speed(env(4)), waste * 0.6), "перелом ноги −40 %")
	ok(not a.can_run(), "со сломанной ногой не бежит")
	var n := plain("n", "Ночь")
	var e := env(4)
	e["night"] = true
	ok(is_equal_approx(n.calculate_speed(e), 3.0 * 0.8), "ночью −20 %")
	n.set_skill_level("survival", 10)
	ok(n.calculate_speed(e) / n.calculate_speed(env(4)) > 0.99, "Выживание 10 снимает ночной штраф")
	var wr := env(4)
	wr["weather"] = "storm"
	ok(is_equal_approx(plain("w", "w").calculate_speed(wr), 1.5), "буря −50 %")
	var rider := plain("r", "Всадник")
	rider.mount = "horse"
	ok(is_equal_approx(rider.calculate_speed(env(4)), 8.0), "лошадь 8 км/ч")
	ok(not rider.can_run(), "верхом не бегают")
	rider.mount = "cart"
	ok(is_equal_approx(rider.calculate_speed(env(4)), 5.0), "повозка 5 км/ч")
	rider.mount = "horse"
	rider.set_skill_level("riding", 5)
	ok(rider.calculate_speed(env(4)) > 8.0, "Верховая езда ускоряет")
	var rs := Actor.new("rs", "Выспался")
	rs.add_buff("rested")
	ok(rs.calculate_speed(env(4)) > 3.0, "выспавшийся быстрее")
	ok(Actor.new("rz", "Зона").calculate_speed(env(8)) < Actor.new("cz", "Чисто").calculate_speed(env(4)), "радиоактивная зона замедляет")


func _swimming() -> void:
	var a := plain("p", "Пловец")
	ok(a.is_swimming(env(1)), "вода = плавание")
	ok(is_equal_approx(a.travel_speed(env(1)), 0.6 * 8.0 * GameClock.GAME_SPEED), "плавание 0,6 м/с × 8 × скорость игры")
	var drowned := false
	for i in 1000:
		a.exert(1.0, env(1), "walk")
		if not a.alive:
			drowned = true
			break
	ok(drowned and a.death_cause == "drowning", "без сил в воде тонет")
	var b := Actor.new("b", "Берег")
	b.res["stamina"] = 10.0
	b.exert(5.0, env(2), "rest")
	ok(b.res["stamina"] > 10.0, "на суше отдыхает")


func _radiation() -> void:
	var a := Actor.new("p", "Сталкер")
	a.tick(3600.0 * 20.0, env(8))
	ok(a.res["radiation"] > 100.0 and a.has_condition("radiation_sickness"), "20 ч в радиоактивной пустоши → лучевая болезнь")
	var stage1: int = a.conditions[a._cond_index("radiation_sickness")]["stage"]
	a.tick(3600.0 * 30.0, env(8))
	ok(a.conditions[a._cond_index("radiation_sickness")]["stage"] > stage1, "стадия растёт с дозой")
	var c := Actor.new("c", "Чистый")
	c.res["radiation"] = 50.0
	c.tick(3600.0 * 10.0, env(3))
	ok(is_equal_approx(c.res["radiation"], 49.0), "в чистом лесу радиация уходит 0,1 в час")
	c.add_buff("anti_radiation")
	c.tick(3600.0, env(3))
	ok(c.res["radiation"] < 44.0, "антирад ускоряет вывод")
	var tough := Actor.new("t", "Крепкий")
	tough.set_stat("end", 40)
	tough.tick(3600.0 * 10.0, env(8))
	var weak := Actor.new("w", "Слабый")
	weak.tick(3600.0 * 10.0, env(8))
	ok(tough.res["radiation"] < weak.res["radiation"], "Стойкость снижает дозу")


func _conditions_and_treatment() -> void:
	var a := Actor.new("p", "Раненый")
	a.add_condition("laceration")
	ok(a.is_bleeding(), "рваная рана кровоточит")
	var hp: float = a.res["health"]
	a.tick(3600.0, env(4))
	ok(a.res["health"] < hp - 5.0, "рана отнимает ~6 здоровья в час")
	var healer := Actor.new("h", "Лекарь", true)
	var r: Dictionary = a.treat("laceration", healer, [])
	ok(not r["ok"] and r["reason"].begins_with("нужно"), "без бинта не лечится")
	healer.set_skill_level("medicine", 10)
	r = a.treat("laceration", healer, ["bandage"])
	ok(r["chance"] > 0.9, "лекарь 10 уровня почти наверняка: %.2f" % r["chance"])
	var tries := 0
	while a.has_condition("laceration") and tries < 20:
		a.treat("laceration", healer, ["bandage"])
		tries += 1
	ok(not a.has_condition("laceration"), "рана вылечена")
	ok(healer.xp > 0.0, "лечение даёт опыт персонажу")
	# Срочные состояния проходят сами
	var t := Actor.new("t", "Отравленный")
	t.add_condition("intoxication")
	t.tick(3600.0 * 25.0, env(4))
	ok(not t.has_condition("intoxication"), "интоксикация проходит за сутки")
	# Брудна вода
	var got := 0
	for i in 200:
		var w := Actor.new("w%d" % i, "Пьёт")
		w.drink(20.0, "dirty")
		if w.has_condition("dysentery"):
			got += 1
	ok(got > 20 and got < 90, "грязная вода: дизентерия примерно у 25 %% (%d из 200)" % got)
	# Ситна їжа
	var f := Actor.new("f", "Едок")
	f.res["hunger"] = 10.0
	f.eat(10.0, "warm")
	ok(f.res["hunger"] >= 50.0 and f.has_buff("warm_meal"), "сытная еда: +30 и эффект")
	ok(f.travel_speed(env(4)) > Actor.new("x", "x").travel_speed(env(4)), "сытная еда ускоряет на 10 %")
	# Знеболювальне знімає витрату енергії від болю
	var p1 := Actor.new("p1", "Ожог")
	p1.add_condition("burn")
	var p2 := Actor.new("p2", "Ожог")
	p2.add_condition("burn")
	p2.add_buff("painkiller")
	p1.tick(3600.0, env(4))
	p2.tick(3600.0, env(4))
	ok(p2.res["energy"] > p1.res["energy"], "обезболивающее")


func _skills() -> void:
	# опыт за дело идёт персонажу (×3), уровень n при n(n−1)/2 × 1000
	var a := Actor.new("p", "Ученик")
	var levels: Array = []
	a.leveled_up.connect(func(l): levels.append(l))
	a.add_xp("survival", 400.0)
	ok(a.level == 2 and levels == [2] and a.skill_points == 15, "1200 опыта → 2 уровень, 15 очков навыков (УМ 5): %d %s %d" % [a.level, levels, a.skill_points])
	a.add_xp("survival", 10000000.0)
	ok(a.level == 30, "предел 30 уровня")
	ok(a.skill_level("riding") == a.skill_level("outdoorsman"), "Верховая езда пака = Выживание")
	var smart := Actor.new("s", "Умник")
	smart.set_stat("int", 10)
	ok(smart.derived()["skill_points"] == 25, "Ум 10 — 25 очков навыков за уровень")
	var walker := Actor.new("w", "Путник")
	var kms: Array = []
	walker.km_passed.connect(func(k): kms.append(k))
	walker.note_travel(30000.0, env(4))
	ok(kms.size() == 30 and kms[-1] == 30, "событие каждого километра: %d" % kms.size())
	ok(walker.xp > 0.0, "путь даёт опыт")


func _stats() -> void:
	var a := plain("p", "Обычный")
	var s := Actor.new("s", "Силач")
	s.set_stat("str", 10)
	ok(s.carry_capacity() > a.carry_capacity() + 20.0, "Сила: больше вес")
	ok(s.derived()["attack_power"] > a.derived()["attack_power"], "Сила: сильнее удар")
	var f := Actor.new("f", "Ловкач")
	f.set_stat("agi", 10)
	ok(f.travel_speed(env(4)) > a.travel_speed(env(4)), "Ловкость: быстрее")
	ok(absf(a.carry_capacity() - 150.0 * 0.4536) < 0.01, "25 + 25×СИЛ фунтов = 68 кг: %.2f" % a.carry_capacity())
	a.carried_kg = a.carry_capacity() * 1.5
	ok(is_equal_approx(a.calculate_speed(env(4)), 3.0 * 0.5), "перегруз 50 %% → скорость ×0,5: %.2f" % a.calculate_speed(env(4)))
	a.carried_kg = a.carry_capacity() * 2.0
	ok(a.calculate_speed(env(4)) == 0.0, "двойной вес — стоит")
	var npc := Actor.new("n", "НПС", true)
	npc.set_stat("luck", 50)
	ok(npc.stat("luck") == 10.0, "Удача у НПС есть, предел 10")
	var d: Dictionary = Actor.new("d", "d").derived()
	ok(d.has("attack_power") and d.has("carry_weight") and int(d["hp"]) == 30 and int(d["ap"]) == 7, "производные пака и %s" % d)


func _same_rules_for_npc() -> void:
	var p := Actor.new("p", "Игрок", false, 7)
	var n := Actor.new("n", "НПС", true, 7)
	p.tick(3600.0 * 30.0, env(5))
	n.tick(3600.0 * 30.0, env(5))
	ok(is_equal_approx(p.res["hunger"], n.res["hunger"]) and is_equal_approx(p.res["energy"], n.res["energy"]), "игрок и НПС живут по одним правилам")
	ok(p.travel_speed(env(6)) == n.travel_speed(env(6)), "одинаковая скорость в горах")


func _save_load() -> void:
	var a := Actor.new("p", "Сейв")
	a.set_stat("str", 8)
	a.add_condition("broken_arm")
	a.add_buff("healing_salve")
	a.add_xp("medicine", 60.0)
	a.tick(3600.0 * 3.0, env(7))
	var b := Actor.from_dict(JSON.parse_string(JSON.stringify(a.to_dict())))
	ok(b.stat("str") == 8.0 and b.has_condition("broken_arm") and b.has_buff("healing_salve"), "сохранение: статы и состояния")
	ok(is_equal_approx(b.res["radiation"], a.res["radiation"]) and b.skill_level("medicine") == a.skill_level("medicine"), "сохранение: ресурсы и навыки")
	a.tick(3600.0, env(4))
	b.tick(3600.0, env(4))
	ok(is_equal_approx(a.res["hunger"], b.res["hunger"]), "после загрузки идёт так же")


func _world_env() -> void:
	var summer_noon: float = WorldEnv.air_temp(4, 15.0, 200.0)
	var winter_night: float = WorldEnv.air_temp(4, 3.0, 17.0)
	ok(summer_noon > 25.0 and winter_night < 0.0, "лето днём %.1f, зима ночью %.1f" % [summer_noon, winter_night])
	ok(WorldEnv.air_temp(6, 15.0, 200.0) < summer_noon, "в горах холоднее")

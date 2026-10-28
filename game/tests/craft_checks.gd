extends SceneTree
## Крафт у кожевника и кузнеца (city/craft.gd, вопрос Q18, Huzzah 2026-10-24): рецепты, заказ у мастера,
## своими руками с навыком (шанс, опыт, выносливость, порча), уроки, шкуры со зверей в бою, окно мастерской в городе.
## godot --headless --path game -s res://tests/craft_checks.gd

const Trade := preload("res://city/trade.gd")
const Craft := preload("res://city/craft.gd")
const Data := preload("res://battle/battle_data.gd")
const Core := preload("res://battle/battle_core.gd")
const Enc := preload("res://battle/encounters.gd")
const R := preload("res://characters/actor_rules.gd")

var fails: int = 0
var checks: int = 0


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("FAIL: ", what)
	else:
		print("ok: ", what)


func frames(n: int) -> void:
	for i in n:
		await process_frame


func _initialize() -> void:
	_run()


func _run() -> void:
	_data()
	_order()
	_self()
	_lessons()
	_battle_hides()
	await _city()
	print("craft_checks: %d/%d" % [checks - fails, checks])
	quit(1 if fails > 0 else 0)


func _data() -> void:
	var recipes: Dictionary = Craft.data().get("recipes", {})
	ok(recipes.size() >= 10, "рецептов прочитано: %d" % recipes.size())
	var bad: Array = []
	for id in recipes:
		var r: Dictionary = recipes[id]
		if Trade.item(String(r.get("out", ""))).is_empty():
			bad.append("%s: нет вещи %s" % [id, r.get("out")])
		for m in r.get("in", {}):
			if Trade.item(m).is_empty():
				bad.append("%s: нет материала %s" % [id, m])
		if Craft.skill_of(String(r.get("master", ""))) == "":
			bad.append("%s: нет мастерской %s" % [id, r.get("master")])
	ok(bad.is_empty(), "рецепты ссылаются на настоящие вещи и мастерские: %s" % str(bad))
	ok(R.skills().has(Craft.skill_of("tanner")) and R.skills().has(Craft.skill_of("smith")), "навыки мастерских есть в паке: кожевник — %s, кузнец — %s" % [Craft.skill_of("tanner"), Craft.skill_of("smith")])
	ok(Craft.skill_of("trader") == "", "у торговки мастерской нет")
	var lv: Array = Craft.recipes_for("smith").map(func(id): return int(Craft.recipe(id)["level"]))
	var sorted: bool = true
	for i in range(1, lv.size()):
		sorted = sorted and lv[i] >= lv[i - 1]
	ok(sorted and lv.size() >= 6, "рецепты кузни по уровню: %s" % str(lv))
	# Что выковано — годится в бой: оружие известно бою, доспех есть среди доспехов
	var cfg: Resource = Data.config()
	var unusable: Array = []
	for id in recipes:
		var out: String = String(recipes[id]["out"])
		var it: Dictionary = Trade.item(out)
		var arm: String = String(it.get("wear", {}).get("armor", ""))
		if arm != "" and Data.armor(arm) == null:
			unusable.append(out)
		if not it.has("wear") and not cfg.item_weapons.has(out):
			unusable.append(out)
		if cfg.item_weapons.has(out) and Data.weapon(String(cfg.item_weapons[out])) == null:
			unusable.append(out)
	ok(unusable.is_empty(), "всё сделанное — оружие боя или одежда/доспех: %s" % str(unusable))


func _master(role: String, level: int) -> Actor:
	var m := Actor.new(role, "Мастер", true, 5)
	m.set_skill_level(Craft.skill_of(role), level)
	return m


func _order() -> void:
	var tanner: Actor = _master("tanner", 4)
	var bag: Dictionary = Trade.new_bag(3)
	var r: Dictionary = Craft.recipe("hide_vest")
	ok(Craft.order(bag, r, tanner) == "Не хватает материалов" and Craft.missing(bag, r) == ["Шкура 0/2"], "без шкур заказ не принят: %s" % str(Craft.missing(bag, r)))
	Trade.add(bag, "hide", 3)
	bag["money"] = 1
	ok(Craft.order(bag, r, tanner) == "Не хватает денег" and Trade.count(bag, "hide") == 3, "без денег — ничего не списано")
	bag["money"] = 10
	ok(Craft.order(bag, r, tanner) == "" and Trade.count(bag, "hide_vest") == 1 and Trade.count(bag, "hide") == 1 and int(bag["money"]) == 10 - int(r["fee"]),
		"заказ: шкуры и плата списаны, безрукавка в сумке")
	var smith: Actor = _master("smith", 3)
	var mail: Dictionary = Craft.recipe("chain_mail")
	Trade.add(bag, "scrap", 20)
	bag["money"] = 100
	ok(Craft.order(bag, mail, smith) == "Мастер такого не умеет" and Trade.count(bag, "scrap") == 20, "кольчугу кузнец 3-го уровня не берётся")
	ok(Craft.order(bag, Craft.recipe("knife"), smith) == "" and Trade.count(bag, "knife") == 1 and Trade.count(bag, "scrap") == 18, "нож из двух кусков лома")
	ok(Craft.order(bag, {}, smith) != "", "пустой рецепт не ломает")


func _self() -> void:
	var hero := Actor.new("hero", "Герой", false, 7)
	var bag: Dictionary = Trade.new_bag(0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 18
	var jacket: Dictionary = Craft.recipe("leather_jacket")
	var vest: Dictionary = Craft.recipe("hide_vest")
	ok(Craft.chance(jacket, hero) == 0.0 and Craft.self_blocker(bag, jacket, hero).begins_with("Нужен навык"), "куртку без навыка самому не сделать")
	ok(is_equal_approx(Craft.chance(vest, hero), 0.7), "безрукавка с нуля: шанс 70 %%: %.2f" % Craft.chance(vest, hero))
	ok(Craft.self_blocker(bag, vest, hero) == "Не хватает материалов", "без шкур — не начать")
	Trade.add(bag, "hide", 200)
	hero.set_res("stamina", 5.0)
	ok(Craft.self_blocker(bag, vest, hero).begins_with("Слишком устали"), "уставший не работает")
	var res: Dictionary = Craft.make(bag, vest, hero, rng)
	ok(not res["ok"] and Trade.count(bag, "hide") == 200, "попытка уставшим ничего не тратит: %s" % res["text"])
	var wins: int = 0
	var losses: int = 0
	var hides: int = Trade.count(bag, "hide")
	var lv_seen: Array = []
	for i in 40:
		hero.set_res("stamina", hero.max_of("stamina"))
		var before: float = float(hero.skills["sewing"]["xp"])
		var r: Dictionary = Craft.make(bag, vest, hero, rng)
		var gained: float = float(hero.skills["sewing"]["xp"]) - before
		if r["ok"]:
			wins += 1
			hides -= 2
		else:
			losses += 1
			hides -= 1
		if gained <= 0.0:
			lv_seen.append("нет опыта на %d" % i)
	ok(wins > 0 and losses > 0, "своими руками бывает и удача, и порча: %d / %d" % [wins, losses])
	ok(Trade.count(bag, "hide_vest") == wins, "вещей столько, сколько удач: %d" % Trade.count(bag, "hide_vest"))
	ok(Trade.count(bag, "hide") == hides, "при порче пропадает половина материалов: осталось %d шкур" % Trade.count(bag, "hide"))
	ok(lv_seen.is_empty(), "опыт идёт за каждую попытку")
	ok(hero.skill_level("sewing") >= 3, "40 попыток подняли портняжное дело до %d" % hero.skill_level("sewing"))
	ok(Craft.chance(vest, hero) > 0.7 and Craft.chance(vest, hero) <= 0.95, "с навыком шанс растёт, но не выше 95 %%: %.2f" % Craft.chance(vest, hero))
	ok(Craft.chance(jacket, hero) > 0.0, "с навыком %d открылась кожаная куртка" % hero.skill_level("sewing"))
	hero.set_res("stamina", hero.max_of("stamina"))
	var st0: float = hero.res["stamina"]
	Craft.make(bag, vest, hero, rng)
	ok(is_equal_approx(hero.res["stamina"], st0 - float(vest["work"])), "работа тратит выносливость: %.0f → %.0f" % [st0, hero.res["stamina"]])


func _lessons() -> void:
	var hero := Actor.new("hero", "Герой", false, 9)
	var smith: Actor = _master("smith", 2)
	var bag: Dictionary = Trade.new_bag(500)
	var fee: int = Craft.lesson_fee(hero, "blacksmith")
	ok(Craft.lesson(bag, hero, smith, "blacksmith") == "" and int(bag["money"]) == 500 - fee and float(hero.skills["blacksmith"]["xp"]) > 0.0, "урок: %d монет, опыт кузнеца %d" % [fee, int(hero.skills["blacksmith"]["xp"])])
	var n: int = 1
	while Craft.lesson(bag, hero, smith, "blacksmith") == "" and n < 50:
		n += 1
	ok(hero.skill_level("blacksmith") == 2, "уроками — до уровня мастера и не выше: %d за %d уроков" % [hero.skill_level("blacksmith"), n])
	ok(Craft.lesson(bag, hero, smith, "blacksmith") == "Мастеру больше нечему вас учить", "дальше мастер не учит")
	ok(Craft.lesson_fee(hero, "blacksmith") > fee, "урок дорожает с уровнем")
	var poor: Dictionary = Trade.new_bag(0)
	ok(Craft.lesson(poor, Actor.new("h2", "Б", false, 1), smith, "blacksmith") == "Не хватает денег", "без денег не учат")


func _battle_hides() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var bag: Dictionary = Trade.new_bag(0)
	var core: Node = Core.new()
	root.add_child(core)
	core.setup({"terrain": "forest", "allies": [Actor.new("hero", "Герой", false, 3)], "inventory": bag, "seed": 5,
		"enemies": [Enc.make_enemy("wolf", 0, rng), Enc.make_enemy("boar", 1, rng), Enc.make_enemy("bandit", 2, rng)]})
	for c in core.all:
		if c.team == 1:
			c.dead = true
	core._finish("win")
	var h: int = Trade.count(bag, "hide")
	ok(h >= 2 and h <= 4, "со зверей шкуры в сумку: %d (волк и кабан по 1–2)" % h)
	ok(int(core.loot.get("items", {}).get("hide", 0)) == h, "шкуры в итоге боя")
	ok(Trade.count(bag, "scrap") == int(core.loot.get("items", {}).get("scrap", 0)), "лом с бандита по-прежнему: %d" % Trade.count(bag, "scrap"))
	core.queue_free()


func _button(city: Node, prefix: String) -> Button:
	for b in city._buttons + city._tab_buttons:
		if b.text.find(prefix) >= 0:
			return b
	return null


func _city() -> void:
	var city: Node2D = load("res://city/city_world.tscn").instantiate()
	root.add_child(city)
	var hero := Actor.new("hero", "Герой", false, 11)
	var bag: Dictionary = Trade.new_bag(50)
	city.enter("s001", hero, {"inventory": bag, "gate": "south"})
	city.clock.paused = true
	await frames(3)
	var tanner: Dictionary = {}
	for n in city.npcs:
		if String(n["def"]["id"]) == "tanner":
			tanner = n
	ok(not tanner.is_empty(), "кожевник в городе с самого начала")
	tanner["pos"] = tanner["work_pos"]
	tanner["actor"].set_sleep(false)
	ok(city._npc_on_duty_here(tanner), "кожевник на работе (%.1f ч)" % city.clock.hour_of_day())
	city.talk(tanner)
	var b: Button = _button(city, "Мастерская")
	ok(b != null and city._tab_buttons.has(b), "в разговоре с кожевником есть вкладка «Мастерская» (Q34)")
	if b == null:
		return
	b.pressed.emit()
	ok(city._panel_kind == "craft" and city._panel_title.text.begins_with("Дубильня"), "открылась дубильня: %s" % city._panel_title.text)
	ok(_button(city, "Учиться у мастера") != null, "у мастера можно учиться")
	ok(_button(city, "Шкурная безрукавка") != null and _button(city, "Кожаная куртка") != null, "рецепты кожевника в списке")
	Trade.add(bag, "hide", 2)
	city.open_craft(tanner)
	_button(city, "Шкурная безрукавка").pressed.emit()
	var order: Button = _button(city, "Заказать у мастера")
	ok(order != null and _button(city, "Сделать самому") != null, "в рецепте: заказать и сделать самому")
	var m0: int = int(bag["money"])
	order.pressed.emit()
	ok(Trade.count(bag, "hide_vest") == 1 and Trade.count(bag, "hide") == 0 and int(bag["money"]) < m0, "заказ из окна: безрукавка в сумке")
	ok(city._panel_kind == "craft" and _button(city, "Сделать самому") == null, "материалов нет — самому уже не сделать")
	city.open_craft(tanner)
	_button(city, "Кожаная куртка").pressed.emit()
	ok(city._panel_text.text.find("нужен навык") >= 0, "куртка: самому нужен навык (%s)" % city._panel_text.text.replace("\n", " | "))
	_button(city, "Назад").pressed.emit()
	ok(city._panel_kind == "craft", "назад — к списку рецептов")
	_button(city, "Назад").pressed.emit()
	ok(city._panel_kind == "talk", "назад — к разговору")
	city._close_panel()
	city.queue_free()
	await frames(2)

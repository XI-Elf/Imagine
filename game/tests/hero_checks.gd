extends SceneTree
## Створення героя й вікно героя (characters/hero_profile.gd, hero_create.gd, hero_window.gd).
## Правила без сцени, потім головне меню, карта, місто. Потрібен екран (xvfb, --rendering-driver opengl3).
## godot --path game --rendering-driver opengl3 -s res://tests/hero_checks.gd -- [тека_для_знімків]

const P := preload("res://characters/hero_profile.gd")
const R := preload("res://characters/actor_rules.gd")
const Sheet := preload("res://characters/sheet.gd")
const Inv := preload("res://characters/inventory_view.gd")
const Trade := preload("res://city/trade.gd")

var fails: int = 0
var checks: int = 0
var shots: String = ""


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


func shot(name: String) -> void:
	if shots == "":
		return
	await frames(3)
	root.get_viewport().get_texture().get_image().save_png(shots.path_join(name))


func key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = true
	root.get_viewport().push_input(ev)
	ev = ev.duplicate()
	ev.pressed = false
	root.get_viewport().push_input(ev)


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	shots = args[0] if args.size() > 0 else ""
	_run()


func _run() -> void:
	_rules()
	await _menu()
	await _game()
	print("hero_checks: %d/%d %s" % [checks - fails, checks, "ok" if fails == 0 else "FAIL"])
	quit(1 if fails > 0 else 0)


# =====================================================================
func _rules() -> void:
	var C: Dictionary = P.C()
	ok(C["origins"].size() == 5 and C["professions"].size() == 6 and C["traits"].size() == 38, "данные 09: 5 происхождений, 6 профессий, 38 черт")
	var p: Dictionary = P.default_params()
	p["name"] = "Конрад"
	p["gender"] = "male"
	p["age"] = 35
	p["origin"] = "peasant"
	p["profession"] = "smith"
	# Характеристики: от 5, свободных 5; Ловкость опущена до 4 — ещё одно очко
	p["alloc"] = {"str": 2, "per": 1, "end": 2, "cha": 0, "int": 1, "agi": -1, "luck": 0}
	p["traits"] = ["strong_build", "glutton", "honest"]
	p["quirks"] = ["bruiser"]
	ok(P.alloc_valid(p["alloc"]), "5 свободных очков распределены (одно взято у Ловкости)")
	var parts: Dictionary = P.stat_parts(p)
	# Сила: 5 + 2 очка + 1 «Крепкое сложение» + 2 «Громила» = 10 (предел); прошлое характеристики не меняет
	ok(int(parts["str"]["total"]) == 10 and int(parts["str"]["traits"]) == 3, "Сила по частям: %s" % parts["str"])
	ok(int(parts["agi"]["total"]) == 4, "Ловкость опущена до 4: %s" % parts["agi"])
	ok(int(parts["cha"]["total"]) == 6 and int(parts["luck"]["total"]) == 5, "«Честный»: Обаяние 6; Удача 5: %s %s" % [parts["cha"], parts["luck"]])
	ok(not P.alloc_valid({"str": 6, "per": 0, "end": 0, "cha": 0, "int": 0, "agi": -1, "luck": 0}), "выше 10 нельзя")
	ok(not P.alloc_valid({"str": 2, "per": 0, "end": 0, "cha": 0, "int": 0, "agi": 0, "luck": 0}), "не все очки — нельзя")
	ok(P.profession_tags("smith") == ["repair", "melee", "barter"], "кузнец отмечает Ремесло, Холодное оружие, Торговлю")
	ok(P.traits_valid(["brave", "coward"]) != "", "противоположные черты нельзя вместе")
	var many: Array = ["brave", "honest", "diligent", "hardy", "strong_build", "nimble", "sharp", "prudent", "keen_eye", "charming", "pious"]
	ok(P.traits_valid(many) != "", "больше 10 черт нельзя (%d)" % many.size())
	ok(P.alignment_name(P.alignment(["honest", "pious", "compassionate"])) == "Законно-добрый", "мировоззрение из черт")
	ok(P.alignment_name(P.alignment(["cruel", "liar", "rash"])) == "Хаотично-злой", "злое мировоззрение из черт")
	var bonus: Dictionary = P.skill_bonus(p)
	# кузнец: Кузнечное дело 3 → Ремесло +15 %; крестьянин: Выживание 1 + Кулинария 1 → Выживание +10 %
	ok(int(bonus.get("repair", 0)) == 15 and int(bonus.get("outdoorsman", 0)) == 10, "добавки к навыкам от прошлого: %s" % bonus)
	var vals: Dictionary = P.skill_values(p)
	# Ремесло: 3×УМ(6) = 18 + отмечен 20 + прошлое 15 = 53
	ok(int(vals["repair"]) == 53, "Ремесло героя: %s" % vals["repair"])
	var bio: String = P.biography(p)
	ok(bio.begins_with("Конрад, 35 лет.") and bio.contains("Мировоззрение: «") and bio.length() < 260 and bio.count(".") <= 4, "биография короткая и пишется сама: " + bio)
	ok(P.biography(p) == bio, "биография одинаковая при одинаковом выборе")

	var a := Actor.new("hero", "Герой", false, 7)
	P.apply(a, p)
	ok(a.display_name == "Конрад" and int(a.stat("str")) == 10 and int(a.stat("luck")) == 5, "герой получил имя и характеристики")
	ok(a.skill("repair") == 53 and a.skill_level("blacksmith") == 5 and a.traits.size() == 3 and a.quirks == ["bruiser"], "герой получил навыки, черты характера и особенность")
	ok(a.tags == ["repair", "melee", "barter"] and a.level == 1, "отмечены навыки профессии, уровень 1")
	var b := Actor.from_dict(a.to_dict())
	ok(b.traits == a.traits and b.profile.get("origin") == "peasant" and String(b.profile.get("biography", "")) == bio, "черты и профиль в сохранении")
	ok(b.quirks == a.quirks and b.tags == a.tags and b.skill("repair") == 53 and int(b.stat("str")) == 10, "характеристики, отметки и особенности в сохранении")
	# Підвиди людей (Alvaren / Sairen / Veyran, числа [ВРЕМЕННО]); без підвиду поправок немає (старі герої)
	var ps: Dictionary = p.duplicate(true)
	ps["subspecies"] = "alvaren"
	var pp: Dictionary = P.stat_parts(ps)
	ok(P.C()["subspecies"].size() == 3 and int(pp["end"]["subspecies"]) == 1 and int(pp["end"]["total"]) == int(parts["end"]["total"]) + 1, "подвид Alvaren: Стойкость +1 к итогу")
	ok(int(parts["end"]["subspecies"]) == 0 and not P.biography(p).contains("альбов"), "без подвида поправок и фразы в биографии нет")
	ok(P.biography(ps).contains("альбов"), "биография называет подвид")
	var sa := Actor.new("s", "s", false, 1)
	P.apply(sa, ps)
	ok(is_equal_approx(sa._sum("cold_resist_c"), 3.0) and is_equal_approx(sa._sum("heat_resist_c"), -2.0) and String(sa.profile.get("subspecies")) == "alvaren", "эффекты подвида: холод +3 °C, жара −2 °C, профиль хранит подвид")
	ok(is_equal_approx(Actor.from_dict(sa.to_dict())._sum("cold_resist_c"), 3.0), "подвид переживает сохранение")
	ok(P.C()["subspecies"].has(P.random_params(RandomNumberGenerator.new())["subspecies"]), "случайный герой получает подвид")
	# Кодекс: записки, шанс, повторів немає, прогрес
	var Cx := load("res://world/codex.gd")
	var found: Dictionary = {}
	var crng := RandomNumberGenerator.new()
	crng.seed = 7
	var got: int = 0
	for _i in 200:
		if not Cx.find(found, "ruins", crng, 1.0).is_empty():
			got += 1
	ok(got == Cx.unfound({}, "ruins").size() and Cx.unfound(found, "ruins").is_empty(), "кодекс: все записки руин находятся по одному разу (%d)" % got)
	ok(Cx.find(found, "ruins", crng, 2.0).is_empty() and Cx.progress(found)["found"] == got and Cx.progress({})["total"] == 18, "кодекс: повторов нет, всего 18 записок")
	ok(Cx.note("hum_1").get("chapter") == "humans" and Cx.chapters().size() == 9, "кодекс: записки и 9 разделов")
	# Риси працюють через ефекти: ненажера голодніє швидше
	var plain := Actor.new("x", "x", false, 1)
	var env := {"biome": 4, "water": 0.0, "temp_c": 15.0, "rain": 0.0, "night": false}
	plain.tick(3600.0 * 5.0, env)
	var glut := Actor.new("y", "y", false, 1)
	glut.traits = ["glutton"]
	glut.tick(3600.0 * 5.0, env)
	ok(glut.res["hunger"] < plain.res["hunger"] - 1.0, "«Обжора» голодает быстрее: %.1f против %.1f" % [glut.res["hunger"], plain.res["hunger"]])
	var dil := Actor.new("z", "z", false, 1)
	dil.traits = ["diligent"]
	dil.add_xp("survival", 100.0)
	var lazy := Actor.new("w", "w", false, 1)
	lazy.traits = ["lazy"]
	lazy.add_xp("survival", 100.0)
	ok(dil.xp > lazy.xp, "«Трудолюбивый» набирает опыт быстрее «Ленивого»")
	var q := Actor.new("q", "q", false, 1)
	q.traits = ["quiet"]
	ok(q.mult("sneak") > 1.0 and plain.mult("sneak") == 1.0, "«Тихий» — выше шанс проникнуть")
	var hl := Actor.new("h", "h", false, 1)
	hl.traits = ["fast_healer"]
	hl.res["health"] = 50.0
	plain.res["health"] = 50.0
	hl.tick(3600.0, env)
	plain.tick(3600.0, env)
	ok(hl.res["health"] > plain.res["health"], "«Быстрое заживление»")
	var r := RandomNumberGenerator.new()
	r.seed = 5
	for i in 30:
		var rp: Dictionary = P.random_params(r)
		if not P.alloc_valid(rp["alloc"]) or P.traits_valid(rp["traits"]) != "" or Sheet.tags_valid(rp["tags"]) != "" or Sheet.traits_valid(rp["quirks"]) != "":
			ok(false, "случайный герой допустим: %s" % rp)
			return
	ok(true, "30 случайных героев допустимы")


# =====================================================================
func _menu() -> void:
	Engine.set_meta("aw_intro_done", true)
	var menu: Control = load("res://main_menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	await frames(3)
	menu._on_new_game()
	await frames(3)
	var cr: CanvasLayer = menu._creator
	ok(cr != null and cr.visible, "«Новая игра» открывает создание персонажа")
	ok(cr.create_btn.disabled, "без имени и очков «Создать» недоступна")
	cr.name_edit.text = "Ильза"
	for s in ["agi", "agi", "agi", "per", "per"]:
		cr.change_stat(s, 1)
	cr.change_stat("str", 1)
	ok(P.points_spent(cr.alloc) == 5, "больше 5 очков не потратить")
	cr.change_stat("cha", -1)
	cr.change_stat("str", 1)
	ok(int(cr.alloc["cha"]) == -1 and int(cr.alloc["str"]) == 1, "опустить Обаяние до 4 — и очко на Силу")
	cr.toggle_tag("bows")
	ok(cr.tags.size() == 3 and not cr.tags.has("bows"), "больше 3 отмеченных навыков нельзя")
	cr.toggle_tag("melee")
	cr.toggle_tag("bows")
	ok(cr.tags.has("bows") and not cr.tags.has("melee"), "отметки можно менять")
	cr.toggle_quirk("small_frame")
	cr.toggle_quirk("finesse")
	cr.toggle_quirk("gifted")
	ok(cr.quirks == ["small_frame", "finesse"], "не больше двух особенностей")
	cr.toggle_trait("nimble")
	cr.toggle_trait("clumsy")
	ok(cr.traits == ["nimble"], "противоположную черту не выбрать")
	cr.toggle_trait("keen_eye")
	cr.toggle_trait("light_sleeper")
	cr._refresh()
	ok(not cr.create_btn.disabled, "можно создавать")
	ok(cr._bio.text.contains("Ильза"), "биография с именем")
	cr._select_key(cr.sub_opt, "veyran")
	cr._refresh()
	ok(cr.params()["subspecies"] == "veyran" and cr.sub_text.text.contains("скорость"), "в создании героя выбирается подвид, видны его эффекты")
	await shot("h01_create.png")
	cr.randomize_all()
	await shot("h02_create_random.png")
	cr._set_gender("female")
	cr.name_edit.text = "Ильза"
	cr.alloc = {"str": 0, "per": 2, "end": 1, "cha": 0, "int": 0, "agi": 2, "luck": 0}
	cr.tags = ["bows", "sneak", "outdoorsman"]
	cr.quirks = ["small_frame"]
	cr.traits = ["nimble", "keen_eye", "light_sleeper", "quiet"]
	cr._refresh()
	# «Створити» веде в гру; тут перехоплюємо, щоб не змінювати сцену в тесті
	var got: Array = []
	cr.finished.disconnect(menu._on_hero_created)
	cr.finished.connect(func(p): got.append(p))
	cr._on_create()
	ok(got.size() == 1 and got[0]["name"] == "Ильза", "«Создать» отдаёт выбор")
	Engine.set_meta("aw_new_hero", got[0] if got.size() > 0 else {})
	menu.queue_free()
	await frames(2)


# =====================================================================
func _game() -> void:
	var W: Node = root.get_node_or_null("Worlds")
	Engine.set_meta("aw_load", "")
	var game: Node2D = load("res://game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	var t0: int = Time.get_ticks_msec()
	while not game.ready_done and Time.get_ticks_msec() - t0 < 120000:
		await process_frame
	await frames(5)
	var cast: Node2D = game.cast
	ok(not cast.hero.is_empty() and cast.hero["actor"].display_name == "Ильза", "новая игра: герой из экрана создания")
	ok(not Engine.has_meta("aw_new_hero"), "выбор применён один раз")
	var a: Actor = cast.hero["actor"]
	ok(a.traits.has("quiet") and a.profile.has("biography"), "у героя черты и история")
	if game.get("settlements") != null:
		ok(cast.hero["pos"].distance_to(game.settlements.spawn_point()) < 600.0, "герой у ворот города")
	ok(W == null or (W.inventory["items"] == {"leather_jacket": 1, "water_flask": 2, "parchment": 1, "charcoal_stick": 1} and String(W.inventory.get("equipped", {}).get("body", "")) == "leather_jacket" and int(W.inventory["money"]) == 0), "новая игра: надетая кожаная куртка (доспех в бою), две фляги воды, пергамент и уголёк")
	game.zoom = 0.6
	key(KEY_I)
	await frames(3)
	ok(cast.window.visible and cast.window.tab == "stats", "I — окно героя, характеристики")
	await shot("h03_window_stats.png")
	var p0: Vector2 = cast.hero["pos"]
	Input.action_press("ui_right")
	await create_timer(1.0).timeout
	Input.action_release("ui_right")
	ok(cast.hero["pos"].distance_to(p0) < 0.5, "пока окно открыто, герой стоит")
	key(KEY_2)
	await frames(3)
	ok(cast.window.tab == "skills", "2 — навыки")
	await shot("h04_window_skills.png")
	key(KEY_3)
	await frames(3)
	ok(cast.window.tab == "perks", "3 — дары и особенности")
	await shot("h05_window_perks.png")
	key(KEY_4)
	await frames(3)
	ok(cast.window.tab == "traits", "4 — черты характера")
	await shot("h05_window_traits.png")
	key(KEY_TAB)
	await frames(3)
	ok(cast.window.tab == "bag", "Tab — инвентарь")
	await shot("h06_window_bag_empty.png")
	# Дневник (вкладка 6): пусто, потом найденные записки по разделам
	if W != null:
		W.codex = {}
	key(KEY_6)
	await frames(3)
	ok(cast.window.tab == "diary", "6 — дневник")
	await shot("h06b_diary_empty.png")
	if W != null:
		W.codex = {"old_3": 1.0, "hum_1": 2.0, "gno_1": 3.0}
		cast.window.refresh_bag()
		await frames(3)
		ok(cast.window._body.get_child_count() >= 7, "дневник: книга из найденных записок (%d блоков)" % cast.window._body.get_child_count())
		await shot("h06c_diary_notes.png")
		W.codex = {}
	key(KEY_TAB)
	await frames(3)
	# У сумці їжа й ніж: з'їсти, узяти в бій, викинути
	var bag: Dictionary = W.inventory if W != null else cast._inventory()
	Trade.add(bag, "bread", 2)
	Trade.add(bag, "knife", 1)
	Trade.add(bag, "torch", 1)
	bag["money"] = 12
	a.res["hunger"] = 40.0
	cast.window.refresh()
	await frames(3)
	await shot("h07_window_bag.png")
	cast.window.use_item("bread")
	ok(Trade.count(bag, "bread") == 1 and a.res["hunger"] > 40.0, "съел хлеб из сумки")
	cast.window.toggle_loadout("knife")
	ok(bag.get("battle_loadout", []) == ["knife"], "нож взят в бой (выбор для окна подготовки к бою)")
	cast.window.drop_item("torch")
	ok(Trade.count(bag, "torch") == 0, "факел выброшен")
	# Лялька персонажа: слоти зброї «у бій», ряд «під рукою», сумка клітинками, обрана річ
	for it in [["water_flask", 2], ["bandage", 3], ["axe", 1], ["amber", 1], ["dried_meat", 4], ["rope", 1]]:
		Trade.add(bag, it[0], it[1])
	cast.window.toggle_loadout("axe")
	cast.window.inv_sel = "axe"
	cast.window.refresh_bag()
	await frames(3)
	var views: Array = cast.window._body.get_children().filter(func(c): return c is Inv)
	ok(views.size() == 1, "инвентарь — кукла персонажа")
	await shot("h08_window_doll.png")
	cast.window.set_filter("food")
	await frames(3)
	views = cast.window._body.get_children().filter(func(c): return c is Inv)
	ok(views.size() == 1 and views[0].shown_items().size() == 3, "фильтр «Провизия»: хлеб, вода, мясо")
	await shot("h09_window_filter_food.png")
	cast.window.set_filter("all")
	cast.window.toggle_sort()
	await frames(3)
	views = cast.window._body.get_children().filter(func(c): return c is Inv)
	ok(views.size() == 1 and Inv.cat_of(views[0].shown_items()[0], views[0].weapons) == "food", "«По типу»: сначала провизия")
	cast.window.toggle_sort()
	cast.window.set_filter("parts")
	cast.window.drop_all()
	ok(Trade.count(bag, "rope") == 1, "«Бросить всё» ждёт второго нажатия")
	cast.window.set_filter("tools")
	cast.window.drop_all()
	cast.window.drop_all()
	ok(Trade.count(bag, "rope") == 0 and Trade.count(bag, "bread") == 1, "«Бросить всё» в «Инструментах» выбросило только верёвку")
	cast.window.set_filter("all")
	var flasks: int = Trade.count(bag, "water_flask")
	cast.window.use_item("water_flask")
	ok(Trade.count(bag, "water_flask") == flasks - 1, "выпил воду из сумки")
	# Одяг на ляльці: без одягу — майка й бриджі (h08), удягнув — видно на фігурі
	for it in ["linen_shirt", "trousers", "boots", "straw_hat", "travel_cloak", "gloves", "leather_jacket"]:
		Trade.add(bag, it, 1)
	for it in ["linen_shirt", "trousers", "boots", "straw_hat", "travel_cloak", "gloves"]:
		cast.window.equip_item(it)
	cast.window.inv_sel = "travel_cloak"
	cast.window.refresh_bag()
	await frames(3)
	views = cast.window._body.get_children().filter(func(c): return c is Inv)
	ok(views.size() == 1 and views[0].looks().size() == 6, "надето 6 вещей — все на кукле")
	await shot("h10_window_dressed.png")
	cast.window.equip_item("leather_jacket")
	ok(bag["equipped"]["body"] == "leather_jacket", "куртка заменила рубаху в слоте «Тело»")
	cast.window.drop_item("boots")
	ok(not bag["equipped"].has("feet"), "выброшенные сапоги сняты с куклы")
	cast.window.unequip_item("straw_hat")
	ok(not bag["equipped"].has("head"), "шляпу сняли")
	cast.window.inv_sel = "leather_jacket"
	cast.window.refresh_bag()
	await frames(3)
	await shot("h11_window_jacket.png")
	for it in ["linen_shirt", "trousers", "travel_cloak", "gloves", "leather_jacket", "straw_hat"]:
		Trade.add(bag, it, -Trade.count(bag, it))
	bag["equipped"] = {}
	for it in ["water_flask", "bandage", "axe", "amber", "dried_meat", "rope"]:
		Trade.add(bag, it, -Trade.count(bag, it))
	bag["battle_loadout"] = ["knife"]
	key(KEY_ESCAPE)
	await frames(3)
	ok(not cast.window.visible and not game.menu_open, "Esc закрывает окно, а не открывает меню паузы")
	# Збереження: ім'я героя в списку, риси на місці
	game.save_world()
	var WS := preload("res://world_save.gd")
	var lst: Array = WS.list()
	ok(not lst.is_empty() and String(lst[0].get("char_name", "")) == "Ильза", "в списке сохранений имя героя")
	# У місті — те саме вікно
	if W != null and W.has_method("enter_city"):
		ok(await W.enter_city("s001", {"return_pos": cast.hero["pos"]}), "в город")
		await frames(5)
		var city: Node = W.current_node()
		if city != null and city.get("window") != null:
			key(KEY_TAB)
			await frames(3)
			ok(city.window.visible and city.window.tab == "bag" and city._menu_blocked(), "Tab в городе — инвентарь, герой стоит")
			ok(city.window._bag() == W.inventory, "в городе та же сумка")
			await shot("h08_city_bag.png")
			key(KEY_I)
			await frames(3)
			ok(city.window.tab == "stats", "I в городе — характеристики")
			key(KEY_I)
			await frames(3)
			ok(not city.window.visible, "I ещё раз — закрыть")
		W.leave()
		for i in 90:
			await process_frame
	# Загибель: екран загибелі з випадковим новим героєм (characters/hero_death.gd, питання Q06)
	a.die("other")
	for i in 120:
		if cast.death.active:
			break
		await process_frame
	ok(cast.death.active, "после гибели — экран нового героя")
	cast.death.continue_as_new()
	await frames(3)
	ok(not cast.death.active and cast.hero["actor"].alive and cast.hero["actor"] != a, "новый герой создан")

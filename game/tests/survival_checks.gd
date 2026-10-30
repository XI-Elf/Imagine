extends SceneTree
## Механіки виживання (Huzzah 2026-10-29, пункти 11, 16, 17): пошук у полі й вікно «Найдено», маскування й напади,
## пергамент героя на M (малювання, обривки карти, позначка героя за Картографією), вічні пергамент і вуглик.
## godot --path game --rendering-driver opengl3 -s res://tests/survival_checks.gd -- [тека_для_знімків]

const Foraging := preload("res://world/foraging.gd")
const Enc := preload("res://battle/encounters.gd")
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


func _key(code: int) -> InputEventKey:
	var k := InputEventKey.new()
	k.physical_keycode = code
	k.keycode = code
	k.pressed = true
	return k


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	shots = args[0] if args.size() > 0 else ""
	_pure()
	_run()


# Без сцени: таблиці, маскування, шанси
func _pure() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var a := Actor.new("t", "T", false, 11)
	a.res["stamina"] = a.max_of("stamina")
	var searched: Dictionary = {}
	var bag: Dictionary = Trade.new_bag()
	var r: Dictionary = Foraging.search(a, 3, Vector2(1000, 1000), 0.0, searched, bag, rng)
	ok(bool(r["ok"]) and float(r["minutes"]) == 60.0, "поиск в лесу: час игры")
	ok(Trade.weight(bag) == 0.0, "находки не падают в сумку сами (окно «Найдено»)")
	var r2: Dictionary = Foraging.search(a, 3, Vector2(1100, 1050), 10.0, searched, bag, rng)
	ok(not bool(r2["ok"]) and Foraging.depleted_left(searched, Vector2(1000, 1000), 10.0) > 0.0, "обшаренное место пустое")
	ok(not bool(Foraging.search(a, 1, Vector2(9000, 9000), 0.0, {}, bag, rng)["ok"]), "в воде искать нечего")
	# Сотня пошуків у лісі: є їжа й хмиз
	var total: Dictionary = {}
	for i in 100:
		a.res["stamina"] = a.max_of("stamina")
		var f: Dictionary = Foraging.search(a, 3, Vector2(i * 1000.0, 0.0), 0.0, {}, bag, rng)["found"]
		for id in f:
			total[id] = int(total.get(id, 0)) + int(f[id])
	ok(int(total.get("berries", 0)) + int(total.get("mushrooms", 0)) + int(total.get("toadstool", 0)) > 20 and int(total.get("brushwood", 0)) > 30, "лес кормит и даёт хворост: %s" % total)
	for id in total:
		ok(not Trade.item(id).is_empty(), "предмет %s есть в items.json" % id)
	# Інструменти й факел
	var axe: Dictionary = Trade.new_bag()
	Trade.add(axe, "axe")
	ok(Foraging.tool_mult("brushwood", axe, false) > 1.0 and Foraging.tool_mult("brushwood", Trade.new_bag(), true) < 1.0, "топор помогает, ночь без факела мешает")
	# Запас місця: перший обхід найщедріший, місце скудніє й відростає
	var sr: Dictionary = {}
	var p0 := Vector2(50000, 50000)
	a.res["stamina"] = a.max_of("stamina")
	ok(Foraging.richness(sr, p0, 0.0) == 1.0, "нетронутое место — полный запас")
	Foraging.search_round(a, 3, p0, 0.0, sr, bag, rng)
	var r1: float = Foraging.richness(sr, p0, 0.0)
	ok(r1 < 1.0 and r1 > 0.5, "обход забирает часть запаса (%.2f)" % r1)
	ok(Foraging.richness(sr, p0, 36.0 * 3600.0) > r1, "место отрастает со временем")
	var first: int = 0
	var last: int = 0
	for i in 200:
		var q: Dictionary = {}
		a.res["stamina"] = a.max_of("stamina")
		var pp := Vector2(i * 1000.0, 7000.0)
		for k in 4:
			var rr: Dictionary = Foraging.search_round(a, 3, pp, 0.0, q, bag, rng)
			if k == 0:
				first += rr["found"].size()
			elif k == 3:
				last += rr["found"].size()
	ok(first > last * 2, "первый обход щедрее четвёртого (%d > %d)" % [first, last])
	# Залишок на місці
	var stash: Dictionary = {}
	Foraging.leave_stash(stash, Vector2(10, 10), 0.0, {"roots": 2})
	ok(Foraging.take_stash(stash, Vector2(20, 20), 100.0).get("roots", 0) == 2 and stash.is_empty(), "оставленное лежит на месте")

	# Маскування
	var env_day := {"biome": 4, "night": false}
	var env_night := {"biome": 3, "night": true}
	var c_day: float = Enc.concealment(a, env_day)
	var c_night: float = Enc.concealment(a, env_night)
	ok(c_night > c_day, "ночью в лесу незаметнее (%.2f > %.2f)" % [c_night, c_day])
	ok(Enc.stealth_mult(c_night) < Enc.stealth_mult(c_day), "незаметнее — реже нападают")
	ok(is_equal_approx(Enc.stealth_mult(Enc.CONCEAL_REF), 1.0), "средний герой: множитель 1")
	a.mount = "cart"
	ok(Enc.concealment(a, env_day) < c_day, "с повозкой заметнее")
	a.mount = ""
	ok(Enc.chance_for_hours(a, env_day, 8.0) > Enc.chance_for_hours(a, env_day, 1.0) and Enc.chance_for_hours(a, {"biome": 1}, 8.0) == 0.0, "стоянка: чем дольше, тем опаснее; на воде нет")

	# Пергамент і вуглик
	var kit: Dictionary = Trade.new_bag()
	Trade.ensure_kit(kit)
	ok(Trade.count(kit, "parchment") == 1 and Trade.count(kit, "charcoal_stick") == 1, "у персонажа пергамент и уголёк")
	ok(Trade.sell(kit, {}, ["parchment"], "parchment", a) != "" and Trade.count(kit, "parchment") == 1, "пергамент не продать")

	# Відстань за Розумом (пункт 12)
	var Route := preload("res://characters/hero_route.gd")
	ok(Route.distance_words(300.0, 2) == "рукой подать" and Route.distance_words(9000.0, 3) == "очень далеко", "Ум 1–3: словами")
	ok(Route.distance_words(2600.0, 5) == "около 3 км", "Ум 4–6: округлённо (%s)" % Route.distance_words(2600.0, 5))
	ok(Route.distance_words(2440.0, 8) == "2.4 км" or Route.distance_words(2440.0, 8) == "2,4 км", "Ум 7+: точно (%s)" % Route.distance_words(2440.0, 8))

	# Стіна зсередини (пункт 14)
	var WC := preload("res://city/wall_climb.gd")
	var climber := Actor.new("c", "C", false, 3)
	climber.res["stamina"] = climber.max_of("stamina")
	var c0: float = WC.chance(climber, Trade.new_bag())
	var rope: Dictionary = Trade.new_bag()
	Trade.add(rope, "rope")
	ok(WC.chance(climber, rope) > c0, "верёвка помогает перелезть (%.2f > %.2f)" % [WC.chance(climber, rope), c0])
	ok(WC.seen_chance(climber, 10.0) > WC.seen_chance(climber, 200.0), "стражник рядом — заметит")
	var outs: Dictionary = {}
	for i in 200:
		climber.res["stamina"] = climber.max_of("stamina")
		climber.conditions.clear()
		var o: String = WC.attempt(climber, rope, 200.0, rng)
		outs[o] = int(outs.get(o, 0)) + 1
	ok(outs.has("over") and outs.size() >= 3, "исходы попыток: %s" % outs)

	# Журнал (пункт 15)
	var J := preload("res://characters/quest_journal.gd")
	var ic: Array = J.icons_for("Убить волков у старого города и принести шкуры старосте за 10 монет")
	ok(ic.has("sword") and ic.has("house") and ic.has("hide") and ic.has("coin"), "Ум низкий: картинки %s" % [ic])
	ok(J.crude_words("Убить волков у города").split(" ").size() <= 3, "Ум низкий: пара простых слов")
	var rt: String = J.rich_text({"text": "принести шкуры старосте", "place": "Эшвик"}, "1 Хомана")
	ok(rt.contains("Эшвик") and rt.contains("старосте с мутным") and rt.length() > 60, "Ум высокий: подробно")


func _run() -> void:
	var game: Node2D = load("res://game.tscn").instantiate()
	root.add_child(game)
	var t0: int = Time.get_ticks_msec()
	while not game.ready_done and Time.get_ticks_msec() - t0 < 120000:
		await process_frame
	ok(game.ready_done, "карта загрузилась")
	var wm: Node = root.get_node_or_null("Worlds")
	if wm != null:
		wm.idle_attacks = false
	var cast: Node2D = game.cast
	cast.spawn_hero(Vector2(20812.0, 18000.0))
	var hero: Dictionary = cast.hero
	var bag: Dictionary = cast._inventory()
	ok(Trade.count(bag, "parchment") == 1 and Trade.count(bag, "charcoal_stick") == 1, "новый герой с пергаментом и угольком")
	cast.window.drop_item("parchment")
	ok(Trade.count(bag, "parchment") == 1, "пергамент не выбросить")

	# Пошук у полі → вікно «Найдено»
	var forest: Vector2 = Vector2.INF
	for k in 400:
		var p: Vector2 = cast._find_land(hero["pos"] + Vector2.from_angle(k * 0.7) * (300.0 + k * 40.0), 2000.0, true)
		if game.biome_at(p) == 3:
			forest = p
			break
	if forest != Vector2.INF:
		hero["pos"] = forest
	hero["actor"].res["stamina"] = hero["actor"].max_of("stamina")
	var t_before: float = game.clock.total_seconds
	var opened: bool = false
	var chose: bool = false
	for tries in 10:
		hero["pos"] += Vector2(500.0, 0.0)
		hero["actor"].res["stamina"] = hero["actor"].max_of("stamina")
		cast.search_field()
		if cast.loot != null and cast.loot.is_open():
			chose = chose or cast.loot.phase == "choose"
			if cast.loot.phase == "choose":
				await shot("s00_search_choose.png")
			cast.loot.start(4)
			ok(cast.loot.is_searching(), "поиск идёт обходами")
			cast.loot.step()
			cast.loot.step()
			await shot("s00_search_progress.png")
			cast.loot.run_all()
			if not cast.loot.items.is_empty():
				opened = true
				break
			cast.loot.finish()
	ok(chose, "F в поле: окно выбора, сколько искать")
	ok(game.clock.total_seconds - t_before >= 3600.0, "поиск съел час игры")
	ok(opened, "находки показаны плитками (биом %d)" % game.biome_at(hero["pos"]))
	if opened:
		ok(cast.loot.phase == "loot" and cast.loot.rounds_done == 4, "четыре обхода по 15 минут")
		ok(cast.hold_hero, "пока выбираем, герой стоит")
		await shot("s01_loot.png")
		var kg0: float = Trade.weight(bag)
		cast.loot.take_all()
		ok(Trade.weight(bag) > kg0 and not cast.loot.is_open() and not cast.hold_hero, "взял всё — в сумке, окно закрыто")

	# Пергамент: M, обривок, малюнок, позначка героя
	Trade.add(bag, "map_fragment", 1)
	Input.parse_input_event(_key(KEY_M))
	await frames(3)
	var pm: CanvasLayer = cast.parchment
	ok(pm.is_open() and game.clock.paused, "M открывает пергамент, время стоит")
	ok(pm.fragments.size() == 1 and Trade.count(bag, "map_fragment") == 0, "отрывок карты приложен к пергаменту")
	pm.begin_stroke(Vector2(200, 200))
	for i in 20:
		pm.stroke_to(Vector2(200 + i * 12, 200 + sin(i * 0.5) * 30))
	pm._finish_stroke()
	ok(pm.strokes.size() == 1 and pm.point_count() > 10, "нарисовал углём: %d точек" % pm.point_count())
	ok(not pm.shows_self(), "Картография %d: героя на листе не видно" % pm.cartography())
	hero["actor"].set_skill_level("cartography", 6)
	ok(pm.shows_self(), "Картография %d: герой на листе виден" % pm.cartography())
	pm._refresh_bar()
	ok(pm._color_btns["red"].disabled, "без набора цветных углей — только чёрный")
	Trade.add(bag, "color_charcoals", 1)
	pm._refresh_bar()
	ok(not pm._color_btns["red"].disabled, "набор цветных углей открывает цвета")
	pm.color = "red"
	pm.begin_stroke(Vector2(400, 300))
	pm.stroke_to(Vector2(500, 330))
	pm._finish_stroke()
	await shot("s02_parchment.png")
	pm.erase_at(Vector2(450, 315))
	ok(pm.strokes.size() == 3, "ластик стёр участок красного штриха: остались два куска")
	Input.parse_input_event(_key(KEY_M))
	await frames(2)
	ok(not pm.is_open() and not game.clock.paused, "M закрывает пергамент, время идёт")

	# Журнал на J: запис зберігається, читається за Розумом
	if wm != null:
		Input.parse_input_event(_key(KEY_J))
		await frames(3)
		ok(wm.journal.is_open() and game.typing, "J открывает журнал, герой не ходит")
		wm.journal._edit.text = "Принести старосте три шкуры волка"
		wm.journal.add(wm.journal._edit.text)
		await shot("s03_journal.png")
		wm.journal.close()
		await frames(2)
		ok(not game.typing and wm.to_dict()["journal"].size() == 1, "запись в журнале сохраняется")

	# Збереження
	var d: Dictionary = cast.to_dict()
	var back: Dictionary = str_to_var(var_to_str(d))
	pm.clear()
	cast.load_dict(back)
	ok(cast.parchment.strokes.size() == 3 and cast.parchment.fragments.size() == 1, "пергамент пережил сохранение")
	ok(not cast.field_searched.is_empty(), "обшаренные места сохраняются")

	print("SURVIVAL CHECKS: %d/%d" % [checks - fails, checks])
	quit(1 if fails > 0 else 0)

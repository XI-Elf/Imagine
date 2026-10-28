extends SceneTree
## Проверка мира города без общей карты (нужен экран: под xvfb, --rendering-driver opengl3).
## godot --path game --rendering-driver opengl3 -s res://tests/city_checks.gd -- [папка_для_снимков]

const Trade := preload("res://city/trade.gd")
const CityMap := preload("res://city/city_map.gd")

var fails: int = 0
var checks: int = 0
var shots: String = ""
var exits: Array = []


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


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	shots = args[0] if args.size() > 0 else ""
	_run()


func set_hour(city: Node, h: float) -> void:
	var t: float = city.clock.total_seconds
	city.clock.total_seconds = t - fposmod(t, 86400.0) + h * 3600.0


func walk(city: Node, dir: Vector2, seconds: float) -> float:
	var start: Vector2 = city.hero_pos
	var steps: int = int(seconds * 30.0)
	for i in steps:
		city.move_hero(dir, false, 1.0 / 30.0, city.env_at(city.hero_pos))
	return city.hero_pos.distance_to(start)


## Город, выросший до конца (city_growth.gd): все поручения сданы — проверки ниже про полный Эшвик
func full_state() -> Dictionary:
	var done: Array = []
	var quests: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/cities/s001.json"))["growth"]["quests"]
	for id in quests:
		for q in quests[id]:
			done.append(q["id"])
	return {"city_id": "s001", "growth": {"done": done, "taken": {}}, "left": true}


func _run() -> void:
	var city: Node2D = load("res://city/city_world.tscn").instantiate()
	root.add_child(city)
	var hero := Actor.new("hero", "Герой", false, 7)
	var bag: Dictionary = Trade.new_bag(60)
	city.enter("s001", hero, {"inventory": bag, "gate": "south", "state": full_state()})
	city.exit_requested.connect(func(c, g): exits.append([c, g]))
	await frames(5)
	ok(city.entered and city.map.radial() and city.map.w == 84 and city.map.h == 84 and city.map.cell_m == 1.0, "Эшвик: радиальный план 84×84 клетки по 1 м")
	ok(city.map.buildings.size() == 43 and city.npcs.size() == 29, "выросший город: 43 дома, 29 НПС (Storybook и кожевник)")
	ok(city.map.tile_at(city.hero_pos) in [CityMap.T.ROAD, CityMap.T.GRASS], "герой у южных ворот на дороге: %s" % city.hero_pos)
	city.clock.paused = true
	set_hour(city, 11.0)
	await frames(2)

	# Ходьба и стены
	var d: float = walk(city, Vector2.UP, 2.0)
	ok(d > 3.0, "идёт на север: %.1f м за 2 с" % d)
	# Круглая стена: изнутри у западной стены идти на запад — дальше стены не уйти
	var wall_r_m: float = float(city.def["wall_r"]) * city.map.cell_m
	city.hero_pos = city.map.center_m() + Vector2(-(wall_r_m - 4.0 * city.map.cell_m), 0.0)
	walk(city, Vector2.LEFT, 3.0)
	ok(city.hero_pos.distance_to(city.map.center_m()) < wall_r_m - city.map.cell_m * 0.5, "стена не пускает: %.1f м от центра" % city.hero_pos.distance_to(city.map.center_m()))
	# Внутрь дома только через дверь
	var shop: Dictionary = city.map.building_by_id("shop")
	var sr: Array = shop["rect"]
	var dc := Vector2i(shop["door"][0], shop["door"][1])
	var out := Vector2i(-1 if dc.x == sr[0] else (1 if dc.x == sr[0] + sr[2] - 1 else 0), -1 if dc.y == sr[1] else (1 if dc.y == sr[1] + sr[3] - 1 else 0))
	var along := Vector2i(absi(out.y), absi(out.x))
	var wc: Vector2i = dc + along * 2
	if city.map.at(wc.x, wc.y) != CityMap.T.WALL:
		wc = dc - along * 2
	city.hero_pos = city.map.center_of(wc + out)
	walk(city, -Vector2(out), 2.0)
	ok(city.map.building_at(city.hero_pos) < 0, "стена лавки не пускает")
	city.hero_pos = city.map.center_of(dc + out)
	walk(city, -Vector2(out), 1.5)
	ok(city.map.building_at(city.hero_pos) == int(shop["index"]), "в лавку через дверь")
	await frames(3)
	ok(city.discovered.has("shop"), "лавка отмечена найденной")
	await shot("t02_inside_shop.png")

	# НПС по распорядку днём
	for i in 600:
		await process_frame
		city._process(0.05)
	var trader: Dictionary = {}
	var guard: Dictionary = {}
	for n in city.npcs:
		if n["def"]["id"] == "trader":
			trader = n
		if n["def"]["id"] == "guard_1":
			guard = n
	ok(trader["pos"].distance_to(trader["work_pos"]) < 1.0, "торговка дошла до лотка: %s" % trader["pos"])
	ok(city._npc_on_duty_here(trader), "торговка на месте и торгует")

	# Торговля
	city.hero_pos = trader["pos"] + Vector2(0, 1.6)
	# Площадь маленького города тесная: прохожих на время проверки отводим в сторону
	for n in city.npcs:
		if n != trader and n["pos"].distance_to(city.hero_pos) < 3.0:
			n["pos"] += Vector2(0, 6)
	await frames(2)
	ok(city._nearest_npc() == trader, "рядом торговка: %s %s" % [String(city._nearest_npc().get("def", {}).get("id", "")), city._nearest_npc().get("pos", "")])
	var m0: int = bag["money"]
	ok(Trade.buy(bag, trader["stock"], "bread", hero) == "" and Trade.count(bag, "bread") == 1, "купил хлеб")
	ok(bag["money"] == m0 - Trade.buy_price("bread", hero), "деньги списаны: %d → %d" % [m0, bag["money"]])
	Trade.add(bag, "hide", 2)
	var m1: int = bag["money"]
	ok(Trade.sell(bag, trader["stock"], trader["buys"], "hide", hero) == "" and bag["money"] > m1, "продал шкуру")
	ok(Trade.sell(bag, trader["stock"], trader["buys"], "vegetables", hero) != "", "чего нет — не продать")
	city.open_trade(trader)
	await shot("t03_trade.png")
	city._close_panel()
	var hunger0: float = hero.res["hunger"]
	Trade.use(bag, "bread", hero)
	ok(hero.res["hunger"] > hunger0 and Trade.count(bag, "bread") == 0, "съел хлеб: сытость %.0f → %.0f" % [hunger0, hero.res["hunger"]])

	# Колодец
	hero.res["thirst"] = 30.0
	var wcells: Array = []
	for p in city.def["props"]:
		if p["kind"] == "well" and wcells.is_empty():
			wcells = p["cells"]
	city.hero_pos = city.map.center_of(Vector2i(wcells[1][0] + 1, wcells[1][1]))
	# Не interact(): житель с площади может оказаться ближе колодца, и E заговорит с ним
	ok(city._nearest_place().get("kind", "") == "water", "у колодца")
	city.use_place(city._nearest_place())
	ok(hero.res["thirst"] > 50.0, "напился из колодца: %.0f" % hero.res["thirst"])

	# Лечение у травницы
	var healer: Dictionary = {}
	for n in city.npcs:
		if n["def"]["id"] == "healer":
			healer = n
	ok(city._npc_on_duty_here(healer), "травница в лечебнице: %s → %s sleep=%s alive=%s h=%.1f" % [healer["pos"], healer["work_pos"], healer["actor"].sleeping, healer["actor"].alive, city.clock.hour_of_day()])
	hero.add_condition("laceration")
	var tries: int = 0
	while hero.has_condition("laceration") and tries < 10:
		city.heal(healer)
		tries += 1
	ok(not hero.has_condition("laceration"), "травница вылечила рваную рану за %d попыток" % tries)

	# Тайник: погреб под развалинами
	var cellar: Dictionary = {}
	for p in city.def["places"]:
		if p["id"] == "cellar":
			cellar = p
	city.hero_pos = city._place_pos(cellar) + Vector2(1.0, 0)
	var items0: int = bag["items"].size() + bag["money"]
	city.interact()
	ok(city.looted.has("cellar"), "погреб обыскан")
	var items1: int = bag["items"].size() + bag["money"]
	city.interact()
	ok(bag["items"].size() + bag["money"] == items1, "второй раз пусто")
	print("  найдено: ", bag)

	# Туман и исследование
	await frames(2)
	city._process(0.05)
	var ex: float = city.explored_fraction()
	ok(ex > 0.03 and ex < 1.0, "изведано %.0f %%" % (ex * 100.0))

	# Обзор днём
	city.hero_pos = city.map.center_m() + Vector2(0, 14.0)
	city._process(0.05)
	await shot("t01_day_square.png")
	city.toggle_map()
	await shot("t05_map.png")
	city.toggle_map()

	# Ночь: ворота заперты, стражник выпускает за плату
	set_hour(city, 23.0)
	city._process(0.05)
	ok(not city.gates_open(), "ночью ворота заперты")
	city.hero_pos = Vector2(city.def["gates"][0]["spawn"][0], city.def["gates"][0]["spawn"][1]) * city.map.cell_m
	walk(city, Vector2.DOWN, 4.0)
	ok(exits.is_empty(), "через запертые ворота не выйти")
	await shot("t04_night_gate.png")
	city.pay_gate(guard)
	city._process(0.05)
	ok(not city.map.closed_gates.has("south"), "после платы южные открыты")
	walk(city, Vector2.DOWN, 4.0)
	ok(exits.size() == 1 and exits[0] == ["s001", "south"], "выход через южные ворота: %s pos=%s tile=%d moving=%s" % [exits, city.hero_pos, city.map.tile_at(city.hero_pos), city.hero.can_move()])

	# Ночью НПС дома и спят
	city.leaving = false
	for i in 2400:
		city._process(0.05)
	var asleep: int = 0
	for n in city.npcs:
		if n["actor"].sleeping:
			asleep += 1
	ok(asleep >= 10, "ночью спят %d из 16" % asleep)

	# Сохранение
	var st: Dictionary = city.to_dict()
	var city2: Node2D = load("res://city/city_world.tscn").instantiate()
	root.add_child(city2)
	city2.enter("s001", hero, {"inventory": bag, "state": st})
	await frames(2)
	ok(city2.looted.has("cellar") and city2.discovered.has("shop"), "состояние города восстановлено")
	ok(city2.hero_pos.distance_to(city.hero_pos) < 0.01, "позиция героя восстановлена")
	ok(absf(city2.explored_fraction() - city.explored_fraction()) < 0.001, "туман восстановлен")
	city2.queue_free()

	# Через стену: у северной стены, чужак; стражник рядом — штраф и за ворота
	var city3: Node2D = load("res://city/city_world.tscn").instantiate()
	root.add_child(city3)
	var bag3: Dictionary = Trade.new_bag(40)
	var ex3: Array = []
	city3.exit_requested.connect(func(c, g): ex3.append(g))
	city3.enter("s001", hero, {"inventory": bag3, "settlement": {"id": "s001", "entry": "sneak", "side": "north"}, "state": full_state()})
	city3.clock.paused = true
	await frames(2)
	ok(city3.hero_pos.y < city3.map.center_m().y - (float(city3.def["wall_r"]) - 6.0) * city3.map.cell_m and city3.is_intruder(), "пролез у северной стены, чужак: %s" % city3.hero_pos)
	ok(city3.map.tile_at(city3.hero_pos) == CityMap.T.GRASS, "место у стены — трава")
	if shots != "":
		await shot("t06_sneak_north.png")
	var g2: Dictionary = {}
	for n in city3.npcs:
		if n["def"]["id"] == "guard_3":
			g2 = n
	g2["pos"] = city3.hero_pos + Vector2(3.0, 0.0)
	city3._process(0.05)
	ok(not city3.is_intruder() and bag3["money"] == 25, "стражник поймал: деньги %d" % bag3["money"])
	ok(ex3 == ["south"], "выведен за южные ворота: %s" % [ex3])
	city3.queue_free()
	# Чужак без стражи рядом через 2 часа становится своим
	var city4: Node2D = load("res://city/city_world.tscn").instantiate()
	root.add_child(city4)
	city4.enter("s001", hero, {"inventory": Trade.new_bag(40), "entry": "sneak", "side": "east", "state": full_state()})
	city4.clock.paused = true
	await frames(2)
	ok(city4.hero_pos.x > city4.map.size_m().x * 0.85 and city4.is_intruder(), "у восточной стены: %s" % city4.hero_pos)
	for n in city4.npcs:
		if n["def"].get("role", "") == "guard":
			n["actor"].set_sleep(true)
			n["def"] = n["def"].duplicate()
			n["def"]["hours"] = [0, 0]
	city4.clock.total_seconds += 2.5 * 3600.0
	city4._process(0.05)
	ok(not city4.is_intruder(), "через 2 часа уже не чужак")
	city4.queue_free()
	# Пойман у стены: казарма и штраф
	var city5: Node2D = load("res://city/city_world.tscn").instantiate()
	root.add_child(city5)
	var bag5: Dictionary = Trade.new_bag(10)
	city5.enter("s001", hero, {"inventory": bag5, "entry": "caught", "state": full_state()})
	await frames(2)
	ok(city5.map.building_at(city5.hero_pos) == int(city5.map.building_by_id("barracks")["index"]) and bag5["money"] == 0, "пойман: в казарме, штраф взят весь (10)")
	city5.queue_free()
	# Состояние, снятое при выходе, не двигает героя при новом входе
	var left: Dictionary = st.duplicate()
	left["left"] = true
	var city6: Node2D = load("res://city/city_world.tscn").instantiate()
	root.add_child(city6)
	city6.enter("s001", hero, {"inventory": bag, "state": left, "entry": "sneak", "side": "west"})
	await frames(2)
	ok(city6.hero_pos.x < city6.map.center_m().x - (float(city6.def["wall_r"]) - 6.0) * city6.map.cell_m and city6.discovered.has("shop"), "после выхода: вход у западной стены, находки на месте")
	city6.queue_free()

	print("city_checks: %d/%d" % [checks - fails, checks])
	quit(1 if fails > 0 else 0)

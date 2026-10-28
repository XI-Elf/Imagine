extends SceneTree
## Рост города (city/city_growth.gd, Huzzah 2026-10-23): в начале лачуга героя и общий дом на троих
## (глава, травница, кожевник); поручения двигают этапы, город перестраивается сразу, состояние сохраняется.
## godot --path game --rendering-driver opengl3 -s res://tests/city_growth_checks.gd

const Trade := preload("res://city/trade.gd")
const Growth := preload("res://city/city_growth.gd")

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


func npc(city: Node, id: String) -> Dictionary:
	for n in city.npcs:
		if String(n["def"]["id"]) == id:
			return n
	return {}


# Выполнить поручение «по-честному»: взять, набрать нужное, сдать
func do_quest(city: Node, n: Dictionary, q: Dictionary) -> void:
	city.take_quest(n, q)
	match String(q["kind"]):
		"walk":
			city.hero.distance_m += float(q["km"]) * 1000.0 + 1.0
		"win":
			city.test_wins += int(q["wins"])
		"bring":
			Trade.add(city.bag, String(q["item"]), int(q["n"]))
		"pay":
			city.bag["money"] = int(city.bag["money"]) + int(q["money"])
	city.turn_in(n, q)


func _run() -> void:
	var city: Node2D = load("res://city/city_world.tscn").instantiate()
	root.add_child(city)
	var hero := Actor.new("hero", "Герой", false, 11)
	var bag: Dictionary = Trade.new_bag(20)
	city.enter("s001", hero, {"inventory": bag, "gate": "south"})
	city.clock.paused = true
	await frames(3)

	# Форт: лачуга героя и общий дом на троих, развалины древные
	var houses: Array = city.map.buildings.filter(func(b): return b.get("kind", "") != "ruins")
	ok(city.stage == 0 and Growth.stage_name(city.full_def, 0) == "Форт", "начальный этап — Форт")
	ok(houses.size() == 2, "в начале два дома: %s" % [houses.map(func(b): return b["name"])])
	ok(not city.map.building_by_id("inn").is_empty() and city.map.building_by_id("inn")["name"] == "Общий дом", "общий дом есть")
	ok(city.map.building_by_id("quarter_house_24")["name"] == "Лачуга", "лачуга героя есть")
	var ids: Array = city.npcs.map(func(n): return String(n["def"]["id"]))
	ids.sort()
	ok(ids == ["healer", "posadnik", "tanner"], "сперва трое: глава, травница, кожевник: %s" % [ids])
	ok(city.npcs.all(func(n): return n["def"]["home"] == "inn"), "все трое живут в общем доме")
	ok(city.map.building_at(npc(city, "tanner")["home_pos"]) == int(city.map.building_by_id("inn")["index"]), "кожевник ночует в общем доме")
	ok(city.def["wall"] == "palisade", "стена — частокол")
	ok(city.map.building_at(npc(city, "posadnik")["work_pos"]) < 0 and city.map.is_free(npc(city, "posadnik")["work_pos"], 0.35), "глава днём на площади")
	ok(npc(city, "tanner")["stock"].has("leather_jacket") and npc(city, "tanner")["stock"].has("boots"), "кожевник продаёт куртку и сапоги")
	ok(npc(city, "posadnik")["stock"].has("linen_shirt"), "рубаху пока продаёт глава")
	ok(city.map.building_by_id("smithy").is_empty() and city.map.building_by_id("hall").is_empty(), "кузницы и чертога ещё нет")

	# Лежанка в лачуге
	var bed: Dictionary = {}
	for p in city.def["places"]:
		if p["id"] == "hero_bed":
			bed = p
	ok(not bed.is_empty() and city.map.building_at(city._place_pos(bed)) == int(city.map.building_by_id("quarter_house_24")["index"]), "лежанка внутри лачуги")
	city.use_place(bed)
	ok(hero.sleeping, "на лежанке герой спит")
	hero.set_sleep(false)

	# Доска объявлений — этап и поручения
	var board: Dictionary = {}
	for p in city.def["places"]:
		if p["id"] == "notice_board":
			board = p
	var bt: String = city._board_text(board)
	ok(bt.contains("Форт") and bt.contains("Скобы для частокола"), "доска: этап и поручения")

	# Поручение главы: принести лом. Без лома не сдать
	var elder: Dictionary = npc(city, "posadnik")
	var q: Dictionary = Growth.current(city.full_def, city.growth, "posadnik")
	ok(q.get("id", "") == "elder_1" and q["kind"] == "bring", "у главы первое поручение — принести лом")
	city.take_quest(elder, q)
	ok(Growth.taken(city.growth, q) and not Growth.ready(city.growth, q, bag, city.hero_km(), city.battles_won()), "взято, но лома нет")
	city.turn_in(elder, q)
	ok(Growth.points(city.growth) == 0, "без лома не сдаётся")
	Trade.add(bag, "scrap", 3)
	var m0: int = int(bag["money"])
	city.turn_in(elder, q)
	ok(Growth.points(city.growth) == 1 and Trade.count(bag, "scrap") == 1 and int(bag["money"]) == m0 + int(q["reward"]), "сдано: лом забран, награда выдана")
	ok(Growth.current(city.full_def, city.growth, "posadnik").is_empty() and Growth.waiting(city.full_def, city.growth, "posadnik"), "следующее поручение главы ждёт роста")

	# Травница: пройти 3 км; кожевник: победа в бою
	var hq: Dictionary = Growth.current(city.full_def, city.growth, "healer")
	city.take_quest(npc(city, "healer"), hq)
	hero.distance_m += 2000.0
	ok(not Growth.ready(city.growth, hq, bag, city.hero_km(), city.battles_won()), "2 км из 3 — рано")
	hero.distance_m += 1100.0
	city.turn_in(npc(city, "healer"), hq)
	ok(Growth.points(city.growth) == 2, "травы найдены")
	var tq: Dictionary = Growth.current(city.full_def, city.growth, "tanner")
	city.test_wins = 4
	city.take_quest(npc(city, "tanner"), tq)
	ok(not Growth.ready(city.growth, tq, bag, city.hero_km(), city.battles_won()), "старые победы не в счёт")
	city.test_wins += 1
	var hero_was: Vector2 = city.hero_pos
	city.turn_in(npc(city, "tanner"), tq)

	# Деревня: кузнец, торговка, стражник и их дома появились сразу
	ok(city.stage == 1, "три поручения — этап Деревня")
	ok(city._panel_text.text.contains("Деревня"), "в разговоре сказано, что город вырос")
	for id in ["smith", "trader", "guard_1"]:
		ok(not npc(city, id).is_empty(), "пришёл %s" % id)
	ok(not city.map.building_by_id("smithy").is_empty() and not city.map.building_by_id("shop").is_empty(), "кузница и лавка стоят")
	ok(npc(city, "posadnik")["def"]["home"] == "inn" and npc(city, "healer")["def"]["home"] == "inn", "основатели пока в общем доме")
	ok(city.map.is_free(city.hero_pos, 0.35), "герой не в стене после перестройки (%s → %s)" % [hero_was, city.hero_pos])
	ok(not Growth.current(city.full_def, city.growth, "smith").is_empty(), "у кузнеца есть поручение")

	# Сохранение и новый вход: этап и взятое поручение на месте
	var sq: Dictionary = Growth.current(city.full_def, city.growth, "smith")
	city.take_quest(npc(city, "smith"), sq)
	var st: Dictionary = city.to_dict()
	var city2: Node2D = load("res://city/city_world.tscn").instantiate()
	root.add_child(city2)
	city2.enter("s001", hero, {"inventory": bag, "state": st})
	city2.clock.paused = true
	await frames(2)
	ok(city2.stage == 1 and city2.npcs.size() == city.npcs.size(), "после загрузки — Деревня, жителей %d" % city2.npcs.size())
	ok(Growth.taken(city2.growth, sq), "взятое поручение кузнеца помнится")
	city2.queue_free()

	# Всё до конца: каждое поручение по порядку
	for pass_i in 10:
		for n in city.npcs.duplicate():
			var cq: Dictionary = Growth.current(city.full_def, city.growth, String(n["def"]["id"]))
			if not cq.is_empty():
				do_quest(city, npc(city, String(n["def"]["id"])), cq)
	ok(city.stage == 4 and Growth.stage_name(city.full_def, 4) == "Крупный город", "все 18 поручений — город вырос до конца")
	ok(city.map.buildings.size() == 43 and city.npcs.size() == 29, "43 дома, 29 жителей: %d, %d" % [city.map.buildings.size(), city.npcs.size()])
	ok(city.def["wall"] == "stone" and city.map.building_by_id("inn")["name"].begins_with("Таверна"), "каменная стена, общий дом снова таверна")
	ok(not npc(city, "posadnik")["def"].has("work_cell") and city.map.building_at(npc(city, "posadnik")["work_pos"]) == int(city.map.building_by_id("hall")["index"]), "глава работает в чертоге")
	ok(npc(city, "posadnik")["def"]["home"] == "hall" and npc(city, "tanner")["def"]["home"] == "house_2", "глава в чертоге, кожевник в дубильне")
	# Все дома достижимы от ворот
	var gate: Vector2 = Vector2(city.def["gates"][0]["spawn"][0], city.def["gates"][0]["spawn"][1]) * city.map.cell_m
	var bad: Array = []
	for b in city.map.buildings:
		if b.get("kind", "") == "ruins":
			continue
		var door: Vector2 = city.map.center_of(Vector2i(b["door"][0], b["door"][1]))
		if city.map.path(gate, door).is_empty():
			bad.append(b["id"])
	ok(bad.is_empty(), "от ворот дойти до каждой двери: %s" % [bad])

	# Миниатюра на карте: этапы по тому же описанию
	var plan: Dictionary = city.full_def
	ok(Growth.view(plan, 0)["buildings"].size() == 4 and Growth.view(plan, 4)["buildings"].size() == 43, "миниатюра: 4 постройки в начале, 43 в конце")

	city.queue_free()
	print("city_growth_checks: %d/%d" % [checks - fails, checks])
	quit(1 if fails > 0 else 0)

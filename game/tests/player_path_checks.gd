extends SceneTree
## Сквозной путь игрока (вопрос Q22, Huzzah 2026-10-24): новая игра → создание героя → у ворот Чёрнославля →
## город и поручения → лом в руинах → нож у кожевника → бой → сдача поручений и рост города → сохранение → загрузка.
## Бот идёт через те же функции, что зовут кнопки и клавиши. Сокращения бота: километры для поручений «пройти»
## прибавляются к счётчику героя, к руинам он переносится, а бой за героя ведёт ИИ боя.
## godot --path game --rendering-driver opengl3 -s res://tests/player_path_checks.gd
## Из сборки: godot --main-pack AmberWorld.pck --headless -s res://tests/player_path_checks.gd

const WorldSave := preload("res://world_save.gd")
const Growth := preload("res://city/city_growth.gd")
const Ruins := preload("res://world/ruins.gd")
const Trade := preload("res://city/trade.gd")
var fails: int = 0
var checks: int = 0


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
	print("ok: " if cond else "FAIL: ", what)


func frames(n: int) -> void:
	for i in n:
		await process_frame


func _initialize() -> void:
	_run()


func wait_worlds(W: Node) -> void:
	await frames(2)
	while W.busy:
		await process_frame
	await frames(2)


func load_game(slot: String) -> Node2D:
	Engine.set_meta("aw_load", slot)
	var game: Node2D = load("res://game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	var t0: int = Time.get_ticks_msec()
	while not game.ready_done and Time.get_ticks_msec() - t0 < 120000:
		await process_frame
	await frames(5)
	return game


func npc(city: Node, id: String) -> Dictionary:
	for n in city.npcs:
		if n["def"]["id"] == id:
			return n
	return {}


func enter_city(W: Node, game: Node2D) -> Node:
	W._on_enter_requested(game.settlements.get_settlement("s001"))
	await wait_worlds(W)
	return W.current_node() if W.current_kind() == "city" else null


func _run() -> void:
	var W: Node = root.get_node("Worlds")
	# ---- Новая игра: экран создания героя
	Engine.set_meta("aw_intro_done", true)
	var menu: Control = load("res://main_menu.tscn").instantiate()
	root.add_child(menu)
	await frames(3)
	menu._on_new_game()
	await frames(3)
	var cr: CanvasLayer = menu._creator
	cr.randomize_all()
	cr.name_edit.text = "Путник"
	cr._refresh()
	var got: Array = []
	cr.finished.disconnect(menu._on_hero_created)
	cr.finished.connect(func(p): got.append(p))
	cr._on_create()
	ok(got.size() == 1, "герой создан на экране создания")
	Engine.set_meta("aw_new_hero", got[0] if got.size() > 0 else {})
	menu.queue_free()
	await frames(2)

	var game: Node2D = await load_game("")
	var cast: Node2D = game.cast
	ok(not cast.hero.is_empty() and cast.hero["actor"].display_name == "Путник", "новая игра с этим героем")
	var a: Actor = cast.hero["actor"]
	var gate: Vector2 = game.settlements.spawn_point()
	ok(cast.hero["pos"].distance_to(gate) < 600.0, "герой у ворот города")
	ok(W.inventory["items"].get("water_flask", 0) == 2 and W.inventory["equipped"].get("body", "") == "leather_jacket", "на старте куртка и две фляги")

	# ---- Город: этап «Острог», берём все поручения
	var city: Node = await enter_city(W, game)
	ok(city != null and city.city_id == "s001", "вход в Чёрнославль")
	if city == null:
		return _done()
	ok(city.stage == 0 and Growth.stage_name(city.full_def, 0) == "Острог", "город на этапе «Острог»")
	ok(npc(city, "tanner")["stock"].has("knife"), "нож у кожевника с «Острога» (Q02)")
	var taken: Array = []
	for id in ["posadnik", "healer", "tanner"]:
		for q in Growth.available(city.full_def, city.growth, id):
			city.take_quest(npc(city, id), q)
			taken.append(q["id"])
	ok(taken.size() == 6, "взято 6 поручений основателей (3 основных и 3 запасных): %s" % [taken])
	await W.leave()
	await wait_worlds(W)
	ok(W.current_kind() == "overworld", "вышли из города")

	# ---- Дорога: пройдено 3 км (сокращение бота)
	a.distance_m += 3100.0

	# ---- Руины на карте: лом (Q04)
	var hp: Vector2 = cast.hero["pos"]
	var sites: Array = Ruins.in_rect(game, Rect2(hp - Vector2(8000, 8000), Vector2(16000, 16000)))
	ok(not sites.is_empty(), "руины в 8 км от города: %d" % sites.size())
	var scrap0: int = Trade.count(W.inventory, "scrap")
	for s in sites:
		if Trade.count(W.inventory, "scrap") - scrap0 >= 2:
			break
		cast.hero["pos"] = s["pos"] + Vector2(5, 0)
		var near: Dictionary = Ruins.near(game, cast.hero["pos"])
		if not near.is_empty():
			print("  ", cast.search_ruins(near))
	ok(Trade.count(W.inventory, "scrap") - scrap0 >= 2, "в руинах найден лом: %d" % (Trade.count(W.inventory, "scrap") - scrap0))
	cast.hero["pos"] = hp

	# ---- Снова в город: сдать два самых дорогих поручения (лом посаднику и «пройти» травнице: 20 монет,
	# 2 очка — город ещё «Острог», Q30) и купить нож. Нож стоит 15 × (1,3 − 0,03 × (Хар − 4)): при Харизме
	# ниже 4 (случайные черты) 20 монет не хватает, поэтому бот берёт героя хотя бы с Харизмой 4
	city = await enter_city(W, game)
	if a.stat("cha") < 4:
		a.set_stat("cha", 4)
	var first_ids: Array = ["elder_1", "healer_1"]
	for id in ["posadnik", "healer"]:
		for q in Growth.available(city.full_def, city.growth, id):
			if first_ids.has(q["id"]) and Growth.ready(city.growth, q, city.bag, city.hero_km(), city.battles_won()):
				city.turn_in(npc(city, id), q)
	ok(Growth.points(city.growth) == 2 and city.stage == 0, "сданы лом и «пройти»: очков %d, денег %d, нож за %d, этап «Острог»" % [Growth.points(city.growth), W.inventory["money"], Trade.buy_price("knife", a)])
	ok(Trade.buy(W.inventory, npc(city, "tanner")["stock"], "knife", a) == "" and Trade.count(W.inventory, "knife") == 1, "куплен нож у кожевника")
	await W.leave()
	await wait_worlds(W)

	# ---- Бой с бандитами и ножом у «Острога»: бандит один (Q30 B), ИИ ведёт героя, до победы (не больше 6 боёв).
	# После гибели бот, как игрок, загружает сохранение
	ok(WorldSave.write(game, true), "сохранение перед боем")
	var pre: String = WorldSave.latest_slot()
	var wins0: int = W.battles_won
	var scrap_b: int = Trade.count(W.inventory, "scrap")
	var money_b: int = int(W.inventory["money"])
	var tries: int = 0
	var killed: int = 0
	while W.battles_won == wins0 and tries < 6:
		tries += 1
		killed = 0
		a.res["health"] = a.max_of("health")
		W.start_battle({"group": "bandits"})
		await wait_worlds(W)
		var b: Node = W.current_node()
		ok(W.is_battle() and b.has_method("prep_confirm"), "бой %d начался" % tries)
		if tries == 1:
			ok(b.core.all.filter(func(c): return c.team == 1).size() == 1, "у «Острога» бандит один (Q30): %d" % b.core.all.filter(func(c): return c.team == 1).size())
		# ИИ боя ходит за всех сразу, без пауз интерфейса
		b.core.auto_ai = true
		for c in b.core.all:
			c.controlled = false
		b.prep_confirm()
		var g: int = 0
		while b.core.outcome == "" and g < 600:
			b.core.run_ai_turn()
			g += 1
		print("  бой %d: %s, ходов %d, раундов %d, герой жив %s, враги %s" % [tries, b.core.outcome, g, b.core.round_n, a.alive, b.core.all.filter(func(c): return c.team == 1).map(func(c): return c.title)])
		killed += b.core.all.filter(func(c): return c.team == 1 and c.dead and c.human).size()
		await frames(2)
		b.leave()
		await wait_worlds(W)
		if not a.alive:
			game.queue_free()
			await frames(5)
			game = await load_game(pre)
			cast = game.cast
			a = cast.hero["actor"]
	WorldSave.delete(pre)
	ok(W.battles_won > wins0 and a.alive, "победа в бою с ножом за %d боёв" % tries)
	ok(W.current_kind() == "overworld", "после боя — на карте")
	# Добыча — только с убитых (сбежавший или сдавшийся ничего не оставляет)
	ok(killed == 0 or int(W.inventory["money"]) > money_b, "убито %d, с бандитов — деньги: +%d, лом: +%d (Q04)" % [killed, int(W.inventory["money"]) - money_b, Trade.count(W.inventory, "scrap") - scrap_b])

	# ---- Сдать остальные «пройти» и «принести»: город растёт до «Слободы» без поручений на бой (Q03)
	city = await enter_city(W, game)
	for id in ["posadnik", "healer", "tanner"]:
		for q in Growth.available(city.full_def, city.growth, id):
			if q["kind"] in ["walk", "bring"] and Growth.ready(city.growth, q, city.bag, city.hero_km(), city.battles_won()):
				city.turn_in(npc(city, id), q)
	ok(Growth.points(city.growth) >= 3, "сданы поручения «пройти» и «принести»: очков %d, денег %d" % [Growth.points(city.growth), W.inventory["money"]])
	ok(city.stage >= 1, "город вырос до «Слободы» без поручений на бой (запасные поручения, Q03)")

	# ---- Сдать бой кожевнику
	var tq: Dictionary = Growth.current(city.full_def, city.growth, "tanner")
	var pts: int = Growth.points(city.growth)
	if not tq.is_empty() and tq["kind"] == "win":
		city.turn_in(npc(city, "tanner"), tq)
	ok(Growth.points(city.growth) == pts + 1, "поручение «победить» сдано")
	var stage_now: int = city.stage
	var done_now: Array = city.growth["done"].duplicate()

	# ---- Сохранение в городе и загрузка
	ok(WorldSave.write(game, true), "сохранение в городе")
	var slot: String = WorldSave.latest_slot()
	game.queue_free()
	await frames(5)
	game = await load_game(slot)
	await wait_worlds(W)
	ok(W.current_kind() == "city", "после загрузки — в городе")
	city = W.current_node()
	ok(city != null and city.stage == stage_now and city.growth["done"] == done_now, "рост города восстановлен: этап %d, сдано %d" % [stage_now, done_now.size()])
	ok(Trade.count(W.inventory, "knife") == 1 and game.cast.hero["actor"].display_name == "Путник", "нож и герой на месте")
	WorldSave.delete(slot)
	_done()


func _done() -> void:
	print("PLAYER PATH CHECKS: %d/%d" % [checks - fails, checks])
	quit(1 if fails > 0 else 0)

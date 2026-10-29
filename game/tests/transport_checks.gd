extends SceneTree
## Кінь і віз (питання Q16, Huzzah 2026-10-24): правила, купівля, швидкість і вантаж, карта, місто, бій,
## збереження. Потрібен екран (xvfb, --rendering-driver opengl3):
## godot --path game --rendering-driver opengl3 -s res://tests/transport_checks.gd -- [тека_для_знімків]

const Transport := preload("res://characters/transport.gd")
const Trade := preload("res://city/trade.gd")
const Growth := preload("res://city/city_growth.gd")
const R := preload("res://characters/actor_rules.gd")
const WorldSave := preload("res://world_save.gd")

var fails: int = 0
var checks: int = 0
var shots: String = ""
var W: Node


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


func _run() -> void:
	_rules()
	_shop()
	_speed_and_load()
	await _in_game()
	print("transport_checks: %d/%d ok%s" % [checks - fails, checks, "" if fails == 0 else " | FAIL %d" % fails])
	quit(1 if fails > 0 else 0)


func _rules() -> void:
	var bag: Dictionary = Trade.new_bag(0)
	ok(Transport.pack_kg(bag) == 0.0 and Transport.mode(bag) == "", "без лошади: пешком, животные ничего не везут")
	ok(Transport.toggle(bag).begins_with("Лошади нет") and not bag.has("ride"), "R без лошади — подсказка, где купить")
	Trade.add(bag, "cart")
	ok(Transport.pack_kg(bag) == 0.0, "повозка без лошади стоит")
	Trade.add(bag, "horse")
	Trade.add(bag, "cart", -1)
	ok(Transport.pack_kg(bag) == 60.0, "лошадь везёт 60 кг вьюков")
	ok(Transport.mode(bag) == "", "купил — пока ведёт в поводу")
	ok(Transport.toggle(bag) == "Верхом" and Transport.mode(bag) == "horse", "R — верхом")
	Trade.add(bag, "cart")
	ok(Transport.mode(bag) == "cart" and Transport.pack_kg(bag) == 310.0, "с повозкой — едет на ней, везут 310 кг")
	ok(Transport.toggle(bag).begins_with("Пешком") and Transport.mode(bag) == "", "R ещё раз — пешком")
	ok(Trade.weight(bag) == 0.0, "лошадь и повозка не весят в сумке")


func _shop() -> void:
	var a := Actor.new("hero", "Герой", false, 3)
	var bag: Dictionary = Trade.new_bag(500)
	var stock: Dictionary = {"horse": 2, "cart": 2}
	ok(Trade.buy(bag, stock, "cart", a) == "Сначала нужна лошадь", "повозку без лошади не продают")
	ok(Trade.buy(bag, stock, "horse", a) == "", "лошадь куплена за %d" % Trade.buy_price("horse", a))
	ok(Trade.buy(bag, stock, "horse", a) == "Уже есть", "вторую лошадь не продают")
	ok(Trade.buy(bag, stock, "cart", a) == "", "повозка куплена за %d" % Trade.buy_price("cart", a))
	ok(Trade.sell(bag, stock, [], "horse", a) == "" and Trade.count(bag, "horse") == 0, "лошадь можно продать обратно")
	# Хто продає: торговка й коваль, з етапу «Село»
	var def: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/cities/s001.json"))
	var who: Dictionary = {}
	for st in [0, 1]:
		for n in Growth.view(def, st)["npcs"]:
			for id in ["horse", "cart"]:
				if int(n.get("stock", {}).get(id, 0)) > 0:
					who["%s@%d" % [id, st]] = n["id"]
	ok(not who.has("horse@0") and not who.has("cart@0"), "в «Форте» лошадей и повозок нет")
	ok(who.get("horse@1", "") == "trader" and who.get("cart@1", "") == "smith", "в «Деревне» лошадь у торговки, повозка у кузнеца: %s" % who)
	var wish: int = Trade.buy_price("horse", a) + Trade.buy_price("cart", a)
	ok(wish > 40 and wish < 250, "лошадь с повозкой — цель на несколько поручений: %d монет" % wish)


func _speed_and_load() -> void:
	var a := Actor.new("hero", "Герой", false, 4)
	var env: Dictionary = {"biome": 4, "temp_c": 15.0}
	var walk: float = a.calculate_speed(env)
	a.mount = "horse"
	var ride: float = a.calculate_speed(env)
	a.mount = "cart"
	var drive: float = a.calculate_speed(env)
	ok(ride > walk * 2.4 and drive > walk * 1.5 and drive < ride, "пустошь: пешком %.1f, верхом %.1f, повозка %.1f км/ч" % [walk, ride, drive])
	ok(not a.can_run(), "верхом не бегают (Shift)")
	var mtn: Dictionary = {"biome": 6, "temp_c": 5.0}
	a.mount = "cart"
	var cart_m: float = a.calculate_speed(mtn)
	a.mount = "horse"
	var horse_m: float = a.calculate_speed(mtn)
	a.mount = ""
	var walk_m: float = a.calculate_speed(mtn)
	ok(cart_m < walk_m and horse_m > walk_m, "горы: повозка %.1f < пешком %.1f < верхом %.1f км/ч" % [cart_m, walk_m, horse_m])
	# Вантаж: 60 кг брухту пішки — стоїть, з конем і возом — їде
	var cap0: float = a.carry_capacity()
	a.carried_kg = cap0 * 2.0
	ok(a.calculate_speed(env) == 0.0, "двойной перегруз пешком — стоит (%.0f кг из %.0f)" % [a.carried_kg, cap0])
	a.pack_kg = 310.0
	ok(is_equal_approx(a.carry_capacity(), cap0 + 310.0) and a.overload_percent() == 0.0, "с лошадью и повозкой тот же груз — без перегруза")
	a.mount = "cart"
	ok(a.calculate_speed(env) > walk, "и повозка едет")
	# Їзда витрачає менше енергії й навчає верхової їзди
	var b := Actor.new("b", "Б", false, 5)
	var c := Actor.new("c", "В", false, 5)
	c.mount = "horse"
	for x in [b, c]:
		x.moving = true
		x.tick(3600.0, env)
	ok(c.res["energy"] > b.res["energy"], "час в седле — энергии меньше трат: %.1f против %.1f" % [c.res["energy"], b.res["energy"]])
	c.note_travel(3000.0, env)
	b.note_travel(3000.0, env)
	ok(c.xp > 0.0 and b.xp > 0.0, "3 км пути — опыт персонажу и верхом, и пешком")


func _in_game() -> void:
	W = root.get_node_or_null("Worlds")
	W.test_doubles = {"city": load("res://tests/doubles/city_stub.gd"), "battle": load("res://tests/doubles/battle_stub.gd")}
	Engine.set_meta("aw_load", "")
	var game: Node2D = load("res://game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	var t0: int = Time.get_ticks_msec()
	while not game.ready_done and Time.get_ticks_msec() - t0 < 120000:
		await process_frame
	await frames(3)
	var cast: Node2D = game.cast
	ok(cast.transport != null, "транспорт подключён к героям карты")
	game.cam_pos = Vector2(20812.0, 18000.0)
	cast.spawn_hero(game.cam_pos)
	var hb: Dictionary = cast.hero
	var hero: Actor = hb["actor"]
	W.inventory["items"].erase("horse")
	game.zoom = 40.0
	await frames(3)
	ok(cast.transport.hud.text == "", "без лошади строки транспорта нет")
	_press_r()
	await frames(2)
	ok(hero.mount == "", "R без лошади ничего не меняет")
	Trade.add(W.inventory, "horse")
	await frames(2)
	ok(hero.pack_kg == 60.0 and hero.mount == "", "купленная лошадь идёт в поводу и везёт вьюки")
	ok(cast.transport.hud.text.contains("R — сесть"), "строка: %s" % cast.transport.hud.text)
	await shot("h01_horse_led.png")
	_press_r()
	await frames(2)
	ok(hero.mount == "horse" and bool(W.inventory.get("ride", false)), "R — верхом")
	ok(cast.transport.rider_lift(40.0) > 0.0, "в седле фигурка героя выше")
	var start: Vector2 = hb["pos"]
	Input.action_press("ui_right")
	await create_timer(1.5).timeout
	Input.action_release("ui_right")
	var rode: float = hb["pos"].distance_to(start)
	await shot("h02_horse_ride.png")
	_press_r()
	await frames(2)
	start = hb["pos"]
	Input.action_press("ui_left")
	await create_timer(1.5).timeout
	Input.action_release("ui_left")
	var walked: float = hb["pos"].distance_to(start)
	ok(rode > walked * 1.8, "верхом за 1,5 с %.0f м, пешком %.0f м" % [rode, walked])
	Trade.add(W.inventory, "cart")
	Trade.add(W.inventory, "scrap", 40)
	_press_r()
	await frames(2)
	ok(hero.mount == "cart" and hero.pack_kg == 310.0, "с повозкой — на повозке, везут 310 кг")
	ok(is_equal_approx(hero.carried_kg, Trade.weight(W.inventory)), "вес сумки на карте считается сразу (лом из руин тоже)")
	ok(hero.overload_percent() == 0.0, "60 кг лома с повозкой — без перегруза")
	Input.action_press("ui_right")
	await create_timer(0.5).timeout
	Input.action_release("ui_right")
	await shot("h03_cart.png")
	game.zoom = 0.4
	await shot("h04_far.png")
	game.zoom = 40.0

	# Місто: там пішки, вантаж при ньому; інвентар не показує й не викидає коня
	await W.enter_city("t1", {"return_pos": hb["pos"], "settlement": {"id": "t1", "name": "Проверочный"}, "stub": true})
	await frames(3)
	ok(W.current_kind() == "city" and hero.mount == "" and hero.pack_kg == 310.0, "в городе пешком, лошадь с повозкой при герое")
	var win: CanvasLayer = cast.window
	win.inv_filter = "all"
	win.inv_drop_armed = true
	win.drop_all()
	ok(Trade.count(W.inventory, "horse") == 1 and Trade.count(W.inventory, "cart") == 1 and Trade.count(W.inventory, "scrap") == 0, "«Бросить всё» не бросает лошадь и повозку")
	var Inv: GDScript = load("res://characters/inventory_view.gd")
	var iv: Control = Inv.new()
	iv.bag = W.inventory
	ok(not iv.shown_items().has("horse") and not iv.shown_items().has("cart"), "в сетке сумки лошади и повозки нет")
	iv.free()
	await W.start_battle({"return_pos": hb["pos"], "stub": true, "enemies": [Actor.new("bandit_1", "Разбойник", true, 7)]})
	await frames(2)
	var battle: Node = W.current_node()
	ok(battle.req["allies"] == [hero] and hero.mount == "", "в бою лошадь не участвует, герой пеший")
	battle.finish("win")
	while W.busy or W.current_kind() == "battle":
		await process_frame
	W.leave({})
	while W.busy or W.current_kind() != "overworld":
		await process_frame
	await frames(3)
	ok(hero.mount == "cart", "вышел из города — снова на повозке")

	# Збереження: кінь, віз і «верхи» — у сумці
	ok(WorldSave.write(game, true), "сохранение записано")
	var saved: Dictionary = WorldSave.read(WorldSave.latest_slot())
	var inv: Dictionary = saved.get("worlds", {}).get("inventory", {})
	ok(int(inv.get("items", {}).get("horse", 0)) == 1 and int(inv.get("items", {}).get("cart", 0)) == 1 and bool(inv.get("ride", false)), "в сейве лошадь, повозка и посадка")


func _press_r() -> void:
	var e := InputEventKey.new()
	e.physical_keycode = KEY_R
	e.keycode = KEY_R
	e.pressed = true
	Input.parse_input_event(e)
	var u := InputEventKey.new()
	u.physical_keycode = KEY_R
	u.keycode = KEY_R
	Input.parse_input_event(u)

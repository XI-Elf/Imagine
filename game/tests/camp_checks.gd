extends SceneTree
## Табір у полі за мотивами виживання (Huzzah 2026-10-29, механіки 1, 2, 4, 6, 8): вогнище й готування, розбирання туш,
## знос і лагодження, сон в укритті. godot --path game --rendering-driver opengl3 -s res://tests/camp_checks.gd -- [тека_для_знімків]

const Trade := preload("res://city/trade.gd")
const Wear := preload("res://characters/wear.gd")
const Enc := preload("res://battle/encounters.gd")

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


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	shots = args[0] if args.size() > 0 else ""
	_wear()
	_run()


# Знос без сцени
func _wear() -> void:
	var bag: Dictionary = Trade.new_bag(100)
	Trade.add(bag, "boots")
	Trade.add(bag, "knife")
	bag["equipped"] = {"feet": "boots"}
	bag["battle_loadout"] = ["knife"]
	for i in 100:
		Wear.on_km(bag)
	ok(Wear.cond(bag, "boots") < 70.0 and Wear.cond(bag, "boots") > 60.0, "100 км: сапоги %.0f %%" % Wear.cond(bag, "boots"))
	Wear.on_battle(bag)
	ok(Wear.cond(bag, "knife") < 100.0, "бой изнашивает нож")
	ok(Wear.master_of("boots") == "tanner" and Wear.master_of("knife") == "smith" and Wear.master_of("linen_shirt") == "weaver", "кто чинит что")
	var fee: int = Wear.repair_fee(bag, "boots")
	var t: String = Wear.repair_at(bag, "tanner")
	ok(Wear.cond(bag, "boots") == 100.0 and int(bag["money"]) == 100 - fee, "кожевник починил сапоги за %d" % fee)
	var msgs: PackedStringArray = []
	for i in 400:
		msgs.append_array(Wear.on_km(bag))
	ok(Trade.count(bag, "boots") == 0 and not bag["equipped"].has("feet") and msgs.size() == 1, "сапоги развалились: %s" % [msgs])
	Trade.add(bag, "trousers")
	bag["equipped"]["legs"] = "trousers"
	for i in 200:
		Wear.on_km(bag)
	Trade.add(bag, "repair_kit")
	var c0: float = Wear.cond(bag, "trousers")
	Wear.repair_with_kit(bag)
	ok(Wear.cond(bag, "trousers") > c0 and Trade.count(bag, "repair_kit") == 0, "набор подлатал штаны")


func _run() -> void:
	var game: Node2D = load("res://game.tscn").instantiate()
	root.add_child(game)
	var t0: int = Time.get_ticks_msec()
	while not game.ready_done and Time.get_ticks_msec() - t0 < 120000:
		await process_frame
	var wm: Node = root.get_node_or_null("Worlds")
	if wm != null:
		wm.idle_attacks = false
	var t: Node = root.get_node_or_null("Tutorial")
	if t != null:
		t.enabled = false
	var cast: Node2D = game.cast
	cast.spawn_hero(Vector2(20812.0, 18000.0))
	var hero: Dictionary = cast.hero
	var a: Actor = hero["actor"]
	var bag: Dictionary = cast._inventory()
	var camp: CanvasLayer = cast.camp
	camp.rng.seed = 5
	game.zoom = 3.0

	# Вогнище
	ok(camp.light_fire().begins_with("Нечем"), "без дров костёр не развести")
	Trade.add(bag, "brushwood", 3)
	ok(camp.light_chance() == 0.0, "без кремня и факела — нечем высечь огонь")
	Trade.add(bag, "flint", 1)
	var lit: bool = false
	for i in 20:
		camp.light_fire()
		if camp.fire_lit():
			lit = true
			break
	ok(lit and Trade.count(bag, "brushwood") == 2, "костёр горит, хворост ушёл")
	ok(camp.near_fire(hero["pos"]), "герой у огня")
	var left: float = camp.fire_left_h()
	camp.add_wood()
	ok(camp.fire_left_h() > left + 1.5, "подбросил дров")

	# Готування
	ok(camp.cook_blocker("roast_meat") != "", "мяса нет — жарить нечего")
	Trade.add(bag, "raw_meat", 6)
	var got: int = 0
	var charred: int = 0
	for i in 6:
		camp.cook("roast_meat")
	got = Trade.count(bag, "roasted_meat")
	charred = Trade.count(bag, "charred_food")
	ok(got + charred == 6 and got > 0, "жарка: %d готово, %d подгорело" % [got, charred])
	Trade.add(bag, "roots", 2)
	Trade.add(bag, "water_flask", 1)
	var before: float = game.clock.total_seconds
	camp.cook("stew_roots")
	ok(Trade.count(bag, "field_stew") + Trade.count(bag, "charred_food") > charred and game.clock.total_seconds - before >= 2400.0, "похлёбка: 40 минут у котелка")
	Trade.add(bag, "wild_herbs", 2)
	Trade.add(bag, "water_flask", 1)
	ok(camp.cook("decoction").begins_with("Готово") and Trade.count(bag, "herbal_decoction") == 1, "отвар из диких трав")

	# Сон і укриття
	camp.open()
	await shot("k01_camp.png")
	ok(camp.is_open() and cast.hold_hero, "K: панель лагеря, герой стоит")
	camp.close()
	a.set_sleep(true)
	camp.tick()
	ok(a.has_buff("by_fire") and a.has_buff("sleep_open"), "сон у огня на голой земле")
	var e_open: float = a.mult("sleep_energy")
	Trade.add(bag, "tent", 1)
	camp.tick()
	ok(a.has_buff("shelter_tent") and not a.has_buff("sleep_open") and a.mult("sleep_energy") > e_open, "в палатке спится лучше")
	var env := {"biome": 3, "night": true}
	var c_fire: float = Enc.concealment(a, env)
	camp.put_out()
	camp.tick()
	ok(not a.has_buff("by_fire") and Enc.concealment(a, env) > c_fire, "огонь ночью выдаёт лагерь")
	a.set_sleep(false)
	camp.tick()
	ok(not a.has_buff("shelter_tent"), "проснулся — палатка не действует")

	# Розбирання туш
	Trade.add(bag, "knife", -Trade.count(bag, "knife"))
	var r0: Dictionary = camp.butcher(["wolf", "wolf"])
	ok(not r0["found"].has("hide") and int(r0["found"].get("raw_meat", 0)) == 2, "без ножа: мяса меньше, шкур нет: %s" % r0["found"])
	Trade.add(bag, "knife", 1)
	var r1: Dictionary = camp.butcher(["wolf", "wolf", "boar", "bandit"])
	ok(int(r1["found"].get("raw_meat", 0)) == 8 and int(r1["found"].get("hide", 0)) == 3 and r1["found"].has("fat"), "с ножом: %s" % r1["found"])
	ok(camp.butcher(["bandit"])["found"].is_empty(), "людей не разделывают")
	cast.after_battle({"outcome": "win", "beasts": ["boar"]})
	ok(cast.loot != null and cast.loot.is_open(), "после боя — туша в окне «Найдено»")
	await shot("k02_butcher.png")
	cast.loot.take_all()

	# Збереження вогнища
	camp.light_fire()
	camp.light_fire()
	var d: Dictionary = cast.to_dict()
	var lit_before: bool = camp.fire_lit()
	camp.fire = {}
	cast.load_dict(d)
	ok(cast.camp.fire_lit() == lit_before, "костёр пережил сохранение")

	print("CAMP CHECKS: %d/%d" % [checks - fails, checks])
	quit(1 if fails > 0 else 0)

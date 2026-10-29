extends SceneTree
## Місто через Worlds (потрібні накладання characters + worlds): вхід, торгівля спільною сумкою, вихід, пам'ять міста.
## godot --path game --rendering-driver opengl3 -s res://tests/city_worlds_checks.gd -- [тека_для_знімків]

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


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	shots = args[0] if args.size() > 0 else ""
	_run()


func _run() -> void:
	var W: Node = root.get_node_or_null("Worlds")
	Engine.set_meta("aw_load", "")
	var game: Node2D = load("res://game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	var t0: int = Time.get_ticks_msec()
	while not game.ready_done and Time.get_ticks_msec() - t0 < 120000:
		await process_frame
	await frames(3)
	game.cam_pos = Vector2(20812.0, 18000.0)
	game.cast.spawn_hero(game.cam_pos)
	var outside: Vector2 = game.cast.hero["pos"]
	W.inventory["money"] = 50
	ok(await W.enter_city("s001", {"return_pos": outside}), "Worlds.enter_city(s001)")
	await frames(3)
	var city: Node = W.current_node()
	ok(city != null and city.has_method("talk") and city.city_id == "s001", "открылся мир Эшвика, не заглушка")
	ok(city.hero == game.cast.hero["actor"], "в городе тот же герой")
	ok(city.bag == W.inventory, "сумка общая с Worlds")
	ok(not game.cast.controls_hero, "общая карта не двигает героя")
	if shots != "":
		await frames(3)
		root.get_viewport().get_texture().get_image().save_png(shots.path_join("w01_city_via_worlds.png"))
	# Купити в торговки, знайти льох
	var hour: float = game.clock.hour_of_day()
	game.clock.total_seconds += fposmod(11.0 - hour, 24.0) * 3600.0
	for i in 900:
		city._process(0.05)
	# Торгує шкіряник: у початковому місті (city_growth.gd) торговки ще немає
	var trader: Dictionary = {}
	for n in city.npcs:
		if n["def"]["id"] == "tanner":
			trader = n
	var m0: int = W.inventory["money"]
	city.hero_pos = trader["pos"] + Vector2(0, 1.6)
	city.open_trade(trader)
	city._buttons[0].emit_signal("pressed")
	ok(W.inventory["money"] < m0 and not W.inventory["items"].is_empty(), "кнопка «Купить» списала деньги из общей сумки: %s" % [W.inventory])
	city._close_panel()
	city.discovered["cellar"] = true
	# До брами й назовні
	city.hero_pos = Vector2(city.def["gates"][0]["spawn"][0], city.def["gates"][0]["spawn"][1]) * city.map.cell_m
	for i in 150:
		city.move_hero(Vector2.DOWN, false, 1.0 / 30.0, city.env_at(city.hero_pos))
	for i in 120:
		await process_frame
	ok(W.current_kind() == "overworld", "вышел через южные ворота на общую карту")
	# З гілкою «Міста на загальній карті» вихід завжди до брами мініатюри (settlements.exit_point)
	var expect: Vector2 = outside
	if game.get("settlements") != null and game.settlements.has_method("exit_point") and not game.settlements.get_settlement("s001").is_empty():
		expect = game.settlements.exit_point("s001")
	ok(game.cast.hero["pos"].distance_to(expect) < 600.0, "герой у города: %s (ждали %s)" % [game.cast.hero["pos"], expect])
	ok(W.city_states.has("s001") and W.city_states["s001"]["discovered"].has("cellar"), "город запомнен")
	# Знову в місто: знахідки на місці
	ok(await W.enter_city("s001", {"return_pos": outside}), "снова в город")
	await frames(3)
	city = W.current_node()
	ok(city.discovered.has("cellar"), "находки сохранились между визитами")
	# Через стіну зі сходу
	await frames(30)
	W.leave()
	for i in 120:
		await process_frame
	ok(await W.enter_city("s001", {"return_pos": outside, "entry": "sneak", "side": "east"}), "пролез через стену")
	await frames(3)
	city = W.current_node()
	ok(city.is_intruder() and city.hero_pos.x > city.map.size_m().x * 0.85, "у восточной стены, чужак: %s" % city.hero_pos)
	print("city_worlds_checks: %d/%d" % [checks - fails, checks])
	quit(1 if fails > 0 else 0)

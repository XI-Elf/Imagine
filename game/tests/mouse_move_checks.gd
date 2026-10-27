extends SceneTree
## Ход героя мышью: общая карта (characters/hero_route.gd) и мир города (city/city_route.gd).
## godot --path game --rendering-driver opengl3 -s res://tests/mouse_move_checks.gd -- [папка_для_снимков]

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


func mouse(pos: Vector2, button: MouseButton, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	Input.parse_input_event(ev)


func click(pos: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	Input.warp_mouse(pos)
	mouse(pos, button, true)
	await frames(1)
	mouse(pos, button, false)
	await frames(2)


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	shots = args[0] if args.size() > 0 else ""
	_run()


# Быстрый ход по пути: много шагов за кадр (как прошли бы минуты игры); у чужого поселения — «Продолжить путь»
func run_route(game: Node2D, max_steps: int = 60000, continue_prompts: bool = true) -> Dictionary:
	var cast: Node2D = game.cast
	var st: Node2D = game.settlements
	var h: Dictionary = cast.hero
	var res := {"blocked": false, "prompts": 0, "steps": 0}
	var n: int = 0
	while cast.route.active() and n < max_steps:
		for i in 40:
			if not cast.route.active():
				break
			if not st.prompt_for.is_empty():
				break
			cast._drive_hero(h, {}, 0.1)
			n += 1
			if st.blocks(h["pos"]):
				res["blocked"] = true
		await process_frame
		if not st.prompt_for.is_empty():
			res["prompts"] += 1
			if not continue_prompts:
				break
			st.choose_continue()
	res["steps"] = n
	return res


func _run() -> void:
	var game: Node2D = load("res://game.tscn").instantiate()
	root.add_child(game)
	var t0: int = Time.get_ticks_msec()
	while not game.ready_done and Time.get_ticks_msec() - t0 < 120000:
		await process_frame
	ok(game.ready_done, "карта загрузилась")
	game.physics.travel_weather = false   # дождь и гроза замедляют ход: шаги проверяются без погоды
	var cast: Node2D = game.cast
	var st: Node2D = game.settlements
	var city: Dictionary = st.list[0]
	ok(cast.route != null, "ход мышью подключён")

	cast.spawn_hero(st.spawn_point())
	var h: Dictionary = cast.hero
	h["actor"].res["thirst"] = 100.0
	h["actor"].res["hunger"] = 100.0
	game.zoom = 0.5
	await frames(5)
	st.choose_continue()
	# Случайные нападения в пути (worlds.gd, по км) уводили героя в бой посреди проверки — тест падал через раз
	for c in h["actor"].km_passed.get_connections():
		h["actor"].km_passed.disconnect(c["callable"])

	# 1. Клик мышью по суше рядом: путь задан, герой дошёл
	var aim: Vector2 = cast._find_land(h["pos"] + Vector2(260, 120), 1500.0, true)
	await click(game.world_to_screen(aim))
	ok(cast.route.active(), "ЛКМ по карте задаёт путь")
	ok(cast.route.target.distance_to(aim) < 3.0, "цель — точка клика")
	await shot("mm01_route_overworld.png")
	var r: Dictionary = await run_route(game)
	ok(not cast.route.active() and h["pos"].distance_to(aim) < 8.0, "герой дошёл до точки (%.1f м)" % h["pos"].distance_to(aim))

	# 2. ПКМ — стоп
	await click(game.world_to_screen(h["pos"] + Vector2(-200, 0)))
	ok(cast.route.active(), "новый путь")
	await click(game.world_to_screen(h["pos"]), MOUSE_BUTTON_RIGHT)
	ok(not cast.route.active(), "ПКМ останавливает")

	# 3. WASD перебивает путь
	cast.route.go_to(h["pos"] + Vector2(150, 0))
	Input.action_press("ui_left")
	await frames(3)
	Input.action_release("ui_left")
	ok(not cast.route.active(), "клавиши отменяют путь")

	# 4. Обход города: с севера на юг мимо стены
	var rect: Rect2 = city["_rect"]
	var north: Vector2 = cast._find_land(Vector2(rect.get_center().x, rect.position.y - 400.0), 600.0, true)
	var south: Vector2 = cast._find_land(Vector2(rect.get_center().x + 300.0, rect.end.y + 400.0), 600.0, true)
	for d in [900.0, 700.0, 500.0, 0.0]:
		h["pos"] = north + Vector2(0, -d)
		await frames(2)
	st.choose_continue()
	var tp: int = Time.get_ticks_msec()
	ok(cast.route.go_to(south), "путь через город на другую сторону")
	print("  план %d мс, клетка %.0f м, точек %d" % [Time.get_ticks_msec() - tp, cast.route._plan_cell, cast.route.points.size()])
	var through: bool = false
	for q in cast.route.points:
		through = through or st.blocks(q)
	ok(not through, "путь не идёт по клеткам города")
	game.zoom = 0.12
	await shot("mm02_route_around_city.png")
	r = await run_route(game)
	ok(not r["blocked"], "герой ни разу не на стене")
	ok(r["prompts"] == 0, "мимо города без вопросов «проникнуть» (%d)" % r["prompts"])
	ok(h["pos"].distance_to(south) < 8.0, "обошёл город (%.0f м до цели, выборов у стены: %d)" % [h["pos"].distance_to(south), r["prompts"]])

	# 5. Клик по городу — к воротам, там выбор «Войти»; путь закончен
	game.zoom = 0.05
	game.cam_pos = h["pos"]
	await frames(2)
	await click(game.world_to_screen(city["_center"]))
	ok(cast.route.active() and cast.route.goal_city == city["id"], "клик по щитку города — путь к нему")
	ok(cast.route.target.distance_to(st.exit_point(city["id"])) < 1.0, "цель — ворота")
	r = await run_route(game, 60000, false)
	ok(st.prompt_kind == "gate" and st.prompt_for.get("id", "") == city["id"], "у ворот открылся выбор «Войти»")
	await frames(2)
	ok(not cast.route.active(), "путь окончен у ворот")
	game.zoom = 0.5
	await shot("mm03_gate_prompt.png")
	# Клик мимо, пока открыт выбор, — «Продолжить путь» и идти
	await click(game.world_to_screen(h["pos"] + Vector2(-180, 60)))
	ok(st.prompt_for.is_empty() and cast.route.active(), "клик по карте при выборе — продолжить путь")
	cast.route.cancel()
	# Снова клик по городу, стоя у ворот, — выбор открывается заново
	await click(game.world_to_screen(city["_center"]))
	await run_route(game, 60000, false)
	await frames(3)
	ok(st.prompt_kind == "gate", "повторный клик по городу у ворот — снова «Войти»")
	st.choose_continue()

	# 6. За край мира — нельзя; в воду — к берегу
	ok(not cast.route.go_to(Vector2(-3000, -3000)), "за край мира путь не строится")
	var wet := Vector2.INF
	var r0: float = 50.0
	while wet == Vector2.INF and r0 < 20000.0:
		for k in 32:
			var q: Vector2 = h["pos"] + Vector2.from_angle(TAU * k / 32.0) * r0
			if game.biome_at(q) == 1 and cast._find_land(q, 300.0) != q:
				wet = q
				break
		r0 += 100.0
	if wet != Vector2.INF:
		var shore: Vector2 = cast._find_land(wet, 400.0)
		print("  вода %s биом %d, берег %s биом %d, герой %s, событие: %s" % [wet, game.biome_at(wet), shore, game.biome_at(shore), h["pos"], game.event_text])
		var wok: bool = cast.route.go_to(wet)
		print("  событие: ", game.event_text)
		ok(wok and game.biome_at(cast.route.target) != 1, "клик в воду у берега — цель на берегу (%s, путь %s, биом цели %d)" % [wet, wok, game.biome_at(cast.route.target) if wok else -1])
	cast.route.cancel()

	# 7. Длинный путь (10 км) считается быстро
	var far: Vector2 = cast._find_land(h["pos"] + Vector2(9000, -3000), 3000.0, true)
	tp = Time.get_ticks_msec()
	var got: bool = cast.route.go_to(far)
	var ms: int = Time.get_ticks_msec() - tp
	print("  далеко: %s биом %d, от героя %s" % [far, game.biome_at(far), h["pos"]])
	ok(got and ms < 400, "путь %.1f км за %d мс" % [h["pos"].distance_to(far) / 1000.0, ms])
	game.zoom = 0.03
	game.cam_pos = (h["pos"] + far) * 0.5
	cast.controls_hero = false
	await frames(2)
	ok(not cast.route.active(), "свободная камера (G) снимает путь")
	cast.controls_hero = true
	game.queue_free()
	await frames(3)

	await _city()
	print("ИТОГ: %d/%d" % [checks - fails, checks])
	quit(1 if fails > 0 else 0)


# =====================================================================
# МИР ГОРОДА
# =====================================================================
func city_run(c: Node, max_steps: int = 20000) -> void:
	var n: int = 0
	while c.route.active() and n < max_steps:
		for i in 30:
			if not c.route.active():
				break
			c._drive_hero(c.env_at(c.hero_pos), 1.0 / 30.0)
			n += 1
		await process_frame


func _city() -> void:
	var c: Node2D = load("res://city/city_world.tscn").instantiate()
	root.add_child(c)
	await frames(4)
	ok(c.entered and c.route != null, "город открыт, ход мышью подключён")
	var t: float = c.clock.total_seconds
	c.clock.total_seconds = t - fposmod(t, 86400.0) + 12.0 * 3600.0
	c.hero.res["thirst"] = 40.0

	# Клик по колодцу на площади — дойти и напиться
	var well: Dictionary = {}
	for p in c.def["places"]:
		if p["id"] == "well_square":
			well = p
	var wp: Vector2 = c._place_pos(well)
	ok(c.route.click(wp + Vector2(0.3, 0.2)), "клик по колодцу — путь")
	ok(not c.route.goal_place.is_empty(), "цель — колодец")
	c.cam.position = c.hero_pos * c.PX
	await shot("mm04_city_route.png")
	await city_run(c)
	ok(c.hero_pos.distance_to(wp) < c.LOOK_M, "дошёл до колодца (%.1f м)" % c.hero_pos.distance_to(wp))
	ok(c.hero.res["thirst"] > 60.0, "напился (вода %d)" % int(c.hero.res["thirst"]))

	# Клик в стену дома — к ближайшему свободному месту, без прохода сквозь стены
	var bld: Dictionary = c.map.buildings[2]
	var fl: Array = bld["floor"]
	var inside: Vector2 = c.map.center_of(fl[fl.size() / 2])
	ok(c.route.click(inside), "клик внутрь дома %s — путь через дверь" % bld.get("name", ""))
	var wall_hit: bool = false
	for q in c.route.points:
		wall_hit = wall_hit or not c.map.is_free(q, 0.3)
	ok(not wall_hit, "путь не идёт сквозь стены")
	await city_run(c)
	ok(c.map.building_at(c.hero_pos) == bld["index"], "герой в доме")

	# Клик по жителю — подойти и заговорить
	var npc: Dictionary = {}
	for n in c.npcs:
		if n["actor"].alive and not n["actor"].sleeping and c.map.building_at(n["pos"]) < 0:
			npc = n
			break
	if not npc.is_empty():
		ok(c.route.click(npc["pos"]), "клик по жителю %s" % npc["actor"].display_name)
		await city_run(c)
		ok(c._panel.visible and c._panel_kind == "talk", "подошёл и заговорил")
		await shot("mm05_city_talk.png")
		c._close_panel()

	# Пока открыто окно — клики не ведут героя
	c.open_bag()
	await click(Vector2(50, 50))
	ok(not c.route.active(), "при открытом окне клик не ведёт героя")
	c._close_panel()
	if c.get("window") != null:   # сумка — во вкладке окна героя (hero/patch)
		c.window.close()

	# Клик по воротам — выйти (отдельный запуск: герой у ворот, сообщение о выходе)
	var gate_cell: Vector2i = Vector2i(c.def["gates"][0]["cells"][1][0], c.def["gates"][0]["cells"][1][1])
	ok(c.route.click(c.map.center_of(gate_cell)), "клик по воротам — путь")
	await city_run(c)
	ok(c.event_text.find("Выход") >= 0, "вышел в ворота: %s" % c.event_text)

	# Ночью ворота заперты — клик не ведёт
	c.clock.total_seconds = c.clock.total_seconds - fposmod(c.clock.total_seconds, 86400.0) + 86400.0 + 23.5 * 3600.0
	await frames(3)
	ok(not c.route.click(c.map.center_of(gate_cell)) and c.event_text.find("заперт") >= 0, "ночью ворота заперты: %s" % c.event_text)
	c.queue_free()
	await frames(2)

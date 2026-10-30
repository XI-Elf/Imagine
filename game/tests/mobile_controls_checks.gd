extends SceneTree
## Сенсорне керування (Android): панель кнопок, щипок, «Назад», масштаб інтерфейсу, тап-рух героя на карті.
## godot --path game --rendering-driver opengl3 -s res://tests/mobile_controls_checks.gd -- --touch [тека_для_знімків]

var fails: int = 0
var checks: int = 0
var shots: String = ""
var got_keys: Array = []
var wheel_up: int = 0
var wheel_down: int = 0


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
	for a in OS.get_cmdline_user_args():
		if a != "--touch":
			shots = a
	_run()


func _spy(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed:
		got_keys.append(ev.physical_keycode)
	elif ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			wheel_up += 1
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			wheel_down += 1


func _run() -> void:
	await frames(2)   # автозагрузки дочекались _ready
	var mc: Node = root.get_node("MobileControls")
	ok(mc.active, "сенсорный режим включён (--touch)")
	ok(is_equal_approx(root.content_scale_factor, mc.ui_scale), "масштаб интерфейса применён: ×%s" % str(mc.ui_scale))
	var spy := Node.new()
	spy.set_script(load("res://tests/doubles/input_spy.gd"))
	spy.cb = _spy
	root.add_child(spy)
	await frames(2)

	# Клавиши
	mc.key(KEY_M)
	mc.key(KEY_I)
	await frames(2)
	ok(got_keys == [KEY_M, KEY_I], "кнопки шлют клавиши M и I: %s" % str(got_keys))
	# Щипок: два «шага колеса» вверх, один вниз
	var pos := Vector2(400, 300)
	for f in [1.3, 1.3, 0.78]:
		var g := InputEventMagnifyGesture.new()
		g.factor = f
		g.position = pos
		mc._input(g)
	await frames(2)
	ok(wheel_up == 2 and wheel_down == 0, "щипок: растяжение %d шагов вверх, обратно ещё мало (%d вниз)" % [wheel_up, wheel_down])
	var g2 := InputEventMagnifyGesture.new()
	g2.factor = 0.6
	g2.position = pos
	mc._input(g2)
	await frames(2)
	ok(wheel_down >= 1, "щипок сжатием даёт шаг вниз")

	# Масштаб интерфейса циклически, значение хранится
	var s0: float = mc.ui_scale
	mc.cycle_scale()
	ok(mc.ui_scale != s0 and is_equal_approx(root.content_scale_factor, mc.ui_scale), "кнопка «Интерфейс» меняет масштаб")
	var cfg := ConfigFile.new()
	ok(cfg.load("user://mobile.cfg") == OK and float(cfg.get_value("ui", "scale")) == mc.ui_scale, "масштаб записан в user://mobile.cfg")
	mc.ui_scale = mc.DEFAULT_SCALE
	mc._apply_scale()
	mc._save_scale()

	# Игра: тап по карте ведёт героя, кнопки открывают окна, щипок масштабирует
	var game: Node2D = load("res://game.tscn").instantiate()
	root.add_child(game)
	var t0: int = Time.get_ticks_msec()
	while not game.ready_done and Time.get_ticks_msec() - t0 < 120000:
		await process_frame
	ok(game.ready_done, "карта загрузилась")
	spy.queue_free()
	var cast: Node2D = game.cast
	var st: Node2D = game.settlements
	cast.spawn_hero(st.spawn_point())
	game.physics.travel_weather = false
	await frames(5)
	st.choose_continue()
	var z0: float = game.zoom
	mc.wheel(true, game.get_viewport_rect().size / 2.0)
	await frames(2)
	ok(game.zoom > z0, "щипок/колесо ближе: %.2f -> %.2f" % [z0, game.zoom])
	mc.key(KEY_I)
	await frames(3)
	ok(cast.window.visible, "кнопка «Герой» открывает окно героя")
	await shot("mc01_hero_window.png")
	mc.key(KEY_ESCAPE)
	await frames(2)
	ok(not cast.window.visible, "«Меню/Назад» закрывает окно героя")
	root.get_node("Tutorial").enabled = false
	var h: Dictionary = cast.hero
	var aim: Vector2 = cast._find_land(h["pos"] + Vector2(-200, 150), 1500.0, true)
	if not st.prompt_for.is_empty():
		st.choose_continue()
	var sp: Vector2 = mc.to_screen(game.world_to_screen(aim))   # палец — экранные пиксели
	Input.warp_mouse(game.world_to_screen(aim))
	await frames(1)
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = sp
		e.global_position = sp
		Input.parse_input_event(e)
		await frames(2)
	ok(cast.route.active(), "тап (эмулированный клик) по карте задаёт путь (экран %s, вьюпорт %s)" % [str(sp), str(game.get_viewport_rect().size)])
	mc.right_click()
	await frames(2)
	ok(not cast.route.active(), "кнопка «Отмена» снимает путь")
	await shot("mc02_map.png")
	print("ИТОГ: %d/%d" % [checks - fails, checks])
	quit(1 if fails > 0 else 0)

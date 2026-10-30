extends SceneTree
## Розмови з варіантами відповідей і рядок унизу з портретом (пункти 7 і 18, Huzzah 2026-10-29).
## godot --path game --rendering-driver opengl3 -s res://tests/dialogue_checks.gd -- [тека_для_знімків]
## Вход в город как в  (видео Huzzah 2026-10-23): у ворот панель места (Искать, Набрать воды),
## «Войти» открывает экран города с карточками услуг, пешая карта — по кнопке, Esc — назад в меню.
## godot --path game --rendering-driver opengl3 -s res://tests/city_menu_checks.gd -- [папка_для_снимков]

const Growth := preload("res://city/city_growth.gd")
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
	await frames(4)
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(shots.path_join(name))


func key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(1)
	var up: InputEventKey = ev.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	await frames(1)


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	shots = args[0] if args.size() > 0 else ""
	_run()


func card(city: Node, kind: String, npc_id: String = "") -> Dictionary:
	for c in city.menu._cards:
		if c["kind"] == kind and (npc_id == "" or String(c["n"]["def"]["id"]) == npc_id):
			return c
	return {}


func _run() -> void:
	var W: Node = root.get_node_or_null("Worlds")
	Engine.set_meta("aw_load", "")
	var t: Node = root.get_node_or_null("Tutorial")
	if t != null:
		t.enabled = false
	var game: Node2D = load("res://game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	var t0: int = Time.get_ticks_msec()
	while not game.ready_done and Time.get_ticks_msec() - t0 < 120000:
		await process_frame
	await frames(3)
	if t != null:
		for c in t.get_children():
			if c is CanvasItem or c is CanvasLayer:
				c.visible = false
	game.show_clouds = false
	# Полудень: мешканці на роботі, брама відчинена
	game.clock.paused = true
	game.clock.total_seconds = floorf(game.clock.total_seconds / 86400.0) * 86400.0 + 86400.0 + 12.0 * 3600.0
	var st: Node = game.settlements
	game.cast.spawn_hero(st.spawn_point())
	await frames(4)
	var hero: Dictionary = game.cast.hero
	var a: Actor = hero["actor"]

	# Панель місця біля брами
	var bag: Dictionary = W.inventory
	bag["money"] = 20
	await key(KEY_E)
	t0 = Time.get_ticks_msec()
	while W.current_kind() != "city" and Time.get_ticks_msec() - t0 < 20000:
		await process_frame
	await frames(30)
	var city: Node = W.current_node()
	ok(city != null and city.has_method("talk"), "вошёл в город")
	if t != null:
		for c in t.get_children():
			if c is CanvasItem or c is CanvasLayer:
				c.visible = false
	var elder: Dictionary = {}
	var kid: Dictionary = {}
	for n in city.npcs:
		if n["def"]["id"] == "posadnik":
			elder = n
		if n["def"]["id"] == "kid":
			kid = n
	elder["actor"].sleeping = false
	city.talk(elder)
	await frames(2)
	ok(city._panel.visible and city._panel_kind == "talk" and city._portrait.visible, "разговор: строка внизу с портретом")
	var vp: Vector2 = city.get_viewport_rect().size
	ok(city._panel.position.y + city._panel.size.y > vp.y - 40.0 and city._panel.size.x > vp.x * 0.8, "панель разговора — внизу во всю ширину")
	var labels: Array = city._buttons.map(func(b): return b.text)
	ok(labels.any(func(s): return s.contains("Что у вас в городе")) and labels.any(func(s): return s.contains("Ищу работу")), "варианты ответов: %s" % [labels])
	ok(not labels.any(func(s): return s.contains("Поговорить")), "вместо «Поговорить» — варианты")
	await create_timer(1.6).timeout
	await shot("d01_dialog_elder.png")
	# Відповідь веде до наступної репліки
	for b in city._buttons:
		if b.text.contains("Что у вас в городе"):
			b.emit_signal("pressed")
			break
	await frames(2)
	ok(city._panel_text.text.contains("писарь"), "ответ ведёт к новой реплике: %s" % city._panel_text.text.left(40))
	# Вимоги: варіант за річ, наслідки
	var healer: Dictionary = {}
	for n in city.npcs:
		if n["def"]["id"] == "healer":
			healer = n
	kid = healer
	kid["actor"].sleeping = false
	Trade.add(bag, "wild_herbs", 1)
	city.talk(kid)
	await frames(2)
	var herb_btn: Button = null
	for b in city._buttons:
		if b.text.contains("дикие травы"):
			herb_btn = b
	ok(herb_btn != null, "вариант «Принёс дикие травы» есть, когда травы в сумке")
	herb_btn.emit_signal("pressed")
	await frames(2)
	for b in city._buttons:
		if b.text.contains("за 2 монеты"):
			b.emit_signal("pressed")
			break
	await frames(2)
	ok(Trade.count(bag, "wild_herbs") == 0 and int(bag["money"]) == 22, "травы проданы лекарке за 2 монеты")
	city.answer(kid, {"next": "end"})
	ok(not city._panel.visible, "«end» закрывает разговор")
	city.talk(kid)
	await frames(2)
	ok(not city._buttons.any(func(b): return b.text.contains("дикие травы")), "без трав вариант скрыт")
	city.dlg_state["healer"]["attitude"] = 2
	kid["def"]["id"] = "healer"
	# Стан розмови зберігається з містом
	var d: Dictionary = city.to_dict()
	city.dlg_state = {}
	city.load_dict(d)
	ok(int(city.dlg_state["healer"]["attitude"]) == 2, "отношение жителя сохраняется")
	city._inspect_speaker()
	ok(city.event_text.contains("дружелюбно"), "клик по портрету: %s" % city.event_text)
	await create_timer(1.6).timeout
	await shot("d02_dialog_kid.png")

	print("DIALOGUE CHECKS: %d/%d" % [checks - fails, checks])
	quit(1 if fails > 0 else 0)

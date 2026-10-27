extends SceneTree
## Комикс-оформление интерфейса (ui/comic_ui.gd, ui/comic_skin.gd; Q08 D, Q24 A) и правило Q21 A
## (статичен только terrain карты). Главное меню, список сохранений, создание героя, карта (HUD, M, пауза),
## подсказки F1, окно героя. Нужен экран: под xvfb, --rendering-driver opengl3.
## godot --path game --rendering-driver opengl3 -s res://tests/comic_ui_checks.gd -- [папка_для_снимков]

const ComicUI := preload("res://ui/comic_ui.gd")

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
	_run.call_deferred()   # после автозагрузок: тему вливает ComicSkin


func is_comic(sb: StyleBox, tex: Texture2D = ComicUI.T_PANEL) -> bool:
	return sb is StyleBoxTexture and (sb as StyleBoxTexture).texture == tex


func src(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f != null else ""


func _run() -> void:
	# ---- картинки и поля nine-patch
	for k in ComicUI.MARGIN:
		var t: Texture2D = ComicUI._tex(k)
		var m: Array = ComicUI.MARGIN[k]
		ok(t != null and t.get_width() > m[0] * 2 and t.get_height() > m[1] * 2, "%s: поля nine-patch меньше картинки" % k)
	ok(ComicUI.T_TECH != null and ComicUI.T_RIBBON != null, "техно-пластина и лента загружаются")
	var meta: Variant = JSON.parse_string(src("res://art/comic_ui/comic_ui.json"))
	var same: bool = meta is Dictionary
	if same:
		for k in ComicUI.MARGIN:
			same = same and meta.has(k) and str(meta[k]["margin"].map(func(v): return int(v))) == str(ComicUI.MARGIN[k]) \
				and str(meta[k]["content"].map(func(v): return int(v))) == str(ComicUI.CONTENT[k])
	ok(same, "поля в comic_ui.gd совпадают с тем, что записал tools/make_comic_ui.py")
	# тёмная палитра: середина панели — уголь
	var img: Image = ComicUI.T_PANEL.get_image()
	if img.is_compressed():
		img.decompress()
	var mid: Color = img.get_pixel(img.get_width() / 2, img.get_height() / 2)
	ok(mid.get_luminance() < 0.15, "внутри панели тёмный уголь (%.2f)" % mid.get_luminance())
	var edge: Color = img.get_pixel(img.get_width() / 2, 12)
	ok(edge.b > edge.r and edge.get_luminance() < 0.45, "рамка — тёмная сталь")

	# ---- общая тема (автозагрузка ComicSkin)
	ok(root.get_node_or_null("ComicSkin") != null, "автозагрузка ComicSkin есть")
	var b := Button.new()
	root.add_child(b)
	ok(is_comic(b.get_theme_stylebox("normal"), ComicUI.T_BUTTON), "кнопка без своих стилей — табличка комикса")
	var pc := PanelContainer.new()
	root.add_child(pc)
	ok(is_comic(pc.get_theme_stylebox("panel")), "панель без своих стилей — рамка комикса")
	var pb := ProgressBar.new()
	root.add_child(pb)
	ok(is_comic(pb.get_theme_stylebox("background"), ComicUI.T_BAR), "шкала — рамка комикса")
	# под CanvasLayer тема корня не доходит, тема по умолчанию — доходит
	var cl := CanvasLayer.new()
	root.add_child(cl)
	var b2 := Button.new()
	cl.add_child(b2)
	ok(is_comic(b2.get_theme_stylebox("hover"), ComicUI.T_BUTTON), "кнопка под CanvasLayer тоже в комиксе")
	for n in [b, pc, pb, cl]:
		n.queue_free()

	# ---- в окнах нет старых плоских рамок
	for path in ["res://main_menu.gd", "res://characters/hero_window.gd", "res://characters/hero_create.gd",
			"res://world/settlements.gd", "res://city/city_world.gd", "res://tutorial/tutorial.gd",
			"res://city/city_menu.gd", "res://characters/hero_death.gd"]:
		ok(not src(path).contains("StyleBoxFlat.new()"), "%s: плоских рамок StyleBoxFlat больше нет" % path.get_file())
	ok(not src("res://characters/inventory_view.gd").contains("draw_texture_rect(marble("), "инвентарь не рисует мрамор")

	# ---- Q21 A: terrain карты статичен (шейдеры карты без TIME), остальное может двигаться
	ok(not src("res://map_shaders.gd").contains("TIME"), "Q21: шейдер карты без TIME — terrain неподвижен")
	ok(src("res://storybook/art.gd").contains("sway"), "Q21: декор и фигуры могут двигаться (покачивание осталось)")

	# ---- главное меню и список сохранений
	Engine.set_meta("aw_intro_done", true)   # без заставки
	var menu: Control = load("res://main_menu.tscn").instantiate()
	root.add_child(menu)
	await frames(3)
	var mb: Button = null
	for n in menu.find_children("*", "Button", true, false):
		if (n as Button).text == "Новая игра":
			mb = n
	ok(mb != null and is_comic(mb.get_theme_stylebox("normal"), ComicUI.T_BUTTON), "меню: кнопки в комиксе")
	await shot("u01_main_menu.png")
	var lp: PanelContainer = menu.get("_load_panel")
	ok(lp != null and is_comic(lp.get_theme_stylebox("panel")) and lp.has_meta("comic_tech"), "список сохранений: рамка комикса и техно-линза")
	lp.visible = true
	menu.get("_main_box").visible = false
	await shot("u02_load_list.png")
	menu.queue_free()
	await frames(2)

	# ---- карта: HUD, переход по координатам, пауза, подсказки
	Engine.set_meta("aw_load", "")
	var game: Node2D = load("res://game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames(2)
	var lb: ProgressBar = game.loading_bar
	ok(is_instance_valid(lb) and is_comic(lb.get_theme_stylebox("background"), ComicUI.T_BAR), "шкала загрузки — рамка комикса")
	await shot("u00_loading.png")
	var t0: int = Time.get_ticks_msec()
	while not game.ready_done and Time.get_ticks_msec() - t0 < 120000:
		await process_frame
	await frames(3)
	ok(game.ready_done, "мир загрузился")
	ok(is_comic(game.hud_panel.get_theme_stylebox("panel")), "подсказка на карте — рамка комикса")
	ok(is_comic(game.goto_panel.get_theme_stylebox("panel")), "переход по координатам — рамка комикса (тема)")
	var cast: Node = game.get("cast")
	if cast != null and cast.has_method("spawn_hero"):
		cast.spawn_hero(game.cam_pos)
		await frames(5)
	await shot("u03_map_hud.png")
	game.goto_panel.visible = true
	await shot("u04_goto.png")
	game.goto_panel.visible = false
	game._toggle_menu()
	await frames(2)
	var frame: Node = game.pause_panel.find_children("*", "PanelContainer", true, false)[0] if not game.pause_panel.find_children("*", "PanelContainer", true, false).is_empty() else null
	ok(frame != null and is_comic((frame as Control).get_theme_stylebox("panel")) and frame.has_meta("comic_tech"), "меню паузы в рамке с техно-линзой")
	await shot("u05_pause.png")
	game._toggle_menu()
	var tut: Node = root.get_node_or_null("Tutorial")
	if tut != null:
		ok(is_comic(tut._style()), "подсказки F1 — рамка комикса")
		tut.toggle_help()
		await shot("u06_help.png")
		tut.toggle_help()
	# окно героя (если хозяин карты его держит)
	var hw: Node = null
	for n in game.find_children("*", "CanvasLayer", true, false):
		if n.get_script() != null and String(n.get_script().resource_path).ends_with("hero_window.gd"):
			hw = n
	if hw == null and cast != null:
		for n in cast.find_children("*", "CanvasLayer", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("hero_window.gd"):
				hw = n
	if hw != null:
		ok(is_comic(hw._panel.get_theme_stylebox("panel")) and hw._panel.has_meta("comic_tech"), "окно героя: рамка комикса и техно-линза")
	game.queue_free()
	await frames(2)
	print("comic_ui_checks: %d/%d" % [checks - fails, checks])
	quit(1 if fails > 0 else 0)

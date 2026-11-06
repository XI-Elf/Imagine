extends SceneTree
## Огляд регіону (world/region_view.gd, Huzzah 2026-11-04): картинки за manifest, заміна з region_art/,
## місто росте на огляді разом зі станом міста, стіна за етапом, риштування, руїни темніють після обшуку,
## туман війни ховає руїни, перехід між регіонами, закриття повертає гру, просмотрщик регіонів запускається.
## Потрібен екран: xvfb-run godot --path game --rendering-driver opengl3 -s res://tests/region_view_checks.gd

const RegionArt := preload("res://world/region_art.gd")
const Growth := preload("res://city/city_growth.gd")
const Ruins := preload("res://world/ruins.gd")

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
	_run.call_deferred()


func _run() -> void:
	art_checks()
	await game_checks()
	await viewer_checks()
	print("region_view_checks: %d/%d" % [checks - fails, checks])
	quit(1 if fails > 0 else 0)


func art_checks() -> void:
	var m: Variant = JSON.parse_string(FileAccess.get_file_as_string(RegionArt.MANIFEST))
	ok(m is Dictionary and m.get("assets", {}).size() >= 40, "manifest.json: усі картинки огляду описані")
	var bad: Array = []
	for k in m["assets"]:
		var a: Dictionary = m["assets"][k]
		var path: String = RegionArt.DIR + String(a["file"])
		if not ResourceLoader.exists(path):
			bad.append(k + " (нет файла)")
			continue
		var img: Image = (load(path) as Texture2D).get_image()
		if img.get_width() != int(a["size"][0]) or img.get_height() != int(a["size"][1]):
			bad.append(k + " (размер)")
		var an: Array = a["anchor"]
		if float(an[0]) < 0 or float(an[0]) > float(a["size"][0]) or float(an[1]) < 0 or float(an[1]) > float(a["size"][1]):
			bad.append(k + " (опора)")
	ok(bad.is_empty(), "каждая заглушка на месте, размер и точка опоры как в manifest %s" % [bad])
	var art := RegionArt.new()
	art.load_all()
	ok(art.missing.is_empty() and art.atlas != null and art.has("tree_pine") and art.has("bld_house") and art.textures.has("fog_clouds"),
		"атлас собран: %d картинок в одной текстуре %s" % [art.regions.size(), art.atlas.get_size() if art.atlas else Vector2.ZERO])
	# Заміна без правки коду: PNG у region_art/ має перевагу над заглушкою; варіант будинку за етапом
	var dir: String = RegionArt.override_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var probe := Image.create(96, 128, false, Image.FORMAT_RGBA8)
	probe.fill(Color(1, 0, 0, 1))
	probe.save_png(dir.path_join("tree_pine.png"))
	probe.save_png(dir.path_join("bld_house_s2.png"))
	var art2 := RegionArt.new()
	art2.load_all()
	ok(art2.overridden.has("tree_pine.png") and art2.regions["tree_pine"].size == Vector2(96, 128), "картинка из region_art/ заменила заглушку")
	ok(art2.stage_key("bld_house", 2) == "bld_house_s2" and art2.stage_key("bld_house", 3) == "bld_house_s3" and art2.stage_key("bld_ruin", 3) == "bld_ruin", "вариант дома по этапу роста берётся (s0–s4 из textures_ai), без варианта — основная картинка")
	var r: Rect2 = art2.rect_for("tree_pine", Vector2(100, 200), 64.0)
	ok(is_equal_approx(r.size.y, 64.0) and absf(r.end.y - (200.0 + 64.0 * (1.0 - art2.anchors["tree_pine"].y))) < 0.01, "спрайт стоит опорой в точке земли")
	DirAccess.remove_absolute(dir.path_join("tree_pine.png"))
	DirAccess.remove_absolute(dir.path_join("bld_house_s2.png"))
	DirAccess.remove_absolute(dir)


func set_points(k: int) -> void:
	var w: Node = root.get_node("/root/Worlds")
	var done: Array = []
	for i in k:
		done.append("t_%d" % i)
	var st: Dictionary = w.city_states.get("s001", {})
	st["growth"] = {"done": done, "taken": {}}
	w.city_states["s001"] = st


func keys_of(rv: Node) -> Dictionary:
	var d: Dictionary = {}
	for it in rv._items:
		d[it[1]] = int(d.get(it[1], 0)) + 1
	return d


func game_checks() -> void:
	Engine.set_meta("aw_load", "")
	var game: Node2D = load("res://game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.ready_done:
		await process_frame
	game.clock.paused = true
	var rv: CanvasLayer = game.region_view
	ok(rv != null and not rv.is_open and rv._root == null, "огляд создан, но не открыт и не грузит картинки до первого открытия")
	var city: Dictionary = game.settlements.list[0]
	var reg: int = game.province_at(city["_center"])
	var plan: Dictionary = city["_plan"]
	set_points(0)
	# V на загальній карті відкриває огляд
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_V
	ev.keycode = KEY_V
	ev.pressed = true
	game._unhandled_input(ev)
	await frames(3)
	ok(rv.is_open and rv.region_id == reg and not game.terrain_layer.visible, "V открывает обзор региона города (%d «%s»)" % [reg, rv.region_name(reg)])
	ok(rv.stats["trees"] > 300 and rv.stats["mountains"] + rv.stats["frame"] > 50 and rv.stats["cities"] == 1, "лес, горы и рамка гор расставлены: %s" % [rv.stats])
	var n0: int = Growth.view(plan, 0)["buildings"].size()
	var k0: Dictionary = keys_of(rv)
	ok(rv.stats["buildings"] == n0 and k0.has("wall_palisade") and not k0.has("wall_stone"), "этап «Форт»: %d домов, стена — частокол" % n0)
	ok(rv.build_ms < 600.0, "перестройка региона %.0f мс" % rv.build_ms)
	# Ріст міста видно без ручної перебудови: стан міста змінився — огляд перебудувався сам
	set_points(5)
	rv._refresh_if_changed()
	var st1: int = Growth.stage(plan, {"done": range(5).map(func(i): return "t_%d" % i), "taken": {}})
	ok(rv.stats["buildings"] == Growth.view(plan, st1)["buildings"].size() and rv.stats["buildings"] > n0, "задания сданы — на обзоре новые дома (%d)" % rv.stats["buildings"])
	ok(rv.stats["scaffolds"] > 0, "дома следующего этапа в лесах, пока к нему идут задания (%d)" % rv.stats["scaffolds"])
	var last: int = int(plan["growth"]["stages"][-1]["points"])
	set_points(last)
	rv._refresh_if_changed()
	var kl: Dictionary = keys_of(rv)
	ok(kl.has("wall_stone") and not kl.has("wall_palisade") and kl.has("gate_stone") and rv.stats["scaffolds"] == 0, "последний этап: каменная стена и ворота, стройки нет")
	ok(rv._labels.size() == 1 and String(rv._labels[0][1]).contains(Growth.stage_name(plan, plan["growth"]["stages"].size() - 1)), "подпись города с этапом роста")
	# Руїни: обшукані темніші
	var sites: Array = Ruins.in_rect(game, rv._bbox).filter(func(s): return game.province_at(s["pos"]) == reg)
	if not sites.is_empty():
		game.cast.ruins_looted[sites[0]["key"]] = game.clock.total_seconds
		rv._refresh_if_changed()
		var dim: bool = false
		for it in rv._items:
			if String(it[1]) in ["ruin_temple", "ruin_hall", "tech_wreck", "tech_dome"] and it[3].r < 0.7:
				dim = true
		ok(dim, "обысканные руины на обзоре темнее")
		game.cast.ruins_looted.erase(sites[0]["key"])
	# Інший регіон: PgDn і клік по сусідньому
	rv.step_region(1)
	ok(rv.region_id != reg, "PgDn — следующий регион (%d)" % rv.region_id)
	rv.open(reg)
	var vp: Vector2 = rv._root.get_viewport_rect().size
	var found: Vector2 = Vector2.INF
	for i in 400:
		var sp := Vector2(fposmod(i * 97.0, vp.x), fposmod(i * 61.0, vp.y))
		var p: Vector2 = rv._cam + (sp - rv._sc(vp)) / rv._zoom()
		var id: int = game.province_at(p)
		if id > 0 and id != reg:
			found = sp
			break
	if found != Vector2.INF:
		rv._click(found)
		ok(rv.region_id != reg, "клик по соседнему региону открывает его")
	rv.open(reg)
	# Масштаб до курсора не виводить регіон з екрана
	rv._zoom_at(vp * 0.5, 3.0)
	ok(rv._uz > 2.9 and rv._bbox.grow(rv._bbox.size.x * 0.06).has_point(rv._cam), "колесо — наближение, камера в пределах региона")
	rv.close()
	ok(not rv.is_open and game.terrain_layer.visible and not game.cast.hold_hero, "закрыть — карта игры снова видна")
	# Герой: туман війни ховає далекі руїни, герой тримається, поки огляд відкритий
	game.cast.spawn_hero(game.settlements.spawn_point() + Vector2(700, 300))
	game.cast.controls_hero = true
	await frames(5)
	var hold_before: bool = game.cast.hold_hero
	print("hero_away=", game.cast.hero_away, " fog_active=", game.fog.active(), " hold=", hold_before)
	rv.open()
	await frames(3)
	ok(game.cast.hold_hero, "пока открыт обзор, герой стоит")
	ok(rv._fog.visible, "туман войны на обзоре включён, пока есть герой")
	var hidden: bool = true
	for it in rv._items:
		if String(it[1]) in ["ruin_temple", "ruin_hall", "tech_wreck", "tech_dome"]:
			var foot: Vector2 = it[2].position + it[2].size * rv.art.anchors[it[1]]
			var pm: Vector2 = foot / rv._fitz + rv._center
			if not game.fog.model.known(pm) and pm.distance_to(city["_center"]) > 800.0:   # місто показується завжди
				hidden = false
	ok(hidden, "под туманом войны руины не показываются")
	rv.close()
	ok(game.cast.hold_hero == hold_before, "после закрытия герой снова слушается")
	# Закритий огляд не працює щокадру
	var t0: int = Time.get_ticks_usec()
	for i in 200:
		rv._process(0.016)
	ok(float(Time.get_ticks_usec() - t0) / 200.0 < 20.0, "закрытый обзор ничего не делает за кадр")
	game.queue_free()
	await frames(3)


func viewer_checks() -> void:
	var v: Node = load("res://region_viewer.tscn").instantiate()
	root.add_child(v)
	var t: int = 0
	while (v.game == null or not v.game.ready_done or not v.game.region_view.is_open) and t < 3000:
		await process_frame
		t += 1
	ok(v.game != null and v.game.region_view.is_open and v.game.region_view.standalone, "просмотрщик регионов запускается сразу с обзором")
	var b0: int = v.game.region_view.stats["buildings"]
	v.set_points(v._max_points())
	ok(v.game.region_view.stats["buildings"] > b0, "G в просмотрщике — город растёт на обзоре")
	ok(ProjectSettings.get_setting("application/run/main_scene.regions", "") == "res://region_viewer.tscn", "сборка «Amber Regions» стартует с просмотрщика")
	v.queue_free()
	await frames(3)

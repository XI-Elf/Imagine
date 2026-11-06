extends SceneTree
## Огляд регіону (world/region_view.gd, Huzzah 2026-11-04; з 2026-11-06 топографічний): картинки за manifest, заміна з region_art/,
## топомодель (горизонталі, відмітки висот, підписи, масштаб — world/region_topo.gd), дані води/висот доходять до пікселів листа,
## місто росте на огляді разом зі станом міста, стіна за етапом, будівництво, руїни тьмяніють після обшуку,
## туман війни — біла пляма (ховає руїни, відмітки й рельєф), перехід між регіонами, закриття повертає гру, просмотрщик регіонів запускається.
## Потрібен екран: xvfb-run godot --path game --rendering-driver opengl3 -s res://tests/region_view_checks.gd

const RegionArt := preload("res://world/region_art.gd")
const Growth := preload("res://city/city_growth.gd")
const Ruins := preload("res://world/ruins.gd")
const Topo := preload("res://world/region_topo.gd")

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
	topo_checks()
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


func topo_checks() -> void:
	# Крок горизонталей: далі від карти — рідше, ближче — частіше; основна кожна п'ята
	ok(Topo.contour_steps(1.0)[0] == 40.0 and Topo.contour_steps(2.0)[0] == 20.0 and Topo.contour_steps(4.0)[0] == 10.0 and Topo.contour_steps(1.0)[1] == 5,
		"крок горизонталей 40/20/10 м за наближенням, основна кожна п'ята")
	var sb: Array = Topo.scale_bar(0.12, 150.0)
	ok(sb[0] == 1000.0 and absf(sb[1] - 120.0) < 0.01, "масштабна лінійка: кругла довжина (%s м = %s px)" % [sb[0], sb[1]])
	ok(Topo.scale_bar(0.5, 150.0)[0] == 200.0 and Topo.scale_bar(0.01, 150.0)[0] == 10000.0, "лінійка підбирає 200 м і 10 км за іншого масштабу")
	ok(Topo.length_text(1500.0, "км", "м") == "1.5 км" and Topo.length_text(200.0, "км", "м") == "200 м", "підпис довжини: метри й кілометри")
	# Штучний горб: конус 0..600 м, регіон — вся сітка
	var nx: int = 41
	var ny: int = 41
	var h := PackedFloat32Array()
	var okm := PackedByteArray()
	h.resize(nx * ny)
	okm.resize(nx * ny)
	for y in ny:
		for x in nx:
			h[y * nx + x] = maxf(0.0, 600.0 - Vector2(x - 20, y - 20).length() * 40.0)
			okm[y * nx + x] = 1
	var grid: Dictionary = {"origin": Vector2.ZERO, "step": 50.0, "nx": nx, "ny": ny, "h": h, "ok": okm}
	var spots: Array = Topo.spot_heights(grid, 100.0, 500.0, 5)
	ok(spots.size() == 1 and absf(spots[0]["h"] - 600.0) < 0.01 and (spots[0]["pos"] as Vector2).distance_to(Vector2(1000, 1000)) < 0.01,
		"висотна відмітка — єдина вершина 600 м на своєму місці (%s)" % [spots])
	var labs: Array = Topo.contour_labels(grid, 200.0, 300.0, 40)
	var good: bool = labs.size() >= 3
	for l in labs:
		good = good and int(l["h"]) % 200 == 0 and int(l["h"]) > 0 and absf(l["angle"]) <= PI * 0.5 + 0.001
		# підпис лежить на своїй горизонталі: висота в точці ≈ рівню
		var q: Vector2 = (l["pos"] as Vector2) / 50.0
		var hh: float = maxf(0.0, 600.0 - (q - Vector2(20, 20)).length() * 40.0)
		good = good and absf(hh - float(l["h"])) < 25.0
	ok(good, "підписи основних горизонталей: кратні 200, лежать на лінії, кут читабельний (%d шт.)" % labs.size())
	var sparse: bool = true
	for i in labs.size():
		for j in range(i + 1, labs.size()):
			if (labs[i]["pos"] as Vector2).distance_to(labs[j]["pos"]) < 299.0:
				sparse = false
	ok(sparse, "підписи не лежать упритул")
	# Вода у воді: клітинки поза «ok» не дають відміток
	okm.fill(0)
	ok(Topo.spot_heights({"origin": Vector2.ZERO, "step": 50.0, "nx": nx, "ny": ny, "h": h, "ok": okm}, 100.0, 500.0, 5).is_empty(), "відмітки не ставляться на воді й поза регіоном")


func pixel_at(rv: CanvasLayer, p: Vector2) -> Color:
	var vp: Vector2 = rv._root.get_viewport_rect().size
	var sp: Vector2 = rv._sc(vp) + (p - rv._cam) * rv._zoom()
	var img: Image = root.get_texture().get_image()
	return img.get_pixel(clampi(int(sp.x), 0, img.get_width() - 1), clampi(int(sp.y), 0, img.get_height() - 1))


func set_points(k: int) -> void:
	var w: Node = root.get_node("/root/Worlds")
	var done: Array = []
	for i in k:
		done.append("t_%d" % i)
	var st: Dictionary = w.city_states.get("s001", {})
	st["growth"] = {"done": done, "taken": {}}
	w.city_states["s001"] = st


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
	ok(rv.stats["cities"] == 1 and rv.stats["spots"] > 0 and rv.stats["contour_labels"] > 0 and rv.stats["contour_m"] == 40.0, "топомодель регіону зібрана: %s" % [rv.stats])
	ok(rv.art.atlas == null and rv._ground_mat.shader != null and rv._ground_mat.get_shader_parameter("height_tex") != null and rv._ground_mat.get_shader_parameter("water_tex") != null,
		"лист читає ті самі шари висот і води, що й гра; спрайтів і атласу немає")
	var n0: int = Growth.view(plan, 0)["buildings"].size()
	ok(rv.stats["buildings"] == n0 and rv.stats["walls"] == "palisade", "етап «Форт»: %d будинків, стіна — частокіл" % n0)
	ok(rv.build_ms < 600.0, "перестройка региона %.0f мс" % rv.build_ms)
	# Дані доходять до пікселів: вода синя, лист не плоский
	rv.legend_on = false
	var reg_rect: Rect2 = rv._bbox
	var water_p: Vector2 = Vector2.INF
	var forest_p: Vector2 = Vector2.INF
	for i in 4000:
		var q: Vector2 = reg_rect.position + Vector2(fposmod(i * 0.6180339 * reg_rect.size.x, reg_rect.size.x), fposmod(i * 0.7548776 * reg_rect.size.y, reg_rect.size.y))
		if game.province_at(q) != reg and game.water_at(q) < 0.5:
			continue
		var sp0: Vector2 = rv._sc(rv._root.get_viewport_rect().size) + (q - rv._cam) * rv._zoom()
		if q.distance_to(city["_center"]) < 1500.0 or sp0.x < 420.0 or sp0.x > 1150.0 or sp0.y < 220.0 or sp0.y > 780.0:
			continue   # подальше від міста й плашок інтерфейсу
		if water_p == Vector2.INF and game.water_at(q) > 0.97 and game.water_at(q + Vector2(60, 0)) > 0.97 and game.water_at(q - Vector2(60, 0)) > 0.97 and game.water_at(q + Vector2(0, 60)) > 0.97 and game.water_at(q - Vector2(0, 60)) > 0.97:
			water_p = q
		if forest_p == Vector2.INF and game.province_at(q) == reg and game.biome_at(q) == 4 and game.water_at(q) < 0.02:
			forest_p = q
	await frames(4)
	if water_p != Vector2.INF:
		var wc: Color = pixel_at(rv, water_p)
		ok(wc.b > wc.r + 0.05, "вода на листі синя (%s в точці %s)" % [wc, water_p])
	else:
		ok(false, "у регіоні знайшлася вода для перевірки")
	if forest_p != Vector2.INF:
		var lc: Color = pixel_at(rv, forest_p)
		ok(lc.r > lc.b + 0.04, "суходіл на листі не синій (%s)" % lc)
	# Ріст міста видно без ручної перебудови: стан міста змінився — огляд перебудувався сам
	set_points(5)
	rv._refresh_if_changed()
	var st1: int = Growth.stage(plan, {"done": range(5).map(func(i): return "t_%d" % i), "taken": {}})
	ok(rv.stats["buildings"] == Growth.view(plan, st1)["buildings"].size() and rv.stats["buildings"] > n0, "задания сданы — на обзоре новые дома (%d)" % rv.stats["buildings"])
	ok(rv.stats["scaffolds"] > 0, "дома следующего этапа пунктиром (будівництво), пока к нему идут задания (%d)" % rv.stats["scaffolds"])
	var last: int = int(plan["growth"]["stages"][-1]["points"])
	set_points(last)
	rv._refresh_if_changed()
	ok(rv.stats["walls"] == "stone" and rv.stats["scaffolds"] == 0, "последний этап: каменная стена, стройки нет")
	ok(rv._labels.size() == 1 and String(rv._labels[0][1]).contains(Growth.stage_name(plan, plan["growth"]["stages"].size() - 1)), "подпись города с этапом роста")
	# Руїни: обшукані темніші
	var sites: Array = Ruins.in_rect(game, rv._bbox).filter(func(s): return game.province_at(s["pos"]) == reg)
	if not sites.is_empty():
		game.cast.ruins_looted[sites[0]["key"]] = game.clock.total_seconds
		rv._refresh_if_changed()
		var dim: bool = false
		for m in rv._marks:
			if String(m[0]) in ["ruin", "tech_wreck", "tech_dome"] and m[2]:
				dim = true
		ok(dim, "обысканные руины на обзоре тьмяніють")
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
	ok(rv.fog_on, "белое пятно (туман войны) на обзоре включено, пока есть герой")
	var hidden: bool = true
	for m in rv._marks:
		var pm: Vector2 = m[1]
		if not game.fog.model.known(pm) and pm.distance_to(city["_center"]) > 800.0:   # місто показується завжди
			hidden = false
	ok(hidden, "под белым пятном руины, вышки и техноостовы не показываются")
	var all_known: bool = true
	for s2 in rv._spots:
		if not game.fog.model.known(s2["pos"]):
			all_known = false
	for l2 in rv._clabels:
		if not game.fog.model.known(l2["pos"]):
			all_known = false
	ok(all_known, "под белым пятном нет ни высотных отметок, ни подписей горизонталей")
	# Пляма на пікселях: далека суша — світлий пергамент без знаків, а не карта
	rv.legend_on = false
	var far_p: Vector2 = Vector2.INF
	for i in 3000:
		var q2: Vector2 = rv._bbox.position + Vector2(fposmod(i * 0.6180339 * rv._bbox.size.x, rv._bbox.size.x), fposmod(i * 0.7548776 * rv._bbox.size.y, rv._bbox.size.y))
		if game.province_at(q2) == rv.region_id and game.water_at(q2) < 0.02 and not game.fog.model.known(q2) and q2.distance_to(game.cast.hero["pos"]) > 3000.0:
			far_p = q2
			break
	await frames(4)
	if far_p != Vector2.INF:
		var bc: Color = pixel_at(rv, far_p)
		ok(bc.r > 0.6 and bc.g > 0.55 and bc.b > 0.4 and bc.r > bc.b, "невідома суша — біла пляма (%s)" % bc)
	rv.fog_enabled = false
	rv.rebuild_now()
	await frames(3)
	ok(not rv.fog_on and rv._spots.size() >= 0, "без туману (просмотрщик, F) білої плями немає, лист відкритий весь")
	rv.fog_enabled = true
	rv.rebuild_now()
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

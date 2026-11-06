extends SceneTree
## Знімки огляду регіону (world/region_view.gd): «до» — звичайна карта, вписана в регіон; «після» — огляд
## на різних етапах росту Ешвіка, з туманом війни й без, з наближенням; заміри часу перебудови й кадру.
## xvfb-run godot --path game --rendering-driver opengl3 -s res://qa/region_shots.gd  (тека — AMBER_QA_OUT)
var OUT: String = OS.get_environment("AMBER_QA_OUT") if OS.has_environment("AMBER_QA_OUT") else "user://region_shots/"


func _initialize() -> void:
	call_deferred("run")


func capture(name: String, n: int = 30) -> void:
	for i in n:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join(name + ".png"))
	print("CAPTURE ", name)


func set_points(game: Node, k: int) -> void:
	var w: Node = root.get_node("/root/Worlds")
	var done: Array = []
	for i in k:
		done.append("qa_%d" % i)
	var st: Dictionary = w.city_states.get("s001", {})
	st["growth"] = {"done": done, "taken": {}}
	w.city_states["s001"] = st


func frame_ms(n: int) -> float:
	var t0: int = Time.get_ticks_usec()
	for i in n:
		await process_frame
	return float(Time.get_ticks_usec() - t0) / 1000.0 / float(n)


func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	Engine.set_meta("aw_load", "")
	var game: Node2D = load("res://game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.ready_done:
		await process_frame
	game.show_clouds = false
	root.get_node("/root/Tutorial").enabled = false
	root.get_node("/root/Tutorial")._card.visible = false
	game.clock.paused = true
	game.clock.total_seconds = floorf(game.clock.total_seconds / 86400.0) * 86400.0 + 11.0 * 3600.0
	var rv: CanvasLayer = game.region_view
	var bb: Rect2 = rv.region_rect(7)
	# ДО: звичайна карта, вписана в регіон
	var vp: Vector2 = game.get_viewport_rect().size
	game.cam_pos = bb.get_center()
	game.zoom = minf(vp.x / (bb.size.x * 1.1), vp.y / (bb.size.y * 1.1))
	await capture("before_region7_map")
	var t_map: float = await frame_ms(60)
	game.zoom = 0.7
	game.cam_pos = game.settlements.spawn_point()
	await capture("before_city_zoom07")
	# ПІСЛЯ: огляд без героя (туману немає)
	set_points(game, 0)
	rv.open(7)
	await capture("after_region7_stage0")
	print("BUILD_MS ", rv.build_ms, " STATS ", rv.stats)
	var t_rv: float = await frame_ms(60)
	for k in [4, 9, 14, 18]:
		set_points(game, k)
		rv.rebuild_now()
		await capture("after_region7_points%02d" % k, 6)
		print("POINTS ", k, " STATS ", rv.stats)
	rv._zoom_at(rv.game.world_to_screen(game.settlements.spawn_point()) if false else vp * 0.5, 1.0)
	rv._uz = 3.2
	rv._cam = game.settlements.list[0]["_center"]
	rv._clamp()
	await capture("after_region7_zoom_city", 8)
	rv.close()
	# Тропа від брами на схід і на південь (як після кількох походів) — на огляді видно протоптане
	var g0: Vector2 = game.settlements.list[0]["_gate"] if game.settlements.list[0].has("_gate") else game.settlements.spawn_point()
	var pts: Array = [g0, g0 + Vector2(1800, 600), g0 + Vector2(3200, 2400), g0 + Vector2(2600, 4800)]
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		for j in int(a.distance_to(b) / 6.0):
			var q: Vector2 = a.lerp(b, float(j) / (a.distance_to(b) / 6.0)) + Vector2(sin(j * 0.05) * 40.0, 0)
			game.trails.model.add_pass(game.trails.model.cell_at(q), game.clock.total_seconds, 90.0 if i == 0 else 35.0)
	game.trails.model.refresh(game.clock.total_seconds)
	set_points(game, 9)
	rv.open(7)
	await capture("after_region7_points09_trails", 10)
	print("TRAILS BUILD_MS ", rv.build_ms, " STATS ", rv.stats)
	rv.close()
	for id in [16, 25]:
		rv.open(id)
		await capture("after_region%02d_nofog" % id, 12)
		rv.close()
	# З героєм: туман війни відкритий лише довкола міста
	game.cast.spawn_hero(game.settlements.spawn_point())
	game.cast.controls_hero = false
	await process_frame
	await process_frame
	print("FOG opened ", game.fog.model.opened, " active ", game.fog.active(), " known_at_city ", game.fog.model.known(game.settlements.spawn_point()))
	rv.open()
	await capture("after_region7_fog", 20)
	rv.close()
	for id in [8, 16, 18, 25]:
		rv.open(id)
		await capture("after_region%02d" % id, 12)
		print("REGION ", id, " BUILD_MS ", rv.build_ms, " STATS ", rv.stats)
		rv.close()
	print("FRAME_MS map=%.2f region_view=%.2f" % [t_map, t_rv])
	quit()

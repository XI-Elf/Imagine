extends SceneTree
## Знімки топографічного огляду регіону (world/region_view.gd): регіон 7 (місто, гори, болото, проклятий ліс), різні етапи росту міста,
## білі плями туману війни, наближення, інші регіони.
## xvfb-run godot --path game --rendering-driver opengl3 --resolution 1600x900 -s res://qa/topo_shots.gd  (тека — AMBER_QA_OUT)
var OUT: String = OS.get_environment("AMBER_QA_OUT") if OS.has_environment("AMBER_QA_OUT") else "user://topo_shots/"


func _initialize() -> void:
	call_deferred("run")


func capture(name: String, n: int = 20) -> void:
	for i in n:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join(name + ".png"))
	print("CAPTURE ", name)


func set_points(k: int) -> void:
	var w: Node = root.get_node("/root/Worlds")
	var done: Array = []
	for i in k:
		done.append("qa_%d" % i)
	var st: Dictionary = w.city_states.get("s001", {})
	st["growth"] = {"done": done, "taken": {}}
	w.city_states["s001"] = st


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
	var vp: Vector2 = game.get_viewport_rect().size
	set_points(0)
	rv.open(7)
	await capture("t01_region7_stage0")
	print("BUILD_MS ", rv.build_ms, " STATS ", rv.stats)
	for k in [9, 18]:
		set_points(k)
		rv.rebuild_now()
		await capture("t02_region7_points%02d" % k, 6)
		print("POINTS ", k, " STATS ", rv.stats)
	rv.legend_on = false
	await capture("t03_region7_nolegend", 4)
	rv.legend_on = true
	# город крупно
	rv._uz = 3.4
	rv._cam = game.settlements.list[0]["_center"]
	rv._clamp()
	await capture("t04_zoom_city", 8)
	# горы крупно
	rv._uz = 2.2
	rv._cam = rv._center + Vector2(900, 200)
	rv._clamp()
	await capture("t05_zoom_mountains", 8)
	rv._uz = 4.0
	rv._cam = rv._center + Vector2(1500, 600)
	rv._clamp()
	await capture("t06_zoom_max", 8)
	rv._uz = 1.0
	rv.close()
	# туман: герой у городе
	game.cast.spawn_hero(game.settlements.spawn_point() + Vector2(300, 100))
	game.cast.controls_hero = true
	for i in 10:
		await process_frame
	rv.open(7)
	await capture("t07_fog_hero", 12)
	print("FOG ", rv.fog_on, " STATS ", rv.stats)
	rv.close()
	for id in [16, 25, 1, 24]:
		rv.fog_enabled = false
		rv.open(id)
		await capture("t08_region%d" % id, 12)
		print("REGION ", id, " BUILD_MS ", rv.build_ms, " STATS ", rv.stats)
	var t0: int = Time.get_ticks_usec()
	for i in 60:
		await process_frame
	print("FRAME_MS region_view=%.2f" % (float(Time.get_ticks_usec() - t0) / 1000.0 / 60.0))
	quit()

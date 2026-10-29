extends SceneTree
## Знімки простої погоди (Q25): уся карта в чотири сезони й через 6 годин, хмари ввімкнено.
## godot --path game --rendering-driver opengl3 -s res://qa/weather_shots.gd  (тека — AMBER_QA_OUT)
var OUT: String = OS.get_environment("AMBER_QA_OUT") if OS.has_environment("AMBER_QA_OUT") else "user://weather_shots/"


func _initialize() -> void:
	call_deferred("run")


func capture(name: String) -> void:
	for i in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + name + ".png")
	print("CAPTURE ", name)


func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	Engine.set_meta("aw_load", "")
	var game: Node2D = load("res://game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.ready_done:
		await process_frame
	game.show_clouds = true
	game.clock.paused = true
	var day0: float = floorf(game.clock.total_seconds / 86400.0 / 365.0) * 365.0 * 86400.0
	var c: Vector2 = game.MAP_SIZE * 0.5
	for s in [["winter", 20.0], ["spring", 100.0], ["summer", 200.0], ["autumn", 290.0]]:
		for h in [11.0, 17.0]:
			game.clock.total_seconds = day0 + float(s[1]) * 86400.0 + h * 3600.0
			game.physics._update_weather(true)
			game.cam_pos = c
			game.zoom = minf(1600.0 / game.MAP_SIZE.x, 900.0 / game.MAP_SIZE.y) * 0.97
			game.details_visible = false
			await capture("w_%s_%02d" % [s[0], int(h)])
			var counts: Dictionary = {}
			for n in game.physics._cells_idx.size():
				var w: Dictionary = game.physics.weather.sample(game.physics._cells_p[n], game.physics._cells_biome[n], game.physics.weather_hours, game.clock.day_of_year(), game.clock.hour_of_day())
				counts[w["name"]] = int(counts.get(w["name"], 0)) + 1
			print("  ", s[0], " ", h, " ч: ", counts)
	game.cam_pos = c
	game.zoom = 0.5
	await capture("w_close")
	quit()

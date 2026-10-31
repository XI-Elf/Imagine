extends SceneTree
## Знімки об'єму гір (patch 01 до 2D 07): світлотінь за картою висот на різних масштабах і герой на схилі.
## godot --path game --rendering-driver opengl3 -s res://qa/p01_mountain_shots.gd -- x y  (тека — AMBER_QA_OUT)
var OUT: String = OS.get_environment("AMBER_QA_OUT") if OS.has_environment("AMBER_QA_OUT") else "user://mountain_shots/"


func _initialize() -> void:
	call_deferred("run")


func capture(name: String) -> void:
	for i in 40:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + name + ".png")
	print("CAPTURE ", name)


func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var p := Vector2(float(args[0]), float(args[1]))
	Engine.set_meta("aw_load", "")
	var game: Node2D = load("res://game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.ready_done:
		await process_frame
	game.show_clouds = false
	game.clock.paused = true
	game.clock.total_seconds = floorf(game.clock.total_seconds / 86400.0) * 86400.0 + 11.0 * 3600.0
	game.cast.spawn_hero(p)
	game.cast.controls_hero = false
	for z in [0.06, 0.4, 2.0, 8.0]:
		game.cam_pos = p
		game.zoom = z
		await capture("m_zoom_%s" % str(z))
	print("height at hero: ", game.height_at(p), " slope uphill: ", game.cast.slope_factor(p, Vector2(1, 0)), " ", game.cast.slope_factor(p, Vector2(-1, 0)))
	quit()

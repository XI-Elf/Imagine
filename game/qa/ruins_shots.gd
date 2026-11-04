extends SceneTree
## Знімки руїн на загальній карті (злиття 2D 12): спрайти з шару світу (storybook/world_decor.gd, за біомом),
## підпис і притінення обшуканих — з characters/cast.gd. Одна руїна позначена обшуканою.
## godot --path game --rendering-driver opengl3 -s res://qa/ruins_shots.gd  (тека — AMBER_QA_OUT)
const Ruins := preload("res://world/ruins.gd")
var OUT: String = OS.get_environment("AMBER_QA_OUT") if OS.has_environment("AMBER_QA_OUT") else "user://ruins_shots/"


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
	Engine.set_meta("aw_load", "")
	var game: Node2D = load("res://game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.ready_done:
		await process_frame
	game.show_clouds = false
	game.clock.paused = true
	game.clock.total_seconds = floorf(game.clock.total_seconds / 86400.0) * 86400.0 + 11.0 * 3600.0
	var c: Vector2 = game.settlements.spawn_point()
	var sites: Array = Ruins.in_rect(game, Rect2(c - Vector2(9000, 9000), Vector2(18000, 18000)))
	print("RUINS ", sites.size())
	var forest: Dictionary = {}
	var other: Dictionary = {}
	for s in sites:
		if game.biome_at(s["pos"]) == 7 and forest.is_empty():
			forest = s
		elif game.biome_at(s["pos"]) != 7 and other.is_empty():
			other = s
	var n: int = 0
	for s in [forest, other]:
		if s.is_empty():
			continue
		n += 1
		game.cast.spawn_hero(s["pos"] + Vector2(30, 30))
		game.cast.controls_hero = false
		if n == 2:
			game.cast.ruins_looted[s["key"]] = game.clock.total_seconds
		for z in [0.7, 2.5]:
			game.cam_pos = s["pos"]
			game.zoom = z
			await capture("ruin%d_biome%d_zoom%s" % [n, game.biome_at(s["pos"]), str(z)])
	quit()

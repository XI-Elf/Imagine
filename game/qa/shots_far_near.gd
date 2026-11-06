extends SceneTree
## Знімки переходу: далека плоска топографічна карта -> вид з текстур місцевості при наближенні.
## godot --path game --rendering-driver opengl3 -s res://qa/shots_far_near.gd  (тека — AMBER_QA_OUT)
var OUT: String = OS.get_environment("AMBER_QA_OUT") if OS.has_environment("AMBER_QA_OUT") else "user://far_near/"


func _initialize() -> void:
	call_deferred("run")


func capture(name: String) -> void:
	for i in 150:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + name + ".png")
	print("CAPTURE ", name)


func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var world = load("res://game.tscn").instantiate()
	root.add_child(world)
	for i in 8000:
		await process_frame
		if world.ready_done:
			break
	var t: Node = root.get_node_or_null("Tutorial")
	if t != null:
		t.enabled = false
		for c in t.get_children():
			if c is CanvasItem or c is CanvasLayer:
				c.visible = false
	world.show_clouds = false
	world.clock.paused = true
	world.clock.total_seconds = floorf(world.clock.total_seconds / 86400.0) * 86400.0 + 12.0 * 3600.0
	var s: Dictionary = world.settlements.list[0]
	world.cam_pos = s["_center"] + Vector2(1500, -1500)
	for z in [0.02, 0.15, 0.4, 1.0, 3.0]:
		world.zoom = z
		await capture("z%03d" % int(z * 100))
	quit()

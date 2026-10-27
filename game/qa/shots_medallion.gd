extends SceneTree
## Снимки медальона Чёрнославля на общей карте: издали, вблизи и на каждом этапе роста (city_growth.gd).
## godot --path game --rendering-driver opengl3 -s res://qa/shots_medallion.gd  (папка — AMBER_QA_OUT)
const Growth := preload("res://city/city_growth.gd")
var OUT: String = OS.get_environment("AMBER_QA_OUT") if OS.has_environment("AMBER_QA_OUT") else "user://medallion_shots/"


func _initialize() -> void:
	call_deferred("run")


func capture(name: String) -> void:
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + name + ".png")
	print("CAPTURE ", name)


func quiet_tutorial() -> void:
	var t: Node = root.get_node_or_null("Tutorial")
	if t != null:
		t.enabled = false
		for c in t.get_children():
			if c is CanvasItem or c is CanvasLayer:
				c.visible = false


func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	quiet_tutorial()
	var world = load("res://game.tscn").instantiate()
	root.add_child(world)
	for i in 8000:
		await process_frame
		if world.ready_done:
			break
	quiet_tutorial()
	world.show_clouds = false
	world.clock.paused = true
	world.clock.total_seconds = floorf(world.clock.total_seconds / 86400.0) * 86400.0 + 12.0 * 3600.0
	var s: Dictionary = world.settlements.list[0]
	var plan: Dictionary = s["_plan"]
	var W: Node = root.get_node_or_null("Worlds")
	world.cam_pos = s["_center"] + Vector2(0, -40)
	world.zoom = 0.05
	await capture("m01_izdali")
	world.zoom = 1.0
	# Этапы роста: первые поручения по порядку, пока город не дойдёт до этапа
	for st in 5:
		var g: Dictionary = Growth.new_state()
		for k in 30:
			if Growth.stage(plan, g) >= st:
				break
			for id in plan["growth"]["quests"]:
				var q: Dictionary = Growth.current(plan, g, id)
				if not q.is_empty() and Growth.stage(plan, g) < st:
					g["done"].append(q["id"])
		if W != null:
			W.city_states[String(s.get("city_id", s["id"]))] = {"growth": g}
		world.settlements.queue_redraw()
		await capture("m%02d_etap_%d_%s" % [st + 2, st, Growth.stage_name(plan, st)])
	quit()

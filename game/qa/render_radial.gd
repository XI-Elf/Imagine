extends SceneTree
## Знімки радіального міста: світ міста (огляд, зблизька) і мініатюра на загальній карті на різних масштабах.
## godot --path game --rendering-driver opengl3 -s res://qa/render_radial.gd  (тека знімків — AMBER_QA_OUT)
var OUT: String = OS.get_environment("AMBER_QA_OUT") if OS.has_environment("AMBER_QA_OUT") else "user://radial_previews/"


func _initialize() -> void:
	call_deferred("run")


func capture(name: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + name + ".png")
	print("CAPTURE ", name)


func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var city = load("res://city/city_world.tscn").instantiate()
	root.add_child(city)
	for i in 12:
		await process_frame
	city.fog.fill(1)
	city._fog_dirty = true
	city._map_view = true
	await capture("r01_city_plan")
	city._map_view = false
	city.hero_pos = city.map.center_m() + Vector2(0, 30)
	city.cam.zoom = Vector2(1.0, 1.0)
	await capture("r02_city_square")
	city.hero_pos = Vector2(city.def["gates"][0]["spawn"][0], city.def["gates"][0]["spawn"][1]) * city.map.cell_m
	await capture("r03_city_gate")
	city.queue_free()
	await process_frame
	var world = load("res://game.tscn").instantiate()
	root.add_child(world)
	for i in 8000:
		await process_frame
		if world.ready_done:
			break
	world.show_clouds = false
	world.clock.paused = true
	world.clock.total_seconds = floorf(world.clock.total_seconds / 86400.0) * 86400.0 + 12.0 * 3600.0
	var s: Dictionary = world.settlements.list[0]
	world.cam_pos = s["_center"]
	for z in [0.05, 0.4, 1.5, 4.0]:
		world.zoom = z
		await capture("r1%d_map_zoom_%s" % [[0.05, 0.4, 1.5, 4.0].find(z), str(z)])
	world.queue_free()
	await process_frame
	quit()

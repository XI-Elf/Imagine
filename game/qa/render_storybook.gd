extends SceneTree
var OUT: String = OS.get_environment("AMBER_QA_OUT") if OS.has_environment("AMBER_QA_OUT") else "user://storybook_previews/"
func _initialize() -> void:
	call_deferred("run")

func capture(name: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png(OUT + name + ".png")
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
	city.cam.zoom = Vector2(0.25, 0.25)
	await capture("city_overview")
	city._map_view = false
	city.hero_pos = Vector2(60, 40) * city.map.cell_m
	city.cam.zoom = Vector2(1.4, 1.4)
	await capture("city_close")
	city.cam.zoom = Vector2(3, 3)
	await capture("city_max_zoom")
	city.queue_free()
	await process_frame
	var battle = load("res://battle/battle.tscn").instantiate()
	root.add_child(battle)
	for i in 12:
		await process_frame
	await capture("battle_forest")
	battle.queue_free()
	await process_frame
	var world = load("res://game.tscn").instantiate()
	root.add_child(world)
	for i in 8000:
		await process_frame
		if world.ready_done:
			break
	assert(world.ready_done, "World did not become ready")
	world.show_clouds = false
	world.clock.paused = true
	world.clock.total_seconds = floorf(world.clock.total_seconds / 86400.0) * 86400.0 + 12.0 * 3600.0
	# Find representative land points directly from the authoritative biome raster.
	for target in [3, 6]:
		var found := false
		for y in range(100, world.biome_img.get_height() - 100, 43):
			for x in range(100, world.biome_img.get_width() - 100, 43):
				var p: Vector2 = Vector2(float(x) / world.biome_img.get_width(), float(y) / world.biome_img.get_height()) * world.MAP_SIZE
				if world.biome_at(p) == target and not world.is_hot(p):
					world.cam_pos = p
					found = true
					break
			if found:
				break
		world.zoom = 4.0 if target == 3 else 0.8
		await capture("world_forest" if target == 3 else "world_mountains")
		world.zoom = 40.0
		await capture("world_forest_max" if target == 3 else "world_mountains_max")
	world.queue_free()
	await process_frame
	quit()

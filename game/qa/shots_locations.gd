extends SceneTree
## По снимку на локацию: общая карта, миниатюра города, каждый биом, места Эшвика, бой.
## godot --path game --rendering-driver opengl3 -s res://qa/shots_locations.gd  (папка — AMBER_QA_OUT)
const Actor := preload("res://characters/actor.gd")
var OUT: String = OS.get_environment("AMBER_QA_OUT") if OS.has_environment("AMBER_QA_OUT") else "user://location_shots/"


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
			if c is CanvasItem:
				c.visible = false
			elif c is CanvasLayer:
				c.visible = false


# Точка, где биом target и вокруг на radius метров тот же (не край)
func find_biome(world: Node, target: int, hot: bool, radius: float) -> Vector2:
	var img: Image = world.biome_img
	for y in range(80, img.get_height() - 80, 17):
		for x in range(80, img.get_width() - 80, 17):
			var p: Vector2 = Vector2(float(x) / img.get_width(), float(y) / img.get_height()) * world.MAP_SIZE
			if world.biome_at(p) != target or world.is_hot(p) != hot:
				continue
			var ok: bool = true
			for k in 12:
				var q: Vector2 = p + Vector2.from_angle(TAU * k / 12.0) * radius
				if world.biome_at(q) != target or world.is_hot(q) != hot:
					ok = false
					break
			if ok:
				return p
	return Vector2.INF


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
	world.cam_pos = s["_center"]
	world.zoom = 0.02
	await capture("01_mir_obshchiy_vid")
	world.zoom = 1.6
	await capture("02_chernoslavl_miniatyura")
	var biomes: Array = [[1, false, "03_voda", 1500.0], [2, false, "04_bereg", 250.0], [3, false, "05_les", 400.0],
		[4, false, "06_pustosh", 400.0], [5, false, "07_boloto", 300.0], [6, false, "08_gory", 400.0], [6, true, "09_zharkie_gory", 400.0],
		[7, false, "10_rad_les", 250.0], [8, false, "11_rad_pustosh", 250.0], [9, false, "12_rad_boloto", 250.0]]
	for b in biomes:
		var p: Vector2 = find_biome(world, b[0], b[1], b[3])
		if p == Vector2.INF:
			p = find_biome(world, b[0], b[1], b[3] * 0.4)
		if p == Vector2.INF:
			print("NO BIOME ", b[2])
			continue
		world.cam_pos = p
		world.zoom = 0.6 if b[0] == 1 else 4.0
		await capture(b[2])
	world.queue_free()
	await process_frame

	var city = load("res://city/city_world.tscn").instantiate()
	root.add_child(city)
	for i in 12:
		await process_frame
	city.fog.fill(1)
	city._fog_dirty = true
	city.clock.paused = true
	var g: Dictionary = city.def["gates"][0]
	city.hero_pos = Vector2(g["spawn"][0], g["spawn"][1]) * city.map.cell_m + Vector2(0, -6)
	await capture("13_gorod_vorota")
	city.hero_pos = city.map.center_m() + Vector2(-6, 10)
	await capture("14_gorod_ploshchad")
	var r1: float = 29.0 * city.map.cell_m
	city.hero_pos = city.map.center_m() + Vector2.from_angle(deg_to_rad(-30)) * r1
	await capture("15_gorod_kolcevaya_ulica")
	var inn: Dictionary = city.map.building_by_id("inn")
	city.hero_pos = city.map.center_of(Vector2i(inn["door"][0], inn["door"][1]))
	await capture("16_gorod_traktir")
	city.hero_pos = city.map.center_m() + Vector2.from_angle(deg_to_rad(200)) * (float(city.def["wall_r"]) - 9.0) * city.map.cell_m
	await capture("17_gorod_stena")
	city.toggle_map()
	await capture("18_gorod_plan")
	city.queue_free()
	await process_frame

	var battle = load("res://battle/battle.tscn").instantiate()
	battle.setup({"terrain": "forest", "allies": [Actor.new("hero", "Герой")], "seed": 7})
	root.add_child(battle)
	for i in 30:
		await process_frame
	await capture("19_boy_les")
	battle.queue_free()
	await process_frame
	quit()

extends SceneTree
## Снимки маленького города (patch 01 к 2D 07): дома под спрайтами, начало и полный город.
## godot --path game --rendering-driver opengl3 -s res://qa/shots_growth.gd  (папка — AMBER_QA_OUT)
const Growth := preload("res://city/city_growth.gd")
var OUT: String = OS.get_environment("AMBER_QA_OUT") if OS.has_environment("AMBER_QA_OUT") else "user://growth_shots/"


func _initialize() -> void:
	call_deferred("run")


func capture(name: String) -> void:
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + name + ".png")
	print("CAPTURE ", name)


# Сданы первые поручения в порядке этапов, пока город не дойдёт до этапа st
func state_for(def: Dictionary, st: int) -> Dictionary:
	var g: Dictionary = Growth.new_state()
	for k in 30:
		if Growth.stage(def, g) >= st:
			break
		for id in def["growth"]["quests"]:
			var q: Dictionary = Growth.current(def, g, id)
			if not q.is_empty() and Growth.stage(def, g) < st:
				g["done"].append(q["id"])
	return {"city_id": "s001", "growth": g, "left": true}


func open_city(state: Dictionary) -> Node2D:
	var city: Node2D = load("res://city/city_world.tscn").instantiate()
	root.add_child(city)
	city.enter("s001", null, {"state": state} if not state.is_empty() else {})
	city.clock.paused = true
	var t: float = city.clock.total_seconds
	city.clock.total_seconds = t - fposmod(t, 86400.0) + 11.0 * 3600.0
	city.fog.fill(1)
	for b in city.map.buildings:
		city.discovered[String(b["id"])] = true
	city._fog_dirty = true
	return city


func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var city: Node2D = open_city({})
	var inn: Dictionary = city.map.building_by_id("inn")
	city.hero_pos = city.map.center_of(Vector2i(inn["door"][0], inn["door"][1])) + Vector2(0, 1.2)
	city.cam.zoom = Vector2(city.START_ZOOM, city.START_ZOOM)
	await capture("c01_start_obshchiy_dom")
	var hut: Dictionary = city.map.building_by_id("quarter_house_24")
	city.hero_pos = city.map.center_of(Vector2i(hut["door"][0], hut["door"][1])) + Vector2(0, 1.2)
	await capture("c02_start_lachuga")
	var full: Dictionary = city.full_def
	city.queue_free()
	await process_frame
	var c: Node2D = open_city(state_for(full, 4))
	c.hero_pos = c.map.center_m() + Vector2(0, 9)
	c.cam.zoom = Vector2(1.0, 1.0)
	await capture("c03_full_square")
	c.hero_pos = Vector2(c.def["gates"][0]["spawn"][0], c.def["gates"][0]["spawn"][1]) * c.map.cell_m
	c.cam.zoom = Vector2(1.6, 1.6)
	await capture("c04_full_gate")
	var hall: Dictionary = c.map.building_by_id("hall")
	c.hero_pos = c.map.center_of(Vector2i(hall["rect"][0] + 2, hall["rect"][1] - 1))
	await capture("c05_behind_hall")
	c.toggle_map()
	await capture("c06_full_plan")
	quit()

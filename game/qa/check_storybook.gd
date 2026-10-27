extends SceneTree
var issues: Array = []

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var city = load("res://city/city_world.tscn").instantiate()
	root.add_child(city)
	for i in 8:
		await process_frame
	if city.map.w == 0:
		issues.append("City did not initialize")
	else:
		var start: Vector2i = city.map.cell_of(city.hero_pos)
		for b in city.map.buildings:
			var door := Vector2i(b["door"][0], b["door"][1])
			if city.map.astar.get_id_path(start, door).is_empty():
				issues.append("Door unreachable: " + String(b["id"]))
		for n in city.npcs:
			if not city.map.astar.is_in_boundsv(city.map.cell_of(n["home_pos"])):
				issues.append("NPC home out of bounds")
	print("CITY: buildings=", city.map.buildings.size(), " NPCs=", city.npcs.size())
	city.queue_free()
	await process_frame
	var battle = load("res://battle/battle.tscn").instantiate()
	root.add_child(battle)
	for i in 12:
		await process_frame
	if battle.core == null or battle.ground_tex == null:
		issues.append("Battle initialization/ground missing")
	print("BATTLE: units=", battle.core.all.size(), " obstacles=", battle.core.grid.obstacle.size())
	battle.queue_free()
	await process_frame
	var dir := DirAccess.open("res://art/storybook")
	for file in dir.get_files():
		if file.ends_with(".png"):
			var texture: Texture2D = load("res://art/storybook/" + file)
			if texture == null or texture.get_width() < 32:
				issues.append("Bad asset: " + file)
	for issue in issues:
		push_error(issue)
	print("STORYBOOK CHECK: ", "PASS" if issues.is_empty() else "FAIL", " issues=", issues.size())
	quit(0 if issues.is_empty() else 1)

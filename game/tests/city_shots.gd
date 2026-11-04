extends SceneTree
## Знімки Эшвика для огляду (під xvfb, --rendering-driver opengl3):
## godot --path game --rendering-driver opengl3 -s res://tests/city_shots.gd -- тека

var dir: String = ""


func _initialize() -> void:
	dir = OS.get_cmdline_user_args()[0]
	_run()


func shot(name: String) -> void:
	for i in 4:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(dir.path_join(name))


func at_hour(city: Node, h: float) -> void:
	var t: float = city.clock.total_seconds
	city.clock.total_seconds = t - fposmod(t, 86400.0) + h * 3600.0


func settle(city: Node, n: int) -> void:
	for i in n:
		city._process(0.05)


func _run() -> void:
	var city: Node2D = load("res://city/city_world.tscn").instantiate()
	root.add_child(city)
	city.enter("s001", null, {})
	city.clock.paused = true
	at_hour(city, 10.5)
	await process_frame
	await shot("city01_gate_arrival.png")
	var posadnik: Dictionary = city.npcs[0]
	city.ask_plan(posadnik)
	city._close_panel()
	settle(city, 1200)
	city.hero_pos = Vector2(118.0, 74.0)
	city.cam.zoom = Vector2(0.8, 0.8)
	settle(city, 2)
	await shot("city02_market_day.png")
	city.toggle_map()
	await shot("city03_plan.png")
	city.toggle_map()
	city.cam.zoom = Vector2(1.0, 1.0)
	var inn: Dictionary = city.map.building_by_id("inn")
	city.hero_pos = city.map.center_of(Vector2i(32, 26))
	settle(city, 2)
	await shot("city04_inside_inn.png")
	var trader: Dictionary = city.npcs[3]
	city.hero_pos = trader["pos"] + Vector2(0, 1.6)
	settle(city, 2)
	city.talk(trader)
	await shot("city05_talk.png")
	city.open_trade(trader)
	await shot("city06_trade.png")
	city._close_panel()
	at_hour(city, 23.0)
	settle(city, 2400)
	city.hero_pos = Vector2(119.0, 168.0)
	settle(city, 2)
	await shot("city07_night_gate.png")
	city.hero_pos = Vector2(214.0, 22.0)
	at_hour(city, 12.0)
	settle(city, 2)
	await shot("city08_ruins.png")
	# Через стіну з півночі: чужинець біля стіни
	city.queue_free()
	await process_frame
	var c2: Node2D = load("res://city/city_world.tscn").instantiate()
	root.add_child(c2)
	c2.enter("s001", null, {"entry": "sneak", "side": "north"})
	c2.clock.paused = true
	c2.cam.make_current()
	settle(c2, 2)
	await shot("city09_sneak_north.png")
	quit()

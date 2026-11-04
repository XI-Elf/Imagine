extends SceneTree
## Замір продуктивності (2D 12): запуск, кадр, збереження й завантаження. Скрипти ідуть без рендера (--rendering-driver dummy),
## тож це вартість коду, а не відеокарти.
## godot --path game --headless --rendering-driver dummy -s res://qa/perf_bench.gd -- [кадрів]
const WorldSave := preload("res://world_save.gd")


func _initialize() -> void:
	_run()


func ms(t0: int) -> float:
	return (Time.get_ticks_usec() - t0) / 1000.0


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	Engine.max_fps = 0
	var n: int = int(args[0]) if args.size() > 0 else 400
	Engine.set_meta("aw_load", "")
	var t0: int = Time.get_ticks_usec()
	var game: Node2D = load("res://game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.ready_done:
		await process_frame
	print("PERF старт до готовности: %.0f мс" % ms(t0))
	var W: Node = root.get_node("Worlds")
	# Герой й «пізня гра»: туман відкрито на 60 %, 60 000 клітинок протоптаних стежок, довгий журнал і хроніка
	game.cast.spawn_hero(game.cam_pos, {})
	await process_frame
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in game.fog.model.cells.size():
		if rng.randf() < 0.6:
			game.fog.model.cells[i] = 255
	for i in 60000:
		game.trails.model.cells[Vector2i(rng.randi_range(0, 3400), rng.randi_range(0, 3000))] = [rng.randi_range(1, 300), rng.randf() * 1.0e6]
	game.trails.model.refresh(game.clock.total_seconds)
	var tr: int = Time.get_ticks_usec()
	game.trails.model.refresh(game.clock.total_seconds)
	print("PERF trails.refresh (раз на ігрову годину): %.1f мс, видимих ступенів %d" % [ms(tr), game.trails.model.stage_of.size()])
	for i in 400:
		W.chronicle.append({"t": float(i), "text": "Подія %d: герой дійшов до місця, яке запам'ятав." % i})
	print("PERF героя створено; клітинок стежок %d, туман відкрито %.0f %%" % [game.trails.model.cells.size(), game.fog.model.fraction() * 100.0])
	var fr: Array = []
	for i in 60:
		await process_frame
	for i in n:
		var t: int = Time.get_ticks_usec()
		await process_frame
		fr.append(ms(t))
	print("PERF монітори: process %.2f мс, physics %.2f мс, об'єктів %d, вузлів %d, пам'ять %.0f МБ, draw calls %d" % [Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	fr.sort()
	var sum: float = 0.0
	for x in fr:
		sum += x
	print("PERF кадр (n=%d): середній %.2f мс, p50 %.2f, p95 %.2f, p99 %.2f, макс %.2f" % [n, sum / n, fr[n / 2], fr[int(n * 0.95)], fr[int(n * 0.99)], fr[n - 1]])
	# Шар стежок: кадр із рухомою камерою (герой іде)
	game.zoom = 1.0
	game.cam_pos = Vector2(20000, 18000)
	var tl: int = Time.get_ticks_usec()
	for i in 100:
		game.cam_pos += Vector2(3.0, 1.0)
		game.trails._process(0.016)
	print("PERF шар стежок, кадр з рухомою камерою: %.2f мс" % (ms(tl) / 100.0))
	var tl2: int = Time.get_ticks_usec()
	for i in 100:
		game.trails._process(0.016)
	print("PERF шар стежок, кадр на місці: %.3f мс" % (ms(tl2) / 100.0))
	# Збереження
	for k in 3:
		var t1: int = Time.get_ticks_usec()
		var d: Dictionary = WorldSave.build(game)
		var tb: float = ms(t1)
		var t2: int = Time.get_ticks_usec()
		var ok: bool = WorldSave.write(game, false)
		var tw: float = ms(t2)
		print("PERF збереження #%d: build %.1f мс, write повністю %.1f мс, ok=%s, ключі=%d, файл %d Б" % [k, tb, tw, ok, d.size(), FileAccess.get_file_as_bytes(WorldSave.path_of(WorldSave.AUTOSAVE)).size()])
	var t3: int = Time.get_ticks_usec()
	var rd: Dictionary = WorldSave.read(WorldSave.AUTOSAVE)
	print("PERF читання сейва: %.1f мс (%d ключів)" % [ms(t3), rd.size()])
	for key in ["cast", "trails", "fog", "worlds"]:
		var t4: int = Time.get_ticks_usec()
		var o: Variant = game.get(key)
		var part: Variant = null
		if key == "worlds":
			part = W.to_dict()
		elif o != null:
			part = o.to_dict()
		print("PERF to_dict %s: %.1f мс, %d Б" % [key, ms(t4), var_to_bytes(part).size()])
	# Завантаження з нового світу: читання + apply
	var t5: int = Time.get_ticks_usec()
	var dd: Dictionary = WorldSave.read(WorldSave.AUTOSAVE)
	WorldSave.apply_late(game, dd)
	print("PERF apply_late (cast, trails, fog, worlds): %.1f мс" % ms(t5))
	quit(0)

extends SceneTree
## Звуки CC0 (вопрос Q15): у каждого файла есть источник и лицензия CC0, все файлы грузятся, автозагрузка Sfx
## играет нужные группы, бой даёт звуки взмаха, попадания и смерти, F9 выключает звук.
## Затем короткий проход по игре: карта → город → бой с включённым Sfx, без ошибок.
## godot --path game --rendering-driver opengl3 -s res://tests/sfx_checks.gd

const MANIFEST := "res://data/audio/sounds.json"
# Группы, которые зовёт audio/sfx.gd
const USED: Array = ["step_gravel", "step_sand", "step_soft", "step_bones", "swing", "whoosh", "hit_blade", "hit_fist",
	"hit_wood", "hit_metal", "die_man", "dog_bark", "dog_die", "draw_weapon", "ignite", "explode", "map_open",
	"map_close", "door_open", "door_close", "gate", "pickup", "dig", "anvil", "amb_wind", "amb_desert",
	"amb_water_1", "amb_rumble", "amb_fire", "bird_jay", "bats", "drip", "ui_click", "ui_open", "ui_close",
	"ui_error", "ui_buy", "ui_success", "ui_victory", "ui_warning", "ui_sleep", "ui_wake", "ui_dice"]

var fails: int = 0
var checks: int = 0


class FakeCore:
	extends Object
	signal acted(c, what: String, data: Dictionary)
	signal moved(c, path: Array)
	signal finished(outcome: String)


class FakeFighter:
	extends RefCounted
	var human: bool = true
	var dead: bool = false
	var down: bool = false


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("FAIL: ", what)


func frames(n: int) -> void:
	for i in n:
		await process_frame


func _initialize() -> void:
	_run()


func _run() -> void:
	await frames(2)
	_manifest()
	var S: Node = root.get_node_or_null("Sfx")
	ok(S != null, "автозагрузка Sfx есть")
	if S != null:
		await _autoload(S)
		await _game(S)
	ok(checks >= 45, "дошли до конца проверок")
	print("sfx_checks: %d проверок, ошибок %d" % [checks, fails])
	quit(1 if fails > 0 else 0)


func _manifest() -> void:
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	ok(f != null, "есть " + MANIFEST)
	if f == null:
		return
	var m: Dictionary = JSON.parse_string(f.get_as_text())
	var packs: Dictionary = m.get("packages", {})
	var snd: Dictionary = m.get("sounds", {})
	ok(snd.size() >= 100, "звуков в списке не меньше 100 (%d)" % snd.size())
	var bad: Array = []
	for id in snd:
		var s: Dictionary = snd[id]
		if String(s.get("license", "")) != "CC0-1.0" or String(s.get("author", "")) == "" \
				or String(s.get("source_url", "")) == "" or not packs.has(String(s.get("package", ""))) \
				or String(s.get("original", "")) == "":
			bad.append(id)
		elif String(s["file"]) != "res://audio/sfx/%s.ogg" % id or not ResourceLoader.exists(s["file"]):
			bad.append(id + " (нет файла)")
		else:
			var st: AudioStream = load(s["file"])
			if st == null or st.get_length() <= 0.05 or st.get_length() > 30.0:
				bad.append(id + " (не грузится)")
	ok(bad.is_empty(), "у каждого звука CC0, автор, ссылка, пакет и файл: " + str(bad))
	for p in packs:
		ok(String(packs[p].get("src", "")) != "" and String(packs[p].get("doc", "")) != "", "пакет %s описан" % p)
	# В папке нет файлов без записи
	var extra: Array = []
	for fn in DirAccess.get_files_at("res://audio/sfx"):
		if fn.ends_with(".ogg") and not snd.has(fn.get_basename()):
			extra.append(fn)
	ok(extra.is_empty(), "в audio/sfx нет звуков без источника: " + str(extra))
	ok(FileAccess.file_exists("res://audio/ЗВУКИ_CC0.txt"), "есть ЗВУКИ_CC0.txt")
	var txt: String = FileAccess.get_file_as_string("res://audio/ЗВУКИ_CC0.txt")
	var missing: Array = []
	for id in snd:
		if not (id + ".ogg |") in txt:
			missing.append(id)
	ok(missing.is_empty(), "ЗВУКИ_CC0.txt перечисляет все файлы: " + str(missing))


func _autoload(S: Node) -> void:
	var was: bool = S.enabled
	S.enabled = true
	var miss: Array = []
	for g in USED:
		if not S.has_sound(g):
			miss.append(g)
	ok(miss.is_empty(), "все группы, которые зовёт Sfx, есть: " + str(miss))
	ok(S.group_of("step_gravel_3") == "step_gravel" and S.group_of("swing") == "swing" and S.group_of("amb_water_1") == "amb_water",
		"group_of отрезает номер")
	ok(S.play("swing"), "play(swing)")
	S.played.clear()
	ok(S.play("step_gravel"), "play группы step_gravel")
	ok(S.played.size() == 1 and String(S.played[0]).begins_with("step_gravel_"), "из группы взят один файл")
	ok(not S.play("нет_такого"), "неизвестный звук не играет")
	ok(AudioServer.get_bus_index("Sfx") >= 0 and AudioServer.get_bus_index("Ambience") >= 0, "шины Sfx и Ambience созданы")
	for bed in S.BEDS:
		ok(S._beds[bed]["player"].stream != null and S._beds[bed]["player"].stream.loop, "фон %s — петля" % bed)
	# Бой: взмах, попадание кулаком, смерть цели
	var core := FakeCore.new()
	S.connect_core(core)
	var t := FakeFighter.new()
	var fists := load("res://data/battle/weapons/fists.tres")
	var club := load("res://data/battle/weapons/club.tres")
	S.played.clear()
	core.acted.emit(null, "attack", {"target": t, "res": {"hit": true, "crit": false}, "weapon": fists})
	t.dead = true
	S._run_queue(1.0)
	await create_timer(0.4).timeout
	ok(S.played.size() >= 3 and S.played[0] == "swing" and S.played.has("hit_fist"), "кулак: взмах и удар " + str(S.played))
	ok(S.played.any(func(x): return String(x).begins_with("die_man_")), "смерть человека — крик")
	S.played.clear()
	core.acted.emit(null, "attack", {"target": FakeFighter.new(), "res": {"hit": true, "crit": true}, "weapon": club})
	S._run_queue(1.0)
	ok(S.played.any(func(x): return String(x).begins_with("hit_wood_")) and S.played.any(func(x): return String(x).begins_with("hit_metal_")),
		"дубина: дробящий удар, крит — металл " + str(S.played))
	S.played.clear()
	core.acted.emit(null, "attack", {"target": FakeFighter.new(), "res": {"hit": false}, "weapon": club})
	S._run_queue(1.0)
	ok(S.played.size() == 1 and S.played[0] == "swing", "промах — только взмах")
	S.played.clear()
	core.moved.emit(null, [Vector2i.ZERO, Vector2i.ONE, Vector2i(2, 2)])
	S._run_queue(1.0)
	ok(S.played.size() == 3, "три клетки — три шага")
	S.played.clear()
	core.finished.emit("win")
	S._run_queue(1.0)
	ok(S.played.has("ui_victory"), "победа — свой звук")
	core.free()
	# F9
	var ev := InputEventKey.new()
	ev.keycode = KEY_F9
	ev.pressed = true
	S._unhandled_key_input(ev)
	ok(not S.enabled and AudioServer.is_bus_mute(AudioServer.get_bus_index("Sfx")), "F9 — звук выключен")
	S._unhandled_key_input(ev)
	ok(S.enabled and not AudioServer.is_bus_mute(AudioServer.get_bus_index("Sfx")), "F9 ещё раз — включён")
	S.set_enabled(was)
	S.enabled = true
	# Кнопки
	var b := Button.new()
	root.add_child(b)
	S.played.clear()
	b.pressed.emit()
	ok(S.played.has("ui_click"), "кнопка щёлкает")
	b.free()


## Проход по игре: новая игра на карте, шаги героя, фон биома, город (ворота, шаги), бой (сигналы ядра)
func _game(S: Node) -> void:
	var W: Node = root.get_node("Worlds")
	Engine.set_meta("aw_intro_done", true)
	var game: Node2D = load("res://game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	var t0: int = Time.get_ticks_msec()
	while not game.ready_done and Time.get_ticks_msec() - t0 < 120000:
		await process_frame
	await frames(5)
	if game.cast.hero.is_empty():
		game.cast.spawn_hero(game.settlements.spawn_point())
		await frames(3)
	var h: Dictionary = game.cast.hero
	ok(not h.is_empty(), "герой на карте")
	if h.is_empty():
		return
	game.zoom = 2.0
	S.played.clear()
	S._watch.clear()
	for i in 40:
		h["pos"] += Vector2(0.6, 0.0)
		await process_frame
	ok(S.played.any(func(x): return String(x).begins_with("step_")), "герой идёт по карте — шаги " + str(S.played.slice(0, 4)))
	await create_timer(1.0).timeout
	var loud: Array = []
	for bed in S._beds:
		if S._beds[bed]["player"].playing:
			loud.append(bed)
	ok(loud.has("wind"), "на карте звучит ветер " + str(loud))
	# Глобальная карта
	S.played.clear()
	game.global_map = true
	await frames(2)
	game.global_map = false
	await frames(2)
	ok(S.played.has("map_open") and S.played.has("map_close"), "M: шорох карты")
	# Город
	S.played.clear()
	W._on_enter_requested(game.settlements.get_settlement("s001"))
	await frames(2)
	while W.busy:
		await process_frame
	await frames(3)
	ok(W.current_kind() == "city", "вошли в город")
	ok(S.played.has("gate"), "вход в город — ворота")
	if W.current_kind() == "city":
		var city: Node = W.current_node()
		S.played.clear()
		for i in 40:
			city.hero_pos += Vector2(0.05, 0.0)
			await process_frame
		ok(S.played.any(func(x): return String(x).begins_with("step_")), "шаги в городе")
		W.leave()
		await frames(2)
		while W.busy:
			await process_frame
		await frames(3)
	# Бой
	S.played.clear()
	W.start_battle({"group": "bandits"})
	await frames(2)
	while W.busy:
		await process_frame
	await frames(5)
	ok(W.is_battle() and S._battle_core != null, "Sfx подписан на ядро боя")
	ok(S.played.has("draw_weapon"), "начало боя — оружие из ножен")
	if W.is_battle():
		var bs: Node = W.current_node()
		bs.core.auto_ai = true
		for c in bs.core.all:
			c.controlled = false
		bs.prep_confirm()
		var g: int = 0
		while bs.core.outcome == "" and g < 600:
			bs.core.run_ai_turn()
			g += 1
		# Взмахи звучат сразу, удары — с задержкой из очереди; played хранит последние 64,
		# поэтому взмахи смотрим до очереди (бой от SPECIAL длиннее: у героя 30 ОЗ)
		var swung: bool = S.played.any(func(x): return String(x) == "swing" or String(x).begins_with("whoosh_"))
		S._run_queue(2.0)
		await create_timer(0.5).timeout
		ok(swung, "в бою звучат взмахи " + str(S.played.slice(0, 8)))
		ok(S.played.any(func(x): return String(x).begins_with("step_gravel_")), "в бою шаги по клеткам")
		await frames(2)
		bs.leave()
		await frames(2)
		while W.busy:
			await process_frame
	game.queue_free()
	await frames(3)

extends SceneTree
## Генеративна музика (audio/music.gd + audio/music_synth.gd): партії з артефакту «Камерата» на місці,
## кожна родина інструментів рендериться в чисту петлю без NaN і перевантаження, настрій залежить від обстановки,
## план п'єси — від стану героя, п'єса 3–5 хв, зміна настрою міняє п'єсу, F10 / Shift+F10, рендер у потоці.
## Потім прохід грою: карта → місто → бій, Music сам вибирає настрій.
## godot --path game --rendering-driver opengl3 -s res://tests/music_checks.gd

const Synth := preload("res://audio/music_synth.gd")
# По одному інструменту з кожної родини синтезу
const FAMILIES: Array = ["tim", "sn", "cym", "tab", "tai", "org", "hps", "piz", "cb", "nyk", "hgy", "flt", "ser",
	"tpt", "dud", "cel", "bel", "glh", "thr", "ond", "gus", "sit", "man", "jaw", "cath"]

var fails: int = 0
var checks: int = 0


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
	_data()
	_synth()
	var M: Node = root.get_node_or_null("Music")
	ok(M != null, "автозагрузка Music есть")
	if M != null:
		ok(not M.auto, "в тестовом скрипте музыка сама не играет")
		_moods(M)
		_plans(M)
		await _playback(M)
		await _settings(M)
		await _thread(M)
		await _game(M)
		M.stop_render()
	print("music_checks: %d проверок, ошибок %d" % [checks, fails])
	quit(1 if fails > 0 else 0)


func _data() -> void:
	var d: Dictionary = Synth.data()
	ok(d.get("inst", []).size() == 44, "44 инструмента из артефакта: " + str(d.get("inst", []).size()))
	ok(d.get("bonus", []).size() == 5, "5 бонусных партий")
	var bad: Array = []
	for x in d.get("inst", []) + d.get("bonus", []):
		for n in x["notes"]:
			if int(n[0]) < 0 or int(n[0]) >= 64 or float(n[2]) <= 0.0:
				bad.append(x["id"])
				break
	ok(bad.is_empty(), "ноты в пределах петли 64 шестнадцатых " + str(bad))
	var M_script: GDScript = load("res://audio/music.gd")
	var missing: Array = []
	for m in M_script.MOODS:
		for cat in ["r", "h", "m", "x"]:
			for id in M_script.MOODS[m].get(cat, []):
				if Synth.inst(id).is_empty() or String(Synth.inst(id)["cat"]) != cat:
					missing.append("%s/%s" % [m, id])
	for id in M_script.THEME["ids"]:
		if Synth.inst(id).is_empty():
			missing.append("theme/" + id)
	ok(missing.is_empty(), "все инструменты пулов есть в данных и в своей группе " + str(missing))
	ok(M_script.THEME["ids"] == ["tim", "cas", "ser", "dud", "hps", "pos", "tpt", "bel"] and M_script.THEME["mode"] == "maj",
		"тема меню = состав из ссылки #mix-maj-tim-cas-ser-dud-hps-pos-tpt-bel")


func _synth() -> void:
	var s = Synth.new(11025, 96.0, "min", 0, 3)
	ok(s.frames == roundi(64 * 60.0 / 96.0 / 4.0 * 11025), "длина петли = 4 такта")
	ok(s.midi_of(0) == 57 and s.midi_of(2) == 60 and s.midi_of(7) == 69, "минор: ля, до, ля октавой выше")
	var mj = Synth.new(11025, 96.0, "maj", 2, 3)
	ok(mj.midi_of(2) == 63, "мажор со сдвигом тональности: до-диез + 2")
	var quiet: Array = []
	var loud: Array = []
	var nan: Array = []
	var t0: int = Time.get_ticks_msec()
	for id in FAMILIES:
		var r = Synth.new(11025, 104.0, "maj" if id in ["hps", "cel"] else "min", 0, 5)
		var b: PackedFloat32Array = r.render_mono(id)
		var p: float = Synth.peak(b)
		if is_nan(p) or is_inf(p):
			nan.append(id)
		elif p < 0.02:
			quiet.append(id)
		elif p > 1.6:
			loud.append("%s %.2f" % [id, p])
	ok(nan.is_empty(), "нет NaN/бесконечностей " + str(nan))
	ok(quiet.is_empty(), "каждая семья инструментов звучит " + str(quiet))
	ok(loud.is_empty(), "нет перегруза одной партии " + str(loud))
	print("  рендер %d семей при 11 кГц: %d мс" % [FAMILIES.size(), Time.get_ticks_msec() - t0])
	var st: AudioStreamWAV = Synth.new(11025, 96.0, "min", 0, 1).render_stream("piz", 1.0, -0.5)
	ok(st.stereo and st.loop_mode == AudioStreamWAV.LOOP_FORWARD and st.loop_end == s.frames and st.data.size() == s.frames * 4,
		"петля: стерео 16 бит, loop на всю длину")
	# Хвост последней ноты литавр переходит в начало петли (без шва)
	var tim: PackedFloat32Array = Synth.new(11025, 96.0, "min", 0, 1).render_mono("tim")
	ok(absf(tim[200]) > 0.0005, "хвосты нот заворачиваются на начало петли")
	# Прокляття: розлад на 20 центів змінює частоту
	var d = Synth.new(11025, 96.0, "min", 0, 1)
	d.detune_c = 20.0
	ok(d.freq_of(0) > Synth.mtof(57) * 1.01, "расстройка в центах повышает частоту")


func _moods(M: Node) -> void:
	var base: Dictionary = {"kind": "overworld", "biome": 3, "night": false, "weather": "", "sleeping": false,
		"energy": 1.0, "hunger": 1.0, "curse": 0.0, "health": 1.0, "ruins": false, "menu": false}
	var cases: Array = [
		[{"kind": ""}, "theme", "главное меню — тема из ссылки"],
		[{}, "wild_day", "лес днём"],
		[{"night": true}, "wild_night", "лес ночью"],
		[{"kind": "city"}, "city_day", "город днём"],
		[{"kind": "city", "night": true}, "city_night", "город ночью"],
		[{"kind": "battle"}, "battle", "бой"],
		[{"sleeping": true}, "sleep", "сон"],
		[{"health": 0.2}, "danger", "мало здоровья — опасность"],
		[{"biome": 8}, "cursed", "проклятая пустошь днём"],
		[{"biome": 8, "night": true}, "danger", "проклятые земли ночью — опасность"],
		[{"biome": 4, "ruins": true}, "ruins", "у руин"],
		[{"curse": 0.7}, "cursed", "сильное проклятие героя"],
		[{"kind": "battle", "sleeping": true}, "battle", "бой важнее сна"],
	]
	for c in cases:
		var ctx: Dictionary = base.duplicate()
		ctx.merge(c[0], true)
		var got: String = M.mood_of(ctx)
		ok(got == c[1], "%s: %s (получили %s)" % [c[2], c[1], got])
	var md: Dictionary = M.mods_of({"energy": 0.1, "hunger": 0.1, "curse": 0.5, "weather": "storm"})
	ok(md["tired"] and md["hungry"] and md["cursed"] and md["storm"], "состояния: усталость, голод, проклятие, гроза")


func _plans(M: Node) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var base: Dictionary = {"biome": 3, "energy": 1.0, "hunger": 1.0, "curse": 0.0, "weather": ""}
	var t: Dictionary = M.plan_for("theme", {}, rng)
	ok(t["ids"] == M.THEME["ids"] and t["mode"] == "maj", "тема меню играет состав из ссылки")
	ok(t["bonus"].is_empty(), "у темы нет бонусов (нет полной тройки)")
	var lens_ok: bool = true
	var sizes_ok: bool = true
	var pool_ok: bool = true
	var seen: Dictionary = {}
	for i in 200:
		var m: String = ["city_day", "wild_day", "wild_night", "cursed", "battle", "danger", "ruins", "city_night", "sleep"][i % 9]
		var p: Dictionary = M.plan_for(m, base, rng)
		if float(p["length"]) < 180.0 or float(p["length"]) > 300.0:
			lens_ok = false
		var ids: Array = p["ids"]
		var uniq: Dictionary = {}
		for id in ids:
			uniq[id] = true
			var cat: String = String(Synth.inst(id)["cat"])
			if not id in M.MOODS[m].get(cat, []):
				pool_ok = false
		if ids.is_empty() or ids.size() > 8 or uniq.size() != ids.size():
			sizes_ok = false
		seen[str(ids)] = true
	ok(lens_ok, "пьеса длится 3–5 минут")
	ok(sizes_ok, "в пьесе 1–8 разных инструментов")
	ok(pool_ok, "инструменты берутся из пула настроения")
	ok(seen.size() > 120, "составы случайны: %d разных из 200" % seen.size())
	var day: Dictionary = M.plan_for("wild_day", base, rng)
	var waste: Dictionary = base.duplicate()
	waste["biome"] = 4
	ok(day["mode"] == "maj" and M.plan_for("wild_day", waste, rng)["mode"] == "min", "лес — мажор, пустошь — минор")
	var tired: Dictionary = base.duplicate()
	tired["energy"] = 0.1
	var no_r: bool = true
	for i in 20:
		var p: Dictionary = M.plan_for("battle", tired, rng)
		for id in p["ids"]:
			if Synth.inst(id)["cat"] == "r":
				no_r = false
	ok(no_r, "усталость: без ударных")
	ok(M.plan_for("city_day", tired, rng)["bpm"] <= 108 * 0.9 + 0.5, "усталость: темп медленнее")
	var hungry: Dictionary = base.duplicate()
	hungry["hunger"] = 0.1
	var hp: Dictionary = M.plan_for("battle", hungry, rng)
	ok(hp["ids"].size() <= 4 and hp["mode"] == "min", "голод: не больше 4 голосов, минор")
	var cursed: Dictionary = base.duplicate()
	cursed["curse"] = 0.5
	var eerie: int = 0
	var detuned: int = 0
	for i in 20:
		var p: Dictionary = M.plan_for("wild_day", cursed, rng)
		if p["ids"].any(func(x): return x in ["thr", "jaw", "glh"]):
			eerie += 1
		if not p["detune"].is_empty():
			detuned += 1
	ok(eerie == 20, "проклятие: в каждой пьесе терменвокс, варган или стеклянная гармоника")
	ok(detuned >= 10, "проклятие: часть голосов расстроена (%d из 20)" % detuned)
	var storm: Dictionary = base.duplicate()
	storm["weather"] = "storm"
	ok(M.plan_for("wild_night", storm, rng)["ids"].any(func(x): return Synth.inst(x)["cat"] == "r"),
		"гроза ночью: появляются ударные")
	var themed: Dictionary = M.plan_for("city_day", base, rng, true)
	ok(themed["ids"] == M.THEME["ids"], "первая пьеса в городе — тема из ссылки")


func _small(mood: String, ids: Array, length: float = 200.0) -> Dictionary:
	var plan: Dictionary = {"mood": mood, "mode": "min", "key": 0, "bpm": 120.0, "ids": ids, "detune": {}, "bonus": [],
		"seed": 1, "length": length}
	return _render8(plan)


func _render8(plan: Dictionary) -> Dictionary:
	return load("res://audio/music.gd").render(plan, 8000)


func _playback(M: Node) -> void:
	M.piece = {}
	M.mood = ""
	M._want = "wild_day"
	M._want_t = 10.0
	var first: Dictionary = _small("wild_day", ["piz", "cas", "flt"])
	ok(first["streams"].size() == 3, "рендер плана: по петле на инструмент")
	var lens: Dictionary = {}
	for e in first["streams"]:
		lens[e["stream"].loop_end] = true
	ok(lens.size() == 1, "все петли пьесы одной длины (идут в такт)")
	M._ready_pieces["wild_day"] = first
	M.tick(0.1)
	ok(M.mood == "wild_day" and M.piece["layers"].size() == 3, "готовая пьеса стартует")
	ok(M.piece["layers"].all(func(l): return l["player"].playing and l["player"].bus == "Music"), "все слои играют на шине Music")
	var on: Array = M.piece["layers"].filter(func(l): return l["on"])
	ok(on.size() >= 1 and on.all(func(l): return l["cat"] != "r"), "вступление без ударных")
	ok(not M.now_playing().is_empty(), "now_playing: " + str(M.now_playing()))
	M.stop_render()
	# Короткий спад настрою (менше 3 с) не міняє п'єсу
	M._want = "wild_night"
	M._want_t = 1.0
	M._ready_pieces["wild_night"] = _small("wild_night", ["pos"])
	M.tick(0.1)
	ok(M.mood == "wild_day", "настроение держится меньше 3 с — пьеса та же")
	M._want_t = 5.0
	M.tick(0.1)
	ok(M.mood == "wild_night" and M._old.size() == 3, "ночь наступила — новая пьеса, старая затухает")
	# Бій — одразу
	M.stop_render()
	M._ready_pieces["battle"] = _small("battle", ["tim", "cb"])
	M._want = "battle"
	M._want_t = 0.0
	M.tick(0.1)
	ok(M.mood == "battle", "бой меняет музыку сразу")
	# П'єса закінчилася — наступна того ж настрою
	M.stop_render()
	var n0: int = M.history.size()
	M._ready_pieces["battle"] = _small("battle", ["sn", "cb"])
	M.tick(float(M.piece["length"]) + 1.0)
	ok(M.history.size() == n0 + 1 and M.mood == "battle", "через 3–5 минут — новая пьеса")
	# Затухання старих шарів
	for i in 30:
		M._fade(0.5)
	ok(M._old.is_empty(), "старые слои затихли и удалены")
	await frames(2)


func _settings(M: Node) -> void:
	var was_on: bool = M.enabled
	var was_v: float = M.volume
	var bus: int = AudioServer.get_bus_index("Music")
	ok(bus >= 0, "шина Music создана")
	ok(AudioServer.get_bus_effect_count(bus) >= 4, "на шине зал, фильтр, фейзер, компрессор")
	M.set_volume(0.5)
	var c := ConfigFile.new()
	ok(c.load(M.CFG) == OK and is_equal_approx(float(c.get_value("music", "volume", 0)), 0.5), "громкость музыки сохраняется")
	ok(absf(AudioServer.get_bus_volume_db(bus) - M.bus_db()) < 0.01, "громкость шины = настройке")
	var ev := InputEventKey.new()
	ev.keycode = KEY_F10
	ev.pressed = true
	M._unhandled_key_input(ev)
	ok(not M.enabled and AudioServer.is_bus_mute(bus), "F10 выключает музыку")
	M._unhandled_key_input(ev)
	ok(M.enabled and not AudioServer.is_bus_mute(bus), "F10 включает снова")
	ev.shift_pressed = true
	M._unhandled_key_input(ev)
	ok(is_equal_approx(M.volume, 0.25), "Shift+F10: 50 % → 25 %")
	M._unhandled_key_input(ev)
	ok(is_equal_approx(M.volume, 1.0), "Shift+F10: 25 % → 100 %")
	var S: Node = root.get_node_or_null("Sfx")
	if S != null:
		var s_on: bool = S.enabled
		S.enabled = false
		ok(M.bus_db() <= M.OFF_DB, "F9 (звук выкл.) глушит и музыку")
		S.enabled = s_on
		var sv: float = S.volume
		S.volume = 0.2
		M.volume = 1.0
		ok(absf(M.bus_db()) < 0.01, "громкость музыки своя, не зависит от громкости звуков")
		S.volume = sv
	M.volume = 1.0
	M.mods = {"menu": true}
	ok(M.bus_db() < -3.0, "открыто меню — музыка тише")
	M.mods = {}
	# Періодичність п'єси
	var pmin: float = M.period_min
	var pmax: float = M.period_max
	M.set_period(7.0, 2.0)
	ok(is_equal_approx(M.period_min, 2.0) and is_equal_approx(M.period_max, 7.0), "период: от 2 до 7 минут (порядок не важен)")
	var c2 := ConfigFile.new()
	ok(c2.load(M.CFG) == OK and is_equal_approx(float(c2.get_value("music", "period_max", 0)), 7.0), "период сохраняется")
	var p: Dictionary = M._next_plan("wild_day")
	ok(float(p["length"]) >= 120.0 and float(p["length"]) <= 420.0, "длина пьесы по настройке: %.0f с" % float(p["length"]))
	M.set_period(30.0, 0.0)
	ok(M.period_min >= 1.0 and M.period_max <= 20.0, "период в пределах 1–20 минут")
	M.set_period(pmin, pmax)
	ok(M.enabled or not was_on, "музыка включена по умолчанию")
	await _settings_ui(M)
	M.set_enabled(was_on)
	M.set_volume(was_v)
	await frames(1)


## Меню «Звук и музыка» в главном меню: переключатель, ползунок, период, «Назад»
func _settings_ui(M: Node) -> void:
	var menu: Control = load("res://main_menu.tscn").instantiate()
	Engine.set_meta("aw_intro_done", true)
	root.add_child(menu)
	await frames(2)
	var btn: Button = null
	for b in menu.find_children("*", "Button", true, false):
		if b.text == I18n.t("Звук и музыка"):
			btn = b
	ok(btn != null, "в главном меню есть кнопка «Звук и музыка»")
	if btn != null:
		btn.pressed.emit()
		await frames(2)
		var panel: Node = menu.find_child("SoundSettings", true, false)
		ok(panel != null and not menu._main_box.visible, "кнопка открывает настройки звука")
		if panel != null:
			panel.music_slider.value = 40
			ok(is_equal_approx(M.volume, 0.4), "ползунок меняет громкость музыки")
			panel.from_spin.value = 4
			panel.to_spin.value = 6
			ok(is_equal_approx(M.period_min, 4.0) and is_equal_approx(M.period_max, 6.0), "поля периода меняют смену пьес")
			panel.music_check.button_pressed = false
			ok(not M.enabled, "переключатель выключает музыку")
			panel.music_check.button_pressed = true
			ok(M.enabled, "и включает снова")
			panel.close()
			await frames(2)
			ok(menu._main_box.visible, "«Назад» возвращает главное меню")
	M.set_volume(0.8)
	M.set_period(3.0, 5.0)
	menu.queue_free()
	await frames(2)


func _thread(M: Node) -> void:
	M.stop_render()
	M._ready_pieces.clear()
	M._render_async({"mood": "ruins", "mode": "min", "key": 0, "bpm": 100.0, "ids": ["cas", "piz"], "detune": {},
		"bonus": [], "seed": 3, "length": 200.0})
	var t0: int = Time.get_ticks_msec()
	while not M._ready_pieces.has("ruins") and Time.get_ticks_msec() - t0 < 30000:
		await process_frame
	ok(M._ready_pieces.has("ruins") and M._ready_pieces["ruins"]["streams"].size() == 2, "рендер в фоновом потоке готов")
	# Довгий рендер переривається (вихід із гри)
	M._render_async(M.plan_for("battle", {}, RandomNumberGenerator.new()))
	await frames(2)
	var t1: int = Time.get_ticks_msec()
	M.stop_render()
	ok(M._thread == null and Time.get_ticks_msec() - t1 < 3000, "рендер прерывается быстро: %d мс" % (Time.get_ticks_msec() - t1))


## Прохід грою: Music сам бачить карту, місто й бій
func _game(M: Node) -> void:
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
	var c: Dictionary = M.context()
	ok(c["kind"] == "overworld", "контекст: общая карта")
	var has_btn: bool = game.pause_panel.find_children("*", "Button", true, false).any(func(b): return b.text == I18n.t("Звук и музыка"))
	ok(has_btn, "в меню Esc есть «Звук и музыка»")
	if has_btn:
		game._toggle_menu()
		for b in game.pause_panel.find_children("*", "Button", true, false):
			if b.text == I18n.t("Звук и музыка"):
				b.pressed.emit()
		await frames(2)
		ok(game.pause_panel.find_child("SoundSettings", true, false) != null, "Esc → «Звук и музыка» открывает настройки")
		game._toggle_menu()
		await frames(2)
		ok(game.pause_panel.find_child("SoundSettings", true, false) == null and not game.menu_open, "закрытие меню убирает настройки")
	ok(M.mood_of(c) in ["wild_day", "wild_night", "danger", "cursed", "ruins", "sleep"], "настроение карты: " + M.mood_of(c))
	var a: Actor = W.hero_actor()
	if a != null:
		var e0: float = float(a.res["energy"])
		a.set_res("energy", 0.0)
		ok(M.mods_of(M.context())["tired"], "контекст видит усталость героя")
		a.set_res("energy", e0)
	W._on_enter_requested(game.settlements.get_settlement("s001"))
	await frames(2)
	while W.busy:
		await process_frame
	await frames(3)
	ok(M.mood_of(M.context()) in ["city_day", "city_night", "sleep", "danger"], "в городе — городская музыка: " + M.mood_of(M.context()))
	if W.current_kind() == "city":
		W.leave()
		await frames(2)
		while W.busy:
			await process_frame
		await frames(3)
	W.start_battle({"group": "bandits"})
	await frames(2)
	while W.busy:
		await process_frame
	await frames(3)
	ok(M.mood_of(M.context()) == "battle", "в бою — боевая музыка")
	# Автоматичний режим кілька кадрів у бою: без помилок, рендер пішов
	M.auto = true
	M._ctx_t = 0.0
	await frames(5)
	ok(M._thread != null or M._ready_pieces.has("battle") or M.mood == "battle", "в бою Music готовит боевую пьесу")
	M.auto = false
	M.stop_render()
	if W.is_battle():
		W.current_node().leave()
		await frames(2)
		while W.busy:
			await process_frame
	game.queue_free()
	await frames(3)

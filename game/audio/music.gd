extends Node
## Генеративна музика (Huzzah 2026-10-29: «музика з артефакту, випадкові інструменти, нова п'єса кожні 3–5 хвилин,
## змінюється від локацій, станів і обстановки»). Синтез — audio/music_synth.gd (перенесення артефакту «Камерата»).
## Кожна п'єса: лад, темп, тональність і 4–8 інструментів, випадково вибраних із пулу настрою.
## Настрій залежить від місця (головне меню, місто вдень/уночі, дика місцевість, прокляті землі, руїни, бій),
## стану героя (утома — тихіше й глухіше, голод — менше голосів, прокляття — розлад і «хвилі», сон) і небезпеки
## (мало здоров'я, ніч у проклятих землях). Поки грає п'єса, наступна рендериться у фоновому потоці.
## Музика вмикається сама з запуску гри (головне меню). Налаштування — кнопка «Звук и музыка» в головному меню
## й у меню Esc (audio/sound_settings.gd): увімк./вимк., гучність, як часто міняється п'єса (від/до хвилин).
## F10 — музика ввімк./вимк., Shift+F10 — гучність музики (user://music.cfg). F9 (Sfx) вимикає й музику.

const Synth := preload("res://audio/music_synth.gd")
const WorldEnv := preload("res://characters/world_env.gd")
const Ruins := preload("res://world/ruins.gd")
const CFG := "user://music.cfg"
const BUS := "Music"
const RATE: int = 22050
const OFF_DB: float = -60.0
const FADE_DB_S: float = 10.0          # швидкість зміни гучності шару, дБ/с
const PIECE_MIN_S: float = 180.0       # типово п'єса звучить 3–5 хвилин (у налаштуваннях — period_min/max)
const PIECE_MAX_S: float = 300.0
const PERIOD_LIMITS: Array = [1, 20]   # межі періодичності в налаштуваннях, хвилини
const MAKEUP_DB: float = 6.0           # підсилення компресора шини: без нього музика тонула під фоном Sfx
const MOOD_HOLD_S: float = 3.0         # новий настрій має протриматися стільки, щоб змінити п'єсу (бій — одразу)
const VOLUMES: Array = [1.0, 0.75, 0.5, 0.25]
const PAN: Array = [-0.7, -0.5, -0.3, -0.1, 0.1, 0.3, 0.5, 0.7]
# Склад з посилання Huzzah на артефакт: #mix-maj-tim-cas-ser-dud-hps-pos-tpt-bel — тема головного меню
const THEME: Dictionary = {"mode": "maj", "ids": ["tim", "cas", "ser", "dud", "hps", "pos", "tpt", "bel"]}
# Пули інструментів за настроєм: r ударні, h орган і бас, m мелодія, x рідкісні; n — скільки брати з кожної групи
const MOODS: Dictionary = {
	"theme": {"mode": "maj", "bpm": [92, 100]},
	"city_day": {"mode": "maj", "bpm": [96, 108], "r": ["tam", "cas", "bod", "tri", "dar"], "h": ["lut", "hps", "pos", "hgy", "piz", "hrm"],
		"m": ["flt", "man", "vln", "cla", "obo", "hrp"], "x": ["gus", "dul", "nyk", "dud", "ser"], "n": [1, 2, 2, 1]},
	"city_night": {"mode": "min", "bpm": [76, 88], "r": [], "h": ["pos", "hrm", "gam", "lut", "hps"],
		"m": ["hrp", "flt", "cel", "vc", "obo"], "x": ["glh", "kot", "nyk"], "n": [0, 2, 2, 1]},
	"wild_day": {"mode": "maj", "bpm": [86, 100], "r": ["bod", "tim", "tai", "tam"], "h": ["gam", "cb", "hgy", "lut", "piz"],
		"m": ["vc", "hrn", "flt", "obo", "hrp", "cla"], "x": ["dud", "nyk", "kot", "shg", "sit", "gus"], "n": [1, 2, 2, 1]},
	"wild_night": {"mode": "min", "bpm": [70, 84], "r": [], "h": ["pos", "cb", "gam", "hrm"],
		"m": ["vc", "hrp", "cel", "flt"], "x": ["glh", "thr", "ond", "kot"], "n": [0, 2, 1, 2]},
	"cursed": {"mode": "min", "bpm": [68, 80], "r": ["tim", "tai"], "h": ["org", "cb", "hgy"],
		"m": ["vc", "bel", "bsn"], "x": ["thr", "ond", "glh", "jaw", "shg", "ser"], "n": [1, 2, 1, 2]},
	"ruins": {"mode": "min", "bpm": [74, 86], "r": ["tim"], "h": ["org", "pos", "gam"],
		"m": ["bel", "cel", "vc"], "x": ["glh", "thr", "kot"], "n": [1, 1, 2, 1]},
	"danger": {"mode": "min", "bpm": [100, 110], "r": ["tim", "tai", "sn", "gc"], "h": ["cb", "piz", "org"],
		"m": ["hrn", "tpt", "vc", "bsn"], "x": ["ser", "jaw"], "n": [2, 2, 2, 1]},
	"battle": {"mode": "min", "bpm": [112, 124], "r": ["tim", "gc", "sn", "tai", "cym"], "h": ["cb", "piz", "org"],
		"m": ["tpt", "hrn", "vln", "vc"], "x": ["ser"], "n": [3, 2, 2, 1]},
	"sleep": {"mode": "maj", "bpm": [64, 74], "r": [], "h": ["pos", "hrm"], "m": ["hrp", "cel"], "x": ["glh", "kot"], "n": [0, 1, 1, 1]},
}
# Біоми, де вдень лунає мажор (вода, берег, ліс); решта — мінор
const MAJOR_BIOMES: Array = [1, 2, 3]

var enabled: bool = true
var volume: float = 0.8
var period_min: float = 3.0            # нова п'єса не раніше, хвилин
var period_max: float = 5.0            # і не пізніше, хвилин
var auto: bool = true                  # false у тестових скриптах (-s): музика не грає сама
var mood: String = ""                  # настрій поточної п'єси
var mods: Dictionary = {}              # стан героя: tired, hungry, cursed, menu
var piece: Dictionary = {}             # {plan, layers: [{player, id, cat, target}], age, length}
var history: Array = []                # плани зіграних п'єс (для тестів), останні 16
var _rng := RandomNumberGenerator.new()
var _thread: Thread = null
var _job: Dictionary = {}              # план, що рендериться
var _synth: Variant = null             # [рендер у роботі] (для abort)
var _ready_pieces: Dictionary = {}     # настрій → готові {plan, streams}
var _old: Array = []                   # шари попередньої п'єси, що згасають
var _want: String = ""                 # настрій, що проситься
var _want_t: float = 0.0
var _ctx_t: float = 0.0
var _ctx: Dictionary = {}
var _loop_pos: float = 0.0
var _themed: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	for a in OS.get_cmdline_args():
		if a == "-s" or a == "--script":
			auto = false
	_bus()
	_load_cfg()
	_apply_volume()


func _bus() -> void:
	if AudioServer.get_bus_index(BUS) >= 0:
		return
	AudioServer.add_bus()
	var i: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, BUS)
	AudioServer.set_bus_send(i, "Master")
	var rv := AudioEffectReverb.new()     # зал замість згортки артефакту
	rv.room_size = 0.7
	rv.damping = 0.45
	rv.wet = 0.22
	rv.dry = 0.95
	AudioServer.add_bus_effect(i, rv)
	var lp := AudioEffectLowPassFilter.new()   # утома й сон: глухіший звук
	lp.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(i, lp)
	var ph := AudioEffectPhaser.new()      # прокляття: «пливе» звук
	ph.rate_hz = 0.3
	ph.depth = 0.6
	AudioServer.add_bus_effect(i, ph)
	AudioServer.set_bus_effect_enabled(i, 2, false)
	var cmp := AudioEffectCompressor.new()
	cmp.threshold = -18.0
	cmp.ratio = 3.0
	cmp.gain = MAKEUP_DB
	AudioServer.add_bus_effect(i, cmp)
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -1.0
	AudioServer.add_bus_effect(i, lim)


# =====================================================================
# НАЛАШТУВАННЯ
# =====================================================================
func set_enabled(on: bool) -> void:
	enabled = on
	_apply_volume()
	_save_cfg()


func set_volume(v: float) -> void:
	volume = clampf(v, 0.0, 1.0)
	_apply_volume()
	_save_cfg()


## Як часто міняється п'єса: від a до b хвилин (1–20). Поточна п'єса теж підлаштовується
func set_period(a: float, b: float) -> void:
	period_min = clampf(minf(a, b), PERIOD_LIMITS[0], PERIOD_LIMITS[1])
	period_max = clampf(maxf(a, b), PERIOD_LIMITS[0], PERIOD_LIMITS[1])
	if not piece.is_empty():
		piece["length"] = clampf(float(piece["length"]), period_min * 60.0, period_max * 60.0)
	_save_cfg()


## Одразу перейти до нової п'єси (кнопка в налаштуваннях)
func skip() -> void:
	if not piece.is_empty():
		piece["length"] = float(piece["age"])


## Гучність шини Music — власна (повзунок у налаштуваннях); F9 (усі звуки вимкнено) глушить і музику
func bus_db() -> float:
	var sfx: Node = get_node_or_null("/root/Sfx")
	var on: bool = enabled and volume > 0.0 and (sfx == null or bool(sfx.get("enabled")))
	if not on:
		return OFF_DB
	return linear_to_db(maxf(volume, 0.001)) + (-4.0 if mods.get("menu", false) else 0.0) \
		+ (-3.0 if mods.get("tired", false) else 0.0)


func _apply_volume() -> void:
	var i: int = AudioServer.get_bus_index(BUS)
	if i < 0:
		return
	var db: float = bus_db()
	AudioServer.set_bus_volume_db(i, db)
	AudioServer.set_bus_mute(i, db <= OFF_DB)


func _load_cfg() -> void:
	var c := ConfigFile.new()
	if c.load(CFG) == OK:
		enabled = bool(c.get_value("music", "enabled", true))
		volume = clampf(float(c.get_value("music", "volume", 0.8)), 0.0, 1.0)
		period_min = clampf(float(c.get_value("music", "period_min", 3.0)), PERIOD_LIMITS[0], PERIOD_LIMITS[1])
		period_max = clampf(float(c.get_value("music", "period_max", 5.0)), period_min, PERIOD_LIMITS[1])


func _save_cfg() -> void:
	var c := ConfigFile.new()
	c.set_value("music", "enabled", enabled)
	c.set_value("music", "volume", volume)
	c.set_value("music", "period_min", period_min)
	c.set_value("music", "period_max", period_max)
	c.save(CFG)


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or k.keycode != KEY_F10:
		return
	if k.shift_pressed:
		var i: int = 0
		for j in VOLUMES.size():
			if absf(float(VOLUMES[j]) - volume) < 0.01:
				i = j
		set_volume(VOLUMES[(i + 1) % VOLUMES.size()])
	else:
		set_enabled(not enabled)
	get_viewport().set_input_as_handled()


# =====================================================================
# ОБСТАНОВКА → НАСТРІЙ
# =====================================================================
## Що зараз довкола героя: місце, біом, ніч, погода, сон, утома, голод, прокляття, здоров'я, руїни, меню
func context() -> Dictionary:
	var c: Dictionary = {"kind": "", "biome": 4, "night": false, "weather": "", "sleeping": false, "energy": 1.0,
		"hunger": 1.0, "curse": 0.0, "health": 1.0, "ruins": false, "menu": false}
	var game: Node = Worlds.game if is_instance_valid(Worlds.game) else null
	if game == null or game.get("ready_done") == false:
		return c
	c["kind"] = Worlds.current_kind()
	c["menu"] = Worlds.menu_open()
	var a: Actor = Worlds.hero_actor()
	match c["kind"]:
		"overworld":
			var body: Dictionary = Worlds.hero_body()
			var cam: Variant = game.get("cam_pos")
			var focus: Vector2 = body["pos"] if not body.is_empty() else (cam if cam is Vector2 else Vector2.ZERO)
			var env: Dictionary = WorldEnv.sample(game, focus)
			c["biome"] = int(env.get("biome", 4))
			c["night"] = bool(env.get("night", false))
			c["weather"] = String(env.get("weather", ""))
			if not body.is_empty() and game.has_method("biome_at"):
				c["ruins"] = not Ruins.near(game, focus).is_empty()
		"city":
			var city: Node = Worlds.current_node()
			if city != null and city.get("hero_pos") != null and city.has_method("env_at"):
				c["night"] = bool(city.env_at(city.hero_pos).get("night", false))
			if city != null and city.get("hero") != null:
				a = city.hero
	if a != null:
		c["sleeping"] = a.sleeping
		c["energy"] = _frac(a, "energy")
		c["hunger"] = _frac(a, "hunger")
		c["health"] = _frac(a, "health")
		c["curse"] = maxf(_frac(a, "radiation"), 1.0 if a.has_condition("radiation_sickness") else 0.0)
	return c


static func _frac(a: Actor, r: String) -> float:
	return clampf(float(a.res.get(r, 0.0)) / maxf(a.max_of(r), 0.001), 0.0, 1.0)


## Настрій п'єси за обстановкою (чиста функція — її перевіряють тести)
static func mood_of(c: Dictionary) -> String:
	var kind: String = String(c.get("kind", ""))
	if kind == "":
		return "theme"
	if kind == "battle":
		return "battle"
	if bool(c.get("sleeping", false)):
		return "sleep"
	var cursed_land: bool = int(c.get("biome", 4)) >= 7 and kind == "overworld"
	if float(c.get("health", 1.0)) < 0.35 or (cursed_land and bool(c.get("night", false))):
		return "danger"
	if kind == "city":
		return "city_night" if bool(c.get("night", false)) else "city_day"
	if bool(c.get("ruins", false)):
		return "ruins"
	if cursed_land or float(c.get("curse", 0.0)) >= 0.6:
		return "cursed"
	return "wild_night" if bool(c.get("night", false)) else "wild_day"


## Стан героя, що змінює звучання поверх настрою
static func mods_of(c: Dictionary) -> Dictionary:
	return {"tired": float(c.get("energy", 1.0)) < 0.3, "hungry": float(c.get("hunger", 1.0)) < 0.25,
		"cursed": float(c.get("curse", 0.0)) >= 0.3, "menu": bool(c.get("menu", false)),
		"storm": String(c.get("weather", "")) == "storm", "rain": String(c.get("weather", "")) in ["rain", "fog"],
		"snow": String(c.get("weather", "")) == "snow"}


## План п'єси: лад, темп, тональність, інструменти (id), розлад у центах для прокляття, бонусні шари
static func plan_for(m: String, c: Dictionary, rng: RandomNumberGenerator, themed: bool = false,
		len_min: float = PIECE_MIN_S, len_max: float = PIECE_MAX_S) -> Dictionary:
	var pool: Dictionary = MOODS.get(m, MOODS["wild_day"])
	var md: Dictionary = mods_of(c)
	var plan: Dictionary = {"mood": m, "mode": String(pool["mode"]), "key": rng.randi_range(-3, 2),
		"bpm": float(rng.randi_range(int(pool["bpm"][0]), int(pool["bpm"][1]))), "ids": [], "detune": {}, "bonus": [],
		"seed": rng.randi(), "length": rng.randf_range(len_min, maxf(len_min, len_max))}
	if m == "theme" or (m == "city_day" and themed):
		plan["mode"] = THEME["mode"]
		plan["ids"] = THEME["ids"].duplicate()
		plan["key"] = 0
	else:
		if m == "wild_day":
			plan["mode"] = "maj" if int(c.get("biome", 4)) in MAJOR_BIOMES else "min"
		var n: Array = (pool["n"] as Array).duplicate()
		if md["tired"]:
			n[0] = 0
		if md["storm"] and n[0] == 0:
			n[0] = 1
		var cats: Array = ["r", "h", "m", "x"]
		for ci in cats.size():
			var opts: Array = (pool.get(cats[ci], []) as Array).duplicate()
			if cats[ci] == "r" and md["storm"] and not "tim" in opts:
				opts.append("tim")
			if cats[ci] == "m" and md["snow"] and not "cel" in opts:
				opts.append("cel")
			_shuffle(opts, rng)
			for i in mini(int(n[ci]), opts.size()):
				plan["ids"].append(opts[i])
		if md["cursed"] and not m in ["theme", "battle"]:
			var eerie: Array = ["thr", "jaw", "glh"]
			_shuffle(eerie, rng)
			if not eerie[0] in plan["ids"]:
				plan["ids"].append(eerie[0])
		if md["hungry"] and plan["ids"].size() > 4:
			plan["ids"] = plan["ids"].slice(0, 4)
	if md["hungry"] or md["rain"]:
		plan["mode"] = "min" if m != "theme" else plan["mode"]
	if md["rain"] or md["tired"]:
		plan["bpm"] = roundf(float(plan["bpm"]) * 0.9)
	if md["cursed"] and m != "theme":
		for id in plan["ids"]:
			if Synth.inst(id).get("cat", "") in ["m", "x"] and rng.randf() < 0.5:
				plan["detune"][id] = rng.randf_range(-22.0, 22.0)
	plan["ids"] = plan["ids"].slice(0, 8)
	for b in Synth.data().get("bonus", []):
		var ok: bool = true
		for need in b.get("need", []):
			if not need in plan["ids"]:
				ok = false
		if ok:
			plan["bonus"].append(String(b["id"]))
	return plan


static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var t: Variant = a[i]
		a[i] = a[j]
		a[j] = t


# =====================================================================
# РЕНДЕР У ФОНОВОМУ ПОТОЦІ
# =====================================================================
## Рендер плану в потоці виклику: {plan, streams: [{id, cat, stream}]}
static func render(plan: Dictionary, rate: int = RATE, holder: Array = []) -> Dictionary:
	var out: Array = []
	var all: Array = (plan["ids"] as Array) + (plan["bonus"] as Array)
	for i in all.size():
		var id: String = all[i]
		var s = Synth.new(rate, float(plan["bpm"]), String(plan["mode"]), int(plan["key"]), int(plan["seed"]) + i)
		s.detune_c = float(plan["detune"].get(id, 0.0))
		if not holder.is_empty():
			holder[0] = s
		var x: Dictionary = Synth.inst(id)
		var pan: float = float(PAN[i % PAN.size()]) if i < plan["ids"].size() else 0.0
		var st: AudioStreamWAV = s.render_stream(id, float(x.get("trim", 1.0)), pan)
		if s.abort:
			return {}
		out.append({"id": id, "cat": String(x.get("cat", "bonus")), "stream": st})
	return {"plan": plan, "streams": out}


func _render_async(plan: Dictionary) -> void:
	if _thread != null:
		return
	_job = plan
	var holder: Array = [null]
	_synth = holder
	_thread = Thread.new()
	_thread.start(func() -> Dictionary: return render(plan, RATE, holder))


func _poll_thread() -> void:
	if _thread == null or _thread.is_alive():
		return
	var res: Variant = _thread.wait_to_finish()
	_thread = null
	_synth = null
	if res is Dictionary and not res.is_empty():
		_ready_pieces[String(res["plan"]["mood"])] = res
	elif not _job.is_empty():
		push_warning("Music: рендер п'єси «%s» не вдався" % _job.get("mood", ""))
	_job = {}


func _exit_tree() -> void:
	stop_render()


## Зупинити рендер (вихід із гри, тести)
func stop_render() -> void:
	if _thread == null:
		return
	if _synth is Array and _synth[0] != null:
		_synth[0].abort = true
	_thread.wait_to_finish()
	_thread = null
	_synth = null
	_job = {}


# =====================================================================
# ВІДТВОРЕННЯ
# =====================================================================
## Пустити готову п'єсу: нові шари з тиші, старі згасають
func start_piece(ready: Dictionary) -> void:
	for l in piece.get("layers", []):
		l["target"] = OFF_DB
		_old.append(l)
	var layers: Array = []
	for e in ready["streams"]:
		var p := AudioStreamPlayer.new()
		p.bus = BUS
		p.stream = e["stream"]
		p.volume_db = OFF_DB
		add_child(p)
		layers.append({"player": p, "id": e["id"], "cat": e["cat"], "target": OFF_DB, "on": false})
	for l in layers:
		l["player"].play()
	var plan: Dictionary = ready["plan"]
	piece = {"plan": plan, "layers": layers, "age": 0.0, "length": float(plan["length"]), "loops": 0}
	mood = String(plan["mood"])
	_loop_pos = 0.0
	print("Music: п'єса «%s» %s, %d уд/хв, %.0f с: %s" % [mood, plan["mode"], int(plan["bpm"]), float(plan["length"]),
		", ".join(plan["ids"] + plan["bonus"])])   # видно в logs/godot.log — так перевіряється, що музика грає
	history.append(plan)
	if history.size() > 16:
		history.pop_front()
	_arrange(true)


## Які шари звучать у цьому колі петлі (кожні 4 такти): гармонія й перша мелодія завжди, решта — за настроєм
func _arrange(first: bool = false) -> void:
	var layers: Array = piece.get("layers", [])
	if layers.is_empty():
		return
	var m: String = mood
	var perc_p: float = {"battle": 1.0, "danger": 0.9, "city_day": 0.75, "wild_day": 0.6, "theme": 0.8}.get(m, 0.4)
	if mods.get("tired", false):
		perc_p = 0.0
	var opt_p: float = 0.45 if mods.get("hungry", false) else 0.7
	var ending: bool = float(piece["age"]) > float(piece["length"]) - 20.0
	var lead_done: bool = false
	for l in layers:
		var on: bool
		match String(l["cat"]):
			"h":
				on = true
			"r":
				on = not first and _rng.randf() < perc_p
			"bonus":
				on = not first
			_:
				if not lead_done:
					lead_done = true
					on = true
				else:
					on = not first and _rng.randf() < opt_p
		if ending and l["cat"] != "h":
			on = false
		l["on"] = on
		l["target"] = 0.0 if on else OFF_DB


func _process(delta: float) -> void:
	_poll_thread()
	_fade(delta)
	if not auto:
		return
	_ctx_t -= delta
	if _ctx_t <= 0.0:
		_ctx_t = 1.0
		_ctx = context()
		mods = mods_of(_ctx)
		_update_bus()
	var want: String = mood_of(_ctx) if not _ctx.is_empty() else "theme"
	if want != _want:
		_want = want
		_want_t = 0.0
	_want_t += delta
	tick(delta)


## Логіка зміни п'єс (окремо від _process, щоб тести могли крутити час)
func tick(delta: float) -> void:
	var want: String = _want if _want != "" else mood_of(_ctx)
	var stable: bool = _want_t >= MOOD_HOLD_S or want == "battle" or mood == ""
	if not piece.is_empty():
		piece["age"] = float(piece["age"]) + delta
		var p0: AudioStreamPlayer = piece["layers"][0]["player"] if not piece["layers"].is_empty() else null
		if p0 != null and p0.playing:
			var pos: float = p0.get_playback_position()
			if pos < _loop_pos - 0.5:
				piece["loops"] = int(piece["loops"]) + 1
				_arrange()
			_loop_pos = pos
	var change: bool = piece.is_empty() or (stable and want != mood) or float(piece.get("age", 0.0)) >= float(piece.get("length", 0.0))
	if change:
		var target: String = want if stable or piece.is_empty() else mood
		if _ready_pieces.has(target):
			var r: Dictionary = _ready_pieces[target]
			_ready_pieces.erase(target)
			start_piece(r)
		else:
			if _thread != null and String(_job.get("mood", "")) != target:
				stop_render()     # рендерилось про запас для іншого настрою — зараз потрібен цей
			if _thread == null:
				_render_async(_next_plan(target))
	elif _thread == null and not _ready_pieces.has(mood):
		# наступна п'єса того самого настрою готується заздалегідь
		_render_async(_next_plan(mood))
	elif _thread == null and mood != "theme" and not _ready_pieces.has("battle"):
		# бій починається раптово — його п'єса чекає напоготові
		_render_async(_next_plan("battle"))


func _next_plan(m: String) -> Dictionary:
	var themed: bool = false
	if m == "city_day":
		themed = not _themed or _rng.randf() < 0.2
		_themed = true
	var plan: Dictionary = plan_for(m, _ctx, _rng, themed, period_min * 60.0, period_max * 60.0)
	# та сама п'єса двічі поспіль не звучить
	if not history.is_empty() and history[-1].get("ids") == plan["ids"] and m != "theme":
		plan = plan_for(m, _ctx, _rng, false, period_min * 60.0, period_max * 60.0)
	return plan


func _fade(delta: float) -> void:
	var speed: float = FADE_DB_S * (3.0 if mood == "battle" else 1.0) * delta
	for l in piece.get("layers", []):
		var p: AudioStreamPlayer = l["player"]
		p.volume_db = move_toward(p.volume_db, float(l["target"]), speed)
	for i in range(_old.size() - 1, -1, -1):
		var p: AudioStreamPlayer = _old[i]["player"]
		p.volume_db = move_toward(p.volume_db, OFF_DB, speed * 1.5)
		if p.volume_db <= OFF_DB + 0.5:
			p.queue_free()
			_old.remove_at(i)


func _update_bus() -> void:
	_apply_volume()
	var i: int = AudioServer.get_bus_index(BUS)
	if i < 0:
		return
	var lp: AudioEffectLowPassFilter = AudioServer.get_bus_effect(i, 1)
	lp.cutoff_hz = 1800.0 if bool(_ctx.get("sleeping", false)) else (2600.0 if mods.get("tired", false) else 20000.0)
	AudioServer.set_bus_effect_enabled(i, 2, mods.get("cursed", false))


## Що грає зараз: назви інструментів (для довідки й тестів)
func now_playing() -> Array:
	var out: Array = []
	for l in piece.get("layers", []):
		if l["on"]:
			out.append(String(Synth.inst(l["id"]).get("name", l["id"])))
	return out

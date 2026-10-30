extends Node
## Звуки (питання Q15, Huzzah 2026-10-24: «вільні звуки CC0»): кроки, бій, інтерфейс, фон карти й міста.
## Автозавантаження Sfx саме стежить за світом через Worlds (карта, місто, бій), тому чужі скрипти не правляться.
## Джерело й ліцензія кожного файлу — data/audio/sounds.json і ЗВУКИ_CC0.txt у корені гри.
## F9 — звук увімк./вимк. (запам'ятовується в user://audio.cfg).

const MANIFEST := "res://data/audio/sounds.json"
const CFG := "user://audio.cfg"
const WorldEnv := preload("res://characters/world_env.gd")
const VOICES: int = 14
const STEP_S: float = 0.42            # реальних секунд між кроками
const OFF_DB: float = -60.0
const FADE_DB_S: float = 30.0         # швидкість згасання фону, дБ за секунду
# Покриття під ногами за номерами біомів game.BIOME_NAMES
const SURFACE: Array = ["", "", "step_sand", "step_soft", "step_gravel", "step_soft", "step_gravel",
	"step_bones", "step_bones", "step_bones"]
# Фонові петлі: ім'я → звук
const BEDS: Dictionary = {"wind": "amb_wind", "desert": "amb_desert", "water": "amb_water_1",
	"rumble": "amb_rumble", "fire": "amb_fire"}

var enabled: bool = true
var volume: float = 0.8               # загальна гучність звуків 0..1
var sounds: Dictionary = {}           # id → запис із sounds.json
var streams: Dictionary = {}          # id → AudioStream
var groups: Dictionary = {}           # «step_gravel» → [step_gravel_0, …]
var played: Array = []                # останні зіграні id (для тестів)
var _voices: Array = []
var _beds: Dictionary = {}            # ім'я → {player, target}
var _queue: Array = []                # відкладені звуки {t, id, db, pitch}
var _rng := RandomNumberGenerator.new()
var _step_t: float = 0.0
var _life_t: float = 4.0              # до наступного звуку життя (птах, собака, сокира)
var _last_pos := Vector2.INF
var _last_city_pos := Vector2.INF
var _last_bld: int = -2
var _watch: Dictionary = {}           # минулі значення: вікно героя, карта, сон, гроші, руїни
var _battle_core: Object = null
var _kind: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_buses()
	_load_cfg()
	_load_manifest()
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "Sfx"
		add_child(p)
		_voices.append(p)
	for bed in BEDS:
		var p := AudioStreamPlayer.new()
		p.bus = "Ambience"
		p.volume_db = OFF_DB
		add_child(p)
		var s: AudioStream = _stream(BEDS[bed])
		if s != null:
			s = s.duplicate()
			if s is AudioStreamOggVorbis:
				s.loop = true
			p.stream = s
		_beds[bed] = {"player": p, "target": OFF_DB}
	get_tree().node_added.connect(_on_node_added)
	_apply_volume()


func _buses() -> void:
	for b in ["Sfx", "Ambience"]:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var i: int = AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")


func _load_manifest() -> void:
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	if f == null:
		push_warning("Sfx: нет " + MANIFEST)
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	if not (d is Dictionary) or not (d.get("sounds") is Dictionary):
		push_warning("Sfx: испорчен " + MANIFEST)
		return
	sounds = d["sounds"]
	for id in sounds:
		var g: String = group_of(id)
		if not groups.has(g):
			groups[g] = []
		groups[g].append(id)


## «step_gravel_3» → «step_gravel»; «swing» → «swing»
static func group_of(id: String) -> String:
	var i: int = id.rfind("_")
	return id.substr(0, i) if i > 0 and id.substr(i + 1).is_valid_int() else id


func _stream(id: String) -> AudioStream:
	if streams.has(id):
		return streams[id]
	var s: AudioStream = null
	if sounds.has(id):
		var path: String = String(sounds[id].get("file", ""))
		if ResourceLoader.exists(path):
			s = load(path)
	streams[id] = s
	return s


func has_sound(name: String) -> bool:
	return sounds.has(name) or groups.has(name)


## Зіграти звук за id або групою (випадковий із групи) з гучністю db і розкидом висоти
func play(name: String, db: float = 0.0, pitch: float = 1.0, spread: float = 0.06) -> bool:
	var id: String = name
	if not sounds.has(id):
		if not groups.has(name):
			return false
		var g: Array = groups[name]
		id = g[_rng.randi() % g.size()]
	played.append(id)
	if played.size() > 64:
		played.pop_front()
	if not enabled:
		return false
	var s: AudioStream = _stream(id)
	if s == null:
		return false
	var p: AudioStreamPlayer = _free_voice()
	p.stream = s
	p.volume_db = db
	p.pitch_scale = maxf(0.3, pitch * (1.0 + _rng.randf_range(-spread, spread)))
	p.play()
	return true


func play_later(name: String, after_s: float, db: float = 0.0, pitch: float = 1.0) -> void:
	_queue.append({"t": after_s, "id": name, "db": db, "pitch": pitch})


func _free_voice() -> AudioStreamPlayer:
	for p in _voices:
		if not p.playing:
			return p
	var oldest: AudioStreamPlayer = _voices[0]
	for p in _voices:
		if p.get_playback_position() > oldest.get_playback_position():
			oldest = p
	return oldest


func set_enabled(on: bool) -> void:
	enabled = on
	_apply_volume()
	_save_cfg()


func set_volume(v: float) -> void:
	volume = clampf(v, 0.0, 1.0)
	_apply_volume()
	_save_cfg()


func _apply_volume() -> void:
	var db: float = linear_to_db(maxf(volume, 0.001)) if enabled else OFF_DB
	for b in ["Sfx", "Ambience"]:
		var i: int = AudioServer.get_bus_index(b)
		if i >= 0:
			AudioServer.set_bus_volume_db(i, db)
			AudioServer.set_bus_mute(i, not enabled)


func _load_cfg() -> void:
	var c := ConfigFile.new()
	if c.load(CFG) == OK:
		enabled = bool(c.get_value("audio", "enabled", true))
		volume = clampf(float(c.get_value("audio", "volume", 0.8)), 0.0, 1.0)


func _save_cfg() -> void:
	var c := ConfigFile.new()
	c.set_value("audio", "enabled", enabled)
	c.set_value("audio", "volume", volume)
	c.save(CFG)


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and k.keycode == KEY_F9:
		set_enabled(not enabled)
		get_viewport().set_input_as_handled()


# =====================================================================
# ІНТЕРФЕЙС: клацання будь-якої кнопки
# =====================================================================
func _on_node_added(n: Node) -> void:
	if n is BaseButton and not n.pressed.is_connected(_on_button):
		n.pressed.connect(_on_button)


func _on_button() -> void:
	play("ui_click", -6.0, 1.0, 0.03)


# =====================================================================
# КОЖЕН КАДР
# =====================================================================
func _process(delta: float) -> void:
	_run_queue(delta)
	for bed in _beds:
		_beds[bed]["target"] = OFF_DB
	var game: Node = Worlds.game if is_instance_valid(Worlds.game) else null
	if game != null and game.get("ready_done") == false:
		game = null   # карта ще будується: погода й висоти не готові
	if game == null:
		_kind = ""
		_battle_core = null
		_fade_beds(delta)
		return
	var kind: String = Worlds.current_kind()
	if kind != _kind:
		_on_world_changed(_kind, kind)
		_kind = kind
	match kind:
		"overworld":
			_overworld(game, delta)
		"city":
			_city(Worlds.current_node(), delta)
		"battle":
			_battle(Worlds.current_node())
	_watch_common(game, kind)
	_fade_beds(delta)


func _run_queue(delta: float) -> void:
	for i in range(_queue.size() - 1, -1, -1):
		_queue[i]["t"] -= delta
		if _queue[i]["t"] <= 0.0:
			var e: Dictionary = _queue[i]
			_queue.remove_at(i)
			play(e["id"], e["db"], e["pitch"])


func _fade_beds(delta: float) -> void:
	for bed in _beds:
		var p: AudioStreamPlayer = _beds[bed]["player"]
		if p.stream == null:
			continue
		var target: float = _beds[bed]["target"] if enabled else OFF_DB
		p.volume_db = move_toward(p.volume_db, target, FADE_DB_S * delta)
		if p.volume_db > OFF_DB + 1.0 and not p.playing:
			p.play(_rng.randf() * p.stream.get_length())
		elif p.volume_db <= OFF_DB + 1.0 and p.playing:
			p.stop()


func _bed(name: String, db: float) -> void:
	if _beds.has(name):
		_beds[name]["target"] = maxf(_beds[name]["target"], db)


func _on_world_changed(from: String, to: String) -> void:
	_last_pos = Vector2.INF
	_last_city_pos = Vector2.INF
	_last_bld = -2
	_battle_core = null
	_watch.clear()
	if to == "city" or from == "city":
		play("gate", -4.0)
	if to == "battle":
		play("draw_weapon", -2.0)


# =====================================================================
# ЗАГАЛЬНА КАРТА
# =====================================================================
func _overworld(game: Node, delta: float) -> void:
	var body: Dictionary = Worlds.hero_body()
	var global: bool = _is(game, "global_map")
	var zoom: float = float(game.get("zoom")) if game.get("zoom") != null else 1.0
	var cam: Variant = game.get("cam_pos")
	var focus: Vector2 = (cam if cam is Vector2 else Vector2.ZERO) if body.is_empty() or global else body["pos"]
	var env: Dictionary = WorldEnv.sample(game, focus)
	var biome: int = int(env.get("biome", 4))
	var night: bool = bool(env.get("night", false))
	var sleeping: bool = not body.is_empty() and body["actor"].sleeping
	var dim: float = (-8.0 if global else 0.0) + (-8.0 if sleeping else 0.0) + (-6.0 if Worlds.menu_open() else 0.0)
	_overworld_beds(game, focus, biome, night, dim)
	if body.is_empty() or global or sleeping or Worlds.menu_open():
		_last_pos = Vector2.INF if body.is_empty() else body["pos"]
		return
	# Кроки: тільки коли герой справді йде, гучніше на близькому зумі
	var pos: Vector2 = body["pos"]
	var moved: bool = _last_pos != Vector2.INF and pos.distance_to(_last_pos) > 0.001 and pos.distance_to(_last_pos) < 500.0
	_last_pos = pos
	if moved:
		_step_t -= delta
		if _step_t <= 0.0:
			_step_t = STEP_S
			var surf: String = SURFACE[biome] if biome < SURFACE.size() else "step_gravel"
			if surf != "":
				var near: float = clampf((log(maxf(zoom, 0.001)) - log(0.05)) / (log(1.0) - log(0.05)), 0.0, 1.0)
				play(surf, lerpf(-20.0, -4.0, near), 0.85 if biome == 5 else 1.0)
	else:
		_step_t = minf(_step_t, 0.1)
	_life(delta, biome, night, -4.0 + dim)


func _overworld_beds(game: Node, focus: Vector2, biome: int, night: bool, dim: float) -> void:
	var cursed: bool = biome >= 7
	_bed("wind", (-14.0 if biome in [4, 6, 8] else -22.0) + dim)
	if biome == 4 or biome == 8:
		_bed("desert", (-12.0 if biome == 8 else -16.0) + dim)
	if cursed:
		_bed("rumble", -14.0 + dim)
	var wet: bool = biome in [1, 2]
	if not wet and game.has_method("biome_at"):
		for o in [Vector2(40, 0), Vector2(-40, 0), Vector2(0, 40), Vector2(0, -40)]:
			if int(game.biome_at(focus + o)) == 1:
				wet = true
				break
	if wet:
		_bed("water", -12.0 + dim)


## Звуки життя довкола: птахи в лісі вдень, краплі на болоті, кажани вночі в проклятих землях
func _life(delta: float, biome: int, night: bool, db: float) -> void:
	_life_t -= delta
	if _life_t > 0.0:
		return
	_life_t = _rng.randf_range(7.0, 18.0)
	if biome == 3 and not night:
		play("bird_jay", db - 6.0, 1.0, 0.12)
	elif biome == 5 or biome == 9:
		play("drip", db - 4.0, 1.0, 0.15)
	elif night and (biome >= 7 or biome == 3):
		play("bats", db - 8.0)


# =====================================================================
# МІСТО
# =====================================================================
func _city(city: Node, delta: float) -> void:
	if city == null or city.get("hero_pos") == null:
		return
	var pos: Vector2 = city.hero_pos
	var map: Object = city.get("map")
	var bld: int = int(map.building_at(pos)) if map != null and map.has_method("building_at") else -1
	var inside: bool = bld >= 0
	var env: Dictionary = city.env_at(pos) if city.has_method("env_at") else {}
	var night: bool = bool(env.get("night", false))
	var sleeping: bool = city.get("hero") != null and city.hero.sleeping
	var dim: float = (-8.0 if sleeping else 0.0) + (-6.0 if Worlds.menu_open() else 0.0)
	_bed("wind", (-28.0 if inside else -20.0) + dim)
	if inside:
		_bed("fire", -12.0 + dim)
	if _last_bld != -2 and bld != _last_bld:
		play("door_open" if inside else "door_close", -6.0)
	_last_bld = bld
	var moved: bool = _last_city_pos != Vector2.INF and pos.distance_to(_last_city_pos) > 0.0005 and pos.distance_to(_last_city_pos) < 50.0
	_last_city_pos = pos
	if moved and not sleeping:
		_step_t -= delta
		if _step_t <= 0.0:
			_step_t = STEP_S
			if inside:
				play("step_soft", -8.0, 1.25)
			else:
				play("step_gravel", -6.0)
	else:
		_step_t = minf(_step_t, 0.1)
	# Життя міста вдень: собака, сокира, кузня, птахи
	_life_t -= delta
	if _life_t <= 0.0:
		_life_t = _rng.randf_range(6.0, 14.0)
		if not night and not sleeping:
			var far: float = -18.0 + (-8.0 if inside else 0.0) + dim
			match _rng.randi() % 4:
				0: play("dog_bark", far - 2.0, 1.0, 0.1)
				1: play("hit_wood", far, 0.9, 0.08)
				2: play("anvil", far - 2.0, 1.0, 0.05)
				_: play("bird_jay", far, 1.0, 0.12)
		elif night and not inside:
			if _rng.randf() < 0.3:
				play("dog_bark", -24.0, 0.9, 0.1)


# =====================================================================
# БІЙ
# =====================================================================
func _battle(scene: Node) -> void:
	_bed("wind", -24.0)
	if scene == null:
		return
	var core: Object = scene.get("core")
	if core == null or core == _battle_core:
		return
	_battle_core = core
	connect_core(core)


## Підписка на сигнали ядра бою (battle_core.gd); викликається й тестами
func connect_core(core: Object) -> void:
	if core.has_signal("acted") and not core.acted.is_connected(_on_acted):
		core.acted.connect(_on_acted)
	if core.has_signal("moved") and not core.moved.is_connected(_on_moved):
		core.moved.connect(_on_moved)
	if core.has_signal("finished") and not core.finished.is_connected(_on_finished):
		core.finished.connect(_on_finished)


func _on_moved(_c, path: Array) -> void:
	for i in mini(path.size(), 5):
		play_later("step_gravel", 0.16 * i, -8.0)


func _on_acted(c, what: String, data: Dictionary) -> void:
	match what:
		"roll":
			play("ui_dice", -16.0, 1.0, 0.1)
		"attack":
			_attack_sound(c, data)
		"ability":
			_ability_sound(data.get("ability"))


func _attack_sound(c, data: Dictionary) -> void:
	var w: Object = data.get("weapon")
	var res: Dictionary = data.get("res", {})
	var t: Object = data.get("target")
	var ranged: bool = w != null and _is(w, "ranged")
	var wid: String = String(w.get("id")) if w != null else ""
	play("whoosh" if ranged else "swing", -4.0)
	if c != null and not _is(c, "human") and ("bite" in wid or "hound" in wid) and _rng.randf() < 0.4:
		play("dog_bark", -8.0, 1.0, 0.1)
	if not bool(res.get("hit", false)):
		return
	var hit: String = "hit_blade"
	var dtype: String = ""
	if w != null and w.get("damage") is Array and not w.damage.is_empty():
		dtype = String(w.damage[0].get("type", ""))
	if wid == "fists":
		hit = "hit_fist"
	elif dtype == "bludgeoning":
		hit = "hit_wood"
	play_later(hit, 0.12 if not ranged else 0.25, -2.0)
	if bool(res.get("crit", false)):
		play_later("hit_metal", 0.16, -4.0)
	_death_check(t, 0.35)


func _ability_sound(ab: Object) -> void:
	var id: String = String(ab.get("id")) if ab != null else ""
	match id:
		"fire_flask":
			play("ignite", -4.0)
			play_later("explode", 0.45, -6.0)
		"healing_salve", "second_wind":
			play("ui_success", -8.0)
		"howl":
			play("dog_bark", -4.0, 0.8)
		"war_cry":
			play("ui_warning", -6.0, 0.8)
		"net", "poison_dart":
			play("whoosh", -4.0)
		_:
			play("swing", -6.0)


func _death_check(t: Object, after_s: float) -> void:
	# Шкода знімається одразу після сигналу, тому дивимося на ціль трохи пізніше
	if t == null:
		return
	get_tree().create_timer(after_s * 0.5).timeout.connect(func() -> void:
		if is_instance_valid(t) and (_is(t, "dead") or _is(t, "down")):
			play("die_man" if _is(t, "human") else "dog_die", -4.0, 1.0, 0.05))


func _on_finished(outcome: String) -> void:
	match outcome:
		"win":
			play_later("ui_victory", 0.6, -6.0)
		"lose":
			play_later("ui_error", 0.6, -6.0, 0.7)
		"flee":
			for i in 4:
				play_later("step_gravel", 0.13 * i, -6.0, 1.1)


# =====================================================================
# ЗАГАЛЬНЕ СТЕЖЕННЯ: вікно героя, глобальна карта, сон, гроші, руїни
# =====================================================================
func _watch_common(game: Node, kind: String) -> void:
	var owner: Node = Worlds.current_node() if kind == "city" else game.get("cast")
	var win: Object = owner.get("window") if owner != null else null
	_changed("window", is_instance_valid(win) and _is(win, "visible"), func(on: bool) -> void:
		play("ui_open" if on else "ui_close", -8.0))
	var map_on: bool = _is(game, "global_map") if kind == "overworld" else (kind == "city" and _is(Worlds.current_node(), "_map_view"))
	_changed("map", map_on, func(on: bool) -> void:
		play("map_open" if on else "map_close", -4.0))
	var a: Actor = Worlds.hero_actor()
	if kind == "city" and Worlds.current_node().get("hero") != null:
		a = Worlds.current_node().hero
	if a != null:
		_changed("sleep", a.sleeping, func(on: bool) -> void:
			play("ui_sleep" if on else "ui_wake", -8.0))
	var money: int = int(Worlds.inventory.get("money", 0))
	if kind == "city":
		var bag: Variant = Worlds.current_node().get("bag")
		if bag is Dictionary:
			money = int(bag.get("money", money))
	if _watch.has("money") and _watch.get("money_kind") == kind:
		if money > int(_watch["money"]):
			play("pickup", -6.0)
		elif money < int(_watch["money"]):
			play("ui_buy", -6.0)
	_watch["money"] = money
	_watch["money_kind"] = kind
	var cast: Object = game.get("cast")
	var looted: int = cast.ruins_looted.size() if cast != null and cast.get("ruins_looted") is Dictionary else 0
	_changed("ruins", looted, func(_n) -> void:
		play("dig", -4.0)
		play_later("dig", 0.3, -6.0)
		play_later("pickup", 0.7, -6.0))


## Властивість об'єкта дорівнює true (у заглушок і чужих сцен її може не бути)
static func _is(o: Object, prop: String) -> bool:
	return o != null and o.get(prop) == true


## Звук лише при зміні значення (перше спостереження — мовчки)
func _changed(key: String, value: Variant, on_change: Callable) -> void:
	if _watch.has(key) and _watch[key] != value:
		if not (value is int and value < int(_watch[key])):
			on_change.call(value)
	_watch[key] = value

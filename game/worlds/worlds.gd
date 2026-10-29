extends Node
## Перемикач світів (автозавантаження Worlds, project.godot [autoload]).
## Загальна карта (game.tscn) — основний світ. Місто й бій — окремі сцени поверх неї:
## загальна карта на цей час лишається в дереві, але схована й не приймає введення; годинник і погода йдуть далі.
## Світи лежать стеком: карта → місто → бій. leave() знімає верхній світ і повертає в той, звідки прийшли:
## з міста — на загальну карту до брами міста, з бою — туди, де бій почався (карта чи місто).
##
## Місто: res://city/city_world.tscn (гілка «Світ міста»).
##   Після add_child: city.enter(city_id, hero: Actor|null, ctx). Вихід: сигнал exit_requested(city_id, gate_id)
##   або Worlds.leave(). Збереження: to_dict() / load_dict(state) (load_dict одразу після enter).
## Бій: res://battle/battle.tscn (гілка «Бойова сцена»).
##   До add_child: battle.setup(req). Вихід: сигнал battle_finished(result)
##   {outcome: win|lose|flee, origin, return_pos, game_minutes, dead: [actor_id]}.
##   На час бою годинник світу стоїть, після бою до нього додається result.game_minutes.
## Міста на карті (гілка «Міста на загальній карті»): якщо в game є settlements із сигналом
##   enter_requested(s), вхід у місто йде через нього; вихід — до settlements.exit_point(id).
## Потреби героя в місті рахує characters/cast.gd за ігровими годинами, як на карті (світ не має викликати tick).
## Збереження: ключ "worlds" у world_save.gd (to_dict / load_dict). Бій у збереженні — його запит:
##   після завантаження бій починається заново з тими самими ворогами.
## Гроші й речі героя: Worlds.inventory {money, items: {id: count}} — один словник на гру, за посиланням у ctx
##   міста й req бою, зберігається тут. Стан кожного міста (to_dict) пам'ятається за city_id між візитами.
## Випадкові напади: на кожен пройдений героєм км запитується battle/encounters.gd roll_on_km(hero, env, rng).
## Налагоджувальних клавіш немає (питання Q07, Huzzah 2026-10-24: F8, K і заглушки з гри прибрано). Заглушки міста й бою
## живуть у tests/doubles/ і підставляються лише тестами: test_doubles = {"city": Script, "battle": Script} і "stub": true.

signal world_changed(kind: String, id: String)
signal battle_finished(result: Dictionary)

const GAME_SCENE := "res://game.tscn"
const CITY_SCENE := "res://city/city_world.tscn"
const BATTLE_SCENE := "res://battle/battle.tscn"
const ENCOUNTERS := "res://battle/encounters.gd"
const WorldEnv := preload("res://characters/world_env.gd")
const JournalScript := preload("res://characters/quest_journal.gd")
const WearRef := preload("res://characters/wear.gd")
const ALLY_RADIUS_M: float = 60.0
const FADE_S: float = 0.25
const AUTOSAVE_SEC: float = 300.0
# Ключі місцевості для бою, за номерами біомів game.BIOME_NAMES (0 — як battle/encounters.gd terrain_key: пустка)
const TERRAIN_KEYS: Array = ["wasteland", "water", "coast", "forest", "wasteland", "swamp", "mountains",
	"rad_forest", "rad_wasteland", "rad_swamp"]

var game: Node2D = null          # загальна карта (game.tscn)
var stack: Array = []            # світи поверх карти: {kind: "city"|"battle", id, node, ctx | req}
var busy: bool = false           # іде перехід (затемнення)
var test_doubles: Dictionary = {}  # лише для тестів: {"city"|"battle": Script} — заглушки з tests/doubles/
var _linked_settlements: Object = null
var _fade_layer: CanvasLayer
var _fade: ColorRect
var _clock_was_paused: bool = false
var _hero_controlled: bool = false
var _autosave_t: float = 0.0
var inventory: Dictionary = {"money": 0, "items": {}}
var city_states: Dictionary = {}   # city_id -> to_dict() міста після останнього візиту
var codex: Dictionary = {}          # кодекс: id знайдених записок -> ігрові секунди (world/codex.gd); живе довше за героя
var left_carts: Array = []         # Q32: вози загиблих героїв на карті [{pos: [x, y], until: с гри, items}] (hero_death.gd)
var battles_won: int = 0           # перемоги героя в боях за гру (доручення «перемогти» в містах, city_growth.gd)
var _km_actor: Actor = null
var sleep_fx: CanvasLayer = null
var journal: CanvasLayer          # журнал завдань на J (characters/quest_journal.gd), пише гравець
var _journal_typing: bool = false
var idle_attacks: bool = true      # пункт 17: напади, поки герой стоїть або спить у полі (тести вимикають)
var _idle_s: float = 0.0           # ігрові секунди, які герой простояв на місці з останньої перевірки
var _idle_pos := Vector2.INF
var _idle_clock: float = -1.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	_rng.randomize()
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 120
	add_child(_fade_layer)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_layer.add_child(_fade)
	# Сон героя: повіки й прискорений час (ui/sleep_fx.gd)
	sleep_fx = preload("res://ui/sleep_fx.gd").new()
	sleep_fx.worlds = self
	add_child(sleep_fx)
	journal = JournalScript.new()
	add_child(journal)
	journal.setup(hero_actor, func() -> float: return game.clock.total_seconds if game != null else 0.0, _journal_place, _journal_weather)
	# Карта могла увійти в дерево раніше за автозавантаження (запуск тестів через -s)
	for n in get_tree().root.get_children():
		_on_node_added(n)


# =====================================================================
# СТАН
# =====================================================================
func current_kind() -> String:
	return "overworld" if stack.is_empty() else String(stack[-1]["kind"])


func current_id() -> String:
	return "" if stack.is_empty() else String(stack[-1]["id"])


func current_node() -> Node:
	return game if stack.is_empty() else stack[-1]["node"]


func is_away() -> bool:
	return not stack.is_empty()


func is_battle() -> bool:
	return current_kind() == "battle"


# Чи відкрите меню паузи гри (Esc): поки відкрите, світ не рухає героя
func menu_open() -> bool:
	return game != null and (bool(game.menu_open) or (journal != null and journal.visible))


func _journal_place() -> String:
	if is_away():
		return place_text()
	var b: Dictionary = hero_body()
	return game.place_line(b["pos"]) if not b.is_empty() and game.has_method("place_line") else ""


func _journal_weather() -> String:
	var b: Dictionary = hero_body()
	if b.is_empty() or game.physics == null:
		return ""
	return String(game.physics.weather_here(b["pos"]).get("name", "")).to_lower()


func hero_body() -> Dictionary:
	if game == null or game.get("cast") == null:
		return {}
	return game.cast.hero


func hero_actor() -> Actor:
	var b: Dictionary = hero_body()
	return b["actor"] if not b.is_empty() else null


# Рядок «де герой» для заголовка збереження
func place_text() -> String:
	for i in range(stack.size() - 1, -1, -1):
		var e: Dictionary = stack[i]
		if e["kind"] == "city":
			var s: Dictionary = e["ctx"].get("settlement", {})
			return I18n.t("Город: ") + String(s.get("name", e["id"]))
	return ""


# =====================================================================
# ПІДКЛЮЧЕННЯ ДО ЗАГАЛЬНОЇ КАРТИ
# =====================================================================
func _on_node_added(n: Node) -> void:
	if n.scene_file_path == GAME_SCENE and n != game:
		_attach(n)


func _attach(g: Node2D) -> void:
	_drop_all()
	game = g
	_linked_settlements = null
	_km_actor = null
	_autosave_t = 0.0
	# Старт: на герої шкіряна куртка — це його обладунок у бою (раніше обладунок видавався з налаштувань бою
	# невидимо й зняти його було не можна; patch 01 до 2D 07). У сумці дві фляги води (питання Q20: без води герой
	# помирав за ~22 реальні хвилини; швидкість потреб не змінюємо)
	inventory = start_inventory()
	city_states = {}
	left_carts = []
	codex = {}
	battles_won = 0
	g.tree_exiting.connect(_on_game_exiting.bind(g))


# Сумка нового героя: у новій грі й після загибелі колишнього (characters/hero_death.gd)
func start_inventory() -> Dictionary:
	return {"money": 0, "items": {"leather_jacket": 1, "water_flask": 2}, "equipped": {"body": "leather_jacket"}}


# Карта вивантажується (вихід у меню): усі світи поверх неї йдуть разом із нею
func _on_game_exiting(g: Node) -> void:
	if g != game:
		return
	_drop_all()
	game = null


func _drop_all() -> void:
	for e in stack:
		if is_instance_valid(e["node"]):
			e["node"].queue_free()
	stack.clear()
	busy = false
	_fade.color.a = 0.0


func _process(delta: float) -> void:
	if game == null or not is_instance_valid(game) or not game.ready_done:
		return
	var st: Object = game.get("settlements")
	if st != null and st != _linked_settlements and st.has_signal("enter_requested"):
		_linked_settlements = st
		st.enter_requested.connect(_on_enter_requested)
	var h: Actor = hero_actor()
	if h != _km_actor:
		_km_actor = h
		if h != null and not h.km_passed.is_connected(_on_hero_km.bind(h)):
			h.km_passed.connect(_on_hero_km.bind(h))
	_track_idle()
	# Поки відкритий журнал, клавіші — у поле запису: карта й герой стоять
	if journal != null and journal.visible != _journal_typing:
		_journal_typing = journal.visible
		game.typing = _journal_typing
	# Карта, поки її не видно, не рахує автозбереження — рахуємо тут (у бою не зберігаємо)
	if is_away() and not is_battle():
		_autosave_t += delta
		if _autosave_t >= AUTOSAVE_SEC:
			_autosave_t = 0.0
			game.save_world()


# Випадковий напад у дорозі (правила шансу — у гілці бою, battle/encounters.gd)
func _on_hero_km(_total_km: int, h: Actor) -> void:
	if h != hero_actor() or is_away() or busy or not h.alive or not ResourceLoader.exists(ENCOUNTERS):
		return
	var enc: Script = load(ENCOUNTERS)
	var env: Dictionary = WorldEnv.sample(game, hero_body()["pos"])
	# Механіка 6: дорога зношує одяг на герої
	for t in WearRef.on_km(inventory):
		game.event_text = t
		game.event_timer = 5.0
	if enc.roll_on_km(h, env, _rng):
		start_battle({})


## Пункт 17: герой стоїть, спить або відпочиває в полі — щогодини гри кидається напад за маскуванням
func _track_idle() -> void:
	var b: Dictionary = hero_body()
	var now: float = game.clock.total_seconds
	if b.is_empty() or is_away() or busy or not b["actor"].alive or not idle_attacks or bool(game.cast.get("hold_hero")):
		_idle_clock = now
		_idle_pos = Vector2.INF
		_idle_s = 0.0
		return
	var p: Vector2 = b["pos"]
	if _idle_clock >= 0.0 and _idle_pos != Vector2.INF and p.distance_to(_idle_pos) < 2.0:
		_idle_s += maxf(now - _idle_clock, 0.0)
	else:
		_idle_s = 0.0
	_idle_pos = p
	_idle_clock = now
	if _idle_s >= 3600.0:
		var hours: float = floor(_idle_s / 3600.0)
		_idle_s -= hours * 3600.0
		noise_check(hours)


## Перевірка нападу за hours годин на місці (стоїть, спить, шукає у полі); true — почався бій
func noise_check(hours: float) -> bool:
	var h: Actor = hero_actor()
	if h == null or is_away() or busy or not idle_attacks or not ResourceLoader.exists(ENCOUNTERS):
		return false
	var enc: Script = load(ENCOUNTERS)
	var env: Dictionary = WorldEnv.sample(game, hero_body()["pos"])
	if not enc.roll_for_hours(h, env, hours, _rng):
		return false
	var slept: bool = h.sleeping
	h.set_sleep(false)
	game.event_text = I18n.t("Застали врасплох во сне!") if slept else I18n.t("Вас выследили!")
	game.event_timer = 4.0
	start_battle({"ambush": slept})
	return true


func _on_enter_requested(s: Dictionary) -> void:
	var id: String = String(s.get("city_id", s.get("id", "")))
	# entry: gate — через браму, sneak — пробрався через стіну, caught — спійманий під час спроби; side — бік міста
	var ctx: Dictionary = {"settlement": s, "entry": String(s.get("entry", "gate")), "side": String(s.get("side", "south"))}
	var st: Object = game.get("settlements")
	if st != null and st.has_method("exit_point"):
		var p: Variant = st.exit_point(String(s.get("id", id)))
		if p is Vector2:
			ctx["return_pos"] = p
	enter_city(id, ctx)


func _unhandled_input(event: InputEvent) -> void:
	if game == null or not game.ready_done or busy:
		return
	# J — журнал завдань (і на карті, і в місті); не в бою й не поки набирають текст
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_J \
			and journal != null and not journal.visible and hero_actor() != null and not is_battle() and not game.typing and not game.menu_open:
		journal.open()
		get_viewport().set_input_as_handled()
		return
	# У місті й у бою Esc, який світ не забрав собі, відкриває меню паузи гри
	if is_away():
		if event.is_action_pressed("ui_cancel"):
			game._toggle_menu()
			get_viewport().set_input_as_handled()
		return


# =====================================================================
# МІСТО
# =====================================================================
## Увійти в місто. ctx: {return_pos: Vector2 метри дошки, settlement: запис міста, gate: "south"…, stub: true — заглушка}.
## Місто отримує ще game, clock, inventory і state (що було в місті минулого візиту; його ж — у load_dict)
func enter_city(city_id: String, ctx: Dictionary = {}) -> bool:
	if busy or game == null or not game.ready_done:
		return false
	busy = true
	await _fade_to(1.0)
	_enter_city_now(city_id, ctx)
	await _fade_to(0.0)
	busy = false
	return true


func _enter_city_now(city_id: String, ctx: Dictionary, state: Variant = null) -> Node:
	var c: Dictionary = ctx.duplicate()
	if not c.has("return_pos"):
		c["return_pos"] = _exit_point(city_id, c, hero_body().get("pos", game.cam_pos))
	c["game"] = game
	c["clock"] = game.clock
	c["inventory"] = inventory
	if state == null and city_states.has(city_id):
		state = city_states[city_id]
	if state != null:
		c["state"] = state
	_deactivate_top()
	var node: Node = _make(CITY_SCENE, "city", bool(c.get("stub", false)))
	get_tree().root.add_child(node)
	if node.has_signal("exit_requested"):
		node.exit_requested.connect(func(_cid: String, gate_id: String) -> void: _leave_when_free(node, {"gate_id": gate_id}))
	stack.append({"kind": "city", "id": city_id, "node": node, "ctx": c})
	node.enter(city_id, hero_actor(), c)
	if state is Dictionary and node.has_method("load_dict"):
		node.load_dict(state)
	world_changed.emit("city", city_id)
	return node


# Точка біля брами міста на загальній карті: від вузла міст, інакше запам'ятована під час входу
func _exit_point(city_id: String, ctx: Dictionary, fallback: Vector2) -> Vector2:
	var st: Object = game.get("settlements") if game != null else null
	var sid: String = String(ctx.get("settlement", {}).get("id", city_id))
	if st != null and st.has_method("exit_point") and not bool(ctx.get("stub", false)):
		var p: Variant = st.exit_point(sid)
		if p is Vector2 and p != Vector2.ZERO:
			return p
	return ctx.get("return_pos", fallback)


# =====================================================================
# БІЙ
# =====================================================================
## Почати бій. req (див. гілку «Бойова сцена»): enemies: Array[Actor], allies: Array[Actor] (за замовчуванням герой),
## return_pos (за замовчуванням де стоїть герой); origin, terrain, biome, hot, night, seed дописуються самі
func start_battle(req: Dictionary = {}) -> bool:
	if busy or game == null or not game.ready_done:
		return false
	busy = true
	await _fade_to(1.0)
	_start_battle_now(req)
	await _fade_to(0.0)
	busy = false
	return true


func _start_battle_now(req: Dictionary, state: Variant = null) -> Node:
	var r: Dictionary = req.duplicate()
	var here: Vector2 = _overworld_pos()
	if not r.has("origin"):
		r["origin"] = "overworld" if stack.is_empty() else "%s:%s" % [stack[-1]["kind"], stack[-1]["id"]]
	if not r.has("return_pos"):
		r["return_pos"] = here
	var b: int = int(game.biome_at(here))
	r["biome"] = int(r.get("biome", b))
	if not r.has("terrain"):
		r["terrain"] = TERRAIN_KEYS[clampi(int(r["biome"]), 0, TERRAIN_KEYS.size() - 1)]
	if not r.has("hot"):
		r["hot"] = bool(game.is_hot(here)) if game.has_method("is_hot") else false
	if not r.has("night"):
		r["night"] = game.physics.sun_elevation_deg_at(deg_to_rad(game.MAP_LAT_DEG), 0.0) < 0.0
	if not r.has("allies"):
		r["allies"] = _allies_near_hero()
	if not r.has("starter"):
		r["starter"] = _starter_zone(here)
	r["inventory"] = inventory
	if not r.has("enemies"):
		r["enemies"] = []
	if not r.has("seed"):
		r["seed"] = randi()
	_deactivate_top()
	if stack.size() <= 0 or stack[-1]["kind"] != "battle":
		_clock_was_paused = game.clock.paused
	game.clock.paused = true
	var node: Node = _make(BATTLE_SCENE, "battle", bool(r.get("stub", false)))
	if node.has_method("setup"):
		node.setup(r)
	get_tree().root.add_child(node)
	if node.has_signal("battle_finished"):
		node.battle_finished.connect(func(result: Dictionary) -> void: _leave_when_free(node, result))
	stack.append({"kind": "battle", "id": String(r["origin"]), "node": node, "req": r})
	if state is Dictionary and node.has_method("load_dict"):
		node.load_dict(state)
	world_changed.emit("battle", String(r["origin"]))
	return node


# Герой і живі неплячі НПС поруч із ним на загальній карті (у місті — лише герой)
func _allies_near_hero() -> Array:
	var hb: Dictionary = hero_body()
	if hb.is_empty() or not hb["actor"].alive:
		return []
	var out: Array = [hb["actor"]]
	if stack.is_empty():
		for b in game.cast.bodies:
			var a: Actor = b["actor"]
			if not b["hero"] and a.alive and not a.sleeping and b["pos"].distance_to(hb["pos"]) <= ALLY_RADIUS_M:
				out.append(a)
	return out


# Де герой на загальній карті (для міста — точка біля його брами)
## Q30: у міста, що росте, на етапі «Форт» (у STARTER_KM) бандити нападають по одному (battle/encounters.gd)
func _starter_zone(p: Vector2) -> bool:
	var st: Node = game.get("settlements") if game != null else null
	if st == null or not st.has_method("growth_stage_near") or not ResourceLoader.exists(ENCOUNTERS):
		return false
	return st.growth_stage_near(p, float(load(ENCOUNTERS).STARTER_KM) * 1000.0) == 0


func _overworld_pos() -> Vector2:
	for i in range(stack.size() - 1, -1, -1):
		if stack[i]["kind"] == "city":
			return stack[i]["ctx"]["return_pos"]
	return hero_body().get("pos", game.cam_pos)


func _apply_battle_result(e: Dictionary, result: Dictionary) -> void:
	game.clock.paused = _clock_was_paused
	var minutes: float = float(result.get("game_minutes", 0.0))
	if minutes > 0.0:
		game.clock.skip(minutes * 60.0)
	var dead: Array = result.get("dead", [])
	for a in e["req"].get("allies", []):
		if a is Actor and a.alive and dead.has(a.actor_id):
			a.die("wounds")
	if String(result.get("outcome", "")) == "win":
		battles_won += 1
		# Механіка 2: убиті звірі — на розбирання (Camp.butcher), шаблони з actor_id вороґів
		var enc: Script = load(ENCOUNTERS) if ResourceLoader.exists(ENCOUNTERS) else null
		if enc != null:
			result["beasts"] = e["req"].get("enemies", []).map(func(a): return enc.kind_of(a)).filter(func(k): return k != "")
	# Механіка 6: бій зношує зброю й обладунок
	var worn: PackedStringArray = WearRef.on_battle(inventory)
	if not worn.is_empty():
		result["text"] = (String(result.get("text", "")) + " " + " ".join(worn)).strip_edges()
	result["origin"] = result.get("origin", e["req"]["origin"])
	result["return_pos"] = result.get("return_pos", e["req"]["return_pos"])


# =====================================================================
# ПОВЕРНЕННЯ
# =====================================================================
## Покинути верхній світ і повернутися туди, звідки в нього увійшли
func leave(result: Dictionary = {}) -> bool:
	if busy or stack.is_empty():
		return false
	busy = true
	await _fade_to(1.0)
	_leave_now(result)
	await _fade_to(0.0)
	busy = false
	return true


# Вихід, про який попросив сам світ (брама, кінець бою): якщо йде затемнення, чекаємо його, а не губимо прохання —
# інакше місто з leaving = true або закінчений бій лишаються на екрані назавжди
func _leave_when_free(node: Node, result: Dictionary) -> void:
	while busy and is_inside_tree():
		await get_tree().process_frame
	if not stack.is_empty() and stack[-1]["node"] == node:
		leave(result)


func _leave_now(result: Dictionary) -> void:
	var e: Dictionary = stack.pop_back()
	if e["kind"] == "battle":
		_apply_battle_result(e, result)
	elif is_instance_valid(e["node"]) and e["node"].has_method("to_dict"):
		# Місто позначає, що з нього вийшли (на відміну від збереження всередині міста)
		if e["node"].has_method("prepare_leave"):
			e["node"].prepare_leave()
		city_states[e["id"]] = e["node"].to_dict()
	if is_instance_valid(e["node"]):
		e["node"].queue_free()
	if stack.is_empty():
		var hb: Dictionary = hero_body()
		var p: Vector2 = Vector2.INF
		if e["kind"] == "city":
			p = _exit_point(e["id"], e["ctx"], e["ctx"]["return_pos"])
		elif e["kind"] == "battle" and result.get("return_pos") is Vector2:
			p = result["return_pos"]
		if p != Vector2.INF:
			if not hb.is_empty():
				hb["pos"] = p
				hb["target"] = p
			game.cam_pos = p
			game._clamp_camera()
		_activate_overworld()
		if e["kind"] == "battle" and game.cast != null and game.cast.has_method("after_battle"):
			game.cast.after_battle(result)
	else:
		var top: Node = stack[-1]["node"]
		_show_tree(top)
		top.process_mode = Node.PROCESS_MODE_INHERIT
		if top.has_method("world_resumed"):
			top.world_resumed(result)
	if e["kind"] == "battle":
		battle_finished.emit(result)
	world_changed.emit(current_kind(), current_id())


# =====================================================================
# ПОКАЗАТИ / СХОВАТИ СВІТИ
# =====================================================================
func _deactivate_top() -> void:
	if stack.is_empty():
		_deactivate_overworld()
	else:
		var top: Node = stack[-1]["node"]
		top.process_mode = Node.PROCESS_MODE_DISABLED
		_hide_tree(top)


# Карта схована: немає малюнка, підказки, введення; годинник, погода й НПС живуть (це діти game і cast)
func _deactivate_overworld() -> void:
	if game.typing:
		game._close_goto()
	game.set_process(false)
	game.set_process_input(false)
	game.set_process_unhandled_input(false)
	for n in [game.terrain_layer, game.hud_panel, game.observer_marker]:
		_hide_tree(n)
	var cast: Node = game.get("cast")
	if cast != null:
		_hero_controlled = cast.controls_hero
		cast.controls_hero = false   # герой на карті стоїть, але його потреби йдуть за годинником
		cast.set("hero_away", true)  # і cast не витрачає його сили на місці: у місті їх рахує місто
		cast.set_process_unhandled_input(false)
		_hide_tree(cast)
	var st: Node = game.get("settlements")
	if st != null:
		st.process_mode = Node.PROCESS_MODE_DISABLED
		_hide_tree(st)


func _activate_overworld() -> void:
	game.set_process(true)
	game.set_process_input(true)
	game.set_process_unhandled_input(true)
	for n in [game.terrain_layer, game.hud_panel, game.observer_marker]:
		_show_tree(n)
	var cast: Node = game.get("cast")
	if cast != null:
		cast.controls_hero = _hero_controlled and not cast.hero.is_empty() and cast.hero["actor"].alive
		cast.set("hero_away", false)
		cast.set_process_unhandled_input(true)
		_show_tree(cast)
	var st: Node = game.get("settlements")
	if st != null:
		st.process_mode = Node.PROCESS_MODE_INHERIT
		_show_tree(st)


# Ховає вузол і всі шари CanvasLayer під ним (шари не ховаються разом із батьком), запам'ятовуючи, що було видно
func _hide_tree(n: Node) -> void:
	if n == null or n.has_meta("_worlds_vis"):
		return
	var saved: Array = []
	var list: Array = [n] + n.find_children("*", "CanvasLayer", true, false)
	for c in list:
		if c is CanvasItem or c is CanvasLayer:
			saved.append([c, c.visible])
			c.visible = false
	n.set_meta("_worlds_vis", saved)


func _show_tree(n: Node) -> void:
	if n == null or not n.has_meta("_worlds_vis"):
		return
	for pair in n.get_meta("_worlds_vis"):
		if is_instance_valid(pair[0]):
			pair[0].visible = pair[1]
	n.remove_meta("_worlds_vis")


func _make(path: String, kind: String, stub: bool) -> Node:
	if stub and test_doubles.has(kind):
		return test_doubles[kind].new()
	var ps: PackedScene = load(path)
	return ps.instantiate()


func _fade_to(a: float) -> void:
	if not is_inside_tree():
		return
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", a, FADE_S)
	await tw.finished


# =====================================================================
# ЗБЕРЕЖЕННЯ
# =====================================================================
func to_dict() -> Dictionary:
	var list: Array = []
	for e in stack:
		var node: Node = e["node"]
		var state: Variant = node.to_dict() if is_instance_valid(node) and node.has_method("to_dict") else null
		if e["kind"] == "city":
			var c: Dictionary = {}
			for k in ["return_pos", "settlement", "stub", "entry", "side", "gate"]:
				if e["ctx"].has(k):
					c[k] = e["ctx"][k]
			list.append({"kind": "city", "id": e["id"], "ctx": c, "state": state})
		else:
			var r: Dictionary = {}
			for k in e["req"]:
				if k != "allies" and k != "enemies":
					r[k] = e["req"][k]
			r["allies_ids"] = e["req"]["allies"].map(func(a): return a.actor_id)
			r["enemies_dicts"] = e["req"]["enemies"].map(func(a): return a.to_dict())
			list.append({"kind": "battle", "req": r, "state": state, "clock_was_paused": _clock_was_paused})
	var cities: Dictionary = city_states.duplicate()
	return {"stack": list, "hero_controlled": _hero_controlled if is_away() else false,
		"inventory": inventory, "city_states": cities, "battles_won": battles_won, "left_carts": left_carts.duplicate(true), "codex": codex.duplicate(),
		"journal": journal.to_array() if journal != null else []}


# Після завантаження карти (world_save.apply_late): заново входить у збережені міста й бій, без затемнення
func load_dict(d: Dictionary) -> void:
	if game == null:
		return
	var list: Array = d.get("stack", []) if d.get("stack") is Array else []
	# Сумка — {money, items}: без цих ключів Trade і місто падають на першому ж зверненні
	var inv: Variant = d.get("inventory", inventory)
	if inv is Dictionary:
		if not (inv.get("items") is Dictionary):
			inv["items"] = {}
		inv["money"] = int(inv.get("money", 0))
		inventory = inv
	city_states = d.get("city_states", {}) if d.get("city_states") is Dictionary else {}
	battles_won = int(d.get("battles_won", 0))
	left_carts = d.get("left_carts", []).duplicate(true) if d.get("left_carts") is Array else []
	codex = d.get("codex", {}).duplicate() if d.get("codex") is Dictionary else {}
	if journal != null:
		journal.load_array(d.get("journal", []))
	if not list.is_empty() and game.get("cast") != null:
		game.cast.controls_hero = bool(d.get("hero_controlled", game.cast.controls_hero))
	for e in list:
		if e["kind"] == "city":
			_enter_city_now(String(e["id"]), e.get("ctx", {}), e.get("state"))
		elif e["kind"] == "battle":
			var r: Dictionary = e["req"].duplicate()
			var allies: Array = []
			for id in r.get("allies_ids", []):
				var a: Actor = _actor_by_id(String(id))
				if a != null:
					allies.append(a)
			r["allies"] = allies
			r["enemies"] = r.get("enemies_dicts", []).map(func(x): return Actor.from_dict(x))
			r.erase("allies_ids")
			r.erase("enemies_dicts")
			var was: bool = bool(e.get("clock_was_paused", false))
			_start_battle_now(r, e.get("state"))
			_clock_was_paused = was


func _actor_by_id(id: String) -> Actor:
	if game.get("cast") == null:
		return null
	for b in game.cast.bodies:
		if b["actor"].actor_id == id:
			return b["actor"]
	return null

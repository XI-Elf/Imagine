extends Node
## Переключатель миров (автозагрузка Worlds, project.godot [autoload]).
## Общая карта (game.tscn) — основной мир. Город и бой — отдельные сцены поверх неё:
## общая карта на это время остаётся в дереве, но спрятана и не принимает ввод; часы и погода идут дальше.
## Миры лежат стеком: карта → город → бой. leave() снимает верхний мир и возвращает в тот, откуда пришли:
## из города — на общую карту к воротам города, из боя — туда, где бой начался (карта или город).
##
## Город: res://city/city_world.tscn (ветка «Мир города»).
##   После add_child: city.enter(city_id, hero: Actor|null, ctx). Выход: сигнал exit_requested(city_id, gate_id)
##   или Worlds.leave(). Сохранение: to_dict() / load_dict(state) (load_dict сразу после enter).
## Бой: res://battle/battle.tscn (ветка «Боевая сцена»).
##   До add_child: battle.setup(req). Выход: сигнал battle_finished(result)
##   {outcome: win|lose|flee, origin, return_pos, game_minutes, dead: [actor_id]}.
##   На время боя часы мира стоят, после боя к ним прибавляется result.game_minutes.
## Города на карте (ветка «Города на общей карте»): если у game есть settlements с сигналом
##   enter_requested(s), вход в город идёт по нему; выход — к settlements.exit_point(id).
## Нужды героя в городе считает characters/cast.gd по игровым часам, как на карте (мир не должен вызывать tick).
## Сохранение: ключ "worlds" в world_save.gd (to_dict / load_dict). Бой в сохранении — его запрос:
##   после загрузки бой начинается заново с теми же врагами.
## Деньги и вещи героя: Worlds.inventory {money, items: {id: count}} — один словарь на игру, по ссылке в ctx
##   города и req боя, сохраняется здесь. Состояние каждого города (to_dict) помнится по city_id между визитами.
## Случайные нападения: на каждый пройденный героем км спрашивается battle/encounters.gd roll_on_km(hero, env, rng).
## Отладочных клавиш нет (вопрос Q07, Huzzah 2026-10-24: F8, K и заглушки из игры убраны). Заглушки города и боя
## живут в tests/doubles/ и подставляются только тестами: test_doubles = {"city": Script, "battle": Script} и "stub": true.

signal world_changed(kind: String, id: String)
signal battle_finished(result: Dictionary)

const GAME_SCENE := "res://game.tscn"
const CITY_SCENE := "res://city/city_world.tscn"
const BATTLE_SCENE := "res://battle/battle.tscn"
const ENCOUNTERS := "res://battle/encounters.gd"
const WorldEnv := preload("res://characters/world_env.gd")
const ALLY_RADIUS_M: float = 60.0
const FADE_S: float = 0.25
const AUTOSAVE_SEC: float = 300.0
# Ключи местности для боя, по номерам биомов game.BIOME_NAMES (0 — как battle/encounters.gd terrain_key: пустошь)
const TERRAIN_KEYS: Array = ["wasteland", "water", "coast", "forest", "wasteland", "swamp", "mountains",
	"rad_forest", "rad_wasteland", "rad_swamp"]

var game: Node2D = null          # общая карта (game.tscn)
var stack: Array = []            # миры поверх карты: {kind: "city"|"battle", id, node, ctx | req}
var busy: bool = false           # идёт переход (затемнение)
var test_doubles: Dictionary = {}  # только для тестов: {"city"|"battle": Script} — заглушки из tests/doubles/
var _linked_settlements: Object = null
var _fade_layer: CanvasLayer
var _fade: ColorRect
var _clock_was_paused: bool = false
var _hero_controlled: bool = false
var _autosave_t: float = 0.0
var inventory: Dictionary = {"money": 0, "items": {}}
var city_states: Dictionary = {}   # city_id -> to_dict() города после последнего визита
var left_carts: Array = []         # Q32: повозки погибших героев на карте [{pos: [x, y], until: с игры, items}] (hero_death.gd)
var battles_won: int = 0           # победы героя в боях за игру (поручения «победить» в городах, city_growth.gd)
var _km_actor: Actor = null
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
	# Карта могла войти в дерево раньше автозагрузки (запуск тестов через -s)
	for n in get_tree().root.get_children():
		_on_node_added(n)


# =====================================================================
# СОСТОЯНИЕ
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


# Открыто ли меню паузы игры (Esc): пока открыто, мир не двигает героя
func menu_open() -> bool:
	return game != null and bool(game.menu_open)


func hero_body() -> Dictionary:
	if game == null or game.get("cast") == null:
		return {}
	return game.cast.hero


func hero_actor() -> Actor:
	var b: Dictionary = hero_body()
	return b["actor"] if not b.is_empty() else null


# Строка «где герой» для заголовка сохранения
func place_text() -> String:
	for i in range(stack.size() - 1, -1, -1):
		var e: Dictionary = stack[i]
		if e["kind"] == "city":
			var s: Dictionary = e["ctx"].get("settlement", {})
			return "Город: " + String(s.get("name", e["id"]))
	return ""


# =====================================================================
# ПОДКЛЮЧЕНИЕ К ОБЩЕЙ КАРТЕ
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
	# Старт: на герое кожаная куртка — это его доспех в бою (раньше доспех давался из настроек боя
	# невидимо и снять его было нельзя; patch 01 к 2D 07). В сумке две фляги воды (вопрос Q20: без воды герой
	# умирал за ~22 реальных минуты; скорость нужд не меняем)
	inventory = start_inventory()
	city_states = {}
	left_carts = []
	battles_won = 0
	g.tree_exiting.connect(_on_game_exiting.bind(g))


# Сумка нового героя: в новой игре и после гибели прежнего (characters/hero_death.gd)
func start_inventory() -> Dictionary:
	return {"money": 0, "items": {"leather_jacket": 1, "water_flask": 2}, "equipped": {"body": "leather_jacket"}}


# Карта выгружается (выход в меню): все миры поверх неё уходят вместе с ней
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
	# Карта, пока её не видно, не считает автосохранение — считаем здесь (в бою не сохраняем)
	if is_away() and not is_battle():
		_autosave_t += delta
		if _autosave_t >= AUTOSAVE_SEC:
			_autosave_t = 0.0
			game.save_world()


# Случайное нападение в пути (правила шанса — в ветке боя, battle/encounters.gd)
func _on_hero_km(_total_km: int, h: Actor) -> void:
	if h != hero_actor() or is_away() or busy or not h.alive or not ResourceLoader.exists(ENCOUNTERS):
		return
	var enc: Script = load(ENCOUNTERS)
	var env: Dictionary = WorldEnv.sample(game, hero_body()["pos"])
	if enc.roll_on_km(h, env, _rng):
		start_battle({})


func _on_enter_requested(s: Dictionary) -> void:
	var id: String = String(s.get("city_id", s.get("id", "")))
	# entry: gate — через ворота, sneak — пробрался через стену, caught — пойман при попытке; side — сторона города
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
	# В городе и в бою Esc, который мир не забрал себе, открывает меню паузы игры
	if is_away():
		if event.is_action_pressed("ui_cancel"):
			game._toggle_menu()
			get_viewport().set_input_as_handled()
		return


# =====================================================================
# ГОРОД
# =====================================================================
## Войти в город. ctx: {return_pos: Vector2 метры доски, settlement: запись города, gate: "south"…, stub: true — заглушка}.
## Город получает ещё game, clock, inventory и state (что было в городе в прошлый визит; его же — в load_dict)
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


# Точка у ворот города на общей карте: от узла городов, иначе запомненная при входе
func _exit_point(city_id: String, ctx: Dictionary, fallback: Vector2) -> Vector2:
	var st: Object = game.get("settlements") if game != null else null
	var sid: String = String(ctx.get("settlement", {}).get("id", city_id))
	if st != null and st.has_method("exit_point") and not bool(ctx.get("stub", false)):
		var p: Variant = st.exit_point(sid)
		if p is Vector2 and p != Vector2.ZERO:
			return p
	return ctx.get("return_pos", fallback)


# =====================================================================
# БОЙ
# =====================================================================
## Начать бой. req (см. ветку «Боевая сцена»): enemies: Array[Actor], allies: Array[Actor] (по умолчанию герой),
## return_pos (по умолчанию где стоит герой); origin, terrain, biome, hot, night, seed дописываются сами
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


# Герой и живые неспящие НПС рядом с ним на общей карте (в городе — только герой)
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


# Где герой на общей карте (для города — точка у его ворот)
## Q30: у растущего города на этапе «Острог» (в STARTER_KM) бандиты нападают по одному (battle/encounters.gd)
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
	result["origin"] = result.get("origin", e["req"]["origin"])
	result["return_pos"] = result.get("return_pos", e["req"]["return_pos"])


# =====================================================================
# ВОЗВРАТ
# =====================================================================
## Покинуть верхний мир и вернуться туда, откуда в него вошли
func leave(result: Dictionary = {}) -> bool:
	if busy or stack.is_empty():
		return false
	busy = true
	await _fade_to(1.0)
	_leave_now(result)
	await _fade_to(0.0)
	busy = false
	return true


# Выход, о котором попросил сам мир (ворота, конец боя): если идёт затемнение, ждём его, а не теряем просьбу —
# иначе город с leaving = true или законченный бой остаются на экране навсегда
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
		# Город помечает, что из него вышли (в отличие от сохранения внутри города)
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
# ПОКАЗАТЬ / СПРЯТАТЬ МИРЫ
# =====================================================================
func _deactivate_top() -> void:
	if stack.is_empty():
		_deactivate_overworld()
	else:
		var top: Node = stack[-1]["node"]
		top.process_mode = Node.PROCESS_MODE_DISABLED
		_hide_tree(top)


# Карта спрятана: нет рисунка, подсказки, ввода; часы, погода и НПС живут (это дети game и cast)
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
		cast.controls_hero = false   # герой на карте стоит, но его нужды идут по часам
		cast.set("hero_away", true)  # и cast не тратит его силы на месте: в городе их считает город
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


# Прячет узел и все слои CanvasLayer под ним (слои не прячутся вместе с родителем), запоминая, что было видно
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
# СОХРАНЕНИЕ
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
		"inventory": inventory, "city_states": cities, "battles_won": battles_won, "left_carts": left_carts.duplicate(true)}


# После загрузки карты (world_save.apply_late): заново входит в сохранённые города и бой, без затемнения
func load_dict(d: Dictionary) -> void:
	if game == null:
		return
	var list: Array = d.get("stack", []) if d.get("stack") is Array else []
	# Сумка — {money, items}: без этих ключей Trade и город падают на первом же обращении
	var inv: Variant = d.get("inventory", inventory)
	if inv is Dictionary:
		if not (inv.get("items") is Dictionary):
			inv["items"] = {}
		inv["money"] = int(inv.get("money", 0))
		inventory = inv
	city_states = d.get("city_states", {}) if d.get("city_states") is Dictionary else {}
	battles_won = int(d.get("battles_won", 0))
	left_carts = d.get("left_carts", []).duplicate(true) if d.get("left_carts") is Array else []
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

extends Node2D
## Мир города: отдельная сцена со своей картой (city_map.gd), своими правилами шага и ворот,
## НПС по распорядку, разговорами, торговлей (trade.gd), обыском тайников и туманом неизведанного.
##
## Контракт с переходами (worlds/worlds.gd):
##   enter(city_id, hero: Actor или null, ctx) — ctx: return_pos, settlement, game, clock, inventory, state, gate,
##   entry ("gate" — по дороге в ворота, "sneak" — пролез через стену, "caught" — пойман у стены), side (сторона стены)
##   exit_requested(city_id, gate_id) — герой вышел в ворота; to_dict() / load_dict() — состояние города.
## Нужды героя (голод, жажда, сон) считает characters/cast.gd по игровым часам, пока город открыт;
## здесь только шаг и запас сил (actor.exert). Без ctx["game"] (сцена запущена отдельно) город
## сам заводит часы и сам считает героя (actor.tick).
##
## Клавиши: WASD — идти, Shift — бежать, E — говорить / осмотреть / обыскать, I — окно героя, Tab — сумка (вкладка окна героя),
## M — план города, колесо — масштаб, 1–9 — выбор в разговоре, Esc — закрыть окно.
## Рост города (city_growth.gd): def — город на нынешнем этапе, full_def — всё описание с пулом будущих домов и жителей;
## задания шести НПС в разговоре, сданное задание — очко роста, новый этап перестраивает город сразу.
## Мышь (city_route.gd): ЛКМ — идти в точку / к жителю (заговорить) / к колодцу, тайнику (как E) / в ворота;
## держать ЛКМ — за курсором, ПКМ — стоп.
## Протоптанные дороги (world/trails.gd, Huzzah 2026-10-28): герой и жители протаптывают траву и поле —
## от 50 проходов клетки тропинка, дальше до грунтовой дороги (рисуется землёй улиц, шаг быстрее).
## Состояние — ключ "trails" в to_dict(), помнится между визитами вместе с остальным городом.

signal exit_requested(city_id: String, gate_id: String)

const CityMap := preload("res://city/city_map.gd")
const Trade := preload("res://city/trade.gd")
const Craft := preload("res://city/craft.gd")
const CityRoute := preload("res://city/city_route.gd")
const WorldEnv := preload("res://characters/world_env.gd")
const R := preload("res://characters/actor_rules.gd")
const Sheet := preload("res://characters/sheet.gd")
const ClockScene := preload("res://game_clock.tscn")
const T = CityMap.T
const Art := preload("res://storybook/art.gd")
const Growth := preload("res://city/city_growth.gd")
const CityMenu := preload("res://city/city_menu.gd")
const Trails := preload("res://world/trails.gd")
const TRAIL_TILES: Array = [CityMap.T.GRASS, CityMap.T.FIELD]   # где видно протоптанное (улицы и площади и так мощёные)
const TRAIL_ALPHA: Array = [0.0, 0.3, 0.5, 0.75, 1.0]
const TRAIL_REFRESH_S: float = 3600.0
## Экран города (city_menu.gd, видео Huzzah 2026-10-23): вход через ворота открывает меню услуг,
## пешая карта — по кнопке «Пройтись по городу», Esc на улице — назад в меню
## (меню — при входе с общей карты; отдельный запуск сцены без "settlement" в ctx — сразу на улице)
var menu: CanvasLayer
var walking: bool = true               # false — открыт экран города
var _gate_in: String = ""              # ворота, через которые вошёл (ими же уходит из меню)
var art_time: float = 0.0
var art_last_hero := Vector2.ZERO
var art_moving: bool = false
var _art_walk: Dictionary = {}          # Actor → шёл ли в этом кадре (НПС)
var _art_face: Dictionary = {}          # Actor → 1 вправо, -1 влево

const DATA_DIR := "res://data/cities/"
const PX: float = 16.0                 # пикселей на метр при масштабе 1
## Повтор текстур земли/стен/крыш: при самом сильном приближении (zoom 3) пиксель картинки 512 px =
## пиксель экрана, при отдалении текстура сжимается (Huzzah 2026-10-23)
const TEX_PERIOD: float = 512.0 / 3.0
const BODY_R: float = 0.35             # радиус тела, м
const START_ZOOM: float = 2.2
const TALK_M: float = 2.4
const LOOK_M: float = 3.4
static var ROLE_NAMES: Dictionary = {
	"innkeeper": I18n.t("хозяин таверны"), "trader": I18n.t("торговка"), "healer": I18n.t("травница"), "smith": I18n.t("кузнец"),
	"guard": I18n.t("стражник"), "elder": I18n.t("олдермен"), "citizen": I18n.t("житель"), "tanner": I18n.t("кожевник"),
}
const ROLE_COLORS: Dictionary = {
	"innkeeper": Color(0.95, 0.6, 0.3), "trader": Color(0.3, 0.85, 0.85), "healer": Color(0.55, 0.9, 0.55),
	"smith": Color(0.75, 0.75, 0.8), "guard": Color(0.9, 0.35, 0.3), "elder": Color(0.8, 0.6, 0.95),
	"citizen": Color(0.55, 0.8, 1.0), "tanner": Color(0.7, 0.5, 0.3),
}

const HeroWindowScript := preload("res://characters/hero_window.gd")
var window: CanvasLayer          # окно героя (characters/hero_window.gd)
var city_id: String = ""
var def: Dictionary = {}               # город на нынешнем этапе роста (Growth.view)
var full_def: Dictionary = {}          # всё описание из JSON
var growth: Dictionary = Growth.new_state()
var stage: int = 0
var test_wins: int = 0                 # победы, если игры нет (сцена отдельно, тесты)
var rules: Dictionary = {}
var display_name: String = ""
var map := CityMap.new()
var trails := Trails.new(1.0)          # протоптанные дороги города (клетка = клетка карты)
var _trails_at: float = -1.0           # игровые секунды последнего пересчёта зарастания
var hero: Actor
var hero_pos := Vector2.ZERO
var hero_dir := Vector2.DOWN
var bag: Dictionary = {}
var own_bag: bool = false
var npcs: Array = []                   # {def, actor, pos, path, path_i, goal, home_pos, work_pos, stock, buys, line_i, wander_t}
var fog := PackedByteArray()           # 1 — клетка уже видена
var discovered: Dictionary = {}        # id дома или места -> true
var looted: Dictionary = {}            # id тайника -> игровые секунды, когда обыскан
var paid_gate: Dictionary = {}         # id ворот -> до каких игровых секунд выпускают ночью
var entry: String = "gate"             # как вошёл: "gate", "sneak" (через стену), "caught" (пойман у стены)
var intruder_until: float = -1.0       # до каких игровых секунд герой — чужак (пролез через стену)
var entered: bool = false
var leaving: bool = false

var game: Node = null                  # общая карта (если город открыт из игры)
var clock: Node = null
var own_clock: bool = false
var ctx: Dictionary = {}
var _last_clock: float = -1.0
var _rng := RandomNumberGenerator.new()
var _hero_bld: int = -1
var _fog_dirty: bool = true
var _map_view: bool = false
var _zoom_before: float = START_ZOOM
var event_text: String = ""
var event_timer: float = 0.0

# Слои рисования
var _ground: Node2D
var _actors: Node2D
var _roofs: Node2D
var _fog: Node2D
var _night: CanvasModulate
var _lights: Array = []
var _hero_light: PointLight2D
var cam: Camera2D
var route: RefCounted                  # ход мышью (city_route.gd)
var _path_layer: Node2D
var _mouse_hold: bool = false
var _hold_t: float = 0.0

# Интерфейс
var _ui: CanvasLayer
var _top: Label
var _status: Label
var _hint: Label
var _event: Label
var _panel: PanelContainer
var _panel_title: Label
var _panel_text: Label
var _panel_box: VBoxContainer
var _buttons: Array = []
var _tabs: HBoxContainer               # вкладки разговора (Q34): Разговор / Поручения / Торговля / Мастерская
var _tab_buttons: Array = []
var _panel_kind: String = ""           # "", "talk", "trade", "craft", "bag", "note"
var _talk_npc: Dictionary = {}
var craft_rng := RandomNumberGenerator.new()   # удача работы своими руками в мастерской (craft.gd)


## Слой с рисованием через Callable: так статичная земля рисуется один раз, а люди каждый кадр
class DrawLayer extends Node2D:
	var fn: Callable
	func _draw() -> void:
		fn.call(self)


func _ready() -> void:
	_setup_nodes()
	craft_rng.randomize()
	# Запуск сцены отдельно (F6 в редакторе): Эшвик и новый герой
	await get_tree().process_frame
	if not entered:
		enter("s001", null, {})


func _setup_nodes() -> void:
	if cam != null:
		return
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_rng.randomize()
	_ground = _layer(_draw_ground)
	_actors = _layer(_draw_actors)
	_roofs = _layer(_draw_roofs)
	route = CityRoute.new(self)
	_path_layer = _layer(func(l: Node2D) -> void: route.draw(l, PX))
	_fog = _layer(_draw_fog)
	_night = CanvasModulate.new()
	add_child(_night)
	cam = Camera2D.new()
	# Герой на экране 60–80 px (вопрос Q09, Huzzah 2026-10-24): 1,9 м × PX × 2,2 ≈ 67 px
	cam.zoom = Vector2(START_ZOOM, START_ZOOM)
	add_child(cam)
	if cam.is_inside_tree():
		cam.make_current()
	_build_ui()
	# Окно героя (characters/hero_window.gd) — то же, что на карте: I — характеристики, Tab — инвентарь
	window = HeroWindowScript.new()
	window.setup(func() -> Actor: return hero, func() -> Dictionary: return bag)
	add_child(window)
	menu = CityMenu.new()
	menu.setup(self)
	add_child(menu)


func _layer(fn: Callable) -> DrawLayer:
	var l := DrawLayer.new()
	l.fn = fn
	add_child(l)
	return l


# =====================================================================
# ВХОД И ВЫХОД
# =====================================================================
func enter(id: String, h: Actor, c: Dictionary) -> void:
	_setup_nodes()
	ctx = c
	var st: Dictionary = c.get("settlement", {})
	full_def = _load_def(id, String(st.get("template", "")))
	def = full_def
	if def.is_empty():
		push_error("city_world: нет описания города %s" % id)
		return
	city_id = id
	rules = def.get("rules", {})
	display_name = String(st.get("name", def.get("name", id)))
	game = c.get("game", null)
	clock = c.get("clock", null)
	if clock == null and game != null:
		clock = game.get("clock")
	if clock == null:
		clock = ClockScene.instantiate()
		clock.start_hour = 10.0
		add_child(clock)
		clock.reset()
		own_clock = true
	hero = h if h != null else Actor.new("hero", I18n.t("Герой"), false, _rng.randi())
	if c.has("inventory"):
		bag = c["inventory"]
		own_bag = false
	elif hero.has_meta("inventory"):
		bag = hero.get_meta("inventory")
		own_bag = true
	else:
		bag = Trade.new_bag(int(rules.get("start_money", 40)))
		own_bag = true
	hero.set_meta("inventory", bag)
	growth = Growth.new_state()
	if c.get("state") is Dictionary and c["state"].get("growth") is Dictionary and String(c["state"].get("city_id", id)) == id:
		growth = _growth_from(c["state"]["growth"])
	stage = Growth.stage(full_def, growth)
	def = Growth.view(full_def, stage)
	map.build(def)
	trails = Trails.new(map.cell_m)
	_trails_at = -1.0
	fog.resize(map.w * map.h)
	fog.fill(0)
	_spawn_npcs()
	_make_lights()
	var gate: Dictionary = _pick_gate(String(c.get("gate", "")))
	hero_pos = map.center_of(Vector2i.ZERO) if gate.is_empty() else Vector2(gate["spawn"][0], gate["spawn"][1]) * map.cell_m
	hero_dir = Vector2.UP
	route.cancel()
	entered = true
	leaving = false
	_last_clock = -1.0
	if c.has("state") and c["state"] is Dictionary and not c["state"].is_empty():
		load_dict(c["state"])
	# Ветка карты кладёт entry/side в запись поселения; Worlds может скопировать их и в ctx
	entry = String(c.get("entry", st.get("entry", "gate")))
	var arrival: String = String(gate.get("name", ""))
	# Загрузка сохранения внутри города: герой там, где был, вход заново не разыгрывается
	var live: bool = c.has("state") and c["state"] is Dictionary and not c["state"].is_empty() and not bool(c["state"].get("left", true))
	match "" if live else entry:
		"sneak":
			var br: Dictionary = _pick_breach(String(c.get("side", st.get("side", ""))))
			if not br.is_empty():
				hero_pos = map.center_of(Vector2i(br["cell"][0], br["cell"][1]))
			intruder_until = clock.total_seconds + float(rules.get("intruder_h", 2.0)) * 3600.0
			arrival = I18n.t("вы перелезли через стену. Не попадайтесь страже")
		"caught":
			var jail: Dictionary = map.building_by_id(String(def.get("jail", "")))
			if not jail.is_empty():
				hero_pos = map.center_of(jail["floor"][jail["floor"].size() / 2])
			var fine: int = _take_fine(int(rules.get("intruder_fine", 15)))
			intruder_until = -1.0
			arrival = I18n.t("стража поймала вас у стены и привела в %s. Штраф %d") % [jail.get("name", I18n.t("казарму")), fine]
	_gate_in = String(gate.get("id", ""))
	var saved_walk: bool = live and bool(c["state"].get("walking", true))
	if (live and not saved_walk) or (not live and entry == "gate" and bool(c.get("menu", c.has("settlement")))):
		open_menu()
	else:
		walking = true
		menu.close()
	_hero_bld = map.building_at(hero_pos)
	_reveal()
	_fit_camera_limits()
	cam.position = hero_pos * PX
	cam.reset_smoothing()
	_ground.queue_redraw()
	_say("%s: %s" % [display_name, arrival])


func _load_def(id: String, template: String) -> Dictionary:
	for name in [id, template, "s001"]:
		if name == "":
			continue
		var path: String = DATA_DIR + name + ".json"
		if not FileAccess.file_exists(path):
			continue
		var v: Variant = I18n.tree(JSON.parse_string(FileAccess.get_file_as_string(path)))
		if v is Dictionary:
			return v
	return {}


# Ворота: заданные, иначе ближайшие к точке на общей карте, откуда пришёл герой
func _pick_gate(want: String) -> Dictionary:
	var gates: Array = def.get("gates", [])
	if gates.is_empty():
		return {}
	for g in gates:
		if g["id"] == want:
			return g
	var st: Dictionary = ctx.get("settlement", {})
	if ctx.has("return_pos") and st.has("center"):
		var dir: Vector2 = (ctx["return_pos"] - Vector2(st["center"][0], st["center"][1])).normalized()
		var mid: Vector2 = map.center_m()
		var best: Dictionary = gates[0]
		var best_dot: float = -INF
		for g in gates:
			var d: float = ((Vector2(g["spawn"][0], g["spawn"][1]) * map.cell_m - mid).normalized()).dot(dir)
			if d > best_dot:
				best_dot = d
				best = g
		return best
	return gates[0]


# Место у стены изнутри: заданной стороны, иначе со стороны, откуда пришёл герой
func _pick_breach(side: String) -> Dictionary:
	var list: Array = def.get("breaches", [])
	if list.is_empty():
		return {}
	for b in list:
		if b["side"] == side:
			return b
	var st: Dictionary = ctx.get("settlement", {})
	if not (ctx.has("return_pos") and st.has("center")):
		return list[0]
	var dir: Vector2 = (ctx["return_pos"] - Vector2(st["center"][0], st["center"][1])).normalized()
	var mid: Vector2 = map.center_m()
	var best: Dictionary = list[0]
	var best_dot: float = -INF
	for b in list:
		var d: float = (map.center_of(Vector2i(b["cell"][0], b["cell"][1])) - mid).normalized().dot(dir)
		if d > best_dot:
			best_dot = d
			best = b
	return best


func _take_fine(amount: int) -> int:
	var fine: int = mini(amount, int(bag["money"]))
	bag["money"] = int(bag["money"]) - fine
	return fine


func is_intruder() -> bool:
	return intruder_until > clock.total_seconds


# Чужака заметил стражник: штраф и за южные ворота
func _check_intruder() -> void:
	if intruder_until < 0.0:
		return
	if clock.total_seconds >= intruder_until:
		intruder_until = -1.0
		_say(I18n.t("Вы смешались с горожанами: стража больше не косится"))
		return
	var night: bool = daylight(clock.hour_of_day()) < 0.4
	var reach: float = float(rules.get("intruder_spot_night_m" if night else "intruder_spot_m", 8.0))
	for n in npcs:
		if n["def"].get("role", "") != "guard" or n["actor"].sleeping or not n["actor"].alive:
			continue
		if n["pos"].distance_to(hero_pos) < reach:
			intruder_until = -1.0
			var fine: int = _take_fine(int(rules.get("intruder_fine", 15)))
			var gates: Array = def.get("gates", [])
			_say(I18n.t("%s узнал чужака: штраф %d, выводят за ворота") % [n["actor"].display_name, fine])
			if not gates.is_empty():
				# Выводят и ночью: ворота открывают для этого
				paid_gate[String(gates[0]["id"])] = clock.total_seconds + 60.0
				_leave(String(gates[0]["id"]))
			return


func _leave(gate_id: String) -> void:
	if leaving:
		return
	_close_panel()
	route.cancel()
	if exit_requested.get_connections().is_empty():
		# Отдельный запуск: переходов нет — герой остаётся у ворот
		_say(I18n.t("Выход на общую карту: %s (переход подключит общая игра)") % _gate_def(gate_id).get("name", gate_id))
		var g: Dictionary = _gate_def(gate_id)
		hero_pos = Vector2(g["spawn"][0], g["spawn"][1]) * map.cell_m
		return
	leaving = true
	exit_requested.emit(city_id, gate_id)


## Worlds зовёт перед to_dict(), когда уводит героя из города не через ворота (меню, бой):
## состояние помечается «вышел», и следующий вход разыгрывается заново по entry
func prepare_leave() -> void:
	leaving = true
	_close_panel()


## После боя, начатого в городе (Worlds зовёт, если метод есть)
func world_resumed(result: Dictionary) -> void:
	leaving = false
	_last_clock = -1.0
	if result.has("text"):
		_say(String(result["text"]))


func _gate_def(id: String) -> Dictionary:
	for g in def.get("gates", []):
		if g["id"] == id:
			return g
	return {}


# =====================================================================
# НПС
# =====================================================================
func _spawn_npcs() -> void:
	npcs.clear()
	for nd in def.get("npcs", []):
		var a := Actor.new(String(nd["id"]), String(nd["name"]), true, hash(city_id + String(nd["id"])))
		# Характеристики горожан 3–7; навык мастера — уровень, который давали прежние 400 опыта навыка пака
		for s in Actor.STATS:
			a.set_stat(s, 3 + int(abs(hash(String(nd["id"]) + s)) % 5))
		if nd.has("skill"):
			a.set_skill_level(String(nd["skill"]), _legacy_level(String(nd["skill"]), 400.0))
		var n: Dictionary = {
			"def": nd, "actor": a, "path": PackedVector2Array(), "path_i": 0, "goal": Vector2.INF,
			"stock": nd.get("stock", {}).duplicate(), "buys": nd.get("buys", []), "line_i": 0, "wander_t": 0.0,
		}
		n["home_pos"] = _spot_in(String(nd.get("home", "")), Vector2.INF)
		n["work_pos"] = _work_spot(nd)
		n["pos"] = n["work_pos"] if _on_duty(nd, 10.0) else n["home_pos"]
		npcs.append(n)


# Свободная клетка пола в доме (своя для каждого НПС), иначе fallback
static func _legacy_level(skill: String, xp: float) -> int:
	var lv: int = 0
	for t in R.xp_table(skill):
		if xp >= float(t):
			lv += 1
	return lv


func _spot_in(bid: String, fallback: Vector2) -> Vector2:
	var b: Dictionary = map.building_by_id(bid)
	if b.is_empty() or b["floor"].is_empty():
		return fallback if fallback != Vector2.INF else map.size_m() * 0.5
	var cells: Array = b["floor"]
	var c: Vector2i = cells[int(abs(hash(bid + str(npcs.size())))) % cells.size()]
	return map.center_of(c)


func _work_spot(nd: Dictionary) -> Vector2:
	if nd.has("work_cell"):
		return map.center_of(Vector2i(nd["work_cell"][0], nd["work_cell"][1]))
	var work: String = String(nd.get("work", nd.get("home", "")))
	if work == "market":
		for s in def.get("squares", []):
			var r: Array = s["rect"]
			return (Vector2(r[0], r[1]) + Vector2(r[2], r[3]) * 0.5) * map.cell_m
	return _spot_in(work, map.size_m() * 0.5)


func _on_duty(nd: Dictionary, hour: float) -> bool:
	var hr: Array = nd.get("hours", [8, 20])
	var a: float = float(hr[0])
	var b: float = float(hr[1])
	return hour >= a and hour < b if a <= b else (hour >= a or hour < b)


func _update_npc(n: Dictionary, env: Dictionary, dt_game: float, delta: float) -> void:
	var a: Actor = n["actor"]
	if not a.alive:
		return
	# Горожане живут с собственных запасов: голод и жажда не опускаются ниже трети [Q19: не баланс, оставлено]
	if dt_game > 0.0:
		a.tick(dt_game, env)
	if a.res["hunger"] < 35.0:
		a.eat(40.0)
	if a.res["thirst"] < 35.0:
		a.drink(40.0)
	var nd: Dictionary = n["def"]
	var hour: float = clock.hour_of_day()
	var duty: bool = _on_duty(nd, hour)
	var goal: Vector2 = n["work_pos"] if duty else n["home_pos"]
	if duty and nd.has("wander"):
		n["wander_t"] -= delta
		if n["wander_t"] <= 0.0 or n["goal"] == Vector2.INF:
			n["wander_t"] = _rng.randf_range(4.0, 9.0)
			var rr: float = float(nd["wander"]) * map.cell_m
			for k in 8:
				var q: Vector2 = n["work_pos"] + Vector2(_rng.randf_range(-rr, rr), _rng.randf_range(-rr, rr))
				if map.is_free(q, BODY_R):
					goal = q
					break
		else:
			goal = n["goal"]
	if goal != n["goal"]:
		n["goal"] = goal
		n["path"] = map.path(n["pos"], goal)
		n["path_i"] = 0
		if a.sleeping:
			a.set_sleep(false)
	var path: PackedVector2Array = n["path"]
	var moved: bool = false
	if n["path_i"] < path.size():
		var speed: float = a.calculate_speed(env) / 3.6 * float(rules.get("walk_scale", 3.0)) * GameClock.GAME_SPEED * ground_speed(n["pos"])
		var step: float = speed * delta
		while step > 0.0 and n["path_i"] < path.size():
			var tgt: Vector2 = path[n["path_i"]]
			if n["path_i"] == path.size() - 1:
				tgt = goal
			var d: float = n["pos"].distance_to(tgt)
			if d <= step:
				n["pos"] = tgt
				step -= d
				n["path_i"] += 1
			else:
				n["pos"] += (tgt - n["pos"]) / d * step
				step = 0.0
			moved = true
	a.exert(delta, env, "walk" if moved else "rest")
	if duty and a.sleeping:
		a.set_sleep(false)
	# Не на службе и дома — спит
	if not duty and n["path_i"] >= path.size() and not a.sleeping and (hour >= 21.0 or hour < 7.0):
		a.set_sleep(true)


func _npc_on_duty_here(n: Dictionary) -> bool:
	if not walking:
		return _on_duty(n["def"], clock.hour_of_day()) and not n["actor"].sleeping
	return _on_duty(n["def"], clock.hour_of_day()) and n["pos"].distance_to(n["work_pos"]) < 4.0 and not n["actor"].sleeping


# =====================================================================
# КАДР
# =====================================================================
func _process(delta: float) -> void:
	art_time += delta
	if not entered or leaving:
		return
	var now: float = clock.total_seconds
	var dt_game: float = 0.0 if _last_clock < 0.0 else maxf(now - _last_clock, 0.0)
	_last_clock = now
	var hour: float = clock.hour_of_day()
	_update_gates(hour, now)
	_check_intruder()

	var env: Dictionary = env_at(hero_pos)
	if own_clock and dt_game > 0.0:
		hero.tick(dt_game, env)
	_drive_hero(env, delta)
	var trails_changed: bool = trails.walk(hero, hero_pos, now)
	art_moving = hero_pos.distance_squared_to(art_last_hero) > 0.00001
	art_last_hero = hero_pos

	for n in npcs:
		var was: Vector2 = n["pos"]
		_update_npc(n, env_at(n["pos"]), dt_game, delta)
		trails_changed = trails.walk(n["actor"], n["pos"], now) or trails_changed
		var d: Vector2 = n["pos"] - was
		_art_walk[n["actor"]] = d.length_squared() > 0.00001
		if absf(d.x) > 0.0005:
			_art_face[n["actor"]] = signf(d.x)

	var b: int = map.building_at(hero_pos)
	if b != _hero_bld:
		_hero_bld = b
		if b >= 0:
			_discover(String(map.buildings[b]["id"]), String(map.buildings[b]["name"]))
	_reveal()
	if _trails_at < 0.0 or absf(now - _trails_at) >= TRAIL_REFRESH_S:
		_trails_at = now
		trails_changed = trails.refresh(now) or trails_changed
	if trails_changed:
		_ground.queue_redraw()

	cam.position = (map.size_m() * 0.5 if _map_view else hero_pos) * PX
	_update_light(hour)
	event_timer = maxf(event_timer - delta, 0.0)
	_update_hud(env)
	_actors.queue_redraw()
	_roofs.queue_redraw()
	_path_layer.queue_redraw()
	if _fog_dirty:
		_fog_dirty = false
		_fog.queue_redraw()


## Среда для правил персонажа: улица — как на общей карте у города, в доме теплее и сухо
func env_at(p: Vector2) -> Dictionary:
	var hour: float = clock.hour_of_day()
	var temp: float
	if game != null and game.has_method("temperature_at") and ctx.has("return_pos"):
		temp = float(game.temperature_at(ctx["return_pos"]))
	else:
		temp = WorldEnv.air_temp(4, hour, clock.day_of_year())
	var bi: int = map.building_at(p)
	if bi >= 0 and map.buildings[bi].get("kind", "") != "ruins":
		temp += float(rules.get("shelter_temp_c", 6.0))
	return {"biome": 4, "water": 0.0, "temp_c": temp, "rain": 0.0, "night": hour < 5.5 or hour >= 20.5, "hour": hour}


func _menu_blocked() -> bool:
	var w: Node = get_node_or_null("/root/Worlds")
	if w != null and w.has_method("menu_open") and w.menu_open():
		return true
	if window != null and window.visible:
		return true
	if not walking:
		return true
	return _panel.visible and _panel_kind != "note"


func _drive_hero(env: Dictionary, delta: float) -> void:
	if not hero.alive:
		return
	var dir := Vector2.ZERO
	if not _menu_blocked() and not _map_view:
		if Input.is_physical_key_pressed(KEY_A) or Input.is_action_pressed("ui_left"): dir.x -= 1
		if Input.is_physical_key_pressed(KEY_D) or Input.is_action_pressed("ui_right"): dir.x += 1
		if Input.is_physical_key_pressed(KEY_W) or Input.is_action_pressed("ui_up"): dir.y -= 1
		if Input.is_physical_key_pressed(KEY_S) or Input.is_action_pressed("ui_down"): dir.y += 1
	var run: bool = Input.is_physical_key_pressed(KEY_SHIFT)
	# Мышь: удержание ЛКМ ведёт за курсором; клавиши и окна перебивают путь
	if _mouse_hold and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not _menu_blocked():
		_hold_t += delta
		if _hold_t >= 0.25:
			_hold_t = 0.0
			var mp: Vector2 = get_global_mouse_position() / PX
			if not route.active() or mp.distance_to(route.target) > 1.0:
				route.click(mp)
	else:
		_mouse_hold = false
	var by_route: bool = false
	if dir != Vector2.ZERO or _menu_blocked():
		route.cancel()
	elif route.active():
		dir = route.steer(delta)
		by_route = dir != Vector2.ZERO
	var goal: Vector2 = route.final_point() if by_route else Vector2.INF
	var from: Vector2 = hero_pos
	var moved: bool = move_hero(dir, run, delta, env)
	# Шаг дотянулся до конца пути или перескочил его — встать точно в точку, без дрожи вокруг
	if goal != Vector2.INF and hero_pos.distance_to(from) >= from.distance_to(goal) - 0.02:
		if map.is_free(goal, BODY_R):
			hero_pos = goal
		route.finish()
	elif by_route:
		route.stepped(moved, delta)


## Шаг героя (открыт для тестов): скользит вдоль стен, ворота — выход
func move_hero(dir: Vector2, run: bool, delta: float, env: Dictionary) -> bool:
	# Первый шаг будит героя (раньше can_move() отсекал спящего и он не вставал)
	if dir != Vector2.ZERO and hero.sleeping:
		hero.set_sleep(false)
		_say(I18n.t("Вы проснулись"))
	if dir == Vector2.ZERO or not hero.can_move():
		hero.exert(delta, env, "rest")
		# Выспался — встаёт сам
		if hero.sleeping and float(hero.res["energy"]) >= 99.0 and hero.sleep_h >= 1.0:
			hero.set_sleep(false)
			_say(I18n.t("Вы выспались и встали"))
		return false
	dir = dir.limit_length(1.0)
	hero_dir = dir.normalized()
	hero.carried_kg = Trade.weight(bag)
	var v: float = hero.calculate_speed(env, run) / 3.6 * float(rules.get("walk_scale", 3.0)) * GameClock.GAME_SPEED * ground_speed(hero_pos)
	var step: Vector2 = dir * v * delta
	var start: Vector2 = hero_pos
	if map.is_free(hero_pos + step, BODY_R):
		hero_pos += step
	else:
		if map.is_free(hero_pos + Vector2(step.x, 0.0), BODY_R):
			hero_pos.x += step.x
		if map.is_free(hero_pos + Vector2(0.0, step.y), BODY_R):
			hero_pos.y += step.y
	hero.exert(delta, env, "run" if run and hero.can_run() else "walk")
	var g: String = map.gate_at(hero_pos)
	if g != "":
		_leave(g)
	return hero_pos != start


## Множитель шага по клетке: тропа по траве и полю быстрее нетоптаной земли (world/trails.gd SPEED)
func ground_speed(p: Vector2) -> float:
	var v: float = map.speed_at(p)
	if map.tile_at(p) in TRAIL_TILES:
		v *= trails.speed_mult(p)
	return v


func _update_gates(hour: float, now: float) -> void:
	var open: bool = hour >= float(rules.get("gates_open_h", 6.0)) and hour < float(rules.get("gates_close_h", 22.0))
	for g in def.get("gates", []):
		var id: String = g["id"]
		if open or float(paid_gate.get(id, -1.0)) > now:
			map.closed_gates.erase(id)
		else:
			map.closed_gates[id] = true


func gates_open() -> bool:
	return map.closed_gates.is_empty()


# =====================================================================
# ИССЛЕДОВАНИЕ: туман, находки, тайники
# =====================================================================
func _reveal() -> void:
	var c: Vector2i = map.cell_of(hero_pos)
	var r: int = int(ceil(float(rules.get("sight_m", 14.0)) / map.cell_m))
	# В доме видно только сам дом
	var inside: int = map.building_at(hero_pos)
	for y in range(c.y - r, c.y + r + 1):
		for x in range(c.x - r, c.x + r + 1):
			if x < 0 or y < 0 or x >= map.w or y >= map.h:
				continue
			if Vector2(x - c.x, y - c.y).length() > r:
				continue
			if inside >= 0 and map.bld[y * map.w + x] != inside:
				continue
			var i: int = y * map.w + x
			if fog[i] == 0:
				fog[i] = 1
				_fog_dirty = true
	for p in def.get("places", []):
		if not discovered.has(p["id"]) and hero_pos.distance_to(_place_pos(p)) < float(rules.get("sight_m", 14.0)) * 0.6:
			_discover(String(p["id"]), String(p["name"]))


func _discover(id: String, name: String) -> void:
	if discovered.has(id):
		return
	discovered[id] = true
	_say(I18n.t("Найдено: %s") % name)


func explored_fraction() -> float:
	# Земля за стеной радиального города не считается
	var n: int = 0
	var total: int = 0
	for i in fog.size():
		if map.tiles[i] == T.OUTSIDE:
			continue
		total += 1
		n += fog[i]
	return float(n) / maxf(total, 1)


func _place_pos(p: Dictionary) -> Vector2:
	return (Vector2(p["cell"][0], p["cell"][1]) + Vector2(0.5, 0.5)) * map.cell_m


func _search(p: Dictionary) -> void:
	var now: float = clock.total_seconds
	var respawn: float = float(rules.get("loot_respawn_days", 3.0)) * 86400.0
	if looted.has(p["id"]) and now - float(looted[p["id"]]) < respawn:
		_say(I18n.t("%s: пусто, загляните через пару дней") % p["name"])
		return
	if bool(p.get("steal", false)):
		for n in npcs:
			if n["def"].get("role", "") == "guard" and not n["actor"].sleeping and n["pos"].distance_to(hero_pos) < float(rules.get("guard_watch_m", 18.0)):
				var fine: int = mini(int(rules.get("steal_fine", 5)), int(bag["money"]))
				bag["money"] = int(bag["money"]) - fine
				_say(I18n.t("%s заметил кражу: штраф %d") % [n["actor"].display_name, fine])
				return
	looted[p["id"]] = now
	var eff: float = float(hero.derived()["search_efficiency"])
	var found: Array = []
	for id in p.get("loot", {}):
		var l: Array = p["loot"][id]
		if _rng.randf() < float(l[2]) * eff:
			var k: int = _rng.randi_range(int(l[0]), int(l[1]))
			if k <= 0:
				continue
			if id == "money":
				bag["money"] = int(bag["money"]) + k
				found.append(I18n.t("%d монет") % k)
			else:
				Trade.add(bag, id, k)
				found.append("%s ×%d" % [Trade.item_name(id), k])
	hero.add_xp("survival", 2.0)
	_say("%s: %s" % [p["name"], I18n.t("ничего") if found.is_empty() else ", ".join(PackedStringArray(found))])


# =====================================================================
# ВЗАИМОДЕЙСТВИЕ
# =====================================================================
func _nearest_npc() -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = TALK_M
	for n in npcs:
		var d: float = n["pos"].distance_to(hero_pos)
		if d < best_d and n["actor"].alive:
			best_d = d
			best = n
	return best


func _nearest_place() -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = LOOK_M
	for p in def.get("places", []):
		var d: float = _place_pos(p).distance_to(hero_pos)
		if d < best_d:
			best_d = d
			best = p
	return best


func interact() -> void:
	if not hero.alive:
		return
	var n: Dictionary = _nearest_npc()
	if not n.is_empty():
		talk(n)
		return
	var p: Dictionary = _nearest_place()
	if p.is_empty():
		return
	use_place(p)


## Колодец — пить, тайник — обыскать, остальное — прочитать (E рядом или клик мышью)
func use_place(p: Dictionary) -> void:
	match String(p.get("kind", "")):
		"water":
			hero.drink(30.0, "clean")
			_say(I18n.t("Напился из колодца"))
		"container":
			_search(p)
		"bed":
			hero.set_sleep(true)
			_say(I18n.t("Вы легли на лежанку в своей лачуге. Сон до первого шага"))
		"board":
			_open_note(String(p["name"]), _board_text(p))
		_:
			_open_note(String(p["name"]), String(p.get("text", "")))


func talk(n: Dictionary) -> void:
	_talk_npc = n
	var a: Actor = n["actor"]
	var nd: Dictionary = n["def"]
	var role: String = String(nd.get("role", "citizen"))
	var title: String = "%s, %s" % [a.display_name, ROLE_NAMES.get(role, role)]
	var opts: Array = []
	var text: String
	if a.sleeping:
		text = I18n.t("Спит. Будить не стоит.")
	else:
		var lines: Array = nd.get("lines", ["…"])
		text = "«%s»" % lines[int(n["line_i"]) % lines.size()]
		# при Уме 3 и ниже — «тупые» разговоры, при 7+ — умные наблюдения
		var dlg: Dictionary = Sheet.sect("dialogue")
		if hero != null and Sheet.dumb(hero):
			text += I18n.t(String(dlg.get("dumb_suffix", "")))
		elif hero != null and Sheet.smart(hero) and int(n["line_i"]) == 0:
			text += I18n.t(String(dlg.get("smart_suffix", "")))
		opts.append([I18n.t("Поговорить"), func(): n["line_i"] += 1; talk(n)])
		var qs: Array = Growth.available(full_def, growth, String(nd["id"]))
		if not qs.is_empty():
			var ready_n: int = qs.filter(func(q): return Growth.taken(growth, q) and Growth.ready(growth, q, bag, hero_km(), battles_won())).size()
			text += I18n.t("\n\nПоручения: %d%s — вкладка «Поручения».") % [qs.size(), I18n.t(", можно сдать: %d") % ready_n if ready_n > 0 else ""]
		elif Growth.waiting(full_def, growth, String(nd["id"])):
			text += I18n.t("\n\nДругих поручений пока нет: пусть город подрастёт.")
		var working: bool = _npc_on_duty_here(n)
		if (not n["stock"].is_empty() or not n["buys"].is_empty()) and not working:
			text += I18n.t("\n\nСейчас не торгует: приходите в часы работы (%d–%d).") % [int(nd["hours"][0]), int(nd["hours"][1])]
		var sv: Dictionary = nd.get("services", {})
		if sv.has("room") and working:
			opts.append([I18n.t("Снять комнату до утра (%d)") % int(sv["room"]), func(): rent_room(n)])
		if sv.has("heal") and working:
			opts.append([I18n.t("Лечиться (%d)") % int(sv["heal"]), func(): heal(n)])
		if nd.has("gate") and map.closed_gates.has(String(nd["gate"])):
			opts.append([I18n.t("Выпусти меня (%d)") % int(rules.get("night_pass_fee", 5)), func(): pay_gate(n)])
		if role == "elder" and not discovered.has("_plan"):
			opts.append([I18n.t("Расспросить о городе"), func(): ask_plan(n)])
	opts.append([I18n.t("Уйти"), _close_panel])
	_open_panel("talk", title, text, opts, _talk_tabs(n, "talk"))


## Вкладки разговора (Q34, Huzzah 2026-10-27, вариант B): у мастеров много действий, и «Мастерская»
## уходила под прокрутку. Вкладка есть, только если в ней есть дело: поручения — когда они есть,
## торговля и мастерская — в часы работы
func _talk_tabs(n: Dictionary, cur: String) -> Array:
	if n["actor"].sleeping:
		return []
	var tabs: Array = [["talk", I18n.t("Разговор"), func(): talk(n)]]
	var qs: Array = Growth.available(full_def, growth, String(n["def"]["id"]))
	if not qs.is_empty():
		tabs.append(["quests", I18n.t("Поручения (%d)") % qs.size(), func(): open_quests(n)])
	if _npc_on_duty_here(n) and (not n["stock"].is_empty() or not n["buys"].is_empty()):
		tabs.append(["trade", I18n.t("Торговля"), func(): open_trade(n)])
		if Craft.skill_of(String(n["def"].get("role", ""))) != "":
			tabs.append(["craft", I18n.t("Мастерская"), func(): open_craft(n)])
	if tabs.size() < 2:
		return []
	return tabs.map(func(t): return [t[1], t[2], t[0] == cur])


## Вкладка «Поручения»: взять, посмотреть, сдать
func open_quests(n: Dictionary) -> void:
	_talk_npc = n
	var opts: Array = []
	var qs: Array = Growth.available(full_def, growth, String(n["def"]["id"]))
	for q in qs:
		if Growth.taken(growth, q):
			var done: bool = Growth.ready(growth, q, bag, hero_km(), battles_won())
			opts.append(["%s: %s (%s)" % [I18n.t("Сдать поручение") if done else I18n.t("Поручение"), q["title"], quest_status(q)], func(): turn_in(n, q)])
		else:
			opts.append([I18n.t("Работа: %s") % q["title"], func(): quest_offer(n, q)])
	opts.append([I18n.t("Назад"), func(): talk(n)])
	_open_panel("quests", I18n.t("Поручения: %s") % n["actor"].display_name, "" if not qs.is_empty() else I18n.t("Поручений нет."), opts, _talk_tabs(n, "quests"))


func open_trade(n: Dictionary) -> void:
	_talk_npc = n
	var a: Actor = n["actor"]
	var opts: Array = []
	for id in n["stock"]:
		if int(n["stock"][id]) > 0:
			opts.append([I18n.t("Купить: %s ×%d — %d") % [Trade.item_name(id), int(n["stock"][id]), Trade.buy_price(id, hero, a)],
				func(): _trade_result(n, Trade.buy(bag, n["stock"], id, hero, a))])
	for id in bag["items"]:
		if n["buys"].has(id) or n["stock"].has(id):
			opts.append([I18n.t("Продать: %s ×%d — %d") % [Trade.item_name(id), Trade.count(bag, id), Trade.sell_price(id, hero, a)],
				func(): _trade_result(n, Trade.sell(bag, n["stock"], n["buys"], id, hero, a))])
	opts.append([I18n.t("Назад"), func(): talk(n)])
	_open_panel("trade", I18n.t("Торговля: %s") % a.display_name, I18n.t("Деньги: %d   Груз: %.1f / %.0f кг   Торговля: у вас %d %%, у торговца %d %%") % [
		int(bag["money"]), Trade.weight(bag), hero.carry_capacity(), hero.skill("barter"), a.skill("barter")], opts, _talk_tabs(n, "trade"))


func _trade_result(n: Dictionary, err: String) -> void:
	if err != "":
		_say(err)
	open_trade(n)


## Мастерская кожевника или кузнеца (craft.gd): список рецептов и урок у мастера
func open_craft(n: Dictionary) -> void:
	_talk_npc = n
	var role: String = String(n["def"].get("role", ""))
	var sk: String = Craft.skill_of(role)
	var master: Actor = n["actor"]
	var opts: Array = []
	for id in Craft.recipes_for(role):
		var r: Dictionary = Craft.recipe(id)
		var mark: String = "" if Craft.missing(bag, r).is_empty() else I18n.t("  (нет материалов)")
		opts.append(["%s: %s%s" % [Trade.item_name(String(r["out"])), Craft.inputs_text(r), mark], func(): open_recipe(n, id)])
	if hero.skill(sk) < master.skill(sk):
		opts.append([I18n.t("Учиться у мастера (%d)") % Craft.lesson_fee(hero, sk), func(): _craft_result(n, "", Craft.lesson(bag, hero, master, sk), I18n.t("Урок пройден"))])
	opts.append([I18n.t("Назад"), func(): talk(n)])
	_open_panel("craft", "%s: %s" % [Craft.workshop_name(role), master.display_name], I18n.t("%s\nДеньги: %d   Выносливость: %d") % [
		_craft_skill_line(sk, master), int(bag["money"]), int(hero.res["stamina"])], opts, _talk_tabs(n, "craft"))


func _craft_skill_line(sk: String, master: Actor) -> String:
	var nm: String = String(R.skills().get(sk, {}).get("name_ru", sk))
	return I18n.t("%s: у вас %d %% (ур. %d), у мастера %d %% (ур. %d)") % [nm, hero.skill(sk), hero.skill_level(sk), master.skill(sk), master.skill_level(sk)]


func open_recipe(n: Dictionary, id: String) -> void:
	var r: Dictionary = Craft.recipe(id)
	var master: Actor = n["actor"]
	var sk: String = Craft.skill_of(String(r["master"]))
	var lines: PackedStringArray = [I18n.t("Материалы: %s") % Craft.inputs_text(r)]
	var lack: Array = Craft.missing(bag, r)
	if not lack.is_empty():
		lines.append(I18n.t("Не хватает: %s") % ", ".join(PackedStringArray(lack)))
	lines.append(I18n.t("Нужен навык: %d") % int(r.get("level", 0)))
	var opts: Array = []
	if master.skill_level(sk) >= int(r.get("level", 0)):
		opts.append([I18n.t("Заказать у мастера (%d)") % int(r.get("fee", 0)), func(): _craft_result(n, id, Craft.order(bag, r, master), I18n.t("Готово: %s") % Trade.item_name(String(r["out"])))])
	else:
		lines.append(I18n.t("Мастер такого не умеет: только своими руками."))
	var why: String = Craft.self_blocker(bag, r, hero)
	if why == "":
		opts.append([I18n.t("Сделать самому (шанс %d %%, выносливость −%d)") % [int(round(Craft.chance(r, hero) * 100.0)), int(r.get("work", 0))],
			func(): _craft_result(n, id, "", String(Craft.make(bag, r, hero, craft_rng)["text"]))])
	else:
		lines.append(I18n.t("Самому: %s") % why.to_lower())
	opts.append([I18n.t("Назад"), func(): open_craft(n)])
	_open_panel("craft", Trade.item_name(String(r["out"])), "\n".join(lines), opts)


func _craft_result(n: Dictionary, id: String, err: String, done: String) -> void:
	_say(err if err != "" else done)
	if id != "":
		open_recipe(n, id)
	else:
		open_craft(n)


func rent_room(n: Dictionary) -> void:
	var fee: int = int(n["def"]["services"]["room"])
	if int(bag["money"]) < fee:
		_say(I18n.t("Не хватает денег"))
		return
	bag["money"] = int(bag["money"]) - fee
	var b: Dictionary = map.building_by_id(String(n["def"].get("home", "")))
	if not b.is_empty():
		hero_pos = map.center_of(b["floor"][0])
	hero.set_sleep(true)
	_close_panel()
	_say(I18n.t("Комната снята. Сон до первого шага"))


func heal(n: Dictionary) -> void:
	var fee: int = int(n["def"]["services"]["heal"])
	if hero.conditions.is_empty():
		_open_panel("talk", n["actor"].display_name, I18n.t("«Здоров ты, иди с миром.»"), [[I18n.t("Назад"), func(): talk(n)]])
		return
	if int(bag["money"]) < fee:
		_say(I18n.t("Не хватает денег"))
		return
	bag["money"] = int(bag["money"]) - fee
	var kit: Array = n["stock"].keys().filter(func(id): return int(n["stock"][id]) > 0)
	var out: Array = []
	for c in hero.conditions.duplicate():
		var r: Dictionary = hero.treat(String(c["id"]), n["actor"], kit)
		var nm: String = R.condition(String(c["id"])).get("name_ru", c["id"])
		for used in r["used"]:
			n["stock"][used] = int(n["stock"].get(used, 0)) - 1
		out.append("%s: %s" % [nm, I18n.t("вылечено") if r["ok"] else r["reason"]])
	_open_panel("talk", n["actor"].display_name, "\n".join(PackedStringArray(out)), [[I18n.t("Назад"), func(): talk(n)]])


func pay_gate(n: Dictionary) -> void:
	var fee: int = int(rules.get("night_pass_fee", 5))
	if int(bag["money"]) < fee:
		_say(I18n.t("Не хватает денег"))
		return
	bag["money"] = int(bag["money"]) - fee
	paid_gate[String(n["def"]["gate"])] = clock.total_seconds + 3600.0
	_close_panel()
	_say(I18n.t("%s отпирает ворота") % n["actor"].display_name)


func ask_plan(n: Dictionary) -> void:
	discovered["_plan"] = true
	for b in map.buildings:
		discovered[String(b["id"])] = true
	fog.fill(1)
	_fog_dirty = true
	_open_panel("talk", n["actor"].display_name, I18n.t("%s рассказал, где что стоит: весь город теперь на плане (M).") % n["actor"].display_name, [[I18n.t("Назад"), func(): talk(n)]])


## Сумка — вкладка «Инвентарь» общего окна героя
func open_bag() -> void:
	if _panel.visible:
		_close_panel()
	window.open("bag")


func _open_note(title: String, text: String) -> void:
	_open_panel("note", title, text, [[I18n.t("Закрыть"), _close_panel]])


func _unhandled_input(event: InputEvent) -> void:
	if not entered or leaving:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_mouse_hold = event.pressed
			_hold_t = 0.0
			if event.pressed and hero.alive and not _menu_blocked():
				route.click(get_global_mouse_position() / PX)
				get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed and route.active():
				route.cancel()
				get_viewport().set_input_as_handled()
		elif event.pressed and not _map_view:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				cam.zoom = (cam.zoom * 1.12).clamp(Vector2(0.4, 0.4), Vector2(3.0, 3.0))
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				cam.zoom = (cam.zoom / 1.12).clamp(Vector2(0.4, 0.4), Vector2(3.0, 3.0))
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var w: Node = get_node_or_null("/root/Worlds")
	if w != null and w.has_method("menu_open") and w.menu_open():
		return
	var k: int = event.physical_keycode
	if _panel.visible and k >= KEY_1 and k <= KEY_9:
		var i: int = k - KEY_1
		if i < _buttons.size():
			_buttons[i].emit_signal("pressed")
		get_viewport().set_input_as_handled()
		return
	match k:
		KEY_E:
			if _panel.visible:
				_close_panel()
			elif walking:
				interact()
		KEY_TAB:
			if _panel.visible:
				_close_panel()
			window.toggle("bag")
		KEY_I:
			if _panel.visible:
				_close_panel()
			window.toggle("stats")
		KEY_M:
			if walking:
				toggle_map()
		KEY_ESCAPE:
			if not _panel.visible and not _map_view:
				if walking and not is_intruder():
					open_menu()
					get_viewport().set_input_as_handled()
				return   # в меню города — меню паузы игры (Worlds)
			_close_panel()
			if _map_view:
				toggle_map()
		_:
			return
	get_viewport().set_input_as_handled()


func toggle_map() -> void:
	_map_view = not _map_view
	if _map_view:
		_zoom_before = cam.zoom.x
		var vp: Vector2 = get_viewport_rect().size
		var z: float = minf(vp.x / (map.size_m().x * PX), vp.y / (map.size_m().y * PX)) * 0.95
		cam.limit_enabled = false
		cam.zoom = Vector2(z, z)
	else:
		cam.zoom = Vector2(_zoom_before, _zoom_before)
		cam.limit_enabled = true


# =====================================================================
# СВЕТ
# =====================================================================
func _light_tex() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 256
	t.height = 256
	return t


func _make_lights() -> void:
	for l in _lights:
		l.queue_free()
	_lights.clear()
	var tex: Texture2D = _light_tex()
	var spots: Array = []
	for b in map.buildings:
		if b.get("kind", "") in ["inn", "shop", "healer", "smithy", "hall", "temple"]:
			spots.append(map.center_of(Vector2i(b["door"][0], b["door"][1])))
	for g in def.get("gates", []):
		spots.append(Vector2(g["guard_post"][0], g["guard_post"][1]) * map.cell_m)
	for p in def.get("places", []):
		if p.get("kind", "") == "water":
			spots.append(_place_pos(p))
	for s in spots:
		var l := PointLight2D.new()
		l.texture = tex
		l.position = s * PX
		l.texture_scale = 2.2
		l.color = Color(1.0, 0.72, 0.38)
		add_child(l)
		_lights.append(l)
	if _hero_light == null:
		_hero_light = PointLight2D.new()
		_hero_light.texture = tex
		_hero_light.texture_scale = 1.4
		_hero_light.color = Color(1.0, 0.85, 0.6)
		add_child(_hero_light)


## Сумерки как на общей карте: день светлый, ночь синяя, у дверей фонари
func daylight(hour: float) -> float:
	return clampf(cos((hour - 13.0) / 24.0 * TAU) * 1.4 + 0.45, 0.0, 1.0)


func _update_light(hour: float) -> void:
	var d: float = daylight(hour)
	_night.color = Color(0.2, 0.22, 0.36).lerp(Color.WHITE, d)
	for l in _lights:
		l.energy = (1.0 - d) * 1.1
	_hero_light.position = hero_pos * PX
	_hero_light.energy = (1.0 - d) * 0.6


func _fit_camera_limits() -> void:
	var s: Vector2 = map.size_m() * PX
	cam.limit_left = -int(PX * 4)
	cam.limit_top = -int(PX * 4)
	cam.limit_right = int(s.x + PX * 4)
	cam.limit_bottom = int(s.y + PX * 4)
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 8.0


# =====================================================================
# РИСОВАНИЕ
# =====================================================================
func _noise(x: int, y: int) -> float:
	return float(abs(hash(Vector2i(x, y) + Vector2i(city_id.length(), 7))) % 1000) / 1000.0


func _draw_ground(l: Node2D) -> void:
	if map.w == 0:
		return
	l.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	var cs: float = map.cell_m * PX
	var grass: Texture2D = Art.ground("t03_field1")
	Art.surface(l, grass, Rect2(Vector2(-PX * 40, -PX * 40), map.size_m() * PX + Vector2(PX * 80, PX * 80)), TEX_PERIOD)
	for y in map.h:
		for x in map.w:
			var t: int = map.at(x, y)
			var r := Rect2(Vector2(x, y) * cs, Vector2(cs, cs))
			var texture: Texture2D = grass
			match t:
				T.ROAD, T.GATE: texture = Art.ground("t01_coast")
				T.SQUARE, T.STALL, T.WELL: texture = Art.tex("cobble")
				T.FIELD: texture = Art.ground("t04_field2")
				T.FLOOR, T.DOOR: texture = Art.tex("wood")
				T.WALL: texture = Art.tex("masonry")
				T.PALISADE: texture = Art.tex("masonry") if String(def.get("wall", "")) == "stone" else Art.tex("wood")
				T.RUBBLE: texture = Art.ground("t07_mountains")
			# Дом рисует спрайт здания; под краями картинки — трава, а не кладка (Huzzah 2026-10-24); пол — когда герой внутри
			var under_sprite: bool = t in [T.WALL, T.DOOR, T.FLOOR] and _sprite_cell(x, y)
			if under_sprite:
				texture = grass
			Art.surface(l, texture, r, TEX_PERIOD)
			if under_sprite:
				l.draw_rect(r, Color(0.48, 0.53, 0.34, 0.30))
				continue
			if t in [T.GRASS, T.TREE]:
				l.draw_rect(r, Color(0.48, 0.53, 0.34, 0.30))
			elif t == T.OUTSIDE:
				# За стеной: поле и выгон, темнее городской травы
				l.draw_rect(r, Color(0.20, 0.24, 0.12, 0.42))
			if t in [T.PALISADE, T.WALL]:
				l.draw_rect(r, Color(0.22, 0.18, 0.12, 0.45), false, 1.2)
			if t == T.DOOR:
				l.draw_line(r.position + Vector2(cs * 0.2, cs * 0.5), r.position + Vector2(cs * 0.8, cs * 0.5), Color(0.3, 0.2, 0.12), 3.0)
	# Протоптанное поверх травы и поля: земля улиц, тем плотнее, чем выше ступень
	var dirt: Texture2D = Art.ground("t01_coast")
	for c in trails.stage_of:
		if map.at(c.x, c.y) in TRAIL_TILES and not _sprite_cell(c.x, c.y):
			Art.surface(l, dirt, Rect2(Vector2(c) * cs, Vector2(cs, cs)), TEX_PERIOD, Color(1, 1, 1, TRAIL_ALPHA[trails.stage_of[c]]))


func _sprite_cell(x: int, y: int) -> bool:
	var b: int = map.bld[y * map.w + x]
	return b >= 0 and String(map.buildings[b].get("kind", "house")) != "ruins"


func _draw_actors(_l: Node2D) -> void:
	# Bodies share one y-sorted paint list with upright scenery below.
	pass


func _visible_for_hero(p: Vector2) -> bool:
	var b: int = map.building_at(p)
	return b < 0 or b == _hero_bld or map.buildings[b].get("kind", "") == "ruins"


func _body(l: Node2D, p: Vector2, col: Color, a: Actor, dir: Vector2) -> void:
	var key: String = "traveler" if a == hero else "villager"
	for n in npcs:
		if n["actor"] == a:
			var role: String = String(n["def"].get("role", "citizen"))
			key = "guard" if role == "guard" else ("woman" if role in ["healer", "trader"] else "villager")
			break
	var tint: Color = Color.WHITE if a.alive else Color(0.5, 0.5, 0.5, 0.65)
	# Анимация: идёт — шаг, стоит — дышит; спящий и мёртвый не шевелятся
	var moving: bool = art_moving if a == hero else bool(_art_walk.get(a, false))
	var face: float = float(_art_face.get(a, 1.0))
	if a == hero and absf(hero_dir.x) > 0.2:
		face = signf(hero_dir.x)
		_art_face[a] = face
	if a.sleeping:
		# Спящий лежит на боку
		Art.sprite(l, key, p * PX + Vector2(-PX * 0.8, PX * 0.3), PX * 1.9, tint, -1.45)
	elif not a.alive:
		Art.sprite(l, key, p * PX, PX * 1.9, tint)
	else:
		Art.figure(l, key, p * PX, PX * 1.9, tint, art_time, moving and a.alive, face < 0.0, p.x * 0.37 + float(a.get_instance_id() % 97))
	if a == hero:
		l.draw_arc(p * PX, BODY_R * PX * 1.2 + 4.0, 0.0, TAU, 24, Color(col, 0.8), 1.5)


func _label(l: Node2D, font: Font, at: Vector2, text: String, col: Color) -> void:
	var k: float = 1.0 / maxf(cam.zoom.x, 0.05)
	var fs: int = int(13.0 * k)
	var wd: float = 260.0 * k
	l.draw_string_outline(font, at + Vector2(-wd / 2, 0), text, HORIZONTAL_ALIGNMENT_CENTER, wd, fs, int(4.0 * k), Color(0, 0, 0, 0.85))
	l.draw_string(font, at + Vector2(-wd / 2, 0), text, HORIZONTAL_ALIGNMENT_CENTER, wd, fs, col)


const ROOF_COLORS: Dictionary = {
	"inn": Color(0.55, 0.25, 0.18), "shop": Color(0.45, 0.33, 0.2), "healer": Color(0.33, 0.42, 0.28),
	"smithy": Color(0.32, 0.32, 0.34), "hall": Color(0.5, 0.3, 0.42), "house": Color(0.48, 0.36, 0.22),
	"temple": Color(0.62, 0.55, 0.38),
}


# Где дверь на спрайте здания (доля ширины) — то же, что DOOR_AT в tools/make_city_radial.py
const DOOR_AT: Dictionary = {"house": 0.43, "inn": 0.66, "hall": 0.5, "temple": 0.45, "smithy": 0.5, "healer": 0.35}


func _draw_roofs(l: Node2D) -> void:
	if map.w == 0:
		return
	var cs: float = map.cell_m * PX
	var font: Font = ThemeDB.fallback_font
	var entries: Array = []
	for b in map.buildings:
		var rr: Array = b["rect"]
		entries.append({"type": "building", "b": b, "y": float(rr[1] + rr[3]) * cs})
	for prop in def.get("props", []):
		if prop["cells"].is_empty():
			continue
		if prop["kind"] == "tree":
			for v in prop["cells"]:
				if map.at(v[0], v[1]) != T.TREE:
					continue
				var foot: Vector2 = map.center_of(Vector2i(v[0], v[1])) * PX
				entries.append({"type": "prop", "key": ["tree_oak", "tree_light", "tree_crooked"][int(Art.seed_at(v[0], v[1]) * 3.0)], "foot": foot, "height": cs * 3.7, "y": foot.y, "sway": true})
		else:
			var foot := Vector2.ZERO
			for v in prop["cells"]:
				foot += map.center_of(Vector2i(v[0], v[1])) * PX
			foot /= float(prop["cells"].size())
			entries.append({"type": "prop", "key": prop["kind"], "foot": foot, "height": cs * float(prop.get("h", 1.8)), "y": foot.y, "sway": false})
	# Small garden plants, deterministic and kept off all paths and door cells.
	for pos in def.get("art_gardens", []):
		if map.at(pos[0], pos[1]) != T.GRASS:
			continue
		var foot: Vector2 = map.center_of(Vector2i(pos[0], pos[1])) * PX
		entries.append({"type": "prop", "key": "bush_flower" if Art.seed_at(pos[0], pos[1]) > 0.5 else "bush_berry", "foot": foot, "height": cs * 0.72, "y": foot.y, "sway": true})
	for n in npcs:
		if _visible_for_hero(n["pos"]):
			entries.append({"type": "person", "n": n, "y": n["pos"].y * PX})
	entries.append({"type": "hero", "y": hero_pos.y * PX})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["y"] < b["y"])
	for e in entries:
		match e["type"]:
			"prop":
				var tint := Color.WHITE
				var foot: Vector2 = e["foot"]
				# Let a hero behind a crown remain readable.
				if absf(hero_pos.x * PX - foot.x) < cs and hero_pos.y * PX < foot.y and foot.y - hero_pos.y * PX < float(e["height"]):
					tint.a = 0.38
				Art.sprite(l, e["key"], foot, e["height"], tint, sin(art_time * 1.2 + foot.x) * 0.012 if e["sway"] else 0.0)
			"building":
				var b: Dictionary = e["b"]
				var rr: Array = b["rect"]
				var rect := Rect2(Vector2(rr[0], rr[1]) * cs, Vector2(rr[2], rr[3]) * cs)
				var kind: String = String(b.get("kind", "house"))
				if kind == "ruins":
					Art.sprite(l, "rock", rect.get_center(), minf(rect.size.x, rect.size.y) * 0.8, Color(0.8, 0.77, 0.69))
				else:
					var inside: bool = int(b["index"]) == _hero_bld
					var key: String = kind if kind in ["inn", "hall", "temple", "smithy", "healer"] else "house"
					var texture: Texture2D = Art.tex(key)
					# Спрайт нарисован фасадом к зрителю: ширина — ширина дома, низ — по южной стене (чуть ниже, на крыльцо),
					# крыша выше прямоугольника; сдвиг — чтобы дверь на картинке пришлась на клетку двери (Huzzah 2026-10-24)
					var h: float = rect.size.x * float(texture.get_height()) / float(texture.get_width())
					var shift: float = (float(b["door"][0]) + 0.5) * cs - (rect.position.x + rect.size.x * float(DOOR_AT.get(key, 0.5)))
					var sprite_rect := Rect2(Vector2(rect.position.x + shift, rect.end.y + cs * 0.35 - h), Vector2(rect.size.x, h))
					var alpha: float = 0.12 if inside else 1.0
					if inside:
						Art.surface(l, Art.tex("wood"), rect, TEX_PERIOD)
						l.draw_rect(rect, Color(0.22, 0.18, 0.12, 0.85), false, cs * 0.35)
					# Герой за домом (крыша выше стены) — дом полупрозрачный, чтобы пешку было видно
					if not inside and hero_pos.y * PX < rect.position.y and sprite_rect.grow(-cs * 0.3).has_point(hero_pos * PX):
						alpha = 0.45
					l.draw_texture_rect(texture, sprite_rect, false, Color(1, 1, 1, alpha))
					# Actual door position remains visible even when a facade is stylized.
					var door: Vector2 = map.center_of(Vector2i(b["door"][0], b["door"][1])) * PX
					if door.distance_to(hero_pos * PX) < cs * 3.0:
						l.draw_arc(door, cs * 0.30, 0, TAU, 20, Color(0.95, 0.86, 0.57, 0.85), 2.0)
					# Subtle chimney smoke, bounded and animated without a particle dependency.
					if not inside and kind in ["inn", "smithy", "house"]:
						for k in 4:
							var phase: float = fposmod(art_time * 0.20 + float(k) * 0.25 + float(rr[0]) * 0.03, 1.0)
							var smoke: Vector2 = sprite_rect.position + Vector2(sprite_rect.size.x * 0.65 + phase * cs * 0.5, cs * 0.4 - phase * cs * 1.6)
							l.draw_circle(smoke, cs * (0.07 + phase * 0.16), Color(0.68, 0.67, 0.60, (1.0 - phase) * 0.12))
			"person":
				var n: Dictionary = e["n"]
				_body(l, n["pos"], Color.WHITE, n["actor"], Vector2.ZERO)
			"hero":
				_body(l, hero_pos, Color(1.0, 0.82, 0.3), hero, hero_dir)
	# Labels and interaction markers remain above scenery, legible at any zoom.
	for b in map.buildings:
		var known: bool = discovered.has(String(b["id"]))
		if known or _map_view:
			var rr: Array = b["rect"]
			var center := Vector2(float(rr[0]) + float(rr[2]) * 0.5, float(rr[1]) + float(rr[3]) * 0.5) * cs
			_label(l, font, center, String(b["name"]) if known else "?", Color(1.0, 0.95, 0.8))
	for n in npcs:
		if n["pos"].distance_to(hero_pos) < 10.0 and _visible_for_hero(n["pos"]):
			_label(l, font, n["pos"] * PX + Vector2(0, -PX * 2.1), n["actor"].display_name + (I18n.t(" (спит)") if n["actor"].sleeping else ""), Color(0.98, 0.93, 0.78))
	for p in def.get("places", []):
		if discovered.has(p["id"]):
			var c: Vector2 = _place_pos(p) * PX
			l.draw_circle(c, 4.0, Color(1.0, 0.9, 0.4))
			_label(l, font, c + Vector2(0, -10), String(p["name"]), Color(1.0, 0.92, 0.6))
	# Башни каменной стены (кладка из набора Storybook): радиальный город — по кругу (поле "towers"),
	# прежний прямоугольный — по углам и у ворот
	if String(def.get("wall", "palisade")) == "stone":
		var towers: Array = []
		for t in def.get("towers", []):
			towers.append(Vector2i(t[0], t[1]))
		if towers.is_empty():
			towers = [Vector2i(0, 0), Vector2i(map.w - 1, 0), Vector2i(0, map.h - 1), Vector2i(map.w - 1, map.h - 1)]
			for g in def.get("gates", []):
				towers.append(Vector2i(g["cells"][0][0] - 1, g["cells"][0][1]))
				towers.append(Vector2i(g["cells"][-1][0] + 1, g["cells"][-1][1]))
		for t in towers:
			var c: Vector2 = map.center_of(t) * PX
			var tr := Rect2(c - Vector2(cs, cs) * 1.1, Vector2(cs, cs) * 2.2)
			Art.surface(l, Art.tex("masonry"), tr, TEX_PERIOD)
			Art.surface(l, Art.tex("roof"), Rect2(c - Vector2(cs, cs) * 0.75, Vector2(cs, cs) * 1.5), TEX_PERIOD)
			l.draw_rect(tr, Color(0.22, 0.18, 0.12, 0.85), false, 2.0)
	# Ворота: подпись и отметка «заперты»
	for g in def.get("gates", []):
		var c: Vector2 = Vector2.ZERO
		for v in g["cells"]:
			c += map.center_of(Vector2i(v[0], v[1]))
		c = c / g["cells"].size() * PX
		var shut: bool = map.closed_gates.has(String(g["id"]))
		_label(l, font, c + Vector2(0, -cs), "%s%s" % [g["name"], I18n.t(" (заперты)") if shut else ""], Color(1.0, 0.6, 0.5) if shut else Color(0.8, 1.0, 0.7))
		if shut:
			for v in g["cells"]:
				l.draw_rect(Rect2(Vector2(v[0], v[1]) * cs, Vector2(cs, cs)), Color(0.3, 0.2, 0.1))


func _draw_fog(l: Node2D) -> void:
	if map.w == 0:
		return
	var cs: float = map.cell_m * PX
	for y in map.h:
		var run_x: int = -1
		for x in map.w + 1:
			var hidden: bool = x < map.w and fog[y * map.w + x] == 0
			if hidden and run_x < 0:
				run_x = x
			elif not hidden and run_x >= 0:
				l.draw_rect(Rect2(Vector2(run_x, y) * cs, Vector2(x - run_x, 1) * cs), Color(0.05, 0.06, 0.07, 0.93))
				run_x = -1


# =====================================================================
# ИНТЕРФЕЙС
# =====================================================================
func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 20
	add_child(_ui)
	_top = _mk_label(16, Color("f0e2b6"))
	_top.position = Vector2(14, 10)
	_status = _mk_label(15, Color("e8dcb0"))
	_hint = _mk_label(15, Color("fff2c0"))
	_event = _mk_label(17, Color("ffffff"))
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", preload("res://ui/comic_ui.gd").panel(22.0, 0.96))   # рамка комикса (Q24)
	_panel.visible = false
	_panel.custom_minimum_size = Vector2(440, 0)
	_ui.add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_panel.add_child(v)
	_panel_title = Label.new()
	_panel_title.add_theme_font_size_override("font_size", 18)
	_panel_title.add_theme_color_override("font_color", Color("f0d890"))
	v.add_child(_panel_title)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 4)
	_tabs.visible = false
	v.add_child(_tabs)
	_panel_text = Label.new()
	_panel_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel_text.custom_minimum_size = Vector2(420, 0)
	_panel_text.add_theme_color_override("font_color", Color("ddd3b5"))
	v.add_child(_panel_text)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(420, 0)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	_panel_box = VBoxContainer.new()
	_panel_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_panel_box)


func _mk_label(size: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	_ui.add_child(l)
	return l


func _open_panel(kind: String, title: String, text: String, opts: Array, tabs: Array = []) -> void:
	_panel_kind = kind
	_panel_title.text = title
	for b in _tab_buttons:
		b.queue_free()
	_tab_buttons.clear()
	for t in tabs:
		var tb := Button.new()
		tb.text = t[0]
		tb.toggle_mode = true
		tb.button_pressed = bool(t[2])
		tb.focus_mode = Control.FOCUS_NONE
		tb.pressed.connect(t[1])
		_tabs.add_child(tb)
		_tab_buttons.append(tb)
	_tabs.visible = not tabs.is_empty()
	_panel_text.text = text
	_panel_text.visible = text != ""
	for b in _buttons:
		b.queue_free()
	_buttons.clear()
	for i in opts.size():
		var b := Button.new()
		b.text = "%s%s" % ["%d. " % (i + 1) if i < 9 else "", opts[i][0]]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(opts[i][1])
		_panel_box.add_child(b)
		_buttons.append(b)
	var sc: ScrollContainer = _panel_box.get_parent()
	# Высота списка по настоящей высоте кнопок: у рамок комикса (Q24) кнопка выше прежних 34 px
	var row: float = (_buttons[0].get_combined_minimum_size().y if not _buttons.is_empty() else 34.0) + float(_panel_box.get_theme_constant("separation"))
	sc.custom_minimum_size.y = minf(opts.size() * row, get_viewport_rect().size.y * 0.55)
	_panel.visible = true
	_panel.reset_size()
	var vp: Vector2 = get_viewport_rect().size
	_panel.position = Vector2(vp.x - _panel.size.x - 20.0, 60.0) if walking else (vp - _panel.size) * 0.5


func _close_panel() -> void:
	_panel.visible = false
	_panel_kind = ""
	_talk_npc = {}


func _say(text: String) -> void:
	if text == "":
		return
	event_text = text
	event_timer = 4.0


func _update_hud(env: Dictionary) -> void:
	var vp: Vector2 = get_viewport_rect().size
	var hour: float = clock.hour_of_day()
	var shut: Array = map.closed_gates.keys().map(func(id): return _gate_def(id).get("name", id))
	_top.text = I18n.t("%s   %02d:%02d   %d °C   Изведано %d %%%s") % [display_name, int(hour), int(fmod(hour, 1.0) * 60.0),
		int(round(float(env["temp_c"]))), int(explored_fraction() * 100.0),
		I18n.t("   заперты: ") + ", ".join(PackedStringArray(shut)) if not shut.is_empty() else ""]
	if Growth.has_growth(full_def):
		_top.text += "   %s" % Growth.stage_name(full_def, stage)
	if is_intruder():
		_top.text += I18n.t("   ЧУЖАК: ещё %.1f ч, держитесь подальше от стражи") % ((intruder_until - clock.total_seconds) / 3600.0)
	var a: Actor = hero
	if not a.alive:
		_status.text = I18n.t("Герой погиб: %s") % Actor.DEATH_CAUSES.get(a.death_cause, a.death_cause)
	else:
		_status.text = I18n.t("Здоровье %d  Сытость %d  Вода %d  Энергия %d  Силы %d   Деньги %d   Груз %.1f кг%s") % [
			int(a.res["health"]), int(a.res["hunger"]), int(a.res["thirst"]), int(a.res["energy"]),
			int(a.res["stamina"]), int(bag["money"]), Trade.weight(bag), I18n.t("   (спит)") if a.sleeping else ""]
	_status.position = Vector2(14.0, vp.y - 34.0)
	var hint: String = ""
	if not _panel.visible:
		var n: Dictionary = _nearest_npc()
		var p: Dictionary = _nearest_place()
		if not n.is_empty():
			hint = I18n.t("E — говорить: %s") % n["actor"].display_name
		elif not p.is_empty():
			hint = "E — %s: %s" % [{"water": I18n.t("пить"), "container": I18n.t("обыскать"), "bed": I18n.t("лечь спать")}.get(p.get("kind", ""), I18n.t("осмотреть")), p["name"]]
	_hint.text = hint if hint != "" else I18n.t("ЛКМ или WASD идти · ПКМ стоп · Shift бег · E говорить · I персонаж · Tab сумка · M план")
	_hint.position = Vector2(14.0, vp.y - 60.0)
	_top.visible = walking
	_hint.visible = walking
	if walking and not is_intruder():
		_hint.text += I18n.t(" · Esc город")
	_event.text = event_text if event_timer > 0.0 else ""
	_event.modulate.a = clampf(event_timer, 0.0, 1.0)
	_event.position = Vector2((vp.x - _event.size.x) * 0.5, 44.0)


# =====================================================================
# РОСТ ГОРОДА: поручения шести НПС (city_growth.gd)
# =====================================================================
func _growth_from(d: Dictionary) -> Dictionary:
	return {"done": d.get("done", []).duplicate(), "taken": d.get("taken", {}).duplicate(true)}


func hero_km() -> float:
	return hero.distance_m / 1000.0


## Победы героя в боях за всю игру (их считает Worlds); без игры — test_wins
func battles_won() -> int:
	var w: Node = get_node_or_null("/root/Worlds")
	if w != null and w.get("battles_won") != null:
		return int(w.battles_won) + test_wins
	return test_wins


func quest_status(q: Dictionary) -> String:
	var p: Array = Growth.progress(growth, q, bag, hero_km(), battles_won())
	match String(q["kind"]):
		"walk":
			return I18n.t("пройдено %.1f из %d км") % [minf(float(p[0]), float(p[1])), int(p[1])]
		"win":
			return I18n.t("побед %d из %d") % [mini(int(p[0]), int(p[1])), int(p[1])]
		"bring":
			return I18n.t("%s: %d из %d") % [Trade.item_name(String(q["item"])), mini(int(p[0]), int(p[1])), int(p[1])]
		"pay":
			return I18n.t("%d монет, у вас %d") % [int(p[1]), int(p[0])]
	return ""


## Добавка Красноречия к деньгам за поручение (уговорить заплатить больше)
func _speech_extra(q: Dictionary) -> int:
	return int(floor(float(q.get("reward", 0)) * Sheet.quest_bonus(hero))) if hero != null else 0


func _quest_reward(q: Dictionary) -> String:
	var r: int = int(q.get("reward", 0)) + _speech_extra(q)
	if q.get("endless", false):
		return I18n.t("Награда: %d монет.") % r
	return I18n.t("Награда: %d монет. Город вырастет.") % r if r > 0 else I18n.t("Город вырастет.")


func quest_offer(n: Dictionary, q: Dictionary) -> void:
	_open_panel("talk", "%s: %s" % [n["actor"].display_name, q["title"]], "«%s»\n\n%s" % [q["ask"], _quest_reward(q)], [
		[I18n.t("Взяться"), func(): take_quest(n, q)], [I18n.t("Назад"), func(): open_quests(n)]])


func take_quest(n: Dictionary, q: Dictionary) -> void:
	Growth.take(growth, q, hero_km(), battles_won())
	_say(I18n.t("Поручение: %s") % q["title"])
	open_quests(n)


func turn_in(n: Dictionary, q: Dictionary) -> void:
	if not Growth.ready(growth, q, bag, hero_km(), battles_won()):
		_open_panel("talk", "%s: %s" % [n["actor"].display_name, q["title"]], I18n.t("«%s»\n\nСейчас: %s.") % [q["ask"], quest_status(q)], [[I18n.t("Назад"), func(): open_quests(n)]])
		return
	var was: int = stage
	var nb: int = def.get("buildings", []).size()
	var nn: int = npcs.size()
	var id: String = String(n["def"]["id"])
	var extra: int = _speech_extra(q)
	Growth.complete(full_def, growth, q, bag)
	var text: String = "«%s»" % q["done"]
	if int(q.get("reward", 0)) > 0:
		text += I18n.t("\n\nПолучено %d монет.") % int(q["reward"])
	if extra > 0:
		bag["money"] = int(bag["money"]) + extra
		text += I18n.t(" Красноречие выторговало ещё %d.") % extra
	# Опыт за поручение: основа + за каждую монету награды [ВРЕМЕННО]
	if hero != null:
		var lv: int = hero.level
		var gx: float = Sheet.num("xp", "quest_base", 50) + Sheet.num("xp", "quest_per_coin", 2) * float(q.get("reward", 0))
		Sheet.gain_xp(hero, gx)
		text += I18n.t("\n\nОпыт +%d.") % int(gx)
		if hero.level > lv:
			text += I18n.t(" Новый уровень: %d! Очки навыков и дары — в окне героя (I).") % hero.level
	if Growth.stage(full_def, growth) != was:
		_rebuild_stage()
		text += I18n.t("\n\n%s растёт: теперь это %s. Новых домов: %d, новых жителей: %d.") % [
			display_name, Growth.stage_name(full_def, stage), def["buildings"].size() - nb, npcs.size() - nn]
		_say("%s — %s" % [display_name, Growth.stage_name(full_def, stage)])
	else:
		var need: int = Growth.next_points(full_def, stage)
		if need > 0:
			text += I18n.t("\n\nДо этапа «%s» сдать ещё поручений: %d.") % [Growth.stage_name(full_def, stage + 1), need - Growth.points(growth)]
	for m in npcs:
		if String(m["def"]["id"]) == id:
			n = m
	_open_panel("talk", "%s: %s" % [n["actor"].display_name, q["title"]], text, [[I18n.t("Назад"), func(): open_quests(n)]])


## Перестроить город по нынешнему этапу: новые дома и жители появляются сразу, прежние жители сохраняют состояние
func _rebuild_stage() -> void:
	var keep: Dictionary = {}
	for n in npcs:
		keep[String(n["def"]["id"])] = n
	stage = Growth.stage(full_def, growth)
	def = Growth.view(full_def, stage)
	map.build(def)
	_spawn_npcs()
	for n in npcs:
		var old: Dictionary = keep.get(String(n["def"]["id"]), {})
		if old.is_empty():
			continue
		n["actor"] = old["actor"]
		n["stock"] = old["stock"]
		n["line_i"] = old["line_i"]
		if map.is_free(old["pos"], BODY_R):
			n["pos"] = old["pos"]
	_make_lights()
	if not map.is_free(hero_pos, BODY_R):
		hero_pos = _free_near(hero_pos)
	_hero_bld = map.building_at(hero_pos)
	route.cancel()
	_ground.queue_redraw()
	_fog_dirty = true


func _free_near(p: Vector2) -> Vector2:
	var c: Vector2i = map.cell_of(p)
	for r in range(1, 16):
		for y in range(c.y - r, c.y + r + 1):
			for x in range(c.x - r, c.x + r + 1):
				var q: Vector2 = map.center_of(Vector2i(x, y))
				if map.is_free(q, BODY_R):
					return q
	return p


## Доска объявлений: этап города и поручения, открытые сейчас
func _board_text(p: Dictionary) -> String:
	if not Growth.has_growth(full_def):
		return String(p.get("text", ""))
	var lines: Array = []
	var need: int = Growth.next_points(full_def, stage)
	lines.append(I18n.t("%s — %s. Сдано поручений: %d%s.") % [display_name, Growth.stage_name(full_def, stage), Growth.points(growth),
		I18n.t(", до этапа «%s» нужно %d") % [Growth.stage_name(full_def, stage + 1), need] if need > 0 else ""])
	for n in npcs:
		for q in Growth.available(full_def, growth, String(n["def"]["id"])):
			lines.append("— %s: %s%s" % [n["actor"].display_name, q["title"], I18n.t(" (взято: %s)") % quest_status(q) if Growth.taken(growth, q) else ""])
	if lines.size() == 1:
		lines.append(I18n.t("Новых поручений нет."))
	return "\n".join(PackedStringArray(lines))


# =====================================================================
# ЭКРАН ГОРОДА (city_menu.gd)
# =====================================================================
func open_menu() -> void:
	walking = false
	route.cancel()
	if _map_view:
		toggle_map()
	_close_panel()
	event_timer = 0.0
	menu.open()


## «Пройтись по городу»: прежняя пешая карта, герой у ворот (или где был)
func walk_city() -> void:
	walking = true
	_close_panel()
	menu.close()
	cam.position = hero_pos * PX
	cam.reset_smoothing()
	_say(I18n.t("%s: вы идёте по улицам. Esc — назад к экрану города") % display_name)


## «Поговорить»: жители без своего дела
func menu_people(list: Array) -> void:
	var opts: Array = []
	for n in list:
		var a: Actor = n["actor"]
		opts.append(["%s%s" % [a.display_name, I18n.t(" (спит)") if a.sleeping else ""], func(): talk(n)])
	opts.append([I18n.t("Назад"), _close_panel])
	_open_panel("talk", I18n.t("Поговорить"), "" if not list.is_empty() else I18n.t("Больше никого нет."), opts)


## «Покинуть город»: через те же ворота; ночью заперто — привратник выпустит за плату
func menu_leave() -> void:
	var g: String = _gate_in if _gate_in != "" else String(def.get("gates", [{}])[0].get("id", ""))
	if not map.closed_gates.has(g):
		_leave(g)
		return
	for n in npcs:
		if String(n["def"].get("gate", "")) == g and not n["actor"].sleeping:
			talk(n)
			_panel_text.text = I18n.t("Ворота заперты до %d:00. %s") % [int(rules.get("gates_open_h", 6.0)), _panel_text.text]
			return
	_open_note(String(_gate_def(g).get("name", I18n.t("Ворота"))), I18n.t("Ворота заперты до %d:00, привратника нет. Переночуйте в городе.") % int(rules.get("gates_open_h", 6.0)))


# =====================================================================
# СОХРАНЕНИЕ
# =====================================================================
func to_dict() -> Dictionary:
	var list: Array = []
	for n in npcs:
		list.append({"id": n["def"]["id"], "actor": n["actor"].to_dict(), "pos": [n["pos"].x, n["pos"].y], "stock": n["stock"].duplicate(), "line_i": n["line_i"]})
	var d: Dictionary = {
		"city_id": city_id, "hero_pos": [hero_pos.x, hero_pos.y], "fog": Marshalls.raw_to_base64(fog),
		"discovered": discovered.keys(), "looted": looted.duplicate(), "paid_gate": paid_gate.duplicate(), "npcs": list,
		"intruder_until": intruder_until, "left": leaving, "growth": growth.duplicate(true), "walking": walking,
		"trails": trails.to_dict(),
	}
	if own_bag:
		d["bag"] = bag.duplicate(true)
	return d


func load_dict(d: Dictionary) -> void:
	if d.is_empty() or String(d.get("city_id", city_id)) != city_id:
		return
	# Состояние, снятое при выходе (left), не двигает героя: при новом входе он у ворот или у стены
	if d.has("hero_pos") and not bool(d.get("left", false)):
		hero_pos = Vector2(d["hero_pos"][0], d["hero_pos"][1])
		intruder_until = float(d.get("intruder_until", -1.0))
	if d.get("growth") is Dictionary:
		growth = _growth_from(d["growth"])
		if Growth.stage(full_def, growth) != stage:
			_rebuild_stage()
	var f: PackedByteArray = Marshalls.base64_to_raw(String(d.get("fog", "")))
	if f.size() == fog.size():
		fog = f
	discovered.clear()
	for k in d.get("discovered", []):
		discovered[k] = true
	looted = d.get("looted", {}).duplicate()
	paid_gate = d.get("paid_gate", {}).duplicate()
	for e in d.get("npcs", []):
		for n in npcs:
			if n["def"]["id"] == e["id"]:
				n["actor"] = Actor.from_dict(e["actor"])
				n["pos"] = Vector2(e["pos"][0], e["pos"][1])
				n["stock"] = e.get("stock", n["stock"]).duplicate()
				n["line_i"] = int(e.get("line_i", 0))
				n["goal"] = Vector2.INF
	if own_bag and d.has("bag"):
		bag.clear()
		bag.merge(d["bag"].duplicate(true))
	trails.load_dict(d.get("trails", {}))
	_trails_at = -1.0
	_ground.queue_redraw()
	_hero_bld = map.building_at(hero_pos)
	_fog_dirty = true
	_last_clock = -1.0

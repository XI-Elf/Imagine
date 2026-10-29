extends Node2D
const Art := preload("res://storybook/art.gd")
## Персонажі на карті: герой гравця й НПС. Правила в усіх одні (Actor, world_env.gd);
## різниця лише у «водії»: героєм керує гравець (клавіші), НПС — простий розпорядок (_npc_think).
## Потреби рахуються в ігровому часі годинника, кроки — у реальному (масштаб ×8 × GameClock.GAME_SPEED, див. actor.gd).
## [ВІДПОВІДЬ АВТОРА, 2026-10-22] «на цьому етапі не створюй НПС поза містом»: OVERWORLD_NPCS = false —
## на загальній карті лише герой; розпорядок НПС залишено для spawn_npc (тести, майбутні поселення).
## НПС далеко від героя й камери рахуються шматками по FAR_TICK_S ігрових секунд, за тими самими правилами.
##
## Клавіші: G — створити героя (біля брами міста) / узяти або відпустити керування, WASD — іти, Shift — бігти,
## Z — спати/прокинутися, E — пити біля води, F — шукати їжу й матеріали (world/foraging.gd), T — лікуватися в лікаря поруч, I — аркуш персонажа.
## Миша (characters/hero_route.gd): ЛКМ — іти в точку (містом — до брами), тримати ЛКМ — за курсором, ПКМ — стоп.

const WorldEnv := preload("res://characters/world_env.gd")
const R := preload("res://characters/actor_rules.gd")
const Sheet := preload("res://characters/sheet.gd")
const HeroProfile := preload("res://characters/hero_profile.gd")
const HeroCreateScript := preload("res://characters/hero_create.gd")
const HeroWindowScript := preload("res://characters/hero_window.gd")
const HeroDeath := preload("res://characters/hero_death.gd")
const HeroRoute := preload("res://characters/hero_route.gd")
const Ruins := preload("res://world/ruins.gd")
const Codex := preload("res://world/codex.gd")
const Trade := preload("res://city/trade.gd")
const TransportScript := preload("res://characters/transport.gd")
const Foraging := preload("res://world/foraging.gd")

const OVERWORLD_NPCS: bool = false
const NPC_COUNT: int = 8
const NPC_RADIUS_M: float = 600.0       # [Q19: не баланс, залишено] НПС блукають у цьому радіусі від дому
const NEAR_M: float = 4000.0            # ближчі за це до героя або камери НПС рахуються щокадру
const FAR_TICK_S: float = 600.0
const DRINK_REACH_M: float = 25.0
const WATER_SEARCH_M: float = 1500.0
const FORAGE_COOLDOWN_S: float = 3.0
const HEAL_REACH_M: float = 30.0
## Загальна карта: герой і НПС — лише точки за будь-якого масштабу (Huzzah 2026-10-29: «тут усе ще текстура
## персонажа, а має бути точка»); фігурки лишилися в місті й у бою
const DOTS_ONLY: bool = true
const HEAL_RETRY_S: float = 20.0        # реальних секунд між спробами лікування в одного НПС
const TOWER_REACH_M: float = 8.0        # F біля підніжжя сигнальної вежі — залізти
const TOWER_VIEW_M: float = 2500.0      # [ВРЕМЕННО] огляд з вежі вдень
const TOWER_MIN: float = 20.0           # [ВРЕМЕННО] ігрових хвилин на підйом і спуск
const TOWER_STAMINA: float = 30.0       # [ВРЕМЕННО] сил на підйом
static var NPC_NAMES: Array = [I18n.t("Эйвинд"), I18n.t("Сигрид"), I18n.t("Кормак"), I18n.t("Айсте"), I18n.t("Годрик"), I18n.t("Ингрид"), I18n.t("Ниалл"), I18n.t("Милда"),
	I18n.t("Хокон"), I18n.t("Эдит"), I18n.t("Фергус"), I18n.t("Расма"), I18n.t("Леофрик"), I18n.t("Тора"), I18n.t("Витаутас"), I18n.t("Сорха")]

var game: Node2D
var bodies: Array = []          # {actor, pos, home, target, plan, wait, acc_s, drowning, hero, kit, heal_cd}
var hero: Dictionary = {}
var controls_hero: bool = false
var hold_hero: bool = false     # герой стоїть, поки гравець обирає біля поселення (world/settlements.gd)
var hero_away: bool = false     # герой у місті або в бою (worlds/worlds.gd): тут лише його потреби за годинником
var sheet_visible: bool = false   # відкрито вікно героя або створення героя: герой стоїть
var window: CanvasLayer             # вікно героя (characters/hero_window.gd): I — характеристики, Tab — інвентар
var _creator: CanvasLayer           # екран створення героя (characters/hero_create.gd), поки відкритий
var _last_clock: float = -1.0
var _forage_cd: float = 0.0
var ruins_looted: Dictionary = {}       # руїни на карті (world/ruins.gd): "x:y" -> ігрові секунди обшуку
var field_searched: Dictionary = {}     # пошук у полі (world/foraging.gd): клітина -> до коли порожня
var _rng := RandomNumberGenerator.new()
var _status: Label
var route: Node2D               # хід мишею: шлях героя до точки (hero_route.gd)
var transport: Node2D           # кінь і віз героя (transport.gd): R — верхи / пішки
var death: Node                 # екран загибелі героя й нового персонажа (hero_death.gd)


func setup(g: Node2D) -> void:
	game = g
	_rng.randomize()
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 15)
	_status.add_theme_color_override("font_color", Color("e8dcb0"))
	_status.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_status.add_theme_constant_override("outline_size", 4)
	layer.add_child(_status)
	window = HeroWindowScript.new()
	window.setup(func() -> Actor: return hero["actor"] if not hero.is_empty() else null, _inventory)
	add_child(window)
	route = HeroRoute.new()
	add_child(route)
	route.setup(self)
	transport = TransportScript.new()
	add_child(transport)
	transport.setup(self)
	death = HeroDeath.new()
	add_child(death)
	death.setup(self)


# Спільна сумка героя — у менеджера світів (worlds/worlds.gd); без нього своя
var _own_bag: Dictionary = {"money": 0, "items": {}}
func _inventory() -> Dictionary:
	var w: Node = get_node_or_null("/root/Worlds")
	return w.inventory if w != null else _own_bag


## Екран створення героя; після «Створити» герой з'являється біля брами міста. Esc — скасування
func open_creator() -> void:
	if _creator != null:
		return
	_creator = HeroCreateScript.new()
	add_child(_creator)
	_creator.finished.connect(func(p: Dictionary) -> void:
		_creator.queue_free()
		_creator = null
		if not p.is_empty():
			create_hero(p))


## Новий герой за вибором з екрана створення (characters/hero_profile.gd) біля брами міста
func create_hero(params: Dictionary) -> void:
	bodies = bodies.filter(func(x): return not x["hero"])
	var at: Vector2 = game.settlements.spawn_point() if game.get("settlements") != null else Vector2.INF
	spawn_hero(at if at != Vector2.INF else game.cam_pos, params)


# =====================================================================
# СТВОРЕННЯ
# =====================================================================
func _land(p: Vector2) -> bool:
	var b: int = game.biome_at(p)
	return b != 0 and b != 1


# Чистий суходіл: без прокляття (будинки й стоянки НПС, місце появи героя)
func _clean_land(p: Vector2) -> bool:
	return _land(p) and float(R.terrain(game.biome_at(p)).get("radiation_h", 0.0)) <= 0.0 \
		and not (game.get("settlements") != null and game.settlements.blocks(p))


# Найближча до p точка суходолу (clean — чистого), кільцями; не знайшлася — p
func _find_land(p: Vector2, max_r: float = 3000.0, clean: bool = false) -> Vector2:
	var good: Callable = _clean_land if clean else _land
	if good.call(p):
		return p
	var r: float = 50.0
	while r <= max_r:
		for k in 24:
			var q: Vector2 = p + Vector2.from_angle(TAU * k / 24.0) * r
			if good.call(q):
				return q
		r += 50.0
	return p


func _add(actor: Actor, pos: Vector2, is_hero: bool) -> Dictionary:
	var b: Dictionary = {"actor": actor, "pos": pos, "home": pos, "target": pos, "plan": "idle",
		"wait": 0.0, "acc_s": 0.0, "drowning": false, "hero": is_hero, "kit": {}, "heal_cd": 0.0, "restock_at": 0.0}
	bodies.append(b)
	actor.died.connect(func(cause: String) -> void: _on_died(b, cause))
	if is_hero:
		actor.leveled_up.connect(func(lv: int) -> void: _event("Новый уровень %d: очки навыков%s — окно героя (I)" % [lv, " и дар" if actor.perk_picks > 0 else ""]))
	return b


func spawn_hero(at: Vector2, params: Dictionary = {}) -> void:
	var p: Vector2 = _find_land(at, 8000.0, true)
	if not _land(p):
		p = _find_land(at)
	var a := Actor.new("hero", I18n.t("Герой"), false, _rng.randi())
	if not params.is_empty():
		HeroProfile.apply(a, params)
	hero = _add(a, p, true)
	if route != null:
		route.cancel()
	controls_hero = true
	if OVERWORLD_NPCS and bodies.filter(func(x): return not x["hero"]).is_empty():
		_spawn_npcs(p)
	_event(I18n.t("Герой появился: %s") % game.biome_name(p))


## НПС на загальній карті вручну (тести, майбутні поселення): ті самі правила й розпорядок
func spawn_npc(actor: Actor, pos: Vector2, kit: Variant = {}) -> Dictionary:
	var b: Dictionary = _add(actor, pos, false)
	b["kit"] = as_kit(kit)
	b["restock_at"] = _now() + restock_s()
	return b


func _spawn_npcs(center: Vector2) -> void:
	var names: Array = NPC_NAMES.duplicate()
	for i in NPC_COUNT:
		var a := Actor.new("npc_%d" % i, names.pop_at(_rng.randi() % names.size()), true, _rng.randi())
		for s in Actor.STATS:
			a.set_stat(s, _rng.randi_range(3, 8))
		a.res["hunger"] = _rng.randf_range(40.0, 90.0)
		a.res["thirst"] = _rng.randf_range(40.0, 90.0)
		# У каждого НПС свое ремесло (навык пака → навык): лекарь, кузнец, повар...
		var sk: Array = R.pack_skills().keys()
		a.set_skill_level(sk[i % sk.size()], _rng.randi_range(2, 5))
		var p: Vector2 = _find_land(center + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(150.0, NPC_RADIUS_M * 1.5), 3000.0, true)
		var b: Dictionary = _add(a, p, false)
		# Лікар носить запас ліків (Q36): скінченний, поповнюється в місті
		if sk[i % sk.size()] == "medicine":
			b["kit"] = full_kit()
			b["restock_at"] = _now() + restock_s()


static func all_remedies() -> Array:
	var out: Array = []
	var tr: Dictionary = R.section("treatments")
	for id in tr:
		for it in tr[id].get("items", []):
			if not out.has(it):
				out.append(it)
	return out


## Запас лікаря (Q36, відповідь Huzzah — варіант B): {предмет: штук}, по medicine.npc_kit_each кожного.
## Витрачається на лікування; раз на medicine.npc_restock_days ігрових діб лікар ходить у місто й поповнює запас.
## Героя лікує за medicine.npc_heal_fee монет (платить за спробу, якщо в лікаря є потрібне), НПС одне одного — задарма.
static func full_kit() -> Dictionary:
	var n: int = int(R.section("medicine").get("npc_kit_each", 3))
	var out: Dictionary = {}
	for it in all_remedies():
		out[it] = n
	return out


## Список предметів (старі сейви й тести) → повний запас цих предметів
static func as_kit(kit: Variant) -> Dictionary:
	if kit is Dictionary:
		return kit
	var n: int = int(R.section("medicine").get("npc_kit_each", 3))
	var out: Dictionary = {}
	for it in kit:
		out[String(it)] = n
	return out


## Що лікар може дати просто зараз (чого лишилося хоч одне)
static func kit_items(kit: Dictionary) -> Array:
	return kit.keys().filter(func(k): return int(kit[k]) > 0)


static func restock_s() -> float:
	return float(R.section("medicine").get("npc_restock_days", 2.0)) * 86400.0


func _now() -> float:
	return game.clock.total_seconds if game != null and game.clock != null else 0.0


## Лікар сходив у місто: запас знову повний
func _restock(b: Dictionary) -> void:
	if b["kit"].is_empty() or _now() < float(b["restock_at"]):
		return
	for it in b["kit"]:
		b["kit"][it] = int(R.section("medicine").get("npc_kit_each", 3))
	b["restock_at"] = _now() + restock_s()


# Найближчий живий лікар (у кого в запасі є хоч щось), крім самого b
func _nearest_healer(b: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = INF
	for o in bodies:
		if o == b or kit_items(o["kit"]).is_empty() or not o["actor"].alive or o["actor"].sleeping:
			continue
		var d: float = o["pos"].distance_to(b["pos"])
		if d < best_d:
			best_d = d
			best = o
	return best


## Лікування в лікаря: перший зі станів пацієнта, який лікар береться лікувати. Для героя й НПС однаково
func heal_at(patient: Dictionary, healer: Dictionary) -> Dictionary:
	var a: Actor = patient["actor"]
	for c in a.conditions:
		var r: Dictionary = a.treat(c["id"], healer["actor"], kit_items(healer["kit"]))
		for used in r["used"]:
			healer["kit"][used] = int(healer["kit"].get(used, 0)) - 1
		r["id"] = c["id"]
		return r
	return {"ok": false, "reason": I18n.t("нечего лечить"), "id": ""}


func _on_died(b: Dictionary, cause: String) -> void:
	var a: Actor = b["actor"]
	_event(I18n.t("%s погиб: %s") % [a.display_name, Actor.DEATH_CAUSES.get(cause, cause)])
	if b["hero"]:
		controls_hero = false


func _event(text: String) -> void:
	game.event_text = text
	game.event_timer = 5.0


# =====================================================================
# ЧАС І РУХ
# =====================================================================
func _process(delta: float) -> void:
	if game == null or not game.ready_done:
		return
	if Engine.has_meta("aw_new_hero"):
		var np: Variant = Engine.get_meta("aw_new_hero")
		Engine.remove_meta("aw_new_hero")
		if np is Dictionary and not np.is_empty():
			create_hero(np)
	var now: float = game.clock.total_seconds
	var dt_game: float = 0.0 if _last_clock < 0.0 else maxf(now - _last_clock, 0.0)
	_last_clock = now
	_forage_cd = maxf(_forage_cd - delta, 0.0)
	var focus: Vector2 = hero["pos"] if not hero.is_empty() else game.cam_pos
	for b in bodies:
		var a: Actor = b["actor"]
		if not a.alive:
			continue
		var env: Dictionary = WorldEnv.sample(game, b["pos"])
		var near: bool = b["hero"] or b["pos"].distance_to(focus) < NEAR_M or b["pos"].distance_to(game.cam_pos) < NEAR_M
		if near:
			a.tick(dt_game + b["acc_s"], env)
			b["acc_s"] = 0.0
		else:
			b["acc_s"] += dt_game
			if b["acc_s"] >= FAR_TICK_S:
				a.tick(b["acc_s"], env)
				b["acc_s"] = 0.0
		if not a.alive:
			continue
		if b["hero"]:
			if not hero_away:
				_drive_hero(b, env, delta)
		else:
			_npc_think(b, env, delta)
	if controls_hero and not hero.is_empty() and not game.global_map:
		game.cam_pos = hero["pos"]
		game._clamp_camera()
	_update_status()
	queue_redraw()


# Крок до точки або в напрямку; повертає, чи зрушив.
# НПС у воду самі не заходять (плавати вміють, але тонуть без сил); герой — з волі гравця
func _step(b: Dictionary, dir: Vector2, run: bool, delta: float) -> bool:
	var a: Actor = b["actor"]
	var env: Dictionary = WorldEnv.sample(game, b["pos"])
	if dir == Vector2.ZERO or not a.can_move():
		b["drowning"] = a.exert(delta, env, "rest")
		return false
	var v: float = a.travel_speed(env, run) * slope_factor(b["pos"], dir)
	var trails: Node = game.get("trails")
	if trails != null:
		v *= trails.speed_mult(b["pos"])
	var next: Vector2 = b["pos"] + dir.normalized() * v * delta
	var into_water: bool = not b["hero"] and game.biome_at(next) == 1 and game.biome_at(b["pos"]) != 1
	if game.biome_at(next) == 0 or v <= 0.0 or into_water or _walled(next, b["pos"]):
		b["drowning"] = a.exert(delta, env, "rest")
		return false
	b["drowning"] = a.exert(delta, env, "run" if run and a.can_run() else "walk")
	a.note_travel(b["pos"].distance_to(next), env)
	b["pos"] = next
	if trails != null:
		trails.walked(b)
	return true


## Під гору повільніше, з гори трохи швидше (об'єм гір, Huzzah 2026-10-24) [Q19: не баланс, залишено]: ухил за картою висот на 12 м уперед
func slope_factor(p: Vector2, dir: Vector2) -> float:
	if not game.has_method("height_at") or dir == Vector2.ZERO:
		return 1.0
	var grade: float = (game.height_at(p + dir.normalized() * 12.0) - game.height_at(p)) / 12.0
	return clampf(1.0 / (1.0 + maxf(grade, 0.0) * 1.2), 0.55, 1.0) * (1.0 + clampf(-grade * 0.3, 0.0, 0.08))


# Стіна міста на загальній карті (world/settlements.gd): ззовні всередину не пройти, зсередини вийти можна
func _walled(next: Vector2, cur: Vector2) -> bool:
	var st: Node = game.get("settlements")
	return st != null and st.blocks(next) and not st.blocks(cur)


func _drive_hero(b: Dictionary, env: Dictionary, delta: float) -> void:
	var dir := Vector2.ZERO
	# Переміщення зупиняється, поки відкрите будь-яке меню (правило пакета), зокрема аркуш
	if controls_hero and not hold_hero and not game.menu_open and not game.typing and not sheet_visible:
		dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		if Input.is_physical_key_pressed(KEY_A): dir.x -= 1
		if Input.is_physical_key_pressed(KEY_D): dir.x += 1
		if Input.is_physical_key_pressed(KEY_W): dir.y -= 1
		if Input.is_physical_key_pressed(KEY_S): dir.y += 1
	var a: Actor = b["actor"]
	if dir != Vector2.ZERO and a.sleeping:
		a.set_sleep(false)
	# Клавіші перебивають шлях мишею; без клавіш герой іде шляхом
	var by_route: bool = false
	if dir != Vector2.ZERO:
		route.cancel()
	elif controls_hero and not hold_hero and not game.menu_open and not sheet_visible and route.active():
		dir = route.steer(b["pos"])
		by_route = dir != Vector2.ZERO
	var goal: Vector2 = route.final_point() if by_route else Vector2.INF
	var from: Vector2 = b["pos"]
	var moved: bool = _step(b, dir.limit_length(1.0), Input.is_physical_key_pressed(KEY_SHIFT), delta)
	# Крок дотягнувся до точки кліку або перескочив її — стати точно в неї (раніше герой
	# зупинявся за 3 м до цілі, а біля самої цілі метався туди-сюди)
	if goal != Vector2.INF and b["pos"].distance_to(from) >= from.distance_to(goal) - 0.01:
		if game.biome_at(goal) != 0 and not _walled(goal, from):
			b["pos"] = goal
		route.cancel()
	elif by_route:
		route.stepped(moved, delta)


func _unhandled_input(event: InputEvent) -> void:
	if game == null or not game.ready_done or game.typing or game.menu_open:
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if _creator != null or (death != null and death.active):
		return
	match event.physical_keycode:
		KEY_G:
			if hero.is_empty() or not hero["actor"].alive:
				# Новий герой — через екран створення; з'являється біля брами міста (world/settlements.gd)
				open_creator()
			else:
				controls_hero = not controls_hero
				_event(I18n.t("Управление героем") if controls_hero else I18n.t("Свободная камера"))
		KEY_I:
			if not hero.is_empty():
				window.toggle("stats")
		KEY_TAB:
			if not hero.is_empty():
				window.toggle("bag")
		KEY_Z:
			if _hero_alive():
				hero["actor"].set_sleep(not hero["actor"].sleeping)
				_event(I18n.t("Сон") if hero["actor"].sleeping else I18n.t("Проснулся"))
		KEY_E:
			if _hero_alive():
				if _water_near(hero["pos"]):
					hero["actor"].drink(25.0, "raw")
					_event(I18n.t("Напился из реки"))
				else:
					_event(I18n.t("Воды рядом нет"))
		KEY_T:
			if _hero_alive():
				var h: Dictionary = _nearest_healer(hero)
				var fee: int = int(R.section("medicine").get("npc_heal_fee", 6))
				var bag: Dictionary = _inventory()
				if h.is_empty() or h["pos"].distance_to(hero["pos"]) > HEAL_REACH_M:
					_event(I18n.t("Лекаря рядом нет"))
				elif hero["actor"].conditions.is_empty():
					_event(I18n.t("Лечить нечего"))
				elif int(bag.get("money", 0)) < fee:
					_event(I18n.t("Лечение у лекаря — %d монет, не хватает денег") % fee)
				else:
					var r: Dictionary = heal_at(hero, h)
					var paid: bool = float(r.get("chance", 0.0)) > 0.0
					if paid:
						bag["money"] = int(bag["money"]) - fee
					var nm: String = R.condition(r["id"]).get("name_ru", r["id"])
					var msg: String = I18n.t("%s вылечил: %s (шанс %d %%)") % [h["actor"].display_name, nm, int(r["chance"] * 100.0)] if r["ok"] else "%s: %s — %s" % [h["actor"].display_name, nm, r["reason"]]
					_event(msg + (I18n.t(", −%d монет") % fee if paid else ""))
		KEY_F:
			if _hero_alive() and _forage_cd <= 0.0:
				_forage_cd = FORAGE_COOLDOWN_S
				var site: Dictionary = Ruins.near(game, hero["pos"])
				var wm: Node = get_node_or_null("/root/Worlds")
				var cart_i: int = HeroDeath.cart_near(wm, hero["pos"], game.clock.total_seconds)
				var tower: Vector2 = tower_near(hero["pos"])
				if cart_i >= 0:
					_event(HeroDeath.take_cart(wm, cart_i))
				elif tower != Vector2.INF:
					_event(climb_tower(tower))
				elif not site.is_empty():
					_event(search_ruins(site))
				else:
					_event(search_field())
		_:
			return
	get_viewport().set_input_as_handled()


## Сигнальна вежа поруч із точкою (storybook/world_decor.gd) або Vector2.INF
func tower_near(p: Vector2) -> Vector2:
	var d: Node = game.get("decor") if game != null else null
	if d == null or not d.has_method("tower_near"):
		return Vector2.INF
	return d.tower_near(p, TOWER_REACH_M)


## Залізти на сигнальну вежу (Huzzah 2026-10-29: «вежа є, а взаємодії немає»): згори видно далеко — туман
## війни відкривається на TOWER_VIEW_M (уночі вдвічі менше), іде TOWER_MIN ігрових хвилин і TOWER_STAMINA сил.
## У старому щитку раз на кілька днів (як руїни) — брухт, іноді записка давніх
func climb_tower(at: Vector2) -> String:
	var a: Actor = hero["actor"]
	if float(a.res["stamina"]) < TOWER_STAMINA:
		return I18n.t("Слишком мало сил, чтобы лезть на вышку")
	a.add_res("stamina", -TOWER_STAMINA)
	game.clock.skip(TOWER_MIN * 60.0)
	var night: bool = bool(WorldEnv.sample(game, at).get("night", false))
	var view: float = TOWER_VIEW_M * (0.5 if night else 1.0)
	var fl: Node = game.get("fog")
	if fl != null and fl.get("model") != null:
		fl.model.reveal(at, view)
	a.add_xp("survival", 1.0)
	var msg: String = I18n.t("Забрались на сигнальную вышку: сверху видно на %.1f км вокруг") % (view / 1000.0)
	var key: String = "tower:%d:%d" % [int(at.x), int(at.y)]
	if not Ruins.looted_now(ruins_looted, key, game.clock.total_seconds):
		ruins_looted[key] = game.clock.total_seconds
		var w: Node = get_tree().root.get_node_or_null("Worlds") if is_inside_tree() else null
		var bag: Dictionary = w.inventory if w != null else {}
		var n_scrap: int = _rng.randi_range(1, 2)
		if not bag.has("items"):
			bag["items"] = {}
		bag["items"]["scrap"] = int(bag["items"].get("scrap", 0)) + n_scrap
		msg += I18n.t(". В щитке наверху: %s ×%d") % [Trade.item_name("scrap"), n_scrap]
		if w != null:
			var note: Dictionary = Codex.find(w.codex, "ruins", _rng, game.clock.total_seconds)
			if not note.is_empty():
				msg += I18n.t(". Там же записка: «%s» (дневник героя, вкладка 6)") % note["title"]
	return msg


## Обшукати руїни поруч із героєм (питання Q04): брухт і монети — у сумку героя (Worlds.inventory)
func search_ruins(site: Dictionary) -> String:
	var w: Node = get_tree().root.get_node_or_null("Worlds") if is_inside_tree() else null
	var bag: Dictionary = w.inventory if w != null else {}
	var a: Actor = hero["actor"]
	var found: Dictionary = Ruins.search(site, ruins_looted, game.clock.total_seconds, a.derived()["search_efficiency"], _rng, bag)
	if found.is_empty():
		return I18n.t("Руины уже обысканы: загляните через несколько дней")
	a.add_xp("survival", 1.0)
	var parts: PackedStringArray = []
	for id in found:
		parts.append("%s ×%d" % [Trade.item_name(id), int(found[id])])
	var msg: String = I18n.t("Обыскал руины: %s") % ", ".join(parts)
	if w != null:
		var n: Dictionary = Codex.find(w.codex, "ruins", _rng, game.clock.total_seconds)
		if not n.is_empty():
			msg += I18n.t(". Среди обломков записка: «%s» (дневник героя, вкладка 6)") % n["title"]
	return msg


## Пошук у полі (пункт 16): час іде, знахідки в сумку; шум пошуку може привернути ворогів (Worlds.noise_check)
func search_field() -> String:
	var a: Actor = hero["actor"]
	var now: float = game.clock.total_seconds
	var r: Dictionary = Foraging.search(a, game.biome_at(hero["pos"]), hero["pos"], now, field_searched, _inventory(), _rng)
	if not bool(r["ok"]):
		return String(r["text"])
	game.clock._set_total(now + float(r["minutes"]) * 60.0)
	var wm: Node = get_node_or_null("/root/Worlds")
	if wm != null and wm.has_method("noise_check"):
		wm.noise_check(float(r["minutes"]) / 60.0)
	return String(r["text"])


func _hero_alive() -> bool:
	return not hero.is_empty() and hero["actor"].alive


func _water_near(p: Vector2) -> bool:
	if game.water_at(p) >= 0.5:
		return true
	for k in 8:
		if game.water_at(p + Vector2.from_angle(TAU * k / 8.0) * DRINK_REACH_M) >= 0.5:
			return true
	return false


## Поиск еды: шанс от поиска (Чутьё, травмы рук, Выживание) и биома [Q19: проверяет tests/balance_checks.gd].
## Одно и то же для героя и НПС
func forage(b: Dictionary) -> bool:
	var a: Actor = b["actor"]
	var biome: int = game.biome_at(b["pos"])
	var base: float = {3: 0.45, 5: 0.3, 2: 0.35, 4: 0.15, 6: 0.15, 7: 0.35, 8: 0.1, 9: 0.25}.get(biome, 0.0)
	a.add_xp("survival", 1.0)
	if _rng.randf() < base * a.derived()["search_efficiency"]:
		# У заражених біомах їжа брудна
		a.eat(15.0, "spoiled" if biome >= 7 and _rng.randf() < 0.5 else "cooked")
		return true
	return false


func _nearest_water(p: Vector2) -> Vector2:
	var r: float = 50.0
	while r <= WATER_SEARCH_M:
		for k in 16:
			var q: Vector2 = p + Vector2.from_angle(TAU * k / 16.0) * r
			if game.water_at(q) >= 0.5:
				return q
		r += 50.0
	return Vector2.INF


# =====================================================================
# НПС: розпорядок на тих самих діях, що й у героя
# =====================================================================
func _npc_think(b: Dictionary, env: Dictionary, delta: float) -> void:
	var a: Actor = b["actor"]
	var hour: float = float(env.get("hour", 12.0))
	var night: bool = bool(env.get("night", false))
	b["heal_cd"] = maxf(float(b["heal_cd"]) - delta, 0.0)
	_restock(b)
	if a.sleeping:
		if a.res["energy"] >= 95.0 or (not night and a.res["energy"] > 60.0):
			a.set_sleep(false)
		else:
			a.exert(delta, env, "rest")
			return
	# Рішення
	if a.res["energy"] < 25.0 or (night and a.res["energy"] < 60.0 and hour > 21.0):
		if not a.is_swimming(env):
			a.set_sleep(true)
			b["plan"] = "sleep"
			return
	if a.res["thirst"] < 40.0 and b["plan"] != "drink":
		var w: Vector2 = _nearest_water(b["pos"])
		if w != Vector2.INF:
			b["plan"] = "drink"
			b["target"] = w
	elif not a.conditions.is_empty() and b["heal_cd"] <= 0.0 and b["plan"] in ["idle", "walk"]:
		if not kit_items(b["kit"]).is_empty():
			# Лікар лікує себе сам
			heal_at(b, b)
			b["heal_cd"] = HEAL_RETRY_S
		elif not _nearest_healer(b).is_empty():
			b["plan"] = "heal"
	elif a.res["hunger"] < 40.0 and (b["plan"] == "idle" or (b["plan"] == "heal" and a.res["hunger"] < 20.0)):
		b["plan"] = "forage"
		b["wait"] = 4.0
	if b["plan"] == "idle":
		b["wait"] -= delta
		if b["wait"] <= 0.0:
			b["plan"] = "walk"
			# Блукають чистою землею: у заражені місця самі не йдуть
			b["target"] = _find_land(b["home"] + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0.0, NPC_RADIUS_M), 500.0, true)
	match b["plan"]:
		"walk":
			if _go(b, delta):
				b["plan"] = "idle"
				b["wait"] = _rng.randf_range(2.0, 8.0)
		"drink":
			if _water_near(b["pos"]):
				a.drink(40.0, "raw")
				b["plan"] = "idle"
				b["wait"] = 2.0
			elif _go(b, delta):
				b["plan"] = "idle"
				b["wait"] = 2.0
		"heal":
			var h: Dictionary = _nearest_healer(b)
			if h.is_empty():
				b["plan"] = "idle"
			elif h["pos"].distance_to(b["pos"]) <= HEAL_REACH_M:
				heal_at(b, h)
				b["heal_cd"] = HEAL_RETRY_S
				b["plan"] = "idle"
				b["wait"] = 2.0
			else:
				b["target"] = h["pos"]
				if _go(b, delta):
					# Не пройти (вода на шляху): спробує пізніше
					b["heal_cd"] = HEAL_RETRY_S
					b["plan"] = "idle"
		"forage":
			a.exert(delta, env, "rest")
			b["wait"] -= delta
			if b["wait"] <= 0.0:
				forage(b)
				b["plan"] = "idle"
				b["wait"] = 1.0
		_:
			a.exert(delta, env, "rest")


# Іде до цілі; true — дійшов (або застряг)
func _go(b: Dictionary, delta: float) -> bool:
	var to: Vector2 = b["target"] - b["pos"]
	if to.length() < 8.0:
		return true
	return not _step(b, to, false, delta)


# =====================================================================
# МАЛЮВАННЯ Й ІНТЕРФЕЙС
# =====================================================================
func _draw() -> void:
	if game == null:
		return
	var font: Font = ThemeDB.fallback_font
	var vp: Rect2 = get_viewport_rect().grow(40.0)
	_draw_ruins(font)
	_draw_tower_hint(font)
	for b in bodies:
		var a: Actor = b["actor"]
		var sp: Vector2 = game.world_to_screen(b["pos"])
		if not vp.has_point(sp):
			continue
		var col: Color = Color(1.0, 0.82, 0.3) if b["hero"] else Color(0.55, 0.8, 1.0)
		if not a.alive:
			col = Color(0.5, 0.5, 0.5)
		var r: float = clampf(0.6 * game.zoom, 4.0, 14.0)
		# На горі фігура ближче до ока: трохи більша, тінь іде далі від ніг
		var up: float = game.height_at(b["pos"]) / game.HEIGHT_MAX_M if game.has_method("height_at") else 0.0
		draw_circle(sp, r + 1.5, Color(0, 0, 0, 0.8))
		if game.zoom > 3.0 and not DOTS_ONLY:
			var hpx: float = clampf(1.9 * game.zoom, 16.0, 76.0) * (1.0 + up * 0.35)
			if up > 0.02:
				draw_set_transform(sp + Vector2(hpx * 0.12, hpx * 0.06) * (1.0 + up * 2.0), 0.0, Vector2(1.0, 0.35))
				draw_circle(Vector2.ZERO, hpx * 0.28, Color(0, 0, 0, 0.28))
				draw_set_transform(Vector2.ZERO)
			var lift: float = transport.rider_lift(hpx) if b["hero"] and transport != null else 0.0
			Art.sprite(self, "traveler" if b["hero"] else "villager", sp - Vector2(0, hpx * 0.08 * up + lift), hpx)
		else:
			draw_circle(sp, r, col)
		if not a.alive:
			draw_line(sp + Vector2(-r, -r), sp + Vector2(r, r), Color.BLACK, 2.0)
			draw_line(sp + Vector2(-r, r), sp + Vector2(r, -r), Color.BLACK, 2.0)
		if b["hero"] or game.zoom > 0.15:
			var label: String = a.display_name
			if a.sleeping:
				label += I18n.t(" (спит)")
			elif b["drowning"]:
				label += I18n.t(" (тонет!)")
			# Ширина за самим підписом: «(спить)», «(тоне!)» більше не обрізаються (Huzzah 2026-10-29)
			var lw: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 8.0
			draw_string_outline(font, sp + Vector2(-lw * 0.5, -r - 6), label, HORIZONTAL_ALIGNMENT_CENTER, lw, 13, 4, Color(0, 0, 0, 0.9))
			draw_string(font, sp + Vector2(-lw * 0.5, -r - 6), label, HORIZONTAL_ALIGNMENT_CENTER, lw, 13, col)
			# Смужка здоров'я
			var w: float = 26.0
			var hp: float = a.res["health"] / a.max_of("health")
			draw_rect(Rect2(sp + Vector2(-w / 2, r + 4), Vector2(w, 4)), Color(0, 0, 0, 0.8))
			draw_rect(Rect2(sp + Vector2(-w / 2, r + 4), Vector2(w * hp, 4)), Color(0.85, 0.2, 0.2) if hp < 0.3 else Color(0.4, 0.85, 0.35))


## Руїни на карті — руїни машин (Q31 B): кістяк крокуючої машини або купол бункера (за клітинкою руїн) і каміння;
## зблизька — підпис (обшукані — сірі)
func _draw_ruins(font: Font) -> void:
	if game.zoom < 0.25:
		return
	var vs: Vector2 = get_viewport_rect().size / game.zoom
	var now: float = game.clock.total_seconds
	for s in Ruins.in_rect(game, Rect2(game.cam_pos - vs * 0.5, vs).grow(40.0)):
		var sp: Vector2 = game.world_to_screen(s["pos"])
		var h: float = clampf(9.0 * game.zoom, 8.0, 260.0)
		var done: bool = Ruins.looted_now(ruins_looted, s["key"], now)
		var tint: Color = Color(0.62, 0.6, 0.56) if done else Color(0.92, 0.86, 0.78)
		var key: String = "tech_dome" if Art.seed_at(absi(hash(s["key"])) % 9973, 7, 31) > 0.6 else "tech_wreck"
		Art.sprite(self, key, sp + Vector2(-h * 0.1, 0.0), h * 0.8, tint)
		Art.sprite(self, "rock", sp + Vector2(h * 0.62, h * 0.12), h * 0.3, tint)
		if game.zoom >= 0.6:
			var label: String = I18n.t("Руины") + (I18n.t(" (обысканы)") if done else "")
			draw_string_outline(font, sp + Vector2(-60, -h * 0.85), label, HORIZONTAL_ALIGNMENT_CENTER, 120, 13, 4, Color(0, 0, 0, 0.9))
			draw_string(font, sp + Vector2(-60, -h * 0.85), label, HORIZONTAL_ALIGNMENT_CENTER, 120, 13, Color(0.95, 0.88, 0.7))


## Підказка біля героя під сигнальною вежею: F — залізти
func _draw_tower_hint(font: Font) -> void:
	if not _hero_alive() or hero_away or tower_near(hero["pos"]) == Vector2.INF:
		return
	var t: String = I18n.t("F — залезть на вышку")
	var hp: Vector2 = game.world_to_screen(hero["pos"]) + Vector2(0, 34)
	var tw: float = font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	draw_string_outline(font, hp - Vector2(tw * 0.5, 0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, 0.9))
	draw_string(font, hp - Vector2(tw * 0.5, 0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.9, 0.55))


func _update_status() -> void:
	var vp: Vector2 = get_viewport_rect().size
	if hero.is_empty():
		_status.text = I18n.t("G — создать героя")
	else:
		var a: Actor = hero["actor"]
		var env: Dictionary = WorldEnv.sample(game, hero["pos"])
		if not a.alive:
			_status.text = I18n.t("Герой погиб: %s") % Actor.DEATH_CAUSES.get(a.death_cause, a.death_cause)
		else:
			var alt: float = game.height_at(hero["pos"]) if game.has_method("height_at") else 0.0
			_status.text = I18n.t("Здоровье %d  Сытость %d  Вода %d  Энергия %d  Силы %d  Воздействие проклятья %d   %s%s, ощущается %d °C, шаг %.1f км/ч%s") % [
				int(a.res["health"]), int(a.res["hunger"]), int(a.res["thirst"]), int(a.res["energy"]),
				int(a.res["stamina"]), int(a.res["radiation"]), game.biome_name(hero["pos"]),
				I18n.t(", высота %d м") % int(round(alt / 10.0) * 10.0) if alt >= 20.0 else "",
				int(round(a.feels_temp(env))), a.calculate_speed(env),
				"" if controls_hero else I18n.t("   (камера свободна, G — к герою)")]
	_status.position = Vector2(14.0, vp.y - 34.0)
	sheet_visible = window.visible or _creator != null


## Аркуш персонажа: годиться для героя й для будь-якого НПС
func sheet_text(a: Actor) -> String:
	var t: String = "%s%s\n\n" % [a.display_name, I18n.t(" (НПС)") if a.is_npc else ""]
	var ch: Dictionary = R.characteristics()
	# «Стойкость» — и характеристика 09, и ресурс пака: ресурс здесь зовётся «Запас сил»;
	# голод и жажда пака — шкалы сытости и воды (100 — сыт и напоен)
	var shown: Dictionary = {"hunger": I18n.t("Сытость"), "thirst": I18n.t("Вода"), "stamina": I18n.t("Запас сил")}
	for r in Actor.RESOURCES:
		t += "%s: %d / %d\n" % [shown.get(r, ch.get(r, {}).get("name_ru", r)), int(a.res[r]), int(a.max_of(r))]
	var names: Dictionary = R.section("stats").get("names", {})
	t += "\n"
	for s in Actor.STATS:
		t += "%s %d   " % [names.get(s, s), int(a.stat(s))]
	t += I18n.t("\n\nСостояния:")
	if a.conditions.is_empty() and a.buffs.is_empty():
		t += I18n.t(" нет")
	for c in a.conditions:
		var d: Dictionary = R.condition(c["id"])
		t += "\n  %s%s" % [d.get("name_ru", c["id"]), "" if c["id"] != "radiation_sickness" else I18n.t(" (стадия %d)") % int(c["stage"])]
	for bf in a.buffs:
		t += I18n.t("\n  + %s (%.0f ч)") % [R.buffs().get(bf["id"], {}).get("name_ru", bf["id"]), float(bf["left_h"])]
	var dv: Dictionary = a.derived()
	t += I18n.t("\n\nСила удара ×%.2f   Поиск ×%.2f   Скорость ×%.2f\nПереносимый вес %.0f кг   Защита от проклятья %d %%\n") % [
		dv["attack_power"], dv["search_efficiency"], dv["move_speed"], dv["carry_weight"], int(dv["radiation_resist"] * 100.0)]
	t += I18n.t("\nУровень %d, опыт %d / %d") % [a.level, int(a.xp), Sheet.xp_to_next(a)]
	t += I18n.t("\nНавыки:")
	var sk: Dictionary = R.skills()
	for k in sk:
		t += "\n  %s %d %%%s" % [sk[k].get("name_ru", k), a.skill(k), " ◆" if a.tags.has(k) else ""]
	t += I18n.t("\n\nПройдено %.1f км") % (a.distance_m / 1000.0)
	t += I18n.t("\n\nG управление, Shift бег, Z сон, E пить, F еда или обыскать руины, T лекарь, R верхом / пешком, I персонаж, Tab сумка")
	return t


# =====================================================================
# ЗБЕРЕЖЕННЯ
# =====================================================================
func to_dict() -> Dictionary:
	var list: Array = []
	for b in bodies:
		list.append({"actor": b["actor"].to_dict(), "pos": b["pos"], "home": b["home"], "hero": b["hero"], "kit": b["kit"], "restock_at": b["restock_at"]})
	Foraging.prune(field_searched, game.clock.total_seconds if game != null and game.clock != null else 0.0)
	return {"bodies": list, "controls_hero": controls_hero, "ruins_looted": ruins_looted.duplicate(), "field_searched": field_searched.duplicate()}


func load_dict(d: Dictionary) -> void:
	bodies.clear()
	hero = {}
	for e in d.get("bodies", []):
		# У збереженнях 2D 06 у героя було 8 НПС довкола: поки НПС поза містом немає, вони не вантажаться
		if not OVERWORLD_NPCS and not bool(e.get("hero", false)):
			continue
		var b: Dictionary = _add(Actor.from_dict(e["actor"]), e["pos"], bool(e.get("hero", false)))
		b["home"] = e.get("home", e["pos"])
		b["kit"] = as_kit(e.get("kit", {}))
		b["restock_at"] = float(e.get("restock_at", 0.0))
		if b["hero"]:
			hero = b
	controls_hero = bool(d.get("controls_hero", false)) and not hero.is_empty()
	ruins_looted = d.get("ruins_looted", {}).duplicate()
	field_searched = d.get("field_searched", {}).duplicate()
	_last_clock = -1.0
	if route != null:
		route.cancel()

extends Node2D
const Art := preload("res://storybook/art.gd")
const Growth := preload("res://city/city_growth.gd")
## Города и поселения на общей карте. Реестр — data/world/settlements.json (tools/make_settlements.py,
## можно править руками). Сейчас по решению Huzzah город один на весь мир, герой появляется у его ворот.
##
## Вид: издали — щиток-эмблема города с подписью (точка интереса, мало места); при сильном приближении
## (клетка поселения от OUTLINE_CELL_PX пикселей) — очерк территории: стена с башнями, ворота,
## улицы и кварталы внутри. Готовой дороги к воротам нет (Huzzah 2026-10-28): дороги протаптываются
## героем и НПС (world/trails.gd, world/trails_layer.gd). Клетка поселения — квадрат cell_m метров доски, число клеток по размеру.
##
## Подход героя:
##   к воротам (ближе GATE_R_M) — «Войти» (E) / «Продолжить путь» (Esc);
##   к стене (ближе APPROACH_M к клеткам, вне ворот) — «Попытаться проникнуть» (E) с шансом
##     sneak_chance(): Ловкость, Восприятие, Удача, ночь, груз, травмы рук и ног, здоровье и силы;
##     числа в блоке "sneak" реестра [ВРЕМЕННО]. Неудача: заметили (вход с entry "caught") или
##     стража настороже cooldown_h игровых часов; можно сорваться и травмироваться.
## Пока открыт выбор, герой стоит (cast.hold_hero). Закрыли выбор, а герой всё ещё у города — E открывает
## его снова (подсказка у героя). Новый герой у ворот сразу видит выбор. Вход — сигнал enter_requested(s), в копии s поля
## "entry" ("gate" | "sneak" | "caught") и "side" (сторона стены); мир города грузит worlds/worlds.gd.
## Выход из города: герой ставится в exit_point(id) — у ворот, вне клеток.
##
## Радиальные поселения (Huzzah 2026-10-23: города как в средневековье — радиальные): в реестре "radius" —
## город круглый, стена — окружность radius метров вокруг center; клетки остаются реестром места
## (круг лежит внутри них). На карте вместо щитка — миниатюра самого города: тот же план из
## data/cities/<city_id>.json (стена, башни, улицы, площадь, дома, деревья), повёрнутый воротами к "gate".

signal enter_requested(s: Dictionary)

const DATA_FILE := "res://data/world/settlements.json"
const APPROACH_M: float = 60.0      # стена: от края клеток поселения
const GATE_R_M: float = 60.0        # ворота: от точки ворот
const LEAVE_M: float = 150.0        # снова спросит, когда герой отойдёт от места ответа дальше этого
const JUMP_M: float = 200.0         # скачок героя за кадр (загрузка, возврат из города) — не подход
const OUTLINE_CELL_PX: float = 28.0 # с такой клетки на экране вместо щитка — очерк города
const SIZE_ORDER: Array = ["hamlet", "village", "town", "city", "capital"]
const BLOCKS: Dictionary = {"hamlet": 2, "village": 3, "town": 4, "city": 5, "capital": 6}   # кварталов в ряд на клетку
const MEDAL_MIN_PX: float = 30.0    # радиус медальона издали не меньше этого (город остаётся точкой интереса)
const MEDALLION_DIR := "res://art/medallion/"
const MEDALLIONS: Array = ["m0_camp", "m1_ostrog", "m2_sloboda", "m3_posad", "m4_gorod", "m5_bolshoy_gorod"]
const SIZE_LEVEL: Dictionary = {"hamlet": 0, "village": 2, "town": 3, "city": 4, "capital": 5}
var _medallions: Dictionary = {}
const CITY_DIR := "res://data/cities/"

var game: Node2D
var cell_m: float = 250.0
var sizes: Dictionary = {}
var sneak_rules: Dictionary = {}
var list: Array = []                # поселения + служебные поля (_cells, _own, _rect, _center, _gate, _gate_wall)
var by_id: Dictionary = {}
var by_cell: Dictionary = {}        # Vector2i -> поселение
var dismissed: Dictionary = {}      # "id:gate" / "id:wall" -> место, где игрок ответил «Продолжить путь»
var alert_until: Dictionary = {}    # id -> игровые секунды: стража настороже после неудачной попытки
var prompt_for: Dictionary = {}     # поселение, о котором сейчас спрашивают
var prompt_kind: String = ""        # "gate" | "wall"
var prompt_side: String = ""
var _last_hero: Vector2 = Vector2.INF
var _rng := RandomNumberGenerator.new()
var _ui: CanvasLayer
var _panel: PanelContainer
var _title: Label
var _info: Label
var _act_btn: Button
# Панель места, как в Day R (видео Huzzah 2026-10-23): картинка поселения, «Искать», «Набрать воды»
var _pic: TextureRect
var _result: Label
var _search_btn: Button
var _water_btn: Button
var searched_until: Dictionary = {}  # id -> игровые секунды, до которых окрестности уже обысканы
const SEARCH_MIN: float = 40.0       # обыск окрестностей, игровых минут
const WATER_MIN: float = 10.0
const SEARCH_LOOT: Dictionary = {    # id -> [от, до, шанс] [ВРЕМЕННО]
	"scrap": [1, 3, 0.6], "charcoal": [1, 2, 0.35], "rope": [1, 1, 0.15], "hide": [1, 1, 0.15],
	"old_coin": [1, 2, 0.2], "money": [1, 4, 0.3],
}


func setup(g: Node2D) -> void:
	game = g
	_rng.randomize()
	_load()
	_build_ui()
	# Новая игра: камера над городом, где появится герой (сохранение потом ставит свою камеру)
	var sp: Vector2 = spawn_point()
	if sp != Vector2.INF and game._save_data.is_empty():
		game.cam_pos = sp


## Место появления героя: у ворот первого поселения реестра (решение Huzzah: один город на весь мир)
func spawn_point() -> Vector2:
	if list.is_empty():
		return Vector2.INF
	return exit_point(String(list[0]["id"]))


func _load() -> void:
	if not FileAccess.file_exists(DATA_FILE):
		game.missing_files.append(DATA_FILE)
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_FILE))
	if not (d is Dictionary):
		push_warning("settlements.json не читается")
		return
	cell_m = float(d.get("cell_m", 250.0))
	sizes = d.get("sizes", {})
	sneak_rules = d.get("sneak", {})
	for s in d.get("settlements", []):
		var cells: Array = []
		var own := {}
		var rect := Rect2()
		for c in s.get("cells", []):
			var k := Vector2i(int(c[0]), int(c[1]))
			cells.append(k)
			own[k] = true
			var r := Rect2(Vector2(k) * cell_m, Vector2(cell_m, cell_m))
			rect = r if rect.size == Vector2.ZERO else rect.merge(r)
			by_cell[k] = s
		if cells.is_empty():
			continue
		s["_cells"] = cells
		s["_own"] = own
		s["_center"] = Vector2(s["center"][0], s["center"][1]) if s.has("center") else rect.get_center()
		s["_radius"] = float(s.get("radius", 0.0))
		if s["_radius"] > 0.0:
			rect = Rect2(s["_center"] - Vector2.ONE * s["_radius"], Vector2.ONE * s["_radius"] * 2.0)
			s["_plan"] = _load_plan(s)
		s["_rect"] = rect
		s["_gate"] = Vector2(s["gate"][0], s["gate"][1]) if s.has("gate") else rect.get_center() + Vector2(0.0, rect.size.y * 0.5 + 40.0)
		if not s.has("walled"):
			s["walled"] = SIZE_ORDER.find(s.get("size", "")) >= 2
		list.append(s)
		by_id[String(s["id"])] = s
		s["_gate_wall"] = nearest_on_cells(s, s["_gate"])


# План города для миниатюры: data/cities/<city_id>.json, иначе <template>.json; только радиальный
func _load_plan(s: Dictionary) -> Dictionary:
	for key in [String(s.get("city_id", "")), String(s.get("template", ""))]:
		var path: String = CITY_DIR + key + ".json"
		if key == "" or not FileAccess.file_exists(path):
			continue
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if d is Dictionary and String(d.get("plan", "")) == "radial":
			return d
	return {}


## План на нынешнем этапе роста города (city/city_growth.gd): этап — по состоянию города в Worlds.city_states
func _plan_now(s: Dictionary) -> Dictionary:
	var d: Dictionary = s["_plan"]
	if not Growth.has_growth(d):
		return d
	var k: int = Growth.stage(d, _growth_of(s))
	if int(s.get("_plan_stage", -1)) != k:
		s["_plan_stage"] = k
		s["_plan_view"] = Growth.view(d, k)
	return s["_plan_view"]


## Состояние роста города из Worlds.city_states (новая игра — начальное)
func _growth_of(s: Dictionary) -> Dictionary:
	var w: Node = get_node_or_null("/root/Worlds")
	var states: Variant = w.get("city_states") if w != null else null
	if states is Dictionary:
		var st: Variant = states.get(String(s.get("city_id", s.get("id", ""))), {})
		if st is Dictionary and st.get("growth") is Dictionary:
			return st["growth"]
	return Growth.new_state()


## Этап роста ближайшего растущего города в радиусе radius_m от точки; -1 — такого нет (Q30)
func growth_stage_near(p: Vector2, radius_m: float) -> int:
	var best: int = -1
	var best_d: float = INF
	for s in list:
		var plan: Dictionary = s.get("_plan", {})
		if not Growth.has_growth(plan):
			continue
		var d: float = p.distance_to(s["_center"])
		if d <= radius_m and d < best_d:
			best_d = d
			best = Growth.stage(plan, _growth_of(s))
	return best


func radial(s: Dictionary) -> bool:
	return float(s.get("_radius", 0.0)) > 0.0


# =====================================================================
# ЗАПРОСЫ ДЛЯ ДРУГИХ ВЕТОК
# =====================================================================
func get_settlement(id: String) -> Dictionary:
	return by_id.get(id, {})


## Поселение, на клетке которого лежит точка p (пусто — нет)
func settlement_at(p: Vector2) -> Dictionary:
	var s: Dictionary = by_cell.get(Vector2i(floori(p.x / cell_m), floori(p.y / cell_m)), {})
	if not s.is_empty() and radial(s) and p.distance_to(s["_center"]) > s["_radius"]:
		return {}
	return s


## Стена: клетки города со стеной на общей карте не проходятся (вход — через выбор у ворот или стены)
func blocks(p: Vector2) -> bool:
	var s: Dictionary = settlement_at(p)
	return not s.is_empty() and bool(s["walled"])


func size_name(s: Dictionary) -> String:
	return String(sizes.get(s.get("size", ""), {}).get("name", s.get("size", "")))


## Точка выхода из города на общую карту: ворота, если там суша; иначе ближайшая суша вне клеток
func exit_point(id: String) -> Vector2:
	var s: Dictionary = get_settlement(id)
	if s.is_empty():
		return Vector2.INF
	var g: Vector2 = s["_gate"]
	if _free_land(g):
		return g
	var out_dir: Vector2 = (g - s["_center"]).normalized()
	if out_dir == Vector2.ZERO:
		out_dir = Vector2.DOWN
	var r: float = 40.0
	while r <= 2000.0:
		for k in 24:
			var q: Vector2 = g + Vector2.from_angle(out_dir.angle() + TAU * k / 24.0) * r
			if _free_land(q):
				return q
		r += 40.0
	return g


func _free_land(p: Vector2) -> bool:
	var b: int = game.biome_at(p)
	return b != 0 and b != 1 and settlement_at(p).is_empty()


## Ближайшая к p точка клеток поселения (p на клетке — сама p)
func nearest_on_cells(s: Dictionary, p: Vector2) -> Vector2:
	if radial(s):
		var v: Vector2 = p - s["_center"]
		return p if v.length() <= s["_radius"] else s["_center"] + v.normalized() * s["_radius"]
	var best: Vector2 = p
	var best_d: float = INF
	for k in s["_cells"]:
		var r := Rect2(Vector2(k) * cell_m, Vector2(cell_m, cell_m))
		var q := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
		var d: float = p.distance_to(q)
		if d < best_d:
			best_d = d
			best = q
	return best


# Расстояние от точки до клеток поселения (0 — на клетке)
func distance_to(s: Dictionary, p: Vector2) -> float:
	if not s["_rect"].grow(APPROACH_M + LEAVE_M + 10.0).has_point(p):
		return INF
	return p.distance_to(nearest_on_cells(s, p))


## Сторона стены, у которой стоит точка: "north" | "east" | "south" | "west"
func side_of(s: Dictionary, p: Vector2) -> String:
	var v: Vector2 = p - nearest_on_cells(s, p)
	if v.length() < 1.0 or radial(s):
		v = p - s["_center"]
	if absf(v.x) > absf(v.y):
		return "east" if v.x > 0.0 else "west"
	return "south" if v.y > 0.0 else "north"


# Зона подхода героя: "gate", "wall" или "" (далеко)
func zone_of(s: Dictionary, p: Vector2) -> String:
	if p.distance_to(s["_gate"]) <= GATE_R_M:
		return "gate"
	if distance_to(s, p) <= APPROACH_M:
		return "wall" if s["walled"] else "gate"
	return ""


# =====================================================================
# ПРОНИКНОВЕНИЕ
# =====================================================================
func _rule(k: String, def: float) -> float:
	return float(sneak_rules.get(k, def))


## Шанс пролезть через стену для героя (или любого персонажа) в его среде; 0 — нельзя
func sneak_chance(a: Actor, env: Dictionary) -> float:
	if a.mount != "" or not a.can_move():
		return 0.0
	var c: float = _rule("base", 0.3)
	c += _rule("per_agi", 0.05) * (a.stat("agi") - 5.0)
	c += _rule("per_per", 0.02) * (a.stat("per") - 5.0)
	c += _rule("per_luck", 0.01) * (a.stat("luck") - 5.0)
	if bool(env.get("night", false)):
		c += _rule("night", 0.2)
	c -= _rule("per_kg_over", 0.01) * maxf(a.carried_kg - _rule("free_kg", 15.0), 0.0)
	c *= a.mult("sneak")   # черты «Тихий» / «Шумный» (data/characters/creation.json)
	for id in sneak_rules.get("hurt_conditions", ["luxation_arm", "broken_arm", "broken_leg", "blindness"]):
		if a.has_condition(id):
			c *= _rule("hurt_mult", 0.3)
			break
	if a.res["health"] < a.max_of("health") / 3.0 or a.res["stamina"] < a.max_of("stamina") / 3.0:
		c *= _rule("low_mult", 0.5)
	return clampf(c, _rule("min", 0.05), _rule("max", 0.9))


## Шанс, что при неудаче заметят
func caught_chance(a: Actor, env: Dictionary) -> float:
	var c: float = _rule("caught_night", 0.25) if bool(env.get("night", false)) else _rule("caught_day", 0.5)
	return clampf(c - _rule("per_agi_caught", 0.03) * (a.stat("agi") - 5.0), 0.05, 0.95)


func alert_left_s(s: Dictionary) -> float:
	return maxf(float(alert_until.get(s["id"], 0.0)) - game.clock.total_seconds, 0.0)


## Попытка проникнуть: "sneak" (пролез), "caught" (заметили), "fail" (не пролез), "" (нельзя)
func try_sneak(s: Dictionary, a: Actor, env: Dictionary) -> String:
	if alert_left_s(s) > 0.0:
		return ""
	var c: float = sneak_chance(a, env)
	if c <= 0.0:
		return ""
	a.add_res("stamina", -_rule("stamina_cost", 30.0))
	if _rng.randf() < c:
		return "sneak"
	if _rng.randf() < _rule("fall_chance", 0.1):
		a.add_condition(String(sneak_rules.get("fall_condition", "luxation_arm")))
	if _rng.randf() < caught_chance(a, env):
		return "caught"
	alert_until[s["id"]] = game.clock.total_seconds + _rule("cooldown_h", 1.0) * 3600.0
	return "fail"


# =====================================================================
# ПОДХОД ГЕРОЯ
# =====================================================================
func _hero() -> Dictionary:
	var c: Node = game.cast
	if c == null or c.hero.is_empty() or not c.hero["actor"].alive:
		return {}
	return c.hero


func _process(_delta: float) -> void:
	if game == null or not game.ready_done:
		return
	var h: Dictionary = _hero()
	if h.is_empty():
		_last_hero = Vector2.INF
		_close_prompt()
		queue_redraw()
		return
	var p: Vector2 = h["pos"]
	# Скачок (загрузка, новый герой, возврат из города): где оказался — там уже «ответил»
	# Новый герой (G) или загрузка — выбор показывается сразу: игрок появляется у ворот и может войти.
	# Скачок уже бывшего героя (перенос) — там, где оказался, уже «ответил»
	var jumped: bool = _last_hero != Vector2.INF and p.distance_to(_last_hero) > JUMP_M
	_last_hero = p
	for key in dismissed.keys():
		if p.distance_to(dismissed[key]) > LEAVE_M:
			dismissed.erase(key)
	var controls: bool = game.cast.controls_hero
	for s in list:
		var z: String = zone_of(s, p)
		if z != "" and (jumped or not controls):
			dismissed[s["id"] + ":" + z] = p
	if prompt_for.is_empty() and controls and not game.menu_open:
		for s in list:
			var z: String = zone_of(s, p)
			if z != "" and not dismissed.has(s["id"] + ":" + z):
				_open_prompt(s, z, side_of(s, p))
				break
	if not prompt_for.is_empty():
		if zone_of(prompt_for, p) != prompt_kind or not controls:
			dismissed[prompt_for["id"] + ":" + prompt_kind] = p
			_close_prompt()
		elif prompt_kind == "wall":
			_refresh_wall_info(h)
	queue_redraw()


func _open_prompt(s: Dictionary, kind: String, side: String) -> void:
	prompt_for = s
	prompt_kind = kind
	prompt_side = side
	game.cast.hold_hero = true
	var sn: String = size_name(s)
	_title.text = "%s%s %s" % [sn.left(1).to_upper(), sn.substr(1), s["name"]]
	_pic.texture = medallion_texture(dev_level(s))
	_result.text = ""
	_result.visible = false
	_water_btn.visible = kind == "gate"
	_refresh_search()
	if kind == "gate":
		var place: String = game.province_name(int(s.get("province", 0)))
		_info.text = "Ворота. Дорога ведёт внутрь%s" % (("   ·   " + place) if place != "" else "")
		_act_btn.text = "Войти  [E]"
		_act_btn.disabled = false
	else:
		_refresh_wall_info(_hero())
	_panel.visible = true
	_layout()


const SIDE_NAMES: Dictionary = {"north": "северной", "east": "восточной", "south": "южной", "west": "западной"}


func _refresh_wall_info(h: Dictionary) -> void:
	if h.is_empty():
		return
	var left: float = alert_left_s(prompt_for)
	var a: Actor = h["actor"]
	var env: Dictionary = WorldEnvRef.sample(game, h["pos"])
	var c: float = sneak_chance(a, env)
	var t: String = "У %s стены, ворота далеко. " % SIDE_NAMES.get(prompt_side, "")
	if left > 0.0:
		t += "Стража настороже: ещё %d мин" % int(ceil(left / 60.0))
	elif c <= 0.0:
		t += "Так не перелезть (верхом или не может идти)"
	else:
		t += "Шанс %d %%%s" % [int(round(c * 100.0)), ", ночь помогает" if bool(env.get("night", false)) else ""]
	_info.text = t
	_act_btn.text = "Попытаться проникнуть  [E]"
	_act_btn.disabled = left > 0.0 or c <= 0.0
	_layout()


func _close_prompt() -> void:
	prompt_for = {}
	prompt_kind = ""
	if game.cast != null:
		game.cast.hold_hero = false
	if _panel != null:
		_panel.visible = false


## Главная кнопка: «Войти» у ворот, «Попытаться проникнуть» у стены
func choose_act() -> void:
	if prompt_for.is_empty() or _act_btn.disabled:
		return
	var s: Dictionary = prompt_for
	var kind: String = prompt_kind
	var side: String = prompt_side
	var h: Dictionary = _hero()
	var entry: String = "gate"
	if kind == "wall":
		entry = try_sneak(s, h["actor"], WorldEnvRef.sample(game, h["pos"]))
		if entry == "":
			return
	dismissed[s["id"] + ":" + kind] = h["pos"]
	_close_prompt()
	match entry:
		"fail":
			_event("Не удалось перелезть стену %s. Стража настороже" % s["name"])
			return
		"sneak":
			_event("Пробрался в %s через стену" % s["name"])
		"caught":
			_event("Стража заметила у стены %s" % s["name"])
	if enter_requested.get_connections().is_empty():
		_event("%s: мир города ещё не подключён" % s["name"])
		return
	# Вернётся из города к воротам: там выбор сам не всплывает (E — открыть)
	dismissed[s["id"] + ":gate"] = s["_gate"]
	var e: Dictionary = s.duplicate()
	e["entry"] = entry
	e["side"] = side if kind == "wall" else side_of(s, s["_gate"])
	enter_requested.emit(e)


## Герой стоит у города (у ворот или у стены), а выбор закрыт: открыть его снова. true — открыт
func reopen_here() -> bool:
	var h: Dictionary = _hero()
	if h.is_empty() or not game.cast.controls_hero or game.cast.get("hero_away") == true:
		return false
	for s in list:
		var z: String = zone_of(s, h["pos"])
		if z != "":
			dismissed.erase(s["id"] + ":" + z)
			_open_prompt(s, z, side_of(s, h["pos"]))
			return true
	return false


# Зона у города, где выбор сейчас закрыт (для подсказки «E»): {s, kind} или пусто
func _quiet_zone() -> Dictionary:
	var h: Dictionary = _hero()
	if h.is_empty() or not prompt_for.is_empty() or not game.cast.controls_hero:
		return {}
	for s in list:
		var z: String = zone_of(s, h["pos"])
		if z != "":
			return {"s": s, "kind": z, "pos": h["pos"]}
	return {}


## «Продолжить путь»
func choose_continue() -> void:
	if prompt_for.is_empty():
		return
	var h: Dictionary = _hero()
	dismissed[prompt_for["id"] + ":" + prompt_kind] = h["pos"] if not h.is_empty() else prompt_for["_gate"]
	_close_prompt()


## «Искать»: обыскать окрестности поселения (лом, уголь, монеты); время идёт, раз в сутки на место
func choose_search() -> void:
	if prompt_for.is_empty() or _search_btn.disabled:
		return
	var h: Dictionary = _hero()
	if h.is_empty():
		return
	var a: Actor = h["actor"]
	var id: String = String(prompt_for["id"])
	_pass_minutes(SEARCH_MIN)
	searched_until[id] = game.clock.total_seconds + 86400.0
	var bag: Dictionary = _bag()
	var eff: float = float(a.derived()["search_efficiency"])
	var found: Array = []
	for item in SEARCH_LOOT:
		var l: Array = SEARCH_LOOT[item]
		if _rng.randf() >= float(l[2]) * eff:
			continue
		var k: int = _rng.randi_range(int(l[0]), int(l[1]))
		if item == "money":
			bag["money"] = int(bag.get("money", 0)) + k
			found.append("%d монет" % k)
		else:
			TradeRef.add(bag, item, k)
			found.append("%s ×%d" % [TradeRef.item_name(item), k])
	a.add_xp("survival", 2.0)
	_show_result("Обыскал окрестности (%d мин): %s" % [int(SEARCH_MIN), "ничего" if found.is_empty() else ", ".join(PackedStringArray(found))])
	_refresh_search()


## «Набрать воды» у колодца перед воротами: напиться вдоволь и наполнить флягу (не больше двух в сумке)
func choose_water() -> void:
	if prompt_for.is_empty() or prompt_kind != "gate":
		return
	var h: Dictionary = _hero()
	if h.is_empty():
		return
	var a: Actor = h["actor"]
	_pass_minutes(WATER_MIN)
	a.drink(100.0, "clean")
	var bag: Dictionary = _bag()
	var t: String = "Напился у колодца"
	if TradeRef.count(bag, "water_flask") < 2:
		TradeRef.add(bag, "water_flask", 1)
		t += " и наполнил флягу"
	_show_result(t)


func _refresh_search() -> void:
	var left: float = float(searched_until.get(String(prompt_for.get("id", "")), -1.0)) - game.clock.total_seconds
	_search_btn.disabled = left > 0.0
	_search_btn.text = "Искать  [F]" if left <= 0.0 else "Обыскано (ещё %d ч)" % int(ceil(left / 3600.0))


func _show_result(t: String) -> void:
	_result.text = t
	_result.visible = true
	_event(t)
	_layout()


func _pass_minutes(m: float) -> void:
	game.clock._set_total(game.clock.total_seconds + m * 60.0)


func _bag() -> Dictionary:
	var w: Node = get_node_or_null("/root/Worlds")
	if w != null and w.get("inventory") is Dictionary:
		return w.inventory
	var a: Actor = _hero().get("actor")
	if a != null and a.has_meta("inventory"):
		return a.get_meta("inventory")
	return {"money": 0, "items": {}}


func _event(text: String) -> void:
	game.event_text = text
	game.event_timer = 5.0


# Пока открыт выбор, клавиши идут сюда раньше карты и героя
func _input(event: InputEvent) -> void:
	if game == null or not game.ready_done or game.typing or game.menu_open:
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if prompt_for.is_empty():
		# У города после «Продолжить путь» или возврата: E снова открывает выбор
		if event.physical_keycode in [KEY_E, KEY_ENTER, KEY_KP_ENTER] and reopen_here():
			get_viewport().set_input_as_handled()
		return
	match event.physical_keycode:
		KEY_E, KEY_ENTER, KEY_KP_ENTER:
			choose_act()
		KEY_F:
			choose_search()
		KEY_R:
			if _water_btn.visible:
				choose_water()
		KEY_ESCAPE, KEY_Q, KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT:
			choose_continue()
		_:
			return
	get_viewport().set_input_as_handled()


const WorldEnvRef := preload("res://characters/world_env.gd")
const TradeRef := preload("res://city/trade.gd")


# =====================================================================
# ИНТЕРФЕЙС ВЫБОРА
# =====================================================================
func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 11
	add_child(_ui)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", preload("res://ui/comic_ui.gd").panel(22.0, 0.96))   # рамка комикса (Q24)
	_panel.visible = false
	_ui.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)
	_pic = TextureRect.new()
	_pic.custom_minimum_size = Vector2(200, 200)
	_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_pic)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 20)
	_title.add_theme_color_override("font_color", Color("f0dca0"))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 14)
	_info.add_theme_color_override("font_color", Color("c8bfa0"))
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_info)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	_act_btn = _button(row, "Войти  [E]", choose_act)
	_button(row, "Продолжить путь  [Esc]", choose_continue)
	var row2 := HBoxContainer.new()
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	row2.add_theme_constant_override("separation", 12)
	box.add_child(row2)
	_search_btn = _button(row2, "Искать  [F]", choose_search)
	_water_btn = _button(row2, "Набрать воды  [R]", choose_water)
	_result = Label.new()
	_result.add_theme_font_size_override("font_size", 14)
	_result.add_theme_color_override("font_color", Color("e8d8a8"))
	_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result.custom_minimum_size = Vector2(460, 0)
	_result.visible = false
	box.add_child(_result)


func _button(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(230, 38)
	b.add_theme_font_size_override("font_size", 16)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _layout() -> void:
	_panel.reset_size()
	var vp: Vector2 = get_viewport_rect().size
	# Карточка места справа, как в Day R: герой и карта у ворот остаются на виду
	_panel.position = Vector2(vp.x - _panel.size.x - 24.0, maxf((vp.y - _panel.size.y) * 0.5, 12.0))


# =====================================================================
# РИСОВАНИЕ: щиток издали, очерк города вблизи
# =====================================================================
func _draw() -> void:
	if game == null or list.is_empty():
		return
	var vp: Rect2 = get_viewport_rect().grow(80.0)
	var z: float = game.zoom
	var cs: float = cell_m * z
	var font: Font = ThemeDB.fallback_font
	var mouse_s: Dictionary = settlement_at(game._mouse_world()) if game.pointer_over_map() else {}
	for s in list:
		var r: Rect2 = s["_rect"]
		var sr := Rect2(game.world_to_screen(r.position), r.size * z)
		var hl: bool = s == prompt_for or s == mouse_s
		if radial(s):
			var c0: Vector2 = game.world_to_screen(s["_center"])
			var rp: float = maxf(s["_radius"] * z, MEDAL_MIN_PX)
			if vp.grow(rp * 1.6).has_point(c0):
				_draw_medallion(s, c0, rp, hl)
				_draw_name(s, c0 + Vector2(0, rp + 18.0), font, hl, rp > 80.0)
		elif cs >= OUTLINE_CELL_PX:
			if vp.intersects(sr):
				_draw_outline(s, cs, z)
				_draw_name(s, Vector2(sr.get_center().x, sr.position.y - 14.0), font, hl, true)
		else:
			var c: Vector2 = game.world_to_screen(s["_center"])
			if vp.has_point(c):
				var rank: int = SIZE_ORDER.find(s["size"])
				var w: float = 24.0 + 3.0 * maxi(rank, 0)
				_draw_shield(c + Vector2(0, -w * 0.25), w, s.get("emblem", {}), hl)
				_draw_name(s, c + Vector2(0, w * 1.05), font, hl, false)
	# Подсказка у героя: выбор закрыт, E — открыть
	var qz: Dictionary = _quiet_zone()
	if not qz.is_empty():
		var t: String = "E — войти в %s" % qz["s"]["name"] if qz["kind"] == "gate" else "E — попытаться проникнуть"
		var hp: Vector2 = game.world_to_screen(qz["pos"]) + Vector2(0, 34)
		var tw: float = font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string_outline(font, hp - Vector2(tw * 0.5, 0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, 0.9))
		draw_string(font, hp - Vector2(tw * 0.5, 0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.9, 0.55))


# Щиток: поле, кайма, фигура эмблемы
func _draw_shield(c: Vector2, w: float, em: Dictionary, hl: bool) -> void:
	var h: float = w * 1.2
	var top: float = c.y - h * 0.5
	var pts := PackedVector2Array([Vector2(c.x - w * 0.5, top), Vector2(c.x + w * 0.5, top)])
	for i in 9:
		var t: float = float(i) / 8.0
		pts.append(Vector2(c.x + w * 0.5 * cos(t * PI * 0.5), top + h * 0.45 + h * 0.55 * sin(t * PI * 0.5)))
	for i in range(1, 9):
		var t: float = 1.0 - float(i) / 8.0
		pts.append(Vector2(c.x - w * 0.5 * cos(t * PI * 0.5), top + h * 0.45 + h * 0.55 * sin(t * PI * 0.5)))
	var sh := PackedVector2Array()
	for q in pts:
		sh.append(q + Vector2(2, 3))
	draw_colored_polygon(sh, Color(0, 0, 0, 0.45))
	var field := Color(String(em.get("field", "#26262c")))
	var tint := Color(String(em.get("tint", "#e2b84c")))
	draw_colored_polygon(pts, field)
	var loop := pts.duplicate()
	loop.append(pts[0])
	draw_polyline(loop, Color(1.0, 0.9, 0.55) if hl else tint, maxf(1.5, w * 0.07), true)
	draw_polyline(loop, Color(0, 0, 0, 0.8), 1.0, true)
	_draw_charge(Vector2(c.x, top + h * 0.47), w * 0.1, em, field, tint)


## Фигура герба (щиток и знамя): башня, корона, дерево, ключ; u — единица размера
func _draw_charge(m: Vector2, u: float, em: Dictionary, field: Color, tint: Color) -> void:
	match String(em.get("charge", "tower")):
		"crown":
			draw_rect(Rect2(m + Vector2(-3.0 * u, 0.5 * u), Vector2(6.0 * u, 1.6 * u)), tint)
			for k in 3:
				var x: float = m.x + (k - 1) * 2.4 * u
				draw_colored_polygon(PackedVector2Array([Vector2(x - 1.0 * u, m.y + 0.6 * u), Vector2(x + 1.0 * u, m.y + 0.6 * u), Vector2(x, m.y - 2.4 * u)]), tint)
				draw_circle(Vector2(x, m.y - 2.6 * u), 0.45 * u, tint)
		"tree":
			draw_rect(Rect2(m + Vector2(-0.5 * u, 0.5 * u), Vector2(u, 2.6 * u)), tint)
			draw_circle(m + Vector2(0, -0.6 * u), 2.3 * u, tint)
		"key":
			draw_arc(m + Vector2(0, -1.6 * u), 1.2 * u, 0, TAU, 16, tint, maxf(1.0, 0.6 * u))
			draw_rect(Rect2(m + Vector2(-0.35 * u, -0.5 * u), Vector2(0.7 * u, 4.0 * u)), tint)
			draw_rect(Rect2(m + Vector2(0.3 * u, 2.4 * u), Vector2(1.2 * u, 0.6 * u)), tint)
			draw_rect(Rect2(m + Vector2(0.3 * u, 1.3 * u), Vector2(0.9 * u, 0.6 * u)), tint)
		_:
			# Башня с зубцами и воротами
			draw_rect(Rect2(m + Vector2(-1.8 * u, -1.6 * u), Vector2(3.6 * u, 4.6 * u)), tint)
			for k in 3:
				draw_rect(Rect2(m + Vector2(-1.8 * u + k * 1.4 * u, -2.6 * u), Vector2(0.8 * u, 1.0 * u)), tint)
			draw_rect(Rect2(m + Vector2(-0.7 * u, 1.2 * u), Vector2(1.4 * u, 1.8 * u)), field)
			draw_circle(m + Vector2(0, 1.2 * u), 0.7 * u, field)


func _draw_name(s: Dictionary, at_center: Vector2, font: Font, hl: bool, with_size: bool) -> void:
	var text: String = s["name"]
	if with_size or hl:
		text += " (%s)" % size_name(s)
	var fs: int = 14
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var box := Rect2(at_center + Vector2(-w * 0.5 - 6.0, -fs + 1.0), Vector2(w + 12.0, fs + 7.0))
	draw_rect(box, Color(0.06, 0.05, 0.04, 0.75))
	draw_rect(box, Color(1.0, 0.86, 0.45) if hl else Color(0.72, 0.6, 0.36), false, 1.0)
	draw_string(font, at_center + Vector2(-w * 0.5, 2.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		Color(1.0, 0.92, 0.6) if hl else Color(0.95, 0.9, 0.78))


# Очерк города: территория, кварталы и улицы, стена с башнями, ворота
func _draw_outline(s: Dictionary, cs: float, z: float) -> void:
	var own: Dictionary = s["_own"]
	var cells: Array = s["_cells"]
	# Ореол: город отделён от обычной карты
	for k in cells:
		var p: Vector2 = game.world_to_screen(Vector2(k) * cell_m)
		draw_rect(Rect2(p - Vector2(cs, cs) * 0.08, Vector2(cs, cs) * 1.16), Color(0, 0, 0, 0.18))
	# Внутреннее пространство
	for k in cells:
		var p: Vector2 = game.world_to_screen(Vector2(k) * cell_m)
		draw_rect(Rect2(p, Vector2(cs, cs)), Color(0.80, 0.73, 0.56, 0.95))
	# Irregular painted wards, inspired by hand-drawn medieval city plans.
	var n: int = BLOCKS.get(s["size"], 4)
	var hseed: int = hash(String(s["id"]))
	var buildings: Array = []
	for k in cells:
		var p: Vector2 = game.world_to_screen(Vector2(k) * cell_m)
		var rng := RandomNumberGenerator.new()
		rng.seed = hseed ^ (k.x * 73856093) ^ (k.y * 19349663)
		var bw: float = cs / n
		for i in n:
			for j in n:
				var roll: float = rng.randf()
				var foot: Vector2 = p + Vector2((float(i) + 0.5 + rng.randf_range(-0.13, 0.13)) * bw, (float(j) + 0.8 + rng.randf_range(-0.10, 0.10)) * bw)
				if roll < 0.16:
					buildings.append({"foot": foot, "key": "tree_oak", "height": bw * 0.62})
				elif roll > 0.28:
					buildings.append({"foot": foot, "key": "house" if roll < 0.78 else "inn", "height": bw * rng.randf_range(0.58, 0.85)})
	buildings.append({"foot": game.world_to_screen(s["_center"]), "key": "hall", "height": cs * 0.36})
	buildings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["foot"].y < b["foot"].y)
	for building in buildings:
		Art.sprite(self, building["key"], building["foot"], building["height"])
	# Стена по краю клеток
	var walled: bool = s["walled"]
	var wall_col: Color = Color(0.66, 0.63, 0.57) if walled else Color(0.45, 0.33, 0.2)
	var wid: float = clampf((9.0 if walled else 3.0) * z * (250.0 / cell_m) * 1.0, 2.0, 30.0)
	var hl_side: String = prompt_side if prompt_for == s and prompt_kind == "wall" else ""
	for k in cells:
		var p: Vector2 = game.world_to_screen(Vector2(k) * cell_m)
		var e: Array = [[Vector2i(0, -1), p, p + Vector2(cs, 0), "north"], [Vector2i(0, 1), p + Vector2(0, cs), p + Vector2(cs, cs), "south"],
			[Vector2i(-1, 0), p, p + Vector2(0, cs), "west"], [Vector2i(1, 0), p + Vector2(cs, 0), p + Vector2(cs, cs), "east"]]
		for ed in e:
			if not own.has(k + ed[0]):
				var col: Color = Color(1.0, 0.85, 0.4) if ed[3] == hl_side else wall_col
				draw_line(ed[1], ed[2], Color(0.1, 0.08, 0.06, 0.85), wid + 3.0)
				draw_line(ed[1], ed[2], col, wid)
				if walled:
					for q in [ed[1], ed[2], (ed[1] + ed[2]) * 0.5]:
						draw_circle(q, wid * 1.1 + 1.5, Color(0.1, 0.08, 0.06, 0.85))
						draw_circle(q, wid * 1.1, col.darkened(0.08))
	# Ворота: проём в стене и две башни
	var gw: Vector2 = game.world_to_screen(s["_gate_wall"])
	var along: Vector2 = Vector2(1, 0) if side_of(s, s["_gate"]) in ["north", "south"] else Vector2(0, 1)
	var gh: float = clampf(18.0 * z, 4.0, 60.0)
	draw_line(gw - along * gh, gw + along * gh, Color(0.62, 0.5, 0.33), wid + 3.0)
	var gate_col: Color = Color(1.0, 0.85, 0.4) if prompt_for == s and prompt_kind == "gate" else Color(0.58, 0.55, 0.5)
	for sgn in [-1.0, 1.0]:
		draw_circle(gw + along * gh * sgn, wid * 1.5 + 2.0, Color(0.1, 0.08, 0.06, 0.9))
		draw_circle(gw + along * gh * sgn, wid * 1.5, gate_col)


# Медальон поселения (Huzzah 2026-10-23, референс Day R): круглая картинка в рамке, сверху знамя с гербом.
# Картинка — по уровню развития (art/medallion, tools/make_settlement_medallions.py): город с ростом (city_growth.gd) —
# по этапу, остальные — по размеру. Медальон занимает круг поселения на карте; издали радиус не меньше MEDAL_MIN_PX
func _draw_medallion(s: Dictionary, c0: Vector2, rp: float, hl: bool) -> void:
	var tex: Texture2D = medallion_texture(dev_level(s))
	draw_circle(c0 + Vector2(3, 5), rp * 1.02, Color(0, 0, 0, 0.35))
	if tex != null:
		# Рамка картинки — на 314 из 320 px от центра (см. генератор)
		var half: float = rp * 320.0 / 314.0
		draw_texture_rect(tex, Rect2(c0 - Vector2(half, half), Vector2(half, half) * 2.0), false)
	else:
		draw_circle(c0, rp, Color(0.55, 0.44, 0.30))
	var near: bool = prompt_for == s and prompt_kind == "wall"
	if hl or near:
		draw_arc(c0, rp + 2.0, 0.0, TAU, 96, Color(1.0, 0.85, 0.4), maxf(2.0, rp * 0.03), true)
	# Ворота: точка на кольце со стороны ворот на карте
	var gd: Vector2 = (s["_gate"] - s["_center"]).normalized()
	var gate_col: Color = Color(1.0, 0.85, 0.4) if (prompt_for == s and prompt_kind == "gate") or hl else Color(0.30, 0.20, 0.12)
	draw_circle(c0 + gd * rp, maxf(rp * 0.05, 3.0) + 1.5, Color(0.1, 0.07, 0.05, 0.9))
	draw_circle(c0 + gd * rp, maxf(rp * 0.05, 3.0), gate_col)
	_draw_banner(c0 + Vector2(0, -rp * 0.86), rp * 0.46, s.get("emblem", {}), hl)


## Знамя с гербом: перекладина, полотнище цвета поля с ласточкиным хвостом, фигура герба
func _draw_banner(top: Vector2, w: float, em: Dictionary, hl: bool) -> void:
	var h: float = w * 1.4
	var field := Color(String(em.get("field", "#26262c")))
	var tint := Color(String(em.get("tint", "#e2b84c")))
	var x0: float = top.x - w * 0.5
	var x1: float = top.x + w * 0.5
	var y0: float = top.y - h * 0.35
	var cloth := PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y0 + h),
		Vector2(top.x, y0 + h * 0.82), Vector2(x0, y0 + h)])
	var sh := PackedVector2Array()
	for q in cloth:
		sh.append(q + Vector2(2, 3))
	draw_colored_polygon(sh, Color(0, 0, 0, 0.4))
	draw_colored_polygon(cloth, field)
	# Складки: светлее у краёв
	draw_colored_polygon(PackedVector2Array([Vector2(x0, y0), Vector2(x0 + w * 0.12, y0), Vector2(x0 + w * 0.12, y0 + h * 0.96), Vector2(x0, y0 + h)]), field.lightened(0.12))
	var loop := cloth.duplicate()
	loop.append(cloth[0])
	draw_polyline(loop, Color(1.0, 0.9, 0.55) if hl else tint, maxf(1.5, w * 0.05), true)
	draw_polyline(loop, Color(0, 0, 0, 0.8), 1.0, true)
	# Перекладина с навершиями
	var bar: float = maxf(2.0, w * 0.06)
	draw_line(Vector2(x0 - w * 0.12, y0), Vector2(x1 + w * 0.12, y0), Color(0.25, 0.17, 0.10), bar + 2.0)
	draw_line(Vector2(x0 - w * 0.12, y0), Vector2(x1 + w * 0.12, y0), Color(0.62, 0.48, 0.28), bar)
	for x in [x0 - w * 0.12, x1 + w * 0.12]:
		draw_circle(Vector2(x, y0), bar * 0.9, tint)
	_draw_charge(Vector2(top.x, y0 + h * 0.42), w * 0.11, em, field, tint)


## Уровень развития поселения для медальона: 0 стоянка … 5 большой город
func dev_level(s: Dictionary) -> int:
	var plan: Dictionary = s.get("_plan", {})
	if Growth.has_growth(plan):
		var g: Dictionary = _growth_of(s)
		return clampi(Growth.stage(plan, g) + 1, 1, MEDALLIONS.size() - 1)
	return int(SIZE_LEVEL.get(String(s.get("size", "")), 2))


func medallion_texture(level: int) -> Texture2D:
	var path: String = MEDALLION_DIR + MEDALLIONS[clampi(level, 0, MEDALLIONS.size() - 1)] + ".png"
	if not _medallions.has(path):
		_medallions[path] = load(path) if ResourceLoader.exists(path) else null
	return _medallions[path]

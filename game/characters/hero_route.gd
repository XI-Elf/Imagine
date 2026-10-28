extends Node2D
## Ход героя мышью по общей карте: ЛКМ по точке — герой идёт туда сам, в обход стен города и края мира,
## по возможности посуху и мимо проклятья; удерживать ЛКМ — вести за курсором; ПКМ — остановиться.
## Клик по городу (щиток, очерк, клетки) — путь к воротам, там открывается обычный выбор «Войти».
## WASD перебивает путь. Shift — бежать по пути. Пока открыт выбор у поселения — герой стоит,
## «Продолжить путь» — идёт дальше (если целью был не этот город).
##
## Путь — AStarGrid2D на сетке вокруг отрезка «герой — цель»: клетка тем крупнее, чем дальше цель
## (CELLS_ALONG клеток на весь путь, от MIN_CELL_M до MAX_CELL_M), и путь пересчитывается мельче,
## когда пройдена большая часть. Вес клетки = 1 / скорость местности; вода и проклятье — дороже
## (WATER_COST, RAD_COST) [Q19: не баланс, оставлено]: реку переплывёт там, где уже, а в лужу посреди суши не полезет.
## Протоптанные дороги (world/trails.gd) дешевле по ступени — путь предпочитает их.

const R := preload("res://characters/actor_rules.gd")

const CELLS_ALONG: float = 90.0
const MIN_CELL_M: float = 12.0
const MAX_CELL_M: float = 450.0
const MARGIN_CELLS: int = 14
const MAX_GRID: int = 260            # клеток по стороне сетки, не больше
const WATER_COST: float = 14.0
const RAD_COST: float = 4.0
const SNAP_LAND_M: float = 400.0     # клик в воду — к ближайшему берегу не дальше этого
const REPLAN_SHARE: float = 0.45     # осталось меньше этой доли пути — пересчитать мельче
const STUCK_S: float = 0.6
const HOLD_RETARGET_S: float = 0.25  # при удержании ЛКМ — новая цель не чаще
const CITY_PICK_PX: float = 26.0     # щиток города издали: попадание в этот радиус от центра
const WALL_RING_COST: float = 8.0    # полоса у стены города (где спрашивают «проникнуть»): путь её обходит
const TRAIL_MAX_CELL_M: float = 100.0  # тропы учитываются, пока клетка сетки не крупнее этого
const Trails := preload("res://world/trails.gd")

var cast: Node2D
var game: Node2D
var points: PackedVector2Array = PackedVector2Array()   # оставшиеся точки пути (метры)
var target: Vector2 = Vector2.INF
var goal_city: String = ""           # id города, если шли к его воротам
var _plan_len: float = 0.0
var _plan_cell: float = 0.0
var _stuck_t: float = 0.0
var _replans_stuck: int = 0
var _hold: bool = false
var _hold_t: float = 0.0


func setup(c: Node2D) -> void:
	cast = c
	game = c.game


func active() -> bool:
	return target != Vector2.INF


func cancel() -> void:
	points = PackedVector2Array()
	target = Vector2.INF
	goal_city = ""
	_stuck_t = 0.0
	_replans_stuck = 0
	queue_redraw()


# =====================================================================
# ВВОД
# =====================================================================
func _unhandled_input(event: InputEvent) -> void:
	if game == null or not game.ready_done or game.typing or game.menu_open:
		return
	if not (event is InputEventMouseButton):
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		_hold = event.pressed
		if not event.pressed:
			return
		_hold_t = 0.0
		if click(event.position):
			get_viewport().set_input_as_handled()
	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and active():
		cancel()
		get_viewport().set_input_as_handled()


## Клик по точке экрана (открыт для тестов). true — путь задан
func click(screen_pos: Vector2) -> bool:
	if not cast.controls_hero or not cast._hero_alive() or cast.hero_away or cast.sheet_visible:
		return false
	return go_to(game._screen_world(screen_pos), _city_on_screen(screen_pos))


## Идти к точке p карты; city — поселение, по которому щёлкнули (пусто — нет)
func go_to(p: Vector2, city: Dictionary = {}) -> bool:
	var st: Node = game.get("settlements")
	var h: Dictionary = cast.hero
	var a: Actor = h["actor"]
	var to: Vector2 = p
	var city_id: String = ""
	if not city.is_empty() and st != null:
		city_id = String(city["id"])
		to = st.exit_point(city_id)
		# Уже у этих ворот — снова показать выбор
		st.dismissed.erase(city_id + ":gate")
		st.dismissed.erase(city_id + ":wall")
	elif game.biome_at(to) == 0:
		cast._event(I18n.t("Туда не дойти: за краем мира"))
		return false
	elif game.biome_at(to) == 1:
		var shore: Vector2 = cast._find_land(to, SNAP_LAND_M)
		if shore != to:
			to = shore
	# Выбор у другого поселения открыт — клик по карте значит «Продолжить путь»
	if st != null and not st.prompt_for.is_empty() and String(st.prompt_for["id"]) != city_id:
		st.choose_continue()
	if a.sleeping:
		a.set_sleep(false)
	if not _plan(h["pos"], to):
		cast._event(I18n.t("Пути туда нет"))
		cancel()
		return false
	goal_city = city_id
	_replans_stuck = 0
	return true


# Поселение под курсором: на клетках или (издали) в щитке
func _city_on_screen(sp: Vector2) -> Dictionary:
	var st: Node = game.get("settlements")
	if st == null:
		return {}
	var s: Dictionary = st.settlement_at(game._screen_world(sp))
	if not s.is_empty():
		return s
	for c in st.list:
		var cp: Vector2 = game.world_to_screen(c["_center"])
		if sp.distance_to(cp + Vector2(0, -6)) <= CITY_PICK_PX:
			return c
	return {}


# =====================================================================
# ПОИСК ПУТИ
# =====================================================================
func _plan(from: Vector2, to: Vector2) -> bool:
	var dist: float = from.distance_to(to)
	target = to
	if dist < 4.0:
		points = PackedVector2Array([to])
		_plan_len = dist
		_plan_cell = MIN_CELL_M
		queue_redraw()
		return true
	# Не нашёлся путь в окне вокруг отрезка — окно вчетверо шире (обход вдоль моря, края мира)
	if _plan_in(from, to, 1.0) or _plan_in(from, to, 4.0):
		return true
	target = Vector2.INF
	return false


func _plan_in(from: Vector2, to: Vector2, widen: float) -> bool:
	var dist: float = from.distance_to(to)
	var cell: float = clampf(dist / CELLS_ALONG, MIN_CELL_M, MAX_CELL_M)
	var lo: Vector2 = Vector2(minf(from.x, to.x), minf(from.y, to.y))
	var hi: Vector2 = Vector2(maxf(from.x, to.x), maxf(from.y, to.y))
	var pad: float = (cell * MARGIN_CELLS + dist * 0.15) * widen
	lo -= Vector2(pad, pad)
	hi += Vector2(pad, pad)
	# Город на пути целиком в окне, с запасом на обход
	var st: Node = game.get("settlements")
	if st != null:
		for s in st.list:
			if bool(s.get("walled", false)) and Rect2(lo, hi - lo).intersects(s["_rect"]):
				var g: Rect2 = s["_rect"].grow(st.APPROACH_M + 300.0)
				lo = Vector2(minf(lo.x, g.position.x), minf(lo.y, g.position.y))
				hi = Vector2(maxf(hi.x, g.end.x), maxf(hi.y, g.end.y))
	var size := Vector2i(ceili((hi.x - lo.x) / cell), ceili((hi.y - lo.y) / cell))
	if size.x > MAX_GRID or size.y > MAX_GRID:
		cell *= maxf(float(size.x), float(size.y)) / float(MAX_GRID)
		size = Vector2i(ceili((hi.x - lo.x) / cell), ceili((hi.y - lo.y) / cell))
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(Vector2i.ZERO, size)
	grid.cell_size = Vector2(cell, cell)
	grid.offset = lo + Vector2(cell, cell) * 0.5
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	for y in size.y:
		for x in size.x:
			var c: Vector2 = grid.offset + Vector2(x, y) * cell
			var b: int = game.biome_at(c)
			if b == 0:
				grid.set_point_solid(Vector2i(x, y), true)
				continue
			var ter: Dictionary = R.terrain(b)
			var w: float
			if b == 1:
				w = WATER_COST
			else:
				w = 1.0 / maxf(float(ter.get("speed", 1.0)), 0.2)
				if float(ter.get("radiation_h", 0.0)) > 0.0:
					w *= RAD_COST
			grid.set_point_weight_scale(Vector2i(x, y), w)
	_prefer_trails(grid, lo, size, cell)
	# Стены городов: клетки сетки, задевающие клетки поселения со стеной (сетка бывает крупнее их).
	# Полоса подхода у стены дорогая: мимо города путь идёт дальше, чем там спрашивают «проникнуть»
	if st != null:
		var area := Rect2(lo, hi - lo)
		for s in st.list:
			if not bool(s.get("walled", false)) or not area.intersects(s["_rect"].grow(st.APPROACH_M + cell)):
				continue
			var ring: float = st.APPROACH_M + cell * 0.75
			var ra: Rect2 = s["_rect"].grow(ring)
			var b0 := Vector2i(floori((ra.position.x - lo.x) / cell), floori((ra.position.y - lo.y) / cell))
			var b1 := Vector2i(floori((ra.end.x - lo.x) / cell), floori((ra.end.y - lo.y) / cell))
			for gy in range(maxi(b0.y, 0), mini(b1.y, size.y - 1) + 1):
				for gx in range(maxi(b0.x, 0), mini(b1.x, size.x - 1) + 1):
					var gp := Vector2i(gx, gy)
					var c: Vector2 = grid.offset + Vector2(gp) * cell
					if not grid.is_point_solid(gp) and c.distance_to(st.nearest_on_cells(s, c)) < ring:
						grid.set_point_weight_scale(gp, grid.get_point_weight_scale(gp) * WALL_RING_COST)
			if st.radial(s):
				# Круглый город: клетки сетки, задевающие круг стены
				var cr: Rect2 = s["_rect"]
				var c0 := Vector2i(floori((cr.position.x - lo.x) / cell), floori((cr.position.y - lo.y) / cell))
				var c1 := Vector2i(floori((cr.end.x - lo.x) / cell), floori((cr.end.y - lo.y) / cell))
				for gy in range(maxi(c0.y, 0), mini(c1.y, size.y - 1) + 1):
					for gx in range(maxi(c0.x, 0), mini(c1.x, size.x - 1) + 1):
						var gr := Rect2(lo + Vector2(gx, gy) * cell, Vector2(cell, cell))
						var q: Vector2 = s["_center"].clamp(gr.position, gr.end)
						if q.distance_to(s["_center"]) < s["_radius"]:
							grid.set_point_solid(Vector2i(gx, gy), true)
				continue
			for k in s["_cells"]:
				var r := Rect2(Vector2(k) * st.cell_m, Vector2(st.cell_m, st.cell_m))
				var a0 := Vector2i(floori((r.position.x - lo.x) / cell), floori((r.position.y - lo.y) / cell))
				var a1 := Vector2i(floori((r.end.x - 0.01 - lo.x) / cell), floori((r.end.y - 0.01 - lo.y) / cell))
				for gy in range(maxi(a0.y, 0), mini(a1.y, size.y - 1) + 1):
					for gx in range(maxi(a0.x, 0), mini(a1.x, size.x - 1) + 1):
						grid.set_point_solid(Vector2i(gx, gy), true)
	var ca := Vector2i(floori((from.x - lo.x) / cell), floori((from.y - lo.y) / cell)).clamp(Vector2i.ZERO, size - Vector2i.ONE)
	var cb := Vector2i(floori((to.x - lo.x) / cell), floori((to.y - lo.y) / cell)).clamp(Vector2i.ZERO, size - Vector2i.ONE)
	# Свои клетки (герой и цель) проходимы всегда: герой может стоять у самой стены
	grid.set_point_solid(ca, false)
	grid.set_point_solid(cb, false)
	# Неполный путь годится, если кончается рядом с целью (цель у самого края мира, в узкой щели)
	var path: PackedVector2Array = grid.get_point_path(ca, cb, true)
	if path.is_empty() or path[path.size() - 1].distance_to(to) > cell * 2.5:
		return false
	path[path.size() - 1] = to
	if path.size() > 1:
		path.remove_at(0)
	points = path
	_plan_len = dist
	_plan_cell = cell
	queue_redraw()
	return true


# Протоптанные дороги (world/trails.gd) дешевле: путь мышью сворачивает на них, и тропа от этого крепнет.
# Только на мелкой сетке: на крупной одна клетка тропы удешевила бы сотни метров вокруг
func _prefer_trails(grid: AStarGrid2D, lo: Vector2, size: Vector2i, cell: float) -> void:
	var tl: Node = game.get("trails")
	if tl == null or cell > TRAIL_MAX_CELL_M or tl.model.stage_of.is_empty():
		return
	var best := {}
	for c in tl.model.stage_of:
		var q: Vector2 = tl.model.center_of(c)
		var g := Vector2i(floori((q.x - lo.x) / cell), floori((q.y - lo.y) / cell))
		if g.x >= 0 and g.y >= 0 and g.x < size.x and g.y < size.y:
			best[g] = maxi(int(best.get(g, 0)), int(tl.model.stage_of[c]))
	for g in best:
		if not grid.is_point_solid(g):
			grid.set_point_weight_scale(g, grid.get_point_weight_scale(g) * float(Trails.ROUTE_WEIGHT[best[g]]))


# =====================================================================
# ХОД
# =====================================================================
## Направление на этот кадр (зовёт cast._drive_hero); ZERO — стоять
func steer(pos: Vector2) -> Vector2:
	if not active():
		return Vector2.ZERO
	var reach: float = maxf(6.0, _plan_cell * 0.5)
	while points.size() > 1 and pos.distance_to(points[0]) < reach:
		points.remove_at(0)
	if points.size() == 1 and pos.distance_to(points[0]) < 0.05:
		cancel()
		return Vector2.ZERO
	# Ближе к цели — путь мельче (крупная сетка не видит узкие места)
	var left: float = pos.distance_to(target)
	if _plan_cell > MIN_CELL_M * 1.5 and left < _plan_len * REPLAN_SHARE and left > 60.0:
		var keep: String = goal_city
		if not _plan(pos, target):
			cancel()
			return Vector2.ZERO
		goal_city = keep
	return (points[0] - pos).normalized()


## Последняя точка пути (INF — путь не на последнем отрезке)
func final_point() -> Vector2:
	return points[0] if active() and points.size() == 1 else Vector2.INF


## Итог шага за кадр: застрял — пересчитать, второй раз — бросить путь
func stepped(moved: bool, delta: float) -> void:
	if not active():
		return
	_stuck_t = 0.0 if moved else _stuck_t + delta
	if _stuck_t < STUCK_S:
		return
	_stuck_t = 0.0
	_replans_stuck += 1
	var keep: String = goal_city
	if _replans_stuck > 2 or not _plan(cast.hero["pos"], target):
		cancel()
		cast._event(I18n.t("Дальше не пройти"))
		return
	goal_city = keep


func _process(delta: float) -> void:
	if game == null or not game.ready_done:
		return
	# Удержание ЛКМ: цель идёт за курсором
	if _hold and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_hold_t += delta
		if _hold_t >= HOLD_RETARGET_S and game.pointer_over_map() and not game.menu_open:
			_hold_t = 0.0
			var p: Vector2 = game._mouse_world()
			if not active() or p.distance_to(target) > 6.0 / maxf(game.zoom, 0.001):
				click(get_viewport().get_mouse_position())
	else:
		_hold = false
	if active() and (not cast._hero_alive() or cast.hero_away or not cast.controls_hero):
		cancel()
	# Дошли до ворот своего города: открылся выбор — путь окончен
	var st: Node = game.get("settlements")
	if active() and st != null and not st.prompt_for.is_empty() and String(st.prompt_for["id"]) == goal_city:
		cancel()
	queue_redraw()


# =====================================================================
# РИСОВАНИЕ
# =====================================================================
func _draw() -> void:
	if not active() or not cast._hero_alive():
		return
	var col := Color(1.0, 0.85, 0.35, 0.85)
	var line := PackedVector2Array([game.world_to_screen(cast.hero["pos"])])
	for q in points:
		line.append(game.world_to_screen(q))
	if line.size() > 1:
		draw_polyline(line, Color(0, 0, 0, 0.55), 4.0, true)
		draw_polyline(line, col, 2.0, true)
	var tp: Vector2 = game.world_to_screen(target)
	draw_arc(tp, 9.0, 0.0, TAU, 24, Color(0, 0, 0, 0.7), 4.0)
	draw_arc(tp, 9.0, 0.0, TAU, 24, col, 2.0)
	draw_line(tp + Vector2(-4, 0), tp + Vector2(4, 0), col, 2.0)
	draw_line(tp + Vector2(0, -4), tp + Vector2(0, 4), col, 2.0)

extends Node2D
## Хід героя мишею загальною картою: ЛКМ по точці — герой іде туди сам, в обхід стін міста й краю світу,
## по змозі суходолом і повз прокляття; утримувати ЛКМ — вести за курсором; ПКМ — зупинитися.
## Клік по місту (щиток, обрис, клітинки) — шлях до брами, там відкривається звичайний вибір «Увійти».
## WASD перебиває шлях. Shift — бігти шляхом. Поки відкритий вибір біля поселення — герой стоїть,
## «Продовжити шлях» — іде далі (якщо ціллю було не це місто).
##
## Шлях — AStarGrid2D на сітці довкола відрізка «герой — ціль»: клітинка тим більша, що далі ціль
## (CELLS_ALONG клітинок на весь шлях, від MIN_CELL_M до MAX_CELL_M), і шлях перераховується дрібніше,
## коли пройдено більшу частину. Вага клітинки = 1 / швидкість місцевості; вода й прокляття — дорожчі
## (WATER_COST, RAD_COST) [Q19: не баланс, залишено]: річку перепливе там, де вужче, а в калюжу посеред суходолу не полізе.
## Протоптані дороги (world/trails.gd) дешевші за ступенем — шлях надає їм перевагу.
## Пункт 12 (Huzzah 2026-10-29): біля героя, на початку лінії, — скільки лишилося йти, за Розумом героя:
## 1–3 — словами («рукой подать» … «очень далеко»), 4–6 — округлено, 7+ — точно.

const R := preload("res://characters/actor_rules.gd")
const Sheet := preload("res://characters/sheet.gd")

const CELLS_ALONG: float = 90.0
const MIN_CELL_M: float = 12.0
const MAX_CELL_M: float = 450.0
const MARGIN_CELLS: int = 14
const MAX_GRID: int = 260            # клітинок по стороні сітки, не більше
const WATER_COST: float = 14.0
const RAD_COST: float = 4.0
const SNAP_LAND_M: float = 400.0     # клік у воду — до найближчого берега не далі за це
const REPLAN_SHARE: float = 0.45     # лишилося менше цієї частки шляху — перерахувати дрібніше
const STUCK_S: float = 0.6
const HOLD_RETARGET_S: float = 0.25  # за утримання ЛКМ — нова ціль не частіше
const CITY_PICK_PX: float = 26.0     # щиток міста здалеку: влучання в цей радіус від центру
const WALL_RING_COST: float = 8.0    # смуга біля стіни міста (де питають «проникнути»): шлях її оминає
const TRAIL_MAX_CELL_M: float = 100.0  # стежки враховуються, поки клітинка сітки не більша за це
const Trails := preload("res://world/trails.gd")

var cast: Node2D
var game: Node2D
var points: PackedVector2Array = PackedVector2Array()   # решта точок шляху (метри)
var target: Vector2 = Vector2.INF
var goal_city: String = ""           # id міста, якщо йшли до його брами
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
# ВВЕДЕННЯ
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


## Клік по точці екрана (відкритий для тестів). true — шлях задано
func click(screen_pos: Vector2) -> bool:
	if not cast.controls_hero or not cast._hero_alive() or cast.hero_away or cast.sheet_visible:
		return false
	return go_to(game._screen_world(screen_pos), _city_on_screen(screen_pos))


## Іти до точки p карти; city — поселення, по якому клацнули (порожньо — немає)
func go_to(p: Vector2, city: Dictionary = {}) -> bool:
	var st: Node = game.get("settlements")
	var h: Dictionary = cast.hero
	var a: Actor = h["actor"]
	var to: Vector2 = p
	var city_id: String = ""
	if not city.is_empty() and st != null:
		city_id = String(city["id"])
		to = st.exit_point(city_id)
		# Уже біля цієї брами — знову показати вибір
		st.dismissed.erase(city_id + ":gate")
		st.dismissed.erase(city_id + ":wall")
	elif game.biome_at(to) == 0:
		cast._event(I18n.t("Туда не дойти: за краем мира"))
		return false
	elif game.biome_at(to) == 1:
		var shore: Vector2 = cast._find_land(to, SNAP_LAND_M)
		if shore != to:
			to = shore
	# Вибір біля іншого поселення відкритий — клік по карті означає «Продовжити шлях»
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


# Поселення під курсором: на клітинках або (здалеку) у щитку
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
# ПОШУК ШЛЯХУ
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
	# Не знайшовся шлях у вікні довкола відрізка — вікно вчетверо ширше (обхід уздовж моря, краю світу)
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
	# Місто на шляху цілком у вікні, із запасом на обхід
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
	# Стіни міст: клітинки сітки, що зачіпають клітинки поселення зі стіною (сітка буває більша за них).
	# Смуга підходу біля стіни дорога: повз місто шлях іде далі, ніж там питають «проникнути»
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
				# Кругле місто: клітинки сітки, що зачіпають коло стіни
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
	# Свої клітинки (герой і ціль) прохідні завжди: герой може стояти біля самої стіни
	grid.set_point_solid(ca, false)
	grid.set_point_solid(cb, false)
	# Неповний шлях годиться, якщо закінчується поруч із ціллю (ціль біля самого краю світу, у вузькій щілині)
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


# Протоптані дороги (world/trails.gd) дешевші: шлях мишею звертає на них, і стежка від цього міцніє.
# Лише на дрібній сітці: на великій одна клітинка стежки здешевила б сотні метрів довкола
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
# ХІД
# =====================================================================
## Напрямок на цей кадр (кличе cast._drive_hero); ZERO — стояти
func steer(pos: Vector2) -> Vector2:
	if not active():
		return Vector2.ZERO
	var reach: float = maxf(6.0, _plan_cell * 0.5)
	while points.size() > 1 and pos.distance_to(points[0]) < reach:
		points.remove_at(0)
	if points.size() == 1 and pos.distance_to(points[0]) < 0.05:
		cancel()
		return Vector2.ZERO
	# Ближче до цілі — шлях дрібніший (велика сітка не бачить вузьких місць)
	var left: float = pos.distance_to(target)
	if _plan_cell > MIN_CELL_M * 1.5 and left < _plan_len * REPLAN_SHARE and left > 60.0:
		var keep: String = goal_city
		if not _plan(pos, target):
			cancel()
			return Vector2.ZERO
		goal_city = keep
	return (points[0] - pos).normalized()


## Скільки метрів лишилося йти шляхом
func remaining_m() -> float:
	if not active() or cast.hero.is_empty():
		return 0.0
	var d: float = 0.0
	var prev: Vector2 = cast.hero["pos"]
	for q in points:
		d += prev.distance_to(q)
		prev = q
	return d


## Відстань для гравця за Розумом (пункт 12)
static func distance_words(m: float, iq: int) -> String:
	if iq <= 3:
		if m < 400.0:
			return I18n.t("рукой подать")
		if m < 2000.0:
			return I18n.t("близко")
		if m < 7000.0:
			return I18n.t("далеко")
		return I18n.t("очень далеко")
	if iq <= 6:
		if m < 1000.0:
			return I18n.t("около %d м") % maxi(int(round(m / 100.0)) * 100, 100)
		return I18n.t("около %d км") % maxi(int(round(m / 1000.0)), 1)
	if m < 1000.0:
		return I18n.t("%d м") % (int(round(m / 10.0)) * 10)
	return I18n.t("%.1f км") % (m / 1000.0)


## Остання точка шляху (INF — шлях не на останньому відрізку)
func final_point() -> Vector2:
	return points[0] if active() and points.size() == 1 else Vector2.INF


## Підсумок кроку за кадр: застряг — перерахувати, удруге — покинути шлях
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
	# Утримання ЛКМ: ціль іде за курсором
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
	# Дійшли до брами свого міста: відкрився вибір — шлях закінчено
	var st: Node = game.get("settlements")
	if active() and st != null and not st.prompt_for.is_empty() and String(st.prompt_for["id"]) == goal_city:
		cancel()
	queue_redraw()


# =====================================================================
# МАЛЮВАННЯ
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
		var font: Font = ThemeDB.fallback_font
		var t: String = distance_words(remaining_m(), Sheet.talk_int(cast.hero["actor"]))
		# Відстань — під позначкою цілі, а не біля героя: над героєм його ім'я (Huzzah 2026-10-30).
		# Ціль зовсім поряд із героєм — підпис під героєм, ім'я ж над ним
		var tw: float = font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		var anchor: Vector2 = line[-1]
		if anchor.distance_to(line[0]) < 70.0:
			anchor = line[0]
		var at: Vector2 = anchor + Vector2(-tw * 0.5, 30.0)
		draw_string_outline(font, at, t, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 5, Color(0, 0, 0, 0.8))
		draw_string(font, at, t, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col)
	var tp: Vector2 = game.world_to_screen(target)
	draw_arc(tp, 9.0, 0.0, TAU, 24, Color(0, 0, 0, 0.7), 4.0)
	draw_arc(tp, 9.0, 0.0, TAU, 24, col, 2.0)
	draw_line(tp + Vector2(-4, 0), tp + Vector2(4, 0), col, 2.0)
	draw_line(tp + Vector2(0, -4), tp + Vector2(0, 4), col, 2.0)

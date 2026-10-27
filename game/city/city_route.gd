extends RefCounted
## Ход героя мышью в мире города (city_world.gd): ЛКМ по месту — герой идёт туда по сетке города
## (city_map.gd, AStarGrid2D: в обход стен, домов, деревьев и лотков, в дома через двери).
## ЛКМ по жителю — подойти и заговорить (житель ходит — путь догоняет его);
## по колодцу, тайнику, доске — подойти и сделать то же, что E; по воротам — выйти, если открыты.
## Держать ЛКМ — вести за курсором, ПКМ — стоп, WASD перебивает путь.

const T = preload("res://city/city_map.gd").T

const PICK_NPC_M: float = 1.2
const PICK_PLACE_M: float = 1.6
const REACH_M: float = 0.45          # точка пути считается пройденной
const CHASE_S: float = 0.5           # пересчёт пути к идущему жителю
const STUCK_S: float = 0.8
const FREE_SEARCH: int = 4           # клик в стену/дерево — ближайшая свободная клетка в этом радиусе

var city: Node2D
var points: PackedVector2Array = PackedVector2Array()
var target: Vector2 = Vector2.INF
var goal_npc: Dictionary = {}
var goal_place: Dictionary = {}
var goal_gate: String = ""
var _chase_t: float = 0.0
var _stuck_t: float = 0.0
var _stuck_n: int = 0


func _init(c: Node2D) -> void:
	city = c


func active() -> bool:
	return target != Vector2.INF


func cancel() -> void:
	points = PackedVector2Array()
	target = Vector2.INF
	goal_npc = {}
	goal_place = {}
	goal_gate = ""
	_stuck_t = 0.0
	_stuck_n = 0


## Клик в точку p (метры города). true — путь задан
func click(p: Vector2) -> bool:
	cancel()
	var m = city.map
	var n: Dictionary = _npc_at(p)
	if not n.is_empty():
		goal_npc = n
		if _route_to(n["pos"]):
			return true
		cancel()
		return false
	var pl: Dictionary = _place_at(p)
	if not pl.is_empty():
		goal_place = pl
		if _route_to(city._place_pos(pl)):
			return true
		cancel()
		city._say("Не подойти: %s" % pl.get("name", ""))
		return false
	var g: String = m.gate_at(p)
	if g != "":
		if m.closed_gates.has(g):
			city._say("%s заперты" % city._gate_def(g).get("name", "Ворота"))
			return false
		goal_gate = g
		var gc: Vector2 = m.center_of(m.cell_of(p))
		if _route_to(gc):
			points.append(gc)
			target = gc
			return true
		cancel()
		return false
	if _route_to(p):
		return true
	cancel()
	city._say("Туда не пройти")
	return false


func _npc_at(p: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = PICK_NPC_M
	for n in city.npcs:
		var d: float = n["pos"].distance_to(p)
		if d < best_d and n["actor"].alive and city._visible_for_hero(n["pos"]):
			best_d = d
			best = n
	return best


func _place_at(p: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = PICK_PLACE_M
	for pl in city.def.get("places", []):
		var d: float = city._place_pos(pl).distance_to(p)
		if d < best_d:
			best_d = d
			best = pl
	return best


# Путь до ближайшей свободной клетки у p (сама p, если свободна)
func _route_to(p: Vector2) -> bool:
	var m = city.map
	var goal: Vector2i = _free_near(m.cell_of(p))
	if goal.x < 0:
		return false
	var path: PackedVector2Array = m.astar.get_point_path(m.cell_of(city.hero_pos).clamp(Vector2i.ZERO, Vector2i(m.w - 1, m.h - 1)), goal, true)
	if path.is_empty():
		return false
	# Последняя точка — сам клик, если он на свободной клетке (не центр клетки)
	if m.cell_of(p) == goal and m.is_free(p, city.BODY_R):
		path[path.size() - 1] = p
	if path.size() > 1:
		path.remove_at(0)
	points = path
	target = path[path.size() - 1]
	return true


func _free_near(c: Vector2i) -> Vector2i:
	var m = city.map
	var best := Vector2i(-1, -1)
	var best_d: float = INF
	for dy in range(-FREE_SEARCH, FREE_SEARCH + 1):
		for dx in range(-FREE_SEARCH, FREE_SEARCH + 1):
			var q := c + Vector2i(dx, dy)
			if q.x < 0 or q.y < 0 or q.x >= m.w or q.y >= m.h or m.astar.is_point_solid(q):
				continue
			var d: float = Vector2(dx, dy).length()
			if d < best_d:
				best_d = d
				best = q
	return best


## Направление на этот кадр; по приходу — разговор, осмотр или выход
func steer(delta: float) -> Vector2:
	if not active():
		return Vector2.ZERO
	var pos: Vector2 = city.hero_pos
	if not goal_npc.is_empty():
		if pos.distance_to(goal_npc["pos"]) < city.TALK_M * 0.8:
			var n: Dictionary = goal_npc
			cancel()
			city.talk(n)
			return Vector2.ZERO
		_chase_t += delta
		if _chase_t >= CHASE_S:
			_chase_t = 0.0
			var n: Dictionary = goal_npc
			if not _route_to(n["pos"]):
				cancel()
				return Vector2.ZERO
			goal_npc = n
	if not goal_place.is_empty() and pos.distance_to(city._place_pos(goal_place)) < city.LOOK_M * 0.8:
		var pl: Dictionary = goal_place
		cancel()
		city.use_place(pl)
		return Vector2.ZERO
	while points.size() > 1 and pos.distance_to(points[0]) < REACH_M:
		points.remove_at(0)
	if points.size() == 1 and pos.distance_to(points[0]) < 0.15:
		_arrive()
		return Vector2.ZERO
	# Последний шаг город сам обрезает до точки (city_world._drive_hero), здесь только направление
	return (points[0] - pos).normalized()


## Последняя точка пути (INF — путь не на последнем отрезке)
func final_point() -> Vector2:
	return points[0] if active() and points.size() == 1 else Vector2.INF


## Дошли до последней точки: поставить героя в неё и завершить путь
func finish() -> void:
	_arrive()


# Конец пути: житель или место рядом — заговорить / использовать (до колодца в клетке не дойти вплотную)
func _arrive() -> void:
	var n: Dictionary = goal_npc
	var pl: Dictionary = goal_place
	cancel()
	if not n.is_empty() and city.hero_pos.distance_to(n["pos"]) < city.TALK_M:
		city.talk(n)
	elif not pl.is_empty() and city.hero_pos.distance_to(city._place_pos(pl)) < city.LOOK_M:
		city.use_place(pl)


func stepped(moved: bool, delta: float) -> void:
	if not active():
		return
	_stuck_t = 0.0 if moved else _stuck_t + delta
	if _stuck_t < STUCK_S:
		return
	_stuck_t = 0.0
	_stuck_n += 1
	var t: Vector2 = target
	var keep := [goal_npc, goal_place, goal_gate]
	if _stuck_n > 2 or not _route_to(t):
		_arrive()
		return
	goal_npc = keep[0]
	goal_place = keep[1]
	goal_gate = keep[2]


func draw(l: Node2D, px: float) -> void:
	if not active():
		return
	var col := Color(1.0, 0.85, 0.35, 0.8)
	var prev: Vector2 = city.hero_pos * px
	for q in points:
		var sp: Vector2 = q * px
		l.draw_dashed_line(prev, sp, col, 2.0, 6.0)
		prev = sp
	var tp: Vector2 = (goal_npc["pos"] if not goal_npc.is_empty() else target) * px
	l.draw_arc(tp, 7.0, 0.0, TAU, 20, Color(0, 0, 0, 0.6), 3.5)
	l.draw_arc(tp, 7.0, 0.0, TAU, 20, col, 2.0)

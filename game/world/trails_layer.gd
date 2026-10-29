extends Node2D
## Протоптані дороги на загальній карті (модель world/trails.gd): малюються під декором, поселеннями й персонажами.
## Проходи рахує characters/cast.gd у _step (герой і НПС на карті); поки герой у місті чи в бою,
## його колишня клітинка забувається, щоб повернення до брами не вважалося проходом.
## Збереження — ключ "trails" у world_save.gd; у старих збереженнях його немає — доріг немає.

const Trails := preload("res://world/trails.gd")
const CELL_M: float = 12.0
const WIDTH_M: Array = [0.0, 3.0, 5.0, 8.0, 12.0]
const MIN_PX: Array = [0.0, 1.2, 1.5, 1.8, 2.2]
const ALPHA: Array = [0.0, 0.38, 0.55, 0.75, 0.92]   # прозорість ступеня цілком
const FILL := Color(0.62, 0.5, 0.33)
const EDGE := Color(0.12, 0.09, 0.06)
const RUT := Color(0.5, 0.39, 0.25)
const REFRESH_GAME_S: float = 3600.0           # заростання перераховується раз на ігрову годину
const NEIGHBOURS: Array = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 1)]

var game: Node2D
var model := Trails.new(CELL_M)
var _refreshed_at: float = -1.0
const CLEAR_STAGE: int = 2                     # зі стежки й вище дерева й кущі декору на клітинці не ростуть
var _layers: Array = []
var _vis: Array = []           # клітинки зі стежками в кадрі


func _process(_delta: float) -> void:
	if game == null or not game.ready_done:
		return
	var now: float = game.clock.total_seconds
	if _refreshed_at < 0.0 or absf(now - _refreshed_at) >= REFRESH_GAME_S:
		_refreshed_at = now
		model.refresh(now)
	var cast: Node = game.get("cast")
	if cast != null and cast.hero_away and not cast.hero.is_empty():
		model.forget(cast.hero["actor"])
	_collect()
	for d in _layers:
		d.queue_redraw()


## Тіло b (словник characters/cast.gd) зробило крок
func walked(b: Dictionary) -> void:
	model.walk(b["actor"], b["pos"], game.clock.total_seconds)


## Протоптано так, що декору (storybook/world_decor.gd) тут не місце
func trodden(p: Vector2) -> bool:
	return model.stage_at(p) >= CLEAR_STAGE


## Клітинки, де змінився ступінь із минулого виклику (декор перезбирає їхні ділянки)
func take_dirty() -> Array:
	var out: Array = model.dirty.keys()
	model.dirty.clear()
	return out


func speed_mult(p: Vector2) -> float:
	return model.speed_mult(p)


class StageDraw extends Node2D:
	var owner_layer: Node2D
	var stage: int = 1
	func _draw() -> void:
		owner_layer.draw_stage(self, stage)


func _ready() -> void:
	model.track_dirty = true
	# Ступінь — своя CanvasGroup: клітинки й стики малюються непрозоро, прозорість — у групи цілком,
	# тому на стиках немає темних «намистин»
	for s in range(1, WIDTH_M.size()):
		var g := CanvasGroup.new()
		g.modulate = Color(1, 1, 1, ALPHA[s])
		add_child(g)
		var d := StageDraw.new()
		d.owner_layer = self
		d.stage = s
		g.add_child(d)
		_layers.append(d)


## Клітинки зі стежками в кадрі (із запасом) — їх і малюють шари ступенів у цьому кадрі
func _collect() -> void:
	_vis.clear()
	if model.stage_of.is_empty():
		return
	var vp: Rect2 = get_viewport_rect().grow(40.0)
	var area := Rect2(game._screen_world(vp.position), vp.size / game.zoom).grow(CELL_M * 2.0)
	for c in model.stage_of:
		if area.has_point(model.center_of(c)):
			_vis.append(c)


## Малює клітинки ступеня s і стики, у яких менший із двох ступенів — s
func draw_stage(l: Node2D, s: int) -> void:
	var z: float = game.zoom
	for pass_i in 2:
		var col: Color = EDGE if pass_i == 0 else FILL
		# Крайка тонша в тонкої стежки: здалеку стежинка — світла нитка, а не темна лінія
		var extra: float = clampf(_px(s, z) * 0.35, 0.0, 2.0) if pass_i == 0 else 0.0
		for c in _vis:
			var cs: int = model.stage_of[c]
			if cs < s:
				continue
			var p: Vector2 = game.world_to_screen(model.center_of(c))
			if cs == s:
				l.draw_circle(p, (_px(s, z) + extra) * 0.5, col)
			for o in NEIGHBOURS:
				var s2: int = int(model.stage_of.get(c + o, 0))
				if s2 != 0 and mini(cs, s2) == s:
					l.draw_line(p, game.world_to_screen(model.center_of(c + o)), col, _px(s, z) + extra, true)
	# Колії на ґрунтовій дорозі
	if s == 4 and _px(4, z) >= 6.0:
		for c in _vis:
			if model.stage_of[c] < 4:
				continue
			var p: Vector2 = game.world_to_screen(model.center_of(c))
			for o in NEIGHBOURS:
				if int(model.stage_of.get(c + o, 0)) >= 4:
					l.draw_line(p, game.world_to_screen(model.center_of(c + o)), RUT, maxf(1.0, _px(4, z) * 0.12), true)


func _px(s: int, z: float) -> float:
	return clampf(WIDTH_M[s] * z, MIN_PX[s], 40.0)


func to_dict() -> Dictionary:
	return model.to_dict()


func load_dict(d: Variant) -> void:
	model.load_dict(d)
	_refreshed_at = -1.0

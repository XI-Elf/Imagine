extends Node
## Слід героя по областях (регіонах) світу: тримає рівень даних world/world_map.gd, будує його покроково,
## стежить за переходом героя між областями й веде «відвідано». У 2D кожна точка карти належить рівно одній
## області, тож неоднозначності кордону з ТЗ немає; лишається тремтіння на межі — його гасить підтвердження:
## нова область зараховується, коли героя бачать у ній CONFIRM_N вибірок поспіль.

signal region_changed(new_id: int, old_id: int)

const WorldMap := preload("res://world/world_map.gd")

const SAMPLE_S: float = 0.25
const CONFIRM_N: int = 2
const BUILD_ROWS: int = 12            # рядків сітки за кадр (~10 тис. клітинок, ~6 мс)

var game: Node2D
var map := WorldMap.new()
var current: int = 0                  # область, у якій герой зараз (0 — ще невідомо)
var _t: float = 0.0
var _cand: int = 0
var _cand_n: int = 0
var _hooked: bool = false


func setup(g: Node2D) -> void:
	game = g
	map.setup(g.province_img, g.map_names.get("provinces", {}))
	map.built.connect(_on_built)
	var fl: Node = g.get("fog")
	if fl != null:
		fl.model.world_map = map


func _on_built() -> void:
	var fl: Node = game.get("fog")
	if fl != null:
		map.sync_explored(fl.model.cells)
	if map.guess_pending:
		map.guess_visited()


func _process(delta: float) -> void:
	if game == null or not game.ready_done:
		return
	if not map.is_ready:
		map.build_step(BUILD_ROWS)
		return
	_t += delta
	if _t < SAMPLE_S:
		return
	_t = 0.0
	var cast: Node = game.get("cast")
	if cast == null or cast.hero.is_empty() or cast.hero_away:
		_cand = 0
		_cand_n = 0
		return
	observe(cast.hero["pos"])


## Одна вибірка положення героя (публічна для тестів)
func observe(p: Vector2) -> void:
	var id: int = map.province_at(p)
	if id == 0 or id == current:
		_cand = 0
		_cand_n = 0
		return
	if id != _cand:
		_cand = id
		_cand_n = 1
	else:
		_cand_n += 1
	if _cand_n >= (1 if current == 0 else CONFIRM_N):
		var old: int = current
		current = id
		_cand = 0
		_cand_n = 0
		map.mark_visited(id)
		region_changed.emit(id, old)


func to_dict() -> Dictionary:
	return map.to_dict()


func load_dict(d: Variant) -> void:
	map.load_dict(d)
	current = 0
	_cand = 0
	_cand_n = 0

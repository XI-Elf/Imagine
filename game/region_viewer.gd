extends Node
## Просмотрщик регіонів (Huzzah 2026-11-04): окремий запуск того самого проєкту, що й гра, — без форка коду.
## Запускає звичайний світ (game.tscn: карта, біоми, місто з ростом, руїни, погода й час) і одразу відкриває
## огляд регіону (world/region_view.gd) у режимі просмотрщика. Збереження не пишуться.
## Клавіші: PgUp/PgDn або клік по сусідньому — інший регіон; колесо — масштаб; G — місто виросло на одне завдання,
## Shift+G — місто знову на початку; F — туман війни; [ ] — швидкість часу, P — пауза; Esc — вихід.
## Запуск із редактора: godot --path game res://region_viewer.tscn; збірка — пресет «Amber Regions» (export_presets.cfg).

const Growth := preload("res://city/city_growth.gd")

var game: Node2D
var points: int = 0


func _ready() -> void:
	Engine.set_meta("aw_load", "")
	game = load("res://game.tscn").instantiate()
	add_child(game)
	get_tree().current_scene = game
	while not game.ready_done:
		await get_tree().process_frame
	var tut: Node = get_node_or_null("/root/Tutorial")
	if tut != null:
		tut.enabled = false
		if tut.get("_card") != null:
			tut._card.visible = false
	game.show_clouds = false
	if game.hud_panel != null:
		game.hud_panel.visible = false
	if game.cast != null and game.cast.get("_status") != null:
		game.cast._status.get_parent().visible = false
	points = _city_points()
	game.region_view.standalone = true
	game.region_view.open(_start_region())
	DisplayServer.window_set_title(I18n.t("Amber — обзор регионов"))


func _start_region() -> int:
	var st: Node = game.settlements
	if st != null and not st.list.is_empty():
		var id: int = game.province_at(st.list[0]["_center"])
		if id > 0:
			return id
	return 7


func _city() -> Dictionary:
	return game.settlements.list[0] if game.settlements != null and not game.settlements.list.is_empty() else {}


func _city_points() -> int:
	var s: Dictionary = _city()
	return Growth.points(game.settlements._growth_of(s)) if not s.is_empty() else 0


## Ріст міста для перегляду: у стан міста додаються умовні здані завдання (лише в пам'яті, без збереження)
func set_points(k: int) -> void:
	var s: Dictionary = _city()
	if s.is_empty():
		return
	var w: Node = get_node_or_null("/root/Worlds")
	if w == null:
		return
	var id: String = String(s.get("city_id", s.get("id", "")))
	var done: Array = []
	for i in k:
		done.append("viewer_%d" % i)
	var cs: Dictionary = w.city_states.get(id, {})
	cs["growth"] = {"done": done, "taken": {}}
	w.city_states[id] = cs
	points = k
	game.region_view.rebuild_now()


func _max_points() -> int:
	var plan: Dictionary = _city().get("_plan", {})
	var stages: Array = plan.get("growth", {}).get("stages", [])
	return int(stages[-1].get("points", 0)) if not stages.is_empty() else 0


func _input(event: InputEvent) -> void:
	if game == null or not game.ready_done or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_ESCAPE:
			get_tree().quit()
		KEY_G:
			set_points(0 if event.shift_pressed else mini(points + 1, _max_points()))
		KEY_V, KEY_M, KEY_I, KEY_E, KEY_K, KEY_Z, KEY_R, KEY_O, KEY_B, KEY_H, KEY_T:
			pass   # клавіші гри в просмотрщику не діють
		_:
			return
	get_viewport().set_input_as_handled()

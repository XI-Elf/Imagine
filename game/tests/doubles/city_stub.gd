extends Node2D
## Заглушка мира города: тот же контракт, что у city/city_world.tscn (ветка «Мир города»), чтобы
## переходы проверялись без неё. Площадь с воротами внизу; WASD — идти, к воротам или Enter — выйти.

signal exit_requested(city_id: String, gate_id: String)

const SIZE := Vector2(900, 560)
const SPEED: float = 220.0     # пикселей экрана в секунду

var city_id: String = ""
var city_name: String = ""
var hero: Actor = null
var ctx: Dictionary = {}
var pos := Vector2(450, 120)   # герой на площади, пиксели от угла площади
var visits: int = 0
var _label: Label
var _left: bool = false


func enter(id: String, hero_actor: Actor, context: Dictionary) -> void:
	city_id = id
	hero = hero_actor
	ctx = context
	city_name = String(ctx.get("settlement", {}).get("name", id))
	visits += 1
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(14, 14)
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", Color("e8dcb0"))
	layer.add_child(_label)


func _origin() -> Vector2:
	return (get_viewport_rect().size - SIZE) * 0.5


func _gate() -> Rect2:
	return Rect2(Vector2(SIZE.x * 0.5 - 50, SIZE.y - 30), Vector2(100, 30))


func _process(delta: float) -> void:
	var dir := Vector2.ZERO
	if not Worlds.menu_open():
		if Input.is_physical_key_pressed(KEY_A) or Input.is_action_pressed("ui_left"): dir.x -= 1
		if Input.is_physical_key_pressed(KEY_D) or Input.is_action_pressed("ui_right"): dir.x += 1
		if Input.is_physical_key_pressed(KEY_W) or Input.is_action_pressed("ui_up"): dir.y -= 1
		if Input.is_physical_key_pressed(KEY_S) or Input.is_action_pressed("ui_down"): dir.y += 1
	pos = (pos + dir.limit_length(1.0) * SPEED * delta).clamp(Vector2(10, 10), SIZE - Vector2(10, 10))
	if _gate().has_point(pos):
		_exit("south")
	var clock: GameClock = ctx.get("clock")
	var t: String = ""
	if clock != null:
		var h: float = clock.hour_of_day()
		t = "%02d:%02d" % [int(h), int((h - floor(h)) * 60.0)]
	var needs: String = ""
	if hero != null:
		needs = "Здоровье %d  Голод %d  Жажда %d  Силы %d" % [int(hero.res["health"]), int(hero.res["hunger"]),
			int(hero.res["thirst"]), int(hero.res["energy"])]
	_label.text = "Город (заглушка): %s   %s\n%s\nWASD — идти, ворота внизу или Enter — выйти на общую карту, K — бой в городе, Esc — меню" % [city_name, t, needs]
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if Worlds.menu_open() or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
		_exit("south")
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_K:
		Worlds.start_battle({"return_pos": pos, "stub": true})
		get_viewport().set_input_as_handled()


func _exit(gate: String) -> void:
	if _left:
		return
	_left = true
	exit_requested.emit(city_id, gate)


func world_resumed(_result: Dictionary) -> void:
	_left = false


func _draw() -> void:
	var o: Vector2 = _origin()
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color("1b1814"))
	draw_rect(Rect2(o, SIZE), Color("6b5d48"))
	for i in 6:
		draw_rect(Rect2(o + Vector2(60 + i * 140, 40), Vector2(90, 70)), Color("8a6f4f"))
		draw_rect(Rect2(o + Vector2(60 + i * 140, 360), Vector2(90, 70)), Color("8a6f4f"))
	var g: Rect2 = _gate()
	draw_rect(Rect2(o + g.position, g.size), Color("c9a24b"))
	draw_circle(o + pos, 8.0, Color(1.0, 0.82, 0.3))


func to_dict() -> Dictionary:
	return {"pos": pos, "visits": visits}


func load_dict(d: Dictionary) -> void:
	pos = d.get("pos", pos)
	if _gate().has_point(pos):
		pos = Vector2(SIZE.x * 0.5, SIZE.y - 80)
	visits = int(d.get("visits", 0)) + 1

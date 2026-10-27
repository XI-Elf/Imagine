extends Node2D
## Заглушка боевой сцены: тот же контракт, что у battle/battle.tscn (ветка «Боевая сцена»), чтобы
## переходы проверялись без неё. Бой идёт в реальном времени 1:1 к игровому, Пробел — тактическая пауза.
## 1 — победа, 2 — поражение, 3 — бегство.

signal battle_finished(result: Dictionary)

var req: Dictionary = {}
var elapsed_s: float = 0.0
var paused: bool = false
var _label: Label
var _done: bool = false


func setup(r: Dictionary) -> void:
	req = r


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(14, 14)
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color("f0d8c0"))
	layer.add_child(_label)


func _process(delta: float) -> void:
	if not paused:
		elapsed_s += delta
	var names: Array = req.get("enemies", []).map(func(a): return a.display_name)
	var allies: Array = req.get("allies", []).map(func(a): return a.display_name)
	_label.text = "Бой (заглушка)%s   %d:%02d\nОткуда: %s   местность: %s%s%s\nСвои: %s\nВраги: %s\n1 — победа, 2 — поражение, 3 — бегство, Пробел — тактическая пауза" % [
		"   ПАУЗА" if paused else "", int(elapsed_s) / 60, int(elapsed_s) % 60, req.get("origin", ""), req.get("terrain", ""),
		", ночь" if req.get("night", false) else "", ", жара" if req.get("hot", false) else "",
		", ".join(allies), ", ".join(names)]
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_SPACE, KEY_ESCAPE:
			paused = not paused
		KEY_1:
			finish("win")
		KEY_2:
			finish("lose")
		KEY_3:
			finish("flee")
		_:
			return
	get_viewport().set_input_as_handled()


func finish(outcome: String) -> void:
	if _done:
		return
	_done = true
	battle_finished.emit({"outcome": outcome, "origin": req.get("origin", "overworld"),
		"return_pos": req.get("return_pos"), "game_minutes": elapsed_s / 60.0, "dead": []})


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color("2a1512"))


func to_dict() -> Dictionary:
	return {"elapsed_s": elapsed_s}


func load_dict(d: Dictionary) -> void:
	elapsed_s = float(d.get("elapsed_s", 0.0))

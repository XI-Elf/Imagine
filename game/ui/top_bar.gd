extends CanvasLayer
## Верхняя панель (п.13, 18, 19 правок Huzzah 2026-11-03): всегда на экране, пока в игре есть герой.
## Слева — показатели героя (здоровье, сытость, вода, энергия, силы, воздействие проклятья): значок и число,
## цветная полоска под числом, красная рамка при низком значении (как раньше в инвентаре и в строке внизу экрана).
## Справа — панель времени: значок солнца днём и луны ночью, часы; клик по времени раскрывает дату;
## рядом значки ветра, дождя или снега, если они есть в погоде у героя (world_physics.weather_here).
## Рисуется кодом на значках inventory_view.stat_icon, рамка — комикс (ui/comic_ui.gd).

const Inv := preload("res://characters/inventory_view.gd")
const ComicUI := preload("res://ui/comic_ui.gd")

const KEYS: Array = ["health", "hunger", "thirst", "energy", "stamina", "radiation"]
const CELL_W: float = 96.0
const BAR_H: float = 40.0
const TIME_W: float = 190.0
const WIND_STRONG: float = 7.0       # м/с, с этого ветер показывается значком
const COL_TEXT := Color("ece6d6")
const COL_BAD := Color("c4413a")

var game: Node
var show_date: bool = false
var _view: Control
var _font: Font


func setup(g: Node) -> void:
	game = g


func _ready() -> void:
	layer = 12
	_font = ThemeDB.fallback_font
	_view = _View.new()
	_view.bar = self
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_view)


func _process(_delta: float) -> void:
	if _view != null:
		_view.queue_redraw()


# ---------------------------------------------------------------------
# ДАННЫЕ (отдельно от рисования — их проверяют тесты)
# ---------------------------------------------------------------------
func hero_actor() -> Actor:
	if game == null or game.get("cast") == null or game.cast.hero.is_empty():
		return null
	return game.cast.hero["actor"]


## Показатели героя: [{key, value, max, low}]; пусто, если героя нет
func stats() -> Array:
	var out: Array = []
	var a: Actor = hero_actor()
	if a == null:
		return out
	for k in KEYS:
		var v: float = float(a.res.get(k, 0.0))
		var mx: float = maxf(a.max_of(k), 1.0)
		var bad: bool = (v / mx > 0.25) if k == "radiation" else (v / mx < 0.25)
		out.append({"key": k, "value": int(v), "max": int(mx), "low": bad})
	return out


func is_night() -> bool:
	if game == null or game.get("physics") == null:
		return false
	return game.physics.sun_elevation_deg_at(deg_to_rad(game.MAP_LAT_DEG), 0.0) < 0.0


func time_text() -> String:
	if game == null or game.get("clock") == null:
		return "--:--"
	var h: float = game.clock.hour_of_day()
	var hh: int = int(h)
	return "%02d:%02d" % [hh, int((h - float(hh)) * 60.0)]


func date_text() -> String:
	if game == null or game.get("clock") == null:
		return ""
	return "%d %s %d" % [game.clock.day_of_month(), GameClock.MONTH_NAMES[game.clock.month()], game.clock.year()]


## Погода там, где герой (или центр экрана): ["wind", "rain", "snow"] — только то, что есть на самом деле
func weather_icons() -> Array:
	var out: Array = []
	if game == null or game.get("physics") == null:
		return out
	var p: Vector2 = game.cast.hero["pos"] if game.get("cast") != null and not game.cast.hero.is_empty() else game.cam_pos
	var w: Dictionary = game.physics.weather_here(p)
	if w.is_empty():
		return out
	var ty: String = String(w.get("type", ""))
	if ty == "snow":
		out.append("snow")
	elif ty == "rain" or ty == "storm" or float(w.get("rain_mm_h", 0.0)) > 0.0:
		out.append("rain")
	var wind: Variant = w.get("wind", Vector2.ZERO)
	if (wind is Vector2 and (wind as Vector2).length() >= WIND_STRONG) or ty == "storm":
		out.append("wind")
	return out


func bar_rect() -> Rect2:
	return Rect2(14.0, 10.0, CELL_W * KEYS.size() + 12.0, BAR_H)


func time_rect() -> Rect2:
	var b: Rect2 = bar_rect()
	var w: float = TIME_W + 34.0 * float(weather_icons().size())
	return Rect2(b.end.x + 10.0, b.position.y, w, BAR_H + (22.0 if show_date else 0.0))


func toggle_date() -> void:
	show_date = not show_date


# ---------------------------------------------------------------------
class _View extends Control:
	var bar: Node

	func _gui_input(_e: InputEvent) -> void:
		pass

	func _draw() -> void:
		if bar != null:
			bar._paint(self)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if time_rect().has_point(event.position):
			toggle_date()
			get_viewport().set_input_as_handled()


func _paint(ci: Control) -> void:
	var st: Array = stats()
	if not st.is_empty():
		var br: Rect2 = bar_rect()
		ComicUI.draw_box(ci, "button", br.grow(4.0))
		for i in st.size():
			var e: Dictionary = st[i]
			var cell := Rect2(br.position.x + 6.0 + CELL_W * i, br.position.y + 4.0, CELL_W - 4.0, BAR_H - 8.0)
			var k: String = String(e["key"])
			var frac: float = clampf(float(e["value"]) / float(e["max"]), 0.0, 1.0)
			ci.draw_rect(cell, Color(0.04, 0.04, 0.05, 0.6))
			var fill: Color = Color("5fc04a") if k == "health" else (Color("b46cf0") if k == "radiation" else Color("e0a040"))
			ci.draw_rect(Rect2(cell.position + Vector2(0, cell.size.y - 4.0), Vector2(cell.size.x * frac, 4.0)), Color(fill, 0.85))
			if bool(e["low"]):
				ci.draw_rect(cell, Color(0.43, 0.11, 0.09, 0.55))
				ci.draw_rect(cell, COL_BAD, false, 2.0)
			Inv.stat_icon(ci, k, Rect2(cell.position + Vector2(4.0, 3.0), Vector2(22.0, 22.0)))
			ci.draw_string_outline(_font, cell.position + Vector2(32.0, 22.0), str(e["value"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 19, 4, Color(0.05, 0.05, 0.07))
			ci.draw_string(_font, cell.position + Vector2(32.0, 22.0), str(e["value"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 19, COL_TEXT)
	var tr: Rect2 = time_rect()
	ComicUI.draw_box(ci, "button", tr.grow(4.0))
	var night: bool = is_night()
	var txt: String = time_text()
	ci.draw_string_outline(_font, tr.position + Vector2(14.0, 28.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 4, Color(0.05, 0.05, 0.07))
	ci.draw_string(_font, tr.position + Vector2(14.0, 28.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, COL_TEXT)
	var ix: float = tr.position.x + 96.0
	if night:
		moon_icon(ci, Vector2(ix + 14.0, tr.position.y + BAR_H * 0.5), 12.0)
	else:
		sun_icon(ci, Vector2(ix + 14.0, tr.position.y + BAR_H * 0.5), 12.0)
	ix += 38.0
	for w in weather_icons():
		weather_icon(ci, String(w), Vector2(ix + 14.0, tr.position.y + BAR_H * 0.5), 12.0)
		ix += 34.0
	if show_date:
		var d: String = date_text()
		ci.draw_string(_font, tr.position + Vector2(14.0, BAR_H + 12.0), d, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("c9a24b"))


# ---------------------------------------------------------------------
# ЗНАЧКИ
# ---------------------------------------------------------------------
static func sun_icon(ci: CanvasItem, o: Vector2, r: float) -> void:
	var c := Color("f0c040")
	ci.draw_circle(o, r * 0.55, c)
	for i in 8:
		var d := Vector2.from_angle(i * TAU / 8.0)
		ci.draw_line(o + d * r * 0.8, o + d * r * 1.1, c, 2.0, true)


static func moon_icon(ci: CanvasItem, o: Vector2, r: float) -> void:
	ci.draw_circle(o, r * 0.85, Color("d9dfee"))
	ci.draw_circle(o + Vector2(r * 0.45, -r * 0.2), r * 0.75, Color(0.1, 0.13, 0.2))


static func weather_icon(ci: CanvasItem, kind: String, o: Vector2, r: float) -> void:
	match kind:
		"rain":
			ci.draw_circle(o + Vector2(-r * 0.25, -r * 0.35), r * 0.45, Color("9aa8bd"))
			ci.draw_circle(o + Vector2(r * 0.3, -r * 0.3), r * 0.4, Color("9aa8bd"))
			for i in 3:
				var x: float = -r * 0.5 + r * 0.5 * i
				ci.draw_line(o + Vector2(x, r * 0.1), o + Vector2(x - r * 0.18, r * 0.75), Color("5aa8f0"), 2.0, true)
		"snow":
			ci.draw_circle(o + Vector2(-r * 0.25, -r * 0.35), r * 0.45, Color("b8c4d8"))
			ci.draw_circle(o + Vector2(r * 0.3, -r * 0.3), r * 0.4, Color("b8c4d8"))
			for i in 3:
				ci.draw_circle(o + Vector2(-r * 0.5 + r * 0.5 * i, r * (0.35 + 0.25 * (i % 2))), 2.0, Color("f2f6ff"))
		"wind":
			var c := Color("aab6c8")
			for i in 3:
				var y: float = -r * 0.5 + r * 0.5 * i
				ci.draw_line(o + Vector2(-r * 0.9, y), o + Vector2(r * (0.5 + 0.2 * (i % 2)), y), c, 2.0, true)
				ci.draw_arc(o + Vector2(r * (0.5 + 0.2 * (i % 2)), y - r * 0.18), r * 0.18, -PI * 0.5, PI * 0.8, 8, c, 2.0, true)

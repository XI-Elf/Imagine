extends Node2D
## Лошадь и повозка (вопрос Q16, Huzzah 2026-10-24): только транспорт — быстрее ехать и больше везти,
## в бою не участвуют. Владение — вещи horse и cart в сумке героя (Worlds.inventory, data/cities/items.json);
## лошадь продаёт торговка, повозку — кузнец, оба с этапа «Деревня». Повозке нужна лошадь (Trade.buy).
## R на карте — сесть верхом (с повозкой — на повозку) или спешиться; выбор — ключ ride в сумке,
## поэтому сохраняется вместе с ней. Пешком лошадь идёт в поводу и груз везёт всё равно.
## Каждый кадр: Actor.mount по выбору (в городе и в бою — пешком), Actor.pack_kg — сколько везут
## животные, Actor.carried_kg — вес сумки. Числа — data/characters/transport.json и movement.json пака.
## Рисуется под фигуркой героя (show_behind_parent): лошадь и повозка нарисованы кодом, картинок пока нет.

const R := preload("res://characters/actor_rules.gd")
const Trade := preload("res://city/trade.gd")

const INK := Color("1e1610")
const COAT := Color("7a4a2a")
const COAT_DARK := Color("4a2c18")
const WOOD := Color("8a6a42")
const WOOD_DARK := Color("5e4529")

var cast: Node2D
var hud: Label
var _face: float = 1.0          # 1 — смотрит вправо, -1 — влево
var _last_pos: Vector2 = Vector2.INF
var _moving: bool = false
var _t: float = 0.0


static func owns(bag: Dictionary, id: String) -> bool:
	return bag.has("items") and Trade.count(bag, id) > 0


## Сколько кг везут: лошадь — вьюки, повозка — ещё сверху; повозка без лошади стоит
static func pack_kg(bag: Dictionary) -> float:
	if not owns(bag, "horse"):
		return 0.0
	var t: Dictionary = R.transport()
	var kg: float = float(t.get("horse", {}).get("carry_kg", 0.0))
	if owns(bag, "cart"):
		kg += float(t.get("cart", {}).get("carry_kg", 0.0))
	return kg


## Как едет герой: "" пешком (лошадь в поводу), "horse" верхом, "cart" на повозке
static func mode(bag: Dictionary) -> String:
	if not owns(bag, "horse") or not bool(bag.get("ride", false)):
		return ""
	return "cart" if owns(bag, "cart") else "horse"


## Сесть или спешиться. Ответ: текст для игрока
static func toggle(bag: Dictionary) -> String:
	if not owns(bag, "horse"):
		return I18n.t("Лошади нет: её продаёт торговка в городе")
	bag["ride"] = not bool(bag.get("ride", false))
	match mode(bag):
		"horse":
			return I18n.t("Верхом")
		"cart":
			return I18n.t("На повозке")
	return I18n.t("Пешком, лошадь в поводу")


## Транспорт к герою: mount, груз животных, вес сумки. away — герой в городе или в бою: там пешком
static func apply(a: Actor, bag: Dictionary, away: bool) -> void:
	if a == null:
		return
	a.pack_kg = pack_kg(bag)
	if bag.has("items"):
		a.carried_kg = Trade.weight(bag)
	a.mount = "" if away or not a.alive else mode(bag)


func setup(c: Node2D) -> void:
	cast = c
	show_behind_parent = true
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	hud = Label.new()
	hud.add_theme_font_size_override("font_size", 14)
	hud.add_theme_color_override("font_color", Color("e9c66a"))
	hud.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	hud.add_theme_constant_override("outline_size", 4)
	layer.add_child(hud)


func _hero() -> Actor:
	return cast.hero["actor"] if cast != null and not cast.hero.is_empty() else null


func _bag() -> Dictionary:
	return cast._inventory() if cast != null else {}


func _process(delta: float) -> void:
	var a: Actor = _hero()
	if a == null:
		hud.text = ""
		_last_pos = Vector2.INF
		return
	var bag: Dictionary = _bag()
	apply(a, bag, bool(cast.hero_away))
	var p: Vector2 = cast.hero["pos"]
	_moving = _last_pos != Vector2.INF and p.distance_to(_last_pos) > 0.001
	if _moving and absf(p.x - _last_pos.x) > 0.0005:
		_face = signf(p.x - _last_pos.x)
	_last_pos = p
	_t += delta
	_update_hud(a, bag)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo or event.physical_keycode != KEY_R:
		return
	var g: Node = cast.game if cast != null else null
	if g == null or not g.ready_done or g.typing or g.menu_open or cast.get("_creator") != null:
		return
	var a: Actor = _hero()
	if a == null or not a.alive or cast.hero_away:
		return
	cast._event(toggle(_bag()))
	apply(a, _bag(), false)
	get_viewport().set_input_as_handled()


func _update_hud(a: Actor, bag: Dictionary) -> void:
	if not owns(bag, "horse") and not owns(bag, "cart") or cast.hero_away:
		hud.text = ""
		return
	var parts: PackedStringArray = []
	if owns(bag, "horse"):
		match a.mount:
			"horse":
				parts.append(I18n.t("Верхом"))
			"cart":
				parts.append(I18n.t("На повозке"))
			_:
				parts.append(I18n.t("Лошадь в поводу"))
	if owns(bag, "cart"):
		parts.append(I18n.t("повозка") if owns(bag, "horse") else I18n.t("повозка стоит: нет лошади"))
	parts.append(I18n.t("груз %.0f / %.0f кг") % [a.carried_kg, a.carry_capacity()])
	if owns(bag, "horse"):
		parts.append(I18n.t("R — спешиться") if a.mount != "" else I18n.t("R — сесть"))
	hud.text = "  ·  ".join(parts)
	hud.position = Vector2(14.0, get_viewport_rect().size.y - 56.0)


# =====================================================================
# РИСОВАНИЕ
# =====================================================================
# Высота фигурки героя в пикселях, как в cast._draw (вблизи — картинка, издали — кружок)
func _hero_px() -> float:
	var g: Node = cast.game
	var up: float = g.height_at(cast.hero["pos"]) / g.HEIGHT_MAX_M if g.has_method("height_at") else 0.0
	return clampf(1.9 * g.zoom, 16.0, 76.0) * (1.0 + up * 0.35)


## На сколько пикселей поднять фигурку героя (cast._draw): сидит в седле или на повозке
func rider_lift(hpx: float) -> float:
	var a: Actor = _hero()
	if a == null or cast.hero_away or cast.game.zoom <= 3.0:
		return 0.0
	match a.mount:
		"horse":
			return hpx / 1.9 * 0.5
		"cart":
			return hpx / 1.9 * 0.45
	return 0.0


func _draw() -> void:
	var a: Actor = _hero()
	if a == null or cast.hero_away or not a.alive:
		return
	var bag: Dictionary = _bag()
	var horse: bool = owns(bag, "horse")
	var cart: bool = owns(bag, "cart") and horse
	if not horse:
		return
	var g: Node = cast.game
	var sp: Vector2 = g.world_to_screen(cast.hero["pos"])
	if not get_viewport_rect().grow(200.0).has_point(sp):
		return
	if g.zoom <= 3.0:
		# Издали: бурая точка лошади за кружком героя, повозка — квадратик
		var r: float = clampf(0.6 * g.zoom, 4.0, 14.0)
		var hp: Vector2 = sp + Vector2(-_face * r * 1.3, -r * 0.3)
		if cart:
			var cp: Vector2 = hp + Vector2(-_face * r * 1.6, 0)
			draw_rect(Rect2(cp - Vector2(r, r) * 0.7, Vector2(r, r) * 1.4), WOOD)
			draw_rect(Rect2(cp - Vector2(r, r) * 0.7, Vector2(r, r) * 1.4), INK, false, 1.0)
		draw_circle(hp, r * 0.95, INK)
		draw_circle(hp, r * 0.8, COAT)
		return
	var m: float = _hero_px() / 1.9      # пикселей на метр у фигурки героя
	var ground: Vector2 = sp
	var horse_at: Vector2
	var cart_at: Vector2
	match a.mount:
		"horse":
			horse_at = ground
		"cart":
			# Герой на передке повозки, колесо видно за ним
			cart_at = ground + Vector2(-_face * 0.6 * m, 0)
			horse_at = cart_at + Vector2(_face * 2.0 * m, 0)
		_:
			# Пешком: лошадь в поводу за плечом, чуть дальше от глаза
			horse_at = ground + Vector2(-_face * 1.1 * m, -0.25 * m)
	if cart and a.mount != "cart":
		cart_at = horse_at + Vector2(-_face * 2.1 * m, 0)
	if cart:
		var fill: float = clampf(a.carried_kg / maxf(a.carry_capacity(), 1.0), 0.0, 1.0)
		_draw_cart(cart_at, m, fill, horse_at)
	_draw_horse(horse_at, m)


# Лошадь сбоку, мордой по _face; p — земля под серединой брюха, m — пикселей на метр
func _draw_horse(p: Vector2, m: float) -> void:
	var lw: float = maxf(1.0, m * 0.04)
	draw_set_transform(p + Vector2(0, 1.5), 0.0, Vector2(1, 0.28))
	draw_circle(Vector2.ZERO, m * 0.95, Color(0.12, 0.10, 0.07, 0.22))
	draw_set_transform(p, 0.0, Vector2(_face * m, m))
	var step: float = sin(_t * 9.0) * 0.12 if _moving else 0.0
	for leg in [[-0.62, step], [-0.48, -step], [0.5, -step], [0.64, step]]:
		var x: float = leg[0]
		var sw: float = leg[1]
		var c: Color = COAT_DARK if x in [-0.48, 0.64] else COAT_DARK.darkened(0.25)
		draw_line(Vector2(x, -0.85), Vector2(x + sw, -0.05), c, 0.13)
		draw_line(Vector2(x + sw - 0.07, -0.03), Vector2(x + sw + 0.08, -0.03), INK, 0.08)
	var body := _ellipse(Vector2(0, -1.08), 0.86, 0.34)
	draw_colored_polygon(body, COAT)
	draw_polyline(body, INK, lw / m)
	var neck := PackedVector2Array([Vector2(0.52, -1.28), Vector2(0.86, -1.02), Vector2(1.12, -1.62), Vector2(0.9, -1.8)])
	draw_colored_polygon(neck, COAT)
	var head := PackedVector2Array([Vector2(0.88, -1.78), Vector2(1.08, -1.86), Vector2(1.5, -1.5), Vector2(1.42, -1.38), Vector2(1.06, -1.5)])
	draw_colored_polygon(head, COAT)
	draw_polyline(head + PackedVector2Array([head[0]]), INK, lw / m)
	draw_line(Vector2(0.86, -1.02), Vector2(1.08, -1.52), INK, lw / m)
	draw_line(Vector2(0.52, -1.3), Vector2(0.9, -1.8), COAT_DARK.darkened(0.4), 0.09)   # грива
	draw_colored_polygon(PackedVector2Array([Vector2(0.98, -1.84), Vector2(1.02, -2.0), Vector2(1.1, -1.84)]), COAT_DARK)
	draw_circle(Vector2(1.18, -1.66), 0.035, INK)
	var sway: float = sin(_t * 4.0) * 0.05 if _moving else 0.0
	draw_polyline(PackedVector2Array([Vector2(-0.84, -1.2), Vector2(-1.0 + sway, -0.95), Vector2(-1.02 + sway, -0.6)]), COAT_DARK.darkened(0.4), 0.1)
	# Седло и вьюки
	draw_colored_polygon(_ellipse(Vector2(0.05, -1.4), 0.3, 0.08), Color("3a2a1c"))
	draw_rect(Rect2(Vector2(-0.38, -1.3), Vector2(0.3, 0.32)), Color("8c7a52"))
	draw_rect(Rect2(Vector2(-0.38, -1.3), Vector2(0.3, 0.32)), INK, false, lw / m)
	draw_set_transform(Vector2.ZERO)


# Повозка сбоку: короб на одном видимом колесе, оглобли к лошади, сверху груз по заполнению fill
func _draw_cart(p: Vector2, m: float, fill: float, horse_at: Vector2) -> void:
	var lw: float = maxf(1.0, m * 0.04)
	draw_set_transform(p + Vector2(0, 1.5), 0.0, Vector2(1, 0.28))
	draw_circle(Vector2.ZERO, m * 1.0, Color(0.12, 0.10, 0.07, 0.22))
	draw_set_transform(p, 0.0, Vector2(_face * m, m))
	# Оглобли до груди лошади
	var reach: float = (horse_at.x - p.x) / (_face * m)
	draw_line(Vector2(0.9, -0.78), Vector2(reach + 0.55, -1.12), WOOD_DARK, 0.07)
	var lumps: int = int(ceil(fill * 4.0))
	for i in lumps:
		var x: float = -0.7 + i * 0.42
		draw_colored_polygon(_ellipse(Vector2(x, -1.12), 0.24, 0.17), [Color("9a7048"), Color("6e7a87"), Color("b8a27a"), Color("7a5a3a")][i % 4])
	draw_rect(Rect2(Vector2(-0.95, -1.05), Vector2(1.9, 0.6)), WOOD)
	for k in 3:
		draw_line(Vector2(-0.95, -0.85 + k * 0.2), Vector2(0.95, -0.85 + k * 0.2), WOOD_DARK, lw / m)
	draw_rect(Rect2(Vector2(-0.95, -1.05), Vector2(1.9, 0.6)), INK, false, lw / m)
	var spin: float = _t * 3.0 if _moving else 0.0
	var hub := Vector2(0.0, -0.42)
	draw_circle(hub, 0.42, INK)
	draw_circle(hub, 0.35, WOOD_DARK)
	for k in 6:
		var ang: float = spin + TAU * k / 6.0
		draw_line(hub, hub + Vector2.from_angle(ang) * 0.36, WOOD, 0.05)
	draw_circle(hub, 0.07, INK)
	draw_set_transform(Vector2.ZERO)


static func _ellipse(c: Vector2, rx: float, ry: float, n: int = 20) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n + 1:
		var t: float = TAU * i / n
		pts.append(c + Vector2(cos(t) * rx, sin(t) * ry))
	return pts

extends Control
## Вкладка «Инвентарь» окна героя (референсы Huzzah 2026-10-23, гамма «синий мрамор»):
## сверху строка показателей героя значками (здоровье, сытость, вода, энергия, силы, радиация) и деньги;
## ниже «По типу» / «Бросить всё» и груз N/M; слева фильтры по виду вещей, в середине сумка крупными
## ячейками (значок, число в углу, значок вида) с листанием страниц, под ней выбранная вещь и её кнопки;
## справа кукла героя (paper_doll.gd): слоты одежды по бокам, фигура в надетом (без одежды — майка
## и короткие бриджи), внизу 3 оружия «в бой» и доспех боя.
## Рисуется кодом, мрамор — шум FastNoiseLite (одна текстура на игру).
## Состояние (выбор, фильтр, страница, сортировка) и действия — у окна hero_window.gd.

const Doll := preload("res://characters/paper_doll.gd")
const Icons := preload("res://battle/battle_icons.gd")
const Trade := preload("res://city/trade.gd")

const INK := Color("0c1626")
const MARBLE_DARK := Color("1a2d4d")
const MARBLE := Color("2c4a7a")
const MARBLE_VEIN := Color("a9bfdc")
const MARBLE_LIGHT := Color("c7d4e4")
const MARBLE_LIGHT2 := Color("9fb3cc")
const MARBLE_LIGHT_VEIN := Color("eef3f9")
const EDGE := Color("6f8cb6")
const TEXT := Color("e8eef7")
const DIM := Color("9fb0c8")
const GOLD := Color("e9c66a")
const RED := Color("c4413a")
const RED_DARK := Color("6e1c18")

## Фильтры слева: id, подпись, виды вещей
const FILTERS: Array = [["all", "Всё"], ["food", "Провизия"], ["med", "Медицина"], ["gear", "Снаряжение"],
	["tools", "Инструменты"], ["weapon", "Оружие"], ["parts", "Компоненты"], ["misc", "Прочее"]]
const CAT_ORDER: Array = ["food", "med", "weapon", "gear", "tools", "parts", "misc"]
const TOOLS: Array = ["rope"]
const PARTS: Array = ["scrap", "hide"]
const STAT_KEYS: Array = ["health", "hunger", "thirst", "energy", "stamina", "radiation"]
const STAT_NAMES: Dictionary = {"health": "Здоровье", "hunger": "Сытость", "thirst": "Вода", "energy": "Энергия", "stamina": "Силы", "radiation": "Радиация"}

const W := 900.0
const FILT := Rect2(0.0, 98.0, 140.0, 416.0)
const GRID := Vector2(152.0, 98.0)
const CELL := 74.0
const GAP := 4.0
const COLS := 5
const ROWS := 4
const DOLL := Rect2(560.0, 98.0, 340.0, 424.0)
const H := 524.0

static var _tex: Dictionary = {}

var win: Node                      # hero_window.gd
var actor: Actor
var bag: Dictionary = {}
var weapons: Dictionary = {}       # предмет -> оружие боя (config.item_weapons)
var armor: Resource = null         # доспех героя в бою (config.hero.armor)
var loadout_max: int = 3
var _hits: Array = []              # [Rect2, тип, id]
var _hover: int = -1
var _font: Font
var _wicons: Dictionary = {}
var _doll := Doll.new()


func setup(window: Node, a: Actor, b: Dictionary, item_weapons: Dictionary, lmax: int, arm: Resource) -> void:
	win = window
	actor = a
	bag = b
	weapons = item_weapons
	loadout_max = lmax
	armor = arm
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = ThemeDB.fallback_font
	custom_minimum_size = Vector2(W, H)
	_layout()


# =====================================================================
# ДАННЫЕ
# =====================================================================
func _w(key: String, def: Variant) -> Variant:
	var v: Variant = win.get(key) if win != null else null
	return def if v == null else v


func _sel() -> String:
	var s: String = String(_w("inv_sel", ""))
	return s if Trade.count(bag, s) > 0 else ""


func kind_of(id: String) -> String:
	var u: Dictionary = Trade.item(id).get("use", {})
	if u.has("eat"):
		return "еда"
	if u.has("drink"):
		return "питьё"
	if bool(Trade.item(id).get("treat", false)):
		return "лечение"
	if weapons.has(id):
		return "оружие"
	if is_wear(id):
		return "одежда"
	return "вещь"


## Вид вещи для фильтров: food, med, weapon, gear, tools, parts, misc
static func cat_of(id: String, item_weapons: Dictionary) -> String:
	var it: Dictionary = Trade.item(id)
	var u: Dictionary = it.get("use", {})
	if u.has("eat") or u.has("drink"):
		return "food"
	if bool(it.get("treat", false)):
		return "med"
	if item_weapons.has(id):
		return "weapon"
	if it.has("wear"):
		return "gear"
	if TOOLS.has(id):
		return "tools"
	if PARTS.has(id):
		return "parts"
	return "misc"


## Вещи в текущем фильтре; «По типу» — по виду, потом по имени
func shown_items() -> Array:
	var f: String = String(_w("inv_filter", "all"))
	var out: Array = []
	for id in bag.get("items", {}).keys():
		if Trade.count(bag, id) > 0 and (f == "all" or cat_of(id, weapons) == f):
			out.append(id)
	if bool(_w("inv_sort", false)):
		out.sort_custom(func(a, b):
			var ca: int = CAT_ORDER.find(cat_of(a, weapons))
			var cb: int = CAT_ORDER.find(cat_of(b, weapons))
			return ca < cb if ca != cb else Trade.item_name(a) < Trade.item_name(b))
	return out


func is_wear(id: String) -> bool:
	return Trade.item(id).has("wear")


func equipped() -> Dictionary:
	return bag.get("equipped", {})


## Вид надетого для куклы: slot -> {look, color}
func looks() -> Dictionary:
	var out: Dictionary = {}
	for slot in equipped():
		if Trade.count(bag, String(equipped()[slot])) <= 0:
			continue
		var w: Dictionary = Trade.item(String(equipped()[slot])).get("wear", {})
		if not w.is_empty():
			out[slot] = {"look": String(w.get("look", "")), "color": Color(String(w.get("color", "777777")))}
	return out


func pages() -> int:
	return maxi(1, ceili(float(shown_items().size()) / float(COLS * ROWS)))


func _page() -> int:
	return clampi(int(_w("inv_page", 0)), 0, pages() - 1)


# =====================================================================
# РАЗМЕТКА: кнопки и места для клика
# =====================================================================
func _layout() -> void:
	for c in get_children():
		c.queue_free()
	_hits.clear()
	# По типу / Бросить всё
	var sort_b := _btn("По типу ✓" if bool(_w("inv_sort", false)) else "По типу", win.toggle_sort, 16)
	sort_b.position = Vector2(0, 52)
	sort_b.custom_minimum_size = Vector2(140, 36)
	add_child(sort_b)
	var drop_b := _btn("Точно? Ещё раз" if bool(_w("inv_drop_armed", false)) else "Бросить всё", win.drop_all, 16)
	drop_b.position = Vector2(152, 52)
	drop_b.custom_minimum_size = Vector2(160, 36)
	drop_b.tooltip_text = "Выбросить все вещи из выбранного фильтра (деньги остаются)"
	add_child(drop_b)
	# фильтры
	var f: String = String(_w("inv_filter", "all"))
	for i in FILTERS.size():
		var b := _btn(FILTERS[i][1], win.set_filter.bind(FILTERS[i][0]), 16, FILTERS[i][0] == f)
		b.position = Vector2(FILT.position.x, FILT.position.y + i * 52.0)
		b.custom_minimum_size = Vector2(FILT.size.x, 46)
		add_child(b)
	# ячейки сумки на странице
	var items: Array = shown_items()
	var p0: int = _page() * COLS * ROWS
	for i in COLS * ROWS:
		var r := Rect2(GRID + Vector2((i % COLS) * (CELL + GAP), int(i / COLS) * (CELL + GAP)), Vector2(CELL, CELL))
		_hits.append([r, "cell", String(items[p0 + i]) if p0 + i < items.size() else ""])
	# листание
	var py: float = GRID.y + ROWS * (CELL + GAP) + 2.0
	var prev := _btn("◀", win.turn_page.bind(-1), 18)
	prev.position = Vector2(GRID.x, py)
	prev.custom_minimum_size = Vector2(54, 30)
	prev.disabled = _page() == 0
	add_child(prev)
	var next := _btn("▶", win.turn_page.bind(1), 18)
	next.position = Vector2(GRID.x + COLS * (CELL + GAP) - GAP - 54, py)
	next.custom_minimum_size = Vector2(54, 30)
	next.disabled = _page() >= pages() - 1
	add_child(next)
	# слоты одежды по бокам куклы: слева голова, тело, плащ; справа руки, ноги, обувь
	var eq: Dictionary = equipped()
	for i in Doll.SLOTS.size():
		var x: float = DOLL.position.x + 10.0 if i < 3 else DOLL.end.x - 72.0
		var r := Rect2(x, DOLL.position.y + 40.0 + (i % 3) * 92.0, 62, 62)
		_hits.append([r, "equip", String(eq.get(Doll.SLOTS[i][0], "")), Doll.SLOTS[i][0]])
	# внизу: оружие в бой и доспех
	var lo: Array = bag.get("battle_loadout", [])
	var bx: float = DOLL.get_center().x - (loadout_max + 1) * 64.0 * 0.5 + 4.0
	for i in loadout_max:
		_hits.append([Rect2(bx + i * 64.0, DOLL.end.y - 66, 56, 56), "weapon", String(lo[i]) if i < lo.size() else ""])
	_hits.append([Rect2(bx + loadout_max * 64.0, DOLL.end.y - 66, 56, 56), "armor", ""])
	# кнопки выбранной вещи
	var s: String = _sel()
	if s != "":
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.position = Vector2(GRID.x + 180, py + 44)
		add_child(row)
		var k: String = kind_of(s)
		if is_wear(s):
			var on: bool = equipped().values().has(s)
			row.add_child(_btn("Снять" if on else "Надеть", (win.unequip_item if on else win.equip_item).bind(s), 14))
		if k == "еда" or k == "питьё":
			row.add_child(_btn("Съесть" if k == "еда" else "Выпить", win.use_item.bind(s), 14))
		if weapons.has(s):
			var b := _btn("В бою ✓" if lo.has(s) else "В бой", win.toggle_loadout.bind(s), 14)
			b.tooltip_text = "До %d видов оружия; окно «Подготовка к бою» предложит этот выбор" % loadout_max
			row.add_child(b)
		row.add_child(_btn("Выбросить", win.drop_item.bind(s), 14))
	queue_redraw()


func _btn(text: String, cb: Callable, size_px: int, on: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size_px)
	b.add_theme_color_override("font_color", INK if on else TEXT)
	b.add_theme_color_override("font_hover_color", INK if on else Color.WHITE)
	b.add_theme_color_override("font_pressed_color", INK)
	b.add_theme_color_override("font_disabled_color", Color(DIM, 0.4))
	b.add_theme_constant_override("outline_size", 0 if on else 3)
	b.add_theme_color_override("font_outline_color", INK)
	for n in ["normal", "hover", "pressed", "disabled"]:
		var light: bool = on or n == "pressed"
		b.add_theme_stylebox_override(n, marble_box(light, n == "hover", n == "disabled"))
	b.pressed.connect(cb)
	return b


## Плита из мрамора с тёмной кромкой и светлой фаской — для кнопок
static func marble_box(light: bool, hover: bool = false, dim: bool = false) -> StyleBoxTexture:
	var st := StyleBoxTexture.new()
	st.texture = marble(light)
	st.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	st.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	st.modulate_color = Color(1.25, 1.25, 1.3) if hover else (Color(0.6, 0.6, 0.65) if dim else Color.WHITE)
	st.content_margin_left = 10.0
	st.content_margin_right = 10.0
	st.content_margin_top = 4.0
	st.content_margin_bottom = 4.0
	return st


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h: int = _hit_at(event.position)
		if h != _hover:
			_hover = h
			tooltip_text = _tip(h)
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		var h: int = _hit_at(event.position)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN or event.button_index == MOUSE_BUTTON_WHEEL_UP:
			win.turn_page(1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1)
			accept_event()
			return
		if h < 0 or event.button_index != MOUSE_BUTTON_LEFT:
			return
		var id: String = _hits[h][2]
		if id != "":
			if event.double_click and kind_of(id) in ["еда", "питьё"]:
				win.use_item(id)
			else:
				win.inv_sel = id
				win.refresh_bag()
		accept_event()


func _hit_at(p: Vector2) -> int:
	for i in _hits.size():
		if (_hits[i][0] as Rect2).has_point(p):
			return i
	return -1


func _tip(h: int) -> String:
	if h < 0:
		return ""
	var e: Array = _hits[h]
	match e[1]:
		"armor":
			return "Доспех в бою: %s" % (String(armor.get("title")) if armor != null else "нет")
		"weapon":
			return "Оружие в бой: %s" % Trade.item_name(e[2]) if e[2] != "" else "Пусто. Выберите оружие в сумке и нажмите «В бой»"
		"equip":
			var nm: String = ""
			for sl in Doll.SLOTS:
				if sl[0] == e[3]:
					nm = sl[1]
			return "%s: %s" % [nm, Trade.item_name(e[2])] if e[2] != "" else "%s: пусто. Выберите одежду в сумке и нажмите «Надеть»" % nm
		"cell":
			return "%s ×%d · двойной клик — съесть/выпить" % [Trade.item_name(e[2]), Trade.count(bag, e[2])] if e[2] != "" and kind_of(e[2]) in ["еда", "питьё"] else ("%s ×%d" % [Trade.item_name(e[2]), Trade.count(bag, e[2])] if e[2] != "" else "")
	return ""


# =====================================================================
# РИСОВАНИЕ
# =====================================================================
func _draw() -> void:
	_draw_stats()
	_draw_weight()
	_panel_rect(Rect2(GRID - Vector2(6, 6), Vector2(COLS * (CELL + GAP) + 8, H - GRID.y + 6)), false)
	_panel_rect(DOLL, true)
	_draw_doll()
	for i in _hits.size():
		var e: Array = _hits[i]
		var r: Rect2 = e[0]
		var sel: bool = e[2] != "" and e[2] == _sel()
		cell(self, r, i == _hover, sel, cat_of(e[2], weapons) if e[2] != "" else "")
		if e[2] != "":
			item_icon(e[2], r.grow(-12.0))
		match e[1]:
			"armor":
				_armor_icon(Rect2(r.position + Vector2(16, 8), Vector2(r.size.x - 32, r.size.y - 26)))
				_text_c(Vector2(r.get_center().x, r.end.y - 6), String(armor.get("title")) if armor != null else "без доспеха", 11, INK)
			"weapon":
				if e[2] == "":
					_text_c(Vector2(r.get_center().x, r.get_center().y + 5), "пусто", 11, Color(INK, 0.5))
				_text(r.position + Vector2(5, r.size.y - 5), str(i - COLS * ROWS - Doll.SLOTS.size() + 1), 10, Color(INK, 0.6))
			"equip":
				if e[2] == "":
					for sl in Doll.SLOTS:
						if sl[0] == e[3]:
							_text_c(Vector2(r.get_center().x, r.get_center().y + 5), sl[1], 12, Color(INK, 0.45))
			"cell":
				if e[2] != "":
					_badge(e[2], Rect2(r.position + Vector2(4, 4), Vector2(16, 16)))
					var n: int = Trade.count(bag, e[2])
					_text_r(r.end - Vector2(6, 6), str(n), 17, TEXT, true)
					if equipped().values().has(e[2]):
						_text(r.position + Vector2(5, r.size.y - 6), "надето", 11, Color("2e6a2e"))
	var py: float = GRID.y + ROWS * (CELL + GAP) + 2.0
	_text_c(Vector2(GRID.x + (COLS * (CELL + GAP) - GAP) * 0.5, py + 22), "%d/%d" % [_page() + 1, pages()], 18, TEXT, true)
	if shown_items().is_empty():
		_text_c(Vector2(GRID.x + (COLS * (CELL + GAP)) * 0.5, GRID.y + CELL * 1.6), "Пусто" if String(_w("inv_filter", "all")) != "all" else "Сумка пуста. Купите в Чёрнославле или найдите в тайниках", 14, INK, false)
	_draw_details(py + 40)


## Строка показателей героя значками (то, что раньше было только внизу экрана)
func _draw_stats() -> void:
	var bar := Rect2(0, 0, W, 42)
	_panel_rect(bar, false)
	if actor == null:
		return
	var x: float = 14.0
	for k in STAT_KEYS:
		var v: float = float(actor.res.get(k, 0.0))
		var mx: float = maxf(actor.max_of(k), 1.0)
		var bad: bool = (v / mx > 0.25) if k == "radiation" else (v / mx < 0.25)
		var r := Rect2(x - 6, 5, 104, 32)
		if bad:
			draw_rect(r, Color(RED_DARK, 0.6))
			draw_rect(r, RED, false, 2.0)
		stat_icon(self, k, Rect2(x, 9, 24, 24))
		_text(Vector2(x + 30, 30), str(int(v)), 20, TEXT, true)
		x += 112.0
	# деньги справа
	var money: String = str(int(bag.get("money", 0)))
	_text_r(Vector2(W - 12, 30), money, 20, GOLD, true)
	var mw: float = _font.get_string_size(money, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	coin(self, Vector2(W - 28 - mw, 21), 10.0)


func _draw_weight() -> void:
	var w: float = Trade.weight(bag)
	var cap: float = actor.carry_capacity() if actor != null else 0.0
	var s: String = "%.1f/%.0f кг" % [w, cap]
	_text_r(Vector2(W - 8, 78), s, 20, RED if w > cap else GOLD, true)
	var sw: float = _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	weight_icon(self, Rect2(W - 40 - sw, 56, 26, 26), GOLD)


## Подложка: мраморная плита с кромкой (тёмная или светлая)
func _panel_rect(r: Rect2, light: bool) -> void:
	draw_texture_rect(marble(light), r, true)
	draw_rect(r, INK, false, 3.0)
	draw_rect(r.grow(-3.0), Color(EDGE, 0.55), false, 1.0)


func _draw_doll() -> void:
	var p: Rect2 = DOLL
	_text(p.position + Vector2(12, 26), "Снаряжение", 17, TEXT, true)
	if actor != null:
		_text_r(Vector2(p.end.x - 12, p.position.y + 26), actor.display_name, 17, GOLD, true)
	var female: bool = actor != null and String(actor.profile.get("gender", "")) in ["female", "f", "woman"]
	var fig := Rect2(p.position.x + 78, p.position.y + 34, p.size.x - 156, p.size.y - 112)
	var foot := Vector2(fig.get_center().x, fig.end.y - 2.0)
	draw_set_transform(foot, 0.0, Vector2(1.0, 0.25))
	draw_circle(Vector2.ZERO, 48.0, Color(0.05, 0.1, 0.2, 0.3))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_doll.draw(self, fig, female, looks())


func _draw_details(y: float) -> void:
	var s: String = _sel()
	if s == "":
		_text(Vector2(GRID.x, y + 20), "Клик — выбрать вещь", 13, DIM)
		return
	var it: Dictionary = Trade.item(s)
	var n: int = Trade.count(bag, s)
	_text(Vector2(GRID.x, y + 18), "%s ×%d" % [Trade.item_name(s), n], 16, TEXT, true)
	var info: String = kind_of(s)
	var u: Dictionary = it.get("use", {})
	if u.has("eat"):
		info += " · сытость +%d" % int(u["eat"])
	elif u.has("drink"):
		info += " · вода +%d" % int(u["drink"])
	if weapons.has(s):
		info += " · " + ("в бою" if bag.get("battle_loadout", []).has(s) else "не в бою")
	_text(Vector2(GRID.x, y + 38), info, 13, DIM)
	_text(Vector2(GRID.x, y + 56), "%.1f кг · %d мон. за шт." % [float(it.get("weight", 0.0)) * n, int(it.get("price", 0))], 13, DIM)


func _text(p: Vector2, s: String, size_px: int, col: Color, outline: bool = false) -> void:
	if outline:
		draw_string_outline(_font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, 4, INK)
	draw_string(_font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, col)


func _text_c(p: Vector2, s: String, size_px: int, col: Color, outline: bool = false) -> void:
	var w: float = _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	_text(p - Vector2(w * 0.5, 0), s, size_px, col, outline)


func _text_r(p: Vector2, s: String, size_px: int, col: Color, outline: bool = false) -> void:
	var w: float = _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	_text(p - Vector2(w, 0), s, size_px, col, outline)


# =====================================================================
# МРАМОР И ДЕТАЛИ ОФОРМЛЕНИЯ (общие с рамкой окна)
# =====================================================================
## Бесшовная текстура мрамора: тёмно-синий со светлыми прожилками или светлый серо-голубой
static func marble(light: bool) -> Texture2D:
	var key: String = "light" if light else "dark"
	if _tex.has(key):
		return _tex[key]
	var nz := FastNoiseLite.new()
	nz.seed = 77 if light else 1488
	nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nz.frequency = 0.012
	nz.fractal_type = FastNoiseLite.FRACTAL_FBM
	nz.fractal_octaves = 5
	var src: Image = nz.get_seamless_image(256, 256)
	var img := Image.create(256, 256, false, Image.FORMAT_RGB8)
	var a: Color = MARBLE_LIGHT if light else MARBLE_DARK
	var b: Color = MARBLE_LIGHT2 if light else MARBLE
	var vc: Color = MARBLE_LIGHT_VEIN if light else MARBLE_VEIN
	for y in 256:
		for x in 256:
			var n: float = src.get_pixel(x, y).r
			var c: Color = a.lerp(b, smoothstep(0.3, 0.7, n))
			# прожилки: волна по диагонали, искривлённая шумом (период 256 — текстура бесшовная)
			var ph: float = TAU * float(x + y) / 256.0 * 2.0 + n * 11.0
			var vein: float = pow(1.0 - absf(sin(ph)), 22.0)
			var fine: float = pow(1.0 - absf(sin(TAU * float(x - y) / 256.0 * 3.0 + n * 17.0)), 40.0) * 0.45
			img.set_pixel(x, y, c.lerp(vc, clampf(vein * (0.6 if light else 0.8) + fine, 0.0, 1.0)))
	_tex[key] = ImageTexture.create_from_image(img)
	return _tex[key]


static func rivet(ci: CanvasItem, c: Vector2, r: float = 3.5) -> void:
	ci.draw_circle(c + Vector2(0.8, 1.2), r, Color(0, 0, 0, 0.5))
	ci.draw_circle(c, r, Color("8796ab"))
	ci.draw_circle(c - Vector2(r, r) * 0.3, r * 0.45, Color("e6edf6"))


## Ячейка: светлый мрамор, тёмная кромка, лёгкий оттенок вида вещи, выбранная — золотая рамка
func cell(ci: CanvasItem, r: Rect2, hover: bool, sel: bool, cat: String) -> void:
	ci.draw_texture_rect(marble(true), r, true, Color(1.12, 1.12, 1.15) if hover else Color.WHITE)
	var tint: Dictionary = {"food": Color(0.85, 0.6, 0.2, 0.14), "med": Color(0.3, 0.8, 0.3, 0.12), "weapon": Color(0.8, 0.25, 0.2, 0.12),
		"tools": Color(0.5, 0.4, 0.3, 0.12), "gear": Color(0.3, 0.45, 0.8, 0.12), "parts": Color(0.3, 0.3, 0.3, 0.12)}
	if tint.has(cat):
		ci.draw_rect(r, tint[cat])
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 4)), Color(0, 0, 0, 0.15))
	ci.draw_rect(r, INK, false, 2.0)
	if sel:
		ci.draw_rect(r.grow(-2.0), GOLD, false, 3.0)


## Значок вида в левом верхнем углу ячейки, как на референсе
func _badge(id: String, r: Rect2) -> void:
	match cat_of(id, weapons):
		"food":
			stat_icon(self, "thirst" if Trade.item(id).get("use", {}).has("drink") else "hunger", r)
		"med":
			stat_icon(self, "health", r)
		"weapon":
			Icons.weapon(self, "sword", r)


static func coin(ci: CanvasItem, c: Vector2, r: float) -> void:
	ci.draw_circle(c, r, Color("8a6326"))
	ci.draw_circle(c, r * 0.8, GOLD)
	ci.draw_circle(c, r * 0.4, Color("b08a3c"))


static func weight_icon(ci: CanvasItem, r: Rect2, col: Color) -> void:
	var c: Vector2 = r.get_center()
	var s: float = r.size.x * 0.5
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-0.55, -0.2) * s, c + Vector2(0.55, -0.2) * s, c + Vector2(0.9, 0.8) * s, c + Vector2(-0.9, 0.8) * s]), col)
	ci.draw_arc(c + Vector2(0, -0.45) * s, s * 0.32, PI, TAU, 10, col, maxf(2.0, s * 0.18))


## Значки показателей: крест, вилка с ножом, капля, молния, бегун, знак радиации
static func stat_icon(ci: CanvasItem, k: String, r: Rect2) -> void:
	var o: Vector2 = r.get_center()
	var s: float = minf(r.size.x, r.size.y) * 0.5
	match k:
		"health":
			var g := Color("5fc04a")
			ci.draw_rect(Rect2(o - Vector2(0.3, 0.85) * s, Vector2(0.6, 1.7) * s), g)
			ci.draw_rect(Rect2(o - Vector2(0.85, 0.3) * s, Vector2(1.7, 0.6) * s), g)
		"hunger":
			var c := Color("f0a030")
			ci.draw_rect(Rect2(o + Vector2(-0.75, -0.85) * s, Vector2(0.18, 0.7) * s), c)
			ci.draw_rect(Rect2(o + Vector2(-0.45, -0.85) * s, Vector2(0.18, 0.7) * s), c)
			ci.draw_rect(Rect2(o + Vector2(-0.75, -0.25) * s, Vector2(0.48, 0.2) * s), c)
			ci.draw_rect(Rect2(o + Vector2(-0.6, -0.1) * s, Vector2(0.2, 0.95) * s), c)
			ci.draw_colored_polygon(PackedVector2Array([o + Vector2(0.2, -0.85) * s, o + Vector2(0.65, -0.6) * s, o + Vector2(0.55, 0.1) * s, o + Vector2(0.45, 0.85) * s, o + Vector2(0.25, 0.85) * s, o + Vector2(0.3, 0.1) * s]), c)
		"thirst":
			var c := Color("5aa8f0")
			ci.draw_circle(o + Vector2(0, 0.3) * s, s * 0.5, c)
			ci.draw_colored_polygon(PackedVector2Array([o + Vector2(0, -0.9) * s, o + Vector2(0.47, 0.15) * s, o + Vector2(-0.47, 0.15) * s]), c)
			ci.draw_circle(o + Vector2(-0.18, 0.3) * s, s * 0.14, Color(1, 1, 1, 0.7))
		"energy":
			ci.draw_colored_polygon(PackedVector2Array([o + Vector2(0.25, -0.95) * s, o + Vector2(-0.55, 0.15) * s, o + Vector2(-0.05, 0.15) * s, o + Vector2(-0.3, 0.95) * s, o + Vector2(0.6, -0.2) * s, o + Vector2(0.08, -0.2) * s]), Color("e8e04a"))
		"stamina":
			Icons.action(ci, "dash", r, Color("e88a4a"))
		"radiation":
			var c := Color("d8d040")
			ci.draw_circle(o, s * 0.9, Color(0.1, 0.1, 0.05))
			for i in 3:
				var a0: float = -PI * 0.5 + i * TAU / 3.0 - 0.5
				var pts := PackedVector2Array([o + Vector2.from_angle(a0) * s * 0.25])
				for j in 7:
					pts.append(o + Vector2.from_angle(a0 + j / 6.0) * s * 0.8)
				pts.append(o + Vector2.from_angle(a0 + 1.0) * s * 0.25)
				ci.draw_colored_polygon(pts, c)
			ci.draw_circle(o, s * 0.14, c)


func _armor_icon(r: Rect2) -> void:
	var o: Vector2 = r.get_center()
	var s: float = minf(r.size.x, r.size.y) * 0.5
	var col: Color = Color("7a5232") if armor == null or String(armor.get("id")) in ["leather", "hides"] else Color("8d99a6")
	var body := PackedVector2Array()
	for p in [[-0.35, -0.75], [-0.12, -0.6], [0.12, -0.6], [0.35, -0.75], [0.75, -0.45], [0.55, -0.1], [0.42, -0.2], [0.42, 0.7], [-0.42, 0.7], [-0.42, -0.2], [-0.55, -0.1], [-0.75, -0.45]]:
		body.append(o + Vector2(p[0], p[1]) * s)
	draw_colored_polygon(body, col if armor != null else Color(col, 0.3))
	body.append(body[0])
	draw_polyline(body, INK, 2.0, true)
	draw_line(o + Vector2(-0.42, 0.25) * s, o + Vector2(0.42, 0.25) * s, INK, 2.0)


## Значок предмета: оружие — из иконок боя, остальное — простые рисунки по виду
func item_icon(id: String, r: Rect2) -> void:
	if weapons.has(id):
		if not _wicons.has(id):
			var path: String = "res://data/battle/weapons/%s.tres" % weapons[id]
			var wr: Resource = load(path) if ResourceLoader.exists(path) else null
			_wicons[id] = String(wr.get("icon")) if wr != null and wr.get("icon") != null else "knife"
		Icons.weapon(self, _wicons[id], r)
		return
	var o: Vector2 = r.get_center()
	var s: float = minf(r.size.x, r.size.y) * 0.5
	if is_wear(id):
		_wear_icon(Trade.item(id)["wear"], o, s)
		return
	match kind_of(id):
		"еда":
			if id == "stew":
				draw_arc(o + Vector2(0, -0.05) * s, s * 0.6, 0.0, PI, 16, INK, 3.0)
				draw_colored_polygon(_pts(o, s, [[-0.7, 0.0], [0.7, 0.0], [0.5, 0.55], [-0.5, 0.55]]), Color("6b4a2e"))
				draw_colored_polygon(_pts(o, s, [[-0.6, -0.05], [0.6, -0.05], [0.6, 0.08], [-0.6, 0.08]]), Color("c9873c"))
			elif id == "vegetables":
				draw_circle(o + Vector2(-0.25, 0.1) * s, s * 0.36, Color("b9502c"))
				draw_circle(o + Vector2(0.28, 0.2) * s, s * 0.3, Color("d8b34a"))
				draw_colored_polygon(_pts(o, s, [[-0.3, -0.3], [-0.1, -0.75], [0.0, -0.3]]), Color("4f7a34"))
			else:
				var c: Color = Color("c08a46") if id == "bread" else Color("7a3b2a")
				draw_colored_polygon(_pts(o, s, [[-0.75, 0.35], [-0.6, -0.2], [-0.2, -0.45], [0.3, -0.45], [0.7, -0.2], [0.78, 0.35]]), c)
				for i in 3:
					draw_line(o + Vector2(-0.4 + i * 0.35, -0.3) * s, o + Vector2(-0.25 + i * 0.35, 0.0) * s, c.darkened(0.35), 2.0)
		"питьё":
			if id == "ale":
				draw_colored_polygon(_pts(o, s, [[-0.45, -0.55], [0.35, -0.55], [0.35, 0.7], [-0.45, 0.7]]), Color("8a5a2c"))
				draw_colored_polygon(_pts(o, s, [[-0.5, -0.75], [0.4, -0.75], [0.4, -0.5], [-0.5, -0.5]]), Color("efe6d2"))
				draw_arc(o + Vector2(0.45, 0.05) * s, s * 0.25, -PI * 0.5, PI * 0.5, 8, INK, 3.0)
			else:
				draw_colored_polygon(_pts(o, s, [[-0.12, -0.8], [0.12, -0.8], [0.12, -0.5], [0.55, -0.25], [0.55, 0.65], [-0.55, 0.65], [-0.55, -0.25], [-0.12, -0.5]]), Color("8f6f48"))
				draw_colored_polygon(_pts(o, s, [[-0.45, 0.0], [0.45, 0.0], [0.45, 0.5], [-0.45, 0.5]]), Color("6d93b5"))
		"лечение":
			if id in ["bandage", "splint"]:
				draw_circle(o, s * 0.55, Color("efe6d2"))
				draw_circle(o, s * 0.18, Color("b9a67c"))
				draw_line(o + Vector2(0.4, 0.3) * s, o + Vector2(0.85, 0.75) * s, Color("efe6d2"), s * 0.3)
			else:
				Icons.action(self, "potion", r, Color("6f8a5a") if id in ["salve", "herbal_decoction", "charcoal"] else Color("8d99a6"))
		_:
			match id:
				"old_coin":
					coin(self, o, s * 0.55)
				"amber":
					draw_colored_polygon(_pts(o, s, [[0.0, -0.7], [0.55, -0.15], [0.35, 0.6], [-0.35, 0.6], [-0.55, -0.15]]), Color("e09a2c"))
					draw_colored_polygon(_pts(o, s, [[0.0, -0.45], [0.25, -0.1], [-0.15, 0.1]]), Color("f6d27a"))
				"rope":
					for k in 3:
						draw_arc(o, s * (0.25 + k * 0.17), 0.0, TAU, 20, Color("a58050"), 3.0)
				"scrap":
					draw_colored_polygon(_pts(o, s, [[-0.7, 0.2], [-0.2, -0.5], [0.6, -0.3], [0.7, 0.4], [-0.1, 0.6]]), Color("6e7a87"))
					draw_line(o + Vector2(-0.3, 0.1) * s, o + Vector2(0.4, -0.1) * s, Color(0.55, 0.3, 0.14, 0.7), 4.0)
				"hide":
					draw_colored_polygon(_pts(o, s, [[-0.6, -0.5], [0.0, -0.7], [0.6, -0.5], [0.7, 0.3], [0.3, 0.7], [-0.3, 0.7], [-0.7, 0.3]]), Color("9a7048"))
				_:
					draw_colored_polygon(_pts(o, s, [[-0.55, -0.3], [0.55, -0.3], [0.7, 0.65], [-0.7, 0.65]]), Color("8c6a44"))
					draw_colored_polygon(_pts(o, s, [[-0.3, -0.65], [0.3, -0.65], [0.2, -0.3], [-0.2, -0.3]]), Color("6e5034"))


## Значок одежды по виду (wear.look) и цвету
func _wear_icon(w: Dictionary, o: Vector2, s: float) -> void:
	var c := Color(String(w.get("color", "777777")))
	var shapes: Dictionary = {
		"straw_hat": [[[-0.85, 0.25], [-0.4, 0.05], [-0.3, -0.45], [0.3, -0.45], [0.4, 0.05], [0.85, 0.25], [0.5, 0.4], [-0.5, 0.4]]],
		"cap": [[[-0.6, 0.35], [-0.55, -0.15], [-0.25, -0.5], [0.25, -0.5], [0.55, -0.15], [0.6, 0.35]]],
		"shirt": [[[-0.3, -0.7], [0.3, -0.7], [0.8, -0.4], [0.6, 0.0], [0.4, -0.15], [0.4, 0.75], [-0.4, 0.75], [-0.4, -0.15], [-0.6, 0.0], [-0.8, -0.4]]],
		"jacket": [[[-0.3, -0.75], [0.3, -0.75], [0.85, -0.45], [0.8, 0.5], [0.5, 0.5], [0.45, 0.8], [-0.45, 0.8], [-0.5, 0.5], [-0.8, 0.5], [-0.85, -0.45]]],
		"cloak": [[[-0.3, -0.75], [0.3, -0.75], [0.6, 0.0], [0.8, 0.8], [-0.8, 0.8], [-0.6, 0.0]]],
		"gloves": [[[-0.75, -0.3], [-0.45, -0.6], [-0.1, -0.4], [-0.15, 0.4], [-0.6, 0.6], [-0.85, 0.2]], [[0.75, -0.3], [0.45, -0.6], [0.1, -0.4], [0.15, 0.4], [0.6, 0.6], [0.85, 0.2]]],
		"trousers": [[[-0.5, -0.75], [0.5, -0.75], [0.55, 0.8], [0.1, 0.8], [0.0, -0.2], [-0.1, 0.8], [-0.55, 0.8]]],
		"boots": [[[-0.75, -0.6], [-0.35, -0.6], [-0.35, 0.4], [-0.1, 0.5], [-0.1, 0.75], [-0.85, 0.75], [-0.75, 0.3]], [[0.15, -0.6], [0.55, -0.6], [0.55, 0.4], [0.8, 0.5], [0.8, 0.75], [0.05, 0.75], [0.15, 0.3]]]}
	for poly in shapes.get(String(w.get("look", "")), [[[-0.55, -0.3], [0.55, -0.3], [0.7, 0.65], [-0.7, 0.65]]]):
		var pts: PackedVector2Array = _pts(o, s, poly)
		draw_colored_polygon(pts, c)
		pts.append(pts[0])
		draw_polyline(pts, INK, 2.0, true)


func _pts(o: Vector2, s: float, a: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in a:
		out.append(o + Vector2(p[0], p[1]) * s)
	return out

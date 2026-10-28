extends Control
## Вкладка «Инвентарь» окна героя (референсы Huzzah 2026-10-23; с 2026-10-24 оформление комикса — Q24 A,
## тёмная сталь и уголь из ui/comic_ui.gd вместо «синего мрамора»):
## сверху строка показателей героя значками (здоровье, сытость, вода, энергия, силы, проклятье) и деньги;
## ниже «По типу» / «Бросить всё» и груз N/M; слева фильтры по виду вещей, в середине сумка крупными
## ячейками (значок, число в углу, значок вида) с листанием страниц, под ней выбранная вещь и её кнопки;
## справа кукла героя: слоты одежды по бокам, в середине силуэт фишки героя (art/storybook/traveler.png),
## внизу 3 оружия «в бой». Доспех в бою берётся из надетого на «Тело» (wear.armor), отдельного слота нет.
## Сумка — один сплошной лист без видимых клеток (сетка только для раскладки и клика).
## Рисуется кодом; рамки — nine-patch комикса (art/comic_ui). marble() оставлен для qa/render_doll.gd.
## Состояние (выбор, фильтр, страница, сортировка) и действия — у окна hero_window.gd.

const Doll := preload("res://characters/paper_doll.gd")
const Icons := preload("res://battle/battle_icons.gd")
const Trade := preload("res://city/trade.gd")
const ComicUI := preload("res://ui/comic_ui.gd")

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
const SHEET := Color(0.075, 0.072, 0.085)   # лист сумки (уголь чуть темнее панелей)

## Фильтры слева: id, подпись, виды вещей
static var FILTERS: Array = [["all", I18n.t("Всё")], ["food", I18n.t("Провизия")], ["med", I18n.t("Медицина")], ["gear", I18n.t("Снаряжение")],
	["tools", I18n.t("Инструменты")], ["weapon", I18n.t("Оружие")], ["parts", I18n.t("Компоненты")], ["misc", I18n.t("Прочее")]]
const CAT_ORDER: Array = ["food", "med", "weapon", "gear", "tools", "parts", "misc"]
const TOOLS: Array = ["rope"]
const PARTS: Array = ["scrap", "hide"]
const STAT_KEYS: Array = ["health", "hunger", "thirst", "energy", "stamina", "radiation"]
static var STAT_NAMES: Dictionary = {"health": I18n.t("Здоровье"), "hunger": I18n.t("Сытость"), "thirst": I18n.t("Вода"), "energy": I18n.t("Энергия"), "stamina": I18n.t("Силы"), "radiation": I18n.t("Воздействие проклятья")}
const PAWN := "res://art/storybook/traveler.png"

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
var armor: Resource = null         # доспех героя в бою: из надетого на «Тело» (wear.armor), иначе нет
var loadout_max: int = 3
var _hits: Array = []              # [Rect2, тип, id]
var _hover: int = -1
var _font: Font
var _wicons: Dictionary = {}


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
		return I18n.t("еда")
	if u.has("drink"):
		return I18n.t("питьё")
	if bool(Trade.item(id).get("treat", false)):
		return I18n.t("лечение")
	if weapons.has(id):
		return I18n.t("оружие")
	if is_wear(id):
		return I18n.t("одежда")
	return I18n.t("вещь")


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
		# Лошадь и повозка — не вещи в сумке: их видно на карте и в строке над героем (transport.gd)
		if Trade.count(bag, id) > 0 and not Trade.item(id).has("transport") and (f == "all" or cat_of(id, weapons) == f):
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
	var sort_b := _btn(I18n.t("По типу ✓") if bool(_w("inv_sort", false)) else I18n.t("По типу"), win.toggle_sort, 16)
	sort_b.position = Vector2(0, 52)
	sort_b.custom_minimum_size = Vector2(140, 36)
	add_child(sort_b)
	var drop_b := _btn(I18n.t("Точно? Ещё раз") if bool(_w("inv_drop_armed", false)) else I18n.t("Бросить всё"), win.drop_all, 16)
	drop_b.position = Vector2(152, 52)
	drop_b.custom_minimum_size = Vector2(160, 36)
	drop_b.tooltip_text = I18n.t("Выбросить все вещи из выбранного фильтра (деньги остаются)")
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
	# внизу: оружие в бой (доспех — то, что надето на «Тело»)
	var lo: Array = bag.get("battle_loadout", [])
	var bx: float = DOLL.get_center().x - loadout_max * 64.0 * 0.5 + 4.0
	for i in loadout_max:
		_hits.append([Rect2(bx + i * 64.0, DOLL.end.y - 66, 56, 56), "weapon", String(lo[i]) if i < lo.size() else ""])
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
			row.add_child(_btn(I18n.t("Снять") if on else I18n.t("Надеть"), (win.unequip_item if on else win.equip_item).bind(s), 14))
		if k == I18n.t("еда") or k == I18n.t("питьё"):
			row.add_child(_btn(I18n.t("Съесть") if k == I18n.t("еда") else I18n.t("Выпить"), win.use_item.bind(s), 14))
		if weapons.has(s):
			var b := _btn(I18n.t("В бою ✓") if lo.has(s) else I18n.t("В бой"), win.toggle_loadout.bind(s), 14)
			b.tooltip_text = I18n.t("До %d видов оружия; окно «Подготовка к бою» предложит этот выбор") % loadout_max
			row.add_child(b)
		row.add_child(_btn(I18n.t("Выбросить"), win.drop_item.bind(s), 14))
	queue_redraw()


## Кнопка — стальная табличка комикса; on (выбранный фильтр) — с янтарным отливом, как нажатая
func _btn(text: String, cb: Callable, size_px: int, on: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	ComicUI.button_styles(b, size_px)
	if on:
		b.add_theme_stylebox_override("normal", ComicUI.button_box("pressed"))
		b.add_theme_stylebox_override("hover", ComicUI.button_box("hover_pressed"))
		b.add_theme_color_override("font_color", Color("ffe2a8"))
	b.pressed.connect(cb)
	return b


## Стиль кнопки комикса (раньше — плита мрамора; имя оставлено для старых вызовов)
static func marble_box(light: bool, hover: bool = false, dim: bool = false) -> StyleBox:
	if dim:
		return ComicUI.button_box("disabled")
	if light:
		return ComicUI.button_box("hover_pressed" if hover else "pressed")
	return ComicUI.button_box("hover" if hover else "normal")


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
			if event.double_click and kind_of(id) in [I18n.t("еда"), I18n.t("питьё")]:
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
		"weapon":
			return I18n.t("Оружие в бой: %s") % Trade.item_name(e[2]) if e[2] != "" else I18n.t("Пусто. Выберите оружие в сумке и нажмите «В бой»")
		"equip":
			var nm: String = ""
			for sl in Doll.SLOTS:
				if sl[0] == e[3]:
					nm = sl[1]
			var tip: String = "%s: %s" % [nm, Trade.item_name(e[2])] if e[2] != "" else I18n.t("%s: пусто. Выберите одежду в сумке и нажмите «Надеть»") % nm
			if e[3] == "body":
				tip += I18n.t("\nДоспех в бою: %s") % (String(armor.get("title")) if armor != null else I18n.t("нет"))
			return tip
		"cell":
			return I18n.t("%s ×%d · двойной клик — съесть/выпить") % [Trade.item_name(e[2]), Trade.count(bag, e[2])] if e[2] != "" and kind_of(e[2]) in [I18n.t("еда"), I18n.t("питьё")] else ("%s ×%d" % [Trade.item_name(e[2]), Trade.count(bag, e[2])] if e[2] != "" else "")
	return ""


# =====================================================================
# РИСОВАНИЕ
# =====================================================================
func _draw() -> void:
	_draw_stats()
	_draw_weight()
	_panel_rect(Rect2(GRID - Vector2(6, 6), Vector2(COLS * (CELL + GAP) + 8, H - GRID.y + 6)), false)
	# сумка — один угольный лист, клетки не видны
	var sheet := Rect2(GRID, Vector2(COLS * (CELL + GAP) - GAP, ROWS * (CELL + GAP) - GAP))
	draw_rect(sheet, SHEET)
	draw_rect(sheet, Color(ComicUI.STEEL_HI, 0.45), false, 1.0)
	ComicUI.draw_box(self, "portrait", DOLL.grow(6.0))
	_draw_doll()
	for i in _hits.size():
		var e: Array = _hits[i]
		var r: Rect2 = e[0]
		var sel: bool = e[2] != "" and e[2] == _sel()
		if e[1] == "cell":
			sheet_mark(self, r, i == _hover and e[2] != "", sel)
		else:
			cell(self, r, i == _hover, sel, cat_of(e[2], weapons) if e[2] != "" else "")
		if e[2] != "":
			item_icon(e[2], r.grow(-12.0))
		match e[1]:
			"weapon":
				if e[2] == "":
					_text_c(Vector2(r.get_center().x, r.get_center().y + 5), I18n.t("пусто"), 11, Color(DIM, 0.6))
				_text(r.position + Vector2(9, r.size.y - 8), str(i - COLS * ROWS - Doll.SLOTS.size() + 1), 10, Color(DIM, 0.8))
			"equip":
				if e[2] == "":
					for sl in Doll.SLOTS:
						if sl[0] == e[3]:
							_text_c(Vector2(r.get_center().x, r.get_center().y + 5), sl[1], 12, Color(DIM, 0.6))
			"cell":
				if e[2] != "":
					_badge(e[2], Rect2(r.position + Vector2(4, 4), Vector2(16, 16)))
					var n: int = Trade.count(bag, e[2])
					_text_r(r.end - Vector2(6, 6), str(n), 17, TEXT, true)
					if equipped().values().has(e[2]):
						_text(r.position + Vector2(5, r.size.y - 6), I18n.t("надето"), 11, Color("8fd18a"), true)
	var py: float = GRID.y + ROWS * (CELL + GAP) + 2.0
	_text_c(Vector2(GRID.x + (COLS * (CELL + GAP) - GAP) * 0.5, py + 22), "%d/%d" % [_page() + 1, pages()], 18, TEXT, true)
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
	var s: String = I18n.t("%.1f/%.0f кг") % [w, cap]
	_text_r(Vector2(W - 8, 78), s, 20, RED if w > cap else GOLD, true)
	var sw: float = _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	weight_icon(self, Rect2(W - 40 - sw, 56, 26, 26), GOLD)


## Подложка: тонкая стальная рамка комикса чуть шире прямоугольника (light — подсвеченная)
func _panel_rect(r: Rect2, light: bool) -> void:
	ComicUI.draw_box(self, "button", r.grow(4.0), Color(1.15, 1.15, 1.2) if light else Color.WHITE)


func _draw_doll() -> void:
	var p: Rect2 = DOLL
	_text(p.position + Vector2(12, 26), I18n.t("Снаряжение"), 17, TEXT, true)
	if actor != null:
		_text_r(Vector2(p.end.x - 12, p.position.y + 26), actor.display_name, 17, GOLD, true)
	var fig := Rect2(p.position.x + 78, p.position.y + 40, p.size.x - 156, p.size.y - 118)
	var foot := Vector2(fig.get_center().x, fig.end.y - 2.0)
	draw_set_transform(foot, 0.0, Vector2(1.0, 0.25))
	draw_circle(Vector2.ZERO, 48.0, Color(0.05, 0.1, 0.2, 0.3))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	pawn_silhouette(self, fig)


## Силуэт героя по текстуре его фишки: тёмная заливка со светлой обводкой
static func pawn_silhouette(ci: CanvasItem, fig: Rect2) -> void:
	var t: Texture2D = silhouette_tex()
	if t == null:
		return
	var k: float = minf(fig.size.y / float(t.get_height()), fig.size.x / float(t.get_width()))
	var sz: Vector2 = Vector2(t.get_size()) * k
	var r := Rect2(Vector2(fig.get_center().x - sz.x * 0.5, fig.end.y - sz.y), sz)
	for d in [Vector2(-2, 0), Vector2(2, 0), Vector2(0, -2), Vector2(0, 2), Vector2(-1.5, -1.5), Vector2(1.5, 1.5), Vector2(-1.5, 1.5), Vector2(1.5, -1.5)]:
		ci.draw_texture_rect(t, Rect2(r.position + d, r.size), false, Color(0.62, 0.67, 0.74, 0.9))
	ci.draw_texture_rect(t, r, false, Color(0.13, 0.15, 0.18))


## Белый силуэт из картинки фишки (альфа та же), красится модуляцией; один на игру
static func silhouette_tex() -> Texture2D:
	if _tex.has("pawn"):
		return _tex["pawn"]
	var src: Texture2D = load(PAWN) if ResourceLoader.exists(PAWN) else null
	if src == null:
		return null
	var img: Image = src.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	img.clear_mipmaps()
	for y in img.get_height():
		for x in img.get_width():
			var a: float = img.get_pixel(x, y).a
			img.set_pixel(x, y, Color(1, 1, 1, 1.0 if a > 0.5 else a * 2.0))
	img.generate_mipmaps()
	_tex["pawn"] = ImageTexture.create_from_image(img)
	return _tex["pawn"]


func _draw_details(y: float) -> void:
	var s: String = _sel()
	if s == "":
		_text(Vector2(GRID.x, y + 20), I18n.t("Клик — выбрать вещь"), 13, DIM)
		return
	var it: Dictionary = Trade.item(s)
	var n: int = Trade.count(bag, s)
	_text(Vector2(GRID.x, y + 18), "%s ×%d" % [Trade.item_name(s), n], 16, TEXT, true)
	var info: String = kind_of(s)
	var u: Dictionary = it.get("use", {})
	if u.has("eat"):
		info += I18n.t(" · сытость +%d") % int(u["eat"])
	elif u.has("drink"):
		info += I18n.t(" · вода +%d") % int(u["drink"])
	if weapons.has(s):
		info += " · " + (I18n.t("в бою") if bag.get("battle_loadout", []).has(s) else I18n.t("не в бою"))
	_text(Vector2(GRID.x, y + 38), info, 13, DIM)
	_text(Vector2(GRID.x, y + 56), I18n.t("%.1f кг · %d мон. за шт.") % [float(it.get("weight", 0.0)) * n, int(it.get("price", 0))], 13, DIM)


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


## Ячейка: стальная ячейка комикса (мелкая — тонкая табличка, чтобы влезла подпись),
## лёгкий оттенок вида вещи внутри, выбранная — золотая рамка
func cell(ci: CanvasItem, r: Rect2, hover: bool, sel: bool, cat: String) -> void:
	var lit: Color = Color(1.3, 1.3, 1.35) if hover else Color.WHITE
	if r.size.x >= 70.0:
		ComicUI.draw_box(ci, "slot", r, lit)
	else:
		ComicUI.draw_box(ci, "button", r.grow(3.0), lit)
	var tint: Dictionary = {"food": Color(0.85, 0.6, 0.2, 0.14), "med": Color(0.3, 0.8, 0.3, 0.12), "weapon": Color(0.8, 0.25, 0.2, 0.12),
		"tools": Color(0.5, 0.4, 0.3, 0.12), "gear": Color(0.3, 0.45, 0.8, 0.12), "parts": Color(0.3, 0.3, 0.3, 0.12)}
	if tint.has(cat):
		ci.draw_rect(r.grow(-14.0), Color(tint[cat], tint[cat].a * 1.6))
	if sel:
		ci.draw_rect(r.grow(-2.0), GOLD, false, 3.0)


## Место вещи на листе сумки: без рамки; наведение — лёгкий свет, выбранная — золотой уголок-рамка
func sheet_mark(ci: CanvasItem, r: Rect2, hover: bool, sel: bool) -> void:
	if hover:
		ci.draw_rect(r.grow(-3.0), Color(1, 1, 1, 0.16))
	if sel:
		ci.draw_rect(r.grow(-3.0), Color(GOLD, 0.18))
		ci.draw_rect(r.grow(-3.0), GOLD, false, 2.0)


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


## Значки показателей: крест, вилка с ножом, капля, молния, бегун, знак проклятья
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
			curse_icon(ci, o, s)


## Значок проклятья: тёмный круг, фиолетовое «дурное око» со зрачком-щелью и шипами
static func curse_icon(ci: CanvasItem, o: Vector2, s: float) -> void:
	var c := Color("b46cf0")
	ci.draw_circle(o, s * 0.95, Color(0.09, 0.04, 0.13))
	for i in 8:
		var a: float = i * TAU / 8.0
		var d := Vector2.from_angle(a)
		var n := Vector2(-d.y, d.x)
		ci.draw_colored_polygon(PackedVector2Array([o + d * s * 0.92, o + d * s * 0.62 + n * s * 0.12, o + d * s * 0.62 - n * s * 0.12]), Color(c, 0.85))
	var eye := PackedVector2Array()
	for k in 13:
		var t: float = PI * k / 12.0
		eye.append(o + Vector2(-cos(t) * 0.62, -sin(t) * 0.34) * s)
	for k in range(1, 12):
		var t: float = PI * k / 12.0
		eye.append(o + Vector2(cos(t) * 0.62, sin(t) * 0.34) * s)
	ci.draw_colored_polygon(eye, c)
	ci.draw_colored_polygon(PackedVector2Array([o + Vector2(0, -0.3) * s, o + Vector2(0.09, 0) * s, o + Vector2(0, 0.3) * s, o + Vector2(-0.09, 0) * s]), Color(0.09, 0.04, 0.13))


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
	# Q26: kind_of отдаёт название на языке игры, а шаблон match должен быть постоянным — сравниваем по номеру
	match [I18n.t("еда"), I18n.t("питьё"), I18n.t("лечение")].find(kind_of(id)):
		0:
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
		1:
			if id == "ale":
				draw_colored_polygon(_pts(o, s, [[-0.45, -0.55], [0.35, -0.55], [0.35, 0.7], [-0.45, 0.7]]), Color("8a5a2c"))
				draw_colored_polygon(_pts(o, s, [[-0.5, -0.75], [0.4, -0.75], [0.4, -0.5], [-0.5, -0.5]]), Color("efe6d2"))
				draw_arc(o + Vector2(0.45, 0.05) * s, s * 0.25, -PI * 0.5, PI * 0.5, 8, INK, 3.0)
			else:
				draw_colored_polygon(_pts(o, s, [[-0.12, -0.8], [0.12, -0.8], [0.12, -0.5], [0.55, -0.25], [0.55, 0.65], [-0.55, 0.65], [-0.55, -0.25], [-0.12, -0.5]]), Color("8f6f48"))
				draw_colored_polygon(_pts(o, s, [[-0.45, 0.0], [0.45, 0.0], [0.45, 0.5], [-0.45, 0.5]]), Color("6d93b5"))
		2:
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

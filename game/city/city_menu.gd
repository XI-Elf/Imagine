extends CanvasLayer
## Экран города, как в  (видео Huzzah 2026-10-23): вход через ворота открывает не пешую карту,
## а меню города. Сверху шапка: картинка поселения (тот же медальон, что на общей карте), имя, этап роста,
## статус героя, часы и ворота. Ниже — карточки услуг: по одной на каждого жителя с делом (глава, травница,
## кожевник, кузнец, торговка…), «Поговорить» — с остальными, «Поручения», «Ночлег», «Колодец»,
## «Пройтись по городу» (прежняя пешая карта) и «Покинуть город».
## Карточка открывает тот же разговор, что и на улице (city_world.talk): окно поверх меню, «Уйти» — назад сюда.
## Жителя не надо искать на улице: в меню он доступен в свои часы работы, ночью спит.

const Growth := preload("res://city/city_growth.gd")
const MEDALLION_DIR := "res://art/medallion/"
const MEDALLIONS: Array = ["m0_camp", "m1_ostrog", "m2_sloboda", "m3_posad", "m4_gorod", "m5_bolshoy_gorod"]
## Портрет на картці мешканця: фігурка з комікс-набору (art/storybook), як на вулиці
const ROLE_ICON: Dictionary = {
	"healer": "woman", "trader": "woman", "guard": "guard",
}
static var ROLE_TITLE: Dictionary = {
	"elder": I18n.t("Глава"), "healer": I18n.t("Травница"), "tanner": I18n.t("Кожевник"), "smith": I18n.t("Кузнец"), "trader": I18n.t("Торговля"),
	"innkeeper": I18n.t("Таверна"), "guard": I18n.t("Стража"),
}
const ComicUI := preload("res://ui/comic_ui.gd")
## Рамки коміксу й темна палітра (Q24 A, Q08 D): світлий текст на вугіллі замість чорнила на папері
const INK := ComicUI.TEXT

var city: Node                     # city/city_world.gd
var _root: Control
var _pic: TextureRect
var _name: Label
var _sub: Label
var _info: Label
var _grid: GridContainer
var _cards: Array = []             # {btn, icon, title, who, note, kind, n}
var _npc_key: String = ""          # які мешканці зараз у картках (перебудувати, якщо місто виросло)
var _tick: float = 0.0


func setup(c: Node) -> void:
	city = c
	layer = 19                     # під вікнами розмови й торгівлі міста (20), над картою
	visible = false
	_build()


func open() -> void:
	visible = true
	refresh(true)


func close() -> void:
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.5
		refresh(false)


# =====================================================================
# ВМІСТ
# =====================================================================
## Мешканці з карткою: у кого є справа (роль не «мешканець», торгівля, послуги або доручення)
func service_npcs() -> Array:
	var out: Array = []
	for n in city.npcs:
		var nd: Dictionary = n["def"]
		var role: String = String(nd.get("role", "citizen"))
		if role != "citizen" or not n["stock"].is_empty() or not nd.get("services", {}).is_empty() \
				or Growth.chain(city.full_def, String(nd["id"])).size() > 0:
			out.append(n)
	return out


func other_npcs() -> Array:
	var s: Array = service_npcs()
	return city.npcs.filter(func(n): return not s.has(n))


## Картки за порядком: kind — "npc", "talk", "quests", "sleep", "water", "walk", "leave"
func card_list() -> Array:
	var out: Array = [{"kind": "quests"}]
	for n in service_npcs():
		out.append({"kind": "npc", "n": n})
	if not other_npcs().is_empty():
		out.append({"kind": "talk"})
	if not _place("bed").is_empty():
		out.append({"kind": "sleep"})
	if not _place("water").is_empty():
		out.append({"kind": "water"})
	out.append({"kind": "walk"})
	out.append({"kind": "leave"})
	return out


func _place(kind: String) -> Dictionary:
	for p in city.def.get("places", []):
		if String(p.get("kind", "")) == kind:
			return p
	return {}


func level() -> int:
	if Growth.has_growth(city.full_def):
		return clampi(city.stage + 1, 0, MEDALLIONS.size() - 1)
	return {"hamlet": 0, "village": 2, "town": 3, "city": 4, "capital": 5}.get(String(city.full_def.get("size", "town")), 3)


func refresh(force: bool) -> void:
	if city == null or not city.entered:
		return
	var key: String = ",".join(PackedStringArray(city.npcs.map(func(n): return String(n["def"]["id"]))))
	if force or key != _npc_key:
		_npc_key = key
		_rebuild_cards()
	var lv: int = level()
	var path: String = MEDALLION_DIR + String(MEDALLIONS[lv]) + ".png"
	if ResourceLoader.exists(path) and (_pic.texture == null or _pic.texture.resource_path != path):
		_pic.texture = load(path)
	_name.text = city.display_name
	_sub.text = header_sub()
	_info.text = header_info()
	for c in _cards:
		_fill_card(c)


func header_sub() -> String:
	var t: String = I18n.t("Вольный город")
	if Growth.has_growth(city.full_def):
		t = I18n.t("%s, этап «%s»") % [t, Growth.stage_name(city.full_def, city.stage)]
	return t


func header_info() -> String:
	var lines: Array = []
	lines.append(I18n.t("Статус: %s") % (I18n.t("Чужак (пробрался через стену)") if city.is_intruder() else I18n.t("Гость")))
	if Growth.has_growth(city.full_def):
		var need: int = Growth.next_points(city.full_def, city.stage)
		var have: int = Growth.points(city.growth)
		lines.append(I18n.t("Поручений сдано: %d%s") % [have, I18n.t(" из %d до этапа «%s»") % [need, Growth.stage_name(city.full_def, city.stage + 1)] if need > 0 else I18n.t(", город вырос полностью")])
	var hour: float = city.clock.hour_of_day()
	lines.append("%02d:%02d   %s" % [int(hour), int(fmod(hour, 1.0) * 60.0), I18n.t("ворота открыты") if city.gates_open() else I18n.t("ворота заперты до %d:00") % int(city.rules.get("gates_open_h", 6.0))])
	return "\n".join(PackedStringArray(lines))


func _rebuild_cards() -> void:
	for c in _cards:
		c["btn"].queue_free()
	_cards.clear()
	for e in card_list():
		var c: Dictionary = e.duplicate()
		_make_card(c)
		_cards.append(c)


func _make_card(c: Dictionary) -> void:
	var b := Button.new()
	b.custom_minimum_size = Vector2(210, 140)
	b.focus_mode = Control.FOCUS_NONE
	b.clip_contents = true
	ComicUI.button_styles(b)
	var icon := TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.position = Vector2(6, 6)
	icon.size = Vector2(64, 128)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(icon)
	var title := Label.new()
	title.position = Vector2(76, 6)
	title.size = Vector2(128, 24)
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", INK)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(title)
	var who := Label.new()
	who.position = Vector2(76, 30)
	who.size = Vector2(128, 40)
	who.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	who.add_theme_font_size_override("font_size", 14)
	who.add_theme_color_override("font_color", INK)
	who.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(who)
	var note := Label.new()
	note.position = Vector2(76, 72)
	note.size = Vector2(128, 64)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", ComicUI.DIM)
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(note)
	c["btn"] = b
	c["icon"] = icon
	c["title"] = title
	c["who"] = who
	c["note"] = note
	b.pressed.connect(func(): press(c))
	_grid.add_child(b)
	var key: String = {"quests": "hall", "talk": "villager", "sleep": "house", "water": "well", "walk": "traveler", "leave": "tree_oak"}.get(c["kind"], "")
	if c["kind"] == "npc":
		key = ROLE_ICON.get(String(c["n"]["def"].get("role", "citizen")), "villager")
	if ResourceLoader.exists("res://art/storybook/%s.png" % key):
		icon.texture = load("res://art/storybook/%s.png" % key)


func _fill_card(c: Dictionary) -> void:
	var t: String = ""
	var who: String = ""
	var note: String = ""
	var off: bool = false
	match String(c["kind"]):
		"npc":
			var n: Dictionary = c["n"]
			var nd: Dictionary = n["def"]
			var role: String = String(nd.get("role", "citizen"))
			t = ROLE_TITLE.get(role, I18n.t("Житель"))
			who = n["actor"].display_name
			if who.begins_with(t + " "):
				who = who.substr(t.length() + 1)     # «Кожевник Эдрик» під «Кожевник» — просто «Эдрик»
			var hr: Array = nd.get("hours", [8, 20])
			if n["actor"].sleeping:
				note = I18n.t("Спит")
				off = true
			elif city._on_duty(nd, city.clock.hour_of_day()):
				note = I18n.t("Работает до %d:00") % int(hr[1]) if int(hr[1]) < 24 else I18n.t("Работает")
			else:
				note = I18n.t("Не работает, с %d:00") % int(hr[0])
			# Усі доручення, які можна взяти або здати зараз: основне й запасні (Growth.available)
			var qs: Array = Growth.available(city.full_def, city.growth, String(nd["id"]))
			if qs.any(func(q): return Growth.taken(city.growth, q) and Growth.ready(city.growth, q, city.bag, city.hero_km(), city.battles_won())):
				note += I18n.t("\nПоручение готово!")
			elif qs.any(func(q): return not Growth.taken(city.growth, q)):
				note += I18n.t("\nЕсть работа: %d") % qs.filter(func(q): return not Growth.taken(city.growth, q)).size()
			elif not qs.is_empty():
				note += I18n.t("\nПоручение взято")
		"talk":
			t = I18n.t("Поговорить")
			note = I18n.t("Жители: %d") % other_npcs().size()
		"quests":
			t = I18n.t("Поручения")
			var open_q: int = 0
			for n in city.npcs:
				open_q += Growth.available(city.full_def, city.growth, String(n["def"]["id"])).size()
			note = I18n.t("Открыто: %d") % open_q if Growth.has_growth(city.full_def) else I18n.t("Доска объявлений")
		"sleep":
			t = I18n.t("Ночлег")
			note = I18n.t("Проснуться (энергия %d)") % int(city.hero.res["energy"]) if city.hero.sleeping else I18n.t("Лежанка в лачуге")
		"water":
			t = I18n.t("Колодец")
			note = I18n.t("Напиться (вода %d)") % int(city.hero.res["thirst"])
		"walk":
			t = I18n.t("Пройтись")
			who = I18n.t("по городу")
			note = I18n.t("Улицы, дома, тайники")
		"leave":
			t = I18n.t("Покинуть")
			who = I18n.t("город")
			note = I18n.t("Через ворота") if city.gates_open() else I18n.t("Ворота заперты")
	c["title"].text = t
	c["who"].text = who
	c["note"].text = note
	c["btn"].modulate = Color(1, 1, 1, 0.7) if off else Color.WHITE


func press(c: Dictionary) -> void:
	match String(c["kind"]):
		"npc":
			city.talk(c["n"])
		"talk":
			city.menu_people(other_npcs())
		"quests":
			if _place("board").is_empty():
				city._open_note(I18n.t("Поручения"), I18n.t("Поручений нет."))
			else:
				city.use_place(_place("board"))
		"sleep":
			if city.hero.sleeping:
				city.hero.set_sleep(false)
				city._say(I18n.t("Вы проснулись"))
			else:
				city.use_place(_place("bed"))
		"water":
			city.use_place(_place("water"))
		"walk":
			city.walk_city()
		"leave":
			city.menu_leave()
	refresh(false)


# =====================================================================
# ВИГЛЯД
# =====================================================================
func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = ComicUI.COAL.darkened(0.3)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)
	var sheet := PanelContainer.new()
	sheet.add_theme_stylebox_override("panel", ComicUI.panel(26.0))
	sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
	sheet.offset_left = 24
	sheet.offset_top = 16
	sheet.offset_right = -24
	sheet.offset_bottom = -48       # знизу смуга стану героя (city_world._status)
	_root.add_child(sheet)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	sheet.add_child(v)
	# Шапка: ліворуч назва й відомості, праворуч картинка поселення
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	v.add_child(head)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 6)
	head.add_child(left)
	_name = _label(left, 38, INK)
	_sub = _label(left, 18, ComicUI.DIM)
	var line := ColorRect.new()
	line.color = ComicUI.STEEL_HI
	line.custom_minimum_size = Vector2(0, 2)
	left.add_child(line)
	_info = _label(left, 17, INK)
	_pic = TextureRect.new()
	_pic.custom_minimum_size = Vector2(250, 250)
	_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(_pic)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	sc.add_child(_grid)
	_root.resized.connect(func(): _grid.columns = maxi(2, int((_root.size.x - 90.0) / 222.0)))


func _label(parent: Node, size: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l

extends CanvasLayer
## Журнал завдань (J, пункт 15 Huzzah 2026-10-29): гравець сам записує доручення, які йому дали (відповідь 3 — Б:
## гра нічого не пише за нього). Записаний текст зберігається як є, а ПОКАЗУЄТЬСЯ за Розумом героя (Sheet.talk_int):
##   1–3 — примітивні малюнки й кілька простих слів (решту герой не здатен записати),
##   4–6 — як написав гравець,
##   7+  — докладно й образно: дата, місце, погода, розгорнуті слова.
## Розум змінився (травма, дари) — змінюється й те, як читаються старі записи.
## Записи живуть у Worlds.journal і пишуться в збереження.

const Sheet := preload("res://characters/sheet.gd")

const MAX_LEN: int = 600
## Ключові корені слів -> піктограма (малюється в _draw_icon)
static var ICONS: Array = [
	["sword", [I18n.t("уб"), I18n.t("бандит"), I18n.t("разбойн"), I18n.t("волк"), I18n.t("кабан"), I18n.t("бой"), I18n.t("бить"), I18n.t("напад"), I18n.t("враг"), I18n.t("пёс"), I18n.t("псов"), I18n.t("чудищ")]],
	["house", [I18n.t("город"), I18n.t("дом"), I18n.t("посад"), I18n.t("слобод"), I18n.t("деревн"), I18n.t("остро"), I18n.t("ворот"), I18n.t("башн"), I18n.t("стен")]],
	["coin", [I18n.t("монет"), I18n.t("деньг"), I18n.t("плат"), I18n.t("цен"), I18n.t("куп"), I18n.t("прода"), I18n.t("серебр"), I18n.t("золот")]],
	["leaf", [I18n.t("трав"), I18n.t("ягод"), I18n.t("гриб"), I18n.t("корен"), I18n.t("цвет"), I18n.t("лес"), I18n.t("хворост")]],
	["hide", [I18n.t("шкур"), I18n.t("кож"), I18n.t("мех")]],
	["hammer", [I18n.t("лом"), I18n.t("желез"), I18n.t("кузн"), I18n.t("метал"), I18n.t("ковать"), I18n.t("инструм")]],
	["drop", [I18n.t("вод"), I18n.t("колод"), I18n.t("река"), I18n.t("пить"), I18n.t("зель"), I18n.t("отвар")]],
	["skull", [I18n.t("смерт"), I18n.t("мёртв"), I18n.t("мертв"), I18n.t("проклят"), I18n.t("могил"), I18n.t("руин"), I18n.t("кост")]],
	["person", [I18n.t("староста"), I18n.t("лекар"), I18n.t("кожев"), I18n.t("торгов"), I18n.t("стража"), I18n.t("кузнец"), I18n.t("человек"), I18n.t("найти"), I18n.t("приве")]],
	["arrow", [I18n.t("иди"), I18n.t("идти"), I18n.t("сход"), I18n.t("отнес"), I18n.t("принес"), I18n.t("достав"), I18n.t("север"), I18n.t("юг"), I18n.t("запад"), I18n.t("восток")]],
]
## Для розумного героя: коротке слово -> образний вираз
static var RICH: Dictionary = {
	I18n.t("волк"): I18n.t("серый волк из промозглой чащи"), I18n.t("волков"): I18n.t("серых волков, что воют за частоколом"),
	I18n.t("кабан"): I18n.t("клыкастый кабан"), I18n.t("бандит"): I18n.t("оборванец с большой дороги"), I18n.t("бандитов"): I18n.t("оборванцев с большой дороги"),
	I18n.t("шкура"): I18n.t("выделанная шкура"), I18n.t("шкуры"): I18n.t("шкуры, пахнущие дымом и кровью"), I18n.t("трава"): I18n.t("горькая трава с обочины"),
	I18n.t("травы"): I18n.t("горькие травы с обочин"), I18n.t("староста"): I18n.t("старый староста с мутным взглядом"), I18n.t("старосте"): I18n.t("старому старосте с мутным взглядом"),
	I18n.t("лекарю"): I18n.t("лекарю, пропахшему уксусом"), I18n.t("кожевнику"): I18n.t("кожевнику с чёрными от дубильни руками"), I18n.t("лекарь"): I18n.t("лекарь, пропахший уксусом"),
	I18n.t("город"): I18n.t("серый город за гнилым частоколом"), I18n.t("монет"): I18n.t("медных монет"), I18n.t("монеты"): I18n.t("медные монеты"), I18n.t("лом"): I18n.t("ржавый лом"),
}

var entries: Array = []      # {text, at: секунди гри, done}
var hero_getter: Callable    # () -> Actor
var clock_getter: Callable   # () -> float
var place_getter: Callable   # () -> String
var weather_getter: Callable # () -> String

var _panel: PanelContainer
var _list: VBoxContainer
var _edit: TextEdit
var _iq_lbl: Label
var _scroll: ScrollContainer


func setup(hero: Callable, clock: Callable, place: Callable = Callable(), weather: Callable = Callable()) -> void:
	hero_getter = hero
	clock_getter = clock
	place_getter = place
	weather_getter = weather


func _ready() -> void:
	layer = 28
	visible = false
	_build()


func _hero() -> Actor:
	return hero_getter.call() if hero_getter.is_valid() else null


func iq() -> int:
	var a: Actor = _hero()
	return Sheet.talk_int(a) if a != null else 5


## Рівень письма: 0 — малюнки, 1 — як є, 2 — образно
func level() -> int:
	var i: int = iq()
	if i <= 3:
		return 0
	if i >= 7:
		return 2
	return 1


func add(text: String) -> bool:
	var t: String = text.strip_edges().left(MAX_LEN)
	if t == "":
		return false
	var now: float = clock_getter.call() if clock_getter.is_valid() else 0.0
	var e: Dictionary = {"text": t, "at": now, "done": false}
	if level() == 2:
		e["place"] = place_getter.call() if place_getter.is_valid() else ""
		e["weather"] = weather_getter.call() if weather_getter.is_valid() else ""
	entries.append(e)
	if is_inside_tree():
		_refresh()
	return true


# =====================================================================
# ЯК ЧИТАЄТЬСЯ ЗАПИС
# =====================================================================
## Піктограми для тексту (рівень 0), по порядку слів, без повторів поспіль
static func icons_for(text: String) -> Array:
	var out: Array = []
	for w in _words(text):
		for pair in ICONS:
			var hit: bool = false
			for root in pair[1]:
				if w.begins_with(root) or (root.length() >= 4 and w.contains(root)):
					hit = true
					break
			if hit:
				if out.is_empty() or out[-1] != pair[0]:
					out.append(pair[0])
				break
	return out.slice(0, 6)


static func _words(text: String) -> PackedStringArray:
	var t: String = text.to_lower()
	for ch in [",", ".", "!", "?", ":", ";", "«", "»", "\"", "(", ")", "\n", "—", "-"]:
		t = t.replace(ch, " ")
	return t.split(" ", false)


## Прості слова для рівня 0: до трьох коротких слів великими літерами
static func crude_words(text: String) -> String:
	var out: PackedStringArray = []
	for w in _words(text):
		if w.length() >= 3 and w.length() <= 6:
			out.append(w.to_upper())
		if out.size() >= 3:
			break
	return " ".join(out)


## Образний текст для рівня 2
static func rich_text(e: Dictionary, date: String) -> String:
	var body: String = String(e["text"])
	for k in RICH:
		var re := RegEx.new()
		re.compile("(?i)(?<![\\p{L}])" + k + "(?![\\p{L}])")
		body = re.sub(body, RICH[k], true)
	body = body.left(1).to_upper() + body.substr(1)
	if not body.ends_with(".") and not body.ends_with("!") and not body.ends_with("?"):
		body += "."
	var head: String = date
	if String(e.get("place", "")) != "":
		head += ", " + String(e["place"])
	if String(e.get("weather", "")) != "":
		head += I18n.t(", %s") % String(e["weather"])
	return I18n.t("%s.\nЗаписано наспех, огрызком угля: %s Не забыть — в этих краях забытое слово стоит жизни.") % [head, body]


func render(e: Dictionary) -> String:
	var date: String = GameClock.date_text(float(e.get("at", 0.0)))
	match level():
		0:
			return crude_words(String(e["text"]))
		2:
			return rich_text(e, date)
	return "%s — %s" % [date, String(e["text"])]


# =====================================================================
# ВІКНО
# =====================================================================
func open() -> void:
	visible = true
	_refresh()
	_edit.text = ""
	_edit.grab_focus()


func close() -> void:
	visible = false
	_edit.release_focus()


func is_open() -> bool:
	return visible


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.offset_left = 120
	_panel.offset_right = -120
	_panel.offset_top = 50
	_panel.offset_bottom = -50
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.82, 0.74, 0.58)
	sb.border_color = Color(0.35, 0.24, 0.12)
	sb.set_border_width_all(4)
	sb.set_content_margin_all(18)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)
	var title := Label.new()
	title.text = I18n.t("Журнал заданий  ·  J — закрыть")
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.2, 0.12, 0.06))
	box.add_child(title)
	_iq_lbl = Label.new()
	_iq_lbl.add_theme_color_override("font_color", Color(0.35, 0.22, 0.1))
	_iq_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_iq_lbl)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	_scroll.add_child(_list)
	_edit = TextEdit.new()
	_edit.custom_minimum_size = Vector2(0, 90)
	_edit.placeholder_text = I18n.t("Что поручили, кто, где и за сколько…")
	_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	box.add_child(_edit)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var save := Button.new()
	save.text = I18n.t("Записать")
	save.pressed.connect(func(): if add(_edit.text): _edit.text = "")
	row.add_child(save)
	var cl := Button.new()
	cl.text = I18n.t("Закрыть")
	cl.pressed.connect(close)
	row.add_child(cl)


func _refresh() -> void:
	_iq_lbl.text = [I18n.t("Ум низкий: герой чертит каракули и пару слов — остальное не запомнит."),
		I18n.t("Герой записывает как есть."), I18n.t("Ум высокий: записи подробные и с прикрасами.")][level()]
	for c in _list.get_children():
		c.queue_free()
	if entries.is_empty():
		var l := Label.new()
		l.text = I18n.t("Записей нет. Напишите внизу, что вам поручили.")
		l.add_theme_color_override("font_color", Color(0.3, 0.2, 0.1))
		_list.add_child(l)
	for i in range(entries.size() - 1, -1, -1):
		_list.add_child(_entry_row(i))


func _entry_row(i: int) -> Control:
	var e: Dictionary = entries[i]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	if level() == 0:
		var pic := Control.new()
		var ic: Array = icons_for(String(e["text"]))
		pic.custom_minimum_size = Vector2(maxf(ic.size(), 1) * 44.0, 40)
		pic.draw.connect(func():
			for k in ic.size():
				_draw_icon(pic, String(ic[k]), Vector2(22 + k * 44, 20)))
		row.add_child(pic)
	var l := Label.new()
	l.text = render(e)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 22 if level() == 0 else 16)
	l.add_theme_color_override("font_color", Color(0.15, 0.1, 0.06, 0.45 if bool(e.get("done", false)) else 1.0))
	row.add_child(l)
	var done := Button.new()
	done.text = I18n.t("Снова") if bool(e.get("done", false)) else I18n.t("Сделано")
	done.pressed.connect(func(): e["done"] = not bool(e.get("done", false)); _refresh())
	row.add_child(done)
	var del := Button.new()
	del.text = I18n.t("Стереть")
	del.pressed.connect(func(): entries.remove_at(i); _refresh())
	row.add_child(del)
	return row


## Грубі малюнки вугликом
func _draw_icon(c: Control, kind: String, p: Vector2) -> void:
	var k := Color(0.12, 0.08, 0.05)
	match kind:
		"sword":
			c.draw_line(p + Vector2(-12, 12), p + Vector2(12, -12), k, 3.0)
			c.draw_line(p + Vector2(-8, 2), p + Vector2(-2, 8), k, 3.0)
		"house":
			c.draw_polyline(PackedVector2Array([p + Vector2(-12, 14), p + Vector2(-12, -2), p + Vector2(0, -14), p + Vector2(12, -2), p + Vector2(12, 14), p + Vector2(-12, 14)]), k, 3.0)
		"coin":
			c.draw_arc(p, 11, 0, TAU, 16, k, 3.0)
			c.draw_line(p + Vector2(0, -6), p + Vector2(0, 6), k, 2.0)
		"leaf":
			c.draw_arc(p + Vector2(-5, 0), 12, -1.0, 1.0, 10, k, 3.0)
			c.draw_arc(p + Vector2(5, 0), 12, PI - 1.0, PI + 1.0, 10, k, 3.0)
			c.draw_line(p + Vector2(0, 14), p + Vector2(0, -10), k, 2.0)
		"hide":
			c.draw_polyline(PackedVector2Array([p + Vector2(-12, -10), p + Vector2(-6, -4), p + Vector2(6, -4), p + Vector2(12, -10), p + Vector2(9, 12), p + Vector2(-9, 12), p + Vector2(-12, -10)]), k, 3.0)
		"hammer":
			c.draw_line(p + Vector2(-10, 12), p + Vector2(6, -4), k, 3.0)
			c.draw_line(p + Vector2(0, -12), p + Vector2(12, 0), k, 5.0)
		"drop":
			c.draw_arc(p + Vector2(0, 4), 9, 0, PI, 10, k, 3.0)
			c.draw_line(p + Vector2(-9, 4), p + Vector2(0, -13), k, 3.0)
			c.draw_line(p + Vector2(9, 4), p + Vector2(0, -13), k, 3.0)
		"skull":
			c.draw_arc(p + Vector2(0, -3), 10, 0, TAU, 16, k, 3.0)
			c.draw_circle(p + Vector2(-4, -4), 2.5, k)
			c.draw_circle(p + Vector2(4, -4), 2.5, k)
			c.draw_line(p + Vector2(-5, 9), p + Vector2(5, 9), k, 3.0)
		"person":
			c.draw_arc(p + Vector2(0, -9), 5, 0, TAU, 10, k, 3.0)
			c.draw_line(p + Vector2(0, -4), p + Vector2(0, 7), k, 3.0)
			c.draw_line(p + Vector2(-9, 0), p + Vector2(9, 0), k, 3.0)
			c.draw_line(p + Vector2(0, 7), p + Vector2(-7, 15), k, 3.0)
			c.draw_line(p + Vector2(0, 7), p + Vector2(7, 15), k, 3.0)
		"arrow":
			c.draw_line(p + Vector2(-13, 0), p + Vector2(12, 0), k, 3.0)
			c.draw_line(p + Vector2(12, 0), p + Vector2(4, -7), k, 3.0)
			c.draw_line(p + Vector2(12, 0), p + Vector2(4, 7), k, 3.0)


func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.is_action_pressed("ui_cancel") or (event.physical_keycode == KEY_J and not _edit.has_focus()):
		close()
		get_viewport().set_input_as_handled()


# =====================================================================
# ЗБЕРЕЖЕННЯ
# =====================================================================
func to_array() -> Array:
	return entries.duplicate(true)


func load_array(a: Variant) -> void:
	entries = []
	if a is Array:
		for e in a:
			if e is Dictionary and e.has("text"):
				entries.append(e.duplicate())

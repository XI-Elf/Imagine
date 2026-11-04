extends RefCounted
## Комікс-оформлення інтерфейсу (відповіді Huzzah 2026-10-24: Q08 D — форми коміксу, темна палітра,
## рідкісні техно-артефакти; Q24 A — рамки коміксу в усіх вікнах).
## Картинки — art/comic_ui/*.png, їх робить tools/make_comic_ui.py з OPTIONAL_UI комікс-набору:
## темна сталь з іржею й латунними заклепками, усередині вугілля. Поля nine-patch нижче — ті самі, що пише
## інструмент в art/comic_ui/comic_ui.json.
## Спільна тема (theme()) вливається в тему Godot за замовчуванням автозавантаженням ui/comic_skin.gd, тому кнопки,
## шкали, поля введення й панелі без власних стилів отримують її самі. Вікна з власним стилем беруть panel()/button_styles().
## Техно-артефакт (бурштинова лінза на сталевій пластині) — tech_plate(), лише на головних вікнах.

const T_PANEL := preload("res://art/comic_ui/panel.png")
const T_BUTTON := preload("res://art/comic_ui/button.png")
const T_SLOT := preload("res://art/comic_ui/slot.png")
const T_PORTRAIT := preload("res://art/comic_ui/portrait.png")
const T_BAR := preload("res://art/comic_ui/bar.png")
const T_RIBBON := preload("res://art/comic_ui/ribbon.png")
const T_TECH := preload("res://art/comic_ui/tech_plate.png")

## Поля nine-patch [x, y] у пікселях картинки й відступи вмісту
const MARGIN: Dictionary = {"panel": [30, 27], "button": [16, 14], "slot": [21, 21], "portrait": [25, 26], "bar": [12, 13]}
const CONTENT: Dictionary = {"panel": [26, 23], "button": [19, 9], "slot": [17, 17], "portrait": [22, 23], "bar": [9, 8]}

## Темна палітра
const COAL := Color("1b1a1e")      # нутро панелей (збігається з COAL у make_comic_ui.py)
const STEEL := Color("3e4856")     # сталь рамок
const STEEL_HI := Color("6f7f94")  # світла крайка сталі
const INK := Color("0b0b0d")       # контур
const TEXT := Color("d8cfb0")
const DIM := Color("8f8a78")
const GOLD := Color("c9a24b")
const AMBER := Color("ffb030")     # бурштин — лише техніка й вибір
const RUST := Color("8a4a2a")

static var _theme: Theme = null


static func _tex(key: String) -> Texture2D:
	match key:
		"panel":
			return T_PANEL
		"button":
			return T_BUTTON
		"slot":
			return T_SLOT
		"portrait":
			return T_PORTRAIT
		"bar":
			return T_BAR
	return T_PANEL


## Рамка коміксу як StyleBoxTexture. key: panel, button, slot, portrait, bar
static func box(key: String = "panel", modulate: Color = Color.WHITE, alpha: float = 1.0) -> StyleBoxTexture:
	var st := StyleBoxTexture.new()
	st.texture = _tex(key)
	var m: Array = MARGIN.get(key, [24, 24])
	var c: Array = CONTENT.get(key, [16, 16])
	st.texture_margin_left = m[0]
	st.texture_margin_right = m[0]
	st.texture_margin_top = m[1]
	st.texture_margin_bottom = m[1]
	st.content_margin_left = c[0]
	st.content_margin_right = c[0]
	st.content_margin_top = c[1]
	st.content_margin_bottom = c[1]
	st.modulate_color = Color(modulate, modulate.a * alpha)
	return st


## Панель вікна; content — власний відступ вмісту (якщо > 0)
static func panel(content: float = -1.0, alpha: float = 1.0) -> StyleBoxTexture:
	var st := box("panel", Color.WHITE, alpha)
	if content > 0.0:
		st.set_content_margin_all(content)
	return st


## Стилі кнопки: звичайна, наведення світліше, натиснута/увімкнена — з бурштиновим полиском, вимкнена — тьмяна
static func button_box(state: String) -> StyleBox:
	match state:
		"hover":
			return box("button", Color(1.3, 1.3, 1.35))
		"pressed", "hover_pressed":
			return box("button", Color(1.55, 1.25, 0.8) if state == "pressed" else Color(1.7, 1.38, 0.88))
		"disabled":
			return box("button", Color(0.6, 0.6, 0.62, 0.8))
		"focus":
			var e := StyleBoxEmpty.new()
			return e
	return box("button")


## Перефарбувати кнопку в комікс поверх її колишніх стилів (для вікон, де стилі задано в коді)
static func button_styles(b: Button, font_size: int = -1) -> void:
	for n in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(n, button_box(n))
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", Color("fff3d6"))
	b.add_theme_color_override("font_pressed_color", Color("ffe2a8"))
	b.add_theme_color_override("font_hover_pressed_color", Color("ffe2a8"))
	b.add_theme_color_override("font_disabled_color", Color(DIM, 0.55))
	b.add_theme_color_override("font_outline_color", INK)
	b.add_theme_constant_override("outline_size", 3)
	if font_size > 0:
		b.add_theme_font_size_override("font_size", font_size)


## Шкала (завантаження тощо): сталева рамка, бурштинова заливка
static func bar_styles(pb: ProgressBar) -> void:
	pb.add_theme_stylebox_override("background", box("bar"))
	pb.add_theme_stylebox_override("fill", bar_fill())


static func bar_fill() -> StyleBoxFlat:
	var f := StyleBoxFlat.new()
	f.bg_color = Color("d08a2a")
	f.border_color = Color(AMBER, 0.9)
	f.border_width_top = 1
	f.set_corner_radius_all(2)
	f.expand_margin_top = -6.0
	f.expand_margin_bottom = -6.0
	f.expand_margin_left = -7.0
	f.expand_margin_right = -7.0
	return f


## Малювання рамок кодом (вікна, що малюють себе самі: інвентар, бій)
static func draw_box(ci: CanvasItem, key: String, r: Rect2, modulate: Color = Color.WHITE) -> void:
	ci.draw_style_box(box(key, modulate), r)


## Техно-артефакт: сталева пластина з бурштиновою лінзою посередині верхньої крайки вікна.
## Малюється поверх рамки сигналом draw, тому не заважає розкладці контейнера.
static func tech_plate(c: Control) -> void:
	if c.has_meta("comic_tech"):
		return
	c.set_meta("comic_tech", true)
	c.draw.connect(func() -> void:
		var sz: Vector2 = T_TECH.get_size()
		c.draw_texture(T_TECH, Vector2(roundf((c.size.x - sz.x) * 0.5), -roundf(sz.y * 0.38))))
	c.queue_redraw()


## Стрічка-закладка (мітка вікна) у лівому верхньому куті
static func ribbon(c: Control, x: float = 26.0) -> void:
	c.draw.connect(func() -> void:
		c.draw_texture(T_RIBBON, Vector2(x, -6.0)))
	c.queue_redraw()


## Тема для всього інтерфейсу: кнопки, панелі, шкали, поля, підказки, роздільники
static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	for cls in ["Button", "OptionButton", "MenuButton"]:
		for n in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			t.set_stylebox(n, cls, button_box(n))
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, Color("fff3d6"))
		t.set_color("font_pressed_color", cls, Color("ffe2a8"))
		t.set_color("font_hover_pressed_color", cls, Color("ffe2a8"))
		t.set_color("font_disabled_color", cls, Color(DIM, 0.55))
		t.set_color("font_outline_color", cls, INK)
		t.set_constant("outline_size", cls, 3)
	t.set_stylebox("panel", "PanelContainer", panel())
	t.set_stylebox("panel", "Panel", panel())
	t.set_stylebox("panel", "TooltipPanel", panel(10.0))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_stylebox("panel", "PopupMenu", panel(10.0))
	t.set_stylebox("panel", "PopupPanel", panel(10.0))
	t.set_stylebox("background", "ProgressBar", box("bar"))
	t.set_stylebox("fill", "ProgressBar", bar_fill())
	t.set_color("font_color", "ProgressBar", TEXT)
	var edit := StyleBoxFlat.new()
	edit.bg_color = Color(0.06, 0.06, 0.07, 0.95)
	edit.border_color = STEEL_HI
	edit.set_border_width_all(2)
	edit.set_corner_radius_all(3)
	edit.set_content_margin_all(8.0)
	t.set_stylebox("normal", "LineEdit", edit)
	var edit_f: StyleBoxFlat = edit.duplicate()
	edit_f.border_color = AMBER
	t.set_stylebox("focus", "LineEdit", edit_f)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("caret_color", "LineEdit", AMBER)
	for cls in ["HSeparator", "VSeparator"]:
		var line := StyleBoxLine.new()
		line.color = Color(STEEL_HI, 0.55)
		line.thickness = 2
		line.vertical = cls == "VSeparator"
		t.set_stylebox("separator", cls, line)
	t.set_color("font_color", "Label", TEXT)
	for cls in ["TabBar", "TabContainer"]:
		t.set_stylebox("tab_selected", cls, button_box("pressed"))
		t.set_stylebox("tab_hovered", cls, button_box("hover"))
		t.set_stylebox("tab_unselected", cls, button_box("normal"))
		t.set_stylebox("tab_disabled", cls, button_box("disabled"))
		t.set_color("font_selected_color", cls, Color("ffe2a8"))
		t.set_color("font_unselected_color", cls, TEXT)
		t.set_color("font_hovered_color", cls, Color("fff3d6"))
	_theme = t
	return t

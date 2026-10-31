extends PanelContainer
## Налаштування звуку й музики (Huzzah 2026-10-30: «у налаштуваннях гри — меню керування музикою, гучність і періодичність»).
## Відкривається кнопкою «Звук и музыка» в головному меню (main_menu.gd) і в меню Esc (game.gd).
## Усе зберігається одразу: музика — user://music.cfg (Music), звуки — user://audio.cfg (Sfx).

signal closed

const ComicUI := preload("res://ui/comic_ui.gd")
const COLOR_TITLE := Color("d8cfb0")

var music_check: CheckButton
var music_slider: HSlider
var music_value: Label
var from_spin: SpinBox
var to_spin: SpinBox
var sfx_check: CheckButton
var sfx_slider: HSlider
var sfx_value: Label
var now_label: Label
var _t: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_theme_stylebox_override("panel", ComicUI.panel(30.0))
	ComicUI.tech_plate(self)
	var M: Node = get_node_or_null("/root/Music")
	var S: Node = get_node_or_null("/root/Sfx")
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.custom_minimum_size = Vector2(560, 0)
	add_child(v)
	var t := Label.new()
	t.text = I18n.t("Звук и музыка")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 30)
	t.add_theme_color_override("font_color", COLOR_TITLE)
	v.add_child(t)

	# Музика: увімк./вимк., гучність, періодичність
	music_check = CheckButton.new()
	music_check.text = I18n.t("Музыка")
	music_check.button_pressed = M != null and M.enabled
	music_check.toggled.connect(func(on: bool) -> void:
		if M != null:
			M.set_enabled(on))
	v.add_child(music_check)
	var mrow := _slider_row(v, I18n.t("Громкость музыки"))
	music_slider = mrow[0]
	music_value = mrow[1]
	music_slider.value = roundf((M.volume if M != null else 0.8) * 100.0)
	music_value.text = "%d %%" % int(music_slider.value)
	music_slider.value_changed.connect(func(x: float) -> void:
		music_value.text = "%d %%" % int(x)
		if M != null:
			M.set_volume(x / 100.0))
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 8)
	v.add_child(prow)
	var pl := Label.new()
	pl.text = I18n.t("Новая пьеса каждые")
	pl.custom_minimum_size = Vector2(200, 0)
	prow.add_child(pl)
	from_spin = _spin(prow, M.period_min if M != null else 3.0)
	var dash := Label.new()
	dash.text = "–"
	prow.add_child(dash)
	to_spin = _spin(prow, M.period_max if M != null else 5.0)
	var mins := Label.new()
	mins.text = I18n.t("мин")
	prow.add_child(mins)
	var apply_period := func(_x: float) -> void:
		if to_spin.value < from_spin.value:
			to_spin.set_value_no_signal(from_spin.value)
		if M != null:
			M.set_period(from_spin.value, to_spin.value)
	from_spin.value_changed.connect(apply_period)
	to_spin.value_changed.connect(apply_period)
	var nrow := HBoxContainer.new()
	nrow.add_theme_constant_override("separation", 8)
	v.add_child(nrow)
	now_label = Label.new()
	now_label.custom_minimum_size = Vector2(400, 0)
	now_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	now_label.add_theme_font_size_override("font_size", 14)
	nrow.add_child(now_label)
	var skip := Button.new()
	skip.text = I18n.t("Другая пьеса")
	skip.pressed.connect(func() -> void:
		if M != null:
			M.skip())
	nrow.add_child(skip)

	# Звуки (Sfx): увімк./вимк. (те саме, що F9) і гучність
	sfx_check = CheckButton.new()
	sfx_check.text = I18n.t("Звуки")
	sfx_check.button_pressed = S == null or S.enabled
	sfx_check.toggled.connect(func(on: bool) -> void:
		if S != null:
			S.set_enabled(on))
	v.add_child(sfx_check)
	var srow := _slider_row(v, I18n.t("Громкость звуков"))
	sfx_slider = srow[0]
	sfx_value = srow[1]
	sfx_slider.value = roundf((S.volume if S != null else 0.8) * 100.0)
	sfx_value.text = "%d %%" % int(sfx_slider.value)
	sfx_slider.value_changed.connect(func(x: float) -> void:
		sfx_value.text = "%d %%" % int(x)
		if S != null:
			S.set_volume(x / 100.0))

	var back := Button.new()
	back.text = I18n.t("Назад")
	back.custom_minimum_size = Vector2(240, 48)
	back.add_theme_font_size_override("font_size", 20)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(close)
	v.add_child(back)
	_update_now()


func _slider_row(parent: Node, text: String) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(200, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = 0
	s.max_value = 100
	s.step = 5
	s.custom_minimum_size = Vector2(260, 24)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(s)
	var val := Label.new()
	val.custom_minimum_size = Vector2(60, 0)
	row.add_child(val)
	return [s, val]


func _spin(parent: Node, value: float) -> SpinBox:
	var sp := SpinBox.new()
	sp.min_value = 1
	sp.max_value = 20
	sp.step = 1
	sp.value = value
	sp.custom_minimum_size = Vector2(80, 0)
	parent.add_child(sp)
	return sp


func _process(delta: float) -> void:
	_t -= delta
	if _t <= 0.0:
		_t = 1.0
		_update_now()


func _update_now() -> void:
	var M: Node = get_node_or_null("/root/Music")
	if M == null:
		return
	var names: Array = M.now_playing().map(func(n): return I18n.t(n))
	now_label.text = I18n.t("Сейчас играет: ") + (", ".join(names) if not names.is_empty() else I18n.t("пьеса готовится…"))


func close() -> void:
	closed.emit()
	queue_free()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()

extends Control
## Сцена перерождения (п.15 правок Huzzah 2026-11-03): после некролога и кнопки «Продолжить» гравец видит
## короткую кинематографичную сцену. Она объясняет механизм: из-за катаклизма душа умершего не находит покоя
## и принудительно направляется на новое перерождение. Новый персонаж и его характеристики здесь не показываются.
## Страницы текста проявляются одна за другой на тёмном фоне с медленными углями и трескающимся кольцом.
## Любая клавиша или клик — к следующей странице, Esc — пропустить всю сцену. Сигнал finished — после последней страницы.

signal finished

const COL_TEXT := Color("d8cfb0")
const COL_DIM := Color("8a8068")
const COL_EMBER := Color("e09a3c")

const FADE_IN: float = 1.2
const HOLD: float = 3.4
const FADE_OUT: float = 0.9
const EMBERS: int = 46

var pages: Array = []          # строки страниц; последняя — «заглавная» крупным шрифтом
var page: int = 0
var done: bool = false
var _t: float = 0.0            # время на текущей странице
var _clock: float = 0.0        # общее время (для углей)
var _label: Label
var _hint: Label
var _seeds: Array = []         # [x, фаза, скорость, размер] углей


## Страницы сцены: dead_name — имя ушедшего, male — его род (для «не обрёл»), чтобы текст читался без новых героев
static func default_pages(dead_name: String, male: bool) -> Array:
	return [
		I18n.t("Небо раскололось давно. Земля так и не срослась."),
		I18n.t("С тех пор души не уходят. Они остаются у края, как вода в треснувшей чаше."),
		(I18n.t("%s не обрёл покоя.") if male else I18n.t("%s не обрела покоя.")) % dead_name,
		I18n.t("Миру нужны руки. Он берёт то, что осталось, и отправляет обратно."),
		I18n.t("Другое имя. Чужая память. Чужие шрамы.\nЭто не милость. Это механизм."),
		I18n.t("Перерождение"),
	]


func setup(page_list: Array) -> void:
	pages = page_list.duplicate()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261103
	for i in EMBERS:
		_seeds.append([rng.randf(), rng.randf() * TAU, rng.randf_range(0.015, 0.05), rng.randf_range(1.2, 3.4)])
	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_color_override("font_color", COL_TEXT)
	_label.add_theme_font_size_override("font_size", 26)
	_label.offset_left = 120.0
	_label.offset_right = -120.0
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	_hint = Label.new()
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -44.0
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.add_theme_color_override("font_color", COL_DIM)
	_hint.text = I18n.t("Любая клавиша — дальше · Esc — пропустить")
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)
	_show_page()


func _show_page() -> void:
	_t = 0.0
	if page >= pages.size():
		return
	_label.text = String(pages[page])
	var last: bool = page == pages.size() - 1
	_label.add_theme_font_size_override("font_size", 44 if last else 26)
	_label.add_theme_color_override("font_color", COL_EMBER if last else COL_TEXT)


## Прозрачность текущей страницы: проявление, пауза, затухание (последняя страница не гаснет сразу)
func page_alpha() -> float:
	if _t < FADE_IN:
		return _t / FADE_IN
	var last: bool = page == pages.size() - 1
	if _t < FADE_IN + HOLD or last:
		return 1.0
	return clampf(1.0 - (_t - FADE_IN - HOLD) / FADE_OUT, 0.0, 1.0)


func page_length() -> float:
	return FADE_IN + HOLD + (FADE_OUT if page < pages.size() - 1 else 1.6)


func _process(delta: float) -> void:
	if done:
		return
	_clock += delta
	_t += delta
	_label.modulate.a = page_alpha()
	if _t >= page_length():
		advance()
	queue_redraw()


## К следующей странице; после последней сцена заканчивается
func advance() -> void:
	if done:
		return
	page += 1
	if page >= pages.size():
		finish()
	else:
		_show_page()


func skip() -> void:
	finish()


func finish() -> void:
	if done:
		return
	done = true
	finished.emit()


func _input(event: InputEvent) -> void:
	if done or not is_visible_in_tree():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			skip()
		else:
			advance()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		advance()
		get_viewport().set_input_as_handled()


func _draw() -> void:
	var sz: Vector2 = size
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0.012, 0.01, 0.018))
	var c: Vector2 = sz * 0.5
	# трескающееся кольцо: к середине сцены разгорается, на последней странице вспыхивает
	var prog: float = clampf((float(page) + clampf(_t / maxf(page_length(), 0.01), 0.0, 1.0)) / maxf(float(pages.size()), 1.0), 0.0, 1.0)
	var r: float = minf(sz.x, sz.y) * (0.16 + 0.12 * prog)
	var gaps: int = 7
	for g in gaps:
		var a0: float = TAU * float(g) / float(gaps) + _clock * 0.03
		var span: float = TAU / float(gaps) * (0.35 + 0.45 * prog)
		draw_arc(c, r, a0, a0 + span, 24, Color(COL_EMBER, 0.10 + 0.5 * prog), 2.0 + 3.0 * prog, true)
	# угли поднимаются снизу вверх, мерцают
	for e in _seeds:
		var y: float = fposmod(1.0 - (float(e[1]) / TAU + _clock * float(e[2])), 1.0)
		var x: float = float(e[0]) + sin(_clock * 0.6 + float(e[1])) * 0.02
		var flick: float = 0.35 + 0.35 * sin(_clock * 2.1 + float(e[1]) * 3.0)
		draw_circle(Vector2(x * sz.x, y * sz.y), float(e[3]), Color(COL_EMBER, clampf(flick * (0.4 + prog), 0.0, 0.9)))

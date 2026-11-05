extends Node
## Сенсорне керування (Android): панель екранних кнопок, щипок для масштабу, кнопка «Назад», масштаб інтерфейсу.
## Працює лише на телефоні/планшеті (або з аргументом `-- --touch`); на ПК нічого не робить.
## Усе зведено до тих самих клавіш і кліків, що й на ПК, тому вікна гри окремої сенсорної логіки не мають.
## Тап по екрану Godot сам перетворює на клік лівою кнопкою (emulate_mouse_from_touch), тож тап-рух героя працює як є.

const BAR_LAYER := 90
const BTN_MIN := Vector2(100, 46)
## Вікна героя й інвентаря розраховані на высоту 800 (панель 700): вище 1,1 вони не вміщаються на екрані телефона
const SCALES := [0.9, 1.0, 1.1]
const DEFAULT_SCALE := 1.0
const CFG_PATH := "user://mobile.cfg"
## Один «крок колеса» ≈ ln(1,25) щипка: масштаб карти йде тим самим кроком, що й колесо миші
const PINCH_STEP := 0.223

var active: bool = false
var ui_scale: float = DEFAULT_SCALE
var _bar: Control
var _more_box: Control
var _more_btn: Button
var _touches: Dictionary = {}
var _pinch_acc: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	active = detect()
	if not active:
		set_process_input(false)
		return
	get_tree().set_auto_accept_quit(false)
	ui_scale = _load_scale()
	_apply_scale()
	_build_bar()


## Телефон/планшет або примусовий режим для перевірки на ПК
static func detect() -> bool:
	return OS.has_feature("mobile") or OS.get_cmdline_user_args().has("--touch") or OS.get_cmdline_args().has("--touch")


func _notification(what: int) -> void:
	if not active:
		return
	# Системна кнопка «Назад» — те саме, що Esc
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		key(KEY_ESCAPE)
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		var g: Node = get_tree().current_scene
		if g != null and g.has_method("save_world") and g.get("ready_done"):
			g.call("save_world")
		get_tree().quit()
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		# Згортання застосунку: зберігаємося, бо ОС може вивантажити гру без попередження
		var g2: Node = get_tree().current_scene
		if g2 != null and g2.has_method("save_world") and g2.get("ready_done"):
			g2.call("save_world")


# =====================================================================
# МАСШТАБ ІНТЕРФЕЙСУ
# =====================================================================
func _apply_scale() -> void:
	get_window().content_scale_factor = ui_scale


func cycle_scale() -> void:
	var i: int = SCALES.find(ui_scale)
	ui_scale = SCALES[(i + 1) % SCALES.size()]
	_apply_scale()
	_save_scale()
	_refresh_labels()


func _load_scale() -> float:
	var cfg := ConfigFile.new()
	if FileAccess.file_exists(CFG_PATH) and cfg.load(CFG_PATH) == OK:
		var s: float = float(cfg.get_value("ui", "scale", DEFAULT_SCALE))
		if SCALES.has(s):
			return s
	return DEFAULT_SCALE


func _save_scale() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("ui", "scale", ui_scale)
	cfg.save(CFG_PATH)


# =====================================================================
# ІМІТАЦІЯ КЛАВІШ І КЛІКІВ
# =====================================================================
func key(code: int, shift: bool = false) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		e.shift_pressed = shift
		Input.parse_input_event(e)


## Права кнопка миші: скасувати маршрут / режим у бою
func right_click() -> void:
	var pos: Vector2 = to_screen(get_viewport().get_mouse_position())
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_RIGHT
		e.pressed = pressed
		e.position = pos
		e.global_position = pos
		Input.parse_input_event(e)


## Подія в логічних координатах (як у вузлах) -> екранні пікселі, які чекає Input.parse_input_event
func to_screen(logical: Vector2) -> Vector2:
	return get_window().get_final_transform() * logical


## pos — у логічних координатах вікна
func wheel(up: bool, pos: Vector2) -> void:
	pos = to_screen(pos)
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
		e.pressed = pressed
		e.position = pos
		e.global_position = pos
		Input.parse_input_event(e)


# =====================================================================
# ЩИПОК (масштаб карти) — кроками колеса, тож діють ті самі межі масштабу
# =====================================================================
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
			# Другий палець: перший вже міг задати маршрут, щипок його скасовує
			if _touches.size() == 2:
				right_click()
		else:
			_touches.erase(event.index)
			if _touches.is_empty():
				_pinch_acc = 0.0
	elif event is InputEventScreenDrag:
		_touches[event.index] = event.position
	elif event is InputEventMagnifyGesture:
		_pinch_acc += log(maxf(event.factor, 0.01))
		while absf(_pinch_acc) >= PINCH_STEP:
			wheel(_pinch_acc > 0.0, event.position)
			_pinch_acc -= PINCH_STEP * signf(_pinch_acc)
		get_viewport().set_input_as_handled()


# =====================================================================
# ПАНЕЛЬ КНОПОК
# =====================================================================
func _build_bar() -> void:
	var layer := CanvasLayer.new()
	layer.layer = BAR_LAYER
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	_bar = Control.new()
	_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_bar)

	# Головна колонка по правому краю: те, чим користуються найчастіше
	var main := VBoxContainer.new()
	main.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	main.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	main.grow_vertical = Control.GROW_DIRECTION_BOTH
	main.add_theme_constant_override("separation", 6)
	main.offset_right = -6
	_bar.add_child(main)
	_btn(main, "Меню", func(): key(KEY_ESCAPE))
	_btn(main, "Герой", func(): key(KEY_I))
	_btn(main, "Сумка", func(): key(KEY_TAB))
	_btn(main, "Карта", func(): key(KEY_M))
	_btn(main, "Действие", func(): key(KEY_E))
	_btn(main, "✕ Отмена", func(): right_click())
	_more_btn = _btn(main, "⋯", _toggle_more)

	# Додаткові кнопки — зліва від головної колонки, ховаються
	_more_box = GridContainer.new()
	(_more_box as GridContainer).columns = 2
	_more_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	_more_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_more_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	_more_box.offset_right = -(BTN_MIN.x + 18)
	_more_box.add_theme_constant_override("h_separation", 6)
	_more_box.add_theme_constant_override("v_separation", 6)
	_more_box.visible = false
	_bar.add_child(_more_box)
	_btn(_more_box, "Журнал", func(): key(KEY_J))
	_btn(_more_box, "Привал", func(): key(KEY_K))
	_btn(_more_box, "Транспорт", func(): key(KEY_R))
	_btn(_more_box, "Герой/камера", func(): key(KEY_G))
	_btn(_more_box, "Справка", func(): key(KEY_F1))
	_btn(_more_box, "Пауза", func(): key(KEY_P))
	_btn(_more_box, "Время +", func(): key(KEY_BRACKETRIGHT))
	_btn(_more_box, "Время −", func(): key(KEY_BRACKETLEFT))
	_btn(_more_box, "Ближе", func(): key(KEY_EQUAL))
	_btn(_more_box, "Дальше", func(): key(KEY_MINUS))
	_btn(_more_box, "Пробел", func(): key(KEY_SPACE))
	_btn(_more_box, "Поиск", func(): key(KEY_F))
	_btn(_more_box, "Интерфейс", cycle_scale)
	_refresh_labels()


func _btn(parent: Control, caption: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = I18n.t(caption)
	b.set_meta("cap", caption)
	b.custom_minimum_size = BTN_MIN
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 18)
	b.modulate = Color(1, 1, 1, 0.78)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _toggle_more() -> void:
	_more_box.visible = not _more_box.visible


func _refresh_labels() -> void:
	if _more_box == null:
		return
	for c in _more_box.get_children():
		if c is Button and c.get_meta("cap", "") == "Интерфейс":
			c.text = "%s ×%s" % [I18n.t("Интерфейс"), str(ui_scale)]

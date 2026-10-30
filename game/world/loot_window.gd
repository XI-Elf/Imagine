extends CanvasLayer
## Вікно «Найдено» після пошуку в полі (пункт 16): гравець бере речі по одній або все, що унесе;
## не взяте лишається на місці (world/foraging.gd stash) і знайдеться при наступному пошуку тут же.
## Поки вікно відкрите, герой стоїть, час іде як завжди.

const Trade := preload("res://city/trade.gd")

signal done(rest: Dictionary)

var items: Dictionary = {}       # id -> скільки лежить перед героєм
var bag: Dictionary = {}
var hero: Actor = null
var _panel: PanelContainer
var _title: Label
var _list: VBoxContainer
var _note: Label


func _ready() -> void:
	layer = 25
	visible = false
	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(460, 0)
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_panel.add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 20)
	box.add_child(_title)
	_list = VBoxContainer.new()
	box.add_child(_list)
	_note = Label.new()
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.add_theme_color_override("font_color", Color(0.9, 0.75, 0.5))
	box.add_child(_note)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	row.add_child(_btn(I18n.t("Взять всё  [E]"), take_all))
	row.add_child(_btn(I18n.t("Оставить остальное  [Esc]"), finish))


func _btn(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(0, 34)
	b.pressed.connect(cb)
	return b


func open(found: Dictionary, title: String, the_bag: Dictionary, a: Actor) -> void:
	items = found.duplicate()
	bag = the_bag
	hero = a
	_title.text = title
	_note.text = ""
	visible = true
	_refresh()
	await get_tree().process_frame
	_panel.reset_size()
	_panel.position = (_panel.get_viewport_rect().size - _panel.size) * 0.5


func is_open() -> bool:
	return visible


func free_kg() -> float:
	return (hero.carry_capacity() if hero != null else 30.0) - Trade.weight(bag)


## Узяти n штук; false — не влазить за вагою
func take(id: String, n: int = 1) -> bool:
	n = mini(n, int(items.get(id, 0)))
	if n <= 0:
		return false
	var kg: float = float(Trade.item(id).get("weight", 0.0))
	if kg > 0.0:
		n = mini(n, int(floor(free_kg() / kg + 0.0001)))
	if n <= 0:
		_note.text = I18n.t("Не унести: %s слишком тяжело (свободно %.1f кг)") % [Trade.item_name(id), maxf(free_kg(), 0.0)]
		return false
	Trade.add(bag, id, n)
	items[id] = int(items[id]) - n
	if int(items[id]) <= 0:
		items.erase(id)
	if hero != null:
		hero.carried_kg = Trade.weight(bag)
	_refresh()
	return true


func take_all() -> void:
	for id in items.keys():
		take(id, int(items[id]))
	if items.is_empty():
		finish()


func finish() -> void:
	if not visible:
		return
	visible = false
	done.emit(items.duplicate())


func _refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	if items.is_empty():
		var l := Label.new()
		l.text = I18n.t("Больше ничего нет")
		_list.add_child(l)
	for id in items:
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = I18n.t("%s ×%d   (%.1f кг)") % [Trade.item_name(id), int(items[id]), float(Trade.item(id).get("weight", 0.0)) * int(items[id])]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		row.add_child(_btn(I18n.t("Взять"), take.bind(id, 1)))
		if int(items[id]) > 1:
			row.add_child(_btn(I18n.t("Все"), take.bind(id, int(items[id]))))
		_list.add_child(row)
	if hero != null and _note.text == "":
		_note.text = I18n.t("Груз: %.1f / %.0f кг") % [Trade.weight(bag), hero.carry_capacity()]


func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.physical_keycode in [KEY_F1, KEY_F10]:
		return   # довідка й гучність музики працюють і над вікном
	if event.physical_keycode == KEY_E:
		take_all()
	elif event.is_action_pressed("ui_cancel"):
		finish()
	get_viewport().set_input_as_handled()

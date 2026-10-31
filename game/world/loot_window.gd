extends CanvasLayer
## Вікно пошуку й знахідок (пункт 16; переробка 2026-10-30). Дві дороги:
##  begin_search — пошук у полі: гравець вибирає, скільки шукати (1–4 або кнопки), обходи йдуть по черзі зі шкалою,
##    кожна знахідка вискакує плиткою одразу; Esc зупиняє пошук, знайдене лишається;
##  open — просто «Найдено» (розбирання туш, старі виклики).
## Плитки: лівий клік — узяти все цієї речі, правий — одну; E — усе, що унесе; Esc — решту лишити на місці.
## Поки вікно відкрите, герой стоїть; час гри рухає round_fn (кожен обхід — свої хвилини).

const Trade := preload("res://city/trade.gd")
const ComicUI := preload("res://ui/comic_ui.gd")

signal done(rest: Dictionary)

const STEP_S := 0.5        # справжніх секунд на обхід: видно, як іде пошук, і не нудно
const TILE := Vector2(96, 92)

var items: Dictionary = {}       # id -> скільки лежить перед героєм
var bag: Dictionary = {}
var hero: Actor = null
var phase: String = ""           # choose | search | loot
var rounds_total: int = 0
var rounds_done: int = 0
var round_fn: Callable           # () -> {ok, found, text, minutes, richness, stop?, ambush?}
var round_min: float = 15.0
var durations: Array = [1, 2, 4, 8]
var ambushed: bool = false
var _wait: float = 0.0
var _fresh: Dictionary = {}      # id -> мить, коли річ вискочила (підсвітка)

var _panel: PanelContainer
var _title: Label
var _place: Label
var _rich: ProgressBar
var _rich_lbl: Label
var _choose: HBoxContainer
var _prog_box: VBoxContainer
var _prog: ProgressBar
var _prog_text: Label
var _log: Label
var _grid: GridContainer
var _note: Label
var _take_btn: Button
var _leave_btn: Button


func _ready() -> void:
	layer = 25
	visible = false
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", ComicUI.panel(22.0, 0.97))
	_panel.custom_minimum_size = Vector2(560, 0)
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)
	_title = _lbl(box, 20, ComicUI.GOLD)
	_place = _lbl(box, 14, ComicUI.DIM)
	_rich_lbl = _lbl(box, 12, ComicUI.DIM)
	_rich_lbl.text = I18n.t("Запас места: каждый обход его вычерпывает, отрастает за трое суток")
	_rich = ProgressBar.new()
	_rich.custom_minimum_size = Vector2(0, 22)
	_rich.show_percentage = false
	_rich.max_value = 1.0
	_rich.step = 0.01
	ComicUI.bar_styles(_rich)
	box.add_child(_rich)
	_choose = HBoxContainer.new()
	_choose.add_theme_constant_override("separation", 6)
	box.add_child(_choose)
	_prog_box = VBoxContainer.new()
	box.add_child(_prog_box)
	_prog = ProgressBar.new()
	_prog.custom_minimum_size = Vector2(0, 26)
	_prog.show_percentage = false
	ComicUI.bar_styles(_prog)
	_prog_box.add_child(_prog)
	_prog_text = _lbl(_prog_box, 15, ComicUI.TEXT)
	_log = _lbl(box, 14, ComicUI.DIM)
	_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	box.add_child(_grid)
	_note = _lbl(box, 14, Color(0.9, 0.75, 0.5))
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	_take_btn = _btn(row, I18n.t("Взять всё  [E]"), take_all)
	_leave_btn = _btn(row, I18n.t("Оставить остальное  [Esc]"), _on_esc)


func _lbl(parent: Control, size: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	parent.add_child(l)
	return l


func _btn(parent: Control, t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(0, 34)
	b.focus_mode = Control.FOCUS_NONE
	ComicUI.button_styles(b)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


# =====================================================================
# ВІДКРИТТЯ
# =====================================================================
## Просто «Найдено»: речі вже знайдено (туші, старі виклики)
func open(found: Dictionary, title: String, the_bag: Dictionary, a: Actor) -> void:
	items = found.duplicate()
	bag = the_bag
	hero = a
	ambushed = false
	rounds_total = 0
	_title.text = title
	_place.visible = false
	_rich.visible = false
	_rich_lbl.visible = false
	_log.text = ""
	_note.text = ""
	_set_phase("loot")


## Пошук у полі. place — «Лес · нетронутое место», richness 0..1, fn — один обхід (cast.gd), here — що лежить тут з минулого разу
func begin_search(title: String, place: String, richness: float, fn: Callable, the_bag: Dictionary, a: Actor, here: Dictionary = {}, minutes_per_round: float = 15.0, choices: Array = [1, 2, 4, 8]) -> void:
	items = here.duplicate()
	bag = the_bag
	hero = a
	round_fn = fn
	round_min = minutes_per_round
	durations = choices
	ambushed = false
	rounds_total = 0
	_title.text = title
	_place.text = place
	_place.visible = true
	_rich.visible = true
	_rich_lbl.visible = true
	_rich.value = richness
	_note.text = ""
	_log.text = I18n.t("Здесь оставлено с прошлого раза.") if not items.is_empty() else I18n.t("Сколько искать? Чем дольше, тем больше найдёте, но место скудеет с каждым обходом.")
	for c in _choose.get_children():
		_choose.remove_child(c)
		c.queue_free()
	for i in durations.size():
		var n: int = int(durations[i])
		_btn(_choose, "%d. %s" % [i + 1, _dur_text(n * round_min)], start.bind(n))
	_set_phase("choose")


func _dur_text(minutes: float) -> String:
	return I18n.t("%d мин") % int(minutes) if minutes < 60.0 else I18n.t("%s ч") % String.num(minutes / 60.0, 1).trim_suffix(".0")


func is_open() -> bool:
	return visible


func is_searching() -> bool:
	return visible and phase == "search"


func _set_phase(p: String) -> void:
	phase = p
	visible = true
	_choose.visible = p == "choose"
	_prog_box.visible = p == "search" or (p == "loot" and rounds_total > 0)
	_log.visible = _log.text != ""
	_take_btn.visible = p == "loot" or (p == "choose" and not items.is_empty())
	_leave_btn.text = I18n.t("Хватит  [Esc]") if p == "search" else (I18n.t("Уйти  [Esc]") if p == "choose" and items.is_empty() else I18n.t("Оставить остальное  [Esc]"))
	_refresh()


func _center() -> void:
	if _panel == null or not visible:
		return
	_panel.reset_size()
	_panel.position = ((_panel.get_viewport_rect().size - _panel.size) * 0.5).floor()


# =====================================================================
# ПОШУК ОБХОДАМИ
# =====================================================================
func start(rounds: int) -> void:
	if phase != "choose":
		return
	rounds_total = maxi(rounds, 1)
	rounds_done = 0
	_prog.max_value = rounds_total
	_log.text = I18n.t("Ищем…")
	_wait = STEP_S * 0.5
	_set_phase("search")
	_update_prog()


## Один обхід; false — пошук скінчився
func step() -> bool:
	if phase != "search":
		return false
	var r: Dictionary = round_fn.call() if round_fn.is_valid() else {"ok": false, "text": ""}
	if not bool(r.get("ok", false)):
		_log.text = String(r.get("text", ""))
		_end_search()
		return false
	rounds_done += 1
	var now: float = Time.get_ticks_msec() / 1000.0
	for id in r["found"]:
		items[id] = int(items.get(id, 0)) + int(r["found"][id])
		_fresh[id] = now
	_rich.value = float(r.get("richness", _rich.value))
	_log.text = I18n.t("Обход %d: %s") % [rounds_done, String(r.get("text", ""))]
	_update_prog()
	if bool(r.get("ambush", false)):
		ambushed = true
		finish()
		return false
	if bool(r.get("stop", false)) or rounds_done >= rounds_total:
		_end_search()
		return false
	_refresh()
	return true


## Прогнати всі обходи одразу (тести)
func run_all() -> void:
	while step():
		pass


func stop_search() -> void:
	if phase == "search":
		_log.text = I18n.t("Хватит искать.") + " " + _log.text
		_end_search()


func _end_search() -> void:
	_note.text = I18n.t("Ничего не нашли.") if items.is_empty() else ""
	_set_phase("loot")


func _update_prog() -> void:
	_prog.value = rounds_done
	_prog_text.text = I18n.t("Обход %d из %d · %s") % [rounds_done, rounds_total, _dur_text(rounds_done * round_min) if rounds_done > 0 else I18n.t("0 мин")]


func _process(delta: float) -> void:
	if not visible:
		return
	if phase == "search":
		_wait -= delta
		if _wait <= 0.0:
			_wait = STEP_S
			step()
	if not _fresh.is_empty():
		for c in _grid.get_children():
			c.queue_redraw()


# =====================================================================
# УЗЯТИ / ЛИШИТИ
# =====================================================================
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
	_note.text = ""
	_refresh()
	return true


func take_all() -> void:
	if phase == "search":
		return
	for id in items.keys():
		take(id, int(items[id]))
	if items.is_empty() and phase == "loot":
		finish()


func finish() -> void:
	if not visible:
		return
	visible = false
	phase = ""
	rounds_total = 0
	_fresh.clear()
	done.emit(items.duplicate())


func _on_esc() -> void:
	if phase == "search":
		stop_search()
	else:
		finish()


func _refresh() -> void:
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	for id in items:
		_grid.add_child(_tile(String(id)))
	if items.is_empty() and phase == "loot":
		var l := Label.new()
		l.text = I18n.t("Больше ничего нет")
		l.add_theme_color_override("font_color", ComicUI.DIM)
		_grid.add_child(l)
	if hero != null and _note.text == "":
		_note.text = I18n.t("Груз: %.1f / %.0f кг") % [Trade.weight(bag), hero.carry_capacity()]
	_center.call_deferred()


func _tile(id: String) -> Control:
	var c := Control.new()
	c.custom_minimum_size = TILE
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.tooltip_text = I18n.t("%s ×%d, %.1f кг\nЛКМ — взять все, ПКМ — одну") % [Trade.item_name(id), int(items.get(id, 0)), float(Trade.item(id).get("weight", 0.0)) * int(items.get(id, 0))]
	c.draw.connect(_draw_tile.bind(c, id))
	c.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and phase != "search":
			if e.button_index == MOUSE_BUTTON_LEFT:
				take(id, int(items.get(id, 0)))
			elif e.button_index == MOUSE_BUTTON_RIGHT:
				take(id, 1))
	return c


func _draw_tile(c: Control, id: String) -> void:
	var r := Rect2(Vector2.ZERO, TILE)
	var age: float = Time.get_ticks_msec() / 1000.0 - float(_fresh.get(id, -10.0))
	ComicUI.draw_box(c, "slot", r, Color(1.5, 1.3, 0.9) if age < 0.8 else Color.WHITE)
	var pop: float = 1.0 + 0.25 * maxf(0.0, 1.0 - age / 0.35)
	draw_find(c, id, Rect2(Vector2(TILE.x * 0.5, 36.0) - Vector2(22, 22) * pop, Vector2(44, 44) * pop))
	var font: Font = ThemeDB.fallback_font
	var cnt: String = "×%d" % int(items.get(id, 0))
	c.draw_string_outline(font, Vector2(TILE.x - 40, 62), cnt, HORIZONTAL_ALIGNMENT_RIGHT, 30, 15, 4, ComicUI.INK)
	c.draw_string(font, Vector2(TILE.x - 40, 62), cnt, HORIZONTAL_ALIGNMENT_RIGHT, 30, 15, ComicUI.AMBER)
	var nm: String = Trade.item_name(id)
	c.draw_string_outline(font, Vector2(6, TILE.y - 12), nm, HORIZONTAL_ALIGNMENT_CENTER, TILE.x - 12, 11, 3, ComicUI.INK)
	c.draw_string(font, Vector2(6, TILE.y - 12), nm, HORIZONTAL_ALIGNMENT_CENTER, TILE.x - 12, 11, ComicUI.TEXT)


## Знахідки малюються кодом у стилі коміксу: темний контур, приглушені кольори
static func draw_find(ci: CanvasItem, id: String, r: Rect2) -> void:
	var o: Vector2 = r.get_center()
	var s: float = minf(r.size.x, r.size.y) * 0.5
	var ink := ComicUI.INK
	match id:
		"berries":
			for p in [Vector2(-0.3, 0.1), Vector2(0.25, 0.15), Vector2(0.0, -0.25), Vector2(-0.05, 0.45)]:
				ci.draw_circle(o + p * s, s * 0.3, ink)
				ci.draw_circle(o + p * s, s * 0.24, Color("7a2a3a"))
				ci.draw_circle(o + p * s + Vector2(-0.08, -0.08) * s, s * 0.07, Color("d88a9a"))
			ci.draw_line(o + Vector2(0, -0.5) * s, o + Vector2(0.35, -0.85) * s, Color("4f6a34"), 3.0)
		"mushrooms", "toadstool":
			var cap: Color = Color("8a5a34") if id == "mushrooms" else Color("a8382a")
			ci.draw_rect(Rect2(o + Vector2(-0.15, -0.1) * s, Vector2(0.3, 0.8) * s), Color("d8cfb0"))
			ci.draw_rect(Rect2(o + Vector2(-0.15, -0.1) * s, Vector2(0.3, 0.8) * s), ink, false, 2.0)
			ci.draw_colored_polygon(_pts(o, s, [[-0.75, 0.0], [-0.5, -0.5], [0.0, -0.7], [0.5, -0.5], [0.75, 0.0]]), cap)
			ci.draw_polyline(_pts(o, s, [[-0.75, 0.0], [-0.5, -0.5], [0.0, -0.7], [0.5, -0.5], [0.75, 0.0], [-0.75, 0.0]]), ink, 2.0)
			if id == "toadstool":
				for p in [Vector2(-0.35, -0.25), Vector2(0.1, -0.45), Vector2(0.4, -0.2)]:
					ci.draw_circle(o + p * s, s * 0.08, Color("efe6d2"))
		"brushwood", "driftwood":
			var wc: Color = Color("6b4a2e") if id == "brushwood" else Color("9a8a74")
			for i in 3:
				var a: float = -0.5 + i * 0.5
				var d := Vector2(cos(a), sin(a)) * s * 0.85
				ci.draw_line(o - d, o + d, ink, 7.0)
				ci.draw_line(o - d, o + d, wc, 4.0)
		"wild_herbs", "reed", "roots":
			var hc: Color = {"wild_herbs": Color("5f8a3a"), "reed": Color("a89a5a"), "roots": Color("8a6a44")}[id]
			for i in 5:
				var x: float = -0.5 + i * 0.25
				var tip := o + Vector2(x * 1.2, -0.8 if id != "roots" else 0.8) * s
				ci.draw_line(o + Vector2(x * 0.4, 0.0) * s, tip, ink, 4.0)
				ci.draw_line(o + Vector2(x * 0.4, 0.0) * s, tip, hc, 2.5)
			ci.draw_circle(o, s * 0.18, ink)
			ci.draw_circle(o, s * 0.13, Color("6b4a2e") if id == "roots" else hc.darkened(0.3))
		"flint", "scrap":
			var fc: Color = Color("5a5e66") if id == "flint" else Color("6f5a48")
			var pts := _pts(o, s, [[-0.6, 0.4], [-0.4, -0.4], [0.2, -0.6], [0.65, -0.1], [0.4, 0.5]])
			ci.draw_colored_polygon(pts, fc)
			pts.append(pts[0])
			ci.draw_polyline(pts, ink, 2.0)
			if id == "scrap":
				ci.draw_circle(o + Vector2(0.1, 0.0) * s, s * 0.15, ComicUI.AMBER.darkened(0.4))
			else:
				ci.draw_line(o + Vector2(-0.2, -0.2) * s, o + Vector2(0.3, 0.1) * s, ComicUI.STEEL_HI, 2.0)
		"amber", "old_coin":
			var ac: Color = ComicUI.AMBER if id == "amber" else Color("b8a060")
			ci.draw_circle(o, s * 0.62, ink)
			ci.draw_circle(o, s * 0.55, ac)
			ci.draw_circle(o + Vector2(-0.2, -0.2) * s, s * 0.14, Color(1, 1, 1, 0.5))
		"shellfish":
			ci.draw_colored_polygon(_pts(o, s, [[-0.7, 0.3], [0.0, -0.6], [0.7, 0.3], [0.0, 0.5]]), Color("8a8a9a"))
			for i in 4:
				ci.draw_line(o + Vector2(0.0, 0.45) * s, o + Vector2(-0.5 + i * 0.33, -0.1) * s, ink, 1.5)
		_:
			# Мішечок з першою літерою назви
			ci.draw_colored_polygon(_pts(o, s, [[-0.55, -0.4], [0.55, -0.4], [0.7, 0.6], [-0.7, 0.6]]), Color("7a6448"))
			ci.draw_line(o + Vector2(-0.55, -0.4) * s, o + Vector2(0.55, -0.4) * s, ink, 3.0)
			var nm: String = Trade.item_name(id)
			ci.draw_string(ThemeDB.fallback_font, o + Vector2(-s, s * 0.35), nm.left(1).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, s * 2.0, int(s * 0.9), ComicUI.TEXT)


static func _pts(o: Vector2, s: float, a: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in a:
		out.append(o + Vector2(p[0], p[1]) * s)
	return out


func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.physical_keycode in [KEY_F1, KEY_F10]:
		return   # довідка й гучність музики працюють і над вікном
	var k: int = event.physical_keycode
	if phase == "choose" and k >= KEY_1 and k < KEY_1 + durations.size():
		start(int(durations[k - KEY_1]))
	elif k == KEY_E:
		take_all()
	elif event.is_action_pressed("ui_cancel"):
		_on_esc()
	get_viewport().set_input_as_handled()

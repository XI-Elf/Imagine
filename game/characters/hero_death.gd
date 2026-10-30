extends Node
## Загибель героя (питання Q06 і Q27, Huzzah 2026-10-24): після смерті гра сама створює випадкового нового персонажа,
## гравець продовжує за нього або починає заново. Переноситься поступ поселень і світу: час, погода, ріст міст
## і здані доручення, запаси крамниць, обшукані схованки й руїни. Не переноситься все, що пов'язане з колишнім героєм
## (forget_hero): гроші й речі (новий герой виходить із набором нової гри, Worlds.start_inventory), навички
## (новий Actor), лічильник перемог, узяті доручення, оплачений прохід у брамника, мітка чужинця, розвіданий план міста.
## Системи репутації немає й не будуємо (Q27).
##
## Екран сам стежить за героєм cast (живе дочірнім у characters/cast.gd), тому однаково спрацьовує
## після смерті на карті, у місті, після бою й під час завантаження збереження із загиблим героєм.
## Якщо герой загинув у місті, спершу виходимо на карту до брами (Worlds.leave); бій закінчується сам.
## «Продовжити» — новий герой біля брами міста (cast.create_hero). «Почати заново» — екран створення героя
## і новий світ, як «Нова гра» в головному меню (Engine meta aw_new_hero, characters/cast.gd).

const P := preload("res://characters/hero_profile.gd")
const R := preload("res://characters/actor_rules.gd")
const HeroCreateScript := preload("res://characters/hero_create.gd")
const GAME_SCENE := "res://game.tscn"

const COL_TEXT := Color("d8cfb0")
const COL_DIM := Color("9a9078")
const COL_GOLD := Color("c9a24b")
const COL_BAD := Color("e08a7a")

var cast: Node2D
var active: bool = false          # екран відкритий: cast не приймає клавіш
var params: Dictionary = {}       # випадковий новий персонаж (HeroProfile params)
var dead_name: String = ""
var _rng := RandomNumberGenerator.new()
var _layer: CanvasLayer
var _creator: CanvasLayer
var _title: Label
var _cause: Label
var _bio: Label
var _stats: Label
var _traits: Label
var _continue_btn: Button


func setup(c: Node2D) -> void:
	cast = c
	_rng.randomize()
	_build()


func _process(_delta: float) -> void:
	if cast == null or cast.game == null or not cast.game.ready_done:
		return
	var a: Actor = cast.hero["actor"] if not cast.hero.is_empty() else null
	if a == null or a.alive:
		if active:
			_close()
		return
	if not active:
		var w: Node = get_node_or_null("/root/Worlds")
		if w != null and w.game == cast.game:
			if w.busy:
				return
			if w.is_away():
				# Бій сам поверне у світ, звідки почався; з міста виходимо до брами
				if not w.is_battle():
					w.leave()
				return
		open(a)
	_layer.visible = _creator == null and not cast.game.menu_open


## Відкрити екран для загиблого героя a й кинути кості нового персонажа
func open(a: Actor) -> void:
	active = true
	dead_name = a.display_name
	params = P.random_params(_rng)
	_title.text = (I18n.t("%s погибла") if _female(a) else I18n.t("%s погиб")) % dead_name
	_cause.text = I18n.t("Причина: %s. Вещи и деньги пропали. Мир остаётся прежним: время, города, сданные поручения, обысканные руины.") % \
		Actor.DEATH_CAUSES.get(a.death_cause, a.death_cause)
	var w: Node = get_node_or_null("/root/Worlds")
	var bag: Variant = w.get("inventory") if w != null else null
	if bag is Dictionary and int(bag.get("items", {}).get("horse", 0)) > 0:
		_cause.text += I18n.t("\nЛошадь погибла вместе с героем.")
	if bag is Dictionary and int(bag.get("items", {}).get("cart", 0)) > 0:
		_cause.text += I18n.t(" Повозка с вещами осталась на месте гибели и пропадёт через %d дня.") % int(CART_DAYS)
	_bio.text = P.biography(params)
	var parts: Dictionary = P.stat_parts(params)
	var st: PackedStringArray = []
	for s in P.stats_list():
		st.append("%s %d" % [P.stat_name(s), int(parts[s]["total"])])
	st.append(I18n.t("Удача %d") % int(parts["luck"]["total"]))
	_stats.text = "   ".join(st)
	var tr: PackedStringArray = []
	for t in params.get("traits", []):
		tr.append(String(R.trait_def(t).get("title", t)))
	_traits.text = I18n.t("Черты: ") + (", ".join(tr) if not tr.is_empty() else I18n.t("нет"))
	var male: bool = String(params.get("gender", "female")) == "male"
	_continue_btn.text = I18n.t("Продолжить за %s (Enter)") % (I18n.t("него") if male else I18n.t("неё"))
	_layer.visible = true


# Рід за профілем загиблого (у героя без профілю — чоловічий). Цілими словами: в українській «загинув / загинула»
func _female(a: Actor) -> bool:
	return String(a.profile.get("gender", "male")) == "female"


## Продовжити за нового персонажа: він з'являється біля брами міста, світ не змінюється
func continue_as_new() -> void:
	if not active:
		return
	var w: Node = get_node_or_null("/root/Worlds")
	var now: float = cast.game.clock.total_seconds if cast.game.get("clock") != null else 0.0
	leave_cart(w, cast.hero.get("pos", Vector2.ZERO), now)
	forget_hero(w)
	var p: Dictionary = params
	_close()
	cast.create_hero(p)
	cast._event(I18n.t("Новый герой: %s") % String(p.get("name", "")))


# ---------------------------------------------------------------------
# Q32 (Huzzah 2026-10-27, своя відповідь): кінь гине разом із героєм, віз із речами лишається
# на місці загибелі й через три дні гри зникає разом із вмістом. На карті його не малюємо:
# новий герой знаходить його сам (F поруч, cast.gd). Вдягнене на загиблому у віз не потрапляє.
# ---------------------------------------------------------------------
const CART_DAYS: float = 3.0
const CART_REACH_M: float = 25.0


## Перед forget_hero: якщо в загиблого був віз, він із речами лишається в Worlds.left_carts
static func leave_cart(w: Node, pos: Vector2, now_s: float) -> bool:
	if w == null or not (w.get("inventory") is Dictionary) or int(w.inventory.get("items", {}).get("cart", 0)) <= 0:
		return false
	var items: Dictionary = w.inventory["items"].duplicate()
	items.erase("horse")
	for slot in w.inventory.get("equipped", {}):
		var id: String = String(w.inventory["equipped"][slot])
		if items.has(id):
			items[id] = int(items[id]) - 1
			if int(items[id]) <= 0:
				items.erase(id)
	w.left_carts.append({"pos": [pos.x, pos.y], "until": now_s + CART_DAYS * 86400.0, "items": items})
	return true


## Віз у CART_REACH_M від точки, що ще не зник; зниклі прибираються. -1 — немає
static func cart_near(w: Node, pos: Vector2, now_s: float) -> int:
	if w == null or not (w.get("left_carts") is Array):
		return -1
	w.left_carts = w.left_carts.filter(func(c): return float(c.get("until", 0.0)) > now_s)
	for i in w.left_carts.size():
		var p: Array = w.left_carts[i].get("pos", [0.0, 0.0])
		if Vector2(float(p[0]), float(p[1])).distance_to(pos) <= CART_REACH_M:
			return i
	return -1


## Забрати віз i в сумку героя: речі й сам віз (тягти його потрібен кінь). Відповідь — текст події
static func take_cart(w: Node, i: int) -> String:
	var c: Dictionary = w.left_carts[i]
	w.left_carts.remove_at(i)
	var bag: Dictionary = w.inventory
	var n: int = 0
	for id in c.get("items", {}):
		bag["items"][id] = int(bag["items"].get(id, 0)) + int(c["items"][id])
		n += int(c["items"][id])
	return I18n.t("Повозка прежнего героя: забрано вещей %d (с повозкой)") % n


## Забути все, що пов'язане із загиблим героєм; поступ поселень (growth.done, крамниці, схованки) лишається
static func forget_hero(w: Node) -> void:
	if w == null:
		return
	if w.has_method("start_inventory"):
		# Сумка змінюється на місці: на неї посилаються вікна героя й торгівля
		w.inventory.clear()
		w.inventory.merge(w.start_inventory())
	w.battles_won = 0
	if w.get("chronicle") is Array:
		w.chronicle.clear()
	for id in w.city_states:
		var st: Variant = w.city_states[id]
		if not (st is Dictionary):
			continue
		# Узяті доручення рахують км і перемоги від колишнього героя (city_growth.gd take)
		if st.get("growth") is Dictionary:
			st["growth"]["taken"] = {}
		st["paid_gate"] = {}
		st["intruder_until"] = -1.0
		# План міста й знахідки на ньому — пам'ять колишнього героя
		st.erase("fog")
		st["discovered"] = []


## Почати заново: екран створення героя, потім новий світ. Esc — назад до цього екрана
func start_over() -> void:
	if not active or _creator != null:
		return
	_creator = HeroCreateScript.new()
	add_child(_creator)
	_creator.finished.connect(func(p: Dictionary) -> void:
		_creator.queue_free()
		_creator = null
		if p.is_empty():
			return
		Engine.set_meta("aw_load", "")
		Engine.set_meta("aw_new_hero", p)
		get_tree().change_scene_to_file(GAME_SCENE))


func _close() -> void:
	active = false
	params = {}
	_layer.visible = false


func _input(event: InputEvent) -> void:
	if not active or not _layer.visible or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k: Key = (event as InputEventKey).keycode
	if k == KEY_ENTER or k == KEY_KP_ENTER:
		continue_as_new()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------
# ЕКРАН
# ---------------------------------------------------------------------
func _build() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 70   # над картою й містом, під екраном створення героя (80)
	_layer.visible = false
	add_child(_layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.04, 0.88)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", preload("res://ui/comic_ui.gd").panel(22.0, 0.97))   # рамка коміксу (Q24)
	panel.custom_minimum_size = Vector2(640.0, 0.0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	_title = _label(26, COL_BAD, true)
	box.add_child(_title)
	_cause = _label(15, COL_DIM)
	box.add_child(_cause)
	box.add_child(HSeparator.new())
	var head := _label(19, COL_GOLD)
	head.text = I18n.t("Новый путник")
	box.add_child(head)
	_bio = _label(17, COL_TEXT)
	box.add_child(_bio)
	_stats = _label(15, COL_TEXT)
	box.add_child(_stats)
	_traits = _label(15, COL_DIM)
	box.add_child(_traits)
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 14)
	box.add_child(btns)
	_continue_btn = _button(I18n.t("Продолжить (Enter)"), continue_as_new)
	_continue_btn.add_theme_color_override("font_color", COL_GOLD)
	btns.add_child(_continue_btn)
	btns.add_child(_button(I18n.t("Начать заново"), start_over))


func _label(size: int, color: Color, centered: bool = false) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(600.0, 0.0)
	if centered:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(220.0, 42.0)
	b.add_theme_font_size_override("font_size", 18)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b

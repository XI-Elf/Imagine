extends CanvasLayer
## Окно героя — одно на всю игру вместо прежнего листа (I) и сумки города (Tab). Вкладки:
## 1 Характеристики (кто он, 7 характеристик и Удача по частям, шкалы, состояния, производные),
## 2 Навыки (уровни навыков пака и опыт), 3 Черты (черты характера, мировоззрение, биография),
## 4 Инвентарь (общая сумка Worlds.inventory: деньги, вещи, вес; использовать, выбросить, взять в бой).
## Хозяин (cast.gd на карте, city_world.gd в городе) зовёт setup(герой, сумка) и open(вкладка).
## Пока окно открыто, клавиши забирает оно: 1–4 вкладки, I / Tab — закрыть или перейти, Esc — закрыть.

signal closed

const P := preload("res://characters/hero_profile.gd")
const R := preload("res://characters/actor_rules.gd")
const Trade := preload("res://city/trade.gd")
const Inv := preload("res://characters/inventory_view.gd")
const ComicUI := preload("res://ui/comic_ui.gd")
const BATTLE_CONFIG := "res://data/battle/config.tres"

const TABS: Array = ["stats", "skills", "traits", "bag"]
const TAB_TITLES: Dictionary = {"stats": "Характеристики", "skills": "Навыки", "traits": "Черты характера", "bag": "Инвентарь"}
const COL_TEXT := Color("d8cfb0")
const COL_DIM := Color("9a9078")
const COL_GOLD := Color("c9a24b")
const COL_GOOD := Color("8fd18a")
const COL_BAD := Color("e08a7a")

var actor_fn: Callable          # () -> Actor
var bag_fn: Callable            # () -> Dictionary {money, items}
var tab: String = "stats"
var _panel: PanelContainer
var _title: Label
var _tab_btns: Dictionary = {}
var _body: VBoxContainer
var _scroll: ScrollContainer
var _note: Label
var _sig: String = ""
var _t: float = 0.0
var _say_t: float = 0.0
var inv_sel: String = ""        # выбранная вещь во вкладке «Инвентарь»
var inv_filter: String = "all"  # фильтр сумки (inventory_view.FILTERS)
var inv_page: int = 0
var inv_sort: bool = false      # «По типу»
var inv_drop_armed: bool = false   # «Бросить всё» нажато один раз, ждёт подтверждения
var _drop_t: float = 0.0


func setup(get_actor: Callable, get_bag: Callable) -> void:
	actor_fn = get_actor
	bag_fn = get_bag


func _ready() -> void:
	layer = 40
	visible = false
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP   # окно модальное: клик мимо не ведёт героя (hero_route.gd)
	add_child(root)
	_panel = PanelContainer.new()
	# рамка комикса: тёмная сталь с заклёпками, внутри уголь, сверху янтарная линза (Q08 D, Q24 A, 2026-10-24)
	_panel.add_theme_stylebox_override("panel", ComicUI.panel(26.0))
	ComicUI.tech_plate(_panel)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(960.0, 700.0)
	root.add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_panel.add_child(v)
	_title = _label("", 22, COL_GOLD)
	_title.add_theme_constant_override("outline_size", 4)
	_title.add_theme_color_override("font_outline_color", Inv.INK)
	v.add_child(_title)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	v.add_child(tabs)
	for i in TABS.size():
		var b := Button.new()
		b.text = "%d  %s" % [i + 1, TAB_TITLES[TABS[i]]]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		_style_tab(b)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(show_tab.bind(TABS[i]))
		_tab_btns[TABS[i]] = b
		tabs.add_child(b)
	v.add_child(HSeparator.new())
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.custom_minimum_size = Vector2(0.0, 534.0)
	v.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 4)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)
	_note = _label("1–4 вкладки · I характеристики · Tab инвентарь · Esc закрыть", 13, COL_DIM)
	v.add_child(_note)


## Вкладки — стальные таблички комикса; выбранная (нажатая) — с янтарным отливом
func _style_tab(b: Button) -> void:
	ComicUI.button_styles(b, 16)


func is_open() -> bool:
	return visible


func open(which: String = "") -> void:
	if which != "":
		tab = which
	visible = true
	show_tab(tab)


func close() -> void:
	if visible:
		visible = false
		closed.emit()


## I / Tab у хозяина: открыть на вкладке; если уже открыто на ней — закрыть
func toggle(which: String) -> void:
	if visible and tab == which:
		close()
	else:
		open(which)


func show_tab(which: String) -> void:
	tab = which
	for k in _tab_btns:
		_tab_btns[k].set_pressed_no_signal(k == tab)
	_sig = ""
	refresh()
	_scroll.scroll_vertical = 0


func _actor() -> Actor:
	return actor_fn.call() if actor_fn.is_valid() else null


func _bag() -> Dictionary:
	var b: Variant = bag_fn.call() if bag_fn.is_valid() else null
	return b if b is Dictionary else {}


func _process(delta: float) -> void:
	if not visible:
		return
	_panel.position = (_panel.get_parent().size - _panel.size) * 0.5
	_say_t = maxf(_say_t - delta, 0.0)
	if inv_drop_armed:
		_drop_t -= delta
		if _drop_t <= 0.0:
			inv_drop_armed = false
			refresh_bag()
	_t += delta
	if _t >= 0.5:
		_t = 0.0
		refresh()


## Перестраивается, только когда что-то поменялось (иначе кнопки не нажать)
func refresh() -> void:
	if _body == null:
		return
	var a: Actor = _actor()
	var sig: String = tab + "|" + JSON.stringify(_bag())
	if a != null:
		sig += "|%s|%s|%s|%d" % [a.display_name, JSON.stringify(a.skills), JSON.stringify(a.traits), int(a.carry_capacity())]
		if tab == "bag":   # строка показателей сверху
			for r in Actor.RESOURCES:
				sig += "|%d" % int(a.res.get(r, 0.0))
		if tab == "stats":
			sig += "|%d" % Time.get_ticks_msec()   # шкалы меняются всё время, на вкладке нет кнопок
	if sig == _sig:
		return
	_sig = sig
	for c in _body.get_children():
		c.queue_free()
	if a == null:
		_title.text = "Героя нет"
		_body.add_child(_label("Создайте героя: G на карте.", 16, COL_DIM))
		return
	_title.text = "%s — %s" % [a.display_name, TAB_TITLES[tab]]
	match tab:
		"stats":
			_fill_stats(a)
		"skills":
			_fill_skills(a)
		"traits":
			_fill_traits(a)
		"bag":
			_fill_bag(a)


# =====================================================================
# ХАРАКТЕРИСТИКИ
# =====================================================================
func _fill_stats(a: Actor) -> void:
	var pf: Dictionary = a.profile
	if not pf.is_empty():
		var g: String = String(P.C()["genders"].get(pf.get("gender", ""), {}).get("title", ""))
		var o: String = String(P.C()["origins"].get(pf.get("origin", ""), {}).get("title", ""))
		var pr: String = String(P.C()["professions"].get(pf.get("profession", ""), {}).get("title", ""))
		_body.add_child(_label("%s, %d %s · %s · %s · %s" % [g, int(pf.get("age", 0)), P.years(int(pf.get("age", 0))), o, pr,
			P.alignment_name(pf.get("alignment", {}))], 15, COL_TEXT))
	else:
		_body.add_child(_label("Герой создан до окна персонажа: происхождения и черт нет.", 14, COL_DIM))
	_body.add_child(_label("Характеристики", 17, COL_GOLD))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	_body.add_child(grid)
	var parts: Dictionary = pf.get("stat_parts", {})
	for s in P.stats_list() + ["luck"]:
		grid.add_child(_label(P.stat_name(s), 16, COL_TEXT))
		grid.add_child(_label(str(int(a.stat(s))), 18, COL_GOLD))
		var tip: String = ""
		if parts.has(s):
			var e: Dictionary = parts[s]
			var bits: Array = ["очки %d" % int(e.get("base", 4))]
			for k in [["gender", "пол"], ["age", "возраст"], ["background", "прошлое"], ["traits", "черты"]]:
				if int(e.get(k[0], 0)) != 0:
					bits.append("%s %+d" % [k[1], int(e[k[0]])])
			if int(e.get("total", a.stat(s))) != int(a.stat(s)):
				bits.append("сейчас %+d" % (int(a.stat(s)) - int(e.get("total", 0))))
			tip = ", ".join(bits)
		grid.add_child(_label(tip, 13, COL_DIM))
	_body.add_child(HSeparator.new())
	_body.add_child(_label("Состояние", 17, COL_GOLD))
	var shown: Dictionary = {"hunger": "Сытость", "thirst": "Вода", "stamina": "Запас сил"}
	var ch: Dictionary = R.characteristics()
	for r in Actor.RESOURCES:
		var row := HBoxContainer.new()
		var l := _label(String(shown.get(r, ch.get(r, {}).get("name_ru", r))), 15, COL_TEXT)
		l.custom_minimum_size = Vector2(160.0, 0.0)
		row.add_child(l)
		var bar := ProgressBar.new()
		bar.max_value = a.max_of(r)
		bar.value = float(a.res.get(r, 0.0))
		bar.custom_minimum_size = Vector2(320.0, 18.0)
		bar.show_percentage = false
		row.add_child(bar)
		row.add_child(_label(" %d / %d" % [int(a.res.get(r, 0.0)), int(a.max_of(r))], 14, COL_DIM))
		_body.add_child(row)
	var cond: Array = []
	for c in a.conditions:
		cond.append(String(R.condition(c["id"]).get("name_ru", c["id"])) + ("" if c["id"] != "radiation_sickness" else " (стадия %d)" % int(c["stage"])))
	for bf in a.buffs:
		cond.append("+ %s (%.0f ч)" % [R.buffs().get(bf["id"], {}).get("name_ru", bf["id"]), float(bf["left_h"])])
	_body.add_child(_wrap("Травмы, болезни, эффекты: " + (", ".join(cond) if not cond.is_empty() else "нет"), 14, COL_TEXT))
	var dv: Dictionary = a.derived()
	_body.add_child(_wrap("Сила удара ×%.2f · Поиск ×%.2f · Скорость ×%.2f · Переносимый вес %.0f кг · Защита от проклятья %d %% · Пройдено %.1f км" % [
		dv["attack_power"], dv["search_efficiency"], dv["move_speed"], dv["carry_weight"], int(dv["radiation_resist"] * 100.0), a.distance_m / 1000.0], 14, COL_DIM))


# =====================================================================
# НАВЫКИ
# =====================================================================
func _fill_skills(a: Actor) -> void:
	var sk: Dictionary = R.skills()
	for k in sk:
		var lv: int = a.skill_level(k)
		var mx: int = int(sk[k].get("max_level", 10))
		var table: Array = R.xp_table(k)
		var xp: float = float(a.skills.get(k, {}).get("xp", 0.0))
		var row := HBoxContainer.new()
		var l := _label("%s  %d / %d" % [sk[k].get("name_ru", k), lv, mx], 16, COL_GOLD if lv > 0 else COL_TEXT)
		l.custom_minimum_size = Vector2(300.0, 0.0)
		row.add_child(l)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(240.0, 16.0)
		bar.show_percentage = false
		var lo: float = float(table[lv - 1]) if lv > 0 and lv - 1 < table.size() else 0.0
		var hi: float = float(table[lv]) if lv < mini(mx, table.size()) else lo
		bar.max_value = maxf(hi - lo, 1.0)
		bar.value = clampf(xp - lo, 0.0, bar.max_value) if hi > lo else bar.max_value
		row.add_child(bar)
		row.add_child(_label("  опыт %d%s" % [int(xp), (" / %d" % int(hi)) if hi > lo else " (предел)"], 13, COL_DIM))
		_body.add_child(row)
		_body.add_child(_wrap(String(sk[k].get("description", "")), 13, COL_DIM))
	_body.add_child(_wrap("Опыт растёт от дела: Выживание — в пути, Медицина — при лечении. Интеллект и черты «Трудолюбивый», «Грамотный» ускоряют рост.", 13, COL_DIM))


# =====================================================================
# ЧЕРТЫ ХАРАКТЕРА
# =====================================================================
func _fill_traits(a: Actor) -> void:
	if a.traits.is_empty():
		_body.add_child(_label("Черт характера нет.", 15, COL_DIM))
	for t in a.traits:
		var c: int = int(R.trait_def(t).get("cost", 0))
		_body.add_child(_wrap(P.trait_text(t), 15, COL_GOOD if c > 0 else COL_BAD))
	var al: Dictionary = a.profile.get("alignment", P.alignment(a.traits))
	_body.add_child(HSeparator.new())
	_body.add_child(_label("Мировоззрение: %s (добро %+d, закон %+d)" % [P.alignment_name(al), int(al.get("moral", 0)), int(al.get("order", 0))], 16, COL_GOLD))
	var bio: String = String(a.profile.get("biography", ""))
	if bio != "":
		_body.add_child(HSeparator.new())
		_body.add_child(_label("История", 17, COL_GOLD))
		_body.add_child(_wrap(bio, 15, Color("e6dcc0")))


# =====================================================================
# ИНВЕНТАРЬ
# =====================================================================
func _item_weapons() -> Dictionary:
	if ResourceLoader.exists(BATTLE_CONFIG):
		var cfg: Resource = load(BATTLE_CONFIG)
		var w: Variant = cfg.get("item_weapons") if cfg != null else null
		if w is Dictionary:
			return w
	return {}


func _loadout_max() -> int:
	if ResourceLoader.exists(BATTLE_CONFIG):
		var cfg: Resource = load(BATTLE_CONFIG)
		if cfg != null and cfg.get("loadout_max") != null:
			return int(cfg.get("loadout_max"))
	return 3


## Доспех в бою — из надетого на «Тело» (items.json wear.armor), иначе без доспеха
func _hero_armor() -> Resource:
	var id: String = armor_of(_bag())
	var p: String = "res://data/battle/armor/%s.tres" % id
	if id != "none" and ResourceLoader.exists(p):
		return load(p)
	return null


static func armor_of(bag: Dictionary) -> String:
	var body: String = String(bag.get("equipped", {}).get("body", ""))
	if body == "" or Trade.count(bag, body) <= 0:
		return "none"
	return String(Trade.item(body).get("wear", {}).get("armor", "none"))


## Кукла персонажа: слоты, герой, сумка клетками (characters/inventory_view.gd)
func _fill_bag(a: Actor) -> void:
	var bag: Dictionary = _bag()
	if bag.is_empty():
		_body.add_child(_label("Сумки нет.", 15, COL_DIM))
		return
	if Trade.count(bag, inv_sel) <= 0:
		inv_sel = ""
	var view := Inv.new()
	view.setup(self, a, bag, _item_weapons(), _loadout_max(), _hero_armor())
	inv_page = clampi(inv_page, 0, view.pages() - 1)
	_body.add_child(view)
	if _say_t <= 0.0:
		_note.text = "Клик — выбрать · двойной клик — съесть/выпить · колесо — страницы · 1–4 вкладки · Esc закрыть"


func refresh_bag() -> void:
	_sig = ""
	refresh()


## Одежда: bag.equipped {slot: id}; надетая вещь остаётся в сумке (вес считается), в слоте одна вещь
func equip_item(id: String) -> void:
	var bag: Dictionary = _bag()
	var w: Dictionary = Trade.item(id).get("wear", {})
	if bag.is_empty() or w.is_empty() or Trade.count(bag, id) <= 0:
		return
	var eq: Dictionary = bag.get("equipped", {})
	var old: String = String(eq.get(w["slot"], ""))
	eq[String(w["slot"])] = id
	bag["equipped"] = eq
	_say("Надето: %s%s" % [Trade.item_name(id), (" (снято: %s)" % Trade.item_name(old)) if old != "" and old != id else ""])
	refresh_bag()


func unequip_item(id: String) -> void:
	var eq: Dictionary = _bag().get("equipped", {})
	for slot in eq.keys():
		if eq[slot] == id:
			eq.erase(slot)
			_say("Снято: %s" % Trade.item_name(id))
	refresh_bag()


## Убрать из слотов то, чего больше нет в сумке (после «Выбросить»)
func _fix_equipped(bag: Dictionary) -> void:
	var eq: Dictionary = bag.get("equipped", {})
	for slot in eq.keys():
		if Trade.count(bag, String(eq[slot])) <= 0:
			eq.erase(slot)


func set_filter(f: String) -> void:
	inv_filter = f
	inv_page = 0
	inv_drop_armed = false
	refresh_bag()


func toggle_sort() -> void:
	inv_sort = not inv_sort
	refresh_bag()


func turn_page(d: int) -> void:
	inv_page = maxi(inv_page + d, 0)
	refresh_bag()


## «Бросить всё»: первый клик — подтвердить, второй (в течение 3 с) — выбросить все вещи фильтра
func drop_all() -> void:
	var bag: Dictionary = _bag()
	if bag.is_empty():
		return
	if not inv_drop_armed:
		inv_drop_armed = true
		_drop_t = 3.0
		refresh_bag()
		return
	inv_drop_armed = false
	var n: int = 0
	for id in bag.get("items", {}).keys():
		if Trade.item(id).has("transport"):
			continue   # лошадь и повозку не выбросить (characters/transport.gd)
		if inv_filter == "all" or Inv.cat_of(id, _item_weapons()) == inv_filter:
			n += Trade.count(bag, id)
			Trade.add(bag, id, -Trade.count(bag, id))
			if bag.has("battle_loadout"):
				bag["battle_loadout"].erase(id)
	if _actor() != null:
		_actor().carried_kg = Trade.weight(bag)
	_fix_equipped(bag)
	_say("Выброшено вещей: %d" % n)
	refresh_bag()


func use_item(id: String) -> void:
	var a: Actor = _actor()
	var bag: Dictionary = _bag()
	if a == null or bag.is_empty():
		return
	_say(Trade.use(bag, id, a))
	a.carried_kg = Trade.weight(bag)
	_sig = ""
	refresh()


func drop_item(id: String) -> void:
	var bag: Dictionary = _bag()
	if bag.is_empty():
		return
	Trade.add(bag, id, -1)
	if Trade.count(bag, id) <= 0 and bag.has("battle_loadout"):
		bag["battle_loadout"].erase(id)
	if _actor() != null:
		_actor().carried_kg = Trade.weight(bag)
	_fix_equipped(bag)
	_say("Выброшено: %s" % Trade.item_name(id))
	_sig = ""
	refresh()


func toggle_loadout(id: String) -> void:
	var bag: Dictionary = _bag()
	if bag.is_empty():
		return
	var lo: Array = bag.get("battle_loadout", [])
	if lo.has(id):
		lo.erase(id)
	elif lo.size() < _loadout_max():
		lo.append(id)
	else:
		_say("В бой — не больше %d видов оружия" % _loadout_max())
	bag["battle_loadout"] = lo
	_sig = ""
	refresh()


func _say(t: String) -> void:
	if t == "":
		return
	_note.text = t
	_say_t = 3.0


# =====================================================================
# КЛАВИШИ: пока окно открыто, всё его
# =====================================================================
func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_ESCAPE:
			close()
		KEY_I:
			toggle("stats")
		KEY_TAB:
			toggle("bag")
		KEY_1, KEY_2, KEY_3, KEY_4:
			show_tab(TABS[event.physical_keycode - KEY_1])
		_:
			return
	get_viewport().set_input_as_handled()


# =====================================================================
func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _wrap(text: String, size: int, color: Color) -> Label:
	var l := _label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(700.0, 0.0)
	return l


func _small(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(cb)
	return b

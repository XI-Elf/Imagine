extends CanvasLayer
## Окно героя — одно на всю игру вместо прежнего листа (I) и сумки города (Tab). Вкладки:
## 1 Характеристики (кто он, уровень и опыт, характеристики, производные, шкалы, состояния),
## 2 Навыки (18 навыков в %, отмеченные, трата очков навыков), 3 Дары (особенности, взятые дары,
## выбор нового дара), 4 Черты (черты характера, мировоззрение, биография),
## 5 Инвентарь (общая сумка Worlds.inventory: деньги, вещи, вес; использовать, выбросить, взять в бой), 6 Дневник (записки кодекса по разделам).
## Хозяин (cast.gd на карте, city_world.gd в городе) зовёт setup(герой, сумка) и open(вкладка).
## Пока окно открыто, клавиши забирает оно: 1–6 вкладки, I / Tab — закрыть или перейти, Esc — закрыть.

signal closed

const P := preload("res://characters/hero_profile.gd")
const R := preload("res://characters/actor_rules.gd")
const S := preload("res://characters/sheet.gd")
const Trade := preload("res://city/trade.gd")
const Inv := preload("res://characters/inventory_view.gd")
const ComicUI := preload("res://ui/comic_ui.gd")
const BATTLE_CONFIG := "res://data/battle/config.tres"

const Codex := preload("res://world/codex.gd")
const TABS: Array = ["stats", "skills", "perks", "traits", "bag", "diary"]
static var TAB_TITLES: Dictionary = {"stats": I18n.t("Характеристики"), "skills": I18n.t("Навыки"), "perks": I18n.t("Дары"), "traits": I18n.t("Черты характера"), "bag": I18n.t("Инвентарь"), "diary": I18n.t("Дневник")}
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
var inv_sel: String = ""        # обрана річ у вкладці «Інвентар»
var inv_filter: String = "all"  # фільтр сумки (inventory_view.FILTERS)
var inv_page: int = 0
var inv_sort: bool = false      # «За типом»
var inv_stat_pin: String = ""   # показник, на який клацнули в рядку інвентаря (підказка лишається між перебудовами)
var inv_drop_armed: bool = false   # «Кинути все» натиснуто один раз, чекає підтвердження
var _drop_t: float = 0.0
var _undo: Dictionary = {}       # навык -> сколько раз поднят, пока окно открыто (можно вернуть)
var perk_sel: String = ""        # дар, выбранный во вкладке «Дары»


func setup(get_actor: Callable, get_bag: Callable) -> void:
	actor_fn = get_actor
	bag_fn = get_bag


func _ready() -> void:
	layer = 40
	visible = false
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP   # вікно модальне: клік повз не веде героя (hero_route.gd)
	add_child(root)
	_panel = PanelContainer.new()
	# рамка коміксу: темна сталь із заклепками, усередині вугілля, згори бурштинова лінза (Q08 D, Q24 A, 2026-10-24)
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
	_note = _label("1–6 вкладки · I характеристики · Tab инвентарь · Esc закрыть", 13, COL_DIM)
	v.add_child(_note)


## Вкладки — сталеві таблички коміксу; обрана (натиснута) — з бурштиновим відливом
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
	_undo = {}
	if visible:
		visible = false
		closed.emit()


## I / Tab у господаря: відкрити на вкладці; якщо вже відкрито на ній — закрити
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


## Перебудовується, лише коли щось змінилося (інакше кнопки не натиснути)
func refresh() -> void:
	if _body == null:
		return
	var a: Actor = _actor()
	var sig: String = tab + "|" + JSON.stringify(_bag())
	if tab == "diary":
		sig += "|%d" % _codex().size()
	if a != null:
		sig += "|%s|%s|%s|%d|%s|%d|%d|%d|%d|%s|%s" % [a.display_name, JSON.stringify(a.skills), JSON.stringify(a.traits), int(a.carry_capacity()),
			JSON.stringify(a.perks), a.skill_points, a.perk_picks, a.level, int(a.xp), JSON.stringify(a.quirks), perk_sel]
		if tab == "bag":   # строка показателей сверху
			for r in Actor.RESOURCES:
				sig += "|%d" % int(a.res.get(r, 0.0))
		if tab == "stats":
			# Шкали — за цілими значеннями показників (раніше перебудова щопівсекунди: підказки й клік по показнику зникали)
			for r in Actor.RESOURCES:
				sig += "|%d" % int(a.res.get(r, 0.0))
			var bh: int = 0
			for bf in a.buffs:
				bh += int(float(bf["left_h"]))
			sig += "|%s|%d|%d" % [JSON.stringify(a.conditions.map(func(c: Dictionary) -> String: return "%s%d" % [c["id"], int(c.get("stage", 0))])), bh, int(a.distance_m / 100.0)]
	if sig == _sig:
		return
	_sig = sig
	for c in _body.get_children():
		c.queue_free()
	if a == null:
		_title.text = I18n.t("Героя нет")
		_body.add_child(_label(I18n.t("Создайте героя: G на карте."), 16, COL_DIM))
		return
	_title.text = "%s — %s" % [a.display_name, TAB_TITLES[tab]]
	match tab:
		"stats":
			_fill_stats(a)
		"skills":
			_fill_skills(a)
		"perks":
			_fill_perks(a)
		"traits":
			_fill_traits(a)
		"bag":
			_fill_bag(a)
		"diary":
			_fill_diary()


# =====================================================================
# ХАРАКТЕРИСТИКИ
# =====================================================================
func _fill_stats(a: Actor) -> void:
	var pf: Dictionary = a.profile
	if not pf.is_empty():
		var g: String = String(P.C()["genders"].get(pf.get("gender", ""), {}).get("title", ""))
		var o: String = String(P.C()["origins"].get(pf.get("origin", ""), {}).get("title", ""))
		var pr: String = String(P.C()["professions"].get(pf.get("profession", ""), {}).get("title", ""))
		var sb: String = String(P.C().get("subspecies", {}).get(pf.get("subspecies", ""), {}).get("title", ""))
		_body.add_child(_label("%s, %d %s · %s%s · %s · %s" % [g, int(pf.get("age", 0)), P.years(int(pf.get("age", 0))), sb + " · " if sb != "" else "", o, pr,
			P.alignment_name(pf.get("alignment", {}))], 15, COL_TEXT))
	else:
		_body.add_child(_label("Герой создан до окна персонажа: происхождения и черт нет.", 14, COL_DIM))
	_body.add_child(_label("Уровень %d · опыт %d / %d · очков навыков: %d · даров к выбору: %d" % [
		a.level, int(a.xp), S.xp_to_next(a), a.skill_points, a.perk_picks], 16, COL_GOLD if a.skill_points > 0 or a.perk_picks > 0 else COL_TEXT))
	_body.add_child(_label("Характеристики", 17, COL_GOLD))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 18)
	_body.add_child(grid)
	for s in S.stats_list():
		grid.add_child(_explain(_label(S.stat_name(s), 16, COL_TEXT), S.stat_name(s), String(S.sect("stat_desc").get(s, ""))))
		var v: int = S.stat_value(a, s)
		grid.add_child(_label(str(v), 18, COL_GOLD))
		grid.add_child(_label(S.stat_level_name(v), 14, COL_TEXT))
		var base: int = int(a.stats.get(s, 5))
		grid.add_child(_label(("база %d, черты и дары %+d" % [base, v - base]) if v != base else String(S.sect("stat_desc").get(s, "")).split(".")[0], 13, COL_DIM))
	var fd: Dictionary = S.derived(a)
	_body.add_child(_wrap("Здоровье в бою %d (+%d за уровень) · Очки действия %d · Защита %d · Груз %d кг · Урон в рукопашной %d · Защита от яда %d %% · от проклятья %d %% · Порядок хода %d · Заживление %d · Шанс крита %d %% · Очков навыков за уровень %d · Спутников до %d" % [
		fd["hp"], fd["hp_level"], fd["ap"], fd["ac"], int(fd["carry_kg"]), fd["melee"], fd["poison"], fd["rad"], fd["sequence"], fd["healing"], fd["crit"], fd["skill_points"], fd["party"]], 14, COL_TEXT))
	_body.add_child(HSeparator.new())
	_body.add_child(_label(I18n.t("Состояние"), 17, COL_GOLD))
	var shown: Dictionary = {"hunger": I18n.t("Сытость"), "thirst": I18n.t("Вода"), "stamina": I18n.t("Запас сил")}
	var ch: Dictionary = R.characteristics()
	for r in Actor.RESOURCES:
		var row := HBoxContainer.new()
		var nm: String = String(shown.get(r, ch.get(r, {}).get("name_ru", r)))
		var l := _explain(_label(nm, 15, COL_TEXT), nm, String(Inv.STAT_DESC.get(r, "")))
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
		cond.append(String(R.condition(c["id"]).get("name_ru", c["id"])) + ("" if c["id"] != "radiation_sickness" else I18n.t(" (стадия %d)") % int(c["stage"])))
	for bf in a.buffs:
		cond.append(I18n.t("+ %s (%.0f ч)") % [R.buffs().get(bf["id"], {}).get("name_ru", bf["id"]), float(bf["left_h"])])
	_body.add_child(_wrap(I18n.t("Травмы, болезни, эффекты: ") + (", ".join(cond) if not cond.is_empty() else I18n.t("нет")), 14, COL_TEXT))
	var dv: Dictionary = a.derived()
	_body.add_child(_wrap(I18n.t("Сила удара ×%.2f · Поиск ×%.2f · Скорость ×%.2f · Переносимый вес %.0f кг · Защита от проклятья %d %% · Пройдено %.1f км") % [
		dv["attack_power"], dv["search_efficiency"], dv["move_speed"], dv["carry_weight"], int(dv["radiation_resist"] * 100.0), a.distance_m / 1000.0], 14, COL_DIM))


# =====================================================================
# НАВИЧКИ
# =====================================================================
func _fill_skills(a: Actor) -> void:
	_body.add_child(_label("Очков навыков: %d · отмеченные (◆) растут на 2 %% за очко · цена растёт после 100, 125, 150, 175, 200 %%" % a.skill_points, 15, COL_GOLD if a.skill_points > 0 else COL_DIM))
	var groups: Dictionary = S.sect("groups")
	for g in groups:
		_body.add_child(_label(String(groups[g]), 16, COL_GOLD))
		for k in S.skill_list():
			if String(S.skills()[k].get("group", "")) != g:
				continue
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			var tag: bool = S.is_tag(a, k)
			var l := _label("%s %s" % ["◆" if tag else "◇", S.skill_name(k)], 15, COL_GOLD if tag else COL_TEXT)
			l.custom_minimum_size = Vector2(230.0, 0.0)
			l.tooltip_text = String(S.skills()[k].get("desc", ""))
			l.mouse_filter = Control.MOUSE_FILTER_PASS
			row.add_child(l)
			var v := _label("%d %%" % S.skill_value(a, k), 16, COL_GOLD)
			v.custom_minimum_size = Vector2(70.0, 0.0)
			row.add_child(v)
			var minus := _small("−", lower_skill.bind(k))
			minus.disabled = int(_undo.get(k, 0)) <= 0
			row.add_child(minus)
			var plus := _small("+", raise_skill.bind(k))
			plus.disabled = not S.can_raise(a, k)
			row.add_child(plus)
			var c: int = S.skill_cost(a, k)
			row.add_child(_label(("цена %d" % c) if c > 0 else "предел", 13, COL_DIM))
			if a.tag_left > 0 and not tag:
				row.add_child(_small("Отметить", tag_skill.bind(k)))
			var fs: Array = S.skills()[k].get("stats", [])
			row.add_child(_label("  от %s" % ", ".join(PackedStringArray(fs.map(func(x): return S.stat_short(x)))), 13, COL_DIM))
			_body.add_child(row)
	_body.add_child(_wrap("Навыки растут очками навыков: %d + 2 × Ум за каждый уровень. Опыт дают бои, поручения, путь, лечение и ремесло. «−» возвращает очки, пока окно открыто." % int(S.d("skill_points_base", 5)), 13, COL_DIM))


func tag_skill(k: String) -> void:
	var a: Actor = _actor()
	if a != null:
		S.add_tag(a, k)
	_sig = ""
	refresh()


func raise_skill(k: String) -> void:
	var a: Actor = _actor()
	if a != null and S.raise(a, k):
		_undo[k] = int(_undo.get(k, 0)) + 1
	_sig = ""
	refresh()


func lower_skill(k: String) -> void:
	var a: Actor = _actor()
	if a != null and int(_undo.get(k, 0)) > 0 and S.lower(a, k):
		_undo[k] = int(_undo[k]) - 1
	_sig = ""
	refresh()


# =====================================================================
# ДАРЫ И ОСОБЕННОСТИ
# =====================================================================
func _fill_perks(a: Actor) -> void:
	_body.add_child(_label("Особенности", 17, COL_GOLD))
	if a.quirks.is_empty():
		_body.add_child(_label("Нет.", 14, COL_DIM))
	for t in a.quirks:
		var row := HBoxContainer.new()
		row.add_child(_wrap(S.trait_text(t), 14, COL_TEXT))
		if a.mutate_left > 0:
			row.add_child(_small("Убрать (Перерождение)", mutate_trait.bind(t, "")))
		_body.add_child(row)
	if a.mutate_left > 0 and a.quirks.size() < int(S.data().get("traits_max", 2)):
		var mg := HFlowContainer.new()
		for t in S.traits():
			if not a.quirks.has(t):
				mg.add_child(_small("+ " + String(S.traits()[t]["title"]), mutate_trait.bind("", t)))
		_body.add_child(_label("Перерождение: можно взять черту", 14, COL_GOLD))
		_body.add_child(mg)
	_body.add_child(HSeparator.new())
	_body.add_child(_label("Дары", 17, COL_GOLD))
	if a.perks.is_empty():
		_body.add_child(_label("Пока нет. Дар — раз в %d уровня." % S.perk_rate(a), 14, COL_DIM))
	for id in a.perks:
		var rk: int = int(a.perks[id])
		_body.add_child(_wrap("%s%s — %s" % [S.perk_def(id).get("title", id), " ×%d" % rk if rk > 1 else "", S.perk_def(id).get("text", "")], 14, COL_GOOD))
	_body.add_child(HSeparator.new())
	if a.perk_picks <= 0:
		_body.add_child(_label("Новый дар — на уровне %d." % _next_perk_level(a), 15, COL_DIM))
		return
	_body.add_child(_label("Выберите дар (можно: %d)" % a.perk_picks, 17, COL_GOLD))
	var av: Array = S.available_perks(a)
	if av.is_empty():
		_body.add_child(_label("Подходящих даров нет: поднимите уровень, характеристики или навыки.", 14, COL_DIM))
		return
	if not av.has(perk_sel):
		perk_sel = av[0]
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 4)
	flow.add_theme_constant_override("v_separation", 4)
	for id in av:
		var b := _small(String(S.perk_def(id).get("title", id)), func() -> void: perk_sel = id; _sig = ""; refresh())
		b.toggle_mode = true
		b.button_pressed = id == perk_sel
		flow.add_child(b)
	_body.add_child(flow)
	_body.add_child(_wrap(S.perk_text(perk_sel), 15, COL_TEXT))
	var take := _small("Взять дар «%s»" % S.perk_def(perk_sel).get("title", perk_sel), pick_perk.bind(perk_sel))
	take.add_theme_font_size_override("font_size", 16)
	_body.add_child(take)


func _next_perk_level(a: Actor) -> int:
	var r: int = S.perk_rate(a)
	return (a.level / r + 1) * r


func pick_perk(id: String) -> void:
	var a: Actor = _actor()
	if a == null:
		return
	var why: String = S.take_perk(a, id)
	_say("Дар взят: %s" % S.perk_def(id).get("title", id) if why == "" else "Нельзя: " + why)
	perk_sel = ""
	_sig = ""
	refresh()


func mutate_trait(remove_id: String, add_id: String) -> void:
	var a: Actor = _actor()
	if a == null:
		return
	var why: String = S.mutate(a, remove_id, add_id)
	_say("Перерождение: готово" if why == "" else "Нельзя: " + why)
	_sig = ""
	refresh()


# =====================================================================
# РИСИ ХАРАКТЕРУ
# =====================================================================
func _fill_traits(a: Actor) -> void:
	if a.traits.is_empty():
		_body.add_child(_label(I18n.t("Черт характера нет."), 15, COL_DIM))
	for t in a.traits:
		var c: int = int(R.trait_def(t).get("cost", 0))
		_body.add_child(_wrap(P.trait_text(t), 15, COL_GOOD if c > 0 else COL_BAD))
	var al: Dictionary = a.profile.get("alignment", P.alignment(a.traits))
	_body.add_child(HSeparator.new())
	_body.add_child(_label(I18n.t("Мировоззрение: %s (добро %+d, закон %+d)") % [P.alignment_name(al), int(al.get("moral", 0)), int(al.get("order", 0))], 16, COL_GOLD))
	var bio: String = String(a.profile.get("biography", ""))
	if bio != "":
		_body.add_child(HSeparator.new())
		_body.add_child(_label(I18n.t("История"), 17, COL_GOLD))
		_body.add_child(_wrap(bio, 15, Color("e6dcc0")))


# =====================================================================
# ІНВЕНТАР
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


## Обладунок у бою — з того, що вдягнено на «Тіло» (items.json wear.armor), інакше без обладунку
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


## Лялька персонажа: слоти, герой, сумка клітинками (characters/inventory_view.gd)
func _fill_bag(a: Actor) -> void:
	var bag: Dictionary = _bag()
	if bag.is_empty():
		_body.add_child(_label(I18n.t("Сумки нет."), 15, COL_DIM))
		return
	if Trade.count(bag, inv_sel) <= 0:
		inv_sel = ""
	var view := Inv.new()
	view.setup(self, a, bag, _item_weapons(), _loadout_max(), _hero_armor())
	inv_page = clampi(inv_page, 0, view.pages() - 1)
	_body.add_child(view)
	if _say_t <= 0.0:
		_note.text = "Клик — выбрать · двойной клик — съесть/выпить · колесо — страницы · 1–6 вкладки · Esc закрыть"


func _codex() -> Dictionary:
	var w: Node = get_node_or_null("/root/Worlds")
	var c: Variant = w.get("codex") if w != null else null
	return c if c is Dictionary else {}


# =====================================================================
# ДНЕВНИК: записки кодексу, зібрані в книгу за розділами
# =====================================================================
func _fill_diary() -> void:
	var found: Dictionary = _codex()
	var pr: Dictionary = Codex.progress(found)
	_body.add_child(_label(I18n.t("Записки найдены: %d из %d") % [int(pr["found"]), int(pr["total"])], 17, COL_GOLD))
	if found.is_empty():
		_body.add_child(_wrap(I18n.t("Пока пусто. Записки лежат в руинах на карте и в тайниках городов (F у руин, E у тайника). Найденное само складывается в книгу по разделам."), 15, COL_DIM))
		return
	for ch in Codex.chapters():
		var here: Array = []
		var total: int = 0
		for n in Codex.notes():
			if String(n["chapter"]) == String(ch["id"]):
				total += 1
				if found.has(String(n["id"])):
					here.append(n)
		if here.is_empty():
			continue
		_body.add_child(HSeparator.new())
		_body.add_child(_label("%s (%d/%d)" % [ch["title"], here.size(), total], 17, COL_GOLD))
		for n in here:
			_body.add_child(_label(String(n["title"]), 15, COL_GOOD))
			_body.add_child(_wrap(String(n["text"]), 14, COL_TEXT))


func refresh_bag() -> void:
	_sig = ""
	refresh()


## Одяг: bag.equipped {slot: id}; вдягнена річ лишається в сумці (вага рахується), у слоті одна річ
func equip_item(id: String) -> void:
	var bag: Dictionary = _bag()
	var w: Dictionary = Trade.item(id).get("wear", {})
	if bag.is_empty() or w.is_empty() or Trade.count(bag, id) <= 0:
		return
	var eq: Dictionary = bag.get("equipped", {})
	var old: String = String(eq.get(w["slot"], ""))
	eq[String(w["slot"])] = id
	bag["equipped"] = eq
	_say(I18n.t("Надето: %s%s") % [Trade.item_name(id), (I18n.t(" (снято: %s)") % Trade.item_name(old)) if old != "" and old != id else ""])
	refresh_bag()


func unequip_item(id: String) -> void:
	var eq: Dictionary = _bag().get("equipped", {})
	for slot in eq.keys():
		if eq[slot] == id:
			eq.erase(slot)
			_say(I18n.t("Снято: %s") % Trade.item_name(id))
	refresh_bag()


## Прибрати зі слотів те, чого більше немає в сумці (після «Викинути»)
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


## «Кинути все»: перший клік — підтвердити, другий (протягом 3 с) — викинути всі речі фільтра
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
			continue   # коня й віз не викинути (characters/transport.gd)
		if inv_filter == "all" or Inv.cat_of(id, _item_weapons()) == inv_filter:
			n += Trade.count(bag, id)
			Trade.add(bag, id, -Trade.count(bag, id))
			if bag.has("battle_loadout"):
				bag["battle_loadout"].erase(id)
	if _actor() != null:
		_actor().carried_kg = Trade.weight(bag)
	_fix_equipped(bag)
	_say(I18n.t("Выброшено вещей: %d") % n)
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
	_say(I18n.t("Выброшено: %s") % Trade.item_name(id))
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
		_say(I18n.t("В бой — не больше %d видов оружия") % _loadout_max())
	bag["battle_loadout"] = lo
	_sig = ""
	refresh()


func _say(t: String) -> void:
	if t == "":
		return
	_note.text = t
	_say_t = 3.0


# =====================================================================
# КЛАВІШІ: поки вікно відкрите, усі його
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
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
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


## Показник з описом (Huzzah 2026-10-29): наведення — підказка, клік — віконце з описом біля курсора
func _explain(l: Label, title: String, desc: String) -> Label:
	if desc == "":
		return l
	l.tooltip_text = desc
	l.mouse_filter = Control.MOUSE_FILTER_STOP
	l.mouse_default_cursor_shape = Control.CURSOR_HELP
	l.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_show_explain(title, desc, l.get_global_mouse_position()))
	return l


var _explain_pop: PopupPanel


func _show_explain(title: String, desc: String, at: Vector2) -> void:
	if _explain_pop == null:
		_explain_pop = PopupPanel.new()
		var box := VBoxContainer.new()
		box.add_child(_label("", 17, COL_GOLD))
		var t := _wrap("", 14, COL_TEXT)
		t.custom_minimum_size = Vector2(360.0, 0.0)
		box.add_child(t)
		_explain_pop.add_child(box)
		add_child(_explain_pop)
	var box: VBoxContainer = _explain_pop.get_child(0)
	(box.get_child(0) as Label).text = title
	(box.get_child(1) as Label).text = desc
	_explain_pop.reset_size()
	_explain_pop.popup(Rect2i(Vector2i(at) + Vector2i(12, 12), Vector2i(380, 10)))


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

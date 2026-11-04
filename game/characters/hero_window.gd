extends CanvasLayer
## Меню персонажа — одно на всю игру, открывается клавишей I (Huzzah 2026-11-03, п.8: журнал заданий, карта и инвентарь
## больше не имеют своих клавиш Tab, J, M, а переключаются здесь же). Разделы:
## 1 Характеристики (кто он, уровень и опыт, характеристики, производные, шкалы, состояния),
## 2 Навыки (18 навыков в %, отмеченные, трата очков навыков), 3 Дары (особенности, взятые дары,
## выбор нового дара), 4 Черты (черты характера, мировоззрение, биография),
## 5 Инвентарь (общая сумка Worlds.inventory: деньги, вещи, вес; использовать, выбросить, взять в бой),
## 6 Задания (журнал героя, characters/quest_journal.gd), 7 Карта (карта мира, заполняется сама по мере исследования,
## world/parchment.gd), 8 Травмы (состояние полученных травм и болезней), 9 Дневник (записки кодекса по разделам), 0 Хроника.
## Хозяин (cast.gd на карте, city_world.gd в городе) зовёт setup(герой, сумка) и open(вкладка).
## Пока окно открыто, клавиши забирает оно: 1–9 и 0 вкладки, I или Esc — закрыть.

signal closed

const P := preload("res://characters/hero_profile.gd")
const R := preload("res://characters/actor_rules.gd")
const S := preload("res://characters/sheet.gd")
const Trade := preload("res://city/trade.gd")
const Inv := preload("res://characters/inventory_view.gd")
const FieldGuide := preload("res://characters/field_guide.gd")
const ItemGlyph := preload("res://characters/item_glyph.gd")
const Growth := preload("res://city/city_growth.gd")
const QuestCampaign := preload("res://world/quest_campaign.gd")
const ComicUI := preload("res://ui/comic_ui.gd")
const BATTLE_CONFIG := "res://data/battle/config.tres"

const Codex := preload("res://world/codex.gd")
const Chronicle := preload("res://characters/chronicle.gd")
const TABS: Array = ["stats", "skills", "perks", "traits", "bag", "quests", "map", "injuries", "diary", "chronicle"]
static var TAB_TITLES: Dictionary = {"stats": I18n.t("Характеристики"), "skills": I18n.t("Навыки"), "perks": I18n.t("Дары"), "traits": I18n.t("Черты характера"), "bag": I18n.t("Инвентарь"),
	"quests": I18n.t("Задания"), "map": I18n.t("Карта"), "injuries": I18n.t("Травмы"), "diary": I18n.t("Дневник"), "chronicle": I18n.t("Хроника")}
const TAB_KEYS: Array = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0]
const EMBED_H: float = 500.0       # высота вкладок «Задания» и «Карта»
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
var diary_mode: String = "lore"
var guide_category: String = "all"
var _embedded: Array = []        # что сейчас прикреплено к вкладке: журнал и/или карта (вернуть на место перед перестройкой)


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
		b.text = "%d %s" % [(i + 1) % 10, TAB_TITLES[TABS[i]]]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		_style_tab(b)
		b.add_theme_font_size_override("font_size", 14)
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
	_note = _label(I18n.t("1–9, 0 — разделы · I или Esc — закрыть"), 13, COL_DIM)
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
	_unmount_embedded()
	if visible:
		visible = false
		closed.emit()


## I у господаря (п.8): відкрити меню на останньому розділі або закрити, якщо воно вже відкрите
func toggle_menu() -> void:
	if visible:
		close()
	else:
		open()


## Відкрити на розділі; якщо вже відкрито на ньому — закрити (для виклику з коду й тестів)
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
		sig += "|%d|%s|%s" % [_codex().size(), diary_mode, guide_category]
	if tab == "chronicle":
		sig += "|%d" % Chronicle.entries(get_node_or_null("/root/Worlds")).size()
	if tab == "quests":
		var active_city := _active_city_node()
		if active_city != null:
			sig += "|%s|%.1f|%d" % [JSON.stringify(active_city.growth), active_city.hero_km(), active_city.battles_won()]
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
	_unmount_embedded()
	for c in _body.get_children():
		c.queue_free()
	if a == null:
		_title.text = I18n.t("Героя нет")
		_body.add_child(_label(I18n.t("Создайте героя: G на карте."), 16, COL_DIM))
		if tab == "map":
			_fill_map()
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
		"quests":
			_fill_quests()
		"map":
			_fill_map()
		"injuries":
			_fill_injuries(a)
		"diary":
			_fill_diary()
		"chronicle":
			_fill_chronicle()


# =====================================================================
# ЗАДАНИЯ И КАРТА: прикрепляются к вкладке (журнал и карта живут в своих узлах)
# =====================================================================
func _worlds() -> Node:
	return get_node_or_null("/root/Worlds")


func _map_owner() -> Node:
	var w: Node = _worlds()
	var g: Variant = w.get("game") if w != null else null
	if g != null and g.get("cast") != null and g.cast.get("parchment") != null:
		return g.cast.parchment
	var p: Node = get_parent()
	return p.get("parchment") if p != null and p.get("parchment") != null else null


func _embed_host() -> Control:
	var h := Control.new()
	h.custom_minimum_size = Vector2(0.0, EMBED_H)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.clip_contents = true
	_body.add_child(h)
	return h


func _fill_quests() -> void:
	_fill_campaign_quest()
	_fill_active_city_quests()
	var w: Node = _worlds()
	var j: Variant = w.get("journal") if w != null else null
	if j == null:
		_body.add_child(_label(I18n.t("Журнала нет."), 15, COL_DIM))
		return
	_body.add_child(_label(I18n.t("Личные заметки героя"), 16, COL_GOLD))
	j.mount(_embed_host())
	_embedded.append(j)
	_title.text = "%s — %s" % [String(_actor().display_name) if _actor() != null else "", TAB_TITLES["quests"]]


func _fill_campaign_quest() -> void:
	var w: Node = _worlds()
	if w == null:
		return
	var q: Dictionary = w.campaign_current() if w.has_method("campaign_current") else {}
	_body.add_child(_label(I18n.t("Основная история"), 18, COL_GOLD))
	if q.is_empty():
		_body.add_child(_label(I18n.t("Основная история завершена. Мир продолжает жить: доступны городские поручения и исследование."), 14, COL_GOOD))
		return
	var title := _label(String(q.get("title", "")), 16, COL_TEXT)
	_body.add_child(title)
	var desc := _label(String(q.get("text", "")), 14, COL_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(desc)
	var km: float = _actor().distance_m / 1000.0 if _actor() != null else 0.0
	var p: Array = QuestCampaign.progress(w.campaign_state, km)
	var status := _label(I18n.t("Прогресс: %d / %d") % [int(p[0]), int(p[1])], 13, COL_GOOD if int(p[0]) >= int(p[1]) else COL_DIM)
	_body.add_child(status)
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = maxf(float(p[1]), 1.0)
	bar.value = float(p[0])
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 10)
	ComicUI.bar_styles(bar)
	_body.add_child(bar)
	_body.add_child(HSeparator.new())

func _active_city_node() -> Node:
	var w: Node = _worlds()
	if w == null or w.stack.is_empty():
		return null
	var top: Dictionary = w.stack[-1]
	if String(top.get("kind", "")) != "city":
		return null
	var city: Variant = top.get("node")
	return city if city is Node and is_instance_valid(city) else null


func _fill_active_city_quests() -> void:
	var city: Node = _active_city_node()
	if city == null:
		return
	var active: Array = []
	for npc in city.npcs:
		var nd: Dictionary = npc.get("def", {})
		var npc_id: String = String(nd.get("id", ""))
		if npc_id == "":
			continue
		for q in Growth.available(city.full_def, city.growth, npc_id):
			if Growth.taken(city.growth, q):
				active.append({"quest": q, "npc": npc})
	if active.is_empty():
		return
	_body.add_child(_label(I18n.t("Принятые поручения Эшвика"), 17, COL_GOLD))
	for entry in active:
		var q: Dictionary = entry.quest
		var npc: Dictionary = entry.npc
		var actor: Actor = npc.get("actor")
		var npc_name: String = actor.display_name if actor != null else String(npc.get("def", {}).get("name", ""))
		var p: Array = Growth.progress(city.growth, q, city.bag, city.hero_km(), city.battles_won())
		var target: float = maxf(float(p[1]), 1.0)
		var current: float = clampf(float(p[0]), 0.0, target)
		var ready: bool = Growth.ready(city.growth, q, city.bag, city.hero_km(), city.battles_won())
		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 3)
		_body.add_child(card)
		var title := Label.new()
		title.text = "%s — %s" % [npc_name, String(q.get("title", I18n.t("Поручение")))]
		title.add_theme_font_size_override("font_size", 15)
		title.add_theme_color_override("font_color", COL_TEXT)
		card.add_child(title)
		var status := Label.new()
		status.text = city.quest_status(q) + (I18n.t(" · можно сдать") if ready else "")
		status.add_theme_font_size_override("font_size", 13)
		status.add_theme_color_override("font_color", COL_GOOD if ready else COL_DIM)
		card.add_child(status)
		var bar := ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = target
		bar.value = current
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0.0, 9.0)
		ComicUI.bar_styles(bar)
		card.add_child(bar)
		_body.add_child(HSeparator.new())


func _fill_map() -> void:
	var pm: Node = _map_owner()
	if pm == null:
		_body.add_child(_label(I18n.t("Карты нет."), 15, COL_DIM))
		return
	pm.mount(_embed_host())
	_embedded.append(pm)


## Вернуть журнал и карту на место: окно закрывается или вкладка перестраивается
func _unmount_embedded() -> void:
	for e in _embedded:
		if is_instance_valid(e):
			e.unmount()
	_embedded.clear()


# =====================================================================
# ТРАВМЫ (п.10 правок): состояние полученных травм и болезней
# =====================================================================
static var PART_NAMES: Dictionary = {"arm": I18n.t("рука"), "leg": I18n.t("нога"), "head": I18n.t("голова")}
static var INJURY_EFFECTS: Dictionary = {
	"speed": I18n.t("скорость"), "power": I18n.t("сила удара"), "loot": I18n.t("поиск"), "poison": I18n.t("отравление"), "thirst": I18n.t("жажда"),
	"hunger": I18n.t("голод"), "health_decay": I18n.t("потеря здоровья"), "exhaustion": I18n.t("усталость"), "emaciation": I18n.t("истощение"),
	"bleeding": I18n.t("кровотечение"), "energy_decay": I18n.t("расход энергии"), "pain": I18n.t("боль")}


## Строки состояния травм героя: [{id, name, kind, part, age_h, left_h, stage, progress, effects: [..], treatment, cause}]
static func injury_rows(a: Actor) -> Array:
	var out: Array = []
	for c in a.conditions:
		var d: Dictionary = R.condition(String(c["id"]))
		var eff: Array = []
		for k in d.get("effects", {}):
			var v: float = float(d["effects"][k])
			var nm: String = String(INJURY_EFFECTS.get(k, ""))
			if nm != "":
				eff.append("%s %+d %%" % [nm, int(round(v * 100.0))] if absf(v) <= 1.0 else "%s %+.1f" % [nm, v])
		var left: float = float(c.get("left_h", 0.0))
		var age: float = float(c.get("age_h", 0.0))
		out.append({"id": String(c["id"]), "name": String(d.get("name_ru", c["id"])), "kind": "trauma" if R.is_trauma(String(c["id"])) else "disease",
			"part": String(PART_NAMES.get(String(d.get("body_part", "")), "")), "age_h": age, "left_h": left, "stage": int(c.get("stage", 1)),
			"progress": clampf(age / (age + left), 0.0, 1.0) if left > 0.0 else 0.0, "effects": eff,
			"treatment": String(d.get("treatment", "")), "cause": String(d.get("cause", ""))})
	return out


func _fill_injuries(a: Actor) -> void:
	var rows: Array = injury_rows(a)
	if rows.is_empty():
		_body.add_child(_label(I18n.t("Травм и болезней нет. Всё цело."), 17, COL_GOOD))
		_body.add_child(_wrap(I18n.t("Когда герой получит травму, она появится здесь: что повреждено, как долго идёт и чем лечится."), 14, COL_DIM))
	else:
		_body.add_child(_label(I18n.t("Травмы и болезни: %d") % rows.size(), 17, COL_GOLD))
	for r in rows:
		_body.add_child(HSeparator.new())
		var head: String = String(r["name"])
		if int(r["stage"]) > 1 and String(r["id"]) == "radiation_sickness":
			head += I18n.t(" (стадия %d)") % int(r["stage"])
		_body.add_child(_label("%s · %s%s" % [head, I18n.t("травма") if r["kind"] == "trauma" else I18n.t("болезнь"),
			((" · " + String(r["part"])) if r["part"] != "" else "")], 17, COL_BAD))
		var left_txt: String = (I18n.t("до выздоровления около %d ч") % int(ceil(float(r["left_h"])))) if float(r["left_h"]) > 0.0 else I18n.t("сама не пройдёт: нужно лечение")
		_body.add_child(_label(I18n.t("Идёт %d ч · %s") % [int(float(r["age_h"])), left_txt], 14, COL_TEXT))
		if float(r["left_h"]) > 0.0:
			var bar := ProgressBar.new()
			bar.max_value = 1.0
			bar.value = float(r["progress"])
			bar.show_percentage = false
			bar.custom_minimum_size = Vector2(320.0, 14.0)
			_body.add_child(bar)
		if not r["effects"].is_empty():
			_body.add_child(_wrap(I18n.t("Что мешает: ") + ", ".join(PackedStringArray(r["effects"])), 14, COL_TEXT))
		if r["treatment"] != "":
			_body.add_child(_wrap(I18n.t("Лечение: ") + String(r["treatment"]) + I18n.t(". Лекарь рядом — T."), 14, COL_GOOD))
		if r["cause"] != "":
			_body.add_child(_wrap(I18n.t("Причина: ") + String(r["cause"]), 13, COL_DIM))
	if not a.buffs.is_empty():
		_body.add_child(HSeparator.new())
		_body.add_child(_label(I18n.t("Действуют"), 16, COL_GOLD))
		for bf in a.buffs:
			_body.add_child(_label(I18n.t("%s — ещё %.0f ч") % [R.buffs().get(bf["id"], {}).get("name_ru", bf["id"]), float(bf["left_h"])], 14, COL_GOOD))


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
		_body.add_child(_label(I18n.t("Герой создан до окна персонажа: происхождения и черт нет."), 14, COL_DIM))
	_body.add_child(_label(I18n.t("Уровень %d · опыт %d / %d · очков навыков: %d · даров к выбору: %d") % [
		a.level, int(a.xp), S.xp_to_next(a), a.skill_points, a.perk_picks], 16, COL_GOLD if a.skill_points > 0 or a.perk_picks > 0 else COL_TEXT))
	_body.add_child(_label(I18n.t("Характеристики"), 17, COL_GOLD))
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
		grid.add_child(_label((I18n.t("база %d, черты и дары %+d") % [base, v - base]) if v != base else String(S.sect("stat_desc").get(s, "")).split(".")[0], 13, COL_DIM))
	var fd: Dictionary = S.derived(a)
	_body.add_child(_wrap(I18n.t("Здоровье в бою %d (+%d за уровень) · Очки действия %d · Защита %d · Груз %d кг · Урон в рукопашной %d · Защита от яда %d %% · от проклятья %d %% · Порядок хода %d · Заживление %d · Шанс крита %d %% · Очков навыков за уровень %d · Спутников до %d") % [
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
	_body.add_child(_label(I18n.t("Очков навыков: %d · отмеченные (◆) растут на 2 %% за очко · цена растёт после 100, 125, 150, 175, 200 %%") % a.skill_points, 15, COL_GOLD if a.skill_points > 0 else COL_DIM))
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
			row.add_child(_label((I18n.t("цена %d") % c) if c > 0 else I18n.t("предел"), 13, COL_DIM))
			if a.tag_left > 0 and not tag:
				row.add_child(_small(I18n.t("Отметить"), tag_skill.bind(k)))
			var fs: Array = S.skills()[k].get("stats", [])
			row.add_child(_label(I18n.t("  от %s") % ", ".join(PackedStringArray(fs.map(func(x): return S.stat_short(x)))), 13, COL_DIM))
			_body.add_child(row)
	_body.add_child(_wrap(I18n.t("Навыки растут очками навыков: %d + 2 × Интеллект за каждый уровень. Опыт дают бои, поручения, путь, лечение и ремесло. «−» возвращает очки, пока окно открыто.") % int(S.d("skill_points_base", 5)), 13, COL_DIM))


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
	_body.add_child(_label(I18n.t("Особенности"), 17, COL_GOLD))
	if a.quirks.is_empty():
		_body.add_child(_label(I18n.t("Нет."), 14, COL_DIM))
	for t in a.quirks:
		var row := HBoxContainer.new()
		row.add_child(_wrap(S.trait_text(t), 14, COL_TEXT))
		if a.mutate_left > 0:
			row.add_child(_small(I18n.t("Убрать (Перерождение)"), mutate_trait.bind(t, "")))
		_body.add_child(row)
	if a.mutate_left > 0 and a.quirks.size() < int(S.data().get("traits_max", 2)):
		var mg := HFlowContainer.new()
		for t in S.traits():
			if not a.quirks.has(t):
				mg.add_child(_small("+ " + String(S.traits()[t]["title"]), mutate_trait.bind("", t)))
		_body.add_child(_label(I18n.t("Перерождение: можно взять черту"), 14, COL_GOLD))
		_body.add_child(mg)
	_body.add_child(HSeparator.new())
	_body.add_child(_label(I18n.t("Дары"), 17, COL_GOLD))
	if a.perks.is_empty():
		_body.add_child(_label(I18n.t("Пока нет. Дар — раз в %d уровня.") % S.perk_rate(a), 14, COL_DIM))
	for id in a.perks:
		var rk: int = int(a.perks[id])
		_body.add_child(_wrap("%s%s — %s" % [S.perk_def(id).get("title", id), " ×%d" % rk if rk > 1 else "", S.perk_def(id).get("text", "")], 14, COL_GOOD))
	_body.add_child(HSeparator.new())
	if a.perk_picks <= 0:
		_body.add_child(_label(I18n.t("Новый дар — на уровне %d.") % _next_perk_level(a), 15, COL_DIM))
		return
	_body.add_child(_label(I18n.t("Выберите дар (можно: %d)") % a.perk_picks, 17, COL_GOLD))
	var av: Array = S.available_perks(a)
	if av.is_empty():
		_body.add_child(_label(I18n.t("Подходящих даров нет: поднимите уровень, характеристики или навыки."), 14, COL_DIM))
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
	var take := _small(I18n.t("Взять дар «%s»") % S.perk_def(perk_sel).get("title", perk_sel), pick_perk.bind(perk_sel))
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
	_say(I18n.t("Дар взят: %s") % S.perk_def(id).get("title", id) if why == "" else I18n.t("Нельзя: ") + why)
	perk_sel = ""
	_sig = ""
	refresh()


func mutate_trait(remove_id: String, add_id: String) -> void:
	var a: Actor = _actor()
	if a == null:
		return
	var why: String = S.mutate(a, remove_id, add_id)
	_say(I18n.t("Перерождение: готово") if why == "" else I18n.t("Нельзя: ") + why)
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
		_note.text = I18n.t("Клик — выбрать · двойной клик — съесть/выпить · колесо — страницы · 1–9, 0 разделы · Esc закрыть")


func _codex() -> Dictionary:
	var w: Node = get_node_or_null("/root/Worlds")
	var c: Variant = w.get("codex") if w != null else null
	return c if c is Dictionary else {}


# =====================================================================
# ДНЕВНИК: записки кодексу, зібрані в книгу за розділами
# =====================================================================
func _fill_diary() -> void:
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 8)
	_body.add_child(mode_row)
	var lore_btn := Button.new()
	lore_btn.text = I18n.t("Летопись мира")
	lore_btn.toggle_mode = true
	lore_btn.button_pressed = diary_mode == "lore"
	ComicUI.button_styles(lore_btn, 14)
	lore_btn.pressed.connect(_set_diary_mode.bind("lore"))
	mode_row.add_child(lore_btn)
	var guide_btn := Button.new()
	guide_btn.text = I18n.t("Справочник выжившего")
	guide_btn.toggle_mode = true
	guide_btn.button_pressed = diary_mode == "guide"
	ComicUI.button_styles(guide_btn, 14)
	guide_btn.pressed.connect(_set_diary_mode.bind("guide"))
	mode_row.add_child(guide_btn)
	if diary_mode == "guide":
		_fill_guide()
		return
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
			_body.add_child(_wrap(_read_note(String(n["text"])), 14, COL_TEXT))


func _set_diary_mode(mode: String) -> void:
	diary_mode = mode
	_sig = ""
	refresh()


func _set_guide_category(category: String) -> void:
	guide_category = category
	_sig = ""
	refresh()


func _fill_guide() -> void:
	# Страница справочника оформлена как полевая книга: тёплая бумага, чернильный текст, тонкие латунные разделители.
	var page := PanelContainer.new()
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color("d5c49e")
	paper.border_color = Color("58442e")
	paper.set_border_width_all(2)
	paper.set_content_margin_all(12)
	page.add_theme_stylebox_override("panel", paper)
	ComicUI.ribbon(page, 18.0)
	_body.add_child(page)
	var book := VBoxContainer.new()
	book.add_theme_constant_override("separation", 7)
	page.add_child(book)
	var ink := Color("30251a")
	var muted := Color("66543d")
	var head := Label.new()
	head.text = I18n.t("Полевой справочник")
	head.add_theme_font_size_override("font_size", 21)
	head.add_theme_color_override("font_color", ink)
	book.add_child(head)
	var intro := Label.new()
	intro.text = I18n.t("Предметы, материалы, ремесло и приёмы, известные герою. Сведения берутся из игровых баз данных.")
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_font_size_override("font_size", 13)
	intro.add_theme_color_override("font_color", muted)
	book.add_child(intro)
	var filters := HFlowContainer.new()
	filters.add_theme_constant_override("h_separation", 5)
	filters.add_theme_constant_override("v_separation", 4)
	book.add_child(filters)
	for category in FieldGuide.categories():
		var b := Button.new()
		b.text = I18n.t(FieldGuide.category_name(String(category)))
		b.toggle_mode = true
		b.button_pressed = guide_category == String(category)
		b.add_theme_font_size_override("font_size", 12)
		b.add_theme_color_override("font_color", ink)
		var bs := StyleBoxFlat.new()
		bs.bg_color = Color("bba77f") if guide_category == String(category) else Color("cbb994")
		bs.border_color = Color("786044")
		bs.set_border_width_all(1)
		bs.set_content_margin_all(5)
		b.add_theme_stylebox_override("normal", bs)
		b.add_theme_stylebox_override("hover", bs)
		b.add_theme_stylebox_override("pressed", bs)
		b.pressed.connect(_set_guide_category.bind(String(category)))
		filters.add_child(b)
	var count_lbl := Label.new()
	count_lbl.text = I18n.t("Предметов в разделе: %d") % FieldGuide.items(guide_category).size()
	count_lbl.add_theme_font_size_override("font_size", 13)
	count_lbl.add_theme_color_override("font_color", muted)
	book.add_child(count_lbl)
	for entry in FieldGuide.items(guide_category):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 9)
		book.add_child(row)
		var glyph := ItemGlyph.new()
		glyph.item_id = String(entry.id)
		glyph.custom_minimum_size = Vector2(54, 54)
		row.add_child(glyph)
		var details := VBoxContainer.new()
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(details)
		var name_lbl := Label.new()
		name_lbl.text = String(entry.data.get("name", entry.id))
		name_lbl.add_theme_font_size_override("font_size", 15)
		name_lbl.add_theme_color_override("font_color", ink)
		details.add_child(name_lbl)
		var desc := Label.new()
		desc.text = String(entry.data.get("description", ""))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_font_size_override("font_size", 12)
		desc.add_theme_color_override("font_color", muted)
		details.add_child(desc)
		var meta: PackedStringArray = []
		if float(entry.data.get("weight", 0.0)) > 0.0:
			meta.append("%s кг" % str(entry.data.get("weight", 0.0)))
		if int(entry.data.get("price", 0)) > 0:
			meta.append("%s мон." % str(entry.data.get("price", 0)))
		if entry.data.has("use"):
			meta.append(I18n.t("можно употребить"))
		if entry.data.has("wear"):
			meta.append(I18n.t("экипировка"))
		if bool(entry.data.get("bound", false)):
			meta.append(I18n.t("неотъемлемая вещь"))
		var meta_lbl := Label.new()
		meta_lbl.text = " · ".join(meta)
		meta_lbl.add_theme_font_size_override("font_size", 11)
		meta_lbl.add_theme_color_override("font_color", Color("80633c"))
		details.add_child(meta_lbl)
		var sep := HSeparator.new()
		sep.add_theme_color_override("separator", Color("9b815b"))
		book.add_child(sep)
	book.add_child(_guide_section_title(I18n.t("Ремесло и рецепты"), ink))
	for recipe in FieldGuide.recipes():
		var out_name := Trade.item_name(String(recipe.get("out", "")))
		var materials: PackedStringArray = []
		for material_id in recipe.get("in", {}):
			materials.append("%s ×%d" % [Trade.item_name(String(material_id)), int(recipe.get("in", {}).get(material_id, 0))])
		var line := Label.new()
		line.text = "%s — %s. %s: %d; %s: %d; %s: %d" % [out_name, ", ".join(materials), I18n.t("уровень ремесла"), int(recipe.get("level", 0)), I18n.t("работа"), int(recipe.get("work", 0)), I18n.t("плата мастеру"), int(recipe.get("fee", 0))]
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.add_theme_font_size_override("font_size", 12)
		line.add_theme_color_override("font_color", ink)
		book.add_child(line)
	book.add_child(_guide_section_title(I18n.t("Боевые способности"), ink))
	for ability in FieldGuide.abilities():
		var title := Label.new()
		title.text = String(ability.title)
		title.add_theme_font_size_override("font_size", 14)
		title.add_theme_color_override("font_color", ink)
		book.add_child(title)
		var desc := Label.new()
		desc.text = String(ability.description)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_font_size_override("font_size", 12)
		desc.add_theme_color_override("font_color", muted)
		book.add_child(desc)


func _guide_section_title(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", color)
	return l


## Записка очима героя: з Інтелектом 3 і нижче розбираються лише окремі слова
func _read_note(text: String) -> String:
	var a: Actor = _actor()
	if a == null or not S.dumb(a):
		return text
	var out: PackedStringArray = []
	for w in text.split(" ", false):
		if w.length() <= 5:
			out.append(w)
		elif out.is_empty() or out[-1] != "…":
			out.append("…")
	return I18n.t("(Буквы пляшут, разобрать удаётся немногое.) %s") % " ".join(out)


# =====================================================================
# ХРОНІКА: ключові події життя самого героя (не історія світу)
# =====================================================================
func _fill_chronicle() -> void:
	var log: Array = Chronicle.entries(get_node_or_null("/root/Worlds"))
	if log.is_empty():
		_body.add_child(_wrap(I18n.t("Пока записать нечего. Хроника ведёт только то, что случилось с этим героем: первый город, первый бой, поручения, болезни, находки. Историю мира она не знает: её приходится выспрашивать, откапывать и читать."), 15, COL_DIM))
		return
	_body.add_child(_label(I18n.t("События жизни героя: %d") % log.size(), 17, COL_GOLD))
	for e in log:
		_body.add_child(HSeparator.new())
		_body.add_child(_label("%s  %s" % [Chronicle.mark(String(e.get("kind", ""))), GameClock.date_text(float(e.get("t", 0.0)))], 13, COL_DIM))
		_body.add_child(_wrap(Chronicle.render(e), 15, COL_TEXT))


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
		if Trade.item(id).has("transport") or Trade.bound(id):
			continue   # коня й віз не викинути (characters/transport.gd), пергамент і вуглик теж
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


## Кнопка «Карта» біля пергаменту в інвентарі: закрити вікно й розгорнути аркуш (world/parchment.gd)
func open_parchment() -> void:
	show_tab("map")


func drop_item(id: String) -> void:
	var bag: Dictionary = _bag()
	if bag.is_empty():
		return
	if Trade.bound(id):
		_say(I18n.t("%s всегда при себе") % Trade.item_name(id))
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
	var k: Key = event.physical_keycode
	# Набор текста в журнале: клавиши разделов не перехватываем, кроме Esc
	var w: Node = _worlds()
	var typing: bool = w != null and w.get("journal") != null and w.journal.is_editing()
	if typing and k != KEY_ESCAPE:
		return
	if k == KEY_ESCAPE or k == KEY_I:
		close()
	elif TAB_KEYS.has(k):
		show_tab(TABS[TAB_KEYS.find(k)])
	else:
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

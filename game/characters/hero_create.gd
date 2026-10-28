extends CanvasLayer
## Экран создания героя (из сборки 09, character_create.gd): слева — имя, пол, возраст, происхождение
## и профессия; по центру — биография, она переписывается при каждом изменении; справа — 10 очков на
## семь характеристик и черты характера. Правила — characters/hero_profile.gd.
## Сигнал finished отдаёт params для HeroProfile.apply или пустой словарь при отмене (Esc, «Назад»).

signal finished(params: Dictionary)

const P := preload("res://characters/hero_profile.gd")
const R := preload("res://characters/actor_rules.gd")
const ComicUI := preload("res://ui/comic_ui.gd")

const COL_TEXT := Color("d8cfb0")
const COL_DIM := Color("9a9078")
const COL_GOLD := Color("c9a24b")
const COL_GOOD := Color("8fd18a")
const COL_BAD := Color("e08a7a")

var gender: String = "female"
var alloc: Dictionary = {}
var traits: Array = []
var name_edit: LineEdit
var age_spin: SpinBox
var origin_opt: OptionButton
var prof_opt: OptionButton
var origin_text: Label
var prof_text: Label
var skills_label: Label
var points_label: Label
var create_btn: Button
var hint_label: Label
var gender_btns: Dictionary = {}
var stat_rows: Dictionary = {}
var _trait_btns: Dictionary = {}
var _trait_info: Label
var _trait_desc: Label
var _bio: RichTextLabel
var _bio_title: Label
var _bio_note: Label
var _rng := RandomNumberGenerator.new()
var _auto_name: String = ""


func _ready() -> void:
	layer = 80
	_rng.randomize()
	for s in P.stats_list():
		alloc[s] = 0
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.04, 0.94)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	root.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	box.add_child(_label(I18n.t("Создание персонажа"), 24, COL_TEXT, true))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 12)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(cols)
	cols.add_child(_side_panel(_build_left(), 300.0))
	cols.add_child(_build_story())
	cols.add_child(_side_panel(_build_right(), 360.0))
	hint_label = _label("", 15, COL_BAD, true)
	box.add_child(hint_label)
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 14)
	box.add_child(btns)
	btns.add_child(_button(I18n.t("Назад (Esc)"), func() -> void: finished.emit({})))
	btns.add_child(_button(I18n.t("Случайно"), randomize_all))
	create_btn = _button(I18n.t("Создать (Enter)"), _on_create)
	create_btn.add_theme_color_override("font_color", COL_GOLD)
	btns.add_child(create_btn)
	_set_gender("female")
	_refresh()
	name_edit.grab_focus.call_deferred()


func _side_panel(content: Control, w: float) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", ComicUI.panel(20.0))
	panel.custom_minimum_size = Vector2(w, 0.0)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(sc)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(content)
	return panel


func _build_story() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", ComicUI.panel(28.0))
	ComicUI.tech_plate(panel)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	_bio_title = _label(I18n.t("История персонажа"), 20, COL_GOLD, true)
	v.add_child(_bio_title)
	v.add_child(HSeparator.new())
	_bio = RichTextLabel.new()
	_bio.scroll_active = true
	_bio.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_bio.custom_minimum_size = Vector2(380.0, 300.0)
	_bio.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bio.add_theme_font_size_override("normal_font_size", 16)
	_bio.add_theme_constant_override("line_separation", 4)
	_bio.add_theme_color_override("default_color", Color("e6dcc0"))
	v.add_child(_bio)
	v.add_child(HSeparator.new())
	_bio_note = _label("", 13, COL_DIM, true)
	_bio_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_bio_note)
	return panel


# ---------------------------------------------------------------------
# СЛЕВА: имя, пол, возраст, происхождение, профессия
# ---------------------------------------------------------------------
func _build_left() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.add_child(_label(I18n.t("Имя"), 16, COL_DIM))
	var nr := HBoxContainer.new()
	name_edit = LineEdit.new()
	name_edit.placeholder_text = I18n.t("Как зовут персонажа")
	name_edit.max_length = 16
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_changed.connect(func(_t: String) -> void: _refresh())
	nr.add_child(name_edit)
	var rb := _small_button("⟳", _random_name)
	rb.tooltip_text = I18n.t("Случайное имя")
	nr.add_child(rb)
	v.add_child(nr)
	v.add_child(_label(I18n.t("Пол"), 16, COL_DIM))
	var gr := HBoxContainer.new()
	gr.add_theme_constant_override("separation", 8)
	v.add_child(gr)
	for g in ["female", "male"]:
		var gd: Dictionary = P.C()["genders"][g]
		var b := Button.new()
		b.text = String(gd["title"])
		var mods: Array = []
		for s in gd.get("stats", {}):
			mods.append("%s %+d" % [P.stat_name(s), int(gd["stats"][s])])
		b.tooltip_text = ", ".join(mods)
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_set_gender.bind(g))
		gender_btns[g] = b
		gr.add_child(b)
	var ar := HBoxContainer.new()
	ar.add_child(_label(I18n.t("Возраст"), 16, COL_DIM))
	age_spin = SpinBox.new()
	age_spin.min_value = int(P.C().get("age_min", 18))
	age_spin.max_value = int(P.C().get("age_max", 60))
	age_spin.value = 25
	age_spin.rounded = true
	age_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	age_spin.value_changed.connect(func(_x: float) -> void: _refresh())
	ar.add_child(age_spin)
	v.add_child(ar)
	v.add_child(HSeparator.new())
	v.add_child(_label(I18n.t("Происхождение"), 16, COL_DIM))
	origin_opt = _keyed_options(P.C()["origins"])
	v.add_child(origin_opt)
	origin_text = _wrap_label(13, COL_DIM)
	v.add_child(origin_text)
	v.add_child(_label(I18n.t("Профессия"), 16, COL_DIM))
	prof_opt = _keyed_options(P.C()["professions"])
	v.add_child(prof_opt)
	prof_text = _wrap_label(13, COL_DIM)
	v.add_child(prof_text)
	v.add_child(HSeparator.new())
	skills_label = _wrap_label(13, COL_TEXT)
	v.add_child(skills_label)
	var bag := _wrap_label(12, COL_DIM)
	bag.text = I18n.t("Вещей с собой нет: сумка пустая, всё нужное покупается или находится в пути.")
	v.add_child(bag)
	return v


func _keyed_options(src: Dictionary) -> OptionButton:
	var o := OptionButton.new()
	var i: int = 0
	for k in src:
		o.add_item(String(src[k]["title"]), i)
		o.set_item_metadata(i, k)
		i += 1
	o.focus_mode = Control.FOCUS_NONE
	o.item_selected.connect(func(_i: int) -> void: _refresh())
	return o


# ---------------------------------------------------------------------
# СПРАВА: очки характеристик и черты
# ---------------------------------------------------------------------
func _build_right() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	points_label = _label("", 17, COL_GOLD)
	v.add_child(points_label)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 3)
	v.add_child(grid)
	for h in ["", "", I18n.t("Очки"), "", I18n.t("Бонус"), I18n.t("Итог")]:
		grid.add_child(_label(h, 12, COL_DIM))
	for s in P.stats_list():
		var row: Dictionary = {}
		grid.add_child(_label(P.stat_name(s), 15, COL_TEXT))
		row["minus"] = _small_button("−", change_stat.bind(s, -1))
		grid.add_child(row["minus"])
		row["base"] = _label("", 15, COL_TEXT, true)
		row["base"].custom_minimum_size = Vector2(26.0, 0.0)
		grid.add_child(row["base"])
		row["plus"] = _small_button("+", change_stat.bind(s, 1))
		grid.add_child(row["plus"])
		row["bg"] = _label("", 15, COL_DIM, true)
		grid.add_child(row["bg"])
		row["total"] = _label("", 16, COL_GOLD, true)
		grid.add_child(row["total"])
		stat_rows[s] = row
	var note := _wrap_label(12, COL_DIM)
	note.text = I18n.t("Бонус — пол, возраст, происхождение, профессия и черты. Удача складывается из происхождения, профессии и черт и в начале скрыта.")
	v.add_child(note)
	v.add_child(HSeparator.new())
	v.add_child(_label(I18n.t("Черты характера"), 17, COL_GOLD))
	_trait_info = _wrap_label(13, COL_TEXT)
	v.add_child(_trait_info)
	var tg := GridContainer.new()
	tg.columns = 2
	tg.add_theme_constant_override("h_separation", 4)
	tg.add_theme_constant_override("v_separation", 3)
	v.add_child(tg)
	for t in P.C()["traits"]:
		var d: Dictionary = R.trait_def(t)
		var c: int = int(d.get("cost", 0))
		var b := Button.new()
		b.text = "%s %s" % [d["title"], ("−%d" % c) if c > 0 else ("+%d" % -c)]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(160.0, 26.0)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 13)
		b.add_theme_color_override("font_color", COL_GOOD if c > 0 else COL_BAD)
		b.add_theme_color_override("font_pressed_color", Color(1, 1, 1))
		b.tooltip_text = P.trait_text(t)
		b.pressed.connect(toggle_trait.bind(t))
		b.mouse_entered.connect(func() -> void: _trait_desc.text = _trait_full(t))
		_trait_btns[t] = b
		tg.add_child(b)
	_trait_desc = _wrap_label(13, COL_DIM)
	_trait_desc.text = I18n.t("Наведите на черту, чтобы увидеть описание. Зелёные — достоинства, красные — недостатки.")
	v.add_child(_trait_desc)
	return v


func _trait_full(t: String) -> String:
	var d: Dictionary = R.trait_def(t)
	var s: String = P.trait_text(t)
	if d.has("opp"):
		s += I18n.t(" Несовместима с «%s».") % R.trait_def(d["opp"]).get("title", "")
	return s


# ---------------------------------------------------------------------
# ЛОГИКА
# ---------------------------------------------------------------------
func origin() -> String:
	return String(origin_opt.get_item_metadata(origin_opt.selected))


func profession() -> String:
	return String(prof_opt.get_item_metadata(prof_opt.selected))


func params() -> Dictionary:
	return {"name": name_edit.text.strip_edges(), "gender": gender, "age": int(age_spin.value),
		"origin": origin(), "profession": profession(), "alloc": alloc.duplicate(), "traits": traits.duplicate()}


func change_stat(s: String, d: int) -> void:
	var nv: int = int(alloc[s]) + d
	if nv < 0 or (d > 0 and P.points_spent(alloc) >= int(P.C().get("points", 10))):
		return
	alloc[s] = nv
	_refresh()


func toggle_trait(t: String) -> void:
	if traits.has(t):
		traits.erase(t)
	else:
		var test: Array = traits.duplicate()
		test.append(t)
		if P.traits_valid(test) == "":
			traits = test
	_refresh()


func _random_name() -> void:
	var names: Array = P.C()["names"][gender]
	var cur: String = name_edit.text.strip_edges()
	var pick: String = cur
	for _i in 8:
		pick = String(names[_rng.randi() % names.size()])
		if pick != cur:
			break
	name_edit.text = pick
	_auto_name = pick
	_refresh()


func _set_gender(g: String) -> void:
	# имя, выданное «случайно» для другого пола, меняется вместе с полом
	var was_auto: bool = name_edit != null and _auto_name != "" and name_edit.text.strip_edges() == _auto_name
	var changed: bool = g != gender
	gender = g
	for k in gender_btns:
		gender_btns[k].button_pressed = k == g
	if was_auto and changed:
		_random_name()
	_refresh()


func randomize_all() -> void:
	var p: Dictionary = P.random_params(_rng)
	_set_gender(p["gender"])
	name_edit.text = p["name"]
	_auto_name = p["name"]
	age_spin.set_value_no_signal(p["age"])
	_select_key(origin_opt, p["origin"])
	_select_key(prof_opt, p["profession"])
	alloc = p["alloc"]
	traits = p["traits"]
	_refresh()


func _select_key(o: OptionButton, key: String) -> void:
	for i in o.item_count:
		if String(o.get_item_metadata(i)) == key:
			o.select(i)


func problems() -> Array:
	var out: Array = []
	if name_edit.text.strip_edges() == "":
		out.append(I18n.t("введите имя"))
	var left: int = int(P.C().get("points", 10)) - P.points_spent(alloc)
	if left > 0:
		out.append(I18n.t("распределите очки (%d)") % left)
	return out


func _refresh() -> void:
	if stat_rows.is_empty() or origin_opt == null:
		return
	var p: Dictionary = params()
	var parts: Dictionary = P.stat_parts(p)
	var left: int = int(P.C().get("points", 10)) - P.points_spent(alloc)
	points_label.text = I18n.t("Свободные очки: %d из %d") % [left, int(P.C().get("points", 10))]
	for s in P.stats_list():
		var row: Dictionary = stat_rows[s]
		var e: Dictionary = parts[s]
		row["base"].text = str(int(e["base"]))
		var diff: int = int(e["total"]) - int(e["base"])
		row["bg"].text = ("%+d" % diff) if diff != 0 else "·"
		row["bg"].add_theme_color_override("font_color", COL_GOOD if diff > 0 else (COL_BAD if diff < 0 else COL_DIM))
		row["total"].text = str(int(e["total"]))
		row["minus"].disabled = int(alloc[s]) <= 0
		row["plus"].disabled = left <= 0
	var c: Dictionary = P.traits_cost(traits)
	var al: String = P.alignment_name(P.alignment(traits))
	_trait_info.text = I18n.t("Выбрано %d из %d · достоинства %d · недостатки %d · мировоззрение: %s") % [
		traits.size(), int(P.C().get("trait_max", 10)), int(c["positive"]), int(c["negative"]), al]
	for t in _trait_btns:
		var b: Button = _trait_btns[t]
		b.set_pressed_no_signal(traits.has(t))
		var test: Array = traits.duplicate()
		test.append(t)
		b.disabled = not traits.has(t) and P.traits_valid(test) != ""
	origin_text.text = _describe(P.C()["origins"][origin()])
	prof_text.text = _describe(P.C()["professions"][profession()])
	var sk: Array = []
	var lv: Dictionary = P.skill_levels(p)
	for k in lv:
		sk.append("%s %d" % [R.skills()[k].get("name_ru", k), int(lv[k])])
	skills_label.text = I18n.t("Навыки: ") + (", ".join(sk) if not sk.is_empty() else I18n.t("нет"))
	var story: String = P.biography(p)
	if _bio.text != story:
		_bio.text = story
		_bio.scroll_to_line(0)
	_bio_title.text = I18n.t("История: %s") % (p["name"] if p["name"] != "" else I18n.t("без имени"))
	_bio_note.text = I18n.t("%s · %s · мировоззрение: %s") % [P.C()["origins"][origin()]["title"], P.C()["professions"][profession()]["title"], al]
	var pr: Array = problems()
	hint_label.text = (I18n.t("Чтобы продолжить: ") + ", ".join(pr)) if not pr.is_empty() else ""
	create_btn.disabled = not pr.is_empty()


func _describe(d: Dictionary) -> String:
	var parts: Array = []
	for s in d.get("stats", {}):
		parts.append("%s %+d" % [P.stat_name(s), int(d["stats"][s])])
	if int(d.get("luck", 0)) != 0:
		parts.append(I18n.t("Удача %+d") % int(d["luck"]))
	for k in d.get("skills", {}):
		parts.append("%s %d" % [R.skills().get(k, {}).get("name_ru", k), int(d["skills"][k])])
	return "%s %s" % [String(d.get("text", "")), "; ".join(parts)]


func _on_create() -> void:
	_refresh()
	if create_btn.disabled or not P.alloc_valid(alloc):
		return
	finished.emit(params())


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var ke := event as InputEventKey
		if ke.keycode == KEY_ESCAPE:
			finished.emit({})
			get_viewport().set_input_as_handled()
		elif ke.keycode == KEY_ENTER or ke.keycode == KEY_KP_ENTER:
			_on_create()
			get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------
# ЭЛЕМЕНТЫ
# ---------------------------------------------------------------------
func _label(text: String, size: int, color: Color, centered: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if centered:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _wrap_label(size: int, color: Color) -> Label:
	var l := _label("", size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(200.0, 0.0)
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(180.0, 40.0)
	b.add_theme_font_size_override("font_size", 18)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


func _small_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(30.0, 28.0)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b

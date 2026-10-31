extends CanvasLayer
## Табір героя в полі (K) — механіки 1, 4, 8 і частина 2, 6 (Huzzah 2026-10-29, за мотивами виживання, без чужих даних):
##   вогнище: хмиз або плавник + кремінь (шанс за Виживанням) чи смолоскип (напевно); горить fire_h годин на оберемок;
##   готування біля вогню: смажити й в'ялити м'ясо, пекти гриби, варити юшку, заварювати відвар, кип'ятити воду біля річки;
##   сон: на голій землі гірше, спальник і намет краще, вогнище гріє, але світло й дим видають героя (ефекти conditions.json);
##   розбирання туші після бою зі звіром (нож — повна здобич), лагодження набором (characters/wear.gd).
## Час гри йде на кожну дію. Стан (вогнище) — у to_dict, пишеться разом із героєм (cast.gd). Числа — data/world/camp.json.

const Trade := preload("res://city/trade.gd")
const Wear := preload("res://characters/wear.gd")
const FILE := "res://data/world/camp.json"

var cast: Node2D
var fire: Dictionary = {}          # {x, y, until} — вогнище на карті
var rng := RandomNumberGenerator.new()
var data: Dictionary = {}

var _panel: PanelContainer
var _title: Label
var _info: Label
var _box: VBoxContainer
var _note: Label


func setup(c: Node2D) -> void:
	cast = c
	layer = 24
	visible = false
	rng.randomize()
	var v: Variant = I18n.tree(JSON.parse_string(FileAccess.get_file_as_string(FILE)))
	data = v if v is Dictionary else {}
	_build()


func _game() -> Node2D:
	return cast.game


func _now() -> float:
	return _game().clock.total_seconds


func _hero() -> Dictionary:
	return cast.hero


func _bag() -> Dictionary:
	return cast._inventory()


func _num(k: String, def: float) -> float:
	return float(data.get(k, def))


# =====================================================================
# ВОГНИЩЕ
# =====================================================================
func fire_lit() -> bool:
	return not fire.is_empty() and float(fire.get("until", 0.0)) > _now()


func fire_pos() -> Vector2:
	return Vector2(float(fire.get("x", 0.0)), float(fire.get("y", 0.0)))


func near_fire(p: Vector2) -> bool:
	return fire_lit() and fire_pos().distance_to(p) <= _num("fire_reach_m", 15.0)


func fire_left_h() -> float:
	return maxf(float(fire.get("until", 0.0)) - _now(), 0.0) / 3600.0 if not fire.is_empty() else 0.0


func _wood(bag: Dictionary) -> String:
	for id in data.get("wood", ["brushwood"]):
		if Trade.count(bag, id) > 0:
			return id
	return ""


func _pass(minutes: float) -> void:
	_game().clock._set_total(_now() + minutes * 60.0)


func light_chance() -> float:
	var bag: Dictionary = _bag()
	if Trade.count(bag, "torch") > 0:
		return 1.0
	if Trade.count(bag, "flint") <= 0:
		return 0.0
	return clampf(_num("light", 0.55) + _num("light_per_level", 0.04) * cast.hero["actor"].skill_level("survival"), 0.05, 0.95)


## Розпалити вогнище на місці героя; текст для гравця
func light_fire() -> String:
	var bag: Dictionary = _bag()
	var w: String = _wood(bag)
	if w == "":
		return I18n.t("Нечем топить: нужен хворост или плавник (F — обшарить округу)")
	var c: float = light_chance()
	if c <= 0.0:
		return I18n.t("Нечем высечь огонь: нужен кремень или факел")
	_pass(_num("light_min", 10.0))
	if rng.randf() >= c:
		cast.hero["actor"].add_xp("survival", 0.5)
		return I18n.t("Искры гаснут в сырых ветках. Ещё раз?")
	Trade.add(bag, w, -1)
	var p: Vector2 = _hero()["pos"]
	fire = {"x": p.x, "y": p.y, "until": _now() + _num("fire_h", 2.0) * 3600.0}
	cast.hero["actor"].add_xp("survival", 1.0)
	return I18n.t("Костёр разгорелся (%s)") % Trade.item_name(w)


func add_wood() -> String:
	var bag: Dictionary = _bag()
	var w: String = _wood(bag)
	if w == "" or not fire_lit():
		return I18n.t("Нечего подбросить")
	Trade.add(bag, w, -1)
	fire["until"] = float(fire["until"]) + _num("fire_h", 2.0) * 3600.0
	return I18n.t("Подбросил дров: гореть ещё %.1f ч") % fire_left_h()


func put_out() -> String:
	fire = {}
	return I18n.t("Костёр затоптан")


# =====================================================================
# ГОТУВАННЯ
# =====================================================================
func recipes() -> Dictionary:
	return data.get("recipes", {})


## Чому не можна приготувати ("" — можна)
func cook_blocker(id: String) -> String:
	var r: Dictionary = recipes().get(id, {})
	if r.is_empty():
		return "?"
	if not near_fire(_hero()["pos"]):
		return I18n.t("нужен костёр")
	if bool(r.get("near_water", false)) and not cast._water_near(_hero()["pos"]):
		return I18n.t("нужна вода рядом")
	if r.has("max_out"):
		for o in r["out"]:
			if Trade.count(_bag(), o) >= int(r["max_out"]):
				return I18n.t("больше не унести")
	var lack: PackedStringArray = []
	for k in r.get("in", {}):
		if Trade.count(_bag(), k) < int(r["in"][k]):
			lack.append("%s ×%d" % [Trade.item_name(k), int(r["in"][k])])
	return I18n.t("нет: %s") % ", ".join(lack) if not lack.is_empty() else ""


func cook(id: String) -> String:
	var why: String = cook_blocker(id)
	if why != "":
		return why
	var r: Dictionary = recipes()[id]
	var bag: Dictionary = _bag()
	var a: Actor = cast.hero["actor"]
	for k in r.get("in", {}):
		Trade.add(bag, k, -int(r["in"][k]))
	_pass(float(r.get("min", 20)))
	a.add_xp("survival", 1.0)
	var burn: float = clampf(float(r.get("burn", _num("burn", 0.25))) - _num("burn_per_level", 0.03) * a.skill_level("survival"), 0.0, 0.9)
	if rng.randf() < burn:
		Trade.add(bag, "charred_food", 1)
		return I18n.t("Подгорело: %s") % Trade.item_name("charred_food")
	var parts: PackedStringArray = []
	for o in r["out"]:
		Trade.add(bag, o, int(r["out"][o]))
		parts.append("%s ×%d" % [Trade.item_name(o), int(r["out"][o])])
	a.carried_kg = Trade.weight(bag)
	return I18n.t("Готово: %s") % ", ".join(parts)


# =====================================================================
# ЗДОБИЧ: розібрати туші після бою (механіка 2)
# =====================================================================
func has_knife() -> bool:
	for id in data.get("knives", ["knife"]):
		if Trade.count(_bag(), id) > 0:
			return true
	return false


## kinds — шаблони вбитих звірів; повертає {found: {id: n}, minutes, text}
func butcher(kinds: Array) -> Dictionary:
	var table: Dictionary = data.get("butcher", {})
	var knife: bool = has_knife()
	var found: Dictionary = {}
	var minutes: float = 0.0
	var n: int = 0
	for k in kinds:
		var t: Dictionary = table.get(String(k), {})
		if t.is_empty():
			continue
		n += 1
		minutes += float(t.get("min", 20)) * (1.0 if knife else 1.5)
		for id in t["out"]:
			var c: int = int(t["out"][id])
			if not knife:
				if id == "hide":
					continue
				if id.ends_with("meat"):
					c = int(ceil(c * 0.5))
			found[id] = int(found.get(id, 0)) + c
	if n == 0:
		return {"found": {}, "minutes": 0.0, "text": ""}
	var txt: String = I18n.t("Разделал туши (%d): %d мин") % [n, int(minutes)]
	if not knife:
		txt += I18n.t(" — без ножа: мяса меньше, шкуры порваны")
	return {"found": found, "minutes": minutes, "text": txt}


# =====================================================================
# СОН І УКРИТТЯ (механіка 8): ефекти тримаються, поки умова діє
# =====================================================================
## Яке укриття зараз у героя: "tent", "bedroll", "open"
func shelter() -> String:
	var bag: Dictionary = _bag()
	if Trade.count(bag, "tent") > 0:
		return "tent"
	if Trade.count(bag, "bedroll") > 0:
		return "bedroll"
	return "open"


static var SHELTER_NAMES: Dictionary = {"tent": I18n.t("в палатке"), "bedroll": I18n.t("на спальнике"), "open": I18n.t("на голой земле")}


## Кадр героя в полі: ефекти вогню й укриття
func tick() -> void:
	var h: Dictionary = _hero()
	if h.is_empty() or cast.hero_away:
		return
	var a: Actor = h["actor"]
	var want: Array = []
	if near_fire(h["pos"]):
		want.append("by_fire")
	if a.sleeping:
		want.append({"tent": "shelter_tent", "bedroll": "shelter_bedroll", "open": "sleep_open"}[shelter()])
	_keep_buffs(a, want)


const CAMP_BUFFS: Array = ["by_fire", "shelter_tent", "shelter_bedroll", "sleep_open"]


# Ефекти табору тримаються, поки умова діє, і знімаються одразу, коли ні (тривалість у conditions.json — запас на довгий крок часу)
static func _keep_buffs(a: Actor, want: Array) -> void:
	for b in a.buffs.duplicate():
		if String(b["id"]) in CAMP_BUFFS and not want.has(String(b["id"])):
			a.buffs.erase(b)
	for id in want:
		a.add_buff(id)


# =====================================================================
# ПАНЕЛЬ (K)
# =====================================================================
func open() -> void:
	if _hero().is_empty() or cast.hero_away:
		return
	visible = true
	cast.hold_hero = true
	_note.text = ""
	refresh()


func close() -> void:
	visible = false
	cast.hold_hero = false


func is_open() -> bool:
	return visible


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func _act(fn: Callable) -> void:
	var t: String = String(fn.call())
	if not visible:
		return
	_note.text = t
	refresh()


func refresh() -> void:
	if not visible:
		return
	var h: Dictionary = _hero()
	var bag: Dictionary = _bag()
	var lines: PackedStringArray = []
	if fire_lit():
		lines.append(I18n.t("Костёр горит ещё %.1f ч%s") % [fire_left_h(), "" if near_fire(h["pos"]) else I18n.t(" (далеко)")])
	else:
		lines.append(I18n.t("Костра нет"))
	lines.append(I18n.t("Ночлег: %s") % SHELTER_NAMES[shelter()])
	var dmg: Array = Wear.damaged(bag)
	if not dmg.is_empty():
		lines.append(I18n.t("Износ: %s") % ", ".join(PackedStringArray(dmg.map(func(id): return "%s %d %%" % [Trade.item_name(id), int(Wear.cond(bag, id))]))))
	_info.text = "\n".join(lines)
	for c in _box.get_children():
		c.queue_free()
	if not near_fire(h["pos"]):
		var t: String = I18n.t("Развести костёр (шанс %d %%)") % int(round(light_chance() * 100.0))
		_btn(t, light_fire, _wood(bag) == "" or light_chance() <= 0.0)
	else:
		_btn(I18n.t("Подбросить дров (+%d ч)") % int(_num("fire_h", 2.0)), add_wood, _wood(bag) == "")
		for id in recipes():
			var why: String = cook_blocker(id)
			var r: Dictionary = recipes()[id]
			_btn(I18n.t("%s (%d мин)%s") % [String(r.get("name", id)), int(r.get("min", 20)), "" if why == "" else "  — " + why], cook.bind(id), why != "")
		_btn(I18n.t("Затоптать костёр"), put_out, false)
	_btn(I18n.t("Подлатать вещь набором"), func(): return Wear.repair_with_kit(bag), Trade.count(bag, "repair_kit") <= 0 or dmg.is_empty())
	_btn(I18n.t("Лечь спать (%s%s)") % [SHELTER_NAMES[shelter()], I18n.t(", у огня") if near_fire(h["pos"]) else ""], _sleep, false)
	_btn(I18n.t("Закрыть  [K]"), _close_btn, false)
	_panel.reset_size()
	_panel.position = Vector2(20, (_panel.get_viewport_rect().size.y - _panel.size.y) * 0.5)


func _close_btn() -> String:
	close()
	return ""


func _sleep() -> String:
	close()
	cast.hero["actor"].set_sleep(true)
	return ""


func _btn(t: String, fn: Callable, disabled: bool) -> void:
	var b := Button.new()
	b.text = t
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.disabled = disabled
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): _act(fn))
	_box.add_child(b)


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", preload("res://ui/comic_ui.gd").panel(22.0, 0.96))
	_panel.custom_minimum_size = Vector2(460, 0)
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_panel.add_child(v)
	_title = Label.new()
	_title.text = I18n.t("Лагерь")
	_title.add_theme_font_size_override("font_size", 20)
	_title.add_theme_color_override("font_color", Color("f0d890"))
	v.add_child(_title)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(430, 0)
	v.add_child(_info)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 4)
	v.add_child(_box)
	_note = Label.new()
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(430, 0)
	_note.add_theme_color_override("font_color", Color(0.95, 0.8, 0.5))
	v.add_child(_note)


func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_K or event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func to_dict() -> Dictionary:
	return fire.duplicate()


func load_dict(d: Variant) -> void:
	fire = d.duplicate() if d is Dictionary else {}

extends RefCounted
## Розмови з варіантами відповідей (пункт 7, Huzzah 2026-10-29): дерева з data/dialogue/dialogues.json.
## Житель знаходиться за id з плану міста або за «role:<роль>». Варіанти з вимогами (характеристика, гроші, річ,
## позначка) показуються лише тим, кому вони доступні, з міткою [Обаяние], [Ум]…; наслідки — гроші, речі,
## ставлення жителя, досвід, позначки «вже було». Стан (вузол розмови, ставлення, позначки) живе в місті.

const Sheet := preload("res://characters/sheet.gd")
const Trade := preload("res://city/trade.gd")
const FILE := "res://data/dialogue/dialogues.json"
static var STAT_TAGS: Dictionary = {"str": I18n.t("Сила"), "per": I18n.t("Чутьё"), "end": I18n.t("Стойкость"), "cha": I18n.t("Обаяние"), "int": I18n.t("Ум"), "agi": I18n.t("Ловкость"), "luck": I18n.t("Удача")}

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(FILE, FileAccess.READ)
		if f != null:
			var v: Variant = I18n.tree(JSON.parse_string(f.get_as_text()))
			if v is Dictionary:
				_data = v
		if _data.is_empty():
			_data = {"_none": true}
	return _data


## Дерево для жителя (за id, інакше за роллю) або {}
static func tree_for(npc_id: String, role: String) -> Dictionary:
	var d: Dictionary = data()
	if d.get(npc_id) is Dictionary:
		return d[npc_id]
	if d.get("role:" + role) is Dictionary:
		return d["role:" + role]
	return {}


static func node(tree: Dictionary, id: String) -> Dictionary:
	return tree.get(id, tree.get("start", {}))


## Чи доступний варіант; state = {flags: {}, attitude: int}
static func allowed(opt: Dictionary, hero: Actor, bag: Dictionary, state: Dictionary) -> bool:
	var r: Dictionary = opt.get("req", {})
	for s in r.get("stat", {}):
		if hero == null or Sheet.stat_value(hero, s) < int(r["stat"][s]):
			return false
	if r.has("money") and int(bag.get("money", 0)) < int(r["money"]):
		return false
	if r.has("item") and Trade.count(bag, String(r["item"])) <= 0:
		return false
	var flags: Dictionary = state.get("flags", {})
	if r.has("flag") and not flags.has(String(r["flag"])):
		return false
	if r.has("not_flag") and flags.has(String(r["not_flag"])):
		return false
	if r.has("attitude") and int(state.get("attitude", 0)) < int(r["attitude"]):
		return false
	return true


## Підпис варіанта: текст уже містить мітку, якщо автор її поставив; інакше — мітка характеристики з вимоги
static func label(opt: Dictionary) -> String:
	var t: String = String(opt.get("text", "…"))
	if t.begins_with("["):
		return t
	var st: Dictionary = opt.get("req", {}).get("stat", {})
	if st.is_empty():
		return t
	var k: String = String(st.keys()[0])
	return "[%s] %s" % [STAT_TAGS.get(k, k), t]


## Застосувати наслідки; відповідь — рядок для підказки ("" — нічого)
static func apply(opt: Dictionary, hero: Actor, bag: Dictionary, state: Dictionary) -> String:
	var e: Dictionary = opt.get("eff", {})
	if e.has("money"):
		bag["money"] = maxi(int(bag.get("money", 0)) + int(e["money"]), 0)
	for id in e.get("item", {}):
		Trade.add(bag, String(id), int(e["item"][id]))
	if e.has("attitude"):
		state["attitude"] = clampi(int(state.get("attitude", 0)) + int(e["attitude"]), -5, 5)
	if e.has("flag"):
		if not state.has("flags"):
			state["flags"] = {}
		state["flags"][String(e["flag"])] = true
	if e.has("xp") and hero != null:
		hero.add_xp(String(e["xp"]), 1.0)
	return I18n.t(String(e.get("say", ""))) if e.has("say") else ""


## Настрій жителя для портрета: -1 злий, 0 байдужий, 1 прихильний
static func mood(state: Dictionary) -> int:
	var a: int = int(state.get("attitude", 0))
	return -1 if a < 0 else (1 if a > 0 else 0)

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
	# Ум у розмові (з дарами): iq — лише для розумних, iq_max — лише для дурних
	var iq: int = Sheet.talk_int(hero) if hero != null else 5
	if r.has("iq") and iq < int(r["iq"]):
		return false
	if r.has("iq_max") and iq > int(r["iq_max"]):
		return false
	return true


## Підпис варіанта: текст уже містить мітку, якщо автор її поставив; інакше — мітка характеристики з вимоги.
## Герой з Умом 3 і нижче (Sheet.dumb) говорить варіантом dumb, а без нього довга фраза мимриться (mumble)
static func label(opt: Dictionary, hero: Actor = null) -> String:
	var t: String = String(opt.get("text", "…"))
	if hero != null and Sheet.dumb(hero):
		t = String(opt["dumb"]) if opt.has("dumb") else mumble(t)
	if t.begins_with("["):
		return t
	var st: Dictionary = opt.get("req", {}).get("stat", {})
	if st.is_empty():
		return t
	var k: String = String(st.keys()[0])
	return "[%s] %s" % [STAT_TAGS.get(k, k), t]


## Довга фраза в устах дурня: мітка [..] лишається, від решти — два-три слова з «е-е»
static func mumble(t: String) -> String:
	var tag: String = ""
	if t.begins_with("[") and t.contains("]"):
		tag = t.left(t.find("]") + 1) + " "
		t = t.substr(t.find("]") + 1).strip_edges()
	var words: PackedStringArray = t.split(" ", false)
	if words.size() <= 2:
		return tag + t
	var keep: PackedStringArray = []
	for w in words:
		var c: String = w.strip_edges().trim_suffix(",").trim_suffix(".").trim_suffix("?").trim_suffix("!").to_lower()
		if c.length() >= 4:
			keep.append(c)
		if keep.size() >= 2:
			break
	if keep.is_empty():
		return tag + t
	var q: String = "?" if t.ends_with("?") else "."
	return tag + I18n.t("Э-э… ") + "… ".join(keep) + q


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

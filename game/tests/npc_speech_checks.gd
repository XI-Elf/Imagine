extends SceneTree
## Четверта стіна: у мові жителів (діалоги, репліки, доручення, розвилки, записки) немає слів про інтерфейс і механіку.
## Системні підписи («Доручення: 2 — вкладка») лишаються поза лапками й тут не перевіряються.
## godot --path game -s res://tests/npc_speech_checks.gd

# Російський і український варіанти: вкладка, клавіша, кнопка, меню, вікно, Tab, F-клавіші, (E)-підказки, рівень, очки, характеристика, інтерфейс
const BAD := "(вкладк|вкладц|клавиш|клавіш|кнопк|кнопц|меню|окн[оеа]\\b|вікн|\\bTab\\b|нажм|натисн|\\bF\\d{1,2}\\b|\\(\\s*[A-Z]\\s*\\)|\\bуровн|\\bрівн|\\bочк[иов]|характеристик|интерфейс|інтерфейс|\\bигрок|\\bгравц|в игре|у грі)"

var fails: int = 0
var checks: int = 0


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("FAIL: ", what)
	else:
		print("ok: ", what)


func load_json(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## Усі рядки мови жителів: [джерело, текст]
func speech() -> Array:
	var out: Array = []
	var d: Dictionary = load_json("res://data/dialogue/dialogues.json")
	for npc in d:
		if String(npc).begins_with("_"):
			continue
		for nid in d[npc]:
			out.append(["dialogue/%s/%s" % [npc, nid], String(d[npc][nid]["text"])])
	var s: Dictionary = load_json("res://data/cities/s001.json")
	for n in s["npcs"]:
		for l in n.get("lines", []):
			out.append(["s001/%s" % n["id"], String(l)])
	for st in s["growth"]["stages"]:
		for k in st.get("npc_set", {}):
			for l in st["npc_set"][k].get("lines", []):
				out.append(["s001/stage/%s" % k, String(l)])
	for k in s["growth"]["quests"]:
		for q in s["growth"]["quests"][k]:
			out.append(["quest/%s/ask" % q["id"], String(q["ask"])])
			out.append(["quest/%s/done" % q["id"], String(q["done"])])
	for p in s["places"]:
		if p.get("text") != null:
			out.append(["place/%s" % p["name"], String(p["text"])])
	var f: Dictionary = load_json("res://data/cities/forks.json")
	for id in f["forks"]:
		var fk: Dictionary = f["forks"][id]
		out.append(["fork/%s/scene" % id, String(fk["scene"])])
		out.append(["fork/%s/complicit" % id, String(fk["complicit"]["text"])])
		out.append(["fork/%s/principled" % id, String(fk["principled"]["text"])])
	var nn: Dictionary = load_json("res://data/lore/notes.json")
	for e in nn["entries"]:
		if String(e.get("src", "")) == "talk":
			out.append(["tale/%s" % e["id"], String(e["text"])])
	return out


func _initialize() -> void:
	var re := RegEx.new()
	re.compile(BAD)
	var all: Array = speech()
	ok(all.size() > 150, "собрано реплик жителей: %d" % all.size())
	var bad: Array = []
	for e in all:
		var m: RegExMatch = re.search(String(e[1]))
		if m != null:
			bad.append("%s: «%s»" % [e[0], m.get_string()])
	ok(bad.is_empty(), "в русских репликах нет слов об интерфейсе %s" % [bad])
	# Украинский перевод тех же строк (в uk.po): msgstr для msgid, равных репликам
	var ru: Dictionary = {}
	for e in all:
		ru[String(e[1])] = e[0]
	var po: String = FileAccess.get_file_as_string("res://i18n/uk.po")
	var uk_bad: Array = []
	var seen: int = 0
	var lines: PackedStringArray = po.split("\n")
	var i: int = 0
	while i < lines.size() - 1:
		if lines[i].begins_with("msgid \"") and lines[i + 1].begins_with("msgstr \""):
			var mid: String = JSON.parse_string(lines[i].substr(6))
			if ru.has(mid):
				seen += 1
				var ms: String = JSON.parse_string(lines[i + 1].substr(7))
				var m2: RegExMatch = re.search(ms)
				if m2 != null:
					uk_bad.append("%s: «%s»" % [ru[mid], m2.get_string()])
		i += 1
	ok(seen > 100 and uk_bad.is_empty(), "в украинских репликах нет слов об интерфейсе (проверено %d) %s" % [seen, uk_bad])
	# Контроль самого теста: слово о вкладке ловится
	ok(re.search("Поручения — во вкладке") != null and re.search("Доручення — у вкладці") != null, "тест ловит «во вкладке» и «у вкладці»")
	print("npc_speech_checks: %d/%d ok" % [checks - fails, checks])
	quit(1 if fails > 0 else 0)

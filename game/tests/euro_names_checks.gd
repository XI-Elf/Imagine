extends SceneTree
## Европейские названия (Huzzah 2026-10-28): нет славянских названий мест, этапов, должностей и имён НПС;
## этап роста называется отдельно от города. Таблица замен — amber2d/euro_names/ЗАМЕНЫ.md.
## godot --headless --path game -s res://tests/euro_names_checks.gd

const Names := preload("res://characters/npc_names.gd")
const Cast := preload("res://characters/cast.gd")
const Growth := preload("res://city/city_growth.gd")

# Корни, которых не должно остаться в игровых текстах
const BANNED: Array = ["Чёрнослав", "Острог", "Слобод", "слобож", "Слобож", "Посад", "посадник", "Детинец", "детинец",
	" изба ", " изба.", " избу", "Изба", "староста", "старосты", "знахар", "Знахар", "капище", "хутор", "посёлок", "посёлке", "посёлка",
	"Трактир", "трактир", "срубы", "на торг", "что у нас торг", "Тракт", "тракте", "грамоты", "Куй не хочу",
	"Агата", "Борислав", "Добрыня", "Ждан", "Остромир", "Прася", "Нежана", "Ведана"]
# Файлы с текстами, которые видит игрок
const FILES: Array = ["res://data/cities/s001.json", "res://data/cities/items.json", "res://data/world/settlements.json",
	"res://art/map/map_names.json", "res://data/characters/creation.json", "res://data/characters/skills.json",
	"res://city/city_world.gd", "res://city/city_menu.gd", "res://city/endless_quests.gd", "res://characters/cast.gd",
	"res://tutorial/tutorial.gd", "res://game.gd", "res://world/settlements.gd"]

var fails: int = 0
var checks: int = 0


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("FAIL: ", what)


func _json(path: String) -> Dictionary:
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return v if v is Dictionary else {}


func _init() -> void:
	for f in FILES:
		var t: String = FileAccess.get_file_as_string(f)
		ok(t != "", "%s читается" % f)
		var found: Array = BANNED.filter(func(w): return t.contains(w))
		ok(found.is_empty(), "%s: славянские названия %s" % [f, found])
	# Город и этапы роста
	var s001: Dictionary = _json("res://data/cities/s001.json")
	var world: Dictionary = _json("res://data/world/settlements.json")
	ok(s001.get("name", "") == "Эшвик" and world["settlements"][0]["name"] == "Эшвик", "город — Эшвик")
	var stages: Array = []
	for i in s001["growth"]["stages"].size():
		stages.append(Growth.stage_name(s001, i))
	ok(stages == ["Форт", "Деревня", "Бург", "Город", "Крупный город"], "этапы роста: %s" % [stages])
	ok(not stages.has(s001["name"]), "этап роста не называется как город")
	ok(world["sizes"]["hamlet"]["name"] == "усадьба" and world["sizes"]["town"]["name"] == "городок", "размеры поселений без хутора и посёлка")
	# Должности и здания
	var b: Dictionary = {}
	for x in s001["buildings"]:
		b[x["id"]] = x["name"]
	ok(b["hall"] == "Чертог олдермена" and b["healer"] == "Лечебница" and b["inn"].begins_with("Таверна"), "здания: %s, %s, %s" % [b["hall"], b["healer"], b["inn"]])
	var elder: String = s001["npcs"].filter(func(n): return n["id"] == "posadnik")[0]["name"]
	ok(elder == "Олдермен Беорхтнот", "глава города: %s" % elder)
	# Области карты — 31 новое название, без повторов
	var prov: Dictionary = _json("res://art/map/map_names.json").get("provinces", {})
	var pn: Dictionary = {}
	for k in prov:
		pn[prov[k]["name"]] = true
	ok(prov.size() == 31 and pn.size() == 31, "31 область, названия не повторяются: %d" % pn.size())
	ok(prov["7"]["name"] == "Брэндхит", "область Эшвика — Брэндхит")
	# Имена НПС на общей карте — из европейского списка
	for n in Cast.NPC_NAMES:
		ok(Names.culture_of(n) != "", "НПС на карте %s — имя из списка" % n)
	ok(not _json("res://data/characters/creation.json")["names"]["male"].has("Ян"), "в именах героя нет «Ян»")
	print("euro_names_checks: %d/%d ok" % [checks - fails, checks])
	quit(1 if fails > 0 else 0)

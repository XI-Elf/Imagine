extends SceneTree
## Серость мира (amber_lore/tone_seryy.md): історії світу з розмов, хроніка героя, відсутність чужих назв у даних гри.
## godot --path game --rendering-driver opengl3 -s res://tests/arkanar_checks.gd

const Trade := preload("res://city/trade.gd")
const Codex := preload("res://world/codex.gd")
const Chronicle := preload("res://characters/chronicle.gd")
const HeroDeath := preload("res://characters/hero_death.gd")
const FORBIDDEN: Array = ["Арканар", "Стругацк", "Fallout", "Day R", "Persona", "Dungeons", "D&D", "Skyrim"]

var fails: int = 0
var checks: int = 0


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("FAIL: ", what)
	else:
		print("ok: ", what)


func frames(n: int) -> void:
	for i in n:
		await process_frame


func npc(city: Node, id: String) -> Dictionary:
	for n in city.npcs:
		if String(n["def"]["id"]) == id:
			return n
	return {}


func shot(name_: String) -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		await frames(3)
		root.get_viewport().get_texture().get_image().save_png(args[0].path_join(name_))


func _initialize() -> void:
	_run()


func _run() -> void:
	await frames(2)
	var W: Node = root.get_node_or_null("Worlds")
	ok(W != null, "автозагрузка Worlds")
	W.chronicle = []
	W.codex = {}
	# Вхід у місто записується в хроніку героя один раз
	var city: Node2D = load("res://city/city_world.tscn").instantiate()
	root.add_child(city)
	var hero := Actor.new("hero", "Герой", false, 7)
	var bag: Dictionary = Trade.new_bag(60)
	var quests: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/cities/s001.json"))["growth"]["quests"]
	var done: Array = []
	for id in quests:
		for q in quests[id]:
			done.append(q["id"])
	city.enter("s001", hero, {"inventory": bag, "gate": "south", "state": {"city_id": "s001", "growth": {"done": done, "taken": {}}, "left": true}})
	city.clock.paused = true
	await frames(4)
	ok(W.chronicle.size() == 1 and String(W.chronicle[0]["kind"]) == "city" and String(W.chronicle[0]["text"]).contains("Впервые вошёл"), "хроника: первый вход в город записан")
	# Историй у олдермена две, они открываются по одной и идут в кодекс
	var eld: Dictionary = npc(city, "posadnik")
	ok(not eld.is_empty() and city._tales_of(eld).size() == 2, "олдермен знает две истории")
	city.talk(eld)
	await shot("a01_talk_with_tale_option.png")
	city.hear_tale(eld)
	await shot("a02_tale_old_5.png")
	ok(W.codex.has("old_5") and not W.codex.has("old_8") and city._tales_of(eld).size() == 1, "первый расспрос: «Что было до нас» в кодексе")
	city.hear_tale(eld)
	ok(W.codex.has("old_8") and city._tales_of(eld).is_empty(), "второй расспрос: «Три империи», больше нечего")
	ok(Codex.progress(W.codex)["found"] == 2 and W.chronicle.size() == 3 and String(W.chronicle[2]["kind"]) == "talk", "кодекс 2/25, хроника записала разговоры")
	# Трактирщик продаёт историю за кружку
	var inn: Dictionary = npc(city, "innkeeper")
	bag["money"] = 1
	city.hear_tale(inn)
	ok(not W.codex.has("old_11") and int(bag["money"]) == 1, "без монет история не рассказывается")
	bag["money"] = 10
	city.hear_tale(inn)
	ok(W.codex.has("old_11") and int(bag["money"]) == 7, "за 3 монеты трактирщик рассказывает «Год за кружкой»")
	# Развилки поручений: цена совести от потери награды до смерти
	var Fk := load("res://world/forks.gd")
	ok(Fk.of("elder_1").has("principled") and Fk.of("nope").is_empty() and Fk.data()["forks"].size() == 5, "развилки: 5 поручений с выбором")
	var qs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/cities/s001.json"))["growth"]["quests"]
	var quest := func(qid: String) -> Dictionary:
		for g in qs:
			for q in qs[g]:
				if q["id"] == qid:
					return q
		return {}
	var e1: Dictionary = quest.call("elder_1")
	bag["items"]["scrap"] = 2
	bag["money"] = 0
	city.growth["taken"] = {"elder_1": {"km": 0.0, "wins": 0}}
	city.turn_in(eld, e1)
	await shot("a03_fork_panel.png")
	ok(city._panel_title.text.contains("Скобы") and bag["items"].get("scrap", 0) == 2, "развилка: перед выбором ничего не списано")
	city.turn_in(eld, e1, "principled")
	ok(int(bag["money"]) == 0 and not bag["items"].has("scrap") and not city.growth["taken"].has("elder_1"), "по совести: награды нет, поручение сдано")
	var h1: Dictionary = quest.call("healer_2")
	bag["money"] = 100
	city.growth["taken"] = {"healer_2": {"km": 0.0, "wins": 0}}
	city.test_wins = 5
	city.turn_in(npc(city, "healer"), h1, "principled")
	ok(int(bag["money"]) == 100 + int(h1["reward"]) - 15, "штраф 15 монет при награде")
	var t3: Dictionary = quest.call("tanner_3")
	bag["money"] = 100
	city.growth["taken"]["tanner_3"] = {"km": 0.0, "wins": 0}
	city.turn_in(npc(city, "tanner"), t3, "complicit")
	ok(int(bag["money"]) == 100 - 25 + 10, "молчание: плата 25, 10 монет за молчание")
	var s2: Dictionary = quest.call("smith_2")
	var farmer: Dictionary = npc(city, "farmer")
	city.growth["taken"]["smith_2"] = {"km": 0.0, "wins": 0}
	city.turn_in(npc(city, "smith"), s2, "principled")
	ok(not farmer["actor"].alive, "отпустить пленника: гибнет огородник")
	var g3: Dictionary = quest.call("guard_3")
	var risk: Dictionary = Fk.of("guard_3")
	city._rng.seed = 1
	var outcome: Array = city._fork_apply(risk, "principled")
	ok(outcome.size() == 2 and (not hero.alive or hero.has_condition("broken_arm")), "отказ при страже: смерть или травма")
	# Спящий молчит
	var wd: Dictionary = npc(city, "widow")
	wd["actor"].sleeping = true
	ok(city._tales_of(wd).is_empty(), "спящий не рассказывает")
	# Смерть героя стирает хронику, кодекс остаётся (знание о мире)
	HeroDeath.forget_hero(W)
	ok(W.chronicle.is_empty() and W.codex.has("old_5"), "новый герой: хроника пуста, кодекс мира цел")
	# Чужих названий в данных игры нет
	var bad: Array = []
	for f in ["res://data/lore/notes.json", "res://data/cities/s001.json", "res://tutorial/tutorial.gd", "res://characters/chronicle.gd"]:
		var t: String = FileAccess.get_file_as_string(f)
		for w in FORBIDDEN:
			if t.contains(w):
				bad.append("%s: %s" % [f, w])
	ok(bad.is_empty(), "в данных и справке нет названий чужих игр и книг %s" % [bad])
	print("arkanar_checks: %d/%d ok" % [checks - fails, checks])
	quit(1 if fails > 0 else 0)

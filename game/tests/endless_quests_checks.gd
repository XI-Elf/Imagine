extends SceneTree
## Бесконечные поручения после «Эшвика» (city/endless_quests.gd, вопрос Q14): город вырос до конца —
## каждый из шести НПС раз за разом даёт новое поручение, награда платится, очки роста не растут, сохранение помнит взятое.
## godot --path game --headless -s res://tests/endless_quests_checks.gd

const Trade := preload("res://city/trade.gd")
const Growth := preload("res://city/city_growth.gd")
const Endless := preload("res://city/endless_quests.gd")
const QUEST_NPCS: Array = ["posadnik", "healer", "tanner", "smith", "trader", "guard_1"]

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


func _initialize() -> void:
	_run()


func npc(city: Node, id: String) -> Dictionary:
	for n in city.npcs:
		if String(n["def"]["id"]) == id:
			return n
	return {}


func do_quest(city: Node, n: Dictionary, q: Dictionary) -> void:
	city.take_quest(n, q)
	match String(q["kind"]):
		"walk":
			city.hero.distance_m += float(q["km"]) * 1000.0 + 1.0
		"win":
			city.test_wins += int(q["wins"])
		"bring":
			Trade.add(city.bag, String(q["item"]), int(q["n"]))
		"pay":
			city.bag["money"] = int(city.bag["money"]) + int(q["money"])
	city.turn_in(n, q)


func _run() -> void:
	var city: Node2D = load("res://city/city_world.tscn").instantiate()
	root.add_child(city)
	var hero := Actor.new("hero", "Герой", false, 11)
	var bag: Dictionary = Trade.new_bag(20)
	city.enter("s001", hero, {"inventory": bag, "gate": "south"})
	city.clock.paused = true
	await frames(3)

	# До последнего этапа бесконечных поручений нет
	for id in QUEST_NPCS:
		for q in Growth.available(city.full_def, city.growth, id):
			ok(not Endless.is_endless(q), "до Эшвика у %s нет бесконечных: %s" % [id, q["id"]])
	ok(not Endless.open_for(city.full_def, 3, "posadnik") and Endless.open_for(city.full_def, 4, "posadnik"), "открываются только на последнем этапе")
	ok(not Endless.open_for(city.full_def, 4, "priest"), "у жителей без цепочки их нет")

	# Город растёт до конца только основными поручениями
	for pass_i in 10:
		for n in city.npcs.duplicate():
			var cq: Dictionary = Growth.current(city.full_def, city.growth, String(n["def"]["id"]))
			if not cq.is_empty() and not Endless.is_endless(cq):
				do_quest(city, npc(city, String(n["def"]["id"])), cq)
	ok(city.stage == 4, "город вырос до Эшвика")
	ok(Growth.points(city.growth) == 18 and Growth.endless_done(city.growth) == 0, "18 очков, бесконечных не сдано")

	# У каждого из шести — бесконечное поручение; запасные цепочки остаются рядом
	for id in QUEST_NPCS:
		var qs: Array = Growth.available(city.full_def, city.growth, id)
		var e: Array = qs.filter(func(q): return Endless.is_endless(q))
		ok(e.size() == 1 and e[0]["id"] == "%s~e1" % id, "у %s одно бесконечное №1: %s" % [id, qs.map(func(q): return q["id"])])
		ok(Growth.waiting(city.full_def, city.growth, id), "у %s поручения не кончаются" % id)
	var tr_qs: Array = Growth.available(city.full_def, city.growth, "trader")
	ok(tr_qs.any(func(q): return q["id"] == "trader_s"), "несданное запасное торговки по-прежнему доступно")
	ok(Endless.is_endless(Growth.current(city.full_def, city.growth, "posadnik")), "current после цепочки — бесконечное (меню города видит его)")

	# Одно и то же поручение при каждом вызове, пока не сдано
	var a: Dictionary = Endless.make("s001", "smith", 5)
	ok(a == Endless.make("s001", "smith", 5), "поручение №5 кузнеца одинаково при каждом вызове")

	# Тексты идут кругами: тот же текст два раза подряд не выпадает; числа согласованы со словами
	var repeats: Array = []
	for id in QUEST_NPCS:
		var prev: String = ""
		for i in range(1, 60):
			var t: String = Endless.make("s001", id, i)["title"]
			if t == prev:
				repeats.append("%s №%d" % [id, i])
			prev = t
	ok(repeats.is_empty(), "подряд одно и то же не повторяется: %s" % [repeats])
	ok(Endless._count(1, "old_coin") == "1 довоенную монету" and Endless._count(3, "scrap") == "3 куска металлолома" and Endless._count(5, "km") == "5 километров" and Endless._count(21, "km") == "21 километр" and Endless._count(12, "vegetables") == "12 пучков овощей", "формы слов: 1 монету, 3 куска, 5 километров")

	# Текст: награда без «город вырастет», число подставлено
	var pq: Dictionary = Growth.current(city.full_def, city.growth, "posadnik")
	ok(not city._quest_reward(pq).contains("вырастет") and city._quest_reward(pq).contains("%d" % int(pq["reward"])), "в предложении — только награда: %s" % city._quest_reward(pq))
	ok(not String(pq["ask"]).contains("%"), "в тексте нет пропусков: %s" % pq["ask"])

	# Взять, сохранить, загрузить: взятое помнится
	city.take_quest(npc(city, "posadnik"), pq)
	var st: Dictionary = city.to_dict()
	var city2: Node2D = load("res://city/city_world.tscn").instantiate()
	root.add_child(city2)
	city2.enter("s001", hero, {"inventory": bag, "state": st})
	city2.clock.paused = true
	await frames(2)
	var pq2: Dictionary = Growth.current(city2.full_def, city2.growth, "posadnik")
	ok(city2.stage == 4 and pq2 == pq and Growth.taken(city2.growth, pq2), "после загрузки взятое бесконечное на месте")
	city2.queue_free()

	# Сдать: награда, следующее — новое; очки роста и этап не меняются
	var m0: int = int(bag["money"])
	do_quest(city, npc(city, "posadnik"), pq)
	ok(int(bag["money"]) == m0 + int(pq["reward"]) + (int(pq.get("money", 0))), "награда выдана: +%d" % int(pq["reward"]))
	var nq: Dictionary = Growth.current(city.full_def, city.growth, "posadnik")
	ok(nq["id"] == "posadnik~e2" and not Growth.taken(city.growth, nq), "следующее поручение — №2, ещё не взято")
	ok(Growth.points(city.growth) == 18 and city.stage == 4 and Growth.endless_done(city.growth) == 1, "очков роста по-прежнему 18, этап тот же")

	# Тридцать поручений у каждого: все сдаются, объёмы растут с потолком, вещи только добываемые
	var kinds: Dictionary = {}
	var items: Dictionary = {}
	var by_npc: Dictionary = {}
	var bad: Array = []
	var max_km: int = 0
	var max_n: int = 0
	var max_w: int = 0
	for id in QUEST_NPCS:
		for i in 30:
			var q: Dictionary = Growth.current(city.full_def, city.growth, id)
			if q.is_empty() or not Endless.is_endless(q):
				bad.append("%s пусто" % id)
				break
			kinds[q["kind"]] = true
			if q["kind"] == "bring":
				items[q["item"]] = true
				if not by_npc.has(id):
					by_npc[id] = {}
				by_npc[id][q["item"]] = true
				if not String(q["ask"]).contains(Endless._count(int(q["n"]), String(q["item"]))):
					bad.append("%s текст не про %s" % [q["id"], q["item"]])
			if q["kind"] == "bring" and not Endless.PRICE.has(String(q["item"])):
				bad.append("%s %s" % [q["id"], q["item"]])
			if int(q.get("reward", 0)) <= 0:
				bad.append("%s без награды" % q["id"])
			max_km = maxi(max_km, int(q.get("km", 0)))
			max_n = maxi(max_n, int(q.get("n", 0)))
			max_w = maxi(max_w, int(q.get("wins", 0)))
			var was: int = Growth.endless_done(city.growth)
			do_quest(city, npc(city, id), q)
			if Growth.endless_done(city.growth) != was + 1:
				bad.append("%s не сдалось" % q["id"])
	ok(bad.is_empty(), "180 поручений сданы: %s" % [bad])
	ok(kinds.has("walk") and kinds.has("win") and kinds.has("bring") and not kinds.has("pay"), "виды: пройти, победить, принести (без «заплатить»): %s" % [kinds.keys()])
	ok(items.size() == Endless.PRICE.size(), "приносить просят лом, монеты, овощи и шкуры: %s" % [items.keys()])
	ok(by_npc.get("tanner", {}).keys() == ["hide"] and by_npc.get("smith", {}).keys() == ["scrap"], "Q33: кожевник просит только шкуры, кузнец только лом: %s" % [by_npc])
	ok(max_km <= 8 and max_n <= 6 and max_w <= 2, "потолок объёма: до %d км, %d шт., %d побед" % [max_km, max_n, max_w])
	ok(Growth.points(city.growth) == 18 and Growth.stage(city.full_def, city.growth) == 4, "после 181 бесконечного очков 18, этап «Крупный город»")

	# Доска объявлений перечисляет и бесконечные
	var board: Dictionary = {}
	for p in city.def["places"]:
		if p["id"] == "notice_board":
			board = p
	var bt: String = city._board_text(board)
	var e_title: String = Growth.current(city.full_def, city.growth, "guard_1")["title"]
	ok(bt.contains(e_title), "на доске есть бесконечное поручение стражника «%s»" % e_title)

	city.queue_free()
	print("endless_quests_checks: %d/%d" % [checks - fails, checks])
	quit(1 if fails > 0 else 0)

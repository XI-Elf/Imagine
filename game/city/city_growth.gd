extends RefCounted
## Ріст міста (Huzzah 2026-10-23): початкове місто майже порожнє — халупа героя й по дому на шість НПС;
## місто всередині стіни росте, коли герой здає завдання цих НПС. Дані — розділ "growth" опису міста
## (tools/make_city_growth.py): етапи (що з'являється, скільки очок потрібно) і ланцюжки завдань.
## Стан росту — {done: [id зданих], taken: {id: {на старті: km, wins}}} — зберігає місто (city_world.gd, to_dict).
## view(def, етап) — опис міста на цьому етапі: його будує city_map.gd і малює мініатюра на загальній карті.

const KINDS: Array = ["walk", "win", "bring", "pay"]
const Endless := preload("res://city/endless_quests.gd")


static func has_growth(def: Dictionary) -> bool:
	return def.get("growth", {}).has("stages")


static func new_state() -> Dictionary:
	return {"done": [], "taken": {}}


## Очки росту — здані доручення ланцюжків; нескінченні (після останнього етапу) не рахуються
static func points(g: Dictionary) -> int:
	var k: int = 0
	for id in g.get("done", []):
		if not String(id).contains(Endless.MARK):
			k += 1
	return k


## Скільки нескінченних доручень здано всього (для дошки й меню міста)
static func endless_done(g: Dictionary) -> int:
	return g.get("done", []).size() - points(g)


## Номер етапу: останній, чиї очки набрано
static func stage(def: Dictionary, g: Dictionary) -> int:
	if not has_growth(def):
		return 0
	var st: int = 0
	var p: int = points(g)
	var stages: Array = def["growth"]["stages"]
	for i in stages.size():
		if p >= int(stages[i].get("points", 0)):
			st = i
	return st


static func stage_name(def: Dictionary, st: int) -> String:
	var stages: Array = def.get("growth", {}).get("stages", [])
	return String(stages[st]["name"]) if st >= 0 and st < stages.size() else ""


## Очок до наступного етапу (-1 — місто виросло до кінця)
static func next_points(def: Dictionary, st: int) -> int:
	var stages: Array = def.get("growth", {}).get("stages", [])
	return int(stages[st + 1]["points"]) if st + 1 < stages.size() else -1


## Опис міста на етапі st: без будинків, мешканців, місць і яток пізніх етапів;
## назви будинків, поля мешканців і стіна — за етапами 0..st
static func view(def: Dictionary, st: int) -> Dictionary:
	if not has_growth(def):
		return def
	var stages: Array = def["growth"]["stages"]
	var later_b: Dictionary = {}
	var later_n: Dictionary = {}
	var later_p: Dictionary = {}
	var later_props: Dictionary = {}
	for i in range(st + 1, stages.size()):
		for id in stages[i].get("buildings", []):
			later_b[id] = true
		for id in stages[i].get("npcs", []):
			later_n[id] = true
		for id in stages[i].get("places", []):
			later_p[id] = true
		for k in stages[i].get("props", []):
			later_props[int(k)] = true
	var names: Dictionary = {}
	var npc_set: Dictionary = {}
	var wall: String = String(def.get("wall", "palisade"))
	for i in mini(st + 1, stages.size()):
		names.merge(stages[i].get("names", {}), true)
		for id in stages[i].get("npc_set", {}):
			if not npc_set.has(id):
				npc_set[id] = {}
			npc_set[id].merge(stages[i]["npc_set"][id], true)
		wall = String(stages[i].get("wall", wall))
	var out: Dictionary = {}
	for k in def:
		if k != "growth":
			out[k] = def[k]
	out["growth"] = def["growth"]
	out["stage"] = st
	out["wall"] = wall
	var blds: Array = []
	for b in def.get("buildings", []):
		if later_b.has(b["id"]):
			continue
		if names.has(b["id"]):
			b = b.duplicate()
			b["name"] = names[b["id"]]
		blds.append(b)
	out["buildings"] = blds
	var npcs: Array = []
	for n in def.get("npcs", []):
		if later_n.has(n["id"]):
			continue
		if npc_set.has(n["id"]):
			n = n.duplicate()
			n.merge(npc_set[n["id"]], true)
			# null у npc_set — прибрати поле (наприклад, місце роботи на площі після переїзду)
			for k in n.keys():
				if n[k] == null:
					n.erase(k)
		npcs.append(n)
	out["npcs"] = npcs
	out["places"] = def.get("places", []).filter(func(p): return not later_p.has(p["id"]))
	var props: Array = []
	for i in def.get("props", []).size():
		if not later_props.has(i):
			props.append(def["props"][i])
	out["props"] = props
	return out


# =====================================================================
# ЗАВДАННЯ
# =====================================================================
static func chain(def: Dictionary, npc_id: String) -> Array:
	return def.get("growth", {}).get("quests", {}).get(npc_id, [])


## Завдання основного ланцюжка, яким НПС зараз зайнятий із героєм: перше нездане, якщо етап його вже відкрив;
## ланцюжок пройдено й місто виросло до кінця — нескінченне доручення (endless_quests.gd, питання Q14)
static func current(def: Dictionary, g: Dictionary, npc_id: String) -> Dictionary:
	var st: int = stage(def, g)
	for q in chain(def, npc_id):
		if q.get("spare", false) or g["done"].has(q["id"]):
			continue
		return q if int(q.get("stage", 0)) <= st else {}
	return Endless.next_for(def, g, npc_id) if Endless.open_for(def, st, npc_id) else {}


## Усі доручення НПС, які можна взяти або здати зараз: поточне основного ланцюжка й відкриті запасні
## (spare — питання Q03: запасні беруться в будь-якому порядку, щоб одне непосильне доручення не тримало ріст)
static func available(def: Dictionary, g: Dictionary, npc_id: String) -> Array:
	var out: Array = []
	var q: Dictionary = current(def, g, npc_id)
	if not q.is_empty():
		out.append(q)
	var st: int = stage(def, g)
	for s in chain(def, npc_id):
		if s.get("spare", false) and not g["done"].has(s["id"]) and int(s.get("stage", 0)) <= st:
			out.append(s)
	# Місто виросло: нескінченне доручення поруч із недоробленими з ланцюжка
	if Endless.open_for(def, st, npc_id) and not Endless.is_endless(q):
		out.append(Endless.next_for(def, g, npc_id))
	return out


## Чи є в НПС наступні завдання, що відкриються пізніше (для репліки «місто має підрости»)
static func waiting(def: Dictionary, g: Dictionary, npc_id: String) -> bool:
	if Endless.open_for(def, stage(def, g), npc_id):
		return true
	for q in chain(def, npc_id):
		if not g["done"].has(q["id"]):
			return true
	return false


static func taken(g: Dictionary, q: Dictionary) -> bool:
	return g["taken"].has(q["id"])


## Узяти завдання: запам'ятати, скільки пройдено й виграно на старті (km, wins — лічильники героя)
static func take(g: Dictionary, q: Dictionary, km: float, wins: int) -> void:
	g["taken"][q["id"]] = {"km": km, "wins": wins}


## Поступ: [є, треба]. bag — сумка героя (Trade), km і wins — поточні лічильники
static func progress(g: Dictionary, q: Dictionary, bag: Dictionary, km: float, wins: int) -> Array:
	var t: Dictionary = g["taken"].get(q["id"], {"km": km, "wins": wins})
	match String(q["kind"]):
		"walk":
			return [floorf((km - float(t["km"])) * 10.0) / 10.0, float(q["km"])]
		"win":
			return [wins - int(t["wins"]), int(q["wins"])]
		"bring":
			return [int(bag.get("items", {}).get(String(q["item"]), 0)), int(q["n"])]
		"pay":
			return [int(bag.get("money", 0)), int(q["money"])]
	# Вид не з KINDS: таке доручення ніколи не здати — описка в даних (tools/make_city_growth.py)
	push_warning("city_growth: поручение %s неизвестного вида «%s» (бывают %s)" % [q.get("id", "?"), q.get("kind", ""), KINDS])
	return [0, 1]


static func ready(g: Dictionary, q: Dictionary, bag: Dictionary, km: float, wins: int) -> bool:
	var p: Array = progress(g, q, bag, km, wins)
	return taken(g, q) and float(p[0]) >= float(p[1])


## Здати: забрати речі чи гроші, видати нагороду, записати очко росту. Повертає етап після здачі
static func complete(def: Dictionary, g: Dictionary, q: Dictionary, bag: Dictionary) -> int:
	match String(q["kind"]):
		"bring":
			var id: String = String(q["item"])
			var left: int = int(bag["items"].get(id, 0)) - int(q["n"])
			if left > 0:
				bag["items"][id] = left
			else:
				bag["items"].erase(id)
		"pay":
			bag["money"] = int(bag["money"]) - int(q["money"])
	bag["money"] = int(bag["money"]) + int(q.get("reward", 0))
	g["taken"].erase(q["id"])
	if not g["done"].has(q["id"]):
		g["done"].append(q["id"])
	return stage(def, g)

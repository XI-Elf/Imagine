extends RefCounted
## Рост города (Huzzah 2026-10-23): начальный город почти пуст — лачуга героя и по дому на шесть НПС;
## город внутри стены растёт, когда герой сдаёт задания этих НПС. Данные — раздел "growth" описания города
## (tools/make_city_growth.py): этапы (что появляется, сколько очков нужно) и цепочки заданий.
## Состояние роста — {done: [id сданных], taken: {id: {на старте: km, wins}}} — хранит город (city_world.gd, to_dict).
## view(def, этап) — описание города на этом этапе: его строит city_map.gd и рисует миниатюра на общей карте.

const KINDS: Array = ["walk", "win", "bring", "pay"]


static func has_growth(def: Dictionary) -> bool:
	return def.get("growth", {}).has("stages")


static func new_state() -> Dictionary:
	return {"done": [], "taken": {}}


static func points(g: Dictionary) -> int:
	return g.get("done", []).size()


## Номер этапа: последний, чьи очки набраны
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


## Очков до следующего этапа (-1 — город вырос до конца)
static func next_points(def: Dictionary, st: int) -> int:
	var stages: Array = def.get("growth", {}).get("stages", [])
	return int(stages[st + 1]["points"]) if st + 1 < stages.size() else -1


## Описание города на этапе st: без домов, жителей, мест и лотков поздних этапов;
## имена домов, поля жителей и стена — по этапам 0..st
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
			# null в npc_set — убрать поле (например, место работы на площади после переезда)
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
# ЗАДАНИЯ
# =====================================================================
static func chain(def: Dictionary, npc_id: String) -> Array:
	return def.get("growth", {}).get("quests", {}).get(npc_id, [])


## Задание, которым НПС сейчас занят с героем: первое несданное в его цепочке, если этап его уже открыл
static func current(def: Dictionary, g: Dictionary, npc_id: String) -> Dictionary:
	var st: int = stage(def, g)
	for q in chain(def, npc_id):
		if g["done"].has(q["id"]):
			continue
		return q if int(q.get("stage", 0)) <= st else {}
	return {}


## Есть ли у НПС следующие задания, которые откроются позже (для реплики «город должен подрасти»)
static func waiting(def: Dictionary, g: Dictionary, npc_id: String) -> bool:
	for q in chain(def, npc_id):
		if not g["done"].has(q["id"]):
			return true
	return false


static func taken(g: Dictionary, q: Dictionary) -> bool:
	return g["taken"].has(q["id"])


## Взять задание: запомнить, сколько пройдено и выиграно на старте (km, wins — счётчики героя)
static func take(g: Dictionary, q: Dictionary, km: float, wins: int) -> void:
	g["taken"][q["id"]] = {"km": km, "wins": wins}


## Прогресс: [есть, нужно]. bag — сумка героя (Trade), km и wins — текущие счётчики
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
	return [0, 1]


static func ready(g: Dictionary, q: Dictionary, bag: Dictionary, km: float, wins: int) -> bool:
	var p: Array = progress(g, q, bag, km, wins)
	return taken(g, q) and float(p[0]) >= float(p[1])


## Сдать: забрать вещи или деньги, выдать награду, записать очко роста. Возвращает этап после сдачи
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

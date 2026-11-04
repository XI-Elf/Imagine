extends RefCounted
## Общая хронология мира между игровыми сессиями (п.16 правок Huzzah 2026-11-03).
## 1) Каждая новая игра продолжает мировую дату с того дня, на котором закончилась предыдущая партия.
## 2) Герой, которого игрок бросил, не дожив до смерти (новая игра при живом прежнем герое), передаётся ИИ и становится
##    враждебным НПС: при случайных нападениях в дороге он может выйти навстречу новому герою (Worlds._on_hero_km).
## Состояние лежит в user://chronology.cfg (не в слотах сохранения, поэтому переживает «Новую игру»):
##   date_s — секунды мира на последнем сохранении; last_hero — Actor.to_dict живого героя последнего сохранения (пусто, если погиб);
##   abandoned — список Actor.to_dict брошенных героев.

const MAX_ABANDONED: int = 6
const MEET_CHANCE: float = 0.35
static var path: String = "user://chronology.cfg"


static func _read() -> Dictionary:
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		return {"date_s": -1.0, "last_hero": {}, "abandoned": []}
	return {"date_s": float(cf.get_value("world", "date_s", -1.0)), "last_hero": cf.get_value("world", "last_hero", {}),
		"abandoned": cf.get_value("world", "abandoned", [])}


static func _write(d: Dictionary) -> void:
	var cf := ConfigFile.new()
	cf.set_value("world", "date_s", float(d.get("date_s", -1.0)))
	cf.set_value("world", "last_hero", d.get("last_hero", {}))
	cf.set_value("world", "abandoned", d.get("abandoned", []))
	cf.save(path)


static func state() -> Dictionary:
	return _read()


static func clear() -> void:
	_write({"date_s": -1.0, "last_hero": {}, "abandoned": []})


## Запомнить, где остановилась партия: мировая дата и живой герой (вызывается при каждом сохранении мира)
static func record(clock_s: float, hero: Actor) -> void:
	var d: Dictionary = _read()
	d["date_s"] = clock_s
	d["last_hero"] = hero.to_dict() if hero != null and hero.alive else {}
	_write(d)


## Герой погиб: бросать некого, он уходит в некролог, а не во враги
static func hero_died(clock_s: float) -> void:
	var d: Dictionary = _read()
	d["date_s"] = maxf(float(d.get("date_s", -1.0)), clock_s)
	d["last_hero"] = {}
	_write(d)


## Новая партия: вернуть дату, с которой продолжить мировой отсчёт (−1 — начинать как обычно), и сдать брошенного героя ИИ
static func begin_session(start_s: float) -> float:
	var d: Dictionary = _read()
	var date: float = float(d.get("date_s", -1.0))
	var lh: Variant = d.get("last_hero", {})
	if lh is Dictionary and not (lh as Dictionary).is_empty():
		var list: Array = d.get("abandoned", [])
		list.append(lh)
		while list.size() > MAX_ABANDONED:
			list.remove_at(0)
		d["abandoned"] = list
	d["last_hero"] = {}
	_write(d)
	return date if date > start_s else -1.0


static func abandoned_count() -> int:
	return (_read().get("abandoned", []) as Array).size()


## Брошенный герой выходит навстречу: с шансом MEET_CHANCE достаётся один (и пропадает из списка), иначе null
static func meet(rng: RandomNumberGenerator) -> Actor:
	var d: Dictionary = _read()
	var list: Array = d.get("abandoned", [])
	if list.is_empty() or rng.randf() >= MEET_CHANCE:
		return null
	var i: int = rng.randi() % list.size()
	var a: Actor = Actor.from_dict(list[i])
	list.remove_at(i)
	d["abandoned"] = list
	_write(d)
	if a != null:
		a.is_npc = true
		a.res["health"] = a.max_of("health")
	return a

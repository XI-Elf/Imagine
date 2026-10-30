extends SceneTree
## Чистка коду 2D 07: перевірки виправлень (годинник після бою, збереження, завантаження бою) і зв'язків даних між модулями
## (предмети, істоти, ефекти, доручення росту, перевірка цілісності в заставці).
## godot --headless --path game -s res://tests/code_audit_checks.gd

const WorldSave := preload("res://world_save.gd")
const Combatant := preload("res://battle/combatant.gd")
const Data := preload("res://battle/battle_data.gd")
const Enc := preload("res://battle/encounters.gd")
const Trade := preload("res://city/trade.gd")
const Growth := preload("res://city/city_growth.gd")
const Intro := preload("res://intro.gd")

var fails: int = 0
var checks: int = 0


class FakePhysics:
	extends RefCounted
	var weather_speed: float = 1.0
	var preload_state: PackedByteArray = PackedByteArray()


class FakeGame:
	extends Node
	var clock: GameClock
	var physics: FakePhysics = FakePhysics.new()


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("FAIL: ", what)


func _initialize() -> void:
	_clock()
	_save()
	_combatant()
	_battle_data()
	_city_data()
	_intro_lists()
	_terrain()
	print("code_audit_checks: %d/%d | FAIL %d" % [checks - fails, checks, fails])
	quit(1 if fails > 0 else 0)


# Бій додає хвилини через GameClock.skip: зміна сезону й року не губиться (раніше _sync_last ковтав сигнали)
func _clock() -> void:
	var c := GameClock.new()
	c.reset()
	var seasons: Array = []
	var years: Array = []
	c.season_changed.connect(func(s: int) -> void: seasons.append(s))
	c.year_changed.connect(func(y: int) -> void: years.append(y))
	# 30 листопада 23:00 внутрішнього року → після 2 годин уже зима
	c.total_seconds = 333.0 * GameClock.SECONDS_PER_DAY + 23.0 * 3600.0
	c._sync_last()
	c.skip(2.0 * 3600.0)
	ok(seasons == [0], "skip через границу сезона даёт season_changed(зима): %s" % [seasons])
	var y0: int = c.year()
	c.skip(GameClock.SECONDS_PER_DAY * GameClock.DAYS_PER_YEAR)
	ok(years.size() == 1 and int(years[0]) == y0 + 1, "skip на год даёт year_changed")
	var t: float = c.total_seconds
	c.skip(-5.0)
	ok(c.total_seconds == t, "skip назад ничего не делает")
	c.free()


func _save() -> void:
	var g := FakeGame.new()
	g.clock = GameClock.new()
	g.clock.reset()
	WorldSave.apply_early(g, {"clock_total": g.clock.total_seconds, "clock_speed": 99, "atmosphere": "мусор"})
	ok(g.clock.speed_index == GameClock.SPEEDS.size() - 1, "скорость часов из сохранения в пределах SPEEDS")
	ok(g.physics.preload_state.is_empty(), "атмосфера не того типа не ломает загрузку")
	WorldSave.apply_early(g, {"clock_speed": -3})
	ok(g.clock.speed_index == 0, "отрицательная скорость → 0")
	g.clock.free()
	g.free()
	ok(WorldSave.read("__нет_такой_ячейки__").is_empty(), "чтение несуществующей ячейки — пусто, без падения")
	# Файл іншої версії не читається
	DirAccess.make_dir_recursive_absolute(WorldSave.DIR)
	var slot: String = "__audit_old"
	var f := FileAccess.open(WorldSave.path_of(slot), FileAccess.WRITE)
	f.store_var({"header": true, "version": 1, "unix": 0}, false)
	f.store_var({"version": 1}, false)
	f.close()
	ok(WorldSave.read(slot).is_empty(), "сохранение старой версии не читается")
	ok(not WorldSave.list().any(func(h): return h["slot"] == slot), "и не показывается в списке")
	WorldSave.delete(slot)
	ok(not FileAccess.file_exists(WorldSave.path_of(slot)), "удаление ячейки")


# Збережений бій з ефектом, якого більше немає в data/battle/effects: не падає й не псує сусідні
func _combatant() -> void:
	var c := Combatant.new()
	c.actor = Actor.new("t", "Проверочный", true, 1)
	c.load_dict({"effects": [{"id": "__нет_эффекта", "left": 9}, {"id": "prone", "left": 2}, {"id": "stunned", "left": 1}]})
	ok(c.effects.size() == 2, "пропал только неизвестный эффект")
	ok(c.has_effect("prone") and int(c.effects[0]["left"]) == 2, "у «prone» осталось 2 раунда")
	c.actor.res["health"] = 50.0
	c.max_hp = 10
	c._from_actor_health(Data.config())
	ok(c.hp >= 1 and c.hp <= 10, "HP по здоровью в пределах")


# Зв'язки ресурсів бою: істоти → зброя/броня/здібності, здібності → ефекти, конфіг → зброя/стани
func _battle_data() -> void:
	var cfg: BattleConfig = Data.config()
	var weapons: PackedStringArray = Data.list("weapons")
	var effects: PackedStringArray = Data.list("effects")
	for id in Data.list("creatures"):
		var cr: BattleCreature = Data.creature(id)
		ok(cr != null and cr.id == id, "существо %s читается, id совпадает с файлом" % id)
		if cr == null:
			continue
		for w in cr.weapons:
			ok(weapons.has(w), "%s: есть оружие %s" % [id, w])
		ok(cr.armor == "" or Data.armor(cr.armor) != null, "%s: есть броня %s" % [id, cr.armor])
		for ab in cr.abilities:
			ok(Data.ability(ab) != null, "%s: есть способность %s" % [id, ab])
	for id in Data.list("abilities"):
		var ab: BattleAbility = Data.ability(id)
		ok(ab != null and (ab.apply_effect == "" or effects.has(ab.apply_effect)), "способность %s: эффект %s есть" % [id, ab.apply_effect if ab != null else "?"])
	for item in cfg.item_weapons:
		ok(weapons.has(String(cfg.item_weapons[item])), "item_weapons: %s → оружие %s есть" % [item, cfg.item_weapons[item]])
	for cond in cfg.pack_effects:
		ok(effects.has(String(cfg.pack_effects[cond])), "pack_effects: %s → эффект %s есть" % [cond, cfg.pack_effects[cond]])
		ok(not _cond(cond).is_empty(), "pack_effects: состояние пака %s есть в conditions.json" % cond)
	for zone in cfg.trauma_table:
		for dt in cfg.trauma_table[zone]:
			var cond: String = cfg.trauma_table[zone][dt]
			ok(not _cond(cond).is_empty(), "trauma_table %s/%s: состояние %s есть" % [zone, dt, cond])
	for g in Enc.GROUPS:
		for m in Enc.GROUPS[g]:
			ok(Data.creature(String(m[0])) != null, "группа %s: шаблон %s есть" % [g, m[0]])
	for t in Enc.BY_TERRAIN:
		for g in Enc.BY_TERRAIN[t]:
			ok(Enc.GROUPS.has(g), "местность %s: группа %s есть" % [t, g])
	var lost: Array = Data.missing.filter(func(k): return not String(k).contains("/__"))
	ok(lost.is_empty(), "battle_data: нет пропавших ресурсов %s" % [lost])


func _cond(id: String) -> Dictionary:
	return preload("res://characters/actor_rules.gd").condition(id)


# Місто: предмети в крамницях, дорученнях і етапах росту є в items.json; будинки й мешканці етапів — в описі міста
func _city_data() -> void:
	var items: Dictionary = Trade.items()
	ok(not items.is_empty(), "items.json прочитан")
	ok(Trade.item("__нет_такого").is_empty(), "неизвестный предмет — пустая запись")
	var def: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/cities/s001.json"))
	ok(def is Dictionary, "s001.json читается")
	if not (def is Dictionary):
		return
	var bids: Dictionary = {}
	for b in def["buildings"]:
		bids[b["id"]] = true
	var nids: Dictionary = {}
	for n in def["npcs"]:
		nids[n["id"]] = true
		for it in n.get("stock", {}):
			ok(items.has(it), "житель %s продаёт известный предмет %s" % [n["id"], it])
		for it in n.get("buys", []):
			ok(items.has(it), "житель %s покупает известный предмет %s" % [n["id"], it])
	for i in def["growth"]["stages"].size():
		var st: Dictionary = def["growth"]["stages"][i]
		for b in st.get("buildings", []):
			ok(bids.has(b), "этап %d: дом %s есть" % [i, b])
		for n in st.get("npcs", []):
			ok(nids.has(n), "этап %d: житель %s есть" % [i, n])
		for n in st.get("npc_set", {}):
			ok(nids.has(n), "этап %d: npc_set для известного жителя %s" % [i, n])
			for it in st["npc_set"][n].get("stock", {}):
				ok(items.has(it), "этап %d: %s продаёт известный %s" % [i, n, it])
	var qn: int = 0
	for npc in def["growth"]["quests"]:
		ok(nids.has(npc), "поручения у известного жителя %s" % npc)
		for q in def["growth"]["quests"][npc]:
			qn += 1
			ok(Growth.KINDS.has(String(q["kind"])), "поручение %s: вид %s известен" % [q["id"], q["kind"]])
			if String(q["kind"]) == "bring":
				ok(items.has(String(q["item"])), "поручение %s: предмет %s есть" % [q["id"], q["item"]])
	var stages: Array = def["growth"]["stages"]
	ok(qn >= int(stages[-1]["points"]), "поручений (%d) хватает на последний этап (%d очков)" % [qn, int(stages[-1]["points"])])


# Заставка перевіряє файли, що є, і класи, які знає проєкт
func _intro_lists() -> void:
	for s in Intro.SCRIPTS:
		ok(ResourceLoader.exists(s[0]), "заставка: скрипт %s есть" % s[0])
	for s in Intro.SCENES:
		ok(ResourceLoader.exists(s[0]), "заставка: сцена %s есть" % s[0])
	for s in Intro.JSONS:
		ok(FileAccess.file_exists(s[0]), "заставка: файл %s есть" % s[0])
	var known: Dictionary = {}
	for c in ProjectSettings.get_global_class_list():
		known[String(c["class"])] = true
	for n in Intro.CLASSES:
		ok(known.has(n), "класс %s в кэше классов" % n)


# Ключ місцевості бою від Worlds збігається з encounters.terrain_key (одна таблиця на два модулі)
func _terrain() -> void:
	var w: Node = root.get_node_or_null("Worlds")
	ok(w != null, "автозагрузка Worlds есть")
	if w == null:
		return
	for i in w.TERRAIN_KEYS.size():
		ok(String(w.TERRAIN_KEYS[i]) == Enc.terrain_key(i), "биом %d: %s = %s" % [i, w.TERRAIN_KEYS[i], Enc.terrain_key(i)])

extends SceneTree
## Проверки боя без карты: DiceRoller, формулы (Combat_Formulas, раздел I), правила боя, сетка, ход боя.
## godot --headless --path game -s res://tests/battle_checks.gd

const Data := preload("res://battle/battle_data.gd")
const Rules := preload("res://battle/combat_rules.gd")
const Combatant := preload("res://battle/combatant.gd")
const Core := preload("res://battle/battle_core.gd")
const Grid := preload("res://battle/battle_grid.gd")
const Enc := preload("res://battle/encounters.gd")

var fails: int = 0
var checks: int = 0


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("FAIL: ", what)
	else:
		print("ok: ", what)


func _initialize() -> void:
	_dice()
	_stats()
	_formulas()
	_rules()
	_grid()
	await _battles()
	print("battle_checks: %d/%d" % [checks - fails, checks])
	quit(1 if fails > 0 else 0)


# --- DiceRoller ------------------------------------------------------------
func _dice() -> void:
	var d := DiceRoller.new(5)
	ok(DiceRoller.parse("1d20+5")["ok"] and DiceRoller.parse("2d6+3")["terms"][0]["n"] == 2 and DiceRoller.parse("8d6")["ok"], "разбор 1d20+5, 2d6+3, 8d6")
	ok(DiceRoller.parse("2d6+1d4-1")["mod"] == -1 and DiceRoller.parse("2d6+1d4-1")["terms"].size() == 2, "разбор нескольких слагаемых")
	ok(not DiceRoller.parse("2d7")["ok"] and not DiceRoller.parse("abc")["ok"], "d7 и мусор не принимаются")
	var all_ok: bool = true
	for s in [4, 6, 8, 10, 12, 20, 100]:
		for i in 300:
			var r: Dictionary = d.roll("1d%d" % s, {"silent": true})
			if int(r["total"]) < 1 or int(r["total"]) > s:
				all_ok = false
	ok(all_ok, "d4–d100 в своих пределах")
	var r: Dictionary = d.roll("8d6+2", {"silent": true})
	ok(r["dice"].size() == 8 and int(r["total"]) == r["dice"].reduce(func(a, x): return a + int(x["value"]), 0) + 2, "лог костей сходится с итогом: " + r["text"])
	var rc: Dictionary = d.roll("1d8+3", {"repeat": 2, "silent": true})
	ok(rc["dice"].size() == 2 and int(rc["mod"]) == 3, "крит: кости дважды, модификатор раз: " + rc["text"])
	d.forced = [3, 17]
	var a: Dictionary = d.d20(0, true, false, "", {"silent": true})
	ok(int(a["natural"]) == 17 and a["mode"] == "adv", "преимущество берёт большее: " + a["text"])
	d.forced = [3, 17]
	var b: Dictionary = d.d20(0, false, true, "", {"silent": true})
	ok(int(b["natural"]) == 3 and b["mode"] == "dis", "помеха берёт меньшее")
	d.forced = [12, 19]
	var c: Dictionary = d.d20(0, true, true, "", {"silent": true})
	ok(c["rolls"].size() == 1 and int(c["natural"]) == 12, "преимущество и помеха отменяются: один d20")
	d.forced = [20]
	ok(d.d20(0, false, false, "", {"silent": true})["nat20"], "натуральная 20 отмечена")
	d.forced = [1]
	ok(d.d20(0, false, false, "", {"silent": true})["nat1"], "натуральная 1 отмечена")
	var got: Array = []
	d.rolled.connect(func(e): got.append(e))
	d.roll("1d6")
	ok(got.size() == 1, "каждый бросок уходит сигналом в лог")
	ok(absf(DiceRoller.chance(5, 16) - 0.5) < 0.001, "шанс: d20+5 против 16 = 50 %")
	ok(DiceRoller.chance(5, 16, true) > 0.74 and DiceRoller.chance(5, 16, false, true) < 0.26, "шанс с преимуществом/помехой")
	ok(absf(DiceRoller.chance(30, 10) - 0.95) < 0.001 and absf(DiceRoller.chance(-30, 10) - 0.05) < 0.001, "натуральные 1 и 20 в шансе")


# --- Характеристики --------------------------------------------------------
func _stats() -> void:
	var tbl: Dictionary = {8: -1, 10: 0, 11: 0, 14: 2, 16: 3, 18: 4, 20: 5, 3: -4}
	var good: bool = true
	for k in tbl:
		if Combatant.ability_mod(k) != tbl[k]:
			good = false
	ok(good, "модификатор = floor((значение − 10) / 2)")
	ok(Combatant.prof_for_level(1) == 2 and Combatant.prof_for_level(4) == 2 and Combatant.prof_for_level(5) == 3
		and Combatant.prof_for_level(9) == 4 and Combatant.prof_for_level(13) == 5 and Combatant.prof_for_level(17) == 6
		and Combatant.prof_for_level(20) == 6, "бонус мастерства по уровням 2/3/4/5/6")
	var a := Actor.new("hero", "Герой")
	a.set_stat("agi", 10)
	a.set_stat("str", 8)
	var c = Combatant.new()
	c.build_from_actor(a, 0, Data.config(), Data.config().hero)
	ok(c.scores["dex"] == 20 and c.scores["str"] == 16 and c.scores["con"] == 10 and c.scores["lck"] == 10 and c.scores["wis"] == 10, "характеристика × 2: Ловкость 10 → DEX 20, Сила 8 → STR 16, 5 → 10")
	ok(c.max_hp == 33 and c.weapons.size() == 2 and c.armor != null and c.armor.id == "leather", "герой: HP 33 (15 + СИЛ 8 + 2×ВЫН 5), меч и праща, кожаная броня")


func mk(scores: Dictionary, armor: String = "none") -> Object:
	var c = Combatant.new()
	c.actor = Actor.new("t%d" % randi(), "Цель", true)
	c.title = "Цель"
	for k in Combatant.STATS:
		c.scores[k] = int(scores.get(k, 10))
	c.armor = Data.armor(armor)
	c.max_hp = 100
	c.hp = 100
	return c


# --- Формулы урона: символьные проверки раздела I ---------------------------
func _formulas() -> void:
	var d := DiceRoller.new(9)
	var t = mk({})
	# фиксированный урон без костей: BASE = F
	var comp: Array = [{"type": "slashing", "dice": "", "F": 10}]
	ok(int(Rules.damage(d, t, comp, {}, 1)["total"]) == 10, "без брони, S и V: FINAL = BASE")
	t.armor = Data.armor("leather")         # DR режущий 2
	ok(int(Rules.damage(d, t, comp, {}, 1)["total"]) == 8, "P = 0: FINAL = max(0, BASE − DR) = 8")
	ok(int(Rules.damage(d, t, comp, {"slashing": 1.0}, 1)["total"]) == 10, "P = 100 %: броня игнорируется")
	ok(int(Rules.damage(d, t, comp, {"slashing": 0.5}, 1)["total"]) == 9, "P = 50 %: DR_EFF = floor(2 × 0,5) = 1")
	ok(int(Rules.damage(d, t, [{"type": "slashing", "dice": "", "F": 2}], {}, 1)["total"]) == 0, "DR ≥ BASE: 0")
	ok(int(Rules.damage(d, t, [{"type": "piercing", "dice": "", "F": 10}], {}, 1)["total"]) == 10, "DR = 0 по этому типу: AFTER = BASE")
	t.resist = {"slashing": 0.5}
	ok(int(Rules.damage(d, t, [{"type": "slashing", "dice": "", "F": 11}], {}, 1)["total"]) == 4, "сопротивление: floor((11 − 2) × 0,5) = 4")
	t.resist = {}
	t.vulnerable = {"slashing": 1.0}
	ok(int(Rules.damage(d, t, [{"type": "slashing", "dice": "", "F": 7}], {}, 1)["total"]) == 10, "уязвимость: floor((7 − 2) × 2) = 10")
	t.resist = {"slashing": 0.5}
	ok(int(Rules.damage(d, t, [{"type": "slashing", "dice": "", "F": 9}], {}, 1)["total"]) == 7, "S и V вместе: floor(7 × 0,5 × 2) = 7")
	t.resist = {}
	t.vulnerable = {}
	t.immune = PackedStringArray(["fire"])
	ok(int(Rules.damage(d, t, [{"type": "fire", "dice": "", "F": 30}], {}, 1)["total"]) == 0, "иммунитет: 0")
	var multi: Dictionary = Rules.damage(d, t, [{"type": "slashing", "dice": "", "F": 6}, {"type": "fire", "dice": "", "F": 5}, {"type": "bludgeoning", "dice": "", "F": 4}], {}, 1)
	ok(int(multi["total"]) == 4 + 0 + 2 and multi["parts"].size() == 3, "несколько типов: у каждого свои DR, S, V, IMM (4 + 0 + 2)")
	var w: BattleWeapon = Data.weapon("battleaxe")
	var a = mk({"str": 16})
	var comps: Array = Rules.components(a, w)
	ok(comps.size() == 2 and int(comps[0]["F"]) == 3 and int(comps[1]["F"]) == 0, "модификатор СИЛ добавлен один раз, в первый компонент")
	# попадание: R = L — промах, R = H — крит, иначе ATK ≥ AC
	var att = mk({"str": 16})
	att.weapons = [Data.weapon("longsword")]
	var tgt = mk({}, "plate")
	var ctx: Dictionary = {"ranged": false, "dist_ft": 5}
	d.forced = [1]
	var low: Dictionary = Rules.attack(d, mk({"str": 30}), tgt, Data.weapon("longsword"), null, ctx.duplicate())
	ok(not low["hit"], "R = L: промах даже при огромном бонусе")
	d.forced = [20, 4, 4]
	var hi: Dictionary = Rules.attack(d, mk({"str": 1}), mk({"dex": 10}, "plate"), Data.weapon("longsword"), null, ctx.duplicate())
	ok(hi["hit"] and hi["crit"] and hi["roll"]["natural"] == 20, "R = H: попадание и крит")
	ok(hi["damage"]["parts"][0]["Q"] == 8, "на крите кости бросаются K_CRIT = 2 раза (4 + 4)")
	d.forced = [10]
	var mid: Dictionary = Rules.attack(d, att, tgt, Data.weapon("longsword"), null, ctx.duplicate())
	ok(not mid["hit"] and int(mid["ATK"]) == 10 + 3 + 2, "ATK = R + M_ATK + PB = 15 против AC 16 — промах")
	d.forced = [11, 5]
	var mid2: Dictionary = Rules.attack(d, att, tgt, Data.weapon("longsword"), null, ctx.duplicate())
	ok(mid2["hit"] and not mid2["crit"], "ATK 16 ≥ AC 16 — попадание: " + mid2["text"])
	ok(mid2["text"].contains("Атака: 11 (d20)") and mid2["text"].contains("против AC 16") and mid2["text"].contains("Урон:"), "лог в формате «Атака: 11 (d20) … против AC 16 → … Урон: …»")


# --- Правила боя -----------------------------------------------------------
func _rules() -> void:
	var t = mk({"dex": 16}, "leather")
	ok(int(Rules.ac(t)["total"]) == 15, "кожаная: 12 + ЛОВ 3 = 15")
	t.armor = Data.armor("chain")
	ok(int(Rules.ac(t)["total"]) == 14, "кольчуга: 14, ЛОВ не идёт")
	ok(int(Rules.ac(t, "half")["total"]) == 16 and int(Rules.ac(t, "three_quarters")["total"]) == 19, "укрытие ½ +2, ¾ +5")
	t.armor = Data.armor("hides")
	ok(int(Rules.ac(t)["total"]) == 14, "шкуры: 11 + ЛОВ 3")
	var att = mk({"str": 14, "dex": 18})
	ok(Rules.attack_terms(att, Data.weapon("shortsword"))["stat"] == "dex", "finesse: берётся лучшая из СИЛ и ЛОВ")
	ok(Rules.attack_terms(att, Data.weapon("sling"))["stat"] == "dex" and Rules.attack_terms(att, Data.weapon("club"))["stat"] == "str", "дальнее — ЛОВ, ближнее — СИЛ")
	var caster = mk({"int": 16})
	ok(Rules.save_dc(caster, "int") == 8 + 3 + 2, "DC = 8 + мод + мастерство = 13")
	var d := DiceRoller.new(3)
	var st = mk({"dex": 10})
	st.add_effect("stunned")
	ok(not Rules.saving_throw(d, st, "dex", 5)["ok"], "оглушённый проваливает спасбросок Ловкости автоматически")
	# преимущество/помеха
	var p = mk({})
	p.add_effect("prone")
	var a2 = mk({})
	ok(Rules.adv_dis(a2, p, {"ranged": false, "dist_ft": 5})["adv"].size() > 0, "по лежащему вблизи — преимущество")
	ok(Rules.adv_dis(a2, p, {"ranged": true, "dist_ft": 30})["dis"].size() > 0, "по лежащему издали — помеха")
	var bl = mk({})
	bl.add_effect("blinded")
	ok(Rules.adv_dis(bl, mk({}), {"ranged": false, "dist_ft": 5})["dis"].size() > 0, "ослеплённый атакует с помехой")
	var dg = mk({})
	dg.add_effect("dodging")
	ok(Rules.adv_dis(mk({}), dg, {"ranged": false, "dist_ft": 5})["dis"].size() > 0, "по уклоняющемуся — помеха")
	# травма при 0 HP: пороги 15 / 8
	var z = mk({"con": 10})
	d.forced = [15]
	ok(Rules.zero_hp_check(d, z)["result"] == "trauma", "0 HP: 15+ — травма, в сознании")
	d.forced = [8]
	ok(Rules.zero_hp_check(d, z)["result"] == "down", "0 HP: 8–14 — без сознания, стабилен")
	d.forced = [7]
	ok(Rules.zero_hp_check(d, z)["result"] == "dead", "0 HP: 7 и ниже — смерть")
	ok(Rules.fall_dice(25) == "2d6" and Rules.fall_dice(500) == "20d6" and Rules.fall_dice(5) == "", "падение: 1d6 за 10 футов, не больше 20d6")


# --- Сетка ------------------------------------------------------------------
func _grid() -> void:
	var g := Grid.new()
	g.size = Vector2i(10, 10)
	ok(g.dist_ft(Vector2i(0, 0), Vector2i(3, 2)) == 15, "расстояние по сетке: диагональ 5 футов")
	var r: Dictionary = g.reachable(Vector2i(0, 0), 30, {}, {})
	ok(r.has(Vector2i(6, 6)) and not r.has(Vector2i(7, 0)), "30 футов = 6 клеток, по диагонали тоже")
	g.difficult[Vector2i(1, 0)] = true
	g.difficult[Vector2i(1, 1)] = true
	var r2: Dictionary = g.reachable(Vector2i(0, 0), 10, {}, {})
	ok(int(r2[Vector2i(1, 0)]["cost"]) == 10 and not r2.has(Vector2i(2, 0)), "трудная местность — двойное движение")
	g.difficult.clear()
	g.obstacle[Vector2i(5, 5)] = "tree"
	ok(g.cover(Vector2i(2, 5), Vector2i(8, 5), {}) == "three_quarters", "дерево между — укрытие ¾")
	g.obstacle[Vector2i(5, 5)] = "rock"
	ok(g.cover(Vector2i(2, 5), Vector2i(8, 5), {}) == "half", "камень — укрытие ½")
	g.obstacle[Vector2i(5, 5)] = "cliff"
	ok(g.cover(Vector2i(2, 5), Vector2i(8, 5), {}) == "full", "скала — полное укрытие, цель не выбрать")
	ok(g.cover(Vector2i(4, 5), Vector2i(8, 5), {}) == "none", "препятствие вплотную к стрелку не мешает")
	ok(g.cover(Vector2i(2, 2), Vector2i(8, 2), {Vector2i(5, 2): true}) == "half", "существо между — укрытие ½")
	var r3: Dictionary = g.reachable(Vector2i(0, 0), 30, {Vector2i(1, 0): true, Vector2i(0, 1): true, Vector2i(1, 1): true}, {})
	ok(r3.size() == 1, "враги вокруг — не пройти")
	_paths()


static func turns(path: Array) -> int:
	var n: int = 0
	for i in range(2, path.size()):
		if path[i] - path[i - 1] != path[i - 1] - path[i - 2]:
			n += 1
	return n


func _paths() -> void:
	var g := Grid.new()
	g.size = Vector2i(14, 10)
	var r: Dictionary = g.reachable(Vector2i(1, 5), 60, {}, {})
	var p: Array = g.path_to(r, Vector2i(9, 5))
	ok(p.size() == 9 and turns(p) == 0 and p.all(func(c): return c.y == 5), "путь по прямой — прямо, без зигзагов: %s" % str(p))
	p = g.path_to(r, Vector2i(7, 2))
	ok(p.size() == 7 and turns(p) <= 1, "наискосок — не больше одного поворота: %s" % str(p))
	g.obstacle[Vector2i(5, 5)] = "rock"
	r = g.reachable(Vector2i(1, 5), 60, {}, {})
	p = g.path_to(r, Vector2i(9, 5))
	ok(int(r[Vector2i(9, 5)]["cost"]) == 40 and p.size() == 9 and turns(p) <= 3 and not p.has(Vector2i(5, 5)) and p.all(func(c): return absi(c.y - 5) <= 2), "камень на пути — обход рядом, за те же футы: %s" % str(p))
	g.obstacle.clear()
	g.hazard[Vector2i(5, 5)] = true
	r = g.reachable(Vector2i(1, 5), 60, {}, {})
	p = g.path_to(r, Vector2i(9, 5))
	ok(p.size() == 9 and not p.has(Vector2i(5, 5)), "светящаяся клетка — в обход, если по футам так же")
	g.hazard.clear()
	var threat: Dictionary = {}
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			threat[Vector2i(4, 3) + Vector2i(dx, dy)] = true
	p = g.path_to(r, Vector2i(9, 5), threat)
	var provoke: bool = false
	for i in range(1, p.size()):
		if threat.has(p[i - 1]) and not threat.has(p[i]):
			provoke = true
	ok(not provoke and p.size() == 9, "мимо врага — не выходить из-под его удара, если можно по тем же футам")
	g.difficult[Vector2i(5, 5)] = true
	g.difficult[Vector2i(5, 4)] = true
	g.difficult[Vector2i(5, 6)] = true
	r = g.reachable(Vector2i(1, 5), 60, {}, {})
	p = g.path_to(r, Vector2i(9, 5))
	var cost: int = 0
	for i in range(1, p.size()):
		cost += g.step_cost(p[i - 1], p[i])
	ok(cost == int(r[Vector2i(9, 5)]["cost"]) and cost == 40, "трудная местность — в обход, путь самый дешёвый: %d фт" % cost)


# --- Бой целиком ------------------------------------------------------------
func make_core(req: Dictionary) -> Node:
	var c: Node = Core.new()
	root.add_child(c)
	c.setup(req)
	return c


func _battles() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var hero := Actor.new("hero", "Герой", false, 1)
	var npc := Actor.new("npc_1", "Ждан", true, 2)
	var core: Node = make_core({"terrain": "forest", "allies": [hero, npc], "pets": ["dog"], "group": "bandits", "seed": 77, "no_cap": true})
	ok(core.all.size() >= 4 and core.all.filter(func(x): return x.is_pet).size() == 1, "на поле герой, НПС, пёс и враги: %d" % core.all.size())
	var turns: Array = []
	core.turn_started.connect(func(c): turns.append(c))
	core.begin()
	var ord: Array = core.order.map(func(x): return x.initiative)
	var sorted: bool = true
	for i in range(1, ord.size()):
		if ord[i] > ord[i - 1]:
			sorted = false
	ok(sorted, "очередь по убыванию инициативы: %s" % str(ord))
	var h = core.hero()
	ok(core.current() == h and h.controlled, "ход дошёл до героя и ждёт игрока (раунд %d)" % core.round_n)
	ok(h.move_left == 30 and h.has_action and h.has_bonus and h.has_reaction, "экономия хода: 30 фт, действие, бонусное, реакция")
	var before: Vector2i = h.cell
	var reach: Dictionary = core.reach_of(h)
	var dest: Vector2i = before
	for c in reach:
		if not reach[c].get("pass_only", false) and int(reach[c]["cost"]) == 15:
			dest = c
			break
	ok(core.move_to(h, dest) and h.move_left == 15, "прошёл 15 футов, осталось 15")
	ok(core.swap_weapon(h) and not core.swap_weapon(h), "смена оружия — одно свободное взаимодействие за ход")
	ok(core.dodge(h) and not core.dash(h), "одно действие за ход")
	var sw: BattleAbility = Data.ability("second_wind")
	h.hp = 3
	ok(core.use_ability(h, sw, h) and h.hp > 3 and not h.has_bonus, "второе дыхание — бонусным действием")
	ok(not core.use_ability(h, sw, h), "второе дыхание раз за бой")
	core.end_turn()
	ok(core.current() == h or core.outcome != "", "ИИ сходил, снова очередь героя (раунд %d)" % core.round_n)

	# Атака по возможности: герой уходит от врага без Disengage
	var core2: Node = make_core({"terrain": "wasteland", "allies": [Actor.new("hero", "Герой", false, 3)], "enemies": [Enc.make_enemy("bandit", 0, rng)], "seed": 12})
	var h2 = core2.hero()
	var e2 = core2.all[1]
	h2.cell = Vector2i(10, 8)
	e2.cell = Vector2i(11, 8)
	h2.start_turn_reset()
	e2.start_turn_reset()
	core2.order = [h2, e2]
	core2.turn_i = 0
	var log_n: int = core2.log_lines.size()
	core2.move_to(h2, Vector2i(8, 8))
	ok(not e2.has_reaction and core2.log_lines.slice(log_n).any(func(l): return l.begins_with("Атака по возможности")), "уход без Disengage — атака по возможности")
	h2.cell = Vector2i(10, 8)
	h2.start_turn_reset()
	e2.has_reaction = true
	core2.disengage(h2)
	core2.move_to(h2, Vector2i(8, 8))
	ok(e2.has_reaction, "после Disengage атаки по возможности нет")
	# Help по врагу даёт преимущество
	h2.cell = Vector2i(10, 8)
	h2.start_turn_reset()
	core2.help(h2, e2)
	ok(Rules.adv_dis(h2, e2, {"ranged": false, "dist_ft": 5})["adv"].has("помощь союзника"), "Help — следующая атака союзника с преимуществом")
	# 0 HP героя: травма в Actor
	h2.hp = 2
	core2.roller.forced = [16, 5]
	core2._apply_damage(h2, {"total": 5, "parts": [{"type": "slashing", "FINAL": 5}]}, e2, false)
	ok(h2.hp == 1 and not h2.down and not h2.actor.conditions.is_empty(), "0 HP, проверка 16 — травма (%s), остаётся с 1 HP" % str(h2.actor.conditions.map(func(x): return x["id"])))
	h2.hp = 1
	core2.roller.forced = [9, 12]
	core2._apply_damage(h2, {"total": 5, "parts": [{"type": "bludgeoning", "FINAL": 5}]}, e2, false)
	ok(h2.down and h2.has_effect("unconscious") and h2.actor.alive, "проверка 9 — без сознания, стабилен")
	var npc2 = Combatant.new()
	core2.roller.forced = [3]
	core2._apply_damage(h2, {"total": 3, "parts": [{"type": "bludgeoning", "FINAL": 3}]}, e2, false)
	ok(h2.dead and not h2.actor.alive and core2.outcome == "lose", "удар по лежащему, проверка 3 — смерть, поражение")
	core2.free()
	core.free()

	# Полные бои под ИИ: герой тоже под ИИ
	var stats: Dictionary = {}
	for grp in ["bandits", "wolves", "boar", "hounds"]:
		var w: int = 0
		var rounds: int = 0
		for s in 20:
			var allies: Array = [Actor.new("hero", "Герой", false, 500 + s)]
			var cb: Node = make_core({"terrain": "wasteland", "allies": allies, "group": grp, "seed": 900 + s})
			for c in cb.all:
				c.controlled = false
			cb.begin()
			var guard: int = 0
			while cb.outcome == "" and guard < 400:
				cb.next_turn()
				guard += 1
			if cb.outcome == "win":
				w += 1
			rounds += cb.round_n
			if s == 0 and grp == "bandits":
				var res: Dictionary = cb.result()
				ok(res.has("outcome") and res.has("dead") and res.has("return_pos") and float(res["game_minutes"]) > 0.0, "результат боя: %s, %d раундов" % [res["outcome"], res["rounds"]])
				var snap: Dictionary = cb.to_dict()
				ok(snap["all"].size() == cb.all.size() and snap.has("order"), "to_dict боя")
			cb.free()
		stats[grp] = [w, rounds / 20.0]
		ok(true, "%s: герой (один, под ИИ) побеждает %d из 20, в среднем %.1f раунда" % [grp, w, rounds / 20.0])
	ok(Data.missing.is_empty(), "все ресурсы найдены: %s" % str(Data.missing))

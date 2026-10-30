extends Node
## Ход боя без интерфейса: участники, инициатива, очередь ходов, действия, реакции, ИИ, итог.
## Интерфейс (battle_scene.gd) только показывает и передаёт сюда приказы игрока; тесты гоняют ядро напрямую.
## Раунд = 6 игровых секунд.

signal logged(text: String, kind: String)
signal turn_started(c)
signal round_started(n: int)
signal moved(c, path: Array)
signal acted(c, what: String, data: Dictionary)
signal finished(outcome: String)

const Data := preload("res://battle/battle_data.gd")
const Rules := preload("res://battle/combat_rules.gd")
const Combatant := preload("res://battle/combatant.gd")
const Grid := preload("res://battle/battle_grid.gd")
const Enc := preload("res://battle/encounters.gd")
const Trade := preload("res://city/trade.gd")
const Sheet := preload("res://characters/sheet.gd")
const ROUND_S: float = 6.0

var cfg: BattleConfig
var roller: DiceRoller
var grid := Grid.new()
var req: Dictionary = {}
var arena_key: String = "wasteland"
var all: Array = []                # усі учасники
var order: Array = []              # черга ініціативи (не змінюється в бою)
var turn_i: int = -1
var round_n: int = 0
var outcome: String = ""
var killed: int = 0
var killed_levels: int = 0           # сумма уровней убитых врагов — опыт после победы
var xp_gained: int = 0
var loot: Dictionary = {}
var log_lines: Array = []
var fleeing: Dictionary = {}       # учасник -> true: здригнувся й відступає
var auto_ai: bool = true           # ШІ ходить одразу (тести); інтерфейс вимикає й веде ходи сам


# =====================================================================
# ВХІД
# =====================================================================
func setup(r: Dictionary) -> void:
	req = r
	cfg = Data.config()
	roller = DiceRoller.new(int(req.get("seed", 0)))
	roller.rolled.connect(func(e: Dictionary) -> void: acted.emit(null, "roll", e))
	var ter: String = String(req.get("terrain", ""))
	if ter == "" and req.has("biome"):
		ter = Enc.terrain_key(int(req["biome"]))
	if ter == "" or ter == "water":
		ter = "coast"
	req["terrain"] = ter
	arena_key = "hot" if bool(req.get("hot", false)) and ter in ["mountains", "wasteland", "rad_wasteland"] else ter
	if not cfg.arena.has(arena_key):
		arena_key = "wasteland"
	grid.setup(arena_key, roller.rng.randi(), cfg)
	if req.get("enemies", []).is_empty():
		req["enemies"] = Enc.make_enemies(req, roller.rng)
	_spawn()


func _spawn() -> void:
	var allies: Array = req.get("allies", [])
	var npc_i: int = 0
	for a in allies:
		if not (a is Actor) or not a.alive:
			continue
		a.set_sleep(false)
		var c = Combatant.new()
		var hero: bool = a.actor_id == "hero" or all.is_empty()
		var lo: Dictionary = cfg.hero.duplicate() if hero else cfg.npc.duplicate()
		if hero and req.get("inventory", null) is Dictionary:
			lo["weapons"] = default_loadout()
			lo["armor"] = worn_armor(req["inventory"])
		if not hero:
			var sets: Array = cfg.npc.get("weapons", [["club"]])
			lo["weapons"] = sets[npc_i % sets.size()]
			npc_i += 1
		c.build_from_actor(a, 0, cfg, lo)
		c.is_hero = hero
		c.controlled = hero
		all.append(c)
	var pn: int = 0
	for pid in req.get("pets", []):
		var cr: BattleCreature = Data.creature(String(pid))
		if cr == null:
			continue
		var c = Combatant.new()
		c.build_from_creature(cr, Actor.new("pet:%s:%d" % [pid, pn], cr.title, true, roller.rng.randi()), 0, cfg, roller)
		all.append(c)
		pn += 1
	for a in req.get("enemies", []):
		if not (a is Actor) or not a.alive:
			continue
		var kind: String = Enc.kind_of(a)
		var cr: BattleCreature = Data.creature(kind if kind != "" else "bandit")
		if cr == null:
			cr = Data.creature("bandit")
		var c = Combatant.new()
		c.build_from_creature(cr, a, 1, cfg, roller)
		all.append(c)
	# Стани персонажа з пакета стають ефектами бою (перелом ноги — повільніше тощо)
	for c in all:
		for cond in c.actor.conditions:
			var eid: String = String(cfg.pack_effects.get(cond["id"], ""))
			if eid != "":
				c.add_effect(eid)
	_place()


func _place() -> void:
	var taken: Dictionary = {}
	var left: Array = all.filter(func(c): return c.team == 0)
	var right: Array = all.filter(func(c): return c.team == 1)
	var mid: int = grid.size.y / 2
	for i in left.size():
		left[i].cell = _free_near(Vector2i(2 + (i % 2), mid - left.size() / 2 + i), taken)
		taken[left[i].cell] = true
	var far_x: int = grid.size.x - 4 - (2 if req.get("night", false) else 0)
	for i in right.size():
		var back: int = 2 if right[i].ai == "ranged" else 0
		right[i].cell = _free_near(Vector2i(far_x + back - (i % 2), mid - right.size() / 2 + i), taken)
		taken[right[i].cell] = true


func _free_near(p: Vector2i, taken: Dictionary) -> Vector2i:
	for r in range(0, 8):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var q: Vector2i = p + Vector2i(dx, dy)
				if grid.walkable(q) and not taken.has(q):
					return q
	return p


## Кидок ініціативи й перший хід. Окремо від setup, щоб інтерфейс устиг підписатися
func begin() -> void:
	log_line(I18n.t("Бой: %s. Бросаем инициативу.") % _group_title(), "head")
	for c in all:
		var r: Dictionary = Rules.initiative(roller, c)
		c.init_tiebreak = 0.0
		log_line(I18n.t("Инициатива %s: %s") % [c.title, r["text"]], "roll")
	order = all.duplicate()
	# за рівності — СПР, далі додатковий кидок, за нової рівності — сторона гравця
	for c in order:
		c.init_tiebreak = float(c.scores.get("dex", 10)) * 100.0 + float(roller.die(20)) + (0.5 if c.team == 0 else 0.0)
	order.sort_custom(func(a, b): return a.initiative > b.initiative or (a.initiative == b.initiative and a.init_tiebreak > b.init_tiebreak))
	log_line(I18n.t("Очередь: ") + ", ".join(PackedStringArray(order.map(func(c): return "%s %d" % [c.title, c.initiative]))), "head")
	round_n = 1
	round_started.emit(round_n)
	turn_i = -1
	next_turn()


# =====================================================================
# ЗБРОЯ ІЗ СУМКИ (до loadout_max видів; обирає гравець перед боєм)
# =====================================================================
## [{item, weapon: BattleWeapon, count}] — зброя, що лежить у req.inventory.items
func inventory_weapons() -> Array:
	var out: Array = []
	var inv: Variant = req.get("inventory", null)
	if not (inv is Dictionary):
		return out
	var items: Dictionary = inv.get("items", {})
	for id in items:
		if int(items[id]) <= 0 or not cfg.item_weapons.has(id):
			continue
		var w: BattleWeapon = Data.weapon(String(cfg.item_weapons[id]))
		if w != null:
			out.append({"item": String(id), "weapon": w, "count": int(items[id])})
	return out


## Обладунок героя — те, що вдягнено на «Тіло» (items.json wear.armor); нічого — без обладунку
static func worn_armor(inv: Dictionary) -> String:
	var body: String = String(inv.get("equipped", {}).get("body", ""))
	if body == "" or int(inv.get("items", {}).get(body, 0)) <= 0:
		return "none"
	return String(Trade.item(body).get("wear", {}).get("armor", "none"))


## Що взяти за замовчуванням: минулий вибір (inventory.battle_loadout), якщо ще в сумці, інакше перші із сумки
func default_loadout() -> Array:
	var have: Array = inventory_weapons()
	var by_item: Dictionary = {}
	for e in have:
		by_item[e["item"]] = e["weapon"].id
	var out: Array = []
	var inv: Dictionary = req.get("inventory", {})
	for it in inv.get("battle_loadout", []):
		if by_item.has(it) and out.size() < cfg.loadout_max:
			out.append(by_item[it])
	if out.is_empty():
		for e in have.slice(0, cfg.loadout_max):
			out.append(e["weapon"].id)
	return out if not out.is_empty() else ["fists"]


## Вибір гравця: items — id предметів із сумки (до loadout_max). Порожньо — кулаки
func set_loadout(c, items: Array) -> void:
	var ids: Array = []
	for it in items.slice(0, cfg.loadout_max):
		if cfg.item_weapons.has(it):
			ids.append(String(cfg.item_weapons[it]))
	c.set_weapons(ids if not ids.is_empty() else ["fists"])
	var inv: Variant = req.get("inventory", null)
	if inv is Dictionary:
		inv["battle_loadout"] = items.slice(0, cfg.loadout_max)
	log_line(I18n.t("%s берёт в бой: %s.") % [c.title, ", ".join(PackedStringArray(c.weapons.map(func(w): return w.title.to_lower())))], "info")


## Узяти до рук зброю зі своїх (до трьох): вільна взаємодія, раз за хід
func draw_weapon(c, i: int) -> bool:
	if i == c.wi or i < 0 or i >= c.weapons.size():
		return i == c.wi
	if c.free_used:
		log_line(I18n.t("%s уже доставал оружие в этот ход.") % c.title, "info")
		return false
	c.free_used = true
	c.wi = i
	log_line(I18n.t("%s берёт %s.") % [c.title, c.weapon().title.to_lower()], "info")
	return true


func _group_title() -> String:
	var t: Dictionary = {"bandits": I18n.t("разбойники"), "wolves": I18n.t("волки"), "boar": I18n.t("кабан"), "hounds": I18n.t("проклятые гончие")}
	return t.get(String(req.get("group", "")), I18n.t("враги"))


# =====================================================================
# ЧЕРГА ХОДІВ
# =====================================================================
func current():
	return order[turn_i] if turn_i >= 0 and turn_i < order.size() else null


func next_turn() -> void:
	# Цикл, а не рекурсія: підряд можуть ходити десятки учасників під ШІ
	while outcome == "":
		turn_i += 1
		if turn_i >= order.size():
			turn_i = 0
			round_n += 1
			round_started.emit(round_n)
			log_line(I18n.t("— Раунд %d —") % round_n, "head")
		var c = current()
		if not c.active():
			continue
		if not _start_turn(c):
			_check_end()
			continue
		turn_started.emit(c)
		if c.controlled:
			return
		if not auto_ai:
			return           # інтерфейс сам викличе run_ai_turn() після паузи
		ai_turn(c)
		_finish_turn(c)


## Хід ШІ на виклик інтерфейсу (коли auto_ai вимкнено — щоб ходи ворогів було видно)
func run_ai_turn() -> void:
	var c = current()
	if outcome != "" or c == null or c.controlled:
		return
	if c.active() and not c.incapacitated():
		ai_turn(c)
	_finish_turn(c)
	next_turn()


func _finish_turn(c) -> void:
	if c.active():
		_end_effect_saves(c)
	_check_end()


# Початок ходу: ефекти, тривалості, небезпечні клітинки. false — хід пропущено
func _start_turn(c) -> bool:
	c.start_turn_reset()
	# «Быстро на ноги»: встаёт в начале хода, не теряя движения
	if c.has_effect("prone") and not c.down and c.fx("quick_recovery") > 0.0:
		c.remove_effect("prone")
		log_line("%s мигом на ногах." % c.title, "info")
	# помощь против врага держится до следующего хода помогавшего
	for o in all:
		if o.helped_by == c.team and o.get_meta("help_src", null) == c:
			o.helped_by = -1
	# тривалості рахуються на початку ходу власника
	for e in c.effects.duplicate():
		if int(e["left"]) > 0:
			e["left"] = int(e["left"]) - 1
			if int(e["left"]) == 0:
				c.remove_effect(e["id"])
				log_line(I18n.t("%s: «%s» прошло.") % [c.title, e["res"].title], "info")
	for e in c.effects.duplicate():
		var r: BattleEffect = e["res"]
		if r.turn_start_dice != "" and c.active():
			var d: Dictionary = Rules.damage(roller, c, [{"type": r.turn_start_type, "dice": r.turn_start_dice, "F": 0}], {}, 1)
			log_line("%s — %s. %s" % [c.title, r.title.to_lower(), d["text"]], "hit")
			_apply_damage(c, d, null, false)
	if grid.hazard.has(c.cell) and c.active():
		var d: Dictionary = Rules.damage(roller, c, [{"type": "radiation", "dice": cfg.hazard_dice, "F": 0}], {}, 1)
		c.actor.add_res("radiation", float(d["total"]))
		log_line(I18n.t("%s стоит в светящемся пятне. %s") % [c.title, d["text"]], "hit")
		_apply_damage(c, d, null, false)
	if not c.active() or c.down:
		return false
	if c.incapacitated():
		log_line(I18n.t("%s пропускает ход (%s).") % [c.title, _incap_reason(c)], "info")
		_end_effect_saves(c)
		return false
	return true


func _incap_reason(c) -> String:
	for e in c.effects:
		if e["res"].incapacitated:
			return e["res"].title.to_lower()
	return I18n.t("не может действовать")


## Гравець закінчив хід
func end_turn() -> void:
	var c = current()
	if c == null or outcome != "":
		return
	_finish_turn(c)
	next_turn()


func _end_effect_saves(c) -> void:
	for e in c.effects.duplicate():
		var r: BattleEffect = e["res"]
		if r.end_save_stat != "":
			var s: Dictionary = Rules.saving_throw(roller, c, r.end_save_stat, r.end_save_dc)
			log_line(s["text"], "roll")
			if s["ok"]:
				c.remove_effect(e["id"])
				log_line(I18n.t("%s: «%s» снято.") % [c.title, r.title], "info")


# =====================================================================
# ПЕРЕМІЩЕННЯ
# =====================================================================
func occupancy(c) -> Dictionary:
	var blocked: Dictionary = {}
	var occupied: Dictionary = {}
	for o in all:
		if o == c or not o.active():
			continue
		occupied[o.cell] = true
		if o.team != c.team and o.standing():
			blocked[o.cell] = true
	return {"blocked": blocked, "occupied": occupied}


func reach_of(c, budget: int = -1) -> Dictionary:
	var oc: Dictionary = occupancy(c)
	var b: int = c.move_left if budget < 0 else budget
	if c.has_effect("prone"):
		b -= c.speed() / 2 if budget < 0 else 0
	return grid.reachable(c.cell, maxi(b, 0), oc["blocked"], oc["occupied"])


## Клітинки, відхід із яких дає ворогові атаку з нагоди (ворог поруч із реакцією)
func threat_cells(c) -> Dictionary:
	var out: Dictionary = {}
	if c.disengaged:
		return out
	for e in all:
		if e.team == c.team or not e.standing() or e.incapacitated() or not e.has_reaction:
			continue
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				out[e.cell + Vector2i(dx, dy)] = true
	return out


## Шлях, яким піде учасник: найдоступніший і найпростіший (battle_grid.path_to)
func path_for(c, reach: Dictionary, to: Vector2i) -> Array:
	return grid.path_to(reach, to, threat_cells(c))


## Пройти в клітинку. Атаки з нагоди й підготовлені атаки спрацьовують дорогою
func move_to(c, to: Vector2i) -> bool:
	if not c.standing() or c.incapacitated() or to == c.cell:
		return false
	var reach: Dictionary = reach_of(c)
	if not reach.has(to) or reach[to].get("pass_only", false):
		return false
	if c.has_effect("prone"):
		c.remove_effect("prone")
		c.move_left -= c.speed() / 2
		log_line(I18n.t("%s встаёт (половина движения).") % c.title, "info")
	var path: Array = path_for(c, reach, to)
	var walked: Array = [path[0]]
	for i in range(1, path.size()):
		var from: Vector2i = path[i - 1]
		var nxt: Vector2i = path[i]
		c.move_left -= grid.step_cost(from, nxt)
		c.cell = nxt
		walked.append(nxt)
		_reactions_on_move(c, from, nxt)
		if not c.standing():
			break
	moved.emit(c, walked)
	if c.has_effect("hidden") and _seen_by_enemies(c):
		c.remove_effect("hidden")
		log_line(I18n.t("%s замечен.") % c.title, "info")
	return true


func _reactions_on_move(c, from: Vector2i, to: Vector2i) -> void:
	for e in all:
		if e.team == c.team or not e.standing() or e.incapacitated() or not e.has_reaction:
			continue
		var mi: int = e.melee_index() if e.weapon().ranged else e.wi
		if mi < 0 and not e.weapons.is_empty():
			continue
		var reach: int = e.weapons[mi].reach_ft if mi >= 0 else 5
		var was_in: bool = grid.dist_ft(from, e.cell) <= reach
		var now_in: bool = grid.dist_ft(to, e.cell) <= reach
		if was_in and not now_in and not c.disengaged:
			e.has_reaction = false
			log_line(I18n.t("Атака по возможности: %s по %s.") % [e.title, c.title], "head")
			_weapon_attack(e, c, mi, true)
		elif not was_in and now_in and e.readied.get("type", "") == "attack":
			e.has_reaction = false
			e.readied = {}
			log_line(I18n.t("Подготовленная атака: %s по %s.") % [e.title, c.title], "head")
			_weapon_attack(e, c, mi, true)
		if not c.standing():
			return


# =====================================================================
# ДІЇ
# =====================================================================
func can_attack(c, t, wi: int = -1) -> Dictionary:
	if wi < 0:
		wi = c.wi
	var w: BattleWeapon = c.weapons[wi] if wi < c.weapons.size() and wi >= 0 else c.weapon()
	var d: int = grid.dist_ft(c.cell, t.cell)
	var cov: String = grid.cover(c.cell, t.cell, _creature_cells([c, t]))
	# «Быстрый выстрел», «Скорострел», «Шквал ударов»: ещё одна атака бонусным действием
	if not c.has_action and not (c.has_bonus and c.bonus_attack_ok(w)):
		return {"ok": false, "why": I18n.t("действие уже потрачено")}
	if not t.active() or t.team == c.team:
		return {"ok": false, "why": I18n.t("не цель")}
	if w.ranged:
		if w.ammo > 0 and int(c.ammo.get(w.id, 0)) <= 0:
			return {"ok": false, "why": I18n.t("нет снарядов")}
		if d > maxi(w.long_range_ft, w.range_ft):
			return {"ok": false, "why": I18n.t("слишком далеко (%d кл.)") % ceili(d / 5.0)}
	elif d > w.reach_ft:
		return {"ok": false, "why": I18n.t("не достать (%d кл.)") % ceili(d / 5.0)}
	if cov == "full":
		return {"ok": false, "why": I18n.t("цель за полным укрытием")}
	return {"ok": true, "dist": d, "cover": cov, "weapon": w}


func _ctx(c, t, w: BattleWeapon, cover: String) -> Dictionary:
	return {"ranged": w.ranged, "dist_ft": grid.dist_ft(c.cell, t.cell), "grid": grid, "all": all,
		"normal_range": w.range_ft if w.ranged else 1 << 20, "cover": cover}


## Шанс влучання й вилка шкоди — для підказки при наведенні
func preview_attack(c, t, wi: int = -1) -> Dictionary:
	var ca: Dictionary = can_attack(c, t, wi)
	var w: BattleWeapon = c.weapons[wi if wi >= 0 else c.wi] if not c.weapons.is_empty() else c.weapon()
	var cov: String = grid.cover(c.cell, t.cell, _creature_cells([c, t]))
	var terms: Dictionary = Rules.attack_terms(c, w)
	var ctx: Dictionary = _ctx(c, t, w, cov)
	ctx["stat"] = terms["stat"]
	var ad: Dictionary = Rules.adv_dis(c, t, ctx)
	var act: Dictionary = Rules.ac(t, cov)
	var p: float = DiceRoller.chance(int(terms["sum"]), int(act["total"]), not ad["adv"].is_empty(), not ad["dis"].is_empty(), true, cfg.attack_die)
	var lo: int = 0
	var hi: int = 0
	for comp in Rules.components(c, w):
		var rg: Vector2i = DiceRoller.range_of(comp["dice"]) if String(comp["dice"]) != "" else Vector2i.ZERO
		lo += maxi(int(comp.get("min", 0)), rg.x + int(comp["F"]))
		hi += maxi(int(comp.get("min", 0)), rg.y + int(comp["F"]))
	return {"ok": ca["ok"], "why": ca.get("why", ""), "chance": p, "ac": act, "mod": terms["sum"], "adv": ad["adv"], "dis": ad["dis"],
		"dmg": Vector2i(lo, hi), "cover": cov, "weapon": w}


func attack(c, t, wi: int = -1) -> bool:
	var ca: Dictionary = can_attack(c, t, wi)
	if not ca["ok"]:
		log_line(I18n.t("%s не может атаковать: %s.") % [c.title, ca["why"]], "info")
		return false
	if wi >= 0:
		c.wi = wi
	if c.has_action:
		c.has_action = false
	else:
		c.has_bonus = false
		log_line("%s атакует ещё раз (бонусное действие)." % c.title, "info")
	_weapon_attack(c, t, c.wi, false)
	_check_end()
	return true


func _creature_cells(skip: Array) -> Dictionary:
	var d: Dictionary = {}
	for o in all:
		if o.standing() and not skip.has(o):
			d[o.cell] = true
	return d


func _weapon_attack(c, t, wi: int, reaction: bool) -> void:
	var w: BattleWeapon = c.weapons[wi] if wi >= 0 and wi < c.weapons.size() else c.weapon()
	var cov: String = grid.cover(c.cell, t.cell, _creature_cells([c, t]))
	if w.ranged and w.ammo > 0:
		c.ammo[w.id] = int(c.ammo.get(w.id, 0)) - 1
	var res: Dictionary = Rules.attack(roller, c, t, w, null, _ctx(c, t, w, cov))
	log_line("%s → %s (%s). %s" % [c.title, t.title, w.title.to_lower(), res["text"]], "hit" if res["hit"] else "miss")
	_after_attack(c, t)
	acted.emit(c, "attack", {"target": t, "res": res, "weapon": w})
	if res["hit"]:
		_apply_damage(t, res["damage"], c, res["crit"])
		if w.on_hit_effect != "" and t.standing():
			_effect_with_save(c, t, w.on_hit_effect, w.on_hit_save, w.on_hit_dc)
	elif _jinxed() and c.standing() and roller.rng.randf() < 0.5:
		# черта «Невезучий»: промах любого рядом с героем — с шансом 50 % падение
		if c.add_effect("prone"):
			log_line("%s спотыкается и падает (невезение)." % c.title, "miss")


func _jinxed() -> bool:
	for o in all:
		if o.team == 0 and o.fx("jinxed") > 0.0:
			return true
	return false


func _after_attack(c, t) -> void:
	if c.has_effect("hidden"):
		c.remove_effect("hidden")
	if t.helped_by == c.team:
		t.helped_by = -1


func _effect_with_save(src, t, eid: String, stat: String, dc: int) -> void:
	if stat != "" and dc > 0:
		var s: Dictionary = Rules.saving_throw(roller, t, stat, dc)
		log_line(s["text"], "roll")
		if s["ok"]:
			return
	if t.add_effect(eid):
		log_line("%s: %s." % [t.title, Data.effect(eid).title.to_lower()], "info")


## Шкода учаснику: HP, 0 HP (перевірка травми для сторони героя), тяжкі рани, бойовий дух ворогів
func _apply_damage(t, dmg: Dictionary, src, crit: bool) -> void:
	var total: int = int(dmg["total"])
	if total <= 0 or not t.active():
		return
	var main: String = _main_type(dmg)
	if t.down:
		# по тому, хто лежить непритомний: нова перевірка; поганий результат — смерть
		var z: Dictionary = Rules.zero_hp_check(roller, t)
		log_line(z["text"], "roll")
		if z["result"] == "dead":
			_kill(t, src)
		return
	var h: Dictionary = Rules.apply_hp(t, total)
	log_line("%s: здоровье %d → %d%s." % [t.title, h["HP_OLD"], h["HP_NEW"], I18n.t(" (с избытком %d)") % h["OVERKILL"] if h["OVERKILL"] > 0 else ""], "info")
	if t.hp <= 0:
		if t.team == 0:
			var z: Dictionary = Rules.zero_hp_check(roller, t)
			log_line(z["text"], "roll")
			match z["result"]:
				"trauma":
					t.hp = 1
					_trauma(t, main, Rules.hit_zone(roller))
				"down":
					t.down = true
					t.add_effect("unconscious")
					t.add_effect("prone")
					_trauma(t, main, Rules.hit_zone(roller))
				_:
					_kill(t, src)
		else:
			_kill(t, src)
		return
	# тяжка рана — у тих, хто живе після бою (сторона героя)
	if t.team == 0 and (crit or total >= int(ceil(t.max_hp * cfg.heavy_hit_frac))):
		var ij: Dictionary = Rules.injury_check(roller, t, main)
		log_line(ij["text"], "roll")
		if ij["trauma"] != "":
			_trauma(t, main, ij["zone"], ij["trauma"])
	# ворог може здригнутися, коли HP впало до чверті
	if t.team == 1 and not fleeing.has(t) and t.hp <= t.max_hp / 4 and not t.get_meta("morale_done", false):
		t.set_meta("morale_done", true)
		if roller.rng.randf() > t.morale:
			fleeing[t] = true
			log_line(I18n.t("%s дрогнул и бежит.") % t.title, "info")


func _main_type(dmg: Dictionary) -> String:
	var best: String = "bludgeoning"
	var bv: int = -1
	for p in dmg.get("parts", []):
		if int(p["FINAL"]) > bv:
			bv = int(p["FINAL"])
			best = String(p["type"])
	return best


func _trauma(t, dtype: String, zone: String, cond: String = "") -> void:
	if cond == "":
		cond = Rules.trauma_for(zone, dtype)
	if cond == "" or not t.actor.add_condition(cond):
		return
	t.new_traumas.append(cond)
	var eid: String = String(cfg.pack_effects.get(cond, ""))
	if eid != "":
		t.add_effect(eid)
	log_line(I18n.t("%s получает травму: %s (%s).") % [t.title, String(Actor.R.condition(cond).get("name_ru", cond)).to_lower(),
		{"head": I18n.t("голова"), "torso": I18n.t("торс"), "arm": I18n.t("рука"), "leg": I18n.t("нога")}.get(zone, zone)], "hit")


func _kill(t, src) -> void:
	t.dead = true
	t.down = false
	t.hp = 0
	t.actor.die("wounds")
	if t.team == 1:
		killed += 1
		killed_levels += maxi(1, t.level)
	log_line((I18n.t("%s погиб.") % t.title if src == null else I18n.t("%s погиб (%s).") % [t.title, src.title]), "hit")
	if src != null and src.team == 0 and _bloody(src):
		log_line("Кровавый след: от %s мало что осталось." % t.title, "hit")
	_check_end()


func _hero_c():
	for c in all:
		if c.is_hero:
			return c
	return null


func _bloody(src) -> bool:
	return src.fx("bloody_mess") > 0.0


func dash(c) -> bool:
	if not c.has_action or not c.standing():
		return false
	c.has_action = false
	c.move_left += c.speed()
	log_line(I18n.t("%s: рывок (+%d кл. движения).") % [c.title, c.speed() / 5], "info")
	return true


func disengage(c) -> bool:
	if not c.has_action or not c.standing():
		return false
	c.has_action = false
	c.disengaged = true
	log_line(I18n.t("%s отходит без атак по возможности.") % c.title, "info")
	return true


func dodge(c) -> bool:
	if not c.has_action or not c.standing():
		return false
	c.has_action = false
	c.add_effect("dodging", 1)
	log_line(I18n.t("%s уклоняется до своего следующего хода.") % c.title, "info")
	return true


## Допомога: непритомного союзника — привести до тями з 1 HP; проти ворога поруч — перевага наступній атаці союзника
func help(c, t) -> bool:
	if not c.has_action or not c.standing() or grid.dist_ft(c.cell, t.cell) > 5:
		return false
	if t.team == c.team and t.down:
		c.has_action = false
		t.down = false
		t.hp = maxi(t.hp, 1)
		t.remove_effect("unconscious")
		log_line(I18n.t("%s приводит в чувство %s (здоровье 1).") % [c.title, t.title], "info")
		return true
	if t.team != c.team and t.standing():
		c.has_action = false
		t.helped_by = c.team
		t.set_meta("help_src", c)
		log_line(I18n.t("%s отвлекает %s: следующая атака союзника — с преимуществом.") % [c.title, t.title], "info")
		return true
	return false


func _seen_by_enemies(c) -> bool:
	for e in all:
		if e.team != c.team and e.standing() and not e.incapacitated():
			var cv: String = grid.cover(e.cell, c.cell, {})
			if cv in ["none", "half"]:
				return true
	return false


## Сховатися: лише якщо жоден ворог не бачить чітко (укриття ¾ або повне від усіх); Скритність проти уважності
func hide(c) -> bool:
	if not c.has_action or not c.standing():
		return false
	if _seen_by_enemies(c):
		log_line(I18n.t("%s: спрятаться негде — враги видят.") % c.title, "info")
		return false
	c.has_action = false
	var m: int = c.mod("dex") + (c.prof() if c.stealth_prof else 0)
	var r: Dictionary = roller.d20(m, false, c.armor != null and c.armor.stealth_disadvantage, I18n.t("Скрытность ") + c.title)
	var pp: int = 0
	for e in all:
		if e.team != c.team and e.standing():
			pp = maxi(pp, Rules.passive_perception(e))
	var ok: bool = int(r["total"]) >= pp
	log_line(I18n.t("Скрытность %s: %s против внимательности %d → %s.") % [c.title, r["text"], pp, I18n.t("скрыт") if ok else I18n.t("замечен")], "roll")
	if ok:
		c.add_effect("hidden")
	return ok


## Використати предмет: лікувальне зілля собі або союзнику поруч
func use_object(c, t = null) -> bool:
	if t == null:
		t = c
	# «Быстрые карманы»: зелье — бонусным действием
	var quick: bool = c.fx("quick_pockets") > 0.0 and c.has_bonus
	if not (c.has_action or quick) or not c.standing() or c.potions <= 0 or grid.dist_ft(c.cell, t.cell) > 5 or t.dead:
		return false
	if quick:
		c.has_bonus = false
	else:
		c.has_action = false
	c.potions -= 1
	var r: Dictionary = roller.roll(cfg.potion_dice, {"label": I18n.t("Зелье")})
	_heal(t, int(r["total"]) + int(c.fx("b_heal")), I18n.t("зелье: ") + r["text"] + (" +%d (целитель)" % int(c.fx("b_heal")) if c.fx("b_heal") > 0.0 else ""))
	return true


func _heal(t, amount: int, how: String) -> void:
	var old: int = t.hp
	t.hp = mini(t.max_hp, t.hp + maxi(0, amount))
	if t.down and t.hp > 0:
		t.down = false
		t.remove_effect("unconscious")
	log_line(I18n.t("%s восстанавливает %d здоровья (%s): %d → %d.") % [t.title, t.hp - old, how, old, t.hp], "heal")


## Підготувати атаку: реакцією вдарити першого ворога, що ввійшов у досяжність (до наступного ходу)
func ready_attack(c) -> bool:
	if not c.has_action or not c.standing():
		return false
	c.has_action = false
	c.readied = {"type": "attack"}
	log_line(I18n.t("%s готовит удар.") % c.title, "info")
	return true


## Вільна взаємодія: змінити зброю (раз за хід)
func swap_weapon(c) -> bool:
	if c.free_used or c.weapons.size() < 2:
		return false
	c.free_used = true
	c.wi = (c.wi + 1) % c.weapons.size()
	log_line(I18n.t("%s берёт %s.") % [c.title, c.weapon().title.to_lower()], "info")
	return true


## Піти з поля: стоячи на краю арени, дією
func flee(c) -> bool:
	if not c.has_action or not c.standing() or not grid.edge(c.cell):
		return false
	c.has_action = false
	c.fled = true
	log_line(I18n.t("%s покидает бой.") % c.title, "info")
	_check_end()
	return true


# =====================================================================
# ЗДІБНОСТІ
# =====================================================================
## target — учасник або клітинка (Vector2i) для здібностей по площі
func can_ability(c, ab: BattleAbility, target) -> Dictionary:
	if not c.standing() or c.incapacitated():
		return {"ok": false, "why": I18n.t("не может действовать")}
	if not c.can_use(ab):
		return {"ok": false, "why": I18n.t("нет %s или кончились применения") % {"action": I18n.t("действия"), "bonus": I18n.t("бонусного действия"), "reaction": I18n.t("реакции")}.get(ab.cost, "")}
	var cell: Vector2i = target if target is Vector2i else (target.cell if target != null else c.cell)
	if ab.target != "self" and grid.dist_ft(c.cell, cell) > maxi(ab.range_ft, 5 if ab.target == "ally" else 0):
		return {"ok": false, "why": I18n.t("далеко (%d кл.)") % ceili(grid.dist_ft(c.cell, cell) / 5.0)}
	if ab.target == "enemy" and (target == null or target is Vector2i or target.team == c.team or not target.active()):
		return {"ok": false, "why": I18n.t("нужна цель-враг")}
	if ab.target == "ally" and (target == null or target is Vector2i or target.team != c.team or target.dead):
		return {"ok": false, "why": I18n.t("нужен союзник")}
	if ab.target in ["enemy", "cell"] and grid.cover(c.cell, cell, {}) == "full":
		return {"ok": false, "why": I18n.t("не видно")}
	return {"ok": true}


func use_ability(c, ab: BattleAbility, target = null) -> bool:
	var ok: Dictionary = can_ability(c, ab, target)
	if not ok["ok"]:
		log_line("%s: %s — %s." % [c.title, ab.title, ok["why"]], "info")
		return false
	match ab.cost:
		"bonus":
			c.has_bonus = false
		"reaction":
			c.has_reaction = false
		_:
			c.has_action = false
	c.uses[ab.id] = int(c.uses.get(ab.id, 0)) + 1
	log_line("%s: %s." % [c.title, ab.title], "head")
	match ab.kind:
		"attack":
			_ability_attack(c, target, ab)
		"save":
			for t in _area_targets(c, ab, target):
				_ability_save(c, t, ab)
		"heal":
			var t = c if ab.target == "self" else target
			var r: Dictionary = roller.roll(ab.heal_dice, {"label": ab.title, "extra_mod": (c.level if ab.heal_add_level else 0) + (c.mod(ab.stat) if ab.target == "ally" else 0) + int(c.fx("b_heal"))})
			_heal(t, int(r["total"]), r["text"])
		"self":
			for t in all:
				if t.team == c.team and t.standing() and grid.dist_ft(c.cell, t.cell) <= ab.radius_ft:
					t.add_effect(ab.apply_effect)
			log_line(I18n.t("Союзники рядом: %s.") % Data.effect(ab.apply_effect).title.to_lower(), "info")
	acted.emit(c, "ability", {"ability": ab, "target": target})
	_check_end()
	return true


func _area_targets(c, ab: BattleAbility, target) -> Array:
	if ab.target == "enemy" and not (target is Vector2i):
		return [target]
	var center: Vector2i = target if target is Vector2i else c.cell
	var out: Array = []
	for t in all:
		if not t.active():
			continue
		if ab.target == "self" and (t.team == c.team):
			continue      # виття, крик — лише по ворогах довкола
		if grid.dist_ft(center, t.cell) <= ab.radius_ft:
			out.append(t)
	return out


func _ability_attack(c, t, ab: BattleAbility) -> void:
	var cov: String = grid.cover(c.cell, t.cell, _creature_cells([c, t]))
	var ctx: Dictionary = {"ranged": ab.range_ft > 5, "dist_ft": grid.dist_ft(c.cell, t.cell), "grid": grid, "all": all,
		"normal_range": ab.range_ft, "cover": cov}
	var res: Dictionary = Rules.attack(roller, c, t, c.weapon(), ab, ctx)
	log_line("%s → %s (%s). %s" % [c.title, t.title, ab.title.to_lower(), res["text"]], "hit" if res["hit"] else "miss")
	_after_attack(c, t)
	acted.emit(c, "attack", {"target": t, "res": res})
	if res["hit"]:
		_apply_damage(t, res["damage"], c, res["crit"])
		if ab.apply_effect != "" and t.standing():
			_effect_with_save(c, t, ab.apply_effect, ab.save_stat, Rules.save_dc(c, ab.stat))


func _ability_save(c, t, ab: BattleAbility) -> void:
	var dc: int = Rules.save_dc(c, ab.stat)
	var s: Dictionary = Rules.saving_throw(roller, t, ab.save_stat, dc)
	log_line(s["text"], "roll")
	if not ab.damage.is_empty() and (not s["ok"] or ab.half_on_save):
		var comps: Array = []
		for d in ab.damage:
			comps.append({"type": String(d.get("type", "fire")), "dice": String(d.get("dice", "")), "F": int(d.get("bonus", 0))})
		var dmg: Dictionary = Rules.damage(roller, t, comps, ab.penetration, 1, s["ok"])
		log_line("%s: %s" % [t.title, dmg["text"]], "hit")
		_apply_damage(t, dmg, c, false)
	if not s["ok"] and ab.apply_effect != "" and t.active():
		if t.add_effect(ab.apply_effect):
			log_line("%s: %s." % [t.title, Data.effect(ab.apply_effect).title.to_lower()], "info")


# =====================================================================
# ШІ: вороги, улюбленці й супутники без наказів
# =====================================================================
func ai_turn(c) -> void:
	if fleeing.has(c):
		_ai_flee(c)
		return
	# лікування й зілля
	if c.hp <= c.max_hp / 3:
		for ab in c.abilities:
			if ab.kind == "heal" and ab.target == "self" and c.can_use(ab):
				use_ability(c, ab, c)
		if c.hp <= c.max_hp / 3 and c.potions > 0 and c.has_action:
			use_object(c, c)
	for ab in c.abilities:
		if ab.kind == "heal" and ab.target == "ally" and c.can_use(ab):
			for a in all:
				if a.team == c.team and not a.dead and a != c and (a.down or a.hp <= a.max_hp / 3) and grid.dist_ft(c.cell, a.cell) <= 5:
					use_ability(c, ab, a)
					break
	# підняти непритомного союзника поруч
	for a in all:
		if a.team == c.team and a.down and c.has_action and grid.dist_ft(c.cell, a.cell) <= 5:
			help(c, a)
	var t = _ai_target(c)
	if t == null:
		if c.has_action:
			dodge(c)
		return
	# бонусні прийоми: клич, виття
	for ab in c.abilities:
		if ab.cost == "bonus" and ab.kind in ["self", "save"] and c.can_use(ab) and ab.target == "self":
			var n: int = 0
			for o in all:
				if o.team != c.team and o.standing() and grid.dist_ft(c.cell, o.cell) <= ab.radius_ft:
					n += 1
			if n > 0:
				use_ability(c, ab, c)
	# бомба по скупченню ворогів
	for ab in c.abilities:
		if ab.kind == "save" and ab.target == "cell" and c.can_use(ab) and c.has_action:
			var cell = _ai_area_cell(c, ab)
			if cell != null:
				use_ability(c, ab, cell)
	if not c.has_action:
		_ai_step_away(c)
		return
	# сітка, дротик — по цілі
	for ab in c.abilities:
		if ab.kind in ["save", "attack"] and ab.target == "enemy" and c.can_use(ab) and c.has_action and t.standing() \
				and can_ability(c, ab, t)["ok"] and roller.rng.randf() < 0.5:
			use_ability(c, ab, t)
	if not c.has_action:
		return
	var ranged: bool = c.ai == "ranged" and c.ranged_index() >= 0
	var adj: bool = _enemy_adjacent(c)
	if ranged and not adj:
		if c.wi != c.ranged_index():
			swap_weapon(c)
		if not _ai_shoot(c, t):
			_ai_close_in(c, t)
	else:
		if c.weapon().ranged and c.melee_index() >= 0:
			if not swap_weapon(c):
				c.wi = c.melee_index()
		_ai_close_in(c, t)
	if c.has_action:
		dodge(c)


func _ai_target(c):
	var best = null
	var bs: float = INF
	for o in all:
		if o.team == c.team or not o.standing():
			continue
		var s: float = float(grid.dist_ft(c.cell, o.cell)) + float(o.hp) * 0.5
		if o.is_hero:
			s -= 10.0
		if o.has_effect("hidden"):
			s += 60.0
		if s < bs:
			bs = s
			best = o
	return best


func _enemy_adjacent(c) -> bool:
	for o in all:
		if o.team != c.team and o.standing() and not o.incapacitated() and grid.dist_ft(c.cell, o.cell) <= 5:
			return true
	return false


func _ai_area_cell(c, ab: BattleAbility):
	var best = null
	var bn: int = 1
	for o in all:
		if o.team == c.team or not o.standing():
			continue
		if grid.dist_ft(c.cell, o.cell) > ab.range_ft:
			continue
		var n: int = 0
		var friendly: bool = false
		for p in all:
			if p.active() and grid.dist_ft(o.cell, p.cell) <= ab.radius_ft:
				if p.team == c.team:
					friendly = true
				else:
					n += 1
		if not friendly and n > bn:
			bn = n
			best = o.cell
	return best


func _ai_shoot(c, t) -> bool:
	var ca: Dictionary = can_attack(c, t)
	var w: BattleWeapon = c.weapon()
	if ca["ok"] and int(ca["dist"]) <= w.range_ft and ca["cover"] != "three_quarters":
		return attack(c, t)
	# відійти/підійти на клітинку, звідки видно й у звичайній дистанції, далі від ворогів
	var reach: Dictionary = reach_of(c)
	var best = null
	var bs: float = -INF
	for cell in reach:
		if reach[cell].get("pass_only", false):
			continue
		var d: int = grid.dist_ft(cell, t.cell)
		if d > w.range_ft or d <= 5:
			continue
		var cov: String = grid.cover(cell, t.cell, {})
		if cov in ["full", "three_quarters"]:
			continue
		var s: float = -float(reach[cell]["cost"]) * 0.2 + float(mini(d, 30)) * 0.3 + (8.0 if grid.elevation(cell) > grid.elevation(t.cell) else 0.0)
		if s > bs:
			bs = s
			best = cell
	if best == null:
		return false
	if best != c.cell:
		move_to(c, best)
	if c.standing() and can_attack(c, t)["ok"]:
		return attack(c, t)
	return false


func _ai_close_in(c, t) -> void:
	var w: BattleWeapon = c.weapon()
	if grid.dist_ft(c.cell, t.cell) <= w.reach_ft:
		attack(c, t)
		return
	var reach: Dictionary = reach_of(c)
	var best = null
	var bc: int = 1 << 30
	for cell in reach:
		if reach[cell].get("pass_only", false):
			continue
		if grid.dist_ft(cell, t.cell) <= w.reach_ft and int(reach[cell]["cost"]) < bc:
			bc = int(reach[cell]["cost"])
			best = cell
	if best != null:
		move_to(c, best)
		if c.standing() and can_attack(c, t)["ok"]:
			attack(c, t)
		return
	# не дійти за хід: ривок і йти шляхом до цілі
	if c.has_action:
		dash(c)
	var oc: Dictionary = occupancy(c)
	var far: Dictionary = grid.reachable(c.cell, 2000, oc["blocked"], {})
	var goal = null
	var gd: int = 1 << 30
	for cell in far:
		if grid.dist_ft(cell, t.cell) <= w.reach_ft and int(far[cell]["cost"]) < gd:
			gd = int(far[cell]["cost"])
			goal = cell
	if goal == null:
		return
	var path: Array = path_for(c, far, goal)
	var stop = null
	var now: Dictionary = reach_of(c)
	for p in path:
		if now.has(p) and not now[p].get("pass_only", false):
			stop = p
	if stop != null and stop != c.cell:
		move_to(c, stop)


func _ai_step_away(c) -> void:
	if c.ai != "ranged" or not _enemy_adjacent(c):
		return


func _ai_flee(c) -> void:
	if grid.edge(c.cell) and c.has_action:
		flee(c)
		return
	if _enemy_adjacent(c) and c.has_action:
		disengage(c)
	elif c.has_action:
		dash(c)
	var reach: Dictionary = reach_of(c)
	var best = null
	var bd: int = 1 << 30
	for cell in reach:
		if reach[cell].get("pass_only", false):
			continue
		var d: int = mini(mini(cell.x, cell.y), mini(grid.size.x - 1 - cell.x, grid.size.y - 1 - cell.y))
		if d < bd:
			bd = d
			best = cell
	if best != null:
		move_to(c, best)
	if grid.edge(c.cell) and c.has_action:
		flee(c)


# =====================================================================
# КІНЕЦЬ БОЮ
# =====================================================================
func hero():
	for c in all:
		if c.is_hero:
			return c
	return null


func _check_end() -> void:
	if outcome != "":
		return
	var h = hero()
	var foes: int = all.filter(func(c): return c.team == 1 and c.standing()).size()
	var friends: int = all.filter(func(c): return c.team == 0 and c.standing()).size()
	if h != null and h.dead:
		_finish("lose")
	elif h != null and h.fled:
		_finish("flee")
	elif foes == 0:
		_finish("win")
	elif friends == 0:
		_finish("lose")


func _finish(o: String) -> void:
	outcome = o
	for c in all:
		if c.team == 0 and not c.is_pet:
			c.write_back()
	if o == "win":
		var money: int = 0
		var scrap: int = 0
		var hides: int = 0
		for c in all:
			if c.team == 1 and c.dead and c.human:
				money += int(roller.roll("2d6", {"silent": true})["total"])
				# Брухт із бандитів (питання Q04, Huzzah 2026-10-24): 0–2 шматки з кожного [Q19: не баланс, залишено]
				# (кісток d3 у DiceRoller немає — «1d3» не розбиралося, і брухт не випадав ніколи)
				scrap += roller.rng.randi_range(0, 2)
			elif c.team == 1 and c.dead and not c.is_pet:
				# Шкури зі звірів — матеріал для шкіряника (питання Q18): 1–2 з кожного [Q19: не баланс, залишено]
				hides += roller.rng.randi_range(1, 2)
		# «Искатель удачи» — вдвое больше денег, «Добытчик» — на вещь больше
		var hero_c = _hero_c()
		if hero_c != null:
			money = int(round(money * (1.0 + hero_c.fx("battle_money"))))
			if hero_c.fx("battle_loot") > 0.0:
				if scrap > 0 or money > 0:
					scrap += int(hero_c.fx("battle_loot"))
				elif hides > 0:
					hides += int(hero_c.fx("battle_loot"))
		# Опыт: за каждого убитого — kill_per_level × уровень, всем живым людям стороны героя
		xp_gained = int(Sheet.num("xp", "kill_per_level", 40) * killed_levels)
		if xp_gained > 0:
			for c in all:
				if c.team == 0 and not c.is_pet and not c.dead and c.on_sheet:
					var lv: int = c.actor.level
					Sheet.gain_xp(c.actor, xp_gained)
					if c.actor.level > lv:
						log_line("%s: новый уровень %d!" % [c.title, c.actor.level], "head")
			log_line("Опыт: +%d." % xp_gained, "info")
		if money > 0:
			loot["money"] = money
		var got: Dictionary = {}
		if scrap > 0:
			got["scrap"] = scrap
		if hides > 0:
			got["hide"] = hides
		if not got.is_empty():
			loot["items"] = got
		var inv: Variant = req.get("inventory", null)
		if inv is Dictionary and not loot.is_empty():
			inv["money"] = int(inv.get("money", 0)) + money
			if not got.is_empty() and not inv.has("items"):
				inv["items"] = {}
			for id in got:
				inv["items"][id] = int(inv["items"].get(id, 0)) + int(got[id])
	log_line({"win": I18n.t("Победа."), "flee": I18n.t("Отступили."), "lose": I18n.t("Поражение.")}[o], "head")
	finished.emit(o)


func result() -> Dictionary:
	var dead: Array = []
	var traumas: Dictionary = {}
	for c in all:
		if c.team == 0 and c.dead:
			dead.append(c.actor.actor_id)
		if c.team == 0 and not c.new_traumas.is_empty():
			traumas[c.actor.actor_id] = c.new_traumas.duplicate()
	return {"outcome": outcome, "origin": req.get("origin", "overworld"), "return_pos": req.get("return_pos", Vector2.ZERO),
		"game_minutes": maxf(round_n, 1) * ROUND_S / 60.0, "rounds": round_n, "dead": dead, "killed": killed, "loot": loot, "xp": xp_gained,
		"traumas": traumas}


func log_line(t: String, kind: String = "info") -> void:
	log_lines.append(t)
	if log_lines.size() > 400:
		log_lines.pop_front()
	logged.emit(t, kind)


# =====================================================================
# ЗБЕРЕЖЕННЯ
# =====================================================================
func to_dict() -> Dictionary:
	return {"round": round_n, "turn": turn_i, "order": order.map(func(c): return c.actor.actor_id),
		"all": all.map(func(c): return c.to_dict()), "killed": killed, "killed_levels": killed_levels, "log": log_lines.slice(maxi(0, log_lines.size() - 60)),
		"fleeing": fleeing.keys().map(func(c): return c.actor.actor_id)}


func load_dict(d: Dictionary) -> void:
	var by_id: Dictionary = {}
	for c in all:
		by_id[c.actor.actor_id] = c
	for e in d.get("all", []):
		if by_id.has(e["id"]):
			by_id[e["id"]].load_dict(e)
	order = []
	for id in d.get("order", []):
		if by_id.has(id):
			order.append(by_id[id])
	for c in all:
		if not order.has(c):
			order.append(c)
	fleeing = {}
	for id in d.get("fleeing", []):
		if by_id.has(id):
			fleeing[by_id[id]] = true
	round_n = int(d.get("round", 1))
	turn_i = int(d.get("turn", 0))
	killed = int(d.get("killed", 0))
	killed_levels = int(d.get("killed_levels", killed))
	log_lines = d.get("log", []).duplicate()

extends RefCounted
## Участник боя: общий Actor + лист D&D (7 характеристик, HP, AC, оружие, способности, состояния)
## и экономия хода (движение, действие, бонусное действие, реакция, свободное взаимодействие).
## Лист строится из Actor (герой, НПС) или из шаблона BattleCreature (враги, питомцы).

const Data := preload("res://battle/battle_data.gd")
const STATS: Array = ["str", "dex", "con", "int", "wis", "cha", "lck"]
static var STAT_NAMES: Dictionary = {"str": I18n.t("СИЛ"), "dex": I18n.t("ЛОВ"), "con": I18n.t("ВЫН"), "int": I18n.t("ИНТ"), "wis": I18n.t("МДР"), "cha": I18n.t("ХАР"), "lck": I18n.t("УДЧ")}
# Характеристики Амбера -> D&D (Восприятие — отдельно, в инициативу и внимательность)
const FROM_AMBER: Dictionary = {"str": "str", "dex": "agi", "con": "end", "int": "int", "wis": "wis", "cha": "cha"}

var actor: Actor
var team: int = 0
var creature: BattleCreature
var title: String = ""
var is_hero: bool = false
var is_pet: bool = false
var human: bool = true
var controlled: bool = false        # ходит игрок; иначе ИИ
var ai: String = "melee"
var morale: float = 0.5
var level: int = 1
var scores: Dictionary = {}
var per_bonus: int = 0
var max_hp: int = 1
var hp: int = 1
var armor: BattleArmor
var weapons: Array = []
var wi: int = 0
var abilities: Array = []
var uses: Dictionary = {}
var ammo: Dictionary = {}
var potions: int = 0
var effects: Array = []             # {id, res: BattleEffect, left (раундов, −1 — пока не снимут)}
var resist: Dictionary = {}
var vulnerable: Dictionary = {}
var immune: PackedStringArray = []
var save_profs: PackedStringArray = []
var stealth_prof: bool = false
var perception_prof: bool = false
var speed_ft: int = 30
var cell: Vector2i = Vector2i.ZERO
var initiative: int = 0
var init_tiebreak: float = 0.0
# Ход
var move_left: int = 0
var has_action: bool = true
var has_bonus: bool = true
var has_reaction: bool = true
var free_used: bool = false
var disengaged: bool = false
var readied: Dictionary = {}
var helped_by: int = -1             # команда, чья помощь даёт преимущество на следующую атаку по этому
# Состояние
var down: bool = false              # без сознания (стабилен)
var dead: bool = false
var fled: bool = false
var hp_at_start: int = 0
var new_traumas: Array = []


func build_from_actor(a: Actor, t: int, cfg: BattleConfig, loadout: Dictionary) -> void:
	actor = a
	team = t
	title = a.display_name
	for k in FROM_AMBER:
		scores[k] = int(a.stats.get(FROM_AMBER[k], 4)) + cfg.stat_offset
	scores["lck"] = int(a.stat("luck")) + cfg.luck_offset
	per_bonus = int(floor((float(a.stats.get("per", 4)) - 4.0) / float(maxi(cfg.per_initiative_div, 1))))
	level = cfg.party_level
	var die_hp: int = int(loadout.get("hp_die", 8))
	max_hp = maxi(1, die_hp + mod("con") + (level - 1) * (die_hp / 2 + 1 + mod("con")))
	armor = Data.armor(String(loadout.get("armor", "none")))
	for w in loadout.get("weapons", ["fists"]):
		_add_weapon(String(w))
	for ab in loadout.get("abilities", []):
		var r: BattleAbility = Data.ability(String(ab))
		if r != null:
			abilities.append(r)
	save_profs = PackedStringArray(loadout.get("save_profs", []))
	potions = int(loadout.get("potions", 0))
	perception_prof = true
	_from_actor_health(cfg)


func build_from_creature(c: BattleCreature, a: Actor, t: int, cfg: BattleConfig, roller) -> void:
	creature = c
	actor = a
	team = t
	title = c.title
	human = c.human
	is_pet = c.pet
	ai = c.ai
	morale = c.morale
	level = c.level
	for k in STATS:
		scores[k] = int(c.scores.get(k, 10))
	# Лист и Actor согласованы: характеристики Амбера = D&D − сдвиг (для сохранения через Actor.to_dict)
	for k in FROM_AMBER:
		a.stats[FROM_AMBER[k]] = int(scores[k]) - cfg.stat_offset
	var r: Dictionary = roller.roll(c.hp_dice, {"extra_mod": mod("con") * level, "label": "HP " + c.title, "silent": true})
	max_hp = maxi(1, int(r["total"]))
	armor = Data.armor(c.armor) if c.armor != "" else null
	for w in c.weapons:
		_add_weapon(String(w))
	for ab in c.abilities:
		var res: BattleAbility = Data.ability(String(ab))
		if res != null:
			abilities.append(res)
	resist = c.resist.duplicate()
	vulnerable = c.vulnerable.duplicate()
	immune = c.immune
	save_profs = c.save_profs
	stealth_prof = c.stealth_prof
	perception_prof = c.perception_prof
	speed_ft = c.speed_ft
	_from_actor_health(cfg)


# Раненый персонаж входит в бой раненым: HP = максимум × здоровье Actor / 100
func _from_actor_health(cfg: BattleConfig) -> void:
	var frac: float = clampf(float(actor.res["health"]) / maxf(actor.max_of("health"), 1.0), 0.0, 1.0)
	hp = maxi(1, int(round(max_hp * frac)))
	hp_at_start = hp


func set_weapons(ids: Array) -> void:
	weapons = []
	ammo = {}
	wi = 0
	for id in ids:
		_add_weapon(String(id))
	if weapons.is_empty():
		_add_weapon("fists")


func _add_weapon(id: String) -> void:
	var w: BattleWeapon = Data.weapon(id)
	if w == null:
		return
	weapons.append(w)
	if w.ammo > 0:
		ammo[w.id] = w.ammo


# Сохранить итог боя в Actor: здоровье по доле HP, смерть
func write_back() -> void:
	if dead:
		return
	var frac: float = float(hp) / float(max_hp)
	actor.res["health"] = clampf(frac * actor.max_of("health"), 1.0, actor.max_of("health"))


# =====================================================================
static func ability_mod(score: int) -> int:
	return int(floor((score - 10) / 2.0))


func mod(stat: String) -> int:
	return ability_mod(int(scores.get(stat, 10)))


static func prof_for_level(lv: int) -> int:
	return 2 + int(floor((clampi(lv, 1, 20) - 1) / 4.0))


func prof() -> int:
	return prof_for_level(level)


func weapon() -> BattleWeapon:
	if weapons.is_empty():
		var f: BattleWeapon = Data.weapon("fists")
		return f if f != null else BattleWeapon.new()
	return weapons[clampi(wi, 0, weapons.size() - 1)]


func melee_index() -> int:
	for i in weapons.size():
		if not weapons[i].ranged:
			return i
	return -1


func ranged_index() -> int:
	for i in weapons.size():
		if weapons[i].ranged and (weapons[i].ammo == 0 or int(ammo.get(weapons[i].id, 0)) > 0):
			return i
	return -1


func reach_ft() -> int:
	var w: BattleWeapon = weapon()
	return w.range_ft if w.ranged else w.reach_ft


func can_use(ab: BattleAbility) -> bool:
	if ab.uses_per_battle > 0 and int(uses.get(ab.id, 0)) >= ab.uses_per_battle:
		return false
	match ab.cost:
		"bonus":
			return has_bonus
		"reaction":
			return has_reaction
	return has_action


# =====================================================================
# СОСТОЯНИЯ
# =====================================================================
func has_effect(id: String) -> bool:
	for e in effects:
		if e["id"] == id:
			return true
	return false


func add_effect(id: String, rounds_override: int = 0) -> bool:
	var r: BattleEffect = Data.effect(id)
	if r == null:
		return false
	var left: int = rounds_override if rounds_override != 0 else r.duration_rounds
	for e in effects:
		if e["id"] == id:
			e["left"] = maxi(int(e["left"]), left) if left >= 0 else -1
			return true
	effects.append({"id": id, "res": r, "left": left})
	return true


func remove_effect(id: String) -> void:
	effects = effects.filter(func(e): return e["id"] != id)


func flag(prop: String) -> bool:
	for e in effects:
		if bool(e["res"].get(prop)):
			return true
	return false


func incapacitated() -> bool:
	return down or dead or flag("incapacitated")


func active() -> bool:
	return not dead and not fled


func standing() -> bool:
	return active() and not down


func speed() -> int:
	var m: float = 1.0
	for e in effects:
		m *= float(e["res"].speed_mult)
	return int(floor(speed_ft * m / 5.0)) * 5


func save_flag(list_prop: String, stat: String) -> bool:
	for e in effects:
		if (e["res"].get(list_prop) as PackedStringArray).has(stat):
			return true
	return false


func effect_resist(dtype: String) -> float:
	var s: float = 0.0
	for e in effects:
		s = maxf(s, float(e["res"].resist.get(dtype, 0.0)))
	return s


func attack_penalty() -> int:
	var p: int = 0
	for e in effects:
		p += int(e["res"].attack_penalty)
	return p


func start_turn_reset() -> void:
	move_left = speed()
	has_action = true
	has_bonus = true
	has_reaction = true
	free_used = false
	disengaged = false
	readied = {}


func to_dict() -> Dictionary:
	return {"id": actor.actor_id, "weapons": weapons.map(func(w): return w.id), "hp": hp, "max_hp": max_hp, "cell": cell, "wi": wi, "uses": uses.duplicate(),
		"ammo": ammo.duplicate(), "potions": potions, "effects": effects.map(func(e): return {"id": e["id"], "left": e["left"]}),
		"init": initiative, "down": down, "dead": dead, "fled": fled, "move_left": move_left, "action": has_action,
		"bonus": has_bonus, "reaction": has_reaction, "free": free_used, "disengaged": disengaged, "controlled": controlled}


func load_dict(d: Dictionary) -> void:
	if d.has("weapons"):
		set_weapons(d["weapons"])
	hp = int(d.get("hp", hp))
	max_hp = int(d.get("max_hp", max_hp))
	cell = d.get("cell", cell)
	wi = int(d.get("wi", 0))
	uses = d.get("uses", {}).duplicate()
	ammo = d.get("ammo", ammo).duplicate()
	potions = int(d.get("potions", potions))
	effects = []
	for e in d.get("effects", []):
		# Эффекта могло не стать в data/battle/effects (переименовали) — пропускаем, не трогая чужие
		if add_effect(String(e["id"])):
			for x in effects:
				if x["id"] == String(e["id"]):
					x["left"] = int(e.get("left", x["left"]))
	initiative = int(d.get("init", initiative))
	down = bool(d.get("down", false))
	dead = bool(d.get("dead", false))
	fled = bool(d.get("fled", false))
	move_left = int(d.get("move_left", move_left))
	has_action = bool(d.get("action", true))
	has_bonus = bool(d.get("bonus", true))
	has_reaction = bool(d.get("reaction", true))
	free_used = bool(d.get("free", false))
	disengaged = bool(d.get("disengaged", false))
	controlled = bool(d.get("controlled", controlled))

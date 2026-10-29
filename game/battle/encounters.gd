extends RefCounted
## Хто нападає й коли. Напад перевіряється на кожен пройдений кілометр (подія km_passed пакета),
## вороги збираються за місцевістю із шаблонів res://data/battle/creatures. Вороги — звичайні Actor;
## шаблон зашито в actor_id: "foe:<шаблон>:<n>", щоб пережити збереження через Actor.to_dict.
## Числа [Q19: перевіряє tests/balance_checks.gd].

const Data := preload("res://battle/battle_data.gd")
const Sheet := preload("res://characters/sheet.gd")
const TERRAINS: Array = ["", "water", "coast", "forest", "wasteland", "swamp", "mountains", "rad_forest", "rad_wasteland", "rad_swamp"]
const PER_KM: float = 0.06
const NIGHT_MULT: float = 1.5
const KM_MULT: Dictionary = {"rad_forest": 1.6, "rad_wasteland": 1.6, "rad_swamp": 1.6, "coast": 0.6}
const BY_TERRAIN: Dictionary = {
	"coast": {"bandits": 3, "boar": 1},
	"forest": {"wolves": 3, "bandits": 2, "boar": 2},
	"wasteland": {"bandits": 4, "wolves": 1},
	"swamp": {"boar": 2, "wolves": 1, "bandits": 1},
	"mountains": {"bandits": 2, "wolves": 2},
	"rad_forest": {"hounds": 3, "wolves": 1},
	"rad_wasteland": {"hounds": 3, "bandits": 1},
	"rad_swamp": {"hounds": 3},
}
## Q30 (Huzzah 2026-10-27, варіант B): поки місто, що росте, на етапі «Форт», у STARTER_KM від нього
## замість зграї виходить один обірванець із палицею (Q19, bandit_ragged) — перший бій із ножем під силу. Прапорець starter ставить Worlds._start_battle_now
const STARTER_KM: float = 8.0
const STARTER_GROUPS: Array = ["bandits", "gang"]
## [шаблон, від, до]
const GROUPS: Dictionary = {
	"bandits": [["bandit", 1, 2], ["bandit_archer", 0, 1], ["bandit_chief", 0, 0]],
	"gang": [["bandit_chief", 1, 1], ["bandit", 1, 2], ["bandit_archer", 1, 1]],
	"wolves": [["wolf", 2, 3]],
	"boar": [["boar", 1, 1]],
	"hounds": [["rad_hound", 1, 2]],
}


static func terrain_key(biome: int) -> String:
	return TERRAINS[biome] if biome > 0 and biome < TERRAINS.size() else "wasteland"


static func kind_of(a: Actor) -> String:
	var p: PackedStringArray = a.actor_id.split(":")
	return p[1] if p.size() >= 3 and (p[0] == "foe" or p[0] == "pet") else ""


static func chance_per_km(env: Dictionary) -> float:
	var ter: String = terrain_key(int(env.get("biome", 4)))
	if ter == "water" or not BY_TERRAIN.has(ter):
		return 0.0
	var p: float = PER_KM * float(KM_MULT.get(ter, 1.0))
	if bool(env.get("night", false)):
		p *= NIGHT_MULT
	return p


static func roll_on_km(hero: Actor, env: Dictionary, rng: RandomNumberGenerator = null) -> bool:
	if hero == null or not hero.alive:
		return false
	var r: float = rng.randf() if rng != null else randf()
	# дары «Странник» — реже нападают, «Друг зверей» — реже звери (по их доле в местности)
	var w: Dictionary = BY_TERRAIN.get(terrain_key(int(env.get("biome", 4))), {})
	var total: float = 0.0
	var beasts: float = 0.0
	for k in w:
		total += float(w[k])
		if k in ["wolves", "boar", "hounds"]:
			beasts += float(w[k])
	var m: float = 1.0 + Sheet.eff(hero, "encounter") + Sheet.eff(hero, "encounter_beast") * (beasts / total if total > 0.0 else 0.0)
	return r < chance_per_km(env) * maxf(m, 0.0) * stealth_mult(concealment(hero, env))


# =====================================================================
# МАСКУВАННЯ (пункт 17 Huzzah 2026-10-29): вороги нападають випадково, і що краще герой ховається,
# то рідше. 0 — видно здалеку, 0,9 — майже непомітний. Середній герой удень у пустці ≈ CONCEAL_REF,
# для нього множник 1 (баланс walk_min_per_fight не зсувається). Числа [ВРЕМЕННО]
# =====================================================================
const CONCEAL_REF: float = 0.2
const COVER: Dictionary = {"forest": 0.12, "rad_forest": 0.12, "swamp": 0.08, "rad_swamp": 0.08, "mountains": 0.06, "coast": -0.04, "wasteland": 0.0, "rad_wasteland": 0.0}
## Напад, коли герой стоїть, спить або шукає (на годину гри, до множників місцевості й ночі)
const PER_HOUR: float = 0.02


## Маскування героя в середовищі env (біом, ніч); ctx: {running, sleeping} — що він зараз робить
static func concealment(hero: Actor, env: Dictionary, ctx: Dictionary = {}) -> float:
	if hero == null:
		return CONCEAL_REF
	var c: float = CONCEAL_REF
	c += 0.006 * (float(hero.skill("sneak")) - 20.0)   # Скрытность (у ній уже є Ловкість)
	c += 0.01 * (hero.stat("per") - 5.0)               # Чутьё: помічає ворога першим
	c += float(COVER.get(terrain_key(int(env.get("biome", 4))), 0.0))
	if bool(env.get("night", false)):
		c += 0.1
	if hero.mount == "horse":
		c -= 0.08
	elif hero.mount == "cart":
		c -= 0.15
	if bool(ctx.get("running", false)):
		c -= 0.1
	if bool(ctx.get("sleeping", hero.sleeping)):
		c -= 0.05   # уві сні не чути, хто підходить
	c -= 0.004 * maxf(hero.carried_kg - 15.0, 0.0)     # брязкіт важкої поклажі
	if Sheet.has(hero, "ghost"):
		c += 0.1
	c *= 0.5 + 0.5 * hero.mult("sneak")                # риси «Тихий» / «Гучний»
	return clampf(c, 0.0, 0.9)


## Множник шансу нападу за маскуванням: 1,6 відкрито … 1 середній … 0,25 добре сховався
static func stealth_mult(c: float) -> float:
	return clampf(1.0 - 3.0 * (c - CONCEAL_REF), 0.25, 1.6)


## Слово для інтерфейсу
static func concealment_word(c: float) -> String:
	if c < 0.1:
		return I18n.t("на виду")
	if c < 0.25:
		return I18n.t("заметен")
	if c < 0.4:
		return I18n.t("в тени")
	if c < 0.6:
		return I18n.t("укрыт")
	return I18n.t("невидим")


## Шанс нападу за hours годин гри, поки герой стоїть, спить або шукає на місці
static func chance_for_hours(hero: Actor, env: Dictionary, hours: float) -> float:
	var ter: String = terrain_key(int(env.get("biome", 4)))
	if ter == "water" or not BY_TERRAIN.has(ter) or hours <= 0.0:
		return 0.0
	var p: float = PER_HOUR * float(KM_MULT.get(ter, 1.0))
	if bool(env.get("night", false)):
		p *= NIGHT_MULT
	p *= stealth_mult(concealment(hero, env)) * maxf(1.0 + Sheet.eff(hero, "encounter"), 0.0)
	return 1.0 - pow(1.0 - clampf(p, 0.0, 0.95), hours)


static func roll_for_hours(hero: Actor, env: Dictionary, hours: float, rng: RandomNumberGenerator = null) -> bool:
	if hero == null or not hero.alive:
		return false
	var r: float = rng.randf() if rng != null else randf()
	return r < chance_for_hours(hero, env, hours)


static func pick_group(terrain: String, rng: RandomNumberGenerator) -> String:
	var w: Dictionary = BY_TERRAIN.get(terrain, {"bandits": 1})
	var total: float = 0.0
	for k in w:
		total += float(w[k])
	var r: float = rng.randf() * total
	for k in w:
		r -= float(w[k])
		if r <= 0.0:
			return k
	return w.keys()[0]


static func make_enemy(kind: String, n: int, rng: RandomNumberGenerator) -> Actor:
	var cr: BattleCreature = Data.creature(kind)
	return Actor.new("foe:%s:%d" % [kind, n], cr.title if cr != null else kind, true, rng.randi())


static func make_enemies(req: Dictionary, rng: RandomNumberGenerator) -> Array:
	var group: String = String(req.get("group", ""))
	if group == "" or not GROUPS.has(group):
		group = pick_group(String(req.get("terrain", "wasteland")), rng)
	var out: Array = []
	var n: int = 0
	if bool(req.get("starter", false)) and group in STARTER_GROUPS:
		req["group"] = group
		return [make_enemy("bandit_ragged", 0, rng)]
	for m in GROUPS[group]:
		for i in rng.randi_range(int(m[1]), int(m[2])):
			out.append(make_enemy(String(m[0]), n, rng))
			n += 1
	# не більше, ніж під силу стороні героя: союзників × cap + extra [Q19: перевіряє tests/balance_checks.gd]
	var allies: int = req.get("allies", []).size()
	if allies > 0 and not bool(req.get("no_cap", false)):
		var cfg: BattleConfig = Data.config()
		var cap: int = maxi(1, int(floor(allies * cfg.encounter_cap_per_ally)) + cfg.encounter_cap_extra)
		while out.size() > cap:
			out.remove_at(rng.randi() % out.size())
	if out.is_empty():
		out.append(make_enemy("bandit", 0, rng))
	req["group"] = group
	return out

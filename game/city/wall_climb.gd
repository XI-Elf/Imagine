extends RefCounted
## Перелізти міську стіну зсередини (пункт 14, Huzzah 2026-10-29, відповідь 5 — так): уночі брама зачинена,
## але біля стіни (місця breaches у плані міста) герой може спробувати перелізти. Шанс — Сила, Ловкість, Скрытность,
## мотузка в сумці допомагає; груз, травми рук і ніг, втома заважають. Невдача: можна зірватися (травма),
## а якщо поруч стражник або просто не пощастило — помітили, штраф. Числа [ВРЕМЕННО].

const Trade := preload("res://city/trade.gd")

const BASE: float = 0.25
const PER_STR: float = 0.04
const PER_AGI: float = 0.04
const PER_SNEAK: float = 0.005
const ROPE: float = 0.15
const FREE_KG: float = 15.0
const PER_KG: float = 0.01
const HURT: Array = ["luxation_arm", "broken_arm", "broken_leg"]
const STAMINA: float = 30.0
const MINUTES: float = 15.0
const FALL_CHANCE: float = 0.35
const FALL_CONDITION: String = "luxation_arm"
const SEEN_BASE: float = 0.25
const SEEN_GUARD_M: float = 25.0      # стражник ближче — помітить майже напевно
const SEEN_GUARD: float = 0.8


static func chance(a: Actor, bag: Dictionary) -> float:
	if not a.can_move() or a.mount != "":
		return 0.0
	var c: float = BASE
	c += PER_STR * (a.stat("str") - 5.0)
	c += PER_AGI * (a.stat("agi") - 5.0)
	c += PER_SNEAK * (float(a.skill("sneak")) - 20.0)
	if Trade.count(bag, "rope") > 0:
		c += ROPE
	c -= PER_KG * maxf(Trade.weight(bag) - FREE_KG, 0.0)
	for id in HURT:
		if a.has_condition(id):
			c *= 0.3
			break
	if a.res["stamina"] < STAMINA:
		c *= 0.5
	return clampf(c, 0.05, 0.9)


## Шанс, що помітять у разі невдачі; guard_m — відстань до найближчого стражника, що не спить
static func seen_chance(a: Actor, guard_m: float) -> float:
	if guard_m <= SEEN_GUARD_M:
		return SEEN_GUARD
	return clampf(SEEN_BASE - 0.03 * (a.stat("agi") - 5.0), 0.05, 0.9)


## Спроба: "over" — переліз, "fall" — зірвався (травма), "seen" — помітили, "fail" — не вийшло
static func attempt(a: Actor, bag: Dictionary, guard_m: float, rng: RandomNumberGenerator) -> String:
	var c: float = chance(a, bag)
	a.add_res("stamina", -STAMINA)
	if rng.randf() < c:
		a.add_xp("sneak", 2.0)
		return "over"
	if rng.randf() < seen_chance(a, guard_m):
		return "seen"
	if rng.randf() < FALL_CHANCE:
		a.add_condition(FALL_CONDITION)
		return "fall"
	return "fail"

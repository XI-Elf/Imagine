class_name Actor
extends RefCounted
## Общий персонаж для игрока и НПС: характеристики и навыки (characters/sheet.gd), ресурсы пака (здоровье, голод, жажда,
## энергия, проклятье, запас сил), травмы, болезни, полезные эффекты, навыки, движение по местности.
## Правила одни для всех: игрок и НПС различаются только тем, кто решает, куда идти (actor_body.gd).
## Нужды идут в игровом времени (tick), запас сил и шаги — в реальном (travel_speed, exert):
## так персонаж проходит одинаковое расстояние при любой скорости часов (масштаб ×8, решение автора).
## Числа — в res://data/characters/ (actor_rules.gd).

signal health_changed(value: float)
signal condition_added(id: String)
signal condition_removed(id: String)
signal skill_leveled_up(skill: String, level: int)
signal leveled_up(level: int)
signal died(cause: String)
signal km_passed(total_km: int)

const R := preload("res://characters/actor_rules.gd")
const S := preload("res://characters/sheet.gd")
# Семь характеристик: Сила, Восприятие, Выносливость, Харизма, Интеллект, Ловкость, Удача
const STATS: Array = ["str", "per", "end", "cha", "int", "agi", "luck"]
const RESOURCES: Array = ["health", "hunger", "thirst", "energy", "radiation", "stamina"]
# Длинный шаг времени режется на куски, чтобы пороги не перескакивались
const SUBSTEP_S: float = 600.0
const OPEN_WOUNDS: Array = ["bullet_wound", "laceration"]
static var DEATH_CAUSES: Dictionary = {
	"thirst": I18n.t("жажда"), "hunger": I18n.t("голод"), "radiation": I18n.t("воздействие проклятья"), "drowning": I18n.t("утонул"),
	"wounds": I18n.t("раны"), "disease": I18n.t("болезнь"), "other": I18n.t("неизвестно"),
}

var actor_id: String = ""
var display_name: String = ""
var is_npc: bool = false
var stats: Dictionary = {}          # характеристики: база (выбор при создании), 1–10; черты и перки — в sheet.gd
var res: Dictionary = {}            # ресурс -> значение
var conditions: Array = []          # {id, age_h, left_h (0 — пока не вылечат), stage}
var buffs: Array = []               # {id, left_h}
var skills: Dictionary = {}         # навык -> {pts (куплено очками, %), bonus (уроки, прошлое, %), spent}
var tags: Array = []                # отмеченные навыки (3)
var quirks: Array = []              # особенности, не больше двух
var perks: Dictionary = {}          # перк -> ранг
var level: int = 1
var xp: float = 0.0
var skill_points: int = 0           # нераспределённые очки навыков
var perk_picks: int = 0             # сколько перков можно выбрать
var mutate_left: int = 0            # перк «Мутация»: смен черт
var tag_left: int = 0               # перк «Ещё один конёк»: отметить навык
var alive: bool = true
var death_cause: String = ""
var sleeping: bool = false
var sleep_h: float = 0.0
var wet_h: float = 0.0              # сколько игровых часов ещё сохнуть
var moving: bool = false            # шёл ли последние секунды (трата энергии в tick)
var carried_kg: float = 0.0
var pack_kg: float = 0.0            # сколько кг везут лошадь и повозка (characters/transport.gd), не сохраняется
var mount: String = ""              # "" пешком, "horse", "cart" (movement.json пака)
var distance_m: float = 0.0
var traits: Array = []              # черты характера (creation.json): постоянные эффекты, как у состояний
var profile: Dictionary = {}        # кто это: пол, возраст, происхождение, профессия, мировоззрение, биография (hero_profile.gd)
var last_env: Dictionary = {}
var rng := RandomNumberGenerator.new()


func _init(id: String = "", name: String = "", npc: bool = false, seed_value: int = 0) -> void:
	actor_id = id
	display_name = name
	is_npc = npc
	rng.seed = seed_value if seed_value != 0 else hash(id + name)
	for s in STATS:
		stats[s] = int(S.data().get("base", 5))
	var ch: Dictionary = R.characteristics()
	for r in RESOURCES:
		res[r] = float(ch.get(r, {}).get("base_max", 100.0))
	res["radiation"] = 0.0
	res["hunger"] = 80.0
	res["thirst"] = 80.0
	skills = S.empty_skills()


# =====================================================================
# ХАРАКТЕРИСТИКИ
# =====================================================================
# Действующая характеристика 1–10 (с чертами и перками). Удача теперь у всех
func stat(s: String) -> float:
	return float(S.stat_value(self, s))


func set_stat(s: String, v: int) -> void:
	stats[s] = clampi(v, int(S.data().get("min", 1)), int(S.data().get("max", 10)))


# Сколько очков сверх средних 5
func _over(s: String) -> float:
	return stat(s) - float(S.data().get("base", 5))


# =====================================================================
# РЕСУРСЫ И ЭФФЕКТЫ
# =====================================================================
func max_of(r: String) -> float:
	var m: float = float(R.characteristics().get(r, {}).get("base_max", 100.0))
	if r == "energy":
		m += _sum("energy_max_bonus")
	return m


func set_res(r: String, v: float) -> void:
	var old: float = float(res.get(r, 0.0))
	res[r] = clampf(v, 0.0, max_of(r))
	if r == "health" and not is_equal_approx(old, res[r]):
		health_changed.emit(res[r])


func add_res(r: String, d: float) -> void:
	set_res(r, float(res.get(r, 0.0)) + d)


func _effects_of(entry: Dictionary, is_buff: bool) -> Dictionary:
	if is_buff:
		return R.buffs().get(entry["id"], {}).get("effects", {})
	return R.condition(entry["id"]).get("effects", {})


# Сумма эффекта по всем состояниям и полезным эффектам. Лучевая болезнь сильнее на поздних стадиях
func _sum(key: String) -> float:
	var total: float = 0.0
	var mults: Array = R.section("radiation").get("stage_effect_mult", [1.0])
	for c in conditions:
		var e: Dictionary = _effects_of(c, false)
		if e.has(key) and not (e[key] is bool):
			var k: float = 1.0
			if c["id"] == "radiation_sickness":
				k = float(mults[clampi(int(c.get("stage", 1)), 0, mults.size() - 1)])
			total += float(e[key]) * k
	for b in buffs:
		var e: Dictionary = _effects_of(b, true)
		if e.has(key) and not (e[key] is bool):
			total += float(e[key])
	for t in traits:
		var e: Dictionary = R.trait_def(t).get("effects", {})
		if e.has(key):
			total += float(e[key])
	for e in S.effect_dicts(self):
		if e.has(key) and not (e[key] is bool):
			total += float(e[key])
	return total


func _flag(key: String) -> bool:
	for b in buffs:
		if bool(_effects_of(b, true).get(key, false)):
			return true
	return false


# Множитель из долей: speed -0.4 и move_speed +0.1 дают ×0,6 × ×1,1
func mult(key: String) -> float:
	var m: float = 1.0
	for c in conditions:
		var e: Dictionary = _effects_of(c, false)
		if e.has(key):
			m *= 1.0 + float(e[key])
	for b in buffs:
		var e: Dictionary = _effects_of(b, true)
		if e.has(key):
			m *= 1.0 + float(e[key])
	for t in traits:
		var e: Dictionary = R.trait_def(t).get("effects", {})
		if e.has(key):
			m *= 1.0 + float(e[key])
	# особенности и перки: общие ключи пака (loot, sneak, move_speed, fall_chance, sleep_energy…)
	for e in S.effect_dicts(self):
		if e.has(key):
			m *= 1.0 + float(e[key])
	return maxf(m, 0.05)


func is_bleeding() -> bool:
	return _sum("bleeding") > 0.0


# =====================================================================
# СОСТОЯНИЯ: травмы, болезни, полезные эффекты
# =====================================================================
func has_condition(id: String) -> bool:
	return _cond_index(id) >= 0


func _cond_index(id: String) -> int:
	for i in conditions.size():
		if conditions[i]["id"] == id:
			return i
	return -1


func add_condition(id: String) -> bool:
	if R.condition(id).is_empty() or has_condition(id) or not alive:
		return false
	var left: float = float(R.section("durations_h").get(id, 0.0))
	conditions.append({"id": id, "age_h": 0.0, "left_h": left, "stage": 1})
	condition_added.emit(id)
	return true


func remove_condition(id: String) -> void:
	var i: int = _cond_index(id)
	if i >= 0:
		conditions.remove_at(i)
		condition_removed.emit(id)


# Шанс заболеть с учётом Выносливости и Удачи; p — вероятность за раз
func try_catch(id: String, p: float) -> bool:
	if has_condition(id):
		return false
	# защита от яда 5×ВЫН % — половина её режет шанс хвори; Удача сверх 5 тоже
	p *= clampf(1.0 - float(S.poison_resist(self)) / 200.0, 0.1, 2.0)
	p *= clampf(1.0 - float(R.section("stats").get("luck_chance_per_pt", 0.0)) * _over("luck"), 0.5, 1.5)
	p *= mult("disease_chance")
	if rng.randf() < p:
		return add_condition(id)
	return false


func has_buff(id: String) -> bool:
	for b in buffs:
		if b["id"] == id:
			return true
	return false


# Полезный эффект: мгновенная часть (сытость, энергия) сразу, остальное на срок. Повтор продлевает срок
func add_buff(id: String) -> bool:
	var d: Dictionary = R.buffs().get(id, {})
	if d.is_empty() or not alive:
		return false
	var e: Dictionary = d.get("effects", {})
	add_res("hunger", float(e.get("hunger_restore", 0.0)))
	add_res("energy", float(e.get("energy_restore", 0.0)))
	# черты «Тяга к снадобьям» / «Стойкость к снадобьям», перк «Дитя цветов»
	var hours: float = float(d.get("duration_hours", 1.0)) * maxf(1.0 + S.eff(self, "buff_time"), 0.1)
	for b in buffs:
		if b["id"] == id:
			b["left_h"] = hours
			return true
	buffs.append({"id": id, "left_h": hours})
	return true


# =====================================================================
# ИГРОВОЕ ВРЕМЯ: нужды, здоровье, проклятье, болезни
# =====================================================================
## env: {biome: int, water: float, temp_c: float, rain: float 0..1, night: bool} — см. world_env.gd
func tick(dt_s: float, env: Dictionary) -> void:
	if not alive or dt_s <= 0.0:
		return
	last_env = env
	var left: float = dt_s
	while left > 0.0 and alive:
		var step: float = minf(left, SUBSTEP_S)
		left -= step
		_step(step / 3600.0, env)


func feels_temp(env: Dictionary) -> float:
	var t: float = float(env.get("temp_c", R.num("climate", "mean_c", 12.0)))
	if wet_h > 0.0:
		t += R.num("needs", "wet_feels", -4.0)
	return t


func _step(h: float, env: Dictionary) -> void:
	var ch: Dictionary = R.characteristics()
	var ter: Dictionary = R.terrain(int(env.get("biome", 4)))
	var feels: float = feels_temp(env)
	var hot: bool = feels >= R.num("climate", "heat_c", 35.0) + _sum("heat_resist_c")
	var cold: bool = feels <= R.num("climate", "cold_c", 0.0) - _sum("cold_resist_c")

	# Голод и жажда
	var hunger_rate: float = float(ch["hunger"].get("decay_per_hour", 1.2)) + 100.0 * (_sum("hunger") + _sum("emaciation"))
	var thirst_rate: float = float(ch["thirst"].get("decay_per_hour", 1.5)) + 100.0 * _sum("thirst")
	if hot:
		thirst_rate *= R.num("climate", "heat_thirst_mult", 1.6)
	add_res("hunger", -hunger_rate * h)
	add_res("thirst", -thirst_rate * h)

	# Энергия: сон восстанавливает, ходьба по тяжёлой местности и холод тратят больше
	var pain: float = 0.0 if _flag("ignore_pain") else _sum("pain")
	var extra: float = 100.0 * (_sum("exhaustion") + _sum("energy_decay") + 0.5 * pain)
	if sleeping:
		sleep_h += h
		add_res("energy", (R.num("needs", "sleep_energy_h", 12.5) * mult("sleep_energy") - extra) * h)
	else:
		var rate: float = float(ch["energy"].get("decay_per_hour", 0.8))
		if moving:
			rate *= R.num("movement", "moving_energy_mult", 1.5) * float(ter.get("energy", 1.0))
			if mount != "":
				rate *= float(R.transport().get("riding_energy_mult", 1.0))
		if cold:
			rate *= R.num("climate", "cold_energy_mult", 1.5)
		add_res("energy", -(rate + extra) * h)

	# Здоровье
	var dmg: float = 100.0 * (_sum("health_decay") + _sum("bleeding") + _sum("poison"))
	if res["hunger"] <= 0.0:
		dmg += R.num("needs", "hunger_zero_health_h", 2.0)
	if res["thirst"] <= 0.0:
		dmg += R.num("needs", "thirst_zero_health_h", 5.0)
		add_res("energy", -R.num("needs", "thirst_zero_energy_h", 2.0) * h)
	var regen: float = _sum("health_regen")
	if res["hunger"] > 0.0 and res["thirst"] > 0.0 and not is_bleeding():
		# Заживление (ВЫН/3, мин. 1): 1 — как было, каждая единица сверху +50 %
		regen += float(ch["health"].get("regen_per_hour", 0.5)) * (0.5 + 0.5 * float(S.healing_rate(self)))
	add_res("health", (regen - dmg) * h)

	# Проклятье: копится в проклятых биомах, само уходит только в чистых
	var rch: Dictionary = ch["radiation"]
	var gain: float = float(ter.get("radiation_h", 0.0)) * (1.0 - radiation_resist())
	if gain > 0.0:
		add_res("radiation", gain * h)
	elif bool(R.section("radiation").get("clean_decay_only", true)):
		add_res("radiation", -float(rch.get("decay_per_hour", 0.1)) * h)
	add_res("radiation", -_sum("radiation_decay") * h)
	_update_radiation_sickness()

	# Мокрый: болото, вода, ливень; потом сохнет
	if bool(ter.get("wet", false)) or bool(ter.get("swim", false)) or float(env.get("rain", 0.0)) > 0.5:
		wet_h = R.num("needs", "wet_dry_h", 2.0)
	else:
		wet_h = maxf(wet_h - h, 0.0)

	# Сроки состояний и эффектов
	for c in conditions.duplicate():
		c["age_h"] = float(c["age_h"]) + h
		if float(c["left_h"]) > 0.0:
			c["left_h"] = float(c["left_h"]) - h
			if float(c["left_h"]) <= 0.0:
				remove_condition(c["id"])
	for b in buffs.duplicate():
		b["left_h"] = float(b["left_h"]) - h
		if float(b["left_h"]) <= 0.0:
			buffs.erase(b)

	# Причины болезней
	var cz: Dictionary = R.section("causes")
	if hot and (res["health"] < 50.0 or res["thirst"] < 20.0):
		try_catch("desert_fever", float(cz.get("desert_fever_h", 0.0)) * h)
	if cold and res["hunger"] < 20.0:
		try_catch("cadaver_shivers", float(cz.get("cadaver_shivers_h", 0.0)) * h)
	for c in conditions:
		if OPEN_WOUNDS.has(c["id"]) and float(c["age_h"]) > float(cz.get("wound_infect_after_h", 12.0)):
			try_catch("blood_poisoning", float(cz.get("blood_poisoning_h", 0.0)) * h)
			break
	var catch: Dictionary = ter.get("catch", {})
	for id in catch:
		try_catch(id, float(catch[id]) * h * maxf(1.0 - 0.05 * skill_level("survival"), 0.1))

	if res["health"] <= 0.0:
		die(_guess_cause())


func _update_radiation_sickness() -> void:
	var th: Array = R.characteristics()["radiation"].get("sickness_thresholds", [100, 200, 350])
	var stage: int = 0
	for t in th:
		if res["radiation"] >= float(t):
			stage += 1
	var i: int = _cond_index("radiation_sickness")
	if stage == 0:
		if i >= 0:
			remove_condition("radiation_sickness")
	elif i < 0:
		add_condition("radiation_sickness")
		conditions[_cond_index("radiation_sickness")]["stage"] = stage
	else:
		conditions[i]["stage"] = stage


func _guess_cause() -> String:
	if res["thirst"] <= 0.0:
		return "thirst"
	if res["hunger"] <= 0.0:
		return "hunger"
	if has_condition("radiation_sickness"):
		return "radiation"
	for c in conditions:
		if R.is_trauma(c["id"]):
			return "wounds"
	return "disease" if not conditions.is_empty() else "other"


func die(cause: String) -> void:
	if not alive:
		return
	alive = false
	sleeping = false
	death_cause = cause if DEATH_CAUSES.has(cause) else "other"
	res["health"] = 0.0
	died.emit(death_cause)


func set_sleep(on: bool) -> void:
	if not alive or on == sleeping:
		return
	sleeping = on
	if on:
		sleep_h = 0.0
	elif sleep_h >= R.num("needs", "rested_after_sleep_h", 8.0):
		add_buff("rested")


# =====================================================================
# ЕДА И ВОДА
# =====================================================================
## water: "clean" (кипячёная, колодец), "raw" (река, озеро), "dirty" (лужа, болото)
func drink(amount: float, water: String = "clean") -> void:
	add_res("thirst", amount)
	_roll_causes(water + "_water")


## kind: "cooked", "warm" (сытная горячая еда: эффект warm_meal), "raw_meat", "spoiled"
func eat(amount: float, kind: String = "cooked") -> void:
	add_res("hunger", amount)
	if kind == "warm":
		add_buff("warm_meal")
	_roll_causes(kind)


func _roll_causes(key: String) -> void:
	var table: Dictionary = R.section("causes").get(key, {})
	for id in table:
		try_catch(id, float(table[id]) * mult("food_water_chance"))


# =====================================================================
# НАВЫКИ
# =====================================================================
## Уровень 0–10 для старых правил (навык % / 10); ключ — новый или старый навык пака
func skill_level(k: String) -> int:
	return S.level_equiv(self, k)


## Навык в процентах
func skill(k: String) -> int:
	return S.skill_value(self, k)


## Опыт за дело (путь, лечение, ремесло): растёт не навык, а опыт героя — уровни и очки навыков
func add_xp(k: String, amount: float) -> void:
	if amount <= 0.0:
		return
	var before: int = level
	S.gain_xp(self, amount * S.num("xp", "use_mult", 3.0) * mult("xp"))
	if level != before:
		skill_leveled_up.emit(S.canon(k), level)


## Начальный уровень навыка (мастера-НПС): значение ≈ уровень × 10 + 5
func set_skill_level(k: String, lv: int) -> void:
	S.set_level_equiv(self, k, lv)


# =====================================================================
# ЛЕЧЕНИЕ: лечит любой персонаж любого, в том числе себя и лекарь-НПС игрока
# =====================================================================
func treat_chance(id: String, healer: Actor) -> float:
	var t: Dictionary = R.section("treatments").get(id, {})
	var m: Dictionary = R.section("medicine")
	var c: float = float(m.get("base_chance", 0.45))
	# Знахарство %: каждые 10 % — уровень старого правила (дробно)
	c += float(m.get("per_level", 0.08)) * (float(healer.skill("doctor")) / 10.0 - float(t.get("skill", 1)))
	c += float(R.section("stats").get("luck_chance_per_pt", 0.0)) * healer._over("luck")
	c += S.eff(healer, "treat")
	return clampf(c, float(m.get("min_chance", 0.05)), float(m.get("max_chance", 0.97)))


## items — что есть у лечащего (ключи вроде "bandage"). Ответ: {ok, reason, chance, used}
## used — какие предметы потрачены (их убирает вызывающий: инвентаря пока нет)
func treat(id: String, healer: Actor, items: Array = []) -> Dictionary:
	if not has_condition(id):
		return {"ok": false, "reason": I18n.t("нечего лечить"), "chance": 0.0, "used": []}
	if healer == null or not healer.alive or healer.sleeping:
		return {"ok": false, "reason": I18n.t("некому лечить"), "chance": 0.0, "used": []}
	var t: Dictionary = R.section("treatments").get(id, {})
	var need: Array = t.get("items", [])
	var missing: Array = need.filter(func(x): return not items.has(x))
	if not missing.is_empty():
		return {"ok": false, "reason": I18n.t("нужно: ") + ", ".join(PackedStringArray(missing)), "chance": 0.0, "used": []}
	var chance: float = treat_chance(id, healer)
	var m: Dictionary = R.section("medicine")
	var ok: bool = healer.rng.randf() < chance
	if ok:
		if id == "radiation_sickness":
			add_buff("anti_radiation")
		else:
			remove_condition(id)
		healer.add_xp("medicine", float(m.get("xp_success", 12.0)) * (1.0 + 0.25 * float(t.get("skill", 1))))
	else:
		healer.add_xp("medicine", float(m.get("xp_fail", 3.0)))
	return {"ok": ok, "reason": "" if ok else I18n.t("не вышло"), "chance": chance, "used": need.duplicate()}


# =====================================================================
# ПРОИЗВОДНЫЕ
# =====================================================================
## Груз: 25 + 25×СИЛ фунтов (в кг), меньше при усталости
func carry_capacity() -> float:
	var kg: float = S.carry_kg(self)
	return kg * (0.5 + 0.5 * res["stamina"] / max_of("stamina")) * mult("power") + pack_kg


## Защита от проклятья (радиации): 2×ВЫН % + перки
func radiation_resist() -> float:
	return clampf(float(S.rad_resist(self)) / 100.0, 0.0, 0.9)


## Производные: старые ключи пака + новые параметры (sheet.gd: hp, ap, ac, carry_kg, melee, poison, rad,
## sequence, healing, crit, skill_points, party)
func derived() -> Dictionary:
	var sr: Dictionary = R.section("stats")
	var out: Dictionary = S.derived(self)
	out.merge({
		"attack_power": (1.0 + float(sr.get("attack_per_str", 0.0)) * _over("str")) * mult("power"),
		"defense": 0.0,
		"search_efficiency": (1.0 + float(sr.get("search_per_per", 0.0)) * _over("per")) * mult("loot") * (1.0 + 0.05 * skill_level("survival")),
		"move_speed": body_speed_mult(),
		"carry_weight": carry_capacity(),
		"radiation_resist": radiation_resist(),
	}, true)
	return out


# =====================================================================
# ДВИЖЕНИЕ (реальное время)
# =====================================================================
func can_move() -> bool:
	return alive and not sleeping


# Множитель скорости от тела, без местности
func body_speed_mult() -> float:
	var mv: Dictionary = R.section("movement")
	var f: float = mult("speed") * mult("move_speed")
	f *= 1.0 + float(R.section("stats").get("speed_per_agi", 0.0)) * _over("agi")
	# Бонусы навыков и сна (getSpeedBonus, getSleepBonus пака): Выживание пешком, Верховая езда на транспорте
	if mount == "":
		f *= 1.0 + float(mv.get("survival_speed_per_level", 0.0)) * skill_level("survival")
	else:
		f *= 1.0 + float(mv.get("riding_speed_per_level", 0.0)) * skill_level("riding")
	if has_buff("rested"):
		f *= 1.0 + float(mv.get("rested_bonus", 0.0))
	if res["health"] < float(R.characteristics()["health"].get("critical_threshold", 20)):
		f *= float(mv.get("critical_health_mult", 0.75))
	if res["energy"] <= 0.0:
		f *= float(mv.get("no_energy_mult", 0.5))
	# Перегруз по паку: speed *= (100 − перегруз %) / 100; при двойном весе стоит
	f *= clampf((100.0 - overload_percent()) / 100.0, 0.0, 1.0)
	return f / float(mv.get("hard_coefficient", 1.0))


func overload_percent() -> float:
	var cap: float = carry_capacity()
	if cap <= 0.0 or carried_kg <= cap:
		return 0.0
	return (carried_kg - cap) / cap * 100.0


func is_swimming(env: Dictionary) -> bool:
	return bool(R.terrain(int(env.get("biome", 4))).get("swim", false))


func can_run() -> bool:
	return mount == "" and res["stamina"] > 0.0 and res["energy"] > 0.0 and not has_condition("broken_leg")


## Метров доски в реальную секунду. Ноль — сюда не пройти (за краем мира) или идти не может
func travel_speed(env: Dictionary, run: bool = false) -> float:
	if not can_move():
		return 0.0
	var mv: Dictionary = R.section("movement")
	var ter: Dictionary = R.terrain(int(env.get("biome", 4)))
	return calculate_speed(env, run) / 3.6 * float(mv.get("travel_scale", 8.0)) * GameClock.GAME_SPEED


## Скорость по земле, км/ч (формула checkSpeed пака):
## база (пешком 3, лошадь 8, повозка 5) × местность × (1 + effect.speed) × (1 − погода) × (1 + ночь)
## / сложность × перегруз × навыки и сон. Плавание — своя скорость из rules.json
func calculate_speed(env: Dictionary, run: bool = false) -> float:
	if not can_move():
		return 0.0
	var mv: Dictionary = R.section("movement")
	var ter: Dictionary = R.terrain(int(env.get("biome", 4)))
	var kmh: float
	if bool(ter.get("swim", false)):
		kmh = float(mv.get("swim_mps", 0.6)) * 3.6
	else:
		kmh = R.base_kmh(mount) * float(ter.get("speed", 1.0)) * R.mount_terrain(mount, int(env.get("biome", 4)))
		if run and can_run():
			kmh *= float(mv.get("run_mult", 2.1))
		if float(ter.get("radiation_h", 0.0)) > 0.0:
			kmh *= float(mv.get("rad_zone_mult", 1.0))
	kmh *= body_speed_mult()
	kmh *= 1.0 - weather_penalty(env)
	if bool(env.get("night", false)):
		if not S.has(self, "night_vision"):
			kmh *= 1.0 + minf(float(mv.get("night_bonus", 0.0)) + float(mv.get("night_bonus_per_survival", 0.0)) * skill_level("survival"), 0.0)
	return maxf(kmh, 0.0)


# Штраф погоды 0..1: env.weather ("rain", "snow", "storm") или дождь rain > 0,5
func weather_penalty(env: Dictionary) -> float:
	var wp: Dictionary = R.section("movement").get("weather_penalty", {})
	var w: String = str(env.get("weather", ""))
	if w == "" and float(env.get("rain", 0.0)) > 0.5:
		w = "rain"
	return clampf(float(wp.get(w, 0.0)), 0.0, 1.0)


## Запас сил за реальные секунды. mode: "rest", "walk", "run". В воде всегда плывёт:
## без сил тонет. Возвращает, тонет ли сейчас
func exert(real_dt: float, env: Dictionary, mode: String) -> bool:
	if not alive:
		return false
	var mv: Dictionary = R.section("movement")
	var endure: float = maxf(1.0 + float(R.section("stats").get("stamina_per_end", 0.0)) * _over("end"), 0.2)
	moving = mode != "rest"
	if is_swimming(env):
		add_res("stamina", -float(mv.get("stamina_swim_s", 0.5)) / endure * real_dt)
		if res["stamina"] <= 0.0:
			add_res("health", -float(mv.get("drown_health_s", 2.0)) * real_dt)
			if res["health"] <= 0.0:
				die("drowning")
			return true
		return false
	match mode:
		"run":
			if can_run():
				add_res("stamina", -float(mv.get("stamina_run_s", 2.0)) / endure * real_dt)
			else:
				add_res("stamina", float(mv.get("stamina_walk_regen_s", 1.0)) * real_dt)
		"walk":
			add_res("stamina", float(mv.get("stamina_walk_regen_s", 1.0)) * real_dt)
		_:
			add_res("stamina", float(mv.get("stamina_rest_regen_s", 3.0)) * real_dt)
	return false


## Пройденный путь: падения в горах, опыт Выживания вне воды
func note_travel(meters: float, env: Dictionary) -> void:
	if meters <= 0.0 or not alive:
		return
	var km_before: int = int(distance_m / 1000.0)
	distance_m += meters
	var ter: Dictionary = R.terrain(int(env.get("biome", 4)))
	var km: float = meters / 1000.0
	# Событие каждого километра (onekmpassed пака): шанс травмы, ночью выше; каждые 100 км — «невезение»
	var mv: Dictionary = R.section("movement")
	for k in range(km_before + 1, int(distance_m / 1000.0) + 1):
		var p: float = float(mv.get("km_trauma_chance", 0.0))
		if bool(env.get("night", false)):
			p *= float(mv.get("night_trauma_mult", 1.0))
		if k % 100 == 0:
			p += float(mv.get("badluck_100km_chance", 0.0))
		p *= clampf(1.0 - 0.05 * skill_level("survival") - float(R.section("stats").get("luck_chance_per_pt", 0.0)) * _over("luck"), 0.1, 1.5)
		p *= mult("fall_chance")
		if not bool(ter.get("swim", false)) and rng.randf() < p:
			_fall()
		km_passed.emit(k)
	var fall: float = float(ter.get("fall_per_km", 0.0)) * km
	if fall > 0.0:
		fall *= clampf(1.0 - 0.01 * _over("agi") - 0.05 * skill_level("survival"), 0.1, 1.0) * mult("fall_chance")
		if rng.randf() < fall:
			_fall()
	if not bool(ter.get("swim", false)):
		if mount != "":
			add_xp("riding", km * float(R.transport().get("riding_xp_per_km", 1.0)))
		else:
			add_xp("survival", km)


func _fall() -> void:
	var w: Dictionary = R.section("fall_traumas")
	var total: float = 0.0
	for k in w:
		total += float(w[k])
	var r: float = rng.randf() * total
	for k in w:
		r -= float(w[k])
		if r <= 0.0:
			add_condition(k)
			return


# =====================================================================
# СОХРАНЕНИЕ
# =====================================================================
func to_dict() -> Dictionary:
	return {
		"id": actor_id, "name": display_name, "npc": is_npc, "stats": stats.duplicate(),
		"res": res.duplicate(), "conditions": conditions.duplicate(true), "buffs": buffs.duplicate(true),
		"skills": skills.duplicate(true), "alive": alive, "death_cause": death_cause,
		"sleeping": sleeping, "sleep_h": sleep_h, "wet_h": wet_h, "carried_kg": carried_kg, "mount": mount,
		"distance_m": distance_m, "rng_state": rng.state, "traits": traits.duplicate(), "profile": profile.duplicate(true),
		"sheet": 1, "tags": tags.duplicate(), "quirks": quirks.duplicate(), "perks": perks.duplicate(),
		"level": level, "xp": xp, "skill_points": skill_points, "perk_picks": perk_picks, "mutate_left": mutate_left, "tag_left": tag_left,
	}


static func from_dict(d: Dictionary) -> Actor:
	var a := Actor.new(str(d.get("id", "")), str(d.get("name", "")), bool(d.get("npc", false)))
	if S.is_legacy(d):
		S.migrate(a, d)   # сохранение до новой системы: 7 характеристик 09 и навыки пака уровнями
	else:
		for s in d.get("stats", {}):
			a.stats[s] = int(d["stats"][s])
		for k in d.get("skills", {}):
			var e: Dictionary = d["skills"][k]
			a.skills[String(k)] = {"pts": int(e.get("pts", 0)), "bonus": int(e.get("bonus", 0)), "spent": int(e.get("spent", 0))}
		a.tags = d.get("tags", []).duplicate()
		a.quirks = d.get("quirks", []).duplicate()
		a.perks = d.get("perks", {}).duplicate()
		a.level = int(d.get("level", 1))
		a.xp = float(d.get("xp", 0.0))
		a.skill_points = int(d.get("skill_points", 0))
		a.perk_picks = int(d.get("perk_picks", 0))
		a.mutate_left = int(d.get("mutate_left", 0))
		a.tag_left = int(d.get("tag_left", 0))
	for r in d.get("res", {}):
		a.res[r] = float(d["res"][r])
	a.conditions = d.get("conditions", []).duplicate(true)
	a.buffs = d.get("buffs", []).duplicate(true)
	a.alive = bool(d.get("alive", true))
	a.death_cause = str(d.get("death_cause", ""))
	a.sleeping = bool(d.get("sleeping", false))
	a.sleep_h = float(d.get("sleep_h", 0.0))
	a.wet_h = float(d.get("wet_h", 0.0))
	a.carried_kg = float(d.get("carried_kg", 0.0))
	a.mount = str(d.get("mount", ""))
	a.distance_m = float(d.get("distance_m", 0.0))
	a.traits = d.get("traits", []).duplicate()
	a.profile = d.get("profile", {}).duplicate(true)
	if d.has("rng_state"):
		a.rng.state = int(d["rng_state"])
	return a

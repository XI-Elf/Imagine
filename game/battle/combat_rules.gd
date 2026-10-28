extends RefCounted
## Формулы боя. Порядок и обозначения — по Combat_Formulas.docx (раздел J):
##   ATK = R + M_ATK + PB + W_ATK + A_ATK + LU_ATK − PEN_ATK
##   HIT = (R ≠ L) ∧ ((R = H) ∨ (ATK ≥ AC_TARGET)), CRIT = HIT ∧ (R = H)
##   BASE_j = max(0, Q_ACTIVE_j + F_j); на крите Q_ACTIVE_j — сумма K_CRIT полных бросков костей
##   DR_EFF_j = floor(max(0, DR_j) × (1 − P_j)); AFTER_ARMOR_j = max(0, BASE_j − DR_EFF_j)
##   MULT_j = (1 − S_j) × (1 + V_j); FINAL_j = 0 при иммунитете, иначе floor(AFTER_ARMOR_j × MULT_j)
##   AC_TARGET = AC_BASE + DEX_EFF + SH_AC + AB_AC + CV_AC
## Прочее (спасброски, инициатива, 0 HP) — по ТЗ D&D 5e и документу Combat_System_Claude_Instructions.
## Числа берутся из BattleConfig и ресурсов, в формулах их нет.

const Data := preload("res://battle/battle_data.gd")
const Combatant := preload("res://battle/combatant.gd")

const DAMAGE_NAMES: Dictionary = {
	"slashing": "режущий", "piercing": "колющий", "bludgeoning": "дробящий", "fire": "огненный",
	"radiation": "проклятый", "poison": "ядовитый", "fall": "падение", "cold": "холод", "acid": "кислота",
	"lightning": "молния", "necrotic": "некротический", "radiant": "светящийся",
}


static func cfg() -> BattleConfig:
	return Data.config()


# =====================================================================
# AC
# =====================================================================
## {total, base, dex, shield, abilities, cover, text}
static func ac(t, cover: String = "none") -> Dictionary:
	var base: int
	var dex_eff: int = t.mod("dex")
	if t.fx("no_agi_ac") > 0.0:
		dex_eff = 0   # черта «Безрассудный»: Ловкость не защищает
	var sh: int = 0
	if t.armor != null:
		base = t.armor.base_ac
		if t.armor.dex_cap == 0:
			dex_eff = 0
		elif t.armor.dex_cap > 0:
			dex_eff = mini(dex_eff, t.armor.dex_cap)
		sh = t.armor.shield_bonus
	else:
		base = t.creature.natural_ac if t.creature != null else 10
	var ab: int = int(t.fx("b_ac"))
	if t.fx("b_ac_unarmed") > 0.0 and t.weapon().proficiency == "natural":
		ab += int(t.fx("b_ac_unarmed"))
	for e in t.effects:
		ab += int(e["res"].ac_bonus)
	var cv: int = int(cfg().cover_ac.get(cover, 0))
	var total: int = base + dex_eff + sh + ab + cv
	return {"total": total, "base": base, "dex": dex_eff, "shield": sh, "abilities": ab, "cover": cv,
		"text": "AC %d (%d + ЛОВ %d%s%s%s)" % [total, base, dex_eff, " + щит %d" % sh if sh else "",
		" + эффекты %d" % ab if ab else "", " + укрытие %d" % cv if cv else ""]}


# =====================================================================
# БРОСОК АТАКИ
# =====================================================================
## Чем атакует: оружие или способность-атака. Слагаемые ATK без R
static func attack_terms(att, w: BattleWeapon, ab: BattleAbility = null) -> Dictionary:
	var stat: String
	var proficient: bool = true
	var w_atk: int = 0
	var a_atk: int = 0
	if ab != null:
		stat = ab.stat
		proficient = ab.proficient
		a_atk = ab.attack_bonus
	else:
		stat = w.stat
		if stat == "finesse":
			stat = "dex" if att.mod("dex") >= att.mod("str") else "str"
		w_atk = w.attack_bonus + att.fo_attack_bonus(w)
	var m: int = att.mod(stat)
	# мастерство: у героя и людей — от навыка оружия Fallout (combatant.attack_prof), у шаблонов — от уровня
	var pb: int = (att.attack_prof(w) if ab == null else att.prof()) if proficient else 0
	var lu: int = att.mod("lck")
	var pen: int = att.attack_penalty()
	return {"stat": stat, "M_ATK": m, "PB": pb, "W_ATK": w_atk, "A_ATK": a_atk, "LU_ATK": lu, "PEN_ATK": pen,
		"sum": m + pb + w_atk + a_atk + lu - pen}


## Источники преимущества и помехи. ctx: {ranged, dist_ft, grid, all (участники), melee_reach}
static func adv_dis(att, tgt, ctx: Dictionary) -> Dictionary:
	var adv: Array = []
	var dis: Array = []
	var ranged: bool = bool(ctx.get("ranged", false))
	var dist: int = int(ctx.get("dist_ft", 5))
	var stat: String = String(ctx.get("stat", ""))
	# свои состояния
	for e in att.effects:
		var r: BattleEffect = e["res"]
		if r.attack_adv:
			adv.append(r.title.to_lower())
		if r.attack_dis:
			dis.append(r.title.to_lower())
		if r.attack_dis_stat != "" and r.attack_dis_stat == stat:
			dis.append(r.title.to_lower())
	# состояния цели
	for e in tgt.effects:
		var r: BattleEffect = e["res"]
		if r.attacked_adv:
			adv.append("цель: " + r.title.to_lower())
		if r.attacked_dis and not tgt.incapacitated():
			dis.append("цель: " + r.title.to_lower())
		if r.melee_attacked_adv and not ranged and dist <= 5:
			adv.append("цель лежит")
		if r.ranged_attacked_dis and (ranged or dist > 5):
			dis.append("цель лежит")
	if tgt.down:
		adv.append("цель без сознания")
	if tgt.helped_by == att.team:
		adv.append("помощь союзника")
	if ranged:
		if dist > int(ctx.get("normal_range", 1 << 20)) and att.fx("sharpshooter") <= 0.0:
			dis.append("дальше обычной дистанции")
		for o in ctx.get("all", []):
			if o.team != att.team and o.standing() and not o.incapacitated() and ctx["grid"].dist_ft(o.cell, att.cell) <= 5:
				dis.append("враг вплотную")
				break
		var g = ctx.get("grid")
		if cfg().high_ground_adv and g != null and g.elevation(att.cell) > g.elevation(tgt.cell):
			adv.append("высота")
	elif cfg().flanking and ctx.get("grid") != null:
		# фланг: союзник атакующего стоит вплотную к цели с противоположной стороны
		for o in ctx.get("all", []):
			if o != att and o.team == att.team and o.standing() and not o.incapacitated():
				if o.cell - tgt.cell == -(att.cell - tgt.cell) and ctx["grid"].dist_ft(o.cell, tgt.cell) <= 5:
					adv.append("фланг")
					break
	return {"adv": adv, "dis": dis}


## Полная атака по разделу J (шаги 3–7). roller — DiceRoller. Ответ — всё для лога (раздел K)
static func attack(roller, att, tgt, w: BattleWeapon, ab: BattleAbility, ctx: Dictionary) -> Dictionary:
	var c: BattleConfig = cfg()
	var terms: Dictionary = attack_terms(att, w, ab)
	ctx["stat"] = terms["stat"]
	var ad: Dictionary = adv_dis(att, tgt, ctx)
	var cover: String = String(ctx.get("cover", "none"))
	var act: Dictionary = ac(tgt, cover)
	var r: Dictionary = roller.check(c.attack_die, int(terms["sum"]), not ad["adv"].is_empty(), not ad["dis"].is_empty(),
		"Атака " + att.title)
	var R: int = int(r["natural"])
	var L: int = 1
	var H: int = c.attack_die
	var atk: int = int(r["total"])
	var hit: bool = R != L and (R == H or atk >= int(act["total"]))
	# окно крита шире от Удачи и перков (Fallout: крит % = Удача); «Убийца» — каждое попадание вблизи крит
	var crit: bool = hit and R >= H - (att.crit_extra(w) if ab == null else 0)
	if hit and ab == null and not w.ranged and att.fx("slayer") > 0.0:
		crit = true
	# По тому, кто без сознания, вплотную — всегда крит (5e)
	if hit and tgt.down and not bool(ctx.get("ranged", false)) and int(ctx.get("dist_ft", 5)) <= 5:
		crit = true
	var out: Dictionary = {"R": R, "L": L, "H": H, "terms": terms, "ATK": atk, "AC": act, "adv": ad["adv"], "dis": ad["dis"],
		"mode": r["mode"], "rolls": r["rolls"], "hit": hit, "crit": crit, "roll": r, "damage": {}}
	var verdict: String = "Крит!" if crit else ("Попадание" if hit else ("Промах (минимум кубика)" if R == L else "Промах"))
	out["text"] = "Атака: %s%s против %s → %s." % [r["text"], _terms_text(terms), act["text"], verdict]
	if ad["adv"].size() > 0 or ad["dis"].size() > 0:
		out["text"] += " [%s]" % ", ".join(PackedStringArray(
			ad["adv"].map(func(x): return "+" + x) + ad["dis"].map(func(x): return "−" + x)))
	if hit:
		var comps: Array = components(att, w, ab)
		var pen: Dictionary = ab.penetration if ab != null else w.penetration
		var rep: int = 1
		if crit:
			# «Лучшие криты» — ещё один набор костей, «Тяжёлая рука» — на один меньше
			rep = maxi(1, c.k_crit + (1 if att.fx("strong_crits") > 0.0 else 0) - (1 if att.fx("weak_crits") > 0.0 else 0))
		var scale: float = maxf(0.0, 1.0 + att.fx("b_dmg_pct") / 100.0)
		if att.has_effect("hidden") and att.fx("b_hidden_mult") > 0.0:
			scale *= 1.0 + att.fx("b_hidden_mult")   # «Тихая смерть»
		out["damage"] = damage(roller, tgt, comps, pen, rep, false, scale)
		out["text"] += " " + out["damage"]["text"]
	return out


static func _terms_text(t: Dictionary) -> String:
	var s: String = " [мод. %+d" % int(t["M_ATK"])
	if int(t["PB"]):
		s += ", мастерство %+d" % int(t["PB"])
	if int(t["W_ATK"]):
		s += ", оружие %+d" % int(t["W_ATK"])
	if int(t["A_ATK"]):
		s += ", способность %+d" % int(t["A_ATK"])
	if int(t["LU_ATK"]):
		s += ", удача %+d" % int(t["LU_ATK"])
	if int(t["PEN_ATK"]):
		s += ", штраф −%d" % int(t["PEN_ATK"])
	return s + "]"


## Компоненты урона атакующего: [{type, dice, F}]. Модификатор характеристики — один раз, в mod_component
static func components(att, w: BattleWeapon, ab: BattleAbility = null) -> Array:
	var out: Array = []
	if ab != null:
		for d in ab.damage:
			var ty: String = String(d.get("type", "bludgeoning"))
			out.append({"type": ty, "dice": String(d.get("dice", "")), "F": int(d.get("bonus", 0)) + int(att.fx("b_dmg_abil")) + (int(att.fx("b_dmg_fire")) if ty == "fire" else 0)})
		return out
	var stat: String = attack_terms(att, w)["stat"]
	for i in w.damage.size():
		var d: Dictionary = w.damage[i]
		var f: int = int(d.get("bonus", 0))
		if i == w.mod_component:
			f += att.mod(stat) + att.fo_damage_bonus(w)
		if String(d.get("type", "")) == "fire":
			f += int(att.fx("b_dmg_fire"))
		out.append({"type": String(d.get("type", "bludgeoning")), "dice": String(d.get("dice", "")), "F": f})
	return out


# =====================================================================
# УРОН: броня, пробитие, сопротивление, уязвимость, иммунитет (разделы D–F, H)
# =====================================================================
## scale — множитель урона атакующего («Изящество» −30 %, «Тихая смерть» ×2); tgt.dr_pct — «Крепкий» цели
static func damage(roller, tgt, comps: Array, penetration: Dictionary, repeat: int, half: bool = false, scale: float = 1.0) -> Dictionary:
	var parts: Array = []
	var total: int = 0
	var texts: Array = []
	for comp in comps:
		var j: String = comp["type"]
		var q: int = 0
		var qtext: String = ""
		if String(comp["dice"]) != "":
			var r: Dictionary = roller.roll(comp["dice"], {"repeat": repeat, "label": "Урон " + DAMAGE_NAMES.get(j, j)})
			q = int(r["total"])
			qtext = "%d (%s%s)" % [q, comp["dice"], " ×%d" % repeat if repeat > 1 else ""]
		var f: int = int(comp["F"])
		var base: int = maxi(0, q + f)
		if half:
			base = int(floor(base / 2.0))
		var dr: int = maxi(0, int(tgt.armor.dr.get(j, 0)) if tgt.armor != null else 0)
		var p: float = clampf(float(penetration.get(j, 0.0)), 0.0, 1.0)
		var dr_eff: int = int(floor(dr * (1.0 - p)))
		var after: int = maxi(0, base - dr_eff)
		var s: float = clampf(maxf(float(tgt.resist.get(j, 0.0)), maxf(tgt.effect_resist(j),
			float(tgt.armor.resist.get(j, 0.0)) if tgt.armor != null else 0.0)), 0.0, 1.0)
		var v: float = maxf(0.0, maxf(float(tgt.vulnerable.get(j, 0.0)), float(tgt.armor.vulnerable.get(j, 0.0)) if tgt.armor != null else 0.0))
		var imm: bool = tgt.immune.has(j)
		var mult: float = (1.0 - s) * (1.0 + v) * scale * (1.0 - float(tgt.dr_pct))
		var fin: int = 0 if imm else int(floor(after * mult + 1e-9))
		total += fin
		parts.append({"type": j, "Q": q, "F": f, "BASE": base, "DR": dr, "P": p, "DR_EFF": dr_eff, "AFTER": after,
			"S": s, "V": v, "IMM": imm, "FINAL": fin})
		var t: String = "%s %s%s%s = %d" % [DAMAGE_NAMES.get(j, j), qtext if qtext != "" else "0", " %+d" % f if f else "", " ÷2" if half else "", base]
		if dr_eff > 0:
			t += " − броня %d%s = %d" % [dr_eff, " (пробито %d%%)" % int(p * 100) if p > 0.0 else "", after]
		if imm:
			t += " → иммунитет 0"
		elif s > 0.0 or v > 0.0 or not is_equal_approx(mult, 1.0):
			t += " × %.2f%s%s → %d" % [mult, " (сопр. %d%%)" % int(s * 100) if s > 0.0 else "", " (уязв. +%d%%)" % int(v * 100) if v > 0.0 else "", fin]
		texts.append(t)
	return {"parts": parts, "total": total, "text": "Урон: %s. Итого %d." % ["; ".join(PackedStringArray(texts)), total]}


## Раздел H: HP_NEW, ACTUAL_HP_LOSS, OVERKILL
static func apply_hp(t, total: int) -> Dictionary:
	var old: int = t.hp
	t.hp = maxi(0, old - total)
	return {"HP_OLD": old, "HP_NEW": t.hp, "LOSS": old - t.hp, "OVERKILL": maxi(0, total - old)}


# =====================================================================
# СПАСБРОСКИ, DC, ИНИЦИАТИВА
# =====================================================================
static func save_dc(c, stat: String) -> int:
	return 8 + c.mod(stat) + c.prof()


## Спасбросок: d20 + мод + мастерство (если владеет). Укрытие даёт бонус к спасброскам Ловкости
static func saving_throw(roller, c, stat: String, dc: int, cover: String = "none") -> Dictionary:
	var m: int = c.mod(stat) + (c.prof() if c.save_profs.has(stat) else 0)
	if stat == "dex":
		m += int(cfg().cover_ac.get(cover, 0))
	if c.save_flag("save_autofail", stat) or (c.down and stat in ["str", "dex"]):
		var t: String = "Спасбросок %s %s: автопровал (DC %d)." % [Combatant.STAT_NAMES.get(stat, stat), c.title, dc]
		return {"ok": false, "auto": true, "text": t, "total": 0}
	var r: Dictionary = roller.d20(m, c.save_flag("save_adv", stat), c.save_flag("save_dis", stat), "Спасбросок " + c.title)
	var ok: bool = int(r["total"]) >= dc
	return {"ok": ok, "roll": r, "total": r["total"], "text": "Спасбросок %s %s: %s против DC %d → %s." % [
		Combatant.STAT_NAMES.get(stat, stat), c.title, r["text"], dc, "успех" if ok else "провал"]}


static func initiative(roller, c) -> Dictionary:
	var r: Dictionary = roller.d20(c.mod("dex") + c.per_bonus, false, false, "Инициатива " + c.title)
	c.initiative = int(r["total"])
	return r


static func passive_perception(c) -> int:
	return 10 + c.mod("wis") + (c.prof() if c.perception_prof else 0) + c.per_bonus + int(c.fx("b_perception"))


# =====================================================================
# ТРАВМЫ И 0 HP (документ: травмы вместо death saves; решение Huzzah)
# =====================================================================
static func hit_zone(roller) -> String:
	var r: Dictionary = roller.d20(0, false, false, "Зона попадания", {"silent": true})
	var zones: Dictionary = cfg().zones
	for z in ["head", "torso", "arm", "leg"]:
		if int(r["natural"]) <= int(zones.get(z, 20)):
			return z
	return "torso"


static func trauma_for(zone: String, dtype: String) -> String:
	var t: Dictionary = cfg().trauma_table.get(zone, {})
	return String(t.get(dtype, t.get("*", "")))


## Проверка при 0 HP: d20 + CON + LCK. Ответ: {result: "trauma"|"down"|"dead", text}
static func zero_hp_check(roller, c) -> Dictionary:
	var k: BattleConfig = cfg()
	var r: Dictionary = roller.d20(c.mod("con") + c.mod("lck"), false, false, "Проверка травмы " + c.title)
	var total: int = int(r["total"])
	var res: String = "dead"
	if total >= k.trauma_high:
		res = "trauma"
	elif total >= k.trauma_mid:
		res = "down"
	var what: Dictionary = {"trauma": "тяжёлая травма, остаётся в сознании с 1 HP", "down": "без сознания, стабилен, травма", "dead": "смерть"}
	return {"result": res, "roll": r, "text": "%s при 0 HP: %s (ВЫН %+d, УДЧ %+d) — пороги %d/%d → %s." % [
		c.title, r["text"], c.mod("con"), c.mod("lck"), k.trauma_high, k.trauma_mid, what[res]]}


## Проверка тяжёлой раны (крит или удар ≥ доли HP): d20 + CON + LCK против injury_dc; провал — травма по зоне
static func injury_check(roller, c, dtype: String) -> Dictionary:
	var k: BattleConfig = cfg()
	var r: Dictionary = roller.d20(c.mod("con") + c.mod("lck"), false, false, "Рана " + c.title)
	var ok: bool = int(r["total"]) >= k.injury_dc
	var zone: String = hit_zone(roller)
	var tr: String = "" if ok else trauma_for(zone, dtype)
	return {"ok": ok, "zone": zone, "trauma": tr, "text": "Проверка раны %s: %s против DC %d → %s." % [
		c.title, r["text"], k.injury_dc, "выдержал" if ok else "травма (%s)" % zone]}


## Урон падения: 1d6 дробящего за каждые 10 футов, не больше 20d6 (документ, раздел 6)
static func fall_dice(height_ft: int) -> String:
	var n: int = clampi(int(floor(height_ft / 10.0)), 0, 20)
	return "" if n == 0 else "%dd6" % n

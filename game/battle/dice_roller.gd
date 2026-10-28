class_name DiceRoller
extends RefCounted
## Единый бросок костей боя. Все броски идут сюда: выражения «NdX+M» (несколько слагаемых: «2d6+1d4+3»),
## d20 с преимуществом/помехой, удвоение костей на крите. Каждый бросок возвращает полный лог
## и уходит сигналом rolled — его ловит лог боя и анимация костей.

signal rolled(entry: Dictionary)

const SIDES: Array = [4, 6, 8, 10, 12, 20, 100]

var rng := RandomNumberGenerator.new()
var history: Array = []            # последние броски (для лога и тестов)
var forced: Array = []             # подложенные значения костей (только тесты): берутся по порядку


func _init(seed_value: int = 0) -> void:
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()


## Разбор выражения: [{n, sides, sign}] и плоский модификатор. Неверное — ok = false
static func parse(expr: String) -> Dictionary:
	var s: String = expr.replace(" ", "").to_lower()
	var terms: Array = []
	var mod: int = 0
	if s == "":
		return {"ok": true, "terms": terms, "mod": 0}
	var re := RegEx.new()
	re.compile("([+-]?)(\\d*)d(\\d+)|([+-]?)(\\d+)")
	var pos: int = 0
	for m in re.search_all(s):
		if m.get_start() != pos:
			return {"ok": false, "terms": [], "mod": 0}
		pos = m.get_end()
		if m.get_string(3) != "":
			var n: int = int(m.get_string(2)) if m.get_string(2) != "" else 1
			var sides: int = int(m.get_string(3))
			if not SIDES.has(sides) or n < 1 or n > 100:
				return {"ok": false, "terms": [], "mod": 0}
			terms.append({"n": n, "sides": sides, "sign": -1 if m.get_string(1) == "-" else 1})
		else:
			mod += int(m.get_string(5)) * (-1 if m.get_string(4) == "-" else 1)
	if pos != s.length():
		return {"ok": false, "terms": [], "mod": 0}
	return {"ok": true, "terms": terms, "mod": mod}


func die(sides: int) -> int:
	if not forced.is_empty():
		return clampi(int(forced.pop_front()), 1, sides)
	return rng.randi_range(1, sides)


## Бросок выражения. opts: repeat (сколько полных бросков набора костей, K_CRIT на крите), label,
## extra_mod (добавить к модификатору — фиксированные бонусы не повторяются), silent
## Ответ: {expr, total, dice: [{sides, value}], mod, crit, label, text, ok}
func roll(expr: String, opts: Dictionary = {}) -> Dictionary:
	var p: Dictionary = parse(expr)
	var rep: int = maxi(1, int(opts.get("repeat", 1)))
	var out: Dictionary = {"expr": expr, "total": 0, "dice": [], "mod": 0, "crit": rep > 1, "repeat": rep,
		"label": String(opts.get("label", "")), "ok": p["ok"], "kind": "roll"}
	if not p["ok"]:
		push_error("DiceRoller: не разобрано выражение «%s»" % expr)
		out["text"] = I18n.t("%s: ошибка в «%s»") % [out["label"], expr]
		return out
	var total: int = 0
	var parts: Array = []
	for t in p["terms"]:
		var n: int = int(t["n"]) * rep
		var vals: Array = []
		for i in n:
			var v: int = die(int(t["sides"]))
			vals.append(v)
			out["dice"].append({"sides": int(t["sides"]), "value": v})
			total += v * int(t["sign"])
		parts.append("%s%s (%dd%d)" % ["-" if int(t["sign"]) < 0 else "", "+".join(PackedStringArray(vals.map(func(x): return str(x)))), n, int(t["sides"])])
	var mod: int = int(p["mod"]) + int(opts.get("extra_mod", 0))
	total += mod
	out["mod"] = mod
	out["total"] = total
	out["text"] = "%s%s%s = %d" % [" + ".join(PackedStringArray(parts)) if not parts.is_empty() else "0",
		"" if mod == 0 else (" + %d" % mod if mod > 0 else " − %d" % -mod), I18n.t(" [сильный удар ×%d]") % rep if rep > 1 else "", total]
	_log(out, opts)
	return out


## Бросок d20 с модификатором. Преимущество и помеха отменяют друг друга (сколько бы их ни было).
## Ответ: {natural, total, rolls: [a, b], mode: "adv"|"dis"|"", nat20, nat1, mod, text}
func d20(mod: int = 0, adv: bool = false, dis: bool = false, label: String = "", opts: Dictionary = {}) -> Dictionary:
	return check(20, mod, adv, dis, label, opts)


## Бросок проверочного кубика с гранями sides (кубик атаки задаётся конфигом: L = 1, H = sides).
## nat20/nat1 здесь значат «выпал максимум/минимум кубика»
func check(sides: int, mod: int = 0, adv: bool = false, dis: bool = false, label: String = "", opts: Dictionary = {}) -> Dictionary:
	var mode: String = ""
	if adv and not dis:
		mode = "adv"
	elif dis and not adv:
		mode = "dis"
	var a: int = die(sides)
	var rolls: Array = [a]
	var nat: int = a
	if mode != "":
		var b: int = die(sides)
		rolls.append(b)
		nat = maxi(a, b) if mode == "adv" else mini(a, b)
	var out: Dictionary = {"kind": "d20", "natural": nat, "rolls": rolls, "mode": mode, "mod": mod, "total": nat + mod,
		"nat20": nat == sides, "nat1": nat == 1, "low": 1, "high": sides, "label": label,
		"dice": rolls.map(func(x): return {"sides": sides, "value": x})}
	var head: String = "%d (d%d)" % [nat, sides]
	if mode != "":
		head = "%d (d%d %s: %d, %d)" % [nat, sides, I18n.t("преим.") if mode == "adv" else I18n.t("помеха"), rolls[0], rolls[1]]
	out["text"] = head + ("" if mod == 0 else (" + %d" % mod if mod > 0 else " − %d" % -mod)) + " = %d" % out["total"]
	_log(out, opts)
	return out


func _log(entry: Dictionary, opts: Dictionary) -> void:
	history.append(entry)
	if history.size() > 200:
		history.pop_front()
	if not bool(opts.get("silent", false)):
		rolled.emit(entry)


## Средний и крайние значения выражения (для подсказок «урон 4–11»)
static func range_of(expr: String, repeat: int = 1) -> Vector2i:
	var p: Dictionary = parse(expr)
	var lo: int = int(p["mod"])
	var hi: int = int(p["mod"])
	for t in p["terms"]:
		var n: int = int(t["n"]) * maxi(1, repeat)
		if int(t["sign"]) > 0:
			lo += n
			hi += n * int(t["sides"])
		else:
			lo -= n * int(t["sides"])
			hi -= n
	return Vector2i(lo, hi)


## Вероятность, что dX + mod >= dc (для атак: максимум кубика — всегда попадание, минимум — промах)
static func chance(mod: int, dc: int, adv: bool = false, dis: bool = false, nat_rules: bool = true, sides: int = 20) -> float:
	var p1: float = 0.0
	for n in range(1, sides + 1):
		var ok: bool = n + mod >= dc
		if nat_rules:
			ok = n == sides or (n != 1 and ok)
		if ok:
			p1 += 1.0 / float(sides)
	if adv and not dis:
		return 1.0 - (1.0 - p1) * (1.0 - p1)
	if dis and not adv:
		return p1 * p1
	return p1

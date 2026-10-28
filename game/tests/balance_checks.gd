extends SceneTree
## Баланс по симуляциям (вопрос Q19, Huzzah: вариант B). Каждое число, которое раньше было [ВРЕМЕННО],
## проверяется здесь через целевую метрику: случайные герои (как при «Случайном герое»), бои под ИИ,
## нужды по часам, цены по Харизме, шанс пролезть в город. Метрика вне цели — FAIL с измеренным значением.
## godot --path game --rendering-driver opengl3 -s res://tests/balance_checks.gd

const P := preload("res://characters/hero_profile.gd")
const R := preload("res://characters/actor_rules.gd")
const Trade := preload("res://city/trade.gd")
const Core := preload("res://battle/battle_core.gd")
const Enc := preload("res://battle/encounters.gd")
const Settl := preload("res://world/settlements.gd")

## Цели. Меняя число в игре, сверяйтесь с этой таблицей; меняя цель — пишите, почему
const TARGET := {
	"starter_knife_win": [0.85, 0.99],     # первый бой у «Острога» (Q30): оборванец, у героя нож — почти наверняка
	"starter_fists_win": [0.3, 0.65],     # тот же бой кулаками: шанс есть, но нож стоит купить
	"group_knife_win": [0.45, 0.8],       # обычное нападение в одиночку с ножом (лимит врагов = 1 на героя).
	                                      # Поражение может стоить героя навсегда (Q06), поэтому не ниже 45 %
	"walk_min_per_fight": [10.0, 25.0],   # реальных минут шагом по пустоши днём между нападениями (скорость x192)
	"knife_max_price": 20,                # первые два поручения дают 20 монет (player_path_checks)
	"sneak_day": [0.3, 0.55],             # средний случайный герой днём
	"sneak_night": [0.5, 0.75],
	"thirst_empty_h": [36.0, 72.0],       # от полной Воды до нуля без питья
	"hunger_empty_h": [60.0, 120.0],
	"curse_sick_h": [10.0, 24.0],         # проклятая пустошь: часов до проклятой хвори (100)
	"forage_forest": [0.35, 0.6],         # шанс найти еду в лесу за одну попытку
}
const N_HEROES := 200
const N_FIGHTS := 120

var fails: int = 0
var checks: int = 0
var report: Array = []


func ok(cond: bool, what: String) -> void:
	checks += 1
	report.append(("ok: " if cond else "FAIL: ") + what)
	if not cond:
		fails += 1
		print("FAIL: ", what)
	else:
		print("ok: ", what)


func within(v: float, key: String, what: String) -> void:
	var t: Array = TARGET[key]
	ok(v >= t[0] and v <= t[1], "%s: %.2f (цель %.2f–%.2f)" % [what, v, t[0], t[1]])


func hero(seed_value: int) -> Actor:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var a := Actor.new("hero", "Герой", false, seed_value)
	P.apply(a, P.random_params(r))
	return a


func _initialize() -> void:
	_trade()
	_needs()
	_sneak()
	_encounters()
	_forage()
	_fights()
	print("balance_checks: %d/%d" % [checks - fails, checks])
	quit(1 if fails > 0 else 0)


func _trade() -> void:
	var worst: int = 0
	var arb: Array = []
	for cha in range(1, 15):
		var a := Actor.new("hero", "Герой", false, 1)
		a.set_stat("cha", cha)
		worst = maxi(worst, Trade.buy_price("knife", a))
		for id in Trade.items():
			if Trade.sell_price(id, a) >= Trade.buy_price(id, a) and int(Trade.item(id).get("price", 1)) > 1:
				arb.append("%s@%d" % [id, cha])
	ok(worst <= int(TARGET["knife_max_price"]), "нож при любой Харизме 1–14 не дороже %d: самый дорогой %d" % [TARGET["knife_max_price"], worst])
	ok(arb.is_empty(), "нигде продажа не дороже покупки: %s" % str(arb.slice(0, 5)))


func _hours_until(a: Actor, env: Dictionary, cond: Callable, limit_h: int = 400) -> float:
	for h in limit_h:
		if cond.call(a):
			return float(h)
		a.tick(3600.0, env)
	return float(limit_h)


func _needs() -> void:
	var env := {"biome": 4, "temp_c": 12.0}
	var th: float = 0.0
	var hu: float = 0.0
	var cu: float = 0.0
	var n: int = 30
	for s in n:
		var a := hero(100 + s)
		a.set_res("hunger", a.max_of("hunger"))
		th += _hours_until(a, env, func(x): return x.res["thirst"] <= 0.0)
		var b := hero(100 + s)
		hu += _hours_until(b, env, func(x):
			x.set_res("thirst", x.max_of("thirst"))
			return x.res["hunger"] <= 0.0)
		var c := hero(100 + s)
		cu += _hours_until(c, {"biome": 8, "temp_c": 12.0}, func(x):
			x.set_res("thirst", x.max_of("thirst"))
			x.set_res("hunger", x.max_of("hunger"))
			return x.has_condition("radiation_sickness"))
	within(th / n, "thirst_empty_h", "Вода: часов до нуля")
	within(hu / n, "hunger_empty_h", "Сытость: часов до нуля")
	within(cu / n, "curse_sick_h", "Проклятая пустошь: часов до проклятой хвори")


func _sneak() -> void:
	var st: Node = Settl.new()
	var f := FileAccess.open("res://data/world/settlements.json", FileAccess.READ)
	if f == null:
		ok(false, "нет data/world/settlements.json")
		return
	st.sneak_rules = JSON.parse_string(f.get_as_text()).get("sneak", {})
	var day: float = 0.0
	var night: float = 0.0
	for s in N_HEROES:
		var a := hero(300 + s)
		day += st.sneak_chance(a, {})
		night += st.sneak_chance(a, {"night": true})
	st.free()
	within(day / N_HEROES, "sneak_day", "Пролезть через стену днём, средний герой")
	within(night / N_HEROES, "sneak_night", "Пролезть через стену ночью, средний герой")


func _encounters() -> void:
	# travel_speed — метры карты в реальную секунду; нападение проверяется на каждый км карты
	var km_min: float = hero(7).travel_speed({"biome": 4}) * 60.0 / 1000.0
	var minutes: float = 1.0 / (Enc.chance_per_km({"biome": 4}) * km_min)
	within(minutes, "walk_min_per_fight", "Минут шагом по пустоши между нападениями (%.2f км карты в минуту)" % km_min)


func _forage() -> void:
	var sum: float = 0.0
	for s in N_HEROES:
		sum += minf(0.45 * hero(500 + s).derived()["search_efficiency"], 1.0)
	within(sum / N_HEROES, "forage_forest", "Еда в лесу за попытку, средний герой")


func _fight(seed_value: int, req: Dictionary) -> bool:
	var a := hero(seed_value)
	var r: Dictionary = req.duplicate(true)
	r["allies"] = [a]
	r["seed"] = seed_value * 7 + 1
	var cb: Node = Core.new()
	root.add_child(cb)
	cb.setup(r)
	for c in cb.all:
		c.controlled = false
	cb.begin()
	var guard: int = 0
	while cb.outcome == "" and guard < 600:
		cb.next_turn()
		guard += 1
	var won: bool = cb.outcome == "win"
	cb.free()
	return won


func _rate(req: Dictionary, base_seed: int) -> float:
	var w: int = 0
	for s in N_FIGHTS:
		if _fight(base_seed + s, req):
			w += 1
	return float(w) / N_FIGHTS


func _fights() -> void:
	var knife := {"items": {"knife": 1}}
	within(_rate({"terrain": "wasteland", "group": "bandits", "starter": true, "inventory": knife}, 1000), "starter_knife_win", "Первый бой с ножом: побед")
	within(_rate({"terrain": "wasteland", "group": "bandits", "starter": true, "inventory": {"items": {}}}, 2000), "starter_fists_win", "Первый бой кулаками: побед")
	for g in ["bandits", "wolves", "boar", "hounds"]:
		within(_rate({"terrain": "wasteland", "group": g, "inventory": knife}, 3000), "group_knife_win", "%s в одиночку с ножом: побед" % g)

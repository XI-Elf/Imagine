extends RefCounted
## Проста погода за сезоном і біомом (замість моделі атмосфери планети, питання Q25).
## Карту поділено на «плями погоди» (~spot_km, нерівна сітка), плями повільно дрейфують на схід.
## Кожна пляма раз на period_h годин погоди кидає одне число 0..1 (із шансом keep_chance лишає
## колишнє), і за ним обирається тип погоди з ваг сезону й біома (data/weather/weather.json).
## Типи йдуть від сухого до мокрого, тому одна пляма над лісом і пусткою дає схожу погоду.
## Усе детерміноване: той самий час погоди й місце дають ту саму погоду (збереження не потрібне).

const FILE := "res://data/weather/weather.json"
const WorldEnv := preload("res://characters/world_env.gd")
# Скільки минулих періодів дивитися, поки пляма «тримає» погоду
const KEEP_DEPTH: int = 8

var rules: Dictionary = {}
var seed_value: int = 12345
var _order: Array = []
var _types: Dictionary = {}
# Накопичені ваги: _cum[біом][сезон] = масив меж 0..1 за _order
var _cum: Dictionary = {}


func _init(data: Dictionary = {}) -> void:
	rules = data if not data.is_empty() else load_rules()
	_order = rules.get("order", ["clear", "cloudy", "fog", "rain", "storm"])
	_types = rules.get("types", {})
	var biomes: Dictionary = rules.get("biomes", {})
	for key in biomes:
		var tab: Dictionary = biomes[key]
		var per_season: Array = []
		for s in 4:
			var total: float = 0.0
			for ty in _order:
				total += _weight(tab, ty, s)
			var cum: Array = []
			var acc: float = 0.0
			for ty in _order:
				acc += _weight(tab, ty, s) / maxf(total, 0.0001)
				cum.append(acc)
			per_season.append(cum)
		_cum[str(key)] = per_season


static func load_rules() -> Dictionary:
	var f := FileAccess.open(FILE, FileAccess.READ)
	if f == null:
		push_error("simple_weather: нет %s" % FILE)
		return {}
	var d: Variant = I18n.tree(JSON.parse_string(f.get_as_text()))
	return d if d is Dictionary else {}


static func _weight(tab: Dictionary, ty: String, s: int) -> float:
	var w: Variant = tab.get(ty, [0, 0, 0, 0])
	return maxf(float(w[s]), 0.0) if w is Array and w.size() > s else 0.0


# Сезон як у GameClock.season(): 0 зима (з 1 грудня), 1 весна, 2 літо, 3 осінь
static func season_of(doy: float) -> int:
	if doy >= 334.0 or doy < 59.0:
		return 0
	if doy < 151.0:
		return 1
	if doy < 243.0:
		return 2
	return 3


# Тип погоди за кидком 0..1 для біома й сезону
func type_for(roll: float, biome: int, season: int) -> String:
	var per: Array = _cum.get(str(biome), _cum.get("default", []))
	if per.is_empty():
		return "clear"
	var cum: Array = per[clampi(season, 0, 3)]
	for i in cum.size():
		if roll < float(cum[i]):
			return _order[i]
	return _order[_order.size() - 1]


# Частка часу, яку тип займає в сезоні в біома (для підпису й тестів)
func share(ty: String, biome: int, season: int) -> float:
	var per: Array = _cum.get(str(biome), _cum.get("default", []))
	var idx: int = _order.find(ty)
	if per.is_empty() or idx < 0:
		return 0.0
	var cum: Array = per[clampi(season, 0, 3)]
	return float(cum[idx]) - (float(cum[idx - 1]) if idx > 0 else 0.0)


func type_name(ty: String) -> String:
	return str(_types.get(ty, {}).get("name", ty))


# Число 0..1 із цілих (однаково на всіх машинах)
func _hash(a: int, b: int, c: int, salt: int) -> float:
	var h: int = (a * 73856093) ^ (b * 19349663) ^ (c * 83492791) ^ (salt * 2654435761) ^ seed_value
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFFFF) / 16777216.0


# Пляма, у яку потрапляє точка (км карти з урахуванням дрейфу): найближчий із 3×3 зсунутих центрів
func spot_of(x_km: float, y_km: float) -> Vector2i:
	var size: float = float(rules.get("spot_km", 7.0))
	var gx: float = x_km / size
	var gy: float = y_km / size
	var ci: int = int(floor(gx))
	var cj: int = int(floor(gy))
	var best := Vector2i(ci, cj)
	var best_d: float = 1.0e9
	for dj in range(-1, 2):
		for di in range(-1, 2):
			var i: int = ci + di
			var j: int = cj + dj
			var cx: float = float(i) + 0.15 + 0.7 * _hash(i, j, 0, 11)
			var cy: float = float(j) + 0.15 + 0.7 * _hash(i, j, 0, 12)
			var d: float = (cx - gx) * (cx - gx) + (cy - gy) * (cy - gy)
			if d < best_d:
				best_d = d
				best = Vector2i(i, j)
	return best


# Кидок плями в періоді k: із шансом keep_chance пляма тримає кидок минулого періоду
func roll_of(spot: Vector2i, k: int) -> float:
	var keep: float = float(rules.get("keep_chance", 0.45))
	var kk: int = k
	for n in KEEP_DEPTH:
		if _hash(spot.x, spot.y, kk, 21) >= keep:
			break
		kk -= 1
	return _hash(spot.x, spot.y, kk, 22)


## Погода в точці карти p (метри), біом, час погоди wtime_h (години), день року й година доби.
## Повертає: type, name, cloud 0..1, rain_mm_h, wind (x схід, y північ, м/с), temp_c, pressure.
## base_t — температура без погоди (WorldEnv.air_temp), якщо вже порахована для цього біома й години
func sample(p: Vector2, biome: int, wtime_h: float, doy: float, hour: float, base_t: float = NAN) -> Dictionary:
	var period: float = maxf(float(rules.get("period_h", 6.0)), 0.5)
	var blend: float = clampf(float(rules.get("blend_h", 1.0)), 0.0, period)
	var x_km: float = p.x / 1000.0 - float(rules.get("drift_kmh", 1.2)) * wtime_h
	var y_km: float = p.y / 1000.0
	var spot: Vector2i = spot_of(x_km, y_km)
	var fk: float = wtime_h / period
	var k: int = int(floor(fk))
	var season: int = season_of(doy)
	if is_nan(base_t):
		base_t = WorldEnv.air_temp(biome, hour, doy)
	var a: Dictionary = _state(spot, k, biome, season, base_t)
	var into: float = (fk - float(k)) * period
	if blend <= 0.0 or into < period - blend:
		return a
	var b: Dictionary = _state(spot, k + 1, biome, season, base_t)
	var w: float = smoothstep(0.0, 1.0, (into - (period - blend)) / blend)
	var r: Dictionary = (b if w >= 0.5 else a).duplicate()
	for key in ["cloud", "rain_mm_h", "temp_c", "pressure"]:
		r[key] = lerpf(float(a[key]), float(b[key]), w)
	r["wind"] = (a["wind"] as Vector2).lerp(b["wind"], w)
	return r


func _state(spot: Vector2i, k: int, biome: int, season: int, base_t: float) -> Dictionary:
	var ty: String = type_for(roll_of(spot, k), biome, season)
	var td: Dictionary = _types.get(ty, {})
	var temp: float = base_t + float(td.get("temp", 0.0))
	if (ty == "rain" or ty == "storm") and temp < float(rules.get("snow_below_c", 0.5)):
		var storm: bool = ty == "storm"
		ty = "snow"
		td = _types.get("snow", td)
		temp = base_t + float(td.get("temp", 0.0))
		if storm:
			td = td.duplicate()
			td["wind"] = float(_types.get("storm", {}).get("wind", 12.0))
	# Вітер у середньому із заходу, у кожної плями й періоду свій поворот ±70° і сила ±30%
	var ang: float = deg_to_rad(-70.0 + 140.0 * _hash(spot.x, spot.y, k, 31))
	var spd: float = float(td.get("wind", 3.0)) * (0.7 + 0.6 * _hash(spot.x, spot.y, k, 32))
	var cloud: float = float(td.get("cloud", 0.0))
	var rain: float = float(td.get("rain_mm_h", 0.0))
	return {
		"type": ty, "name": str(td.get("name", ty)), "cloud": cloud, "rain_mm_h": rain,
		"wind": Vector2(cos(ang), sin(ang)) * spd, "temp_c": temp,
		"pressure": 1016.0 - 4.0 * cloud - 2.5 * rain,
	}

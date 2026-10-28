extends RefCounted
## Среда в точке карты для правил персонажа (Actor.tick, travel_speed): биом, вода, температура, ночь.
## Одна функция для игрока и НПС. Если у карты появится своя temperature_at(p) (жаркие горы),
## берётся она; иначе — простая оценка по сезону, часу и биому [Q19: не баланс, оставлено].

const R := preload("res://characters/actor_rules.gd")


static func sample(game: Node, p: Vector2) -> Dictionary:
	var biome: int = int(game.biome_at(p)) if game.has_method("biome_at") else 4
	var water: float = float(game.water_at(p)) if game.has_method("water_at") else 0.0
	var hour: float = 12.0
	var doy: float = 200.0
	var clock: Variant = game.get("clock")
	if clock != null:
		hour = clock.hour_of_day()
		doy = clock.day_of_year()
	var temp: float
	if game.has_method("temperature_at"):
		temp = float(game.temperature_at(p))
	else:
		temp = air_temp(biome, hour, doy)
	# Погода в точке (world_physics.weather_here): тип для штрафа скорости и дождь, мм/ч
	var weather: String = ""
	var rain: float = 0.0
	var physics: Variant = game.get("physics")
	if physics != null and physics.has_method("weather_here") and bool(physics.get("travel_weather")):
		var w: Dictionary = physics.weather_here(p)
		weather = str(w.get("type", ""))
		rain = float(w.get("rain_mm_h", 0.0))
	return {"biome": biome, "water": water, "temp_c": temp, "weather": weather, "rain": rain,
		"night": hour < 5.5 or hour >= 20.5, "hour": hour}


static func air_temp(biome: int, hour: float, doy: float) -> float:
	var c: Dictionary = R.section("climate")
	var seas: float = cos(TAU * (doy - 200.0) / 365.0)   # как seas в world_physics.gd: 1 летом, −1 зимой
	var day: float = cos(TAU * (hour - float(c.get("warmest_hour", 15.0))) / 24.0)
	return float(c.get("mean_c", 12.0)) + float(c.get("season_amp_c", 10.0)) * seas \
		+ float(c.get("day_amp_c", 5.0)) * day + float(R.terrain(biome).get("temp", 0.0))

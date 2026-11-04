extends RefCounted
## Середовище в точці карти для правил персонажа (Actor.tick, travel_speed): біом, вода, температура, ніч.
## Одна функція для гравця й НПС. Якщо в карти з'явиться своя temperature_at(p) (спекотні гори),
## береться вона; інакше — проста оцінка за сезоном, годиною й біомом [Q19: не баланс, залишено].

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
	# Погода в точці (world_physics.weather_here): тип для штрафу швидкості й дощ, мм/год
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
	var seas: float = cos(TAU * (doy - 200.0) / 365.0)   # як seas у world_physics.gd: 1 улітку, −1 узимку
	var day: float = cos(TAU * (hour - float(c.get("warmest_hour", 15.0))) / 24.0)
	return float(c.get("mean_c", 12.0)) + float(c.get("season_amp_c", 10.0)) * seas \
		+ float(c.get("day_amp_c", 5.0)) * day + float(R.terrain(biome).get("temp", 0.0))

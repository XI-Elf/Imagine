class_name WorldPhysics
extends Node
## Фізика планети. Окрема сцена: бере час із GameClock і рахує астрономію (схилення сонця,
## фаза й схилення місяця) і сезон. Погода простая: по сезону и биому (weather/simple_weather.gd,
## таблицы в data/weather/weather.json). Отсюда шейдер получает облака, дождь и ветер текстурами
## atm_a/atm_b (сетка NX x NY на всю планету, считается только окно карты), а правила персонажа —
## погоду в точке (weather_here). Усе, що залежить від місця (висота сонця, місцевий час), шейдер
## рахує сам за широтою і довготою.
## Тут же реєструються повільні процеси (фізичні й хімічні), які ідуть за ігровим часом.

signal weather_updated

# Мінімальне освітлення вночі (0 = повна темрява)
@export var night_light: float = 0.10
# Скорость погоды: сколько часов погоды проходит за час игры (клавиши , и .)
@export var weather_speed: float = 1.0
# Не чаще стольких пересчётов текстур погоды в секунду
@export var updates_per_second: float = 2.0

# Не частіше 30 разів на секунду
const MIN_INTERVAL: float = 1.0 / 30.0
# Период сдвига мелких деталей облаков в шейдере, секунды игры
const FLOW_PERIOD: float = 7200.0
# Доступные скорости погоды (клавиши , и .)
const WEATHER_SPEEDS: Array = [0.25, 0.5, 1.0, 2.0, 4.0]
static var COMPASS: Array = [I18n.t("С"), I18n.t("СВ"), I18n.t("В"), I18n.t("ЮВ"), I18n.t("Ю"), I18n.t("ЮЗ"), I18n.t("З"), I18n.t("СЗ")]
# Сетка текстур погоды на всю планету (как была у модели атмосферы: шейдер берёт окно ATM_*)
const NX: int = 144
const NY: int = 72
# Версия состояния погоды в сохранении
const STATE_VERSION: int = 1
# Сколько клеток окна погоды пересчитывать за кадр (окно ~700 клеток)
const CELLS_PER_FRAME: int = 120
const SimpleWeather := preload("res://weather/simple_weather.gd")
const WorldEnv := preload("res://characters/world_env.gd")

# Розмір карти: ширина = довжина екватора, висота = від полюса до полюса
var world_w: float = 36000.0
var world_h: float = 18000.0

var clock: GameClock
# Карта мира (game.gd): биомы и окно ATM_ORIGIN / ATM_SPAN / MAP_SIZE. Без неё всё — пустошь
var game: Node
# Лічильник змін: коли він росте, треба передати нові значення в шейдер
var version: int = 0

# Астрономія (спільна для всієї планети)
var decl: float = 0.0
var utc_h: float = 6.0
var moon_decl: float = 0.0
var moon_phase: float = 0.0
var moon_illum: float = 0.0
var subsolar_lat: float = 0.0
var subsolar_lon: float = 0.0
# Час і сезон
var doy: float = 105.0
var seas: float = 0.0
var seas_m: float = 0.0
var summer: float = 0.5
# Погода
var weather: SimpleWeather
var drift_scale: float = 0.02
var flow_phase: float = 0.0
var tex_a: ImageTexture
var tex_b: ImageTexture
# Время погоды, часы (идёт со скоростью weather_speed от игрового)
var weather_hours: float = 0.0
# Совместимость с world_save.gd: фонового потока больше нет
var model: Object = null
# Погода мешает ходу героя и НПС (world_env). Автотесты, где важен темп шагов, выключают
var travel_weather: bool = true
var turbo: bool = false
var preload_state := PackedByteArray()   # задать до setup, чтобы продолжить с сохранённой погоды

var _since: float = 0.0
var _last_t: float = -1.0
var _processes: Array = []
var _last_weather_t: float = 0.0
var _upd_since: float = 1.0e9
# Клетки текстуры в окне карты: индекс, точка карты (м), биом
var _cells_idx := PackedInt32Array()
var _cells_p := PackedVector2Array()
var _cells_biome := PackedInt32Array()
var _cells_ready: bool = false
# Проход по окну: позиция, игровые часы с прошлого прохода, день, час, температура биомов без погоды
var _pass_pos: int = 0
var _pass_game_h: float = 0.0
var _pass_doy: float = 0.0
var _pass_hour: float = 0.0
var _pass_base_t: Dictionary = {}
# Облачность 0..1 и дождь мм/ч по клеткам до сглаживания
var _cloud := PackedFloat32Array()
var _rain := PackedFloat32Array()
var _img_a: Image
var _img_b: Image
var _snap_u := PackedFloat32Array()
var _snap_v := PackedFloat32Array()
var _snap_p := PackedFloat32Array()
var _snap_ry := PackedFloat32Array()


# Підключає годинник. Викликається один раз після створення
func setup(game_clock: GameClock, width_m: float, height_m: float) -> void:
	clock = game_clock
	world_w = width_m
	world_h = height_m
	weather = SimpleWeather.new()
	# Скорость из старых сохранений (модель атмосферы, 10..240) — к обычной
	if not WEATHER_SPEEDS.has(weather_speed):
		weather_speed = 1.0
	var n: int = NX * NY
	_snap_u.resize(n)
	_snap_v.resize(n)
	_snap_p.resize(n)
	_snap_p.fill(1013.0)
	_snap_ry.resize(n)
	_cloud.resize(n)
	_cloud.fill(0.1)
	_rain.resize(n)
	_img_a = Image.create(NX, NY, false, Image.FORMAT_RGBA8)
	_img_a.fill(Color(0.1, 0.0, 0.0, 0.0))
	_img_b = Image.create(NX, NY, false, Image.FORMAT_RGBA8)
	_img_b.fill(Color(0.5, 0.5, 0.5, 0.0))
	tex_a = ImageTexture.create_from_image(_img_a)
	tex_b = ImageTexture.create_from_image(_img_b)
	if not preload_state.is_empty():
		load_state(preload_state)
		preload_state = PackedByteArray()
	_last_weather_t = clock.total_seconds
	clock.year_changed.connect(_on_year_changed)
	force_update()
	_update_weather(true)
	# Приклад повільного процесу: щогодини перераховуємо, де сонце в зеніті
	register_process(I18n.t("точка в зените"), 3600.0, _proc_subsolar)
	_proc_subsolar(0.0)


func _process(delta: float) -> void:
	if clock == null:
		return
	flow_phase = fposmod(clock.total_seconds / FLOW_PERIOD, 1.0)
	_upd_since += delta
	if _pass_pos > 0 or _upd_since >= 1.0 / maxf(updates_per_second, 0.1):
		_update_weather(false)
	_since += delta
	if _since < MIN_INTERVAL:
		return
	_since = 0.0
	# Якщо час не змінився (пауза), нічого перераховувати не треба. Порівнюємо точно: is_equal_approx
	# має відносний допуск 1e-5, а це ~90 с ігрового часу на початку гри і ще більше далі,
	# тому світ оновлювався б лише раз на 90 с на швидкості x1 і ривками на x60
	if clock.total_seconds == _last_t:
		return
	var dt_game: float = clock.total_seconds - _last_t
	_last_t = clock.total_seconds
	_compute()
	_run_processes(dt_game)


# ---------------------------------------------------------------------
# ПОГОДА
# ---------------------------------------------------------------------
# Точка карты (м) для точки исходной сетки планеты (src: 0..world_w, 0..world_h)
func _map_of_src(src: Vector2) -> Vector2:
	if game == null:
		return src
	return (src - game.ATM_ORIGIN) / game.ATM_SPAN * game.MAP_SIZE


# Точка карты для широты и долготы (радианы), обратно lat_of / lon_of
func map_point(lat: float, lon: float) -> Vector2:
	return _map_of_src(Vector2((lon / TAU + 0.5) * world_w, (0.5 - lat / PI) * world_h))


func _biome(p: Vector2) -> int:
	if game != null and game.has_method("biome_at"):
		return int(game.biome_at(p))
	return 4


# Клетки текстуры над картой (с полем в клетку) и их биом: что чаще всего на 4x4 точках клетки.
# Карта грузится после setup, поэтому вызывается, пока биомы не появятся
func _build_cells() -> void:
	_cells_idx = PackedInt32Array()
	_cells_p = PackedVector2Array()
	_cells_biome = PackedInt32Array()
	var size: Vector2 = game.MAP_SIZE if game != null else Vector2(world_w, world_h)
	var cell: Vector2 = _map_of_src(Vector2(world_w / NX, world_h / NY)) - _map_of_src(Vector2.ZERO)
	var seen_land: bool = false
	for j in NY:
		for i in NX:
			var p: Vector2 = _map_of_src(Vector2((i + 0.5) * world_w / NX, (j + 0.5) * world_h / NY))
			if p.x < -cell.x or p.y < -cell.y or p.x > size.x + cell.x or p.y > size.y + cell.y:
				continue
			var votes: Dictionary = {}
			for sy in 4:
				for sx in 4:
					var q: Vector2 = p + cell * Vector2((sx + 0.5) / 4.0 - 0.5, (sy + 0.5) / 4.0 - 0.5)
					var b: int = _biome(q.clamp(Vector2.ZERO, size - Vector2.ONE))
					if b > 0:
						votes[b] = int(votes.get(b, 0)) + 1
			var best: int = 1
			var best_n: int = 0
			for b in votes:
				if int(votes[b]) > best_n:
					best_n = int(votes[b])
					best = int(b)
			seen_land = seen_land or best_n > 0
			_cells_idx.append(j * NX + i)
			_cells_p.append(p)
			_cells_biome.append(best)
	_cells_ready = seen_land or game == null


# Время погоды идёт за игровым. Окно карты пересчитывается проходами: за кадр не больше
# CELLS_PER_FRAME клеток, текстуры обновляются в конце прохода (без рывков кадра). force — весь проход сразу
func _update_weather(force: bool) -> void:
	if weather == null:
		return
	if _pass_pos == 0:
		var dg: float = clock.total_seconds - _last_weather_t
		_last_weather_t = clock.total_seconds
		if dg > 0.0:
			weather_hours += dg / 3600.0 * weather_speed
		if not force and dg == 0.0 and _cells_ready:
			return
		if not _cells_ready:
			_build_cells()
		_pass_game_h = maxf(dg, 0.0) / 3600.0
		_pass_doy = clock.day_of_year()
		_pass_hour = clock.hour_of_day()
		_pass_base_t.clear()
	var stop: int = _cells_idx.size() if force else mini(_pass_pos + CELLS_PER_FRAME, _cells_idx.size())
	for n in range(_pass_pos, stop):
		var k: int = _cells_idx[n]
		var b: int = _cells_biome[n]
		if not _pass_base_t.has(b):
			_pass_base_t[b] = WorldEnv.air_temp(b, _pass_hour, _pass_doy)
		var w: Dictionary = weather.sample(_cells_p[n], b, weather_hours, _pass_doy, _pass_hour, _pass_base_t[b])
		var wind: Vector2 = w["wind"]
		var rain: float = float(w["rain_mm_h"])
		_snap_u[k] = wind.x
		_snap_v[k] = wind.y
		_snap_p[k] = float(w["pressure"])
		_snap_ry[k] += rain * _pass_game_h
		_cloud[k] = float(w["cloud"])
		_rain[k] = rain
	_pass_pos = stop
	if _pass_pos < _cells_idx.size():
		return
	_pass_pos = 0
	_upd_since = 0.0
	_write_textures()
	tex_a.update(_img_a)
	tex_b.update(_img_b)
	# Детали облаков в шейдере сносит ветром (~4,5 м/с) примерно с той же скоростью, что и пятна погоды
	drift_scale = float(weather.rules.get("drift_kmh", 1.2)) / 3.6 / 4.5 * weather_speed
	weather_updated.emit()


# Облака и дождь в текстуру сглаженными (два прохода 3x3): у пятен погоды прямые края по клеткам сетки
func _write_textures() -> void:
	var c: PackedFloat32Array = _cloud
	var r: PackedFloat32Array = _rain
	for rep in 2:
		var c2: PackedFloat32Array = c.duplicate()
		var r2: PackedFloat32Array = r.duplicate()
		for k in _cells_idx:
			var i: int = k % NX
			var j: int = k / NX
			var sc: float = 0.0
			var sr: float = 0.0
			var wsum: float = 0.0
			for dj in range(-1, 2):
				var jj: int = clampi(j + dj, 0, NY - 1)
				for di in range(-1, 2):
					var kk: int = jj * NX + posmod(i + di, NX)
					var wt: float = 4.0 if (di == 0 and dj == 0) else (2.0 if (di == 0 or dj == 0) else 1.0)
					sc += c[kk] * wt
					sr += r[kk] * wt
					wsum += wt
			c2[k] = sc / wsum
			r2[k] = sr / wsum
		c = c2
		r = r2
	for k in _cells_idx:
		var i: int = k % NX
		var j: int = k / NX
		_img_a.set_pixel(i, j, Color(c[k], clampf(r[k] / 8.0, 0.0, 1.0), 0.0, 0.0))
		_img_b.set_pixel(i, j, Color(clampf((_snap_u[k] + 25.0) / 50.0, 0.0, 1.0), clampf((_snap_v[k] + 25.0) / 50.0, 0.0, 1.0), 0.5, 0.0))


## Погода в точке карты (м): type ("clear", "cloudy", "fog", "rain", "storm", "snow"), name, cloud,
## rain_mm_h, wind (м/с, x восток, y север), temp_c, pressure. Одна функция для игрока, НПС и подсказки
func weather_here(p: Vector2) -> Dictionary:
	if weather == null or clock == null:
		return {}
	return weather.sample(p, _biome(p), weather_hours, clock.day_of_year(), clock.hour_of_day())


# Сохранение мира: время погоды и осадки за год (погода по времени восстанавливается сама)
func export_state() -> PackedByteArray:
	return var_to_bytes({"v": STATE_VERSION, "hours": weather_hours, "ry": _snap_ry})


# Состояние из сохранения; чужое (старой модели атмосферы) пропускается, погода начнётся заново
func load_state(bytes: PackedByteArray) -> bool:
	if bytes.size() < 8:
		return false
	var d: Variant = bytes_to_var(bytes)
	if not (d is Dictionary) or int(d.get("v", 0)) != STATE_VERSION:
		return false
	weather_hours = float(d.get("hours", 0.0))
	var ry: Variant = d.get("ry")
	if ry is PackedFloat32Array and ry.size() == NX * NY:
		_snap_ry = ry
	return true


# Змінює швидкість погоди на крок по списку швидкостей
func change_weather_speed(step: int) -> void:
	var idx: int = 0
	var best: float = 1.0e9
	for i in WEATHER_SPEEDS.size():
		var diff: float = absf(float(WEATHER_SPEEDS[i]) - weather_speed)
		if diff < best:
			best = diff
			idx = i
	idx = clampi(idx + step, 0, WEATHER_SPEEDS.size() - 1)
	weather_speed = float(WEATHER_SPEEDS[idx])


# Подготовки атмосферы больше нет: погода готова сразу
func spinup_progress() -> float:
	return 1.0


func is_spinning_up() -> bool:
	return false


# Рядок стану погоди для підказки
func status_text() -> String:
	return I18n.t("Погода: сезон %s, скорость x%s (клавиши , и .)") % [GameClock.SEASON_NAMES[clock.season()], str(weather_speed)]


# Білінійна вибірка з сітки погоди за широтою і довготою в радіанах
func _sample(arr: PackedFloat32Array, lat: float, lon: float) -> float:
	if arr.size() < NX * NY:
		return 0.0
	var fi: float = (lon / TAU + 0.5) * float(NX) - 0.5
	var fj: float = clampf((0.5 - lat / PI) * float(NY) - 0.5, 0.0, float(NY - 1))
	var i0: int = posmod(int(floor(fi)), NX)
	var i1: int = (i0 + 1) % NX
	var fx: float = fi - floor(fi)
	var j0: int = int(floor(fj))
	var j1: int = mini(j0 + 1, NY - 1)
	var fy: float = fj - float(j0)
	var a: float = arr[j0 * NX + i0] * (1.0 - fx) + arr[j0 * NX + i1] * fx
	var b: float = arr[j1 * NX + i0] * (1.0 - fx) + arr[j1 * NX + i1] * fx
	return a * (1.0 - fy) + b * fy


# Вітер у точці: x на схід, y на північ, м/с
func wind_at(lat: float, lon: float) -> Vector2:
	var w: Dictionary = weather_here(map_point(lat, lon))
	return w.get("wind", Vector2.ZERO)


# Осадки, накопленные в текущем игровом году, мм
func rain_year_at(lat: float, lon: float) -> float:
	return _sample(_snap_ry, lat, lon)


# Новый игровой год: накопленные осадки обнуляются
func _on_year_changed(_year: int) -> void:
	_snap_ry.fill(0.0)


# Температура воздуха у земли, °C: сезон, час, биом и погода в этом месте
func temperature_at(lat: float, lon: float) -> float:
	var w: Dictionary = weather_here(map_point(lat, lon))
	return float(w.get("temp_c", NAN))


# Тиск на рівні моря, гПа
func pressure_at(lat: float, lon: float) -> float:
	return float(weather_here(map_point(lat, lon)).get("pressure", 1013.0))


# Название погоды в точке (широта, долгота) для подсказки
func weather_name_at(lat: float, lon: float) -> String:
	return str(weather_here(map_point(lat, lon)).get("name", ""))


# Примусовий перерахунок (для старту)
func force_update() -> void:
	_last_t = clock.total_seconds
	_compute()


# ---------------------------------------------------------------------
# РЕЄСТР ПРОЦЕСІВ. Сюди підключаються фізичні й хімічні процеси.
# interval: через скільки ІГРОВИХ секунд викликати.
# callable: функція, яка приймає dt (скільки ігрових секунд минуло з минулого виклику).
# ---------------------------------------------------------------------
func register_process(proc_name: String, interval: float, callable: Callable) -> void:
	_processes.append({"name": proc_name, "interval": interval, "accum": 0.0, "call": callable})


func _run_processes(dt_game: float) -> void:
	for p in _processes:
		p["accum"] = float(p["accum"]) + absf(dt_game)
		if float(p["accum"]) >= float(p["interval"]):
			var dt: float = p["accum"]
			p["accum"] = 0.0
			var fn: Callable = p["call"]
			fn.call(dt)


# Точка на планеті, де сонце зараз у зеніті
func _proc_subsolar(_dt: float) -> void:
	subsolar_lat = decl
	subsolar_lon = wrapf(-(utc_h - 12.0) * PI / 12.0, -PI, PI)


# ---------------------------------------------------------------------
# ГЕОМЕТРІЯ ПЛАНЕТИ. Карта 2D (рівнопроміжна проекція):
# x від 0 до world_w це довгота, y від 0 до world_h це широта від +90 до -90.
# ---------------------------------------------------------------------
func lat_of(y: float) -> float:
	return (0.5 - y / world_h) * PI


# Довгота: 0 посередині карти, на схід додатна. Карта замкнута по x
func lon_of(x: float) -> float:
	return (fposmod(x, world_w) / world_w - 0.5) * TAU


# Напрям на небесне тіло: x на схід, y на південь, z вгору
func _dir_enu(lat: float, d: float, ha: float) -> Vector3:
	var e: float = -cos(d) * sin(ha)
	var n: float = sin(d) * cos(lat) - cos(d) * sin(lat) * cos(ha)
	var u: float = sin(lat) * sin(d) + cos(lat) * cos(d) * cos(ha)
	return Vector3(e, -n, u)


# Висота сонця в градусах у точці з широтою і довготою (радіани)
func sun_elevation_deg_at(lat: float, lon: float) -> float:
	var ha: float = (utc_h - 12.0) * PI / 12.0 + lon
	var u: float = _dir_enu(lat, decl, ha).z
	return rad_to_deg(asin(clampf(u, -1.0, 1.0)))


# Місцевий сонячний час у точці з довготою (радіани)
func local_hour_at(lon: float) -> float:
	return fposmod(utc_h + lon / TAU * 24.0, 24.0)


# Довжина світлого дня на широті (години). 24 це полярний день, 0 це полярна ніч
func day_length_at(lat: float) -> float:
	var c: float = clampf(-tan(lat) * tan(decl), -1.0, 1.0)
	return 24.0 / PI * acos(c)


# Температура на рівні моря за широтою, середньорічна
func zonal_t(lat: float) -> float:
	return 27.0 - 52.0 * pow(absf(lat) / (PI / 2.0), 1.8)


# Скільки метрів землі в одному метрі карти по горизонталі на цій широті
func ground_scale_x(lat: float) -> float:
	return maxf(cos(lat), 0.0)


# Межа снігу (висота, вище якої середня температура нижче нуля) на цій широті
func snowline_at(lat: float) -> float:
	var t0: float = 9.0 + zonal_t(lat) - zonal_t(deg_to_rad(50.0))
	var ampf: float = (0.15 + 0.85 * pow(sin(absf(lat)), 0.9)) / 0.818
	var hemi: float = 1.0 # Один календарний сезон для всієї карти (як у шейдері)
	return clampf((t0 + 9.25 * ampf * seas * hemi + 1.25) / 0.0065, 0.0, 6000.0)


# Рахує все, що залежить від часу
func _compute() -> void:
	var t: float = clock.total_seconds
	doy = clock.day_of_year()
	utc_h = clock.hour_of_day()

	# Сонце: схилення за днем року
	decl = deg_to_rad(23.44) * sin(TAU * (284.0 + doy + 1.0) / 365.0)

	# Місяць: фаза за 29.53 доби
	moon_phase = fposmod(t / 86400.0 / 29.53, 1.0)
	moon_illum = 0.5 - 0.5 * cos(TAU * moon_phase)
	moon_decl = decl * cos(TAU * moon_phase)

	# Пори року (для північної півкулі; шейдер перевертає їх для південної)
	seas = cos(TAU * (doy - 200.0) / 365.0)
	seas_m = cos(TAU * (doy - 215.0) / 365.0)
	summer = 0.5 + 0.5 * seas

	version += 1


# Передає значення в шейдерний матеріал
func apply_to(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("decl", decl)
	mat.set_shader_parameter("utc_h", utc_h)
	mat.set_shader_parameter("moon_decl", moon_decl)
	mat.set_shader_parameter("moon_phase", moon_phase)
	mat.set_shader_parameter("night_light", night_light)
	mat.set_shader_parameter("doy", doy)
	mat.set_shader_parameter("seas", seas)
	mat.set_shader_parameter("seas_m", seas_m)
	mat.set_shader_parameter("summer", summer)
	mat.set_shader_parameter("atm_a", tex_a)
	mat.set_shader_parameter("atm_b", tex_b)
	mat.set_shader_parameter("drift_scale", drift_scale)
	mat.set_shader_parameter("flow_phase", flow_phase)


# Напрямок, ЗВІДКИ дме вітер, словами
func wind_from_name(wv: Vector2) -> String:
	var to_bearing: float = atan2(wv.x, wv.y)
	var from_bearing: float = fposmod(rad_to_deg(to_bearing) + 180.0, 360.0)
	var idx: int = int(round(from_bearing / 45.0)) % 8
	return COMPASS[idx]


func moon_name() -> String:
	if moon_phase < 0.06 or moon_phase > 0.94:
		return I18n.t("новолуние")
	if moon_phase < 0.44:
		return I18n.t("растущая")
	if moon_phase < 0.56:
		return I18n.t("полнолуние")
	return I18n.t("убывающая")

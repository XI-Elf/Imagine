class_name WorldPhysics
extends Node
## Фізика планети. Окрема сцена: бере час із GameClock і рахує астрономію (схилення сонця,
## фаза й схилення місяця) і сезон. Погоду (тиск, вітер, хмари, дощі, фронти) рахує
## AtmosphereModel у фоновому потоці. Усе, що залежить від місця (висота сонця, місцевий
## час, пояс клімату), шейдер рахує сам за широтою і довготою.
## Тут же реєструються повільні процеси (фізичні й хімічні), які ідуть за ігровим часом.

signal weather_updated

# Мінімальне освітлення вночі (0 = повна темрява)
@export var night_light: float = 0.10
# Швидкість погоди: скільки годин моделі проходить за одну годину гри. Планета в 1112 разів
# менша за Землю, тому при 22 хмари повзуть близько 0.2 м/с, а циклон проходить за ~70 хвилин
@export var weather_speed: float = 60.0
# Не більше стільки кроків моделі на секунду: так потік погоди не займає все ядро
@export var max_steps_per_second: float = 3.0
# Готовий стан атмосфери (щоб на старті одразу була погода, зокрема над сушею)
@export var state_file: String = "res://art/map/atmo_state.bin"
# Калибровка осадков (множитель на ячейку модели); для новой карты её пока нет
@export var rain_scale_file: String = ""
# Скільки кроків моделі просчитати на старті, щоб на карті одразу була погода
@export var spinup_steps: int = 120
# Файл із сушею й горами для моделі (144 x 72)
@export var static_file: String = "res://art/map/atmo_static.png"

# Не частіше 30 разів на секунду
const MIN_INTERVAL: float = 1.0 / 30.0
# Радіус Землі до радіуса планети: стільки разів планета менша
const SCALE_DOWN: float = 6371000.0 / 5729.578
# Період зсуву дрібних деталей хмар у шейдері, секунди гри
const FLOW_PERIOD: float = 7200.0
# Доступні швидкості погоди (клавіші , і .)
const WEATHER_SPEEDS: Array = [10.0, 22.0, 60.0, 120.0, 240.0]
const COMPASS: Array = ["С", "СВ", "В", "ЮВ", "Ю", "ЮЗ", "З", "СЗ"]

# Розмір карти: ширина = довжина екватора, висота = від полюса до полюса
var world_w: float = 36000.0
var world_h: float = 18000.0

var clock: GameClock
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
# Погода з моделі атмосфери
var drift_scale: float = 0.02
var flow_phase: float = 0.0
var tex_a: ImageTexture
var tex_b: ImageTexture
var model: AtmosphereModel
var static_missing: bool = false
var state_loaded: bool = false
# Режим быстрой загрузки: поток погоды работает без ограничения скорости (на экране загрузки)
var turbo: bool = false
var _spin_total: int = 1
var _budget: float = 2.0

var _since: float = 0.0
var _last_t: float = -1.0
var _processes: Array = []

# Потік моделі
var _thread: Thread
var _sem := Semaphore.new()
var _mutex := Mutex.new()
var _exit: bool = false
var _busy: bool = false
var _req_steps: int = 0
var _req_doy: float = 105.0
var _req_utc: float = 6.0
var _req_acc: float = 1.0 / 60.0
var _year_reset: bool = false
var _result_ready: bool = false
var _snap: Dictionary = {}
var _accum: float = 0.0
var _spin_left: int = 0
var _model_steps: int = 0
var _snap_u := PackedFloat32Array()
var _snap_v := PackedFloat32Array()
var _snap_p := PackedFloat32Array()
var _snap_ry := PackedFloat32Array()
var _snap_t := PackedFloat32Array()


# Підключає годинник. Викликається один раз після створення
func setup(game_clock: GameClock, width_m: float, height_m: float) -> void:
	clock = game_clock
	world_w = width_m
	world_h = height_m
	force_update()
	_start_model()
	# Приклад повільного процесу: щогодини перераховуємо, де сонце в зеніті
	register_process("точка в зените", 3600.0, _proc_subsolar)
	_proc_subsolar(0.0)


func _exit_tree() -> void:
	if _thread != null:
		_mutex.lock()
		_exit = true
		_mutex.unlock()
		_sem.post()
		_thread.wait_to_finish()


func _process(delta: float) -> void:
	if clock == null:
		return
	flow_phase = fposmod(clock.total_seconds / FLOW_PERIOD, 1.0)
	_update_model(delta)
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
# МОДЕЛЬ АТМОСФЕРИ у фоновому потоці
# ---------------------------------------------------------------------
func _load_static() -> Image:
	if ResourceLoader.exists(static_file):
		var tex: Texture2D = load(static_file)
		var img: Image = tex.get_image()
		if img.is_compressed():
			img.decompress()
		return img
	static_missing = true
	var blank := Image.create(AtmosphereModel.NX, AtmosphereModel.NY, false, Image.FORMAT_RGBA8)
	blank.fill(Color(0.0, 0.0, 0.0, 1.0))
	return blank


func _start_model() -> void:
	model = AtmosphereModel.new()
	model.setup(_load_static(), 12345, clock.day_of_year())
	var snap: Dictionary = model.export_snapshot()
	tex_a = ImageTexture.create_from_image(Image.create_from_data(AtmosphereModel.NX, AtmosphereModel.NY, false, Image.FORMAT_RGBA8, snap["a"]))
	tex_b = ImageTexture.create_from_image(Image.create_from_data(AtmosphereModel.NX, AtmosphereModel.NY, false, Image.FORMAT_RGBA8, snap["b"]))
	_snap_u = snap["u"]
	_snap_v = snap["v"]
	_snap_p = snap["p"]
	_snap_ry = snap["ry"]
	if FileAccess.file_exists(rain_scale_file):
		model.load_rain_scale(FileAccess.get_file_as_bytes(rain_scale_file))
	if not preload_state.is_empty():
		state_loaded = model.load_state(preload_state)
		preload_state = PackedByteArray()
	if not state_loaded and FileAccess.file_exists(state_file):
		state_loaded = model.load_state(FileAccess.get_file_as_bytes(state_file))
	clock.year_changed.connect(_on_year_changed)
	if state_loaded:
		var snap2: Dictionary = model.export_snapshot()
		tex_a.update(Image.create_from_data(AtmosphereModel.NX, AtmosphereModel.NY, false, Image.FORMAT_RGBA8, snap2["a"]))
		tex_b.update(Image.create_from_data(AtmosphereModel.NX, AtmosphereModel.NY, false, Image.FORMAT_RGBA8, snap2["b"]))
		_snap_u = snap2["u"]
		_snap_v = snap2["v"]
		_snap_p = snap2["p"]
		_snap_ry = snap2["ry"]
	drift_scale = weather_speed / SCALE_DOWN
	_last_model_t = clock.total_seconds
	# Із готового стану достатньо короткого розгону, інакше довгий
	_spin_left = 24 if state_loaded else spinup_steps
	_spin_total = maxi(_spin_left, 1)
	_thread = Thread.new()
	_thread.start(_worker)


# Потік: чекає завдання, рахує кроки, пакує результат
func _worker() -> void:
	while true:
		_sem.wait()
		_mutex.lock()
		var ex: bool = _exit
		var n: int = _req_steps
		var d: float = _req_doy
		var u: float = _req_utc
		var af: float = _req_acc
		var yr: bool = _year_reset
		_year_reset = false
		_mutex.unlock()
		if ex:
			return
		model.doy = d
		model.utc_h = u
		model.acc_factor = af
		if yr:
			model.reset_year()
		for k in n:
			model.step(3600.0)
		var snap: Dictionary = model.export_snapshot()
		_mutex.lock()
		_snap = snap
		_result_ready = true
		_busy = false
		_mutex.unlock()


# Сохранение мира: состояние атмосферы, когда фоновый поток свободен (иначе пустой массив)
var preload_state := PackedByteArray()   # задать до setup, чтобы продолжить с сохранённой погоды


func export_state() -> PackedByteArray:
	if model == null:
		return PackedByteArray()
	_mutex.lock()
	var busy: bool = _busy
	_mutex.unlock()
	if busy:
		return PackedByteArray()
	return model.save_state()


# Головний потік: забирає готовий результат і замовляє нову порцію кроків
func _update_model(delta: float) -> void:
	if model == null:
		return
	_mutex.lock()
	var has_result: bool = _result_ready
	var snap: Dictionary = _snap
	_result_ready = false
	var busy: bool = _busy
	_mutex.unlock()
	if has_result:
		tex_a.update(Image.create_from_data(AtmosphereModel.NX, AtmosphereModel.NY, false, Image.FORMAT_RGBA8, snap["a"]))
		tex_b.update(Image.create_from_data(AtmosphereModel.NX, AtmosphereModel.NY, false, Image.FORMAT_RGBA8, snap["b"]))
		_snap_u = snap["u"]
		_snap_v = snap["v"]
		_snap_p = snap["p"]
		_snap_ry = snap["ry"]
		_snap_t = snap.get("t", PackedFloat32Array())
		_model_steps = int(snap["steps"])
		weather_updated.emit()

	# Скільки годин моделі набіглося за ігровий час
	var dg: float = clock.total_seconds - _last_model_t
	_last_model_t = clock.total_seconds
	drift_scale = weather_speed / SCALE_DOWN
	if absf(dg) > 7200.0:
		# Великий стрибок часу (затримка кадрів): стара погода неактуальна, швидко добудовуємо нову
		_accum = 0.0
		_spin_left = maxi(_spin_left, 30)
	elif not clock.paused:
		_accum = minf(_accum + dg * weather_speed / 3600.0, 16.0)
	if turbo:
		_budget = 8.0
	else:
		_budget = minf(_budget + delta * max_steps_per_second, 8.0)
	if busy:
		return
	var steps: int = 0
	if _spin_left > 0:
		steps = mini(mini(_spin_left, 8), maxi(int(_budget), 1))
		_spin_left -= steps
		_budget = maxf(_budget - float(steps), 0.0)
	else:
		steps = mini(mini(int(_accum), 8), int(_budget))
		_accum -= float(steps)
		_budget -= float(steps)
	if steps > 0:
		_mutex.lock()
		_req_steps = steps
		_req_doy = clock.day_of_year()
		_req_utc = clock.hour_of_day()
		_req_acc = 1.0 / weather_speed
		_busy = true
		_mutex.unlock()
		_sem.post()


var _last_model_t: float = 0.0


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


# Частка виконаного початкового розгону атмосфери, від 0 до 1
func spinup_progress() -> float:
	return clampf(1.0 - float(_spin_left) / float(_spin_total), 0.0, 1.0)


# Чи ще йде початковий розгін атмосфери
func is_spinning_up() -> bool:
	return _spin_left > 0


# Рядок стану погоди для підказки
func status_text() -> String:
	if static_missing:
		return "Погода: нет файла atmo_static.png (океан без материков)"
	if _spin_left > 0:
		return "Погода: подготовка атмосферы, осталось %d шагов" % _spin_left
	return "Погода: x%.0f (клавиши , и . меняют), облака ~%.1f м/с, шагов %d" % [weather_speed, 10.0 * drift_scale, _model_steps]


# Білінійна вибірка з полів вітру й тиску (на CPU) за широтою і довготою в радіанах
func _sample(arr: PackedFloat32Array, lat: float, lon: float) -> float:
	if arr.size() < AtmosphereModel.N:
		return 0.0
	var nx: int = AtmosphereModel.NX
	var ny: int = AtmosphereModel.NY
	var fi: float = (lon / TAU + 0.5) * float(nx) - 0.5
	var fj: float = clampf((0.5 - lat / PI) * float(ny) - 0.5, 0.0, float(ny - 1))
	var i0: int = posmod(int(floor(fi)), nx)
	var i1: int = (i0 + 1) % nx
	var fx: float = fi - floor(fi)
	var j0: int = int(floor(fj))
	var j1: int = mini(j0 + 1, ny - 1)
	var fy: float = fj - float(j0)
	var a: float = arr[j0 * nx + i0] * (1.0 - fx) + arr[j0 * nx + i1] * fx
	var b: float = arr[j1 * nx + i0] * (1.0 - fx) + arr[j1 * nx + i1] * fx
	return a * (1.0 - fy) + b * fy


# Вітер у точці: x на схід, y на північ, земні м/с
func wind_at(lat: float, lon: float) -> Vector2:
	return Vector2(_sample(_snap_u, lat, lon), _sample(_snap_v, lat, lon))


# Осадки, накопленные в текущем игровом году, мм (при текущей калибровке они сходятся к годовой норме)
func rain_year_at(lat: float, lon: float) -> float:
	return _sample(_snap_ry, lat, lon)


# Новый игровой год: накопленные осадки обнуляются в потоке перед следующей порцией шагов
func _on_year_changed(_year: int) -> void:
	_mutex.lock()
	_year_reset = true
	_mutex.unlock()


# Температура воздуха у земли по модели, °C (NAN, пока модель не дала первого снимка)
func temperature_at(lat: float, lon: float) -> float:
	if _snap_t.size() < AtmosphereModel.N:
		return NAN
	return _sample(_snap_t, lat, lon)


# Тиск на рівні моря, гПа
func pressure_at(lat: float, lon: float) -> float:
	return _sample(_snap_p, lat, lon)


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
		return "новолуние"
	if moon_phase < 0.44:
		return "растущая"
	if moon_phase < 0.56:
		return "полнолуние"
	return "убывающая"

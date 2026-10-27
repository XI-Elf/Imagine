extends SceneTree
## Простая погода по сезону и биому (weather/simple_weather.gd, world_physics.gd, Q25).
## godot --headless --path game -s res://tests/weather_checks.gd

const SimpleWeather := preload("res://weather/simple_weather.gd")
const WorldEnv := preload("res://characters/world_env.gd")
const PhysicsScene := preload("res://world_physics.tscn")
const GameScript := preload("res://game.gd")

var fails: int = 0
var checks: int = 0


# Карта без картинок: те же окно и размеры, что у game.gd; запад — лес, восток — пустошь, зимой горы
class FakeGame:
	extends Node
	const ATM_ORIGIN := GameScript.ATM_ORIGIN
	const ATM_SPAN := GameScript.ATM_SPAN
	const MAP_SIZE := GameScript.MAP_SIZE
	var clock: GameClock
	var physics: Node
	var calls: int = 0

	func biome_at(p: Vector2) -> int:
		calls += 1
		return 3 if p.x < MAP_SIZE.x * 0.5 else 4


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("FAIL: ", what)


func _initialize() -> void:
	_tables()
	_shares()
	_snow()
	_smooth()
	_moves()
	_physics()
	print("weather_checks: %d/%d | FAIL %d" % [checks - fails, checks, fails])
	quit(1 if fails > 0 else 0)


# Таблицы читаются, у каждого биома и сезона доли в сумме 1, тип по броску детерминирован
func _tables() -> void:
	var w := SimpleWeather.new()
	ok(not w.rules.is_empty(), "data/weather/weather.json читается")
	for b in range(1, 10):
		for s in 4:
			var sum: float = 0.0
			for ty in w._order:
				sum += w.share(ty, b, s)
			ok(absf(sum - 1.0) < 0.001, "биом %d сезон %d: доли в сумме 1 (%.3f)" % [b, s, sum])
	ok(w.type_for(0.0, 4, 2) == "clear" and w.type_for(0.9999, 4, 2) == "storm", "бросок 0 — ясно, ~1 — гроза")
	var p := Vector2(12000.0, 9000.0)
	ok(w.sample(p, 3, 31.3, 120.0, 14.0) == w.sample(p, 3, 31.3, 120.0, 14.0), "одно время и место — одна погода")
	ok(SimpleWeather.season_of(10.0) == 0 and SimpleWeather.season_of(100.0) == 1 \
		and SimpleWeather.season_of(200.0) == 2 and SimpleWeather.season_of(300.0) == 3, "сезоны как у GameClock")


# Частота типов на многих пятнах и периодах совпадает с весами таблицы (keep_chance не сдвигает доли)
func _shares() -> void:
	var w := SimpleWeather.new()
	for cs in [[4, 2], [5, 3], [8, 1]]:
		var counts: Dictionary = {}
		var n: int = 0
		for sx in 40:
			for k in 100:
				var ty: String = w.type_for(w.roll_of(Vector2i(sx, sx * 7 % 13), k), cs[0], cs[1])
				counts[ty] = int(counts.get(ty, 0)) + 1
				n += 1
		for ty in w._order:
			var got: float = float(counts.get(ty, 0)) / float(n)
			var want: float = w.share(ty, cs[0], cs[1])
			ok(absf(got - want) < 0.04, "биом %d сезон %d: %s %.2f ≈ %.2f" % [cs[0], cs[1], ty, got, want])
	# Пустошь летом суше болота осенью
	ok(w.share("clear", 4, 2) > w.share("clear", 5, 3), "пустошь летом ясная чаще, чем болото осенью")
	ok(w.share("fog", 9, 3) > w.share("fog", 4, 3), "в проклятом болоте туман чаще, чем в пустоши")


# Зимой в горах ночью дождь становится снегом; летом в пустоши снега нет
func _snow() -> void:
	var w := SimpleWeather.new()
	var winter: Dictionary = {}
	var summer: Dictionary = {}
	for i in 400:
		var p := Vector2(float(i % 20) * 2100.0, float(i / 20) * 1800.0)
		var a: Dictionary = w.sample(p, 6, float(i) * 7.0, 20.0, 3.0)
		winter[a["type"]] = true
		var b: Dictionary = w.sample(p, 4, float(i) * 7.0, 200.0, 14.0)
		summer[b["type"]] = true
		if a["type"] == "snow":
			ok(float(a["rain_mm_h"]) > 0.0, "снег даёт осадки")
	ok(winter.has("snow"), "зимой в горах бывает снег")
	ok(not winter.has("rain") and not winter.has("storm"), "в мороз нет дождя и грозы")
	ok(not summer.has("snow"), "летом в пустоши снега нет")
	ok(summer.size() >= 4, "летом в пустоши несколько типов погоды (%d)" % summer.size())


# Смена периода плавная: за минуту погоды облачность и дождь меняются чуть-чуть
func _smooth() -> void:
	var w := SimpleWeather.new()
	var worst_c: float = 0.0
	var worst_r: float = 0.0
	for i in 30:
		var p := Vector2(float(i) * 1300.0, float(i) * 900.0)
		var prev: Dictionary = w.sample(p, 3, 0.0, 120.0, 12.0)
		var t: float = 0.0
		while t < 24.0:
			t += 1.0 / 60.0
			var cur: Dictionary = w.sample(p, 3, t, 120.0, 12.0)
			worst_c = maxf(worst_c, absf(float(cur["cloud"]) - float(prev["cloud"])))
			# Граница пятна, пересекающая точку при дрейфе, даёт скачок; его не считаем
			if w.spot_of(p.x / 1000.0 - 1.2 * t, p.y / 1000.0) == w.spot_of(p.x / 1000.0 - 1.2 * (t - 1.0 / 60.0), p.y / 1000.0):
				worst_r = maxf(worst_r, absf(float(cur["rain_mm_h"]) - float(prev["rain_mm_h"])))
			prev = cur
	ok(worst_r < 0.6, "дождь внутри пятна без скачков (макс. %.2f мм/ч за минуту)" % worst_r)
	ok(worst_c <= 0.86, "облачность меняется не больше, чем ясно↔гроза (%.2f)" % worst_c)


# Погода движется: за сутки погоды в точке бывает больше одного типа, а соседние точки чаще совпадают
func _moves() -> void:
	var w := SimpleWeather.new()
	var types: Dictionary = {}
	for h in 48:
		types[w.sample(Vector2(20000.0, 18000.0), 3, float(h), 120.0, 12.0)["type"]] = true
	ok(types.size() >= 2, "за двое суток в точке погода меняется (%d типов)" % types.size())
	var same_near: int = 0
	var same_far: int = 0
	for i in 200:
		var p := Vector2(float(i % 20) * 2000.0, float(i / 20) * 3500.0)
		var t: float = float(i) * 3.0
		var a: String = w.sample(p, 3, t, 120.0, 12.0)["type"]
		if w.sample(p + Vector2(300.0, 0.0), 3, t, 120.0, 12.0)["type"] == a:
			same_near += 1
		if w.sample(p + Vector2(20000.0, 15000.0), 3, t, 120.0, 12.0)["type"] == a:
			same_far += 1
	ok(same_near > same_far, "рядом погода совпадает чаще, чем вдали (%d против %d)" % [same_near, same_far])


# Узел погоды: текстуры для шейдера, погода в точке, сохранение, старые сохранения, скорость
func _physics() -> void:
	var g := FakeGame.new()
	root.add_child(g)
	g.clock = GameClock.new()
	g.add_child(g.clock)
	var ph: Node = PhysicsScene.instantiate()
	g.physics = ph
	g.add_child(ph)
	ph.game = g
	ph.weather_speed = 60.0   # из сохранения старой модели атмосферы
	ph.preload_state = PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
	ph.setup(g.clock, GameScript.SRC_SIZE.x, GameScript.SRC_SIZE.y)
	ok(ph.weather_speed == 1.0, "скорость погоды из старого сохранения сброшена на x1")
	ok(ph.weather_hours == 0.0, "чужое состояние атмосферы не загружается")
	ok(not ph.is_spinning_up() and ph.spinup_progress() == 1.0, "подготовки атмосферы нет")
	ok(ph.tex_a.get_width() == 144 and ph.tex_a.get_height() == 72, "текстура погоды 144×72, как ждёт шейдер")
	var n_cells: int = ph._cells_idx.size()
	ok(n_cells > 400 and n_cells < 1200, "считается только окно карты (%d клеток)" % n_cells)
	ok(ph._cells_biome.has(3) and ph._cells_biome.has(4), "у клеток биомы карты")
	# Время погоды идёт за игровым и со скоростью
	g.clock.total_seconds += 7200.0
	ph._update_weather(true)
	ok(absf(ph.weather_hours - 2.0) < 0.001, "2 часа игры = 2 часа погоды на x1")
	ph.weather_speed = 4.0
	g.clock.total_seconds += 3600.0
	ph._update_weather(true)
	ok(absf(ph.weather_hours - 6.0) < 0.001, "на x4 час игры = 4 часа погоды")
	ph.change_weather_speed(1)
	ok(ph.weather_speed == 4.0, "скорость не выше x4")
	ph.change_weather_speed(-9)
	ok(ph.weather_speed == 0.25, "скорость не ниже x0.25")
	ph.weather_speed = 1.0
	# Скорость пересчёта окна (на экране это 2 раза в секунду)
	var t0: int = Time.get_ticks_usec()
	for i in 5:
		g.clock.total_seconds += 60.0
		ph._update_weather(true)
	var ms: float = float(Time.get_ticks_usec() - t0) / 5000.0
	var per_frame: float = ms * float(ph.CELLS_PER_FRAME) / float(n_cells)
	print("  пересчёт окна погоды: %.1f мс за проход, ~%.1f мс за кадр" % [ms, per_frame])
	ok(per_frame < 5.0, "за кадр погода занимает мало (%.1f мс)" % per_frame)
	# Обычный ход: проход разбит на кадры, текстура обновляется в конце
	g.clock.total_seconds += 60.0
	ph._upd_since = 1.0
	var frames: int = 0
	ph._update_weather(false)
	frames += 1
	while ph._pass_pos > 0 and frames < 50:
		ph._update_weather(false)
		frames += 1
	ok(frames == ceili(float(n_cells) / float(ph.CELLS_PER_FRAME)), "проход окна за %d кадров" % frames)
	# Погода в точке и через широту/долготу — одна и та же
	var p := Vector2(30000.0, 20000.0)
	var here: Dictionary = ph.weather_here(p)
	ok(here.has("type") and here.has("temp_c"), "погода в точке: тип и температура")
	var src: Vector2 = GameScript.ATM_ORIGIN + p / GameScript.MAP_SIZE * GameScript.ATM_SPAN
	var lat: float = ph.lat_of(src.y)
	var lon: float = ph.lon_of(src.x)
	ok(ph.map_point(lat, lon).distance_to(p) < 1.0, "широта/долгота ↔ точка карты")
	ok(absf(ph.temperature_at(lat, lon) - float(here["temp_c"])) < 0.01, "temperature_at = температура погоды в точке")
	ok(ph.weather_name_at(lat, lon) == str(here["name"]), "название погоды для подсказки")
	# Текстура совпадает с погодой клетки
	var k: int = ph._cells_idx[n_cells / 2]
	var w: Dictionary = ph.weather.sample(ph._cells_p[n_cells / 2], ph._cells_biome[n_cells / 2], ph.weather_hours, g.clock.day_of_year(), g.clock.hour_of_day())
	ok(absf(ph._cloud[k] - float(w["cloud"])) < 0.01, "облачность клетки = погода в её центре")
	var lo: float = 1.0
	var hi: float = 0.0
	for kk in ph._cells_idx:
		lo = minf(lo, ph._cloud[kk])
		hi = maxf(hi, ph._cloud[kk])
	var px: float = ph._img_a.get_pixel(k % 144, k / 144).r
	ok(px >= lo - 0.01 and px <= hi + 0.01, "в текстуре сглаженная облачность в пределах окна")
	# Годовые осадки копятся и сохраняются
	for i in 48:
		g.clock.total_seconds += 3600.0
		ph._update_weather(true)
	var ry: float = 0.0
	for v in ph._snap_ry:
		ry += v
	ok(ry > 0.0, "за двое суток где-то выпали осадки")
	var bytes: PackedByteArray = ph.export_state()
	var hours: float = ph.weather_hours
	ph.weather_hours = 0.0
	ph._snap_ry.fill(0.0)
	ok(ph.load_state(bytes) and ph.weather_hours == hours, "состояние погоды сохраняется и читается")
	var ry2: float = 0.0
	for v in ph._snap_ry:
		ry2 += v
	ok(absf(ry2 - ry) < 0.01, "годовые осадки из сохранения")
	ph._on_year_changed(1)
	ok(ph.rain_year_at(lat, lon) == 0.0, "новый год обнуляет осадки")
	# Правила персонажа получают погоду: тип для штрафа скорости и дождь
	var env: Dictionary = WorldEnv.sample(g, p)
	ok(env.get("weather", "") == here_type(ph, p), "world_env: погода в точке")
	ph.travel_weather = false
	ok(WorldEnv.sample(g, p).get("weather", "x") == "", "travel_weather = false: погода не мешает ходу")
	ph.travel_weather = true
	var hero := Actor.new()
	ok(absf(hero.weather_penalty({"weather": "storm"}) - 0.5) < 0.001 and hero.weather_penalty({"weather": "fog"}) == 0.0,
		"штраф скорости: гроза 0,5, туман 0")
	ok(hero.weather_penalty({"weather": "snow"}) > hero.weather_penalty({"weather": "rain"}), "снег мешает идти сильнее дождя")
	g.queue_free()


func here_type(ph: Node, p: Vector2) -> String:
	return str(ph.weather_here(p).get("type", ""))

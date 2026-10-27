class_name AtmosphereModel
extends RefCounted
## Модель атмосфери планети. Сітка 144 x 72 (по 2.5 градуса). Рахується в земних одиницях
## (радіус 6371 км, справжнє обертання), а до маленької планети масштабується при показі.
## Змінні: температура повітря T, вологість q, хмарна вода cw, вологість ґрунту S.
## Тиск і вітер виходять з поля температури (теплові мінімуми й максимуми) плюс кліматичні
## пояси тиску, які зсуваються за сонцем. Вітер: баланс сили тиску, Коріоліса і тертя.
## Перенос температури, вологи і хмар напівлагранжевий (стійкий). Конденсація залежить від
## піднімання повітря: сходження вітру, схили гір, теплі фронти. Це не повна модель погоди,
## але циклони, фронти, мусони й дощова тінь виникають самі.

const NX: int = 144
const NY: int = 72
const N: int = 10368
const EARTH_R: float = 6371000.0
const OMEGA: float = 7.292e-5
const RHO: float = 1.2
const LAT_PTS: Array = [0.0, 12.0, 30.0, 45.0, 62.0, 80.0, 90.0]
const P_PTS: Array = [-5.0, -2.0, 8.0, 1.5, -10.0, 0.5, 3.0]
const SMW: Array = [0.0219, 0.2283, 0.4985, 0.2283, 0.0219]

var a_t: float = 3.0
var latent: float = 0.10
var eddy_sigma: float = 0.55
var doy: float = 105.0
var rng := RandomNumberGenerator.new()
var steps_done: int = 0
# Время на нулевом меридиане, часы (задаётся снаружи на каждую порцию шагов)
var utc_h: float = 6.0
# Сколько игрового времени приходится на один шаг модели: нужно для годового учёта осадков.
# Один шаг модели это 1 час модели, а в игровом часу weather_speed таких шагов
var acc_factor: float = 1.0 / 60.0
# Скільки кроків враховано в довгому середньому зміщенні температури
var anom_steps: int = 0

# Статичні поля
var land := PackedFloat32Array()
var hgt := PackedFloat32Array()
var dhdx := PackedFloat32Array()
var dhdy := PackedFloat32Array()
var eps := PackedFloat32Array()
# Параметри по рядках широти
var phi_r := PackedFloat32Array()
var cos_r := PackedFloat32Array()
var dxm := PackedFloat32Array()
var f_r := PackedFloat32Array()
var tz_r := PackedFloat32Array()
var amp_r := PackedFloat32Array()
var hemi_r := PackedFloat32Array()
var lat_deg := PackedFloat32Array()
var track_r := PackedFloat32Array()
var dy: float = 1.0

# Стан
var T := PackedFloat32Array()
var q := PackedFloat32Array()
var cw := PackedFloat32Array()
var S := PackedFloat32Array()
var u := PackedFloat32Array()
var v := PackedFloat32Array()
var p := PackedFloat32Array()
var rain := PackedFloat32Array()
var cf := PackedFloat32Array()
var ts_cur := PackedFloat32Array()
# Температура поверхности с суточным ходом (для конвекции, испарения и бриза)
var ts_dyn := PackedFloat32Array()
# Суточная добавка к давлению (доля от -1 до 1): днём над сушей тепловой минимум
var dpt := PackedFloat32Array()
# Долгота колонки в часах (для местного солнечного времени)
var lon_h := PackedFloat32Array()
# Калибровка осадков по годовым нормам таблицы биомов (по ячейкам) и накопленное за игровой год
var rain_scale := PackedFloat32Array()
var rain_year := PackedFloat32Array()
# Середнє зміщення (T повітря - T поверхні) у кожній клітинці: його віднімаємо, лишається погода
var anom_mean := PackedFloat32Array()

# Тимчасові масиви
var _nT := PackedFloat32Array()
var _nq := PackedFloat32Array()
var _ncw := PackedFloat32Array()
var _div := PackedFloat32Array()
var _adv := PackedFloat32Array()
var _tsl := PackedFloat32Array()
var _n0 := PackedFloat32Array()
var _n1 := PackedFloat32Array()
var _n2 := PackedFloat32Array()
var _belt := PackedFloat32Array()
var _tzm := PackedFloat32Array()
var _wx := PackedFloat32Array()
var _wy := PackedFloat32Array()
var _kx: int = 8
var _ky: int = 5


func _make(size: int) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(size)
	a.fill(0.0)
	return a


func _qsat(t: float) -> float:
	var es: float = 6.11 * exp(17.27 * t / (t + 237.3))
	return 622.0 * es / (1013.0 - es)


# static_img: картинка 144 x 72, канали R суша, G гори. start_doy: день року
func setup(static_img: Image, seed_value: int, start_doy: float) -> void:
	rng.seed = seed_value
	doy = start_doy
	var img: Image = static_img
	if img.get_width() != NX or img.get_height() != NY:
		img = static_img.duplicate()
		img.resize(NX, NY, Image.INTERPOLATE_BILINEAR)
	land = _make(N)
	hgt = _make(N)
	dhdx = _make(N)
	dhdy = _make(N)
	eps = _make(N)
	T = _make(N)
	q = _make(N)
	cw = _make(N)
	S = _make(N)
	u = _make(N)
	v = _make(N)
	p = _make(N)
	rain = _make(N)
	cf = _make(N)
	ts_cur = _make(N)
	anom_mean = _make(N)
	ts_dyn = _make(N)
	dpt = _make(N)
	rain_scale = _make(N)
	rain_scale.fill(1.0)
	rain_year = _make(N)
	lon_h = _make(NX)
	_nT = _make(N)
	_nq = _make(N)
	_ncw = _make(N)
	_div = _make(N)
	_adv = _make(N)
	_tsl = _make(N)
	_n0 = _make(N)
	_n1 = _make(N)
	_n2 = _make(N)
	phi_r = _make(NY)
	cos_r = _make(NY)
	dxm = _make(NY)
	f_r = _make(NY)
	tz_r = _make(NY)
	amp_r = _make(NY)
	hemi_r = _make(NY)
	lat_deg = _make(NY)
	track_r = _make(NY)
	_belt = _make(NY)
	_tzm = _make(NY)

	var dphi: float = PI / float(NY)
	var dlam: float = TAU / float(NX)
	dy = EARTH_R * dphi
	for i0 in NX:
		lon_h[i0] = (-PI + (float(i0) + 0.5) * dlam) / TAU * 24.0
	for j in NY:
		var ph: float = PI / 2.0 - (float(j) + 0.5) * dphi
		phi_r[j] = ph
		cos_r[j] = cos(ph)
		dxm[j] = EARTH_R * maxf(cos(ph), 0.08) * dlam
		f_r[j] = 2.0 * OMEGA * sin(ph)
		tz_r[j] = 27.0 - 52.0 * pow(absf(ph) / (PI / 2.0), 1.8)
		amp_r[j] = (0.15 + 0.85 * pow(absf(sin(ph)), 0.9)) / 0.818
		hemi_r[j] = 1.0 # Один календарний сезон для всієї карти, як у шейдері (широта лишається в амплітуді)
		lat_deg[j] = rad_to_deg(ph)
		var dist_track: float = (absf(lat_deg[j]) - 50.0) / 18.0
		track_r[j] = exp(-dist_track * dist_track)

	for j in NY:
		for i in NX:
			var c: Color = img.get_pixel(i, j)
			var k: int = j * NX + i
			land[k] = c.r
			hgt[k] = c.r * (60.0 + 2400.0 * pow(c.g, 1.5))
	for j in NY:
		for i in NX:
			var k2: int = j * NX + i
			dhdx[k2] = (hgt[j * NX + posmod(i + 1, NX)] - hgt[j * NX + posmod(i - 1, NX)]) / (2.0 * dxm[j])
			if j == 0:
				dhdy[k2] = (hgt[k2] - hgt[k2 + NX]) / dy
			elif j == NY - 1:
				dhdy[k2] = (hgt[k2 - NX] - hgt[k2]) / dy
			else:
				dhdy[k2] = (hgt[k2 - NX] - hgt[k2 + NX]) / (2.0 * dy)
			eps[k2] = 2.0e-5 + 2.0e-5 * land[k2] + 3.0e-5 * clampf(hgt[k2] / 1500.0, 0.0, 1.0)

	# Ядра розмиття для випадкових «вихорів»
	_wx = _make(2 * _kx + 1)
	_wy = _make(2 * _ky + 1)
	var sx: float = 3.8
	var sy: float = 2.5
	var tx: float = 0.0
	var ty: float = 0.0
	for d in range(-_kx, _kx + 1):
		_wx[d + _kx] = exp(-0.5 * float(d * d) / (sx * sx))
		tx += _wx[d + _kx]
	for d in range(-_ky, _ky + 1):
		_wy[d + _ky] = exp(-0.5 * float(d * d) / (sy * sy))
		ty += _wy[d + _ky]
	for d in range(2 * _kx + 1):
		_wx[d] = _wx[d] / tx
	for d in range(2 * _ky + 1):
		_wy[d] = _wy[d] / ty

	_surface_t()
	for k3 in N:
		T[k3] = ts_cur[k3]
		q[k3] = 0.7 * _qsat(T[k3])
		S[k3] = 0.5
	_step_wind()


# Завантажує готовий стан атмосфери (T, q, cw, S, середнє зміщення) з файлу, щоб на старті
# вже була справжня погода, зокрема хмари над сушею. Формат: п'ять масивів float32 по 10368
func load_state(bytes: PackedByteArray) -> bool:
	var arr: PackedFloat32Array = bytes.to_float32_array()
	if arr.size() != 5 * N:
		return false
	for k in N:
		T[k] = arr[k]
		q[k] = arr[N + k]
		cw[k] = arr[2 * N + k]
		S[k] = arr[3 * N + k]
		anom_mean[k] = arr[4 * N + k]
	anom_steps = 720
	_surface_t()
	_step_wind()
	return true


# Состояние для сохранения мира: тот же формат, что читает load_state
func save_state() -> PackedByteArray:
	var arr := PackedFloat32Array()
	arr.resize(5 * N)
	for k in N:
		arr[k] = T[k]
		arr[N + k] = q[k]
		arr[2 * N + k] = cw[k]
		arr[3 * N + k] = S[k]
		arr[4 * N + k] = anom_mean[k]
	return arr.to_byte_array()


# Калибровка осадков по нормам: множитель на ячейку, float32 по 10368 значений
func load_rain_scale(bytes: PackedByteArray) -> bool:
	var arr: PackedFloat32Array = bytes.to_float32_array()
	# Допускаем и старый формат из 12 месячных слоёв: берём их среднее
	var layers: int = int(float(arr.size()) / float(N))
	if layers < 1 or arr.size() != layers * N:
		return false
	for k in N:
		var sum: float = 0.0
		for l in layers:
			sum += arr[l * N + k]
		rain_scale[k] = clampf(sum / float(layers), 0.05, 10.0)
	return true


# Начинает новый игровой год: обнуляет накопленные осадки
func reset_year() -> void:
	rain_year.fill(0.0)


# Температура поверхні за сезоном: суша прогрівається сильніше й раніше за море
func _surface_t() -> void:
	var seas: float = cos(TAU * (doy - 200.0) / 365.0)
	var seasm: float = cos(TAU * (doy - 215.0) / 365.0)
	for j in NY:
		var tl_base: float = tz_r[j] + 12.0 * amp_r[j] * hemi_r[j] * seas
		var ts_base: float = tz_r[j] + 5.5 * amp_r[j] * hemi_r[j] * seasm
		for i in NX:
			var k: int = j * NX + i
			var tl: float = tl_base - 0.0065 * hgt[k]
			ts_cur[k] = land[k] * tl + (1.0 - land[k]) * ts_base


# Кліматичні пояси тиску (гПа відносно 1013), зсунуті за сонцем
func _belts_rows() -> void:
	var shift: float = 6.0 * cos(TAU * (doy - 200.0) / 365.0)
	var raw := PackedFloat32Array()
	raw.resize(NY)
	for j in NY:
		var l: float = absf(lat_deg[j] - shift)
		var val: float = P_PTS[6]
		if l <= LAT_PTS[0]:
			val = P_PTS[0]
		else:
			for n in range(1, 7):
				if l <= LAT_PTS[n]:
					var t: float = (l - LAT_PTS[n - 1]) / (LAT_PTS[n] - LAT_PTS[n - 1])
					val = P_PTS[n - 1] + (P_PTS[n] - P_PTS[n - 1]) * t
					break
		raw[j] = val
	var wsum: float = 0.0
	for d in 5:
		wsum += SMW[d]
	for j in NY:
		var s: float = 0.0
		for d in range(-2, 3):
			var jj: int = clampi(j + d, 0, NY - 1)
			s += raw[jj] * SMW[d + 2]
		_belt[j] = s / wsum


# Тиск із температури і поясів, потім вітер із балансу тиску, Коріоліса і тертя
func _step_wind() -> void:
	_belts_rows()
	for j in NY:
		var s: float = 0.0
		for i in NX:
			var k: int = j * NX + i
			_tsl[k] = T[k] + 0.0065 * hgt[k]
			s += _tsl[k]
		_tzm[j] = s / float(NX)
	for j in NY:
		for i in NX:
			var k2: int = j * NX + i
			p[k2] = 1013.0 + _belt[j] - a_t * (_tsl[k2] - _tzm[j]) - 2.4 * dpt[k2]
	for j in NY:
		var dx2: float = 2.0 * dxm[j]
		var f: float = f_r[j]
		for i in NX:
			var k3: int = j * NX + i
			var gx: float = (p[j * NX + posmod(i + 1, NX)] - p[j * NX + posmod(i - 1, NX)]) * 100.0 / dx2 / RHO
			var gy: float = 0.0
			if j == 0:
				gy = (p[k3] - p[k3 + NX]) * 100.0 / dy / RHO
			elif j == NY - 1:
				gy = (p[k3 - NX] - p[k3]) * 100.0 / dy / RHO
			else:
				gy = (p[k3 - NX] - p[k3 + NX]) * 100.0 / (2.0 * dy) / RHO
			var e: float = eps[k3]
			var d: float = e * e + f * f
			var uu: float = (-e * gx - f * gy) / d
			var vv: float = (-e * gy + f * gx) / d
			var sp: float = sqrt(uu * uu + vv * vv)
			var kf: float = 1.0
			if sp > 0.000000001:
				kf = 15.0 * tanh(sp / 15.0) / sp
			u[k3] = uu * kf
			v[k3] = vv * kf


# Випадкові збурення температури в штормових поясах: з них ростуть циклони
func _make_noise() -> void:
	for k in N:
		_n0[k] = rng.randfn()
	for j in NY:
		for i in NX:
			var s: float = 0.0
			for d in range(-_kx, _kx + 1):
				s += _n0[j * NX + posmod(i + d, NX)] * _wx[d + _kx]
			_n1[j * NX + i] = s
	var sq: float = 0.0
	for j in NY:
		for i in NX:
			var s2: float = 0.0
			for d in range(-_ky, _ky + 1):
				var jj: int = clampi(j + d, 0, NY - 1)
				s2 += _n1[jj * NX + i] * _wy[d + _ky]
			_n2[j * NX + i] = s2
			sq += s2 * s2
	var inv_std: float = 1.0 / (sqrt(sq / float(N)) + 0.000000001)
	for k2 in N:
		_n2[k2] = _n2[k2] * inv_std


# Один крок моделі (dt в секундах моделі, зазвичай 3600). День року задається ззовні
func step(dt: float) -> void:
	_surface_t()
	# Суточный ход по местному солнечному времени: суша ±6 К, море ±0.5 К
	for j0 in NY:
		for i0 in NX:
			var k0: int = j0 * NX + i0
			var lh: float = fposmod(utc_h + lon_h[i0], 24.0)
			var amp: float = 6.0 * land[k0] + 0.5 * (1.0 - land[k0])
			var dc: float = cos(TAU * (lh - 15.0) / 24.0)
			ts_dyn[k0] = ts_cur[k0] + amp * dc
			dpt[k0] = amp * dc / 6.0
	# 1. перенос T, q, cw напівлагранжевим методом
	for j in NY:
		var dxj: float = dxm[j]
		for i in NX:
			var k: int = j * NX + i
			var xi: float = float(i) - u[k] * dt / dxj
			var yj: float = clampf(float(j) + v[k] * dt / dy, 0.0, float(NY - 1))
			var x0f: float = floor(xi)
			var fx: float = xi - x0f
			var x0: int = posmod(int(x0f), NX)
			var x1: int = (x0 + 1) % NX
			var y0: int = int(floor(yj))
			var y1: int = mini(y0 + 1, NY - 1)
			var fy: float = yj - float(y0)
			var k00: int = y0 * NX + x0
			var k10: int = y0 * NX + x1
			var k01: int = y1 * NX + x0
			var k11: int = y1 * NX + x1
			var w00: float = (1.0 - fx) * (1.0 - fy)
			var w10: float = fx * (1.0 - fy)
			var w01: float = (1.0 - fx) * fy
			var w11: float = fx * fy
			_nT[k] = T[k00] * w00 + T[k10] * w10 + T[k01] * w01 + T[k11] * w11
			_nq[k] = q[k00] * w00 + q[k10] * w10 + q[k01] * w01 + q[k11] * w11
			_ncw[k] = cw[k00] * w00 + cw[k10] * w10 + cw[k01] * w01 + cw[k11] * w11
	_make_noise()
	for k2 in N:
		T[k2] = _nT[k2]
		q[k2] = _nq[k2]
		cw[k2] = _ncw[k2]
	# 2. нагрів від поверхні і випадкові збурення
	for j in NY:
		var amp: float = eddy_sigma * track_r[j]
		for i in NX:
			var k3: int = j * NX + i
			T[k3] += dt / 86400.0 * (ts_cur[k3] - T[k3]) / 2.0
			T[k3] += amp * _n2[k3]
	# 3. дивергенція вітру і тепла адвекція
	for j in NY:
		var dx2: float = 2.0 * dxm[j]
		for i in NX:
			var k4: int = j * NX + i
			var ip: int = j * NX + posmod(i + 1, NX)
			var im: int = j * NX + posmod(i - 1, NX)
			var dudx: float = (u[ip] - u[im]) / dx2
			var dtdx: float = (T[ip] - T[im]) / dx2
			var dvcdy: float = 0.0
			var dtdy: float = 0.0
			if j == 0:
				dvcdy = (v[k4] * cos_r[j] - v[k4 + NX] * cos_r[j + 1]) / dy
				dtdy = (T[k4] - T[k4 + NX]) / dy
			elif j == NY - 1:
				dvcdy = (v[k4 - NX] * cos_r[j - 1] - v[k4] * cos_r[j]) / dy
				dtdy = (T[k4 - NX] - T[k4]) / dy
			else:
				dvcdy = (v[k4 - NX] * cos_r[j - 1] - v[k4 + NX] * cos_r[j + 1]) / (2.0 * dy)
				dtdy = (T[k4 - NX] - T[k4 + NX]) / (2.0 * dy)
			_div[k4] = dudx + dvcdy / maxf(cos_r[j], 0.05)
			_adv[k4] = u[k4] * dtdx + v[k4] * dtdy
	# 4. вологість, конденсація, опади
	for k5 in N:
		# Підйом повітря: сходження вітру, схили гір, тепла адвекція і конвекція від нагрітої поверхні
		var conv_w: float = 0.012 * maxf(ts_dyn[k5] - T[k5] - 0.5, 0.0)
		var wv: float = -800.0 * _div[k5] + 0.6 * (u[k5] * dhdx[k5] + v[k5] * dhdy[k5]) + 2200.0 * _adv[k5] + conv_w
		wv = clampf(wv, -0.15, 0.07)
		# Критична вологість: над сушею нижча (неоднорідність усередині клітинки)
		var rhc: float = 0.90
		var rhcf: float = 0.65
		var beta: float = 1.0
		var tau: float = 1.2
		if land[k5] > 0.5:
			rhc = 0.74
			rhcf = 0.52
			beta = 0.60 + 0.35 * S[k5]
			tau = 1.5
		var qs_eff: float = rhc * _qsat(T[k5] - 6.5e-3 * wv * 21600.0)
		# Поверхня лише додає вологу в повітря, але не висушує його
		q[k5] += dt / 86400.0 * maxf(beta * _qsat(ts_dyn[k5]) - q[k5], 0.0) / tau
		var cond: float = maxf(q[k5] - qs_eff, 0.0) * 0.4
		var evap: float = minf(cw[k5], maxf(qs_eff - q[k5], 0.0) * 0.25)
		q[k5] += evap - cond
		cw[k5] += cond - evap
		T[k5] += 2.49 * latent * (cond - evap)
		var pr: float = maxf(cw[k5] - 0.10, 0.0) * 0.55
		cw[k5] -= pr
		# Внутренняя (сырая) интенсивность гонит почву и облачность, а наружу идёт откалиброванная по нормам
		var rain_raw_mm: float = pr * 1.5
		rain[k5] = rain_raw_mm * rain_scale[k5]
		rain_year[k5] += rain[k5] * acc_factor
		var lossf: float = clampf((T[k5] + 5.0) / 20.0, 0.1, 1.5)
		S[k5] = clampf(S[k5] + rain_raw_mm / 60.0 * (dt / 3600.0) - S[k5] * dt / 86400.0 / 12.0 * lossf, 0.0, 1.0)
		q[k5] = clampf(q[k5], 0.0, 40.0)
		cw[k5] = clampf(cw[k5], 0.0, 3.0)
		T[k5] = clampf(T[k5], -70.0, 50.0)
		var rh: float = clampf(q[k5] / _qsat(T[k5]), 0.0, 1.2)
		var cf_rh: float = 0.0
		if rh > rhcf:
			cf_rh = 1.0 - sqrt(clampf((1.0 - rh) / (1.0 - rhcf), 0.0, 1.0))
		cf[k5] = clampf(cf_rh + 2.5 * cw[k5] + (1.0 - exp(-4.0 * rain_raw_mm)), 0.0, 1.0)
	# Повільне середнє зміщення: на початку це просто накопичене середнє, далі вікно ~30 діб
	var am: float = maxf(1.0 / float(anom_steps + 1), 0.00139)
	anom_steps += 1
	for k6 in N:
		anom_mean[k6] += (T[k6] - ts_cur[k6] - anom_mean[k6]) * am
	_step_wind()
	steps_done += 1


# Кодує поля в два RGBA8-зображення для шейдера і копії вітру, тиску для підказки.
# A: R хмарність, G опади (1 це 8 мм/год), B хмарна вода, A вологість повітря (1 це 32 г/кг)
# B: R вітер на схід, G вітер на північ (-25..25 м/с), B аномалія температури (-20..20), A ґрунт
func export_snapshot() -> Dictionary:
	var a := PackedByteArray()
	var b := PackedByteArray()
	a.resize(N * 4)
	b.resize(N * 4)
	for k in N:
		var o: int = k * 4
		a[o] = clampi(int(cf[k] * 255.0 + 0.5), 0, 255)
		a[o + 1] = clampi(int(rain[k] / 8.0 * 255.0 + 0.5), 0, 255)
		a[o + 2] = clampi(int(cw[k] / 1.5 * 255.0 + 0.5), 0, 255)
		a[o + 3] = clampi(int(q[k] / 32.0 * 255.0 + 0.5), 0, 255)
		b[o] = clampi(int((u[k] + 25.0) / 50.0 * 255.0 + 0.5), 0, 255)
		b[o + 1] = clampi(int((v[k] + 25.0) / 50.0 * 255.0 + 0.5), 0, 255)
		b[o + 2] = clampi(int((T[k] - ts_cur[k] - anom_mean[k] + 20.0) / 40.0 * 255.0 + 0.5), 0, 255)
		b[o + 3] = clampi(int(S[k] * 255.0 + 0.5), 0, 255)
	# Температура воздуха у земли, °C: поле T и половина суточного хода поверхности
	var t2 := PackedFloat32Array()
	t2.resize(N)
	for k in N:
		t2[k] = T[k] + 0.5 * (ts_dyn[k] - ts_cur[k])
	return {"a": a, "b": b, "t": t2, "u": u.duplicate(), "v": v.duplicate(), "p": p.duplicate(), "ry": rain_year.duplicate(), "steps": steps_done}

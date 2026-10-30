extends RefCounted
## Синтез музики: перенесення генератора «Камерата» (артефакт Huzzah, Web Audio) на GDScript.
## Кожен інструмент рендериться в окрему стереопетлю на 64 шістнадцятих (4 такти) — AudioStreamWAV із loop.
## Усі петлі п'єси однакової довжини, тож Music (audio/music.gd) пускає їх разом і вмикає/вимикає шари наживо.
## Хвости нот, що виходять за кінець петлі, загортаються на її початок — петля звучить без шва.
## Працює у фоновому потоці: тільки обчислення, без звертань до дерева сцени.

const DATA := "res://data/audio/music.json"
const MIN_SCALE: Array = [0, 2, 3, 5, 7, 8, 10]
const MAJ_SCALE: Array = [0, 2, 4, 5, 7, 9, 11]
const R: Array = [0, 5, 3, 4]                 # ступені акордів по тактах (як у артефакті)
const STEPS: int = 64
# Параметри щипкових струн (Карплус — Стронг): згасання, змішування, м'якість, довжина с, гучність
const KS: Dictionary = {
	"hrp": [0.997, 0.5, 0.35, 2.6, 0.45], "hps": [0.9965, 0.72, 0.0, 1.8, 0.3], "piz": [0.985, 0.5, 0.45, 0.9, 0.65],
	"gus": [0.9975, 0.56, 0.15, 3.0, 0.3], "man": [0.995, 0.62, 0.1, 1.2, 0.2], "lut": [0.996, 0.5, 0.3, 2.0, 0.4],
	"sit": [0.9985, 0.62, 0.05, 3.0, 0.28], "kot": [0.997, 0.58, 0.15, 2.5, 0.38], "dul": [0.9975, 0.66, 0.0, 2.2, 0.2]}
# Духові: гучність, атака, згасання (wind() артефакту)
const WIND: Dictionary = {"flt": [0.17, 0.06, 0.15], "obo": [0.12, 0.04, 0.12], "dud": [0.2, 0.12, 0.25],
	"ser": [0.22, 0.025, 0.1], "kul": [0.11, 0.05, 0.3], "cla": [0.1, 0.04, 0.12], "bsn": [0.18, 0.02, 0.08],
	"hrn": [0.13, 0.07, 0.2], "tpt": [0.1, 0.02, 0.1], "shg": [0.05, 0.22, 0.3], "hrm": [0.06, 0.04, 0.1]}
# Хвилі осциляторів
enum { SINE, SAW, SQUARE, TRI, TABLE }
const TABLE_N: int = 1024
# Типи фільтрів
enum { LP, HP, BP, PK }

static var _data: Dictionary = {}

var sr: int = 22050
var bpm: float = 96.0
var mode: String = "min"
var key: int = 0                  # зсув тональності, півтони
var detune_c: float = 0.0         # розлад шару в центах (прокляття)
var sd: float = 0.0               # тривалість шістнадцятої, с
var frames: int = 0               # довжина петлі в семплах
var abort: bool = false           # Music ставить при виході з гри
var _buf := PackedFloat32Array()
var _rng := RandomNumberGenerator.new()
var _noise := PackedFloat32Array()
var _ks_cache: Dictionary = {}
var _last_f: float = 0.0          # остання нота ковзних (терменвокс, хвилі Мартено)


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(DATA, FileAccess.READ)
		if f != null:
			var d: Variant = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_data = d
				var by: Dictionary = {}
				for x in d.get("inst", []) + d.get("bonus", []):
					by[String(x["id"])] = x
				_data["by_id"] = by
	return _data


static func inst(id: String) -> Dictionary:
	return data().get("by_id", {}).get(id, {})


static func ids_of(cat: String) -> Array:
	var out: Array = []
	for x in data().get("inst", []):
		if String(x["cat"]) == cat:
			out.append(String(x["id"]))
	return out


func _init(rate: int = 22050, tempo: float = 96.0, md: String = "min", shift: int = 0, seed_value: int = 1) -> void:
	sr = rate
	bpm = tempo
	mode = md
	key = shift
	sd = 60.0 / bpm / 4.0
	frames = int(round(STEPS * sd * sr))
	_rng.seed = seed_value
	_noise.resize(sr)
	for i in sr:
		_noise[i] = _rng.randf() * 2.0 - 1.0


static func mtof(m: float) -> float:
	return 440.0 * pow(2.0, (m - 69.0) / 12.0)


func midi_of(g: int) -> int:
	var o: int = floori(g / 7.0)
	var i: int = posmod(g, 7)
	return 57 + key + 12 * o + int((MAJ_SCALE if mode == "maj" else MIN_SCALE)[i])


func freq_of(g: int) -> float:
	return mtof(midi_of(g)) * pow(2.0, detune_c / 1200.0)


# =====================================================================
# РЕНДЕР ШАРУ
# =====================================================================
## Моно-петля інструмента id: PackedFloat32Array довжиною frames
func render_mono(id: String) -> PackedFloat32Array:
	_buf = PackedFloat32Array()
	_buf.resize(frames)
	_last_f = 0.0
	var x: Dictionary = inst(id)
	for n in x.get("notes", []):
		if abort:
			break
		var t: float = float(n[0]) * sd
		var g: int = int(n[1])
		var dur: float = float(n[2]) * sd
		var v: float = float(n[3])
		var k: String = String(n[4]) if n.size() > 4 else ""
		_play(id, t, g, dur, v, k)
	return _buf


## Стерео AudioStreamWAV із петлею; gain — множник, pan −1..1
func render_stream(id: String, gain: float = 1.0, pan: float = 0.0) -> AudioStreamWAV:
	var mono: PackedFloat32Array = render_mono(id)
	return to_stream(mono, gain, pan)


func to_stream(mono: PackedFloat32Array, gain: float, pan: float) -> AudioStreamWAV:
	var a: float = (clampf(pan, -1.0, 1.0) + 1.0) * PI / 4.0
	var gl: float = cos(a) * gain * 1.41
	var gr: float = sin(a) * gain * 1.41
	var bytes := PackedByteArray()
	bytes.resize(frames * 4)
	for i in frames:
		var s: float = mono[i]
		bytes.encode_s16(i * 4, int(clampf(s * gl, -1.0, 1.0) * 32767.0))
		bytes.encode_s16(i * 4 + 2, int(clampf(s * gr, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.stereo = true
	w.mix_rate = sr
	w.data = bytes
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = frames
	return w


## Пікове значення буфера (для тестів і нормування)
static func peak(b: PackedFloat32Array) -> float:
	var p: float = 0.0
	for s in b:
		p = maxf(p, absf(s))
	return p


func _play(id: String, t: float, g: int, dur: float, v: float, k: String) -> void:
	match id:
		"tim": _timp(t, freq_of(g), v)
		"gc": _cassa(t, v)
		"sn": _snare(t, v)
		"cym": _cymbal(t, v)
		"cas":
			_noise_hit(t, BP, 2600.0, 5.0, 0.8 * v, 0.035)
			_noise_hit(t + 0.012, BP, 2600.0, 5.0, 0.8 * v, 0.035)
		"tri":
			for pa in [[1.0, 0.1], [2.73, 0.06], [5.2, 0.04], [8.1, 0.02]]:
				_tone_hit(t, 1180.0 * pa[0], 1180.0 * pa[0], pa[1] * v, 1.6)
		"tam": _tamb(t, v, k)
		"bod": _bodhran(t, v, k)
		"dar": _darbuka(t, v, k)
		"tab": _tabla(t, v, k)
		"tai": _taiko(t, v, k)
		"org": _organ(t, freq_of(g), dur, v, true)
		"pos": _organ(t, freq_of(g), dur, v, false)
		"hrm", "flt", "obo", "cla", "bsn", "hrn", "tpt", "dud", "ser", "shg": _wind(t, freq_of(g), dur, v, id)
		"hps", "piz", "lut", "hrp", "sit", "kot", "bar": _pluck(t, midi_of(g), dur, v, "hps" if id == "bar" else id)
		"cb": _bowed(t, freq_of(g), dur, v, {"bright": 2.6, "amp": 0.16, "att": 0.1, "vib": 0.003})
		"gam": _bowed(t, freq_of(g), dur, v, {"bright": 3.5, "amp": 0.13, "att": 0.12, "vib": 0.004, "peak": 600.0, "pg": 4.0})
		"hgy":
			if k == "d":
				_bowed(t, freq_of(g), dur, v, {"bright": 9.0, "peak": 1700.0, "pg": 9.0, "amp": 0.07, "att": 0.18, "rel": 0.2, "vib": 0.0015})
			else:
				_voice({"t": t, "f": 220.0, "oscs": [[SAW, 1.0, 1.0]], "filt": [[BP, 1600.0, 4.0, 0.0]], "env": ["hit", 0.12 * v, 0.09]})
				_noise_hit(t, BP, 2200.0, 3.0, 0.06 * v, 0.06)
		"vln": _bowed(t, freq_of(g), dur, v, {"bright": 6.0, "amp": 0.11, "att": 0.07, "vib": 0.007})
		"vc": _bowed(t, freq_of(g), dur, v, {"bright": 4.0, "amp": 0.13, "att": 0.1, "vib": 0.006, "peak": 350.0, "pg": 4.0})
		"nyk": _bowed(t, freq_of(g), dur, v, {"bright": 7.0, "amp": 0.1, "att": 0.04, "rel": 0.12, "vib": 0.003, "peak": 1500.0, "pg": 6.0, "sym": true})
		"cel", "eth": _bell(t, freq_of(g), v)
		"bel": _tubular(t, freq_of(g), v)
		"man":
			_pluck(t, midi_of(g), dur, v, "man")
			_pluck(t + 0.004, midi_of(g), dur, v * 0.8, "man", 7.0)
		"dul":
			_pluck(t, midi_of(g), dur, v, "dul")
			_pluck(t, midi_of(g), dur, v * 0.7, "dul", 6.0)
		"glh": _glass(t, freq_of(g), dur, v)
		"thr", "ond": _glide(t, freq_of(g), dur, v, id)
		"gus": _strum(t, g, v, k)
		"jaw": _jaw(t, freq_of(g), v)
		"saga": _wind(t, freq_of(g), dur, v, "kul")
		"east": _pluck(t, midi_of(g), dur, v, "sit")
		"cath": _choir(t, freq_of(g), dur, v)


# =====================================================================
# ГОЛОС: осцилятори → до двох фільтрів → (+ прямі осцилятори, шум) → обвідна
# =====================================================================
## spec: t, f, oscs [[хвиля, множник частоти, гучність, (true — повз фільтри)]], glide [від множника, час],
## vib [частота, глибина Гц, затримка], trem [частота, глибина, затримка], filt [[тип, f, q, дБ]],
## sweep [[час, f], …] — частота першого фільтра, noise [гучність, тип, f, q], env ["sus", amp, att, dur, rel] | ["hit", amp, dec],
## len — довжина, с (інакше з обвідної), ramp_lin — ковзання частоти лінійне
func _voice(spec: Dictionary) -> void:
	var t0: float = spec["t"]
	var f: float = spec["f"]
	var env: Array = spec["env"]
	var is_hit: bool = env[0] == "hit"
	var amp: float = env[1]
	var att: float = 0.003 if is_hit else float(env[2])
	var dec: float = float(env[2]) if is_hit else 0.0
	var hold: float = 0.0 if is_hit else maxf(att, float(env[3]))
	var tau: float = 1.0 if is_hit else maxf(float(env[4]) / 3.0, 0.005)
	var length: float = float(spec.get("len", (dec + 0.02) if is_hit else hold + tau * 9.0 + 0.05))
	var n: int = mini(int(length * sr), frames)
	if n <= 0 or amp <= 0.0:
		return
	var start: int = int(t0 * sr)
	var oscs: Array = spec.get("oscs", [])
	var no: int = oscs.size()
	var ph := PackedFloat32Array()
	ph.resize(no)
	# Параметри осциляторів у пакованих масивах: у циклі по семплах без словників
	var wv := PackedInt32Array()
	var rt := PackedFloat32Array()
	var am := PackedFloat32Array()
	var dr := PackedByteArray()
	var tabs: Array = []
	for oc in oscs:
		wv.append(int(oc[0]))
		rt.append(float(oc[1]))
		am.append(float(oc[2]))
		dr.append(1 if oc.size() > 3 and oc[3] else 0)
		tabs.append(oc[4] if oc.size() > 4 else PackedFloat32Array())
	var gl: Array = spec.get("glide", [])
	var g_from: float = float(gl[0]) if not gl.is_empty() else 1.0
	var g_t: float = maxf(float(gl[1]), 0.001) if not gl.is_empty() else 0.0
	var g_lin: bool = bool(spec.get("ramp_lin", false))
	var g_log: float = log(1.0 / g_from) if g_from > 0.0 else 0.0
	var vb: Array = spec.get("vib", [])
	var has_vib: bool = not vb.is_empty()
	var v_rate: float = TAU * float(vb[0]) if has_vib else 0.0
	var v_depth: float = float(vb[1]) if has_vib else 0.0
	var v_del: float = maxf(float(vb[2]), 0.001) if has_vib else 1.0
	var tr: Array = spec.get("trem", [])
	var has_tr: bool = not tr.is_empty()
	var t_rate: float = TAU * float(tr[0]) if has_tr else 0.0
	var t_depth: float = float(tr[1]) if has_tr else 0.0
	var t_del: float = maxf(float(tr[2]), 0.001) if has_tr else 1.0
	var flt: Array = spec.get("filt", [])
	var sweep: Array = spec.get("sweep", [])
	var nz: Array = spec.get("noise", [])
	var nyq: float = sr * 0.45
	# Коефіцієнти біквадів (RBJ); стан у локальних змінних — так швидше
	var c1 := _coef(flt[0], nyq) if flt.size() > 0 else PackedFloat64Array()
	var c2 := _coef(flt[1], nyq) if flt.size() > 1 else PackedFloat64Array()
	var has1: bool = c1.size() > 0
	var has2: bool = c2.size() > 0
	var x11: float = 0.0; var x12: float = 0.0; var y11: float = 0.0; var y12: float = 0.0
	var x21: float = 0.0; var x22: float = 0.0; var y21: float = 0.0; var y22: float = 0.0
	var cn := _coef([nz[1], nz[2], nz[3], 0.0], nyq) if not nz.is_empty() else PackedFloat64Array()
	var nx1: float = 0.0; var nx2: float = 0.0; var ny1: float = 0.0; var ny2: float = 0.0
	var n_amp: float = float(nz[0]) if not nz.is_empty() else 0.0
	var nn: int = _noise.size()
	var n_off: int = _rng.randi() % nn
	var log_end: float = log(0.0001 / amp) if is_hit else 0.0
	var inv: float = 1.0 / sr
	var pos: int = start % frames
	for i in n:
		var x: float = i * inv
		# частота з ковзанням і вібрато
		var fi: float = f
		if g_t > 0.0 and x < g_t:
			fi = f * (lerpf(g_from, 1.0, x / g_t) if g_lin else g_from * exp(g_log * x / g_t))
		if has_vib:
			fi += minf(x / v_del, 1.0) * v_depth * sin(v_rate * x)
		if not sweep.is_empty() and (i & 31) == 0:
			c1 = _coef([flt[0][0], _sweep_at(sweep, x), flt[0][2], flt[0][3]], nyq)
		var filtered: float = 0.0
		var direct: float = 0.0
		var fdt: float = fi * inv
		for o in no:
			var p: float = ph[o]
			var dt: float = fdt * rt[o]
			var w: float
			match wv[o]:
				SINE:
					w = sin(TAU * p)
				SAW:
					w = 2.0 * p - 1.0 - _blep(p, dt)
				SQUARE:
					w = (1.0 if p < 0.5 else -1.0) + _blep(p, dt) - _blep(fposmod(p + 0.5, 1.0), dt)
				TRI:
					w = 4.0 * absf(p - 0.5) - 1.0
				_:
					var tb: PackedFloat32Array = tabs[o]
					var fx: float = p * TABLE_N
					var ix: int = int(fx)
					w = lerpf(tb[ix], tb[ix + 1], fx - ix)
			p += dt
			if p >= 1.0:
				p -= floorf(p)
			ph[o] = p
			if dr[o] == 1:
				direct += w * am[o]
			else:
				filtered += w * am[o]
		var s: float = filtered
		if has1:
			var y: float = c1[0] * s + c1[1] * x11 + c1[2] * x12 - c1[3] * y11 - c1[4] * y12
			x12 = x11; x11 = s; y12 = y11; y11 = y; s = y
		if has2:
			var y2: float = c2[0] * s + c2[1] * x21 + c2[2] * x22 - c2[3] * y21 - c2[4] * y22
			x22 = x21; x21 = s; y22 = y21; y21 = y2; s = y2
		s += direct
		if n_amp > 0.0:
			var ns: float = _noise[(n_off + i) % nn]
			var yn: float = cn[0] * ns + cn[1] * nx1 + cn[2] * nx2 - cn[3] * ny1 - cn[4] * ny2
			nx2 = nx1; nx1 = ns; ny2 = ny1; ny1 = yn
			s += yn * n_amp
		if has_tr:
			s *= 1.0 + minf(x / t_del, 1.0) * t_depth * sin(t_rate * x)
		var e: float
		if is_hit:
			e = amp * x / att if x < att else amp * exp(log_end * (x - att) / maxf(dec - att, 0.001))
		elif x < att:
			e = amp * x / att
		elif x < hold:
			e = amp
		else:
			e = amp * exp(-(x - hold) / tau)
		_buf[pos] += s * e
		pos += 1
		if pos >= frames:
			pos = 0


## Поправка PolyBLEP проти дзвону на стрибках пилки й меандра
static func _blep(p: float, dt: float) -> float:
	if dt <= 0.0:
		return 0.0
	if p < dt:
		var q: float = p / dt
		return q + q - q * q - 1.0
	if p > 1.0 - dt:
		var r: float = (p - 1.0) / dt
		return r * r + r + r + 1.0
	return 0.0


## Частота фільтра в момент x за точками [[час, f], …] (лінійно між точками)
static func _sweep_at(pts: Array, x: float) -> float:
	if x <= float(pts[0][0]):
		return float(pts[0][1])
	for i in range(1, pts.size()):
		if x <= float(pts[i][0]):
			var a: Array = pts[i - 1]
			var b: Array = pts[i]
			return lerpf(float(a[1]), float(b[1]), (x - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.0001))
	return float(pts[-1][1])


## Біквад RBJ: [b0, b1, b2, a1, a2] (нормовані на a0)
func _coef(fl: Array, nyq: float) -> PackedFloat64Array:
	var typ: int = int(fl[0])
	var fc: float = clampf(float(fl[1]), 20.0, nyq)
	var q: float = maxf(float(fl[2]), 0.3)
	var w0: float = TAU * fc / sr
	var cw: float = cos(w0)
	var al: float = sin(w0) / (2.0 * q)
	var b0: float; var b1: float; var b2: float; var a0: float; var a1: float; var a2: float
	match typ:
		LP:
			b0 = (1.0 - cw) / 2.0; b1 = 1.0 - cw; b2 = b0
			a0 = 1.0 + al; a1 = -2.0 * cw; a2 = 1.0 - al
		HP:
			b0 = (1.0 + cw) / 2.0; b1 = -(1.0 + cw); b2 = b0
			a0 = 1.0 + al; a1 = -2.0 * cw; a2 = 1.0 - al
		BP:
			b0 = al; b1 = 0.0; b2 = -al
			a0 = 1.0 + al; a1 = -2.0 * cw; a2 = 1.0 - al
		_:
			var A: float = pow(10.0, float(fl[3]) / 40.0)
			b0 = 1.0 + al * A; b1 = -2.0 * cw; b2 = 1.0 - al * A
			a0 = 1.0 + al / A; a1 = -2.0 * cw; a2 = 1.0 - al / A
	return PackedFloat64Array([b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0])


func _tone_hit(t: float, f0: float, f1: float, amp: float, dec: float, bend: float = 0.05, wave: int = SINE) -> void:
	if f0 >= sr * 0.48:
		return
	_voice({"t": t, "f": f1, "oscs": [[wave, 1.0, 1.0]], "glide": [f0 / f1, bend] if f0 != f1 else [], "env": ["hit", amp, dec]})


func _noise_hit(t: float, typ: int, f: float, q: float, amp: float, dec: float) -> void:
	_voice({"t": t, "f": 1.0, "oscs": [], "noise": [1.0, typ, f, q], "env": ["hit", amp, dec]})


# =====================================================================
# ІНСТРУМЕНТИ
# =====================================================================
func _bowed(t: float, f: float, dur: float, v: float, o: Dictionary) -> void:
	var rel: float = float(o.get("rel", 0.22))
	var filt: Array = [[LP, minf(f * float(o.get("bright", 5.0)), 9000.0), 0.8, 0.0]]
	if o.has("peak"):
		filt.append([PK, o["peak"], 2.5, float(o.get("pg", 7.0))])
	var vib: float = float(o.get("vib", 0.006))
	var spec: Dictionary = {"t": t, "f": f, "oscs": [[SAW, 1.0, 1.0], [SAW, 1.004, 1.0]], "filt": filt,
		"env": ["sus", float(o.get("amp", 0.12)) * v, float(o.get("att", 0.08)), dur, rel]}
	if vib > 0.0:
		spec["vib"] = [5.5, f * vib, 0.25]
	_voice(spec)
	if o.get("sym", false):
		# резонансні струни 2f і 1,5f = гармоніки 4 і 3 від f/2
		_voice({"t": t, "f": f, "oscs": [[TABLE, 0.5, 1.0, true, _table([[4, 1.0], [3, 1.0]], f * 0.5)]],
			"env": ["sus", 0.035 * v, 0.25, dur, 2.2], "len": dur + 2.0})


func _wind(t: float, f: float, dur: float, v: float, k: String) -> void:
	var p: Array = WIND[k]
	var env: Array = ["sus", float(p[0]) * v, p[1], dur, p[2]]
	var s: Dictionary = {"t": t, "f": f, "env": env}
	match k:
		"flt":
			s["oscs"] = [[SINE, 1.0, 1.0, true], [SINE, 2.0, 0.12, true]]
			s["vib"] = [5.0, f * 0.005, 0.2]
			s["noise"] = [0.22, BP, f * 2.0, 1.2]
		"obo":
			s["oscs"] = [[SAW, 1.0, 1.0]]
			s["filt"] = [[BP, 1300.0, 1.1, 0.0], [LP, 4200.0, 0.7, 0.0]]
			s["vib"] = [5.2, f * 0.004, 0.2]
		"dud":
			s["oscs"] = [[SAW, 1.0, 1.0], [TRI, 1.0, 1.0]]
			s["glide"] = [1.06, 0.09]
			s["ramp_lin"] = true
			s["filt"] = [[LP, 1100.0, 0.9, 0.0], [PK, 520.0, 1.5, 6.0]]
			s["vib"] = [5.0, f * 0.005, 0.4]
			s["noise"] = [0.12, BP, 1200.0, 1.0]
		"ser":
			s["oscs"] = [[SAW, 1.0, 1.0], [SINE, 1.0, 0.4, true]]
			s["filt"] = [[LP, 150.0, 2.0, 0.0]]
			s["sweep"] = [[0.0, 150.0], [0.04, minf(f * 6.0, 3000.0)], [0.2, f * 3.0]]
		"kul":
			s["oscs"] = [[SINE, 1.0, 1.0, true]]
			s["glide"] = [1.04, 0.12]
			s["vib"] = [6.0, f * 0.01, 0.15]
		"cla":
			s["oscs"] = [[SQUARE, 1.0, 1.0]]
			s["filt"] = [[LP, minf(f * 4.0, 5000.0), 0.5, 0.0]]
			s["vib"] = [5.0, f * 0.003, 0.3]
		"bsn":
			s["oscs"] = [[SAW, 1.0, 1.0]]
			s["filt"] = [[BP, 450.0, 0.9, 0.0], [LP, 2500.0, 0.7, 0.0]]
		"hrn":
			s["oscs"] = [[SAW, 1.0, 1.0]]
			s["filt"] = [[LP, f * 1.5, 0.9, 0.0]]
			s["sweep"] = [[0.0, f * 1.5], [0.09, f * 3.2]]
			s["vib"] = [4.8, f * 0.003, 0.35]
		"tpt":
			s["oscs"] = [[SAW, 1.0, 1.0]]
			s["filt"] = [[LP, f * 2.0, 1.2, 0.0], [PK, 1500.0, 1.5, 5.0]]
			s["sweep"] = [[0.0, f * 2.0], [0.03, minf(f * 10.0, 9000.0)], [0.2, f * 6.0]]
			s["vib"] = [5.5, f * 0.003, 0.3]
		"shg":
			s["oscs"] = [[SQUARE, 1.0, 1.0], [SQUARE, 1.005, 1.0]]
			s["filt"] = [[LP, minf(f * 3.0, 6000.0), 0.7, 0.0]]
		"hrm":
			s["oscs"] = [[SQUARE, 1.0, 1.0], [SAW, 1.003, 0.6]]
			s["filt"] = [[LP, minf(f * 5.0, 6000.0), 0.6, 0.0]]
	_voice(s)


func _organ(t: float, f: float, dur: float, v: float, big: bool) -> void:
	# Регістри органу — одна таблиця на період найнижчої гармоніки (у великого це 0,5 f)
	var parts: Array = [[1, 0.5], [2, 1], [4, 0.7], [6, 0.35], [8, 0.4], [12, 0.15], [16, 0.2]] if big \
		else [[1, 1], [2, 0.6], [3, 0.3], [4, 0.22], [8, 0.07]]
	var base: float = f * (0.5 if big else 1.0)
	var oscs: Array = [[TABLE, 0.5 if big else 1.0, 1.0, true, _table(parts, base)]]
	_voice({"t": t, "f": f, "oscs": oscs, "env": ["sus", (0.04 if big else 0.055) * v, 0.08 if big else 0.05, dur, 0.3 if big else 0.12]})
	_noise_hit(t, HP, 2200.0, 0.7, 0.05 * v, 0.06)


func _glass(t: float, f: float, dur: float, v: float) -> void:
	_voice({"t": t, "f": f, "oscs": [[SINE, 1.0, 1.0, true], [SINE, 2.0, 0.12, true]], "trem": [5.2, 0.22, 0.4],
		"env": ["sus", 0.12 * v, 0.35, dur, 0.9], "len": dur + 2.0})


func _glide(t: float, f: float, dur: float, v: float, k: String) -> void:
	var from: float = _last_f if _last_f > 0.0 else f
	_last_f = f
	var ond: bool = k == "ond"
	var s: Dictionary = {"t": t, "f": f, "glide": [from / f, 0.22 if ond else 0.14],
		"vib": [5.5 if ond else 6.2, f * (0.008 if ond else 0.012), 0.15],
		"env": ["sus", (0.11 if ond else 0.13) * v, 0.08, dur, 0.25], "len": dur + 0.8}
	if ond:
		s["oscs"] = [[TRI, 1.0, 1.0], [SQUARE, 1.0, 0.25]]
		s["filt"] = [[PK, 2400.0, 3.0, 8.0]]
	else:
		s["oscs"] = [[SINE, 1.0, 1.0, true], [TRI, 1.0, 0.1, true]]
	_voice(s)


func _choir(t: float, f: float, dur: float, v: float) -> void:
	# Форманта «а»: смуга 800 Гц і підйом 2900 Гц (в артефакті — три паралельні смуги; так утричі швидше)
	_voice({"t": t, "f": f, "oscs": [[SAW, 1.0, 1.0], [SAW, 1.006, 1.0], [SAW, 0.995, 1.0]],
		"filt": [[BP, 900.0, 2.0, 0.0], [PK, 2900.0, 4.0, 9.0]], "vib": [5.0, f * 0.004, 0.5],
		"env": ["sus", 0.1 * v, 0.4, dur, 0.6], "len": dur + 2.0})


## Таблиця одного періоду із гармонік [[номер, гучність], …]; гармоніки вище частоти Найквіста відкидаються
func _table(parts: Array, base: float) -> PackedFloat32Array:
	var key_t: String = str(parts) + "@" + str(int(base * 0.25))
	if _ks_cache.has(key_t):
		return _ks_cache[key_t]
	var tb := PackedFloat32Array()
	tb.resize(TABLE_N + 1)
	for pa in parts:
		if base * float(pa[0]) >= sr * 0.45:
			continue
		for i in TABLE_N:
			tb[i] += float(pa[1]) * sin(TAU * float(pa[0]) * i / TABLE_N)
	tb[TABLE_N] = tb[0]
	_ks_cache[key_t] = tb
	return tb


func _bell(t: float, f: float, v: float) -> void:
	for pa in [[1.0, 1.0, 1.6], [2.0, 0.35, 0.7], [3.0, 0.12, 0.4], [4.07, 0.06, 0.25]]:
		_tone_hit(t, f * pa[0], f * pa[0], 0.12 * v * pa[1], pa[2])


func _tubular(t: float, f: float, v: float) -> void:
	for pa in [[1.0, 1.0, 4.0], [2.76, 0.5, 2.2], [5.4, 0.3, 1.2], [8.9, 0.15, 0.7]]:
		_tone_hit(t, f * pa[0], f * pa[0], 0.11 * v * pa[1], pa[2])
	_noise_hit(t, BP, 3000.0, 1.0, 0.08 * v, 0.04)


func _jaw(t: float, f: float, v: float) -> void:
	for pa in [[1.0, 500.0, 1400.0, 8.0], [0.6, 900.0, 2200.0, 10.0]]:
		_voice({"t": t, "f": f, "oscs": [[SAW, 1.0, float(pa[0])]], "filt": [[BP, pa[1], pa[3], 0.0]],
			"sweep": [[0.0, pa[1]], [0.12, pa[2]], [0.35, float(pa[1]) * 1.2]], "env": ["hit", 1.2 * v, 0.38], "len": 0.4})


func _timp(t: float, f: float, v: float) -> void:
	_tone_hit(t, f * 1.06, f, 0.55 * v, 1.6, 0.06)
	_tone_hit(t, f * 1.51, f * 1.51, 0.12 * v, 0.8)
	_noise_hit(t, LP, 500.0, 0.7, 0.3 * v, 0.08)


func _cassa(t: float, v: float) -> void:
	_tone_hit(t, 72.0, 42.0, 0.8 * v, 0.7, 0.25)
	_noise_hit(t, LP, 180.0, 0.7, 0.3 * v, 0.15)


func _snare(t: float, v: float) -> void:
	_tone_hit(t, 200.0, 165.0, 0.32 * v, 0.1, 0.05)
	_noise_hit(t, HP, 1200.0, 0.7, 0.45 * v, 0.17)
	_noise_hit(t, BP, 4200.0, 1.5, 0.25 * v, 0.12)


func _cymbal(t: float, v: float) -> void:
	var oscs: Array = []
	for f in [263.0, 400.0, 527.0, 685.0, 812.0, 1053.0]:
		oscs.append([SQUARE, f * 1.7 / 263.0, 1.0])
	_voice({"t": t, "f": 263.0, "oscs": oscs, "filt": [[HP, 4800.0, 0.7, 0.0]], "env": ["hit", 0.18 * v, 2.8]})
	_noise_hit(t, HP, 7000.0, 0.7, 0.25 * v, 1.6)


func _tamb(t: float, v: float, k: String) -> void:
	var lo: bool = k == "lo"
	if lo:
		_noise_hit(t, BP, 180.0, 1.5, 0.7 * v, 0.18)
		_tone_hit(t, 95.0, 95.0, 0.4 * v, 0.2)
	_noise_hit(t, HP, 6500.0, 0.7, 0.28 * v * (0.5 if lo else 1.0), 0.12)
	_noise_hit(t, BP, 9000.0, 8.0, 0.5 * v, 0.09)


func _bodhran(t: float, v: float, k: String) -> void:
	if k == "lo":
		_tone_hit(t, 90.0, 68.0, 0.65 * v, 0.3, 0.08)
		_noise_hit(t, LP, 400.0, 0.7, 0.3 * v, 0.06)
	else:
		_tone_hit(t, 170.0, 150.0, 0.3 * v, 0.12, 0.04)
		_noise_hit(t, BP, 800.0, 1.0, 0.25 * v, 0.05)


func _darbuka(t: float, v: float, k: String) -> void:
	if k == "D":
		_tone_hit(t, 115.0, 88.0, 0.75 * v, 0.32, 0.06)
		_noise_hit(t, LP, 300.0, 0.7, 0.25 * v, 0.06)
	else:
		_noise_hit(t, BP, 3500.0, 2.0, (0.55 if k == "T" else 0.3) * v, 0.04)
		_tone_hit(t, 620.0, 600.0, (0.2 if k == "T" else 0.1) * v, 0.05)


func _tabla(t: float, v: float, k: String) -> void:
	var sa: float = freq_of(7)
	var dl: float = 0.7 if k == "dhin" else (0.25 if k == "na" else 0.45)
	for pa in [[1.0, 0.5], [2.0, 0.3], [3.0, 0.2], [4.0, 0.1]]:
		_tone_hit(t, sa * pa[0], sa * pa[0], pa[1] * 0.5 * v, dl * (1.2 - pa[0] * 0.15))
	if k == "dha" or k == "dhin":
		_voice({"t": t, "f": 125.0, "oscs": [[SINE, 1.0, 1.0]], "glide": [0.68, 0.18], "ramp_lin": true, "env": ["hit", 0.6 * v, 0.55]})
	_noise_hit(t, BP, 4000.0, 2.0, 0.12 * v, 0.02)


func _taiko(t: float, v: float, k: String) -> void:
	if k == "ka":
		_noise_hit(t, BP, 2500.0, 3.0, 0.5 * v, 0.03)
		_tone_hit(t, 900.0, 900.0, 0.12 * v, 0.03)
	else:
		_tone_hit(t, 62.0, 46.0, 0.9 * v, 0.95, 0.2)
		_tone_hit(t, 125.0, 110.0, 0.2 * v, 0.3, 0.05)
		_noise_hit(t, LP, 250.0, 0.7, 0.4 * v, 0.2)


func _strum(t: float, g: int, v: float, k: String) -> void:
	var r: int = int(R[clampi(g, 0, 3)])
	var notes: Array = [midi_of(r + 7), midi_of(r + 9), midi_of(r + 11), midi_of(r + 14)]
	if k == "up":
		notes.reverse()
	for i in notes.size():
		_pluck(t + i * 0.018, notes[i], 1.0, v * (1.0 - i * 0.08), "gus")


# =====================================================================
# ЩИПКОВІ: Карплус — Стронг із кешем за висотою
# =====================================================================
func _ks_buf(m: int, k: String, cents: float) -> PackedFloat32Array:
	var cache_key: String = "%s%d@%d" % [k, m, int(cents + detune_c)]
	if _ks_cache.has(cache_key):
		return _ks_cache[cache_key]
	var p: Array = KS[k]
	var decay: float = p[0]
	var blend: float = p[1]
	var soft: float = p[2]
	var length: int = int(sr * float(p[3]))
	var period: int = maxi(2, roundi(sr / (mtof(m) * pow(2.0, (cents + detune_c) / 1200.0))))
	var y := PackedFloat32Array()
	y.resize(length)
	var prev: float = 0.0
	var mean: float = 0.0
	for i in mini(period, length):
		var r: float = _rng.randf() * 2.0 - 1.0
		if soft > 0.0:
			r = prev + (r - prev) * (1.0 - soft)
			prev = r
		y[i] = r
		mean += r
	mean /= period
	for i in mini(period, length):
		y[i] -= mean
	var nb: float = 1.0 - blend
	for i in range(period, length):
		y[i] = decay * (blend * y[i - period] + nb * (y[i - period - 1] if i > period else 0.0))
	if k == "sit":
		# «Жужжання» широкої підставки: м'яке насичення
		for i in length:
			var x: float = clampf(y[i], -1.0, 1.0)
			y[i] = tanh(x * 2.2) + 0.12 * x * x
	_ks_cache[cache_key] = y
	return y


func _pluck(t: float, m: int, dur: float, v: float, k: String, cents: float = 0.0) -> void:
	var p: Array = KS[k]
	var y: PackedFloat32Array = _ks_buf(m, k, cents)
	var g: float = float(p[4]) * v
	var start: int = int(t * sr)
	# Густі партії (мандоліна, цимбали) обрізаємо за 0,8 с після ноти з плавним згасанням — інакше рендер задовгий
	var n: int = y.size()
	if k == "man" or k == "dul":
		n = mini(n, int((dur + 0.8) * sr))
	var fade_from: int = n - int(0.15 * sr)
	var cut: int = int(dur * sr) if k == "piz" else -1
	var hp: bool = k == "hps" or k == "sit"
	var hp_a: float = exp(-TAU * (140.0 if k == "hps" else 90.0) / sr)
	var hx: float = 0.0
	var hy: float = 0.0
	for i in n:
		var s: float = y[i] * g
		if hp:
			var yy: float = hp_a * (hy + s - hx)
			hx = s
			hy = yy
			s = yy
		if cut >= 0 and i > cut:
			s *= exp(-float(i - cut) / (0.05 * sr))
		if i > fade_from and fade_from > 0:
			s *= float(n - i) / float(n - fade_from)
		_buf[(start + i) % frames] += s
	if k == "sit":
		var f: float = mtof(m)
		_voice({"t": t, "f": f, "oscs": [[SINE, 2.0, 1.0], [SINE, 3.0, 1.0]], "env": ["hit", 0.03 * v, 2.5]})

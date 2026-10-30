extends Node2D
## Деревья, горы, кусты и камни общей карты — как в  (Huzzah 2026-10-23):
## у каждого спрайта свой размер в метрах, поэтому при самом близком зуме у пешки деревья и горы
## крупные, а при отдалении они сжимаются и сливаются в пятно своего биома (лес — сплошной лес,
## горы — гряды), дальше — только текстура и цвет биома.
## По биомам: лес — густые деревья (поляны шейдера — без деревьев, с цветами), проклятый лес — кривые
## деревья с лиловым оттенком, болото — редкие кривые деревья и кусты, пустошь — редкие сухие деревья
## и камни, горы — горы и скалы в 8–15 м (жаркие — рыжие), берег — камешки.
## На протоптанной тропе и дороге (world/trails_layer.gd, со ступени «тропа») деревьев и кустов нет.
##
## Швидко: карта ділиться на клітинки CHUNK м; дані клітинки рахуються по кілька за кадр від центру екрана й
## запам'ятовуються; зсув камери змінює лише перетворення кореня.
## Порядок малювання (Huzzah 2026-10-29: дерева не накладаються, кущі й квіти не лежать на кронах): усе — дерева,
## гори, кущі, каміння — малюється одним списком за висотою ніг (що нижче на екрані, те ближче й перекриває
## дальнє). Видимий ряд клітинок — один MultiMesh: клітинки ряду зшиваються смугами BAND_M м, тож сусідні
## клітинки не перекривають одна одну навпаки. Дрібниця проявляється з наближенням через uniform шейдера.

const Art := preload("res://storybook/art.gd")

const CHUNK: float = 128.0
const BUILD_MS: float = 5.0            # скільки мілісекунд кадру можна витрачати на нові клітинки
const MAX_CACHED: int = 2500           # клітинок у пам'яті (дані), вузли — лише видимі
const BIG_FROM_Z: float = 0.5          # велике (дерева, гори) видно з цього масштабу (пікселів на метр)
const BIG_FULL_Z: float = 0.9
const SMALL_FROM_Z: float = 3.0        # дрібниця (кущі, каміння)
const SMALL_FULL_Z: float = 5.0
const SHADOW: float = 0.12             # частка висоти під ногами в комірці атласу (тінь)
const BAND_M: float = 2.0              # смуга ряду: у межах смуги порядок — зліва направо (помилка не більша за смугу)
const BANDS: int = int(CHUNK / BAND_M)
const SMALL_FLAG: float = 0.5          # альфа екземпляра-дрібниці (шейдер підміняє її на small_a)
const FLOATS: int = 16                 # на екземпляр у буфері MultiMesh: 8 перетворення, 4 колір, 4 custom

## Ключ спрайта -> висота комірки атласу (пікс.)
const KEYS: Array = ["tree_oak", "tree_light", "tree_crooked", "mountain_gray", "ridge_gray", "peak_gray", "cliff_gray",
	"mountain_hot", "mesa_hot", "ridge_hot", "bush_flower", "bush_berry", "rock", "tech_tower"]
const CELL_PX: int = 288
const PAD: int = 16

var game: Node2D
var _root := Node2D.new()
var _atlas: ImageTexture
var _uv: Dictionary = {}               # ключ -> Color(u0, v0, du, dv)
var _aspect: Dictionary = {}           # ключ -> ширина / висота
var _mesh: ArrayMesh
var _mat: ShaderMaterial
var _data: Dictionary = {}             # Vector2i -> {big: [...], small: [...]} — спрайти клітинки (позиція від кута клітинки)
var _bands: Dictionary = {}            # Vector2i -> Array[PackedFloat32Array] (BANDS смуг готових екземплярів)
var _rows: Dictionary = {}             # номер ряду -> {node: MultiMeshInstance2D, c0, c1, full}
var _order: Array = []                 # порядок появи даних (для витіснення)
var _noise: Image


func _ready() -> void:
	add_child(_root)
	_build_atlas()
	_build_mesh()


func _process(_delta: float) -> void:
	if game == null or not game.ready_done or _atlas == null:
		return
	if _noise == null:
		_noise = game.get("noise_image")
	_drop_trodden_chunks()
	var z: float = game.zoom
	var vp: Vector2 = get_viewport_rect().size
	_root.position = vp * 0.5 - game.cam_pos * z
	_root.scale = Vector2(z, z)
	# Світло за годинником, як у решти декору
	var hour: float = game.clock.hour_of_day()
	var daylight: float = clampf(sin((hour - 6.0) / 12.0 * PI) * 1.4, 0.0, 1.0)
	_root.modulate = Color(0.32, 0.39, 0.51).lerp(Color.WHITE, daylight)
	var big_a: float = smoothstep(BIG_FROM_Z, BIG_FULL_Z, z)
	var small_a: float = smoothstep(SMALL_FROM_Z, SMALL_FULL_Z, z)
	if big_a <= 0.0:
		_root.visible = false
		return
	_root.visible = true
	_mat.set_shader_parameter("big_a", big_a)
	_mat.set_shader_parameter("small_a", small_a)
	# Видимі клітинки (із запасом у пів клітинки)
	var half: Vector2 = vp * 0.5 / z + Vector2(CHUNK, CHUNK) * 0.5
	var max_c := Vector2i(floori(game.MAP_SIZE.x / CHUNK), floori(game.MAP_SIZE.y / CHUNK))
	var c0 := Vector2i(maxi(floori((game.cam_pos.x - half.x) / CHUNK), 0), maxi(floori((game.cam_pos.y - half.y) / CHUNK), 0))
	var c1 := Vector2i(mini(floori((game.cam_pos.x + half.x) / CHUNK), max_c.x), mini(floori((game.cam_pos.y + half.y) / CHUNK), max_c.y))
	# Ряди, що пішли з екрана, — прибрати
	for cy in _rows.keys():
		if cy < c0.y or cy > c1.y:
			_rows[cy]["node"].queue_free()
			_rows.erase(cy)
	# Ряди — від центру; дані нових клітинок рахуються, скільки встигнемо за кадр, ряд зшивається, коли готовий
	var mid_y: float = game.cam_pos.y / CHUNK - 0.5
	var order: Array = range(c0.y, c1.y + 1)
	order.sort_custom(func(a: int, b: int) -> bool: return absf(a - mid_y) < absf(b - mid_y))
	var t0: int = Time.get_ticks_usec()
	for cy in order:
		var row: Dictionary = _rows.get(cy, {})
		if not row.is_empty() and row["c0"] == c0.x and row["c1"] == c1.x and row["full"]:
			continue
		if float(Time.get_ticks_usec() - t0) > BUILD_MS * 1000.0 and not row.is_empty():
			continue
		var full: bool = true
		for cx in range(c0.x, c1.x + 1):
			var k := Vector2i(cx, cy)
			if not _bands.has(k):
				if float(Time.get_ticks_usec() - t0) > BUILD_MS * 1000.0:
					full = false
					continue
				_chunk_bands(k)
		_build_row(cy, c0.x, c1.x, full)
	while _order.size() > MAX_CACHED:
		var old: Vector2i = _order.pop_front()
		_data.erase(old)
		_bands.erase(old)


# Змінився ступінь протоптаної клітинки — її ділянка розставляється заново (дорога витоптує ліс)
func _drop_trodden_chunks() -> void:
	var tl: Node = game.get("trails")
	if tl == null:
		return
	var cells: Array = tl.take_dirty()
	if cells.is_empty():
		return
	var keys: Dictionary = {}
	for c in cells:
		var q: Vector2 = tl.model.center_of(c)
		var h: float = tl.model.cell_m * 0.5
		for o in [Vector2(-h, -h), Vector2(h, -h), Vector2(-h, h), Vector2(h, h)]:
			keys[Vector2i(floori((q.x + o.x) / CHUNK), floori((q.y + o.y) / CHUNK))] = true
	for k in keys:
		_data.erase(k)
		_bands.erase(k)
		if _rows.has(k.y):
			_rows[k.y]["full"] = false
			_rows[k.y]["c0"] = -1


# =====================================================================
# РОЗСТАНОВКА (детермінована: та сама точка — той самий спрайт)
# =====================================================================
func _chunk_data(k: Vector2i) -> Dictionary:
	if _data.has(k):
		return _data[k]
	var big: Array = []
	var small: Array = []
	var o := Vector2(k) * CHUNK
	# Велике: дерева сіткою 5,5 м (ліс), гори по 9 м, решта рідше
	_grid(o, 5.5, 1, func(p: Vector2, n: float, b: int):
		if b == 3 or b == 7:
			if n > 0.18 and not _clearing(p):
				var key: String = ["tree_oak", "tree_oak", "tree_light", "tree_crooked"][int(n * 37.0) % 4] if b == 3 else ["tree_crooked", "tree_crooked", "tree_light"][int(n * 37.0) % 3]
				big.append([p, key, 7.0 + fposmod(n * 13.7, 1.0) * 5.0, Color(0.88, 0.8, 1.0) if b == 7 else Color.WHITE]))
	_grid(o, 11.0, 2, func(p: Vector2, n: float, b: int):
		if (b == 5 or b == 9) and n > 0.7:
			big.append([p, "tree_crooked" if n > 0.82 else "tree_light", 5.0 + fposmod(n * 7.3, 1.0) * 3.0, Color(0.88, 0.8, 1.0) if b == 9 else Color.WHITE])
		elif (b == 4 or b == 8) and n > 0.95 and not _dry_grass(p):
			big.append([p, "tree_crooked", 4.0 + fposmod(n * 5.1, 1.0) * 2.0, Color(0.9, 0.85, 0.75)]))
	_grid(o, 9.0, 3, func(p: Vector2, n: float, b: int):
		if b == 6 and n > 0.12:
			var hot: bool = game.is_hot(p)
			# Об'єм гір: вище за картою висот — скелі більші, біля вершин — піки (Huzzah 2026-10-24)
			var up: float = game.height_at(p) / game.HEIGHT_MAX_M if game.has_method("height_at") else 0.5
			var key: String = ["mountain_hot", "mesa_hot", "ridge_hot"][int(n * 17.0) % 3] if hot else ("peak_gray" if up > 0.75 and n > 0.4 else ["mountain_gray", "ridge_gray", "peak_gray", "cliff_gray"][int(n * 19.0) % 4])
			big.append([p, key, (8.0 + fposmod(n * 9.1, 1.0) * 7.0) * (0.65 + 0.8 * up), Color.WHITE]))
	# Техно-артефакти (Q31 B): рідкісні сигнальні вежі 16–24 м — близько однієї на 2 км² суходолу, крім гір і боліт
	_grid(o, 64.0, 5, func(p: Vector2, n: float, b: int):
		if b in [2, 3, 4, 7, 8] and n > 0.993:
			big.append([p, "tech_tower", 16.0 + fposmod(n * 911.0, 1.0) * 8.0, Color.WHITE]))
	# Дрібниця: кущі й каміння по 4 м
	_grid(o, 4.0, 4, func(p: Vector2, n: float, b: int):
		if (b == 3 or b == 7) and _clearing(p) and n > 0.8:
			small.append([p, "bush_flower", 0.8 + n * 0.6, Color.WHITE])
		elif (b == 3 or b == 5 or b == 7 or b == 9) and n > 0.9:
			small.append([p, "bush_berry" if n > 0.95 else "bush_flower", 0.9 + n * 0.7, Color.WHITE])
		elif (b == 4 or b == 8) and _dry_grass(p) and n > 0.9:
			small.append([p, "bush_flower", 0.7 + n * 0.5, Color(0.95, 0.9, 0.7)])
		elif (b == 4 or b == 8 or b == 6) and n > 0.9:
			small.append([p, "rock", 0.6 + n * 1.2, Color.WHITE])
		elif b == 2 and n > 0.97:
			small.append([p, "rock", 0.5 + n * 0.6, Color.WHITE]))
	var d: Dictionary = {"big": _pack(big, o), "small": _pack(small, o)}
	_data[k] = d
	_order.append(k)
	return d


## Обхід сітки кроку s у клітинці o (глобальна сітка — стиків між клітинками немає)
func _grid(o: Vector2, s: float, salt: int, f: Callable) -> void:
	var x0: int = floori(o.x / s)
	var y0: int = floori(o.y / s)
	var tl: Node = game.get("trails") if game != null else null
	var st: Node = game.get("settlements") if game != null else null
	if st != null and not st.has_method("near_dot"):
		st = null
	var x1: int = floori((o.x + CHUNK) / s)
	var y1: int = floori((o.y + CHUNK) / s)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var n: float = Art.seed_at(x, y, salt)
			var p := (Vector2(x, y) + Vector2(0.15 + n * 0.7, 0.15 + Art.seed_at(x, y, salt + 9) * 0.7)) * s
			if p.x < o.x or p.y < o.y or p.x >= o.x + CHUNK or p.y >= o.y + CHUNK:
				continue
			var b: int = game.biome_at(p)
			# Протоптана стежка й дорога (world/trails_layer.gd) і місце міста-точки — без дерев і кущів
			if b >= 2 and (tl == null or not tl.trodden(p)) and (st == null or not st.near_dot(p)):
				f.call(p, n, b)


## Сортування за y й пакування: x, y, ширина, висота, r, g, b, ключ
func _pack(items: Array, o: Vector2) -> Array:
	items.sort_custom(func(a: Array, b: Array) -> bool: return a[0].y < b[0].y)
	return items.map(func(e: Array) -> Array: return [e[0] - o, e[1], e[2], e[3]])


## Смуги клітинки: екземпляри (дерева й дрібниця разом) за висотою ніг, координати ряду (x — карти, y — від верху ряду)
func _chunk_bands(k: Vector2i) -> Array:
	if _bands.has(k):
		return _bands[k]
	var d: Dictionary = _chunk_data(k)
	var items: Array = []
	for e in d["big"]:
		items.append([e, 1.0])
	for e in d["small"]:
		items.append([e, SMALL_FLAG])
	items.sort_custom(func(a: Array, b: Array) -> bool: return a[0][0].y < b[0][0].y)
	var bands: Array = []
	for i in BANDS:
		bands.append(PackedFloat32Array())
	var ox: float = float(k.x) * CHUNK
	for it in items:
		var e: Array = it[0]
		var key: String = e[1]
		var h: float = e[2]
		var w: float = h * float(_aspect.get(key, 1.0))
		var p: Vector2 = e[0]
		var wp := Vector2(ox + p.x, float(k.y) * CHUNK + p.y)
		# Дзеркало для різноманіття
		if fposmod(wp.x * 0.37 + wp.y * 0.11, 1.0) > 0.5:
			w = -w
		var col: Color = e[3]
		var uv: Color = _uv.get(key, Color(0, 0, 0, 0))
		var bi: int = clampi(int(p.y / BAND_M), 0, BANDS - 1)
		bands[bi].append_array(PackedFloat32Array([w, 0.0, 0.0, wp.x, 0.0, h, 0.0, p.y,
			col.r, col.g, col.b, it[1], uv.r, uv.g, uv.b, uv.a]))
	_bands[k] = bands
	return bands


## Ряд cy від клітинки c0 до c1 — один MultiMesh: смуга за смугою, у смузі клітинки зліва направо
func _build_row(cy: int, c0: int, c1: int, full: bool) -> void:
	var buf := PackedFloat32Array()
	for bi in BANDS:
		for cx in range(c0, c1 + 1):
			var bands: Array = _bands.get(Vector2i(cx, cy), [])
			if not bands.is_empty():
				buf.append_array(bands[bi])
	var row: Dictionary = _rows.get(cy, {})
	if row.is_empty():
		var mi := MultiMeshInstance2D.new()
		mi.texture = _atlas
		mi.material = _mat
		mi.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		mi.position = Vector2(0.0, float(cy) * CHUNK)
		_root.add_child(mi)
		row = {"node": mi}
		_rows[cy] = row
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = _mesh
	mm.instance_count = buf.size() / FLOATS
	if buf.size() > 0:
		mm.buffer = buf
	row["node"].multimesh = mm
	row["c0"] = c0
	row["c1"] = c1
	row["full"] = full
	_sort_rows()


## Ряди в корені — згори вниз (нижній ряд перекриває верхній)
func _sort_rows() -> void:
	var keys: Array = _rows.keys()
	keys.sort()
	for i in keys.size():
		_root.move_child(_rows[keys[i]]["node"], i)


## Сигнальна вежа (Q31 B) біля точки p ближче reach м: її місце (ноги) або Vector2.INF.
## Те саме правило, що й розстановка в _chunk_data: сітка 64 м, сіль 5, рідкісний шум, суходіл без гір і боліт
func tower_near(p: Vector2, reach: float) -> Vector2:
	if game == null:
		return Vector2.INF
	var s: float = 64.0
	var tl: Node = game.get("trails")
	var st: Node = game.get("settlements")
	for y in range(floori((p.y - reach) / s) - 1, floori((p.y + reach) / s) + 1):
		for x in range(floori((p.x - reach) / s) - 1, floori((p.x + reach) / s) + 1):
			var n: float = Art.seed_at(x, y, 5)
			if n <= 0.993:
				continue
			var q := (Vector2(x, y) + Vector2(0.15 + n * 0.7, 0.15 + Art.seed_at(x, y, 14) * 0.7)) * s
			if q.distance_to(p) > reach or not game.biome_at(q) in [2, 3, 4, 7, 8]:
				continue
			if (tl != null and tl.trodden(q)) or (st != null and st.has_method("near_dot") and st.near_dot(q)):
				continue
			return q
	return Vector2.INF


## Точка лежить на галявині лісу (b — біом точки): дерев декор тут не садить, шейдер малює луг
func glade(p: Vector2, b: int) -> bool:
	return (b == 3 or b == 7) and _clearing(p)


# Галявина в лісі й суха трава в пустці — ті самі плями, що малює шейдер (map_shaders.gd)
func _clearing(p: Vector2) -> bool:
	return _noise2(p / 520.0 + Vector2(4.3, 9.1)) > 0.66


func _dry_grass(p: Vector2) -> bool:
	return _noise2(p / 430.0 + Vector2(1.9, 6.2)) > 0.69


## noise2 із шейдера: vnoise3(p, 17) за тією самою текстурою шуму
func _noise2(p: Vector2) -> float:
	if _noise == null:
		return 0.0
	var iz: float = 17.0
	var i := Vector2(floor(p.x), floor(p.y))
	var f := p - i
	f = f * f * (Vector2(3, 3) - 2.0 * f)
	var b := Vector2(fposmod(i.x + 37.0 * iz, 256.0), fposmod(i.y + 17.0 * iz, 256.0))
	var b1 := Vector2(fposmod(b.x + 1.0, 256.0), fposmod(b.y + 1.0, 256.0))
	var t00: Color = _noise.get_pixel(int(b.x), int(b.y))
	var t10: Color = _noise.get_pixel(int(b1.x), int(b.y))
	var t01: Color = _noise.get_pixel(int(b.x), int(b1.y))
	var t11: Color = _noise.get_pixel(int(b1.x), int(b1.y))
	var r: float = lerpf(lerpf(t00.r, t10.r, f.x), lerpf(t01.r, t11.r, f.x), f.y)
	return r   # z ціле (17) — змішувати з каналом G не треба


# =====================================================================
# АТЛАС, СІТКА, ШЕЙДЕР
# =====================================================================
func _build_atlas() -> void:
	var cols: int = 4
	var rows: int = ceili(float(KEYS.size()) / cols)
	var img := Image.create(cols * CELL_PX, rows * CELL_PX, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var inner: int = CELL_PX - PAD * 2
	var sh_px: int = int(inner * SHADOW)
	for i in KEYS.size():
		var key: String = KEYS[i]
		var t: Texture2D = Art.tex(key)
		if t == null:
			continue
		var src: Image = t.get_image()
		if src.is_compressed():
			src.decompress()
		src.convert(Image.FORMAT_RGBA8)
		var hh: int = inner - sh_px
		var ww: int = mini(inner, int(round(float(src.get_width()) * hh / src.get_height())))
		hh = int(round(float(src.get_height()) * ww / src.get_width()))
		src.resize(ww, hh, Image.INTERPOLATE_LANCZOS)
		var cx: int = (i % cols) * CELL_PX + PAD
		var cy: int = (i / cols) * CELL_PX + PAD
		var foot_y: int = cy + inner - sh_px
		# Тінь під ногами — м'який еліпс
		var rx: float = ww * 0.32
		var ry: float = sh_px * 0.55
		for y in range(maxi(foot_y - int(ry), cy), mini(foot_y + int(ry) + 1, cy + inner)):
			for x in range(cx + inner / 2 - int(rx), cx + inner / 2 + int(rx) + 1):
				var q: float = pow((x - (cx + inner / 2)) / rx, 2.0) + pow((y - foot_y) / ry, 2.0)
				if q < 1.0:
					img.set_pixel(x, y, Color(0.12, 0.1, 0.07, 0.22 * (1.0 - q)))
		img.blend_rect(src, Rect2i(0, 0, ww, hh), Vector2i(cx + (inner - ww) / 2, foot_y - hh))
		# Квад: x від -0,5 до 0,5 ширини, y від -1 до SHADOW/(1-SHADOW) висоти; в атласі — та сама частка
		var w_full: float = float(ww)
		var u0: float = float(cx + (inner - ww) / 2) / img.get_width()
		var v0: float = float(foot_y - hh) / img.get_height()
		_uv[key] = Color(u0, v0, w_full / img.get_width(), float(hh + sh_px) / img.get_height())
		_aspect[key] = w_full / float(hh)
	img.generate_mipmaps()
	_atlas = ImageTexture.create_from_image(img)


func _build_mesh() -> void:
	var k: float = SHADOW / (1.0 - SHADOW)
	var v := PackedVector2Array([Vector2(-0.5, -1.0), Vector2(0.5, -1.0), Vector2(0.5, k), Vector2(-0.5, k)])
	var uv := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	_mesh = ArrayMesh.new()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var sh := Shader.new()
	# Альфа екземпляра — ознака: 1 велике, SMALL_FLAG дрібниця; проявлення за масштабом — big_a / small_a
	sh.code = """shader_type canvas_item;
uniform float big_a = 1.0;
uniform float small_a = 1.0;
void vertex() {
	UV = INSTANCE_CUSTOM.xy + UV * INSTANCE_CUSTOM.zw;
	COLOR.a = COLOR.a > 0.75 ? big_a : small_a;
}
"""
	_mat = ShaderMaterial.new()
	_mat.shader = sh

extends Node2D
## Деревья, горы, кусты и камни общей карты — как в Day R (Huzzah 2026-10-23):
## у каждого спрайта свой размер в метрах, поэтому при самом близком зуме у пешки деревья и горы
## крупные, а при отдалении они сжимаются и сливаются в пятно своего биома (лес — сплошной лес,
## горы — гряды), дальше — только текстура и цвет биома.
## По биомам: лес — густые деревья (поляны шейдера — без деревьев, с цветами), проклятый лес — кривые
## деревья с лиловым оттенком, болото — редкие кривые деревья и кусты, пустошь — редкие сухие деревья
## и камни, горы — горы и скалы в 8–15 м (жаркие — рыжие), берег — камешки.
##
## Быстро: карта делится на клетки CHUNK м; у клетки два MultiMesh (крупное и мелочь) из одного атласа,
## один вызов отрисовки на клетку. Клетки считаются по нескольку за кадр от центра экрана и
## запоминаются; сдвиг камеры меняет только преобразование корня.

const Art := preload("res://storybook/art.gd")

const CHUNK: float = 128.0
const BUILD_MS: float = 5.0            # сколько миллисекунд кадра можно тратить на новые клетки
const MAX_CACHED: int = 2500           # клеток в памяти (данные), узлы — только видимые
const BIG_FROM_Z: float = 0.5          # крупное (деревья, горы) видно с этого масштаба (пикселей на метр)
const BIG_FULL_Z: float = 0.9
const SMALL_FROM_Z: float = 3.0        # мелочь (кусты, камни)
const SMALL_FULL_Z: float = 5.0
const SHADOW: float = 0.12             # доля высоты под ногами в ячейке атласа (тень)

## Ключ спрайта -> высота ячейки атласа (пикс.)
const KEYS: Array = ["tree_oak", "tree_light", "tree_crooked", "mountain_gray", "ridge_gray", "peak_gray", "cliff_gray",
	"mountain_hot", "mesa_hot", "ridge_hot", "bush_flower", "bush_berry", "rock", "tech_tower"]
const CELL_PX: int = 288
const PAD: int = 16

var game: Node2D
var _root := Node2D.new()
var _atlas: ImageTexture
var _uv: Dictionary = {}               # ключ -> Color(u0, v0, du, dv)
var _aspect: Dictionary = {}           # ключ -> ширина / высота
var _mesh: ArrayMesh
var _mat: ShaderMaterial
var _data: Dictionary = {}             # Vector2i -> {big: PackedFloat32Array, small: ...} (по 8 чисел на спрайт)
var _nodes: Dictionary = {}            # Vector2i -> Node2D с двумя MultiMeshInstance2D
var _order: Array = []                 # порядок появления данных (для вытеснения)
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
	var z: float = game.zoom
	var vp: Vector2 = get_viewport_rect().size
	_root.position = vp * 0.5 - game.cam_pos * z
	_root.scale = Vector2(z, z)
	# Свет по часам, как у остального декора
	var hour: float = game.clock.hour_of_day()
	var daylight: float = clampf(sin((hour - 6.0) / 12.0 * PI) * 1.4, 0.0, 1.0)
	_root.modulate = Color(0.32, 0.39, 0.51).lerp(Color.WHITE, daylight)
	var big_a: float = smoothstep(BIG_FROM_Z, BIG_FULL_Z, z)
	var small_a: float = smoothstep(SMALL_FROM_Z, SMALL_FULL_Z, z)
	if big_a <= 0.0:
		_root.visible = false
		return
	_root.visible = true
	# Видимые клетки (с запасом в половину клетки)
	var half: Vector2 = vp * 0.5 / z + Vector2(CHUNK, CHUNK) * 0.5
	var c0 := Vector2i(floori((game.cam_pos.x - half.x) / CHUNK), floori((game.cam_pos.y - half.y) / CHUNK))
	var c1 := Vector2i(floori((game.cam_pos.x + half.x) / CHUNK), floori((game.cam_pos.y + half.y) / CHUNK))
	var want: Dictionary = {}
	var todo: Array = []
	for cy in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var k := Vector2i(cx, cy)
			if cx < 0 or cy < 0 or cx * CHUNK > game.MAP_SIZE.x or cy * CHUNK > game.MAP_SIZE.y:
				continue
			want[k] = true
			if not _nodes.has(k):
				todo.append(k)
	# Ушедшие с экрана — убрать узлы
	for k in _nodes.keys():
		if not want.has(k):
			_nodes[k].queue_free()
			_nodes.erase(k)
	# Новые — от центра, сколько успеем за кадр
	var mid := Vector2(game.cam_pos.x / CHUNK - 0.5, game.cam_pos.y / CHUNK - 0.5)
	todo.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return Vector2(a).distance_squared_to(mid) < Vector2(b).distance_squared_to(mid))
	var t0: int = Time.get_ticks_usec()
	for k in todo:
		if not _data.has(k) and float(Time.get_ticks_usec() - t0) > BUILD_MS * 1000.0:
			break
		_nodes[k] = _make_node(k)
		_root.add_child(_nodes[k])
	for k in _nodes:
		var n: Node2D = _nodes[k]
		n.get_child(1).visible = small_a > 0.0
		(n.get_child(0) as CanvasItem).self_modulate.a = big_a
		(n.get_child(1) as CanvasItem).self_modulate.a = small_a
	while _order.size() > MAX_CACHED:
		var old: Vector2i = _order.pop_front()
		if not _nodes.has(old):
			_data.erase(old)


# =====================================================================
# РАССТАНОВКА (детерминированная: та же точка — тот же спрайт)
# =====================================================================
func _chunk_data(k: Vector2i) -> Dictionary:
	if _data.has(k):
		return _data[k]
	var big: Array = []
	var small: Array = []
	var o := Vector2(k) * CHUNK
	# Крупное: деревья по сетке 5,5 м (лес), горы по 9 м, остальное реже
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
			# Объём гор: выше по карте высот — скалы крупнее, у вершин — пики (Huzzah 2026-10-24)
			var up: float = game.height_at(p) / game.HEIGHT_MAX_M if game.has_method("height_at") else 0.5
			var key: String = ["mountain_hot", "mesa_hot", "ridge_hot"][int(n * 17.0) % 3] if hot else ("peak_gray" if up > 0.75 and n > 0.4 else ["mountain_gray", "ridge_gray", "peak_gray", "cliff_gray"][int(n * 19.0) % 4])
			big.append([p, key, (8.0 + fposmod(n * 9.1, 1.0) * 7.0) * (0.65 + 0.8 * up), Color.WHITE]))
	# Техно-артефакты (Q31 B): редкие сигнальные вышки 16–24 м — около одной на 2 км² суши, кроме гор и болот
	_grid(o, 64.0, 5, func(p: Vector2, n: float, b: int):
		if b in [2, 3, 4, 7, 8] and n > 0.993:
			big.append([p, "tech_tower", 16.0 + fposmod(n * 911.0, 1.0) * 8.0, Color.WHITE]))
	# Мелочь: кусты и камни по 4 м
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


## Обход сетки шага s в клетке o (глобальная сетка — стыков между клетками нет)
func _grid(o: Vector2, s: float, salt: int, f: Callable) -> void:
	var x0: int = floori(o.x / s)
	var y0: int = floori(o.y / s)
	var x1: int = floori((o.x + CHUNK) / s)
	var y1: int = floori((o.y + CHUNK) / s)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var n: float = Art.seed_at(x, y, salt)
			var p := (Vector2(x, y) + Vector2(0.15 + n * 0.7, 0.15 + Art.seed_at(x, y, salt + 9) * 0.7)) * s
			if p.x < o.x or p.y < o.y or p.x >= o.x + CHUNK or p.y >= o.y + CHUNK:
				continue
			var b: int = game.biome_at(p)
			if b >= 2:
				f.call(p, n, b)


## Сортировка по y и упаковка: x, y, ширина, высота, r, g, b, ключ
func _pack(items: Array, o: Vector2) -> Array:
	items.sort_custom(func(a: Array, b: Array) -> bool: return a[0].y < b[0].y)
	return items.map(func(e: Array) -> Array: return [e[0] - o, e[1], e[2], e[3]])


func _make_node(k: Vector2i) -> Node2D:
	var d: Dictionary = _chunk_data(k)
	var n := Node2D.new()
	n.position = Vector2(k) * CHUNK
	n.add_child(_mm(d["big"]))
	n.add_child(_mm(d["small"]))
	return n


func _mm(items: Array) -> MultiMeshInstance2D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = _mesh
	mm.instance_count = items.size()
	for i in items.size():
		var e: Array = items[i]
		var key: String = e[1]
		var h: float = e[2]
		var w: float = h * float(_aspect[key])
		# Зеркало для разнообразия
		if fposmod(e[0].x * 0.37 + e[0].y * 0.11, 1.0) > 0.5:
			w = -w
		mm.set_instance_transform_2d(i, Transform2D(Vector2(w, 0), Vector2(0, h), e[0]))
		mm.set_instance_color(i, e[3])
		mm.set_instance_custom_data(i, _uv[key])
	var mi := MultiMeshInstance2D.new()
	mi.multimesh = mm
	mi.texture = _atlas
	mi.material = _mat
	mi.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return mi


# Поляна в лесу и сухая трава в пустоши — те же пятна, что рисует шейдер (map_shaders.gd)
func _clearing(p: Vector2) -> bool:
	return _noise2(p / 520.0 + Vector2(4.3, 9.1)) > 0.66


func _dry_grass(p: Vector2) -> bool:
	return _noise2(p / 430.0 + Vector2(1.9, 6.2)) > 0.69


## noise2 из шейдера: vnoise3(p, 17) по той же текстуре шума
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
	return r   # z целое (17) — смешивать с каналом G не нужно


# =====================================================================
# АТЛАС, СЕТКА, ШЕЙДЕР
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
		# Тень под ногами — мягкий эллипс
		var rx: float = ww * 0.32
		var ry: float = sh_px * 0.55
		for y in range(maxi(foot_y - int(ry), cy), mini(foot_y + int(ry) + 1, cy + inner)):
			for x in range(cx + inner / 2 - int(rx), cx + inner / 2 + int(rx) + 1):
				var q: float = pow((x - (cx + inner / 2)) / rx, 2.0) + pow((y - foot_y) / ry, 2.0)
				if q < 1.0:
					img.set_pixel(x, y, Color(0.12, 0.1, 0.07, 0.22 * (1.0 - q)))
		img.blend_rect(src, Rect2i(0, 0, ww, hh), Vector2i(cx + (inner - ww) / 2, foot_y - hh))
		# Квад: x от -0,5 до 0,5 ширины, y от -1 до SHADOW/(1-SHADOW) высоты; в атласе — та же доля
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
	sh.code = """shader_type canvas_item;
void vertex() {
	UV = INSTANCE_CUSTOM.xy + UV * INSTANCE_CUSTOM.zw;
}
"""
	_mat = ShaderMaterial.new()
	_mat.shader = sh

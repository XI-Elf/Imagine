extends RefCounted
## Обрис області для пергаменту (Huzzah 2026-10-30): лист показує лише поточну область, її край — легкий пунктир.
## Межу беремо з шару областей art/map/map_provinces.png (номер області в пікселі, як game.province_at):
## клітинки області на сітці з кроком STRIDE пікселів шару, зовнішні ребра зшиваються в замкнені ламані,
## потім спрощення й легке згладжування. Результат у метрах дошки, кеш на весь сеанс.

const STRIDE: int = 2            # крок сітки, пікселів шару областей (≈35 м)
const BOX_STRIDE: int = 4        # крок першого проходу, що шукає рамки всіх областей
const MIN_LOOP: int = 10         # дрібніші острівці не обводимо

static var _boxes: Dictionary = {}    # id -> Rect2i у пікселях шару
static var _loops: Dictionary = {}    # id -> Array[PackedVector2Array] у метрах
static var _img_id: int = 0


static func _prepare(img: Image) -> void:
	if img == null or img.get_instance_id() == _img_id:
		return
	_img_id = img.get_instance_id()
	_boxes = {}
	_loops = {}
	var w: int = img.get_width()
	var h: int = img.get_height()
	var data: PackedByteArray = _bytes(img)
	for y in range(0, h, BOX_STRIDE):
		var row: int = y * w
		for x in range(0, w, BOX_STRIDE):
			var id: int = data[row + x]
			if id == 0:
				continue
			if _boxes.has(id):
				var r: Rect2i = _boxes[id]
				_boxes[id] = r.expand(Vector2i(x, y))
			else:
				_boxes[id] = Rect2i(x, y, 0, 0)


static func _bytes(img: Image) -> PackedByteArray:
	if img.get_format() == Image.FORMAT_L8:
		return img.get_data()
	var c: Image = img.duplicate()
	c.convert(Image.FORMAT_L8)
	return c.get_data()


## Рамка області в метрах (порожня, якщо такої області немає)
static func bounds(img: Image, id: int, map_size: Vector2) -> Rect2:
	_prepare(img)
	if not _boxes.has(id):
		return Rect2()
	var r: Rect2i = _boxes[id].grow(BOX_STRIDE)
	var k := Vector2(map_size.x / img.get_width(), map_size.y / img.get_height())
	return Rect2(Vector2(r.position) * k, Vector2(r.size) * k)


## Замкнені ламані краю області id у метрах
static func loops(img: Image, id: int, map_size: Vector2) -> Array:
	_prepare(img)
	if _loops.has(id):
		return _loops[id]
	var out: Array = []
	if not _boxes.has(id):
		return out
	var w: int = img.get_width()
	var h: int = img.get_height()
	var data: PackedByteArray = _bytes(img)
	var box: Rect2i = _boxes[id].grow(BOX_STRIDE * 2).intersection(Rect2i(0, 0, w, h))
	var s: int = STRIDE
	var cw: int = box.size.x / s + 1
	var ch: int = box.size.y / s + 1
	var inside := PackedByteArray()
	inside.resize(cw * ch)
	for j in ch:
		var py: int = mini(box.position.y + j * s, h - 1)
		for i in cw:
			var px: int = mini(box.position.x + i * s, w - 1)
			inside[j * cw + i] = 1 if data[py * w + px] == id else 0
	# Ребра між клітинкою області й чужою — за годинниковою стрілкою, вузли (cx, cy) як cy*(cw+1)+cx
	var nx: int = cw + 1
	var nxt: Dictionary = {}
	for j in ch:
		for i in cw:
			if inside[j * cw + i] == 0:
				continue
			if j == 0 or inside[(j - 1) * cw + i] == 0:
				_edge(nxt, j * nx + i, j * nx + i + 1)
			if i == cw - 1 or inside[j * cw + i + 1] == 0:
				_edge(nxt, j * nx + i + 1, (j + 1) * nx + i + 1)
			if j == ch - 1 or inside[(j + 1) * cw + i] == 0:
				_edge(nxt, (j + 1) * nx + i + 1, (j + 1) * nx + i)
			if i == 0 or inside[j * cw + i - 1] == 0:
				_edge(nxt, (j + 1) * nx + i, j * nx + i)
	var k := Vector2(map_size.x / w, map_size.y / h)
	while not nxt.is_empty():
		var start: int = nxt.keys()[0]
		var loop := PackedVector2Array()
		var cur: int = start
		var guard: int = 0
		while guard < 1000000:
			guard += 1
			loop.append(Vector2(box.position.x + (cur % nx) * s, box.position.y + (cur / nx) * s) * k)
			var outs: Array = nxt.get(cur, [])
			if outs.is_empty():
				break
			var to: int = outs.pop_back()
			if outs.is_empty():
				nxt.erase(cur)
			cur = to
			if cur == start:
				break
		if loop.size() >= MIN_LOOP:
			loop.append(loop[0])
			out.append(_soften(_simplify(loop, k.x * s * 0.9)))
	_loops[id] = out
	return out


static func _edge(nxt: Dictionary, a: int, b: int) -> void:
	if nxt.has(a):
		nxt[a].append(b)
	else:
		nxt[a] = [b]


## Рамер — Дуглас — Пекер
static func _simplify(p: PackedVector2Array, eps: float) -> PackedVector2Array:
	if p.size() < 3:
		return p
	var keep := PackedByteArray()
	keep.resize(p.size())
	keep[0] = 1
	keep[p.size() - 1] = 1
	var stack: Array = [[0, p.size() - 1]]
	while not stack.is_empty():
		var se: Array = stack.pop_back()
		var a: int = se[0]
		var b: int = se[1]
		var best: float = -1.0
		var bi: int = -1
		for i in range(a + 1, b):
			var d: float = Geometry2D.get_closest_point_to_segment(p[i], p[a], p[b]).distance_to(p[i])
			if d > best:
				best = d
				bi = i
		if bi >= 0 and best > eps:
			keep[bi] = 1
			stack.append([a, bi])
			stack.append([bi, b])
	var out := PackedVector2Array()
	for i in p.size():
		if keep[i] == 1:
			out.append(p[i])
	return out


## Один прохід Чайкіна: сходинки пікселів стають плавною лінією, як рукою
static func _soften(p: PackedVector2Array) -> PackedVector2Array:
	if p.size() < 4:
		return p
	var out := PackedVector2Array()
	for i in p.size() - 1:
		out.append(p[i].lerp(p[i + 1], 0.25))
		out.append(p[i].lerp(p[i + 1], 0.75))
	out.append(out[0])
	return out

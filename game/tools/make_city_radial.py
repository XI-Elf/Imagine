# Радиальный город (решение Huzzah 2026-10-23: город и все поселения — как в средневековье, радиальные):
# круглая каменная стена, площадь в центре, улицы лучами от площади (главная — к воротам),
# кольцевые улицы и дорога вдоль стены изнутри, кварталы между ними.
# Здания, жители, места и правила берутся из прежнего описания города (имена, реплики, товары);
# заново считаются только координаты. Сетка и проходимость — те же, что строит city/city_map.gd
# (план "radial": клетки дальше wall_r + 1 от центра — за стеной, кольцо шириной 2 клетки — стена).
# Запуск: python3 make_city_radial.py <прежний s001.json> <выходной s001.json> [seed]
import json, math, random, sys
from collections import deque

src_path, out_path = sys.argv[1], sys.argv[2]
SEED = int(sys.argv[3]) if len(sys.argv) > 3 else 1488
src = json.load(open(src_path, encoding='utf-8'))
rng = random.Random(SEED)

N = 128                    # клеток по стороне (2 м)
C = N / 2.0                # центр города
R = 61                     # радиус стены, клеток
SQ_R = 11                  # площадь
RING1, RING2, POM = 29, 44, 57    # кольцевые улицы; POM — дорога вдоль стены изнутри
SPOKES = [90, 45, 135, 0, 180, -45, -135, -90]   # лучи, градусы (90 — юг, к воротам)
BANDS = {'A': (SQ_R + 2, RING1 - 2), 'B': (RING1 + 2, RING2 - 2), 'C': (RING2 + 2, POM - 2)}

GRASS, ROAD, SQUARE, PALISADE, WALL, FLOOR, DOOR, WELL, GATE, FIELD, TREE, STALL, RUBBLE, OUTSIDE = range(14)
WALKABLE = {GRASS, ROAD, SQUARE, FIELD, DOOR, FLOOR, RUBBLE}
grid = [[GRASS] * N for _ in range(N)]
reserved = set()           # клетки перед дверями и у ворот: сюда ничего не ставим


def put(x, y, t):
	if 0 <= x < N and 0 <= y < N:
		grid[y][x] = t


def at(x, y):
	return grid[y][x] if 0 <= x < N and 0 <= y < N else OUTSIDE


def dist(x, y):
	return math.hypot(x + 0.5 - C, y + 0.5 - C)


def gd_round(v):           # Vector2.round() в Godot: половина — от нуля
	return int(math.floor(v + 0.5)) if v >= 0 else -int(math.floor(-v + 0.5))


def polar(r, deg):
	a = math.radians(deg)
	return C + math.cos(a) * r, C + math.sin(a) * r


roads = []


def road(a, b, w):
	# Как city_map._road: кисть w×w от точки вправо-вниз; сдвигаем, чтобы улица шла по оси
	o = w // 2
	a = [gd_round(a[0] - 0.5) - o, gd_round(a[1] - 0.5) - o]
	b = [gd_round(b[0] - 0.5) - o, gd_round(b[1] - 0.5) - o]
	if a == b:
		return
	roads.append({'from': a, 'to': b, 'w': w})
	n = max(abs(b[0] - a[0]), abs(b[1] - a[1]))
	for i in range(n + 1):
		t = i / max(n, 1)
		px, py = a[0] + gd_round((b[0] - a[0]) * t), a[1] + gd_round((b[1] - a[1]) * t)
		for dy in range(w):
			for dx in range(w):
				put(px + dx, py + dy, ROAD)


def ring(r, w, segs=72):
	pts = [polar(r, 360.0 * k / segs) for k in range(segs + 1)]
	for p, q in zip(pts, pts[1:]):
		road(p, q, w)


# ---- Улицы ----
ring(RING1, 2)
ring(RING2, 2)
ring(POM, 2, 96)
for a in SPOKES:
	main = a == 90
	# Главные улицы (по сторонам света) — от площади; диагональные переулки — от первого кольца
	r0 = SQ_R - 1 if a % 90 == 0 else RING1
	road(polar(r0, a), polar(R + 1.5 if main else POM, a), 4 if main else 2)

# ---- Площадь ----
square = {'id': 'market', 'name': 'Торговая площадь', 'circle': [C, C, SQ_R],
	'rect': [int(C - SQ_R), int(C - SQ_R), 2 * SQ_R, 2 * SQ_R]}
for y in range(N):
	for x in range(N):
		if dist(x, y) <= SQ_R:
			put(x, y, SQUARE)

# ---- Стена и земля за ней ----
for y in range(N):
	for x in range(N):
		d = dist(x, y)
		if d >= R + 1.0:
			put(x, y, OUTSIDE)
		elif d >= R - 1.0:
			put(x, y, PALISADE)

# Ворота: стена на столбцах главной улицы
gate_cols = range(int(C) - 2, int(C) + 2)
gate_cells = [[x, y] for x in gate_cols for y in range(int(C), N) if at(x, y) == PALISADE]
for x, y in gate_cells:
	put(x, y, GATE)
gate_y = min(y for _, y in gate_cells)
spawn = [C, gate_y - 2.5]
guard_post = [int(C) - 4, gate_y - 3]
for y in range(gate_y - 5, gate_y):
	for x in range(int(C) - 5, int(C) + 5):
		reserved.add((x, y))

# Башни: по кругу через 30° и по бокам ворот (клетки на стене)
towers = []
for k in range(12):
	a = 30.0 * k + 15.0
	x, y = polar(R, a)
	towers.append([int(x), int(y)])
towers += [[int(C) - 4, gate_y], [int(C) + 3, gate_y]]


# ---- Здания ----
def rect_free(r, pad=1):
	x0, y0, w, h = r
	for y in range(y0 - pad, y0 + h + pad):
		for x in range(x0 - pad, x0 + w + pad):
			inside = x0 <= x < x0 + w and y0 <= y < y0 + h
			t = at(x, y)
			if inside:
				if t != GRASS or (x, y) in reserved or dist(x, y) > POM - 1.5:
					return False
			elif t not in (GRASS, ROAD, SQUARE, FIELD):
				return False
	return True


def door_of(r):
	# Дверь — клетка стены (не угол), перед которой улица или площадь; иначе трава ближе к улице
	x0, y0, w, h = r
	best, best_s = None, -1e9
	cand = [(x, y0, 0, -1) for x in range(x0 + 1, x0 + w - 1)] + [(x, y0 + h - 1, 0, 1) for x in range(x0 + 1, x0 + w - 1)] + \
		[(x0, y, -1, 0) for y in range(y0 + 1, y0 + h - 1)] + [(x0 + w - 1, y, 1, 0) for y in range(y0 + 1, y0 + h - 1)]
	for x, y, dx, dy in cand:
		fx, fy = x + dx, y + dy
		t = at(fx, fy)
		if t not in (GRASS, ROAD, SQUARE) or (fx, fy) in reserved:
			continue
		s = 0.0
		for k in range(1, 4):
			if at(x + dx * k, y + dy * k) in (ROAD, SQUARE):
				s = 10.0 - k
				break
		# Дверь ближе к середине стены
		s -= 0.15 * (abs(x - (x0 + (w - 1) / 2)) + abs(y - (y0 + (h - 1) / 2)))
		if s > best_s:
			best, best_s = (x, y, dx, dy), s
	return best if best_s > 0 else None


placed = {}


def build(bid, r, ruins=False):
	x0, y0, w, h = r
	dx_ = door_of(r)
	if dx_ is None:
		return None
	x, y, dx, dy = dx_
	for yy in range(y0, y0 + h):
		for xx in range(x0, x0 + w):
			edge = xx in (x0, x0 + w - 1) or yy in (y0, y0 + h - 1)
			put(xx, yy, WALL if edge else FLOOR)
	put(x, y, DOOR)
	for k in range(1, 3):
		reserved.add((x + dx * k, y + dy * k))
	placed[bid] = {'rect': [x0, y0, w, h], 'door': [x, y]}
	return placed[bid]


def place(bid, w, h, band, ang, spread=180.0, ruins=False):
	lo, hi = BANDS[band]
	angs = sorted([ang + s for s in [k * 2.0 for k in range(-int(spread / 2), int(spread / 2) + 1)]], key=lambda a: abs(a - ang))
	rads = sorted(range(lo, hi + 1), key=lambda r: abs(r - (lo + hi) / 2))
	for a in angs:
		for rr in rads:
			cx, cy = polar(rr, a)
			for (ww, hh) in ((w, h), (h, w)) if w != h else ((w, h),):
				r = [int(round(cx - ww / 2)), int(round(cy - hh / 2)), ww, hh]
				if rect_free(r) and build(bid, r, ruins):
					return placed[bid]
	raise SystemExit('нет места для %s' % bid)


# Площадь: детинец к северу, храм к востоку, лавки вокруг
place("hall", 15, 9, 'A', -60, 50)
place('temple', 12, 10, 'A', -25, 40)
place('inn', 14, 9, 'A', 118, 40)
place('shop', 10, 8, 'A', 180, 40)
place('healer', 10, 7, 'A', -150, 40)
place('tailor', 10, 7, 'A', 30, 40)
place('barracks', 11, 7, 'C', 72, 30)        # у ворот
place('smithy', 10, 7, 'C', 10, 40)          # у стены: огонь подальше от площади
place('ruins_n', 10, 8, 'C', -55, 40, ruins=True)
place('ruins_e', 10, 8, 'C', -10, 40, ruins=True)

# Огороды и второй колодец — во внешнем кольце
fields = []


def place_field(w, h, ang):
	lo, hi = BANDS['C']
	for s in range(0, 90, 2):
		for a in (ang + s, ang - s):
			for rr in range(lo, hi + 1):
				cx, cy = polar(rr, a)
				r = [int(round(cx - w / 2)), int(round(cy - h / 2)), w, h]
				if rect_free(r):
					for yy in range(r[1], r[1] + h):
						for xx in range(r[0], r[0] + w):
							put(xx, yy, FIELD)
					fields.append({'rect': r})
					return r
	raise SystemExit('нет места для огорода')


f1 = place_field(10, 7, 155)
f2 = place_field(10, 7, -120)

wells = []
wx, wy = int(C) + 5, int(C) + 3
wells.append([[wx, wy], [wx + 1, wy], [wx, wy + 1], [wx + 1, wy + 1]])


def place_well(ang):
	lo, hi = BANDS['C']
	for s in range(0, 90, 2):
		for a in (ang + s, ang - s):
			for rr in range(lo, hi + 1):
				cx, cy = polar(rr, a)
				x, y = int(cx), int(cy)
				if rect_free([x, y, 2, 2], 2):
					cells = [[x, y], [x + 1, y], [x, y + 1], [x + 1, y + 1]]
					for c in cells:
						put(c[0], c[1], WELL)
					wells.append(cells)
					return cells
	raise SystemExit('нет места для колодца')


for c in wells[0]:
	put(c[0], c[1], WELL)
w2 = place_well(135)

# Дома с жителями из сюжета — рядом с их делом
place('house_1', 9, 7, 'C', 165, 60)          # Годрик — у огорода
place('house_2', 9, 7, 'B', -170, 60)
place('house_3', 9, 7, 'C', 128, 50)          # вдова — у колодца
place('house_4', 9, 7, 'B', 160, 60)
place('house_5', 9, 7, 'B', -110, 60)
place('house_6', 9, 7, 'C', 100, 50)          # у южной стены
place('house_7', 9, 7, 'C', 50, 60)           # старьёвщик

# Кварталы: дома ремесленников по кольцам, от площади наружу
quarter = [b['id'] for b in src['buildings'] if b['id'].startswith('quarter_house_')]
order = []
for band in ('B', 'C', 'A'):
	for k in range(36):
		order.append((band, 10.0 * k + rng.uniform(-3, 3)))
qi = 0
for band, a in order:
	if qi >= len(quarter):
		break
	w, h = rng.choice([(8, 6), (7, 6), (8, 7)])
	try:
		place(quarter[qi], w, h, band, a, 8)
		qi += 1
	except SystemExit:
		pass
assert qi == len(quarter), 'кварталы: поставлено %d из %d' % (qi, len(quarter))

# Лотки на площади
stalls = []
for a in (200, 240, 300, 340):
	x, y = polar(7, a)
	x, y = int(x), int(y)
	cells = [[x, y], [x + 1, y]]
	assert all(at(c[0], c[1]) == SQUARE for c in cells)
	for c in cells:
		put(c[0], c[1], STALL)
	stalls.append(cells)


# ---- Проходы: всё, что нужно, достижимо от ворот ----
def reach_from(sx, sy):
	seen = {(sx, sy)}
	q = deque([(sx, sy)])
	while q:
		x, y = q.popleft()
		for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
			p = (x + dx, y + dy)
			if p not in seen and at(*p) in WALKABLE:
				seen.add(p)
				q.append(p)
	return seen


reach = reach_from(int(spawn[0]), int(spawn[1]))


def free_grass_near(x, y, rmax=12, need=1):
	best = None
	for r in range(rmax + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				p = (x + dx, y + dy)
				if max(abs(dx), abs(dy)) != r or at(*p) != GRASS or p in reserved or p not in reach:
					continue
				if all(at(p[0] + ex, p[1] + ey) in WALKABLE for ex in range(-need, need + 1) for ey in range(-need, need + 1)):
					return [p[0], p[1]]
	raise SystemExit('нет свободной травы у %s' % ((x, y),))


# Лазы: тихие места у стены изнутри по сторонам света
breaches = []
for side, a in (('north', -80), ('west', 190), ('east', 10), ('south', 125)):
	x, y = polar(R - 3, a)
	c = free_grass_near(int(x), int(y))
	breaches.append({'side': side, 'cell': c})
	for ey in range(-1, 2):
		for ex in range(-1, 2):
			reserved.add((c[0] + ex, c[1] + ey))


# Деревья — на траве, не у дверей и проходов
def tree_ok(x, y):
	if at(x, y) != GRASS or (x, y) in reserved or dist(x, y) > R - 2:
		return False
	return all(at(x + dx, y + dy) in (GRASS, FIELD, TREE) and (x + dx, y + dy) not in reserved
		for dx in (-1, 0, 1) for dy in (-1, 0, 1) if dx or dy)


trees = []
tries = 0
while len(trees) < 60 and tries < 100000:
	tries += 1
	x, y = rng.randrange(2, N - 2), rng.randrange(2, N - 2)
	if tree_ok(x, y) and not any(abs(x - t[0]) <= 2 and abs(y - t[1]) <= 2 for t in trees):
		trees.append([x, y])
		put(x, y, TREE)

# Кусты в садах у домов (art_gardens Storybook): трава, не на пути
gardens = []
for bid in sorted(placed):
	if len(gardens) >= 38:
		break
	x0, y0, w, h = placed[bid]['rect']
	for (x, y) in ((x0 - 2, y0 + h // 2), (x0 + w + 1, y0 + h // 2), (x0 + w // 2, y0 - 2)):
		if tree_ok(x, y) and [x, y] not in gardens:
			gardens.append([x, y])
			break

# После деревьев проходы не должны пропасть
reach = reach_from(int(spawn[0]), int(spawn[1]))
for bid, b in placed.items():
	x, y = b['door']
	assert (x, y) in reach, 'дверь %s недостижима' % bid
for br in breaches:
	assert tuple(br['cell']) in reach, br


def center_of(bid):
	x0, y0, w, h = placed[bid]['rect']
	return [x0 + w // 2, y0 + h // 2]


def front_of(bid, k=2):
	x, y = placed[bid]['door']
	x0, y0, w, h = placed[bid]['rect']
	dx = -1 if x == x0 else (1 if x == x0 + w - 1 else 0)
	dy = -1 if y == y0 else (1 if y == y0 + h - 1 else 0)
	return [x + dx * k, y + dy * k]


def sq_cell(a, r):
	x, y = polar(r, a)
	# Ближайшая свободная клетка площади (лотки и колодец заняты)
	for rr in range(4):
		for dy in range(-rr, rr + 1):
			for dx in range(-rr, rr + 1):
				c = [int(x) + dx, int(y) + dy]
				if at(*c) == SQUARE and tuple(c) in reach:
					return c
	raise SystemExit('площадь занята у %s' % ((a, r),))


# ---- Здания: прежние имена и типы, новые места ----
buildings = []
for b in src['buildings']:
	p = placed[b['id']]
	buildings.append({'id': b['id'], 'name': b['name'], 'kind': b['kind'], 'rect': p['rect'], 'door': p['door']})

# ---- Жители: прежние, новые рабочие места ----
work = {
	'trader': sq_cell(200, 5), 'junkman': front_of('house_7', 3), 'guard_1': guard_post, 'guard_2': sq_cell(60, 6),
	'guard_3': front_of('hall', 3), 'farmer': [f1[0] + 2, f1[1] + 3], 'potter': sq_cell(330, 6),
	'widow': free_grass_near(w2[0][0], w2[0][1] - 2), 'kid': sq_cell(20, 8),
}
npcs = []
k = 0
for n in src['npcs']:
	n = dict(n)
	if n['id'] in work:
		n['work_cell'] = work[n['id']]
	elif n['id'].startswith('art_resident_'):
		# По площади, но не у лотка торговки (200°): с ней говорят, рядом никого
		n['work_cell'] = sq_cell(-100.0 + 22.0 * k, 9 if k % 2 else 6)
		k += 1
	for c in [n.get('work_cell')]:
		assert c is None or tuple(c) in reach, n['id']
	# Ключи в прежнем порядке, реплики последними
	lines = n.pop('lines')
	n['lines'] = lines
	npcs.append(n)

# ---- Места ----
cellar, cache = center_of('ruins_n'), center_of('ruins_e')
smith = placed['smithy']['rect']
pos = {
	'notice_board': sq_cell(-60, 8), 'well_square': [wx + 0.5, wy + 0.5], 'well_south': [w2[0][0] + 0.5, w2[0][1] + 0.5],
	'altar': center_of('temple'), 'shrine': free_grass_near(*[int(v) for v in polar(R - 5, -150)]),
	'cellar': cellar, 'tower_cache': cache,
	'junk': free_grass_near(smith[0] + smith[2] + 1, smith[1] + smith[3] // 2), 'garden': [f1[0] + 1, f1[1] + 1],
}
places = []
for p in src['places']:
	p = dict(p)
	p['cell'] = pos[p['id']]
	places.append(p)

gate = dict(src['gates'][0])
gate.update({'cells': gate_cells, 'spawn': spawn, 'guard_post': guard_post})

d = {}
for key in src:
	d[key] = src[key]
d['_note'] = ('Чёрнославль — единственный город мира (id s001 из data/world/settlements.json). Радиальный план (Huzzah 2026-10-23): '
	'круглая стена радиусом wall_r клеток вокруг center, площадь в центре, улицы лучами и кольцами. Клетки по cell_m метров, '
	'x вправо, y вниз. Сделан скриптом tools/make_city_radial.py (seed %d); числа [ВРЕМЕННО].' % SEED)
d['size'] = [N, N]
d['plan'] = 'radial'
d['center'] = [C, C]
d['wall_r'] = R
d['towers'] = towers
d['gates'] = [gate]
d['breaches'] = breaches
d['roads'] = roads
d['squares'] = [square]
d['fields'] = fields
d['buildings'] = buildings
d['props'] = [{'kind': 'stall', 'cells': s} for s in stalls] + [{'kind': 'well', 'cells': w} for w in wells] + [{'kind': 'tree', 'cells': trees}]
d['places'] = places
d['npcs'] = npcs
d['art_gardens'] = gardens
d['art_direction'] = 'Radial medieval plan: round wall, central market, radial and ring streets. Storybook sprites.'
order_keys = ['_note', 'id', 'name', 'size', 'cell_m', 'plan', 'center', 'wall_r', 'wall', 'towers', 'rules', 'gates', 'breaches', 'jail',
	'roads', 'squares', 'fields', 'buildings', 'props', 'places', 'npcs', 'art_gardens', 'art_direction']
d = {k: d[k] for k in order_keys if k in d} | {k: v for k, v in d.items() if k not in order_keys}
json.dump(d, open(out_path, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
open(out_path, 'a', encoding='utf-8').write('\n')
print('ok', len(buildings), 'buildings', len(npcs), 'npcs', len(trees), 'trees', len(gardens), 'gardens', len(roads), 'roads')

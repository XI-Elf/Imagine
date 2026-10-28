# Поселения на общей карте -> data/world/settlements.json.
# Доска делится на клетки поселений CELL_M x CELL_M метров; город занимает несколько клеток, число
# клеток зависит от размера (SIZES). Места выбираются по слоям карты art/map:
#   - только чистая суша: не вода (map_water), не радиоактивные биомы 7-9, не жаркие горы (map_hot);
#   - лучше у воды (река, озеро, берег моря) и не в горах и болоте;
#   - главный город в каждой области (размер по площади чистой суши области), деревни и хутора
#     в крупных регионах, не ближе MIN_GAP_M к соседям.
# Результат детерминирован (seed). Файл можно править руками: игра читает его как есть.
# Режим single (так решил Huzzah 2026-10-22): один город на весь мир, у его ворот появляется герой.
# Радиальные поселения (Huzzah 2026-10-23): город круглый — "radius" (метры) вокруг center, круг лежит
# внутри клеток пятна (не больше radius_m размера); ворота — на окружности со стороны выбранной
# стороны пятна, точка выхода GATE_OUT_M за стеной. План мира города строит tools/make_city_radial.py.
# Запуск: python3 make_settlements.py <папка art/map> <выходной settlements.json> [seed] [single|all]
import sys, json, math, random
import numpy as np
from PIL import Image
sys.path.insert(0, __file__.rsplit('/', 1)[0])
import board_proj as bp

map_dir, out_path = sys.argv[1], sys.argv[2]
SEED = int(sys.argv[3]) if len(sys.argv) > 3 else 7
MODE = sys.argv[4] if len(sys.argv) > 4 else 'single'
SINGLE_SIZE = 'city'
SINGLE_NAME = 'Чёрнославль'   # имя единственного города закреплено (его уже знают ветки «Мир города» и др.)
W, H = bp.BOARD_W, bp.BOARD_H
CELL_M = 250.0
NCX, NCY = int(math.ceil(W / CELL_M)), int(math.ceil(H / CELL_M))

# Размеры: число клеток, имя, шаблон мира города
SIZES = {
	'hamlet':  {'name': 'хутор',         'cells': 1,  'template': 'tpl_hamlet', 'radius_m': 60.0},
	'village': {'name': 'деревня',       'cells': 2,  'template': 'tpl_village', 'radius_m': 90.0},
	'town':    {'name': 'посёлок',       'cells': 4,  'template': 'tpl_town', 'radius_m': 140.0},
	'city':    {'name': 'город',         'cells': 7,  'template': 'tpl_city', 'radius_m': 190.0},
	'capital': {'name': 'крупный город', 'cells': 12, 'template': 'tpl_capital', 'radius_m': 260.0},
}
MIN_GAP_M = {'hamlet': 1800.0, 'village': 2200.0, 'town': 3000.0, 'city': 3500.0, 'capital': 4000.0}

names = json.load(open(map_dir + '/map_names.json', encoding='utf-8'))
bio = np.asarray(Image.open(map_dir + '/map_biomes.png')).astype(np.int32)
water = np.asarray(Image.open(map_dir + '/map_water.png')).astype(np.float32) / 255.0
hot = np.asarray(Image.open(map_dir + '/map_hot.png')).astype(np.float32) / 255.0
prov = np.asarray(Image.open(map_dir + '/map_provinces.png')).astype(np.int32)
reg = np.asarray(Image.open(map_dir + '/map_regions.png')).astype(np.int32)


# Среднее и мода растра по клеткам поселений (растр покрывает всю доску W x H)
def cell_stats(img, fn):
	ny, nx = img.shape
	out = np.zeros((NCY, NCX), np.float32)
	for cy in range(NCY):
		y0, y1 = int(cy * CELL_M / H * ny), max(int((cy + 1) * CELL_M / H * ny), int(cy * CELL_M / H * ny) + 1)
		for cx in range(NCX):
			x0, x1 = int(cx * CELL_M / W * nx), max(int((cx + 1) * CELL_M / W * nx), int(cx * CELL_M / W * nx) + 1)
			out[cy, cx] = fn(img[y0:min(y1, ny), x0:min(x1, nx)])
	return out


def mode_nz(a):
	v = a[a > 0]
	return np.bincount(v).argmax() if v.size else 0


land = cell_stats(water, lambda a: (a < 0.5).mean() if a.size else 0.0)
wet = cell_stats(water, lambda a: (a >= 0.5).mean() if a.size else 0.0)
hotc = cell_stats(hot, lambda a: (a >= 0.5).mean() if a.size else 0.0)
inside = cell_stats(bio, lambda a: (a > 0).mean() if a.size else 0.0)
rad = cell_stats(bio, lambda a: (a >= 7).mean() if a.size else 0.0)
mount = cell_stats(bio, lambda a: (a == 6).mean() if a.size else 0.0)
swamp = cell_stats(bio, lambda a: (a == 5).mean() if a.size else 0.0)
pcell = cell_stats(prov, mode_nz).astype(int)
rcell = cell_stats(reg, mode_nz).astype(int)


# Клетка целиком в одном регионе (а значит, и в одной области): в окне клетки с запасом BORDER_PAD_PX
# пикселей растра на каждую сторону нет чужого номера — линия границы не проходит ни через клетку,
# ни вплотную к её краю (так решил Huzzah: город не пересекает границы областей и регионов)
BORDER_PAD_PX = 2


def pure_cells(img):
	ny, nx = img.shape
	out = np.zeros((NCY, NCX), bool)
	for cy in range(NCY):
		y0 = max(int(cy * CELL_M / H * ny) - BORDER_PAD_PX, 0); y1 = min(int(math.ceil((cy + 1) * CELL_M / H * ny)) + BORDER_PAD_PX, ny)
		for cx in range(NCX):
			x0 = max(int(cx * CELL_M / W * nx) - BORDER_PAD_PX, 0); x1 = min(int(math.ceil((cx + 1) * CELL_M / W * nx)) + BORDER_PAD_PX, nx)
			a = img[y0:y1, x0:x1]
			out[cy, cx] = a.size > 0 and a.min() == a.max() and a.min() > 0
	return out


rpure = pure_cells(reg) & pure_cells(prov)

# Центры клеток внутри гекса доски с отступом
cxs, cys = np.meshgrid((np.arange(NCX) + 0.5) * CELL_M, (np.arange(NCY) + 0.5) * CELL_M)
in_board = bp.hex_norm(cxs - bp.CX, cys - bp.CY) <= bp.APO - 2 * CELL_M

# Клетка годится под застройку: суша почти целиком, без радиации и жары
buildable = in_board & (inside > 0.99) & (land > 0.97) & (rad < 0.02) & (hotc < 0.02) & (pcell > 0) & rpure

# Расстояние до воды в клетках (обход по соседям; вода — клетка, где воды хотя бы 15 %)
dist_w = np.full((NCY, NCX), 99, np.int32)
dist_w[wet > 0.15] = 0
for step in range(1, 12):
	prev = dist_w == step - 1
	grow = np.zeros_like(prev)
	grow[1:, :] |= prev[:-1, :]; grow[:-1, :] |= prev[1:, :]
	grow[:, 1:] |= prev[:, :-1]; grow[:, :-1] |= prev[:, 1:]
	dist_w[grow & (dist_w == 99)] = step

# Оценка места: у воды (1-2 клетки), не в горах и болоте
score = np.where(buildable, 1.0, -1e9)
score += np.where(dist_w == 1, 1.2, np.where(dist_w == 2, 0.9, np.where(dist_w <= 4, 0.4, 0.0)))
score -= 1.2 * mount + 0.8 * swamp
# Подальше от радиации и жаркой зоны (соседи клетки)
pad = np.pad(np.maximum(rad, hotc), 2)
near_bad = np.zeros_like(rad)
for dy in range(5):
	for dx in range(5):
		near_bad = np.maximum(near_bad, pad[dy:dy + NCY, dx:dx + NCX])
score -= 1.5 * near_bad

rng = random.Random(SEED)


# Пятно из n клеток от центра: соседние годные клетки по возрастанию расстояния (с лёгким шумом)
def footprint(cx, cy, n):
	cells = [(cx, cy)]
	front = set()
	while len(cells) < n:
		for (x, y) in cells:
			for (dx, dy) in ((1, 0), (-1, 0), (0, 1), (0, -1)):
				q = (x + dx, y + dy)
				if 0 <= q[0] < NCX and 0 <= q[1] < NCY and q not in cells and buildable[q[1], q[0]] \
						and rcell[q[1], q[0]] == rcell[cy, cx]:
					front.add(q)
		front -= set(cells)
		if not front:
			return None
		best = min(front, key=lambda q: math.hypot(q[0] - cx, q[1] - cy) + rng.random() * 0.6)
		cells.append(best)
	return cells


taken = np.zeros((NCY, NCX), bool)
placed = []


def far_enough(p, size):
	for s in placed:
		gap = max(MIN_GAP_M[size], MIN_GAP_M[s['size']])
		if math.hypot(p[0] - s['center'][0], p[1] - s['center'][1]) < gap:
			return False
	return True


def try_place(mask, size):
	n = SIZES[size]['cells']
	cand = np.argwhere(mask & buildable & ~taken)
	if cand.size == 0:
		return None
	order = sorted(cand.tolist(), key=lambda yx: -score[yx[0], yx[1]])
	for cy, cx in order[:400]:
		c = ((cx + 0.5) * CELL_M, (cy + 0.5) * CELL_M)
		if not far_enough(c, size):
			continue
		fp = footprint(cx, cy, n)
		if fp is None or any(taken[y, x] for (x, y) in fp):
			continue
		return fp
	return None


# ---- Имена ----
ROOTS = ['Бел', 'Вер', 'Глин', 'Дуб', 'Жар', 'Звен', 'Кам', 'Клён', 'Крут', 'Лип', 'Лис', 'Мох', 'Мост',
	'Озер', 'Ольх', 'Перун', 'Под', 'Рыб', 'Рябин', 'Сер', 'Сосн', 'Студ', 'Тёмн', 'Тихо', 'Туман', 'Ус',
	'Чёрн', 'Яр', 'Бор', 'Брод', 'Вол', 'Гор', 'Дол', 'Зар', 'Ив', 'Кедр', 'Кос', 'Лес', 'Луг', 'Мед',
	'Нов', 'Охот', 'Пес', 'Ржав', 'Сол', 'Стар', 'Сух', 'Тур', 'Хмел', 'Ясн', 'Вран', 'Смол', 'Гуд',
	'Берез', 'Вишн', 'Голуб', 'Дым', 'Ёлк', 'Журав', 'Знам', 'Калин', 'Ковыл', 'Лён', 'Малин', 'Медв',
	'Орл', 'Полын', 'Ракит', 'Сокол', 'Терн', 'Ухв', 'Хвощ', 'Черёмух', 'Шипш', 'Щеглов', 'Ягод', 'Ветл',
	'Глух', 'Дрозд', 'Камыш', 'Мшан', 'Ореш']
ENDS = {
	'hamlet': ['ов хутор', 'ин хутор', 'ова заимка', 'ина заимка', 'ов двор'],
	'village': ['ово', 'ино', 'ки', 'цы', 'овка', 'ище', 'ичи', 'ево'],
	'town': ['ец', 'овск', 'ин', 'ичи', 'ово', 'ск'],
	'city': ['град', 'город', 'омир', 'ославль', 'ск'],
	'capital': ['град', 'ополь', 'ославль', 'город'],
}
used_names = set()
used_roots = set()


def make_name(size):
	for _ in range(500):
		r = rng.choice(ROOTS)
		e = rng.choice(ENDS[size])
		# Корень на гласную: «Тихо» + «овск» -> «Тиховск»
		n = r + (e[1:] if r[-1] in 'аеёиоуыэюя' and e[0] in 'аеёиоуыэюя' else e)
		# Один корень — одно поселение, чтобы имена не путались
		if r not in used_roots:
			used_roots.add(r)
			used_names.add(n)
			return n
	n = rng.choice(ROOTS) + rng.choice(ENDS[size]) + ' ' + str(len(placed) + 1)
	used_names.add(n)
	return n


# Ворота: середина свободной стороны пятна (сосед — суша вне города), лучше к югу; точка
# GATE_OUT_M за краем пятна. Сюда игрок выходит из города
GATE_OUT_M = 40.0


def gate_of(fp, center):
	cells = set(fp)
	best, best_s = None, -1e9
	for (x, y) in fp:
		for (dx, dy) in ((0, 1), (1, 0), (-1, 0), (0, -1)):
			q = (x + dx, y + dy)
			if q in cells or not (0 <= q[0] < NCX and 0 <= q[1] < NCY):
				continue
			if land[q[1], q[0]] < 0.97 or not in_board[q[1], q[0]]:
				continue
			p = ((x + 0.5 + dx * 0.5) * CELL_M + dx * GATE_OUT_M, (y + 0.5 + dy * 0.5) * CELL_M + dy * GATE_OUT_M)
			s = (2.0 if dy == 1 else 0.0) - math.hypot(p[0] - center[0], p[1] - center[1]) / CELL_M + (1.0 if buildable[q[1], q[0]] else 0.0)
			# Ворота и площадка перед ними — в том же регионе, что и город
			if rpure[q[1], q[0]] and rcell[q[1], q[0]] == rcell[fp[0][1], fp[0][0]]:
				s += 3.0
			if s > best_s:
				best, best_s = p, s
	return best


# Точка доски — чистая суша (вода, радиация и жаркие горы — нет)
def clean_at(x, y):
	if not (0 <= x < W and 0 <= y < H) or bp.hex_norm(x - bp.CX, y - bp.CY) > bp.APO - 100:
		return False
	wy, wx = int(y / H * water.shape[0]), int(x / W * water.shape[1])
	by, bx = int(y / H * bio.shape[0]), int(x / W * bio.shape[1])
	return water[wy, wx] < 0.5 and 0 < bio[by, bx] < 7 and hot[by, bx] < 0.5


# Готовой дороги от ворот нет (Huzzah 2026-10-28): дороги протаптываются в игре (world/trails.gd)


# Эмблемы на щитке: поле, фигура, цвет фигуры
EMBLEMS = [
	{'field': '#26262c', 'charge': 'tower', 'tint': '#e2b84c'},
	{'field': '#7a1f1f', 'charge': 'crown', 'tint': '#f0d488'},
	{'field': '#1f4a2c', 'charge': 'tree', 'tint': '#e8e0c0'},
	{'field': '#1f3560', 'charge': 'key', 'tint': '#e2c060'},
]


def add(fp, size):
	n = len(placed) + 1
	xs = [(x + 0.5) * CELL_M for x, y in fp]; ys = [(y + 0.5) * CELL_M for x, y in fp]
	center = (round(sum(xs) / len(xs), 1), round(sum(ys) / len(ys), 1))
	cx, cy = fp[0]
	for (x, y) in fp:
		taken[y, x] = True
	sid = 's%03d' % n
	g = gate_of(fp, center) or (center[0], center[1] + CELL_M)
	# Круглая стена: наибольший круг из центра внутри клеток пятна, но не больше radius_m размера
	cells = set(fp)
	radius = SIZES[size]['radius_m']
	while radius > 20.0 and not all((int((center[0] + math.cos(a) * radius * t) // CELL_M), int((center[1] + math.sin(a) * radius * t) // CELL_M)) in cells
			for a in [k * math.pi / 90 for k in range(180)] for t in (0.5, 1.0)):
		radius -= 10.0
	ga = math.atan2(g[1] - center[1], g[0] - center[0])
	g = (center[0] + math.cos(ga) * (radius + GATE_OUT_M), center[1] + math.sin(ga) * (radius + GATE_OUT_M))
	placed.append({
		'id': sid, 'name': SINGLE_NAME if MODE == 'single' else make_name(size), 'size': size,
		'cells': [[int(x), int(y)] for (x, y) in fp],
		'center': [center[0], center[1]], 'radius': radius, 'gate': [round(g[0], 1), round(g[1], 1)],
		'province': int(pcell[cy, cx]), 'region': int(rcell[cy, cx]),
		'city_id': sid, 'template': SIZES[size]['template'],
		'walled': size in ('town', 'city', 'capital'),
		'emblem': EMBLEMS[(n - 1) % len(EMBLEMS)],
	})


# 1) Главный город области: размер по чистой суше области
prov_ids = sorted(int(k) for k in names['provinces'])
area = {p: int((buildable & (pcell == p)).sum()) for p in prov_ids}
rank = sorted(prov_ids, key=lambda p: -area[p])
if MODE == 'single':
	# Один город: лучшее место в области с самой большой чистой сушей
	rank = rank[:1]
for i, p in enumerate(rank):
	a = area[p]
	if a < 8:
		continue
	size = SINGLE_SIZE if MODE == 'single' else 'capital' if i < 4 else 'city' if i < 12 else 'town' if a >= 60 else 'village'
	fp = None
	for s in [size] + [k for k in ['city', 'town', 'village', 'hamlet'] if SIZES[k]['cells'] < SIZES[size]['cells']]:
		fp = try_place(pcell == p, s)
		if fp:
			add(fp, s)
			break

# 2) Посёлки, деревни и хутора в регионах: чем больше чистой суши, тем крупнее
reg_ids = sorted(int(k) for k in names['regions']) if MODE != 'single' else []
rarea = {r: int((buildable & (rcell == r)).sum()) for r in reg_ids}
for r in sorted(reg_ids, key=lambda r: -rarea[r]):
	a = rarea[r]
	if a < 6:
		continue
	if any(s['region'] == r for s in placed):
		# В крупном регионе бывает второе поселение
		if a < 120:
			continue
	size = 'town' if a >= 150 else 'village' if a >= 40 else 'hamlet'
	for s in [size, 'village', 'hamlet']:
		if SIZES[s]['cells'] > SIZES[size]['cells']:
			continue
		fp = try_place(rcell == r, s)
		if fp:
			add(fp, s)
			break

out = {
	'_note': 'Поселения на общей карте. Создано tools/make_settlements.py (seed %d); можно править руками. '
		'Координаты center и gate — метры доски; готовой дороги нет — дороги протаптываются в игре (world/trails.gd); cells — клетки [cx, cy] размером cell_m, клетка cx покрывает X от cx*cell_m. '
		'gate — точка выхода из города на общую карту. city_id — ключ мира города (data/cities/<city_id>.json, '
		'нет файла — data/cities/<template>.json).' % SEED,
	'cell_m': CELL_M,
	# Проникновение через стену [ВРЕМЕННО]: шанс = base + per_agi*(Ловк-5) + per_per*(Восп-5) + per_luck*(Удача-5)
	# + night (ночью) - per_kg_over*(кг сверх free_kg); ×hurt_mult при травме рук/ног, ×low_mult при здоровье
	# или силах ниже трети; верхом нельзя. Неудача: «заметили» с шансом caught_day/caught_night
	# (минус per_agi_caught за Ловкость сверх 5), иначе стража настороже cooldown_h игровых часов.
	# Сорвался со стены: fall_chance — травма fall_condition. Попытка тратит stamina_cost сил.
	'sneak': {'base': 0.3, 'per_agi': 0.05, 'per_per': 0.02, 'per_luck': 0.01, 'night': 0.2,
		'free_kg': 15.0, 'per_kg_over': 0.01, 'hurt_mult': 0.3, 'low_mult': 0.5,
		'hurt_conditions': ['luxation_arm', 'broken_arm', 'broken_leg', 'blindness'],
		'min': 0.05, 'max': 0.9, 'caught_day': 0.5, 'caught_night': 0.25, 'per_agi_caught': 0.03,
		'cooldown_h': 1.0, 'fall_chance': 0.1, 'fall_condition': 'luxation_arm', 'stamina_cost': 30.0},
	'sizes': SIZES,
	'settlements': placed,
}
json.dump(out, open(out_path, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
cnt = {}
for s in placed:
	cnt[s['size']] = cnt.get(s['size'], 0) + 1
print('settlements', len(placed), cnt)

# Медальоны поселений для общей карты (Huzzah 2026-10-23, референс Day R): круглая картинка поселения в рамке,
# сверху знамя с гербом (знамя рисует world/settlements.gd кодом). Картинка — по уровню развития:
#   0 стоянка (палатка у костра), 1 острог, 2 слобода, 3 посад, 4 город, 5 большой город.
# Собирается из спрайтов art/storybook (комикс-набор) и простых фигур, тонируется в сепию, как на референсе.
# Генератора изображений нет: это коллаж из готовых спрайтов, не рисунок художника.
# Запуск: python3 make_settlement_medallions.py <папка art/storybook> <папка вывода>
import math, os, random, sys
from PIL import Image, ImageDraw, ImageFilter, ImageOps, ImageChops

ART, OUT = sys.argv[1], sys.argv[2]
os.makedirs(OUT, exist_ok=True)
N = 640                    # сторона картинки
R = 300                    # радиус круга картинки (рамка — до края)
C = N // 2
INK = (52, 36, 24, 255)
_cache = {}


def sprite(name, h):
	if name not in _cache:
		_cache[name] = Image.open(os.path.join(ART, name + '.png')).convert('RGBA')
	im = _cache[name]
	w = max(1, round(im.width * h / im.height))
	return im.resize((w, h), Image.LANCZOS)


def put(img, name, cx, foot, h, flip=False):
	s = sprite(name, h)
	if flip:
		s = ImageOps.mirror(s)
	img.alpha_composite(s, (round(cx - s.width / 2), round(foot - s.height)))


def background(img, ground_y):
	d = ImageDraw.Draw(img)
	for y in range(N):
		t = y / N
		if y < ground_y:
			col = (round(236 - 30 * t), round(222 - 34 * t), round(190 - 40 * t), 255)
		else:
			k = (y - ground_y) / (N - ground_y)
			col = (round(170 - 40 * k), round(140 - 38 * k), round(98 - 30 * k), 255)
		d.line([(0, y), (N, y)], fill=col)
	# Дальние холмы
	pts = [(0, ground_y)]
	for x in range(0, N + 1, 20):
		pts.append((x, ground_y - 22 - 18 * math.sin(x / 70.0) - 10 * math.sin(x / 23.0)))
	pts.append((N, ground_y))
	d.polygon(pts, fill=(176, 152, 112, 255), outline=None)


def tent(img, cx, foot, w):
	d = ImageDraw.Draw(img)
	h = w * 0.72
	top = (cx, foot - h)
	d.polygon([(cx - w / 2, foot), top, (cx + w / 2, foot)], fill=(214, 196, 158, 255), outline=INK)
	d.polygon([(cx - w * 0.14, foot), (cx, foot - h * 0.62), (cx + w * 0.14, foot)], fill=(70, 52, 36, 255), outline=INK)
	d.line([top, (cx, foot - h - w * 0.14)], fill=INK, width=4)
	for sx in (-1, 1):
		d.line([(cx + sx * w * 0.5, foot), (cx + sx * w * 0.62, foot + 6)], fill=INK, width=3)
		d.line([(cx + sx * w * 0.18, foot - h * 0.75), (cx + sx * w * 0.7, foot + 4)], fill=(90, 70, 50, 255), width=2)
	for k in range(1, 4):
		y = foot - h * k / 4
		x = (h * (1 - k / 4)) / h * w / 2
		d.line([(cx - x + 6, y), (cx - x * 0.35, y + 4)], fill=(150, 128, 92, 255), width=2)


def campfire(img, cx, foot, s):
	d = ImageDraw.Draw(img)
	for a in (-25, 25, 0):
		r = math.radians(a)
		dx, dy = math.sin(r) * s, math.cos(r) * s * 0.25
		d.line([(cx - dx, foot + dy), (cx + dx, foot - dy)], fill=(96, 64, 40, 255), width=max(3, round(s * 0.18)))
	for k in range(7):
		a = math.radians(k * 360 / 7)
		d.ellipse([cx + math.cos(a) * s * 0.75 - s * 0.14, foot + math.sin(a) * s * 0.22 - s * 0.1,
			cx + math.cos(a) * s * 0.75 + s * 0.14, foot + math.sin(a) * s * 0.22 + s * 0.1], fill=(120, 112, 100, 255), outline=INK)
	d.polygon([(cx - s * 0.42, foot - 2), (cx - s * 0.2, foot - s * 0.9), (cx, foot - s * 0.5), (cx + s * 0.12, foot - s * 1.25),
		(cx + s * 0.3, foot - s * 0.6), (cx + s * 0.44, foot - 2)], fill=(232, 150, 52, 255), outline=INK)
	d.polygon([(cx - s * 0.2, foot - 2), (cx - s * 0.05, foot - s * 0.55), (cx + s * 0.1, foot - s * 0.75), (cx + s * 0.22, foot - 2)], fill=(250, 214, 110, 255))
	# Дым
	for k in range(4):
		r = s * (0.16 + k * 0.07)
		x, y = cx + s * 0.1 + k * s * 0.18, foot - s * 1.35 - k * s * 0.42
		d.ellipse([x - r, y - r, x + r, y + r], fill=(150, 140, 128, 90 - k * 15))


def palisade(img, y, gate_w=70, h=78):
	d = ImageDraw.Draw(img)
	x = 0
	rnd = random.Random(7)
	while x < N:
		w = rnd.randint(15, 19)
		top = y - h - rnd.randint(0, 10)
		if abs(x + w / 2 - C) > gate_w / 2:
			d.polygon([(x, y), (x, top + 10), (x + w / 2, top), (x + w, top + 10), (x + w, y)], fill=(122, 86, 52, 255), outline=INK)
			d.line([(x + w * 0.35, top + 14), (x + w * 0.35, y - 4)], fill=(150, 110, 70, 255), width=2)
		x += w
	d.line([(0, y - h * 0.62), (C - gate_w / 2, y - h * 0.62)], fill=(84, 58, 36, 255), width=5)
	d.line([(C + gate_w / 2, y - h * 0.62), (N, y - h * 0.62)], fill=(84, 58, 36, 255), width=5)
	# Ворота: две створки из досок
	gx0, gx1 = C - gate_w / 2, C + gate_w / 2
	d.rectangle([gx0, y - h * 0.95, gx1, y], fill=(98, 66, 40, 255), outline=INK, width=2)
	d.line([(C, y - h * 0.95), (C, y)], fill=INK, width=2)
	for k in range(1, 4):
		d.line([(gx0, y - h * 0.95 * k / 4), (gx1, y - h * 0.95 * k / 4)], fill=(70, 48, 30, 255), width=2)


def stone_wall(img, y, h=96, towers=(110, 530), gate_w=86):
	mas = Image.open(os.path.join(ART, 'masonry.png')).convert('RGBA').resize((170, 170), Image.LANCZOS)
	wall = Image.new('RGBA', (N, N), (0, 0, 0, 0))
	for tx in range(0, N, 170):
		for ty in range(0, N, 170):
			wall.alpha_composite(mas, (tx, ty))
	mask = Image.new('L', (N, N), 0)
	md = ImageDraw.Draw(mask)
	md.rectangle([0, y - h, N, N], fill=255)
	for x in range(0, N, 44):
		md.rectangle([x, y - h - 18, x + 24, y - h], fill=255)
	for tx in towers:
		md.rectangle([tx - 44, y - h - 70, tx + 44, N], fill=255)
		for k in range(3):
			md.rectangle([tx - 44 + k * 34, y - h - 92, tx - 44 + k * 34 + 20, y - h - 70], fill=255)
	img.paste(wall, (0, 0), mask)
	edge = mask.filter(ImageFilter.FIND_EDGES)
	ink = Image.new('RGBA', (N, N), INK)
	img.paste(ink, (0, 0), edge.point(lambda v: 255 if v > 40 else 0))
	d = ImageDraw.Draw(img)
	for tx in towers:
		d.rectangle([tx - 8, y - h - 48, tx + 8, y - h - 22], fill=(40, 30, 22, 255))
	# Ворота аркой
	gx0, gx1 = C - gate_w / 2, C + gate_w / 2
	d.rectangle([gx0, y - h * 0.68, gx1, N], fill=(58, 40, 26, 255), outline=INK, width=3)
	d.pieslice([gx0, y - h * 0.68 - gate_w / 2, gx1, y - h * 0.68 + gate_w / 2], 180, 360, fill=(58, 40, 26, 255), outline=INK, width=3)
	for k in range(1, 4):
		x = gx0 + gate_w * k / 4
		d.line([(x, y - h * 0.9), (x, N)], fill=(90, 66, 44, 255), width=3)


def finish(img):
	# Сепия, как на референсе: цвет приглушён, остаётся теплый коричневый
	rgb = img.convert('RGB')
	g = ImageOps.grayscale(rgb)
	sep = ImageOps.colorize(g, (40, 26, 16), (246, 230, 196), mid=(160, 120, 78))
	mix = Image.blend(sep, rgb, 0.28)
	# Виньетка
	vig = Image.new('L', (N, N), 0)
	vd = ImageDraw.Draw(vig)
	for k in range(40):
		r = R - k * 3
		vd.ellipse([C - r, C - r, C + r, C + r], fill=round(255 * (1 - k / 40) * 0.55))
	vig = vig.filter(ImageFilter.GaussianBlur(18))
	dark = Image.new('RGB', (N, N), (36, 22, 12))
	mix = Image.composite(dark, mix, vig.point(lambda v: v))
	inner = Image.new('L', (N, N), 0)
	ImageDraw.Draw(inner).ellipse([C - R, C - R, C + R, C + R], fill=255)
	out = Image.new('RGBA', (N, N), (0, 0, 0, 0))
	out.paste(mix, (0, 0), inner)
	# Рамка: светлое кольцо с тёмной обводкой
	d = ImageDraw.Draw(out)
	d.ellipse([C - R - 14, C - R - 14, C + R + 14, C + R + 14], outline=(40, 28, 18, 255), width=4)
	d.ellipse([C - R - 11, C - R - 11, C + R + 11, C + R + 11], outline=(228, 214, 190, 255), width=10)
	d.ellipse([C - R - 1, C - R - 1, C + R + 1, C + R + 1], outline=(60, 42, 28, 255), width=3)
	return out


def level(n):
	img = Image.new('RGBA', (N, N), (0, 0, 0, 0))
	gy = 380 if n == 0 else 300
	background(img, gy)
	if n == 0:
		put(img, 'tree_oak', 470, 400, 250)
		put(img, 'tree_light', 140, 370, 190, flip=True)
		put(img, 'rock', 520, 470, 80)
		tent(img, 260, 470, 240)
		campfire(img, 410, 505, 90)
		put(img, 'traveler', 500, 525, 130)
		return finish(img)
	# Задний ряд
	if n >= 5:
		put(img, 'temple', 200, 300, 230)
	if n >= 4:
		put(img, 'hall', 420 if n >= 5 else 330, 300, 250)
	if n >= 3:
		put(img, 'healer', 120 if n >= 5 else 160, 345, 150)
		put(img, 'house', 540, 340, 140, flip=True)
	put(img, 'tree_oak', 560 if n < 3 else 80, 330, 200)
	# Средний ряд
	if n >= 2:
		put(img, 'smithy', 170, 420, 170)
		put(img, 'stall', 470, 420, 120)
	put(img, 'inn', 340 if n < 2 else 320, 430 if n < 3 else 440, 210)
	if n >= 3:
		put(img, 'house', 490, 470, 150)
		put(img, 'house', 110, 470, 140, flip=True)
	if n == 1:
		put(img, 'house', 500, 470, 120, flip=True)    # лачуга героя
		put(img, 'tree_light', 140, 450, 170)
	if n == 2:
		put(img, 'house', 510, 480, 130, flip=True)
		put(img, 'well', 90, 480, 90)
	# Стена
	if n >= 4:
		stone_wall(img, 610, h=78, towers=(120, 520))
	else:
		palisade(img, 560 + (0 if n >= 3 else 10), h=78 if n >= 2 else 64)
	return finish(img)


for n, name in enumerate(['m0_camp', 'm1_ostrog', 'm2_sloboda', 'm3_posad', 'm4_gorod', 'm5_bolshoy_gorod']):
	level(n).save(os.path.join(OUT, name + '.png'))
	print('ok', name)

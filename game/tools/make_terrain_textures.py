# Кадры terrain (исходные кадры, 1168 x 784, вид сверху) -> бесшовные текстуры биомов для шейдера карты.
# Из каждого кадра берётся квадрат, края сводятся плавным переходом (лево с правым, верх с низом),
# крупные перепады яркости гасятся, чтобы при повторе не было пятен. Результат 512 x 512 RGB:
# art/terrain/t00_water.png ... t11_rad_swamp.png и t12_glow.png — маски свечения радиоактивных биомов
# (R лес: фиолетовые и бирюзовые грибы, G пустошь: жёлтый налёт, B болото: красные грибы).
# Номера слоёв те же, что в map_shaders.gd (TEX_*). Жаркие горы (t08) — горы, перекрашенные в охру.
# Запуск: python3 make_terrain_textures.py <папка кадров> <папка art/terrain>
import sys, os
import numpy as np
from PIL import Image, ImageFilter

src_dir, out_dir = sys.argv[1:3]
OUT = 512


def load(name):
	for f in os.listdir(src_dir):
		if f.startswith(name):
			return np.asarray(Image.open(os.path.join(src_dir, f)).convert('RGB')).astype(np.float32)
	raise SystemExit('нет кадра ' + name)


# Квадрат (x, y, сторона T + o) -> бесшовный тайл T x T: полоса o за правым/нижним краем
# переходит в начало тайла
def seamless(img, x, y, t, o):
	c = img[y:y + t + o, x:x + t + o].copy()
	w = np.linspace(0.0, 1.0, o)[None, :, None]
	w = w * w * (3 - 2 * w)
	h = c[:, :t].copy()
	h[:, :o] = c[:, t:t + o] * (1 - w) + c[:, :o] * w
	v = h[:t].copy()
	wv = np.transpose(w, (1, 0, 2))
	v[:o] = h[t:t + o] * (1 - wv) + h[:o] * wv
	return v


# Гасит крупные перепады яркости (пятна размером с треть тайла), сохраняя мелкий рисунок
def flatten(t, k=0.6):
	im = Image.fromarray(np.clip(t, 0, 255).astype(np.uint8))
	n = t.shape[0]
	big = np.tile(np.asarray(im), (3, 3, 1))
	blur = np.asarray(Image.fromarray(big).filter(ImageFilter.GaussianBlur(n / 6))).astype(np.float32)[n:2 * n, n:2 * n]
	mean = t.reshape(-1, 3).mean(0)
	return np.clip(t * ((mean + 1) / (blur + 1)) ** k, 0, 255)


def save(t, name):
	im = Image.fromarray(np.clip(t, 0, 255).astype(np.uint8)).resize((OUT, OUT), Image.LANCZOS)
	im.save(os.path.join(out_dir, name))
	return np.asarray(im).astype(np.float32)


def hsv(a):
	a = a / 255.0
	mx = a.max(-1); mn = a.min(-1); d = np.maximum(mx - mn, 1e-6)
	r, g, b = a[..., 0], a[..., 1], a[..., 2]
	h = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) * 60
	return h, (mx - mn) / np.maximum(mx, 1e-6), mx


# Квадраты в кадрах выбраны по месту: в «Побережье» песок слева от линии прибоя, вода справа
SPEC = [
	('t00_water.png', '06_', 900, 250, 236, 32),
	('t01_coast.png', '06_', 200, 150, 268, 32),
	('t02_forest.png', '03_', 200, 0, 680, 104),
	('t03_field1.png', '01_', 200, 0, 680, 104),
	('t04_field2.png', '02_', 200, 0, 680, 104),
	('t05_wasteland.png', '04_', 200, 0, 680, 104),
	('t06_swamp.png', '05_', 200, 0, 680, 104),
	('t07_mountains.png', '07_', 200, 0, 680, 104),
	('t09_rad_forest.png', '08_', 200, 0, 680, 104),
	('t10_rad_wasteland.png', '09_', 200, 0, 680, 104),
	('t11_rad_swamp.png', '10_', 200, 0, 680, 104),
]
tiles = {}
for name, frame, x, y, t, o in SPEC:
	img = load(frame)
	tl = seamless(img, x, y, t, o)
	tiles[name] = save(flatten(tl, 0.35 if name.startswith('t00') else 0.6), name)
	print(name, 'из', frame, 'квадрат', x, y, t + o)

# Жаркие горы: тот же камень, перекрашенный по яркости в выжженную охру и ржавчину
m = tiles['t07_mountains.png']
lum = (m @ np.array([0.299, 0.587, 0.114], np.float32))[..., None] / 255.0
dark = np.array([70, 26, 10], np.float32); mid = np.array([196, 96, 38], np.float32); light = np.array([246, 196, 128], np.float32)
hot = np.where(lum < 0.5, dark + (mid - dark) * (lum / 0.5), mid + (light - mid) * ((lum - 0.5) / 0.5))
save(hot * 0.8 + m * 0.2, 't08_hot_mountains.png')

# Маски свечения (0..255) для радиоактивных биомов: яркие насыщенные пятна своего цвета
glow = np.zeros((OUT, OUT, 3), np.float32)
h, s, v = hsv(tiles['t09_rad_forest.png'])
glow[..., 0] = ((s > 0.35) & (v > 0.40) & (((h > 240) & (h < 320)) | ((h > 150) & (h < 200)))).astype(np.float32)
h, s, v = hsv(tiles['t10_rad_wasteland.png'])
glow[..., 1] = ((s > 0.45) & (v > 0.45) & (h > 40) & (h < 70)).astype(np.float32)
h, s, v = hsv(tiles['t11_rad_swamp.png'])
glow[..., 2] = ((s > 0.45) & (v > 0.35) & ((h < 15) | (h > 335))).astype(np.float32)
g = Image.fromarray((glow * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2.0))
g = np.clip(np.asarray(g).astype(np.float32) * 1.6, 0, 255)
Image.fromarray(g.astype(np.uint8)).save(os.path.join(out_dir, 't12_glow.png'))
print('glow share', (g > 64).mean((0, 1)))

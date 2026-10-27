# Высоты для объёма гор (Huzzah 2026-10-24: «должен чувствоваться объём от того, что я поднимаюсь на гору»).
# Своей карты высот у мира нет, поэтому высота выводится из биома гор (6): предгорья плавно поднимаются к краю гор,
# внутри — массив с гребнями (шум). Результат: art/map/map_height.png (L8, того же размера, что map_biomes.png),
# 0 — низина, 255 — game.gd HEIGHT_MAX_M (900 м). Шейдер карты строит по нему светотень, cast.gd — высоту героя.
# Запуск: python3 tools/make_height.py  (из папки game)
import numpy as np
from PIL import Image, ImageFilter

b = np.array(Image.open('art/map/map_biomes.png'))
mask = (b == 6).astype(np.float32)
H, W = mask.shape


def blur(a, r):
	im = Image.fromarray((a * 255).astype(np.uint8))
	return np.array(im.filter(ImageFilter.GaussianBlur(r))).astype(np.float32) / 255.0


def noise(cell, seed):
	rng = np.random.default_rng(seed)
	g = rng.random((H // cell + 2, W // cell + 2)).astype(np.float32)
	im = Image.fromarray((g * 255).astype(np.uint8)).resize((W + cell * 2, H + cell * 2), Image.BICUBIC)
	return np.array(im)[:H, :W].astype(np.float32) / 255.0


hb = blur(mask, 4) * 0.25 + blur(mask, 14) * 0.4 + blur(mask, 36) * 0.35
base = np.clip((hb - 0.05) / 0.8, 0.0, 1.0) ** 1.6
ridge = np.zeros_like(base)
for cell, w, seed in ((48, 0.5, 1), (20, 0.3, 2), (8, 0.2, 3)):
	n = noise(cell, seed)
	ridge += w * (1.0 - np.abs(2.0 * n - 1.0))
h = base * (0.45 + 0.8 * ridge)
h = np.clip(h / max(h.max(), 1e-6), 0.0, 1.0)
# Вода — на нуле
w = np.array(Image.open('art/map/map_water.png').resize((W, H), Image.BILINEAR)).astype(np.float32) / 255.0
h *= np.clip(1.0 - w * 2.0, 0.0, 1.0)
Image.fromarray((h * 255).astype(np.uint8), 'L').save('art/map/map_height.png', optimize=True)
print('map_height.png', W, H, 'mountain mean', float(h[mask > 0].mean()), 'max', float(h.max()))

# Карта світу (малюнок + шари біомів, областей і регіонів) -> растри дошки-гекса гри й суходіл для моделі атмосфери.
# Шестикутник малюнка неправильний, тому він переноситься на правильний гекс дошки за шістьма
# трикутниками «центр — сторона» (кусково-афінно): вершини малюнка точно лягають на вершини дошки.
# Вершини шукаються за шаром біомів (0 = за краєм). Малюнок може бути іншого розміру: він масштабується
# на полотно шарів.
# Вода (озера й річки) береться з малюнка: art/map/map_water.png, див. нижче.
# Спекотні гори (помаранчеві на малюнку, +40 °C): art/map/map_hot.png, див. нижче.
# Запуск: python3 make_new_map.py <малюнок.png> <biomes_id_16bit.png> <provinces_id_16bit.png>
#         <regions_id_16bit.png> <map_metadata.json> <тека art/map>
import sys, json, math
import numpy as np
from PIL import Image
sys.path.insert(0, __file__.rsplit('/', 1)[0])
import board_proj as bp

pic_path, bio_path, prov_path, reg_path, meta_path, out_dir = sys.argv[1:7]
meta = json.load(open(meta_path, encoding='utf-8-sig'))
NX, NY = 2368, 2048                       # растр дошки, клітинка 17,58 м
W, H = bp.BOARD_W, bp.BOARD_H
R = bp.APO / bp.C30                       # радіус описаного кола дошки
C = np.array([bp.CX, bp.CY])
bio_src = np.asarray(Image.open(bio_path)).astype(np.int32)
SH, SW = bio_src.shape
ins = bio_src > 0
ys, xs = np.nonzero(ins)
top, bot, xl, xr = ys.min(), ys.max(), xs.min(), xs.max()
row_t = np.nonzero(ins[top])[0]; row_b = np.nonzero(ins[bot])[0]
# Вершини малюнка: верх-ліво, верх-право, право, низ-право, низ-ліво, ліво (центри пікселів краю)
iv = np.array([[row_t.min(), top], [row_t.max() + 1, top], [xr + 1, np.nonzero(ins[:, xr])[0].mean() + 0.5],
	[row_b.max() + 1, bot + 1], [row_b.min(), bot + 1], [xl, np.nonzero(ins[:, xl])[0].mean() + 0.5]], float)
print('hex vertices', iv.tolist())
bv = np.array([C + R * np.array([math.cos(a), math.sin(a)]) for a in np.radians([240, 300, 0, 60, 120, 180])])
ic = iv.mean(0)


def tri_affine(src, dst):
	A = np.hstack([src, np.ones((3, 1))])
	return np.linalg.solve(A, dst)


mats = [tri_affine(np.array([C, bv[k], bv[(k + 1) % 6]]), np.array([ic, iv[k], iv[(k + 1) % 6]])) for k in range(6)]


# Для растра дошки nx x ny: точки малюнка (IX, IY) у центрах клітинок і маска «усередині гекса»
def board_to_pic(nx, ny):
	px, py = np.meshgrid((np.arange(nx) + 0.5) * W / nx, (np.arange(ny) + 0.5) * H / ny)
	ang = np.degrees(np.arctan2(py - C[1], px - C[0])) % 360
	k = (((ang - 240) % 360) // 60).astype(int)
	ones = np.ones_like(px)
	ix = np.zeros_like(px); iy = np.zeros_like(px)
	for s in range(6):
		m = k == s
		v = np.stack([px[m], py[m], ones[m]], 1) @ mats[s]
		ix[m] = v[:, 0]; iy[m] = v[:, 1]
	return ix, iy, bp.hex_norm(px - C[0], py - C[1]) <= bp.APO


IX, IY, inside = board_to_pic(NX, NY)

pic_img = Image.open(pic_path).convert('RGB')
if pic_img.size != (SW, SH):
	pic_img = pic_img.resize((SW, SH), Image.LANCZOS)
pic = np.asarray(pic_img).astype(np.float32)


def pic_bilinear(ix, iy):
	x0 = np.clip(np.floor(ix - 0.5), 0, SW - 2).astype(int); y0 = np.clip(np.floor(iy - 0.5), 0, SH - 2).astype(int)
	fx = np.clip(ix - 0.5 - x0, 0, 1)[..., None]; fy = np.clip(iy - 0.5 - y0, 0, 1)[..., None]
	return (pic[y0, x0] * (1 - fx) * (1 - fy) + pic[y0, x0 + 1] * fx * (1 - fy) + pic[y0 + 1, x0] * (1 - fx) * fy + pic[y0 + 1, x0 + 1] * fx * fy)


col = pic_bilinear(IX, IY)
col[~inside] = 0
Image.fromarray(col.astype(np.uint8)).save(out_dir + '/map_color.png')

ni = np.clip(np.floor(IX).astype(int), 0, SW - 1); nj = np.clip(np.floor(IY).astype(int), 0, SH - 1)


def layer(path, name, fill):
	src = np.asarray(Image.open(path)).astype(np.int32)
	assert src.max() < 256, name
	a = src[nj, ni].astype(np.uint8)
	a[~inside] = 0
	if fill is not None:
		a[inside & (a == 0)] = fill
	Image.fromarray(a, 'L').save(out_dir + '/' + name)
	return a


bio = layer(bio_path, 'map_biomes.png', 1)    # облямівка за контуром малюнка всередині дошки — вода
bio_pack = bio.copy()                          # біоми пакета як є — для моделі атмосфери
prov = layer(prov_path, 'map_provinces.png', None)
reg = layer(reg_path, 'map_regions.png', None)
print('biomes on board:', {int(i): int((bio == i).sum()) for i in np.unique(bio)})
print('provinces', len(np.unique(prov)) - 1, 'regions', len(np.unique(reg)) - 1)

# Вода за малюнком: озера й річки, що намальовані, але дрібніші за шар біомів (піксель пакета ~27 м).
# Ознака води — синява B - (R + G) / 2: у води шару біомів 5-й процентиль 24, у суходолу 95-й не вище 2.
# Растр удвічі дрібніший за дошку (8,8 м); упевнена вода (> WATER_HI) тягнеться зв'язними слабкими слідами
# (> WATER_LO), так переривчасті річки не рвуться. Зберігається згладжена маска (L8, 128 — берег):
# шейдер і підказка під курсором читають її однаково — білінійно, поріг 0,5.
WATER_HI, WATER_LO = 8.0, -2.0
from scipy import ndimage as nd
WX, WY = NX * 2, NY * 2
wix, wiy, w_in = board_to_pic(WX, WY)
wc = pic_bilinear(wix, wiy)
blue = nd.gaussian_filter(wc[..., 2] - 0.5 * (wc[..., 0] + wc[..., 1]), 0.7)
del wc
strong = blue > WATER_HI
lab, n = nd.label(blue > WATER_LO)
keep = np.zeros(n + 1, bool); keep[np.unique(lab[strong])] = True; keep[0] = False
water = keep[lab]
del lab
# За контуром малюнка всередині дошки — вода, як і раніше
src_bio = np.asarray(Image.open(bio_path)).astype(np.int32)
wni = np.clip(np.floor(wix).astype(int), 0, SW - 1); wnj = np.clip(np.floor(wiy).astype(int), 0, SH - 1)
water |= w_in & (src_bio[wnj, wni] == 0)
del wix, wiy, wni, wnj
# Дрібний шум: плями води й суходолу менші за 6 клітинок (~470 м2) прибираються
lab, n = nd.label(water); sz = np.bincount(lab.ravel()); water &= ~((sz < 6)[lab] & (lab > 0))
lab, n = nd.label(~water); sz = np.bincount(lab.ravel()); water |= (sz < 6)[lab] & (lab > 0)
del lab
water &= w_in
soft = nd.gaussian_filter(water.astype(np.float32), 0.8)
Image.fromarray(np.round(soft * 255).astype(np.uint8), 'L').save(out_dir + '/map_water.png')
# Вода на дошці (для моделі атмосфери й перевірок) — за центрами клітинок дошки, як читає гра
water_b = soft.reshape(NY, 2, NX, 2).mean((1, 3)) >= 0.5
print('water on board: biomes layer', int((bio == 1).sum()), 'picture', int((water_b & inside).sum()),
	'new', int((water_b & inside & (bio > 1)).sum()), 'dried', int((~water_b & (bio == 1)).sum()))
# Спекотні гори: там, де гори на малюнку помаранчеві, завжди на 40 °C спекотніше (прохання Huzzah 2026-10-22).
# Помаранчевий піксель — насичений (S > 0,62) червоно-жовтий (тон 8–34°, R > 1,5 G) не темний (V > 0,35).
# Такі пікселі є й на освітлених схилах звичайних гір, тому зона — де їх щільно: частка у вікні
# (гаус 15 пікселів полотна) більша за HOT_DENS. Зберігається згладжена маска (L8, 128 — край зони),
# гра й шейдер читають її як воду: білінійно, поріг 0,5; на воді зони немає
HOT_DENS = 0.4
pa = pic / 255.0
pmx = pa.max(-1); pmn = pa.min(-1); pd = np.maximum(pmx - pmn, 1e-6)
ph = np.where(pmx == pa[..., 0], ((pa[..., 1] - pa[..., 2]) / pd) % 6, 0) * 60
orange = ((pmx - pmn) / np.maximum(pmx, 1e-6) > 0.62) & (ph > 8) & (ph < 34) & (pmx > 0.35) & (pa[..., 0] > pa[..., 1] * 1.5)
dens = nd.gaussian_filter(orange.astype(np.float32), 12.0 * SW / 1254.0)
del pa, pmx, pmn, pd, ph
hx = np.clip(IX - 0.5, 0, SW - 1.001); hy = np.clip(IY - 0.5, 0, SH - 1.001)
hx0 = hx.astype(int); hy0 = hy.astype(int); hfx = hx - hx0; hfy = hy - hy0
hd = (dens[hy0, hx0] * (1 - hfx) * (1 - hfy) + dens[hy0, hx0 + 1] * hfx * (1 - hfy)
	+ dens[hy0 + 1, hx0] * (1 - hfx) * hfy + dens[hy0 + 1, hx0 + 1] * hfx * hfy)
hot = (hd > HOT_DENS) & inside & ~water_b
lab, n = nd.label(hot)
# Крихти менші за 200 клітинок (~6 га) — не зона
hot &= ~((np.bincount(lab.ravel()) < 200)[lab] & (lab > 0))
lab, n = nd.label(hot)
print('hot zones', n, 'cells', [int(c) for c in np.bincount(lab.ravel())[1:]],
	'centers m', [(int(c[1] * W / NX), int(c[0] * H / NY)) for c in nd.center_of_mass(hot, lab, range(1, n + 1))])
print('hot biomes', {int(i): int(((bio > 0) & hot & (np.where(water_b & inside, 1, bio) == i)).sum()) for i in range(1, 10)})
Image.fromarray(np.round(nd.gaussian_filter(hot.astype(np.float32), 0.8) * 255).astype(np.uint8), 'L').save(out_dir + '/map_hot.png')
del lab

# Шар біомів зберігає лише суходіл: де була вода — найближчий біом суходолу (на березі озера, яке
# на малюнку менше, це зазвичай «берег»). Воду гра бере з map_water.png
land_src = (bio > 1)
_, (lj, li) = nd.distance_transform_edt(~land_src, return_indices=True)
land = bio[lj, li]
land[~inside] = 0
Image.fromarray(land, 'L').save(out_dir + '/map_biomes.png')
bio = np.where(water_b & inside, 1, land).astype(np.uint8)   # лише для зведення
print('biomes after water:', {int(i): int((bio == i).sum()) for i in np.unique(bio)})

# Назви областей і склад регіонів для гри
# Європейські назви областей (Huzzah 2026-10-28: «Усі назви змінити на європейські»)
EURO_PROVINCES = {1: 'Нордстейн', 2: 'Форнхейм', 3: 'Гринесс', 4: 'Вестстранд', 5: 'Упите', 6: 'Эжеренай', 7: 'Брэндхит', 8: 'Стангейт', 9: 'Судрскард', 10: 'Лионесс', 11: 'Аскрюгг', 12: 'Корран', 13: 'Нордскер', 14: 'Инишард', 15: 'Дастнесс', 16: 'Аустберг', 17: 'Клофтхольм', 18: 'Инишмор', 19: 'Пелькяй', 20: 'Таннстранд', 21: 'Эйнсанд', 22: 'Скеллиг-Бег', 23: 'Норфорс', 24: 'Стейнхальс', 25: 'Кетильфьелль', 26: 'Судвик', 27: 'Уиндмур', 28: 'Рыткальняй', 29: 'Кнокруа', 30: 'Сатмарк', 31: 'Финистер'}
names = {'provinces': {str(p['id']): {'name': EURO_PROVINCES.get(p['id'], p['name']), 'regions': p['region_ids']} for p in meta['provinces']},
	'regions': {str(r['id']): {'province': r['province_id'], 'code': 'R%03d' % r['id'], 'dominant_biome': r['dominant_biome']} for r in meta['regions']}}
json.dump(names, open(out_dir + '/map_names.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=1)

# Суходіл і гори для моделі атмосфери: 144 x 72 у колишній розгортці S (R суходіл, G гори).
# Пласка карта лежить у вікні моделі ATM_ORIGIN / ATM_SPAN (ті самі числа в game.gd і map_shaders.gd),
# поза вікном океан
ATM_ORIGIN = np.array([13900.0, 2000.0]); ATM_SPAN = np.array([8200.0, 5000.0])
ANX, ANY, SUB = 144, 72, 6
sx = (np.arange(ANX * SUB) + 0.5) * bp.SRC_W / (ANX * SUB)
sy = (np.arange(ANY * SUB) + 0.5) * bp.SRC_H / (ANY * SUB)
SX, SY = np.meshgrid(sx, sy)
bx = (SX - ATM_ORIGIN[0]) / ATM_SPAN[0] * W; by = (SY - ATM_ORIGIN[1]) / ATM_SPAN[1] * H
win = (bx >= 0) & (bx < W) & (by >= 0) & (by < H)
bi = np.clip((bx / W * NX).astype(int), 0, NX - 1); bj = np.clip((by / H * NY).astype(int), 0, NY - 1)
# Клітинка моделі ~4 км: озер і річок малюнка вона не бачить, береться шар пакета (як у 2D 04)
b = np.where(win, bio_pack[bj, bi], 1)
land = ((b != 1) & (b != 0)).astype(np.float32)
mount = (b == 6).astype(np.float32)
land = land.reshape(ANY, SUB, ANX, SUB).mean((1, 3)); mount = mount.reshape(ANY, SUB, ANX, SUB).mean((1, 3))
st = np.zeros((ANY, ANX, 4), np.uint8)
st[..., 0] = np.round(land * 255); st[..., 1] = np.round(np.sqrt(mount) * 255); st[..., 3] = 255
Image.fromarray(st, 'RGBA').save(out_dir + '/atmo_static.png')
print('land share in window', float(land.mean()))

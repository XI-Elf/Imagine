#!/usr/bin/env python3
"""Підготовка текстур від нейромережі для гри (Amber, 2D 12).

Нейромережа віддала RGB 1168x784 на сірому тлі (#808080 з віньєткою) замість RGBA потрібного розміру.
Скрипт: прибирає тло в прозорість, обрізає по габариту, ставить поле 4 %, робить плитки безшовними,
ефекти на чорному перетворює на RGBA. Виклик:
    python3 tools/ingest_textures.py <тека_з_PNG_рекурсивно> <вихідна_тека> [--report report.csv]
Потрібні numpy, scipy, Pillow. Вихід: <вихід>/<ім'я>.png + report.csv (вид, розмір, частка прозорого).
"""
import sys, os, csv, glob
import numpy as np
from PIL import Image
from scipy import ndimage as ndi

PAD = 0.04
MAX_SIDE = 640
OBJ_PREFIX = ("bld_", "out_", "gate_", "wall_", "far_")
DECAL_PREFIX = ("edge_", "decal_", "road_", "path_")
STRIPS = ("road_dirt_straight", "road_dirt_wide", "road_cobble_straight")
TILE_PREFIX = ("ground_",)
FX_PREFIX = ("fx_",)


def kind_of(name: str) -> str:
    if name.startswith(FX_PREFIX):
        return "fx"
    if name.startswith(TILE_PREFIX):
        return "tile"
    if name.startswith(DECAL_PREFIX):
        return "decal"
    return "object"


def _bg_model(a: np.ndarray, ring: int = 10, top_only: bool = False):
    """Тло — гладка поверхня (віньєтка): поліном 2-го ступеня по кадровому кільцю.
    top_only — для смуг доріг: вони впираються в три краї кадру, тло видно лише зверху."""
    h, w, _ = a.shape
    yy, xx = np.mgrid[0:h, 0:w]
    m = np.zeros((h, w), bool)
    if top_only:
        m[:ring * 2] = True
    else:
        m[:ring] = m[-ring:] = True
        m[:, :ring] = m[:, -ring:] = True
    x = xx / w - 0.5
    y = yy / h - 0.5
    basis = np.stack([np.ones_like(x), x, y, x * x, y * y, x * y], -1)
    use = m.copy()
    model = np.zeros_like(a)
    for _ in range(3):   # відкидаємо викиди (об'єкт, що торкається краю)
        A = basis[use]
        for c in range(3):
            coef, *_ = np.linalg.lstsq(A, a[..., c][use], rcond=None)
            model[..., c] = basis @ coef
        d = np.abs(a - model).max(-1)
        use = m & (d < 18)
    return model


def key_background(img: Image.Image, top_only: bool = False):
    a = np.asarray(img.convert("RGB")).astype(np.float32)
    model = _bg_model(a, top_only=top_only)
    d = np.abs(a - model).max(-1)
    d = ndi.gaussian_filter(d, 0.7)
    fg = d > 14
    fg = ndi.binary_opening(fg, iterations=1)
    # тло: усе, що не fg і з'єднане з краєм, + великі внутрішні «вікна» тла
    lab, n = ndi.label(~fg)
    border = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    sizes = ndi.sum(np.ones_like(lab), lab, range(n + 1))
    bgmask = np.isin(lab, [l for l in range(1, n + 1) if l in border or sizes[l] > 2500])
    # м'яка альфа: 0 у тлі, 1 в об'єкті, перехід по відстані від тла
    alpha = np.clip((d - 8) / 22.0, 0, 1)
    alpha[bgmask & (d < 14)] = 0
    near = ndi.binary_dilation(bgmask, iterations=2)
    alpha = np.where(bgmask, np.minimum(alpha, 0.0), np.where(near, alpha, 1.0))
    # Тінь на землі (нейромережа малює її попри вимогу): гладке нейтральне затемнення тла.
    # Гра малює власну тінь, тож ця — зайва; відрізняємо від об'єкта за відсутністю текстури й кольору.
    ratio = a / np.maximum(model, 1.0)
    k = ratio.mean(-1)
    neutral = ratio.std(-1) < 0.05
    loc = ndi.uniform_filter(a.mean(-1), 7)
    texture = np.sqrt(np.maximum(ndi.uniform_filter(a.mean(-1) ** 2, 7) - loc ** 2, 0))
    shadow = neutral & (k < 0.97) & (k > 0.35) & (texture < 3.5) & (d < 75)
    shadow = ndi.binary_opening(shadow, iterations=2)
    alpha = np.where(shadow, 0.0, alpha)
    alpha = ndi.gaussian_filter(alpha, 0.6)
    # прибрати сірий ореол: c = (p - bg*(1-a)) / a
    al = np.maximum(alpha, 1e-3)[..., None]
    col = np.where(alpha[..., None] < 0.98, (a - model * (1 - al)) / al, a)
    col = np.clip(col, 0, 255)
    out = np.dstack([col, alpha * 255]).astype(np.uint8)
    # дрібні острівці шуму (<150 пікс) прибрати
    lab2, n2 = ndi.label(out[..., 3] > 20)
    if n2:
        s2 = ndi.sum(np.ones_like(lab2), lab2, range(n2 + 1))
        small = np.isin(lab2, [l for l in range(1, n2 + 1) if s2[l] < 150])
        out[..., 3][small] = 0
    return Image.fromarray(out, "RGBA")


def crop_pad(im: Image.Image, bottom_center=True) -> Image.Image:
    bb = im.getchannel("A").point(lambda v: 255 if v > 12 else 0).getbbox()
    if bb is None:
        return im
    c = im.crop(bb)
    w, h = c.size
    px, py = int(w * PAD) + 1, int(h * PAD) + 1
    out = Image.new("RGBA", (w + 2 * px, h + 2 * py), (0, 0, 0, 0))
    out.paste(c, (px, py))
    return out


def make_tile(img: Image.Image, size: int = 512) -> Image.Image:
    """Центральний квадрат -> size; безшовність: зсув на половину й змішування по косинусній вазі."""
    w, h = img.size
    s = min(w, h)
    sq = img.convert("RGB").crop(((w - s) // 2, (h - s) // 2, (w - s) // 2 + s, (h - s) // 2 + s)).resize((size, size), Image.LANCZOS)
    a = np.asarray(sq).astype(np.float32)
    sh = np.roll(a, (size // 2, size // 2), (0, 1))
    y, x = np.mgrid[0:size, 0:size].astype(np.float32) / size
    wx = np.sin(np.pi * x) ** 2   # 0 на краю, 1 у центрі
    wy = np.sin(np.pi * y) ** 2
    wgt = (wx * wy)[..., None]
    out = a * wgt + sh * (1 - wgt)   # у центрі оригінал, на краях — зсунуте (там шов зникає)
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGB")


def make_fx(img: Image.Image, shadow: bool = False) -> Image.Image:
    a = np.asarray(img.convert("RGB")).astype(np.float32)
    lum = a.max(-1)
    top = max(float(np.percentile(lum, 99.8)), 1.0)
    alpha = np.clip(lum / top, 0, 1)
    if shadow:   # AO: чорний із альфою за яскравістю
        col = np.zeros_like(a)
    else:        # зняти премультиплікацію з чорного
        col = np.clip(a / np.maximum(alpha, 0.02)[..., None], 0, 255)
    out = np.dstack([col, alpha * 255]).astype(np.uint8)
    im = Image.fromarray(out, "RGBA")
    bb = im.getchannel("A").point(lambda v: 255 if v > 6 else 0).getbbox()
    return im.crop(bb) if bb else im


def process(path: str, outdir: str):
    name = os.path.basename(path)
    stem = os.path.splitext(name)[0]
    k = kind_of(stem)
    src = Image.open(path)
    if k == "tile":
        res = make_tile(src)
    elif k == "fx":
        res = make_fx(src, shadow=stem.startswith("fx_ao"))
    else:
        res = crop_pad(key_background(src, top_only=stem in STRIPS))
    if stem in STRIPS:   # нижній край смуги несе залишок тла
        res = crop_pad(res.crop((0, 0, res.size[0], int(res.size[1] * 0.94))))
    if k != "tile" and max(res.size) > MAX_SIDE:   # на екрані об'єкти ≤ ~200 px: 2–3x запасу досить
        sc = MAX_SIDE / max(res.size)
        res = res.resize((max(1, round(res.size[0] * sc)), max(1, round(res.size[1] * sc))), Image.LANCZOS)
    res.save(os.path.join(outdir, name), optimize=True)
    alpha = np.asarray(res.getchannel("A")) if res.mode == "RGBA" else None
    cover = float((alpha > 20).mean()) if alpha is not None else 1.0
    return [stem, k, res.size[0], res.size[1], round(cover, 3)]


def main():
    args = [x for x in sys.argv[1:] if not x.startswith("--")]
    src, dst = args[0], args[1]
    os.makedirs(dst, exist_ok=True)
    rows = []
    for p in sorted(glob.glob(os.path.join(src, "**", "*.png"), recursive=True)):
        rows.append(process(p, dst))
        print(rows[-1])
    if "--report" in sys.argv:
        rp = sys.argv[sys.argv.index("--report") + 1]
        with open(rp, "w", newline="") as f:
            w = csv.writer(f)
            w.writerow(["name", "kind", "w", "h", "opaque_share"])
            w.writerows(rows)


if __name__ == "__main__":
    main()

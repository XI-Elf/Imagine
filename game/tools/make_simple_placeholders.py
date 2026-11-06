#!/usr/bin/env python3
"""Прості заглушки графіки світу (Huzzah 2026-11-06: «лиши тільки топографічну карту, решту заміни простими
текстурами, але щоб різнилися одна від одної»). Малюються кодом, без намальованих текстур:
  art/terrain/t00..t12   — безшовні плитки місцевості (кожна свій колір і візерунок)
  art/storybook/*.png    — спрайти: дерева, гори, будівлі, фігурки (прості форми, кожна своя)
  art/medallion/m0..m5   — значки поселень (скупчення будиночків, без кола й рамки)
Розміри й імена файлів ті самі, що були, тож код не змінюється. Запуск: python3 tools/make_simple_placeholders.py
Потрібні numpy, scipy, Pillow."""
import os
import zlib
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi

ART = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "art")
rng = np.random.default_rng(7)


# ---------------------------------------------------------------- плитки (безшовні)
def noise(size, sigma, seed):
    r = np.random.default_rng(seed)
    n = ndi.gaussian_filter(r.random((size, size)), sigma, mode="wrap")
    return (n - n.min()) / (n.max() - n.min() + 1e-9)


def tile(base, var, seed, kind=""):
    s = 512
    col = np.zeros((s, s, 3), np.float32)
    n1, n2, n3 = noise(s, 40, seed), noise(s, 9, seed + 1), noise(s, 2.0, seed + 2)
    k = 0.55 * n1 + 0.3 * n2 + 0.15 * n3
    for c in range(3):
        col[..., c] = base[c] * (1 + var * (k - 0.5) * 2)
    yy, xx = np.mgrid[0:s, 0:s]
    if kind == "waves":
        w = np.sin((yy + 18 * n1 * 20) / 9.0 + n2 * 4) > 0.82
        col[w] = np.minimum(col[w] * 1.35, 1)
    elif kind == "stripes":
        col *= (0.9 + 0.1 * np.sin(xx / 5.0))[..., None]
    elif kind == "dots":
        d = n3 > 0.82
        col[d] = col[d] * 0.7
    elif kind == "facets":
        pts = np.random.default_rng(seed).random((40, 2)) * s
        d = np.full((s, s), 1e9); idx = np.zeros((s, s), int)
        for i, (px, py) in enumerate(pts):
            for ox in (-s, 0, s):
                for oy in (-s, 0, s):
                    dd = (xx - px - ox) ** 2 + (yy - py - oy) ** 2
                    m = dd < d
                    d[m] = dd[m]; idx[m] = i
        shade = (np.random.default_rng(seed + 5).random(40) - 0.5)[idx]
        col *= (1 + 0.45 * shade)[..., None]
        edge = (ndi.maximum_filter(idx, 3) != ndi.minimum_filter(idx, 3))
        col[edge] *= 0.6
    elif kind == "puddles":
        p = noise(s, 14, seed + 9) > 0.62
        col[p] = np.array(var_puddle[0], np.float32)
    elif kind == "blobs":
        b = noise(s, 6, seed + 3) > 0.6
        col[b] *= 0.65
    elif kind == "cracks":
        e = np.abs(noise(s, 7, seed + 4) - 0.5) < 0.012
        col[e] *= 0.45
    elif kind == "glow":
        col = col * (0.6 + 0.8 * n1[..., None])
    return Image.fromarray(np.clip(col * 255, 0, 255).astype(np.uint8), "RGB")


var_puddle = [(0.30, 0.42, 0.45)]
TERRAIN = {
    "t00_water": ((0.22, 0.43, 0.56), 0.10, "waves"),
    "t01_coast": ((0.80, 0.73, 0.54), 0.08, "dots"),
    "t02_forest": ((0.16, 0.31, 0.14), 0.18, "blobs"),
    "t03_field1": ((0.40, 0.60, 0.20), 0.10, ""),
    "t04_field2": ((0.60, 0.66, 0.28), 0.08, "stripes"),
    "t05_wasteland": ((0.56, 0.50, 0.40), 0.12, "cracks"),
    "t06_swamp": ((0.34, 0.37, 0.19), 0.14, "puddles"),
    "t07_mountains": ((0.36, 0.35, 0.37), 0.14, "facets"),
    "t08_hot_mountains": ((0.56, 0.31, 0.20), 0.14, "facets"),
    "t09_rad_forest": ((0.26, 0.27, 0.36), 0.18, "blobs"),
    "t10_rad_wasteland": ((0.44, 0.39, 0.47), 0.12, "cracks"),
    "t11_rad_swamp": ((0.36, 0.28, 0.34), 0.14, "puddles"),
    "t12_glow": ((0.90, 0.63, 0.20), 0.30, "glow"),
}
SURF = {   # плитки поверхонь міста: Art.surface
    "cobble": ((0.48, 0.47, 0.45), 0.12, "dots"),
    "masonry": ((0.52, 0.50, 0.47), 0.10, "stripes"),
    "roof": ((0.55, 0.30, 0.20), 0.10, "stripes"),
    "wood": ((0.45, 0.31, 0.18), 0.10, "stripes"),
}


# ---------------------------------------------------------------- спрайти
SS = 2


def canvas(w, h):
    im = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))
    return im, ImageDraw.Draw(im)


def fin(im, w, h):
    return im.resize((w, h), Image.LANCZOS)


def c255(c):
    return tuple(int(v * 255) for v in c) + (255,)


def shade(c, k):
    return tuple(min(1.0, v * k) for v in c)


def poly(d, pts, col):
    d.polygon([(x * SS, y * SS) for x, y in pts], fill=c255(col))


def ell(d, box, col):
    d.ellipse([v * SS for v in box], fill=c255(col))


def rect(d, box, col):
    d.rectangle([v * SS for v in box], fill=c255(col))


def tree_round(w, h, col):
    im, d = canvas(w, h)
    rect(d, (w * 0.46, h * 0.62, w * 0.54, h), (0.30, 0.20, 0.12))
    ell(d, (w * 0.12, h * 0.04, w * 0.88, h * 0.72), shade(col, 0.8))
    ell(d, (w * 0.18, h * 0.04, w * 0.78, h * 0.62), col)
    ell(d, (w * 0.28, h * 0.10, w * 0.56, h * 0.34), shade(col, 1.25))
    return fin(im, w, h)


def tree_pine(w, h, col):
    im, d = canvas(w, h)
    rect(d, (w * 0.47, h * 0.80, w * 0.53, h), (0.28, 0.19, 0.11))
    for i, f in enumerate((0.0, 0.25, 0.5)):
        y0 = h * (0.02 + f * 0.8 * 0.6)
        poly(d, [(w * 0.5, y0), (w * (0.18 + 0.04 * i), h * (0.38 + f * 0.5)), (w * (0.82 - 0.04 * i), h * (0.38 + f * 0.5))], shade(col, 0.85 + 0.15 * i))
    return fin(im, w, h)


def tree_bare(w, h, col):
    im, d = canvas(w, h)
    d.line([(w * 0.5 * SS, h * SS), (w * 0.5 * SS, h * 0.3 * SS)], fill=c255(col), width=int(w * 0.04 * SS))
    for x1, y1 in ((0.15, 0.1), (0.85, 0.15), (0.2, 0.45), (0.8, 0.5), (0.5, 0.0)):
        d.line([(w * 0.5 * SS, h * 0.6 * SS), (w * x1 * SS, h * y1 * SS)], fill=c255(col), width=int(w * 0.025 * SS))
    return fin(im, w, h)


def bush(w, h, col, flower=None):
    im, d = canvas(w, h)
    for bx, by, r in ((0.3, 0.6, 0.3), (0.65, 0.58, 0.32), (0.48, 0.4, 0.3)):
        ell(d, (w * (bx - r), h * (by - r), w * (bx + r), h * (by + r + 0.1)), col)
    if flower:
        for fx, fy in ((0.3, 0.5), (0.5, 0.35), (0.7, 0.55), (0.45, 0.6)):
            ell(d, (w * fx - 6, h * fy - 6, w * fx + 6, h * fy + 6), flower)
    return fin(im, w, h)


def mountain(w, h, col, snow=False, ridge=False):
    im, d = canvas(w, h)
    peaks = [(0.18, 0.55), (0.42, 0.08), (0.66, 0.38), (0.88, 0.62)] if not ridge else [(0.1, 0.5), (0.3, 0.2), (0.5, 0.45), (0.72, 0.12), (0.9, 0.5)]
    pts = [(0.0, 1.0)] + [(x, y) for x, y in peaks] + [(1.0, 1.0)]
    poly(d, [(x * w, y * h) for x, y in pts], shade(col, 0.8))
    for i in range(1, len(pts) - 2):   # світла грань кожного піка
        (x0, y0), (x1, y1) = pts[i], pts[i + 1]
        poly(d, [(x0 * w, y0 * h), (x1 * w, y1 * h), (x0 * w, 1.0 * h)], shade(col, 1.15))
    if snow:
        for x, y in peaks[1:3]:
            poly(d, [(x * w, y * h), ((x - 0.07) * w, (y + 0.15) * h), ((x + 0.07) * w, (y + 0.15) * h)], (0.9, 0.92, 0.95))
    return fin(im, w, h)


def mesa(w, h, col):
    im, d = canvas(w, h)
    poly(d, [(0.05 * w, h), (0.15 * w, 0.2 * h), (0.85 * w, 0.2 * h), (0.95 * w, h)], shade(col, 0.85))
    rect(d, (0.15 * w, 0.2 * h, 0.85 * w, 0.32 * h), shade(col, 1.2))
    return fin(im, w, h)


def rock(w, h, col):
    im, d = canvas(w, h)
    poly(d, [(0.05 * w, h), (0.15 * w, 0.4 * h), (0.45 * w, 0.1 * h), (0.8 * w, 0.3 * h), (0.95 * w, h)], shade(col, 0.85))
    poly(d, [(0.45 * w, 0.1 * h), (0.8 * w, 0.3 * h), (0.5 * w, 0.6 * h)], shade(col, 1.2))
    return fin(im, w, h)


def cliff(w, h, col):
    im, d = canvas(w, h)
    rect(d, (0.04 * w, 0.25 * h, 0.96 * w, h), shade(col, 0.85))
    for i in range(5):
        rect(d, (0.04 * w + i * 0.18 * w, 0.25 * h, 0.04 * w + i * 0.18 * w + 0.07 * w, h), shade(col, 1.15))
    poly(d, [(0.04 * w, 0.25 * h), (0.2 * w, 0.05 * h), (0.5 * w, 0.18 * h), (0.8 * w, 0.0), (0.96 * w, 0.25 * h)], shade(col, 1.1))
    return fin(im, w, h)


def house(w, h, wall, roof, kind="house"):
    im, d = canvas(w, h)
    wl, wr = w * 0.12, w * 0.88
    rect(d, (wl, h * 0.45, wr, h * 0.96), wall)
    poly(d, [(wl - w * 0.04, h * 0.47), (w * 0.5, h * 0.06), (wr + w * 0.04, h * 0.47)], roof)
    rect(d, (w * 0.44, h * 0.66, w * 0.56, h * 0.96), shade(wall, 0.55))
    rect(d, (w * 0.2, h * 0.55, w * 0.3, h * 0.66), (0.95, 0.8, 0.4))
    if kind == "hall":
        rect(d, (w * 0.36, h * 0.0, w * 0.64, h * 0.3), shade(wall, 0.9))
        poly(d, [(w * 0.34, h * 0.0), (w * 0.5, -h * 0.0 + 1), (w * 0.66, h * 0.0)], roof)
    if kind == "smithy":
        rect(d, (w * 0.72, h * 0.04, w * 0.8, h * 0.5), (0.35, 0.33, 0.32))
    if kind == "temple":
        rect(d, (w * 0.4, h * 0.0, w * 0.6, h * 0.35), shade(wall, 1.1))
        poly(d, [(w * 0.38, h * 0.02), (w * 0.5, -h * 0.02 + 1), (w * 0.62, h * 0.02)], (0.3, 0.3, 0.4))
    if kind == "inn":
        rect(d, (w * 0.7, h * 0.55, w * 0.8, h * 0.66), (0.95, 0.8, 0.4))
        rect(d, (w * 0.88, h * 0.6, w * 0.97, h * 0.7), (0.6, 0.15, 0.15))
    if kind == "healer":
        rect(d, (w * 0.7, h * 0.52, w * 0.78, h * 0.72), (0.9, 0.9, 0.9))
        rect(d, (w * 0.66, h * 0.58, w * 0.82, h * 0.66), (0.9, 0.9, 0.9))
    return fin(im, w, h)


def stall(w, h):
    im, d = canvas(w, h)
    rect(d, (w * 0.1, h * 0.45, w * 0.9, h * 0.95), (0.45, 0.32, 0.2))
    for i in range(6):
        poly(d, [(w * (0.06 + i * 0.15), h * 0.15), (w * (0.21 + i * 0.15), h * 0.15), (w * (0.2 + i * 0.15), h * 0.45), (w * (0.07 + i * 0.15), h * 0.45)], (0.75, 0.25, 0.2) if i % 2 == 0 else (0.9, 0.85, 0.7))
    return fin(im, w, h)


def well(w, h):
    im, d = canvas(w, h)
    ell(d, (w * 0.2, h * 0.55, w * 0.8, h * 0.98), (0.5, 0.5, 0.52))
    ell(d, (w * 0.28, h * 0.6, w * 0.72, h * 0.85), (0.15, 0.25, 0.35))
    rect(d, (w * 0.22, h * 0.12, w * 0.28, h * 0.78), (0.4, 0.28, 0.18))
    rect(d, (w * 0.72, h * 0.12, w * 0.78, h * 0.78), (0.4, 0.28, 0.18))
    poly(d, [(w * 0.15, h * 0.18), (w * 0.5, 0.0), (w * 0.85, h * 0.18)], (0.55, 0.3, 0.2))
    return fin(im, w, h)


def tech(w, h, kind):
    im, d = canvas(w, h)
    steel, amber = (0.42, 0.45, 0.5), (0.95, 0.65, 0.15)
    if kind == "tower":
        poly(d, [(w * 0.3, h), (w * 0.4, h * 0.05), (w * 0.6, h * 0.05), (w * 0.7, h)], steel)
        ell(d, (w * 0.38, h * 0.0, w * 0.62, h * 0.1), amber)
    elif kind == "dome":
        ell(d, (w * 0.05, h * 0.1, w * 0.95, h * 1.6), steel)
        ell(d, (w * 0.42, h * 0.3, w * 0.58, h * 0.5), amber)
    else:
        poly(d, [(w * 0.05, h * 0.9), (w * 0.25, h * 0.2), (w * 0.55, h * 0.5), (w * 0.9, h * 0.9)], shade(steel, 0.8))
        ell(d, (w * 0.4, h * 0.55, w * 0.5, h * 0.7), amber)
    return fin(im, w, h)


def figure(w, h, body, head=(0.85, 0.7, 0.55), extra=""):
    im, d = canvas(w, h)
    if extra == "hound":
        ell(d, (w * 0.1, h * 0.35, w * 0.8, h * 0.8), body)
        ell(d, (w * 0.65, h * 0.2, w * 0.95, h * 0.5), shade(body, 1.1))
        for x in (0.2, 0.35, 0.55, 0.7):
            rect(d, (w * x, h * 0.75, w * (x + 0.06), h * 0.98), shade(body, 0.8))
        return fin(im, w, h)
    ell(d, (w * 0.28, h * 0.02, w * 0.72, h * 0.22), head)
    poly(d, [(w * 0.18, h * 0.98), (w * 0.3, h * 0.24), (w * 0.7, h * 0.24), (w * 0.82, h * 0.98)], body)
    if extra == "guard":
        rect(d, (w * 0.82, h * 0.1, w * 0.88, h * 0.95), (0.55, 0.5, 0.4))
    if extra == "bandit":
        rect(d, (w * 0.28, h * 0.08, w * 0.72, h * 0.14), (0.15, 0.1, 0.1))
    if extra == "woman":
        poly(d, [(w * 0.1, h * 0.98), (w * 0.3, h * 0.4), (w * 0.7, h * 0.4), (w * 0.9, h * 0.98)], shade(body, 0.9))
    return fin(im, w, h)


# ---------------------------------------------------------------- значки поселень (без кола: скупчення будинків)
def settlement(level, size=640):
    im, d = canvas(size, size)
    r = np.random.default_rng(100 + level)
    n = [2, 4, 7, 11, 16, 22][level]
    spots = sorted([(r.random() * 0.7 + 0.15, r.random() * 0.6 + 0.2) for _ in range(n)], key=lambda p: p[1])
    for x, y in spots:
        s = size * (0.14 + 0.03 * r.random())
        wall = (0.5 + 0.1 * r.random(), 0.42, 0.3)
        roof = (0.5 + 0.2 * r.random(), 0.28, 0.2)
        d.rectangle([(x * size - s / 2) * SS, (y * size - s * 0.5) * SS, (x * size + s / 2) * SS, (y * size) * SS], fill=c255(wall))
        poly(d, [(x * size - s * 0.6, y * size - s * 0.45), (x * size, y * size - s * 1.0), (x * size + s * 0.6, y * size - s * 0.45)], roof)
    return fin(im, size, size)


def save(img, rel):
    p = os.path.join(ART, rel)
    img.save(p, optimize=True)


def main():
    for k, (base, var, kind) in TERRAIN.items():
        save(tile(base, var, zlib.crc32(k.encode()) % 1000, kind), f"terrain/{k}.png")
    for k, (base, var, kind) in SURF.items():
        save(tile(base, var, zlib.crc32(k.encode()) % 1000, kind), f"storybook/{k}.png")
    G, DG, LG = (0.28, 0.5, 0.2), (0.15, 0.32, 0.14), (0.5, 0.66, 0.28)
    spr = {
        "tree_oak": tree_round(491, 460, G), "tree_light": tree_round(391, 442, LG), "tree_crooked": tree_pine(442, 408, DG),
        "bush_berry": bush(351, 282, (0.2, 0.42, 0.18), (0.75, 0.15, 0.2)), "bush_flower": bush(387, 259, (0.3, 0.5, 0.2), (0.95, 0.85, 0.3)),
        "mountain_gray": mountain(469, 340, (0.4, 0.39, 0.42)), "peak_gray": mountain(507, 427, (0.36, 0.36, 0.4), snow=True),
        "ridge_gray": mountain(629, 251, (0.42, 0.4, 0.43), ridge=True), "cliff_gray": cliff(454, 355, (0.45, 0.44, 0.46)),
        "mountain_hot": mountain(437, 305, (0.6, 0.34, 0.22)), "ridge_hot": mountain(574, 353, (0.58, 0.36, 0.24), ridge=True),
        "mesa_hot": mesa(585, 281, (0.62, 0.38, 0.25)), "rock": rock(345, 265, (0.5, 0.49, 0.5)),
        "house": house(494, 375, (0.62, 0.54, 0.4), (0.55, 0.3, 0.2)), "hall": house(499, 516, (0.58, 0.55, 0.5), (0.35, 0.25, 0.2), "hall"),
        "inn": house(527, 469, (0.65, 0.5, 0.32), (0.45, 0.22, 0.16), "inn"), "smithy": house(537, 442, (0.45, 0.42, 0.4), (0.3, 0.28, 0.3), "smithy"),
        "temple": house(485, 491, (0.75, 0.73, 0.68), (0.3, 0.3, 0.42), "temple"), "healer": house(481, 410, (0.7, 0.68, 0.55), (0.3, 0.5, 0.35), "healer"),
        "stall": stall(503, 382), "well": well(364, 372),
        "tech_tower": tech(221, 600, "tower"), "tech_dome": tech(536, 280, "dome"), "tech_wreck": tech(485, 300, "wreck"),
        "traveler": figure(243, 510, (0.3, 0.4, 0.55)), "villager": figure(335, 517, (0.55, 0.45, 0.3)),
        "woman": figure(283, 489, (0.65, 0.3, 0.35), extra="woman"), "guard": figure(344, 548, (0.45, 0.47, 0.5), extra="guard"),
        "bandit": figure(404, 489, (0.3, 0.22, 0.2), extra="bandit"), "hound": figure(444, 428, (0.4, 0.33, 0.25), extra="hound"),
    }
    for k, im in spr.items():
        save(im, f"storybook/{k}.png")
    for i, k in enumerate(["m0_camp", "m1_ostrog", "m2_sloboda", "m3_posad", "m4_gorod", "m5_bolshoy_gorod"]):
        save(settlement(i), f"medallion/{k}.png")
    print("ok")


if __name__ == "__main__":
    main()

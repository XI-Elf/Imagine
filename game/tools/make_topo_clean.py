#!/usr/bin/env python3
"""Топокарта світу без підписів: art/map/map_topo.png (канон, 2026-10-29) має «запечені» назви регіонів і жовту точку міста.
Для огляду регіону (world/region_view.gd) підписи малюються окремо, тому тут вони прибираються: пікселі кольору кремового
ореолу й темно-коричневих літер (+ жовта точка міста з чорним кільцем) розширюються на 3 px і заповнюються дифузією сусідніх
пікселів. Результат — art/map/map_topo_clean.png (оригінал не чіпаємо: на M показується він).
  python3 -I game/tools/make_topo_clean.py [тека game]
"""
import pathlib
import sys

import numpy as np
from PIL import Image

game = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else pathlib.Path(__file__).resolve().parent.parent
src = game / "art" / "map" / "map_topo.png"
img = np.array(Image.open(src).convert("RGB")).astype(np.int32)


def near(color, tol):
    return (np.abs(img - np.array(color)).max(axis=2) <= tol)


mask = near((240, 224, 192), 8) | near((250, 240, 215), 6) | near((40, 16, 8), 10) | near((36, 23, 13), 9)          # ореол і літери
dot = near((250, 190, 40), 40)                                   # жовта точка міста
mask |= dot
# розширення маски (AA-краї літер, чорне кільце точки)
def dilate(m, n):
    out = m.copy()
    for _ in range(n):
        p = np.pad(out, 1)
        out = out | p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:]
    return out
ring = dilate(dot, 5) & near((16, 16, 16), 40)
mask = dilate(mask, 3) | ring
# Заповнення: спершу фронтом від відомих пікселів, потім релаксація Лапласа (гладко, без смуг)
work = img.astype(np.float32)
known = ~mask
for _ in range(40):
    p = np.pad(work, ((1, 1), (1, 1), (0, 0)), mode="edge")
    k = np.pad(known.astype(np.float32), 1)
    num = (p[:-2, 1:-1] * k[:-2, 1:-1, None] + p[2:, 1:-1] * k[2:, 1:-1, None] + p[1:-1, :-2] * k[1:-1, :-2, None] + p[1:-1, 2:] * k[1:-1, 2:, None])
    den = (k[:-2, 1:-1] + k[2:, 1:-1] + k[1:-1, :-2] + k[1:-1, 2:])[:, :, None]
    fill = np.where(den > 0, num / np.maximum(den, 1e-6), work)
    work = np.where(known[:, :, None], work, fill)
    known = known | (den[:, :, 0] > 0)
for _ in range(300):
    p = np.pad(work, ((1, 1), (1, 1), (0, 0)), mode="edge")
    avg = (p[:-2, 1:-1] + p[2:, 1:-1] + p[1:-1, :-2] + p[1:-1, 2:]) * 0.25
    work = np.where(mask[:, :, None], avg, work)
out = game / "art" / "map" / "map_topo_clean.png"
Image.fromarray(np.clip(work, 0, 255).astype(np.uint8)).save(out, optimize=True)
print("маска %.2f%% пікселів -> %s" % (mask.mean() * 100.0, out))

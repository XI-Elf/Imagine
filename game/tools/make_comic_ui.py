#!/usr/bin/env python3
"""Тёмные комикс-рамки интерфейса (Q08 D + Q24 A) из OPTIONAL_UI комикс-набора.

python3 tools/make_comic_ui.py <Amber_Comic_Assets.zip | папка comic_ui> [game/art/comic_ui]

Что делает:
  * перекрашивает пергамент внутри рамок в тёмный «уголь», сталь — в тёмный оружейный металл,
    ржавчину и латунные заклёпки оставляет (тёмная палитра, формы комикса те же);
  * собирает из рамок nine-patch: углы берутся из картинки как есть, края — из чистого куска
    края без ржавчины и без средней пластины, поэтому рамка растягивается на окно любого размера;
  * уменьшает всё до размера экрана (рамка ~16–20 px вместо 50 px исходника);
  * отдельно режет среднюю пластину верхнего края и ставит в неё янтарную линзу —
    это редкий «техно-артефакт», который ставится только на главные окна.
Результат и поля nine-patch (в пикселях результата) пишутся в comic_ui.json рядом с картинками.
"""
import io
import json
import math
import os
import sys
import zipfile

from PIL import Image, ImageDraw, ImageFilter

NAMES = ["dialogue_panel", "button", "health_frame", "inventory_slot", "portrait_panel", "ribbon"]

# Тёмная палитра (те же значения — в ui/comic_ui.gd).
COAL = (27, 26, 30)          # внутренность панелей
STEEL_MUL = (0.55, 0.58, 0.64)  # сталь темнее и холоднее
AMBER = (255, 176, 48)       # янтарь — цвет техно-артефакта


def load_sources(src):
    out = {}
    if os.path.isdir(src):
        for n in NAMES:
            out[n] = Image.open(os.path.join(src, n + ".png")).convert("RGBA")
        return out
    with zipfile.ZipFile(src) as z:
        for n in NAMES:
            path = [p for p in z.namelist() if p.endswith("comic_ui/" + n + ".png")][0]
            out[n] = Image.open(io.BytesIO(z.read(path))).convert("RGBA")
    return out


def lum(p):
    return 0.299 * p[0] + 0.587 * p[1] + 0.114 * p[2]


def is_parchment(p):
    return p[3] > 40 and lum(p) > 150 and p[0] > p[2] + 12


def is_rust(p):
    return p[3] > 40 and p[0] > p[1] + 22 and p[0] > p[2] + 40 and lum(p) < 175


def is_steel(p):
    return p[3] > 40 and p[2] > p[0] + 12 and lum(p) > 45


def darken(im):
    """Пергамент → уголь (с сохранением штриховки), сталь → тёмный металл."""
    px = im.load()
    w, h = im.size
    out = im.copy()
    po = out.load()
    for y in range(h):
        for x in range(w):
            p = px[x, y]
            if p[3] == 0:
                continue
            if is_parchment(p):
                d = (lum(p) - 222.0) * 0.45  # штриховка и пятна пергамента — лёгкая рябь на угле
                po[x, y] = (clamp(COAL[0] + d), clamp(COAL[1] + d), clamp(COAL[2] + d * 1.1), p[3])
            elif is_steel(p):
                po[x, y] = (clamp(p[0] * STEEL_MUL[0]), clamp(p[1] * STEEL_MUL[1]), clamp(p[2] * STEEL_MUL[2]), p[3])
            elif is_rust(p):
                po[x, y] = (clamp(p[0] * 0.8), clamp(p[1] * 0.72), clamp(p[2] * 0.7), p[3])
    return out


def clamp(v):
    return max(0, min(255, int(round(v))))


def defect(im, box):
    """Сколько в куске края ржавчины и сколов пергамента (меньше — чище)."""
    px = im.load()
    n = 0
    for y in range(box[1], box[3]):
        for x in range(box[0], box[2]):
            p = px[x, y]
            if is_rust(p) or is_parchment(p):
                n += 1
    return n


def best_strip(im, horizontal, lo, hi, thick, s):
    """Самая чистая полоса шириной s вдоль края между lo и hi."""
    best, best_at = None, lo
    for a in range(lo, hi - s):
        box = (a, 0, a + s, thick) if horizontal else (0, a, thick, a + s)
        d = defect(im, box)
        if best is None or d < best:
            best, best_at = d, a
    return best_at


def nine_patch(src, cx, cy, s=6):
    """Новая картинка: углы cx×cy из исходника, края — чистые полосы шириной s, середина — уголь."""
    w, h = src.size
    out = Image.new("RGBA", (2 * cx + s, 2 * cy + s), (0, 0, 0, 0))
    # углы
    out.paste(src.crop((0, 0, cx, cy)), (0, 0))
    out.paste(src.crop((w - cx, 0, w, cy)), (cx + s, 0))
    out.paste(src.crop((0, h - cy, cx, h)), (0, cy + s))
    out.paste(src.crop((w - cx, h - cy, w, h)), (cx + s, cy + s))
    # края: ищем чистый кусок между углом и средней пластиной (пластина около середины)
    mid_x, mid_y = w // 2, h // 2
    flip_b = src.transpose(Image.FLIP_TOP_BOTTOM)
    flip_r = src.transpose(Image.FLIP_LEFT_RIGHT)
    tx = best_strip(src, True, cx, mid_x - int(w * 0.14), cy, s)
    bx = best_strip(flip_b, True, cx, mid_x - int(w * 0.14), cy, s)
    ly = best_strip(src, False, cy, mid_y - int(h * 0.14), cx, s)
    ry = best_strip(flip_r, False, cy, mid_y - int(h * 0.14), cx, s)
    out.paste(src.crop((tx, 0, tx + s, cy)), (cx, 0))
    out.paste(src.crop((bx, h - cy, bx + s, h)), (cx, cy + s))
    out.paste(src.crop((0, ly, cx, ly + s)), (0, cy))
    out.paste(src.crop((w - cx, ry, w, ry + s)), (cx + s, cy))
    # середина
    out.paste(Image.new("RGBA", (s, s), COAL + (255,)), (cx, cy))
    return out


def scaled(im, k):
    return im.resize((max(1, round(im.size[0] * k)), max(1, round(im.size[1] * k))), Image.LANCZOS)


def tech_plate(src_dark, k):
    """Средняя пластина верхнего края + янтарная линза на месте заклёпки."""
    w, h = src_dark.size
    # пластина — непрозрачный участок сверху посередине, выше края рамки
    plate = src_dark.crop((w // 2 - 70, 0, w // 2 + 70, 62))
    pw, ph = plate.size
    # стираем всё, что ниже пластины (внутренность панели), оставляя саму пластину
    pp = plate.load()
    for y in range(ph):
        for x in range(pw):
            p = pp[x, y]
            if p[3] and lum(p) < 40 and abs(p[0] - COAL[0]) < 14 and abs(p[2] - COAL[2]) < 14 and y > 30:
                pp[x, y] = (0, 0, 0, 0)
    d = ImageDraw.Draw(plate)
    c = (pw // 2, 26)
    r = 13
    # гнездо и линза
    d.ellipse((c[0] - r - 4, c[1] - r - 4, c[0] + r + 4, c[1] + r + 4), fill=(14, 14, 16, 255))
    d.ellipse((c[0] - r - 1, c[1] - r - 1, c[0] + r + 1, c[1] + r + 1), fill=(70, 74, 82, 255))
    glow = Image.new("RGBA", plate.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    for i in range(r, 0, -1):
        t = i / r
        col = (clamp(AMBER[0] * (1.0 - 0.15 * t)), clamp(AMBER[1] * (1.15 - 0.55 * t)), clamp(AMBER[2] * (1.6 - 1.2 * t)), 255)
        gd.ellipse((c[0] - i, c[1] - i, c[0] + i, c[1] + i), fill=col)
    gd.ellipse((c[0] - 5, c[1] - 7, c[0] + 1, c[1] - 2), fill=(255, 240, 200, 230))  # блик
    plate = Image.alpha_composite(plate, glow)
    d = ImageDraw.Draw(plate)
    d.ellipse((c[0] - r - 1, c[1] - r - 1, c[0] + r + 1, c[1] + r + 1), outline=(10, 10, 10, 255), width=3)
    # две «жилы» от линзы по пластине — техника, а не украшение
    for sgn in (-1, 1):
        x0 = c[0] + sgn * (r + 4)
        d.line((x0, c[1], x0 + sgn * 16, c[1]), fill=(10, 10, 10, 255), width=4)
        d.line((x0, c[1], x0 + sgn * 16, c[1]), fill=(200, 130, 40, 255), width=2)
    return scaled(plate, k)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    dst = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(__file__), "..", "art", "comic_ui")
    os.makedirs(dst, exist_ok=True)
    src = load_sources(sys.argv[1])
    dark = {n: darken(im) for n, im in src.items()}
    meta = {}
    K = 0.36  # масштаб: рамка исходника ~50 px → ~18 px на экране

    def put(name, im, margins=None, content=None):
        im.save(os.path.join(dst, name + ".png"))
        meta[name] = {"size": list(im.size)}
        if margins:
            meta[name]["margin"] = margins
        if content:
            meta[name]["content"] = content

    # панель окна
    cx, cy = 82, 74
    np_ = scaled(nine_patch(dark["dialogue_panel"], cx, cy), K)
    m = [round(cx * K), round(cy * K)]
    put("panel", np_, m, [round(60 * K) + 4, round(52 * K) + 4])
    # кнопка: тонкая рамка, отдельно — нажатая (светлее линия) делается модуляцией в коде
    bx, by = 74, 64
    BK = 0.22
    put("button", scaled(nine_patch(dark["button"], bx, by), BK), [round(bx * BK), round(by * BK)], [round(66 * BK) + 4, round(52 * BK) - 2])
    # ячейка инвентаря
    sx, sy = 70, 70
    put("slot", scaled(nine_patch(dark["inventory_slot"], sx, sy), 0.3), [round(sx * 0.3), round(sy * 0.3)], [round(56 * 0.3), round(56 * 0.3)])
    # рамка портрета / куклы
    qx, qy = 70, 72
    put("portrait", scaled(nine_patch(dark["portrait_panel"], qx, qy), K), [round(qx * K), round(qy * K)], [round(56 * K) + 2, round(58 * K) + 2])
    # рамка шкалы (внутри и так тёмная): края по горизонтали
    hb = dark["health_frame"]
    hx = 60
    hw, hh = hb.size
    strip = hb.crop((hx, 0, hx + 6, hh))
    bar = Image.new("RGBA", (2 * hx + 6, hh), (0, 0, 0, 0))
    bar.paste(hb.crop((0, 0, hx, hh)), (0, 0))
    bar.paste(strip, (hx, 0))
    bar.paste(hb.crop((hw - hx, 0, hw, hh)), (hx + 6, 0))
    put("bar", scaled(bar, 0.2), [round(hx * 0.2), round(hh * 0.2 * 0.5) - 1], [round(46 * 0.2), round(38 * 0.2)])
    # лента (заголовок / метка) — без растяжения
    put("ribbon", scaled(dark["ribbon"], 0.18))
    # техно-пластина с янтарной линзой
    put("tech_plate", tech_plate(dark["dialogue_panel"], K + 0.06))
    with open(os.path.join(dst, "comic_ui.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=1)
    print(json.dumps(meta, ensure_ascii=False))


if __name__ == "__main__":
    main()

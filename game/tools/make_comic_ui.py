#!/usr/bin/env python3
"""Темні комікс-рамки інтерфейсу (Q08 D + Q24 A) з OPTIONAL_UI комікс-набору.

python3 tools/make_comic_ui.py <Amber_Comic_Assets.zip | тека comic_ui> [game/art/comic_ui]

Що робить:
  * перефарбовує пергамент усередині рамок у темне «вугілля», сталь — у темний збройовий метал,
    іржу й латунні заклепки залишає (темна палітра, форми коміксу ті самі);
  * збирає з рамок nine-patch: кути беруться з картинки як є, краї — з чистого шматка
    краю без іржі й без середньої пластини, тому рамка розтягується на вікно будь-якого розміру;
  * зменшує все до розміру екрана (рамка ~16–20 px замість 50 px вихідника);
  * окремо ріже середню пластину верхнього краю й ставить у неї бурштинову лінзу —
    це рідкісний «техно-артефакт», який ставиться лише на головні вікна.
Результат і поля nine-patch (у пікселях результату) пишуться в comic_ui.json поруч із картинками.
"""
import io
import json
import math
import os
import sys
import zipfile

from PIL import Image, ImageDraw, ImageFilter

NAMES = ["dialogue_panel", "button", "health_frame", "inventory_slot", "portrait_panel", "ribbon"]

# Темна палітра (ті самі значення — в ui/comic_ui.gd).
COAL = (27, 26, 30)          # нутро панелей
STEEL_MUL = (0.55, 0.58, 0.64)  # сталь темніша й холодніша
AMBER = (255, 176, 48)       # бурштин — колір техно-артефакту


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
    """Пергамент → вугілля (зі збереженням штрихування), сталь → темний метал."""
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
                d = (lum(p) - 222.0) * 0.45  # штрихування й плями пергаменту — легкі брижі на вугіллі
                po[x, y] = (clamp(COAL[0] + d), clamp(COAL[1] + d), clamp(COAL[2] + d * 1.1), p[3])
            elif is_steel(p):
                po[x, y] = (clamp(p[0] * STEEL_MUL[0]), clamp(p[1] * STEEL_MUL[1]), clamp(p[2] * STEEL_MUL[2]), p[3])
            elif is_rust(p):
                po[x, y] = (clamp(p[0] * 0.8), clamp(p[1] * 0.72), clamp(p[2] * 0.7), p[3])
    return out


def clamp(v):
    return max(0, min(255, int(round(v))))


def defect(im, box):
    """Скільки в шматку краю іржі й сколів пергаменту (менше — чистіше)."""
    px = im.load()
    n = 0
    for y in range(box[1], box[3]):
        for x in range(box[0], box[2]):
            p = px[x, y]
            if is_rust(p) or is_parchment(p):
                n += 1
    return n


def best_strip(im, horizontal, lo, hi, thick, s):
    """Найчистіша смуга завширшки s уздовж краю між lo і hi."""
    best, best_at = None, lo
    for a in range(lo, hi - s):
        box = (a, 0, a + s, thick) if horizontal else (0, a, thick, a + s)
        d = defect(im, box)
        if best is None or d < best:
            best, best_at = d, a
    return best_at


def nine_patch(src, cx, cy, s=6):
    """Нова картинка: кути cx×cy з вихідника, краї — чисті смуги завширшки s, середина — вугілля."""
    w, h = src.size
    out = Image.new("RGBA", (2 * cx + s, 2 * cy + s), (0, 0, 0, 0))
    # кути
    out.paste(src.crop((0, 0, cx, cy)), (0, 0))
    out.paste(src.crop((w - cx, 0, w, cy)), (cx + s, 0))
    out.paste(src.crop((0, h - cy, cx, h)), (0, cy + s))
    out.paste(src.crop((w - cx, h - cy, w, h)), (cx + s, cy + s))
    # краї: шукаємо чистий шматок між кутом і середньою пластиною (пластина біля середини)
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
    """Середня пластина верхнього краю + бурштинова лінза на місці заклепки."""
    w, h = src_dark.size
    # пластина — непрозора ділянка згори посередині, вище за край рамки
    plate = src_dark.crop((w // 2 - 70, 0, w // 2 + 70, 62))
    pw, ph = plate.size
    # стираємо все, що нижче за пластину (нутро панелі), залишаючи саму пластину
    pp = plate.load()
    for y in range(ph):
        for x in range(pw):
            p = pp[x, y]
            if p[3] and lum(p) < 40 and abs(p[0] - COAL[0]) < 14 and abs(p[2] - COAL[2]) < 14 and y > 30:
                pp[x, y] = (0, 0, 0, 0)
    d = ImageDraw.Draw(plate)
    c = (pw // 2, 26)
    r = 13
    # гніздо й лінза
    d.ellipse((c[0] - r - 4, c[1] - r - 4, c[0] + r + 4, c[1] + r + 4), fill=(14, 14, 16, 255))
    d.ellipse((c[0] - r - 1, c[1] - r - 1, c[0] + r + 1, c[1] + r + 1), fill=(70, 74, 82, 255))
    glow = Image.new("RGBA", plate.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    for i in range(r, 0, -1):
        t = i / r
        col = (clamp(AMBER[0] * (1.0 - 0.15 * t)), clamp(AMBER[1] * (1.15 - 0.55 * t)), clamp(AMBER[2] * (1.6 - 1.2 * t)), 255)
        gd.ellipse((c[0] - i, c[1] - i, c[0] + i, c[1] + i), fill=col)
    gd.ellipse((c[0] - 5, c[1] - 7, c[0] + 1, c[1] - 2), fill=(255, 240, 200, 230))  # відблиск
    plate = Image.alpha_composite(plate, glow)
    d = ImageDraw.Draw(plate)
    d.ellipse((c[0] - r - 1, c[1] - r - 1, c[0] + r + 1, c[1] + r + 1), outline=(10, 10, 10, 255), width=3)
    # дві «жили» від лінзи по пластині — техніка, а не прикраса
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
    K = 0.36  # масштаб: рамка вихідника ~50 px → ~18 px на екрані

    def put(name, im, margins=None, content=None):
        im.save(os.path.join(dst, name + ".png"))
        meta[name] = {"size": list(im.size)}
        if margins:
            meta[name]["margin"] = margins
        if content:
            meta[name]["content"] = content

    # панель вікна
    cx, cy = 82, 74
    np_ = scaled(nine_patch(dark["dialogue_panel"], cx, cy), K)
    m = [round(cx * K), round(cy * K)]
    put("panel", np_, m, [round(60 * K) + 4, round(52 * K) + 4])
    # кнопка: тонка рамка, окремо — натиснута (світліша лінія) робиться модуляцією в коді
    bx, by = 74, 64
    BK = 0.22
    put("button", scaled(nine_patch(dark["button"], bx, by), BK), [round(bx * BK), round(by * BK)], [round(66 * BK) + 4, round(52 * BK) - 2])
    # комірка інвентарю
    sx, sy = 70, 70
    put("slot", scaled(nine_patch(dark["inventory_slot"], sx, sy), 0.3), [round(sx * 0.3), round(sy * 0.3)], [round(56 * 0.3), round(56 * 0.3)])
    # рамка портрета / ляльки
    qx, qy = 70, 72
    put("portrait", scaled(nine_patch(dark["portrait_panel"], qx, qy), K), [round(qx * K), round(qy * K)], [round(56 * K) + 2, round(58 * K) + 2])
    # рамка шкали (усередині й так темна): краї по горизонталі
    hb = dark["health_frame"]
    hx = 60
    hw, hh = hb.size
    strip = hb.crop((hx, 0, hx + 6, hh))
    bar = Image.new("RGBA", (2 * hx + 6, hh), (0, 0, 0, 0))
    bar.paste(hb.crop((0, 0, hx, hh)), (0, 0))
    bar.paste(strip, (hx, 0))
    bar.paste(hb.crop((hw - hx, 0, hw, hh)), (hx + 6, 0))
    put("bar", scaled(bar, 0.2), [round(hx * 0.2), round(hh * 0.2 * 0.5) - 1], [round(46 * 0.2), round(38 * 0.2)])
    # стрічка (заголовок / мітка) — без розтягування
    put("ribbon", scaled(dark["ribbon"], 0.18))
    # техно-пластина з бурштиновою лінзою
    put("tech_plate", tech_plate(dark["dialogue_panel"], K + 0.06))
    with open(os.path.join(dst, "comic_ui.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=1)
    print(json.dumps(meta, ensure_ascii=False))


if __name__ == "__main__":
    main()

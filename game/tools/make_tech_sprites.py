#!/usr/bin/env python3
"""Спрайты техно-артефактов (Q31 B, Huzzah 2026-10-27): остов машины, сигнальная вышка, купол-люк.

python3 tools/make_tech_sprites.py [game/art/storybook]

Рисуются кодом в манере комикс-набора: толстый чёрный контур, плоские заливки, тень одним тоном,
штриховка, ржавые пятна, янтарные огни (тот же янтарь, что у линзы интерфейса). Рисуется в 4 раза
крупнее и уменьшается — линии ровные. Опора — низ по центру, фон прозрачный, как у art/storybook.
"""
import math
import os
import random
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

K = 4
INK = (16, 15, 18, 255)
STEEL = (92, 104, 118, 255)
STEEL_D = (58, 66, 78, 255)
STEEL_L = (132, 146, 160, 255)
IRON = (74, 70, 66, 255)
IRON_D = (46, 43, 41, 255)
RUST = (138, 74, 42, 255)
RUST_D = (96, 50, 30, 255)
AMBER = (255, 176, 48, 255)
AMBER_L = (255, 228, 160, 255)
SAND = (168, 146, 104, 255)
SAND_D = (126, 106, 74, 255)
GRASS = (92, 104, 60, 255)


class Pic:
    def __init__(self, w, h, seed):
        self.w, self.h = w * K, h * K
        self.im = Image.new("RGBA", (self.w, self.h), (0, 0, 0, 0))
        self.rnd = random.Random(seed)

    def P(self, pts):
        return [(x * K, y * K) for x, y in pts]

    def poly(self, pts, fill, outline=True, width=3.2):
        d = ImageDraw.Draw(self.im)
        d.polygon(self.P(pts), fill=fill)
        if outline:
            q = self.P(pts)
            d.line(q + [q[0]], fill=INK, width=int(width * K), joint="curve")

    def ellipse(self, box, fill, outline=True, width=3.0):
        d = ImageDraw.Draw(self.im)
        b = [box[0] * K, box[1] * K, box[2] * K, box[3] * K]
        d.ellipse(b, fill=fill, outline=INK if outline else None, width=int(width * K) if outline else 0)

    def line(self, pts, fill=INK, width=2.0):
        ImageDraw.Draw(self.im).line(self.P(pts), fill=fill, width=max(1, int(width * K)), joint="curve")

    def hatch(self, pts, step=6.0, angle=-0.9, fill=(0, 0, 0, 90), width=1.1):
        """Штриховка внутри многоугольника."""
        mask = Image.new("L", self.im.size, 0)
        ImageDraw.Draw(mask).polygon(self.P(pts), fill=255)
        layer = Image.new("RGBA", self.im.size, (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
        r = max(max(xs) - min(xs), max(ys) - min(ys))
        dx, dy = math.cos(angle), math.sin(angle)
        nx, ny = -dy, dx
        t = -r
        while t < r:
            a = (cx + nx * t - dx * r, cy + ny * t - dy * r)
            b = (cx + nx * t + dx * r, cy + ny * t + dy * r)
            d.line([(a[0] * K, a[1] * K), (b[0] * K, b[1] * K)], fill=fill, width=int(width * K))
            t += step
        layer.putalpha(ImageChops.multiply(layer.getchannel("A"), mask))
        self.im.alpha_composite(layer)

    def rust(self, pts, n=4, size=9.0):
        """Ржавые пятна, обрезанные формой."""
        mask = Image.new("L", self.im.size, 0)
        ImageDraw.Draw(mask).polygon(self.P(pts), fill=255)
        layer = Image.new("RGBA", self.im.size, (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        for _ in range(n):
            cx = self.rnd.uniform(min(xs), max(xs))
            cy = self.rnd.uniform(min(ys), max(ys))
            blob = []
            m = 9
            for i in range(m):
                a = i / m * math.tau
                rr = size * self.rnd.uniform(0.45, 1.0)
                blob.append(((cx + math.cos(a) * rr * 1.4) * K, (cy + math.sin(a) * rr) * K))
            d.polygon(blob, fill=RUST)
            d.line(blob + [blob[0]], fill=RUST_D, width=int(1.2 * K))
        layer.putalpha(ImageChops.multiply(layer.getchannel("A"), mask))
        self.im.alpha_composite(layer)

    def lamp(self, cx, cy, r, lit=True):
        self.ellipse((cx - r - 1.5, cy - r - 1.5, cx + r + 1.5, cy + r + 1.5), INK, outline=False)
        if lit:
            glow = Image.new("RGBA", self.im.size, (0, 0, 0, 0))
            ImageDraw.Draw(glow).ellipse([(cx - r * 3) * K, (cy - r * 3) * K, (cx + r * 3) * K, (cy + r * 3) * K], fill=(255, 170, 40, 90))
            glow = glow.filter(ImageFilter.GaussianBlur(r * K * 1.2))
            self.im.alpha_composite(glow)
            self.ellipse((cx - r, cy - r, cx + r, cy + r), AMBER, outline=False)
            self.ellipse((cx - r * 0.55, cy - r * 0.75, cx + r * 0.05, cy - r * 0.15), AMBER_L, outline=False)
        else:
            self.ellipse((cx - r, cy - r, cx + r, cy + r), (70, 52, 30, 255), outline=False)
            self.ellipse((cx - r * 0.55, cy - r * 0.75, cx, cy - r * 0.2), (130, 96, 50, 255), outline=False)

    def ground(self, cx, cy, rx, ry):
        """Подсыпка песка и трава у основания (как у спрайтов набора)."""
        pts = []
        for i in range(24):
            a = i / 24 * math.tau
            rr = self.rnd.uniform(0.85, 1.05)
            pts.append((cx + math.cos(a) * rx * rr, cy + math.sin(a) * ry * rr))
        ImageDraw.Draw(self.im).polygon(self.P(pts), fill=SAND)
        self.hatch(pts, step=7, angle=0.15, fill=(90, 70, 40, 70), width=1.0)
        for _ in range(7):
            x = cx + self.rnd.uniform(-rx * 0.9, rx * 0.9)
            y = cy + self.rnd.uniform(-ry * 0.3, ry * 0.6)
            self.grass(x, y)

    def grass(self, x, y):
        for k in range(4):
            a = -math.pi / 2 + (k - 1.5) * 0.35
            self.line([(x + (k - 1.5) * 1.6, y), (x + (k - 1.5) * 1.6 + math.cos(a) * 7, y + math.sin(a) * 9)], fill=GRASS, width=1.6)

    def stones(self, cx, cy, n, spread):
        for _ in range(n):
            x = cx + self.rnd.uniform(-spread, spread)
            y = cy + self.rnd.uniform(-spread * 0.2, spread * 0.25)
            s = self.rnd.uniform(4, 9)
            pts = [(x - s, y), (x - s * 0.7, y - s * 0.7), (x + s * 0.2, y - s * 0.9), (x + s, y - s * 0.3), (x + s * 0.8, y + s * 0.2)]
            self.poly(pts, (128, 124, 116, 255), width=1.8)

    def save(self, path, out_h):
        im = self.im.resize((self.w // K, self.h // K), Image.LANCZOS)
        bb = im.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
        im = im.crop((max(0, bb[0] - 4), max(0, bb[1] - 4), min(im.size[0], bb[2] + 4), min(im.size[1], bb[3] + 4)))
        k = out_h / im.size[1]
        im = im.resize((round(im.size[0] * k), out_h), Image.LANCZOS)
        im.save(path)
        return im.size


def wreck(path):
    """Остов шагающей машины: корпус-котёл, ржавые панели, огромная шестерня, трубы, погасший глаз."""
    p = Pic(520, 340, 31)
    p.ground(260, 300, 235, 34)
    # отломанная нога-опора сзади
    p.poly([(330, 300), (352, 150), (380, 140), (392, 158), (372, 300)], IRON)
    p.hatch([(330, 300), (352, 150), (380, 140), (392, 158), (372, 300)], step=7, angle=-1.2)
    p.poly([(392, 158), (450, 118), (470, 132), (402, 182)], IRON_D)
    # шестерня
    cx, cy, R = 150, 205, 82
    teeth = []
    for i in range(32):
        a = i / 32 * math.tau
        rr = R if (i // 2) % 2 == 0 else R - 13
        teeth.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    p.poly(teeth, IRON)
    p.rust(teeth, n=3, size=14)
    p.ellipse((cx - 50, cy - 50, cx + 50, cy + 50), IRON_D)
    for i in range(6):
        a = i / 6 * math.tau + 0.3
        p.line([(cx + math.cos(a) * 14, cy + math.sin(a) * 14), (cx + math.cos(a) * 48, cy + math.sin(a) * 48)], fill=IRON, width=9)
    p.ellipse((cx - 16, cy - 16, cx + 16, cy + 16), STEEL_D)
    # корпус-котёл, наполовину в песке
    hull = [(160, 300), (170, 180), (200, 140), (260, 118), (330, 120), (378, 146), (396, 196), (392, 300)]
    p.poly(hull, STEEL)
    shade = [(300, 300), (330, 121), (378, 146), (396, 196), (392, 300)]
    p.poly(shade, STEEL_D, outline=False)
    p.hatch(shade, step=6, angle=-0.95)
    p.rust(hull, n=6, size=12)
    p.line(hull + [hull[0]], width=3.4)
    # швы и заклёпки панелей
    for y in (170, 215, 260):
        p.line([(172, y), (392, y + 6)], width=1.8)
    for x in range(186, 390, 22):
        for y in (176, 221, 266):
            p.ellipse((x - 2.6, y - 2.6 + (x - 186) * 0.03, x + 2.6, y + 2.6 + (x - 186) * 0.03), STEEL_L, width=1.2)
    # вырванная панель, видна рёбра
    hole = [(210, 230), (226, 196), (262, 192), (270, 228), (246, 252)]
    p.poly(hole, (22, 20, 24, 255))
    for x in (228, 242, 256):
        p.line([(x, 200), (x - 6, 246)], fill=IRON, width=4)
    # кабина-глаз с погасшей янтарной линзой
    p.poly([(250, 124), (262, 92), (318, 88), (334, 122)], STEEL_L)
    p.hatch([(250, 124), (262, 92), (318, 88), (334, 122)], step=8, angle=-0.6, fill=(0, 0, 0, 60))
    p.lamp(291, 108, 11, lit=False)
    # трубы
    p.poly([(352, 128), (360, 70), (378, 66), (384, 72), (372, 136)], IRON)
    p.poly([(356, 70), (360, 52), (386, 52), (382, 70)], RUST)
    p.line([(170, 260), (120, 268), (96, 292)], fill=INK, width=9)
    p.line([(170, 260), (120, 268), (96, 292)], fill=RUST_D, width=5)
    p.stones(300, 304, 6, 150)
    return p.save(path, 300)


def tower(path):
    """Сигнальная вышка: решётчатая мачта, наклонённая, с антенной-тарелкой и живым янтарным огнём."""
    p = Pic(300, 620, 47)
    p.ground(150, 586, 110, 22)
    # бетонное основание
    p.poly([(92, 590), (98, 552), (202, 552), (208, 590)], (120, 116, 108, 255))
    p.hatch([(92, 590), (98, 552), (202, 552), (208, 590)], step=7)
    # мачта (лёгкий наклон)
    lean = 0.06
    def X(x, y):
        return x + (560 - y) * lean
    left = [(X(108, 556), 556), (X(136, 120), 120)]
    right = [(X(192, 556), 556), (X(164, 120), 120)]
    for a, b in ((left[0], left[1]), (right[0], right[1])):
        p.line([a, b], width=13)
        p.line([a, b], fill=STEEL, width=7.5)
    y = 556
    side = 0
    while y > 140:
        y2 = y - 52
        t1 = (y - 120) / 436
        t2 = (y2 - 120) / 436
        xl1, xr1 = X(136 - 28 * t1, y), X(164 + 28 * t1, y)
        xl2, xr2 = X(136 - 28 * t2, y2), X(164 + 28 * t2, y2)
        p.line([(xl1, y), (xr1, y)], width=7)
        p.line([(xl1, y), (xr1, y)], fill=STEEL_D, width=3.6)
        a, b = ((xl1, y), (xr2, y2)) if side == 0 else ((xr1, y), (xl2, y2))
        p.line([a, b], width=6)
        p.line([a, b], fill=STEEL_D, width=3)
        side ^= 1
        y = y2
    # ржавая табличка и оборванный кабель
    p.poly([(X(150, 420), 400), (X(186, 400), 396), (X(186, 400), 424), (X(150, 420), 428)], RUST)
    p.line([(X(138, 300), 300), (60, 360), (40, 470), (70, 584)], fill=INK, width=4.5)
    p.line([(X(138, 300), 300), (60, 360), (40, 470), (70, 584)], fill=(40, 38, 44, 255), width=2.4)
    # площадка и тарелка
    p.poly([(X(112, 126), 126), (X(188, 126), 126), (X(184, 112), 112), (X(116, 112), 112)], IRON)
    dish = [(X(104, 92), 98), (X(146, 34), 30), (X(214, 58), 54), (X(206, 110), 106)]
    p.poly(dish, STEEL_L)
    p.hatch(dish, step=7, angle=-0.5, fill=(0, 0, 0, 70))
    p.rust(dish, n=2, size=8)
    p.line([(X(160, 112), 112), (X(170, 74), 72)], width=3)
    # антенна и огонь
    p.line([(X(140, 112), 112), (X(132, 20), 18)], width=4)
    p.line([(X(140, 112), 112), (X(132, 20), 18)], fill=STEEL, width=2)
    p.lamp(X(132, 16), 14, 7.5, lit=True)
    p.stones(150, 590, 4, 70)
    return p.save(path, 600)


def dome(path):
    """Купол-люк древного бункера: треснувший металл, гермодверь, янтарный индикатор."""
    p = Pic(440, 300, 59)
    p.ground(220, 262, 200, 30)
    body = []
    for i in range(0, 37):
        a = math.pi + i / 36 * math.pi
        body.append((220 + math.cos(a) * 170, 262 + math.sin(a) * 170 * 0.78))
    p.poly(body, STEEL)
    shade = [(220 + math.cos(a) * 170, 262 + math.sin(a) * 133) for a in [math.pi * 1.5 + k / 18 * math.pi * 0.5 for k in range(19)]] + [(220, 262)]
    p.poly(shade, STEEL_D, outline=False)
    p.hatch(shade, step=6, angle=-0.9)
    p.rust(body, n=6, size=13)
    p.line(body, width=3.4)
    # рёбра купола
    for t in (-0.6, -0.2, 0.2, 0.6):
        pts = [(220 + t * 170 * math.sqrt(max(0.0, 1 - s * s)) , 262 - s * 133) for s in [k / 10 for k in range(11)]]
        p.line(pts, width=2)
    # трещина
    p.line([(270, 150), (282, 176), (276, 196), (296, 226)], width=3)
    # гермодверь
    door = [(170, 262), (172, 196), (186, 178), (254, 178), (268, 196), (270, 262)]
    p.poly(door, IRON)
    p.hatch(door, step=8, angle=-1.3, fill=(0, 0, 0, 80))
    p.ellipse((206, 206, 234, 234), IRON_D, width=2.4)
    for i in range(4):
        a = i / 4 * math.tau + 0.4
        p.line([(220, 220), (220 + math.cos(a) * 18, 220 + math.sin(a) * 18)], width=3.2)
    p.lamp(286, 188, 7, lit=True)
    # торчащая труба-перископ
    p.poly([(120, 168), (126, 108), (142, 108), (144, 172)], IRON)
    p.poly([(116, 112), (122, 92), (156, 92), (150, 112)], RUST)
    p.stones(220, 268, 7, 170)
    return p.save(path, 280)


def main():
    dst = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "art", "storybook")
    os.makedirs(dst, exist_ok=True)
    for name, f in (("tech_wreck", wreck), ("tech_tower", tower), ("tech_dome", dome)):
        print(name, f(os.path.join(dst, name + ".png")))


if __name__ == "__main__":
    main()

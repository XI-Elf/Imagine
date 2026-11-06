#!/usr/bin/env python3
"""Обзор региона (Huzzah 2026-11-04): список картинок, заглушки, manifest.json и промпты.

python3 tools/make_region_art.py [game]

Один источник правды — список ASSETS ниже. Скрипт:
  1. рисует заглушки в game/art/region/ (из спрайтов art/storybook или кодом), точно нужного размера;
  2. пишет game/art/region/manifest.json — его читает игра (world/region_art.gd): файл, размер, точка опоры,
     высота на экране 1080 px;
  3. пишет docs/region_art/АССЕТЫ.md, assets.csv и prompts.txt — список для генерации в другой нейросети.
Готовую картинку с тем же именем и размером кладут вместо заглушки (в game/art/region/ или в папку
region_art/ рядом с exe) — код править не нужно.
"""
import csv
import json
import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..")
OUT = os.path.join(ROOT, "art", "region")
SB = os.path.join(ROOT, "art", "storybook")
DOCS = os.path.join(ROOT, "..", "docs", "region_art")

# Стиль-якорь — единый для всех картинок игры: /mnt/project-files/amber2d/style/prompt_style_25d.md (тред стиля).
# При расхождениях правится тот файл, а здесь — копия якоря.
STYLE = (
    "Game asset in a unified 2.5D style, close to realism: physically based painted look, semi-realistic proportions, "
    "believable materials (worn leather, dull iron, rough wool, weathered wood, cracked stone, corroded alloy). "
    "Slightly top-down three-quarter view, camera about 35 to 40 degrees above the horizon, same angle for every asset, "
    "subject centered with a little margin. Soft directional light from the upper left, gentle ambient occlusion, subtle rim light. "
    "Dark sci-fi fantasy setting: medieval European world with remnants of lost technology. Muted desaturated palette "
    "(ash grey, mud brown, dark olive, rust, cold steel blue), small accents of amber glow only on technology and amber stones. "
    "Fine surface detail, scratches, dust, wear, no cartoon outlines, no cel shading, no pixel art, no glossy plastic, no neon, "
    "no text, no watermark, no logo."
)
NEGATIVE = ("cartoon, comic outline, cel shading, anime, pixel art, flat vector, oversaturated colors, neon, glossy plastic, "
            "text, letters, watermark, logo, frame, border, multiple objects, cropped subject, extreme perspective, fisheye, "
            "blur, low detail, modern clothing, guns, cars")
VIEW_OBJ = ("Seen as a miniature on a painted regional map: three-quarter top view, the same 35-40 degree camera, "
            "ground footprint visible, the object stands up and shows its front and roof or top")
VIEW_TOP = ("seamless tileable top-down terrain texture, no objects, even lighting, no shadows from outside, "
            "edges wrap perfectly")
OBJ_TAIL = ("Single isolated object, centered horizontally, its base (where it touches the ground) at the bottom centre "
            "of the canvas, transparent background (PNG with alpha), no ground plane and NO cast shadow on the ground "
            "(the game draws the shadow to the lower right itself)")
# kind: object — стоит на земле (опора anchor), ground — плоская бесшовная текстура, overlay — полупрозрачный слой, ui
# h — высота на экране 1080 px при масштабе «весь регион» (для зданий — 0: размер по участку плана города)
ASSETS = [
    # ---- лес и растения
    dict(key="tree_pine", size=(192, 256), kind="object", h=24, src="proc:pine",
         what="Тёмная ель/сосна, основной лес", dyn="лес (биом 3); вырубается тропами",
         prompt="a dark conifer pine tree, dense needle crown, deep green with cold blue shadows"),
    dict(key="tree_broad", size=(224, 224), kind="object", h=22, src="tree_oak",
         what="Лиственное дерево (дуб)", dyn="лес, берега рек",
         prompt="a broad deciduous oak tree, rounded dark olive crown, thick trunk"),
    dict(key="tree_light", size=(192, 224), kind="object", h=22, src="tree_light",
         what="Светлое лиственное дерево (берёза)", dyn="опушки, луга",
         prompt="a slender birch-like tree with light trunk and sparse yellow-green crown"),
    dict(key="tree_cursed", size=(224, 224), kind="object", h=22, src="tree_crooked:cursed",
         what="Кривое дерево проклятого леса", dyn="проклятый лес (биом 7)",
         prompt="a twisted cursed tree with violet-tinted bark, sickly purple leaves and a faint amber glow in cracks"),
    dict(key="tree_dead", size=(224, 224), kind="object", h=18, src="tree_crooked:dead",
         what="Сухое мёртвое дерево", dyn="болота, пустоши (биомы 4, 5, 9)",
         prompt="a dead leafless crooked tree, grey bleached branches"),
    dict(key="reed", size=(128, 96), kind="object", h=9, src="proc:reed",
         what="Камыш на болоте", dyn="болото (биомы 5, 9)",
         prompt="a clump of swamp reeds and cattails, dull ochre and green"),
    dict(key="rock", size=(160, 128), kind="object", h=9, src="rock",
         what="Валуны", dyn="пустошь, берег",
         prompt="a small group of grey boulders with moss"),
    # ---- горы
    dict(key="mountain_a", size=(384, 288), kind="object", h=70, src="mountain_gray",
         what="Гора серая", dyn="горы (биом 6) и горная рамка вокруг региона",
         prompt="a jagged dark grey rocky mountain with steep cliffs and sparse snow on top"),
    dict(key="mountain_b", size=(384, 320), kind="object", h=86, src="peak_gray",
         what="Высокий пик", dyn="высокие горы (по карте высот)",
         prompt="a tall sharp mountain peak, dark slate rock, cold highlights"),
    dict(key="ridge", size=(448, 192), kind="object", h=44, src="ridge_gray",
         what="Горный хребет низкий", dyn="предгорья",
         prompt="a low long rocky ridge, dark grey stone"),
    dict(key="mountain_hot", size=(384, 288), kind="object", h=66, src="mountain_hot",
         what="Спекотная (рыжая) гора", dyn="жаркие горы (map_hot)",
         prompt="a rust-orange scorched mountain, cracked red rock, heat-blasted"),
    dict(key="mesa_hot", size=(384, 224), kind="object", h=50, src="mesa_hot",
         what="Столовая гора рыжая", dyn="жаркие горы",
         prompt="a flat-topped red sandstone mesa, scorched"),
    # ---- руины и техноруины
    dict(key="ruin_temple", size=(256, 256), kind="object", h=30, src="temple:ruin",
         what="Руины храма", dyn="руины в пустоши/лесу; обысканные — темнее",
         prompt="a ruined stone chapel with collapsed roof, broken bell tower, overgrown"),
    dict(key="ruin_hall", size=(256, 256), kind="object", h=30, src="hall:ruin",
         what="Руины зала в лесу", dyn="руины в проклятом лесу",
         prompt="a ruined stone hall half swallowed by roots, broken arches"),
    dict(key="tech_wreck", size=(256, 160), kind="object", h=22, src="tech_wreck",
         what="Остов древней машины", dyn="проклятая пустошь (биом 8)",
         prompt="a wreck of an ancient giant machine, rusted steel hull, broken gears, one faint amber lens"),
    dict(key="tech_dome", size=(256, 144), kind="object", h=20, src="tech_dome",
         what="Купол-бункер", dyn="проклятая пустошь",
         prompt="a half-buried ancient metal dome bunker with a hatch and amber lights"),
    dict(key="tech_tower", size=(128, 320), kind="object", h=46, src="tech_tower",
         what="Сигнальная вежа (на неё можно залезть)", dyn="редкие точки суши",
         prompt="a tall ancient lattice signal tower of rusted steel with a glowing amber beacon on top"),
    # ---- город (по этапам роста)
    dict(key="bld_house", size=(256, 208), kind="object", h=0, src="house", stages=True,
         what="Жилой дом", dyn="появляется с этапом роста города",
         prompt="a small medieval timber house with steep roof and chimney"),
    dict(key="bld_hall", size=(256, 256), kind="object", h=0, src="hall", stages=True,
         what="Чертог олдермена", dyn="центр города",
         prompt="the town hall of the alderman, two storeys, banner, stone base"),
    dict(key="bld_temple", size=(256, 256), kind="object", h=0, src="temple", stages=True,
         what="Храм Светлого Огня", dyn="с этапа, где он построен",
         prompt="a stone temple with a bell tower and an amber flame lantern"),
    dict(key="bld_inn", size=(256, 224), kind="object", h=0, src="inn", stages=True,
         what="Таверна", dyn="этапы роста",
         prompt="a two-storey tavern with balcony, sign post and warm windows"),
    dict(key="bld_shop", size=(256, 208), kind="object", h=0, src="stall:shop", stages=True,
         what="Лавка", dyn="этапы роста",
         prompt="a merchant shop with awning and crates"),
    dict(key="bld_healer", size=(256, 208), kind="object", h=0, src="healer:house", stages=True,
         what="Дом травницы", dyn="этапы роста",
         prompt="a herbalist cottage with drying herbs and a small garden"),
    dict(key="bld_smithy", size=(256, 224), kind="object", h=0, src="smithy", stages=True,
         what="Кузница", dyn="этапы роста",
         prompt="a blacksmith forge with open side, anvil, smoke from chimney"),
    dict(key="bld_ruin", size=(256, 208), kind="object", h=0, src="house:ruin",
         what="Развалины внутри стен", dyn="разрушенные дома города",
         prompt="a burnt collapsed house, charred beams"),
    dict(key="prop_stall", size=(192, 160), kind="object", h=0, src="stall",
         what="Торговая палатка", dyn="рыночная площадь",
         prompt="a market stall with cloth canopy"),
    dict(key="prop_well", size=(128, 128), kind="object", h=0, src="well",
         what="Колодец", dyn="площадь",
         prompt="a stone well with wooden roof"),
    dict(key="wall_palisade", size=(128, 112), kind="object", h=0, src="proc:palisade",
         what="Отрезок частокола", dyn="стена города, пока она деревянная (этапы Форт…Город)",
         prompt="a short straight segment of a wooden palisade wall of sharpened logs"),
    dict(key="wall_stone", size=(128, 112), kind="object", h=0, src="proc:stonewall",
         what="Отрезок каменной стены", dyn="стена города после перестройки в камень",
         prompt="a short straight segment of a crenellated stone city wall"),
    dict(key="tower_wood", size=(96, 176), kind="object", h=0, src="proc:towerwood",
         what="Деревянная башня частокола", dyn="башни стены (деревянная стена)",
         prompt="a wooden watchtower on log legs with a small roof"),
    dict(key="tower_stone", size=(96, 176), kind="object", h=0, src="proc:towerstone",
         what="Каменная башня стены", dyn="башни стены (каменная стена)",
         prompt="a round stone wall tower with conical slate roof"),
    dict(key="gate_wood", size=(160, 160), kind="object", h=0, src="proc:gatewood",
         what="Ворота частокола", dyn="ворота (деревянная стена)",
         prompt="a wooden palisade gatehouse with double gate"),
    dict(key="gate_stone", size=(160, 160), kind="object", h=0, src="proc:gatestone",
         what="Каменные ворота", dyn="ворота (каменная стена)",
         prompt="a stone gatehouse with two towers and an arched gate"),
    dict(key="scaffold", size=(192, 176), kind="object", h=0, src="proc:scaffold",
         what="Стройка: леса и сруб", dyn="здания следующего этапа, пока к нему идут задания",
         prompt="a building under construction: wooden scaffolding, half-built timber frame, stacked logs and a crane"),
    dict(key="hero", size=(128, 160), kind="object", h=30, src="proc:hero",
         what="Знак героя на карте", dyn="где сейчас герой",
         prompt="a small heraldic map pin: an amber flag on a pole with a dark circular base, clearly readable"),
    # ---- плоское
    dict(key="field", size=(256, 256), kind="ground", h=0, src="proc:field",
         what="Пашня (бесшовно)", dyn="поля города",
         prompt="crop field rows, ochre and olive"),
    dict(key="city_ground", size=(256, 256), kind="ground", h=0, src="proc:cityground",
         what="Утоптанная земля внутри стен (бесшовно)", dyn="площадь и улицы города",
         prompt="trampled earth and cobble patches of a medieval town ground"),
    # ---- слои
    dict(key="shadow", size=(128, 64), kind="overlay", h=0, src="proc:shadow",
         what="Мягкая тень под объектом", dyn="под каждым объектом",
         prompt="a soft blurred black ellipse shadow, alpha gradient, nothing else"),
    dict(key="mist", size=(256, 192), kind="overlay", h=70, src="proc:mist",
         what="Клуб ядовитого тумана", dyn="болота и проклятые земли, медленно плывёт",
         prompt="a soft semi-transparent puff of drifting mist, white-grey (the game tints it violet or green)"),
    dict(key="fog_clouds", size=(512, 512), kind="overlay", h=0, src="proc:fog",
         what="Облака тумана войны (бесшовно)", dyn="закрывает неисследованное, исчезает, когда герой там прошёл",
         prompt="seamless tileable painted clouds, white on transparent, soft volumes with darker undersides"),
    dict(key="title_plate", size=(1024, 192), kind="ui", h=0, src="proc:plate",
         what="Табличка с названием региона", dyn="заголовок обзора",
         prompt="an empty horizontal plaque of dark weathered metal riveted onto a wooden board, amber trim, empty centre for text"),
]

# Для плиток из якоря убраны фразы про ракурс и свет (правило файла стиля)
STYLE_TILE = " ".join(x for x in STYLE.split(". ") if "view" not in x and "light" not in x).rstrip(".") + "."

TERRAIN = [
    ("t00_water", "вода (море, озёра, реки)", "dark teal water with soft ripples"),
    ("t01_coast", "берег", "wet sand and pebbles"),
    ("t02_forest", "лесная подстилка", "forest floor of moss and needles"),
    ("t03_field1", "луг 1", "meadow grass, olive"),
    ("t04_field2", "луг 2", "meadow grass with wildflowers, muted"),
    ("t05_wasteland", "пустошь", "dry cracked wasteland soil with sparse dead grass"),
    ("t06_swamp", "болото", "swamp mud with puddles and moss"),
    ("t07_mountains", "горы (каменистая земля)", "grey rocky scree ground"),
    ("t08_hot_mountains", "жаркие горы", "scorched red rock ground with cracks"),
    ("t09_rad_forest", "проклятый лес (подстилка)", "violet-tinted sick moss ground"),
    ("t10_rad_wasteland", "проклятая пустошь", "ash-grey poisoned soil with faint violet stains"),
    ("t11_rad_swamp", "проклятое болото", "poisoned dark swamp with violet sheen"),
    ("t12_glow", "маска свечения (чёрно-белая)", "black texture with a few small glowing amber specks (glow mask)"),
]

STAGE_NAMES = ["Форт", "Деревня", "Бург", "Город", "Крупный город"]
STAGE_PROMPTS = [
    "very poor and rough: rough logs, patched roof, mud",
    "simple village quality: timber and thatch",
    "solid burgh quality: timber frame on stone base, tiled roof",
    "prosperous town quality: plastered walls, slate roof, small banner",
    "rich city quality: stone and timber, carved details, amber lanterns",
]

INK = (18, 16, 18, 255)


def grade(im, kind=""):
    """Тёмная палитра проекта: меньше насыщенности, темнее."""
    rgb = im.convert("RGBA")
    a = rgb.getchannel("A")
    c = ImageEnhance.Color(rgb.convert("RGB")).enhance(0.72)
    c = ImageEnhance.Brightness(c).enhance(0.86)
    if kind == "cursed":
        c = Image.blend(c, Image.new("RGB", c.size, (96, 60, 130)), 0.28)
    elif kind == "dead":
        c = ImageEnhance.Color(c).enhance(0.2)
        c = Image.blend(c, Image.new("RGB", c.size, (120, 112, 100)), 0.25)
    elif kind == "ruin":
        c = ImageEnhance.Color(c).enhance(0.35)
        c = ImageEnhance.Brightness(c).enhance(0.8)
    out = c.convert("RGBA")
    out.putalpha(a)
    return out


def ruin_cut(im, seed):
    """Заглушка руины: рваная верхняя кромка и проломы."""
    rnd = random.Random(seed)
    a = im.getchannel("A")
    d = ImageDraw.Draw(a)
    w, h = im.size
    pts = [(0, 0)]
    for i in range(9):
        pts.append((w * i / 8, h * (0.12 + rnd.random() * 0.33)))
    pts += [(w, 0)]
    d.polygon(pts, fill=0)
    for _ in range(3):
        x, y = rnd.uniform(0.2, 0.8) * w, rnd.uniform(0.35, 0.7) * h
        r = rnd.uniform(0.04, 0.08) * w
        d.ellipse([x - r, y - r, x + r, y + r], fill=0)
    im.putalpha(a)
    return im


def fit_sprite(src, size):
    """Спрайт storybook вписывается в холст: низ по центру, поля 6 %."""
    w, h = size
    im = src.copy()
    bbox = im.getbbox()
    if bbox:
        im = im.crop(bbox)
    s = min(w * 0.94 / im.width, h * 0.96 / im.height)
    im = im.resize((max(1, int(im.width * s)), max(1, int(im.height * s))), Image.LANCZOS)
    out = Image.new("RGBA", size, (0, 0, 0, 0))
    out.paste(im, ((w - im.width) // 2, h - im.height - int(h * 0.03)), im)
    return out


def canvas(size, k=4):
    return Image.new("RGBA", (size[0] * k, size[1] * k), (0, 0, 0, 0))


def down(im, size):
    return im.resize(size, Image.LANCZOS)


def proc(name, size, seed):
    rnd = random.Random(seed)
    K = 4
    W, H = size[0] * K, size[1] * K
    im = canvas(size, K)
    d = ImageDraw.Draw(im)
    lw = 3 * K
    if name == "pine":
        cx = W / 2
        d.rectangle([cx - 5 * K, H - 34 * K, cx + 5 * K, H - 6 * K], fill=(64, 44, 30, 255), outline=INK, width=lw)
        tiers = 5
        for i in range(tiers):
            t = i / (tiers - 1)
            y0 = H * (0.06 + 0.15 * i)
            y1 = H * (0.34 + 0.14 * i)
            half = W * (0.16 + 0.22 * t)
            col = (34 + int(10 * t), 58 + int(14 * t), 46 + int(6 * t), 255)
            d.polygon([(cx, y0), (cx + half, y1), (cx - half, y1)], fill=col, outline=INK)
            d.line([(cx, y0), (cx + half, y1)], fill=INK, width=lw)
            d.line([(cx, y0), (cx - half, y1)], fill=INK, width=lw)
            d.line([(cx - half, y1), (cx + half, y1)], fill=INK, width=lw)
            d.polygon([(cx, y0 + 6 * K), (cx - half * 0.7, y1 - 2 * K), (cx - half * 0.15, y1 - 2 * K)], fill=(52, 82, 60, 255))
    elif name == "reed":
        for i in range(14):
            x = W * (0.2 + 0.6 * rnd.random())
            top = H * (0.05 + 0.4 * rnd.random())
            d.line([(x, H * 0.95), (x + rnd.uniform(-8, 8) * K, top)], fill=(110, 104, 58, 255), width=3 * K)
            if rnd.random() < 0.5:
                d.ellipse([x - 3 * K, top, x + 3 * K, top + 12 * K], fill=(84, 52, 34, 255), outline=INK, width=K)
    elif name in ("palisade", "stonewall"):
        if name == "palisade":
            n = 7
            for i in range(n):
                x0 = W * i / n
                x1 = W * (i + 1) / n
                top = H * (0.08 + 0.06 * rnd.random())
                col = (96 + rnd.randint(-10, 10), 70, 46, 255)
                d.polygon([(x0, H * 0.96), (x0, top + 14 * K), ((x0 + x1) / 2, top), (x1, top + 14 * K), (x1, H * 0.96)],
                          fill=col, outline=INK)
                d.line([(x0, H * 0.96), (x0, top + 14 * K)], fill=INK, width=lw)
            d.rectangle([0, H * 0.55, W, H * 0.62], fill=(70, 50, 34, 255), outline=INK, width=K * 2)
        else:
            d.rectangle([0, H * 0.25, W, H * 0.96], fill=(104, 100, 94, 255), outline=INK, width=lw)
            for i in range(4):
                x0 = W * i / 4 + W * 0.03
                d.rectangle([x0, H * 0.06, x0 + W * 0.15, H * 0.27], fill=(118, 114, 106, 255), outline=INK, width=lw)
            for r in range(4):
                y = H * (0.36 + 0.15 * r)
                d.line([(0, y), (W, y)], fill=(70, 68, 64, 255), width=K * 2)
                for c in range(5):
                    x = W * (c / 5 + (0.1 if r % 2 else 0))
                    d.line([(x, y), (x, y + H * 0.15)], fill=(70, 68, 64, 255), width=K * 2)
    elif name in ("towerwood", "towerstone"):
        cx = W / 2
        if name == "towerwood":
            for x in (cx - W * 0.3, cx + W * 0.3):
                d.line([(x, H * 0.97), (cx + (x - cx) * 0.7, H * 0.35)], fill=(84, 60, 40, 255), width=6 * K)
            d.rectangle([cx - W * 0.33, H * 0.22, cx + W * 0.33, H * 0.42], fill=(100, 74, 48, 255), outline=INK, width=lw)
            d.polygon([(cx - W * 0.42, H * 0.24), (cx, H * 0.03), (cx + W * 0.42, H * 0.24)], fill=(70, 52, 40, 255), outline=INK)
        else:
            d.rectangle([cx - W * 0.32, H * 0.3, cx + W * 0.32, H * 0.96], fill=(110, 106, 98, 255), outline=INK, width=lw)
            d.ellipse([cx - W * 0.32, H * 0.9, cx + W * 0.32, H * 0.99], fill=(100, 96, 90, 255), outline=INK, width=lw)
            d.polygon([(cx - W * 0.4, H * 0.32), (cx, H * 0.02), (cx + W * 0.4, H * 0.32)], fill=(58, 64, 78, 255), outline=INK)
            d.rectangle([cx - W * 0.06, H * 0.45, cx + W * 0.06, H * 0.56], fill=(255, 176, 48, 255), outline=INK, width=K)
    elif name in ("gatewood", "gatestone"):
        wood = name == "gatewood"
        body = (98, 72, 46, 255) if wood else (110, 106, 98, 255)
        for x0 in (W * 0.02, W * 0.66):
            d.rectangle([x0, H * 0.18, x0 + W * 0.32, H * 0.96], fill=body, outline=INK, width=lw)
            d.polygon([(x0 - W * 0.03, H * 0.2), (x0 + W * 0.16, H * 0.02), (x0 + W * 0.35, H * 0.2)],
                      fill=(70, 52, 40, 255) if wood else (58, 64, 78, 255), outline=INK)
        d.rectangle([W * 0.3, H * 0.38, W * 0.7, H * 0.96], fill=body, outline=INK, width=lw)
        d.rectangle([W * 0.38, H * 0.55, W * 0.62, H * 0.96], fill=(40, 30, 24, 255), outline=INK, width=lw)
    elif name == "scaffold":
        d.rectangle([W * 0.15, H * 0.5, W * 0.85, H * 0.95], fill=(120, 92, 60, 160), outline=INK, width=lw)
        for i in range(5):
            x = W * (0.12 + 0.19 * i)
            d.line([(x, H * 0.97), (x, H * 0.18)], fill=(150, 116, 70, 255), width=4 * K)
        for y in (0.3, 0.52, 0.74):
            d.line([(W * 0.08, H * y), (W * 0.92, H * y)], fill=(150, 116, 70, 255), width=4 * K)
        d.line([(W * 0.12, H * 0.74), (W * 0.5, H * 0.3)], fill=(130, 100, 60, 255), width=3 * K)
        d.line([(W * 0.88, H * 0.18), (W * 0.88, H * 0.02), (W * 0.55, H * 0.02)], fill=(90, 70, 50, 255), width=4 * K)
        d.line([(W * 0.6, H * 0.02), (W * 0.6, H * 0.25)], fill=INK, width=K)
        for i in range(4):
            y = H * (0.86 - 0.05 * i)
            d.rounded_rectangle([W * 0.62, y, W * 0.95, y + H * 0.05], radius=6 * K, fill=(110, 80, 50, 255), outline=INK, width=K)
    elif name == "hero":
        cx = W / 2
        d.ellipse([cx - W * 0.3, H * 0.86, cx + W * 0.3, H * 0.99], fill=(30, 26, 26, 255), outline=(255, 176, 48, 255), width=lw)
        d.line([(cx, H * 0.92), (cx, H * 0.05)], fill=INK, width=5 * K)
        d.polygon([(cx, H * 0.06), (cx + W * 0.42, H * 0.16), (cx, H * 0.3)], fill=(255, 176, 48, 255), outline=INK)
        d.line([(cx, H * 0.06), (cx + W * 0.42, H * 0.16), (cx, H * 0.3)], fill=INK, width=lw)
    elif name == "shadow":
        sh = Image.new("L", (W, H), 0)
        ImageDraw.Draw(sh).ellipse([W * 0.12, H * 0.18, W * 0.88, H * 0.82], fill=200)
        sh = sh.filter(ImageFilter.GaussianBlur(W * 0.06))
        im = Image.new("RGBA", (W, H), (8, 8, 12, 0))
        im.putalpha(sh)
    elif name == "mist":
        m = Image.new("L", (W, H), 0)
        md = ImageDraw.Draw(m)
        for _ in range(9):
            r = rnd.uniform(0.15, 0.28) * W
            x, y = rnd.uniform(0.3, 0.7) * W, rnd.uniform(0.35, 0.65) * H
            md.ellipse([x - r, y - r * 0.6, x + r, y + r * 0.6], fill=rnd.randint(120, 200))
        m = m.filter(ImageFilter.GaussianBlur(W * 0.07))
        im = Image.new("RGBA", (W, H), (235, 235, 240, 0))
        im.putalpha(m)
    elif name == "fog":
        # бесшовные облака: сумма периодических синусоид + размытые пятна, свернутые по краям
        m = Image.new("L", (W, H), 0)
        md = ImageDraw.Draw(m)
        for _ in range(60):
            r = rnd.uniform(0.06, 0.16) * W
            x, y = rnd.random() * W, rnd.random() * H
            v = rnd.randint(140, 255)
            for ox in (-W, 0, W):
                for oy in (-H, 0, H):
                    md.ellipse([x + ox - r, y + oy - r * 0.75, x + ox + r, y + oy + r * 0.75], fill=v)
        m = m.filter(ImageFilter.GaussianBlur(W * 0.035))
        im = Image.merge("RGBA", (m, m, m, Image.new("L", (W, H), 255)))
        # альфа = светлота, цвет — белый с серым низом
        im = Image.new("RGBA", (W, H), (236, 236, 242, 0))
        im.putalpha(m.point(lambda v: min(255, int(v * 1.2))))
    elif name == "field":
        im = Image.new("RGBA", (W, H), (112, 100, 58, 255))
        d = ImageDraw.Draw(im)
        for i in range(16):
            y = H * i / 16
            d.rectangle([0, y, W, y + H / 32], fill=(88, 92, 50, 255))
    elif name == "cityground":
        im = Image.new("RGBA", (W, H), (98, 86, 68, 255))
        d = ImageDraw.Draw(im)
        for _ in range(140):
            x, y = rnd.random() * W, rnd.random() * H
            r = rnd.uniform(4, 14) * K
            c = rnd.randint(70, 112)
            for ox in (-W, 0, W):
                for oy in (-H, 0, H):
                    d.ellipse([x + ox - r, y + oy - r * 0.7, x + ox + r, y + oy + r * 0.7], fill=(c, c - 8, c - 22, 255))
    elif name == "plate":
        d.rounded_rectangle([2 * K, 10 * K, W - 2 * K, H - 10 * K], radius=22 * K, fill=(58, 42, 30, 240), outline=INK, width=lw)
        d.rounded_rectangle([18 * K, 26 * K, W - 18 * K, H - 26 * K], radius=14 * K, fill=(34, 32, 34, 245),
                            outline=(214, 166, 74, 255), width=lw)
        for x in (32 * K, W - 32 * K):
            for y in (40 * K, H - 40 * K):
                d.ellipse([x - 6 * K, y - 6 * K, x + 6 * K, y + 6 * K], fill=(150, 140, 120, 255), outline=INK, width=K)
    return down(im, size)


def make(a):
    size = tuple(a["size"])
    src = a["src"]
    if src.startswith("proc:"):
        return proc(src[5:], size, hash(a["key"]) & 0xFFFF)
    name, _, mod = src.partition(":")
    im = Image.open(os.path.join(SB, name + ".png")).convert("RGBA")
    im = fit_sprite(im, size)
    if mod == "ruin":
        im = ruin_cut(im, len(a["key"]) * 31)
    return grade(im, mod)


def anchor(a):
    w, h = a["size"]
    if a["kind"] != "object":
        return [w // 2, h // 2]
    return [w // 2, int(h * 0.97)]


def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(DOCS, exist_ok=True)
    manifest = {"_note": "Обзор региона: картинки и их точки опоры. Пишет tools/make_region_art.py; читает world/region_art.gd. "
                "Заменить картинку: тот же файл, тот же размер (или крупнее с теми же пропорциями) — в art/region/ или в "
                "папку region_art/ рядом с exe. Вариант здания по этапу роста города: bld_<вид>_s<этап>.png (необязателен).",
                "style": STYLE, "assets": {}, "terrain": {}}
    rows = []
    for a in ASSETS:
        im = make(a)
        im.save(os.path.join(OUT, a["key"] + ".png"))
        manifest["assets"][a["key"]] = {"file": a["key"] + ".png", "size": list(a["size"]), "anchor": anchor(a),
                                        "kind": a["kind"], "h": a["h"], "stages": bool(a.get("stages"))}
        rows.append(a)
    for t, what, _ in TERRAIN:
        manifest["terrain"][t] = {"file": "terrain/" + t + ".png", "size": [512, 512], "what": what}
    with open(os.path.join(OUT, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=1)
    write_docs()


def view_of(a):
    return {"object": "3/4 сверху (~40°), стоит на земле", "ground": "строго сверху, бесшовно",
            "overlay": "строго сверху, полупрозрачно", "ui": "фронтально"}[a["kind"]]


def alpha_of(a):
    return "нет (непрозрачная плитка)" if a["kind"] == "ground" else "да (PNG с альфой)"


def full_prompt(a, stage=-1):
    if a["kind"] == "object":
        p = a["prompt"]
        if stage >= 0:
            p += ", " + STAGE_PROMPTS[stage]
        return "%s. %s. %s. %s. Canvas %dx%d px." % (p[0].upper() + p[1:], VIEW_OBJ, OBJ_TAIL, STYLE, a["size"][0], a["size"][1])
    if a["kind"] == "ground":
        return "%s. %s. %s Canvas %dx%d px, opaque." % (a["prompt"][0].upper() + a["prompt"][1:], VIEW_TOP, STYLE_TILE, *a["size"])
    if a["kind"] == "overlay":
        return "%s. Seen from straight above, transparent background (PNG alpha). %s Canvas %dx%d px." % (
            a["prompt"][0].upper() + a["prompt"][1:], STYLE.split(". ")[1] + ".", *a["size"])
    return "%s. Front view, transparent background (PNG alpha). %s Canvas %dx%d px." % (
        a["prompt"][0].upper() + a["prompt"][1:], STYLE, *a["size"])


def write_docs():
    lines = []
    lines.append("# Обзор региона — список картинок для генерации\n")
    lines.append("Сгенерировано `game/tools/make_region_art.py`. Все картинки лежат в `game/art/region/` (заглушки). "
                 "Чтобы заменить: сохраните PNG **с тем же именем**, тем же размером (или крупнее в тех же пропорциях) "
                 "и положите в папку `region_art/` рядом с `AmberRegions.exe` (или `AmberWorld.exe`), либо в "
                 "`game/art/region/` исходников. Код менять не нужно: игра сама берёт картинку из `region_art/`, "
                 "если она есть. Террейны — в `region_art/terrain/`.\n")
    lines.append("## Общий стиль (вставлять в начало каждого промпта)\n")
    lines.append("Это копия стиля-якоря игры (`amber2d/style/prompt_style_25d.md`) — один стиль на все картинки.\n")
    lines.append("```\n" + STYLE + "\n```\n")
    lines.append("Негативный промпт (если генератор его принимает):\n")
    lines.append("```\n" + NEGATIVE + "\n```\n")
    lines.append("Совет из файла стиля: первую удачную картинку подавайте дальше как референс стиля, один сид на всю серию.\n")
    lines.append("**Точка опоры** — пиксель картинки, который ставится на точку земли (у объектов — низ по центру, "
                 "где предмет касается земли). Тень игра рисует сама (свет слева сверху, тень вправо вниз), "
                 "поэтому на картинке тени на землю быть не должно.\n")
    lines.append("## Объекты, слои, интерфейс\n")
    lines.append("| Файл | Что | Размер, px | Ракурс | Опора (x, y) | Прозрачность | Высота на экране 1080p | Когда меняется |")
    lines.append("|---|---|---|---|---|---|---|---|")
    for a in ASSETS:
        h = ("%d px" % a["h"]) if a["h"] else ("по участку плана" if a["kind"] == "object" else "—")
        lines.append("| `%s.png` | %s | %d×%d | %s | %s | %s | %s | %s |" % (
            a["key"], a["what"], a["size"][0], a["size"][1], view_of(a), tuple(anchor(a)), alpha_of(a), h, a["dyn"]))
    lines.append("\n### Здания по этапам роста города (необязательно)\n")
    lines.append("Для каждого здания с пометкой «этапы» можно дать свой вид на каждом этапе: `bld_<вид>_s0.png` … "
                 "`bld_<вид>_s4.png` (0 Форт, 1 Деревня, 2 Бург, 3 Город, 4 Крупный город). Размер и опора — как у "
                 "основного файла. Нет файла этапа — берётся основной.\n")
    lines.append("## Террейны (плоские, бесшовные, 512×512, без прозрачности)\n")
    lines.append("Используются и в обычной карте, и в обзоре. В обзор подхватываются из `region_art/terrain/`.\n")
    lines.append("| Файл | Что |")
    lines.append("|---|---|")
    for t, what, _ in TERRAIN:
        lines.append("| `terrain/%s.png` | %s |" % (t, what))
    lines.append("\n## Промпты\n")
    lines.append("Готовые промпты на каждый файл — в `prompts.txt` (один блок на файл), таблица — `assets.csv`.\n")
    with open(os.path.join(DOCS, "АССЕТЫ.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

    with open(os.path.join(DOCS, "prompts.txt"), "w", encoding="utf-8") as f:
        f.write("# Amber Game — обзор региона: промпты для генерации картинок\n")
        f.write("# Общий стиль уже вписан в каждый промпт. Формат: === имя файла (размер) ===\n")
        f.write("# Негативный промпт для всех: " + NEGATIVE + "\n\n")
        for a in ASSETS:
            f.write("=== %s.png (%dx%d) ===\n%s\n\n" % (a["key"], a["size"][0], a["size"][1], full_prompt(a)))
            if a.get("stages"):
                for s in range(5):
                    f.write("=== %s_s%d.png (%dx%d) — этап «%s» ===\n%s\n\n" % (
                        a["key"], s, a["size"][0], a["size"][1], STAGE_NAMES[s], full_prompt(a, s)))
        for t, what, p in TERRAIN:
            f.write("=== terrain/%s.png (512x512) ===\n%s. %s. %s Canvas 512x512 px, opaque.\n\n" % (
                t, p[0].upper() + p[1:], VIEW_TOP, STYLE_TILE))

    with open(os.path.join(DOCS, "assets.csv"), "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f, delimiter=";")
        w.writerow(["file", "what", "width", "height", "view", "anchor_x", "anchor_y", "alpha", "screen_h_1080", "dynamic", "prompt"])
        for a in ASSETS:
            ax, ay = anchor(a)
            w.writerow([a["key"] + ".png", a["what"], a["size"][0], a["size"][1], view_of(a), ax, ay, alpha_of(a),
                        a["h"], a["dyn"], full_prompt(a)])
            if a.get("stages"):
                for s in range(5):
                    w.writerow(["%s_s%d.png" % (a["key"], s), "%s — этап %s" % (a["what"], STAGE_NAMES[s]), a["size"][0],
                                a["size"][1], view_of(a), ax, ay, alpha_of(a), 0, "этап роста %d" % s, full_prompt(a, s)])
        for t, what, p in TERRAIN:
            w.writerow(["terrain/%s.png" % t, what, 512, 512, "строго сверху, бесшовно", 256, 256, "нет", 0,
                        "биом на карте", "%s. %s. %s" % (p, VIEW_TOP, STYLE_TILE)])


if __name__ == "__main__":
    main()

"""Собирает index.html (предметы + всё остальное с картинками) и catalog_extra.csv. Запуск: python3 -I make_catalog_extra.py"""
import csv, base64, html, io, os, re
from PIL import Image
here = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(here, "index.html"), encoding="utf-8").read()
items_body = re.search(r'</p>(.*?)(?:<h2>Бійці|</main>)', src, re.S).group(1)
n_items = items_body.count("<figure>")
N = {  # id: (укр, рус)
 "hero": ("Герой", "Герой"), "bandit": ("Розбійник", "Бандит"), "archer": ("Розбійник-лучник", "Бандит-лучник"), "chief": ("Ватажок", "Главарь"),
 "wolf": ("Вовк", "Волк"), "hound": ("Радіаційний пес", "Радиоактивный пёс"), "dog": ("Пес", "Пёс"), "boar": ("Кабан", "Кабан"),
 "knife": ("Ніж", "Нож"), "sword": ("Меч", "Меч"), "axe": ("Сокира", "Топор"), "cleaver": ("Тесак", "Тесак"), "club": ("Дубина", "Дубина"), "mace": ("Булава", "Булава"),
 "spear": ("Спис", "Копьё"), "sling": ("Пращя", "Праща"), "bow": ("Лук", "Лук"), "torch": ("Смолоскип", "Факел"), "fist": ("Кулаки", "Кулаки"), "bite": ("Укус", "Укус"), "tusk": ("Ікла", "Клыки"),
 "move": ("Рух", "Движение"), "dash": ("Ривок", "Рывок"), "disengage": ("Відступ", "Отход"), "dodge": ("Ухиляння", "Уклонение"), "shield": ("Щит", "Щит"), "help": ("Допомога", "Помощь"), "hide": ("Сховатися", "Спрятаться"),
 "potion": ("Зілля", "Зелье"), "salve": ("Мазь", "Мазь"), "ready": ("Приготуватися", "Приготовиться"), "flee": ("Втеча", "Бегство"), "second_wind": ("Друге дихання", "Второе дыхание"), "heal": ("Лікування", "Лечение"),
 "fire_flask": ("Палаюча фляга", "Горящая фляга"), "poison_dart": ("Отруйний дротик", "Ядовитый дротик"), "war_cry": ("Бойовий клич", "Боевой клич"), "howl": ("Виття", "Вой"), "net": ("Сітка", "Сеть"), "swap": ("Змінити зброю", "Сменить оружие"), "log": ("Журнал бою", "Журнал боя"),
 "fire": ("Вогонь", "Огонь"), "radiation": ("Радіація", "Радиация"), "poison": ("Отрута", "Яд"), "slashing": ("Різальний", "Рубящий"), "piercing": ("Колючий", "Колющий"), "bludgeoning": ("Дробильний", "Дробящий"), "cold": ("Холод", "Холод"),
 "male_bare": ("Лялька героя, без одягу", "Кукла героя, без одежды"), "female_bare": ("Лялька героїні, без одягу", "Кукла героини, без одежды"),
 "male_dressed": ("Лялька героя в одязі", "Кукла героя в одежде"), "female_dressed": ("Лялька героїні в одязі", "Кукла героини в одежде"),
 "bush_berry": ("Кущ ягід", "Куст ягод"), "bush_flower": ("Кущ квітів", "Куст цветов"), "cliff_gray": ("Скеля сіра", "Скала серая"), "cobble": ("Бруківка", "Брусчатка"), "guard": ("Вартовий", "Стражник"),
 "hall": ("Ратуша", "Ратуша"), "healer": ("Лікар", "Лекарь"), "hound_": ("", ""), "house": ("Будинок", "Дом"), "inn": ("Корчма", "Трактир"), "masonry": ("Кладка", "Кладка"), "mesa_hot": ("Гаряче плато", "Горячее плато"),
 "mountain_gray": ("Гора сіра", "Гора серая"), "mountain_hot": ("Гора гаряча", "Гора горячая"), "peak_gray": ("Вершина сіра", "Вершина серая"), "ridge_gray": ("Хребет сірий", "Хребет серый"), "ridge_hot": ("Хребет гарячий", "Хребет горячий"),
 "rock": ("Камінь", "Камень"), "roof": ("Дах", "Крыша"), "smithy": ("Кузня", "Кузница"), "stall": ("Ятка", "Лавка"), "tech_dome": ("Техно-купол", "Техно-купол"), "tech_tower": ("Техно-вежа", "Техно-башня"), "tech_wreck": ("Техно-уламки", "Техно-обломки"),
 "temple": ("Храм", "Храм"), "traveler": ("Мандрівник", "Путник"), "tree_crooked": ("Крива сосна", "Кривое дерево"), "tree_light": ("Світле дерево", "Светлое дерево"), "tree_oak": ("Дуб", "Дуб"), "villager": ("Селянин", "Селянин"), "well": ("Колодязь", "Колодец"), "woman": ("Жінка", "Женщина"), "wood": ("Дерево, дошки", "Дерево, доски"),
 "t00_water": ("Вода", "Вода"), "t01_coast": ("Узбережжя", "Побережье"), "t02_forest": ("Ліс", "Лес"), "t03_field1": ("Поле 1", "Поле 1"), "t04_field2": ("Поле 2", "Поле 2"), "t05_wasteland": ("Пустир", "Пустошь"), "t06_swamp": ("Болото", "Болото"),
 "t07_mountains": ("Гори", "Горы"), "t08_hot_mountains": ("Гарячі гори", "Горячие горы"), "t09_rad_forest": ("Радіаційний ліс", "Радиоактивный лес"), "t10_rad_wasteland": ("Радіаційний пустир", "Радиоактивная пустошь"), "t11_rad_swamp": ("Радіаційне болото", "Радиоактивное болото"), "t12_glow": ("Сяйво", "Свечение"),
 "m0_camp": ("Табір", "Лагерь"), "m1_ostrog": ("Острог", "Острог"), "m2_sloboda": ("Слобода", "Слобода"), "m3_posad": ("Посад", "Посад"), "m4_gorod": ("Місто", "Город"), "m5_bolshoy_gorod": ("Велике місто", "Большой город"),
 "bar": ("Смуга", "Полоса"), "button": ("Кнопка", "Кнопка"), "panel": ("Панель", "Панель"), "portrait": ("Рамка портрета", "Рамка портрета"), "ribbon": ("Стрічка", "Лента"), "slot": ("Слот", "Слот"), "tech_plate": ("Техно-плита", "Техно-плита"),
 "map_biomes": ("Карта: біоми", "Карта: биомы"), "map_color": ("Карта: кольорова", "Карта: цветная"), "map_height": ("Карта: висоти", "Карта: высоты"), "map_hot": ("Карта: гарячі зони", "Карта: горячие зоны"), "map_provinces": ("Карта: провінції", "Карта: провинции"),
 "map_regions": ("Карта: регіони", "Карта: регионы"), "map_topo": ("Карта: топографія", "Карта: топография"), "map_water": ("Карта: вода", "Карта: вода"), "menu_bg": ("Фон меню", "Фон меню"),
}
SEC = [
 ("Бійці й істоти (портрети бою)", "extra/creatures", "Малюється кодом battle_icons.gd"),
 ("Зброя в бою (значки)", "extra/battle_weapons", "Малюється кодом battle_icons.gd"),
 ("Дії в бою (значки)", "extra/actions", "Малюється кодом battle_icons.gd"),
 ("Типи шкоди", "extra/damage", "Малюється кодом battle_icons.gd"),
 ("Лялька героя", "extra/dolls", "Малюється кодом paper_doll.gd"),
 ("Спрайти світу", "world/storybook", "art/storybook, зменшено до 512 px"),
 ("Місцевість (текстури)", "world/terrain", "art/terrain, зменшено до 512 px"),
 ("Медальйони поселень", "world/medallion", "art/medallion, зменшено до 512 px"),
 ("Карти світу", "world/map", "art/map, зменшено до 512 px"),
 ("Оформлення інтерфейсу", "world/comic_ui", "art/comic_ui, зменшено до 512 px"),
 ("Меню", "world", "art/menu_bg"),
]
def thumb(path):
    im = Image.open(path).convert("RGBA"); im.thumbnail((256, 256))
    b = io.BytesIO(); im.save(b, "WEBP", quality=82); return base64.b64encode(b.getvalue()).decode()
rows = []; secs = []; total = 0
for title, d, note in SEC:
    files = sorted(f for f in os.listdir(os.path.join(here, d)) if f.endswith(".png"))
    cards = []
    for f in files:
        k = f[:-4]; uk, ru = N.get(k, (k, k))
        cards.append('<figure><img alt="" loading="lazy" src="data:image/webp;base64,%s"><b>%s</b><i>%s</i><span>%s</span></figure>' % (thumb(os.path.join(here, d, f)), html.escape(uk), html.escape(ru), f))
        rows.append([title, k, uk, ru, d + "/" + f])
    total += len(files)
    secs.append('<h2>%s <em>%d</em></h2><p class="note">%s</p><div class="g">%s</div>' % (title, len(files), note, "".join(cards)))
with open(os.path.join(here, "catalog_extra.csv"), "w", encoding="utf-8-sig", newline="") as f:
    w = csv.writer(f); w.writerow(["Раздел", "id", "Назва (uk)", "Название (ru)", "Файл"]); w.writerows(rows)
page = src.split("</style>")[0].split("<style>")[1]
page += ".note{color:var(--mut);margin:-4px 0 10px;font-size:13px}.g img{object-fit:contain}"
out = ('<title>Каталог предметов Amber</title>\n<meta name="claude:viewport-fit-sides" content="cover">\n<style>' + page + '</style>\n<main><h1>Каталог предметов Amber</h1>'
 '<p class="lead">Всё, что в игре 2D 12 имеет картинку: ' + str(n_items) + ' предметов и ' + str(total) + ' других изображений. Названия на украинском и русском. Файлы лежат в папке amber2d/items_catalog.</p>'
 + items_body.replace("<h2>", "<h2 data-s>", 0) + "".join(secs) + '</main>')
open("/tmp/catalog_page.html", "w", encoding="utf-8").write(out)
print(n_items, total, len(out) / 1e6, "MB")

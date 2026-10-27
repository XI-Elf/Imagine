import json, random, sys
out = sys.argv[1]
W, H = 120, 90
B = lambda i, n, k, r, d: {"id": i, "name": n, "kind": k, "rect": r, "door": d}
buildings = [
 B("hall",   "Детинец посадника",           "hall",   [48, 2, 24, 11],  [59, 12]),
 B("temple", "Храм Светлого Огня",          "temple", [80, 18, 14, 12], [86, 29]),
 B("inn",    "Трактир «Янтарная кружка»",   "inn",    [24, 18, 18, 11], [32, 28]),
 B("shop",   "Лавка Сигрид",                "shop",   [24, 32, 14, 10], [37, 36]),
 B("healer", "Знахарская",                  "healer", [80, 32, 12, 9],  [80, 36]),
 B("smithy", "Кузница",                     "smithy", [100, 48, 14, 10],[100, 52]),
 B("tailor", "Мастерская ткачихи",          "shop",   [80, 48, 12, 8],  [86, 48]),
 B("barracks","Казарма стражи",             "hall",   [64, 74, 14, 9],  [64, 78]),
 B("house_1","Дом Годрика",                "house",  [4, 18, 12, 8],   [15, 22]),
 B("house_2","Дом кожевника",               "house",  [4, 30, 12, 8],   [15, 34]),
 B("house_3","Дом вдовы Мейв",            "house",  [4, 48, 12, 8],   [15, 52]),
 B("house_4","Дом гончара",                 "house",  [24, 48, 12, 8],  [24, 52]),
 B("house_5","Дом писаря",                  "house",  [40, 48, 12, 8],  [46, 48]),
 B("house_6","Дом у южной стены",           "house",  [24, 74, 12, 8],  [30, 74]),
 B("house_7","Дом старьёвщика",             "house",  [40, 74, 12, 8],  [46, 74]),
 B("ruins_n","Развалины довоенного склада", "ruins",  [100, 4, 16, 10], [107, 13]),
 B("ruins_e","Обрушенная башня",            "ruins",  [102, 64, 14, 12],[108, 64]),
]
roads = [
 {"from": [58, 13], "to": [58, 88], "w": 3},
 {"from": [2, 44],  "to": [117, 44], "w": 2},
 {"from": [10, 14], "to": [110, 14], "w": 2},
 {"from": [20, 14], "to": [20, 80], "w": 2},
 {"from": [98, 14], "to": [98, 80], "w": 2},
 {"from": [2, 70],  "to": [97, 70], "w": 2},
]
squares = [{"id": "market", "name": "Торговая площадь", "rect": [44, 30, 32, 13]}]
fields = [{"rect": [4, 60, 14, 9]}, {"rect": [80, 60, 14, 8]}]
gate = {"id": "south", "name": "Южные ворота", "cells": [[58, 89], [59, 89], [60, 89], [61, 89]],
        "spawn": [59.5, 86.5], "guard_post": [56, 86]}
stalls = [[[47, 33], [48, 33]], [[51, 33], [52, 33]], [[66, 33], [67, 33]], [[70, 33], [71, 33]]]
wells = [[[66, 38], [67, 38], [66, 39], [67, 39]], [[30, 62], [31, 62], [30, 63], [31, 63]]]

# Проверочная сетка: где можно ставить деревья
grid = [[0] * W for _ in range(H)]   # 0 трава, 1 занято
def fill(r, v=1, pad=0):
    for y in range(r[1] - pad, r[1] + r[3] + pad):
        for x in range(r[0] - pad, r[0] + r[2] + pad):
            if 0 <= x < W and 0 <= y < H: grid[y][x] = v
for x in range(W): grid[0][x] = grid[H-1][x] = 1
for y in range(H): grid[y][0] = grid[y][W-1] = 1
for rd in roads:
    (x0, y0), (x1, y1), w = rd["from"], rd["to"], rd["w"]
    fill([min(x0, x1), min(y0, y1), abs(x1 - x0) + w, abs(y1 - y0) + w])
for s in squares: fill(s["rect"])
for f in fields: fill(f["rect"])
for b in buildings: fill(b["rect"], pad=2)
fill([56, 84, 8, 6])
for g in wells: [fill([c[0], c[1], 1, 1], pad=1) for c in g]
# Тихие места у стены изнутри: сюда попадает герой, пролезший через стену (entry "sneak")
breaches = [
 {"side": "north", "cell": [85, 2]}, {"side": "west", "cell": [2, 40]},
 {"side": "east", "cell": [117, 36]}, {"side": "south", "cell": [90, 87]},
]
for b in breaches:
    x, y = b["cell"]
    assert grid[y][x] == 0, b
    fill([x, y, 1, 1], pad=1)
rng = random.Random(1488)
trees = []
while len(trees) < 46:
    x, y = rng.randrange(2, W - 2), rng.randrange(2, H - 2)
    if all(grid[yy][xx] == 0 for yy in range(y - 1, y + 2) for xx in range(x - 1, x + 2)):
        trees.append([x, y]); grid[y][x] = 1

# Двери: на краю дома, снаружи — проход
for b in buildings:
    x, y, w, h = b["rect"]; dx, dy = b["door"]
    assert (dx in (x, x + w - 1) and y < dy < y + h - 1) or (dy in (y, y + h - 1) and x < dx < x + w - 1), b["id"]

def npc(i, name, role, home, hours, lines, **kw):
    d = {"id": i, "name": name, "role": role, "home": home, "hours": hours}
    d.update(kw); d["lines"] = lines; return d

npcs = [
 npc("posadnik", "Посадник Беорхтнот", "elder", "hall", [8, 20], [
   "Чёрнославль стоит с тех пор, как после Вспышки здесь сошлись три обоза. Стены — моя забота, порядок — тоже.",
   "За обрушенной башней никто не следит. Что найдёшь — твоё, только стражу не зли.",
   "На северо-востоке горы горячие, как печь. Кто туда ходил, возвращались обожжёнными."], work="hall"),
 npc("priest", "Жрец Кормак", "citizen", "temple", [6, 21], [
   "Светлый Огонь горел и в ту ночь, когда небо вспыхнуло. Мы его бережём.",
   "Больных веди к Бригит, а за душу их молись здесь."], work="temple"),
 npc("innkeeper", "Альгирдас", "innkeeper", "inn", [7, 24], [
   "Заходи, путник. Похлёбка горячая, эль свежий.", "Комната — десять монет, до утра."],
   work="inn", skill="cookery", stock={"bread": 14, "stew": 10, "ale": 24, "water_flask": 16}, services={"room": 10}),
 npc("trader", "Сигрид", "trader", "shop", [8, 20], [
   "Всё нужное в дорогу, недорого.", "Шкуры беру, янтарь беру — по честной цене."],
   work="market", work_cell=[49, 34],
   stock={"bread": 12, "dried_meat": 10, "water_flask": 12, "rope": 5, "torch": 12, "bandage": 6, "knife": 2},
   buys=["hide", "scrap", "old_coin", "amber", "rope", "torch", "knife", "vegetables"]),
 npc("weaver", "Бирута", "trader", "tailor", [9, 19], [
   "Ткань нынче дорогая.", "Шкуры выделаю — неси, куплю."],
   work="tailor", skill="sewing", stock={"rope": 6, "bandage": 8, "torch": 4}, buys=["hide", "rope"]),
 npc("healer", "Бригит", "healer", "healer", [7, 21], [
   "Покажи, где болит.", "Лечу за плату. Лекарства мои — своё не трать."],
   work="healer", skill="medicine",
   stock={"bandage": 10, "splint": 4, "salve": 5, "herbal_decoction": 6, "charcoal": 8, "anti_rad_potion": 3,
          "healing_potion": 2, "fever_potion": 3, "warming_potion": 3, "vermifuge": 3, "stimulant": 2, "strong_potion": 1},
   services={"heal": 6}, buys=["amber"]),
 npc("smith", "Торстейн", "smith", "smithy", [7, 19], [
   "Железо есть? Тащи — куплю.", "Топоры хорошие, на всю зиму хватит."],
   work="smithy", skill="blacksmith", stock={"knife": 4, "axe": 3, "splint": 2}, buys=["scrap", "knife", "axe"]),
 npc("junkman", "Старьёвщик Эльфрик", "trader", "house_7", [10, 22], [
   "Довоенное? Покажи. Монеты старые беру, янтарь беру.", "В развалинах склада погреб есть. Я туда уже не лазаю — колени."],
   work_cell=[50, 71], stock={"torch": 6, "rope": 2, "old_coin": 2}, buys=["scrap", "old_coin", "amber", "knife"]),
 npc("guard_1", "Хальвдан", "guard", "barracks", [0, 24], [
   "Ворота закрываются в десять вечера.", "Ночью выпускаю за плату — порядок такой."], work_cell=[56, 86], gate="south"),
 npc("guard_2", "Скирмантас", "guard", "barracks", [6, 22], [
   "На площади не воруй — глаз у меня острый.", "Днём тут тихо. Ночью — другое дело."], work_cell=[60, 38], wander=8),
 npc("guard_3", "Лоркан", "guard", "barracks", [6, 22], [
   "Посадник никого без дела не принимает.", "Стой, где стоишь, и говори по делу."], work_cell=[62, 13]),
 npc("farmer", "Годрик", "citizen", "house_1", [6, 19], [
   "Огород кормит лучше любой торговли.", "Чужой огород не трогай — стража не любит."], work_cell=[11, 64]),
 npc("potter", "Эрконвальд", "citizen", "house_4", [8, 18], [
   "Глина у нас добрая, у южной стены копаем.", "Горшки на торгу у Сигрид бери."], work="market", work_cell=[54, 39], wander=6),
 npc("widow", "Мейв", "citizen", "house_3", [8, 20], [
   "Муж ушёл в горячие горы и не вернулся.", "В колодце вода чистая, пей смело."], work_cell=[31, 60], wander=5),
 npc("kid", "Ульв", "citizen", "house_5", [9, 20], [
   "А ты из-за стены пришёл? Расскажи!", "Я знаю, где в обрушенной башне тайник!"], work_cell=[62, 40], wander=12),
 npc("scribe", "Писарь Себберт", "citizen", "house_5", [9, 18], [
   "Записываю всех, кто входит в город. И тебя записал.", "Довоенные книги? Если найдёшь — неси, хорошо заплачу… когда-нибудь."], work="hall"),
]
places = [
 {"id": "notice_board", "name": "Доска объявлений", "kind": "board", "cell": [56, 30], "text":
  "«Ищу попутчиков до восточных копей — Торстейн». «Пропала коза, вознаграждение — Годрик». «Из южных болот не пить: дизентерия». «Посадник набирает стражу»."},
 {"id": "well_square", "name": "Колодец на площади", "kind": "water", "cell": [66.5, 38.5]},
 {"id": "well_south", "name": "Колодец у огородов", "kind": "water", "cell": [30.5, 62.5]},
 {"id": "altar", "name": "Алтарь Светлого Огня", "kind": "lore", "cell": [86, 22], "text":
  "Огонь в каменной чаше. Рядом выбиты имена тех, кто погиб во Вспышке — сотни имён."},
 {"id": "shrine", "name": "Старое капище", "kind": "lore", "cell": [10, 83], "text":
  "Камни с вырезанными знаками. Говорят, их поставили ещё до Вспышки."},
 {"id": "cellar", "name": "Погреб под складом", "kind": "container", "cell": [107, 8],
  "loot": {"scrap": [1, 3, 0.8], "old_coin": [1, 2, 0.4], "torch": [1, 1, 0.5], "amber": [1, 1, 0.15], "money": [2, 9, 0.6]}},
 {"id": "tower_cache", "name": "Тайник в башне", "kind": "container", "cell": [108, 70],
  "loot": {"knife": [1, 1, 0.3], "old_coin": [1, 3, 0.5], "bandage": [1, 2, 0.4], "money": [3, 12, 0.5]}},
 {"id": "junk", "name": "Куча хлама за кузницей", "kind": "container", "cell": [116, 53],
  "loot": {"scrap": [1, 4, 0.9], "rope": [1, 1, 0.25]}},
 {"id": "garden", "name": "Огород Годрика", "kind": "container", "cell": [10, 66], "loot": {"vegetables": [1, 3, 0.7]}, "steal": True},
]
d = {
 "_note": "Чёрнославль — единственный город мира (id s001 из data/world/settlements.json). Клетки по cell_m метров, x вправо, y вниз. Сделан скриптом make_s001.py; числа [ВРЕМЕННО].",
 "id": "s001", "name": "Чёрнославль", "size": [W, H], "cell_m": 2.0, "wall": "stone",
 "rules": {"walk_scale": 3.0, "gates_open_h": 6.0, "gates_close_h": 22.0, "night_pass_fee": 5, "shelter_temp_c": 6.0,
           "start_money": 40, "sight_m": 16.0, "loot_respawn_days": 3.0, "guard_watch_m": 18.0, "steal_fine": 5,
           "intruder_h": 2.0, "intruder_spot_m": 8.0, "intruder_spot_night_m": 4.0, "intruder_fine": 15},
 "gates": [gate], "breaches": breaches, "jail": "barracks", "roads": roads, "squares": squares, "fields": fields, "buildings": buildings,
 "props": [{"kind": "stall", "cells": s} for s in stalls] + [{"kind": "well", "cells": w} for w in wells] + [{"kind": "tree", "cells": trees}],
 "places": places, "npcs": npcs,
}
json.dump(d, open(out, "w"), ensure_ascii=False, indent=1)
print("ok", len(npcs), "npcs", len(buildings), "buildings", len(trees), "trees")

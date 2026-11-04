#!/usr/bin/env python3
"""README_UK.txt і README_RU.txt у корені гри (питання Q23, варіанти B+C; Q38 — українська головна).

  python3 -I game/tools/make_readme.py

Опис гри написано тут вручну. Керування й «Основні механіки» беруться з tutorial/tutorial.gd
(ті самі рядки, що в довідці F1), тому після правки клавіш README досить перезібрати.
Спосіб запуску обирається за файлами в корені: AmberWorld.exe і/або Start_HEX.vbs.
"""
import json
import pathlib
import re
import sys

GAME = pathlib.Path(__file__).resolve().parent.parent
ROOT = GAME.parent
OUT = {"uk": ROOT / "README_UK.txt", "ru": ROOT / "README_RU.txt"}
START = {"uk": ROOT / "README_START_UK.txt", "ru": ROOT / "README_START_RU.txt"}
PO = GAME / "i18n" / "uk.po"
TUTORIAL = GAME / "tutorial" / "tutorial.gd"
CODE_REF = re.compile(r" *\([^)]*\.gd\)")   # «(audio/sfx.gd)» у довідці — для розробника

INTRO_RU = """\
AMBER WORLD — 2D

Ролевая игра на выживание с открытым миром. Стиль — Dark sci-fi fantasy: рисованная карта с видом сверху,
средневековые города и обломки машин прошлого.

МИР
{lore}
Проклятые лес, пустошь и болото отмечены на карте свечением. Среди пустошей стоят руины машин и башни,
в которых можно найти лом и старые монеты.

- Общая карта — шестиугольник около 42 × 36 км: море, реки, леса, пустоши, болота, горы и их проклятые двойники.
  Оранжевые жаркие горы всегда на 40 °C жарче. Есть день и ночь, времена года, облака, дождь и снег.
- {city} — единственный город. Он начинается с лачуги героя и общего дома, где живут олдермен,
  травница и кожевник. Их поручения выращивают город: {stages}.
  С каждым этапом появляются дома, жители, товары и новые поручения.
- Дорог к городу заранее нет: где часто ходят, появляются тропинка, тропа, просёлок и грунтовая дорога.
- Мастерские: кожевник и кузнец делают вещи на заказ или учат делать самому (шкуры со зверей, лом с руин).
- Лошадь и повозка продаются, когда город дорастёт до второго этапа: верхом быстрее, повозка везёт груз.
- Если герой погибает, игра продолжается новым случайным героем. Город и его рост сохраняются,
  вещи и навыки прежнего героя — нет.

БОЙ
Пошаговый, на клетках: инициатива, действие, бонусное действие, реакция, укрытия,
атаки по возможности, способности и зелья. При 0 здоровья герой делает проверку: травма, потеря сознания
или смерть. Первый бой у города на первом этапе — с одиночным оборванцем, и с ножом он почти всегда выигран.
"""

LAUNCH_EXE_RU = "1. Распакуйте архив целиком в папку, куда можно писать.\n2. Запустите AmberWorld.exe.\n"
LAUNCH_HEX_RU = ("1. Распакуйте архив целиком в папку, куда можно писать (не запускайте из окна архиватора).\n"
              "2. Запустите Start_HEX.vbs. Первый запуск импортирует ресурсы и идёт дольше.\n"
              "   Если экран чёрный или игра вылетает — Start_HEX_compat.cmd (режим совместимости).\n")

OUTRO_RU = """\
ФАЙЛЫ
- README_RU.txt — этот файл; README_UK.txt — он же на украинском (оба собирает game/tools/make_readme.py).
- ART_DIRECTION.md — художественный стиль и откуда взяты рисунки.
- Сохранения и настройки обучения лежат в папке пользователя Godot (user://), а не рядом с игрой.
"""

INTRO_UK = """\
AMBER WORLD — 2D

Рольова гра на виживання з відкритим світом. Стиль — Dark sci-fi fantasy: мальована карта з виглядом згори,
середньовічні міста й уламки машин минулого.

СВІТ
{lore}
Прокляті ліс, пустку й болото позначено на карті світінням. Серед пусток стоять руїни машин і вежі,
у яких можна знайти брухт і старі монети.

- Загальна карта — шестикутник близько 42 × 36 км: море, річки, ліси, пустки, болота, гори та їхні прокляті двійники.
  Помаранчеві спекотні гори завжди на 40 °C спекотніші. Є день і ніч, пори року, хмари, дощ і сніг.
- {city} — єдине місто. Воно починається з халупи героя й спільного дому, де живуть олдермен,
  травниця й шкіряник. Їхні доручення вирощують місто: {stages}.
  З кожним етапом з'являються будинки, мешканці, товари й нові доручення.
- Доріг до міста заздалегідь немає: де часто ходять, з'являються стежинка, стежка, путівець і ґрунтова дорога.
- Майстерні: шкіряник і коваль роблять речі на замовлення або вчать робити самому (шкури зі звірів, брухт із руїн).
- Кінь і віз продаються, коли місто доросте до другого етапу: верхи швидше, віз везе вантаж.
- Якщо герой гине, гра триває з новим випадковим героєм. Місто і його ріст зберігаються,
  речі й навички колишнього героя — ні.

БІЙ
Покроковий, на клітинках, за правилами D&D 5e: ініціатива, дія, бонусна дія, реакція, укриття,
атаки за нагоди, здібності й зілля. За 0 здоров'я герой робить перевірку: травма, втрата свідомості
або смерть. Перший бій біля міста на першому етапі — з одиноким обірванцем, і з ножем він майже завжди виграний.
"""

LAUNCH_EXE_UK = "1. Розпакуйте архів повністю в теку, куди можна писати.\n2. Запустіть AmberWorld.exe.\n"
LAUNCH_HEX_UK = ("1. Розпакуйте архів повністю в теку, куди можна писати (не запускайте з вікна архіватора).\n"
                 "2. Запустіть Start_HEX.vbs. Перший запуск імпортує ресурси й триває довше.\n"
                 "   Якщо екран чорний або гра вилітає — Start_HEX_compat.cmd (режим сумісності).\n")

OUTRO_UK = """\
ФАЙЛИ
- README_UK.txt — цей файл; README_RU.txt — він же російською (обидва збирає game/tools/make_readme.py).
- ART_DIRECTION.md — художній стиль і звідки взято малюнки.
- Збереження й налаштування навчання лежать у теці користувача Godot (user://), а не поруч із грою.
"""

TEXT = {
    "ru": {"intro": INTRO_RU, "exe": LAUNCH_EXE_RU, "hex": LAUNCH_HEX_RU, "outro": OUTRO_RU,
           "launch": "ЗАПУСК\n", "mech": "ОСНОВНЫЕ МЕХАНИКИ\n", "keys": "УПРАВЛЕНИЕ (то же, что в справке F1)",
           "steps": "3. В меню — «Новая игра», затем создание героя (или «Случайно»). F1 в игре — справка.\n"
                    "4. Игра запускается на украинском. Русский — кнопка «Мова» в главном меню, игра перезапустится.\n",
           "start": "AMBER WORLD — 2D\n\nРаспакуйте архив целиком и запустите игру. Как именно, описание мира, механики\n"
                    "и все клавиши — в README_RU.txt (те же клавиши показывает F1 в игре).\n"},
    "uk": {"intro": INTRO_UK, "exe": LAUNCH_EXE_UK, "hex": LAUNCH_HEX_UK, "outro": OUTRO_UK,
           "launch": "ЗАПУСК\n", "mech": "ОСНОВНІ МЕХАНІКИ\n", "keys": "КЕРУВАННЯ (те саме, що в довідці F1)",
           "steps": "3. У меню — «Нова гра», потім створення героя (або «Випадково»). F1 у грі — довідка.\n"
                    "4. Гра запускається українською. Російська — кнопка «Мова» в головному меню, гра перезапуститься.\n",
           "start": "AMBER WORLD — 2D\n\nРозпакуйте архів повністю й запустіть гру. Як саме, опис світу, механіки\n"
                    "й усі клавіші — у README_UK.txt (ті самі клавіші показує F1 у грі). Російською — README_RU.txt.\n"},
}


def gd_string(s: str) -> str:
    return s.replace('\\"', '"').replace("\\n", " ")


def block(text: str, start: str, end: str) -> str:
    i = text.index(start)
    return text[i:text.index(end, i)]


def parse_rows(src: str):
    """Рядки виду ["клавіша", "що робить"] і ["підзаголовок"] по черзі; "Розділ": [ — новий розділ."""
    out = []
    for line in src.splitlines():
        sec = re.match(r'\s*(?:I18n\.t\()?"([^"]+)"\)?:\s*\[', line)
        if sec:
            out.append(("section", sec.group(1)))
            continue
        items = re.findall(r'"((?:[^"\\]|\\.)*)"', line)
        if re.match(r"\s*\[", line) and items:
            out.append(("row", [gd_string(x) for x in items]))
    return out


def read_po():
    """{російський рядок: український} з i18n/uk.po (як read_po у tools/i18n.py)."""
    tr, cur, field = {}, {"msgid": "", "msgstr": ""}, None
    unq = lambda q: q[1:-1].replace('\\"', '"').replace("\\n", "\n").replace("\\t", "\t").replace("\\\\", "\\")
    for line in PO.read_text(encoding="utf-8").split("\n") + [""]:
        if line.startswith("msgid "):
            cur, field = {"msgid": unq(line[6:]), "msgstr": ""}, "msgid"
        elif line.startswith("msgstr "):
            cur["msgstr"], field = unq(line[7:]), "msgstr"
        elif line.startswith('"') and field:
            cur[field] += unq(line)
        elif not line.strip() and field == "msgstr":
            if cur["msgid"] and cur["msgstr"]:
                tr[cur["msgid"]] = cur["msgstr"]
            cur, field = {"msgid": "", "msgstr": ""}, None
    return tr


def main():
    src = TUTORIAL.read_text(encoding="utf-8")
    # із Q26 тексти обгорнуто в I18n.t(...) й оголошено static var; README збирається з російських вихідників,
    # українська версія перекладає їх через i18n/uk.po (ті самі рядки, що бачить гра)
    keys = parse_rows(block(src, " KEYS: Dictionary = {", "\n}\n"))
    mech = [r for k, r in parse_rows(block(src, " MECHANICS: Array = [", "\n]\n")) if k == "row"]
    if not keys or not mech:
        sys.exit("tutorial.gd: не знайдено KEYS або MECHANICS")
    city = json.loads((GAME / "data" / "cities" / "s001.json").read_text(encoding="utf-8"))
    po = read_po()
    exe_only = (ROOT / "AmberWorld.exe").exists() and not (ROOT / "Start_HEX.vbs").exists()
    for lang, out in OUT.items():
        t = (lambda x: po.get(x, x)) if lang == "uk" else (lambda x: x)
        T = TEXT[lang]
        lore = next((t(r[1]) for r in mech if r[0] == "Мир после Вспышки"), "")
        stages = " → ".join(t(s["name"]) for s in city.get("growth", {}).get("stages", []))
        parts = [T["intro"].format(lore=lore, city=t(city.get("name", "")), stages=stages)]
        parts.append(T["launch"] + (T["exe"] if exe_only else T["hex"]) + T["steps"])
        parts.append(T["mech"] + "\n".join(f"- {t(a)}: {t(d)}" for a, d in mech if a != "Мир после Вспышки") + "\n")
        lines = [T["keys"]]
        for kind, v in keys:
            if kind == "section":
                lines.append(f"\n[{t(v)}]")
            elif len(v) == 1:
                lines.append(f"  {t(v[0])}:")
            else:
                lines.append(f"    {t(v[0])} — {CODE_REF.sub('', t(v[1]))}")
        parts.append("\n".join(lines) + "\n")
        parts.append(T["outro"])
        out.write_text("\n".join(parts), encoding="utf-8", newline="\r\n")
        START[lang].write_text(T["start"], encoding="utf-8", newline="\r\n")
        miss = [x for x in [r[1] for r in mech] if lang == "uk" and x not in po]
        print(f"{out}: {len(mech)} механік, {sum(1 for k, _ in keys if k == 'row')} рядків керування"
              + (f", без перекладу {len(miss)}" if miss else ""))


if __name__ == "__main__":
    main()

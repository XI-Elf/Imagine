#!/usr/bin/env python3
"""README_RU.txt в корне игры (вопрос Q23, варианты B+C).

  python3 -I game/tools/make_readme.py

Описание игры написано здесь руками. Управление и «Основные механики» берутся из tutorial/tutorial.gd
(те же строки, что в справке F1), поэтому после правки клавиш README достаточно пересобрать.
Способ запуска выбирается по файлам в корне: AmberWorld.exe и/или Start_HEX.vbs.
"""
import json
import pathlib
import re
import sys

GAME = pathlib.Path(__file__).resolve().parent.parent
ROOT = GAME.parent
OUT = ROOT / "README_RU.txt"
TUTORIAL = GAME / "tutorial" / "tutorial.gd"
CODE_REF = re.compile(r" *\([^)]*\.gd\)")   # «(audio/sfx.gd)» в справке — для разработчика

INTRO = """\
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

LAUNCH_EXE = "1. Распакуйте архив целиком в папку, куда можно писать.\n2. Запустите AmberWorld.exe.\n"
LAUNCH_HEX = ("1. Распакуйте архив целиком в папку, куда можно писать (не запускайте из окна архиватора).\n"
              "2. Запустите Start_HEX.vbs. Первый запуск импортирует ресурсы и идёт дольше.\n"
              "   Если экран чёрный или игра вылетает — Start_HEX_compat.cmd (режим совместимости).\n")

OUTRO = """\
ФАЙЛЫ
- README_RU.txt — этот файл (собирается скриптом game/tools/make_readme.py).
- ART_DIRECTION.md — художественный стиль и откуда взяты рисунки.
- Сохранения и настройки обучения лежат в папке пользователя Godot (user://), а не рядом с игрой.
"""


def gd_string(s: str) -> str:
    return s.replace('\\"', '"').replace("\\n", " ")


def block(text: str, start: str, end: str) -> str:
    i = text.index(start)
    return text[i:text.index(end, i)]


def parse_rows(src: str):
    """Строки вида ["клавиша", "что делает"] и ["подзаголовок"] по порядку; "Раздел": [ — новый раздел."""
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


def main():
    src = TUTORIAL.read_text(encoding="utf-8")
    # с Q26 тексты обёрнуты в I18n.t(...) и объявлены static var; README собирается из русских исходников
    keys = parse_rows(block(src, " KEYS: Dictionary = {", "\n}\n"))
    mech = [r for k, r in parse_rows(block(src, " MECHANICS: Array = [", "\n]\n")) if k == "row"]
    if not keys or not mech:
        sys.exit("tutorial.gd: не найдены KEYS или MECHANICS")
    lore = next((r[1] for r in mech if r[0] == "Мир после Вспышки"), "")
    city = json.loads((GAME / "data" / "cities" / "s001.json").read_text(encoding="utf-8"))
    stages = " → ".join(s["name"] for s in city.get("growth", {}).get("stages", []))
    parts = [INTRO.format(lore=lore, city=city.get("name", ""), stages=stages)]
    parts.append("ЗАПУСК\n" + (LAUNCH_EXE if (ROOT / "AmberWorld.exe").exists() and not (ROOT / "Start_HEX.vbs").exists() else LAUNCH_HEX)
                 + "3. В меню — «Новая игра», затем создание героя (или «Случайно»). F1 в игре — справка.\n"
                 + "4. Язык (русский или украинский) — кнопка «Язык» в главном меню, игра перезапустится.\n")
    parts.append("ОСНОВНЫЕ МЕХАНИКИ\n" + "\n".join(f"- {t}: {d}" for t, d in mech if t != "Мир после Вспышки") + "\n")
    lines = ["УПРАВЛЕНИЕ (то же, что в справке F1)"]
    for kind, v in keys:
        if kind == "section":
            lines.append(f"\n[{v}]")
        elif len(v) == 1:
            lines.append(f"  {v[0]}:")
        else:
            lines.append(f"    {v[0]} — {CODE_REF.sub('', v[1])}")
    parts.append("\n".join(lines) + "\n")
    parts.append(OUTRO)
    OUT.write_text("\n".join(parts), encoding="utf-8", newline="\r\n")
    print(f"{OUT}: {len(mech)} механик, {sum(1 for k, _ in keys if k == 'row')} строк управления")


if __name__ == "__main__":
    main()

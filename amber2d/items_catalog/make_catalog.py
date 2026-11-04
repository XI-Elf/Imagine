"""Собирает каталог предметов: catalog.csv, README.md, index.html (PNG внутри, base64).
Вход: catalog.json (qa/render_catalog.gd) и game/data/cities/items.json (русские названия)."""
import json, csv, base64, html, sys, os
here = os.path.dirname(os.path.abspath(__file__))
cat = json.load(open(sys.argv[1], encoding="utf-8"))
ru = json.load(open(sys.argv[2], encoding="utf-8"))["items"]
SLOT = {"head": "голова", "body": "тело", "back": "спина", "hands": "руки", "legs": "ноги", "feet": "ступни"}
def kind(i):
    if "transport" in ru[i]: return "Транспорт"
    if i in ("amber","old_coin"): return "Ценности"
    u = i and cat[i]["use"]
    if "eat" in u: return "Еда"
    if "drink" in u: return "Питьё"
    if cat[i]["treat"]: return "Лечение"
    if cat[i]["weapon"]: return "Оружие"
    if cat[i]["wear"]: return "Одежда и броня"
    return "Вещи и материалы"
def stats(i):
    c = cat[i]; s = []
    if c["use"].get("eat"): s.append("сытость +%d" % c["use"]["eat"])
    if c["use"].get("drink"): s.append("жажда −%d" % c["use"]["drink"])
    if c["wear"]: s.append("слот: " + SLOT.get(c["wear"]["slot"], c["wear"]["slot"]) + (", броня: " + c["wear"]["armor"] if c["wear"].get("armor") else ""))
    if c["weapon"]: s.append("оружие боя: " + c["weapon"])
    if c["treat"]: s.append("лечит при использовании")
    return "; ".join(s)
rows = []
for i, c in cat.items():
    rows.append(dict(id=i, uk=c["name"], ru=ru[i]["name"], kind=kind(i), price=int(c["price"]), weight=c["weight"], stats=stats(i)))
rows.sort(key=lambda r: (r["kind"], r["uk"]))
with open(os.path.join(here, "catalog.csv"), "w", encoding="utf-8-sig", newline="") as f:
    w = csv.writer(f); w.writerow(["id","Назва (uk)","Название (ru)","Вид","Цена","Вес, кг","Свойства","PNG"])
    for r in rows: w.writerow([r["id"], r["uk"], r["ru"], r["kind"], r["price"], r["weight"], r["stats"], "png/%s.png" % r["id"]])
cards = {}
for r in rows:
    b = base64.b64encode(open(os.path.join(here, "png", r["id"] + ".png"), "rb").read()).decode()
    cards.setdefault(r["kind"], []).append(
        '<figure><img alt="" src="data:image/png;base64,%s"><b>%s</b><i>%s</i><span>%s · %s кг · %d мон.</span><small>%s</small></figure>'
        % (b, html.escape(r["uk"]), html.escape(r["ru"]), r["id"], r["weight"], r["price"], html.escape(r["stats"])))
body = "".join('<h2>%s <em>%d</em></h2><div class="g">%s</div>' % (k, len(v), "".join(v)) for k, v in cards.items())
open(os.path.join(here, "index.html"), "w", encoding="utf-8").write("""<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Каталог предметов</title><style>
:root{--bg:#f4efe6;--fg:#2a2622;--card:#fffaf0;--mut:#6b6258;--line:#d8ccb8;--icon:#2a2622}
@media(prefers-color-scheme:dark){:root:not([data-theme=light]){--bg:#1d1a17;--fg:#eee6d8;--card:#2a2622;--mut:#a89d8e;--line:#443c33}}
body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.4 system-ui,sans-serif;padding:20px 16px}
h1{margin:0 0 4px}p{color:var(--mut);margin:0 0 16px}h2{margin:28px 0 10px;border-bottom:1px solid var(--line);padding-bottom:4px}h2 em{color:var(--mut);font-weight:400;font-style:normal;font-size:.8em}
.g{display:grid;grid-template-columns:repeat(auto-fill,minmax(170px,1fr));gap:12px}
figure{margin:0;background:var(--card);border:1px solid var(--line);border-radius:10px;padding:10px;display:flex;flex-direction:column;gap:2px}
img{width:100%%;aspect-ratio:1;background:var(--icon);border-radius:8px;object-fit:contain}
figure i{color:var(--mut);font-size:13px}figure span{font-size:12px;color:var(--mut)}figure small{font-size:12px}
</style></head><body><h1>Каталог предметов</h1><p>%d предметов, значки 256×256 из игры (2D 12). Названия: украинский / русский. Файлы PNG — в amber2d/items_catalog/png.</p>%s</body></html>""" % (len(rows), body))
print(len(rows), "ok")

# Лошадь и повозка в продаже (вопрос Q16, Huzzah 2026-10-24): лошадь у торговки Сигрид, повозка у кузнеца
# Торстейна; оба появляются в городе на этапе «Деревня». Скрипт можно запускать повторно и после
# make_city_radial.py / make_city_growth.py: он только дописывает запас, остальное не трогает.
# python3 tools/add_transport_stock.py [data/cities/s001.json]
import json, sys

path = sys.argv[1] if len(sys.argv) > 1 else 'data/cities/s001.json'
SELL = {'trader': {'horse': 1}, 'smith': {'cart': 1}}

d = json.load(open(path, encoding='utf-8'))
for n in d['npcs']:
	for k, v in SELL.get(n['id'], {}).items():
		n.setdefault('stock', {})[k] = v
json.dump(d, open(path, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
print('ok', path)

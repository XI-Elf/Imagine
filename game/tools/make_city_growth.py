# Растущий город (Huzzah 2026-10-23): начальный город почти пуст — лачуга героя и один общий дом на троих
# (глава поселения, травница, кожевник). Город внутри стены растёт, когда герой выполняет их задания;
# со слободой приходят кузнец, торговка и стражник со своими заданиями. Остальные дома и жители прежнего
# Чёрнославля — пул для этапов роста.
# Добавляет в описание города кожевника, лачугу героя (место "bed") и раздел "growth":
#   stages[i] = {name, points, wall?, buildings, npcs, places, props — что появляется на этапе i,
#                names — переименования домов, npc_set — поля жителей (дом, работа, реплики)}
#   quests = {id НПС: [{id, stage, title, kind, ...}]} — kind: walk (km), win (wins), bring (item, n), pay (money)
# Что не упомянуто ни в одном этапе после нулевого, стоит с самого начала (развалины, деревья, поля, дороги).
# Запуск: python3 make_city_growth.py <s001.json> <выходной s001.json>
import json, sys

src_path, out_path = sys.argv[1], sys.argv[2]
d = json.load(open(src_path, encoding='utf-8'))
d.pop('growth', None)
d['npcs'] = [n for n in d['npcs'] if n['id'] != 'tanner']
d['places'] = [p for p in d['places'] if p['id'] != 'hero_bed']
bld = {b['id']: b for b in d['buildings']}
npc = {n['id']: n for n in d['npcs']}


def qh(*nums):
	return ['quarter_house_%d' % k for k in nums]


def res(*nums):
	return ['art_resident_%d' % k for k in nums]


# Нулевой этап (Huzzah 2026-10-23: «все должны жить в одном», сперва трое — глава поселения, травник, кожевник):
# лачуга героя и один общий дом (будущий трактир), где живут и работают все трое
COMMON, HERO_HUT, GUARD_HUT, ELDER_HUT, TANNERY = 'inn', 'quarter_house_24', 'quarter_house_25', 'quarter_house_21', 'house_2'
for b in [COMMON, HERO_HUT, GUARD_HUT, ELDER_HUT, TANNERY]:
	assert b in bld, b

# Кожевник — новый житель, имя англосаксонское (Huzzah: новые имена норвежские и англосаксонские)
d['npcs'].append({
	'id': 'tanner', 'name': 'Кожевник Эдрик', 'role': 'tanner', 'home': TANNERY, 'work': TANNERY,
	# Одежда (ветка инвентаря): портниха и старьёвщик придут только с посадом, а кожаное — у кожевника с самого начала
	'hours': [7, 19], 'skill': 'sewing', 'stock': {'rope': 4, 'leather_jacket': 1, 'boots': 2, 'gloves': 3}, 'buys': ['hide', 'rope'],
	'lines': ['Кожа любит терпение: неделю в чане, неделю на сушилах.', 'Шкуры несите — выделаю, куплю.'],
})

# Лачуга героя: лежанка у дальней от двери стены — спать даром
hx, hy, hw, hh = bld[HERO_HUT]['rect']
dx, dy = bld[HERO_HUT]['door']
bed = [hx + hw - 2 if dx <= hx + hw // 2 else hx + 1, hy + hh - 2 if dy <= hy + hh // 2 else hy + 1]
d['places'].append({'id': 'hero_bed', 'name': 'Лежанка в лачуге', 'kind': 'bed', 'cell': bed})

stall_props = [i for i, p in enumerate(d['props']) if p['kind'] == 'stall']
well_props = [i for i, p in enumerate(d['props']) if p['kind'] == 'well']
# Колодец на площади — с самого начала, второй (у огородов) — со слободой
south_well = max(well_props, key=lambda i: d['props'][i]['cells'][0][1])

elder_lines = npc['posadnik']['lines']
in_common = {'home': COMMON, 'work': COMMON}
stages = [
	{'name': 'Острог', 'points': 0, 'wall': 'palisade',
	 'names': {COMMON: 'Общий дом', HERO_HUT: 'Лачуга', GUARD_HUT: 'Сторожка у ворот', ELDER_HUT: 'Изба старосты', TANNERY: 'Дубильня Эдрика'},
	 'npc_set': {
		# Пока портнихи нет, рубаху, штаны и шапку продаёт глава из общих запасов (одежда — ветка инвентаря)
		# Глава днём стоит на площади у доски объявлений, ночует в общем доме
		'posadnik': dict(in_common, work_cell=[66, 58], stock={'linen_shirt': 2, 'trousers': 2, 'felt_cap': 1}, buys=[], lines=[
			'Нас трое под одной крышей, а места за частоколом на целый город. Поможешь — люди и придут.',
			'Дела есть у каждого из нас: у меня, у Бригит, у Эдрика. Спрашивай.'] + elder_lines[1:]),
		'healer': dict(in_common),
		'tanner': dict(in_common)}},
	{'name': 'Слобода', 'points': 3,
	 'buildings': ['smithy', 'shop', GUARD_HUT, 'house_1', 'house_3'],
	 'npcs': ['smith', 'trader', 'guard_1', 'farmer', 'widow'],
	 'places': ['well_south'], 'props': stall_props + [south_well],
	 'npc_set': {'guard_1': {'home': GUARD_HUT}}},
	{'name': 'Посад', 'points': 7,
	 'buildings': ['healer', TANNERY, ELDER_HUT, 'tailor', 'house_4', 'house_7'] + qh(9, 10, 11, 12),
	 'npcs': ['innkeeper', 'weaver', 'potter', 'junkman'] + res(9, 10, 11, 12),
	 'names': {COMMON: bld[COMMON]['name']},
	 'npc_set': {'posadnik': {'home': ELDER_HUT, 'work': ELDER_HUT, 'work_cell': None}, 'healer': {'home': 'healer', 'work': 'healer'},
		'tanner': {'home': TANNERY, 'work': TANNERY}}},
	{'name': 'Город', 'points': 12,
	 'buildings': ['barracks', 'house_5', 'house_6'] + qh(1, 2, 3, 4) + qh(*range(13, 21)),
	 'npcs': ['guard_2', 'guard_3', 'kid'] + res(1, 2, 3, 4),
	 'names': {GUARD_HUT: bld[GUARD_HUT]['name']},
	 'npc_set': {'guard_1': {'home': 'barracks'}}},
	{'name': 'Чёрнославль', 'points': 18, 'wall': 'stone',
	 'buildings': ['temple', 'hall'] + qh(5, 6, 7, 8, 22, 23) + qh(*range(26, 35)),
	 'npcs': ['priest', 'scribe'] + res(5, 6, 7, 8),
	 'places': ['altar'],
	 'names': {ELDER_HUT: bld[ELDER_HUT]['name']},
	 'npc_set': {'posadnik': {'home': 'hall', 'work': 'hall', 'lines': elder_lines}}},
]

# Задания: по три у каждого. У троих основателей первое — с острога, у кузнеца, торговки и стражника — со слободы;
# следующее в цепочке открывает следующий этап. Каждое сданное задание — очко роста (points у этапа — сколько нужно)
Q = lambda **k: k
quests = {
	'posadnik': [
		Q(id='elder_1', stage=0, kind='bring', item='scrap', n=2, reward=10, title='Скобы для частокола',
		  ask='Частокол держится на честном слове. Принеси два куска металлолома на скобы — в развалинах его полно.',
		  done='Теперь не завалится. Можно звать людей: пошлю весть по деревням.'),
		Q(id='elder_2', stage=1, kind='pay', money=30, reward=0, title='Казна на срубы',
		  ask='Лес на срубы даром не рубят. Дай в казну 30 монет — поставим новые дворы.',
		  done='Плотники уже тешут брёвна. Будет каждому своя изба.'),
		Q(id='elder_3', stage=2, kind='bring', item='old_coin', n=3, reward=30, title='Довоенные монеты для печати',
		  ask='Городу нужна печать, а на печать — довоенный металл. Принеси три довоенные монеты: в развалинах они попадаются.',
		  done='Будет у Чёрнославля своя печать.'),
	],
	'healer': [
		Q(id='healer_1', stage=0, kind='walk', km=3, reward=10, title='Травы за частоколом',
		  ask='Мне нужны травы, а за частокол одной ходить страшно. Пройди по округе километра три, посмотри, где что растёт.',
		  done='Есть и тысячелистник, и подорожник. Будет чем лечить новых людей.'),
		Q(id='healer_2', stage=1, kind='win', wins=1, reward=15, title='Раненые на дороге',
		  ask='На путников нападают по дороге. Отгони напавших, а уцелевших я перевяжу.',
		  done='Довели раненых. Двое остались жить в слободе.'),
		Q(id='healer_3', stage=2, kind='bring', item='bandage', n=2, reward=18, title='Бинты для знахарской',
		  ask='В своей знахарской без бинтов не обойтись. Принеси два — у Сигрид бывают.',
		  done='Знахарская готова. Посад может спать спокойно.'),
	],
	'tanner': [
		Q(id='tanner_1', stage=0, kind='win', wins=1, reward=12, title='Зверь у реки',
		  ask='У реки бродит зверь, к воде не подойти. Разберись с ним — и шкуры будут.',
		  done='Теперь и воду носить не страшно. Начну выделку.'),
		Q(id='tanner_2', stage=1, kind='bring', item='rope', n=2, reward=12, title='Верёвки для сушил',
		  ask='Шкуры сушить не на чем. Принеси две верёвки — у Сигрид бывают.',
		  done='Сушила натянуты. Будет кожа на сапоги слобожанам.'),
		Q(id='tanner_3', stage=2, kind='pay', money=25, reward=0, title='Своя дубильня',
		  ask='В общем доме от моих чанов все морщатся. На свою дубильню нужно 25 монет.',
		  done='Дубильня стоит, и в общем доме опять можно дышать.'),
	],
	'smith': [
		Q(id='smith_1', stage=1, kind='bring', item='scrap', n=3, reward=12, title='Лом для горна',
		  ask='Без железа горн холодный. Принеси три куска металлолома.',
		  done='Вот теперь застучит молот. Слобожанам будут гвозди и скобы.'),
		Q(id='smith_2', stage=2, kind='win', wins=1, reward=15, title='Проверить клинок',
		  ask='Нож, что я кую, надо проверить в деле. Отбейся от кого-нибудь за стенами и расскажи, как держал.',
		  done='Держал, говоришь? Значит, можно ковать стражникам.'),
		Q(id='smith_3', stage=3, kind='bring', item='scrap', n=5, reward=25, title='Оковки на ворота',
		  ask='Городу нужны оковки на ворота и петли на казарму. Пять кусков лома — и будут.',
		  done='Ворота окованы. Таким городом и посадника не стыдно звать.'),
	],
	'trader': [
		Q(id='trader_1', stage=1, kind='walk', km=5, reward=12, title='Дорога для обозов',
		  ask='Обозы не пойдут, пока никто не прошёл дорогу. Пройди километров пять и вернись живым.',
		  done='Расскажу купцам, что дорога есть.'),
		Q(id='trader_2', stage=2, kind='bring', item='vegetables', n=4, reward=14, title='Овощи на торг',
		  ask='На торгу пусто. Принеси четыре пучка овощей с огородов у западной стены.',
		  done='Есть чем торговать — будут и покупатели.'),
		Q(id='trader_3', stage=3, kind='pay', money=40, reward=0, title='Пай в торговый ряд',
		  ask='Хочу расширить ряды вокруг площади. Вложи 40 монет — вернётся торговлей.',
		  done='Ряды будут. И цены у меня для тебя — свои.'),
	],
	'guard_1': [
		Q(id='guard_1', stage=1, kind='win', wins=1, reward=15, title='Разбойники у дороги',
		  ask='У дороги шалят. Одному мне ворота не бросить — разгони их сам.',
		  done='Тихо стало. Люди перестанут бояться к нам идти.'),
		Q(id='guard_2', stage=2, kind='walk', km=6, reward=12, title='Дозор',
		  ask='Обойди дозором окрестности — километров шесть. Посмотри, кто ходит у наших земель.',
		  done='Чисто, говоришь. Можно ставить казарму.'),
		Q(id='guard_3', stage=3, kind='win', wins=2, reward=25, title='Науки для новых стражников',
		  ask='Новички держат копьё как вилы. Покажи им, как бьются: две победы за стенами.',
		  done='Теперь стражей не стыдно ставить на каменную стену.'),
	],
}

# Проверки: всё, что появляется на этапах, есть в пуле; нулевой этап — трое в общем доме и лачуга
later_b = {b for s in stages[1:] for b in s.get('buildings', [])}
later_n = {n for s in stages[1:] for n in s.get('npcs', [])}
for b in later_b:
	assert b in bld, b
for n in later_n:
	assert n in npc, n
base_n = [n['id'] for n in d['npcs'] if n['id'] not in later_n]
assert sorted(base_n) == sorted(['posadnik', 'healer', 'tanner']), base_n
base_b = [b['id'] for b in d['buildings'] if b['id'] not in later_b and b['kind'] != 'ruins']
assert sorted(base_b) == sorted([COMMON, HERO_HUT]), base_b
for nid, chain in quests.items():
	assert nid in [n['id'] for n in d['npcs']], nid
	for i, q in enumerate(chain):
		assert q['stage'] == i + (0 if nid in ('posadnik', 'healer', 'tanner') else 1), q['id']
total = sum(len(c) for c in quests.values())
assert stages[-1]['points'] == total, total

d['growth'] = {
	'_note': 'Рост города (Huzzah 2026-10-23). Этап — по числу сданных заданий (points). Что не упомянуто в этапах 1+, стоит с начала. Генератор: tools/make_city_growth.py',
	'stages': stages, 'quests': quests,
}
json.dump(d, open(out_path, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
print('этапы:', [(s['name'], s['points'], len(s.get('buildings', [])), len(s.get('npcs', []))) for s in stages])
print('с начала: дома', base_b, 'жители', base_n)

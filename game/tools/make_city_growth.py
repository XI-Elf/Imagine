# Місто, що росте (Huzzah 2026-10-23): початкове місто майже порожнє — халупа героя й один спільний дім на трьох
# (голова поселення, травниця, шкіряник). Місто всередині стіни росте, коли герой виконує їхні завдання;
# із селом приходять коваль, торговка й стражник зі своїми завданнями. Решта будинків і мешканців колишнього
# Эшвика — пул для етапів росту.
# Додає в опис міста шкіряника, халупу героя (місце "bed") і розділ "growth":
#   stages[i] = {name, points, wall?, buildings, npcs, places, props — що з'являється на етапі i,
#                names — перейменування будинків, npc_set — поля мешканців (дім, робота, репліки)}
#   quests = {id НПС: [{id, stage, title, kind, ...}]} — kind: walk (km), win (wins), bring (item, n), pay (money)
# Що не згадано в жодному етапі після нульового, стоїть від самого початку (руїни, дерева, поля, дороги).
# Запуск: python3 make_city_growth.py <s001.json> <вихідний s001.json>
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


# Нульовий етап (Huzzah 2026-10-23: «усі мають жити в одному», спершу троє — голова поселення, травник, шкіряник):
# халупа героя й один спільний дім (майбутня таверна), де живуть і працюють усі троє
COMMON, HERO_HUT, GUARD_HUT, ELDER_HUT, TANNERY = 'inn', 'quarter_house_24', 'quarter_house_25', 'quarter_house_21', 'house_2'
for b in [COMMON, HERO_HUT, GUARD_HUT, ELDER_HUT, TANNERY]:
	assert b in bld, b

# Шкіряник — новий мешканець, ім'я англосаксонське (Huzzah: нові імена норвезькі й англосаксонські)
d['npcs'].append({
	'id': 'tanner', 'name': 'Кожевник Эдрик', 'role': 'tanner', 'home': TANNERY, 'work': TANNERY,
	# Одяг (гілка інвентарю): кравчиня й лахмітник прийдуть лише з бургом, а шкіряне — у шкіряника від самого початку.
	# Ніж — теж у шкіряника з «Форту» (питання Q02, Huzzah 2026-10-24): перший бій кулаками непрохідний
	'hours': [7, 19], 'skill': 'sewing', 'stock': {'rope': 4, 'knife': 2, 'leather_jacket': 1, 'boots': 2, 'gloves': 3}, 'buys': ['hide', 'rope'],
	'lines': ['Кожа любит терпение: неделю в чане, неделю на сушилах.', 'Шкуры несите — выделаю, куплю.'],
})

# Халупа героя: лежанка біля дальньої від дверей стіни — спати задарма
hx, hy, hw, hh = bld[HERO_HUT]['rect']
dx, dy = bld[HERO_HUT]['door']
bed = [hx + hw - 2 if dx <= hx + hw // 2 else hx + 1, hy + hh - 2 if dy <= hy + hh // 2 else hy + 1]
d['places'].append({'id': 'hero_bed', 'name': 'Лежанка в лачуге', 'kind': 'bed', 'cell': bed})

stall_props = [i for i, p in enumerate(d['props']) if p['kind'] == 'stall']
well_props = [i for i, p in enumerate(d['props']) if p['kind'] == 'well']
# Криниця на площі — від самого початку, друга (біля городів) — із селом
south_well = max(well_props, key=lambda i: d['props'][i]['cells'][0][1])

elder_lines = npc['posadnik']['lines']
# Голова стоїть біля дошки оголошень на площі
BOARD = next(list(p['cell']) for p in d['places'] if p['id'] == 'notice_board')
BOARD = [BOARD[0], BOARD[1] + 1]
in_common = {'home': COMMON, 'work': COMMON}
stages = [
	{'name': 'Форт', 'points': 0, 'wall': 'palisade',
	 'names': {COMMON: 'Общий дом', HERO_HUT: 'Лачуга', GUARD_HUT: 'Сторожка у ворот', ELDER_HUT: 'Дом олдермена', TANNERY: 'Дубильня Эдрика'},
	 'npc_set': {
		# Поки кравчині немає, сорочку, штани й шапку продає голова зі спільних запасів (одяг — гілка інвентарю)
		# Голова вдень стоїть на площі біля дошки оголошень, ночує в спільному домі
		'posadnik': dict(in_common, work_cell=BOARD, stock={'linen_shirt': 2, 'trousers': 2, 'felt_cap': 1}, buys=[], lines=[
			'Нас трое под одной крышей, а места за частоколом на целый город. Поможешь — люди и придут.',
			'Дела есть у каждого из нас: у меня, у Бригит, у Эдрика. Спрашивай.'] + elder_lines[1:]),
		'healer': dict(in_common),
		'tanner': dict(in_common)}},
	{'name': 'Деревня', 'points': 3,
	 'buildings': ['smithy', 'shop', GUARD_HUT, 'house_1', 'house_3'],
	 'npcs': ['smith', 'trader', 'guard_1', 'farmer', 'widow'],
	 'places': ['well_south'], 'props': stall_props + [south_well],
	 'npc_set': {'guard_1': {'home': GUARD_HUT}}},
	{'name': 'Бург', 'points': 7,
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
	{'name': 'Крупный город', 'points': 18, 'wall': 'stone',
	 'buildings': ['temple', 'hall'] + qh(5, 6, 7, 8, 22, 23) + qh(*range(26, 35)),
	 'npcs': ['priest', 'scribe'] + res(5, 6, 7, 8),
	 'places': ['altar'],
	 'names': {ELDER_HUT: bld[ELDER_HUT]['name']},
	 'npc_set': {'posadnik': {'home': 'hall', 'work': 'hall', 'lines': elder_lines}}},
]

# Маленьке місто (Huzzah 2026-10-24) — не всі будинки кварталів є в плані
for st in stages:
	if 'buildings' in st:
		st['buildings'] = [b for b in st['buildings'] if b in bld]

# Завдання: по три в кожного. У трьох засновників перше — з форту, у коваля, торговки й стражника — із села;
# наступне в ланцюжку відкриває наступний етап. Кожне здане завдання — очко росту (points у етапу — скільки потрібно)
Q = lambda **k: k
quests = {
	'posadnik': [
		Q(id='elder_1', stage=0, kind='bring', item='scrap', n=2, reward=10, title='Скобы для частокола',
		  ask='Частокол держится на честном слове. Принеси два куска металлолома на скобы — в развалинах его полно.',
		  done='Теперь не завалится. Можно звать людей: пошлю весть по деревням.'),
		Q(id='elder_2', stage=1, kind='pay', money=30, reward=0, title='Казна на новые дома',
		  ask='Лес на дома даром не рубят. Дай в казну 30 монет — поставим новые дворы.',
		  done='Плотники уже тешут брёвна. Будет каждому свой дом.'),
		Q(id='elder_3', stage=2, kind='bring', item='old_coin', n=3, reward=30, title='Древные монеты для печати',
		  ask='Городу нужна печать, а на печать — древный металл. Принеси три древные монеты: в развалинах они попадаются.',
		  done='Будет у Эшвика своя печать.'),
	],
	'healer': [
		Q(id='healer_1', stage=0, kind='walk', km=3, reward=10, title='Травы за частоколом',
		  ask='Мне нужны травы, а за частокол одной ходить страшно. Пройди по округе километра три, посмотри, где что растёт.',
		  done='Есть и тысячелистник, и подорожник. Будет чем лечить новых людей.'),
		Q(id='healer_2', stage=1, kind='win', wins=1, reward=15, title='Раненые на дороге',
		  ask='На путников нападают по дороге. Отгони напавших, а уцелевших я перевяжу.',
		  done='Довели раненых. Двое остались жить в деревне.'),
		Q(id='healer_3', stage=2, kind='bring', item='bandage', n=2, reward=18, title='Бинты для лечебницы',
		  ask='В своей лечебнице без бинтов не обойтись. Принеси два — у Сигрид бывают.',
		  done='Лечебница готова. Бург может спать спокойно.'),
	],
	'tanner': [
		Q(id='tanner_1', stage=0, kind='win', wins=1, reward=12, title='Зверь у реки',
		  ask='У реки бродит зверь, к воде не подойти. Разберись с ним — и шкуры будут.',
		  done='Теперь и воду носить не страшно. Начну выделку.'),
		Q(id='tanner_2', stage=1, kind='bring', item='rope', n=2, reward=12, title='Верёвки для сушил',
		  ask='Шкуры сушить не на чем. Принеси две верёвки — у Сигрид бывают.',
		  done='Сушила натянуты. Будет кожа на сапоги поселенцам.'),
		Q(id='tanner_3', stage=2, kind='pay', money=25, reward=0, title='Своя дубильня',
		  ask='В общем доме от моих чанов все морщатся. На свою дубильню нужно 25 монет.',
		  done='Дубильня стоит, и в общем доме опять можно дышать.'),
	],
	'smith': [
		Q(id='smith_1', stage=1, kind='bring', item='scrap', n=3, reward=12, title='Лом для горна',
		  ask='Без железа горн холодный. Принеси три куска металлолома.',
		  done='Вот теперь застучит молот. Поселенцам будут гвозди и скобы.'),
		Q(id='smith_2', stage=2, kind='win', wins=1, reward=15, title='Проверить клинок',
		  ask='Нож, что я кую, надо проверить в деле. Отбейся от кого-нибудь за стенами и расскажи, как держал.',
		  done='Держал, говоришь? Значит, можно ковать стражникам.'),
		Q(id='smith_3', stage=3, kind='bring', item='scrap', n=5, reward=25, title='Оковки на ворота',
		  ask='Городу нужны оковки на ворота и петли на казарму. Пять кусков лома — и будут.',
		  done='Ворота окованы. Таким городом и олдермена не стыдно звать.'),
	],
	'trader': [
		Q(id='trader_1', stage=1, kind='walk', km=5, reward=12, title='Дорога для обозов',
		  ask='Обозы не пойдут, пока никто не прошёл дорогу. Пройди километров пять и вернись живым.',
		  done='Расскажу купцам, что дорога есть.'),
		Q(id='trader_2', stage=2, kind='bring', item='vegetables', n=4, reward=14, title='Овощи на рынок',
		  ask='На рынке пусто. Принеси четыре пучка овощей с огородов у западной стены.',
		  done='Есть чем торговать — будут и покупатели.'),
		Q(id='trader_3', stage=3, kind='pay', money=40, reward=0, title='Доля в рыночных лавках',
		  ask='Хочу расширить лавки вокруг площади. Вложи 40 монет — вернётся торговлей.',
		  done='Лавки будут. И цены у меня для тебя — свои.'),
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

# Запасні доручення (питання Q03, Huzzah 2026-10-24: «близько 24 доручень на 18 очок росту»): по одному в кожного,
# мирні, беруться в будь-якому порядку поруч з основним ланцюжком. Якщо основне не під силу (бій кулаками), ріст не стає
spares = {
	'posadnik': Q(id='elder_s', stage=0, spare=True, kind='walk', km=2, reward=8, title='Обойти межи',
		ask='Межевые камни растащили, кто куда. Обойди округу километра два и запомни, где наша земля кончается.',
		done='Теперь знаю, докуда пахать. Соседям так и скажу.'),
	'healer': Q(id='healer_s', stage=0, spare=True, kind='pay', money=10, reward=0, title='Ступка и котелок',
		ask='Травы есть, а растереть и сварить не в чем. Дай 10 монет на ступку и котелок.',
		done='Теперь и отвар будет, и мазь. Спасибо.'),
	'tanner': Q(id='tanner_s', stage=0, spare=True, kind='walk', km=2, reward=8, title='Дубовая кора',
		ask='Для чанов нужна кора, а дубы далеко. Пройди километра два, найди мне рощу поближе.',
		done='Есть роща у оврага. Хватит на всю зиму.'),
	'smith': Q(id='smith_s', stage=1, spare=True, kind='pay', money=20, reward=0, title='Уголь для горна',
		ask='Лом есть, угля нет. Дай 20 монет углежогам — и горн не остынет.',
		done='Угля на месяц. Куй сколько влезет.'),
	'trader': Q(id='trader_s', stage=2, spare=True, kind='walk', km=4, reward=10, title='Весть купцам',
		ask='Купцы не знают, что у нас рынок. Пройди километра четыре по дорогам, расскажи встречным.',
		done='Уже спрашивают, когда ярмарка. Твоя работа.'),
	'guard_1': Q(id='guard_s', stage=2, spare=True, kind='bring', item='rope', n=2, reward=10, title='Верёвки для сторожки',
		ask='Колокол у ворот висит на гнилой верёвке. Принеси две крепкие — у Эдрика бывают.',
		done='Теперь, если что, весь город услышит.'),
}
for nid, q in spares.items():
	quests[nid].append(q)

# Перевірки: усе, що з'являється на етапах, є в пулі; нульовий етап — троє в спільному домі й халупа
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
	for i, q in enumerate([q for q in chain if not q.get('spare')]):
		assert q['stage'] == i + (0 if nid in ('posadnik', 'healer', 'tanner') else 1), q['id']
total = sum(len(c) for c in quests.values())
main = sum(1 for c in quests.values() for q in c if not q.get('spare'))
assert stages[-1]['points'] == main == 18 and total == 24, (main, total)
# На кожному етапі очок із запасом: доступних до нього доручень більше, ніж потрібно для наступного етапу
for k in range(1, len(stages)):
	open_q = sum(1 for c in quests.values() for q in c if q['stage'] < k)
	assert open_q > stages[k]['points'] or k == len(stages) - 1, (k, open_q)

d['growth'] = {
	'_note': 'Рост города (Huzzah 2026-10-23). Этап — по числу сданных заданий (points). Что не упомянуто в этапах 1+, стоит с начала. Генератор: tools/make_city_growth.py',
	'stages': stages, 'quests': quests,
}
json.dump(d, open(out_path, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
print('этапы:', [(s['name'], s['points'], len(s.get('buildings', [])), len(s.get('npcs', []))) for s in stages])
print('с начала: дома', base_b, 'жители', base_n)

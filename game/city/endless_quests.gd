extends RefCounted
## Бесконечные поручения (вопрос Q14, Huzzah 2026-10-24, вариант «песочница»): когда город вырос до последнего
## этапа («Крупный город»), каждый из шести НПС с цепочкой роста раз за разом даёт новое случайное поручение.
## Поручение — тот же словарь, что и в цепочках city_growth.gd (kind walk / win / bring), плюс "endless": true и "npc".
## Номер n следующего поручения НПС = сданных бесконечных + 1; id "<нпс>~e<n>". Поручение собирается заново
## из (город, НПС, n), поэтому взятое помнится через обычное growth.taken, а сданное — через growth.done.
## Очков роста они не дают (город уже вырос), только награду; с номером поручения объёмы растут, но с потолком.

const MARK := "~e"

## Что приносить: только то, что в игре добывается (обыск развалин и тайников, бандиты, огороды, шкуры со зверей в бою).
## Q33 (Huzzah 2026-10-27, вариант B): кожевник просит только шкуры, кузнец только лом
const PRICE: Dictionary = {"scrap": 3, "old_coin": 12, "vegetables": 2, "hide": 7}

## Формы слов для 1, 2–4, 5+ (винительный падеж после «принеси», «пройди»)
static var WORDS: Dictionary = {
	"km": [I18n.t("километр"), I18n.t("километра"), I18n.t("километров")],
	"scrap": [I18n.t("кусок металлолома"), I18n.t("куска металлолома"), I18n.t("кусков металлолома")],
	"old_coin": [I18n.t("довоенную монету"), I18n.t("довоенные монеты"), I18n.t("довоенных монет")],
	"vegetables": [I18n.t("пучок овощей"), I18n.t("пучка овощей"), I18n.t("пучков овощей")],
	"hide": [I18n.t("шкуру"), I18n.t("шкуры"), I18n.t("шкур")],
}
static var WINS: Array = [I18n.t("в одном бою"), I18n.t("в двух боях")]

## Виды поручений у каждого НПС и тексты: title, ask, done (у «принести» ещё вещь); %s — сколько, словами с числом («3 километра», «в двух боях»)
static var POOL: Dictionary = {
	"posadnik": {
		"walk": [
			[I18n.t("Гонец в деревни"), I18n.t("Надо снести весть по дальним дворам: в Эшвике рынок и защита. Пройди %s."), I18n.t("Весть разошлась. Ждём новых людей к зиме.")],
			[I18n.t("Межи после половодья"), I18n.t("Вода снесла межевые вехи. Обойди землю, %s, и поставь, где были."), I18n.t("Межи на месте, споров меньше.")],
		],
		"win": [
			[I18n.t("Дорога без разбоя"), I18n.t("На большой дороге снова грабят обозы. Отбейся от них: победи %s."), I18n.t("Купцы снова ездят. Город тебе обязан.")],
		],
		"bring": [
			[I18n.t("Монеты для казны"), I18n.t("Печатникам опять нужен довоенный металл. Принеси %s."), I18n.t("Отчеканим новые хартии. Держи плату."), "old_coin"],
		],
	},
	"healer": {
		"walk": [
			[I18n.t("Редкие корни"), I18n.t("Лихорадочный корень растёт далеко за стеной. Пройди %s и примечай, где он."), I18n.t("Нашлись корни. Хватит на зиму отваров.")],
			[I18n.t("Обход больных"), I18n.t("По фермам лежат больные, а мне не дойти. Пройди %s, расскажи, кто как."), I18n.t("Теперь знаю, к кому идти первой.")],
		],
		"win": [
			[I18n.t("Тропа к роднику"), I18n.t("У целебного родника завелось зверьё. Расчисти тропу: победи %s."), I18n.t("Родник снова наш. Вода в нём лечит лучше моих отваров.")],
		],
		"bring": [
			[I18n.t("Овощи для лазарета"), I18n.t("Больных нечем кормить. Принеси %s с огородов."), I18n.t("Похлёбка будет. Спасибо."), "vegetables"],
		],
	},
	"tanner": {
		"walk": [
			[I18n.t("Звериные тропы"), I18n.t("Хочу ставить силки, а троп не знаю. Пройди по лесам %s."), I18n.t("Тропы нашлись. Будет кожа.")],
		],
		"win": [
			[I18n.t("Зверь у чанов"), I18n.t("Опять повадился зверь к дубильне. Разберись: победи %s."), I18n.t("Тихо у чанов. Работа пошла.")],
		],
		"bring": [
			[I18n.t("Шкуры в чан"), I18n.t("Чаны пустуют. Принеси %s — волчьи, кабаньи, какие добудешь."), I18n.t("Добрые шкуры. Держи за труды."), "hide"],
			[I18n.t("Мех на зиму"), I18n.t("Зимой будут спрашивать тёплое. Принеси %s."), I18n.t("Хватит на пару плащей. Плачу."), "hide"],
		],
	},
	"smith": {
		"win": [
			[I18n.t("Клинок в деле"), I18n.t("Выковал новую партию. Проверь: победи %s и расскажи, как держит."), I18n.t("Держит, значит. Отдам страже.")],
		],
		"bring": [
			[I18n.t("Железо для горна"), I18n.t("Заказов больше, чем железа. Принеси %s."), I18n.t("Горн не остынет. Держи плату."), "scrap"],
			[I18n.t("Лом на подковы"), I18n.t("Подков не напасёшься. Принеси %s из развалин."), I18n.t("Будут подковы. Плачу, как обещал."), "scrap"],
		],
	},
	"trader": {
		"walk": [
			[I18n.t("Новый путь для обоза"), I18n.t("Купцы спрашивают другой путь. Пройди %s и запомни дорогу."), I18n.t("Расскажу обозникам. Вот твоя доля.")],
		],
		"bring": [
			[I18n.t("Овощи на ярмарку"), I18n.t("Ярмарка скоро, а прилавки пусты. Принеси %s."), I18n.t("Будет чем торговать. Держи."), "vegetables"],
			[I18n.t("Монеты для менял"), I18n.t("Заезжие меняют довоенные монеты втридорога. Принеси %s, и поделим выгоду."), I18n.t("Хорошая сделка. Твоя доля."), "old_coin"],
		],
	},
	"guard_1": {
		"walk": [
			[I18n.t("Дальний дозор"), I18n.t("Обойди дозором дальние земли, %s. Смотри, кто ходит у границ."), I18n.t("Чисто, говоришь. Спать будем спокойней.")],
		],
		"win": [
			[I18n.t("Разбойники у стен"), I18n.t("Снова шайка у стен. Разгони их: победи %s."), I18n.t("Стражники видели, как ты бился. Уважают.")],
			[I18n.t("Учения"), I18n.t("Новобранцам нужен пример. Покажи им бой за стенами: победи %s."), I18n.t("Теперь копья держат как надо.")],
		],
	},
}


static func is_endless(q: Dictionary) -> bool:
	return bool(q.get("endless", false))


## Бесконечные поручения есть у НПС, если город на последнем этапе и у НПС есть свои виды поручений
static func open_for(def: Dictionary, st: int, npc_id: String) -> bool:
	var stages: Array = def.get("growth", {}).get("stages", [])
	return not stages.is_empty() and st >= stages.size() - 1 and POOL.has(npc_id)


## Сколько бесконечных поручений НПС уже сдано
static func done_count(g: Dictionary, npc_id: String) -> int:
	var pre: String = npc_id + MARK
	var k: int = 0
	for id in g.get("done", []):
		if String(id).begins_with(pre):
			k += 1
	return k


## Следующее поручение НПС (одно на НПС за раз): то же, пока не сдано
static func next_for(def: Dictionary, g: Dictionary, npc_id: String) -> Dictionary:
	return make(String(def.get("id", "")), npc_id, done_count(g, npc_id) + 1)


## Поручение номер n (с 1) у НПС в городе city_id: одно и то же при каждом вызове
static func make(city_id: String, npc_id: String, n: int) -> Dictionary:
	var pool: Dictionary = POOL.get(npc_id, {})
	if pool.is_empty():
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([city_id, npc_id, n])
	var t: Array = _texts(pool)[_pick(city_id, npc_id, n, _texts(pool).size())]
	var kind: String = String(t[0])
	t = t[1]
	var grow: int = mini((n - 1) / 3, 3)  # каждые три поручения чуть больше, не больше +3
	var q: Dictionary = {"id": "%s%s%d" % [npc_id, MARK, n], "npc": npc_id, "endless": true, "kind": kind, "stage": 0}
	var amount: int
	var how: String = ""
	match kind:
		"walk":
			amount = rng.randi_range(3, 5) + grow
			q["km"] = amount
			how = _count(amount, "km")
			q["reward"] = 3 * amount + 2
		"win":
			amount = 1 + (1 if grow >= 2 and rng.randf() < 0.5 else 0)
			q["wins"] = amount
			how = WINS[amount - 1]
			q["reward"] = 14 * amount + 2 * grow
		"bring":
			var item: String = String(t[3])
			amount = (rng.randi_range(2, 3) + grow) if item != "old_coin" else (1 + grow / 2)
			q["item"] = item
			q["n"] = amount
			how = _count(amount, item)
			# Дороже, чем продать торговке: поручение выгоднее сбыта
			q["reward"] = int(ceil(float(PRICE[item]) * amount * 1.5)) + 4
	q["title"] = String(t[0])
	q["ask"] = String(t[1]) % how
	q["done"] = String(t[2])
	return q


## Все тексты НПС подряд: [вид, [title, ask, done]]
static func _texts(pool: Dictionary) -> Array:
	var out: Array = []
	var kinds: Array = pool.keys()
	kinds.sort()
	for k in kinds:
		for t in pool[k]:
			out.append([k, t])
	return out


## Какой текст у поручения n: тексты идут кругами, в каждом круге — все по разу в случайном порядке;
## на стыке кругов тот же текст два раза подряд не выпадает
static func _pick(city_id: String, npc_id: String, n: int, size: int) -> int:
	if size <= 1:
		return 0
	var c: int = (n - 1) / size
	var order: Array = _round(city_id, npc_id, c, size)
	return int(order[(n - 1) % size])


static func _round(city_id: String, npc_id: String, c: int, size: int) -> Array:
	var order: Array = range(size)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([city_id, npc_id, "round", c])
	for i in range(size - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var x = order[i]
		order[i] = order[j]
		order[j] = x
	if c > 0 and order[0] == _round(city_id, npc_id, c - 1, size)[size - 1]:
		var x = order[0]
		order[0] = order[1]
		order[1] = x
	return order


## «1 километр», «3 куска металлолома», «5 довоенных монет»
static func _count(k: int, word: String) -> String:
	var f: Array = WORDS[word]
	var m10: int = k % 10
	var m100: int = k % 100
	var i: int = 2
	if m10 == 1 and m100 != 11:
		i = 0
	elif m10 >= 2 and m10 <= 4 and (m100 < 12 or m100 > 14):
		i = 1
	return "%d %s" % [k, f[i]]

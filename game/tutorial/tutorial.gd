extends CanvasLayer
## Навчання: довідка за клавішами (F1 будь-коли) і короткі підказки по ходу гри під час першого запуску.
## Автозавантаження Tutorial. Чужі скрипти не змінює: стан читає у Worlds (карта, місто, бій, герой).
## Підказки показуються по одній у куті, введення не забирають; кожна — один раз. Що показано й чи вимкнено
## навчання, зберігається в user://tutorial.cfg (спільне для всіх збережень). Поки відкрита довідка, гра на паузі.

const SAVE_PATH := "user://tutorial.cfg"
const CHECK_S: float = 0.5          # як часто перевіряти умови підказок
const GAP_S: float = 2.0            # пауза між підказками
const MIN_SHOW_S: float = 3.0       # підказку, чию справу вже зроблено, тримаємо хоча б стільки
const MAX_SHOW_S: float = 30.0      # і не довше за це, якщо гравець її не закрив
const CARD_W: float = 400.0

const C_BG := Color(0.08, 0.07, 0.06, 0.93)
const C_EDGE := Color("c9a24b")
const C_TEXT := Color("e6dcc0")
const C_DIM := Color("8a8470")
const C_KEY := Color("f0c860")

## Довідка за клавішами, зібрана з коду: game.gd, characters/cast.gd, characters/transport.gd, world/settlements.gd, worlds/worlds.gd,
## city/city_world.gd, battle/battle_scene.gd. [клавіша, що робить]; рядок без клавіші — підзаголовок.
static var KEYS: Dictionary = {
	I18n.t("Карта"): [
		[I18n.t("Камера")],
		[I18n.t("WASD / стрелки"), I18n.t("двигать камеру (когда герой не под управлением)")],
		[I18n.t("Колесо мыши, + −"), I18n.t("масштаб (колесо — к курсору, + − — к центру)")],
		["M", I18n.t("глобальная карта: видна только исследованная часть мира, остальное в тумане; ещё раз M — назад к герою")],
		["Shift+M", I18n.t("перейти к точке «X Y» (Esc — закрыть поле)")],
		["O", I18n.t("маркер в центре экрана: данные панели для центра, а не под курсором")],
		["H", I18n.t("подробная панель")],
		[I18n.t("Мир")],
		["P", I18n.t("пауза игрового времени")],
		["[  ]", I18n.t("медленнее / быстрее время")],
		[",  .", I18n.t("медленнее / быстрее погода")],
		["C", I18n.t("облака сверху")],
		["B", I18n.t("границы: нет / области / области и регионы")],
		[I18n.t("Общее")],
		["F1", I18n.t("эта справка (в любой момент, игра на паузе)")],
		["F9", I18n.t("звук вкл/выкл (audio/sfx.gd)")],
		["Esc", I18n.t("меню паузы: сохранить, выйти в меню")],
		[I18n.t("Новая игра"), I18n.t("сначала создание героя: Enter — создать, «Случайно», Esc — назад")],
	],
	I18n.t("Герой"): [
		["G", I18n.t("переключить: герой ↔ свободная камера (после гибели экран нового героя открывается сам)")],
		[I18n.t("WASD / стрелки"), I18n.t("идти (пока открыто окно героя или меню, герой стоит)")],
		["Shift", I18n.t("бег — тратит Силы")],
		["Z", I18n.t("лечь спать / проснуться (шаг тоже будит)")],
		["E", I18n.t("пить из реки или озера рядом")],
		["F", I18n.t("искать еду вокруг; у руин — обыскать их (металлолом, монеты); у повозки погибшего героя — забрать её")],
		["T", I18n.t("лечиться у лекаря-НПС, если он рядом (до 30 м)")],
		["R", I18n.t("верхом / пешком, если есть лошадь (повозка едет следом); у ворот города R — набрать воды")],
		["I", I18n.t("окно героя: характеристики, состояния")],
		["Tab", I18n.t("окно героя: инвентарь — съесть, выпить, выбросить, взять в бой (до 3 видов оружия)")],
		[I18n.t("Окно героя")],
		["1 … 6", I18n.t("вкладки: Характеристики, Навыки, Дары, Черты характера, Инвентарь, Дневник (найденные записки о мире)")],
		["I / Tab / Esc", I18n.t("закрыть (пока окно открыто, герой стоит)")],
		[I18n.t("Мышь")],
		[I18n.t("ЛКМ по карте"), I18n.t("герой идёт туда сам, в обход стен и проклятых земель; держать — вести за курсором")],
		[I18n.t("ЛКМ по городу"), I18n.t("идти к воротам; при открытом выборе у города клик — продолжить путь")],
		[I18n.t("ПКМ"), I18n.t("остановиться (WASD тоже перебивает путь, Shift — бежать по пути)")],
		[I18n.t("Тропы")],
		[I18n.t("Протоптать"), I18n.t("10 проходов по одному месту — тропинка, дальше тропа, просёлок, грунтовая дорога; по ним идти быстрее, путь мышью выбирает их; тропинка и тропа без хождения зарастают")],
		[I18n.t("У города")],
		["E / Enter", I18n.t("у ворот — войти; у стены — попытаться проникнуть")],
		[I18n.t("Esc / шаг"), I18n.t("продолжить путь мимо")],
	],
	I18n.t("Город"): [
		[I18n.t("WASD / стрелки"), I18n.t("идти")],
		["Shift", I18n.t("бег — тратит Силы")],
		["E", I18n.t("говорить, пить у колодца, обыскать тайник, осмотреть")],
		[I18n.t("ЛКМ"), I18n.t("идти к месту; по жителю — подойти и заговорить; по колодцу, тайнику, воротам — подойти и сделать")],
		[I18n.t("ПКМ"), I18n.t("остановиться")],
		["1 … 9", I18n.t("выбрать ответ или товар в разговоре")],
		["I / Tab", I18n.t("окно героя: характеристики / инвентарь (съесть, выпить)")],
		["M", I18n.t("план города")],
		[I18n.t("Колесо мыши"), I18n.t("масштаб")],
		["Esc", I18n.t("закрыть окно; если окон нет — меню паузы")],
		[I18n.t("Выход"), I18n.t("через ворота (ночью их открывает стражник за 5 монет)")],
	],
	I18n.t("Бой"): [
		[I18n.t("Мышь")],
		[I18n.t("ЛКМ по клетке"), I18n.t("идти (видна цена хода в клетках и угроза атаки по возможности)")],
		[I18n.t("ЛКМ по врагу"), I18n.t("атаковать (далеко — подойти и ударить)")],
		[I18n.t("Наведение на врага"), I18n.t("шанс попадания, урон, защита, укрытие")],
		[I18n.t("ПКМ / Esc"), I18n.t("отменить выбор")],
		[I18n.t("Клавиши")],
		["1", I18n.t("обычная атака")],
		["2 … 7", I18n.t("способности")],
		["D", I18n.t("рывок — двойное перемещение")],
		["G", I18n.t("отход — без атак по возможности")],
		["V", I18n.t("уклонение")],
		["H", I18n.t("помочь союзнику")],
		["K", I18n.t("спрятаться")],
		["U", I18n.t("выпить зелье")],
		["R", I18n.t("подготовить атаку")],
		["Q", I18n.t("сменить оружие")],
		["X", I18n.t("уйти с края поля")],
		["C", I18n.t("спутники: ходят сами / под вашим управлением")],
		[I18n.t("Пробел / Enter"), I18n.t("конец хода; после боя — вернуться")],
	],
}

## Основні механіки — коротко, своїми словами; числа з data/characters/rules.json і data/cities/s001.json
static var MECHANICS: Array = [
	[I18n.t("Мир Тёмной эпохи"), I18n.t("Идёт 1488 год Тёмной эпохи: она отсчитывается от конца Трёх человеческих империй. Цивилизация не исчезла, а потеряла единство: у каждого города свои вода, еда и мастера, дороги опасны. Людей мало, они уязвимы. Проклятые земли — след древних катастроф. Подробности на вкладке «Хроника».")],
	[I18n.t("Нужды"), I18n.t("Сытость, Вода и Энергия убывают по игровым часам. Пустая Вода или Сытость отнимает здоровье. Пить — E у воды (сырая вода иногда даёт дизентерию), есть — F на карте или из инвентаря (Tab), спать — Z. После 8 часов сна — «Отдохнувший»: шаг быстрее.")],
	[I18n.t("Силы и движение"), I18n.t("Бег (Shift) и плавание тратят Силы, шагом они восстанавливаются. Без сил в воде герой тонет. Лес, болото, горы замедляют; ночью шаг на 20 % медленнее, перегруз тоже тормозит.")],
	[I18n.t("Воздействие проклятья"), I18n.t("Проклятые лес, пустошь и болото каждый час усиливают воздействие проклятья. Оно спадает только на чистой земле. От 100 начинается проклятая хворь, от 200 и 350 — тяжелее.")],
	[I18n.t("Температура"), I18n.t("В оранжевых жарких горах на 40 °C жарче. Выше 35 °C жажда растёт в 1,6 раза, ниже 0 °C энергия тратится в 1,5 раза быстрее. Мокрая одежда холодит ещё на 4 °C.")],
	[I18n.t("Травмы и болезни"), I18n.t("Падения в горах, путь (особенно ночью) и бой дают травмы, грязная вода и болота — болезни. Всё видно в окне героя (I). Лечит травница в городе (E — говорить, 6 монет) или лекарь-НПС на карте (T).")],
	[I18n.t("Город Эшвик"), I18n.t("Войти можно днём через южные ворота или тайком через стену: шанс выше ночью и с Ловкостью, ниже с травмами и грузом. Попытка стоит 30 сил; если заметят — штраф и казарма. Проникшему 2 часа нельзя попадаться страже. Торговцы работают днём, таверна кормит и сдаёт комнату.")],
	[I18n.t("Пошаговый бой"), I18n.t("Порядок ходов — по инициативе. За ход — перемещение, одно действие, иногда бонусное действие и реакция. При 0 здоровья у героя одна проверка: травма, потеря сознания или смерть. На пути нападают случайно.")],
]

## Хроника мира: канон из энциклопедии (lore/canon.md), коротко. Заголовок и текст, без клавиш
static var CHRONICLE: Array = [
	[I18n.t("Древняя цивилизация"), I18n.t("До катастрофы жила цивилизация, знавшая больше, чем нынешние народы. Остались руины, герметичные камеры и обрывки процедур, смысл которых забыт. Их потомки называют это магией, но чаще это уцелевшая технология, обряд или особенность тела.")],
	[I18n.t("Биотехнологическая катастрофа"), I18n.t("Она уничтожила древнюю цивилизацию и изменила живые организмы. Из общин проточеловека сложились три ветви людей: альбы, сайны и вейры. Что именно случилось, не знает никто.")],
	[I18n.t("Эпоха наблюдателей"), I18n.t("Эльфы и дворфы долго превосходили людей. Эльфы считали людей низшей и временной формой жизни. Дворфы передали человеческим общинам технологии добычи и ремесла, надеясь найти союзников против эльфов.")],
	[I18n.t("Три империи"), I18n.t("Люди выучились быстро. Из помощников они стали главной силой, вытеснили эльфов с многих земель, оттеснили гноллов в пустыни и болота и обратили оружие против дворфов. Возникли три человеческие империи.")],
	[I18n.t("Раскол Луны"), I18n.t("Комета ударила в Луну, и она раскололась. Осколки упали на землю, начались пожары и холода, изменился климат. В народной памяти это одна Вспышка. Часть зверей поумнела: эльфы вывели из гиен гноллов, дворфы из крыс получили скавенов.")],
	[I18n.t("Война с ирхидами"), I18n.t("С другого материка пришли насекомоподобные ирхиды, не знавшие ни дипломатии, ни границ. Империи потеряли много людей. Древнее оружие затопило тот материк, кто его включил, неизвестно. Это конец эпохи Трёх империй.")],
	[I18n.t("Тёмная эпоха"), I18n.t("Знания стали локальными, дороги опасными, мастера дороже золота. Людей мало, многие скрываются или в рабстве. Идёт 1488 год. Проклятые земли остались там, где катастрофы оставили свой след.")],
]

var enabled: bool = true            # підказки по ходу гри (довідка F1 працює завжди)
var seen: Dictionary = {}           # id підказки -> true
var _hints: Array = []
var _current: Dictionary = {}
var _shown_t: float = 0.0
var _gap_t: float = 0.0
var _check_t: float = 0.0
var _mark: Dictionary = {}          # значення на момент показу (для «справу зроблено»)
var _since: Dictionary = {}         # id -> час (real), коли відкрилася минула підказка цього ланцюжка
var _now: float = 0.0

var _card: PanelContainer
var _card_title: Label
var _card_text: Label
var _help: Control
var _tabs: TabContainer
var _toggle: CheckButton
var _was_paused: bool = false


func _ready() -> void:
	layer = 110          # вище за інтерфейс карти, міста й бою, нижче за затемнення переходів (120)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load()
	_make_hints()
	_build_card()
	_build_help()


# =====================================================================
# СТАН ГРИ (через Worlds, без правок чужих скриптів)
# =====================================================================
func _worlds() -> Node:
	return get_node_or_null("/root/Worlds")


func _game() -> Node:
	var w: Node = _worlds()
	if w == null:
		return null
	var g: Variant = w.get("game")
	if g == null or not is_instance_valid(g) or not bool(g.get("ready_done")):
		return null
	return g


## "map" | "city" | "battle" | "" (гри немає: ролик, меню)
func context() -> String:
	var g: Node = _game()
	if g == null:
		return ""
	var k: String = _worlds().current_kind()
	return k if k in ["city", "battle"] else "map"


func _hero() -> Actor:
	var w: Node = _worlds()
	if w == null or _game() == null:
		return null
	var a: Actor = w.hero_actor()
	return a if a != null and a.alive else null


func _hero_pos() -> Vector2:
	return _worlds().hero_body().get("pos", Vector2.INF)


func _cast() -> Node:
	var g: Node = _game()
	return g.get("cast") if g != null else null


func _controls_hero() -> bool:
	var c: Node = _cast()
	return c != null and bool(c.get("controls_hero"))


func _env() -> Dictionary:
	var g: Node = _game()
	var p: Vector2 = _hero_pos()
	if g == null or p == Vector2.INF:
		return {}
	return WorldEnvRef.sample(g, p)


const WorldEnvRef := preload("res://characters/world_env.gd")
const RADIOACTIVE: Array = [7, 8, 9]   # біоми game.BIOME_NAMES


func _map_busy() -> bool:
	var g: Node = _game()
	if g == null or bool(g.get("menu_open")) or bool(g.get("typing")):
		return true
	# Вікно героя або екран створення героя (гілка «Створення персонажа»): нові підказки чекають
	var c: Node = _cast()
	return c != null and bool(c.get("sheet_visible"))


# =====================================================================
# ПІДКАЗКИ
# =====================================================================
## Підказка: id, ctx (де показувати), when (коли), done (справу зроблено — прибрати), title, text.
## mark — що запам'ятати під час показу, для done. Порядок у списку — пріоритет.
func _make_hints() -> void:
	_hints = [
		{"id": "welcome", "ctx": "map", "title": I18n.t("Добро пожаловать"),
			"text": I18n.t("Это карта мира. WASD или стрелки двигают камеру, колесо мыши — масштаб.\nНажмите G — у ворот города Эшвик появится ваш герой (в новой игре его сначала создают).\nF1 — все клавиши и правила в любой момент."),
			"when": func(): return _cast() != null and _worlds().hero_body().is_empty(),
			"done": func(): return not _worlds().hero_body().is_empty()},
		{"id": "walk", "ctx": "map", "title": I18n.t("Герой"),
			"text": I18n.t("WASD — идти, Shift — бег (тратит Силы).\nG — отпустить героя и смотреть карту свободной камерой; ещё раз G — назад к герою."),
			"when": func(): return _hero() != null and _controls_hero(),
			"mark": func(): return {"m": _hero().distance_m},
			"done": func(): return _hero() != null and _hero().distance_m - float(_mark.get("m", 0.0)) > 40.0},
		{"id": "status", "ctx": "map", "title": I18n.t("Состояние героя"), "after": "walk",
			"text": I18n.t("Строка внизу: Здоровье, Сытость, Вода, Энергия, Силы, Воздействие проклятья, температура и скорость шага.\nI — окно героя: характеристики, состояния, навыки; Tab — инвентарь."),
			"when": func(): return _hero() != null,
			"done": func(): return _cast() != null and bool(_cast().get("sheet_visible"))},
		{"id": "gate", "ctx": "map", "title": I18n.t("Ворота города"),
			"text": I18n.t("E — войти в город. Esc или шаг в сторону — пройти мимо."),
			"when": func(): return _prompt_kind() == "gate",
			"done": func(): return _prompt_kind() == ""},
		{"id": "wall", "ctx": "map", "title": I18n.t("Городская стена"),
			"text": I18n.t("E — попытаться проникнуть тайком, шанс виден в панели. Ночью и с Ловкостью шанс выше, с травмами и грузом ниже. Попытка стоит 30 сил; если заметят — штраф и казарма."),
			"when": func(): return _prompt_kind() == "wall",
			"done": func(): return _prompt_kind() == ""},
		{"id": "thirst", "ctx": "map", "title": I18n.t("Жажда"),
			"text": I18n.t("Герой хочет пить. Подойдите к реке или озеру и нажмите E. Сырая вода иногда даёт дизентерию; в городе есть колодцы."),
			"when": func(): return _hero() != null and _hero().res["thirst"] < 50.0,
			"mark": func(): return {"v": _hero().res["thirst"]},
			"done": func(): return _hero() != null and _hero().res["thirst"] > float(_mark.get("v", 0.0)) + 5.0},
		{"id": "hunger", "ctx": "map", "title": I18n.t("Голод"),
			"text": I18n.t("Герой голоден. F — поискать еду вокруг (находится не всегда). В городе еду продают; съесть — в инвентаре (Tab)."),
			"when": func(): return _hero() != null and _hero().res["hunger"] < 50.0,
			"mark": func(): return {"v": _hero().res["hunger"]},
			"done": func(): return _hero() != null and _hero().res["hunger"] > float(_mark.get("v", 0.0)) + 5.0},
		{"id": "sleep", "ctx": "map", "title": I18n.t("Усталость"),
			"text": I18n.t("Энергия на исходе. Z — лечь спать, ещё раз Z или шаг — проснуться. После 8 часов сна герой «Отдохнувший» и идёт быстрее."),
			"when": func(): return _hero() != null and _hero().res["energy"] < 40.0,
			"done": func(): return _hero() != null and _hero().sleeping},
		{"id": "radiation", "ctx": "map", "title": I18n.t("Проклятая земля"),
			"text": I18n.t("Здесь проклятая земля: воздействие проклятья копится каждый час и спадает только на чистой земле. От 100 начинается проклятая хворь. Не задерживайтесь."),
			"when": func(): return _hero() != null and int(_env().get("biome", 0)) in RADIOACTIVE,
			"done": func(): return _hero() == null or not (int(_env().get("biome", 0)) in RADIOACTIVE)},
		{"id": "heat", "ctx": "map", "title": I18n.t("Жаркие горы"),
			"text": I18n.t("В оранжевых горах на 40 °C жарче. Выше 35 °C жажда растёт в 1,6 раза — держите воду под рукой."),
			"when": func(): return _hero() != null and _game().has_method("is_hot") and _game().is_hot(_hero_pos())},
		{"id": "cold", "ctx": "map", "title": I18n.t("Холод"),
			"text": I18n.t("Ниже 0 °C энергия тратится в 1,5 раза быстрее. Мокрая одежда холодит ещё на 4 °C. Сон и отдых возвращают энергию."),
			"when": func(): return _hero() != null and _hero().feels_temp(_env()) < 0.0},
		{"id": "swim", "ctx": "map", "title": I18n.t("Плавание"),
			"text": I18n.t("Герой плывёт: это тратит Силы, а без сил он тонет. Держитесь ближе к берегу."),
			"when": func(): return _hero() != null and _hero().is_swimming(_env())},
		{"id": "condition", "ctx": "", "title": I18n.t("Травма или болезнь"),
			"text": I18n.t("Посмотреть, что случилось, — окно героя (I). Лечит травница в Эшвике (E — говорить) или лекарь-НПС рядом на карте (T). Для некоторых травм нужны шина или навык."),
			"when": func(): return _hero() != null and not _hero().conditions.is_empty()},
		{"id": "low_health", "ctx": "", "title": I18n.t("Мало здоровья"),
			"text": I18n.t("Здоровье падает от голода, жажды, кровотечения, болезней и воздействия проклятья. Поешьте, попейте, выспитесь, вылечите травмы."),
			"when": func(): return _hero() != null and _hero().res["health"] < 40.0},
		{"id": "city", "ctx": "city", "title": I18n.t("Город"),
			"text": I18n.t("E — говорить, пить у колодца, обыскать, осмотреть. 1–9 — ответ в разговоре.\nTab — инвентарь, I — герой, M — план города, колесо — масштаб. Уйти — через ворота."),
			"when": func(): return true},
		{"id": "city_life", "ctx": "city", "title": I18n.t("Жизнь города"), "after": "city", "delay": 25.0,
			"text": I18n.t("Торговцы работают днём, ночью горожане спят, а ворота заперты. Хозяин таверны кормит и сдаёт комнату, травница лечит. Тайники можно обыскать, но кража на глазах стражи — штраф."),
			"when": func(): return true},
		{"id": "intruder", "ctx": "city", "title": I18n.t("Вы чужак"),
			"text": I18n.t("Вы пробрались тайком. Два игровых часа не подходите к стражникам: заметят — штраф, и вас выведут за ворота."),
			"when": func(): return _city_intruder()},
		{"id": "battle", "ctx": "battle", "title": I18n.t("Пошаговый бой"),
			"text": I18n.t("ЛКМ по клетке — идти, по врагу — атаковать; наведите на врага, чтобы увидеть шанс попадания.\n1 — атака, 2–7 — способности, Пробел — конец хода. F1 — все клавиши боя."),
			"when": func(): return true},
		{"id": "battle_more", "ctx": "battle", "title": I18n.t("Ход в бою"), "after": "battle", "delay": 20.0,
			"text": I18n.t("За ход — перемещение и одно действие. D — рывок, G — отход без атак по возможности, V — уклонение, U — зелье, X — уйти с края поля. При 0 здоровья — проверка: травма, потеря сознания или смерть."),
			"when": func(): return true},
	]


func _prompt_kind() -> String:
	var g: Node = _game()
	var st: Variant = g.get("settlements") if g != null else null
	if st == null or (st.get("prompt_for") as Dictionary).is_empty():
		return ""
	return String(st.get("prompt_kind"))


func _city_intruder() -> bool:
	var n: Node = _worlds().current_node()
	return n != null and n.has_method("is_intruder") and n.is_intruder()


func _process(delta: float) -> void:
	_now += delta
	if _help.visible:
		return
	var ctx: String = context()
	if not _current.is_empty():
		_shown_t += delta
		if ctx == "" or (_current["ctx"] != "" and _current["ctx"] != ctx):
			_hide_card(false)   # пішли зі світу підказки — покажемо пізніше, коли повернемося
			return
		_layout()   # перенесення рядків і розмір вікна можуть змінитися будь-якого кадру — тримаємо розмір за текстом
		var done: bool = _current.has("done") and _safe(_current["done"])
		if (done and _shown_t >= MIN_SHOW_S) or _shown_t >= MAX_SHOW_S:
			_hide_card(true)
		return
	if not enabled or ctx == "":
		return
	if _gap_t > 0.0:
		_gap_t -= delta
		return
	_check_t -= delta
	if _check_t > 0.0:
		return
	_check_t = CHECK_S
	if ctx == "map" and _map_busy():
		return
	for h in _hints:
		if seen.has(h["id"]) or (h["ctx"] != "" and h["ctx"] != ctx):
			continue
		if h.has("after"):
			if not seen.has(h["after"]) or _now - float(_since.get(h["after"], -1e9)) < float(h.get("delay", 0.0)):
				continue
		if _safe(h["when"]):
			_show_card(h)
			return


func _safe(fn: Callable) -> bool:
	# Умови читають чужі вузли: якщо їх ще/уже немає, вважаємо «ні»
	var r: Variant = fn.call()
	return r is bool and r


func _show_card(h: Dictionary) -> void:
	_current = h
	_shown_t = 0.0
	_mark = h["mark"].call() if h.has("mark") else {}
	_card_title.text = I18n.t("Обучение · ") + String(h["title"])
	_card_text.text = h["text"]
	_card.visible = true
	_layout()


## mark_seen=false — підказку прибрали, не показавши до кінця (змінився світ): вона повернеться
func _hide_card(mark_seen: bool) -> void:
	if not _current.is_empty() and mark_seen:
		seen[_current["id"]] = true
		_since[_current["id"]] = _now
		_save()
	_current = {}
	_card.visible = false
	_gap_t = GAP_S


func dismiss() -> void:
	_hide_card(true)


## «Пропустити навчання»: підказок більше не буде (увімкнути знову — у довідці F1)
func skip_all() -> void:
	enabled = false
	_hide_card(true)
	_save()
	if _toggle != null:
		_toggle.set_pressed_no_signal(false)


func set_enabled(on: bool) -> void:
	enabled = on
	if not on and not _current.is_empty():
		_hide_card(false)
	_save()


func restart() -> void:
	seen.clear()
	_since.clear()
	enabled = true
	if _toggle != null:
		_toggle.set_pressed_no_signal(true)
	_save()


# =====================================================================
# ДОВІДКА F1
# =====================================================================
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_F1:
		toggle_help()
		get_viewport().set_input_as_handled()
	elif _help.visible:
		# Поки відкрита довідка, клавіші в гру не йдуть; Esc закриває її
		if event.physical_keycode == KEY_ESCAPE:
			toggle_help()
		get_viewport().set_input_as_handled()


func toggle_help() -> void:
	if _help.visible:
		_help.visible = false
		get_tree().paused = _was_paused
		return
	_was_paused = get_tree().paused
	get_tree().paused = true
	var names: Array = [I18n.t("Карта"), I18n.t("Герой"), I18n.t("Город"), I18n.t("Бой"), I18n.t("Механики")]
	var ctx: String = context()
	var tab: String = {"city": I18n.t("Город"), "battle": I18n.t("Бой")}.get(ctx, I18n.t("Герой") if _controls_hero() else I18n.t("Карта"))
	_tabs.current_tab = names.find(tab)
	_help.visible = true
	_layout()


func is_help_open() -> bool:
	return _help.visible


# =====================================================================
# ІНТЕРФЕЙС
# =====================================================================
## Рамка коміксу (ui/comic_ui.gd, Q24); alpha — прозорість усієї рамки
func _style(alpha: float = 1.0) -> StyleBox:
	return preload("res://ui/comic_ui.gd").panel(18.0, C_BG.a * alpha)


func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE     # пробіл і Enter не мають натискати кнопку замість гри
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _build_card() -> void:
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", _style())
	_card.custom_minimum_size = Vector2(CARD_W, 0)
	_card.visible = false
	add_child(_card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_card.add_child(box)
	_card_title = _label(13, C_KEY)
	box.add_child(_card_title)
	_card_text = _label(15, C_TEXT)
	_card_text.custom_minimum_size = Vector2(CARD_W - 30.0, 0)
	box.add_child(_card_text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	_button(row, I18n.t("Понятно"), dismiss)
	_button(row, I18n.t("Все клавиши (F1)"), toggle_help)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	_button(row, I18n.t("Пропустить обучение"), skip_all)


func _build_help() -> void:
	_help = Control.new()
	_help.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_help.mouse_filter = Control.MOUSE_FILTER_STOP
	_help.visible = false
	add_child(_help)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_help.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_help.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style())
	panel.custom_minimum_size = Vector2(860, 600)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var head := HBoxContainer.new()
	box.add_child(head)
	var title := _label(22, C_TEXT)
	title.text = I18n.t("Справка: клавиши и правила")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var note := _label(13, C_DIM)
	note.text = I18n.t("игра на паузе · F1 или Esc — закрыть")
	note.autowrap_mode = TextServer.AUTOWRAP_OFF
	head.add_child(note)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.focus_mode = Control.FOCUS_NONE
	box.add_child(_tabs)
	for tab in KEYS:
		_tabs.add_child(_keys_page(tab, KEYS[tab]))
	_tabs.add_child(_mechanics_page())
	_tabs.add_child(_chronicle_page())

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	_toggle = CheckButton.new()
	_toggle.text = I18n.t("Подсказки по ходу игры")
	_toggle.focus_mode = Control.FOCUS_NONE
	_toggle.button_pressed = enabled
	_toggle.toggled.connect(set_enabled)
	row.add_child(_toggle)
	_button(row, I18n.t("Начать обучение заново"), restart)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	_button(row, I18n.t("Закрыть"), toggle_help)


func _scroll(name_: String) -> Array:
	var sc := ScrollContainer.new()
	sc.name = name_
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 4)
	sc.add_child(inner)
	return [sc, inner]


func _keys_page(name_: String, rows: Array) -> Control:
	var s: Array = _scroll(name_)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 5)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s[1].add_child(grid)
	for r in rows:
		if r.size() == 1:
			var h := _label(14, C_DIM)
			h.text = String(r[0]).to_upper()
			h.autowrap_mode = TextServer.AUTOWRAP_OFF
			grid.add_child(h)
			grid.add_child(Control.new())
			continue
		var k := _label(15, C_KEY)
		k.text = r[0]
		k.autowrap_mode = TextServer.AUTOWRAP_OFF
		k.custom_minimum_size = Vector2(170, 0)
		grid.add_child(k)
		var d := _label(15, C_TEXT)
		d.text = r[1]
		d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(d)
	return s[0]


func _mechanics_page() -> Control:
	var s: Array = _scroll(I18n.t("Механики"))
	for m in MECHANICS:
		var h := _label(16, C_KEY)
		h.text = m[0]
		s[1].add_child(h)
		var t := _label(15, C_TEXT)
		t.text = m[1]
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s[1].add_child(t)
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 6)
		s[1].add_child(gap)
	return s[0]


func _chronicle_page() -> Control:
	var s: Array = _scroll(I18n.t("Хроника"))
	for m in CHRONICLE:
		var h := _label(16, C_KEY)
		h.text = m[0]
		s[1].add_child(h)
		var t := _label(15, C_TEXT)
		t.text = m[1]
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s[1].add_child(t)
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 6)
		s[1].add_child(gap)
	return s[0]


func _layout() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if _card.visible:
		# Висота — за текстом: спершу стиснути до мінімуму ширини CARD_W
		_card.size = Vector2(CARD_W, 0.0)
		# Місце, де підказка не закриває чужий інтерфейс: на карті праворуч згори панель даних —
		# підказка згори по центру; у місті — праворуч згори; у бою — унизу правої колонки, над кнопками
		match context():
			"city":
				_card.position = Vector2(vp.x - _card.size.x - 16.0, 16.0)
			"battle":
				_card.position = Vector2(vp.x - _card.size.x - 16.0, vp.y - _card.size.y - 130.0)
			_:
				_card.position = Vector2((vp.x - _card.size.x) * 0.5, 16.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED and _card != null:
		_layout()


# =====================================================================
# ЗБЕРЕЖЕННЯ (одне на всю гру, не в сейві світу)
# =====================================================================
func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return
	enabled = bool(cf.get_value("tutorial", "enabled", true))
	for id in cf.get_value("tutorial", "seen", []):
		seen[String(id)] = true


func _save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("tutorial", "enabled", enabled)
	cf.set_value("tutorial", "seen", seen.keys())
	cf.save(SAVE_PATH)

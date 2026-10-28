class_name GameClock
extends Node
## Годинник гри. Окрема сцена: рахує тільки час і календар.
## Час це одне число: секунди від 1 січня 1-го року, 00:00. Усе, що залежить від часу,
## читає його звідси. Сигнали нижче призначені для будь-яких майбутніх алгоритмів.

signal hour_changed(hour: int)
signal day_changed(day_index: int)
signal season_changed(season: int)
signal year_changed(year: int)

const SECONDS_PER_DAY: float = 86400.0
const DAYS_PER_YEAR: float = 365.0
# Календарь игры: 6 месяцев на 365 суток (пять по 61 дню и последний 60). Год начинается 1 Хомана,
# в начале осени. Номер года растёт в этот день. Сезонов четыре, их границы по дням как у обычных
# времён года: зима с 1 декабря, весна с 1 марта, лето с 1 июня, осень с 1 сентября.
const MONTH_DAYS: Array = [61, 61, 61, 61, 61, 60]
const MONTH_NAMES: Array = ["Хомана", "Овётганна", "Хугайда", "Кеттари", "Шаванахола", "Тубур"]
const SEASON_NAMES: Array = ["Зима", "Весна", "Лето", "Осень"]
const FIRST_YEAR: int = 1488            # номер года при старте игры
const YEAR_START_DAY: float = 243.0     # с этого дня внутреннего года (0 = 1 января) начинается 1 Хомана
# Швидкості: скільки ігрових секунд іде за одну реальну. Швидше ×60 нема: атмосфера хранить стан,
# а перемотка й дуже швидкий час розсинхронізували б погоду (і гравців у мережевій грі)
# [СПЕЦ, раздел 21] обычный ход: игровой день = реальный час (x24). x60 — для сна и ожидания.
# Шаги персонажей идут в реальном времени (pawn.gd), поэтому ускорение не делает их «бегущими»
# [ОТВЕТ АВТОРА] обычный ход в 4 раза быстрее прежнего: x96 (сутки = 15 минут); сон x240 (сутки = 6 минут)
# [ОТВЕТ АВТОРА, 2026-10-22] «увеличить скорость всей игры»: общий множитель. Им же умножаются шаги
# героя и НПС на карте и в городе (Actor.travel_speed, city_world.gd), чтобы путь в часах игры не менялся
const GAME_SPEED: float = 2.0
const SPEEDS: Array = [96.0 * GAME_SPEED, 240.0 * GAME_SPEED]
const SPEED_NAMES: Array = ["x192 (день = 7,5 мин)", "x480 (день = 3 мин)"]

# Початок гри: день внутрішнього року (1 = 1 січня, 244 = 1 вересня, це 1 Хомана) і година
@export var start_day: float = 244.0
@export var start_hour: float = 6.0
@export var speed_index: int = 0

var total_seconds: float = 0.0
var paused: bool = false

var _last_hour: int = 0
var _last_day: int = 0
var _last_year: int = 1
var _last_season: int = 0


func _ready() -> void:
	add_to_group("clock")
	reset()


func _process(delta: float) -> void:
	advance(delta)


func _start_seconds() -> float:
	return (start_day - 1.0) * SECONDS_PER_DAY + start_hour * 3600.0


func _sync_last() -> void:
	_last_hour = int(floor(total_seconds / 3600.0))
	_last_day = int(floor(total_seconds / SECONDS_PER_DAY))
	_last_year = year()
	_last_season = season()


# День року від 0 до 365 (0 = 1 січня 00:00)
func day_of_year() -> float:
	return fposmod(total_seconds / SECONDS_PER_DAY, DAYS_PER_YEAR)


# Година доби від 0 до 24
func hour_of_day() -> float:
	return fposmod(total_seconds, SECONDS_PER_DAY) / 3600.0


# Номер года игры: растёт 1 Хомана (в начале осени). При старте это FIRST_YEAR
func year() -> int:
	var internal_year: int = int(floor(total_seconds / (SECONDS_PER_DAY * DAYS_PER_YEAR)))
	if day_of_year() < YEAR_START_DAY:
		internal_year -= 1
	return FIRST_YEAR + internal_year


# Номер суток от начала года игры (1 Хомана это 0), от 0 до 364
func calendar_day() -> float:
	return fposmod(day_of_year() - YEAR_START_DAY, DAYS_PER_YEAR)


# Месяц 0..5 (0 Хомана, 1 Овётганна, 2 Хугайда, 3 Кеттари, 4 Шаванахола, 5 Тубур)
func month() -> int:
	var d: float = calendar_day()
	var acc: float = 0.0
	for i in MONTH_DAYS.size():
		acc += float(MONTH_DAYS[i])
		if d < acc:
			return i
	return MONTH_DAYS.size() - 1


# День месяца от 1
func day_of_month() -> int:
	var d: float = calendar_day()
	var acc: float = 0.0
	for i in MONTH_DAYS.size():
		var len_m: float = float(MONTH_DAYS[i])
		if d < acc + len_m:
			return int(d - acc) + 1
		acc += len_m
	return int(MONTH_DAYS[MONTH_DAYS.size() - 1])


# Дата словами для любого момента (секунды игры): «12 Хугайда 1489»
static func date_text(sec: float) -> String:
	var doy: float = fposmod(sec / SECONDS_PER_DAY, DAYS_PER_YEAR)
	var y: int = int(floor(sec / (SECONDS_PER_DAY * DAYS_PER_YEAR)))
	if doy < YEAR_START_DAY:
		y -= 1
	var d: float = fposmod(doy - YEAR_START_DAY, DAYS_PER_YEAR)
	var acc: float = 0.0
	for i in MONTH_DAYS.size():
		var len_m: float = float(MONTH_DAYS[i])
		if d < acc + len_m or i == MONTH_DAYS.size() - 1:
			return "%d %s %d" % [mini(int(d - acc) + 1, int(len_m)), MONTH_NAMES[i], FIRST_YEAR + y]
		acc += len_m
	return ""


# Пора року: 0 зима, 1 весна, 2 літо, 3 осінь (по дням внутреннего года: зима с 1 декабря и т. д.)
func season() -> int:
	var d: float = day_of_year()
	if d >= 334.0 or d < 59.0:
		return 0
	if d < 151.0:
		return 1
	if d < 243.0:
		return 2
	return 3


# Рухає час уперед на реальні секунди з урахуванням швидкості
# Временное ускорение (ремонт персонажа): игровых секунд за реальную. 0 — обычная скорость
var boost: float = 0.0


# Множитель обычного хода времени (панель: ×½, ×2, ×4). Сон (x60) и ремонт идут как раньше
var mult: float = 1.0


# Как в : игрок стоит без дела — мир почти замер (idle_rate); идёт, ищет, готовит, спит — время быстрое.
# game.gd выставляет active каждый кадр в режиме пешки; у наблюдателя всегда true
var active: bool = true
var idle_rate: float = 2.0


func current_rate() -> float:
	if boost > 0.0:
		return boost
	if speed_index == 0 and not active:
		return idle_rate
	return float(SPEEDS[speed_index]) * (mult if speed_index == 0 else 1.0)


func advance(real_delta: float) -> void:
	if paused:
		return
	_set_total(total_seconds + real_delta * current_rate())


# Повертає час на початок гри
func reset() -> void:
	total_seconds = _start_seconds()
	_sync_last()


## Перескок времени вперёд (бой, ожидание): сигналы часа, дня, года и сезона идут как при обычном ходе
func skip(seconds: float) -> void:
	if seconds > 0.0:
		_set_total(total_seconds + seconds)


func change_speed(step: int) -> void:
	speed_index = clampi(speed_index + step, 0, SPEEDS.size() - 1)


func _set_total(new_total: float) -> void:
	total_seconds = new_total
	var h: int = int(floor(total_seconds / 3600.0))
	var d: int = int(floor(total_seconds / SECONDS_PER_DAY))
	if h != _last_hour:
		_last_hour = h
		hour_changed.emit(h % 24)
	if d != _last_day:
		_last_day = d
		day_changed.emit(d)
	var y: int = year()
	if y != _last_year:
		_last_year = y
		year_changed.emit(y)
	var s: int = season()
	if s != _last_season:
		_last_season = s
		season_changed.emit(s)

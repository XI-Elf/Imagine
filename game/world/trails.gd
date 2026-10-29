extends RefCounted
## Протоптані дороги (Huzzah 2026-10-28): готової дороги до міста немає, дороги з'являються там, де ходять.
## Земля ділиться на клітинки cell_m метрів; кожен вхід ходока (герой, НПС, будь-хто з ключем) у клітинку —
## один прохід. Ступені за числом проходів (STAGES): 10 — стежинка, далі стежка, путівець, ґрунтова дорога.
## За ступенем крок трохи швидший (SPEED), шлях мишею віддає перевагу стежкам (ROUTE_WEIGHT, characters/hero_route.gd).
## Заростання: після decay_grace_days ігрових діб без проходів клітинка втрачає decay_per_day проходів на добу;
## нижче за ступінь decay_min_stage (якщо задано й уже досягнуто) не опускається. decay_per_day = 0 — не заростає.
## Рішення Huzzah 2026-10-28 (варіант C): заростають лише стежинка й стежка, з путівця дорога лишається назавжди.
## Поодинокі сліди (менше 10 проходів) забуваються через FORGET_DAYS діб без проходів за будь-якого налаштування,
## щоб збереження не накопичувало кожну клітинку, де колись пройшов герой.
## Одна модель на загальну карту (world/trails_layer.gd, cell 12 м) і на кожне місто (city/city_world.gd, клітинка міста).
## Пороги 10/30/80/200 — відповідь Huzzah на Q35 (2026-10-28, варіант B); заростання зменшено в тій самій пропорції (було 50/…/500 і 5 на добу).

const STAGES: Array = [10, 30, 80, 200]       # проходів до ступеня 1..4
static var STAGE_NAMES: Array = ["", I18n.t("тропинка"), I18n.t("тропа"), I18n.t("просёлок"), I18n.t("грунтовая дорога")]
const SPEED: Array = [1.0, 1.03, 1.06, 1.10, 1.15]
const ROUTE_WEIGHT: Array = [1.0, 0.8, 0.7, 0.6, 0.5]
const DAY_S: float = 86400.0
const FORGET_DAYS: float = 30.0
const JUMP_CELLS: int = 4                       # стрибок далі за це (завантаження, вхід у місто) — не прохід

var cell_m: float = 12.0
var decay_grace_days: float = 3.0
var decay_per_day: float = 1.0
var decay_min_stage: int = 3          # Huzzah 2026-10-28: путівець і ґрунтівка не заростають
var cells: Dictionary = {}       # Vector2i -> [проходи, ігрові секунди останнього проходу]
var stage_of: Dictionary = {}    # Vector2i -> ступінь 1..4 (лише видимі клітинки; оновлюється під час проходу й refresh)
var _last: Dictionary = {}       # ключ ходока -> Vector2i його клітинки
var version: int = 0             # росте, коли змінюється хоч один ступінь (перемальовування)
var track_dirty: bool = false    # накопичувати клітинки зі зміною ступеня в dirty (декор загальної карти прибирає з дороги дерева)
var dirty: Dictionary = {}       # Vector2i -> true


func _init(cell: float = 12.0) -> void:
	cell_m = cell


func cell_at(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / cell_m), floori(p.y / cell_m))


func center_of(c: Vector2i) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * cell_m


static func stage_for(count: float) -> int:
	var s: int = 0
	for i in STAGES.size():
		if count >= float(STAGES[i]):
			s = i + 1
	return s


## Проходи з урахуванням заростання на момент now
func count_of(c: Vector2i, now: float) -> float:
	var e: Variant = cells.get(c)
	return 0.0 if e == null else _effective(e, now)


func _effective(e: Array, now: float) -> float:
	var n: float = float(e[0])
	var idle: float = (now - float(e[1])) / DAY_S
	if n < float(STAGES[0]):
		return 0.0 if idle > FORGET_DAYS else n
	if decay_per_day <= 0.0 or idle <= decay_grace_days:
		return n
	var v: float = n - (idle - decay_grace_days) * decay_per_day
	if decay_min_stage > 0 and n >= float(STAGES[decay_min_stage - 1]):
		v = maxf(v, float(STAGES[decay_min_stage - 1]))
	return maxf(v, 0.0)


func stage_at(p: Vector2) -> int:
	return int(stage_of.get(cell_at(p), 0))


func stage_name_at(p: Vector2) -> String:
	return STAGE_NAMES[stage_at(p)]


func speed_mult(p: Vector2) -> float:
	return SPEED[stage_at(p)]


## Ходок key зараз у p. Нова клітинка — прохід (і клітинки між колишньою й новою, якщо крок довгий).
## Повертає true, якщо змінився ступінь хоч однієї клітинки
func walk(key: Variant, p: Vector2, now: float) -> bool:
	var c: Vector2i = cell_at(p)
	var prev: Variant = _last.get(key)
	_last[key] = c
	if prev == null or prev == c:
		return false
	var d: Vector2i = c - prev
	var n: int = maxi(absi(d.x), absi(d.y))
	if n > JUMP_CELLS:
		return false
	var changed: bool = false
	var last_cell: Vector2i = prev
	for i in range(1, n + 1):
		var q: Vector2i = Vector2i((Vector2(prev) + Vector2(d) * float(i) / float(n)).round())
		if q != last_cell:
			changed = add_pass(q, now) or changed
			last_cell = q
	return changed


## Один прохід через клітинку
func add_pass(c: Vector2i, now: float, times: float = 1.0) -> bool:
	var e: Variant = cells.get(c)
	var n: float = times if e == null else _effective(e, now) + times
	cells[c] = [n, now]
	return _set_stage(c, stage_for(n))


func _set_stage(c: Vector2i, s: int) -> bool:
	if int(stage_of.get(c, 0)) == s:
		return false
	if s == 0:
		stage_of.erase(c)
	else:
		stage_of[c] = s
	version += 1
	if track_dirty:
		dirty[c] = true
	return true


## Забути, де стояв ходок (вхід у місто, завантаження): наступний крок не вважається проходом
func forget(key: Variant) -> void:
	_last.erase(key)


## Перерахувати ступені із заростанням, прибрати зарослі клітинки; true — щось змінилося
func refresh(now: float) -> bool:
	var changed: bool = false
	for c in cells.keys():
		var v: float = _effective(cells[c], now)
		if v <= 0.0:
			cells.erase(c)
			changed = _set_stage(c, 0) or changed
		else:
			changed = _set_stage(c, stage_for(v)) or changed
	return changed


func clear() -> void:
	if track_dirty:
		dirty.merge(stage_of)
	cells.clear()
	stage_of.clear()
	_last.clear()
	version += 1


func to_dict() -> Dictionary:
	var flat := PackedFloat64Array()
	for c in cells:
		var e: Array = cells[c]
		flat.append(c.x)
		flat.append(c.y)
		flat.append(float(e[0]))
		flat.append(float(e[1]))
	return {"cell_m": cell_m, "cells": flat}


func load_dict(d: Variant) -> void:
	clear()
	if not (d is Dictionary) or not is_equal_approx(float(d.get("cell_m", cell_m)), cell_m):
		return
	var flat: Variant = d.get("cells", PackedFloat64Array())
	if not (flat is PackedFloat64Array or flat is Array):
		return
	for i in range(0, flat.size() - 3, 4):
		var c := Vector2i(int(flat[i]), int(flat[i + 1]))
		cells[c] = [float(flat[i + 2]), float(flat[i + 3])]
		var s: int = stage_for(float(flat[i + 2]))
		if s > 0:
			stage_of[c] = s
			if track_dirty:
				dirty[c] = true
	version += 1

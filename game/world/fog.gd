extends RefCounted
## Туман війни загальної карти (Huzzah 2026-10-29): модель дослідженого. Світ накритий сіткою клітинок;
## клітинка стає відкритою, коли герой підійшов ближче за радіус огляду, і закритою вже не стає.
## Малює туман world/fog_layer.gd, зберігає world_save.gd (ключ "fog"; у старих збереженнях його немає — тоді
## відкрито лише те, що навколо героя).

const CELL_M: float = 50.0
const VISION_M: float = 400.0        # [ВРЕМЕННО] радіус огляду героя на рівній місцевості
const JUMP_M: float = 3000.0         # різкий стрибок (перехід за координатами) не відкриває шлях між точками

var map_size: Vector2
var cols: int
var rows: int
var cells: PackedByteArray           # 0 — невідоме, 255 — відкрите
var opened: int = 0                  # скільки клітинок відкрито
var version: int = 0                 # росте щоразу, коли відкрилася хоч одна клітинка (шар оновлює текстуру)
var _last: Vector2 = Vector2(-1.0, -1.0)


func _init(size: Vector2 = Vector2(41625.0, 36000.0)) -> void:
	map_size = size
	cols = int(ceil(size.x / CELL_M))
	rows = int(ceil(size.y / CELL_M))
	cells = PackedByteArray()
	cells.resize(cols * rows)


func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int(p.x / CELL_M), 0, cols - 1), clampi(int(p.y / CELL_M), 0, rows - 1))


## Точка p (метри карти) вже відкрита
func known(p: Vector2) -> bool:
	if p.x < 0.0 or p.y < 0.0 or p.x >= map_size.x or p.y >= map_size.y:
		return false
	var c: Vector2i = cell_of(p)
	return cells[c.y * cols + c.x] != 0


## Відкриває коло радіуса r навколо p; повертає, скільки клітинок відкрилося вперше
func reveal(p: Vector2, r: float = VISION_M) -> int:
	var c0: Vector2i = cell_of(p - Vector2(r, r))
	var c1: Vector2i = cell_of(p + Vector2(r, r))
	var r2: float = r * r
	var fresh: int = 0
	for y in range(c0.y, c1.y + 1):
		var dy: float = (y + 0.5) * CELL_M - p.y
		for x in range(c0.x, c1.x + 1):
			var dx: float = (x + 0.5) * CELL_M - p.x
			if dx * dx + dy * dy <= r2 and cells[y * cols + x] == 0:
				cells[y * cols + x] = 255
				fresh += 1
	opened += fresh
	if fresh > 0:
		version += 1
	return fresh


## Герой тепер у p: відкриває шлях від попередньої точки, щоб при швидкому русі не лишалось прогалин
func walk_to(p: Vector2) -> int:
	var fresh: int = 0
	if _last.x >= 0.0 and _last.distance_to(p) <= JUMP_M:
		var n: int = maxi(int(_last.distance_to(p) / (CELL_M * 2.0)), 1)
		for i in range(1, n):
			fresh += reveal(_last.lerp(p, float(i) / n))
	fresh += reveal(p)
	_last = p
	return fresh


## Герой зник з карти (місто, бій) або з'явився деінде: наступний крок не тягне лінію від старої точки
func forget_last() -> void:
	_last = Vector2(-1.0, -1.0)


## Частка відкритого світу, 0..1
func fraction() -> float:
	return float(opened) / float(cols * rows)


func to_dict() -> Dictionary:
	return {"cols": cols, "rows": rows, "cells": cells.compress(FileAccess.COMPRESSION_ZSTD), "raw": cells.size()}


## Старе або пошкоджене збереження (інший розмір сітки) — сітка лишається порожньою
func load_dict(d: Variant) -> void:
	cells.fill(0)
	opened = 0
	forget_last()
	if d is Dictionary and int(d.get("cols", 0)) == cols and int(d.get("rows", 0)) == rows:
		var packed: Variant = d.get("cells", PackedByteArray())
		if packed is PackedByteArray and int(d.get("raw", 0)) == cells.size():
			var raw: PackedByteArray = packed.decompress(cells.size(), FileAccess.COMPRESSION_ZSTD)
			if raw.size() == cells.size():
				cells = raw
				for v in cells:
					if v != 0:
						opened += 1
	version += 1

extends SceneTree
## Значки предметов (п.7 правок Huzzah 2026-11-03): у каждой вещи из data/cities/items.json свой рисунок.
## godot --headless --rendering-driver dummy -s res://tests/item_art_checks.gd

const Art := preload("res://characters/item_art.gd")
const Trade := preload("res://city/trade.gd")

var fails: int = 0
var checks: int = 0


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("FAIL: ", what)


func _initialize() -> void:
	var f := FileAccess.open("res://data/cities/items.json", FileAccess.READ)
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	var items: Dictionary = d.get("items", d)
	# Оружие рисуется иконками боя: у каждой вещи-оружия своя иконка
	var weapon_ids: Array = ["knife", "axe", "spear", "mace", "shortsword", "torch"]
	var wicons: Dictionary = {"knife": "knife", "axe": "axe", "spear": "spear", "mace": "mace", "shortsword": "sword", "torch": "torch"}
	var seen: Dictionary = {}
	var missing: Array = []
	for id in items:
		if id in weapon_ids:
			var key: String = "weapon|" + String(wicons[id])
			ok(not seen.has(key), "оружие %s: иконка боя своя" % id)
			seen[key] = id
			continue
		var it: Dictionary = Trade.item(id)
		var sig: String = Art.signature(id, it.get("wear", {}) if it.get("wear", {}) is Dictionary else {})
		if sig == "" or (not Art.has_spec(id) and not it.has("wear")):
			missing.append(id)
			continue
		ok(not seen.has(sig), "у %s рисунок не повторяет %s" % [id, seen.get(sig, "")])
		seen[sig] = id
	ok(missing.is_empty(), "у всех вещей есть рисунок (нет: %s)" % [missing])
	for id in Art.SPECS:
		ok(items.has(id), "запись %s есть в items.json" % id)
	print("ITEM ART CHECKS: %d/%d (вещей %d)" % [checks - fails, checks, items.size()])
	quit(1 if fails > 0 else 0)

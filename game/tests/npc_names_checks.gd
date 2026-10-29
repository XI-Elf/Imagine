extends SceneTree
## Імена НПС: чотири культури, без повторів, у всіх мешканців міст — ім'я зі списку.
## godot --headless --path game -s res://tests/npc_names_checks.gd

const Names := preload("res://characters/npc_names.gd")

var fails: int = 0
var checks: int = 0


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("FAIL: ", what)


func _init() -> void:
	for c in Names.CULTURES:
		ok(Names.all("male", c).size() >= 10 and Names.all("female", c).size() >= 10, "культура %s: имена обоих полов" % c)
	ok(Names.all().size() == 96, "всего имён: %d" % Names.all().size())
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var used: Array = []
	for i in 40:
		used.append(Names.pick(rng, "", "", used))
	var uniq: Dictionary = {}
	for n in used:
		uniq[n] = true
	ok(uniq.size() == 40, "40 имён без повторов")
	ok(Names.all("female").has(Names.pick(rng, "female")), "пол учитывается")
	ok(Names.culture_of(Names.pick(rng, "", "irish")) == "irish", "культура учитывается")
	# Мешканці міст
	for f in DirAccess.get_files_at("res://data/cities"):
		if not f.begins_with("s") or not f.ends_with(".json"):
			continue
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/cities/" + f))
		for n in d.get("npcs", []):
			ok(Names.culture_of(String(n["name"])) != "", "%s: %s — имя из списка" % [f, n["name"]])
	print("npc_names_checks: %d/%d ok" % [checks - fails, checks])
	quit(1 if fails > 0 else 0)

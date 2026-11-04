extends SceneTree
const Campaign := preload("res://story/campaign.gd")
var fails: int = 0
var checks: int = 0


## Перевірка без assert: assert у безголовому режимі зупиняє функцію й тест зависає без підсумку
func _ok(cond: bool, what: String) -> bool:
	checks += 1
	if not cond:
		fails += 1
		print("FAIL: ", what)
	return cond


func _initialize() -> void:
	var d: Dictionary = Campaign.data()
	_ok(d.get("chapters", []).size() == 6, "п.1")
	_ok(d.get("characters", []).size() >= 5, "п.2")
	_ok(d.get("bosses", []).size() == 2, "п.3")
	var s: Dictionary = Campaign.fresh()
	_ok(Campaign.record(s, "city_enter", "s001"), "п.4")
	_ok(s.get("awaiting_choice", false), "п.5")
	_ok(Campaign.choose(s, "invalid").is_empty(), "п.6")
	_ok(Campaign.choose(s, "refugees").get("id", "") == "refugees", "п.7")
	_ok(Campaign.current(s).get("id", "") == "names", "п.8")
	_ok(Campaign.record(s, "city_quest", "s001"), "п.9")
	_ok(Campaign.choose(s, "publish").get("id", "") == "publish", "п.10")
	for i in 3: _ok(Campaign.record(s, "travel_km"), "п.11")
	_ok(Campaign.choose(s, "study").get("id", "") == "study", "п.12")
	_ok(Campaign.boss_unlocked(s, "boss_warden"), "п.13")
	_ok(Campaign.record(s, "boss_defeated", "boss_warden"), "п.14")
	_ok(Campaign.boss_unlocked(s, "boss_beacon_core"), "п.15")
	_ok(Campaign.record(s, "boss_defeated", "boss_beacon_core"), "п.16")
	_ok(Campaign.choose(s, "warn").get("id", "") == "warn", "п.17")
	_ok(Campaign.is_complete(s), "п.18")
	# Міграція стану (злиття 2D 12): 2D 11 без ключа, схема проміжної збірки без version, JSON-числа як float
	_ok(Campaign.migrate(null) == Campaign.fresh(), "п.19")
	_ok(int(Campaign.migrate({"chapter": 2, "events": {}, "completed": [], "finished": false}).get("chapter", -1)) == 0, "п.20")
	var m: Dictionary = Campaign.migrate({"version": 1.0, "chapter": 3.0, "progress": 1.0, "flags": {"a": true}, "junk": 5})
	_ok(int(m["chapter"]) == 3 and m["chapter"] is int and int(m["progress"]) == 1 and m["flags"].has("a") and not m.has("junk"), "п.21")
	_ok(int(Campaign.migrate({"version": 1, "chapter": 99}).get("chapter", 0)) == Campaign.chapters().size(), "п.22")
	_ok(Campaign.migrate({"version": 1, "flags": "зіпсовано"})["flags"] is Dictionary, "п.23")
	print("story_campaign_checks: %d/%d | FAIL %d" % [checks - fails, checks, fails])
	quit(1 if fails > 0 else 0)

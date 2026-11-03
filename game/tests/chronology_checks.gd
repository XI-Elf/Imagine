extends SceneTree
## Хронология между партиями (п.16 правок): дата продолжается, брошенный герой уходит в список врагов.
## godot --path game --headless --rendering-driver dummy -s res://tests/chronology_checks.gd

const Chrono := preload("res://world/chronology.gd")
var checks: int = 0
var fails: int = 0


func ok(c: bool, msg: String) -> void:
	checks += 1
	if not c:
		fails += 1
	print(("ok: " if c else "FAIL: ") + msg)


func _initialize() -> void:
	Chrono.path = "user://chronology_test.cfg"
	Chrono.clear()
	ok(Chrono.begin_session(1000.0) == -1.0, "нет прошлой партии — старт как обычно")
	var hero := Actor.new("hero", "Берта", false, 5)
	Chrono.record(5_000_000.0, hero)
	ok(float(Chrono.state()["date_s"]) == 5_000_000.0 and not (Chrono.state()["last_hero"] as Dictionary).is_empty(), "дата и живой герой записаны")
	var d: float = Chrono.begin_session(1000.0)
	ok(d == 5_000_000.0, "новая партия продолжает дату прошлой: %s" % d)
	ok(Chrono.abandoned_count() == 1 and (Chrono.state()["last_hero"] as Dictionary).is_empty(), "живой прежний герой брошен и отдан ИИ")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var got: Actor = null
	for i in 40:
		got = Chrono.meet(rng)
		if got != null:
			break
	ok(got != null and got.display_name == "Берта" and got.is_npc and Chrono.abandoned_count() == 0, "брошенный герой выходит врагом и уходит из списка")
	hero.die("thirst")
	Chrono.record(6_000_000.0, hero)
	Chrono.begin_session(1000.0)
	ok(Chrono.abandoned_count() == 0, "погибший герой не становится врагом")
	Chrono.hero_died(7_000_000.0)
	ok(float(Chrono.state()["date_s"]) == 7_000_000.0, "дата смерти запомнена")
	Chrono.clear()
	print("chronology_checks: %d/%d" % [checks - fails, checks])
	quit(1 if fails > 0 else 0)

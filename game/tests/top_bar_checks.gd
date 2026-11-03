extends SceneTree
## Верхняя панель (п.13, 18, 19 правок): показатели героя, время, дата по клику, значки солнца/луны и погоды.
## godot --path game --headless --rendering-driver dummy -s res://tests/top_bar_checks.gd

const TopBar := preload("res://ui/top_bar.gd")
var checks: int = 0
var fails: int = 0


func ok(c: bool, msg: String) -> void:
	checks += 1
	if not c:
		fails += 1
	print(("ok: " if c else "FAIL: ") + msg)


class FakeClock extends RefCounted:
	var h: float = 8.25
	func hour_of_day() -> float:
		return h
	func day_of_month() -> int:
		return 12
	func month() -> int:
		return 2
	func year() -> int:
		return 1489


func _initialize() -> void:
	var tb: Node = TopBar.new()
	root.add_child(tb)
	ok(tb.stats().is_empty() and tb.weather_icons().is_empty(), "без игры: показателей и погоды нет")
	ok(tb.time_text() == "--:--", "без часов время прочерком")
	tb.game = null
	var r0: Rect2 = tb.time_rect()
	tb.toggle_date()
	ok(tb.show_date and tb.time_rect().size.y > r0.size.y, "клик по времени раскрывает дату (панель выше)")
	tb.toggle_date()
	ok(not tb.show_date and is_equal_approx(tb.time_rect().size.y, r0.size.y), "второй клик скрывает дату")
	ok(tb.bar_rect().end.x < tb.time_rect().position.x, "панель времени справа от показателей")
	ok(TopBar.KEYS == ["health", "hunger", "thirst", "energy", "stamina", "radiation"], "шесть показателей героя")
	print("top_bar_checks: %d/%d" % [checks - fails, checks])
	quit(1 if fails > 0 else 0)

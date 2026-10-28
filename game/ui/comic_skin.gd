extends Node
## Автозагрузка ComicSkin: вливает комикс-тему (ui/comic_ui.gd) в тему Godot по умолчанию до того,
## как создаётся любое окно. Тема по умолчанию действует на все Control, в том числе под CanvasLayer,
## куда тема корневого окна не доходит. Свои стили окон (add_theme_*_override) по-прежнему главнее.
## Ещё держит тёмный фильтр мира (ui/world_grade.gd, Q31 B): виден, только пока открыта общая карта или город.

const ComicUI := preload("res://ui/comic_ui.gd")
const WorldGrade := preload("res://ui/world_grade.gd")

var grade: CanvasLayer


func _enter_tree() -> void:
	apply()


func _ready() -> void:
	grade = WorldGrade.layer()
	grade.visible = false
	add_child(grade)


func _process(_delta: float) -> void:
	grade.visible = WorldGrade.ENABLED and WorldGrade.world_open(get_tree())
	if grade.visible:
		var w: Node = get_node_or_null("/root/Worlds")
		var n: Node = w.current_node() if w != null and w.has_method("current_node") else null
		var clock: Variant = n.get("clock") if n != null else null
		if clock != null and clock.has_method("hour_of_day"):
			WorldGrade.set_strength(grade.get_child(0), WorldGrade.strength_at(clock.hour_of_day()))


static func apply() -> void:
	var t: Theme = ThemeDB.get_default_theme()
	if t != null and not t.has_meta("comic_ui"):
		t.merge_with(ComicUI.theme())
		t.set_meta("comic_ui", true)

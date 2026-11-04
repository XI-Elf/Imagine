extends Node
## Автозавантаження ComicSkin: вливає комікс-тему (ui/comic_ui.gd) у тему Godot за замовчуванням до того,
## як створюється будь-яке вікно. Тема за замовчуванням діє на всі Control, зокрема під CanvasLayer,
## куди тема кореневого вікна не доходить. Власні стилі вікон (add_theme_*_override), як і раніше, головніші.
## Ще тримає темний фільтр світу (ui/world_grade.gd, Q31 B): видно, лише поки відкрита загальна карта або місто.

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

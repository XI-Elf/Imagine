extends Node
## Автозагрузка ComicSkin: вливает комикс-тему (ui/comic_ui.gd) в тему Godot по умолчанию до того,
## как создаётся любое окно. Тема по умолчанию действует на все Control, в том числе под CanvasLayer,
## куда тема корневого окна не доходит. Свои стили окон (add_theme_*_override) по-прежнему главнее.

const ComicUI := preload("res://ui/comic_ui.gd")


func _enter_tree() -> void:
	apply()


static func apply() -> void:
	var t: Theme = ThemeDB.get_default_theme()
	if t != null and not t.has_meta("comic_ui"):
		t.merge_with(ComicUI.theme())
		t.set_meta("comic_ui", true)

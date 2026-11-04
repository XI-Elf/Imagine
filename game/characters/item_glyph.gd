extends Control
## Иллюстрированный знак предмета для полей справочника и каталогов.
const Art := preload("res://characters/item_art.gd")
const BattleIcons := preload("res://battle/battle_icons.gd")
const Trade := preload("res://city/trade.gd")
var item_id: String = ""

func _ready() -> void:
	custom_minimum_size = Vector2(54, 54)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var r := Rect2(Vector2(2, 2), size - Vector2(4, 4))
	draw_rect(r, Color("d8c9a6"), true)
	draw_rect(r, Color("4a3928"), false, 1.5)
	draw_line(r.position + Vector2(5, 8), r.position + Vector2(r.size.x - 5, 8), Color("a58a61", 0.55), 1.0)
	draw_line(r.position + Vector2(5, r.size.y - 7), r.position + Vector2(r.size.x - 5, r.size.y - 7), Color("a58a61", 0.45), 1.0)
	var inner := Rect2(r.position + Vector2(5, 5), r.size - Vector2(10, 10))
	if not Art.draw(self, item_id, inner):
		var item_data: Dictionary = Trade.item(item_id)
		var wear: Dictionary = item_data.get("wear", {})
		if not wear.is_empty():
			Art.wear_icon(self, wear, inner.get_center(), minf(inner.size.x, inner.size.y) * 0.42)
		else:
			var weapon_ids := {"knife": "knife", "axe": "axe", "spear": "spear", "mace": "mace", "shortsword": "sword", "torch": "torch"}
			if weapon_ids.has(item_id):
				BattleIcons.weapon(self, String(weapon_ids[item_id]), inner)
			else:
				draw_circle(inner.get_center(), minf(inner.size.x, inner.size.y) * 0.25, Color("80633c"))
	# Маленькие штрихи сухой кисти — единый «чернильный» финиш у каталожных знаков.
	for i in 3:
		var x := r.position.x + 7.0 + float(i) * 4.0
		draw_line(Vector2(x, r.end.y - 3), Vector2(x + 2, r.end.y - 6), Color("5a4630", 0.45), 0.8)

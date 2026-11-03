extends SceneTree
## Сетка значков всех предметов (characters/item_art.gd) для глаз: godot --path game --rendering-driver opengl3 -s res://qa/render_items.gd
const Art := preload("res://characters/item_art.gd")
const Trade := preload("res://city/trade.gd")
var OUT: String = OS.get_environment("AMBER_QA_OUT") if OS.has_environment("AMBER_QA_OUT") else "user://item_previews/"
const COLS: int = 12
const CELL: float = 96.0


class Canvas extends Control:
	var ids: Array = []

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("2a2622"))
		for i in ids.size():
			var r := Rect2(Vector2(i % 12, i / 12) * 96.0 + Vector2(8, 8), Vector2(80, 80))
			draw_rect(r, Color("3a342e"))
			var rr: Rect2 = r.grow(-8.0)
			var it: Dictionary = Trade.item(ids[i])
			if it.has("wear"):
				Art.wear_icon(self, it["wear"], rr.get_center(), 36.0)
				Art.wear_detail(self, ids[i], rr.get_center(), 36.0, Color(String(it["wear"].get("color", "777777"))))
			elif not Art.draw(self, ids[i], rr):
				draw_rect(rr, Color(0.35, 0.3, 0.28))


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var f := FileAccess.open("res://data/cities/items.json", FileAccess.READ)
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	var items: Dictionary = d.get("items", d)
	var c := Canvas.new()
	c.ids = items.keys().filter(func(k): return not Trade.item(k).has("transport") or true)
	c.size = Vector2(COLS * CELL + 16, ceil(c.ids.size() / float(COLS)) * CELL + 16)
	root.add_child(c)
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().get_region(Rect2i(0, 0, int(c.size.x), int(c.size.y))).save_png(OUT + "items.png")
	print("CAPTURE items")
	quit()



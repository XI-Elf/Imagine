extends SceneTree
## Знімок ляльки героя (characters/paper_doll.gd): чоловік і жінка, без одягу й у різних наборах.
## godot --path game --rendering-driver opengl3 -s res://qa/render_doll.gd  (тека знімків — AMBER_QA_OUT)
const Doll := preload("res://characters/paper_doll.gd")
const Inv := preload("res://characters/inventory_view.gd")
const Trade := preload("res://city/trade.gd")
var OUT: String = OS.get_environment("AMBER_QA_OUT") if OS.has_environment("AMBER_QA_OUT") else "user://doll_previews/"
const SETS: Array = [[], ["linen_shirt", "trousers", "boots"], ["leather_jacket", "trousers", "boots", "felt_cap", "gloves"],
	["linen_shirt", "travel_cloak", "straw_hat", "trousers", "boots", "gloves"]]


class Canvas extends Control:
	func _draw() -> void:
		draw_texture_rect(Inv.marble(true), Rect2(Vector2.ZERO, size), true)
		var d := Doll.new()
		for g in 2:
			for i in SETS.size():
				var looks: Dictionary = {}
				for id in SETS[i]:
					var w: Dictionary = Trade.item(id)["wear"]
					looks[w["slot"]] = {"look": w["look"], "color": Color(w["color"])}
				d.draw(self, Rect2(20 + (g * SETS.size() + i) * 165, 20, 150, 300), g == 1, looks)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var c := Canvas.new()
	c.size = Vector2(1360, 340)
	root.add_child(c)
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().get_region(Rect2i(0, 0, 1360, 340)).save_png(OUT + "d01_dolls.png")
	print("CAPTURE d01_dolls")
	quit()

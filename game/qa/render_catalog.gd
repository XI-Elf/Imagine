extends SceneTree
## Каталог предметов: PNG 256×256 каждого предмета + catalog.json (имя, цена, вес, вид).
## godot --path game --rendering-driver opengl3 -s res://qa/render_catalog.gd  (AMBER_QA_OUT — папка результата)
const Art := preload("res://characters/item_art.gd")
const Icons := preload("res://battle/battle_icons.gd")
const Inv := preload("res://characters/inventory_view.gd")
const Trade := preload("res://city/trade.gd")
var OUT: String = OS.get_environment("AMBER_QA_OUT") if OS.has_environment("AMBER_QA_OUT") else "user://catalog/"
const SZ := 256


class Cv extends Control:
	var id: String = ""
	var weapons: Dictionary = {}
	var kind: String = ""
	func _draw() -> void:
		var r := Rect2(Vector2(24, 24), Vector2(SZ - 48, SZ - 48))
		var it: Dictionary = Trade.item(id)
		if weapons.has(id):
			var wr: Resource = load("res://data/battle/weapons/%s.tres" % weapons[id])
			var ic: String = String(wr.get("icon")) if wr != null and wr.get("icon") != null else "knife"
			Icons.weapon(self, ic, r)
			kind = "weapon"
		elif it.has("wear"):
			Art.wear_icon(self, it["wear"], r.get_center(), r.size.x * 0.5)
			Art.wear_detail(self, id, r.get_center(), r.size.x * 0.5, Color(String(it["wear"].get("color", "777777"))))
			kind = "wear"
		elif Art.draw(self, id, r):
			kind = "art"
		else:
			kind = "missing"


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var cfg: Resource = load("res://data/battle/config.tres")
	var weapons: Dictionary = cfg.get("item_weapons")
	var items: Dictionary = Trade.items()
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.transparent_bg = true
	root.size = Vector2i(SZ, SZ)
	var out: Dictionary = {}
	for id in items:
		var c := Cv.new()
		c.id = id
		c.weapons = weapons
		c.size = Vector2(SZ, SZ)
		root.add_child(c)
		for i in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var img: Image = root.get_texture().get_image()
		img.save_png(OUT + id + ".png")
		var it: Dictionary = items[id]
		out[id] = {"name": it.get("name", id), "price": it.get("price", 0), "weight": it.get("weight", 0), "kind": c.kind, "use": it.get("use", {}), "wear": it.get("wear", {}), "treat": it.get("treat", false), "weapon": weapons.get(id, "")}
		c.queue_free()
		await process_frame
	var f := FileAccess.open(OUT + "catalog.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "\t", false))
	print("CAPTURE catalog ", out.size())
	quit()

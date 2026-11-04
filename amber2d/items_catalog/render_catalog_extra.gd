extends SceneTree
## Каталог, часть 2: нарисованное кодом, не предметы — портреты бойцов, значки оружия и действий боя, типы урона, кукла героя.
## godot --path game --rendering-driver opengl3 -s res://qa/render_catalog_extra.gd  (AMBER_QA_OUT — папка результата)
const Icons := preload("res://battle/battle_icons.gd")
const Doll := preload("res://characters/paper_doll.gd")
const Trade := preload("res://city/trade.gd")
var OUT: String = OS.get_environment("AMBER_QA_OUT") if OS.has_environment("AMBER_QA_OUT") else "user://catalog2/"
const SZ := 256
const SETS := {
	"creatures": ["hero", "bandit", "archer", "chief", "wolf", "hound", "dog", "boar"],
	"battle_weapons": ["knife", "sword", "axe", "cleaver", "club", "mace", "spear", "sling", "bow", "torch", "fist", "bite", "tusk"],
	"actions": ["move", "dash", "disengage", "dodge", "shield", "help", "hide", "potion", "salve", "ready", "flee", "second_wind", "heal", "fire_flask", "poison_dart", "war_cry", "howl", "net", "swap", "log"],
	"damage": ["fire", "radiation", "poison", "slashing", "piercing", "bludgeoning", "cold"],
	"dolls": ["male_bare", "female_bare", "male_dressed", "female_dressed"],
}


class Cv extends Control:
	var set_id: String = ""
	var id: String = ""
	func _draw() -> void:
		var r := Rect2(Vector2(24, 24), Vector2(SZ - 48, SZ - 48))
		match set_id:
			"creatures": Icons.portrait(self, id, Vector2(SZ, SZ) * 0.5, 100.0)
			"battle_weapons": Icons.weapon(self, id, r)
			"actions": Icons.action(self, id, r, Color("d8cfbf"))
			"damage": Icons.damage_type(self, id, Vector2(SZ, SZ) * 0.5, 90.0)
			"dolls":
				var looks: Dictionary = {}
				if id.ends_with("dressed") and not id.ends_with("bare"):
					for it in ["linen_shirt", "trousers", "boots", "travel_cloak", "felt_cap"]:
						var w: Dictionary = Trade.item(it)["wear"]
						looks[w["slot"]] = {"look": w["look"], "color": Color(w["color"])}
				Doll.new().draw(self, Rect2(48, 8, 160, 240), id.begins_with("female"), looks, 0.0)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.transparent_bg = true
	root.size = Vector2i(SZ, SZ)
	for sid in SETS:
		DirAccess.make_dir_recursive_absolute(OUT + sid)
		for id in SETS[sid]:
			var c := Cv.new()
			c.set_id = sid
			c.id = id
			c.size = Vector2(SZ, SZ)
			root.add_child(c)
			for i in 3:
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s%s/%s.png" % [OUT, sid, id])
			c.queue_free()
			await process_frame
	print("CAPTURE extra")
	quit()

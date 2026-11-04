extends SceneTree
## Знімок портретів співрозмовника для всіх ролей (city/portrait.gd): верхній ряд — настрій «прихильний», нижній — «злий».
## godot --path game --rendering-driver opengl3 -s res://qa/portrait_shots.gd -- <файл.png>
func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var roles: Array = ["elder", "guard", "healer", "trader", "smith", "tanner", "innkeeper", "citizen", "stranger"]
	var box := Control.new()
	box.size = Vector2(160 * roles.size(), 360)
	root.add_child(box)
	for row in 2:
		for i in roles.size():
			var p: Control = load("res://city/portrait.gd").new()
			box.add_child(p)
			p.position = Vector2(160 * i, 180 * row)
			p.size = Vector2(150, 170)
			p.seed_value = 1234 + i * 77
			p.role = roles[i]
			p.mood = 1 if row == 0 else -1
			p._update_art()
	for i in 40:
		await process_frame
	await RenderingServer.frame_post_draw
	var args: PackedStringArray = OS.get_cmdline_user_args()
	root.get_texture().get_image().save_png(args[0] if args.size() > 0 else "user://portraits.png")
	quit()

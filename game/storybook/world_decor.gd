extends Node2D
## Upright 2D cutouts, deterministic placement, viewport culling and fixed-scale LOD.
const Art := preload("res://storybook/art.gd")
var game: Node2D
var elapsed: float = 0.0

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

func _process(delta: float) -> void:
	elapsed += delta
	if game != null and game.ready_done:
		queue_redraw()

func _draw() -> void:
	if game == null or not game.ready_done or game.zoom < 0.25:
		return
	var z: float = game.zoom
	var vp: Vector2 = get_viewport_rect().size
	var items: Array = []
	# Large geological silhouettes give way to detailed rocks at walking scale.
	if z < 5.0:
		_collect(items, 150.0, 0, smoothstep(0.25, 0.65, z) * (1.0 - smoothstep(2.0, 5.0, z)), vp)
	if z > 1.1:
		_collect(items, 14.0, 1, smoothstep(1.1, 2.6, z), vp)
	if z > 5.0:
		_collect(items, 6.0, 2, smoothstep(5.0, 9.0, z), vp)
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["foot"].y < b["foot"].y)
	var hour: float = game.clock.hour_of_day()
	var daylight: float = clampf(sin((hour - 6.0) / 12.0 * PI) * 1.4, 0.0, 1.0)
	var tone: Color = Color(0.32, 0.39, 0.51).lerp(Color.WHITE, daylight)
	for item in items:
		var tint: Color = tone
		tint.a = item["alpha"]
		var sway: float = sin(elapsed * 1.1 + item["phase"]) * 0.009 if item["plant"] else 0.0
		Art.sprite(self, item["key"], item["foot"], item["height"] * z, tint, sway)

func _collect(items: Array, spacing: float, level: int, alpha: float, vp: Vector2) -> void:
	if alpha < 0.01:
		return
	var z: float = game.zoom
	var pad: float = spacing * 1.5
	var lo: Vector2 = game.cam_pos - vp * 0.5 / z - Vector2(pad, pad)
	var hi: Vector2 = game.cam_pos + vp * 0.5 / z + Vector2(pad, pad)
	for y in range(floori(lo.y / spacing), ceili(hi.y / spacing)):
		for x in range(floori(lo.x / spacing), ceili(hi.x / spacing)):
			var n: float = Art.seed_at(x, y, level)
			var p: Vector2 = (Vector2(x, y) + Vector2(0.2 + n * 0.6, 0.2 + Art.seed_at(x, y, 9) * 0.6)) * spacing
			if p.x < 0 or p.y < 0 or p.x > game.MAP_SIZE.x or p.y > game.MAP_SIZE.y:
				continue
			var biome: int = game.biome_at(p)
			if biome < 2:
				continue
			var key: String = ""
			var height: float = 1.0
			var plant: bool = false
			if level == 0:
				if biome != 6 or n < 0.26:
					continue
				key = ["mountain_hot", "mesa_hot", "ridge_hot"][int(n * 17.0) % 3] if game.is_hot(p) else ["mountain_gray", "ridge_gray", "peak_gray", "cliff_gray"][int(n * 19.0) % 4]
				height = 110.0 + n * 40.0
			elif level == 1:
				if biome in [3, 7] and n > 0.16:
					key = ["tree_oak", "tree_light", "tree_crooked"][int(n * 11.0) % 3]
					height = 6.0 + n * 4.0
					plant = true
				elif biome in [5, 9] and n > 0.73:
					key = "tree_light"; height = 5.0 + n * 2.0; plant = true
				elif biome == 6 and n > 0.45:
					key = "rock"; height = 2.0 + n * 3.0
			else:
				if biome in [3, 5, 7, 9] and n > 0.76:
					key = "bush_flower" if n > 0.88 else "bush_berry"; height = 0.9 + n * 0.8; plant = true
				elif biome in [2, 4, 6, 8] and n > 0.88:
					key = "rock"; height = 0.6 + n * 0.7
			if key == "":
				continue
			var foot: Vector2 = game.world_to_screen(p)
			var h: float = height * z
			if not Rect2(Vector2(-h, -h), vp + Vector2(h * 2.0, h * 2.0)).has_point(foot):
				continue
			items.append({"key": key, "foot": foot, "height": height, "alpha": alpha, "phase": n * TAU, "plant": plant})

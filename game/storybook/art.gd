extends RefCounted
## Shared hand-painted asset renderer. Coordinates always use ground/foot anchors.
static var cache: Dictionary = {}

static func tex(key: String) -> Texture2D:
	if not cache.has(key):
		cache[key] = load("res://art/storybook/%s.png" % key)
	return cache[key] as Texture2D

static func ground(key: String) -> Texture2D:
	var k: String = "ground/" + key
	if not cache.has(k):
		cache[k] = load("res://art/terrain/%s.png" % key)
	return cache[k] as Texture2D

static func surface(node: Node2D, texture: Texture2D, rect: Rect2, period: float, tint: Color = Color.WHITE) -> void:
	# World-aligned sampling: neighbouring cells share one continuous texture.
	var scale_uv: float = float(texture.get_width()) / period
	node.draw_texture_rect_region(texture, rect, Rect2(rect.position * scale_uv, rect.size * scale_uv), tint, false, false)

static func sprite(node: Node2D, key: String, foot: Vector2, height: float, tint: Color = Color.WHITE, sway: float = 0.0) -> void:
	var texture: Texture2D = tex(key)
	var size: Vector2 = Vector2(texture.get_size()) * (height / float(texture.get_height()))
	# Grounding shadow, visually separate from the painted silhouette.
	node.draw_set_transform(foot + Vector2(0, 1.5), 0.0, Vector2(1, 0.28))
	node.draw_circle(Vector2.ZERO, size.x * 0.31, Color(0.12, 0.10, 0.07, 0.20 * tint.a))
	node.draw_set_transform(foot, sway, Vector2.ONE)
	node.draw_texture_rect(texture, Rect2(Vector2(-size.x * 0.5, -size.y), size), false, tint)
	node.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

static func seed_at(x: int, y: int, salt: int = 0) -> float:
	return fposmod(sin(float(x * 127 + y * 311 + salt * 73)) * 43758.5453, 1.0)

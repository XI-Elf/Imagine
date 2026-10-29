extends CanvasLayer
## Туман війни на загальній карті (модель world/fog.gd): шар над картою, декором і персонажами, під інтерфейсом.
## Локальна карта (герой): невідоме закрите туманом, відкрите, але далеке від героя — приглушене, навколо героя — ясне.
## Глобальна карта (M): досліджене видно як є, недосліджене закрите туманом.
## Поки героя немає (створення героя, спостерігач) або він у місті чи в бою, туману немає.

const Fog := preload("res://world/fog.gd")
const REFRESH_S: float = 0.15        # не частіше стільки реальних секунд оновлюємо текстуру відкритого

const SHADER := """
shader_type canvas_item;
render_mode unshaded;
uniform sampler2D mask : filter_linear, repeat_disable;
uniform vec2 map_size = vec2(41625.0, 36000.0);
uniform vec2 cam_pos = vec2(0.0);
uniform vec2 view_px = vec2(1280.0, 720.0);
uniform vec2 hero_pos = vec2(0.0);
uniform float zoom = 1.0;
uniform float vision = 400.0;
uniform float global_mode = 0.0;
uniform float anim = 0.0;
uniform vec3 fog_col = vec3(0.07, 0.06, 0.09);

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.03 + 7.1) * 0.3 + vnoise(p * 4.1 + 3.7) * 0.15;
}

void fragment() {
	vec2 P = cam_pos + (UV - vec2(0.5)) * view_px / zoom;
	// Край відкритого рвано-хмарний: шум зсуває вибірку маски приблизно на клітинку
	float n = fbm(P / 90.0 + vec2(anim * 0.01, 0.0));
	// Маска груба (клітинка 50 м): усереднюємо дев'ять вибірок, щоб край був м'яким, а не східцями
	vec2 px = vec2(75.0) / map_size;
	vec2 Q = P / map_size;
	float known = texture(mask, Q).r * 0.2;
	known += (texture(mask, Q + vec2(px.x, 0.0)).r + texture(mask, Q - vec2(px.x, 0.0)).r
		+ texture(mask, Q + vec2(0.0, px.y)).r + texture(mask, Q - vec2(0.0, px.y)).r) * 0.15;
	known += (texture(mask, Q + px).r + texture(mask, Q - px).r
		+ texture(mask, Q + vec2(px.x, -px.y)).r + texture(mask, Q + vec2(-px.x, px.y)).r) * 0.05;
	known = smoothstep(0.3, 0.7, known + (n - 0.5) * 0.4);
	float outside = step(0.0, P.x) * step(P.x, map_size.x) * step(0.0, P.y) * step(P.y, map_size.y);
	known *= outside;
	float cloud = fbm(P / 260.0 + vec2(anim * 0.012, -anim * 0.008));
	vec3 col = fog_col + vec3(0.05, 0.05, 0.07) * cloud;
	float a_unknown = mix(0.93, 1.0, global_mode);
	float near_hero = 1.0 - smoothstep(vision * 0.55, vision * 1.05, length(P - hero_pos));
	// Відкрите, але далеке: приглушене лише на локальній карті
	float a_known = (1.0 - near_hero) * 0.5 * (1.0 - global_mode);
	float a = mix(a_unknown, a_known, known);
	COLOR = vec4(mix(col, vec3(0.04, 0.04, 0.06), known), a);
}
"""

var game: Node2D
var model := Fog.new()
var _mat := ShaderMaterial.new()
var _rect: ColorRect
var _tex: ImageTexture
var _tex_version: int = -1
var _since_refresh: float = 0.0


func _init() -> void:
	layer = 1        # над світом (шар 0), під інтерфейсом (10) і вікнами


func _ready() -> void:
	var sh := Shader.new()
	sh.code = SHADER
	_mat.shader = sh
	_rect = ColorRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _mat
	_rect.visible = false
	add_child(_rect)
	_mat.set_shader_parameter("map_size", model.map_size)
	_mat.set_shader_parameter("vision", Fog.VISION_M)


## Туман зараз закриває карту: є герой на карті
func active() -> bool:
	var cast: Node = game.get("cast") if game != null else null
	return cast != null and not cast.hero.is_empty() and not cast.hero_away


## Місце p відкрите — інтерфейс не показує про нього даних, поки воно в тумані
func known(p: Vector2) -> bool:
	return not active() or model.known(p)


func _process(delta: float) -> void:
	if game == null or not game.ready_done:
		return
	var cast: Node = game.get("cast")
	var on: bool = active()
	if cast != null and not cast.hero.is_empty():
		if cast.hero_away:
			model.forget_last()
		else:
			model.walk_to(cast.hero["pos"])
	_rect.visible = on
	if not on:
		return
	_since_refresh += delta
	if _tex == null or (_tex_version != model.version and _since_refresh >= REFRESH_S):
		_since_refresh = 0.0
		_upload()
	_mat.set_shader_parameter("cam_pos", game.cam_pos)
	_mat.set_shader_parameter("zoom", game.zoom)
	_mat.set_shader_parameter("view_px", game.get_viewport_rect().size)
	_mat.set_shader_parameter("hero_pos", cast.hero["pos"])
	_mat.set_shader_parameter("global_mode", 1.0 if game.global_map else 0.0)
	_mat.set_shader_parameter("anim", fposmod(Time.get_ticks_msec() / 1000.0, 3600.0))


func _upload() -> void:
	var img := Image.create_from_data(model.cols, model.rows, false, Image.FORMAT_R8, model.cells)
	if _tex == null:
		_tex = ImageTexture.create_from_image(img)
		_mat.set_shader_parameter("mask", _tex)
	else:
		_tex.update(img)
	_tex_version = model.version


func to_dict() -> Dictionary:
	return model.to_dict()


func load_dict(d: Variant) -> void:
	model.load_dict(d)
	_tex_version = -1

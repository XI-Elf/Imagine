extends RefCounted
## Тёмная палитра мира (Q31 B, Huzzah 2026-10-27: «мир заметно темнее»). Один фильтр поверх уже нарисованного
## мира: меньше насыщенности, глубже тени, холодный оттенок в тенях; янтарные огни (линзы, вышки, фонари)
## остаются яркими. Интерфейс не задевается: фильтр стоит под слоями интерфейса.
## Общая карта и город — слой LAYER, его держит автозагрузка ComicSkin, пока открыт мир (game.gd).
## Бой — тот же фильтр внутри сцены боя между полем и панелями (battle_scene.gd).
## Откатить: ENABLED = false. Сила — STRENGTH (0 — как было, 1 — как задумано). Ночью мир и так тёмный,
## поэтому фильтр слабеет до NIGHT_STRENGTH (strength_at), чтобы ночью было видно дорогу.

const ENABLED: bool = true
const STRENGTH: float = 1.0
const NIGHT_STRENGTH: float = 0.25
const LAYER: int = 5          # над картой (terrain −1, мир 0), под интерфейсом карты (10) и города (19–20)

const SHADER := """
shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float strength = 1.0;
void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	vec3 g = mix(vec3(l), c, 0.66);                       // меньше насыщенности
	g = pow(max(g, vec3(0.0)), vec3(1.22)) * 0.72 + 0.012; // темнее, тени глубже, чёрное не проваливается
	float sh = (1.0 - l) * (1.0 - l);
	g += sh * vec3(-0.018, 0.0, 0.032);                   // холодные тени
	// янтарь (r высокий, b низкий, яркий) остаётся светиться
	float amber = smoothstep(0.62, 0.9, c.r) * smoothstep(0.28, 0.55, c.r - c.b) * smoothstep(0.45, 0.7, l);
	COLOR = vec4(mix(c, mix(g, c, amber), strength), 1.0);
}
"""

static var _shader: Shader = null


## Сила фильтра по часу суток: днём STRENGTH, глубокой ночью NIGHT_STRENGTH (тот же свет, что у декора карты)
static func strength_at(hour: float) -> float:
	var daylight: float = clampf(sin((hour - 6.0) / 12.0 * PI) * 1.4, 0.0, 1.0)
	return lerpf(NIGHT_STRENGTH, 1.0, daylight) * STRENGTH


static func set_strength(r: CanvasItem, s: float) -> void:
	if r != null and r.material is ShaderMaterial:
		(r.material as ShaderMaterial).set_shader_parameter("strength", s)


## Полноэкранный прямоугольник с фильтром (ставится в любой слой после того, что надо затемнить)
static func rect() -> ColorRect:
	var r := ColorRect.new()
	r.name = "WorldGrade"
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("strength", STRENGTH)
	r.material = m
	r.visible = ENABLED
	return r


## Слой фильтра для общей карты и города
static func layer() -> CanvasLayer:
	var l := CanvasLayer.new()
	l.name = "WorldGradeLayer"
	l.layer = LAYER
	l.add_child(rect())
	return l


## Открыт ли мир (общая карта или город): текущая сцена — game.gd
static func world_open(tree: SceneTree) -> bool:
	var s: Node = tree.current_scene
	return s != null and s.get_script() != null and String(s.get_script().resource_path).ends_with("/game.gd")

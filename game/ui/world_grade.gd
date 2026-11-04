extends RefCounted
## Темна палітра світу (Q31 B, Huzzah 2026-10-27: «світ помітно темніший»). Один фільтр поверх уже намальованого
## світу: менше насиченості, глибші тіні, холодний відтінок у тінях; бурштинові вогні (лінзи, вежі, ліхтарі)
## лишаються яскравими. Інтерфейс не зачіпається: фільтр стоїть під шарами інтерфейсу.
## Загальна карта й місто — шар LAYER, його тримає автозавантаження ComicSkin, поки відкритий світ (game.gd).
## Бій — той самий фільтр усередині сцени бою між полем і панелями (battle_scene.gd).
## Відкотити: ENABLED = false. Сила — STRENGTH (0 — як було, 1 — як задумано). Уночі світ і так темний,
## тому фільтр слабшає до NIGHT_STRENGTH (strength_at), щоб уночі було видно дорогу.

const ENABLED: bool = true
const STRENGTH: float = 1.0
const NIGHT_STRENGTH: float = 0.25
const LAYER: int = 5          # над картою (terrain −1, світ 0), під інтерфейсом карти (10) і міста (19–20)

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


## Сила фільтра за годиною доби: удень STRENGTH, глибокої ночі NIGHT_STRENGTH (те саме світло, що в декору карти)
static func strength_at(hour: float) -> float:
	var daylight: float = clampf(sin((hour - 6.0) / 12.0 * PI) * 1.4, 0.0, 1.0)
	return lerpf(NIGHT_STRENGTH, 1.0, daylight) * STRENGTH


static func set_strength(r: CanvasItem, s: float) -> void:
	if r != null and r.material is ShaderMaterial:
		(r.material as ShaderMaterial).set_shader_parameter("strength", s)


## Повноекранний прямокутник із фільтром (ставиться в будь-який шар після того, що треба затемнити)
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


## Шар фільтра для загальної карти й міста
static func layer() -> CanvasLayer:
	var l := CanvasLayer.new()
	l.name = "WorldGradeLayer"
	l.layer = LAYER
	l.add_child(rect())
	return l


## Чи відкритий світ (загальна карта або місто): поточна сцена — game.gd
static func world_open(tree: SceneTree) -> bool:
	var s: Node = tree.current_scene
	return s != null and s.get_script() != null and String(s.get_script().resource_path).ends_with("/game.gd")

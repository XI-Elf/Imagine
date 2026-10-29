extends Control
## Портрет того, хто говорить (пункт 18, Huzzah 2026-10-29): погруддя в рамці коміксу ліворуч від рядка розмови,
## як у візуальних новелах. Живий: очі стежать за курсором, кліпає, рот — за настроєм жителя (Dialogue.mood),
## наведення підсвічує, клік — герой придивляється (signal inspected). Малюється кодом, доки немає намальованих портретів;
## колір шкіри, волосся й одягу — від зерна жителя й ролі.

signal inspected

const ComicUI := preload("res://ui/comic_ui.gd")
const ROLE_CLOTH: Dictionary = {"elder": Color(0.42, 0.2, 0.16), "guard": Color(0.3, 0.3, 0.26), "healer": Color(0.5, 0.48, 0.4),
	"trader": Color(0.36, 0.3, 0.18), "smith": Color(0.22, 0.2, 0.2), "tanner": Color(0.4, 0.28, 0.16), "innkeeper": Color(0.45, 0.32, 0.2)}

var seed_value: int = 0
var role: String = "citizen"
var mood: int = 0
var _blink_t: float = 2.0
var _blinking: float = 0.0
var _hover: bool = false


func _ready() -> void:
	custom_minimum_size = Vector2(150, 170)
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func(): _hover = true; queue_redraw())
	mouse_exited.connect(func(): _hover = false; queue_redraw())
	tooltip_text = I18n.t("Присмотреться")


func show_for(a: Actor, r: String, m: int) -> void:
	seed_value = hash(a.actor_id) if a != null else 0
	role = r
	mood = m
	queue_redraw()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_blink_t -= delta
	if _blinking > 0.0:
		_blinking -= delta
	elif _blink_t <= 0.0:
		_blinking = 0.12
		_blink_t = randf_range(2.0, 5.0)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		inspected.emit()
		accept_event()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	# рамка коміксу знизу, фігура — поверх її середини
	var box: StyleBoxTexture = ComicUI.box("portrait", Color(1.0, 0.92, 0.7) if _hover else Color.WHITE)
	draw_style_box(box, r)
	draw_rect(r.grow(-12.0), Color(0.16, 0.14, 0.12))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var skin: Color = Color(0.86, 0.7, 0.56).lerp(Color(0.55, 0.38, 0.27), rng.randf())
	var hair: Color = [Color(0.15, 0.1, 0.07), Color(0.4, 0.27, 0.14), Color(0.62, 0.55, 0.45), Color(0.3, 0.12, 0.05)][rng.randi() % 4]
	var cloth: Color = ROLE_CLOTH.get(role, Color(0.33, 0.3, 0.25).lerp(Color(0.2, 0.25, 0.22), rng.randf()))
	var c := Vector2(size.x * 0.5, size.y * 0.44)
	var hr: float = size.x * 0.22
	# плечі й тулуб
	draw_colored_polygon(PackedVector2Array([Vector2(size.x * 0.12, size.y - 12.0), Vector2(size.x * 0.2, size.y * 0.72), Vector2(size.x * 0.8, size.y * 0.72), Vector2(size.x * 0.88, size.y - 12.0)]), cloth)
	draw_rect(Rect2(c + Vector2(-hr * 0.35, hr * 0.7), Vector2(hr * 0.7, hr * 0.6)), skin.darkened(0.15))
	# голова, волосся
	draw_circle(c, hr, skin)
	draw_arc(c, hr, PI * 1.05, PI * 1.95, 18, hair, hr * 0.5)
	if role == "guard":
		draw_arc(c, hr * 1.05, PI, TAU, 18, Color(0.45, 0.45, 0.42), hr * 0.35)   # шолом
	# очі стежать за курсором
	var look: Vector2 = (get_local_mouse_position() - c).limit_length(60.0) / 60.0 * hr * 0.12
	for sx in [-1.0, 1.0]:
		var e: Vector2 = c + Vector2(sx * hr * 0.38, -hr * 0.1)
		if _blinking > 0.0:
			draw_line(e + Vector2(-hr * 0.14, 0), e + Vector2(hr * 0.14, 0), Color(0.1, 0.07, 0.05), 2.0)
		else:
			draw_circle(e, hr * 0.14, Color(0.93, 0.9, 0.84))
			draw_circle(e + look, hr * 0.07, Color(0.12, 0.09, 0.07))
		# брови за настроєм
		var tilt: float = -0.25 * mood * sx
		draw_line(e + Vector2(-hr * 0.18, -hr * 0.22 + tilt * hr * 0.4), e + Vector2(hr * 0.18, -hr * 0.22 - tilt * hr * 0.4), hair.darkened(0.3), 3.0)
	# рот: злий — дугою вниз, прихильний — вгору
	var m: Vector2 = c + Vector2(0, hr * 0.5)
	if mood == 0:
		draw_line(m + Vector2(-hr * 0.25, 0), m + Vector2(hr * 0.25, 0), Color(0.35, 0.15, 0.12), 2.5)
	else:
		draw_arc(m + Vector2(0, -hr * 0.25 * mood), hr * 0.3, PI * 0.2 if mood > 0 else PI * 1.2, PI * 0.8 if mood > 0 else PI * 1.8, 10, Color(0.35, 0.15, 0.12), 2.5)

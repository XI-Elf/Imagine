extends CanvasLayer
## Сон героя (Huzzah 2026-10-29): екран гасне, ніби герой заплющує очі; поки він спить, час іде прискорено
## до пробудження. Повний сон від найбільшої втоми триває не довше MAX_S реальних секунд разом із повіками.
## Прокидається сам, коли виспався (енергія від WAKE_ENERGY і щонайменше годину сну), або від будь-якої клавіші чи кліку.
## Однаково на загальній карті й у місті: вузол живе в автозавантаженні Worlds, годинник — game.clock.
## Під час сну годинник іде з boost (game_clock.gd), після сну boost знімається.

const CLOSE_S: float = 0.7            # повіки заплющуються
const OPEN_S: float = 0.7             # розплющуються
const MAX_S: float = 10.0             # увесь сон разом із повіками — не довше
const SLEEP_RATE: float = 3600.0      # ігрових секунд за реальну: 8 годин сну — 8 секунд
const WAKE_ENERGY: float = 99.0

var worlds: Node
var _t: float = -1.0                  # реальних секунд від початку сну (-1 — не спить)
var _start_ms: int = 0
var _lid: float = 0.0                 # 0 — очі розплющені, 1 — заплющені
var _boosted: GameClock = null
var _view: Control
var _text: Label


func _ready() -> void:
	layer = 60                        # над містом і вікном героя, під екраном загибелі (70) і меню паузи (100)
	_view = Control.new()
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.draw.connect(_draw_lids)
	add_child(_view)
	_text = Label.new()
	_text.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_text.grow_vertical = Control.GROW_DIRECTION_BOTH
	_text.add_theme_font_size_override("font_size", 18)
	_text.add_theme_color_override("font_color", Color(0.75, 0.72, 0.66))
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.modulate.a = 0.0
	add_child(_text)


func _hero() -> Actor:
	if worlds == null or worlds.game == null or not is_instance_valid(worlds.game):
		return null
	return worlds.hero_actor()


func _clock() -> GameClock:
	if worlds == null or worlds.game == null or not is_instance_valid(worlds.game):
		return null
	return worlds.game.get("clock") as GameClock


## Герой зараз спить (і це не бій)
func asleep() -> bool:
	var a: Actor = _hero()
	return a != null and a.alive and a.sleeping and not worlds.is_battle()


func _process(delta: float) -> void:
	var a: Actor = _hero()
	var on: bool = asleep()
	if on:
		# Реальний годинник, а не сума delta: на слабкому комп'ютері кадри довгі, а сон однаково не довший за MAX_S
		if _t < 0.0:
			_start_ms = Time.get_ticks_msec()
		_t = float(Time.get_ticks_msec() - _start_ms) / 1000.0
		var rested: bool = float(a.res["energy"]) >= WAKE_ENERGY and a.sleep_h >= 1.0
		if rested or _t >= MAX_S - OPEN_S:
			wake(I18n.t("Вы выспались и встали") if rested else I18n.t("Вы проснулись"))
			on = false
	if not on:
		_t = -1.0
	# Час біжить, щойно повіки майже заплющилися
	var clock: GameClock = _clock()
	var want: bool = on and _t >= CLOSE_S * 0.5 and clock != null
	if want:
		clock.boost = SLEEP_RATE
		_boosted = clock
	elif _boosted != null:
		if is_instance_valid(_boosted):
			_boosted.boost = 0.0
		_boosted = null
	_lid = move_toward(_lid, 1.0 if on else 0.0, delta / (CLOSE_S if on else OPEN_S))
	_view.mouse_filter = Control.MOUSE_FILTER_STOP if _lid > 0.05 else Control.MOUSE_FILTER_IGNORE
	_text.modulate.a = clampf((_lid - 0.8) / 0.2, 0.0, 1.0)
	if _text.modulate.a > 0.0 and clock != null and a != null:
		var h: float = clock.hour_of_day()
		_text.text = I18n.t("Сон…  %02d:%02d   энергия %d\nлюбая клавиша — проснуться") % [int(h), int(fmod(h, 1.0) * 60.0), int(a.res["energy"])]
	_view.queue_redraw()


## Розбудити героя (з повідомленням у світі, де він зараз)
func wake(msg: String = "") -> void:
	var a: Actor = _hero()
	if a == null or not a.sleeping:
		return
	a.set_sleep(false)
	if msg == "":
		return
	var node: Node = worlds.current_node()
	if node != null and node.has_method("_say"):
		node._say(msg)
	elif worlds.game.get("cast") != null and worlds.game.cast.has_method("_event"):
		worlds.game.cast._event(msg)


func _input(event: InputEvent) -> void:
	if not asleep() or _t < 0.2:
		return
	var key: bool = event is InputEventKey and event.pressed and not event.echo
	var click: bool = event is InputEventMouseButton and event.pressed
	if key or click:
		wake(I18n.t("Вы проснулись"))
		get_viewport().set_input_as_handled()


## Повіки: темні смуги згори й знизу сходяться до середини, край м'який
func _draw_lids() -> void:
	if _lid <= 0.0:
		return
	var vs: Vector2 = _view.size
	var k: float = ease(_lid, 0.6)
	var half: float = vs.y * 0.5 * k
	var soft: float = 60.0
	_view.draw_rect(Rect2(0, 0, vs.x, half), Color.BLACK)
	_view.draw_rect(Rect2(0, vs.y - half, vs.x, half), Color.BLACK)
	for i in 6:
		var a: float = (1.0 - float(i) / 6.0) * 0.8 * k
		var y0: float = half + soft * float(i) / 6.0
		_view.draw_rect(Rect2(0, y0, vs.x, soft / 6.0 + 1.0), Color(0, 0, 0, a))
		_view.draw_rect(Rect2(0, vs.y - y0 - soft / 6.0 - 1.0, vs.x, soft / 6.0 + 1.0), Color(0, 0, 0, a))
	if k >= 0.999:
		_view.draw_rect(Rect2(Vector2.ZERO, vs), Color.BLACK)

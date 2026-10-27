extends Control

# Шляхи до сцени гри і до фонової картинки
const GAME_SCENE := "res://game.tscn"
const WorldSave := preload("res://world_save.gd")
const BG_IMAGE := "res://art/menu_bg.jpg"
const HeroCreateScript := preload("res://characters/hero_create.gd")

# Кольори інтерфейсу
const COLOR_BG := Color("2b2823")      # колір фону, якщо картинки немає
const COLOR_TITLE := Color("d8cfb0")   # колір назви гри
const COLOR_HINT := Color("8a8470")    # колір другорядного тексту

# Мітка для повідомлень під кнопками
var message_label: Label
var _main_box: VBoxContainer
var _load_panel: PanelContainer
var _load_list: VBoxContainer
var _creator: CanvasLayer


func _ready() -> void:
	# Заставка (синематик) показывается один раз при запуске игры, перед меню. Если сцены заставки нет
	# или она не открылась, меню строится как обычно
	if not Engine.has_meta("aw_intro_done") and ResourceLoader.exists("res://intro.tscn"):
		Engine.set_meta("aw_intro_done", true)
		get_tree().change_scene_to_file.call_deferred("res://intro.tscn")
		return
	# Розтягуємо меню на все вікно
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Суцільний фон (його видно, якщо картинка не завантажилась)
	var base := ColorRect.new()
	base.color = COLOR_BG
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(base)

	# Фонова картинка
	if ResourceLoader.exists(BG_IMAGE):
		var bg := TextureRect.new()
		bg.texture = load(BG_IMAGE)
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(bg)

	# Напівпрозоре затемнення, щоб текст читався
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.45)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	# Центрування вмісту
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	# Колонка: назва і кнопки одна під одною
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)

	# Назва гри
	var title := Label.new()
	title.text = "Ambers World"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", COLOR_TITLE)
	box.add_child(title)

	# Проміжок між назвою і кнопками
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	box.add_child(spacer)

	# Кнопки меню
	_add_button(box, "Новая игра", _on_new_game)

	# «Продолжить» — последнее сохранение, «Загрузить» — выбор из списка
	var has_saves: bool = WorldSave.exists()
	var continue_button := _add_button(box, "Продолжить", _on_continue)
	continue_button.disabled = not has_saves
	var load_button := _add_button(box, "Загрузить", _on_load_menu)
	load_button.disabled = not has_saves

	_add_button(box, "Выход", _on_quit)

	# Мітка для повідомлень
	message_label = Label.new()
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.add_theme_color_override("font_color", COLOR_HINT)
	box.add_child(message_label)
	_main_box = box
	_build_load_panel(center)


# Створює кнопку, додає її в колонку і підключає дію
func _add_button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(240, 48)
	button.add_theme_font_size_override("font_size", 20)
	parent.add_child(button)
	if callback.is_valid():
		button.pressed.connect(callback)
	return button


# «Новая игра»: сначала экран создания героя (characters/hero_create.gd), потом мир.
# Выбор передаётся в игру через Engine meta "aw_new_hero" — герой появится у ворот города (characters/cast.gd)
func _on_new_game() -> void:
	if _creator != null:
		return
	_creator = HeroCreateScript.new()
	add_child(_creator)
	_creator.finished.connect(_on_hero_created)


func _on_hero_created(params: Dictionary) -> void:
	_creator.queue_free()
	_creator = null
	if params.is_empty():
		return
	Engine.set_meta("aw_load", "")
	Engine.set_meta("aw_new_hero", params)
	if ResourceLoader.exists(GAME_SCENE):
		get_tree().change_scene_to_file(GAME_SCENE)
	else:
		message_label.text = "Сцену гри ще не створено"


# «Продолжить»: игра загрузит сохранённый мир
func _on_continue() -> void:
	_load_slot(WorldSave.latest_slot())


func _load_slot(slot: String) -> void:
	if slot == "":
		return
	Engine.set_meta("aw_load", slot)
	get_tree().change_scene_to_file(GAME_SCENE)


# Список сохранений: вид, дата, персонаж, игровая дата; «Загрузить» и «Удалить»
func _build_load_panel(parent: Control) -> void:
	_load_panel = PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.10, 0.09, 0.08, 0.96)
	st.border_color = Color("c9a24b")
	st.set_border_width_all(2)
	st.set_corner_radius_all(8)
	st.set_content_margin_all(18.0)
	_load_panel.add_theme_stylebox_override("panel", st)
	_load_panel.visible = false
	parent.add_child(_load_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_load_panel.add_child(v)
	var t := Label.new()
	t.text = "Загрузить"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 30)
	t.add_theme_color_override("font_color", COLOR_TITLE)
	v.add_child(t)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(620, 360)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	_load_list = VBoxContainer.new()
	_load_list.add_theme_constant_override("separation", 6)
	sc.add_child(_load_list)
	var back := _add_button(v, "Назад", _close_load_menu)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER


func _close_load_menu() -> void:
	_load_panel.visible = false
	_main_box.visible = true


func _delete_slot(slot: String) -> void:
	WorldSave.delete(slot)
	if WorldSave.exists():
		_on_load_menu()
	else:
		get_tree().reload_current_scene()


func _on_load_menu() -> void:
	for c in _load_list.get_children():
		c.queue_free()
	for h in WorldSave.list():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var l := Label.new()
		var who: String = String(h.get("char_name", ""))
		l.text = "%s  %s\n%s%s" % [h["title"], String(h.get("saved_at", "")).replace("T", " "),
			("Персонаж: " + who + "   ") if who != "" else "",
			String(h.get("game_date", "")) + ("   " + String(h["place"]) if h.has("place") else "")]
		l.custom_minimum_size = Vector2(420, 0)
		l.add_theme_color_override("font_color", COLOR_TITLE)
		row.add_child(l)
		var b := Button.new()
		b.text = "Загрузить"
		b.pressed.connect(_load_slot.bind(String(h["slot"])))
		row.add_child(b)
		var d := Button.new()
		d.text = "Удалить"
		d.pressed.connect(_delete_slot.bind(String(h["slot"])))
		row.add_child(d)
		_load_list.add_child(row)
	_main_box.visible = false
	_load_panel.visible = true


# Натиснули "Выход"
func _on_quit() -> void:
	get_tree().quit()

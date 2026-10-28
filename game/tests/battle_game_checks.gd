extends SceneTree
## Пошаговая боевая сцена в окне (экран по образцу): выбор оружия из сумки, ход мышью и клавишами,
## шанс над целью, кости, карточки, ИИ, окно итогов, сохранение.
## godot --path game --rendering-driver opengl3 -s res://tests/battle_game_checks.gd -- [папка_для_снимков]

var fails: int = 0
var checks: int = 0
var shots: String = ""


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
	print("ok: " if cond else "FAIL: ", what)


func frames(n: int) -> void:
	for i in n:
		await process_frame


func shot(name: String) -> void:
	if shots != "":
		await frames(2)
		root.get_viewport().get_texture().get_image().save_png(shots.path_join(name))


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	shots = args[0] if args.size() > 0 else ""
	_run()


func make(req: Dictionary) -> CanvasLayer:
	var b: CanvasLayer = load("res://battle/battle.tscn").instantiate()
	b.setup(req)
	root.add_child(b)
	return b


func hover(b, p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	b._unhandled_input(e)


func click(b, p: Vector2) -> void:
	hover(b, p)
	var e := InputEventMouseButton.new()
	e.position = p
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	b._unhandled_input(e)


func key(b, k: int) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = true
	b._unhandled_input(e)


func hit_rect(b, id: String) -> Rect2:
	for h in b.hits:
		if h["id"] == id:
			return h["rect"]
	return Rect2()


func wait_player(b, limit: float = 30.0) -> bool:
	var t: float = 0.0
	while b.me() == null and b.core.outcome == "" and t < limit:
		await process_frame
		t += 1.0 / 60.0
	return b.me() != null


func _run() -> void:
	var hero := Actor.new("hero", "Выживший")
	hero.set_stat("agi", 6)
	hero.set_stat("str", 6)
	var npc := Actor.new("npc_1", "Прася")
	var inv: Dictionary = {"money": 5, "items": {"knife": 1, "axe": 1, "torch": 2, "bread": 3, "sling": 1}}
	var b := make({"terrain": "wasteland", "origin": "overworld", "allies": [hero, npc], "pets": ["dog"], "group": "bandits",
		"seed": 77, "inventory": inv})
	await frames(4)
	# ---- выбор оружия перед боем
	ok(b.phase == "prep" and b.core.round_n == 0, "перед боем — окно выбора оружия, бой ещё не начат")
	ok(b.prep_list.size() == 4, "из сумки найдено оружие: %s" % ", ".join(PackedStringArray(b.prep_list.map(func(e): return e["item"]))))
	ok(b.prep_sel.size() == 3, "по умолчанию выбраны первые три")
	await shot("b00_prep.png")
	var sling_r: Rect2 = hit_rect(b, "prep:sling")
	click(b, sling_r.get_center())
	ok(not b.prep_sel.has("sling"), "четвёртое не взять, пока выбрано три")
	click(b, hit_rect(b, "prep:axe").get_center())
	click(b, sling_r.get_center())
	ok(b.prep_sel == ["knife", "torch", "sling"] or b.prep_sel.size() == 3 and b.prep_sel.has("sling") and not b.prep_sel.has("axe"), "топор снят, праща взята: %s" % str(b.prep_sel))
	await shot("b01_prep_choice.png")
	key(b, KEY_ENTER)
	var h = b.core.hero()
	ok(b.phase == "battle" and b.core.round_n == 1, "Enter — в бой, брошена инициатива")
	ok(h.weapons.size() == 3 and h.weapons.map(func(w): return w.id).has("sling") and h.weapons.map(func(w): return w.id).has("torch"), "в руках у героя: %s" % ", ".join(PackedStringArray(h.weapons.map(func(w): return w.title))))
	ok(inv.get("battle_loadout", []).size() == 3, "выбор запомнен в сумке для следующего боя")
	var finished: Array = []
	b.battle_finished.connect(func(r): finished.append(r))
	ok(await wait_player(b), "дошло до хода игрока")
	var c = b.me()
	ok(c != null and c.is_hero, "ходит герой")
	await frames(20)
	await shot("b02_turn_start.png")
	ok(b.mode == "move", "в начале хода — режим движения (зелёные клетки)")
	# ---- шаг по клетке
	var reach: Dictionary = b.core.reach_of(c)
	var goal: Vector2i = c.cell
	for p in reach:
		if not reach[p].get("pass_only", false) and int(reach[p]["cost"]) == 10 and p.x > goal.x:
			goal = p
	hover(b, b.cell_to_screen(Vector2(goal)))
	await frames(2)
	ok(b.hover_text().contains("кл."), "реплика при наведении на клетку: " + b.hover_text())
	await shot("b03_move_hover.png")
	click(b, b.cell_to_screen(Vector2(goal)))
	ok(c.cell == goal and c.move_left == c.speed() - 10, "шаг на 10 фт, осталось %d" % c.move_left)
	await frames(30)
	# ---- карточка пращи, наведение на врага: шанс и урон над целью
	var si: int = c.weapons.map(func(w): return w.id).find("sling")
	click(b, hit_rect(b, "weapon:%d" % si).get_center())
	ok(c.wi == si and b.mode == "attack" and c.free_used, "клик по карточке — праща в руках, песочные клетки дальности")
	var foe = null
	for u in b.core.all:
		if u.team == 1 and u.active():
			foe = u
			break
	hover(b, b.cell_to_screen(Vector2(foe.cell)))
	await frames(2)
	ok(b.hover_text().contains("попадание") and b.hover_text().contains("%"), "шанс при наведении: " + b.hover_text())
	await shot("b04_hit_chance.png")
	var fi: int = b.core.all.find(foe)
	ok(hit_rect(b, "foe:%d" % fi).has_area(), "карточка врага справа")
	click(b, hit_rect(b, "foe:%d" % fi).get_center())
	await frames(10)
	ok(not c.has_action, "клик по карточке врага — выстрел, действие потрачено")
	ok(b.dice_show.size() > 0, "кубик на экране")
	ok(not b.log_box.visible, "журнал скрыт")
	ok(b.speech.contains("бьёт") and not b.speech.contains("d20"), "реплика — короткий итог без формул: " + b.speech)
	await shot("b05_dice.png")
	key(b, KEY_L)
	await frames(2)
	ok(b.log_box.visible and b.log_box.get_parsed_text().contains("против: защита"), "L — журнал с формулами")
	await shot("b06_log.png")
	key(b, KEY_L)
	# ---- способность: выбор цели, Esc
	key(b, KEY_5)
	ok(b.mode == "ability:fire_flask", "5 — выбор цели огненной смеси")
	hover(b, b.cell_to_screen(Vector2(foe.cell)))
	ok(b.hover_text().contains("Огненная смесь"), "реплика способности: " + b.hover_text())
	key(b, KEY_ESCAPE)
	ok(b.mode == "move", "Esc — отмена")
	key(b, KEY_C)
	ok(not b.companions_ai, "C — спутники вручную")
	key(b, KEY_C)
	# ---- сохранение посреди боя
	var d: Dictionary = b.to_dict()
	key(b, KEY_SPACE)
	ok(b.me() == null, "Пробел — конец хода")
	await frames(3)
	await shot("b07_enemy_turn.png")
	var b2 := make(b.req.duplicate())
	b2.load_dict(d)
	await frames(3)
	var h2 = b2.core.hero()
	ok(b2.phase == "battle" and b2.core.round_n == int(d["round"]) and h2.weapons.size() == 3 and h2.wi == si, "загрузка: бой, то же оружие в руках")
	b2.queue_free()
	# ---- доигрываем: герой бьёт ближайшего, подходя, потом конец хода
	var guard: int = 0
	while b.core.outcome == "" and guard < 80:
		guard += 1
		if not await wait_player(b, 30.0):
			break
		c = b.me()
		var t = b.core._ai_target(c)
		if t != null and c.has_action:
			if not b.core.can_attack(c, t)["ok"] and c.weapon().ranged:
				b.press("weapon:0")
			b.attack_or_approach(c, t)
		await frames(15)
		if b.me() != null:
			key(b, KEY_ENTER)
		await frames(2)
	ok(b.core.outcome != "", "бой закончился: %s за %d раундов" % [b.core.outcome, b.core.round_n])
	await create_timer(0.5).timeout
	ok(b.phase == "end" and hit_rect(b, "finish").has_area(), "окно итогов с кнопкой «Завершить»")
	await shot("b08_end.png")
	click(b, hit_rect(b, "finish").get_center())
	key(b, KEY_ENTER)
	ok(finished.size() == 1, "battle_finished ровно один раз")
	var r: Dictionary = finished[0] if not finished.is_empty() else {}
	ok(r.get("outcome", "") in ["win", "lose", "flee"] and r.has("game_minutes") and r.has("dead") and r.has("loot"), "результат по договору Worlds")
	b.queue_free()
	# ---- пустая сумка — кулаки
	var b3 := make({"terrain": "rad_swamp", "night": true, "allies": [Actor.new("hero", "Выживший")], "group": "hounds", "seed": 5,
		"inventory": {"money": 0, "items": {}}})
	await frames(4)
	ok(b3.phase == "prep" and b3.prep_list.is_empty(), "пустая сумка: окно выбора без оружия")
	await shot("b09_prep_empty.png")
	b3.press("prep_go")
	ok(b3.core.hero().weapons.size() == 1 and b3.core.hero().weapons[0].id == "fists", "без оружия — кулаки")
	await frames(30)
	await shot("b10_rad_swamp_night.png")
	b3.queue_free()
	# ---- без сумки (проверочный бой) — сразу бой с набором из config
	var b4 := make({"terrain": "forest", "allies": [Actor.new("hero", "Выживший")], "seed": 9})
	await frames(4)
	ok(b4.phase == "battle" and b4.core.round_n >= 1, "без сумки — сразу бой")
	b4.queue_free()
	await frames(2)
	print("BATTLE GAME CHECKS: %d/%d" % [checks - fails, checks])
	quit(1 if fails > 0 else 0)

extends CanvasLayer
## Боевая сцена: отдельный мир боя на сетке 5 футов, пошагово по инициативе.
## Экран — по образцу Huzzah (battle/spec/battle_screen_reference.mp4): слева карточка героя, «Движение»
## и до трёх карточек оружия; справа карточки врагов и «Конец хода»; внизу реплика с портретом;
## над целью — шанс попадания и урон; табличка «Ход игрока / врага»; окно итогов.
## Перед боем игрок выбирает до трёх видов оружия из сумки (req.inventory).
##
## Вход и выход — через переключатель миров (Worlds.start_battle): setup(req) до add_child,
## по окончании — сигнал battle_finished(result); сама сцена себя не выгружает.
## Вся логика — в battle_core.gd; здесь только показ и приказы игрока.
##
## req: {origin, return_pos, terrain/biome, hot, night, allies: Array[Actor], enemies: Array[Actor] (пусто —
##       соберутся по местности), pets: [id шаблона], group, seed, inventory {money, items}}
## result: {outcome: win|lose|flee, origin, return_pos, game_minutes, rounds, dead, killed, loot, traumas}
##
## Управление: ЛКМ по клетке — идти; по врагу (на поле или по карточке) — атаковать текущим оружием
## (если далеко — подойти и ударить); 1–3 — оружие, M — движение, 4–7 — способности, D рывок, G отход,
## V уклонение, H помощь, K спрятаться, U зелье, R подготовить, X уйти с поля (с края), C — спутники ИИ/вручную,
## L — журнал, Enter/Пробел — конец хода, Esc/ПКМ — отмена.

signal battle_finished(result: Dictionary)

const Core := preload("res://battle/battle_core.gd")
const Rules := preload("res://battle/combat_rules.gd")
const Data := preload("res://battle/battle_data.gd")
const Icons := preload("res://battle/battle_icons.gd")
const Art := preload("res://storybook/art.gd")
const ComicUI := preload("res://ui/comic_ui.gd")

const C_TEXT := Color(0.91, 0.86, 0.69)
const C_DIM := Color(0.62, 0.6, 0.5)
const C_HP := Color(0.5, 0.86, 0.3)
const C_ORANGE := Color(0.95, 0.6, 0.16)
const C_PANEL := Color(0.105, 0.125, 0.085)
const C_PANEL_HI := Color(0.17, 0.2, 0.13)
const C_EDGE := Color(0.33, 0.38, 0.25)
const C_ALLY_RING := Color(0.95, 0.62, 0.15)
const C_NPC_RING := Color(0.45, 0.7, 0.95)
const C_FOE_RING := Color(0.16, 0.32, 0.18)
const C_MOVE := Color(0.55, 0.85, 0.25)
const C_RANGE := Color(0.98, 0.86, 0.55)
const STEP_ANIM_S: float = 0.09
const AI_DELAY_S: float = 0.5
const COL_W: float = 250.0
const PAD: float = 8.0


class Layer extends Node2D:
	var fn: Callable
	func _draw() -> void:
		fn.call(self)


var core: Node
var req: Dictionary = {}
var phase: String = "battle"           # prep — выбор оружия, battle, end
var mode: String = "move"              # move, attack, ability:<id>, help, use
var hover_cell: Vector2i = Vector2i(-1, -1)
var mouse: Vector2 = Vector2.ZERO
var hover_hit: String = ""
var hits: Array = []                   # [{rect, id}] — кнопки интерфейса, перестраиваются при рисовании
var vis: Dictionary = {}               # участник -> позиция на экране в клетках (для плавного шага)
var paths: Dictionary = {}
var floaters: Array = []
var dice_show: Dictionary = {}
var ai_wait: float = -1.0
var companions_ai: bool = true
var ground_tex: Texture2D
var prep_sel: Array = []               # id предметов из сумки, по порядку выбора
var prep_list: Array = []              # core.inventory_weapons()
var speech: String = ""
var speech_who = null
var banner: Dictionary = {}            # {text, t}
var last_side: int = -1
var show_log: bool = false
var _loaded: bool = false
var _sent: bool = false
var _anim_t: float = 0.0

var view: Layer
var hud: Layer
var log_box: RichTextLabel


# =====================================================================
# ВХОД
# =====================================================================
func setup(r: Dictionary) -> void:
	req = r
	layer = 50
	core = Core.new()
	core.auto_ai = false
	add_child(core)
	core.setup(req)
	core.logged.connect(_on_log)
	core.turn_started.connect(_on_turn)
	core.moved.connect(_on_moved)
	core.acted.connect(_on_acted)
	core.finished.connect(_on_finished)
	for c in core.all:
		vis[c] = Vector2(c.cell)
		if c.team == 0 and not c.is_hero:
			c.controlled = not companions_ai
	var tex: int = int(core.cfg.arena.get(core.arena_key, {}).get("tex", 5))
	var path: String = "res://art/terrain/t%02d_%s.png" % [tex, _tex_name(tex)]
	if ResourceLoader.exists(path):
		ground_tex = load(path)
	_build()


static func _tex_name(i: int) -> String:
	return ["water", "coast", "forest", "field1", "field2", "wasteland", "swamp", "mountains", "hot_mountains",
		"rad_forest", "rad_wasteland", "rad_swamp"][clampi(i, 0, 11)]


func _ready() -> void:
	if core == null:          # без setup — проверочный бой
		setup({"terrain": "forest", "allies": [Actor.new("hero", I18n.t("Герой"))]})
	call_deferred("_begin")


func _begin() -> void:
	if _loaded:
		return
	if req.get("inventory", null) is Dictionary and core.hero() != null:
		_open_prep()
	else:
		phase = "battle"
		core.begin()


func _open_prep() -> void:
	phase = "prep"
	prep_list = core.inventory_weapons()
	prep_sel = []
	var inv: Dictionary = req.get("inventory", {})
	var have: Array = prep_list.map(func(e): return e["item"])
	for it in inv.get("battle_loadout", []):
		if have.has(it) and prep_sel.size() < core.cfg.loadout_max:
			prep_sel.append(it)
	if prep_sel.is_empty():
		for it in have.slice(0, core.cfg.loadout_max):
			prep_sel.append(it)


func prep_toggle(item: String) -> void:
	if prep_sel.has(item):
		prep_sel.erase(item)
	elif prep_sel.size() < core.cfg.loadout_max:
		prep_sel.append(item)


func prep_confirm() -> void:
	if phase != "prep":
		return
	core.set_loadout(core.hero(), prep_sel)
	phase = "battle"
	core.begin()


# =====================================================================
# СОБЫТИЯ ЯДРА
# =====================================================================
func _on_turn(c) -> void:
	mode = "move"
	var side: int = 0 if c.controlled else (1 if c.team == 1 else 2)
	if side != last_side:
		banner = {"text": [I18n.t("Ход\nигрока"), I18n.t("Ход\nврага"), I18n.t("Ход\nсоюзника")][side], "t": 0.0}
		last_side = side
	if not c.controlled:
		ai_wait = AI_DELAY_S


func _on_moved(c, path: Array) -> void:
	var p: Array = paths.get(c, [])
	for i in range(1, path.size()):
		p.append(Vector2(path[i]))
	paths[c] = p


func _on_acted(c, what: String, data: Dictionary) -> void:
	if what == "roll":
		if data.get("kind", "") == "d20":
			dice_show = {"entry": data, "t": 0.0}
		return
	if what == "attack":
		var t = data["target"]
		var res: Dictionary = data["res"]
		var w = data.get("weapon", null)
		var how: String = (" (%s)" % w.title.to_lower()) if w != null else ""
		if res["hit"]:
			var dmg: int = int(res["damage"].get("total", 0))
			_float(t, "−%d" % dmg + (I18n.t(" сильный удар") if res["crit"] else ""), Color(0.85, 0.08, 0.06))
			_say(I18n.t("%s бьёт %s%s: %s, %d урона. У %s осталось %d здоровья.") % [c.title, t.title, how, I18n.t("сильный удар") if res["crit"] else I18n.t("попадание"),
				dmg, t.title, maxi(t.hp, 0)], c)
		else:
			_float(t, I18n.t("мимо"), Color(0.3, 0.3, 0.3))
			_say(I18n.t("%s бьёт %s%s: промах.") % [c.title, t.title, how], c)


func _on_log(text: String, kind: String) -> void:
	var col: String = {"head": "e8dcb0", "roll": "b9c4d6", "hit": "f0a070", "miss": "a0a0a0", "heal": "9fe39a"}.get(kind, "c8c0a8")
	log_box.append_text("[color=#%s]%s[/color]\n" % [col, text.replace("[", "[lb]")])
	# на экран — только короткие итоги без формул (журнал целиком — по L)
	if kind in ["head", "info"] and not text.begins_with("—") and not text.begins_with(I18n.t("Очередь")) and not text.contains("(d20)") and not text.contains("→"):
		_say(text, core.current())


func _say(text: String, who) -> void:
	speech = text
	if who != null:
		speech_who = who


func _on_finished(_o: String) -> void:
	mode = ""
	phase = "end"


func leave() -> void:
	if core.outcome == "" or _sent:
		return
	_sent = true
	battle_finished.emit(core.result())


func result() -> Dictionary:
	return core.result()


# =====================================================================
# КАДР
# =====================================================================
func _process(delta: float) -> void:
	_anim_t += delta
	var animating: bool = false
	for c in paths.keys():
		var p: Array = paths[c]
		if p.is_empty():
			continue
		animating = true
		var cur: Vector2 = vis.get(c, Vector2(c.cell))
		var to: Vector2 = p[0]
		var step: float = delta / STEP_ANIM_S
		if cur.distance_to(to) <= step:
			vis[c] = to
			p.pop_front()
		else:
			vis[c] = cur + (to - cur).normalized() * step
	for c in core.all:
		if not paths.has(c) or paths[c].is_empty():
			vis[c] = Vector2(c.cell)
	if ai_wait >= 0.0 and not animating and core.outcome == "" and phase == "battle":
		ai_wait -= delta
		if ai_wait < 0.0:
			core.run_ai_turn()
	for f in floaters:
		f["t"] += delta
	floaters = floaters.filter(func(x): return x["t"] < 1.4)
	if not dice_show.is_empty():
		dice_show["t"] += delta
	if not banner.is_empty():
		banner["t"] += delta
		if banner["t"] > 1.4:
			banner = {}
	log_box.visible = show_log
	if show_log:
		var r: Rect2 = grid_rect()
		log_box.position = r.position + Vector2(20, 20)
		log_box.size = r.size - Vector2(40, 40)
	view.queue_redraw()
	hud.queue_redraw()


# =====================================================================
# ВВОД
# =====================================================================
func me():
	if phase != "battle":
		return null
	var c = core.current()
	return c if c != null and c.controlled and core.outcome == "" and ai_wait < 0.0 else null


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse = event.position
		hover_cell = screen_to_cell(mouse)
		hover_hit = _hit_at(mouse)
		if hover_hit != "":
			hover_cell = Vector2i(-1, -1)
			if hover_hit.begins_with("foe:"):
				var u = core.all[int(hover_hit.substr(4))]
				hover_cell = u.cell
		return
	if event is InputEventKey and event.pressed and not event.echo:
		get_viewport().set_input_as_handled()
		_key(event.physical_keycode)
	elif event is InputEventMouseButton and event.pressed:
		get_viewport().set_input_as_handled()
		if event.button_index == MOUSE_BUTTON_RIGHT:
			mode = "move" if phase == "battle" else mode
			show_log = false
			return
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		mouse = event.position
		var h: String = _hit_at(mouse)
		if h != "":
			press(h)
			return
		if phase != "battle" or show_log:
			return
		var cell: Vector2i = screen_to_cell(mouse)
		if core.grid.in_bounds(cell):
			click_cell(cell)


func _key(k: int) -> void:
	if phase == "prep":
		if k in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			prep_confirm()
		elif k >= KEY_1 and k <= KEY_9 and k - KEY_1 < prep_list.size():
			prep_toggle(prep_list[k - KEY_1]["item"])
		return
	if phase == "end" or core.outcome != "":
		if k in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_ESCAPE]:
			leave()
		return
	if k == KEY_ESCAPE:
		mode = "move"
		show_log = false
		return
	if k == KEY_L:
		show_log = not show_log
		return
	if k == KEY_C:
		toggle_companions()
		return
	var c = me()
	if c == null:
		return
	match k:
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			press("end")
		KEY_M:
			press("move")
		KEY_1, KEY_2, KEY_3:
			press("weapon:%d" % (k - KEY_1))
		KEY_4, KEY_5, KEY_6, KEY_7:
			var i: int = k - KEY_4
			if i < c.abilities.size():
				press("ab:" + c.abilities[i].id)
		KEY_D:
			press("act:dash")
		KEY_G:
			press("act:disengage")
		KEY_V:
			press("act:dodge")
		KEY_H:
			press("act:help")
		KEY_K:
			press("act:hide")
		KEY_U:
			press("act:potion")
		KEY_R:
			press("act:ready")
		KEY_X:
			press("act:flee")
		KEY_Q:
			press("weapon:%d" % ((c.wi + 1) % maxi(1, c.weapons.size())))


## Нажатие кнопки интерфейса по её id (мышь, клавиши и тесты идут сюда)
func press(id: String) -> void:
	if id.begins_with("prep:"):
		prep_toggle(id.substr(5))
		return
	match id:
		"prep_go":
			prep_confirm()
			return
		"finish":
			leave()
			return
		"log":
			show_log = not show_log
			return
		"companions":
			toggle_companions()
			return
	if id.begins_with("foe:"):
		var c0 = me()
		if c0 != null:
			click_cell(core.all[int(id.substr(4))].cell)
		return
	var c = me()
	if c == null:
		return
	if id == "end":
		core.end_turn()
	elif id == "move":
		mode = "move"
	elif id.begins_with("weapon:"):
		var i: int = int(id.substr(7))
		if i < c.weapons.size() and core.draw_weapon(c, i):
			mode = "attack"
	elif id.begins_with("ab:"):
		var ab: BattleAbility = Data.ability(id.substr(3))
		if ab.target == "self":
			core.use_ability(c, ab, c)
			mode = "move"
		else:
			mode = "ability:" + ab.id
	elif id.begins_with("act:"):
		match id.substr(4):
			"dash":
				core.dash(c)
			"disengage":
				core.disengage(c)
			"dodge":
				core.dodge(c)
			"help":
				mode = "help"
			"hide":
				core.hide(c)
			"potion":
				mode = "use"
			"ready":
				core.ready_attack(c)
			"flee":
				core.flee(c)


func _hit_at(p: Vector2) -> String:
	for i in range(hits.size() - 1, -1, -1):
		if hits[i]["rect"].has_point(p):
			return hits[i]["id"]
	return ""


func toggle_companions() -> void:
	companions_ai = not companions_ai
	for c in core.all:
		if c.team == 0 and not c.is_hero:
			c.controlled = not companions_ai
	core.log_line(I18n.t("Спутники и питомцы: %s.") % (I18n.t("ходят сами") if companions_ai else I18n.t("под управлением игрока")), "info")
	var cur = core.current()
	if cur != null and cur.team == 0 and not cur.is_hero and companions_ai and ai_wait < 0.0 and phase == "battle":
		ai_wait = AI_DELAY_S


func unit_at(cell: Vector2i):
	for c in core.all:
		if c.active() and c.cell == cell:
			return c
	return null


## Клик по клетке в ход игрока: идти, атаковать (подойти и ударить), цель способности, помощь, зелье
func click_cell(cell: Vector2i) -> void:
	var c = me()
	if c == null:
		return
	var u = unit_at(cell)
	if mode.begins_with("ability:"):
		var ab: BattleAbility = Data.ability(mode.substr(8))
		var target = cell if ab.target == "cell" else u
		if core.use_ability(c, ab, target):
			mode = "move"
		return
	if mode == "help":
		if u != null and core.help(c, u):
			mode = "move"
		return
	if mode == "use":
		if core.use_object(c, u if u != null else c):
			mode = "move"
		return
	if u != null and u.team != c.team:
		attack_or_approach(c, u)
	elif u == null:
		core.move_to(c, cell)


func attack_or_approach(c, t) -> bool:
	if core.can_attack(c, t)["ok"]:
		return core.attack(c, t)
	if not c.has_action or c.weapon().ranged:
		core.attack(c, t)       # напишет в лог, почему нет
		return false
	var best = _approach_cell(c, t)
	if best == null:
		core.log_line(I18n.t("%s: до %s не дойти за этот ход.") % [c.title, t.title], "info")
		return false
	core.move_to(c, best)
	if c.standing() and core.can_attack(c, t)["ok"]:
		return core.attack(c, t)
	return false


func _approach_cell(c, t):
	var reach: Dictionary = core.reach_of(c)
	var best = null
	var bc: int = 1 << 30
	for cell in reach:
		if reach[cell].get("pass_only", false):
			continue
		if core.grid.dist_ft(cell, t.cell) <= c.weapon().reach_ft and int(reach[cell]["cost"]) < bc:
			bc = int(reach[cell]["cost"])
			best = cell
	return best


# =====================================================================
# СОХРАНЕНИЕ (Worlds пишет req, состояние боя — здесь)
# =====================================================================
func to_dict() -> Dictionary:
	var d: Dictionary = core.to_dict()
	d["companions_ai"] = companions_ai
	d["phase"] = phase
	return d


func load_dict(d: Dictionary) -> void:
	_loaded = true
	core.load_dict(d)
	companions_ai = bool(d.get("companions_ai", true))
	for c in core.all:
		vis[c] = Vector2(c.cell)
	paths.clear()
	for line in core.log_lines:
		_on_log(line, "info")
	if core.round_n <= 0 or String(d.get("phase", "battle")) == "prep":
		_loaded = false
		call_deferred("_begin")
		return
	phase = "battle"
	var cur = core.current()
	if cur != null and not cur.controlled:
		ai_wait = AI_DELAY_S


# =====================================================================
# ГЕОМЕТРИЯ
# =====================================================================
func vp() -> Vector2:
	return hud.get_viewport_rect().size if hud != null and hud.is_inside_tree() else Vector2(1366, 800)


## Место под поле: между колонками, под очередью и над репликой
func grid_rect() -> Rect2:
	var v: Vector2 = vp()
	var x0: float = PAD + COL_W + 14.0
	var x1: float = v.x - PAD - COL_W - 14.0
	return Rect2(Vector2(x0, 54.0), Vector2(x1 - x0, v.y - 54.0 - 88.0))


func cell_px() -> float:
	var r: Rect2 = grid_rect()
	var gs: Vector2i = core.grid.size
	return floorf(minf(r.size.x / gs.x, r.size.y / gs.y))


func origin() -> Vector2:
	var r: Rect2 = grid_rect()
	var s: float = cell_px()
	return (r.position + (r.size - Vector2(core.grid.size) * s) / 2.0).floor()


func cell_to_screen(p: Vector2) -> Vector2:
	return origin() + (p + Vector2(0.5, 0.5)) * cell_px()


func screen_to_cell(s: Vector2) -> Vector2i:
	var q: Vector2 = (s - origin()) / cell_px()
	return Vector2i(floori(q.x), floori(q.y))


# =====================================================================
# ПОЛЕ
# =====================================================================
func _draw_field(v: Node2D) -> void:
	var size: Vector2 = vp()
	v.draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.065, 0.05))
	if phase == "prep":
		return
	var s: float = cell_px()
	var g = core.grid
	var o: Vector2 = origin()
	var area := Rect2(o, Vector2(g.size) * s)
	var night: bool = bool(req.get("night", false))
	var tint: Color = Color(0.62, 0.66, 0.85) if night else Color.WHITE
	v.draw_rect(area.grow(6.0), Color(0.2, 0.17, 0.12))
	v.draw_rect(area.grow(6.0), Color(0, 0, 0, 0.8), false, 2.0)
	if ground_tex != null:
		var k: float = s * 1.3 / float(ground_tex.get_width())
		v.draw_set_transform(o, 0.0, Vector2(k, k))
		v.draw_texture_rect(ground_tex, Rect2(Vector2.ZERO, area.size / k), true, tint)
		v.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		v.draw_rect(area, Color(0.6, 0.53, 0.38) * tint)
	v.draw_rect(area, Color(0.35, 0.39, 0.25, 0.30) if core.arena_key in ["forest", "rad_forest"] else Color(0.52, 0.46, 0.33, 0.16))
	for p in g.high:
		var r := Rect2(o + Vector2(p) * s, Vector2(s, s))
		v.draw_rect(r, Color(1, 1, 0.9, 0.14))
		v.draw_line(r.position, r.position + Vector2(s, 0), Color(1, 1, 0.9, 0.35), 2.0)
	for p in g.difficult:
		var r := Rect2(o + Vector2(p) * s, Vector2(s, s))
		v.draw_rect(r, Color(0.25, 0.2, 0.1, 0.32))
		for i in 3:
			var y: float = r.position.y + s * (0.25 + 0.25 * i)
			v.draw_line(Vector2(r.position.x + 5, y), Vector2(r.position.x + s - 5, y + 3), Color(0.15, 0.12, 0.06, 0.55), 1.0)
	for p in g.hazard:
		v.draw_rect(Rect2(o + Vector2(p) * s, Vector2(s, s)), Color(0.8, 1.0, 0.2, 0.25))
	for x in g.size.x + 1:
		v.draw_line(o + Vector2(x * s, 0), o + Vector2(x * s, g.size.y * s), Color(0.22, 0.18, 0.12, 0.17), 1.0)
	for y in g.size.y + 1:
		v.draw_line(o + Vector2(0, y * s), o + Vector2(g.size.x * s, y * s), Color(0.22, 0.18, 0.12, 0.17), 1.0)
	# подсветка: зелёные клетки — куда дойти; песочные — куда достаёт оружие
	var c = me()
	var reach: Dictionary = {}
	if c != null:
		if mode == "move":
			reach = core.reach_of(c)
			for p in reach:
				if not reach[p].get("pass_only", false) and p != c.cell:
					_cell_hl(v, p, C_MOVE)
		elif mode == "attack":
			var w: BattleWeapon = c.weapon()
			var rr: int = (w.range_ft if w.ranged else w.reach_ft) / g.cell_ft
			for dx in range(-rr, rr + 1):
				for dy in range(-rr, rr + 1):
					var p: Vector2i = c.cell + Vector2i(dx, dy)
					if p != c.cell and g.in_bounds(p) and g.walkable(p):
						_cell_hl(v, p, C_RANGE)
	# Storybook: препятствия — вертикальные спрайты, сортировка по глубине; след клетки остаётся виден
	var paint: Array = []
	for p in g.obstacle:
		var cc: Vector2 = cell_to_screen(Vector2(p))
		var kind: String = String(g.obstacle[p])
		var key: String = (["tree_oak", "tree_light", "tree_crooked"][posmod(p.x + p.y, 3)] if kind == "tree" else (("mesa_hot" if core.arena_key == "hot" else "cliff_gray") if kind == "cliff" else "rock"))
		v.draw_rect(Rect2(cc - Vector2.ONE * s * 0.46, Vector2.ONE * s * 0.92), Color(0.24, 0.19, 0.12, 0.45), false, 1.0)
		paint.append({"key": key, "foot": cc + Vector2(0, s * 0.20), "height": s * (1.65 if kind == "tree" else 1.15)})
	paint.sort_custom(func(aa: Dictionary, bb: Dictionary) -> bool: return aa["foot"].y < bb["foot"].y)
	for item in paint:
		Art.sprite(v, item["key"], item["foot"], item["height"], tint)
	if c != null and g.in_bounds(hover_cell):
		_draw_hover_field(v, c, reach)
	var font: Font = ThemeDB.fallback_font
	for u in core.all:
		if u.fled:
			continue
		var cc: Vector2 = cell_to_screen(vis.get(u, Vector2(u.cell)))
		var r: float = s * 0.42
		if u.dead:
			v.draw_circle(cc, r * 0.7, Color(0.2, 0.17, 0.14, 0.8))
			v.draw_line(cc + Vector2(-r, -r) * 0.45, cc + Vector2(r, r) * 0.45, Color(0.55, 0.1, 0.08), 3.0)
			v.draw_line(cc + Vector2(-r, r) * 0.45, cc + Vector2(r, -r) * 0.45, Color(0.55, 0.1, 0.08), 3.0)
			continue
		_token(v, u, cc, r)
	for f in floaters:
		var p: Vector2 = cell_to_screen(Vector2(f["cell"])) + Vector2(0, -s * 0.6 - 24.0 * f["t"])
		var a: float = clampf(1.5 - f["t"], 0.0, 1.0)
		_tag(v, p, f["text"], Color(f["col"], a * 0.92), Color(1, 1, 1, a), 16)


func _cell_hl(v: Node2D, p: Vector2i, col: Color) -> void:
	var s: float = cell_px()
	var r := Rect2(origin() + Vector2(p) * s + Vector2(2, 2), Vector2(s - 4, s - 4))
	v.draw_rect(r, Color(col, 0.42))
	v.draw_rect(r, Color(col.lightened(0.3), 0.8), false, 1.5)


func portrait_kind(u) -> String:
	if u.is_hero:
		return "hero"
	if u.creature != null:
		return {"bandit": "bandit", "bandit_archer": "archer", "bandit_chief": "chief", "wolf": "wolf", "boar": "boar",
			"rad_hound": "hound", "dog": "dog"}.get(u.creature.resource_path.get_file().get_basename(), "bandit" if u.human else "wolf")
	return "npc"


func ring_color(u) -> Color:
	if u.team == 1:
		return C_FOE_RING
	return C_ALLY_RING if u.is_hero else C_NPC_RING


func _token(v: CanvasItem, u, cc: Vector2, r: float) -> void:
	var cur: bool = u == core.current() and phase == "battle"
	var target: bool = false
	var c = me()
	if c != null and u.team != c.team and u.cell == hover_cell and mode in ["move", "attack"]:
		target = true
	v.draw_circle(cc + Vector2(2, 4), r + 4.0, Color(0, 0, 0, 0.45))
	v.draw_circle(cc, r + 4.0, Color(0.06, 0.06, 0.05))
	var ring: Color = Color(0.85, 0.15, 0.1) if target else ring_color(u)
	v.draw_arc(cc, r + 2.0, 0.0, TAU, 32, ring, 3.5, true)
	Icons.portrait(v, portrait_kind(u), cc, r - 1.0, u.down)
	if cur:
		var pulse: float = 1.5 * sin(_anim_t * 5.0)
		v.draw_arc(cc, r + 6.5 + pulse, 0.0, TAU, 36, C_ORANGE, 2.5, true)
		for a in 4:
			var dir := Vector2.from_angle(a * PI / 2.0 + PI / 4.0)
			v.draw_line(cc + dir * (r + 4.0), cc + dir * (r + 10.0 + pulse), C_ORANGE, 2.5, true)
	if target:
		for a in 4:
			var dir := Vector2.from_angle(a * PI / 2.0)
			v.draw_line(cc + dir * (r - 2.0), cc + dir * (r + 9.0), Color(0.9, 0.15, 0.1), 2.5, true)
	if u.down:
		v.draw_string(ThemeDB.fallback_font, cc + Vector2(-r, r * 0.25), "zZ", HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 14, Color(0.1, 0.1, 0.2))
	var w: float = r * 1.6
	var hp: float = clampf(float(u.hp) / float(u.max_hp), 0.0, 1.0)
	var bp: Vector2 = cc + Vector2(-w / 2.0, r + 6.0)
	v.draw_rect(Rect2(bp - Vector2(1, 1), Vector2(w + 2, 5)), Color(0, 0, 0, 0.85))
	v.draw_rect(Rect2(bp, Vector2(w * hp, 3)), Color(0.85, 0.2, 0.15) if hp < 0.3 else C_HP)
	var ix: float = -w / 2.0
	for e in u.effects:
		v.draw_rect(Rect2(cc + Vector2(ix, -r - 10.0), Vector2(7, 7)), _effect_color(e["id"]))
		ix += 9.0


func _effect_color(id: String) -> Color:
	return {"prone": Color(0.8, 0.6, 0.3), "poisoned": Color(0.5, 0.9, 0.3), "burning": Color(1.0, 0.45, 0.1),
		"bleeding": Color(0.8, 0.05, 0.05), "dodging": Color(0.5, 0.7, 1.0), "hidden": Color(0.4, 0.4, 0.5),
		"stunned": Color(1.0, 0.95, 0.4), "restrained": Color(0.6, 0.5, 0.4), "frightened": Color(0.7, 0.4, 0.9),
		"unconscious": Color(0.3, 0.3, 0.3), "rallied": Color(1.0, 0.85, 0.3)}.get(id, Color(0.85, 0.85, 0.85))


## Чёрная табличка с текстом (как «100%» и «20–35» над целью в образце)
func _tag(ci: CanvasItem, center_bottom: Vector2, text: String, bg: Color, fg: Color, size: int = 14) -> float:
	var font: Font = ThemeDB.fallback_font
	var ts: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var r := Rect2(center_bottom - Vector2(ts.x / 2.0 + 6.0, ts.y + 2.0), Vector2(ts.x + 12.0, ts.y + 2.0))
	ci.draw_rect(r, bg)
	ci.draw_rect(r, Color(0.9, 0.85, 0.7, bg.a * 0.6), false, 1.0)
	ci.draw_string(font, r.position + Vector2(6, ts.y - 3.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, fg)
	return r.size.y


func _draw_hover_field(v: Node2D, c, reach: Dictionary) -> void:
	var s: float = cell_px()
	var g = core.grid
	var u = unit_at(hover_cell)
	if mode.begins_with("ability:"):
		var ab: BattleAbility = Data.ability(mode.substr(8))
		if ab.radius_ft > 0:
			var rr: int = ab.radius_ft / g.cell_ft
			v.draw_rect(Rect2(origin() + Vector2(hover_cell - Vector2i(rr, rr)) * s, Vector2(rr * 2 + 1, rr * 2 + 1) * s), Color(1.0, 0.5, 0.2, 0.25))
	elif u != null and u.team != c.team and u.active():
		var pv: Dictionary = core.preview_attack(c, u)
		var top: Vector2 = cell_to_screen(Vector2(u.cell)) + Vector2(0, -s * 0.5 - 6.0)
		var h: float = _tag(v, top, "%d–%d" % [pv["dmg"].x, pv["dmg"].y], Color(0.05, 0.05, 0.04, 0.92), C_TEXT, 14)
		_tag(v, top - Vector2(0, h + 2.0), "%d%%" % int(round(pv["chance"] * 100.0)), Color(0.05, 0.05, 0.04, 0.92), Color.WHITE, 14)
		if not pv["ok"] and not c.weapon().ranged and c.has_action:
			var best = _approach_cell(c, u)
			if best != null:
				var path: Array = core.path_for(c, reach if not reach.is_empty() else core.reach_of(c), best)
				for i in range(1, path.size()):
					v.draw_line(cell_to_screen(Vector2(path[i - 1])), cell_to_screen(Vector2(path[i])), Color(1.0, 0.4, 0.3, 0.9), 3.0)
	elif u == null and mode == "move" and reach.has(hover_cell) and not reach[hover_cell].get("pass_only", false):
		var path: Array = core.path_for(c, reach, hover_cell)
		for i in range(1, path.size()):
			v.draw_line(cell_to_screen(Vector2(path[i - 1])), cell_to_screen(Vector2(path[i])), Color(0.85, 1.0, 0.6, 0.95), 3.0)
		_tag(v, cell_to_screen(Vector2(hover_cell)) + Vector2(0, -s * 0.5 - 2.0), I18n.t("%d кл.") % int(reach[hover_cell]["cost"] / 5), Color(0.05, 0.05, 0.04, 0.9), C_TEXT, 13)
	v.draw_rect(Rect2(origin() + Vector2(hover_cell) * s, Vector2(s, s)), Color(1, 1, 1, 0.55), false, 1.5)


## Описание того, что под курсором, — в реплику внизу
func hover_text() -> String:
	if phase != "battle":
		return ""
	var c = me()
	if hover_hit != "" and not hover_hit.begins_with("foe:"):
		return _button_text(hover_hit, c)
	if c == null or not core.grid.in_bounds(hover_cell):
		return ""
	var u = unit_at(hover_cell)
	if mode.begins_with("ability:"):
		var ab: BattleAbility = Data.ability(mode.substr(8))
		var ok: Dictionary = core.can_ability(c, ab, hover_cell if ab.target == "cell" else u)
		var t: String = "%s: %s." % [ab.title, I18n.t("можно") if ok["ok"] else ok["why"]]
		if ab.kind == "save":
			t += I18n.t(" Спасбросок %s против сложности %d.") % [Rules.Combatant.STAT_NAMES.get(ab.save_stat, ab.save_stat), Rules.save_dc(c, ab.stat)]
			if u != null and u.team != c.team:
				var m: int = u.mod(ab.save_stat) + (u.prof() if u.save_profs.has(ab.save_stat) else 0)
				t += I18n.t(" %s провалит с шансом %d%%.") % [u.title, int(round((1.0 - DiceRoller.chance(m, Rules.save_dc(c, ab.stat), false, false, false)) * 100.0))]
		return t
	if u != null and u.team != c.team and u.active():
		var pv: Dictionary = core.preview_attack(c, u)
		var t: String = I18n.t("%s: здоровье %d/%d, %s. %s: попадание %d%% (бросок +%d), урон %d–%d.") % [u.title, u.hp, u.max_hp,
			pv["ac"]["text"], pv["weapon"].title, int(round(pv["chance"] * 100.0)), int(pv["mod"]), pv["dmg"].x, pv["dmg"].y]
		if pv["cover"] != "none":
			t += I18n.t(" Укрытие %s.") % {"half": "½", "three_quarters": "¾", "full": I18n.t("полное")}.get(pv["cover"], "")
		if not pv["adv"].is_empty():
			t += I18n.t(" Преимущество: ") + ", ".join(PackedStringArray(pv["adv"])) + "."
		if not pv["dis"].is_empty():
			t += I18n.t(" Помеха: ") + ", ".join(PackedStringArray(pv["dis"])) + "."
		if not pv["ok"]:
			t += " (%s%s)" % [pv["why"], I18n.t(" — подойдёт и ударит") if not c.weapon().ranged and _approach_cell(c, u) != null and c.has_action else ""]
		return t
	if u != null:
		var t: String = "%s: здоровье %d/%d, %s." % [u.title, u.hp, u.max_hp, Rules.ac(u)["text"]]
		for e in u.effects:
			t += " " + e["res"].title + "."
		return t
	if mode == "move":
		var reach: Dictionary = core.reach_of(c)
		if reach.has(hover_cell) and not reach[hover_cell].get("pass_only", false):
			var t: String = I18n.t("Идти: %d кл. из %d.") % [int(reach[hover_cell]["cost"] / 5), c.move_left / 5]
			if _provokes(c, core.path_for(c, reach, hover_cell)):
				t += I18n.t(" Враг рядом ударит вслед (атака по возможности).")
			if core.grid.difficult.has(hover_cell):
				t += I18n.t(" Трудная местность.")
			return t
	return ""


func _provokes(c, path: Array) -> bool:
	if c.disengaged:
		return false
	for e in core.all:
		if e.team == c.team or not e.standing() or e.incapacitated() or not e.has_reaction:
			continue
		for i in range(1, path.size()):
			if core.grid.dist_ft(path[i - 1], e.cell) <= 5 and core.grid.dist_ft(path[i], e.cell) > 5:
				return true
	return false


func _float(t, text: String, col: Color) -> void:
	floaters.append({"cell": t.cell, "text": text, "t": 0.0, "col": col})


# =====================================================================
# ИНТЕРФЕЙС
# =====================================================================
func _build() -> void:
	view = Layer.new()
	view.fn = _draw_field
	add_child(view)
	add_child(preload("res://ui/world_grade.gd").rect())   # тёмная палитра мира (Q31 B): поле — да, панели — нет
	hud = Layer.new()
	hud.fn = _draw_hud
	add_child(hud)
	log_box = RichTextLabel.new()
	log_box.bbcode_enabled = true
	log_box.scroll_following = true
	log_box.add_theme_font_size_override("normal_font_size", 13)
	log_box.add_theme_stylebox_override("normal", ComicUI.panel(22.0))   # рамка комикса (Q24)
	log_box.visible = false
	add_child(log_box)


func _hit(r: Rect2, id: String) -> void:
	hits.append({"rect": r, "id": id})


## Плашка интерфейса боя: тонкая стальная рамка комикса (ui/comic_ui.gd, Q24) чуть шире прямоугольника,
## чтобы рамка не налезала на текст; наведение (fill = C_PANEL_HI) — светлее, своя заливка — внутри рамки,
## выбор — цветная кромка hl
func _panel(ci: CanvasItem, r: Rect2, hl: Color = Color(0, 0, 0, 0), fill: Color = C_PANEL) -> void:
	ci.draw_rect(Rect2(r.position + Vector2(3, 4), r.size), Color(0, 0, 0, 0.45))
	if r.size.x >= 24.0 and r.size.y >= 20.0:
		ComicUI.draw_box(ci, "button", r.grow(5.0), Color(1.3, 1.3, 1.35) if fill == C_PANEL_HI else Color.WHITE)
		if fill != C_PANEL and fill != C_PANEL_HI:   # цветная кнопка («В бой», «Конец хода») — заливка внутри рамки
			ci.draw_rect(r.grow(-3.0), fill)
	else:
		ci.draw_rect(r, fill)
		ci.draw_rect(r, Color(0, 0, 0, 0.95), false, 1.5)
	if hl.a > 0.0:
		ci.draw_rect(r.grow(-1.0), hl, false, 2.5)


func _text(ci: CanvasItem, p: Vector2, t: String, size: int, col: Color = C_TEXT, w: float = -1.0, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var font: Font = ThemeDB.fallback_font
	ci.draw_string_outline(font, p, t, align, w, size, 3, Color(0, 0, 0, 0.8))
	ci.draw_string(font, p, t, align, w, size, col)


func _cross(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	ci.draw_rect(Rect2(c - Vector2(s * 0.22, s * 0.6), Vector2(s * 0.44, s * 1.2)), col)
	ci.draw_rect(Rect2(c - Vector2(s * 0.6, s * 0.22), Vector2(s * 1.2, s * 0.44)), col)


func _shield(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	var p := PackedVector2Array([c + Vector2(-0.55, -0.6) * s, c + Vector2(0.55, -0.6) * s, c + Vector2(0.5, 0.1) * s,
		c + Vector2(0, 0.7) * s, c + Vector2(-0.5, 0.1) * s])
	ci.draw_colored_polygon(p, col)


func _crosshair(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	ci.draw_arc(c, s * 0.55, 0.0, TAU, 16, col, 1.6, true)
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		ci.draw_line(c + d * s * 0.3, c + d * s * 0.85, col, 1.6, true)


func _draw_hud(ci: Node2D) -> void:
	hits.clear()
	if phase == "prep":
		_draw_prep(ci)
		return
	var v: Vector2 = vp()
	var c = me()
	var cur = core.current()
	var who = c if c != null else core.hero()
	if who == null:
		who = cur
	_draw_queue(ci)
	# ---- левая колонка: герой, движение, оружие, действия, спутники
	var x: float = PAD
	var y: float = PAD
	if who != null:
		_hero_card(ci, Rect2(x, y, COL_W, 118), who, c != null)
		y += 126.0
		var mr := Rect2(x, y, COL_W, 50)
		_panel(ci, mr, C_ORANGE if c != null and mode == "move" else Color(0, 0, 0, 0))
		var ib := Rect2(x + 10, y + 6, 46, 38)
		ci.draw_rect(ib, Color(0.82, 0.8, 0.72))
		ci.draw_rect(ib, Color(0, 0, 0, 0.8), false, 1.0)
		Icons.action(ci, "move", ib.grow(-3.0), Color(0.12, 0.1, 0.08))
		_text(ci, Vector2(x + 66, y + 23), I18n.t("Движение"), 16)
		_text(ci, Vector2(x + 66, y + 42), I18n.t("%d / %d кл.") % [(who.move_left if c != null else who.speed()) / 5, who.speed() / 5], 13, C_DIM)
		_text(ci, Vector2(x + COL_W - 26, y + 44), "M", 11, C_DIM)
		_hit(mr, "move")
		y += 58.0
		for i in 3:
			var wr := Rect2(x, y, COL_W, 80)
			if i < who.weapons.size():
				_weapon_card(ci, wr, who, i, c != null)
				_hit(wr, "weapon:%d" % i)
			else:
				_panel(ci, wr, Color(0, 0, 0, 0), Color(0.08, 0.09, 0.065))
				_text(ci, Vector2(x, y + 46), I18n.t("пусто"), 13, Color(C_DIM, 0.5), COL_W, HORIZONTAL_ALIGNMENT_CENTER)
			y += 86.0
		y = _actions(ci, Vector2(x, y), who, c)
		y = _allies(ci, Vector2(x, y + 6.0), who)
	var tb := Rect2(x, v.y - 36.0, COL_W, 28)
	_panel(ci, tb, Color(0, 0, 0, 0), C_PANEL_HI if hover_hit == "companions" else C_PANEL)
	_text(ci, tb.position + Vector2(0, 19), I18n.t("C  Спутники: ") + (I18n.t("сами") if companions_ai else I18n.t("вручную")), 13, C_TEXT, COL_W, HORIZONTAL_ALIGNMENT_CENTER)
	_hit(tb, "companions")
	# ---- правая колонка: враги и «Конец хода»
	_foe_column(ci, v)
	var er := Rect2(v.x - PAD - COL_W, v.y - 56.0, COL_W, 48)
	var can_end: bool = c != null
	_panel(ci, er, C_ORANGE if can_end and hover_hit == "end" else Color(0, 0, 0, 0), Color(0.36, 0.42, 0.22) if can_end else Color(0.14, 0.15, 0.11))
	ci.draw_rect(er.grow(-6.0), Color(0.86, 0.84, 0.62, 0.15 if can_end else 0.05))
	_text(ci, er.position + Vector2(0, 31), I18n.t("Конец хода"), 18, C_TEXT if can_end else C_DIM, COL_W, HORIZONTAL_ALIGNMENT_CENTER)
	_hit(er, "end")
	# ---- реплика внизу
	_speech(ci, v)
	_dice(ci)
	_banner(ci)
	if phase == "end":
		_draw_end(ci)


func _draw_queue(ci: CanvasItem) -> void:
	var r: Rect2 = grid_rect()
	var x: float = r.position.x + 18.0
	var y: float = 26.0
	_text(ci, Vector2(r.position.x, 20), "", 12)
	for u in core.order:
		if u.fled or u.dead:
			continue
		var cur: bool = u == core.current()
		var rad: float = 17.0 if cur else 14.0
		ci.draw_circle(Vector2(x, y), rad + 2.5, Color(0.05, 0.05, 0.05))
		ci.draw_arc(Vector2(x, y), rad + 1.0, 0.0, TAU, 24, C_ORANGE if cur else ring_color(u), 2.5, true)
		Icons.portrait(ci, portrait_kind(u), Vector2(x, y), rad - 1.0, u.down)
		_text(ci, Vector2(x - 14, y + rad + 12.0), str(u.initiative), 11, C_DIM, 28, HORIZONTAL_ALIGNMENT_CENTER)
		x += rad * 2.0 + 10.0
		if x > r.end.x - 120.0:
			break
	var night: String = I18n.t(", ночь") if req.get("night", false) else ""
	_text(ci, Vector2(r.end.x - 260, 22), "%s%s" % [ARENA_NAMES.get(core.arena_key, core.arena_key), night], 13, C_DIM, 260, HORIZONTAL_ALIGNMENT_RIGHT)
	_text(ci, Vector2(r.end.x - 260, 42), I18n.t("Раунд %d") % maxi(core.round_n, 1), 16, C_TEXT, 260, HORIZONTAL_ALIGNMENT_RIGHT)


func _hero_card(ci: CanvasItem, r: Rect2, u, mine: bool) -> void:
	_panel(ci, r)
	_text(ci, r.position + Vector2(12, 22), u.title, 16)
	var pc: Vector2 = r.position + Vector2(44, 66)
	ci.draw_circle(pc, 31.0, Color(0.05, 0.05, 0.05))
	ci.draw_arc(pc, 30.0, 0.0, TAU, 32, ring_color(u), 2.5, true)
	Icons.portrait(ci, portrait_kind(u), pc, 28.0, u.down)
	_cross(ci, r.position + Vector2(96, 49), 12.0, C_HP)
	_text(ci, r.position + Vector2(110, 57), "%d / %d" % [u.hp, u.max_hp], 20, C_HP)
	_shield(ci, r.position + Vector2(96, 75), 12.0, Color(0.62, 0.64, 0.66))
	_text(ci, r.position + Vector2(110, 82), I18n.t("Защита %d") % int(Rules.ac(u)["total"]), 15, Color(0.8, 0.8, 0.78))
	var font: Font = ThemeDB.fallback_font
	var px: float = r.position.x + 96.0
	var on: bool = mine
	Icons.pip(ci, Vector2(px, r.position.y + 101), 10.0, on and u.has_action, I18n.t("Д"), font)
	Icons.pip(ci, Vector2(px + 26, r.position.y + 101), 10.0, on and u.has_bonus, I18n.t("Б"), font)
	Icons.pip(ci, Vector2(px + 52, r.position.y + 101), 10.0, on and u.has_reaction, I18n.t("Р"), font)
	var ix: float = r.position.x + 12.0
	for e in u.effects:
		ci.draw_rect(Rect2(ix, r.position.y + 100, 9, 9), _effect_color(e["id"]))
		ix += 11.0


func _weapon_card(ci: CanvasItem, r: Rect2, u, i: int, mine: bool) -> void:
	var w: BattleWeapon = u.weapons[i]
	var sel: bool = i == u.wi
	var hl: Color = C_ORANGE if sel and (mode == "attack" or not mine) else (Color(C_ORANGE, 0.55) if sel else Color(0, 0, 0, 0))
	_panel(ci, r, hl, C_PANEL_HI if hover_hit == "weapon:%d" % i else C_PANEL)
	var no_ammo: bool = w.ammo > 0 and int(u.ammo.get(w.id, 0)) <= 0
	ci.draw_rect(Rect2(r.position + Vector2(5, 8), Vector2(4, r.size.y - 16)), Color(0.85, 0.2, 0.15) if no_ammo else C_HP)
	var ib := Rect2(r.position + Vector2(16, 8), Vector2(64, 64))
	ci.draw_rect(ib, Color(0.74, 0.8, 0.82) if not no_ammo else Color(0.45, 0.47, 0.48))
	ci.draw_rect(ib, Color(0, 0, 0, 0.8), false, 1.0)
	Icons.weapon(ci, w.icon, ib.grow(-6.0), no_ammo)
	var main_type: String = String(w.damage[-1].get("type", "")) if not w.damage.is_empty() else ""
	if main_type != "" and (w.damage.size() > 1 or main_type in ["fire", "radiation", "poison", "cold"]):
		Icons.damage_type(ci, main_type, ib.end - Vector2(8, 8), 7.0)
	var font: Font = ThemeDB.fallback_font
	var tx: float = r.position.x + 90.0
	Icons.pip(ci, Vector2(tx + 8, r.position.y + 17), 8.0, not mine or u.has_action, I18n.t("Д"), font)
	_text(ci, Vector2(tx + 22, r.position.y + 22), w.title, 13, C_TEXT, r.size.x - 116.0)
	_crosshair(ci, Vector2(tx + 8, r.position.y + 42), 10.0, C_TEXT)
	var lo: int = 0
	var hi: int = 0
	for comp in Rules.components(u, w):
		var rg: Vector2i = DiceRoller.range_of(comp["dice"]) if String(comp["dice"]) != "" else Vector2i.ZERO
		lo += maxi(0, rg.x + int(comp["F"]))
		hi += maxi(0, rg.y + int(comp["F"]))
	_text(ci, Vector2(tx + 22, r.position.y + 48), "%d–%d" % [lo, hi], 17)
	var line3: String
	if w.ammo > 0:
		line3 = "▮ %d / %d" % [int(u.ammo.get(w.id, 0)), w.ammo]
	elif w.ranged:
		line3 = I18n.t("%d/%d кл.") % [w.range_ft / 5, w.long_range_ft / 5]
	else:
		line3 = I18n.t("вплотную") if w.reach_ft <= 5 else I18n.t("%d кл.") % (w.reach_ft / 5)
	_text(ci, Vector2(tx + 22, r.position.y + 69), line3, 12, C_DIM)
	_text(ci, Vector2(r.end.x - 18, r.end.y - 8), str(i + 1), 11, C_DIM)


static var ACTIONS: Array = [["dash", I18n.t("Рывок"), "D"], ["disengage", I18n.t("Отход"), "G"], ["dodge", I18n.t("Уклонение"), "V"], ["help", I18n.t("Помощь"), "H"],
	["hide", I18n.t("Спрятаться"), "K"], ["potion", I18n.t("Зелье"), "U"], ["ready", I18n.t("Подготовить"), "R"], ["flee", I18n.t("Уйти с поля"), "X"]]


func _actions(ci: CanvasItem, p: Vector2, u, mine) -> float:
	var list: Array = []
	for i in u.abilities.size():
		var ab: BattleAbility = u.abilities[i]
		var left: int = ab.uses_per_battle - int(u.uses.get(ab.id, 0)) if ab.uses_per_battle > 0 else -1
		list.append({"id": "ab:" + ab.id, "icon": ab.id, "n": left, "key": str(4 + i)})
	for a in ACTIONS:
		list.append({"id": "act:" + a[0], "icon": a[0], "n": u.potions if a[0] == "potion" else -1, "key": a[2]})
	var size: float = 44.0
	var gap: float = (COL_W - size * 5.0) / 4.0
	for i in list.size():
		var r := Rect2(p + Vector2((i % 5) * (size + gap), floorf(i / 5.0) * (size + 6.0)), Vector2(size, size))
		var e: Dictionary = list[i]
		var on: bool = mine != null
		var sel: bool = mode == "ability:" + String(e["id"]).substr(3) or (e["id"] == "act:help" and mode == "help") or (e["id"] == "act:potion" and mode == "use")
		_panel(ci, r, C_ORANGE if sel else Color(0, 0, 0, 0), C_PANEL_HI if hover_hit == e["id"] else C_PANEL)
		Icons.action(ci, String(e["icon"]), r.grow(-9.0), C_TEXT if on else C_DIM)
		if int(e["n"]) >= 0:
			_text(ci, r.end - Vector2(12, 4), str(e["n"]), 11, C_ORANGE if int(e["n"]) > 0 else Color(0.8, 0.3, 0.2))
		_text(ci, r.position + Vector2(3, 11), String(e["key"]), 9, C_DIM)
		_hit(r, String(e["id"]))
	return p.y + ceilf(list.size() / 5.0) * (size + 6.0)


func _allies(ci: CanvasItem, p: Vector2, who) -> float:
	var y: float = p.y
	var v: Vector2 = vp()
	for u in core.all:
		if u.team != 0 or u == who or u.fled:
			continue
		if y + 40.0 > v.y - 42.0:
			break
		var r := Rect2(p.x, y, COL_W, 38)
		_panel(ci, r, C_ORANGE if u == core.current() else Color(0, 0, 0, 0))
		var pc: Vector2 = r.position + Vector2(20, 19)
		ci.draw_circle(pc, 15.0, Color(0.05, 0.05, 0.05))
		Icons.portrait(ci, portrait_kind(u), pc, 13.0, u.down or u.dead)
		_text(ci, r.position + Vector2(42, 16), u.title + (" †" if u.dead else (I18n.t(" (без сознания)") if u.down else "")), 13, C_DIM if u.dead else C_TEXT)
		var hp: float = clampf(float(u.hp) / float(u.max_hp), 0.0, 1.0)
		ci.draw_rect(Rect2(r.position + Vector2(42, 24), Vector2(140, 6)), Color(0, 0, 0, 0.7))
		ci.draw_rect(Rect2(r.position + Vector2(42, 24), Vector2(140 * hp, 6)), C_HP if hp >= 0.3 else Color(0.85, 0.2, 0.15))
		_text(ci, r.position + Vector2(188, 31), "%d/%d" % [u.hp, u.max_hp], 12, C_DIM)
		y += 44.0
	return y


func _foe_column(ci: CanvasItem, v: Vector2) -> void:
	var foes: Array = core.all.filter(func(u): return u.team == 1)
	var avail: float = v.y - PAD - 64.0
	var h: float = clampf(avail / maxf(1.0, foes.size()) - 8.0, 46.0, 96.0)
	var y: float = PAD
	var x: float = v.x - PAD - COL_W
	var font: Font = ThemeDB.fallback_font
	for u in foes:
		if y + h > v.y - 64.0:
			break
		var r := Rect2(x, y, COL_W, h)
		var idx: int = core.all.find(u)
		var hl: Color = Color(0, 0, 0, 0)
		if u == core.current() and phase == "battle":
			hl = C_ORANGE
		elif u.cell == hover_cell and u.active():
			hl = Color(0.9, 0.2, 0.15)
		_panel(ci, r, hl, C_PANEL_HI if hover_hit == "foe:%d" % idx else C_PANEL)
		var gone: bool = u.dead or u.fled
		_text(ci, r.position + Vector2(12, 20), u.title, 15, C_DIM if gone else C_TEXT)
		var pr: float = minf(26.0, (h - 30.0) * 0.5)
		var pc: Vector2 = r.position + Vector2(14 + pr, 26 + pr)
		ci.draw_circle(pc, pr + 2.0, Color(0.05, 0.05, 0.05))
		Icons.portrait(ci, portrait_kind(u), pc, pr, gone or u.down)
		var tx: float = r.position.x + 30.0 + pr * 2.0
		if gone:
			_text(ci, Vector2(tx, r.position.y + 50), I18n.t("погиб") if u.dead else I18n.t("бежал"), 15, C_DIM)
		else:
			_cross(ci, Vector2(tx + 8, r.position.y + 37), 10.0, C_HP)
			_text(ci, Vector2(tx + 20, r.position.y + 44), "%d / %d" % [u.hp, u.max_hp], 17, C_HP)
			if h >= 70.0:
				_shield(ci, Vector2(tx + 8, r.position.y + 58), 10.0, Color(0.62, 0.64, 0.66))
				_text(ci, Vector2(tx + 20, r.position.y + 64), I18n.t("Защита %d") % int(Rules.ac(u)["total"]), 13, Color(0.8, 0.8, 0.78))
			var w: BattleWeapon = u.weapon()
			var lo: int = 0
			var hi: int = 0
			for comp in Rules.components(u, w):
				var rg: Vector2i = DiceRoller.range_of(comp["dice"]) if String(comp["dice"]) != "" else Vector2i.ZERO
				lo += maxi(0, rg.x + int(comp["F"]))
				hi += maxi(0, rg.y + int(comp["F"]))
			var wy: float = r.position.y + (82.0 if h >= 90.0 else h - 10.0)
			Icons.weapon(ci, w.icon, Rect2(Vector2(tx + 92, wy - 16), Vector2(20, 20)))
			_text(ci, Vector2(tx + 116, wy), "%d–%d" % [lo, hi], 14)
			var ix: float = tx
			for e in u.effects:
				ci.draw_rect(Rect2(ix, wy + 4.0 - (0.0 if h >= 90.0 else 14.0), 8, 8), _effect_color(e["id"]))
				ix += 10.0
			_hit(r, "foe:%d" % idx)
		y += h + 8.0


func _speech(ci: CanvasItem, v: Vector2) -> void:
	var g: Rect2 = grid_rect()
	var r := Rect2(g.position.x, v.y - 78.0, g.size.x, 66.0)
	ci.draw_rect(Rect2(r.position + Vector2(3, 4), r.size), Color(0, 0, 0, 0.4))
	ci.draw_rect(r, Color(0.07, 0.07, 0.06, 0.94))
	ci.draw_rect(r, Color(0.3, 0.3, 0.26), false, 1.5)
	var who = speech_who if speech_who != null else core.hero()
	if who != null:
		var pc: Vector2 = r.position + Vector2(36, 33)
		ci.draw_circle(pc, 28.0, Color(0.03, 0.03, 0.03))
		ci.draw_arc(pc, 27.0, 0.0, TAU, 28, ring_color(who), 2.0, true)
		Icons.portrait(ci, portrait_kind(who), pc, 25.0)
	var t: String = hover_text()
	var col: Color = C_TEXT
	if t == "":
		t = speech
		col = Color(0.85, 0.82, 0.72)
	if t == "" and me() != null:
		t = I18n.t("Клик по клетке — идти, по врагу — ударить текущим оружием. 1–3 — оружие, Enter — конец хода.")
	var lb := Rect2(r.position + Vector2(74, 8), Vector2(r.size.x - 74 - 58, r.size.y - 12))
	var font: Font = ThemeDB.fallback_font
	ci.draw_multiline_string(font, lb.position + Vector2(0, 16), t, HORIZONTAL_ALIGNMENT_LEFT, lb.size.x, 14, 3, col)
	var lr := Rect2(r.end.x - 50, r.position.y + 11, 42, 42)
	_panel(ci, lr, C_ORANGE if show_log else Color(0, 0, 0, 0), C_PANEL_HI if hover_hit == "log" else C_PANEL)
	Icons.action(ci, "log", lr.grow(-10.0), C_TEXT)
	_text(ci, lr.position + Vector2(3, 11), "L", 9, C_DIM)
	_hit(lr, "log")


func _dice(ci: CanvasItem) -> void:
	if dice_show.is_empty() or float(dice_show["t"]) >= 1.6:
		return
	var e: Dictionary = dice_show["entry"]
	var t: float = float(dice_show["t"])
	var g: Rect2 = grid_rect()
	var r := Rect2(g.get_center().x - 190, g.position.y + 10, 380, 92)
	var a: float = clampf((1.6 - t) * 2.0, 0.0, 1.0)
	ci.draw_rect(r, Color(0.07, 0.07, 0.05, 0.9 * a))
	ci.draw_rect(r, Color(0.5, 0.45, 0.3, a), false, 1.5)
	var sides: int = int(e.get("high", 20))
	var rolling: bool = t < 0.45
	var n: String = str(randi_range(1, sides)) if rolling else str(int(e["natural"]))
	var dc: Vector2 = r.position + Vector2(48, 46)
	var pts := PackedVector2Array()
	for k in 6:
		pts.append(dc + Vector2.from_angle(k * TAU / 6.0 + (t * 12.0 if rolling else 0.0) + PI / 6.0) * 34.0)
	var col: Color = Color(0.95, 0.88, 0.62)
	if not rolling and e.get("nat20", false):
		col = Color(0.5, 1.0, 0.4)
	elif not rolling and e.get("nat1", false):
		col = Color(1.0, 0.4, 0.3)
	ci.draw_colored_polygon(pts, Color(col, a))
	pts.append(pts[0])
	ci.draw_polyline(pts, Color(0, 0, 0, a), 2.0, true)
	_text(ci, dc + Vector2(-34, 9), n, 24, Color(0.08, 0.06, 0.04, a), 68, HORIZONTAL_ALIGNMENT_CENTER)
	_text(ci, r.position + Vector2(92, 30), String(e.get("label", "")), 14, Color(C_TEXT, a), 280)
	_text(ci, r.position + Vector2(92, 56), "…" if rolling else String(e.get("text", "")), 13, Color(C_TEXT, a), 280)


func _banner(ci: CanvasItem) -> void:
	if banner.is_empty():
		return
	var t: float = float(banner["t"])
	var a: float = clampf(minf(t * 5.0, (1.4 - t) * 4.0), 0.0, 1.0)
	var r := Rect2(PAD, 280.0 - (1.0 - a) * 40.0, COL_W, 170)
	ci.draw_rect(r, Color(0.28, 0.2, 0.12, a))
	for i in 9:
		ci.draw_line(Vector2(r.position.x, r.position.y + 10 + i * 18), Vector2(r.end.x, r.position.y + 10 + i * 18), Color(0.18, 0.12, 0.07, a), 2.0)
	ci.draw_rect(r, Color(0.1, 0.07, 0.04, a), false, 3.0)
	var lines: PackedStringArray = String(banner["text"]).split("\n")
	for i in lines.size():
		_text(ci, Vector2(r.position.x, r.position.y + 72 + i * 44), lines[i], 34, Color(0.95, 0.88, 0.7, a), COL_W, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_end(ci: CanvasItem) -> void:
	var v: Vector2 = vp()
	ci.draw_rect(Rect2(Vector2.ZERO, v), Color(0, 0, 0, 0.55))
	var r := Rect2((v - Vector2(560, 400)) / 2.0, Vector2(560, 400))
	_panel(ci, r, Color(0, 0, 0, 0), Color(0.09, 0.09, 0.07))
	var o: String = core.outcome
	var green: Color = Color(0.1, 0.55, 0.15) if o == "win" else (Color(0.55, 0.12, 0.1) if o == "lose" else Color(0.45, 0.4, 0.15))
	for bx in [r.position.x + 12, r.end.x - 52]:
		var b := Rect2(bx, r.position.y + 8, 40, r.size.y - 60)
		ci.draw_rect(b, green)
		ci.draw_colored_polygon(PackedVector2Array([b.position + Vector2(0, b.size.y), b.end, b.position + Vector2(20, b.size.y + 22)]), green)
		var cc: Vector2 = b.position + Vector2(20, b.size.y - 30)
		ci.draw_line(cc + Vector2(-10, -10), cc + Vector2(10, 10), Color(0.6, 0.95, 0.5), 2.5)
		ci.draw_line(cc + Vector2(10, -10), cc + Vector2(-10, 10), Color(0.6, 0.95, 0.5), 2.5)
	var hb := Rect2(r.position.x + 60, r.position.y + 14, r.size.x - 120, 40)
	ci.draw_rect(hb, green.darkened(0.3))
	_text(ci, hb.position + Vector2(0, 29), {"win": I18n.t("Победа"), "flee": I18n.t("Отступление"), "lose": I18n.t("Поражение")}.get(o, ""), 22, C_TEXT, hb.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	_text(ci, Vector2(r.position.x + 60, r.position.y + 84), I18n.t("Результаты боя:"), 16, C_TEXT, r.size.x - 120, HORIZONTAL_ALIGNMENT_CENTER)
	ci.draw_line(Vector2(r.position.x + 70, r.position.y + 94), Vector2(r.end.x - 70, r.position.y + 94), Color(0.5, 0.5, 0.42), 1.5)
	# плитки: убитые по видам, добыча, время
	var tiles: Array = []
	var kinds: Dictionary = {}
	for u in core.all:
		if u.team == 1 and u.dead:
			var k: String = portrait_kind(u)
			kinds[k] = int(kinds.get(k, 0)) + 1
	for k in kinds:
		tiles.append({"kind": "portrait", "id": k, "n": kinds[k]})
	if int(core.loot.get("money", 0)) > 0:
		tiles.append({"kind": "coin", "n": int(core.loot["money"])})
	if int(core.loot.get("items", {}).get("scrap", 0)) > 0:
		tiles.append({"kind": "scrap", "n": int(core.loot["items"]["scrap"])})
	if int(core.loot.get("items", {}).get("hide", 0)) > 0:
		tiles.append({"kind": "pelt", "n": int(core.loot["items"]["hide"])})
	tiles.append({"kind": "time", "n": core.round_n})
	var tx: float = r.get_center().x - tiles.size() * 36.0
	for t in tiles:
		var tr := Rect2(tx, r.position.y + 106, 64, 64)
		ci.draw_rect(tr, Color(0.72, 0.62, 0.42))
		ci.draw_rect(tr, Color(0, 0, 0, 0.8), false, 1.5)
		match t["kind"]:
			"portrait":
				Icons.portrait(ci, t["id"], tr.get_center(), 26.0)
			"coin":
				ci.draw_circle(tr.get_center(), 20.0, Color(0.85, 0.68, 0.2))
				ci.draw_circle(tr.get_center(), 15.0, Color(0.95, 0.8, 0.35))
			"time":
				Icons.action(ci, "ready", tr.grow(-14.0), Color(0.2, 0.15, 0.1))
			"scrap":
				# Металлолом: гнутая пластина с заклёпками
				var c: Vector2 = tr.get_center()
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-18, -6), c + Vector2(8, -16), c + Vector2(18, 4), c + Vector2(-4, 16)]), Color(0.45, 0.42, 0.38))
				ci.draw_polyline(PackedVector2Array([c + Vector2(-18, -6), c + Vector2(8, -16), c + Vector2(18, 4), c + Vector2(-4, 16), c + Vector2(-18, -6)]), Color(0.15, 0.12, 0.1), 2.0)
				for k in 3:
					ci.draw_circle(c + Vector2(-8 + k * 8, -4 + k * 4), 2.2, Color(0.7, 0.45, 0.25))
			"pelt":
				# Шкура: растянутая кожа с лапами
				var c: Vector2 = tr.get_center()
				var pelt := PackedVector2Array([c + Vector2(-10, -18), c + Vector2(-20, -14), c + Vector2(-14, -4), c + Vector2(-20, 10), c + Vector2(-10, 8),
					c + Vector2(-6, 18), c + Vector2(6, 18), c + Vector2(10, 8), c + Vector2(20, 10), c + Vector2(14, -4), c + Vector2(20, -14), c + Vector2(10, -18)])
				ci.draw_colored_polygon(pelt, Color(0.55, 0.38, 0.22))
				pelt.append(pelt[0])
				ci.draw_polyline(pelt, Color(0.15, 0.1, 0.06), 2.0)
		_text(ci, tr.end - Vector2(24, 4), str(t["n"]), 13, Color.WHITE, 22, HORIZONTAL_ALIGNMENT_RIGHT)
		tx += 72.0
	var lines: Array = []
	lines.append(I18n.t("Раундов: %d (%.1f мин игрового времени). Убито врагов: %d.") % [core.round_n, core.result()["game_minutes"], core.killed])
	for u in core.all:
		if u.team != 0 or u.is_pet and not u.dead:
			continue
		if u.dead:
			lines.append(I18n.t("%s погиб.") % u.title)
		elif not u.new_traumas.is_empty():
			lines.append(I18n.t("%s: травмы — %s.") % [u.title, ", ".join(PackedStringArray(u.new_traumas.map(func(x): return _cond_name(x).to_lower())))])
		elif u.down:
			lines.append(I18n.t("%s без сознания.") % u.title)
	var font: Font = ThemeDB.fallback_font
	ci.draw_multiline_string(font, Vector2(r.position.x + 70, r.position.y + 200), "\n".join(PackedStringArray(lines)), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 140, 14, 6, C_TEXT)
	var br := Rect2(r.get_center().x - 80, r.end.y - 62, 160, 44)
	_panel(ci, br, C_ORANGE if hover_hit == "finish" else Color(0.85, 0.82, 0.6), Color(0.62, 0.66, 0.36))
	_text(ci, br.position + Vector2(0, 29), I18n.t("Завершить"), 17, Color(0.1, 0.08, 0.04), br.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	_hit(br, "finish")


func _draw_prep(ci: CanvasItem) -> void:
	var v: Vector2 = vp()
	var r := Rect2((v - Vector2(820, 560)) / 2.0, Vector2(820, 560))
	_panel(ci, r, Color(0, 0, 0, 0), Color(0.09, 0.1, 0.075))
	var hb := Rect2(r.position.x + 40, r.position.y + 14, r.size.x - 80, 40)
	ci.draw_rect(hb, Color(0.2, 0.3, 0.14))
	_text(ci, hb.position + Vector2(0, 29), I18n.t("Подготовка к бою"), 22, C_TEXT, hb.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	var foes: Array = core.all.filter(func(u): return u.team == 1)
	var friends: Array = core.all.filter(func(u): return u.team == 0 and not u.is_hero)
	_text(ci, r.position + Vector2(40, 84), I18n.t("Противник: %s — %s.") % [core._group_title(), ", ".join(PackedStringArray(foes.map(func(u): return u.title)))], 14, C_TEXT, r.size.x - 80)
	if not friends.is_empty():
		_text(ci, r.position + Vector2(40, 106), I18n.t("С вами: ") + ", ".join(PackedStringArray(friends.map(func(u): return u.title))) + ".", 14, C_DIM, r.size.x - 80)
	_text(ci, r.position + Vector2(40, 140), I18n.t("Возьмите в бой до %d видов оружия из сумки (1–9 — выбрать, Enter — в бой):") % core.cfg.loadout_max, 15, C_TEXT, r.size.x - 80)
	var gx: float = r.position.x + 40.0
	var gy: float = r.position.y + 158.0
	if prep_list.is_empty():
		_text(ci, Vector2(gx, gy + 60), I18n.t("В сумке нет оружия — герой дерётся кулаками."), 17, C_ORANGE, r.size.x - 80, HORIZONTAL_ALIGNMENT_CENTER)
	var cw: float = (r.size.x - 80.0 - 2 * 10.0) / 3.0
	var font: Font = ThemeDB.fallback_font
	for i in prep_list.size():
		var e: Dictionary = prep_list[i]
		var w: BattleWeapon = e["weapon"]
		var cr := Rect2(gx + (i % 3) * (cw + 10.0), gy + floorf(i / 3.0) * 98.0, cw, 88)
		if cr.end.y > r.end.y - 80.0:
			break
		var si: int = prep_sel.find(e["item"])
		var full: bool = prep_sel.size() >= core.cfg.loadout_max and si < 0
		_panel(ci, cr, C_ORANGE if si >= 0 else Color(0, 0, 0, 0), C_PANEL_HI if hover_hit == "prep:" + e["item"] else C_PANEL)
		var ib := Rect2(cr.position + Vector2(10, 9), Vector2(64, 64))
		ci.draw_rect(ib, Color(0.74, 0.8, 0.82) if not full else Color(0.45, 0.47, 0.48))
		ci.draw_rect(ib, Color(0, 0, 0, 0.8), false, 1.0)
		Icons.weapon(ci, w.icon, ib.grow(-6.0), full)
		var dmg: String = " + ".join(PackedStringArray(w.damage.map(func(d): return (String(d.get("dice", "")) if String(d.get("dice", "")) != "" else str(int(d.get("bonus", 0)))) + " " + Rules.DAMAGE_NAMES.get(String(d.get("type", "")), ""))))
		_text(ci, cr.position + Vector2(84, 24), "%s%s" % [w.title, " ×%d" % e["count"] if int(e["count"]) > 1 else ""], 15, C_TEXT if not full else C_DIM, cw - 92)
		ci.draw_multiline_string(font, cr.position + Vector2(84, 43), dmg, HORIZONTAL_ALIGNMENT_LEFT, cw - 92, 12, 2, C_DIM)
		_text(ci, cr.position + Vector2(84, 76), I18n.t("дальнобойное %d/%d кл.") % [w.range_ft / 5, w.long_range_ft / 5] if w.ranged else I18n.t("ближний бой"), 11, Color(0.75, 0.7, 0.5), cw - 92)
		if si >= 0:
			ci.draw_circle(cr.position + Vector2(cr.size.x - 16, 16), 11.0, C_ORANGE)
			_text(ci, cr.position + Vector2(cr.size.x - 27, 21), str(si + 1), 13, Color(0.1, 0.07, 0.03), 22, HORIZONTAL_ALIGNMENT_CENTER)
		_text(ci, cr.position + Vector2(4, 80), str(i + 1), 10, C_DIM)
		_hit(cr, "prep:" + e["item"])
	var br := Rect2(r.get_center().x - 90, r.end.y - 62, 180, 46)
	_panel(ci, br, C_ORANGE if hover_hit == "prep_go" else Color(0.85, 0.82, 0.6), Color(0.62, 0.66, 0.36))
	_text(ci, br.position + Vector2(0, 30), I18n.t("В бой"), 18, Color(0.1, 0.08, 0.04), br.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	_hit(br, "prep_go")
	var chosen: String = ", ".join(PackedStringArray(prep_sel.map(func(it): return _item_title(it)))) if not prep_sel.is_empty() else I18n.t("кулаки")
	_text(ci, Vector2(r.position.x + 40, r.end.y - 76), I18n.t("В руках будет: ") + chosen, 13, C_DIM, r.size.x - 80, HORIZONTAL_ALIGNMENT_CENTER)


func _item_title(it: String) -> String:
	for e in prep_list:
		if e["item"] == it:
			return e["weapon"].title.to_lower()
	return it


func _button_text(id: String, c) -> String:
	if id == "move":
		return I18n.t("Движение (M): зелёные клетки — куда дойти. Осталось %d кл.") % (c.move_left / 5) if c != null else I18n.t("Движение")
	if id.begins_with("weapon:"):
		var u = c if c != null else core.hero()
		var i: int = int(id.substr(7))
		if u == null or i >= u.weapons.size():
			return ""
		var w: BattleWeapon = u.weapons[i]
		var t: String = I18n.t("%s (%d): атака действием, бросок +%d. ") % [w.title, i + 1, int(Rules.attack_terms(u, w)["sum"])]
		t += I18n.t("Взять в руки — свободное взаимодействие, раз в ход.") if i != u.wi else I18n.t("Сейчас в руках; клик по врагу — удар.")
		return t
	if id.begins_with("ab:"):
		var ab: BattleAbility = Data.ability(id.substr(3))
		return "%s: %s, %s." % [ab.title, {"action": I18n.t("действие"), "bonus": I18n.t("бонусное действие"), "reaction": I18n.t("реакция")}.get(ab.cost, ab.cost),
			(I18n.t("осталось %d") % (ab.uses_per_battle - int(c.uses.get(ab.id, 0))) if c != null and ab.uses_per_battle > 0 else I18n.t("без ограничений"))]
	for a in ACTIONS:
		if id == "act:" + a[0]:
			return "%s (%s). %s" % [a[1], a[2], {"dash": I18n.t("Действие: ещё столько же движения."), "disengage": I18n.t("Действие: уйти без атак по возможности."),
				"dodge": I18n.t("Действие: по вам атаки с помехой до вашего хода."), "help": I18n.t("Действие: поднять союзника без сознания или дать преимущество против врага рядом."),
				"hide": I18n.t("Действие: скрытность против внимательности врагов; нужно укрытие ¾."), "potion": I18n.t("Действие: целебное зелье себе или соседу."),
				"ready": I18n.t("Действие: ударить первого врага, вошедшего в досягаемость."), "flee": I18n.t("Действие: уйти с поля, стоя на краю.")}.get(a[0], "")]
	if id == "end":
		return I18n.t("Конец хода (Enter).")
	if id == "companions":
		return I18n.t("Спутники и питомцы ходят сами или под вашим управлением (C).")
	if id == "log":
		return I18n.t("Журнал боя (L): все броски и формулы.")
	return ""


static var ARENA_NAMES: Dictionary = {"coast": I18n.t("побережье"), "forest": I18n.t("лес"), "wasteland": I18n.t("пустошь"), "swamp": I18n.t("болото"),
	"mountains": I18n.t("горы"), "hot": I18n.t("раскалённые горы"), "rad_forest": I18n.t("проклятый лес"), "rad_wasteland": I18n.t("проклятая пустошь"),
	"rad_swamp": I18n.t("проклятое болото")}


func _cond_name(id: String) -> String:
	var d: Dictionary = Actor.R.condition(id)
	return String(d.get("name_ru", id))

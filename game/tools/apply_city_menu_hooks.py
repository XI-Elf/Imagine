# Хуки экрана города (city/city_menu.gd) в city/city_world.gd. Повторно накладываются на новую версию файла.
# Запуск: python3 apply_city_menu_hooks.py <game/city/city_world.gd> — дописывает хуки в новую версию файла
import sys
p = sys.argv[1]
s = open(p).read()
def rep(a, b):
	global s
	assert s.count(a) == 1, ("нет или не один раз", a[:80], s.count(a))
	s = s.replace(a, b)

rep('''const Growth := preload("res://city/city_growth.gd")
''', '''const Growth := preload("res://city/city_growth.gd")
const CityMenu := preload("res://city/city_menu.gd")
## Экран города (city_menu.gd, видео Huzzah 2026-10-23): вход через ворота открывает меню услуг,
## пешая карта — по кнопке «Пройтись по городу», Esc на улице — назад в меню
## (меню — при входе с общей карты; отдельный запуск сцены без "settlement" в ctx — сразу на улице)
var menu: CanvasLayer
var walking: bool = true               # false — открыт экран города
var _gate_in: String = ""              # ворота, через которые вошёл (ими же уходит из меню)
''')
# Узлы: меню
rep('''	window = HeroWindowScript.new()
	window.setup(func() -> Actor: return hero, func() -> Dictionary: return bag)
	add_child(window)
''', '''	window = HeroWindowScript.new()
	window.setup(func() -> Actor: return hero, func() -> Dictionary: return bag)
	add_child(window)
	menu = CityMenu.new()
	menu.setup(self)
	add_child(menu)
''')
# Вход: ворота -> меню; пролез или пойман -> на улице
rep('''	_hero_bld = map.building_at(hero_pos)
	_reveal()
	_fit_camera_limits()
''', '''	_gate_in = String(gate.get("id", ""))
	var saved_walk: bool = live and bool(c["state"].get("walking", true))
	if (live and not saved_walk) or (not live and entry == "gate" and bool(c.get("menu", c.has("settlement")))):
		open_menu()
	else:
		walking = true
		menu.close()
	_hero_bld = map.building_at(hero_pos)
	_reveal()
	_fit_camera_limits()
''')
rep('''	if window != null and window.visible:
		return true
	return _panel.visible and _panel_kind != "note"
''', '''	if window != null and window.visible:
		return true
	if not walking:
		return true
	return _panel.visible and _panel_kind != "note"
''')
# В меню житель доступен в свои часы, искать его на улице не нужно
rep('''func _npc_on_duty_here(n: Dictionary) -> bool:
''', '''func _npc_on_duty_here(n: Dictionary) -> bool:
	if not walking:
		return _on_duty(n["def"], clock.hour_of_day()) and not n["actor"].sleeping
''')
# Esc: на улице — в меню
rep('''			if not _panel.visible and not _map_view:
				return   # меню паузы игры (Worlds)
''', '''			if not _panel.visible and not _map_view:
				if walking and not is_intruder():
					open_menu()
					get_viewport().set_input_as_handled()
				return   # в меню города — меню паузы игры (Worlds)
''')
rep('''		KEY_E:
			if _panel.visible:
				_close_panel()
			else:
				interact()
''', '''		KEY_E:
			if _panel.visible:
				_close_panel()
			elif walking:
				interact()
''')
rep('''		KEY_M:
			toggle_map()
''', '''		KEY_M:
			if walking:
				toggle_map()
''')
# Окно разговора поверх меню — по центру
rep('''	_panel.position = Vector2(vp.x - _panel.size.x - 20.0, 60.0)
''', '''	_panel.position = Vector2(vp.x - _panel.size.x - 20.0, 60.0) if walking else (vp - _panel.size) * 0.5
''')
# HUD: в меню своё, сверху и подсказки не нужны
rep('''	_event.text = event_text if event_timer > 0.0 else ""
''', '''	_top.visible = walking
	_hint.visible = walking
	if walking and not is_intruder():
		_hint.text += " · Esc город"
	_event.text = event_text if event_timer > 0.0 else ""
''')
rep('''		"intruder_until": intruder_until, "left": leaving, "growth": growth.duplicate(true),
''', '''		"intruder_until": intruder_until, "left": leaving, "growth": growth.duplicate(true), "walking": walking,
''')
# Функции меню
rep('''# =====================================================================
# СОХРАНЕНИЕ
''', '''# =====================================================================
# ЭКРАН ГОРОДА (city_menu.gd)
# =====================================================================
func open_menu() -> void:
	walking = false
	route.cancel()
	if _map_view:
		toggle_map()
	_close_panel()
	event_timer = 0.0
	menu.open()


## «Пройтись по городу»: прежняя пешая карта, герой у ворот (или где был)
func walk_city() -> void:
	walking = true
	_close_panel()
	menu.close()
	cam.position = hero_pos * PX
	cam.reset_smoothing()
	_say("%s: вы идёте по улицам. Esc — назад к экрану города" % display_name)


## «Поговорить»: жители без своего дела
func menu_people(list: Array) -> void:
	var opts: Array = []
	for n in list:
		var a: Actor = n["actor"]
		opts.append(["%s%s" % [a.display_name, " (спит)" if a.sleeping else ""], func(): talk(n)])
	opts.append(["Назад", _close_panel])
	_open_panel("talk", "Поговорить", "" if not list.is_empty() else "Больше никого нет.", opts)


## «Покинуть город»: через те же ворота; ночью заперто — привратник выпустит за плату
func menu_leave() -> void:
	var g: String = _gate_in if _gate_in != "" else String(def.get("gates", [{}])[0].get("id", ""))
	if not map.closed_gates.has(g):
		_leave(g)
		return
	for n in npcs:
		if String(n["def"].get("gate", "")) == g and not n["actor"].sleeping:
			talk(n)
			_panel_text.text = "Ворота заперты до %d:00. %s" % [int(rules.get("gates_open_h", 6.0)), _panel_text.text]
			return
	_open_note(String(_gate_def(g).get("name", "Ворота")), "Ворота заперты до %d:00, привратника нет. Переночуйте в городе." % int(rules.get("gates_open_h", 6.0)))


# =====================================================================
# СОХРАНЕНИЕ
''')
open(p, 'w').write(s)
print("ok")

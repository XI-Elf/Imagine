# Гачки екрана міста (city/city_menu.gd) у city/city_world.gd. Повторно накладаються на нову версію файлу.
# Запуск: python3 apply_city_menu_hooks.py <game/city/city_world.gd> — дописує гачки в нову версію файлу
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
## Екран міста (city_menu.gd, відео Huzzah 2026-10-23): вхід через браму відкриває меню послуг,
## піша карта — за кнопкою «Пройтися містом», Esc на вулиці — назад у меню
## (меню — під час входу з загальної карти; окремий запуск сцени без "settlement" у ctx — одразу на вулиці)
var menu: CanvasLayer
var walking: bool = true               # false — відкритий екран міста
var _gate_in: String = ""              # брама, через яку ввійшов (нею ж іде з меню)
''')
# Вузли: меню
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
# Вхід: брама -> меню; проліз або спійманий -> на вулиці
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
# У меню мешканець доступний у свої години, шукати його на вулиці не треба
rep('''func _npc_on_duty_here(n: Dictionary) -> bool:
''', '''func _npc_on_duty_here(n: Dictionary) -> bool:
	if not walking:
		return _on_duty(n["def"], clock.hour_of_day()) and not n["actor"].sleeping
''')
# Esc: на вулиці — у меню
rep('''			if not _panel.visible and not _map_view:
				return   # меню паузи гри (Worlds)
''', '''			if not _panel.visible and not _map_view:
				if walking and not is_intruder():
					open_menu()
					get_viewport().set_input_as_handled()
				return   # у меню міста — меню паузи гри (Worlds)
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
# Вікно розмови поверх меню — по центру
rep('''	_panel.position = Vector2(vp.x - _panel.size.x - 20.0, 60.0)
''', '''	_panel.position = Vector2(vp.x - _panel.size.x - 20.0, 60.0) if walking else (vp - _panel.size) * 0.5
''')
# HUD: у меню своє, згори й підказки не потрібні
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
# Функції меню
rep('''# =====================================================================
# ЗБЕРЕЖЕННЯ
''', '''# =====================================================================
# ЕКРАН МІСТА (city_menu.gd)
# =====================================================================
func open_menu() -> void:
	walking = false
	route.cancel()
	if _map_view:
		toggle_map()
	_close_panel()
	event_timer = 0.0
	menu.open()


## «Пройтися містом»: колишня піша карта, герой біля брами (або де був)
func walk_city() -> void:
	walking = true
	_close_panel()
	menu.close()
	cam.position = hero_pos * PX
	cam.reset_smoothing()
	_say("%s: вы идёте по улицам. Esc — назад к экрану города" % display_name)


## «Поговорити»: мешканці без своєї справи
func menu_people(list: Array) -> void:
	var opts: Array = []
	for n in list:
		var a: Actor = n["actor"]
		opts.append(["%s%s" % [a.display_name, " (спит)" if a.sleeping else ""], func(): talk(n)])
	opts.append(["Назад", _close_panel])
	_open_panel("talk", "Поговорить", "" if not list.is_empty() else "Больше никого нет.", opts)


## «Покинути місто»: через ту саму браму; уночі замкнено — брамник випустить за плату
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
# ЗБЕРЕЖЕННЯ
''')
open(p, 'w').write(s)
print("ok")

extends SceneTree
## Сумісність збережень (злиття 2D 12): файл, записаний справжньою грою 2D 11 (tests/fixtures/save_2d11.dat:
## герой «Сумісний» у Ешвіку, взяті доручення шкіряника, ніж), відкривається новою збіркою без втрат.
## Кампанія в такому файлі відсутня — має початися з першого розділу; після запису й повторного читання прогрес кампанії зберігається.
## Також: перегляд списку збережень не видаляє файли іншої версії (пункт аудиту 2D 10).
## godot --path game --rendering-driver opengl3 -s res://tests/save_compat_checks.gd

const WorldSave := preload("res://world_save.gd")
const Trade := preload("res://city/trade.gd")
const StoryCampaign := preload("res://story/campaign.gd")
const FIXTURE := "res://tests/fixtures/save_2d11.dat"
const SLOT := "compat_2d11"
var fails: int = 0
var checks: int = 0


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
	print("ok: " if cond else "FAIL: ", what)


func frames(n: int) -> void:
	for i in n:
		await process_frame


func _initialize() -> void:
	_run()


func wait_worlds(W: Node) -> void:
	await frames(2)
	while W.busy:
		await process_frame
	await frames(2)


func load_game(slot: String) -> Node2D:
	Engine.set_meta("aw_intro_done", true)
	Engine.set_meta("aw_load", slot)
	var game: Node2D = load("res://game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	var t0: int = Time.get_ticks_msec()
	while not game.ready_done and Time.get_ticks_msec() - t0 < 120000:
		await process_frame
	await frames(5)
	return game


func _run() -> void:
	var W: Node = root.get_node("Worlds")
	if not FileAccess.file_exists(FIXTURE):
		print("SAVE COMPAT CHECKS: фікстури немає (запуск із .pck) — пропущено")
		quit(0)
		return
	DirAccess.make_dir_recursive_absolute(WorldSave.DIR)
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(FIXTURE)
	var f := FileAccess.open(WorldSave.path_of(SLOT), FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	# Чужий файл іншої версії: список його не показує, але й не видаляє
	var alien: String = WorldSave.DIR + "alien_v5.dat"
	var fa := FileAccess.open(alien, FileAccess.WRITE)
	fa.store_var({"header": true, "version": 5}, false)
	fa.store_var({"version": 5}, false)
	fa.close()
	var slots: Array = []
	for e in WorldSave.list():
		slots.append(String(e.get("slot", "")))
	ok(slots.has(SLOT), "збереження 2D 11 є у списку")
	ok(not slots.has("alien_v5") and FileAccess.file_exists(alien), "файл іншої версії прихований, але не видалений")
	DirAccess.remove_absolute(alien)

	var d: Dictionary = WorldSave.read(SLOT)
	ok(not d.is_empty() and not d.get("worlds", {}).has("campaign"), "файл 2D 11 читається; ключа кампанії в ньому немає")

	var game: Node2D = await load_game(SLOT)
	await wait_worlds(W)
	ok(game.ready_done and not game.cast.hero.is_empty(), "світ і герой завантажені")
	ok(game.cast.hero["actor"].display_name == "Сумісний", "ім'я героя збережене")
	ok(W.current_kind() == "city" and W.current_node() != null and W.current_node().city_id == "s001", "після завантаження — у Ешвіку")
	ok(Trade.count(W.inventory, "knife") == 1 and Trade.count(W.inventory, "water_flask") == 2, "сумка з 2D 11 на місці")
	# Вхід у Ешвік під час завантаження сам зараховує мету першого розділу («прибути до Ешвіка»)
	ok(int(W.campaign_state.get("version", 0)) == 1 and int(W.campaign_state.get("chapter", -1)) == 0 and W.campaign_state.get("completed", [1]).is_empty() and W.campaign_state.get("history", [1]).is_empty(),
		"кампанія для старого збереження починається з першого розділу")

	# Прогрес кампанії переживає запис і повторне читання
	ok(W.campaign_event("city_enter", "s001"), "подія кампанії «прибути до Ешвіка» зарахована")
	var ch_before: int = int(W.campaign_state.get("chapter", 0))
	var waiting: bool = bool(W.campaign_state.get("awaiting_choice", false))
	ok(WorldSave.write(game, true), "запис у новому форматі")
	var slot2: String = WorldSave.latest_slot()
	game.queue_free()
	await frames(5)
	game = await load_game(slot2)
	await wait_worlds(W)
	ok(int(W.campaign_state.get("chapter", -1)) == ch_before and bool(W.campaign_state.get("awaiting_choice", false)) == waiting and int(W.campaign_state.get("version", 0)) == 1,
		"стан кампанії відновлено (розділ %d, очікує вибору: %s)" % [ch_before, waiting])
	WorldSave.delete(slot2)
	WorldSave.delete(SLOT)
	print("SAVE COMPAT CHECKS: %d/%d" % [checks - fails, checks])
	quit(1 if fails > 0 else 0)

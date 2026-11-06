extends SceneTree
## Сумісність збережень (злиття 2D 12): файл, записаний справжньою грою 2D 11 (tests/fixtures/save_2d11.dat:
## герой «Сумісний» у Ешвіку, взяті доручення шкіряника, ніж), відкривається новою збіркою без втрат.
## Кампанію 2D 12 вирізано (modules_cut/quests_2d12): файл 2D 12 з ключем «campaign», сюжетною річчю в сумці
## й боєм із сюжетним босом відкривається без помилок; ключ кампанії переноситься в нове збереження без змін.
## Також: перегляд списку збережень не видаляє файли іншої версії (пункт аудиту 2D 10).
## godot --path game --rendering-driver opengl3 -s res://tests/save_compat_checks.gd

const WorldSave := preload("res://world_save.gd")
const Trade := preload("res://city/trade.gd")
const FIXTURE := "res://tests/fixtures/save_2d11.dat"
const SLOT := "compat_2d11"
const SLOT12 := "compat_2d12_campaign"
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
	ok(W.get("campaign_state") == null and not W.has_method("campaign_event"), "кампанії в грі немає (модуль вирізано)")
	ok(not WorldSave.read(SLOT).is_empty(), "файл 2D 11 і далі читається")

	# Файл 2D 12 з кампанією: той самий світ + ключ «campaign», сюжетна річ у сумці, збережений бій із босом
	var hdr: Dictionary = {}
	var fr := FileAccess.open(WorldSave.path_of(SLOT), FileAccess.READ)
	var first: Variant = fr.get_var(false)
	fr.close()
	if first is Dictionary and first.has("header"):
		hdr = first.duplicate(true)
	var d12: Dictionary = d.duplicate(true)
	var campaign: Dictionary = {"version": 1, "chapter": 2, "progress": 1, "awaiting_choice": true, "completed": ["arrival", "amber_trace"], "flags": {"told_guard": true}, "effects": {}, "history": []}
	d12["worlds"]["campaign"] = campaign
	d12["worlds"]["inventory"]["items"]["beacon_lens"] = 1
	var stack: Array = d12["worlds"].get("stack", [])
	stack.append({"kind": "battle", "req": {"origin": "story_boss:boss_warden", "enemies_dicts": [], "allies_ids": []}, "state": {}})
	d12["worlds"]["stack"] = stack
	var fw := FileAccess.open(WorldSave.path_of(SLOT12), FileAccess.WRITE)
	if not hdr.is_empty():
		fw.store_var(hdr, false)
	fw.store_var(d12, false)
	fw.close()
	game.queue_free()
	await frames(5)
	game = await load_game(SLOT12)
	await wait_worlds(W)
	ok(game.ready_done and not game.cast.hero.is_empty(), "збереження 2D 12 з кампанією завантажилося")
	ok(W.current_kind() != "battle", "бій із вирізаним сюжетним босом не відновлюється")
	ok(Trade.count(W.inventory, "beacon_lens") == 0 and Trade.count(W.inventory, "knife") == 1, "сюжетна річ прибрана з сумки, решта на місці")
	ok(WorldSave.write(game, true), "запис після завантаження")
	var slot2: String = WorldSave.latest_slot()
	var back: Dictionary = WorldSave.read(slot2)
	ok(back.get("worlds", {}).get("campaign", {}) == campaign, "ключ кампанії перенесено в нове збереження без змін")
	game.queue_free()
	await frames(5)
	WorldSave.delete(slot2)
	WorldSave.delete(SLOT12)
	WorldSave.delete(SLOT)
	print("SAVE COMPAT CHECKS: %d/%d" % [checks - fails, checks])
	quit(1 if fails > 0 else 0)

extends SceneTree
## Дві мови (питання Q26): український переклад повний, підстановки %s/%d збігаються з російськими,
## перемикання мови пишеться в user://settings.cfg, дані з JSON перекладаються під час читання.
## godot --path game --headless -s res://tests/i18n_checks.gd

const PH := "%[-+ 0-9.]*[sdf%]"

var fails: int = 0
var checks: int = 0


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("FAIL: ", what)
	else:
		print("ok: ", what)


func _placeholders(s: String) -> Array:
	var rx := RegEx.create_from_string(PH)
	return rx.search_all(s).map(func(m): return m.get_string())


func _initialize() -> void:
	var tr: Translation = load("res://i18n/uk.po") as Translation
	ok(tr != null and tr.locale == "uk", "uk.po загружен как перевод, язык uk")
	if tr == null:
		quit(1)
		return
	var ids: PackedStringArray = tr.get_message_list()
	var empty: Array = []
	var bad: Array = []
	for id in ids:
		if id == "":
			continue
		var u: String = String(tr.get_message(id))
		if u == "":
			empty.append(id)
		elif _placeholders(id) != _placeholders(u) or id.count("\n") != u.count("\n"):
			bad.append(id)
	ok(ids.size() > 1500, "строк в переводе: %d" % ids.size())
	ok(empty.is_empty(), "все строки переведены, пустых: %d %s" % [empty.size(), str(empty.slice(0, 3))])
	ok(bad.is_empty(), "подстановки и переносы строк совпадают: %d %s" % [bad.size(), str(bad.slice(0, 3))])
	# Формат с подстановками не падает на украинском
	var f: String = String(tr.get_message("%s бьёт %s%s: %s, %d урона. У %s осталось %d здоровья.")) % ["A", "B", "", "попадание", 3, "B", 4]
	ok(f.begins_with("A б'є B"), "формат с подстановками: %s" % f)

	# Вибір мови: зберігається й читається, невідомий код і відсутній вибір — українська (Q38)
	var cf := ConfigFile.new()
	var had: bool = cf.load(I18n.SETTINGS) == OK
	var was: String = String(cf.get_value("game", "language", I18n.DEFAULT)) if had else I18n.DEFAULT
	ok(I18n.choose("uk") == (was != "uk"), "выбор uk записан (смена: %s)" % str(was != "uk"))
	ok(I18n.saved() == "uk", "сохранённый язык — uk")
	I18n.apply_saved()
	var want: String = OS.get_environment("AMBER_TEST_LANG") if OS.get_environment("AMBER_TEST_LANG") == "uk" else "ru"
	ok(I18n.current() == want, "в тестах язык %s, хоть в настройках uk (AMBER_TEST_LANG)" % want)
	I18n.choose("xx")
	ok(I18n.saved() == "uk" and I18n.DEFAULT == "uk", "неизвестный язык и язык по умолчанию — украинский (Q38)")
	I18n.choose(was)
	I18n.apply_saved()

	# Переклад рядка й даних українською, російською — без змін
	TranslationServer.set_locale("uk")
	I18n._locale = "uk"
	ok(I18n.t("Новая игра") == "Нова гра", "I18n.t на украинском: %s" % I18n.t("Новая игра"))
	ok(I18n.t("строки нет в переводе") == "строки нет в переводе", "нет перевода — русская строка")
	var d: Variant = I18n.tree({"id": "knife", "name": "Нож", "list": ["Хлеб", 5], "Нож": "Нож"})
	ok(d["id"] == "knife" and d["name"] == "Ніж" and d["list"][0] == "Хліб" and d["list"][1] == 5 and d.has("Нож"),
		"I18n.tree переводит значения, ключи и числа не трогает: %s" % str(d))
	TranslationServer.set_locale("ru")
	I18n._locale = "ru"
	ok(I18n.t("Новая игра") == "Новая игра", "на русском строка не меняется")

	print("i18n_checks: %d/%d" % [checks - fails, checks])
	quit(1 if fails > 0 else 0)

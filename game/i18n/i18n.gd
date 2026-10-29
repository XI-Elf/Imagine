class_name I18n
extends Node
## Мова гри (питання Q26): російська (вихідна, рядки коду й даних — ключі) та українська (i18n/uk.po).
## Вибір зберігається в user://settings.cfg і діє із запуску: тексти в static var збираються під час завантаження скриптів,
## тому зміна мови в меню перезапускає гру. Автозавантаження LangBoot стоїть першим і ставить мову до решти.
## Рядки поповнює й перевіряє tools/i18n.py (wrap / extract / check).

const SETTINGS := "user://settings.cfg"
const LANGS: Array = [["ru", "Русский"], ["uk", "Українська"]]
## Мова за замовчуванням — українська (питання Q38, Huzzah 2026-10-28: «Украинский язык приоритетный»).
## Російська лишається вихідною мовою рядків і вмикається кнопкою «Мова».
const DEFAULT := "uk"

static var _locale: String = ""


func _init() -> void:
	apply_saved()


static func saved() -> String:
	var cf := ConfigFile.new()
	var code: String = DEFAULT
	if cf.load(SETTINGS) == OK:
		code = String(cf.get_value("game", "language", DEFAULT))
	return code if LANGS.any(func(l): return l[0] == code) else DEFAULT


static func apply_saved() -> void:
	var test: String = test_lang()
	_locale = test if test != "" else saved()
	TranslationServer.set_locale(_locale)


## Тести (godot -s res://tests/...) звіряють російські тексти, тому йдуть російською, хоч би що обрав гравець.
## Прогнати їх українською: AMBER_TEST_LANG=uk. Поза тестами — порожній рядок.
static func test_lang() -> String:
	if not Array(OS.get_cmdline_args()).any(func(a): return String(a).begins_with("res://tests/")):
		return ""
	var code: String = OS.get_environment("AMBER_TEST_LANG")
	return code if LANGS.any(func(l): return l[0] == code) else "ru"


static func current() -> String:
	if _locale == "":
		apply_saved()
	return _locale


## Записати вибір. Поверне true, якщо мова змінилася (тоді гру треба перезапустити: restart())
static func choose(code: String) -> bool:
	var cf := ConfigFile.new()
	cf.load(SETTINGS)
	var was: String = String(cf.get_value("game", "language", DEFAULT))
	cf.set_value("game", "language", code)
	cf.save(SETTINGS)
	return was != code


static func restart(tree: SceneTree) -> void:
	OS.set_restart_on_exit(true, OS.get_cmdline_args())
	tree.quit()


## Переклад рядка: російською — він сам, українською — з uk.po (немає перекладу — російський)
static func t(s: String) -> String:
	if current() == "ru":
		return s
	return String(TranslationServer.translate(s))


## Переклад усіх рядкових значень у даних із JSON (ключі словників — ідентифікатори, їх не чіпаємо)
static func tree(v: Variant) -> Variant:
	if current() == "ru":
		return v
	if v is Dictionary:
		for k in v:
			v[k] = tree(v[k])
	elif v is Array:
		for i in v.size():
			v[i] = tree(v[i])
	elif v is String:
		return t(v)
	return v

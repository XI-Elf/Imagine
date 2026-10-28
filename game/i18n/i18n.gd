class_name I18n
extends Node
## Язык игры (вопрос Q26): русский (исходный, строки кода и данных — ключи) и украинский (i18n/uk.po).
## Выбор хранится в user://settings.cfg и действует с запуска: тексты в static var собираются при загрузке скриптов,
## поэтому смена языка в меню перезапускает игру. Автозагрузка LangBoot стоит первой и ставит язык до остальных.
## Строки пополняет и проверяет tools/i18n.py (wrap / extract / check).

const SETTINGS := "user://settings.cfg"
const LANGS: Array = [["ru", "Русский"], ["uk", "Українська"]]

static var _locale: String = ""


func _init() -> void:
	apply_saved()


static func saved() -> String:
	var cf := ConfigFile.new()
	var code: String = "ru"
	if cf.load(SETTINGS) == OK:
		code = String(cf.get_value("game", "language", "ru"))
	return code if LANGS.any(func(l): return l[0] == code) else "ru"


static func apply_saved() -> void:
	var test: String = test_lang()
	_locale = test if test != "" else saved()
	TranslationServer.set_locale(_locale)


## Тесты (godot -s res://tests/...) сверяют русские тексты, поэтому идут на русском, что бы ни выбрал игрок.
## Прогнать их на украинском: AMBER_TEST_LANG=uk. Вне тестов — пустая строка.
static func test_lang() -> String:
	if not Array(OS.get_cmdline_args()).any(func(a): return String(a).begins_with("res://tests/")):
		return ""
	var code: String = OS.get_environment("AMBER_TEST_LANG")
	return code if LANGS.any(func(l): return l[0] == code) else "ru"


static func current() -> String:
	if _locale == "":
		apply_saved()
	return _locale


## Записать выбор. Вернёт true, если язык поменялся (тогда игру нужно перезапустить: restart())
static func choose(code: String) -> bool:
	var cf := ConfigFile.new()
	cf.load(SETTINGS)
	var was: String = String(cf.get_value("game", "language", "ru"))
	cf.set_value("game", "language", code)
	cf.save(SETTINGS)
	return was != code


static func restart(tree: SceneTree) -> void:
	OS.set_restart_on_exit(true, OS.get_cmdline_args())
	tree.quit()


## Перевод строки: на русском — она сама, на украинском — из uk.po (нет перевода — русская)
static func t(s: String) -> String:
	if current() == "ru":
		return s
	return String(TranslationServer.translate(s))


## Перевод всех строковых значений в данных из JSON (ключи словарей — идентификаторы, их не трогаем)
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

extends RefCounted
## Хроніка героя: ключові події саме його життя (початок шляху, перші ворота, бої, поради, хвороби, записки).
## Історія світу сюди не входить: вона відкривається гравцеві з розмов, руїн і знахідок (world/codex.gd).
## Живе в Worlds.chronicle [{t, kind, key, text}], зникає разом з героєм (HeroDeath.forget_hero) і входить у збереження світу.

const MAX := 80
const Sheet := preload("res://characters/sheet.gd")
const Journal := preload("res://characters/quest_journal.gd")

## Як записано, залежить від Уму героя в мить запису (lv: 0 — каракулі, 1 — як є, 2 — з роздумом), як і журнал J
static var CODA: Dictionary = {
	"start": I18n.t("Дорога длинная, а сапоги одни. Посмотрим, что сотрётся раньше."),
	"city": I18n.t("Стены высокие, а люди за ними — те же, что снаружи, только записанные."),
	"battle": I18n.t("Руки дрожали ещё час. Живой — значит, в этот раз повезло, а не выучился."),
	"quest": I18n.t("Заплатили. Кто кому на самом деле услужил — вопрос, который лучше не задавать вслух."),
	"body": I18n.t("Тело напоминает, что оно тоже участвует в походе, и без спросу."),
	"note": I18n.t("Кто-то писал это, не надеясь, что прочтут. Прочёл я. Неизвестно, к добру ли."),
	"talk": I18n.t("Сказано было больше, чем произнесено."),
	"level": I18n.t("Чему-то научился. Мир от этого не стал понятнее, только я — живучее."),
	"death": I18n.t("Дальше пишет кто-то другой."),
}

static var KINDS: Dictionary = {"start": "·", "city": "◆", "battle": "✕", "quest": "✓", "body": "+", "note": "§", "talk": "…", "level": "↑", "death": "†"}


## Дописати подію. key — щоб не повторювати одне й те саме («city:s001» записується раз); порожній — завжди новий запис.
## w — вузол Worlds (може бути null у тестах без нього), t — ігрові секунди
static func add(w: Node, kind: String, text: String, t: float, key: String = "") -> void:
	if w == null or not (w.get("chronicle") is Array):
		return
	var log: Array = w.chronicle
	if key != "":
		for e in log:
			if String(e.get("key", "")) == key:
				return
	log.append({"t": t, "kind": kind, "key": key, "text": text, "lv": level_of(w)})
	# Переповнення: викидаємо найстарішу, крім першого запису (початок шляху)
	while log.size() > MAX:
		log.remove_at(1)


## Рівень письма героя Worlds: 0 при Умі 3 і нижче, 2 при 7 і вище (Sheet.dumb / smart)
static func level_of(w: Node) -> int:
	var a: Actor = w.hero_actor() if w != null and w.has_method("hero_actor") else null
	if a == null:
		return 1
	return 0 if Sheet.dumb(a) else (2 if Sheet.smart(a) else 1)


## Текст запису так, як його записав герой; старі записи без lv — як є
static func render(e: Dictionary) -> String:
	var t: String = String(e.get("text", ""))
	match int(e.get("lv", 1)):
		0:
			var w: String = Journal.crude_words(t)
			return I18n.t("(каракули) %s") % (w if w != "" else "…")
		2:
			var c: String = String(CODA.get(String(e.get("kind", "")), ""))
			return t if c == "" else "%s %s" % [t, c]
	return t


static func entries(w: Node) -> Array:
	if w != null and w.get("chronicle") is Array:
		return w.chronicle
	return []


static func mark(kind: String) -> String:
	return String(KINDS.get(kind, "·"))

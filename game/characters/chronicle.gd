extends RefCounted
## Хроніка героя: ключові події саме його життя (початок шляху, перші ворота, бої, поради, хвороби, записки).
## Історія світу сюди не входить: вона відкривається гравцеві з розмов, руїн і знахідок (world/codex.gd).
## Живе в Worlds.chronicle [{t, kind, key, text}], зникає разом з героєм (HeroDeath.forget_hero) і входить у збереження світу.

const MAX := 80

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
	log.append({"t": t, "kind": kind, "key": key, "text": text})
	# Переповнення: викидаємо найстарішу, крім першого запису (початок шляху)
	while log.size() > MAX:
		log.remove_at(1)


static func entries(w: Node) -> Array:
	if w != null and w.get("chronicle") is Array:
		return w.chronicle
	return []


static func mark(kind: String) -> String:
	return String(KINDS.get(kind, "·"))

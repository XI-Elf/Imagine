extends RefCounted
## Розвилки доручень міста (data/cities/forks.json): згода на брудне проти вчинку за совістю, ціна совісті різна.
## Само доручення здається за будь-якого вибору, тож ріст міста не блокується.

const FILE := "res://data/cities/forks.json"

static var _cache: Dictionary = {}


static func data() -> Dictionary:
	if _cache.is_empty():
		var f := FileAccess.open(FILE, FileAccess.READ)
		if f != null:
			var v: Variant = I18n.tree(JSON.parse_string(f.get_as_text()))
			if v is Dictionary:
				_cache = v
		if _cache.is_empty():
			push_error("forks: не прочитано " + FILE)
	return _cache


## Розвилка доручення id або {}
static func of(id: String) -> Dictionary:
	return data().get("forks", {}).get(id, {})


## Підпис наслідку на кнопці: гравець бачить ціну заздалегідь
static func cost_text(cost: Dictionary) -> String:
	match String(cost.get("type", "")):
		"reward":
			return I18n.t("награда пропадёт")
		"fine":
			return I18n.t("−%d монет") % int(cost.get("amount", 0))
		"wound":
			return I18n.t("побои")
		"npc_death":
			return I18n.t("чужая жизнь")
		"hero_risk":
			return I18n.t("риск смерти %d %%") % int(round(float(cost.get("p", 0.0)) * 100.0))
	return ""

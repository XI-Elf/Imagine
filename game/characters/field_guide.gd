extends RefCounted
## Каталог справочника строится из тех же JSON/TRES, которыми пользуются игровые системы.
const Trade := preload("res://city/trade.gd")
const Craft := preload("res://city/craft.gd")

const CATEGORY_NAMES: Dictionary = {
	"all": "Все записи", "food": "Пища", "medicine": "Лечение", "resources": "Ресурсы",
	"tools": "Инструменты и походное", "weapons": "Оружие", "clothing": "Одежда и броня",
	"transport": "Транспорт", "quest": "Сюжетные",
}

static func categories() -> Array:
	return CATEGORY_NAMES.keys()

static func category_name(id: String) -> String:
	return String(CATEGORY_NAMES.get(id, id))

static func items(category: String = "all") -> Array:
	var out: Array = []
	for id in Trade.items():
		var d: Dictionary = Trade.item(String(id))
		if category != "all" and String(d.get("category", "resources")) != category:
			continue
		out.append({"id": String(id), "data": d})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var an := String(a.data.get("name", a.id))
		var bn := String(b.data.get("name", b.id))
		return an.naturalnocasecmp_to(bn) < 0
	)
	return out

static func recipes() -> Array:
	var out: Array = []
	var all: Dictionary = Craft.data().get("recipes", {})
	for id in all:
		var r: Dictionary = all[id].duplicate(true)
		r["id"] = String(id)
		out.append(r)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("level", 0)) != int(b.get("level", 0)):
			return int(a.get("level", 0)) < int(b.get("level", 0))
		return Trade.item_name(String(a.get("out", ""))).naturalnocasecmp_to(Trade.item_name(String(b.get("out", "")))) < 0
	)
	return out

static func abilities() -> Array:
	var out: Array = []
	var dir := DirAccess.open("res://data/battle/abilities")
	if dir == null:
		return out
	for file in dir.get_files():
		if not file.ends_with(".tres"):
			continue
		var resource: Resource = load("res://data/battle/abilities/" + file)
		if resource == null:
			continue
		out.append({"title": String(resource.get("title")), "description": String(resource.get("description")), "id": file.get_basename()})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.title).naturalnocasecmp_to(String(b.title)) < 0
	)
	return out

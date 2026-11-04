extends RefCounted
## Знос і лагодження (механіка 6, Huzzah 2026-10-29): одяг зношується в дорозі, зброя й обладунок — у бою.
## Стан речі — bag["wear"][id] від 100 (ціла) до 0 (розлізлася й пропала). Одне число на вид речі: та, що на герої.
## Лагодять майстри (кузнець — метал, кожум'яка — шкіра, ткаля — тканина) за плату або сам герой набором для починки.
## Числа в data/world/camp.json, розділ wear [ВРЕМЕННО].

const Trade := preload("res://city/trade.gd")
const FILE := "res://data/world/camp.json"

static var _rules: Dictionary = {}


static func rules() -> Dictionary:
	if _rules.is_empty():
		var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
		_rules = v.get("wear", {}) if v is Dictionary else {}
	return _rules


static func cond(bag: Dictionary, id: String) -> float:
	return float(bag.get("wear", {}).get(id, 100.0))


static func _put(bag: Dictionary, id: String, v: float) -> void:
	if not bag.has("wear"):
		bag["wear"] = {}
	if v >= 100.0:
		bag["wear"].erase(id)
	else:
		bag["wear"][id] = v


## Зношує річ на amount; якщо розлізлася — прибирає одну з сумки. Повертає текст для гравця або ""
static func damage(bag: Dictionary, id: String, amount: float) -> String:
	if id == "" or Trade.count(bag, id) <= 0 or amount <= 0.0:
		return ""
	var v: float = cond(bag, id) - amount
	if v > 0.0:
		_put(bag, id, v)
		return ""
	_put(bag, id, 100.0)
	Trade.add(bag, id, -1)
	if Trade.count(bag, id) <= 0:
		var eq: Dictionary = bag.get("equipped", {})
		for slot in eq.keys():
			if String(eq[slot]) == id:
				eq.erase(slot)
		if bag.has("battle_loadout"):
			bag["battle_loadout"].erase(id)
	return I18n.t("%s развалилось от износа") % Trade.item_name(id)


## Кілометр дороги: одяг на герої
static func on_km(bag: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	var km: Dictionary = rules().get("km", {})
	var eq: Dictionary = bag.get("equipped", {})
	for slot in eq.keys():
		var t: String = damage(bag, String(eq[slot]), float(km.get(slot, 0.1)))
		if t != "":
			out.append(t)
	return out


## Бій: зброя, взята в бій, і обладунок на тілі
static func on_battle(bag: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	for id in bag.get("battle_loadout", []).duplicate():
		var t: String = damage(bag, String(id), float(rules().get("battle_weapon", 4.0)))
		if t != "":
			out.append(t)
	var body: String = String(bag.get("equipped", {}).get("body", ""))
	var t2: String = damage(bag, body, float(rules().get("battle_armor", 5.0)))
	if t2 != "":
		out.append(t2)
	return out


## Хто з майстрів лагодить річ: smith, tanner, weaver або ""
static func master_of(id: String) -> String:
	var m: Dictionary = rules().get("masters", {})
	for k in m:
		if id in m[k]:
			return k
	return ""


## Зношені речі в сумці (за бажанням — лише ті, що лагодить master)
static func damaged(bag: Dictionary, master: String = "") -> Array:
	var out: Array = []
	for id in bag.get("wear", {}):
		if Trade.count(bag, id) > 0 and (master == "" or master_of(id) == master):
			out.append(id)
	return out


static func repair_fee(bag: Dictionary, id: String) -> int:
	var lost: float = 100.0 - cond(bag, id)
	return maxi(int(ceil(float(Trade.item(id).get("price", 10)) * float(rules().get("repair_fee", 0.5)) * lost / 100.0)), 1)


## Лагодження в майстра: усі зношені речі його ремесла, якщо вистачає грошей
static func repair_at(bag: Dictionary, master: String) -> String:
	var list: Array = damaged(bag, master)
	if list.is_empty():
		return I18n.t("Чинить нечего")
	var fee: int = 0
	for id in list:
		fee += repair_fee(bag, id)
	if int(bag.get("money", 0)) < fee:
		return I18n.t("Починка стоит %d монет, не хватает") % fee
	bag["money"] = int(bag["money"]) - fee
	for id in list:
		_put(bag, id, 100.0)
	return I18n.t("Починено за %d монет") % fee


## Набір для починки: найзношеніша річ +repair_kit, набір витрачається
static func repair_with_kit(bag: Dictionary) -> String:
	if Trade.count(bag, "repair_kit") <= 0:
		return I18n.t("Нет набора для починки")
	var list: Array = damaged(bag)
	if list.is_empty():
		return I18n.t("Чинить нечего")
	list.sort_custom(func(a, b): return cond(bag, a) < cond(bag, b))
	var id: String = list[0]
	_put(bag, id, minf(cond(bag, id) + float(rules().get("repair_kit", 40.0)), 100.0))
	Trade.add(bag, "repair_kit", -1)
	return I18n.t("Подлатал: %s — %d %%") % [Trade.item_name(id), int(cond(bag, id))]

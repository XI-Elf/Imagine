extends RefCounted
## Вещи и торговля: сумка {"money": int, "items": {id: count}}, предметы из data/cities/items.json.
## Сумка — простой словарь, чтобы её мог держать кто угодно (Worlds, город) и писать в сохранение.
## Цены: покупка дороже базовой, продажа дешевле; Харизма двигает обе [ВРЕМЕННО].

const ITEMS_FILE := "res://data/cities/items.json"

static var _items: Dictionary = {}
static var _read: bool = false


static func items() -> Dictionary:
	# Читается один раз: если файла нет, ошибка пишется один раз, а не на каждый вызов (каждый кадр)
	if not _read:
		_read = true
		var f := FileAccess.open(ITEMS_FILE, FileAccess.READ)
		if f != null:
			var v: Variant = JSON.parse_string(f.get_as_text())
			if v is Dictionary:
				_items = v.get("items", {})
		if _items.is_empty():
			push_error("trade: не прочитан " + ITEMS_FILE)
	return _items


static func item(id: String) -> Dictionary:
	return items().get(id, {})


static func item_name(id: String) -> String:
	return String(item(id).get("name", id))


static func new_bag(money: int = 0) -> Dictionary:
	return {"money": money, "items": {}}


static func count(bag: Dictionary, id: String) -> int:
	return int(bag["items"].get(id, 0))


static func add(bag: Dictionary, id: String, n: int = 1) -> void:
	var c: int = count(bag, id) + n
	if c <= 0:
		bag["items"].erase(id)
	else:
		bag["items"][id] = c


static func weight(bag: Dictionary) -> float:
	var kg: float = 0.0
	for id in bag["items"]:
		kg += float(item(id).get("weight", 0.0)) * int(bag["items"][id])
	return kg


## Что из сумки годится для лечения (ключи для Actor.treat)
static func remedies(bag: Dictionary) -> Array:
	return bag["items"].keys().filter(func(id): return bool(item(id).get("treat", false)))


# Харизма 4 — без скидки; каждое очко сверху — 3 % в пользу покупателя
static func _cha_bonus(buyer: Actor) -> float:
	return clampf((buyer.stat("cha") - 4.0) * 0.03, -0.15, 0.3) if buyer != null else 0.0


static func buy_price(id: String, buyer: Actor) -> int:
	return maxi(1, int(round(float(item(id).get("price", 1)) * (1.3 - _cha_bonus(buyer)))))


static func sell_price(id: String, seller: Actor) -> int:
	return maxi(1, int(round(float(item(id).get("price", 1)) * (0.45 + _cha_bonus(seller)))))


## Купить одну вещь у торговца (его запас stock: {id: count}). Ответ: текст для игрока, "" — удалось
static func buy(bag: Dictionary, stock: Dictionary, id: String, buyer: Actor) -> String:
	if int(stock.get(id, 0)) <= 0:
		return "Нет в наличии"
	# Лошадь и повозка (Q16): одна на героя, повозке нужна лошадь
	if bool(item(id).get("unique", false)) and count(bag, id) > 0:
		return "Уже есть"
	var need: String = String(item(id).get("requires", ""))
	if need != "" and count(bag, need) <= 0:
		return "Сначала нужна %s" % item_name(need).to_lower()
	var price: int = buy_price(id, buyer)
	if int(bag["money"]) < price:
		return "Не хватает денег"
	bag["money"] = int(bag["money"]) - price
	stock[id] = int(stock[id]) - 1
	add(bag, id)
	return ""


## Продать одну вещь торговцу, если он такое берёт (buys) или уже им торгует
static func sell(bag: Dictionary, stock: Dictionary, buys: Array, id: String, seller: Actor) -> String:
	if count(bag, id) <= 0:
		return "Нечего продать"
	if not buys.has(id) and not stock.has(id):
		return "Такое здесь не берут"
	bag["money"] = int(bag["money"]) + sell_price(id, seller)
	add(bag, id, -1)
	stock[id] = int(stock.get(id, 0)) + 1
	return ""


## Съесть или выпить вещь из сумки. Ответ: текст для игрока
static func use(bag: Dictionary, id: String, a: Actor) -> String:
	if count(bag, id) <= 0 or a == null or not a.alive:
		return ""
	var u: Dictionary = item(id).get("use", {})
	if u.has("eat"):
		a.eat(float(u["eat"]), String(u.get("kind", "cooked")))
	elif u.has("drink"):
		a.drink(float(u["drink"]), String(u.get("kind", "clean")))
	else:
		return "%s: так не используется" % item_name(id)
	add(bag, id, -1)
	return "Использовано: %s" % item_name(id)

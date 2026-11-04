extends RefCounted
## Руины на общей карте (вопрос Q04, Huzzah 2026-10-24: «лом падает с бандитов и лежит в руинах на общей карте»).
## В пустошах и проклятых землях стоят развалины; герой рядом с ними по F обыскивает их и находит металлолом,
## иногда древную монету. Обысканные руины пусты RESPAWN_DAYS игровых дней.
## Места не хранятся: сетка GRID_M по карте, в клетке руины с вероятностью CHANCE (хеш клетки), если там подходящий биом.
## Обысканные — словарь "x:y" -> игровые секунды обыска (characters/cast.gd, to_dict ключ "ruins_looted").

const GRID_M: float = 450.0
const CHANCE: float = 0.22
const REACH_M: float = 30.0
const RESPAWN_DAYS: float = 3.0
const BIOMES: Array = [4, 7, 8]      # пустка, проклятий ліс, проклята пустка (game.gd BIOME_NAMES)


static func _hash(x: int, y: int, k: int) -> float:
	var h: int = (x * 73856093) ^ (y * 19349663) ^ (k * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	return float((h ^ (h >> 16)) & 0xFFFF) / 65535.0


static func key_of(c: Vector2i) -> String:
	return "%d:%d" % [c.x, c.y]


## Руїни в клітинці сітки c або Vector2.INF
static func site_in(game: Node, c: Vector2i) -> Vector2:
	if _hash(c.x, c.y, 1) > CHANCE:
		return Vector2.INF
	var p := (Vector2(c) + Vector2(0.2 + 0.6 * _hash(c.x, c.y, 2), 0.2 + 0.6 * _hash(c.x, c.y, 3))) * GRID_M
	if not BIOMES.has(game.biome_at(p)):
		return Vector2.INF
	var st: Object = game.get("settlements")
	if st != null and st.has_method("blocks") and st.blocks(p):
		return Vector2.INF
	return p


## Усі руїни в прямокутнику карти (метри): [{key, pos}]
static func in_rect(game: Node, r: Rect2) -> Array:
	var out: Array = []
	var c0 := Vector2i(floori(r.position.x / GRID_M), floori(r.position.y / GRID_M))
	var c1 := Vector2i(floori(r.end.x / GRID_M), floori(r.end.y / GRID_M))
	for y in range(c0.y, c1.y + 1):
		for x in range(c0.x, c1.x + 1):
			var p: Vector2 = site_in(game, Vector2i(x, y))
			if p != Vector2.INF:
				out.append({"key": key_of(Vector2i(x, y)), "pos": p})
	return out


## Найближчі до точки руїни в межах REACH_M або {}
static func near(game: Node, p: Vector2) -> Dictionary:
	for s in in_rect(game, Rect2(p - Vector2(REACH_M, REACH_M), Vector2(REACH_M, REACH_M) * 2.0)):
		if s["pos"].distance_to(p) <= REACH_M:
			return s
	return {}


static func looted_now(looted: Dictionary, key: String, now: float) -> bool:
	return looted.has(key) and now - float(looted[key]) < RESPAWN_DAYS * 86400.0


## Обшукати: {"scrap": n, "old_coin": n} (порожньо, якщо обшукано нещодавно). Речі кладуться в сумку bag (Trade)
## [Q19: не баланс, залишено] 1–3 шматки брухту, більше за доброго пошуку; монета — в одному випадку із шести
static func search(site: Dictionary, looted: Dictionary, now: float, search_eff: float, rng: RandomNumberGenerator, bag: Dictionary) -> Dictionary:
	if looted_now(looted, site["key"], now):
		return {}
	looted[site["key"]] = now
	var found: Dictionary = {"scrap": clampi(int(round(float(rng.randi_range(1, 3)) * search_eff)), 1, 4)}
	if rng.randf() < 1.0 / 6.0:
		found["old_coin"] = 1
	if not bag.has("items"):
		bag["items"] = {}
	for id in found:
		bag["items"][id] = int(bag["items"].get(id, 0)) + int(found[id])
	return found

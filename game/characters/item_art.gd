extends RefCounted
## Значки предметов (п.7 правок Huzzah 2026-11-03): у каждой вещи свой рисунок, а не общая «сумка» на всех.
## Рисуется кодом из заготовок формы: форма + два цвета + знак. Оружие рисуется иконками боя (battle/battle_icons.gd),
## одежда — силуэтом вида (wear.look) с отличительной деталью вещи (кольца кольчуги, пластины лат, мех плаща, ремешок шляпы).
## Таблица SPECS — единое место: тест проверяет, что у всех вещей из data/cities/items.json есть запись
## и что подпись (форма, цвета, знак) у каждой своя. Настоящие текстуры ляжут поверх позже (список — amber2d/assets_list).

const INK := Color("1a1410")

## id -> [форма, основной цвет, второй цвет, знак]
const SPECS: Dictionary = {
	# еда
	"bread": ["loaf", "c08a46", "8a5a2c", "cuts"],
	"dried_meat": ["strip", "7a3b2a", "4a2218", "ties"],
	"stew": ["bowl", "6b4a2e", "c9873c", "steam"],
	"vegetables": ["veg", "b9502c", "4f7a34", "leaf"],
	"berries": ["cluster", "7a2a4a", "4f7a34", "leaf"],
	"mushrooms": ["mushroom", "c9b48a", "8a7550", ""],
	"toadstool": ["mushroom", "b8402a", "efe6d2", "dots"],
	"roots": ["roots", "a58050", "6e5034", ""],
	"shellfish": ["shell", "d8cfc0", "8a8478", "ribs"],
	"wild_herbs": ["herbs", "5f8a42", "3a5a2a", "flower"],
	"raw_meat": ["steak", "b3434a", "efe6d2", ""],
	"tainted_meat": ["steak", "6f8a4a", "b8b28a", "flies"],
	"roasted_meat": ["steak", "8a4a2a", "c9873c", "sizzle"],
	"field_stew": ["pot", "3a3a3e", "c9873c", "steam"],
	"roasted_mushrooms": ["mushroom", "8a5a3a", "c9873c", "sizzle"],
	"charred_food": ["lump", "2a2622", "5a4a3a", "smoke"],
	"fat": ["lump", "efe2b8", "d8c58a", "shine"],
	"bone": ["bone", "e4dcc4", "b8ae94", ""],
	# питьё
	"water_flask": ["flask", "8f6f48", "6d93b5", ""],
	"ale": ["mug", "8a5a2c", "efe6d2", ""],
	# лечение и зелья
	"bandage": ["roll", "efe6d2", "b9a67c", ""],
	"splint": ["splint", "a58050", "efe6d2", ""],
	"salve": ["jar", "8a7a4a", "6f8a5a", "lid"],
	"herbal_decoction": ["bottle", "6f8a5a", "3a5a2a", "leaf"],
	"charcoal": ["pouch", "3a3632", "6a625a", "dust"],
	"anti_rad_potion": ["vial", "9a5ad0", "efe6d2", "rad"],
	"healing_potion": ["vial", "c4413a", "efe6d2", "cross"],
	"fever_potion": ["vial", "5aa8f0", "efe6d2", "drop"],
	"warming_potion": ["vial", "e09a3c", "efe6d2", "flame"],
	"vermifuge": ["bottle", "c9c04a", "6e6a2a", "stripes"],
	"stimulant": ["ampoule", "4ac0a8", "efe6d2", "spark"],
	"strong_potion": ["flask_round", "5a2a6a", "d8a43a", "skull"],
	# вещи
	"rope": ["coil", "a58050", "6e5034", ""],
	"hide": ["pelt", "9a7048", "6e4a2c", ""],
	"scrap": ["scrap", "6e7a87", "8c4a1e", "rust"],
	"old_coin": ["coin", "c9a24b", "8a6a24", "worn"],
	"amber": ["gem", "e09a2c", "f6d27a", ""],
	"amber_key_fragment": ["key_fragment", "d6a64a", "7b4932", "rings"],
	"flooded_ledger_page": ["ledger_page", "d8c692", "5a4b39", "ink"],
	"beacon_lens": ["lens", "d6a64a", "8d9aa0", "crack"],
	"brushwood": ["sticks", "7a5a3a", "4a3624", ""],
	"driftwood": ["log", "b8a98a", "8a7a5c", "grain"],
	"reed": ["reeds", "b9b45a", "7a8a3a", ""],
	"flint": ["stone", "5a5e64", "9aa0a8", "spark"],
	"parchment": ["scroll", "e4d6a8", "b89a64", ""],
	"charcoal_stick": ["stick", "2a2622", "6a625a", "tip"],
	"color_charcoals": ["sticks_color", "2a2622", "c4413a", ""],
	"map_fragment": ["map", "d8c692", "8a6a3a", "route"],
	"bedroll": ["bedroll", "6d7a5a", "8a6a44", "strap"],
	"tent": ["tent", "9a8a64", "6e5034", "flap"],
	"repair_kit": ["kit", "6e5034", "b0b4ba", "tools"],
	# транспорт (в сумке не лежит, но значок нужен окну торговли)
	"horse": ["horse", "7a4a2a", "2a1a10", ""],
	"cart": ["cart", "8a6a44", "4a3624", "wheel"],
}

## Одежда: у вещей с общим силуэтом (wear.look) — своя деталь
const WEAR_DETAIL: Dictionary = {
	"straw_hat": "band", "felt_cap": "fold", "leather_cap": "stitch", "linen_shirt": "laces", "leather_jacket": "buttons",
	"hide_vest": "fur_edge", "chain_mail": "rings", "plate_armor": "plates", "travel_cloak": "clasp", "fur_cloak": "fur_edge",
	"gloves": "cuffs", "trousers": "seam", "boots": "soles"}


static func has_spec(id: String) -> bool:
	return SPECS.has(id)


## Подпись значка: форма + цвета + знак (для проверки неповторимости)
static func signature(id: String, wear: Dictionary = {}) -> String:
	if SPECS.has(id):
		return "|".join(PackedStringArray(SPECS[id]))
	if not wear.is_empty():
		return "wear|%s|%s|%s" % [wear.get("look", ""), wear.get("color", ""), WEAR_DETAIL.get(id, "")]
	return ""


## Нарисовать значок предмета id в прямоугольнике r. false — вещи нет в таблице (рисует вызывающий)
static func draw(ci: CanvasItem, id: String, r: Rect2) -> bool:
	if not SPECS.has(id):
		return false
	var sp: Array = SPECS[id]
	var o: Vector2 = r.get_center()
	var s: float = minf(r.size.x, r.size.y) * 0.5
	_shape(ci, String(sp[0]), o, s, Color(String(sp[1])), Color(String(sp[2])), String(sp[3]))
	# Лёгкая сухая штриховка поверх заливки: единая тушевая фактура для еды,
	# материалов, оружия и экипировки, без замены исходных силуэтов предметов.
	var seed_value: int = abs(hash(id))
	for i in 4:
		var x: float = -0.42 + float((seed_value >> (i * 3)) & 7) * 0.11
		var y: float = -0.48 + float((seed_value >> (i * 4 + 2)) & 7) * 0.12
		ci.draw_line(o + Vector2(x, y) * s, o + Vector2(x + 0.13, y + 0.18) * s, Color(0.10, 0.07, 0.05, 0.22), maxf(0.8, s * 0.012))
	return true


## Деталь поверх силуэта одежды (рисует inventory_view после основного многоугольника)
static func wear_detail(ci: CanvasItem, id: String, o: Vector2, s: float, c: Color) -> void:
	var d: String = String(WEAR_DETAIL.get(id, ""))
	var dark: Color = c.darkened(0.45)
	var light: Color = c.lightened(0.4)
	match d:
		"band":
			ci.draw_line(o + Vector2(-0.38, -0.05) * s, o + Vector2(0.38, -0.05) * s, Color("7a2a20"), s * 0.16)
		"fold":
			ci.draw_line(o + Vector2(-0.58, 0.2) * s, o + Vector2(0.58, 0.2) * s, dark, s * 0.14)
		"stitch":
			for i in 5:
				ci.draw_line(o + Vector2(-0.35 + i * 0.17, -0.3) * s, o + Vector2(-0.3 + i * 0.17, -0.1) * s, light, 1.5)
		"laces":
			for i in 3:
				ci.draw_line(o + Vector2(-0.12, -0.55 + i * 0.16) * s, o + Vector2(0.12, -0.45 + i * 0.16) * s, dark, 1.6)
		"buttons":
			for i in 3:
				ci.draw_circle(o + Vector2(0.0, -0.4 + i * 0.3) * s, s * 0.06, INK)
		"fur_edge":
			for i in 7:
				ci.draw_circle(o + Vector2(-0.6 + i * 0.2, 0.62) * s, s * 0.11, Color("e4dcc4"))
		"rings":
			for yy in 5:
				for xx in 4:
					ci.draw_arc(o + Vector2(-0.3 + xx * 0.2 + (yy % 2) * 0.1, -0.3 + yy * 0.2) * s, s * 0.07, 0.0, TAU, 8, dark, 1.2)
		"plates":
			for i in 3:
				ci.draw_line(o + Vector2(-0.45, -0.3 + i * 0.28) * s, o + Vector2(0.45, -0.3 + i * 0.28) * s, dark, 2.0)
			for p in [Vector2(-0.35, -0.45), Vector2(0.35, -0.45), Vector2(0.0, 0.55)]:
				ci.draw_circle(o + p * s, s * 0.06, INK)
		"clasp":
			ci.draw_circle(o + Vector2(0.0, -0.62) * s, s * 0.09, Color("c9a24b"))
		"cuffs":
			ci.draw_line(o + Vector2(-0.62, 0.42) * s, o + Vector2(-0.18, 0.28) * s, dark, s * 0.12)
			ci.draw_line(o + Vector2(0.62, 0.42) * s, o + Vector2(0.18, 0.28) * s, dark, s * 0.12)
		"seam":
			ci.draw_line(o + Vector2(0.0, -0.2) * s, o + Vector2(0.0, 0.7) * s, dark, 1.4)
		"soles":
			ci.draw_line(o + Vector2(-0.85, 0.7) * s, o + Vector2(-0.1, 0.7) * s, INK, s * 0.1)
			ci.draw_line(o + Vector2(0.05, 0.7) * s, o + Vector2(0.8, 0.7) * s, INK, s * 0.1)


# ---------------------------------------------------------------------
# ФОРМЫ
# ---------------------------------------------------------------------
static func _p(o: Vector2, s: float, a: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in a:
		out.append(o + Vector2(q[0], q[1]) * s)
	return out


static func _poly(ci: CanvasItem, o: Vector2, s: float, a: Array, col: Color, outline: bool = true) -> void:
	var pts: PackedVector2Array = _p(o, s, a)
	ci.draw_colored_polygon(pts, col)
	if outline:
		pts.append(pts[0])
		ci.draw_polyline(pts, INK, 1.8, true)


static func _disc(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	ci.draw_circle(c, r, col)
	ci.draw_arc(c, r, 0.0, TAU, 16, INK, 1.6, true)


static func _shape(ci: CanvasItem, kind: String, o: Vector2, s: float, c1: Color, c2: Color, mark: String) -> void:
	match kind:
		"key_fragment":
			_poly(ci, o, s, [[-0.18, -0.8], [0.18, -0.8], [0.18, 0.18], [0.58, 0.18], [0.58, 0.42], [0.3, 0.42], [0.3, 0.7], [-0.05, 0.7], [-0.05, 0.18], [-0.18, 0.18]], c1)
			_disc(ci, o + Vector2(0, -0.52) * s, s * 0.22, c2)
			for i in 3:
				ci.draw_arc(o + Vector2(0, -0.52) * s, s * (0.28 + i * 0.09), 0.3, 2.7, 16, c2, 1.2)
		"ledger_page":
			_poly(ci, o, s, [[-0.58, -0.78], [0.42, -0.78], [0.62, -0.56], [0.62, 0.78], [-0.58, 0.78]], c1)
			ci.draw_line(o + Vector2(0.42, -0.78) * s, o + Vector2(0.42, -0.56) * s, c2, 1.5)
			for i in 4:
				ci.draw_line(o + Vector2(-0.36, -0.35 + i * 0.22) * s, o + Vector2(0.38, -0.35 + i * 0.22) * s, c2, 1.5)
			ci.draw_line(o + Vector2(-0.3, -0.48) * s, o + Vector2(0.15, -0.48) * s, Color("7b4932"), 2.0)
		"lens":
			_disc(ci, o, s * 0.62, c2)
			_poly(ci, o, s, [[0, -0.7], [0.48, -0.3], [0.62, 0.1], [0.28, 0.62], [-0.28, 0.62], [-0.62, 0.1], [-0.48, -0.3]], c1)
			ci.draw_line(o + Vector2(-0.22, -0.35) * s, o + Vector2(0.18, 0.45) * s, Color("efe6d2"), 2.0)
			ci.draw_line(o + Vector2(0.18, 0.45) * s, o + Vector2(0.34, 0.1) * s, INK, 1.3)
		"loaf":
			_poly(ci, o, s, [[-0.8, 0.35], [-0.7, -0.15], [-0.3, -0.45], [0.3, -0.45], [0.7, -0.15], [0.8, 0.35], [0.5, 0.5], [-0.5, 0.5]], c1)
			for i in 3:
				ci.draw_line(o + Vector2(-0.4 + i * 0.35, -0.35) * s, o + Vector2(-0.25 + i * 0.35, -0.05) * s, c2, 2.2)
		"strip":
			_poly(ci, o, s, [[-0.85, -0.2], [0.6, -0.4], [0.85, 0.1], [-0.6, 0.4]], c1)
			ci.draw_line(o + Vector2(-0.3, -0.2) * s, o + Vector2(-0.2, 0.3) * s, c2, s * 0.14)
			ci.draw_line(o + Vector2(0.3, -0.3) * s, o + Vector2(0.4, 0.1) * s, c2, s * 0.14)
		"bowl":
			_poly(ci, o, s, [[-0.75, -0.05], [0.75, -0.05], [0.5, 0.55], [-0.5, 0.55]], c1)
			ci.draw_line(o + Vector2(-0.65, -0.05) * s, o + Vector2(0.65, -0.05) * s, c2, s * 0.2)
			for i in 2:
				ci.draw_arc(o + Vector2(-0.25 + i * 0.5, -0.45) * s, s * 0.18, PI * 0.5, PI * 1.6, 8, Color(1, 1, 1, 0.6), 2.0)
		"veg":
			_disc(ci, o + Vector2(-0.25, 0.1) * s, s * 0.38, c1)
			_disc(ci, o + Vector2(0.3, 0.2) * s, s * 0.3, Color("d8b34a"))
			_poly(ci, o, s, [[-0.3, -0.3], [-0.1, -0.78], [0.05, -0.3]], c2)
		"cluster":
			for p in [Vector2(-0.3, 0.0), Vector2(0.25, -0.05), Vector2(0.0, 0.35), Vector2(-0.1, -0.35), Vector2(0.4, 0.4)]:
				_disc(ci, o + p * s, s * 0.22, c1)
			_poly(ci, o, s, [[0.1, -0.7], [0.45, -0.6], [0.2, -0.4]], c2)
		"mushroom":
			_poly(ci, o, s, [[-0.18, 0.0], [0.18, 0.0], [0.15, 0.7], [-0.15, 0.7]], Color("efe6d2"))
			_poly(ci, o, s, [[-0.75, 0.05], [-0.6, -0.4], [-0.2, -0.65], [0.2, -0.65], [0.6, -0.4], [0.75, 0.05]], c1)
			if mark == "dots":
				for p in [Vector2(-0.35, -0.3), Vector2(0.1, -0.45), Vector2(0.4, -0.15)]:
					ci.draw_circle(o + p * s, s * 0.09, c2)
			elif mark == "sizzle":
				ci.draw_line(o + Vector2(-0.5, -0.4) * s, o + Vector2(0.5, -0.1) * s, c2, 2.0)
		"roots":
			_poly(ci, o, s, [[-0.2, -0.7], [0.2, -0.7], [0.3, 0.1], [0.0, 0.8], [-0.3, 0.1]], c1)
			ci.draw_line(o + Vector2(0.0, 0.3) * s, o + Vector2(-0.6, 0.7) * s, c2, 2.4)
			ci.draw_line(o + Vector2(0.0, 0.2) * s, o + Vector2(0.55, 0.65) * s, c2, 2.4)
		"shell":
			_poly(ci, o, s, [[-0.75, 0.35], [-0.55, -0.35], [0.0, -0.65], [0.55, -0.35], [0.75, 0.35], [0.0, 0.6]], c1)
			for i in 4:
				ci.draw_line(o + Vector2(0.0, 0.55) * s, o + Vector2(-0.55 + i * 0.37, -0.45) * s, c2, 1.6)
		"herbs":
			for i in 3:
				var a: float = -0.5 + i * 0.5
				ci.draw_line(o + Vector2(0.0, 0.75) * s, o + Vector2(sin(a) * 0.7, -0.5) * s, c1, 3.0)
				_disc(ci, o + Vector2(sin(a) * 0.7, -0.5) * s, s * 0.17, c2)
			ci.draw_circle(o + Vector2(0.0, -0.15) * s, s * 0.1, Color("e8d85a"))
		"steak":
			_poly(ci, o, s, [[-0.75, 0.0], [-0.4, -0.45], [0.3, -0.5], [0.8, -0.1], [0.5, 0.45], [-0.3, 0.5]], c1)
			_disc(ci, o + Vector2(0.15, -0.05) * s, s * 0.2, c2)
			if mark == "flies":
				ci.draw_circle(o + Vector2(-0.6, -0.6) * s, 2.0, INK)
				ci.draw_circle(o + Vector2(0.6, -0.65) * s, 2.0, INK)
			elif mark == "sizzle":
				for i in 3:
					ci.draw_line(o + Vector2(-0.4 + i * 0.35, -0.3) * s, o + Vector2(-0.25 + i * 0.35, 0.2) * s, c2.darkened(0.3), 2.0)
		"pot":
			_poly(ci, o, s, [[-0.65, -0.15], [0.65, -0.15], [0.55, 0.6], [-0.55, 0.6]], c1)
			ci.draw_line(o + Vector2(-0.75, -0.15) * s, o + Vector2(0.75, -0.15) * s, INK, s * 0.12)
			ci.draw_arc(o + Vector2(0.0, -0.15) * s, s * 0.7, PI, TAU, 14, INK, 2.4)
			ci.draw_rect(Rect2(o + Vector2(-0.5, -0.12) * s, Vector2(1.0, 0.1) * s), c2)
		"lump":
			_poly(ci, o, s, [[-0.6, 0.2], [-0.4, -0.4], [0.2, -0.55], [0.65, -0.1], [0.55, 0.45], [-0.2, 0.55]], c1)
			ci.draw_circle(o + Vector2(0.1, -0.1) * s, s * 0.15, c2)
			if mark == "smoke":
				ci.draw_arc(o + Vector2(0.0, -0.75) * s, s * 0.15, PI * 0.5, PI * 1.8, 8, Color(0.6, 0.6, 0.6, 0.7), 2.0)
		"bone":
			ci.draw_line(o + Vector2(-0.55, 0.55) * s, o + Vector2(0.55, -0.55) * s, c1, s * 0.3)
			for p in [Vector2(-0.65, 0.4), Vector2(-0.4, 0.7), Vector2(0.65, -0.4), Vector2(0.4, -0.7)]:
				_disc(ci, o + p * s, s * 0.2, c1)
		"flask":
			_poly(ci, o, s, [[-0.14, -0.8], [0.14, -0.8], [0.14, -0.5], [0.55, -0.25], [0.55, 0.65], [-0.55, 0.65], [-0.55, -0.25], [-0.14, -0.5]], c1)
			_poly(ci, o, s, [[-0.45, 0.0], [0.45, 0.0], [0.45, 0.55], [-0.45, 0.55]], c2, false)
		"mug":
			_poly(ci, o, s, [[-0.45, -0.55], [0.35, -0.55], [0.35, 0.7], [-0.45, 0.7]], c1)
			_poly(ci, o, s, [[-0.5, -0.78], [0.4, -0.78], [0.4, -0.5], [-0.5, -0.5]], c2)
			ci.draw_arc(o + Vector2(0.45, 0.05) * s, s * 0.25, -PI * 0.5, PI * 0.5, 8, INK, 3.0)
		"roll":
			_disc(ci, o, s * 0.55, c1)
			_disc(ci, o, s * 0.2, c2)
			ci.draw_line(o + Vector2(0.4, 0.3) * s, o + Vector2(0.85, 0.75) * s, c1, s * 0.3)
		"splint":
			for i in 2:
				ci.draw_line(o + Vector2(-0.6 + i * 0.5, 0.7) * s, o + Vector2(-0.3 + i * 0.5, -0.7) * s, c1, s * 0.22)
			for yy in [-0.3, 0.3]:
				ci.draw_line(o + Vector2(-0.7, yy) * s, o + Vector2(0.6, yy - 0.1) * s, c2, s * 0.14)
		"jar":
			_poly(ci, o, s, [[-0.5, -0.3], [0.5, -0.3], [0.55, 0.65], [-0.55, 0.65]], c1)
			_poly(ci, o, s, [[-0.55, -0.6], [0.55, -0.6], [0.55, -0.3], [-0.55, -0.3]], c2)
			ci.draw_line(o + Vector2(-0.3, 0.1) * s, o + Vector2(0.3, 0.1) * s, Color(1, 1, 1, 0.4), 2.0)
		"bottle":
			_poly(ci, o, s, [[-0.12, -0.8], [0.12, -0.8], [0.12, -0.35], [0.5, -0.1], [0.5, 0.7], [-0.5, 0.7], [-0.5, -0.1], [-0.12, -0.35]], c1)
			ci.draw_rect(Rect2(o + Vector2(-0.14, -0.9) * s, Vector2(0.28, 0.14) * s), Color("8a5a2c"))
			if mark == "stripes":
				for i in 3:
					ci.draw_line(o + Vector2(-0.45, 0.05 + i * 0.2) * s, o + Vector2(0.45, 0.05 + i * 0.2) * s, c2, 2.4)
			elif mark == "leaf":
				_poly(ci, o, s, [[0.0, 0.0], [0.25, 0.25], [0.0, 0.5], [-0.25, 0.25]], c2, false)
		"pouch":
			_poly(ci, o, s, [[-0.5, -0.2], [0.5, -0.2], [0.7, 0.65], [-0.7, 0.65]], c1)
			_poly(ci, o, s, [[-0.3, -0.65], [0.3, -0.65], [0.25, -0.2], [-0.25, -0.2]], c2)
			ci.draw_line(o + Vector2(-0.3, -0.2) * s, o + Vector2(0.3, -0.2) * s, INK, 2.4)
		"vial":
			_poly(ci, o, s, [[-0.14, -0.8], [0.14, -0.8], [0.14, -0.4], [0.5, 0.0], [0.5, 0.6], [0.2, 0.75], [-0.2, 0.75], [-0.5, 0.6], [-0.5, 0.0], [-0.14, -0.4]], c1)
			ci.draw_rect(Rect2(o + Vector2(-0.16, -0.92) * s, Vector2(0.32, 0.16) * s), Color("8a5a2c"))
			var m := o + Vector2(0.0, 0.25) * s
			match mark:
				"cross":
					ci.draw_rect(Rect2(m - Vector2(0.06, 0.2) * s, Vector2(0.12, 0.4) * s), c2)
					ci.draw_rect(Rect2(m - Vector2(0.2, 0.06) * s, Vector2(0.4, 0.12) * s), c2)
				"drop":
					_poly(ci, m, s, [[0.0, -0.25], [0.18, 0.05], [0.0, 0.2], [-0.18, 0.05]], c2, false)
				"flame":
					_poly(ci, m, s, [[0.0, -0.28], [0.2, 0.05], [0.08, 0.22], [-0.08, 0.22], [-0.2, 0.05]], c2, false)
				"rad":
					for i in 3:
						ci.draw_arc(m, s * 0.22, TAU * i / 3.0, TAU * i / 3.0 + 0.9, 6, c2, 3.0)
		"ampoule":
			_poly(ci, o, s, [[0.0, -0.85], [0.18, -0.5], [0.3, 0.3], [0.0, 0.8], [-0.3, 0.3], [-0.18, -0.5]], c1)
			ci.draw_line(o + Vector2(-0.1, -0.2) * s, o + Vector2(0.1, 0.35) * s, c2, 2.0)
			ci.draw_line(o + Vector2(0.1, -0.2) * s, o + Vector2(-0.1, 0.35) * s, c2, 2.0)
		"flask_round":
			_poly(ci, o, s, [[-0.14, -0.8], [0.14, -0.8], [0.14, -0.4], [0.7, 0.15], [0.55, 0.65], [-0.55, 0.65], [-0.7, 0.15], [-0.14, -0.4]], c1)
			ci.draw_rect(Rect2(o + Vector2(-0.16, -0.92) * s, Vector2(0.32, 0.16) * s), Color("8a5a2c"))
			ci.draw_circle(o + Vector2(0.0, 0.2) * s, s * 0.14, c2)
			ci.draw_line(o + Vector2(-0.14, 0.4) * s, o + Vector2(0.14, 0.4) * s, c2, 2.0)
		"coil":
			for k in 3:
				ci.draw_arc(o, s * (0.25 + k * 0.17), 0.0, TAU, 20, c1, 3.2)
			ci.draw_line(o + Vector2(0.4, 0.0) * s, o + Vector2(0.85, 0.5) * s, c2, 3.0)
		"pelt":
			_poly(ci, o, s, [[-0.6, -0.5], [0.0, -0.7], [0.6, -0.5], [0.8, -0.1], [0.7, 0.3], [0.3, 0.7], [-0.3, 0.7], [-0.7, 0.3], [-0.8, -0.1]], c1)
			ci.draw_line(o + Vector2(0.0, -0.6) * s, o + Vector2(0.0, 0.6) * s, c2, 2.0)
		"scrap":
			_poly(ci, o, s, [[-0.7, 0.2], [-0.2, -0.5], [0.6, -0.3], [0.7, 0.4], [-0.1, 0.6]], c1)
			ci.draw_line(o + Vector2(-0.3, 0.1) * s, o + Vector2(0.4, -0.1) * s, Color(c2, 0.8), 4.0)
		"coin":
			_disc(ci, o, s * 0.62, c1)
			ci.draw_arc(o, s * 0.42, 0.0, TAU, 16, c2, 2.0)
			ci.draw_line(o + Vector2(-0.12, 0.0) * s, o + Vector2(0.12, 0.0) * s, c2, 2.0)
		"gem":
			_poly(ci, o, s, [[0.0, -0.7], [0.55, -0.15], [0.35, 0.6], [-0.35, 0.6], [-0.55, -0.15]], c1)
			_poly(ci, o, s, [[0.0, -0.45], [0.25, -0.1], [-0.15, 0.1]], c2, false)
		"sticks":
			for i in 4:
				ci.draw_line(o + Vector2(-0.7, -0.4 + i * 0.28) * s, o + Vector2(0.7, -0.2 + i * 0.22) * s, c1 if i % 2 == 0 else c2, s * 0.14)
		"log":
			_poly(ci, o, s, [[-0.8, -0.2], [0.7, -0.35], [0.8, 0.2], [-0.7, 0.4]], c1)
			_disc(ci, o + Vector2(0.75, -0.08) * s, s * 0.22, c2)
			ci.draw_line(o + Vector2(-0.5, 0.0) * s, o + Vector2(0.4, -0.1) * s, c2, 1.6)
		"reeds":
			for i in 4:
				var xx: float = -0.5 + i * 0.33
				ci.draw_line(o + Vector2(xx * 0.5, 0.8) * s, o + Vector2(xx, -0.7) * s, c1, 3.0)
				_poly(ci, o + Vector2(xx, -0.7) * s, s, [[-0.06, 0.0], [0.06, 0.0], [0.06, 0.4], [-0.06, 0.4]], c2, false)
		"stone":
			_poly(ci, o, s, [[-0.6, 0.3], [-0.4, -0.4], [0.2, -0.6], [0.7, -0.1], [0.5, 0.5], [-0.2, 0.55]], c1)
			ci.draw_line(o + Vector2(-0.2, -0.3) * s, o + Vector2(0.3, 0.2) * s, c2, 2.0)
			if mark == "spark":
				ci.draw_circle(o + Vector2(0.55, -0.55) * s, s * 0.08, Color("f6d27a"))
		"scroll":
			_poly(ci, o, s, [[-0.5, -0.65], [0.5, -0.65], [0.5, 0.65], [-0.5, 0.65]], c1)
			ci.draw_rect(Rect2(o + Vector2(-0.58, -0.75) * s, Vector2(1.16, 0.18) * s), c2)
			ci.draw_rect(Rect2(o + Vector2(-0.58, 0.57) * s, Vector2(1.16, 0.18) * s), c2)
		"stick":
			ci.draw_line(o + Vector2(-0.55, 0.55) * s, o + Vector2(0.55, -0.55) * s, c1, s * 0.3)
			ci.draw_line(o + Vector2(0.4, -0.4) * s, o + Vector2(0.62, -0.62) * s, c2, s * 0.3)
		"sticks_color":
			var cols: Array = [c2, Color("d8b34a"), Color("5f8a42"), Color("5a8ad0")]
			for i in 4:
				ci.draw_line(o + Vector2(-0.6 + i * 0.35, 0.6) * s, o + Vector2(-0.35 + i * 0.35, -0.6) * s, cols[i], s * 0.2)
			ci.draw_line(o + Vector2(-0.7, 0.2) * s, o + Vector2(0.7, 0.1) * s, c1, s * 0.12)
		"map":
			_poly(ci, o, s, [[-0.75, -0.5], [-0.2, -0.65], [0.3, -0.5], [0.75, -0.6], [0.7, 0.55], [0.2, 0.65], [-0.3, 0.5], [-0.8, 0.6]], c1)
			ci.draw_polyline(_p(o, s, [[-0.5, 0.3], [-0.1, -0.1], [0.2, 0.15], [0.55, -0.3]]), Color("8a2a20"), 2.0, true)
			ci.draw_circle(o + Vector2(0.55, -0.3) * s, s * 0.07, Color("8a2a20"))
		"bedroll":
			_poly(ci, o, s, [[-0.8, -0.25], [0.7, -0.25], [0.8, 0.0], [0.7, 0.25], [-0.8, 0.25]], c1)
			_disc(ci, o + Vector2(0.72, 0.0) * s, s * 0.25, c1.darkened(0.2))
			for xx in [-0.4, 0.2]:
				ci.draw_line(o + Vector2(xx, -0.28) * s, o + Vector2(xx, 0.28) * s, c2, s * 0.12)
		"tent":
			_poly(ci, o, s, [[0.0, -0.75], [0.85, 0.65], [-0.85, 0.65]], c1)
			_poly(ci, o, s, [[0.0, -0.1], [0.3, 0.65], [-0.3, 0.65]], c2)
			ci.draw_line(o + Vector2(0.0, -0.75) * s, o + Vector2(0.0, -0.95) * s, INK, 2.0)
		"kit":
			_poly(ci, o, s, [[-0.75, -0.25], [0.75, -0.25], [0.75, 0.6], [-0.75, 0.6]], c1)
			ci.draw_arc(o + Vector2(0.0, -0.25) * s, s * 0.3, PI, TAU, 8, INK, 3.0)
			ci.draw_line(o + Vector2(-0.35, 0.0) * s, o + Vector2(0.35, 0.45) * s, c2, 3.0)
			ci.draw_line(o + Vector2(0.35, 0.0) * s, o + Vector2(-0.35, 0.45) * s, c2, 3.0)
		"horse":
			_poly(ci, o, s, [[-0.7, 0.0], [-0.2, -0.3], [0.3, -0.35], [0.45, -0.75], [0.7, -0.6], [0.55, -0.25], [0.6, 0.3], [0.45, 0.8], [0.3, 0.8], [0.3, 0.3], [-0.3, 0.3], [-0.4, 0.8], [-0.55, 0.8], [-0.6, 0.3]], c1)
			ci.draw_line(o + Vector2(0.3, -0.35) * s, o + Vector2(0.35, -0.7) * s, c2, 3.0)
		"cart":
			_poly(ci, o, s, [[-0.75, -0.3], [0.75, -0.3], [0.65, 0.3], [-0.65, 0.3]], c1)
			_disc(ci, o + Vector2(-0.4, 0.45) * s, s * 0.3, c2)
			_disc(ci, o + Vector2(0.4, 0.45) * s, s * 0.3, c2)
			ci.draw_line(o + Vector2(0.75, -0.2) * s, o + Vector2(1.0, -0.5) * s, INK, 2.4)
		_:
			_poly(ci, o, s, [[-0.55, -0.3], [0.55, -0.3], [0.7, 0.65], [-0.7, 0.65]], c1)


## Значок одягу за видом (wear.look) і кольором
static func wear_icon(ci: CanvasItem, w: Dictionary, o: Vector2, s: float) -> void:
	var c := Color(String(w.get("color", "777777")))
	var shapes: Dictionary = {
		"straw_hat": [[[-0.85, 0.25], [-0.4, 0.05], [-0.3, -0.45], [0.3, -0.45], [0.4, 0.05], [0.85, 0.25], [0.5, 0.4], [-0.5, 0.4]]],
		"cap": [[[-0.6, 0.35], [-0.55, -0.15], [-0.25, -0.5], [0.25, -0.5], [0.55, -0.15], [0.6, 0.35]]],
		"shirt": [[[-0.3, -0.7], [0.3, -0.7], [0.8, -0.4], [0.6, 0.0], [0.4, -0.15], [0.4, 0.75], [-0.4, 0.75], [-0.4, -0.15], [-0.6, 0.0], [-0.8, -0.4]]],
		"jacket": [[[-0.3, -0.75], [0.3, -0.75], [0.85, -0.45], [0.8, 0.5], [0.5, 0.5], [0.45, 0.8], [-0.45, 0.8], [-0.5, 0.5], [-0.8, 0.5], [-0.85, -0.45]]],
		"cloak": [[[-0.3, -0.75], [0.3, -0.75], [0.6, 0.0], [0.8, 0.8], [-0.8, 0.8], [-0.6, 0.0]]],
		"gloves": [[[-0.75, -0.3], [-0.45, -0.6], [-0.1, -0.4], [-0.15, 0.4], [-0.6, 0.6], [-0.85, 0.2]], [[0.75, -0.3], [0.45, -0.6], [0.1, -0.4], [0.15, 0.4], [0.6, 0.6], [0.85, 0.2]]],
		"trousers": [[[-0.5, -0.75], [0.5, -0.75], [0.55, 0.8], [0.1, 0.8], [0.0, -0.2], [-0.1, 0.8], [-0.55, 0.8]]],
		"boots": [[[-0.75, -0.6], [-0.35, -0.6], [-0.35, 0.4], [-0.1, 0.5], [-0.1, 0.75], [-0.85, 0.75], [-0.75, 0.3]], [[0.15, -0.6], [0.55, -0.6], [0.55, 0.4], [0.8, 0.5], [0.8, 0.75], [0.05, 0.75], [0.15, 0.3]]]}
	for poly in shapes.get(String(w.get("look", "")), [[[-0.55, -0.3], [0.55, -0.3], [0.7, 0.65], [-0.7, 0.65]]]):
		var pts: PackedVector2Array = _p(o, s, poly)
		ci.draw_colored_polygon(pts, c)
		pts.append(pts[0])
		ci.draw_polyline(pts, INK, 2.0, true)

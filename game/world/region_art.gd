extends RefCounted
## Картинки огляду регіону (world/region_view.gd). Список, розміри й точки опори — art/region/manifest.json
## (пише tools/make_region_art.py). Заміна без правки коду: PNG із тим самим ім'ям у теці region_art/ поруч з exe
## (у редакторі — поруч із теки game/) має перевагу над заглушкою з art/region/. Варіант будинку за етапом росту
## міста — bld_<вид>_s<етап>.png; немає — береться основний.
## Усі об'єкти пакуються в один атлас: увесь регіон малюється однією текстурою (одна партія для відеокарти).

const DIR := "res://art/region/"
const MANIFEST := "res://art/region/manifest.json"
const OVERRIDE_DIR := "region_art"
## Намальовані нейромережею текстури (art/textures_ai, готує tools/ingest_textures.py): ключ огляду -> файл без .png.
## Основа без етапу (hall/inn/...) бере варіант s2, щоб на всіх етапах без власного варіанту був справжній, а не заглушка.
const AI_DIR := "res://art/textures_ai/"
const AI_ALIAS: Dictionary = {
	"bld_house": "bld_house_s2", "bld_hall": "bld_hall_s2", "bld_temple": "bld_temple_s2", "bld_inn": "bld_inn_s2",
	"bld_shop": "bld_shop_s2", "bld_healer": "bld_healer_s2", "bld_smithy": "bld_smithy_s2",
	"prop_well": "out_well", "prop_stall": "out_market_stall", "gate_wood": "gate_wood_open", "gate_stone": "gate_stone_open",
}
const MAX_SIDE: int = 512          # більша картинка в атласі зменшується до цього (пропорції ті самі)
const ATLAS_W: int = 4096

var manifest: Dictionary = {}
var atlas: ImageTexture
var regions: Dictionary = {}        # ключ -> Rect2 в атласі (пікселі)
var anchors: Dictionary = {}        # ключ -> точка опори в частках (0..1) розміру картинки
var heights: Dictionary = {}        # ключ -> висота на екрані 1080 px
var textures: Dictionary = {}       # окремі текстури (туман, плитки, табличка)
var overridden: Array = []          # які картинки взято з region_art/
var missing: Array = []


## Тека з картинками користувача: поруч з exe, а в редакторі — поруч із тeкою проєкту
static func override_dir() -> String:
	if OS.has_feature("editor") or not OS.has_feature("template"):
		return ProjectSettings.globalize_path("res://").path_join("..").simplify_path().path_join(OVERRIDE_DIR)
	return OS.get_executable_path().get_base_dir().path_join(OVERRIDE_DIR)


func load_all() -> void:
	if FileAccess.file_exists(MANIFEST):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
		if d is Dictionary:
			manifest = d
	var assets: Dictionary = manifest.get("assets", {})
	var imgs: Dictionary = {}
	for key in assets:
		var a: Dictionary = assets[key]
		var img: Image = _image(String(a["file"]))
		if img == null:
			missing.append(key)
			continue
		var kind: String = String(a.get("kind", "object"))
		if kind == "object" or key == "shadow" or key == "mist":
			imgs[key] = img
			var size: Array = a.get("size", [img.get_width(), img.get_height()])
			var an: Array = a.get("anchor", [size[0] * 0.5, size[1]])
			anchors[key] = Vector2(float(an[0]) / float(size[0]), float(an[1]) / float(size[1]))
			heights[key] = float(a.get("h", 0))
			# Варіанти за етапами росту міста (необов'язкові)
			if bool(a.get("stages", false)):
				for s in 5:
					var vk: String = "%s_s%d" % [key, s]
					var vi: Image = _image(vk + ".png")
					if vi != null:
						imgs[vk] = vi
						anchors[vk] = anchors[key]
						heights[vk] = heights[key]
		if kind != "object":
			textures[key] = ImageTexture.create_from_image(img)
	_pack(imgs)


## Картинка: спершу region_art/ користувача, потім заглушка з art/region/
func _image(file: String) -> Image:
	var user_path: String = override_dir().path_join(file)
	if FileAccess.file_exists(user_path):
		var img := Image.load_from_file(user_path)
		if img != null and not img.is_empty():
			overridden.append(file)
			return _prep(img)
	var stem: String = file.get_basename()
	var ai: String = AI_DIR + String(AI_ALIAS.get(stem, stem)) + ".png"
	if ResourceLoader.exists(ai):
		var at: Texture2D = load(ai)
		if at != null:
			return _prep(at.get_image())
	var res_path: String = DIR + file
	if ResourceLoader.exists(res_path):
		var tex: Texture2D = load(res_path)
		if tex != null:
			return _prep(tex.get_image())
	return null


func _prep(img: Image) -> Image:
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


## Пакування полицями в один атлас ATLAS_W завширшки
func _pack(imgs: Dictionary) -> void:
	var keys: Array = imgs.keys()
	keys.sort_custom(func(a, b): return imgs[a].get_height() > imgs[b].get_height())
	var placed: Dictionary = {}
	var x: int = 0
	var y: int = 0
	var shelf: int = 0
	for k in keys:
		var img: Image = imgs[k]
		var s: float = minf(1.0, float(MAX_SIDE) / float(maxi(img.get_width(), img.get_height())))
		if s < 1.0:
			img = img.duplicate()
			img.resize(maxi(1, int(img.get_width() * s)), maxi(1, int(img.get_height() * s)), Image.INTERPOLATE_LANCZOS)
			imgs[k] = img
		if x + img.get_width() + 2 > ATLAS_W:
			x = 0
			y += shelf + 2
			shelf = 0
		placed[k] = Vector2i(x + 1, y + 1)
		x += img.get_width() + 2
		shelf = maxi(shelf, img.get_height())
	var h: int = maxi(4, nearest_po2(y + shelf + 2))
	var out := Image.create(ATLAS_W, h, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	for k in placed:
		var img: Image = imgs[k]
		out.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), placed[k])
		regions[k] = Rect2(Vector2(placed[k]), Vector2(img.get_size()))
	out.generate_mipmaps()
	atlas = ImageTexture.create_from_image(out)


func has(key: String) -> bool:
	return regions.has(key)


## Ключ варіанта за етапом росту міста (є картинка етапу — вона, інакше основна)
func stage_key(key: String, stage: int) -> String:
	var vk: String = "%s_s%d" % [key, stage]
	return vk if regions.has(vk) else key


## Прямокутник на екрані для спрайта: опора в foot, висота h пікселів
func rect_for(key: String, foot: Vector2, h: float) -> Rect2:
	var r: Rect2 = regions[key]
	var size := Vector2(r.size.x * h / r.size.y, h)
	var an: Vector2 = anchors.get(key, Vector2(0.5, 1.0))
	return Rect2(foot - an * size, size)


## Прямокутник за шириною (будинки за ділянкою плану міста)
func rect_for_width(key: String, foot: Vector2, w: float) -> Rect2:
	var r: Rect2 = regions[key]
	return rect_for(key, foot, w * r.size.y / r.size.x)


## Плоска текстура (туман, плитки) із region_art/ або art/region/; для террейнів — region_art/terrain/
func terrain_override(name: String) -> Image:
	var p: String = override_dir().path_join("terrain").path_join(name + ".png")
	if FileAccess.file_exists(p):
		var img := Image.load_from_file(p)
		if img != null and not img.is_empty():
			overridden.append("terrain/" + name + ".png")
			return _prep(img)
	return null

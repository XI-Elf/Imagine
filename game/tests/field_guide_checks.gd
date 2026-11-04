extends SceneTree
## godot --headless --rendering-driver dummy -s res://tests/field_guide_checks.gd
const Trade := preload("res://city/trade.gd")
const Guide := preload("res://characters/field_guide.gd")
const Craft := preload("res://city/craft.gd")
var checks := 0
var fails := 0
func ok(value: bool, label: String) -> void:
    checks += 1
    if not value:
        fails += 1
        print("FAIL: ", label)
func _initialize() -> void:
    var all := Guide.items("all")
    ok(all.size() == Trade.items().size(), "справочник содержит все предметы базы")
    for e in all:
        ok(String(e.data.get("category", "")) != "", "категория у " + String(e.id))
        ok(String(e.data.get("description", "")) != "", "описание у " + String(e.id))
    var valid := true
    for r in Guide.recipes():
        if not Trade.items().has(String(r.get("out", ""))):
            valid = false
        for input_id in r.get("in", {}):
            if not Trade.items().has(String(input_id)):
                valid = false
    ok(valid, "все входы и выходы рецептов существуют в каталоге предметов")
    ok(not Guide.abilities().is_empty(), "боевые способности загружаются из TRES")
    print("FIELD GUIDE CHECKS: %d/%d" % [checks - fails, checks])
    quit(1 if fails else 0)

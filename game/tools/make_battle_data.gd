extends SceneTree
## Один раз создаёт ресурсы боя (.tres) в res://data/battle/. Дальше источник — сами .tres
## (их удобно править в инспекторе Godot); этот скрипт перезапишет их, если запустить снова.
## godot --headless --path game -s res://tools/make_battle_data.gd

const OUT := "res://data/battle/"

const WEAPONS: Array = [
	{"id": "fists", "icon": "fist", "title": "Кулаки", "damage": [{"type": "bludgeoning", "dice": "", "bonus": 1}], "proficiency": "natural"},
	{"id": "dagger", "icon": "knife", "title": "Нож", "damage": [{"type": "piercing", "dice": "1d4", "bonus": 0}], "stat": "finesse", "light": true, "range_ft": 20, "long_range_ft": 60},
	{"id": "club", "icon": "club", "title": "Дубина", "damage": [{"type": "bludgeoning", "dice": "1d4", "bonus": 0}], "light": true},
	{"id": "handaxe", "icon": "axe", "title": "Топорик", "damage": [{"type": "slashing", "dice": "1d4", "bonus": 0}, {"type": "bludgeoning", "dice": "", "bonus": 1}], "light": true},
	{"id": "spear", "icon": "spear", "title": "Копьё", "damage": [{"type": "piercing", "dice": "1d6", "bonus": 0}]},
	{"id": "shortsword", "icon": "sword", "title": "Тесак", "damage": [{"type": "slashing", "dice": "1d6", "bonus": 0}], "stat": "finesse", "light": true, "proficiency": "martial"},
	{"id": "longsword", "icon": "sword", "title": "Меч", "damage": [{"type": "slashing", "dice": "1d8", "bonus": 0}], "proficiency": "martial"},
	{"id": "battleaxe", "icon": "axe", "title": "Боевой топор", "damage": [{"type": "slashing", "dice": "1d6", "bonus": 0}, {"type": "bludgeoning", "dice": "1d4", "bonus": 0}], "proficiency": "martial"},
	{"id": "mace", "icon": "mace", "title": "Булава", "damage": [{"type": "bludgeoning", "dice": "1d6", "bonus": 0}]},
	{"id": "mutant_cleaver", "icon": "cleaver", "title": "Ржавый мутоклинок", "damage": [{"type": "slashing", "dice": "1d8", "bonus": 0}, {"type": "radiation", "dice": "1d4", "bonus": 0}], "proficiency": "martial"},
	{"id": "sling", "icon": "sling", "title": "Праща", "damage": [{"type": "bludgeoning", "dice": "1d4", "bonus": 0}], "stat": "dex", "ranged": true, "range_ft": 30, "long_range_ft": 120, "ammo": 20},
	{"id": "shortbow", "icon": "bow", "title": "Короткий лук", "damage": [{"type": "piercing", "dice": "1d6", "bonus": 0}], "stat": "dex", "ranged": true, "range_ft": 80, "long_range_ft": 320, "ammo": 16, "two_handed": true},
	{"id": "wolf_bite", "icon": "bite", "title": "Укус", "damage": [{"type": "piercing", "dice": "2d4", "bonus": 0}], "proficiency": "natural", "on_hit_effect": "prone", "on_hit_save": "str", "on_hit_dc": 11},
	{"id": "tusk", "icon": "tusk", "title": "Клыки", "damage": [{"type": "slashing", "dice": "1d6", "bonus": 0}], "proficiency": "natural"},
	{"id": "hound_bite", "icon": "bite", "title": "Светящийся укус", "damage": [{"type": "piercing", "dice": "1d6", "bonus": 0}, {"type": "radiation", "dice": "1d4", "bonus": 0}], "proficiency": "natural"},
	{"id": "dog_bite", "icon": "bite", "title": "Укус", "damage": [{"type": "piercing", "dice": "1d6", "bonus": 0}], "proficiency": "natural"},
	{"id": "torch", "icon": "torch", "title": "Факел", "damage": [{"type": "bludgeoning", "dice": "1d4", "bonus": 0}, {"type": "fire", "dice": "", "bonus": 1}], "light": true},
]

const ARMOR: Array = [
	{"id": "none", "title": "Без брони", "base_ac": 10, "dex_cap": -1},
	{"id": "hides", "title": "Ткань / шкуры", "base_ac": 11, "dex_cap": -1, "dr": {"bludgeoning": 1}, "good_vs": ["bludgeoning"], "weak_vs": ["slashing", "piercing"]},
	{"id": "leather", "title": "Кожаная", "base_ac": 12, "dex_cap": -1, "dr": {"slashing": 2, "bludgeoning": 2}, "good_vs": ["slashing", "bludgeoning"], "weak_vs": ["piercing"]},
	{"id": "chain", "title": "Кольчуга", "base_ac": 14, "dex_cap": 0, "dr": {"slashing": 2, "piercing": 2}, "good_vs": ["slashing", "piercing"], "weak_vs": ["bludgeoning"], "stealth_disadvantage": true},
	{"id": "plate", "title": "Латные элементы", "base_ac": 16, "dex_cap": 0, "dr": {"slashing": 2, "piercing": 2, "bludgeoning": 2}, "good_vs": ["slashing", "piercing", "bludgeoning"], "weak_vs": ["radiation"], "stealth_disadvantage": true},
	{"id": "lead", "title": "Свинцовые пластины", "base_ac": 15, "dex_cap": 0, "dr": {"radiation": 4}, "good_vs": ["radiation"], "weak_vs": ["slashing"], "stealth_disadvantage": true},
]

const EFFECTS: Array = [
	{"id": "prone", "title": "Сбит с ног", "melee_attacked_adv": true, "ranged_attacked_dis": true, "attack_dis": true, "stand_up_cost": true},
	{"id": "poisoned", "title": "Отравлен", "attack_dis": true, "duration_rounds": 3, "end_save_stat": "con", "end_save_dc": 11},
	{"id": "burning", "title": "Горит", "duration_rounds": 3, "turn_start_dice": "1d4", "turn_start_type": "fire", "end_save_stat": "dex", "end_save_dc": 10},
	{"id": "bleeding", "title": "Кровотечение", "duration_rounds": 3, "turn_start_dice": "1d4", "turn_start_type": "slashing", "end_save_stat": "con", "end_save_dc": 10},
	{"id": "dodging", "title": "Уклоняется", "duration_rounds": 1, "attacked_dis": true, "save_adv": ["dex"]},
	{"id": "hidden", "title": "Скрыт", "attack_adv": true, "attacked_dis": true, "ends_on_attack": true},
	{"id": "stunned", "title": "Оглушён", "duration_rounds": 1, "incapacitated": true, "attacked_adv": true, "save_autofail": ["str", "dex"], "speed_mult": 0.0},
	{"id": "restrained", "title": "Опутан", "duration_rounds": 2, "speed_mult": 0.0, "attacked_adv": true, "attack_dis": true, "save_dis": ["dex"], "end_save_stat": "str", "end_save_dc": 12},
	{"id": "blinded", "title": "Ослеплён", "attack_dis": true, "attacked_adv": true},
	{"id": "frightened", "title": "Напуган", "duration_rounds": 2, "attack_dis": true, "end_save_stat": "wis", "end_save_dc": 11},
	{"id": "unconscious", "title": "Без сознания", "incapacitated": true, "attacked_adv": true, "save_autofail": ["str", "dex"], "speed_mult": 0.0},
	{"id": "hurt_leg", "title": "Повреждена нога", "speed_mult": 0.5},
	{"id": "hurt_arm", "title": "Повреждена рука", "attack_dis_stat": "str"},
	{"id": "concussed", "title": "Сотрясение", "save_dis": ["int", "wis"]},
	{"id": "rallied", "title": "Воодушевлён", "duration_rounds": 2, "attack_adv": true},
]

const ABILITIES: Array = [
	{"id": "second_wind", "title": "Второе дыхание", "description": "Бонусное действие: восстановить 1d10 + уровень HP. Раз за бой.", "cost": "bonus", "kind": "heal", "target": "self", "heal_dice": "1d10", "heal_add_level": true, "uses_per_battle": 1, "range_ft": 0},
	{"id": "fire_flask", "title": "Огненная смесь", "description": "Бросок склянки: все в радиусе 5 футов — спасбросок Ловкости, 2d6 огня (половина при успехе), провал — горит.", "kind": "save", "target": "cell", "stat": "int", "range_ft": 30, "radius_ft": 5, "save_stat": "dex", "damage": [{"type": "fire", "dice": "2d6", "bonus": 0}], "apply_effect": "burning", "uses_per_battle": 2},
	{"id": "poison_dart", "title": "Ядовитый дротик", "description": "Дальняя атака Ловкостью: 1d4 колющего + 1d6 яда; спасбросок Выносливости или отравлен.", "kind": "attack", "target": "enemy", "stat": "dex", "range_ft": 40, "damage": [{"type": "piercing", "dice": "1d4", "bonus": 0}, {"type": "poison", "dice": "1d6", "bonus": 0}], "save_stat": "con", "apply_effect": "poisoned", "uses_per_battle": 3},
	{"id": "healing_salve", "title": "Лечебная мазь", "description": "Действие: союзник рядом восстанавливает 1d8 + Мудрость HP.", "kind": "heal", "target": "ally", "stat": "wis", "range_ft": 5, "heal_dice": "1d8", "uses_per_battle": 3},
	{"id": "war_cry", "title": "Боевой клич", "description": "Бонусное действие: союзники в 15 футах воодушевлены (атаки с преимуществом 2 раунда). Раз за бой.", "cost": "bonus", "kind": "self", "target": "self", "radius_ft": 15, "apply_effect": "rallied", "uses_per_battle": 1, "range_ft": 0},
	{"id": "net", "title": "Сеть", "description": "Бросок сети: спасбросок Силы или опутан.", "kind": "save", "target": "enemy", "stat": "dex", "range_ft": 15, "save_stat": "str", "apply_effect": "restrained", "uses_per_battle": 1, "half_on_save": false},
	{"id": "howl", "title": "Вой", "description": "Бонусное действие: враги в 30 футах — спасбросок Мудрости или напуганы. Раз за бой.", "cost": "bonus", "kind": "save", "target": "self", "stat": "con", "radius_ft": 30, "save_stat": "wis", "apply_effect": "frightened", "uses_per_battle": 1, "range_ft": 0, "half_on_save": false},
]

const CREATURES: Array = [
	{"id": "bandit", "title": "Разбойник", "scores": {"str": 11, "dex": 12, "con": 12, "int": 10, "wis": 10, "cha": 10, "lck": 10}, "hp_dice": "2d8", "armor": "leather", "weapons": ["shortsword", "dagger"], "abilities": ["net"], "ai": "melee", "morale": 0.5},
	{"id": "bandit_archer", "title": "Разбойник-лучник", "scores": {"str": 10, "dex": 14, "con": 12, "int": 10, "wis": 11, "cha": 10, "lck": 10}, "hp_dice": "2d8", "armor": "hides", "weapons": ["shortbow", "dagger"], "ai": "ranged", "morale": 0.4, "perception_prof": true},
	{"id": "bandit_chief", "title": "Атаман", "level": 2, "scores": {"str": 15, "dex": 12, "con": 14, "int": 11, "wis": 11, "cha": 14, "lck": 10}, "hp_dice": "4d8", "armor": "chain", "weapons": ["battleaxe", "dagger"], "abilities": ["war_cry"], "ai": "melee", "morale": 0.8, "save_profs": ["str", "con"]},
	{"id": "wolf", "title": "Волк", "human": false, "scores": {"str": 12, "dex": 15, "con": 12, "int": 3, "wis": 12, "cha": 6, "lck": 10}, "hp_dice": "2d8", "natural_ac": 11, "weapons": ["wolf_bite"], "speed_ft": 40, "ai": "beast", "morale": 0.4, "perception_prof": true, "stealth_prof": true},
	{"id": "boar", "title": "Кабан", "human": false, "scores": {"str": 13, "dex": 11, "con": 12, "int": 2, "wis": 9, "cha": 5, "lck": 10}, "hp_dice": "2d8", "natural_ac": 11, "weapons": ["tusk"], "speed_ft": 40, "ai": "beast", "morale": 0.9},
	{"id": "rad_hound", "title": "Проклятая гончая", "human": false, "scores": {"str": 13, "dex": 14, "con": 13, "int": 3, "wis": 12, "cha": 5, "lck": 10}, "hp_dice": "2d8", "natural_ac": 11, "weapons": ["hound_bite"], "abilities": ["howl"], "resist": {"radiation": 0.5}, "speed_ft": 40, "ai": "beast", "morale": 0.0},
	{"id": "dog", "title": "Пёс", "human": false, "pet": true, "scores": {"str": 13, "dex": 14, "con": 12, "int": 3, "wis": 12, "cha": 7, "lck": 10}, "hp_dice": "2d8", "natural_ac": 11, "weapons": ["dog_bite"], "speed_ft": 40, "ai": "beast", "morale": 1.0, "perception_prof": true},
]


func _initialize() -> void:
	for d in ["weapons", "armor", "effects", "abilities", "creatures"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + d))
	_save_all(WEAPONS, BattleWeapon, "weapons")
	_save_all(ARMOR, BattleArmor, "armor")
	_save_all(EFFECTS, BattleEffect, "effects")
	_save_all(ABILITIES, BattleAbility, "abilities")
	_save_all(CREATURES, BattleCreature, "creatures")
	var cfg := BattleConfig.new()
	ResourceSaver.save(cfg, OUT + "config.tres")
	print("battle data: ok")
	quit()


func _save_all(list: Array, cls, dir: String) -> void:
	for d in list:
		var r: Resource = cls.new()
		for k in d:
			var v: Variant = d[k]
			if v is Array and k != "damage":
				v = PackedStringArray(v)
			r.set(k, v)
		var err: int = ResourceSaver.save(r, OUT + dir + "/" + String(d["id"]) + ".tres")
		if err != OK:
			push_error("не сохранён %s: %d" % [d["id"], err])

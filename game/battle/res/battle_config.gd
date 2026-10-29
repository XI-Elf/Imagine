class_name BattleConfig
extends Resource
## Общие числа боя. Все [Q19: проверяет tests/balance_checks.gd], кроме базовых формул.

## Combat_Formulas: параметри, не зашиті у формули. Значення — з ТЗ і документа користувача
## (d20, крит — другий кидок костей, укриття +2/+5, опір половина, вразливість удвічі)
@export var attack_die: int = 20                 # L = 1, H = attack_die
@export var k_crit: int = 2                      # повних кидків набору костей на криті
@export var cover_ac: Dictionary = {"none": 0, "half": 2, "three_quarters": 5}
@export var resist_default: float = 0.5          # S для «опору» без числа
@export var vulnerable_default: float = 1.0      # V для «вразливості» без числа
@export var grid_size: Vector2i = Vector2i(18, 12)
@export var cell_ft: int = 5
## 0 HP (решение Huzzah: травмы по документу, без death saves): бросок d20 + CON + LCK
@export var trauma_high: int = 15                # ≥ — травма, остаётся в сознании с 1 здоровья
@export var trauma_mid: int = 8                  # ≥ — без сознания, стабилен, травма; ниже — смерть
## Тяжёлый удар: урон ≥ доли максимума HP — проверка травмы по зоне (так же на крите)
@export var heavy_hit_frac: float = 0.5
@export var injury_dc: int = 12
@export var stat_offset: int = 6                 # боевое = значение Амбера + 6 (база 4 → 10)
@export var luck_offset: int = 10                # LCK = Удача Амбера + 10
@export var per_initiative_div: int = 4          # Чутьё сверх базы / 4 — к инициативе и внимательности
@export var flanking: bool = true
@export var high_ground_adv: bool = true
@export var party_level: int = 1
## Зброя героя — із сумки (inventory.items), до loadout_max видів; предмет -> зброя бою.
## Предмет з id, що збігається з id зброї, теж вважається зброєю, якщо він є в цьому списку
@export var loadout_max: int = 3
@export var item_weapons: Dictionary = {"knife": "dagger", "axe": "handaxe", "torch": "torch", "dagger": "dagger", "club": "club",
	"handaxe": "handaxe", "spear": "spear", "shortsword": "shortsword", "longsword": "longsword", "battleaxe": "battleaxe",
	"mace": "mace", "mutant_cleaver": "mutant_cleaver", "sling": "sling", "shortbow": "shortbow"}
## weapons героя — лише коли сумки немає зовсім (перевірний бій без Worlds)
@export var hero: Dictionary = {"hp_die": 10, "weapons": ["longsword", "sling"], "armor": "leather",
	"abilities": ["second_wind", "fire_flask"], "save_profs": ["str", "con"], "potions": 2}
@export var npc: Dictionary = {"hp_die": 8, "weapons": [["club"], ["spear"], ["handaxe"], ["dagger", "sling"]],
	"armor": "hides", "abilities": [], "save_profs": ["con"], "potions": 0}
@export var potion_dice: String = "2d4+2"
## Травма за зоною й типом шкоди -> стан пакета (actor conditions)
@export var trauma_table: Dictionary = {
	"head": {"bludgeoning": "broken_head", "slashing": "laceration", "piercing": "bullet_wound", "fire": "burn", "*": "broken_head"},
	"torso": {"slashing": "laceration", "piercing": "bullet_wound", "fire": "burn", "*": "laceration"},
	"arm": {"bludgeoning": "broken_arm", "slashing": "laceration", "piercing": "bullet_wound", "fire": "burn", "*": "luxation_arm"},
	"leg": {"bludgeoning": "broken_leg", "slashing": "laceration", "piercing": "bullet_wound", "fire": "burn", "*": "broken_leg"},
}
## Зона влучання за d20: до якого числа включно
@export var zones: Dictionary = {"head": 2, "torso": 10, "arm": 15, "leg": 20}
## Стани пакета в персонажа -> ефект бою
@export var pack_effects: Dictionary = {"broken_leg": "hurt_leg", "broken_arm": "hurt_arm", "luxation_arm": "hurt_arm",
	"blindness": "blinded", "broken_head": "concussed", "intoxication": "poisoned", "dysentery": "poisoned"}
@export var hazard_dice: String = "1d4"          # проклята клітинка на початку ходу
@export var encounter_cap_per_ally: float = 1.0
@export var encounter_cap_extra: int = 0
@export var arena: Dictionary = {
	"coast": {"tex": 1, "trees": 3, "rocks": 10, "difficult": 6, "glow": 0, "hills": 2},
	"forest": {"tex": 2, "trees": 34, "rocks": 4, "difficult": 14, "glow": 0, "hills": 1},
	"wasteland": {"tex": 5, "trees": 2, "rocks": 12, "difficult": 4, "glow": 0, "hills": 3},
	"swamp": {"tex": 6, "trees": 10, "rocks": 0, "difficult": 40, "glow": 0, "hills": 0},
	"mountains": {"tex": 7, "trees": 0, "rocks": 22, "difficult": 10, "glow": 0, "hills": 5},
	"hot": {"tex": 8, "trees": 0, "rocks": 20, "difficult": 10, "glow": 0, "hills": 5},
	"rad_forest": {"tex": 9, "trees": 28, "rocks": 4, "difficult": 12, "glow": 8, "hills": 1},
	"rad_wasteland": {"tex": 10, "trees": 2, "rocks": 12, "difficult": 4, "glow": 10, "hills": 3},
	"rad_swamp": {"tex": 11, "trees": 8, "rocks": 0, "difficult": 36, "glow": 8, "hills": 0},
}

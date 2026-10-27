class_name BattleArmor
extends Resource
## Броня: AC = base_ac + DEX (не больше dex_cap; −1 — без предела, 0 — DEX не идёт) + щит.
## dr — плоское снижение урона по типу (вычитается после броска, до сопротивления).

@export var id: String = ""
@export var title: String = ""
@export var base_ac: int = 10
@export var dex_cap: int = -1
@export var shield_bonus: int = 0
@export var dr: Dictionary = {}
## S_j (0..1) и V_j (≥0) по типу урона, если броня их даёт
@export var resist: Dictionary = {}
@export var vulnerable: Dictionary = {}
@export var stealth_disadvantage: bool = false
@export var good_vs: PackedStringArray = []
@export var weak_vs: PackedStringArray = []

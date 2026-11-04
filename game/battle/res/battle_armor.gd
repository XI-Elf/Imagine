class_name BattleArmor
extends Resource
## Броня: AC = base_ac + DEX (не більше dex_cap; −1 — без межі, 0 — DEX не йде) + щит.
## dr — пласке зниження шкоди за типом (віднімається після кидка, до опору).

@export var id: String = ""
@export var title: String = ""
@export var base_ac: int = 10
@export var dex_cap: int = -1
@export var shield_bonus: int = 0
@export var dr: Dictionary = {}
## S_j (0..1) і V_j (≥0) за типом шкоди, якщо броня їх дає
@export var resist: Dictionary = {}
@export var vulnerable: Dictionary = {}
@export var stealth_disadvantage: bool = false
@export var good_vs: PackedStringArray = []
@export var weak_vs: PackedStringArray = []

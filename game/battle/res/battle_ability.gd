class_name BattleAbility
extends Resource
## Способность или «заклинание» (в Амбере — алхимия, бомбы, приёмы). Механика:
## kind "attack" — бросок атаки против AC; "save" — цель бросает спасбросок против DC;
## "heal" — лечение; "self" — эффект на себя. Цель: enemy, ally, self, cell (по площади).

@export var id: String = ""
@export var title: String = ""
@export_multiline var description: String = ""
@export var cost: String = "action"              # action, bonus, reaction
@export var kind: String = "attack"
@export var target: String = "enemy"
@export var stat: String = "int"                 # характеристика атаки/DC
@export var range_ft: int = 30
@export var radius_ft: int = 0
@export var save_stat: String = "dex"
## Компоненты урона, как у оружия: [{type, dice, bonus}]; модификатор характеристики сюда не входит
@export var damage: Array = []
@export var penetration: Dictionary = {}
@export var attack_bonus: int = 0              # A_ATK
@export var half_on_save: bool = true
@export var heal_dice: String = ""
@export var heal_add_level: bool = false
@export var apply_effect: String = ""
@export var effect_on_fail_only: bool = true
@export var uses_per_battle: int = 0             # 0 — без ограничения
@export var proficient: bool = true

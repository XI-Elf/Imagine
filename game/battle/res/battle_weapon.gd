class_name BattleWeapon
extends Resource
## Зброя бою. Шкода — складники за типами (Combat_Formulas, розділ D): у кожного типу j свої кості Q_j і
## фіксований бонус F_j. Модифікатор характеристики йде один раз — у складник mod_component.

@export var id: String = ""
@export var title: String = ""
## Малюнок на картці: knife, sword, axe, club, mace, spear, cleaver, sling, bow, fist, torch, bite, tusk
@export var icon: String = ""
## [{type, dice, bonus}] — складники шкоди. Приклад сокири: [{slashing, 1d4}, {bludgeoning, 1d4}]
@export var damage: Array = [{"type": "bludgeoning", "dice": "1d4", "bonus": 0}]
@export var mod_component: int = 0
## P_j — частка пробиття броні за типом (0..1): {"piercing": 0.5}
@export var penetration: Dictionary = {}
## "str", "dex" або "finesse" (краща з двох)
@export var stat: String = "str"
@export var ranged: bool = false
@export var reach_ft: int = 5
@export var range_ft: int = 0
@export var long_range_ft: int = 0
@export var light: bool = false
@export var two_handed: bool = false
@export var ammo: int = 0                       # 0 — без ліку
@export var proficiency: String = "simple"      # simple, martial, natural
@export var attack_bonus: int = 0              # W_ATK
## Що робить влучання, крім шкоди: id ефекту й рятівний кидок проти нього (порожньо — нічого)
@export var on_hit_effect: String = ""
@export var on_hit_save: String = ""
@export var on_hit_dc: int = 0

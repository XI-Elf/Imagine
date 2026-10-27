class_name BattleWeapon
extends Resource
## Оружие боя. Урон — компоненты по типам (Combat_Formulas, раздел D): у каждого типа j свои кости Q_j и
## фиксированный бонус F_j. Модификатор характеристики идёт один раз — в компонент mod_component.

@export var id: String = ""
@export var title: String = ""
## Рисунок на карточке: knife, sword, axe, club, mace, spear, cleaver, sling, bow, fist, torch, bite, tusk
@export var icon: String = ""
## [{type, dice, bonus}] — компоненты урона. Пример топора: [{slashing, 1d4}, {bludgeoning, 1d4}]
@export var damage: Array = [{"type": "bludgeoning", "dice": "1d4", "bonus": 0}]
@export var mod_component: int = 0
## P_j — доля пробития брони по типу (0..1): {"piercing": 0.5}
@export var penetration: Dictionary = {}
## "str", "dex" или "finesse" (лучшая из двух)
@export var stat: String = "str"
@export var ranged: bool = false
@export var reach_ft: int = 5
@export var range_ft: int = 0
@export var long_range_ft: int = 0
@export var light: bool = false
@export var two_handed: bool = false
@export var ammo: int = 0                       # 0 — без счёта
@export var proficiency: String = "simple"      # simple, martial, natural
@export var attack_bonus: int = 0              # W_ATK
## Что делает попадание кроме урона: id эффекта и спасбросок против него (пусто — ничего)
@export var on_hit_effect: String = ""
@export var on_hit_save: String = ""
@export var on_hit_dc: int = 0

class_name BattleCreature
extends Resource
## Шаблон участника боя: враг, спутник или питомец. Характеристики — 7 (6 из D&D + Удача).

@export var id: String = ""
@export var title: String = ""
@export var human: bool = true
@export var pet: bool = false
@export var level: int = 1
## str dex con int wis cha lck — значения D&D (10 — средне)
@export var scores: Dictionary = {"str": 10, "dex": 10, "con": 10, "int": 10, "wis": 10, "cha": 10, "lck": 10}
@export var hp_dice: String = "2d8"              # HP = бросок + CON×уровень (как в 5e: 2d8+2)
@export var armor: String = ""                   # id брони; пусто — natural_ac + DEX
@export var natural_ac: int = 10
@export var weapons: PackedStringArray = []
@export var abilities: PackedStringArray = []
## S_j — доля сопротивления (0..1), V_j — доп. урон уязвимости (≥0), IMM_j — иммунитет
@export var resist: Dictionary = {}
@export var vulnerable: Dictionary = {}
@export var immune: PackedStringArray = []
@export var save_profs: PackedStringArray = []
@export var stealth_prof: bool = false
@export var perception_prof: bool = false
@export var speed_ft: int = 30
@export var ai: String = "melee"                 # melee, ranged, beast, support
@export var morale: float = 0.5                  # шанс держаться при HP ≤ четверти

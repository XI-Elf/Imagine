class_name BattleEffect
extends Resource
## Стан або ефект бою: збитий з ніг, отруєний, горить, кровотеча, ухилення, схований…
## Стани самі змінюють кидки: перевага/перешкода, AC, швидкість, автопровал рятівних кидків.

@export var id: String = ""
@export var title: String = ""
@export var duration_rounds: int = -1           # −1 — доки не знімуть
@export var attack_adv: bool = false             # свої атаки з перевагою
@export var attack_dis: bool = false             # свої атаки з перешкодою
@export var attack_dis_stat: String = ""         # перешкода лише на атаки цією характеристикою ("str")
@export var attacked_adv: bool = false           # атаки по ньому з перевагою
@export var attacked_dis: bool = false           # атаки по ньому з перешкодою
@export var melee_attacked_adv: bool = false     # збитий з ніг: ближні по ньому з перевагою,
@export var ranged_attacked_dis: bool = false    # дальні — з перешкодою
@export var incapacitated: bool = false          # не діє й не реагує
@export var speed_mult: float = 1.0
@export var ac_bonus: int = 0
@export var save_adv: PackedStringArray = []
@export var save_dis: PackedStringArray = []
@export var save_autofail: PackedStringArray = []
@export var turn_start_dice: String = ""         # шкода на початку ходу
@export var turn_start_type: String = ""
@export var end_save_stat: String = ""           # рятівний кидок наприкінці ходу, щоб зняти
@export var end_save_dc: int = 0
@export var ends_on_attack: bool = false         # скритність зникає після атаки
@export var stand_up_cost: bool = false          # підвестися — половина руху
@export var resist: Dictionary = {}              # S_j, поки ефект висить
@export var attack_penalty: int = 0              # PEN_ATK

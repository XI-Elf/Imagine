class_name BattleEffect
extends Resource
## Состояние или эффект боя: сбит с ног, отравлен, горит, кровотечение, уклонение, скрыт…
## Состояния сами меняют броски: преимущество/помеха, AC, скорость, автопровал спасбросков.

@export var id: String = ""
@export var title: String = ""
@export var duration_rounds: int = -1           # −1 — пока не снимут
@export var attack_adv: bool = false             # свои атаки с преимуществом
@export var attack_dis: bool = false             # свои атаки с помехой
@export var attack_dis_stat: String = ""         # помеха только на атаки этой характеристикой ("str")
@export var attacked_adv: bool = false           # атаки по нему с преимуществом
@export var attacked_dis: bool = false           # атаки по нему с помехой
@export var melee_attacked_adv: bool = false     # сбит с ног: ближние по нему с преимуществом,
@export var ranged_attacked_dis: bool = false    # дальние — с помехой
@export var incapacitated: bool = false          # не действует и не реагирует
@export var speed_mult: float = 1.0
@export var ac_bonus: int = 0
@export var save_adv: PackedStringArray = []
@export var save_dis: PackedStringArray = []
@export var save_autofail: PackedStringArray = []
@export var turn_start_dice: String = ""         # урон в начале хода
@export var turn_start_type: String = ""
@export var end_save_stat: String = ""           # спасбросок в конце хода, чтобы снять
@export var end_save_dc: int = 0
@export var ends_on_attack: bool = false         # скрытность пропадает после атаки
@export var stand_up_cost: bool = false          # встать — половина движения
@export var resist: Dictionary = {}              # S_j, пока эффект висит
@export var attack_penalty: int = 0              # PEN_ATK

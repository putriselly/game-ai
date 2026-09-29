class_name SkillData
extends Resource
## Describes one skill. The battle interprets these fields, so every skill in
## the design doc is just data (see [Roster]).

enum TargetMode { ENEMY, ALL_ENEMIES, ALLY, ALL_ALLIES, SELF }

@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var target_mode: TargetMode = TargetMode.ENEMY
@export var is_ultimate: bool = false

## Damage dealt to each target (0 = no damage).
@export var power: int = 0
## Damage used instead of [member power] when the target is burning (0 = off).
@export var power_if_target_burning: int = 0
## HP restored to each target.
@export var heal: int = 0
## Shield points granted to each target.
@export var shield: int = 0
## Burn applied to each target for this many turns (0 = none).
@export var burn_turns: int = 0
## Stun applied to each target for this many turns (0 = none).
@export var stun_turns: int = 0
## If > 0, [member stun_turns] is applied only while the user's HP ratio is
## below this value (Knight's Bump: stun only under 50% HP).
@export var stun_only_if_user_hp_below: float = 0.0


func targets_enemies() -> bool:
	return target_mode == TargetMode.ENEMY or target_mode == TargetMode.ALL_ENEMIES


func needs_target_pick() -> bool:
	return target_mode == TargetMode.ENEMY or target_mode == TargetMode.ALLY


static func make(values: Dictionary) -> SkillData:
	var s := SkillData.new()
	for key in values:
		s.set(key, values[key])
	return s

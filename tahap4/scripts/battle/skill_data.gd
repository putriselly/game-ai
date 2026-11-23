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

## --- PRECONDITIONS / EFFECTS (boss skills; what the planner reasons about) ---
## Flags the user must have, see [method UnitState.has_flag] (e.g. ["enraged"]).
@export var requires: Array[String] = []
## Flags the user must NOT have (e.g. ["enraged"] so a rage cannot be stacked).
@export var forbids: Array[String] = []
## Flags set on the user after the skill resolves.
@export var grants: Array[String] = []
## Flags removed from the user after the skill resolves (spent by the skill).
@export var consumes: Array[String] = []
## Damage used instead of [member power] while the user is enraged (0 = off).
@export var power_if_user_enraged: int = 0
## Usable once per battle; the use is recorded as flag [method used_flag].
@export var once_per_battle: bool = false
## If > 0, the skill is offered only while the user's HP ratio is below this.
@export var only_if_user_hp_below: float = 0.0


func targets_enemies() -> bool:
	return target_mode == TargetMode.ENEMY or target_mode == TargetMode.ALL_ENEMIES


func needs_target_pick() -> bool:
	return target_mode == TargetMode.ENEMY or target_mode == TargetMode.ALLY


## Flag that marks a [member once_per_battle] skill as spent.
func used_flag() -> String:
	return "used_" + id


## True when the skill carries any precondition or status effect.
func has_preconditions() -> bool:
	return not requires.is_empty() or not forbids.is_empty() \
		or once_per_battle or only_if_user_hp_below > 0.0


static func make(values: Dictionary) -> SkillData:
	var s := SkillData.new()
	for key in values:
		var value = values[key]
		if value is Array and not (value as Array).is_typed():
			# Plain string lists in the roster become the typed Array[String].
			var typed: Array[String] = []
			typed.assign(value)
			s.set(key, typed)
		else:
			s.set(key, value)
	return s

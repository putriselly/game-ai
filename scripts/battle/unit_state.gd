class_name UnitState
extends RefCounted
## Plain-data snapshot of one combatant. This is what the search clones and
## mutates; the on-screen [BattleUnit] only displays it.

var data: UnitData
var side: int = 0     # BattleSim.PLAYER or BattleSim.NPC
var index: int = 0    # position in BattleSim.units
var hp: int = 0
var shield: int = 0
var ult: int = 0
var burn: int = 0     # remaining burn turns
var stun: int = 0     # remaining stunned turns
var stun_immune: int = 0  # turns during which a new stun is resisted
## Named statuses granted/consumed by skills ("enraged", "phase2",
## "used_regrow", ...). Query through [method has_flag], which also answers
## the derived flags listed there.
var flags: Dictionary = {}

## HP ratio below which a unit counts as "low_hp" (and a boss enters phase 2).
const LOW_HP_RATIO := 0.5


static func create(unit_data: UnitData, unit_side: int, unit_index: int, start_hp: int = -1) -> UnitState:
	var u := UnitState.new()
	u.data = unit_data
	u.side = unit_side
	u.index = unit_index
	u.hp = unit_data.max_hp if start_hp < 0 else clampi(start_hp, 1, unit_data.max_hp)
	return u


func clone() -> UnitState:
	var u := UnitState.new()
	u.data = data
	u.side = side
	u.index = index
	u.hp = hp
	u.shield = shield
	u.ult = ult
	u.burn = burn
	u.stun = stun
	u.stun_immune = stun_immune
	u.flags = flags.duplicate()
	return u


func is_alive() -> bool:
	return hp > 0


func is_burning() -> bool:
	return burn > 0


func is_stunned() -> bool:
	return stun > 0


func hp_ratio() -> float:
	return float(hp) / float(data.max_hp)


func ult_ready() -> bool:
	return ult >= BattleSim.ULT_MAX


func display_name() -> String:
	return data.display_name


## Status predicate used by skill preconditions and by the planner. Stored
## flags plus derived ones: alive, shielded, burning, stunned, ult_ready, low_hp.
func has_flag(flag: String) -> bool:
	match flag:
		"alive":
			return is_alive()
		"shielded":
			return shield > 0
		"burning":
			return is_burning()
		"stunned":
			return is_stunned()
		"ult_ready":
			return ult_ready()
		"low_hp":
			return hp_ratio() < LOW_HP_RATIO
	return flags.has(flag)


func set_flag(flag: String) -> void:
	flags[flag] = true


func clear_flag(flag: String) -> void:
	flags.erase(flag)


## Stored flags, sorted (for describe() and the overlay).
func flag_names() -> Array:
	var names := flags.keys()
	names.sort()
	return names

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

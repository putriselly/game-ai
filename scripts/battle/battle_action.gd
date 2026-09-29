class_name BattleAction
extends RefCounted
## One move in the search tree: a unit uses a skill on some targets.
## A "pass" action (unit == -1) is generated only when a side cannot act.

var unit: int = -1
var skill: SkillData = null
var targets: Array[int] = []


static func make(unit_index: int, unit_skill: SkillData, target_indices: Array[int]) -> BattleAction:
	var a := BattleAction.new()
	a.unit = unit_index
	a.skill = unit_skill
	a.targets = target_indices
	return a


static func pass_action() -> BattleAction:
	return BattleAction.new()


func is_pass() -> bool:
	return unit < 0 or skill == null


func describe(sim: BattleSim) -> String:
	if is_pass():
		return "Pass"
	var text := "%s: %s" % [sim.units[unit].display_name(), skill.display_name]
	if targets.size() == 1 and skill.needs_target_pick():
		text += " -> " + sim.units[targets[0]].display_name()
	return text


func same_as(other: BattleAction) -> bool:
	return unit == other.unit and skill == other.skill and targets == other.targets

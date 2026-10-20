class_name UnitData
extends Resource
## Static definition of a combatant: stats, sprite and skill list.
## [member skills][0] is the basic skill; the entry with is_ultimate is the
## ultimate. Bosses may carry more than two skills.

@export var id: String = ""
@export var display_name: String = ""
@export var max_hp: int = 30
@export_dir var sprite_folder: String = ""
@export var skills: Array[SkillData] = []
@export var is_boss: bool = false
## Ultimate charge gained per target hit (bar is 0..100).
@export var ult_per_hit: int = 25
## Who this unit prefers to attack when the battle runs with
## [constant BattleSim.TargetRule.PER_UNIT] (WEAKEST, THREAT or TOUGHEST).
@export var preferred_target: BattleSim.TargetRule = BattleSim.TargetRule.WEAKEST


func basic_skills() -> Array[SkillData]:
	var out: Array[SkillData] = []
	for s in skills:
		if not s.is_ultimate:
			out.append(s)
	return out


func ultimate() -> SkillData:
	for s in skills:
		if s.is_ultimate:
			return s
	return null

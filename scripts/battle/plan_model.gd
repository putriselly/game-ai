class_name PlanModel
extends RefCounted
## AUTOMATED PLANNING model of the boss's turns (Tahap 4).
##
## The planner never searches the live [BattleSim]. It reasons over an
## abstract [PlanState] with STRIPS-style operators grounded from the boss's
## skills: PRECONDITIONS come from [member SkillData.requires] / forbids /
## once_per_battle / only_if_user_hp_below (plus the ultimate rule and the
## potion stock), EFFECTS are damage, heal, shield, burn and the flags the
## skill grants or consumes, with HP as a numeric fluent.
##
## The world is RELAXED: the player is assumed to pass between boss actions,
## so one plan step = boss action + the two turn boundaries (hero burn ticks,
## boss burn tick, phase-2 check). BattleSim stays the ground truth: the tests
## check that [method apply] predicts exactly what the simulation does when
## the player passes, and the executor re-checks every step on the real state
## ([method holds_in_sim]) before playing it, replanning when it fails.

const ELEMENT_KB = preload("res://scripts/battle/element_kb.gd")

## Literal predicates understood by [method PlanState.holds] besides flags.
const BUILTIN_PREDICATES: Array[String] = ["alive", "dead", "burning", "shielded", "low_hp", "ult_ready"]


## Abstract state: only what the boss's skills can read or change.
class PlanState:
	var sim: BattleSim          ## static data (unit data, sides, modes); never mutated
	var actor: int = -1         ## the planning unit (the boss)
	var hp: Dictionary = {}     ## unit index -> hp (0 when dead)
	var shield: Dictionary = {} ## unit index -> shield points
	var burn: Dictionary = {}   ## unit index -> burn turns left
	var flags: Dictionary = {}  ## unit index -> {flag: true}
	var ult: int = 0            ## actor's ultimate charge
	var potions: int = 0        ## potions of the actor's side
	var actor_stunned := false  ## a stunned boss has no actions this turn

	func clone() -> PlanState:
		var s := PlanState.new()
		s.sim = sim
		s.actor = actor
		s.hp = hp.duplicate()
		s.shield = shield.duplicate()
		s.burn = burn.duplicate()
		for i in flags:
			s.flags[i] = flags[i].duplicate()
		s.ult = ult
		s.potions = potions
		s.actor_stunned = actor_stunned
		return s

	func side_of(i: int) -> int:
		return sim.units[i].side

	func max_hp(i: int) -> int:
		return sim.units[i].data.max_hp

	func is_alive(i: int) -> bool:
		return hp.get(i, 0) > 0

	func hp_ratio(i: int) -> float:
		return float(hp.get(i, 0)) / float(max_hp(i))

	func alive_units(side: int) -> Array[int]:
		var out: Array[int] = []
		for i in range(sim.units.size()):
			if side_of(i) == side and is_alive(i):
				out.append(i)
		return out

	## Mirror of [method UnitState.has_flag] on the abstract state.
	func has_flag(i: int, flag: String) -> bool:
		match flag:
			"alive":
				return is_alive(i)
			"dead":
				return not is_alive(i)
			"shielded":
				return shield.get(i, 0) > 0
			"burning":
				return burn.get(i, 0) > 0
			"stunned":
				return i == actor and actor_stunned
			"ult_ready":
				return i == actor and ult >= BattleSim.ULT_MAX
			"low_hp":
				return hp_ratio(i) < UnitState.LOW_HP_RATIO
		return flags.get(i, {}).has(flag)

	func set_flag(i: int, flag: String) -> void:
		if not flags.has(i):
			flags[i] = {}
		flags[i][flag] = true

	func clear_flag(i: int, flag: String) -> void:
		if flags.has(i):
			flags[i].erase(flag)

	## A literal is "pred(unit)" or "not pred(unit)"; pred is a builtin
	## predicate or a flag name, unit a unit index.
	func holds(literal: String) -> bool:
		var parsed := PlanModel.parse_literal(literal)
		var value := has_flag(parsed["unit"], parsed["pred"])
		return not value if parsed["neg"] else value

	func holds_all(literals: Array) -> bool:
		for l in literals:
			if not holds(l):
				return false
		return true

	## Number of literals in [param literals] that do not hold (goal-count heuristic).
	func unsatisfied(literals: Array) -> int:
		var n := 0
		for l in literals:
			if not holds(l):
				n += 1
		return n

	## Canonical string: equal states have equal keys (closed list / visited set).
	func key() -> String:
		var parts: PackedStringArray = []
		for i in range(sim.units.size()):
			var f: Array = flags.get(i, {}).keys()
			f.sort()
			parts.append("%d:%d/%d/%d/%s" % [i, hp.get(i, 0), shield.get(i, 0), burn.get(i, 0), ",".join(PackedStringArray(f))])
		parts.append("ult%d pot%d%s" % [ult, potions, " stun" if actor_stunned else ""])
		return " ".join(parts)

	func equals(other: PlanState) -> bool:
		return key() == other.key()

	func describe() -> String:
		var parts: PackedStringArray = []
		for i in range(sim.units.size()):
			var u := sim.units[i]
			var tags := ""
			if shield.get(i, 0) > 0:
				tags += " sh%d" % shield[i]
			if burn.get(i, 0) > 0:
				tags += " burn%d" % burn[i]
			for f in flags.get(i, {}).keys():
				tags += " " + f
			parts.append("%s%s(%d%s)" % ["P" if u.side == BattleSim.PLAYER else "N", u.display_name(), hp.get(i, 0), tags])
		return "ult%d potions%d: %s" % [ult, potions, " ".join(parts)]

	## Writes the abstract state back into a clone of the simulation (used to
	## score plan end states with [BattleEvaluator]).
	func to_sim() -> BattleSim:
		var out := sim.clone()
		for i in range(out.units.size()):
			var u := out.units[i]
			u.hp = hp.get(i, 0)
			u.shield = shield.get(i, 0)
			u.burn = burn.get(i, 0)
			u.flags = flags.get(i, {}).duplicate()
			if not u.is_alive():
				u.stun = 0
		out.units[actor].ult = ult
		out.potions[side_of(actor)] = potions
		out.side_to_move = side_of(actor)
		return out


## One grounded operator: the actor uses a skill on concrete targets.
class PlanAction:
	var actor: int = -1
	var skill: SkillData
	var targets: Array[int] = []

	static func make(actor_index: int, action_skill: SkillData, target_indices: Array[int]) -> PlanAction:
		var a := PlanAction.new()
		a.actor = actor_index
		a.skill = action_skill
		a.targets = target_indices
		return a

	## Stable identifier, e.g. "bamboo_spear(3)".
	func id() -> String:
		var t: PackedStringArray = []
		for i in targets:
			t.append(str(i))
		return "%s(%s)" % [skill.id, ",".join(t)]

	func describe(state: PlanState) -> String:
		var text := skill.display_name
		if targets.size() == 1 and skill.needs_target_pick():
			text += " -> " + state.sim.units[targets[0]].display_name()
		return text

	func same_as(other: PlanAction) -> bool:
		return actor == other.actor and skill == other.skill and targets == other.targets

	func to_battle_action() -> BattleAction:
		return BattleAction.make(actor, skill, targets.duplicate())


# --- Construction ---------------------------------------------------------------

## Snapshot of [param sim] for planning unit [param actor] (default: the first
## living boss on the NPC side, else the first living NPC unit).
static func from_sim(sim: BattleSim, actor: int = -1) -> PlanState:
	var s := PlanState.new()
	s.sim = sim
	if actor < 0:
		for u in sim.alive_units(BattleSim.NPC):
			if u.data.is_boss:
				actor = u.index
				break
		if actor < 0 and not sim.alive_units(BattleSim.NPC).is_empty():
			actor = sim.alive_units(BattleSim.NPC)[0].index
	s.actor = actor
	for u in sim.units:
		s.hp[u.index] = maxi(u.hp, 0)
		s.shield[u.index] = u.shield
		s.burn[u.index] = u.burn
		if not u.flags.is_empty():
			s.flags[u.index] = u.flags.duplicate()
	if actor >= 0:
		var boss := sim.units[actor]
		s.ult = boss.ult
		s.potions = sim.potions[boss.side]
		s.actor_stunned = boss.is_stunned()
	return s


static func parse_literal(literal: String) -> Dictionary:
	var text := literal.strip_edges()
	var neg := false
	if text.begins_with("not "):
		neg = true
		text = text.substr(4).strip_edges()
	elif text.begins_with("!"):
		neg = true
		text = text.substr(1).strip_edges()
	var open := text.find("(")
	var pred := text.substr(0, open) if open >= 0 else text
	var unit := -1
	if open >= 0:
		unit = int(text.substr(open + 1, text.length() - open - 2))
	return {"neg": neg, "pred": pred, "unit": unit}


# --- Preconditions (mirror of BattleSim.usable_skills / legal_actions) -----------

static func skill_available(state: PlanState, skill: SkillData) -> bool:
	var a := state.actor
	for flag in skill.requires:
		if not state.has_flag(a, flag):
			return false
	for flag in skill.forbids:
		if state.has_flag(a, flag):
			return false
	if skill.once_per_battle and state.has_flag(a, skill.used_flag()):
		return false
	if skill.only_if_user_hp_below > 0.0 and state.hp_ratio(a) >= skill.only_if_user_hp_below:
		return false
	return true


static func usable_skills(state: PlanState) -> Array[SkillData]:
	var out: Array[SkillData] = []
	var data := state.sim.units[state.actor].data
	var ultimate := data.ultimate()
	if state.ult >= BattleSim.ULT_MAX and ultimate != null and skill_available(state, ultimate):
		out.append(ultimate)
		if state.sim.ultimate_mode == BattleSim.UltimateMode.AUTO:
			return out
	for s in data.basic_skills():
		if skill_available(state, s):
			out.append(s)
	return out


## All applicable grounded actions of the actor (every living target is a
## separate action, like BattleSim with full targeting).
static func ground_actions(state: PlanState) -> Array[PlanAction]:
	var out: Array[PlanAction] = []
	var a := state.actor
	if a < 0 or not state.is_alive(a) or state.actor_stunned:
		return out
	var side := state.side_of(a)
	for skill in usable_skills(state):
		if BattleSim.consumes_potion(skill) and state.potions <= 0:
			continue
		match skill.target_mode:
			SkillData.TargetMode.ENEMY:
				for t in state.alive_units(BattleSim.other(side)):
					out.append(PlanAction.make(a, skill, [t]))
			SkillData.TargetMode.ALL_ENEMIES:
				var foes := state.alive_units(BattleSim.other(side))
				if not foes.is_empty():
					out.append(PlanAction.make(a, skill, foes))
			SkillData.TargetMode.ALLY:
				for t in state.alive_units(side):
					if skill.heal > 0 and state.hp[t] >= state.max_hp(t):
						continue
					out.append(PlanAction.make(a, skill, [t]))
			SkillData.TargetMode.ALL_ALLIES:
				var friends := state.alive_units(side)
				var any_hurt := false
				for t in friends:
					any_hurt = any_hurt or state.hp[t] < state.max_hp(t)
				if skill.heal > 0 and not any_hurt:
					continue
				out.append(PlanAction.make(a, skill, friends))
			SkillData.TargetMode.SELF:
				out.append(PlanAction.make(a, skill, [a]))
	return out


static func applicable(state: PlanState, action: PlanAction) -> bool:
	for candidate in ground_actions(state):
		if candidate.same_as(action):
			return true
	return false


## Execution monitoring: is [param action] still applicable on the real state?
static func holds_in_sim(sim: BattleSim, action: PlanAction) -> bool:
	return applicable(from_sim(sim, action.actor), action)


# --- Effects (mirror of BattleSim.apply with a passing player) --------------------

## Damage before shields: rage / burn overrides, then the element multiplier.
static func predicted_damage(state: PlanState, skill: SkillData, target: int) -> int:
	var damage := skill.power
	if skill.power_if_user_enraged > 0 and state.has_flag(state.actor, "enraged"):
		damage = skill.power_if_user_enraged
	if skill.power_if_target_burning > 0 and state.has_flag(target, "burning"):
		damage = skill.power_if_target_burning
	var status: Variant = ELEMENT_KB.get_element_status(
		state.sim.units[state.actor].data.element, state.sim.units[target].data.element)
	if status == ELEMENT_KB.STRENGTH:
		damage = roundi(damage * BattleSim.STRENGTH_MULTIPLIER)
	elif status == ELEMENT_KB.WEAKNESS:
		damage = roundi(damage * BattleSim.WEAKNESS_MULTIPLIER)
	return damage


## Successor state: the skill resolves (hit assumed), the actor's flags are
## updated, then both turn boundaries pass with a passive opponent.
static func apply(state: PlanState, action: PlanAction) -> PlanState:
	var s := state.clone()
	var a := s.actor
	var skill := action.skill
	if skill.is_ultimate:
		s.ult = 0
	if BattleSim.consumes_potion(skill):
		s.potions = maxi(0, s.potions - 1)
	var hits := 0
	for t in action.targets:
		if not s.is_alive(t):
			continue
		var damage := predicted_damage(s, skill, t)
		if damage > 0:
			var absorbed: int = mini(s.shield.get(t, 0), damage)
			s.shield[t] = s.shield.get(t, 0) - absorbed
			var lost: int = mini(damage - absorbed, s.hp[t])
			s.hp[t] -= lost
			if not s.is_alive(t):
				s.burn[t] = 0
		hits += 1
		if skill.heal > 0:
			s.hp[t] = mini(s.hp[t] + skill.heal, s.max_hp(t))
		if skill.shield > 0:
			s.shield[t] = s.shield.get(t, 0) + skill.shield
		if skill.burn_turns > 0 and s.is_alive(t):
			s.burn[t] = maxi(s.burn.get(t, 0), skill.burn_turns)
		# Stuns are not modelled: no boss skill stuns.
	for flag in skill.consumes:
		s.clear_flag(a, flag)
	for flag in skill.grants:
		s.set_flag(a, flag)
	if skill.once_per_battle:
		s.set_flag(a, skill.used_flag())
	if hits > 0 and not skill.is_ultimate:
		s.ult = mini(s.ult + BattleSim.ULT_PER_HIT, BattleSim.ULT_MAX)
	# Opponent's turn begins (their burns tick), they pass, our turn begins.
	var side := s.side_of(a)
	_begin_turn(s, BattleSim.other(side))
	_begin_turn(s, side)
	return s


static func _begin_turn(s: PlanState, side: int) -> void:
	for i in s.alive_units(side):
		if s.burn.get(i, 0) > 0:
			s.hp[i] = maxi(0, s.hp[i] - BattleSim.BURN_DAMAGE)
			s.burn[i] -= 1
			if not s.is_alive(i):
				s.burn[i] = 0
	for i in s.alive_units(side):
		if s.sim.units[i].data.is_boss and not s.has_flag(i, "phase2") and s.has_flag(i, "low_hp"):
			s.set_flag(i, "phase2")

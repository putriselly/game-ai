class_name BattleSim
extends RefCounted
## Pure, cloneable battle model. Holds the complete game STATE and implements
## the rules (ACTIONS, transition, TERMINAL TEST, UTILITY). No nodes, no
## animation: the visual [Battle] drives one instance and asks it what
## happened, the AI clones it thousands of times.
##
## Turn structure: sides alternate; on its turn a side performs exactly ONE
## action (one unit uses one skill), so the branching factor is at most the
## number of living, un-stunned units on that side (<= 4).

const PLAYER := 0
const NPC := 1

const ULT_MAX := 100
const ULT_PER_HIT := 25
const BURN_DAMAGE := 2
const WIN_SCORE := 1000.0
## Each side starts with this many potions; a basic healing skill consumes one.
const POTIONS_PER_SIDE := 3

## AUTO: a unit whose bar is full always fires the ultimate (branching <= 4).
## CHOICE: basic skill and ultimate are both offered (branching <= 8).
enum UltimateMode { AUTO, CHOICE }
## Fixed targeting rule for damage skills (used when full_targeting is off).
## WEAKEST: lowest HP first. THREAT: most dangerous unit first (see threat_of).
## TOUGHEST: highest HP first (spreads damage; good for burns). PER_UNIT: every
## unit follows its own [member UnitData.preferred_target], so different
## enemies pick different heroes. For THREAT and TOUGHEST a target that can
## be killed right now always comes first.
enum TargetRule { WEAKEST, THREAT, TOUGHEST, PER_UNIT }

var units: Array[UnitState] = []
var side_to_move: int = PLAYER
var turn: int = 0
## Potions left per side (index = side). Part of the state, like HP.
var potions: Array[int] = [POTIONS_PER_SIDE, POTIONS_PER_SIDE]
## false: targets are fixed by [method default_targets] (branching <= units).
## true: every valid target is a separate action (branching <= units x targets).
var full_targeting: bool = false
var target_rule: TargetRule = TargetRule.WEAKEST
## Game is declared a draw after this many actions (keeps the tree finite).
var max_turns: int = 80
## Probability that a damaging skill connects. 1.0 = deterministic game.
var hit_chance: float = 1.0
var ultimate_mode: UltimateMode = UltimateMode.AUTO
var rng := RandomNumberGenerator.new()


# --- Construction ---------------------------------------------------------------

static func create(player_ids: Array[String], npc_ids: Array[String], party_hp: Dictionary = {}) -> BattleSim:
	var sim := BattleSim.new()
	for id in player_ids:
		sim.add_unit(Roster.get_unit(id), PLAYER, party_hp.get(id, -1))
	for id in npc_ids:
		sim.add_unit(Roster.get_unit(id), NPC)
	sim.rng.randomize()
	return sim


func add_unit(data: UnitData, side: int, start_hp: int = -1) -> UnitState:
	var u := UnitState.create(data, side, units.size(), start_hp)
	units.append(u)
	return u


func clone() -> BattleSim:
	var sim := BattleSim.new()
	for u in units:
		sim.units.append(u.clone())
	sim.side_to_move = side_to_move
	sim.turn = turn
	sim.max_turns = max_turns
	sim.hit_chance = hit_chance
	sim.ultimate_mode = ultimate_mode
	sim.potions = potions.duplicate()
	sim.full_targeting = full_targeting
	sim.target_rule = target_rule
	sim.rng = rng  # shared: search never rolls, only the live game does
	return sim


# --- Queries ------------------------------------------------------------------------

static func other(side: int) -> int:
	return NPC if side == PLAYER else PLAYER


func side_units(side: int) -> Array[UnitState]:
	var out: Array[UnitState] = []
	for u in units:
		if u.side == side:
			out.append(u)
	return out


func alive_units(side: int) -> Array[UnitState]:
	var out: Array[UnitState] = []
	for u in units:
		if u.side == side and u.is_alive():
			out.append(u)
	return out


func total_hp(side: int) -> int:
	var sum := 0
	for u in units:
		if u.side == side:
			sum += u.hp
	return sum


func total_max_hp(side: int) -> int:
	var sum := 0
	for u in units:
		if u.side == side:
			sum += u.data.max_hp
	return sum


## TERMINAL TEST: one side has no living unit, or the turn limit is reached.
func is_terminal() -> bool:
	return winner() != -1 or turn >= max_turns


## Returns PLAYER / NPC, or -1 when nobody has won (yet, or draw).
func winner() -> int:
	var p := alive_units(PLAYER).size()
	var n := alive_units(NPC).size()
	if p == 0 and n == 0:
		return -1
	if n == 0:
		return PLAYER
	if p == 0:
		return NPC
	return -1


## UTILITY of a terminal state from [param side]'s point of view.
## Winning faster / healthier scores higher; a draw (turn limit) is 0.
func utility(side: int) -> float:
	var w := winner()
	if w == -1:
		return 0.0
	if w == side:
		return WIN_SCORE + total_hp(side)
	return -(WIN_SCORE + total_hp(w))


# --- Actions ------------------------------------------------------------------------

## ACTIONS available to [param side]: one per (living, un-stunned unit, usable
## skill). Targets are fixed by [method default_targets] so the branching stays
## small; a Pass is offered only when nothing else is possible.
func legal_actions(side: int = -1) -> Array[BattleAction]:
	if side == -1:
		side = side_to_move
	var actions: Array[BattleAction] = []
	for u in alive_units(side):
		if u.is_stunned():
			continue
		for skill in usable_skills(u):
			if consumes_potion(skill) and potions[side] <= 0:
				continue
			if full_targeting and skill.needs_target_pick():
				for t in candidate_targets(u, skill):
					actions.append(BattleAction.make(u.index, skill, [t]))
				continue
			var targets := default_targets(u, skill)
			if targets.is_empty():
				continue
			actions.append(BattleAction.make(u.index, skill, targets))
	if actions.is_empty():
		actions.append(BattleAction.pass_action())
	return actions


## Basic (non-ultimate) healing skills drink one of the side's potions.
static func consumes_potion(skill: SkillData) -> bool:
	return skill.heal > 0 and not skill.is_ultimate


## Every sensible target of a single-target skill (used by full targeting and
## by the player's UI): living opponents, or living allies that are wounded
## for heals.
func candidate_targets(user: UnitState, skill: SkillData) -> Array[int]:
	var out: Array[int] = []
	if skill.targets_enemies():
		for f in alive_units(other(user.side)):
			out.append(f.index)
	else:
		for f in alive_units(user.side):
			if skill.heal > 0 and f.hp >= f.data.max_hp:
				continue
			out.append(f.index)
	return out


func usable_skills(u: UnitState) -> Array[SkillData]:
	var out: Array[SkillData] = []
	var ultimate := u.data.ultimate()
	if u.ult_ready() and ultimate != null:
		out.append(ultimate)
		if ultimate_mode == UltimateMode.AUTO:
			return out
	for s in u.data.basic_skills():
		out.append(s)
	return out


## Rule-based targeting used by the search (and as the AI's own choice):
## damage -> by [member target_rule] (burning ones first for Explode),
## heal -> most wounded ally that is actually hurt, shield -> most wounded ally.
func default_targets(user: UnitState, skill: SkillData) -> Array[int]:
	var out: Array[int] = []
	match skill.target_mode:
		SkillData.TargetMode.ENEMY:
			var foes := alive_units(other(user.side))
			if foes.is_empty():
				return out
			var best: UnitState = foes[0]
			for f in foes:
				if _better_attack_target(f, best, skill, user):
					best = f
			out.append(best.index)
		SkillData.TargetMode.ALL_ENEMIES:
			for f in alive_units(other(user.side)):
				out.append(f.index)
		SkillData.TargetMode.ALLY:
			var friends := alive_units(user.side)
			var best: UnitState = null
			for f in friends:
				if skill.heal > 0 and f.hp >= f.data.max_hp:
					continue  # healing a full-HP ally is never useful
				if best == null or f.hp_ratio() < best.hp_ratio():
					best = f
			if best != null:
				out.append(best.index)
		SkillData.TargetMode.ALL_ALLIES:
			var any_hurt := false
			for f in alive_units(user.side):
				out.append(f.index)
				any_hurt = any_hurt or f.hp < f.data.max_hp
			if skill.heal > 0 and not any_hurt:
				out.clear()
		SkillData.TargetMode.SELF:
			out.append(user.index)
	return out


## The rule a given attacker follows.
func rule_for(user: UnitState) -> TargetRule:
	if target_rule == TargetRule.PER_UNIT:
		return user.data.preferred_target
	return target_rule


func _better_attack_target(candidate: UnitState, current: UnitState, skill: SkillData, user: UnitState) -> bool:
	if skill.power_if_target_burning > 0 and candidate.is_burning() != current.is_burning():
		return candidate.is_burning()
	var rule := rule_for(user)
	if rule != TargetRule.WEAKEST:
		# A kill now beats any preference.
		var damage := maxi(skill.power, skill.power_if_target_burning if candidate.is_burning() else 0)
		var can_kill_candidate := candidate.hp + candidate.shield <= damage
		var can_kill_current := current.hp + current.shield <= damage
		if can_kill_candidate != can_kill_current:
			return can_kill_candidate
	match rule:
		TargetRule.THREAT:
			var tc := threat_of(candidate)
			var tu := threat_of(current)
			if not is_equal_approx(tc, tu):
				return tc > tu
		TargetRule.TOUGHEST:
			if candidate.hp != current.hp:
				return candidate.hp > current.hp
	return candidate.hp < current.hp


## THREAT MODEL: expected value of one action by [param u], in HP-equivalents.
## Basic skills count fully; the ultimate counts in proportion to its charge.
## Multi-target skills are multiplied by the number of living opponents.
func threat_of(u: UnitState) -> float:
	if not u.is_alive():
		return 0.0
	var foes := alive_units(other(u.side)).size()
	var allies := alive_units(u.side).size()
	var total := 0.0
	var basics := u.data.basic_skills()
	for skill in basics:
		total += _skill_value(skill, u, foes, allies)
	if not basics.is_empty():
		total /= basics.size()
	var ultimate := u.data.ultimate()
	if ultimate != null:
		total += _skill_value(ultimate, u, foes, allies) * float(u.ult) / float(ULT_MAX)
	return total


func _skill_value(skill: SkillData, user: UnitState, foes: int, allies: int) -> float:
	var value := 0.0
	value += maxf(skill.power, skill.power_if_target_burning * 0.5)
	value += skill.burn_turns * BURN_DAMAGE
	value += skill.heal * 0.8 + skill.shield * 0.8
	if skill.stun_turns > 0 and (skill.stun_only_if_user_hp_below <= 0.0 or user.hp_ratio() < skill.stun_only_if_user_hp_below):
		value += 6.0 * skill.stun_turns
	if skill.target_mode == SkillData.TargetMode.ALL_ENEMIES:
		value *= foes
	elif skill.target_mode == SkillData.TargetMode.ALL_ALLIES:
		value *= allies
	return value


## Whether [param action] has a random outcome (only when hit_chance < 1).
func is_chance_action(action: BattleAction) -> bool:
	return hit_chance < 1.0 and not action.is_pass() and action.skill.power > 0


# --- Transition ---------------------------------------------------------------------

## Applies [param action] for the side to move, then hands the turn over.
## [param forced_hit]: -1 = roll the dice (live game), 1 = hit, 0 = miss
## (the search never rolls; expectimax expands both outcomes).
## Returns a list of event dictionaries for the presentation layer.
func apply(action: BattleAction, forced_hit: int = -1) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var side := side_to_move
	if not action.is_pass():
		var user := units[action.unit]
		var targets: Array[UnitState] = []
		for i in action.targets:
			targets.append(units[i])
		var hit := true
		if is_chance_action(action):
			hit = (rng.randf() < hit_chance) if forced_hit < 0 else forced_hit == 1
		events.append_array(apply_skill(user, action.skill, targets, hit))
	else:
		events.append({"type": "pass", "unit": -1})
	end_turn(side)
	turn += 1
	side_to_move = other(side)
	events.append_array(begin_turn(side_to_move))
	return events


## The RULES. Shared by the live battle and the search.
func apply_skill(user: UnitState, skill: SkillData, targets: Array[UnitState], hit: bool = true) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	events.append({"type": "use", "unit": user.index, "skill": skill, "targets": targets.map(func(t): return t.index)})
	if skill.is_ultimate:
		user.ult = 0
	if consumes_potion(skill):
		potions[user.side] = maxi(0, potions[user.side] - 1)
		events.append({"type": "potion", "unit": user.index, "left": potions[user.side]})
	var hits := 0
	for target in targets:
		if not target.is_alive():
			continue
		var damage := skill.power
		if skill.power_if_target_burning > 0 and target.is_burning():
			damage = skill.power_if_target_burning
		if damage > 0:
			if not hit:
				events.append({"type": "miss", "unit": user.index, "target": target.index})
				continue
			var absorbed := mini(target.shield, damage)
			target.shield -= absorbed
			var lost := mini(damage - absorbed, target.hp)
			target.hp -= lost
			events.append({"type": "damage", "unit": user.index, "target": target.index,
				"amount": damage, "lost": lost, "absorbed": absorbed})
			if not target.is_alive():
				target.burn = 0
				target.stun = 0
				events.append({"type": "death", "unit": target.index})
		hits += 1
		if skill.heal > 0:
			var healed := mini(skill.heal, target.data.max_hp - target.hp)
			target.hp += healed
			events.append({"type": "heal", "unit": user.index, "target": target.index, "amount": healed})
		if skill.shield > 0:
			target.shield += skill.shield
			events.append({"type": "shield", "unit": user.index, "target": target.index, "amount": skill.shield})
		if skill.burn_turns > 0 and target.is_alive():
			target.burn = maxi(target.burn, skill.burn_turns)  # no stacking
			events.append({"type": "burn", "unit": user.index, "target": target.index, "turns": target.burn})
		if skill.stun_turns > 0 and target.is_alive():
			var allowed := skill.stun_only_if_user_hp_below <= 0.0 \
				or user.hp_ratio() < skill.stun_only_if_user_hp_below
			if allowed and target.stun_immune > 0:
				events.append({"type": "resist", "unit": user.index, "target": target.index})
			elif allowed:
				target.stun = maxi(target.stun, skill.stun_turns)
				events.append({"type": "stun", "unit": user.index, "target": target.index, "turns": target.stun})
	if hits > 0 and not skill.is_ultimate:
		user.ult = mini(user.ult + ULT_PER_HIT, ULT_MAX)
	return events


## Start of [param side]'s turn: burning units take damage.
func begin_turn(side: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for u in alive_units(side):
		if u.burn > 0:
			var lost := mini(BURN_DAMAGE, u.hp)
			u.hp -= lost
			u.burn -= 1
			events.append({"type": "burn_tick", "unit": u.index, "amount": lost})
			if not u.is_alive():
				u.burn = 0
				u.stun = 0
				events.append({"type": "death", "unit": u.index})
	return events


## End of [param side]'s turn: stuns on that side wear off by one. A unit
## whose stun just ended resists stuns for one turn, so a single attacker
## cannot stun-lock the opponent forever.
func end_turn(side: int) -> void:
	for u in side_units(side):
		if u.stun_immune > 0:
			u.stun_immune -= 1
		if u.stun > 0:
			u.stun -= 1
			if u.stun == 0:
				u.stun_immune = 1


func describe() -> String:
	var parts: PackedStringArray = []
	for u in units:
		var tags := ""
		if u.shield > 0:
			tags += " sh%d" % u.shield
		if u.burn > 0:
			tags += " burn%d" % u.burn
		if u.stun > 0:
			tags += " stun%d" % u.stun
		if u.stun_immune > 0:
			tags += " imm"
		parts.append("%s%s(%d%s ult%d)" % ["P" if u.side == PLAYER else "N", u.display_name(), u.hp, tags, u.ult])
	return "turn %d, %s to move, potions %d/%d: %s" % [turn, "player" if side_to_move == PLAYER else "npc",
		potions[PLAYER], potions[NPC], " ".join(parts)]

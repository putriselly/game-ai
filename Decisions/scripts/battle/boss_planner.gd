class_name BossPlanner
extends RefCounted
## AUTOMATED PLANNING for the boss (Tahap 4): forward state-space search over
## [PlanModel] from the current abstract state to a GOAL (a conjunction of
## literals), returning a sequence of grounded actions.
##
## * Search: A* with f = g + h, one action per step, depth bound
##   [member max_plan_length]. With [constant Heuristic.NONE] it degenerates
##   to uniform-cost search (breadth-first), the baseline for the experiments.
## * Heuristics: GOAL_COUNT (unsatisfied literals; not admissible: one AoE can
##   satisfy several) and DAMAGE (domain lower bound on the actions still
##   needed; admissible, also used to prune branches that cannot reach the goal
##   within the depth bound).
## * Goal selection: every candidate goal ([method candidate_goals]) is planned
##   for and scored with [BattleEvaluator] on the plan's end state. The
##   default scoring is the GAIN PER BOSS ACTION: the relaxed model ignores the
##   player, so every extra step is a free turn for them and a long plan must
##   earn it (with plain end values a 4-step kill of a big hero outranks a
##   2-step kill of the healer). So the boss weighs "kill the healer" against
##   "set up a party-wide burn" or "fortify" with the evaluation the minimax
##   NPC uses.
## The result carries search statistics for the debug overlay and experiments.

enum Heuristic { NONE, GOAL_COUNT, DAMAGE }
const HEURISTIC_NAMES: Array[String] = ["none", "goal_count", "damage"]
## END_VALUE: evaluation of the end state minus length_penalty per step.
## GAIN_RATE: (evaluation of end state - evaluation now) / plan length.
enum Scoring { END_VALUE, GAIN_RATE }
const SCORING_NAMES: Array[String] = ["end_value", "gain_rate"]


## A conjunctive goal.
class Goal:
	var name: String = ""
	var kind: String = ""              # kill / burn_all / fortify / recover
	var literals: Array[String] = []
	var target: int = -1               # unit the goal is about (kill), else -1

	static func make(goal_name: String, goal_kind: String, goal_literals: Array[String], goal_target: int = -1) -> Goal:
		var g := Goal.new()
		g.name = goal_name
		g.kind = goal_kind
		g.literals = goal_literals
		g.target = goal_target
		return g


## Outcome of planning for one goal (or, from [method decide], of the whole
## decision with the per-goal outcomes in [member candidates]).
class PlanResult:
	var goal: Goal
	var found: bool = false
	var steps: Array[PlanModel.PlanAction] = []
	var end_state: PlanModel.PlanState
	var score: float = -INF            # utility used to choose between goals
	var note: String = ""              # why no plan: "already satisfied", "unreachable", "no plan within bound", "node limit"
	var expanded: int = 0              # nodes popped and expanded
	var generated: int = 0             # successor states created
	var time_ms: float = 0.0
	var heuristic: String = ""
	## decide() only: one entry per goal tried
	## {goal, found, length, score, expanded, generated, note, steps}
	## (steps are copied, not the PlanResult, so the chosen result never
	## references itself through this list)
	var candidates: Array[Dictionary] = []
	var goals_tried: int = 0
	var total_expanded: int = 0
	var total_generated: int = 0
	var total_time_ms: float = 0.0

	func length() -> int:
		return steps.size()

	func describe(state: PlanModel.PlanState) -> String:
		if not found:
			return "no plan (%s)" % note
		var names: PackedStringArray = []
		for a in steps:
			names.append(a.describe(state))
		return "%s: %s" % [goal.name, " -> ".join(names)]

	func summary() -> String:
		return "%s len=%d expanded=%d generated=%d %.1fms (goals %d, total expanded %d)" % [
			heuristic, steps.size(), expanded, generated, time_ms, goals_tried, total_expanded]


var heuristic: Heuristic = Heuristic.DAMAGE
## Longest plan considered (boss actions).
var max_plan_length: int = 4
## Expansion budget per goal (0 = unlimited).
var node_limit: int = 5000
## Drop branches whose admissible lower bound exceeds the remaining depth.
var prune_unreachable: bool = true
## Evaluation used to compare plan end states (same names as the minimax NPC).
var eval_name: String = "tactical"
var personality: String = "balanced"
var scoring: Scoring = Scoring.GAIN_RATE
## END_VALUE only: utility lost per plan step.
var length_penalty: float = 3.0

var _seq := 0


# --- Goals ----------------------------------------------------------------------------

## Goals worth planning for in [param state], derived from the actor's skills:
## kill each living hero (healers and heroes weak to the boss's element first),
## burn every hero, fortify (shield + every status the boss can grant), recover.
func candidate_goals(state: PlanModel.PlanState) -> Array[Goal]:
	var goals: Array[Goal] = []
	var a := state.actor
	var sim := state.sim
	var actor_data := sim.units[a].data
	var side := state.side_of(a)
	var heroes := state.alive_units(BattleSim.other(side))

	var ranked: Array = []
	for h in heroes:
		var data := sim.units[h].data
		var rank := 0
		for s in data.skills:
			if s.heal > 0:
				rank -= 100  # healers first
		if PlanModel.ELEMENT_KB.get_element_status(actor_data.element, data.element) == PlanModel.ELEMENT_KB.STRENGTH:
			rank -= 50
		ranked.append({"unit": h, "rank": rank, "hp": state.hp[h] + state.shield.get(h, 0)})
	ranked.sort_custom(func(x, y):
		if x["rank"] != y["rank"]:
			return x["rank"] < y["rank"]
		return x["hp"] < y["hp"])
	for entry in ranked:
		var h: int = entry["unit"]
		goals.append(Goal.make("Kill %s" % sim.units[h].display_name(), "kill", ["dead(%d)" % h], h))

	var can_burn := false
	var grants: Array[String] = []
	var can_shield := false
	var can_heal := false
	for s in actor_data.skills:
		can_burn = can_burn or s.burn_turns > 0
		can_shield = can_shield or (s.shield > 0 and s.target_mode == SkillData.TargetMode.SELF)
		can_heal = can_heal or (s.heal > 0 and s.target_mode == SkillData.TargetMode.SELF)
		for flag in s.grants:
			if not grants.has(flag):
				grants.append(flag)

	if can_burn and not heroes.is_empty():
		var lits: Array[String] = []
		for h in heroes:
			lits.append("burning(%d)" % h)
		goals.append(Goal.make("Burn every hero", "burn_all", lits))

	var fortify: Array[String] = []
	if can_shield:
		fortify.append("shielded(%d)" % a)
	for flag in grants:
		fortify.append("%s(%d)" % [flag, a])
	if not fortify.is_empty():
		goals.append(Goal.make("Fortify", "fortify", fortify))

	if can_heal and state.has_flag(a, "low_hp"):
		goals.append(Goal.make("Recover", "recover", ["not low_hp(%d)" % a]))
	return goals


# --- Heuristics -------------------------------------------------------------------

func heuristic_name() -> String:
	return HEURISTIC_NAMES[heuristic]


func _h(state: PlanModel.PlanState, goal: Goal) -> int:
	match heuristic:
		Heuristic.GOAL_COUNT:
			return state.unsatisfied(goal.literals)
		Heuristic.DAMAGE:
			return lower_bound(state, goal)
	return 0


## Admissible lower bound on the actions still needed: for dead(u) the HP plus
## shield divided by the most damage one action (plus a burn tick) can do;
## every other unsatisfied literal needs at least one action. Max over literals.
func lower_bound(state: PlanModel.PlanState, goal: Goal) -> int:
	var bound := 0
	for literal in goal.literals:
		if state.holds(literal):
			continue
		var parsed := PlanModel.parse_literal(literal)
		var need := 1
		if parsed["pred"] == "dead" and not parsed["neg"]:
			var u: int = parsed["unit"]
			var per_step := _max_damage(state, u) + BattleSim.BURN_DAMAGE
			need = ceili(float(state.hp[u] + state.shield.get(u, 0)) / float(per_step))
		bound = maxi(bound, need)
	return bound


## Most damage one of the actor's skills can deal to [param target] in a single
## action (rage assumed available).
func _max_damage(state: PlanModel.PlanState, target: int) -> int:
	var best := 1
	var enraged := state.clone()
	enraged.set_flag(state.actor, "enraged")
	for s in state.sim.units[state.actor].data.skills:
		if s.power > 0 or s.power_if_user_enraged > 0 or s.power_if_target_burning > 0:
			best = maxi(best, PlanModel.predicted_damage(enraged, s, target))
	return best


# --- Search -------------------------------------------------------------------------

## A* from [param state] to [param goal].
func plan_for(state: PlanModel.PlanState, goal: Goal) -> PlanResult:
	var result := PlanResult.new()
	result.goal = goal
	result.heuristic = heuristic_name()
	var start := Time.get_ticks_usec()
	if state.holds_all(goal.literals):
		result.note = "already satisfied"
		result.time_ms = (Time.get_ticks_usec() - start) / 1000.0
		return result
	if prune_unreachable and lower_bound(state, goal) > max_plan_length:
		result.note = "unreachable within bound"
		result.time_ms = (Time.get_ticks_usec() - start) / 1000.0
		return result

	var open: Array = []   # binary heap of nodes
	var closed := {}
	_seq = 0
	_push(open, _node(state, [], 0, _h(state, goal)))
	result.note = "no plan within bound"
	while not open.is_empty():
		var node: Dictionary = _pop(open)
		var current: PlanModel.PlanState = node["state"]
		var key: String = current.key()
		if closed.has(key):
			continue
		closed[key] = true
		if current.holds_all(goal.literals):
			result.found = true
			result.steps.assign(node["plan"])
			result.end_state = current
			result.note = ""
			break
		if node_limit > 0 and result.expanded >= node_limit:
			result.note = "node limit"
			break
		result.expanded += 1
		var g: int = node["g"] + 1
		if g > max_plan_length:
			continue
		for action in PlanModel.ground_actions(current):
			var next := PlanModel.apply(current, action)
			if closed.has(next.key()):
				continue
			if prune_unreachable and g + lower_bound(next, goal) > max_plan_length:
				continue
			result.generated += 1
			var plan: Array = node["plan"].duplicate()
			plan.append(action)
			_push(open, _node(next, plan, g, _h(next, goal)))
	result.time_ms = (Time.get_ticks_usec() - start) / 1000.0
	return result


## Plans for every candidate goal and returns the best plan by utility; the
## result's [member PlanResult.candidates] lists every goal tried. If no goal
## has a plan, [member PlanResult.found] is false (the caller falls back).
func decide(state: PlanModel.PlanState) -> PlanResult:
	var start := Time.get_ticks_usec()
	var best: PlanResult = null
	var candidates: Array[Dictionary] = []
	var total_expanded := 0
	var total_generated := 0
	for goal in candidate_goals(state):
		var r := plan_for(state, goal)
		total_expanded += r.expanded
		total_generated += r.generated
		if r.found:
			r.score = score_plan(state, r)
		candidates.append({"goal": goal, "found": r.found, "length": r.length(), "score": r.score,
			"expanded": r.expanded, "generated": r.generated, "note": r.note, "steps": r.steps.duplicate()})
		if r.found and (best == null or r.score > best.score):
			best = r
	if best == null:
		best = PlanResult.new()
		best.heuristic = heuristic_name()
		best.note = "no goal reachable"
	best.candidates = candidates
	best.goals_tried = candidates.size()
	best.total_expanded = total_expanded
	best.total_generated = total_generated
	best.total_time_ms = (Time.get_ticks_usec() - start) / 1000.0
	return best


## Utility of a plan (see [member scoring]).
func score_plan(state: PlanModel.PlanState, result: PlanResult) -> float:
	var end_value := state_value(result.end_state)
	if scoring == Scoring.GAIN_RATE:
		return (end_value - state_value(state)) / float(maxi(1, result.length()))
	return end_value - length_penalty * result.length()


## Value of an abstract state for the actor's side: terminal utility if the
## battle is over there, else the configured evaluation function.
func state_value(state: PlanModel.PlanState) -> float:
	var side := state.side_of(state.actor)
	var sim := state.to_sim()
	if sim.is_terminal():
		return sim.utility(side)
	return BattleEvaluator.evaluate(sim, side, eval_name, BattleEvaluator.personality(personality))


# --- Priority queue (binary heap on f, then h, then insertion order) --------------

func _node(state: PlanModel.PlanState, plan: Array, g: int, h: int) -> Dictionary:
	_seq += 1
	return {"state": state, "plan": plan, "g": g, "h": h, "f": g + h, "seq": _seq}


static func _before(a: Dictionary, b: Dictionary) -> bool:
	if a["f"] != b["f"]:
		return a["f"] < b["f"]
	if a["h"] != b["h"]:
		return a["h"] < b["h"]
	return a["seq"] < b["seq"]


static func _push(heap: Array, node: Dictionary) -> void:
	heap.append(node)
	var i := heap.size() - 1
	while i > 0:
		var parent := (i - 1) >> 1
		if _before(heap[i], heap[parent]):
			var tmp = heap[i]
			heap[i] = heap[parent]
			heap[parent] = tmp
			i = parent
		else:
			break


static func _pop(heap: Array) -> Dictionary:
	var top: Dictionary = heap[0]
	var last = heap.pop_back()
	if not heap.is_empty():
		heap[0] = last
		var i := 0
		var n := heap.size()
		while true:
			var l := 2 * i + 1
			var r := l + 1
			var smallest := i
			if l < n and _before(heap[l], heap[smallest]):
				smallest = l
			if r < n and _before(heap[r], heap[smallest]):
				smallest = r
			if smallest == i:
				break
			var tmp = heap[i]
			heap[i] = heap[smallest]
			heap[smallest] = tmp
			i = smallest
	return top

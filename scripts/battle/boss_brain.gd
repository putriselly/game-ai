class_name BossBrain
extends RefCounted
## PLAN -> EXECUTE -> MONITOR -> REPLAN loop that drives a boss in the live
## battle (Tahap 4).
##
## Each NPC turn the brain plays the next step of its current plan if that
## step is still applicable on the REAL state ([method PlanModel.applicable])
## and the goal has not been reached; otherwise it asks [BossPlanner] for a
## new plan. The player acts between every two steps, so plans go stale when
## heroes die, heal, shield or stun the boss: how often that happens is a
## measured property (see the counters). When no goal is reachable the brain
## falls back to [MinimaxAI], so the boss never stalls.
##
## Modes: PLANNER (above), MINIMAX (control: the ordinary NPC search) and
## HYBRID (the first step of every candidate plan becomes a root action for
## minimax, which picks among them with the opponent in mind).

enum Mode { MINIMAX, PLANNER, HYBRID }
const MODE_NAMES: Array[String] = ["minimax", "planner", "hybrid"]


## One decision, with everything the overlay and the experiments want to know.
class Decision:
	var action: BattleAction
	var source: String = ""          # "plan", "fallback", "hybrid", "minimax", "pass"
	var plan: BossPlanner.PlanResult # plan in force after this decision (null when none)
	var step_index: int = -1         # index of the executed step in the plan
	var remaining: Array[PlanModel.PlanAction] = []
	var replanned: bool = false      # a (re)planning happened this turn
	var reason: String = ""          # why: no plan / plan finished / goal reached / precondition failed / no goal reachable
	var search: MinimaxAI.SearchResult  # set when minimax ran (fallback, hybrid, minimax)
	var time_ms: float = 0.0

	func describe(sim: BattleSim) -> String:
		var text := "%s: %s" % [source, action.describe(sim) if action else "-"]
		if plan != null and plan.found:
			text += "  [%s, step %d/%d]" % [plan.goal.name, step_index + 1, plan.length()]
		if replanned:
			text += "  (replanned: %s)" % reason
		return text


var mode: Mode = Mode.PLANNER
var planner := BossPlanner.new()
## Used by MINIMAX / HYBRID and as the fallback of PLANNER.
var fallback: MinimaxAI = MinimaxAI.new()

var current_plan: BossPlanner.PlanResult = null
var remaining: Array[PlanModel.PlanAction] = []
var next_step_index := 0

# --- Counters (per battle) ---
var decisions := 0
var plans_made := 0        # every call to the planner
var replans := 0           # plannings forced by a stale plan (precondition failed)
var steps_executed := 0    # plan steps played
var steps_continued := 0   # steps played from a plan made on an earlier turn
var fallbacks := 0         # turns decided by minimax because no goal was reachable
var history: Array[Decision] = []


func mode_name() -> String:
	return MODE_NAMES[mode]


## Decides the boss's action for the side to move in [param sim].
func decide(sim: BattleSim) -> Decision:
	var start := Time.get_ticks_usec()
	var d := Decision.new()
	decisions += 1
	var legal := sim.legal_actions(BattleSim.NPC)
	if legal.size() == 1 and legal[0].is_pass():
		d.action = legal[0]
		d.source = "pass"
		d.plan = current_plan
		return _finish(d, start)
	match mode:
		Mode.MINIMAX:
			d.search = fallback.decide(sim)
			d.action = d.search.action
			d.source = "minimax"
		Mode.HYBRID:
			_decide_hybrid(sim, d)
		Mode.PLANNER:
			_decide_planner(sim, d)
	return _finish(d, start)


func _decide_planner(sim: BattleSim, d: Decision) -> void:
	var state := PlanModel.from_sim(sim)
	var reason := _why_replan(state)
	if reason != "":
		d.replanned = true
		d.reason = reason
		plans_made += 1
		if reason == "precondition failed" or reason == "goal unreachable by plan":
			replans += 1
		current_plan = planner.decide(state)
		remaining = []
		next_step_index = 0
		if current_plan.found:
			remaining = current_plan.steps.duplicate()
		else:
			fallbacks += 1
			d.reason = reason + "; no goal reachable"
			d.search = fallback.decide(sim)
			d.action = d.search.action
			d.source = "fallback"
			d.plan = current_plan
			return
	else:
		steps_continued += 1
	var step: PlanModel.PlanAction = remaining.pop_front()
	d.action = step.to_battle_action()
	d.step_index = next_step_index
	next_step_index += 1
	steps_executed += 1
	d.source = "plan"
	d.plan = current_plan
	d.remaining = remaining.duplicate()


## Execution monitoring: "" when the plan can simply go on. Action monitoring
## checks the next step's preconditions; plan monitoring replays the remaining
## steps on the current (relaxed) state and demands that the goal still comes
## out, so a plan the player has undone (healed the target, say) is dropped.
func _why_replan(state: PlanModel.PlanState) -> String:
	if current_plan == null:
		return "no plan"
	if remaining.is_empty():
		return "plan finished"
	if current_plan.found and state.holds_all(current_plan.goal.literals):
		return "goal reached"
	if not PlanModel.applicable(state, remaining[0]):
		return "precondition failed"
	var projected := state
	for step in remaining:
		if not PlanModel.applicable(projected, step):
			return "precondition failed"
		projected = PlanModel.apply(projected, step)
	if not projected.holds_all(current_plan.goal.literals):
		return "goal unreachable by plan"
	return ""


func _decide_hybrid(sim: BattleSim, d: Decision) -> void:
	var state := PlanModel.from_sim(sim)
	plans_made += 1
	d.replanned = true
	d.reason = "hybrid replans every turn"
	current_plan = planner.decide(state)
	var allowed: Array[BattleAction] = []
	for c in current_plan.candidates:
		if c["found"] and not c["steps"].is_empty():
			var first: PlanModel.PlanAction = c["steps"][0]
			var ba := first.to_battle_action()
			var duplicate := false
			for a in allowed:
				duplicate = duplicate or a.same_as(ba)
			if not duplicate:
				allowed.append(ba)
	if allowed.is_empty():
		fallbacks += 1
		d.source = "fallback"
	else:
		d.source = "hybrid"
	d.search = fallback.decide(sim, allowed)
	d.action = d.search.action
	d.plan = current_plan
	remaining = []


func _finish(d: Decision, start: int) -> Decision:
	d.time_ms = (Time.get_ticks_usec() - start) / 1000.0
	history.append(d)
	return d


## Share of executed plan steps that came from an earlier turn's plan: how
## much of the planning survives the player's moves.
func continuation_rate() -> float:
	return float(steps_continued) / float(steps_executed) if steps_executed > 0 else 0.0


func stats_summary() -> String:
	return "%d decisions, %d plans, %d replans (stale), %d fallbacks, %d steps (%.0f%% continued)" % [
		decisions, plans_made, replans, fallbacks, steps_executed, 100.0 * continuation_rate()]

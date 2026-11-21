class_name MinimaxAI
extends RefCounted
## Adversarial search over [BattleSim]: minimax, alpha-beta, expectimax and a
## one-ply greedy baseline, with move ordering and an optional node budget
## ("early stop"). Every decision returns a [SearchResult] with the scores of
## all root actions and the node statistics, which feeds the debug overlay
## and the experiments.

enum Algorithm { MINIMAX, ALPHABETA, EXPECTIMAX, GREEDY }
enum Ordering { NONE, HEURISTIC, RANDOM, WORST }

const ALGORITHM_NAMES: Array[String] = ["minimax", "alphabeta", "expectimax", "greedy"]
const ORDERING_NAMES: Array[String] = ["none", "heuristic", "random", "worst"]

class SearchResult:
	var action: BattleAction
	## [{action, score, bound}] for every root action; bound = true when the
	## score is only an upper bound because alpha-beta cut the branch.
	var root_scores: Array[Dictionary] = []
	var nodes: int = 0          # search nodes expanded (root included)
	var evals: int = 0          # evaluation-function calls (incl. ordering)
	var pruned: int = 0         # branches skipped by alpha-beta
	var cutoff: bool = false    # true if the node budget stopped the search
	var time_ms: float = 0.0
	var depth: int = 0
	var algorithm: String = ""
	var evaluation: String = ""
	## Value of the selected root action. For a chance action this is its
	## Expected Utility (EU).
	var best_value: float = -INF
	## Expanded decision / chance nodes, useful for analysis and the debug overlay.
	var max_nodes: int = 0
	var min_nodes: int = 0
	var chance_nodes: int = 0

	func summary() -> String:
		return "%s d=%d nodes=%d evals=%d pruned=%d %.1fms%s" % [
			algorithm, depth, nodes, evals, pruned, time_ms, " (budget hit)" if cutoff else ""]

var algorithm: Algorithm = Algorithm.ALPHABETA
var depth: int = 4
var eval_name: String = "tactical"
var personality: String = "balanced"
var ordering: Ordering = Ordering.HEURISTIC
## 0 = unlimited. When the budget is spent, remaining nodes are evaluated
## statically instead of expanded (graceful early stop).
var node_limit: int = 0
var side: int = BattleSim.NPC
var rng := RandomNumberGenerator.new()

var _weights: Dictionary
var _result: SearchResult


func decide(sim: BattleSim, allowed_actions: Array[BattleAction] = []) -> SearchResult:
	_weights = BattleEvaluator.personality(personality)
	_result = SearchResult.new()
	_result.algorithm = ALGORITHM_NAMES[algorithm]
	_result.evaluation = "%s/%s" % [eval_name, personality]
	var search_depth := 1 if algorithm == Algorithm.GREEDY else depth
	_result.depth = search_depth
	var start := Time.get_ticks_usec()

	var legal_actions := sim.legal_actions(side)
	var actions: Array[BattleAction] = []

	if allowed_actions.is_empty():
		actions = legal_actions
	else:
		for action in allowed_actions:
			for legal_action in legal_actions:
				if action.same_as(legal_action):
					actions.append(legal_action)
					break

		if actions.is_empty():
			actions = legal_actions

	actions = _order(sim, actions, true)
	_result.nodes += 1
	_result.max_nodes += 1 # Root decision: choose the best action for our side (MAX).

	var best_action: BattleAction = actions[0]
	var best_value := -INF
	var alpha := -INF

	for action in actions:
		# Keep the two chance outcomes for the root action. This makes the
		# Expected Utility auditable and available to the debug overlay.
		var chance_detail: Dictionary = {}
		var value := _action_value(sim, action, search_depth - 1, alpha, INF, chance_detail, true)
		var bound := algorithm == Algorithm.ALPHABETA and value <= alpha and best_value > -INF
		var root_entry := {"action": action, "score": value, "bound": bound}
		if not chance_detail.is_empty():
			root_entry["chance"] = chance_detail.duplicate(true)
		_result.root_scores.append(root_entry)

		if value > best_value:
			best_value = value
			best_action = action

		if algorithm == Algorithm.ALPHABETA:
			alpha = maxf(alpha, best_value)

	_result.action = best_action
	_result.best_value = best_value
	_result.time_ms = (Time.get_ticks_usec() - start) / 1000.0
	return _result


func _evaluate(sim: BattleSim) -> float:
	_result.evals += 1
	return BattleEvaluator.evaluate(sim, side, eval_name, _weights)


## Value of [param sim] for [member side], searching [param depth] more plies.
func _value(sim: BattleSim, depth_left: int, alpha: float, beta: float) -> float:
	_result.nodes += 1
	if sim.is_terminal():
		return sim.utility(side)
	if depth_left <= 0:
		return _evaluate(sim)
	if node_limit > 0 and _result.nodes >= node_limit:
		_result.cutoff = true
		return _evaluate(sim)

	var maximizing := sim.side_to_move == side
	if maximizing:
		_result.max_nodes += 1
	else:
		_result.min_nodes += 1
	var actions := _order(sim, sim.legal_actions(), maximizing)
	var best := -INF if maximizing else INF
	for i in range(actions.size()):
		var value := _action_value(sim, actions[i], depth_left - 1, alpha, beta)
		if maximizing:
			best = maxf(best, value)
			alpha = maxf(alpha, best)
		else:
			best = minf(best, value)
			beta = minf(beta, best)
		if algorithm == Algorithm.ALPHABETA and beta <= alpha:
			_result.pruned += actions.size() - i - 1
			break
	return best


## Expands one action. The EXPECTIMAX mode builds an Expectiminimax tree:
## MAX/MIN decision nodes alternate, while damaging actions create a CHANCE
## node with Hit and Miss outcomes weighted by their probabilities.
## Minimax and Alpha-Beta retain their deterministic hit-assumption baseline.
func _action_value(
	sim: BattleSim,
	action: BattleAction,
	depth_left: int,
	alpha: float,
	beta: float,
	root_chance_detail: Dictionary = {},
	capture_root_chance_detail: bool = false
) -> float:
	if algorithm == Algorithm.EXPECTIMAX and sim.is_chance_action(action):
		_result.chance_nodes += 1
		var p_hit: float = sim.hit_chance
		var p_miss: float = 1.0 - p_hit
		var hit_sim := sim.clone()
		hit_sim.apply(action, 1)
		var miss_sim := sim.clone()
		miss_sim.apply(action, 0)
		# Both outcomes must be evaluated; alpha-beta pruning is not valid
		# across an expectation until probability bounds are implemented.
		var hit_value: float = _value(hit_sim, depth_left, -INF, INF)
		var miss_value: float = _value(miss_sim, depth_left, -INF, INF)
		var expected_utility: float = p_hit * hit_value + p_miss * miss_value
		if capture_root_chance_detail:
			root_chance_detail["hit_probability"] = p_hit
			root_chance_detail["miss_probability"] = p_miss
			root_chance_detail["hit_value"] = hit_value
			root_chance_detail["miss_value"] = miss_value
			root_chance_detail["expected_utility"] = expected_utility
		return expected_utility
	var next := sim.clone()
	next.apply(action, 1)
	return _value(next, depth_left, alpha, beta)


## MOVE ORDERING. HEURISTIC sorts by the one-ply evaluation (best first for
## the maximizer, worst first for the minimizer), WORST is the reverse,
## RANDOM shuffles, NONE keeps generation order.
func _order(sim: BattleSim, actions: Array[BattleAction], maximizing: bool) -> Array[BattleAction]:
	if actions.size() <= 1 or ordering == Ordering.NONE or algorithm == Algorithm.GREEDY:
		return actions
	if ordering == Ordering.RANDOM:
		var shuffled := actions.duplicate()
		for i in range(shuffled.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp: BattleAction = shuffled[i]
			shuffled[i] = shuffled[j]
			shuffled[j] = tmp
		return shuffled
	var scored: Array = []
	for a in actions:
		var v: float
		if algorithm == Algorithm.EXPECTIMAX and sim.is_chance_action(a):
			# Ordering must use the same expected-outcome model as the search.
			# It only changes exploration order, not the backed-up value.
			var p_hit: float = sim.hit_chance
			var hit_next := sim.clone()
			hit_next.apply(a, 1)
			var miss_next := sim.clone()
			miss_next.apply(a, 0)
			var hit_value: float = hit_next.utility(side) if hit_next.is_terminal() else _evaluate(hit_next)
			var miss_value: float = miss_next.utility(side) if miss_next.is_terminal() else _evaluate(miss_next)
			v = p_hit * hit_value + (1.0 - p_hit) * miss_value
		else:
			var next := sim.clone()
			next.apply(a, 1)
			v = next.utility(side) if next.is_terminal() else _evaluate(next)
		scored.append({"a": a, "v": v})
	var best_first := maximizing
	if ordering == Ordering.WORST:
		best_first = not best_first
	scored.sort_custom(func(x, y): return x["v"] > y["v"] if best_first else x["v"] < y["v"])
	var out: Array[BattleAction] = []
	for s in scored:
		out.append(s["a"])
	return out

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


func decide(sim: BattleSim) -> SearchResult:
	_weights = BattleEvaluator.personality(personality)
	_result = SearchResult.new()
	_result.algorithm = ALGORITHM_NAMES[algorithm]
	_result.evaluation = "%s/%s" % [eval_name, personality]
	var search_depth := 1 if algorithm == Algorithm.GREEDY else depth
	_result.depth = search_depth
	var start := Time.get_ticks_usec()

	var actions := _order(sim, sim.legal_actions(side), true)
	_result.nodes += 1
	var best_action: BattleAction = actions[0]
	var best_value := -INF
	var alpha := -INF
	for action in actions:
		var value := _action_value(sim, action, search_depth - 1, alpha, INF)
		var bound := algorithm == Algorithm.ALPHABETA and value <= alpha and best_value > -INF
		_result.root_scores.append({"action": action, "score": value, "bound": bound})
		if value > best_value:
			best_value = value
			best_action = action
		if algorithm == Algorithm.ALPHABETA:
			alpha = maxf(alpha, best_value)

	_result.action = best_action
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


## Expands one action. Expectimax turns chance actions into a chance node
## weighted by hit probability; the other algorithms assume the hit lands.
func _action_value(sim: BattleSim, action: BattleAction, depth_left: int, alpha: float, beta: float) -> float:
	if algorithm == Algorithm.EXPECTIMAX and sim.is_chance_action(action):
		var p := sim.hit_chance
		var hit_sim := sim.clone()
		hit_sim.apply(action, 1)
		var miss_sim := sim.clone()
		miss_sim.apply(action, 0)
		# No pruning through chance nodes: both outcomes must be valued.
		return p * _value(hit_sim, depth_left, -INF, INF) + (1.0 - p) * _value(miss_sim, depth_left, -INF, INF)
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
		var next := sim.clone()
		next.apply(a, 1)
		var v: float = next.utility(side) if next.is_terminal() else _evaluate(next)
		scored.append({"a": a, "v": v})
	var best_first := maximizing
	if ordering == Ordering.WORST:
		best_first = not best_first
	scored.sort_custom(func(x, y): return x["v"] > y["v"] if best_first else x["v"] < y["v"])
	var out: Array[BattleAction] = []
	for s in scored:
		out.append(s["a"])
	return out

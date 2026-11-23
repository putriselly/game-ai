class_name ExpectedUtility
extends RefCounted
## Reusable one-action evaluator for stochastic battle outcomes.
## This module is used by CSP/Local Search to score NPC plan actions without
## rolling the live BattleSim RNG. It evaluates forced Hit and Miss branches.


## Returns a dictionary containing the outcome values and expected utility.
## `side` is the perspective used by BattleEvaluator; -1 infers the actor side.
## Deterministic actions (heal, shield, self-buffs, pass) are evaluated once.
static func evaluate_action(
	sim: BattleSim,
	action: BattleAction,
	side: int = -1,
	eval_name: String = "tactical",
	weights: Dictionary = {}
) -> Dictionary:
	if sim == null or action == null:
		return _invalid_result("Missing simulation or action")

	var actor_side := sim.side_to_move
	if not action.is_pass():
		if action.unit < 0 or action.unit >= sim.units.size():
			return _invalid_result("Action has an invalid unit index")
		actor_side = sim.units[action.unit].side

	var evaluation_side := side if side >= 0 else actor_side
	var probabilistic := not action.is_pass() and sim.is_chance_action(action)

	if not probabilistic:
		var next_sim := sim.clone()
		next_sim.side_to_move = actor_side
		next_sim.apply(action, 1)
		var value := _state_value(next_sim, evaluation_side, eval_name, weights)
		return {
			"valid": true,
			"probabilistic": false,
			"hit_probability": 1.0,
			"miss_probability": 0.0,
			"hit_value": value,
			"miss_value": null,
			"expected_utility": value
		}

	var p_hit := clampf(sim.hit_chance, 0.0, 1.0)
	var p_miss := 1.0 - p_hit

	# Forced outcomes guarantee that evaluation never calls rng.randf().
	# BattleSim.clone() shares the RNG reference, so avoiding random rolls here
	# is essential to keep the live battle's random stream unchanged.
	var hit_sim := sim.clone()
	hit_sim.side_to_move = actor_side
	hit_sim.apply(action, 1)

	var miss_sim := sim.clone()
	miss_sim.side_to_move = actor_side
	miss_sim.apply(action, 0)

	var hit_value := _state_value(hit_sim, evaluation_side, eval_name, weights)
	var miss_value := _state_value(miss_sim, evaluation_side, eval_name, weights)
	var expected := p_hit * hit_value + p_miss * miss_value

	return {
		"valid": true,
		"probabilistic": true,
		"hit_probability": p_hit,
		"miss_probability": p_miss,
		"hit_value": hit_value,
		"miss_value": miss_value,
		"expected_utility": expected
	}


static func _state_value(
	sim: BattleSim,
	side: int,
	eval_name: String,
	weights: Dictionary
) -> float:
	if sim.is_terminal():
		return sim.utility(side)
	return BattleEvaluator.evaluate(sim, side, eval_name, weights)


static func _invalid_result(reason: String) -> Dictionary:
	return {
		"valid": false,
		"reason": reason,
		"probabilistic": false,
		"hit_probability": 0.0,
		"miss_probability": 0.0,
		"hit_value": 0.0,
		"miss_value": null,
		"expected_utility": -INF
	}


class_name BossMDP
extends RefCounted

const PLAYER := BattleSim.PLAYER
const NPC := BattleSim.NPC

var discount_factor: float = 0.9
var convergence_threshold: float = 0.01
var max_iterations: int = 100

var state_values: Dictionary = {}
var policy: Dictionary = {}
var known_states: Dictionary = {}
var iterations_used: int = 0


## Menghasilkan kemungkinan state berikutnya dari suatu aksi.
static func get_transitions(sim: BattleSim, action: BattleAction) -> Array[Dictionary]:
	var transitions: Array[Dictionary] = []

	if sim == null or action == null:
		return transitions

	var actor_side := sim.side_to_move

	if not action.is_pass():
		if action.unit < 0 or action.unit >= sim.units.size():
			return transitions
		actor_side = sim.units[action.unit].side

	if sim.is_chance_action(action):
		var p_hit := sim.hit_chance
		var p_miss := 1.0 - p_hit

		var hit_sim := sim.clone()
		hit_sim.side_to_move = actor_side
		hit_sim.apply(action, 1)

		var miss_sim := sim.clone()
		miss_sim.side_to_move = actor_side
		miss_sim.apply(action, 0)

		if p_hit > 0.0:
			transitions.append({
				"probability": p_hit,
				"state": hit_sim
			})

		if p_miss > 0.0:
			transitions.append({
				"probability": p_miss,
				"state": miss_sim
			})
	else:
		var next_sim := sim.clone()
		next_sim.side_to_move = actor_side
		next_sim.apply(action, 1)

		transitions.append({
			"probability": 1.0,
			"state": next_sim
		})

	return transitions


## Reward dari perspektif NPC (boss).
static func calculate_reward(previous: BattleSim, next: BattleSim) -> float:
	if next.is_terminal():
		return next.utility(NPC)

	var player_hp_before := previous.total_hp(PLAYER)
	var player_hp_after := next.total_hp(PLAYER)

	var boss_hp_before := previous.total_hp(NPC)
	var boss_hp_after := next.total_hp(NPC)

	var damage_to_player := player_hp_before - player_hp_after
	var damage_to_boss := boss_hp_before - boss_hp_after

	return float(damage_to_player - damage_to_boss)


## Menghitung nilai state dan menentukan aksi terbaik.

func value_iteration(initial_state: BattleSim) -> void:
	state_values.clear()
	policy.clear()
	known_states.clear()
	if initial_state == null:
		return
	var states := collect_states(initial_state)
	print("State pertama hasil collect: ", state_key(states[0]))
	print("State awal dari input: ", state_key(initial_state))
	iterations_used = 0
	for iteration in range(max_iterations):
		iterations_used += 1
		var max_change := 0.0
		var new_values: Dictionary = {}
		var new_policy: Dictionary = {}
		for sim in states:
			var key := state_key(sim)
			if sim.is_terminal():
				var terminal_value := sim.utility(NPC)
				new_values[key] = terminal_value
				var terminal_change := absf(terminal_value - state_values.get(key, 0.0))
				max_change = maxf(max_change, terminal_change)
				continue
			var best_value: float

			if sim.side_to_move == NPC:
				best_value = -INF
			else:
				best_value = INF
			var best_action: BattleAction = null
			for action in sim.legal_actions(sim.side_to_move):
				var transitions := get_transitions(sim, action)
				var action_value := 0.0
				for transition in transitions:
					var next_sim: BattleSim = transition["state"]
					var probability: float = transition["probability"]
					var reward := calculate_reward(sim, next_sim)
					var next_key := state_key(next_sim)
					var future_value: float = state_values.get(next_key, 0.0)
					action_value += probability * (reward + discount_factor * future_value)
				if sim.side_to_move == NPC:
					if action_value > best_value:
						best_value = action_value
						best_action = action
				else:
					if action_value < best_value:
						best_value = action_value
						best_action = action
			if best_action != null:
				new_values[key] = best_value
				if sim.side_to_move == NPC:
					new_policy[key] = best_action
				var change := absf(best_value - state_values.get(key, 0.0))
				max_change = maxf(max_change, change)
		state_values.merge(new_values, true)
		policy.merge(new_policy, true)
		print("Iterasi: ", iteration + 1, " | Max Change: ", max_change)
		if max_change < convergence_threshold:
			break
	print("MDP Iterasi digunakan: ", iterations_used)
	print("Batas iterasi maksimum: ", max_iterations)
	print("Threshold konvergensi: ", convergence_threshold)


## Mengumpulkan state yang dapat dicapai dari state awal.
func collect_states(initial_state: BattleSim) -> Array[BattleSim]:
	var states: Array[BattleSim] = []
	var visited: Dictionary = {}
	var queue: Array[BattleSim] = [initial_state.clone()]

	while not queue.is_empty() and states.size() < 500:
		var current: BattleSim = queue.pop_front()
		var key := state_key(current)

		if visited.has(key):
			continue

		visited[key] = true
		known_states[key] = current
		states.append(current)
		

		if current.is_terminal():
			continue

		for action in current.legal_actions(current.side_to_move):
			for transition in get_transitions(current, action):
				var next_state: BattleSim = transition["state"]
				var next_key := state_key(next_state)

				if not visited.has(next_key):
					queue.append(next_state)

	return states
	

## Identitas unik state berdasarkan kondisi pertarungan.

## Identitas state berdasarkan seluruh kondisi yang memengaruhi simulasi.
static func state_key(sim: BattleSim) -> String:
	var parts: PackedStringArray = []

	parts.append("turn:%d" % sim.turn)
	parts.append("side:%d" % sim.side_to_move)
	parts.append("potions:%s" % str(sim.potions))
	parts.append("hit:%.4f" % sim.hit_chance)
	parts.append("max_turns:%d" % sim.max_turns)
	parts.append("full_targeting:%s" % str(sim.full_targeting))
	parts.append("target_rule:%d" % sim.target_rule)
	parts.append("ultimate_mode:%d" % sim.ultimate_mode)

	for unit in sim.units:
		parts.append(
			"%d:%d:%d:%d:%d:%d:%d:%s" % [
				unit.index,
				unit.hp,
				unit.shield,
				unit.burn,
				unit.stun,
				unit.stun_immune,
				unit.ult,
				str(unit.flag_names())
			]
		)

	return "|".join(parts)


## Mengambil aksi terbaik berdasarkan policy.
func get_best_action(sim: BattleSim) -> BattleAction:
	if sim == null:
		return null

	var key := state_key(sim)

	if policy.has(key):
		return policy[key]

	return null
	
static func test_transitions(sim: BattleSim, action: BattleAction) -> void:
	var transitions := get_transitions(sim, action)
	var total_probability := 0.0
	print("Jumlah kemungkinan: ", transitions.size())
	for transition in transitions:
		print("Probabilitas: ", transition["probability"])
		total_probability += transition["probability"]
	print("Total probabilitas: ", total_probability)

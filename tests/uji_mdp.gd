
extends Node

const SIM = preload("res://scripts/battle/battle_sim.gd")
const SKILL = preload("res://scripts/battle/skill_data.gd")
const DATA = preload("res://scripts/battle/unit_data.gd")
const ACTION = preload("res://scripts/battle/battle_action.gd")
const MDP = preload("res://scripts/battle/boss_mdp.gd")
const BRAIN = preload("res://scripts/battle/boss_brain.gd")

func _ready() -> void:
	print("===== PERSIAPAN TEST =====")

	var sim = SIM.new()
	sim.hit_chance = 0.7

	# Membuat skill
	var skill = SKILL.make({
		"id": "test_attack",
		"display_name": "Test Attack",
		"power": 10
	})

	# Membuat data Player
	var player_data = DATA.new()
	player_data.display_name = "Player"
	player_data.max_hp = 30
	player_data.skills.append(skill)

	# Membuat data Boss
	var boss_data = DATA.new()
	boss_data.display_name = "Boss"
	boss_data.max_hp = 30
	boss_data.skills.append(skill)

	# Memasukkan unit ke simulasi
	var player = sim.add_unit(player_data, SIM.PLAYER)
	var boss = sim.add_unit(boss_data, SIM.NPC)

	print("Player HP: ", player.hp)
	print("Boss HP: ", boss.hp)

	# Membuat aksi Player menyerang Boss
	var player_action = ACTION.make(player.index, skill, [boss.index])

	print("\n===== TEST 1: STOCHASTIC TRANSITION =====")

	var transitions = MDP.get_transitions(sim, player_action)
	var total_probability := 0.0

	for transition in transitions:
		var probability: float = transition["probability"]
		var next_state = transition["state"]

		total_probability += probability

		print("Probabilitas: ", probability)
		print("HP Boss: ", next_state.units[boss.index].hp)

	print("Total probabilitas: ", total_probability)

	if is_equal_approx(total_probability, 1.0):
		print("[PASS] Total probabilitas = 1.0")
	else:
		print("[FAIL] Total probabilitas tidak sama dengan 1.0")

	print("\n===== TEST 2: DETERMINISTIC TRANSITION =====")

	sim.hit_chance = 1.0

	var deterministic = MDP.get_transitions(sim, player_action)

	print("Jumlah kemungkinan: ", deterministic.size())

	if deterministic.size() == 1:
		print("Probabilitas: ", deterministic[0]["probability"])
		print("[PASS] Transisi deterministik")
	else:
		print("[FAIL] Jumlah transisi tidak sesuai")

	print("\n===== TEST 3: REWARD =====")

	var player_transition = MDP.get_transitions(sim, player_action)
	var player_reward = MDP.calculate_reward(
		sim,
		player_transition[0]["state"]
	)

	print("Reward Player menyerang Boss: ", player_reward)

	if is_equal_approx(player_reward, -10.0):
		print("[PASS] Reward Player menyerang Boss")
	else:
		print("[FAIL] Reward Player tidak sesuai")

	# Membuat simulasi baru untuk menguji serangan Boss
	var boss_turn_sim = sim.clone()
	boss_turn_sim.side_to_move = SIM.NPC

	var boss_action = ACTION.make(boss.index, skill, [player.index])
	var boss_transition = MDP.get_transitions(boss_turn_sim, boss_action)

	var boss_reward = MDP.calculate_reward(
		boss_turn_sim,
		boss_transition[0]["state"]
	)

	print("Reward Boss menyerang Player: ", boss_reward)

	if is_equal_approx(boss_reward, 10.0):
		print("[PASS] Reward Boss menyerang Player")
	else:
		print("[FAIL] Reward Boss tidak sesuai")

	print("\n===== TEST 4: VALUE ITERATION =====")

	# Kembalikan simulasi ke kondisi awal
	sim = SIM.new()
	sim.hit_chance = 1.0

	player = sim.add_unit(player_data, SIM.PLAYER)
	boss = sim.add_unit(boss_data, SIM.NPC)

	var mdp = MDP.new()
	mdp.value_iteration(sim)

	var initial_key = MDP.state_key(sim)

	print("Jumlah state: ", mdp.state_values.size())
	print("Jumlah policy: ", mdp.policy.size())
	print("Nilai state awal: ", mdp.state_values.get(initial_key, "Tidak ditemukan"))

	if mdp.state_values.has(initial_key):
		print("[PASS] State awal memiliki nilai")
	else:
		print("[FAIL] State awal tidak memiliki nilai")

	print("\n===== TEST 5: POLICY BOSS =====")

	# Simulasikan Player menyerang Boss
	var player_actions = sim.legal_actions(SIM.PLAYER)

	if player_actions.is_empty() or player_actions[0].is_pass():
		print("[FAIL] Player tidak memiliki aksi menyerang")
	else:
		var next_transitions = MDP.get_transitions(sim, player_actions[0])
		var boss_turn_state: SIM = next_transitions[0]["state"]

		var boss_key = MDP.state_key(boss_turn_state)
		var best_action = mdp.get_best_action(boss_turn_state)

		print("Side setelah Player: ", boss_turn_state.side_to_move)
		print("State Boss dikenal: ", mdp.known_states.has(boss_key))
		print("State Boss memiliki nilai: ", mdp.state_values.has(boss_key))

		if best_action != null:
			print("Aksi pilihan Boss: ", best_action.describe(boss_turn_state))
			print("[PASS] Policy Boss ditemukan")
		else:
			print("[FAIL] Policy Boss tidak ditemukan")
			
	print("\n===== TEST 6: BOSS BRAIN MDP =====")

	var brain = BRAIN.new()
	brain.mode = 3

	# Siapkan kondisi ketika giliran Boss
	var mdp_boss_sim = sim.clone()
	mdp_boss_sim.side_to_move = SIM.NPC

	var decision = brain.decide(mdp_boss_sim)

	if decision.action != null:
		print("Mode: ", brain.mode_name())
		print("Source: ", decision.source)
		print("Aksi Boss: ", decision.action.describe(mdp_boss_sim))
		print("Waktu keputusan: ", decision.time_ms, " ms")

		if decision.source == "mdp":
			("[PASS] BossBrain menggunakan policy MDP")
		else:
			print("[FAIL] BossBrain menggunakan fallback")
	else:
		print("[FAIL] BossBrain tidak menghasilkan aksi")
		

	print("\n===== TEST 7: MDP MULTIPLE TURNS =====")

	var battle_sim = mdp_boss_sim.clone()
	var successful_decisions := 0

	for round_index in range(3):
		print("\n--- RONDE ", round_index + 1, " ---")		
		if not battle_sim.is_terminal():
			# Giliran Boss
			var boss_decision = brain.decide(battle_sim)

			if boss_decision.action != null and boss_decision.source == "mdp":
				successful_decisions += 1
				print("Boss: ", boss_decision.action.describe(battle_sim))
				battle_sim.apply(boss_decision.action)
			else:
				print("[FAIL] Boss gagal menggunakan MDP")

		if not battle_sim.is_terminal():
			# Giliran Player
			var available_actions = battle_sim.legal_actions(SIM.PLAYER)

			if not available_actions.is_empty():
				player_action = available_actions[0]
				print("Player: ", player_action.describe(battle_sim))
				battle_sim.apply(player_action)

	print("\nJumlah keputusan MDP berhasil: ", successful_decisions)

	if successful_decisions == 3:
		print("[PASS] MDP berhasil mengambil keputusan pada 3 giliran Boss")
	else:
		print("[FAIL] MDP tidak berhasil pada semua giliran")
		

	print("\n===== TEST 8: MDP WITH HIT CHANCE 70% =====")

	var probability_sim = mdp_boss_sim.clone()
	probability_sim.hit_chance = 0.7

	var probability_brain = BRAIN.new()
	probability_brain.mode = BRAIN.Mode.MDP

	var probability_decision = probability_brain.decide(probability_sim)

	print("Hit Chance: ", probability_sim.hit_chance)
	print("Source: ", probability_decision.source)
	print("Aksi Boss: ", probability_decision.action.describe(probability_sim))

	if probability_decision.source == "mdp" and probability_decision.action != null:
		print("[PASS] MDP berhasil mengambil keputusan dengan Hit Chance 70%")
	else:
		print("[FAIL] MDP gagal mengambil keputusan dengan Hit Chance 70%")


	print("\n===== TEST SELESAI =====")

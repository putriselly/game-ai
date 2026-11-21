
extends Node

const SIM = preload("res://scripts/battle/battle_sim.gd")
const STATE = preload("res://scripts/battle/unit_state.gd")
const SKILL = preload("res://scripts/battle/skill_data.gd")
const DATA = preload("res://scripts/battle/unit_data.gd")


func _ready() -> void:
	print("===== TEST DAMAGE MULTIPLIER =====")

	# TEST 1: Strength
	test_damage(
		"Strength",
		"Wind",
		"Electric",
		10,
		0,
		0,
		20,
		0,
		20
	)

	# TEST 2: Weakness
	test_damage(
		"Weakness",
		"Fire",
		"Water",
		10,
		0,
		0,
		5,
		0,
		5
	)

	# TEST 3: Strength dengan Shield
	test_damage(
		"Strength + Shield",
		"Wind",
		"Electric",
		10,
		7,
		0,
		20,
		7,
		13
	)

	# TEST 4: Weakness terhadap target Burning
	test_damage(
		"Weakness + Burning",
		"Fire",
		"Water",
		10,
		0,
		1,
		8,
		0,
		8
	)

	print("===== TEST SELESAI =====")


func test_damage(
	test_name: String,
	attacker_element: String,
	target_element: String,
	power: int,
	target_shield: int,
	target_burn: int,
	expected_damage: int,
	expected_absorbed: int,
	expected_lost: int
) -> void:

	var sim = SIM.new()

	# Membuat data penyerang
	var attacker_data = DATA.new()
	attacker_data.display_name = "Attacker"
	attacker_data.element = attacker_element
	attacker_data.max_hp = 30

	# Membuat data target
	var target_data = DATA.new()
	target_data.display_name = "Target"
	target_data.element = target_element
	target_data.max_hp = 30

	# Membuat unit
	var attacker = sim.add_unit(attacker_data, SIM.PLAYER)
	var target = sim.add_unit(target_data, SIM.NPC)

	target.shield = target_shield
	target.burn = target_burn

	# Membuat skill
	var skill = SKILL.make({
		"id": "test_skill",
		"display_name": "Test Skill",
		"power": power,
		"power_if_target_burning": 15
	})

	# Menjalankan serangan
	var targets: Array[UnitState] = [target]
	var events = sim.apply_skill(attacker, skill, targets)

	# Memeriksa event damage
	for event in events:
		if event["type"] == "damage":
			var actual_damage = event["amount"]
			var actual_absorbed = event["absorbed"]
			var actual_lost = event["lost"]

			var passed = (
				actual_damage == expected_damage
				and actual_absorbed == expected_absorbed
				and actual_lost == expected_lost
			)

			if passed:
				print("[PASS] ", test_name)
			else:
				print("[FAIL] ", test_name)

			print("  Damage: ", actual_damage)
			print("  Shield terserap: ", actual_absorbed)
			print("  HP berkurang: ", actual_lost)
			print("  HP target tersisa: ", target.hp)
			return

	print("[FAIL] ", test_name, " - Event damage tidak ditemukan")

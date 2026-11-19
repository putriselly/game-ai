
extends Node

const KB = preload("res://scripts/battle/element_kb.gd")


func _ready() -> void:
	print("===== TEST ELEMENT KNOWLEDGE BASE =====")

	# Seluruh kombinasi hubungan empat elemen
	var tests = [
		{"attacker": "Fire", "target": "Fire", "expected": true},
		{"attacker": "Fire", "target": "Water", "expected": false},
		{"attacker": "Fire", "target": "Electric", "expected": true},
		{"attacker": "Fire", "target": "Wind", "expected": true},

		{"attacker": "Water", "target": "Fire", "expected": true},
		{"attacker": "Water", "target": "Water", "expected": true},
		{"attacker": "Water", "target": "Electric", "expected": false},
		{"attacker": "Water", "target": "Wind", "expected": true},

		{"attacker": "Electric", "target": "Fire", "expected": true},
		{"attacker": "Electric", "target": "Water", "expected": true},
		{"attacker": "Electric", "target": "Electric", "expected": true},
		{"attacker": "Electric", "target": "Wind", "expected": false},

		{"attacker": "Wind", "target": "Fire", "expected": false},
		{"attacker": "Wind", "target": "Water", "expected": true},
		{"attacker": "Wind", "target": "Electric", "expected": true},
		{"attacker": "Wind", "target": "Wind", "expected": true}
	]

	var passed := 0
	var failed := 0

	for test in tests:
		var attacker: String = test["attacker"]
		var target: String = test["target"]
		var expected: bool = test["expected"]

		var actual = KB.get_relation(attacker, target)

		if actual == expected:
			print("[PASS] ", attacker, " -> ", target, " = ", actual)
			passed += 1
		else:
			print("[FAIL] ", attacker, " -> ", target,
				" | Expected: ", expected,
				" | Actual: ", actual)
			failed += 1

	# Pengujian penerjemahan hubungan menjadi Strength atau Weakness
	print("===== TEST ELEMENT STATUS =====")

	var status_1 = KB.get_element_status("Fire", "Water")
	var status_2 = KB.get_element_status("Fire", "Wind")
	var status_3 = KB.get_element_status("Water", "Electric")
	var status_4 = KB.get_element_status("Electric", "Water")

	print("Fire -> Water: ", status_1)
	print("Fire -> Wind: ", status_2)
	print("Water -> Electric: ", status_3)
	print("Electric -> Water: ", status_4)

	print("===== TEST STATUS SELESAI =====")

	print("--------------------------------------")
	print("Total pengujian: ", passed + failed)
	print("Berhasil: ", passed)
	print("Gagal: ", failed)
	print("======================================")

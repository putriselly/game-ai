class_name NpcCSP
extends RefCounted

# Membuat domain untuk setiap NPC.
# Setiap NPC boleh tidak bertindak, sehingga setiap domain
# selalu memiliki pilihan null.

static func build_domains(sim: BattleSim) -> Dictionary:
	var domains: Dictionary = {}

	# Ambil seluruh aksi NPC yang dianggap legal oleh BattleSim.
	var legal: Array[BattleAction] = sim.legal_actions(BattleSim.NPC)

	for unit in sim.side_units(BattleSim.NPC):
		var options: Array = [null]

		# Masukkan kandidat aksi yang benar-benar milik NPC ini.
		for action in legal:
			if action.is_pass():
				continue

			if action.unit == unit.index:
				options.append(action)

		domains[unit.index] = options

	return domains


# Memeriksa apakah satu aksi masih termasuk aksi legal
# untuk NPC yang bersangkutan.
static func is_action_legal(
	sim: BattleSim,
	unit_index: int,
	action: BattleAction
) -> bool:
	if unit_index < 0 or unit_index >= sim.units.size():
		return false

	var unit: UnitState = sim.units[unit_index]

	# Indeks tersebut harus benar-benar milik NPC.
	if unit.side != BattleSim.NPC:
		return false

	# NPC yang mati atau terkena stun tidak boleh bertindak.
	if not unit.is_alive() or unit.is_stunned():
		return false

	# null ditangani sebagai "tidak bertindak" oleh CSP.
	if action == null or action.is_pass():
		return false

	# Aksi harus dilakukan oleh NPC pada variabel tersebut.
	if action.unit != unit_index:
		return false

	# Gunakan kembali pemeriksaan legalitas dari BattleSim.
	var legal: Array[BattleAction] = sim.legal_actions(BattleSim.NPC)

	for legal_action in legal:
		if legal_action.is_pass():
			continue

		if legal_action.same_as(action):
			return true

	return false


# Memeriksa konsistensi assignment, termasuk assignment parsial.
# Key Dictionary = indeks NPC.
# Value Dictionary = BattleAction atau null.
static func is_assignment_consistent(
	sim: BattleSim,
	assignment: Dictionary
) -> bool:
	var potion_used := 0

	for unit_index in assignment:
		var action = assignment[unit_index]

		# Pastikan indeks mewakili NPC.
		if unit_index < 0 or unit_index >= sim.units.size():
			return false

		if sim.units[unit_index].side != BattleSim.NPC:
			return false

		# NPC boleh memilih tidak bertindak.
		if action == null:
			continue

		# Tolak aksi yang tidak legal.
		if not is_action_legal(sim, unit_index, action):
			return false

		# Hitung kebutuhan potion seluruh aksi dalam rencana.
		if BattleSim.consumes_potion(action.skill):
			potion_used += 1

	# Constraint global: persediaan potion tidak boleh terlampaui.
	if potion_used > sim.potions[BattleSim.NPC]:
		return false

	return true


# Mencari satu rencana aksi NPC yang memenuhi constraint.
# use_mrv mengaktifkan heuristik MRV.
# use_lcv mengaktifkan heuristik LCV.

static func backtracking_search(
	sim: BattleSim,
	use_mrv: bool = true,
	use_lcv: bool = true
) -> Dictionary:
	var domains: Dictionary = build_domains(sim)
	var variables: Array[int] = []

	for npc in sim.side_units(BattleSim.NPC):
		variables.append(npc.index)

	if variables.is_empty():
		return {}

	return _backtrack(
		sim,
		variables,
		domains,
		{},
		use_mrv,
		use_lcv
	)


# Proses rekursif Backtracking.

static func _backtrack(
	sim: BattleSim,
	variables: Array[int],
	domains: Dictionary,
	assignment: Dictionary,
	use_mrv: bool,
	use_lcv: bool
) -> Dictionary:
	if not is_assignment_consistent(sim, assignment):
		return {}

	# Salin domain agar perubahan pada cabang ini
	# tidak memengaruhi cabang Backtracking lainnya.
	var current_domains: Dictionary = _copy_domains(domains)

	# Batasi domain setiap variabel yang sudah dipilih
	# menjadi nilai yang telah ditetapkan.
	for variable_index in assignment:
		if not current_domains.has(variable_index):
			return {}

		current_domains[variable_index] = [
			assignment[variable_index]
		]

	# Jalankan AC-3 kembali setelah assignment berubah.
	if not enforce_ac3(sim, variables, current_domains):
		return {}

	# Jika seluruh variabel sudah terisi, periksa solusi lengkap.
	if assignment.size() == variables.size():
		if _has_any_action(assignment):
			return assignment.duplicate()

		# Rencana tanpa aksi diterima hanya jika memang tidak
		# ada aksi legal yang tersedia pada kondisi awal ini.
		var original_domains: Dictionary = build_domains(sim)
		if not _has_any_legal_action(variables, original_domains):
			return assignment.duplicate()

		return {}

	# Pilih variabel berikutnya menggunakan MRV
	# atau urutan tetap jika MRV dimatikan.
	var variable_index: int

	if use_mrv:
		variable_index = _select_variable_mrv(
			sim,
			variables,
			current_domains,
			assignment
		)
	else:
		variable_index = _select_first_unassigned(
			variables,
			assignment
		)

	if variable_index == -1:
		return {}

	# Ambil nilai yang konsisten dari domain terbaru.
	var values: Array = _consistent_values(
		sim,
		variable_index,
		current_domains,
		assignment
	)

	if use_lcv:
		values = _order_values_lcv(
			sim,
			variable_index,
			values,
			variables,
			current_domains,
			assignment
		)
	else:
		values = _actions_before_idle(values)

	# Coba setiap pilihan melalui Backtracking.
	for value in values:
		var next_assignment: Dictionary = assignment.duplicate()
		next_assignment[variable_index] = value

		if not is_assignment_consistent(sim, next_assignment):
			continue

		var next_domains: Dictionary = _copy_domains(current_domains)

		# Pilihan yang sedang dicoba menjadi satu-satunya
		# nilai untuk variabel ini.
		next_domains[variable_index] = [value]

		var result: Dictionary = _backtrack(
			sim,
			variables,
			next_domains,
			next_assignment,
			use_mrv,
			use_lcv
		)

		if result.size() == variables.size():
			return result

	return {}


# Mendapatkan pilihan yang konsisten untuk satu variabel.
static func _consistent_values(
	sim: BattleSim,
	variable_index: int,
	domains: Dictionary,
	assignment: Dictionary
) -> Array:
	var values: Array = []

	for value in domains.get(variable_index, []):
		var test_assignment: Dictionary = assignment.duplicate()
		test_assignment[variable_index] = value

		if is_assignment_consistent(sim, test_assignment):
			values.append(value)

	return values


# MRV: pilih variabel dengan pilihan konsisten paling sedikit.
static func _select_variable_mrv(
	sim: BattleSim,
	variables: Array[int],
	domains: Dictionary,
	assignment: Dictionary
) -> int:
	var selected_index := -1
	var smallest_domain := 2147483647

	for variable_index in variables:
		if assignment.has(variable_index):
			continue

		var available: Array = _consistent_values(
			sim,
			variable_index,
			domains,
			assignment
		)

		if available.size() < smallest_domain:
			smallest_domain = available.size()
			selected_index = variable_index

	return selected_index


# Memilih variabel dengan urutan tetap jika MRV dimatikan.
static func _select_first_unassigned(
	variables: Array[int],
	assignment: Dictionary
) -> int:
	for variable_index in variables:
		if not assignment.has(variable_index):
			return variable_index

	return -1


# LCV: urutkan aksi menurut jumlah pilihan variabel lain
# yang akan menjadi tidak konsisten apabila aksi tersebut dipilih.
# Pilihan null ditempatkan terakhir sebagai fallback.
static func _order_values_lcv(
	sim: BattleSim,
	variable_index: int,
	values: Array,
	variables: Array[int],
	domains: Dictionary,
	assignment: Dictionary
) -> Array:
	var ranked: Array = []
	var idle_values: Array = []

	for value in values:
		if value == null:
			idle_values.append(value)
			continue

		var conflicts := 0
		var partial: Dictionary = assignment.duplicate()
		partial[variable_index] = value

		for other_index in variables:
			if other_index == variable_index:
				continue

			if assignment.has(other_index):
				continue

			for other_value in domains.get(other_index, []):
				var pair: Dictionary = partial.duplicate()
				pair[other_index] = other_value

				if not is_assignment_consistent(sim, pair):
					conflicts += 1

		ranked.append({
			"value": value,
			"conflicts": conflicts
		})

	# Nilai dengan konflik lebih sedikit dicoba terlebih dahulu.
	ranked.sort_custom(
		func(a, b):
			return a["conflicts"] < b["conflicts"]
	)

	var ordered: Array = []

	for entry in ranked:
		ordered.append(entry["value"])

	# NPC boleh tidak bertindak jika diperlukan.
	for value in idle_values:
		ordered.append(value)

	return ordered


# Urutan nilai sederhana saat LCV dimatikan.
static func _actions_before_idle(values: Array) -> Array:
	var ordered: Array = []

	for value in values:
		if value != null:
			ordered.append(value)

	for value in values:
		if value == null:
			ordered.append(value)

	return ordered


# Memastikan rencana tidak hanya berisi pilihan tidak bertindak
# ketika masih ada aksi legal.
static func _has_any_action(assignment: Dictionary) -> bool:
	for variable_index in assignment:
		if assignment[variable_index] != null:
			return true

	return false


static func _has_any_legal_action(
	variables: Array[int],
	domains: Dictionary
) -> bool:
	for variable_index in variables:
		for value in domains.get(variable_index, []):
			if value != null:
				return true

	return false



# AC-3: menyaring domain berdasarkan konsistensi antarvariabel.
static func enforce_ac3(sim: BattleSim, variables: Array[int], domains: Dictionary) -> bool:

	var queue: Array[Vector2i] = []

	# Buat arc untuk setiap pasangan variabel yang berbeda.
	for xi in variables:
		for xj in variables:
			if xi != xj:
				queue.append(Vector2i(xi, xj))

	while not queue.is_empty():
		var arc: Vector2i = queue.pop_front()
		var xi: int = arc.x
		var xj: int = arc.y

		if _revise_domain(sim, xi, xj, domains):
			if domains[xi].is_empty():
				return false

			# Jika domain xi berubah, periksa kembali
			# variabel lain yang berhubungan dengan xi.
			for xk in variables:
				if xk != xi and xk != xj:
					queue.append(Vector2i(xk, xi))

	return true


# Menghapus nilai domain xi yang tidak memiliki dukungan
# dalam domain xj.
static func _revise_domain(
	sim: BattleSim,
	xi: int,
	xj: int,
	domains: Dictionary
) -> bool:
	var revised := false
	var kept_values: Array = []

	var values_i: Array = domains.get(xi, [])
	var values_j: Array = domains.get(xj, [])

	for action_i in values_i:
		var supported := false

		for action_j in values_j:
			if _pairwise_compatible(
				sim,
				xi,
				action_i,
				xj,
				action_j
			):
				supported = true
				break

		if supported:
			kept_values.append(action_i)
		else:
			revised = true

	domains[xi] = kept_values
	return revised


# Constraint pasangan: kedua aksi harus legal dan
# kebutuhan potion pasangan tidak boleh melebihi persediaan.
static func _pairwise_compatible(
	sim: BattleSim,
	xi: int,
	action_i,
	xj: int,
	action_j
) -> bool:
	if action_i != null:
		if not is_action_legal(sim, xi, action_i):
			return false

	if action_j != null:
		if not is_action_legal(sim, xj, action_j):
			return false

	var potion_needed := 0

	if action_i != null:
		if BattleSim.consumes_potion(action_i.skill):
			potion_needed += 1

	if action_j != null:
		if BattleSim.consumes_potion(action_j.skill):
			potion_needed += 1

	return potion_needed <= sim.potions[BattleSim.NPC]


# Salin array domain untuk mencegah perubahan satu cabang
# Backtracking memengaruhi cabang lainnya.
static func _copy_domains(domains: Dictionary) -> Dictionary:
	var copied: Dictionary = {}

	for variable_index in domains:
		copied[variable_index] = domains[variable_index].duplicate()

	return copied


# Menghitung pelanggaran constraint penggunaan potion.
static func count_violations(
	sim: BattleSim,
	assignment: Dictionary
) -> int:
	var potion_used := 0
	for unit_index in assignment:
		var action = assignment[unit_index]
		if action == null:
			continue
		if BattleSim.consumes_potion(action.skill):
			potion_used += 1
	return maxi(
		0,
		potion_used - sim.potions[BattleSim.NPC]
	)
	
	
static func build_neighbor_plan(sim: BattleSim, assignment: Dictionary) -> Dictionary:
	var neighbor = assignment.duplicate(true)
	var domains = build_domains(sim)
	var units = neighbor.keys()

	if units.is_empty():
		return {}

	var unit_index = units[randi() % units.size()]
	var alternatives = domains.get(unit_index, [])

	if alternatives.is_empty():
		return neighbor

	var current_action = neighbor[unit_index]
	var candidates = []

	for action in alternatives:
		if action == null:
			if current_action != null:
				candidates.append(action)
		elif current_action == null or not action.same_as(current_action):
			candidates.append(action)

	if candidates.is_empty():
		return neighbor

	neighbor[unit_index] = candidates[randi() % candidates.size()]
	return neighbor

static func build_initial_plan(sim: BattleSim) -> Dictionary:
	return backtracking_search(sim, true, true)

static func evaluate_plan(sim: BattleSim, assignment: Dictionary) -> float:
	if not is_assignment_consistent(sim, assignment):
		return -INF

	var best_score: float = -INF

	for unit_index in assignment:
		var action = assignment[unit_index]

		if action == null:
			continue

		if not is_action_legal(sim, unit_index, action):
			continue

		var sim_copy = sim.clone()
		sim_copy.apply(action)

		var score: float = BattleEvaluator.evaluate(
			sim_copy,
			BattleSim.NPC,
			"tactical",
			{}
		)

		best_score = maxf(best_score, score)

	return best_score

static func local_search(
	sim: BattleSim,
	max_iterations: int = 100
) -> Dictionary:
	var current_plan: Dictionary = build_initial_plan(sim)

	if current_plan.is_empty():
		return {}

	var current_score: float = evaluate_plan(sim, current_plan)
	var best_plan: Dictionary = current_plan.duplicate(true)
	var best_score: float = current_score

	for i in range(max_iterations):
		var neighbor: Dictionary = build_neighbor_plan(sim, current_plan)

		if neighbor.is_empty():
			break

		if not is_assignment_consistent(sim, neighbor):
			continue

		var neighbor_score: float = evaluate_plan(sim, neighbor)

		if neighbor_score > current_score:
			current_plan = neighbor
			current_score = neighbor_score

		if current_score > best_score:
			best_plan = current_plan.duplicate(true)
			best_score = current_score

	return best_plan
	

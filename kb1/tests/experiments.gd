extends Node
## Experiment runner for the report.
## Run: godot --headless --path . res://tests/experiments_runner.tscn
## Writes markdown tables to docs/experiments.md and prints them.
##
## Experiments:
##  1. minimax vs alpha-beta vs alpha-beta+ordering vs node budget (same positions)
##  2. evaluation functions (win rate vs a fixed player policy)
##  3. move ordering (nodes/pruning with alpha-beta)
##  4. search depth (cost per decision and win rate)
##  5. personalities (aggressive / defensive / balanced behaviour)
##  6. expectimax vs alpha-beta in a stochastic game (hit chance < 1)
##  7. own feature: ultimate mode AUTO vs CHOICE (branching factor)

const ENCOUNTERS: Array = [
	["evil_bamboo", "bear"],
	["bomber", "evil_fire_mage", "evil_thunder_mage"],
	["bear", "evil_bamboo", "evil_bamboo", "bomber"],
]
const PARTY: Array[String] = ["ninja", "flame", "knight", "monk"]
const GAMES_PER_CONFIG := 30
const POSITION_SAMPLES := 40

var out: Array[String] = []
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	out.append("# Hasil Eksperimen AI Battle\n")
	out.append("Dihasilkan oleh `tests/experiments.gd`. Lawan (pihak player) selalu dikendalikan oleh kebijakan tetap: alpha-beta kedalaman 2 dengan evaluasi `tactical` (pemain yang cukup kompeten). Setiap konfigurasi dimainkan pada %d pertandingan (3 encounter, HP awal party diacak 70-100%% dengan seed tetap).\n" % GAMES_PER_CONFIG)
	var positions := _sample_positions()
	_exp1_algorithms(positions)
	_exp3_ordering(positions)
	_exp4_depth(positions)
	_exp2_evaluations(positions)
	_exp5_personalities(positions)
	_exp6_expectimax(positions)
	_exp7_ultimate_mode(positions)
	_exp8_targeting(positions)
	_exp9_target_rule(positions)
	out.append("\n_Total waktu eksperimen: %.1f detik._\n" % ((Time.get_ticks_msec() - t0) / 1000.0))
	var text := "\n".join(out)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs"))
	var f := FileAccess.open("res://docs/experiments.md", FileAccess.WRITE)
	f.store_string(text)
	f.close()
	print(text)
	get_tree().quit()


# --- Helpers --------------------------------------------------------------------

func _npc(algorithm: MinimaxAI.Algorithm, depth: int, eval_name := "tactical", personality := "balanced",
		ordering := MinimaxAI.Ordering.HEURISTIC, node_limit := 0) -> MinimaxAI:
	var ai := MinimaxAI.new()
	ai.side = BattleSim.NPC
	ai.algorithm = algorithm
	ai.depth = depth
	ai.eval_name = eval_name
	ai.personality = personality
	ai.ordering = ordering
	ai.node_limit = node_limit
	ai.rng.seed = 12345
	return ai


## The fixed opponent: a competent "player" (alpha-beta, depth 2, tactical).
func _player_policy() -> MinimaxAI:
	var ai := MinimaxAI.new()
	ai.side = BattleSim.PLAYER
	ai.algorithm = MinimaxAI.Algorithm.ALPHABETA
	ai.depth = 2
	ai.eval_name = "tactical"
	return ai


func _new_game(game_index: int, hit_chance := 1.0, ultimate_mode := BattleSim.UltimateMode.AUTO, full_targeting := false,
		target_rule := BattleSim.TargetRule.WEAKEST) -> BattleSim:
	rng.seed = 1000 + game_index
	var hp := {}
	for id in PARTY:
		var max_hp := Roster.get_unit(id).max_hp
		hp[id] = int(round(max_hp * rng.randf_range(0.7, 1.0)))
	var foes: Array[String] = []
	for id in ENCOUNTERS[game_index % ENCOUNTERS.size()]:
		foes.append(id)
	var sim := BattleSim.create(PARTY, foes, hp)
	sim.hit_chance = hit_chance
	sim.ultimate_mode = ultimate_mode
	sim.full_targeting = full_targeting
	sim.target_rule = target_rule
	sim.rng.seed = 5000 + game_index
	return sim


## Plays one game. Returns stats.
func _play(npc: MinimaxAI, sim: BattleSim, record: Array = []) -> Dictionary:
	var player := _player_policy()
	var nodes := 0
	var time_ms := 0.0
	var decisions := 0
	var player_start := sim.total_hp(BattleSim.PLAYER)
	while not sim.is_terminal():
		if sim.side_to_move == BattleSim.PLAYER:
			sim.apply(player.decide(sim).action)
		else:
			if record != null and record.size() < 400:
				record.append(sim.clone())
			var r := npc.decide(sim)
			nodes += r.nodes
			time_ms += r.time_ms
			decisions += 1
			sim.apply(r.action)
	return {
		"winner": sim.winner(), "turns": sim.turn,
		"npc_hp": sim.total_hp(BattleSim.NPC), "player_hp": sim.total_hp(BattleSim.PLAYER),
		"damage_dealt": player_start - sim.total_hp(BattleSim.PLAYER),
		"nodes": nodes, "time_ms": time_ms, "decisions": decisions,
	}


func _series(npc: MinimaxAI, hit_chance := 1.0, ultimate_mode := BattleSim.UltimateMode.AUTO, full_targeting := false,
		target_rule := BattleSim.TargetRule.WEAKEST) -> Dictionary:
	var wins := 0
	var draws := 0
	var turns := 0
	var npc_hp := 0
	var player_hp := 0
	var dealt := 0
	var nodes := 0
	var time_ms := 0.0
	var decisions := 0
	for g in range(GAMES_PER_CONFIG):
		var r := _play(npc, _new_game(g, hit_chance, ultimate_mode, full_targeting, target_rule), [])
		if r["winner"] == BattleSim.NPC:
			wins += 1
		elif r["winner"] == -1:
			draws += 1
		turns += r["turns"]
		npc_hp += r["npc_hp"]
		player_hp += r["player_hp"]
		dealt += r["damage_dealt"]
		nodes += r["nodes"]
		time_ms += r["time_ms"]
		decisions += r["decisions"]
	var n := float(GAMES_PER_CONFIG)
	return {
		"win_rate": wins / n, "draws": draws, "avg_turns": turns / n,
		"avg_npc_hp": npc_hp / n, "avg_player_hp": player_hp / n, "avg_dealt": dealt / n,
		"avg_nodes": float(nodes) / maxf(1, decisions), "avg_ms": time_ms / maxf(1, decisions),
	}


func _sample_positions() -> Array:
	var record: Array = []
	var npc := _npc(MinimaxAI.Algorithm.ALPHABETA, 3)
	for g in range(6):
		_play(npc, _new_game(g), record)
	var positions: Array = []
	var step := maxf(1.0, float(record.size()) / POSITION_SAMPLES)
	var i := 0.0
	while i < record.size() and positions.size() < POSITION_SAMPLES:
		positions.append(record[int(i)])
		i += step
	out.append("Posisi uji: %d state tengah-permainan (giliran NPC) yang diambil merata dari 6 pertandingan alpha-beta (depth 3) vs kebijakan player.\n" % positions.size())
	return positions


func _best_score(r: MinimaxAI.SearchResult) -> float:
	var best := -INF
	for e in r.root_scores:
		best = maxf(best, e["score"])
	return best


## How often [param ai] picks a different root action than [param reference]
## on the sample positions, and the average immediate damage of its choice.
func _behaviour(ai: MinimaxAI, reference: MinimaxAI, positions: Array, full_targeting := false,
		target_rule := BattleSim.TargetRule.WEAKEST) -> Dictionary:
	var differ := 0
	var damage := 0
	var aoe := 0
	var on_threat := 0
	var single := 0
	for p in positions:
		var sim: BattleSim = p.clone()
		sim.full_targeting = full_targeting
		sim.target_rule = target_rule
		var a := ai.decide(sim).action
		var b := reference.decide(sim).action
		if not a.same_as(b):
			differ += 1
		if not a.is_pass() and a.targets.size() > 1:
			aoe += 1
		if not a.is_pass() and a.targets.size() == 1 and a.skill.targets_enemies():
			single += 1
			if a.targets[0] == _most_dangerous(sim, BattleSim.PLAYER):
				on_threat += 1
		var after := sim.clone()
		after.apply(a, 1)
		damage += sim.total_hp(BattleSim.PLAYER) - after.total_hp(BattleSim.PLAYER)
	var n := float(positions.size())
	return {"differ": "%d/%d" % [differ, positions.size()], "avg_damage": damage / n,
		"aoe": "%d/%d" % [aoe, positions.size()], "on_threat": "%d/%d" % [on_threat, single]}


func _most_dangerous(sim: BattleSim, side: int) -> int:
	var best := -1
	var best_t := -1.0
	for u in sim.alive_units(side):
		var t := sim.threat_of(u)
		if t > best_t:
			best_t = t
			best = u.index
	return best


func _table(header: Array, rows: Array) -> void:
	out.append("| " + " | ".join(header) + " |")
	var sep: Array = []
	for _h in header:
		sep.append("---")
	out.append("| " + " | ".join(sep) + " |")
	for row in rows:
		out.append("| " + " | ".join(row.map(func(v): return str(v))) + " |")
	out.append("")


func _f(v: float, digits := 1) -> String:
	return String.num(v, digits)


# --- Experiments ----------------------------------------------------------------

func _exp1_algorithms(positions: Array) -> void:
	out.append("## 1. Minimax vs Alpha-Beta vs Early Stop (kedalaman 4)\n")
	var configs := [
		["minimax", _npc(MinimaxAI.Algorithm.MINIMAX, 4, "tactical", "balanced", MinimaxAI.Ordering.NONE)],
		["alpha-beta (tanpa ordering)", _npc(MinimaxAI.Algorithm.ALPHABETA, 4, "tactical", "balanced", MinimaxAI.Ordering.NONE)],
		["alpha-beta + heuristic ordering", _npc(MinimaxAI.Algorithm.ALPHABETA, 4)],
		["alpha-beta + ordering, budget 150 node", _npc(MinimaxAI.Algorithm.ALPHABETA, 4, "tactical", "balanced", MinimaxAI.Ordering.HEURISTIC, 150)],
		["alpha-beta + ordering, budget 60 node", _npc(MinimaxAI.Algorithm.ALPHABETA, 4, "tactical", "balanced", MinimaxAI.Ordering.HEURISTIC, 60)],
	]
	var reference: Array = []
	var rows: Array = []
	for c in configs:
		var nodes := 0
		var evals := 0
		var pruned := 0
		var time_ms := 0.0
		var same_action := 0
		var same_value := 0
		var cutoffs := 0
		for i in range(positions.size()):
			var r: MinimaxAI.SearchResult = c[1].decide(positions[i])
			nodes += r.nodes
			evals += r.evals
			pruned += r.pruned
			time_ms += r.time_ms
			if r.cutoff:
				cutoffs += 1
			if reference.size() <= i:
				reference.append(r)
			var ref: MinimaxAI.SearchResult = reference[i]
			if r.action.same_as(ref.action):
				same_action += 1
			if is_equal_approx(_best_score(r), _best_score(ref)):
				same_value += 1
		var n := float(positions.size())
		rows.append([c[0], _f(nodes / n, 0), _f(evals / n, 0), _f(pruned / n, 0), _f(time_ms / n, 2),
			"%d/%d" % [same_action, positions.size()], "%d/%d" % [same_value, positions.size()], cutoffs])
	_table(["Algoritma", "Node/keputusan", "Evaluasi/keputusan", "Cabang dipangkas", "Waktu (ms)", "Aksi sama dgn minimax", "Nilai sama", "Budget tercapai"], rows)


func _exp3_ordering(positions: Array) -> void:
	out.append("## 3. Urutan aksi pada alpha-beta (kedalaman 4)\n")
	var rows: Array = []
	for i in range(MinimaxAI.ORDERING_NAMES.size()):
		var ai := _npc(MinimaxAI.Algorithm.ALPHABETA, 4, "tactical", "balanced", i)
		var nodes := 0
		var pruned := 0
		var time_ms := 0.0
		for p in positions:
			var r := ai.decide(p)
			nodes += r.nodes
			pruned += r.pruned
			time_ms += r.time_ms
		var n := float(positions.size())
		rows.append([MinimaxAI.ORDERING_NAMES[i], _f(nodes / n, 0), _f(pruned / n, 0), _f(time_ms / n, 2)])
	_table(["Ordering", "Node/keputusan", "Cabang dipangkas", "Waktu (ms)"], rows)


func _exp4_depth(positions: Array) -> void:
	out.append("## 4. Kedalaman pencarian (alpha-beta + ordering; win rate diukur dengan full targeting agar pilihan target ikut dicari)\n")
	var rows: Array = []
	for depth in range(1, 7):
		var ai := _npc(MinimaxAI.Algorithm.ALPHABETA, depth)
		var nodes := 0
		var time_ms := 0.0
		for p in positions:
			var r := ai.decide(p)
			nodes += r.nodes
			time_ms += r.time_ms
		var n := float(positions.size())
		var row := [depth, _f(nodes / n, 0), _f(time_ms / n, 2)]
		if depth <= 5:
			var s := _series(ai, 1.0, BattleSim.UltimateMode.AUTO, true)
			row.append_array([_f(s["win_rate"] * 100, 0) + "%", _f(s["avg_turns"]), _f(s["avg_npc_hp"])])
		else:
			row.append_array(["-", "-", "-"])
		rows.append(row)
	_table(["Depth", "Node/keputusan", "Waktu (ms)", "Win rate NPC", "Rata-rata giliran", "Sisa HP NPC"], rows)


func _exp2_evaluations(positions: Array) -> void:
	out.append("## 2. Fungsi evaluasi (alpha-beta, kedalaman 4, full targeting)\n")
	var rows: Array = []
	var reference := _npc(MinimaxAI.Algorithm.ALPHABETA, 4, "tactical")
	for eval_name in BattleEvaluator.EVALUATIONS:
		var ai := _npc(MinimaxAI.Algorithm.ALPHABETA, 4, eval_name)
		var s := _series(ai, 1.0, BattleSim.UltimateMode.AUTO, true)
		var b := _behaviour(ai, reference, positions, true)
		rows.append([eval_name, _f(s["win_rate"] * 100, 0) + "%", s["draws"], _f(s["avg_turns"]), _f(s["avg_npc_hp"]), _f(s["avg_player_hp"]), b["differ"], _f(b["avg_damage"]), b["on_threat"]])
	_table(["Evaluasi", "Win rate NPC", "Seri", "Rata-rata giliran", "Sisa HP NPC", "Sisa HP player", "Aksi beda dari tactical", "Damage langsung rata-rata", "Serangan ke hero paling berbahaya"], rows)


func _exp5_personalities(positions: Array) -> void:
	out.append("## 5. Tingkah laku NPC: personality (evaluasi tactical, kedalaman 4, full targeting)\n")
	var rows: Array = []
	var reference := _npc(MinimaxAI.Algorithm.ALPHABETA, 4, "tactical", "balanced")
	for p in BattleEvaluator.PERSONALITIES:
		var ai := _npc(MinimaxAI.Algorithm.ALPHABETA, 4, "tactical", p)
		var s := _series(ai, 1.0, BattleSim.UltimateMode.AUTO, true)
		var b := _behaviour(ai, reference, positions, true)
		rows.append([p, _f(s["win_rate"] * 100, 0) + "%", _f(s["avg_turns"]), _f(s["avg_dealt"]), _f(s["avg_npc_hp"]), _f(s["avg_player_hp"]), b["differ"], _f(b["avg_damage"]), b["aoe"]])
	_table(["Personality", "Win rate NPC", "Rata-rata giliran", "Damage ke player", "Sisa HP NPC", "Sisa HP player", "Aksi beda dari balanced", "Damage langsung rata-rata", "Aksi AoE"], rows)


func _exp6_expectimax(positions: Array) -> void:
	out.append("## 6. Expectimax pada permainan stokastik (peluang serangan kena = 0.75, kedalaman 3, full targeting)\n")
	var rows: Array = []
	var reference := _npc(MinimaxAI.Algorithm.ALPHABETA, 3)
	var configs := [
		["alpha-beta (mengasumsikan selalu kena)", _npc(MinimaxAI.Algorithm.ALPHABETA, 3)],
		["expectimax", _npc(MinimaxAI.Algorithm.EXPECTIMAX, 3)],
	]
	var stochastic: Array = []
	for p in positions:
		var sim: BattleSim = p.clone()
		sim.hit_chance = 0.75
		stochastic.append(sim)
	for c in configs:
		var s := _series(c[1], 0.75, BattleSim.UltimateMode.AUTO, true)
		var b := _behaviour(c[1], reference, stochastic, true)
		rows.append([c[0], _f(s["win_rate"] * 100, 0) + "%", _f(s["avg_turns"]), _f(s["avg_npc_hp"]), _f(s["avg_nodes"], 0), _f(s["avg_ms"], 2), b["differ"]])
	_table(["Algoritma", "Win rate NPC", "Rata-rata giliran", "Sisa HP NPC", "Node/keputusan", "Waktu (ms)", "Aksi beda dari alpha-beta"], rows)


func _exp7_ultimate_mode(positions: Array) -> void:
	out.append("## 7. Fitur sendiri: mode ultimate AUTO vs CHOICE (alpha-beta, kedalaman 4)\n")
	var rows: Array = []
	for mode in [BattleSim.UltimateMode.AUTO, BattleSim.UltimateMode.CHOICE]:
		var ai := _npc(MinimaxAI.Algorithm.ALPHABETA, 4)
		var nodes := 0
		var branching := 0
		for p in positions:
			var sim: BattleSim = p.clone()
			sim.ultimate_mode = mode
			branching += sim.legal_actions().size()
			nodes += ai.decide(sim).nodes
		var s := _series(ai, 1.0, mode)
		var n := float(positions.size())
		rows.append(["auto" if mode == BattleSim.UltimateMode.AUTO else "choice", _f(branching / n, 2), _f(nodes / n, 0), _f(s["win_rate"] * 100, 0) + "%", _f(s["avg_turns"])])
	_table(["Mode", "Branching rata-rata (akar)", "Node/keputusan", "Win rate NPC", "Rata-rata giliran"], rows)


func _exp8_targeting(positions: Array) -> void:
	out.append("## 8. Fitur sendiri: target berdasarkan aturan vs full targeting (alpha-beta, kedalaman 4)\n")
	var rows: Array = []
	for full in [false, true]:
		var ai := _npc(MinimaxAI.Algorithm.ALPHABETA, 4)
		var nodes := 0
		var branching := 0
		var time_ms := 0.0
		for p in positions:
			var sim: BattleSim = p.clone()
			sim.full_targeting = full
			branching += sim.legal_actions().size()
			var r := ai.decide(sim)
			nodes += r.nodes
			time_ms += r.time_ms
		var s := _series(ai, 1.0, BattleSim.UltimateMode.AUTO, full)
		var n := float(positions.size())
		rows.append(["full" if full else "rule", _f(branching / n, 2), _f(nodes / n, 0), _f(time_ms / n, 2), _f(s["win_rate"] * 100, 0) + "%", s["draws"], _f(s["avg_turns"])])
	_table(["Targeting", "Branching rata-rata (akar)", "Node/keputusan", "Waktu (ms)", "Win rate NPC", "Seri", "Rata-rata giliran"], rows)


func _exp9_target_rule(positions: Array) -> void:
	out.append("## 9. Fitur sendiri: aturan target WEAKEST / THREAT / TOUGHEST / PER_UNIT (alpha-beta, kedalaman 4, rule targeting)\n")
	out.append("Aturan target menentukan siapa yang diserang saat pilihan target tidak dicari. THREAT memakai model ancaman `threat_of`; TOUGHEST menyerang HP tertinggi; PER_UNIT memberi tiap musuh preferensinya sendiri (Bamboo/Bomber: weakest, Bear/Thunder Mage: threat, Fire Mage: toughest). Kill yang tersedia selalu diambil lebih dulu. Kolom terakhir kedua mengukur seberapa sering serangan jatuh ke hero paling berbahaya.\n")
	var rows: Array = []
	var reference := _npc(MinimaxAI.Algorithm.ALPHABETA, 4, "tactical")
	var configs := [
		["weakest + tactical", BattleSim.TargetRule.WEAKEST, "tactical"],
		["threat + tactical", BattleSim.TargetRule.THREAT, "tactical"],
		["threat + threat", BattleSim.TargetRule.THREAT, "threat"],
		["toughest + tactical", BattleSim.TargetRule.TOUGHEST, "tactical"],
		["per_unit + tactical", BattleSim.TargetRule.PER_UNIT, "tactical"],
	]
	for c in configs:
		var ai := _npc(MinimaxAI.Algorithm.ALPHABETA, 4, c[2])
		var s := _series(ai, 1.0, BattleSim.UltimateMode.AUTO, false, c[1])
		var b := _behaviour(ai, reference, positions, false, c[1])
		rows.append([c[0], _f(s["win_rate"] * 100, 0) + "%", _f(s["avg_turns"]), _f(s["avg_npc_hp"]), _f(s["avg_player_hp"]), b["on_threat"], b["differ"]])
	_table(["Konfigurasi", "Win rate NPC", "Rata-rata giliran", "Sisa HP NPC", "Sisa HP player", "Serangan ke hero paling berbahaya", "Aksi beda dari weakest+tactical"], rows)

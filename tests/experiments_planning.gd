extends Node
## Experiment runner for Tahap 4 (automated planning for the boss).
## Run: godot --headless --path . res://tests/experiments_planning_runner.tscn
## Writes markdown tables to docs/experiments_planning.md and prints them.
## Env: EXP_GAMES (games per configuration, default 30), EXP_POSITIONS
## (sampled boss-turn positions, default 30).

const PARTY: Array[String] = ["ninja", "flame", "knight", "monk"]
const BOSS := "giant_bamboo"
const SEARCH_NODE_LIMIT := 1500

var games_per_config := 30
var position_samples := 30
## Boss max HP override (env EXP_BOSS_HP) for balance sweeps; 0 = roster value.
var boss_hp_override := 0
## Env EXP_ONLY = model|search|goals|execution|brains|ablation runs one section.
var only := ""
var out: Array[String] = []
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	if OS.get_environment("EXP_GAMES") != "":
		games_per_config = int(OS.get_environment("EXP_GAMES"))
	if OS.get_environment("EXP_POSITIONS") != "":
		position_samples = int(OS.get_environment("EXP_POSITIONS"))
	if OS.get_environment("EXP_BOSS_HP") != "":
		boss_hp_override = int(OS.get_environment("EXP_BOSS_HP"))
	only = OS.get_environment("EXP_ONLY")
	var t0 := Time.get_ticks_msec()
	out.append("# Hasil Eksperimen Tahap 4: Automated Planning untuk Boss\n")
	out.append("Dihasilkan oleh `tests/experiments_planning.gd`. Boss: Giant Bamboo (%d HP, Wind) melawan party Ninja, Flame, Knight, Monk dengan HP awal acak 70-100 %% (seed tetap, %d pertandingan per konfigurasi). Lawan (pihak player) = kebijakan tetap alpha-beta kedalaman 2, evaluasi tactical, full targeting. Planner default: A* heuristik damage + pruning, panjang rencana maks. 4, skor gain_rate, fallback alpha-beta kedalaman 4.\n" % [_boss_data().max_hp, games_per_config])
	if boss_hp_override > 0:
		out.append("_HP boss diubah menjadi %d untuk run ini._\n" % boss_hp_override)
	var positions := _sample_positions() if only in ["", "model", "search", "goals", "ablation"] else []
	if only in ["", "model"]:
		_exp_model_validity(positions)
	if only in ["", "search"]:
		_exp_search(positions)
	if only in ["", "goals"]:
		_exp_goal_selection(positions)
	if only in ["", "execution"]:
		_exp_execution()
	if only in ["", "brains"]:
		_exp_brains()
	if only in ["", "ablation"]:
		_exp_ablation(positions)
	out.append("\n_Total waktu eksperimen: %.1f detik._\n" % ((Time.get_ticks_msec() - t0) / 1000.0))
	var text := "\n".join(out)
	if only == "" and boss_hp_override == 0:
		var f := FileAccess.open("res://docs/experiments_planning.md", FileAccess.WRITE)
		f.store_string(text)
		f.close()
	print(text)
	get_tree().quit()


# --- Helpers --------------------------------------------------------------------

func _player_ai(depth: int) -> MinimaxAI:
	var ai := MinimaxAI.new()
	ai.side = BattleSim.PLAYER
	ai.algorithm = MinimaxAI.Algorithm.ALPHABETA
	ai.depth = depth
	ai.eval_name = "tactical"
	ai.personality = "balanced"
	ai.ordering = MinimaxAI.Ordering.HEURISTIC
	ai.rng.seed = 1
	return ai


func _boss_ai(algorithm: MinimaxAI.Algorithm, depth: int) -> MinimaxAI:
	var ai := MinimaxAI.new()
	ai.side = BattleSim.NPC
	ai.algorithm = algorithm
	ai.depth = depth
	ai.eval_name = "tactical"
	ai.personality = "balanced"
	ai.ordering = MinimaxAI.Ordering.HEURISTIC
	ai.rng.seed = 2
	return ai


func _brain(mode: BossBrain.Mode, heuristic := BossPlanner.Heuristic.DAMAGE, scoring := BossPlanner.Scoring.GAIN_RATE,
		max_len := 4, fallback_algorithm := MinimaxAI.Algorithm.ALPHABETA, fallback_depth := 4) -> BossBrain:
	var b := BossBrain.new()
	b.mode = mode
	b.planner.heuristic = heuristic
	b.planner.scoring = scoring
	b.planner.max_plan_length = max_len
	b.planner.node_limit = SEARCH_NODE_LIMIT
	b.fallback = _boss_ai(fallback_algorithm, fallback_depth)
	return b


## Boss whose skills lost every precondition / status effect (ablation).
func _boss_data() -> UnitData:
	var data := Roster.get_unit(BOSS)
	if boss_hp_override > 0:
		data.max_hp = boss_hp_override
	return data


## Boss without setup -> payoff chains (ablation): Sap Surge and Thorn Storm
## are removed and Bamboo Spear is always 10, so no action enables another.
## Single-action gates (Harden Bark only while unshielded, Regrow once under
## 50 %) stay, because they do not create multi-step structure.
func _flat_boss() -> UnitData:
	var data := _boss_data()
	var kept: Array[SkillData] = []
	for s in data.skills:
		if s.id == "sap_surge" or s.id == "thorn_storm":
			continue
		s.requires = []
		s.grants = []
		s.consumes = []
		s.power_if_user_enraged = 0
		kept.append(s)
	data.skills = kept
	return data


func _new_game(game_index: int, flat := false) -> BattleSim:
	rng.seed = 1000 + game_index
	var sim := BattleSim.new()
	for id in PARTY:
		var data := Roster.get_unit(id)
		sim.add_unit(data, BattleSim.PLAYER, int(round(data.max_hp * rng.randf_range(0.7, 1.0))))
	sim.add_unit(_flat_boss() if flat else _boss_data(), BattleSim.NPC)
	sim.full_targeting = true
	sim.side_to_move = BattleSim.PLAYER
	sim.rng.seed = 5000 + game_index
	return sim


## Plays one game to the end. Boss-turn snapshots go to [param record]
## (every [param every]-th decision) when every > 0.
func _play(sim: BattleSim, brain: BossBrain, player: MinimaxAI, record: Array = [], every := 0) -> Dictionary:
	var boss_ms := 0.0
	var decisions := 0
	var skills := {}
	var reasons := {}
	while not sim.is_terminal():
		if sim.side_to_move == BattleSim.PLAYER:
			sim.apply(player.decide(sim).action, 1)
		else:
			if every > 0 and decisions % every == 0:
				record.append(sim.clone())
			var d := brain.decide(sim)
			boss_ms += d.time_ms
			decisions += 1
			if not d.action.is_pass():
				skills[d.action.skill.id] = skills.get(d.action.skill.id, 0) + 1
			if d.replanned:
				reasons[d.reason] = reasons.get(d.reason, 0) + 1
			sim.apply(d.action, 1)
	var boss := sim.side_units(BattleSim.NPC)[0]
	return {"winner": sim.winner(), "turns": sim.turn, "boss_hp": boss.hp, "decisions": decisions,
		"ms": boss_ms / float(maxi(1, decisions)), "skills": skills, "reasons": reasons, "brain": brain}


func _series(make_brain: Callable, player_depth := 2, flat := false) -> Dictionary:
	var wins := 0
	var draws := 0
	var turns := 0
	var boss_hp := 0
	var ms := 0.0
	var decisions := 0
	var skills := {}
	var reasons := {}
	var plans := 0
	var replans := 0
	var fallbacks := 0
	var steps := 0
	var continued := 0
	for g in range(games_per_config):
		var brain: BossBrain = make_brain.call()
		var r := _play(_new_game(g, flat), brain, _player_ai(player_depth))
		if r["winner"] == BattleSim.NPC:
			wins += 1
		elif r["winner"] == -1:
			draws += 1
		turns += r["turns"]
		boss_hp += r["boss_hp"]
		ms += r["ms"] * r["decisions"]
		decisions += r["decisions"]
		for k in r["skills"]:
			skills[k] = skills.get(k, 0) + r["skills"][k]
		for k in r["reasons"]:
			reasons[k] = reasons.get(k, 0) + r["reasons"][k]
		plans += brain.plans_made
		replans += brain.replans
		fallbacks += brain.fallbacks
		steps += brain.steps_executed
		continued += brain.steps_continued
	var n := float(games_per_config)
	return {"wins": wins, "draws": draws, "win_rate": 100.0 * wins / n, "turns": turns / n, "boss_hp": boss_hp / n,
		"ms": ms / float(maxi(1, decisions)), "decisions": decisions / n, "skills": skills, "reasons": reasons,
		"plans": plans / n, "replans": replans / n, "fallbacks": fallbacks / n,
		"continuation": 100.0 * continued / float(maxi(1, steps)), "steps": steps / n}


var stunned_positions := 0


## Boss-turn positions from planner games; turns where the boss is stunned
## (Knight's Bump) are counted and skipped, since nothing can be planned there.
func _sample_positions() -> Array:
	var all: Array = []
	for g in range(6):
		_play(_new_game(100 + g), _brain(BossBrain.Mode.PLANNER), _player_ai(2), all, 2)
	var usable: Array = []
	for pos in all:
		if pos.side_units(BattleSim.NPC)[0].is_stunned():
			stunned_positions += 1
		else:
			usable.append(pos)
	var positions: Array = []
	if usable.is_empty():
		return positions
	for i in range(position_samples):
		positions.append(usable[int(float(i) * usable.size() / position_samples)])
	return positions


func _skill_share(skills: Dictionary, id: String) -> float:
	var total := 0
	for k in skills:
		total += skills[k]
	return 100.0 * skills.get(id, 0) / float(maxi(1, total))


func _pct(a: int, b: int) -> String:
	return "%.1f %%" % (100.0 * a / float(maxi(1, b)))


# --- E1: model validity ---------------------------------------------------------------

func _exp_model_validity(positions: Array) -> void:
	out.append("\n## 1. Validitas model planning (PlanModel vs BattleSim)\n")
	out.append("Pada setiap posisi uji: aksi applicable menurut model dibandingkan dengan `legal_actions` simulasi (full targeting); lalu untuk tiga aksi acak, state yang diprediksi `PlanModel.apply` dibandingkan dengan simulasi setelah boss bertindak dan player pass. Posisi uji diambil dari giliran boss pada 6 pertandingan planner; %d dari %d giliran boss terkena stun (Bump Knight) dan tidak dipakai.\n" % [stunned_positions, stunned_positions + positions.size()])
	rng.seed = 77
	var action_sets := 0
	var action_match := 0
	var steps := 0
	var exact := 0
	var phase2 := 0
	var branching := 0
	for pos in positions:
		var sim: BattleSim = pos
		var state := PlanModel.from_sim(sim)
		if state.has_flag(state.actor, "phase2"):
			phase2 += 1
		var actions := PlanModel.ground_actions(state)
		branching += actions.size()
		var model_ids := []
		for a in actions:
			model_ids.append(a.id())
		model_ids.sort()
		var sim_ids := []
		for a in sim.legal_actions(BattleSim.NPC):
			if not a.is_pass():
				var t: PackedStringArray = []
				for i in a.targets:
					t.append(str(i))
				sim_ids.append("%s(%s)" % [a.skill.id, ",".join(t)])
		sim_ids.sort()
		action_sets += 1
		if model_ids == sim_ids:
			action_match += 1
		for k in range(3):
			if actions.is_empty():
				break
			var action: PlanModel.PlanAction = actions[rng.randi_range(0, actions.size() - 1)]
			var predicted := PlanModel.apply(state, action)
			var copy := sim.clone()
			copy.apply(action.to_battle_action(), 1)
			copy.apply(BattleAction.pass_action())
			steps += 1
			if predicted.equals(PlanModel.from_sim(copy, state.actor)):
				exact += 1
	out.append("| Posisi uji | Posisi fase 2 | Aksi applicable rata-rata | Himpunan aksi sama dengan simulasi | Langkah diuji | Prediksi state tepat |")
	out.append("|---|---|---|---|---|---|")
	out.append("| %d | %d | %.2f | %d/%d | %d | %d/%d (%s) |" % [positions.size(), phase2, branching / float(maxi(1, positions.size())),
		action_match, action_sets, steps, exact, steps, _pct(exact, steps)])


# --- E2: search algorithms ---------------------------------------------------------------

func _exp_search(positions: Array) -> void:
	out.append("\n## 2. Algoritma pencarian: uniform cost (BFS) vs A* dengan heuristik goal_count / damage\n")
	out.append("Setiap posisi uji x setiap goal kandidat = satu masalah planning (panjang maks. 4, batas %d node diekspansi). Pruning = cabang dengan batas bawah damage melampaui sisa kedalaman dibuang. 'Optimal' dihitung pada masalah yang diselesaikan semua konfigurasi: panjang rencana sama dengan panjang terpendek yang ditemukan.\n" % SEARCH_NODE_LIMIT)
	var configs := [
		{"label": "Uniform cost (h = 0), tanpa pruning", "h": BossPlanner.Heuristic.NONE, "prune": false},
		{"label": "Uniform cost (h = 0) + pruning", "h": BossPlanner.Heuristic.NONE, "prune": true},
		{"label": "A* goal_count + pruning", "h": BossPlanner.Heuristic.GOAL_COUNT, "prune": true},
		{"label": "A* damage, tanpa pruning", "h": BossPlanner.Heuristic.DAMAGE, "prune": false},
		{"label": "A* damage + pruning (default)", "h": BossPlanner.Heuristic.DAMAGE, "prune": true},
	]
	var stats := []
	for c in configs:
		stats.append({"problems": 0, "found": 0, "budget": 0, "expanded": 0, "generated": 0, "ms": 0.0, "common_len": 0, "optimal": 0})
	var problems := 0
	var solvable := 0
	var common := 0
	var reference := _brain(BossBrain.Mode.PLANNER).planner
	for pos in positions:
		var state := PlanModel.from_sim(pos)
		for goal in reference.candidate_goals(state):
			problems += 1
			var results := []
			for i in range(configs.size()):
				var p := BossPlanner.new()
				p.heuristic = configs[i]["h"]
				p.prune_unreachable = configs[i]["prune"]
				p.max_plan_length = 4
				p.node_limit = SEARCH_NODE_LIMIT
				var r := p.plan_for(state, goal)
				results.append(r)
				stats[i]["problems"] += 1
				stats[i]["expanded"] += r.expanded
				stats[i]["generated"] += r.generated
				stats[i]["ms"] += r.time_ms
				if r.found:
					stats[i]["found"] += 1
				if r.note == "node limit":
					stats[i]["budget"] += 1
			var all_found := true
			var shortest := 99
			for r in results:
				all_found = all_found and r.found
				if r.found:
					shortest = mini(shortest, r.length())
			if shortest < 99:
				solvable += 1
			if all_found:
				common += 1
				for i in range(configs.size()):
					stats[i]["common_len"] += results[i].length()
					if results[i].length() == shortest:
						stats[i]["optimal"] += 1
	out.append("Masalah planning: %d (goal dengan rencana pada minimal satu konfigurasi: %d; diselesaikan semua konfigurasi: %d).\n" % [problems, solvable, common])
	out.append("| Konfigurasi | Rencana ditemukan | Berhenti karena batas node | Node diekspansi rata-rata | Node dibangkitkan rata-rata | Waktu rata-rata (ms) | Panjang rencana rata-rata (masalah bersama) | Optimal |")
	out.append("|---|---|---|---|---|---|---|---|")
	for i in range(configs.size()):
		var s: Dictionary = stats[i]
		var n := float(maxi(1, s["problems"]))
		out.append("| %s | %d/%d | %d | %.1f | %.1f | %.2f | %.2f | %s |" % [configs[i]["label"], s["found"], s["problems"], s["budget"],
			s["expanded"] / n, s["generated"] / n, s["ms"] / n, s["common_len"] / float(maxi(1, common)), _pct(s["optimal"], common)])


# --- E3: goal selection ---------------------------------------------------------------

func _exp_goal_selection(positions: Array) -> void:
	out.append("\n## 3. Pemilihan goal: skor gain_rate vs end_value\n")
	out.append("`decide()` dijalankan pada setiap posisi uji dengan dua cara menilai rencana. gain_rate = (V(akhir) - V(sekarang)) / panjang; end_value = V(akhir) - 3 x panjang. Kolom jenis goal = persentase posisi di mana goal jenis itu terpilih.\n")
	var modes := [
		{"label": "gain_rate (default)", "scoring": BossPlanner.Scoring.GAIN_RATE},
		{"label": "end_value", "scoring": BossPlanner.Scoring.END_VALUE},
	]
	var chosen := []
	for m in modes:
		var kinds := {"kill": 0, "burn_all": 0, "fortify": 0, "recover": 0, "none": 0}
		var length := 0
		var found := 0
		var ms := 0.0
		var picks := []
		for pos in positions:
			var p := _brain(BossBrain.Mode.PLANNER, BossPlanner.Heuristic.DAMAGE, m["scoring"]).planner
			var r := p.decide(PlanModel.from_sim(pos))
			ms += r.total_time_ms
			if r.found:
				kinds[r.goal.kind] += 1
				length += r.length()
				found += 1
				picks.append(r.goal.name + "|" + str(r.length()))
			else:
				kinds["none"] += 1
				picks.append("none")
		chosen.append(picks)
		m["row"] = "| %s | %s | %s | %s | %s | %s | %.2f | %.1f |" % [m["label"], _pct(kinds["kill"], positions.size()), _pct(kinds["burn_all"], positions.size()),
			_pct(kinds["fortify"], positions.size()), _pct(kinds["recover"], positions.size()), _pct(kinds["none"], positions.size()),
			length / float(maxi(1, found)), ms / float(maxi(1, positions.size()))]
	var agree := 0
	for i in range(positions.size()):
		if chosen[0][i] == chosen[1][i]:
			agree += 1
	out.append("| Skor | Kill | Burn every hero | Fortify | Recover | Tidak ada goal | Panjang rencana rata-rata | Waktu decide (ms) |")
	out.append("|---|---|---|---|---|---|---|---|")
	for m in modes:
		out.append(m["row"])
	out.append("\nKedua skor memilih goal dan panjang yang sama pada %d/%d posisi (%s).\n" % [agree, positions.size(), _pct(agree, positions.size())])


# --- E4: execution monitoring ---------------------------------------------------------------

func _exp_execution() -> void:
	out.append("\n## 4. Eksekusi: replanning vs panjang rencana dan kekuatan player\n")
	out.append("Pertandingan penuh dengan otak planner. 'Replan basi' = rencana dibuang karena precondition gagal atau sisa langkah tidak lagi mencapai goal (akibat aksi player); 'lanjutan' = persentase langkah yang berasal dari rencana giliran sebelumnya.\n")
	var configs := [
		{"label": "maks. 2 langkah, player d2", "len": 2, "depth": 2},
		{"label": "maks. 3 langkah, player d2", "len": 3, "depth": 2},
		{"label": "maks. 4 langkah, player d2 (default)", "len": 4, "depth": 2},
		{"label": "maks. 5 langkah, player d2", "len": 5, "depth": 2},
		{"label": "maks. 4 langkah, player d1 (greedy)", "len": 4, "depth": 1},
		{"label": "maks. 4 langkah, player d3", "len": 4, "depth": 3},
	]
	out.append("| Konfigurasi | Win rate boss | Seri | Giliran rata-rata | Keputusan boss/game | Rencana/game | Replan basi/game | Fallback/game | Langkah lanjutan | Waktu/keputusan (ms) | Alasan replan (precondition / goal tak tercapai / selesai / goal tercapai) |")
	out.append("|---|---|---|---|---|---|---|---|---|---|---|")
	for c in configs:
		var s := _series(func(): return _brain(BossBrain.Mode.PLANNER, BossPlanner.Heuristic.DAMAGE, BossPlanner.Scoring.GAIN_RATE, c["len"]), c["depth"])
		var rs: Dictionary = s["reasons"]
		out.append("| %s | %.0f %% | %d | %.1f | %.1f | %.2f | %.2f | %.2f | %.0f %% | %.1f | %d / %d / %d / %d |" % [c["label"], s["win_rate"], s["draws"], s["turns"],
			s["decisions"], s["plans"], s["replans"], s["fallbacks"], s["continuation"], s["ms"],
			rs.get("precondition failed", 0), rs.get("goal unreachable by plan", 0), rs.get("plan finished", 0), rs.get("goal reached", 0)])


# --- E5: boss brains ---------------------------------------------------------------

func _exp_brains() -> void:
	out.append("\n## 5. Otak boss: minimax vs greedy vs planner vs hybrid\n")
	out.append("Pertandingan penuh melawan player alpha-beta kedalaman 2. minimax = alpha-beta kedalaman 4 (kontrol), greedy = kedalaman 1, planner = default, hybrid = langkah pertama tiap rencana kandidat menjadi aksi akar alpha-beta kedalaman 4. Kolom skill = persentase aksi boss yang memakai skill tersebut.\n")
	var configs := [
		{"label": "minimax (alpha-beta d4)", "make": func(): return _brain(BossBrain.Mode.MINIMAX)},
		{"label": "greedy (d1)", "make": func(): return _brain(BossBrain.Mode.MINIMAX, BossPlanner.Heuristic.DAMAGE, BossPlanner.Scoring.GAIN_RATE, 4, MinimaxAI.Algorithm.GREEDY, 1)},
		{"label": "planner (default)", "make": func(): return _brain(BossBrain.Mode.PLANNER)},
		{"label": "hybrid", "make": func(): return _brain(BossBrain.Mode.HYBRID)},
	]
	out.append("| Otak | Win rate boss | Seri | Giliran rata-rata | Sisa HP boss rata-rata | Waktu/keputusan (ms) | Sap Surge | Bamboo Spear | Thorn Storm | Harden Bark | Regrow | Root Slam |")
	out.append("|---|---|---|---|---|---|---|---|---|---|---|---|")
	for c in configs:
		var s := _series(c["make"])
		var sk: Dictionary = s["skills"]
		out.append("| %s | %.0f %% | %d | %.1f | %.1f | %.1f | %.0f %% | %.0f %% | %.0f %% | %.0f %% | %.0f %% | %.0f %% |" % [c["label"], s["win_rate"], s["draws"], s["turns"], s["boss_hp"], s["ms"],
			_skill_share(sk, "sap_surge"), _skill_share(sk, "bamboo_spear"), _skill_share(sk, "thorn_storm"),
			_skill_share(sk, "harden_bark"), _skill_share(sk, "regrow"), _skill_share(sk, "root_slam")])


# --- E6: ablation (flat boss) ---------------------------------------------------------------

func _exp_ablation(positions: Array) -> void:
	out.append("\n## 6. Ablasi: boss tanpa prasyarat (skill datar)\n")
	out.append("Rantai setup -> payoff dihapus: Sap Surge dan Thorn Storm dibuang, Bamboo Spear selalu 10, tidak ada status enraged. Gerbang satu aksi (Harden Bark hanya saat tanpa shield, Regrow sekali di bawah 50 %) dipertahankan karena tidak membentuk struktur multi-langkah. Jika nilai planning berasal dari struktur aksi, planner pada boss datar seharusnya mendekati greedy.\n")
	var agree_flat := 0
	var agree_struct := 0
	var n := 0
	var flat_data := _flat_boss()
	for pos in positions:
		var sim: BattleSim = pos
		var greedy := _boss_ai(MinimaxAI.Algorithm.GREEDY, 1)
		var planner := _brain(BossBrain.Mode.PLANNER).planner
		var r := planner.decide(PlanModel.from_sim(sim))
		var g := greedy.decide(sim)
		n += 1
		if r.found and r.steps[0].to_battle_action().same_as(g.action):
			agree_struct += 1
		var flat := sim.clone()
		var boss := flat.side_units(BattleSim.NPC)[0]
		boss.data = flat_data
		boss.flags = {}
		var rf := planner.decide(PlanModel.from_sim(flat))
		var gf := greedy.decide(flat)
		if rf.found and rf.steps[0].to_battle_action().same_as(gf.action):
			agree_flat += 1
	out.append("Kesamaan aksi pertama planner dengan greedy pada posisi uji: boss berstruktur %d/%d (%s), boss datar %d/%d (%s).\n" % [
		agree_struct, n, _pct(agree_struct, n), agree_flat, n, _pct(agree_flat, n)])
	var configs := [
		{"label": "boss datar: greedy (d1)", "make": func(): return _brain(BossBrain.Mode.MINIMAX, BossPlanner.Heuristic.DAMAGE, BossPlanner.Scoring.GAIN_RATE, 4, MinimaxAI.Algorithm.GREEDY, 1)},
		{"label": "boss datar: minimax (alpha-beta d4)", "make": func(): return _brain(BossBrain.Mode.MINIMAX)},
		{"label": "boss datar: planner", "make": func(): return _brain(BossBrain.Mode.PLANNER)},
	]
	out.append("| Otak | Win rate boss | Seri | Giliran rata-rata | Sisa HP boss rata-rata | Rencana/game | Langkah lanjutan | Waktu/keputusan (ms) |")
	out.append("|---|---|---|---|---|---|---|---|")
	for c in configs:
		var s := _series(c["make"], 2, true)
		out.append("| %s | %.0f %% | %d | %.1f | %.1f | %.2f | %.0f %% | %.1f |" % [c["label"], s["win_rate"], s["draws"], s["turns"], s["boss_hp"], s["plans"], s["continuation"], s["ms"]])

extends RefCounted
## Tahap 4 tests: the planning model ([PlanModel]) against the simulation.
## Driven by tests/test_battle.gd (same headless runner).

var failures := 0
var rng := RandomNumberGenerator.new()

const FIXTURE_HP := {"ninja": 40, "flame": 35, "knight": 60, "monk": 35, "giant_bamboo": 150}


func run() -> void:
	rng.seed = 2024
	_test_snapshot_and_grounding()
	_test_effects()
	_test_literals()
	_test_model_matches_sim()
	_test_planner_search()
	_test_planner_goals()
	_test_planner_executes()
	_test_brain()


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   - " + msg)
	else:
		failures += 1
		print("  FAIL - " + msg)


# --- Helpers ---------------------------------------------------------------------

func _boss_sim() -> BattleSim:
	var s := BattleSim.create(["ninja", "flame", "knight", "monk"], ["giant_bamboo"])
	for u in s.units:
		if FIXTURE_HP.has(u.data.id):
			u.data.max_hp = FIXTURE_HP[u.data.id]
			u.hp = u.data.max_hp
	s.side_to_move = BattleSim.NPC
	s.full_targeting = true
	return s


func _u(sim: BattleSim, id: String) -> UnitState:
	for u in sim.units:
		if u.data.id == id:
			return u
	return null


func _skill(sim: BattleSim, skill_id: String) -> SkillData:
	for sk in _u(sim, "giant_bamboo").data.skills:
		if sk.id == skill_id:
			return sk
	return null


func _action(sim: BattleSim, skill_id: String, target_ids: Array = []) -> PlanModel.PlanAction:
	var boss := _u(sim, "giant_bamboo")
	var targets: Array[int] = []
	for id in target_ids:
		targets.append(_u(sim, id).index)
	if targets.is_empty():
		var sk := _skill(sim, skill_id)
		match sk.target_mode:
			SkillData.TargetMode.SELF:
				targets.append(boss.index)
			SkillData.TargetMode.ALL_ENEMIES:
				for f in sim.alive_units(BattleSim.PLAYER):
					targets.append(f.index)
	return PlanModel.PlanAction.make(boss.index, _skill(sim, skill_id), targets)


func _ids(actions: Array) -> Array:
	var out := []
	for a in actions:
		out.append(a.id())
	out.sort()
	return out


func _sim_action_ids(sim: BattleSim) -> Array:
	var out := []
	for a in sim.legal_actions(BattleSim.NPC):
		if a.is_pass():
			continue
		var t: PackedStringArray = []
		for i in a.targets:
			t.append(str(i))
		out.append("%s(%s)" % [a.skill.id, ",".join(t)])
	out.sort()
	return out


# --- Tests -------------------------------------------------------------------------

func _test_snapshot_and_grounding() -> void:
	print("[Plan model: state and grounding]")
	var sim := _boss_sim()
	var boss := _u(sim, "giant_bamboo")
	var state := PlanModel.from_sim(sim)
	check(state.actor == boss.index, "from_sim picks the boss as the planning actor (%d)" % state.actor)
	check(state.hp[boss.index] == 150 and state.hp[_u(sim, "monk").index] == 35 and state.potions == 3,
		"snapshot copies HP and potions (%s)" % state.describe())
	var actions := PlanModel.ground_actions(state)
	check(actions.size() == 10, "start: 4 Root Slam + Sap Surge + 4 Bamboo Spear + Harden Bark = 10 grounded actions (%d)" % actions.size())
	check(_ids(actions) == _sim_action_ids(sim), "grounded actions equal BattleSim.legal_actions under full targeting")
	check(PlanModel.applicable(state, _action(sim, "sap_surge")) and not PlanModel.applicable(state, _action(sim, "thorn_storm")),
		"applicable(): Sap Surge yes, Thorn Storm (needs rage + phase 2) no")
	check(PlanModel.holds_in_sim(sim, _action(sim, "harden_bark")), "holds_in_sim checks the real simulation")
	boss.shield = 15
	check(not PlanModel.holds_in_sim(sim, _action(sim, "harden_bark")), "holds_in_sim fails once the real boss is shielded")
	boss.shield = 0
	var again := PlanModel.from_sim(sim)
	check(state.equals(again) and state.key() == again.key(), "equal states have equal keys")
	check(PlanModel.from_sim(state.to_sim()).equals(state), "to_sim() round-trips the abstract state")
	var battle_action := _action(sim, "bamboo_spear", ["monk"]).to_battle_action()
	check(battle_action.unit == boss.index and battle_action.skill.id == "bamboo_spear" and battle_action.targets == [_u(sim, "monk").index],
		"to_battle_action() builds the executable action")


func _test_effects() -> void:
	print("[Plan model: effects]")
	var sim := _boss_sim()
	var boss := _u(sim, "giant_bamboo")
	var monk := _u(sim, "monk")
	var flame := _u(sim, "flame")
	var s0 := PlanModel.from_sim(sim)
	var s1 := PlanModel.apply(s0, _action(sim, "sap_surge"))
	check(s1.has_flag(boss.index, "enraged") and not s0.has_flag(boss.index, "enraged"), "apply() returns a new state; Sap Surge grants enraged without mutating the parent")
	check(s1.ult == 25, "self-buff charges the ultimate in the model too (%d)" % s1.ult)
	check(PlanModel.predicted_damage(s1, _skill(sim, "bamboo_spear"), monk.index) == 24
		and PlanModel.predicted_damage(s1, _skill(sim, "bamboo_spear"), flame.index) == 12,
		"predicted_damage: enraged 24 on Monk, halved to 12 on Flame (Fire beats Wind)")
	var s2 := PlanModel.apply(s1, _action(sim, "bamboo_spear", ["monk"]))
	check(s2.hp[monk.index] == 11 and not s2.has_flag(boss.index, "enraged"), "Bamboo Spear: Monk 35 -> 11 and the rage is spent")
	check(_ids(PlanModel.ground_actions(s2)).has("sap_surge(%d)" % boss.index), "Sap Surge is applicable again after the rage is spent")
	# Phase 2 after the turn boundaries, then Thorn Storm with burn ticks.
	var s3 := s2.clone()
	s3.hp[boss.index] = 60
	s3 = PlanModel.apply(s3, _action(sim, "sap_surge"))
	check(s3.has_flag(boss.index, "phase2"), "the boss's next turn start sets phase2 below 50% HP")
	var storm := _action(sim, "thorn_storm")
	check(PlanModel.applicable(s3, storm), "Thorn Storm becomes applicable (enraged + phase2)")
	var s4 := PlanModel.apply(s3, storm)
	check(s4.hp[monk.index] == 11 - 6 - 2 and s4.burn[monk.index] == 1, "Thorn Storm then the hero burn tick: Monk 11 -> 5 -> 3, burn 2 -> 1 (hp %d burn %d)" % [s4.hp[monk.index], s4.burn[monk.index]])
	check(s4.hp[flame.index] == 35 - 3 - 2, "Flame takes 3 (halved) + 2 burn (hp %d)" % s4.hp[flame.index])
	# Kill, shield absorb, boss burn tick and Regrow.
	var s5 := s4.clone()
	s5.ult = 0  # a full bar would leave only the ultimate (AUTO mode)
	s5.hp[monk.index] = 3
	s5.shield[monk.index] = 4
	s5 = PlanModel.apply(s5, _action(sim, "root_slam", ["monk"]))
	check(s5.hp[monk.index] == 0 and s5.burn[monk.index] == 0 and not s5.is_alive(monk.index), "6 damage through 4 shield kills Monk at 3 HP and clears the burn")
	check(not s5.alive_units(BattleSim.PLAYER).has(monk.index) and _ids(PlanModel.ground_actions(s5)).has("root_slam(%d)" % flame.index)
		and not _ids(PlanModel.ground_actions(s5)).has("root_slam(%d)" % monk.index), "dead heroes are no longer targets")
	var s6 := s5.clone()
	s6.burn[boss.index] = 2
	s6 = PlanModel.apply(s6, _action(sim, "regrow"))
	check(s6.hp[boss.index] == 60 + 25 - 2 and s6.burn[boss.index] == 1 and s6.potions == 2 and s6.has_flag(boss.index, "used_regrow"),
		"Regrow heals 25, drinks a potion, then the boss's own burn ticks (hp %d)" % s6.hp[boss.index])
	check(not PlanModel.applicable(s6, _action(sim, "regrow")), "Regrow is spent in the model")
	var s7 := s0.clone()
	s7.ult = 100
	check(_ids(PlanModel.ground_actions(s7)) == ["bamboo_fury(%s)" % ",".join(PackedStringArray(["0", "1", "2", "3"]))], "AUTO ultimate mode: a full bar leaves only Bamboo Fury (%s)" % str(_ids(PlanModel.ground_actions(s7))))
	var s8 := PlanModel.apply(s7, PlanModel.ground_actions(s7)[0])
	check(s8.ult == 0 and s8.hp[monk.index] == 35 - 8, "the ultimate empties the bar and hits everyone (monk %d)" % s8.hp[monk.index])


func _test_literals() -> void:
	print("[Plan model: literals]")
	var sim := _boss_sim()
	var boss := _u(sim, "giant_bamboo")
	var monk := _u(sim, "monk")
	var s := PlanModel.from_sim(sim)
	check(s.holds("alive(%d)" % monk.index) and not s.holds("dead(%d)" % monk.index), "alive/dead literals")
	check(s.holds("not enraged(%d)" % boss.index) and s.holds("!burning(%d)" % monk.index), "negation with 'not ' and '!'")
	var parsed := PlanModel.parse_literal(" not low_hp(4) ")
	check(parsed["neg"] and parsed["pred"] == "low_hp" and parsed["unit"] == 4, "parse_literal splits negation, predicate and unit")
	var goal := ["dead(%d)" % monk.index, "enraged(%d)" % boss.index]
	check(s.unsatisfied(goal) == 2, "goal-count: 2 unsatisfied literals")
	var s2 := PlanModel.apply(s, _action(sim, "sap_surge"))
	check(s2.unsatisfied(goal) == 1 and not s2.holds_all(goal), "goal-count drops to 1 after Sap Surge")
	s2.hp[monk.index] = 0
	check(s2.holds_all(goal), "holds_all once Monk is dead and the boss enraged")
	check(s2.holds("low_hp(%d)" % monk.index) and s2.holds("not low_hp(%d)" % boss.index), "low_hp literal follows the HP ratio")


## Randomised fidelity: from many perturbed positions, the model's applicable
## actions must equal the simulation's legal actions and apply() must predict
## the simulation exactly when the player passes.
func _test_model_matches_sim() -> void:
	print("[Plan model vs BattleSim]")
	var walks := 150
	var steps := 0
	var mismatched_actions := 0
	var mismatched_states := 0
	var first_error := ""
	var used_skills := {}
	for w in range(walks):
		var sim := _boss_sim()
		var boss := _u(sim, "giant_bamboo")
		for u in sim.alive_units(BattleSim.PLAYER):
			u.hp = rng.randi_range(1, u.data.max_hp)
			u.burn = rng.randi_range(0, 2)
			u.shield = 10 if rng.randf() < 0.2 else 0
		boss.hp = rng.randi_range(20, boss.data.max_hp)
		boss.burn = rng.randi_range(0, 2)
		boss.shield = 15 if rng.randf() < 0.3 else 0
		boss.ult = 25 * rng.randi_range(0, 4)
		if rng.randf() < 0.3:
			boss.set_flag("enraged")
		if boss.hp_ratio() < 0.5 and rng.randf() < 0.5:
			boss.set_flag("phase2")
		sim.potions[BattleSim.NPC] = rng.randi_range(0, 3)
		var state := PlanModel.from_sim(sim)
		for step in range(6):
			if sim.is_terminal():
				break
			var actions := PlanModel.ground_actions(state)
			if _ids(actions) != _sim_action_ids(sim):
				mismatched_actions += 1
				if first_error == "":
					first_error = "actions differ at %s: model %s vs sim %s" % [sim.describe(), str(_ids(actions)), str(_sim_action_ids(sim))]
				break
			if actions.is_empty():
				break
			var action: PlanModel.PlanAction = actions[rng.randi_range(0, actions.size() - 1)]
			used_skills[action.skill.id] = true
			var predicted := PlanModel.apply(state, action)
			sim.apply(action.to_battle_action(), 1)
			sim.apply(BattleAction.pass_action())
			var actual := PlanModel.from_sim(sim, boss.index)
			steps += 1
			if not predicted.equals(actual):
				mismatched_states += 1
				if first_error == "":
					first_error = "state differs after %s:\n    predicted %s\n    actual    %s" % [action.id(), predicted.key(), actual.key()]
				break
			state = actual
	check(mismatched_actions == 0, "applicable actions match legal actions on every visited state (%d steps)" % steps)
	check(mismatched_states == 0, "apply() predicts BattleSim exactly with a passing player (%d steps)" % steps)
	check(used_skills.size() == 7, "the walks exercised all 7 boss skills: %s" % str(used_skills.keys()))
	if first_error != "":
		print("    first mismatch: " + first_error)


# --- Planner -----------------------------------------------------------------------

func _planner(h: BossPlanner.Heuristic = BossPlanner.Heuristic.DAMAGE, max_len: int = 4) -> BossPlanner:
	var p := BossPlanner.new()
	p.heuristic = h
	p.max_plan_length = max_len
	return p


func _kill_goal(sim: BattleSim, hero_id: String) -> BossPlanner.Goal:
	var h := _u(sim, hero_id)
	return BossPlanner.Goal.make("Kill " + h.display_name(), "kill", ["dead(%d)" % h.index], h.index)


func _plan_ids(r: BossPlanner.PlanResult) -> Array:
	var out := []
	for a in r.steps:
		out.append(a.skill.id)
	return out


func _test_planner_search() -> void:
	print("[Planner: search]")
	# Monk at 22 HP: two calm Spears (20) fall short, Sap Surge -> Spear (24) kills.
	var sim := _boss_sim()
	var monk := _u(sim, "monk")
	var boss := _u(sim, "giant_bamboo")
	monk.hp = 22
	var state := PlanModel.from_sim(sim)
	var goal := _kill_goal(sim, "monk")
	var p := _planner()
	check(p.lower_bound(state, goal) == 1, "DAMAGE bound: 22 HP / (24 + burn 2) -> 1 action (%d)" % p.lower_bound(state, goal))
	var r := p.plan_for(state, goal)
	check(r.found and _plan_ids(r) == ["sap_surge", "bamboo_spear"] and r.steps[1].targets == [monk.index],
		"A* finds the setup chain Sap Surge -> Bamboo Spear(Monk): %s" % r.describe(state))
	check(r.end_state.holds("dead(%d)" % monk.index) and r.end_state.hp[monk.index] == 0, "the plan's end state has Monk dead")
	check(r.expanded > 0 and r.generated >= r.expanded and r.time_ms >= 0.0, "search statistics recorded (%s)" % r.summary())

	var results := {}
	for h in [BossPlanner.Heuristic.NONE, BossPlanner.Heuristic.GOAL_COUNT, BossPlanner.Heuristic.DAMAGE]:
		var ph := _planner(h)
		ph.prune_unreachable = false
		results[h] = ph.plan_for(state, goal)
	check(results[BossPlanner.Heuristic.NONE].found and results[BossPlanner.Heuristic.NONE].length() == 2
		and results[BossPlanner.Heuristic.GOAL_COUNT].length() == 2 and results[BossPlanner.Heuristic.DAMAGE].length() == 2,
		"every heuristic returns an optimal 2-step plan (uniform cost / goal-count / damage)")
	check(results[BossPlanner.Heuristic.DAMAGE].expanded <= results[BossPlanner.Heuristic.NONE].expanded,
		"the damage heuristic expands no more nodes than uniform cost (%d <= %d)" % [results[BossPlanner.Heuristic.DAMAGE].expanded, results[BossPlanner.Heuristic.NONE].expanded])
	var r2 := _planner().plan_for(state, goal)
	check(_plan_ids(r2) == _plan_ids(r), "planning is deterministic")

	# Depth bound and unreachable goals.
	check(not _planner(BossPlanner.Heuristic.DAMAGE, 1).plan_for(state, goal).found, "max_plan_length 1 cannot kill Monk at 22 HP")
	var knight_goal := _kill_goal(sim, "knight")
	check(p.lower_bound(state, knight_goal) == 3, "DAMAGE bound for Knight at 60 HP: 3 actions (%d)" % p.lower_bound(state, knight_goal))
	var rk := p.plan_for(state, knight_goal)
	check(not rk.found and rk.note == "no plan within bound" and rk.expanded > 0,
		"Knight at 60 HP: the loose bound admits the search, which proves no 4-step plan exists (%s, %d expanded)" % [rk.note, rk.expanded])
	var rk1 := _planner(BossPlanner.Heuristic.DAMAGE, 2).plan_for(state, knight_goal)
	check(not rk1.found and rk1.note == "unreachable within bound" and rk1.expanded == 0,
		"with max_plan_length 2 the bound prunes Knight at the root without expanding (%s)" % rk1.note)
	var pk := _planner()
	pk.prune_unreachable = false
	pk.node_limit = 300
	var rk2 := pk.plan_for(state, knight_goal)
	check(not rk2.found and rk2.note == "node limit" and rk2.expanded == 300, "without pruning the node limit stops the search (%s, %d)" % [rk2.note, rk2.expanded])
	var already := BossPlanner.Goal.make("x", "x", ["alive(%d)" % monk.index])
	check(not p.plan_for(state, already).found and p.plan_for(state, already).note == "already satisfied", "a goal that already holds yields no plan")

	# Burn every hero: Sap Surge (boundary sets phase 2) -> Thorn Storm.
	boss.hp = 60
	state = PlanModel.from_sim(sim)
	var burn_goal: BossPlanner.Goal = null
	for g in p.candidate_goals(state):
		if g.kind == "burn_all":
			burn_goal = g
	var rb := p.plan_for(state, burn_goal)
	check(rb.found and _plan_ids(rb) == ["sap_surge", "thorn_storm"], "burn-all goal: Sap Surge -> Thorn Storm once phase 2 is reached (%s)" % rb.describe(state))
	# Recover: Regrow alone, impossible without potions.
	var recover := BossPlanner.Goal.make("Recover", "recover", ["not low_hp(%d)" % boss.index])
	check(_plan_ids(p.plan_for(state, recover)) == ["regrow"], "recover goal: Regrow in one step")
	sim.potions[BattleSim.NPC] = 0
	check(not p.plan_for(PlanModel.from_sim(sim), recover).found, "recover is impossible without potions")


func _test_planner_goals() -> void:
	print("[Planner: goals and selection]")
	var sim := _boss_sim()
	var boss := _u(sim, "giant_bamboo")
	var monk := _u(sim, "monk")
	var state := PlanModel.from_sim(sim)
	var p := _planner()
	var goals := p.candidate_goals(state)
	var kinds := []
	for g in goals:
		kinds.append(g.kind)
	check(kinds.count("kill") == 4 and kinds.has("burn_all") and kinds.has("fortify") and not kinds.has("recover"),
		"at full HP: 4 kill goals, burn-all, fortify, no recover (%s)" % str(kinds))
	check(goals[0].target == monk.index, "the healer is the first kill candidate (%s)" % goals[0].name)
	var fortify: BossPlanner.Goal = null
	for g in goals:
		if g.kind == "fortify":
			fortify = g
	check(fortify.literals.size() == 2 and fortify.literals.has("shielded(%d)" % boss.index) and fortify.literals.has("enraged(%d)" % boss.index),
		"fortify = shield + every status the boss can grant (%s)" % str(fortify.literals))
	var rf := p.plan_for(state, fortify)
	check(rf.found and rf.length() == 2 and _plan_ids(rf).has("harden_bark") and _plan_ids(rf).has("sap_surge"), "fortify plan: Harden Bark + Sap Surge (%s)" % rf.describe(state))

	# decide(): a reachable kill beats fortifying.
	monk.hp = 22
	state = PlanModel.from_sim(sim)
	var d := p.decide(state)
	check(d.found and d.goal.kind == "kill" and d.goal.target == monk.index, "decide() (gain per action) picks the 2-step kill of Monk (%s)" % d.describe(state))
	var pe := _planner()
	pe.scoring = BossPlanner.Scoring.END_VALUE
	var de := pe.decide(state)
	check(de.found and de.goal.kind == "kill" and de.goal.target != monk.index and de.length() == 4,
		"end-value scoring prefers the 4-step kill of a bigger hero instead (%s)" % de.describe(state))
	check(d.candidates.size() == goals.size() and d.goals_tried == goals.size() and d.total_expanded >= d.expanded,
		"decide() reports every goal tried (%d) with aggregated statistics" % d.candidates.size())
	var found_count := 0
	for c in d.candidates:
		if c["found"]:
			found_count += 1
	check(found_count >= 2, "several goals had plans; the best score won (%d found, best %.1f)" % [found_count, d.score])

	# No kill reachable: a non-kill goal is chosen.
	for u in sim.alive_units(BattleSim.PLAYER):
		u.hp = u.data.max_hp
		u.data.max_hp = 200
		u.hp = 200
	state = PlanModel.from_sim(sim)
	var d2 := p.decide(state)
	check(d2.found and d2.goal.kind != "kill", "with no kill in reach the boss picks %s" % d2.goal.name)

	# Nothing reachable at all: found = false, fallback expected.
	var p1 := _planner(BossPlanner.Heuristic.DAMAGE, 0)
	var d3 := p1.decide(state)
	check(not d3.found and d3.note == "no goal reachable" and d3.candidates.size() == goals.size(), "max_plan_length 0: no goal reachable, candidates still listed")


## Plans are executable: replaying the steps on the real simulation with a
## passing player satisfies the goal, and every step passes holds_in_sim.
func _test_planner_executes() -> void:
	print("[Planner: plans are executable]")
	var walks := 40
	var plans := 0
	var invalid_steps := 0
	var unmet_goals := 0
	var p := _planner()
	for w in range(walks):
		var sim := _boss_sim()
		var boss := _u(sim, "giant_bamboo")
		for u in sim.alive_units(BattleSim.PLAYER):
			u.hp = rng.randi_range(5, u.data.max_hp)
		boss.hp = rng.randi_range(30, boss.data.max_hp)
		if rng.randf() < 0.3:
			boss.set_flag("enraged")
		var d := p.decide(PlanModel.from_sim(sim))
		if not d.found:
			continue
		plans += 1
		for step in d.steps:
			if not PlanModel.holds_in_sim(sim, step):
				invalid_steps += 1
				break
			sim.apply(step.to_battle_action(), 1)
			sim.apply(BattleAction.pass_action())
		if not PlanModel.from_sim(sim, boss.index).holds_all(d.goal.literals):
			unmet_goals += 1
	check(plans > 0 and invalid_steps == 0, "every plan step is applicable on the real simulation when replayed (%d plans)" % plans)
	check(unmet_goals == 0, "replaying a plan with a passing player achieves its goal (%d plans)" % plans)


# --- Brain: execute / monitor / replan -----------------------------------------------

func _brain(mode: BossBrain.Mode = BossBrain.Mode.PLANNER, max_len: int = 4) -> BossBrain:
	var b := BossBrain.new()
	b.mode = mode
	b.planner.max_plan_length = max_len
	b.fallback = MinimaxAI.new()
	b.fallback.side = BattleSim.NPC
	b.fallback.depth = 2
	b.fallback.eval_name = "tactical"
	return b


func _player_passes(sim: BattleSim) -> void:
	sim.apply(BattleAction.pass_action())


func _test_brain() -> void:
	print("[Brain: execution monitoring]")
	var sim := _boss_sim()
	var boss := _u(sim, "giant_bamboo")
	var monk := _u(sim, "monk")
	monk.hp = 22
	var brain := _brain()

	var d1 := brain.decide(sim)
	check(d1.source == "plan" and d1.replanned and d1.reason == "no plan" and d1.action.skill.id == "sap_surge",
		"first turn: plans and plays step 1 (%s)" % d1.describe(sim))
	check(d1.plan.goal.target == monk.index and d1.remaining.size() == 1 and d1.step_index == 0, "the plan is Kill Monk with one step left")
	sim.apply(d1.action, 1)
	_player_passes(sim)
	var d2 := brain.decide(sim)
	check(d2.source == "plan" and not d2.replanned and d2.action.skill.id == "bamboo_spear" and d2.action.targets == [monk.index],
		"second turn: continues the plan without replanning (%s)" % d2.describe(sim))
	check(brain.steps_continued == 1 and brain.replans == 0, "continuation counted, no stale replan")
	sim.apply(d2.action, 1)
	_player_passes(sim)
	check(not monk.is_alive(), "Monk is dead after the plan")
	var d3 := brain.decide(sim)
	check(d3.replanned and d3.reason == "plan finished" and d3.action != null and not d3.action.is_pass(), "after the plan ends the brain plans again (%s)" % d3.reason)

	# Plan monitoring: the player heals Monk, the old plan no longer kills.
	sim = _boss_sim()
	boss = _u(sim, "giant_bamboo")
	monk = _u(sim, "monk")
	monk.hp = 22
	brain = _brain()
	var e1 := brain.decide(sim)
	sim.apply(e1.action, 1)
	_player_passes(sim)
	monk.hp = 35  # healed by the player
	var e2 := brain.decide(sim)
	check(e2.replanned and e2.reason == "goal unreachable by plan" and brain.replans == 1,
		"replans when the remaining steps no longer reach the goal (%s)" % e2.reason)
	check(PlanModel.holds_in_sim(sim, PlanModel.PlanAction.make(boss.index, e2.action.skill, e2.action.targets)), "the new action is applicable")

	# Action monitoring: a precondition breaks (boss already shielded).
	sim = _boss_sim()
	boss = _u(sim, "giant_bamboo")
	for u in sim.alive_units(BattleSim.PLAYER):
		u.data.max_hp = 200
		u.hp = 200
	brain = _brain()
	var f1 := brain.decide(sim)
	check(f1.plan.goal.kind == "fortify", "no kill in reach: the boss fortifies (%s)" % f1.describe(sim))
	sim.apply(f1.action, 1)
	_player_passes(sim)
	var next_skill: String = f1.remaining[0].skill.id if not f1.remaining.is_empty() else ""
	if next_skill == "harden_bark":
		boss.shield = 15
	else:
		boss.set_flag("enraged")
	var f2 := brain.decide(sim)
	check(f2.replanned and (f2.reason.begins_with("precondition failed") or f2.reason.begins_with("goal reached")),
		"a broken precondition or an already reached goal triggers replanning (%s)" % f2.reason)

	# Fallback, pass, hybrid, minimax.
	var g := _brain(BossBrain.Mode.PLANNER, 0)
	var gd := g.decide(_boss_sim())
	check(gd.source == "fallback" and gd.search != null and not gd.action.is_pass() and g.fallbacks == 1, "no reachable goal: minimax fallback decides (%s)" % gd.describe(_boss_sim()))
	var stunned := _boss_sim()
	_u(stunned, "giant_bamboo").stun = 1
	var pd := _brain().decide(stunned)
	check(pd.source == "pass" and pd.action.is_pass(), "a stunned boss passes")
	var h := _brain(BossBrain.Mode.HYBRID)
	var hsim := _boss_sim()
	_u(hsim, "monk").hp = 22
	var hd := h.decide(hsim)
	var first_steps := []
	for c in hd.plan.candidates:
		if c["found"]:
			first_steps.append(c["steps"][0].id())
	check(hd.source == "hybrid" and hd.search != null and hd.search.root_scores.size() <= first_steps.size() and hd.search.root_scores.size() >= 1,
		"hybrid: minimax chooses among the candidate plans' first steps (%d roots from %d plans)" % [hd.search.root_scores.size(), first_steps.size()])
	var m := _brain(BossBrain.Mode.MINIMAX)
	check(m.decide(_boss_sim()).source == "minimax", "minimax mode uses the plain search")
	check(brain.history.size() == 2 and brain.stats_summary().length() > 0, "history and summary are kept")

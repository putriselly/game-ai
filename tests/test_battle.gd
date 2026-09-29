extends Node
## Headless test: godot --headless --path . res://tests/test_runner.tscn
## Covers the A* pathfinder, the state machine, every skill rule from the
## design document (through BattleSim), the one-action-per-turn structure,
## the minimax / alpha-beta / expectimax search, and a full autopilot battle.

var failures := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_pathfinder()
	await _test_state_machine()
	_test_sim_rules()
	_test_turn_structure()
	_test_search()
	await _test_full_battle()
	print("\n%s" % ("ALL TESTS PASSED" if failures == 0 else "%d FAILURE(S)" % failures))
	get_tree().quit(0 if failures == 0 else 1)


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   - " + msg)
	else:
		failures += 1
		print("  FAIL - " + msg)


func _test_pathfinder() -> void:
	print("[A*]")
	var f := AStarPathfinder.new(Rect2i(0, 0, 10, 10))
	for y in range(9):
		f.set_blocked(Vector2i(5, y), true)
	var path := f.find_path(Vector2i(0, 0), Vector2i(9, 0))
	check(path.size() > 0, "path found around wall")
	check(path[0] == Vector2i(0, 0) and path[-1] == Vector2i(9, 0), "path starts and ends correctly")
	check(path.size() == 28, "path is optimal (27 steps, got %d)" % (path.size() - 1))
	var steps_ok := true
	for i in range(1, path.size()):
		var d: Vector2i = path[i] - path[i - 1]
		if absi(d.x) + absi(d.y) != 1 or f.is_blocked(path[i]):
			steps_ok = false
	check(steps_ok, "every step is 4-directional and walkable")
	f.set_blocked(Vector2i(5, 9), true)
	var closest := f.find_path(Vector2i(0, 0), Vector2i(9, 0))
	check(closest.size() > 0 and closest[-1].x == 4, "unreachable goal -> path to closest cell")
	check(f.find_path(Vector2i(3, 3), Vector2i(3, 3)).size() == 1, "start == goal")


func _test_state_machine() -> void:
	print("[StateMachine]")
	var host := Node.new()
	get_tree().root.add_child(host)
	var sm := StateMachine.new()
	host.add_child(sm)
	var a := State.new()
	var b := State.new()
	sm.add_state(&"A", a)
	sm.add_state(&"B", b)
	var changes: Array = []
	sm.state_changed.connect(func(p, c): changes.append([p, c]))
	sm.start(&"A")
	check(sm.is_in(&"A"), "start enters initial state")
	a.go_to(&"B")
	check(sm.is_in(&"B") and changes.size() == 2, "state can request transition")
	check(a.owner_node == host and b.machine == sm, "states know owner and machine")
	host.queue_free()


## Fixture with fixed HP values so the rule checks below stay readable no
## matter how the roster is balanced.
const FIXTURE_HP := {"ninja": 40, "flame": 35, "knight": 60, "monk": 35,
	"evil_bamboo": 30, "bear": 45, "bomber": 30, "evil_fire_mage": 35}


func _sim() -> BattleSim:
	var s := BattleSim.create(["ninja", "flame", "knight", "monk"], ["evil_bamboo", "bear", "bomber", "evil_fire_mage"])
	for u in s.units:
		u.data.max_hp = FIXTURE_HP[u.data.id]
		u.hp = u.data.max_hp
	return s


func _u(sim: BattleSim, id: String) -> UnitState:
	for u in sim.units:
		if u.data.id == id:
			return u
	return null


func _basic(u: UnitState) -> SkillData:
	return u.data.basic_skills()[0]


func _ult(u: UnitState) -> SkillData:
	return u.data.ultimate()


func _test_sim_rules() -> void:
	print("[Skill rules]")
	var s := _sim()
	var ninja := _u(s, "ninja")
	var flame := _u(s, "flame")
	var knight := _u(s, "knight")
	var monk := _u(s, "monk")
	var bamboo := _u(s, "evil_bamboo")
	var bear := _u(s, "bear")
	var bomber := _u(s, "bomber")
	var mage := _u(s, "evil_fire_mage")
	check(s.units.size() == 8 and mage != null, "all units created from the roster")

	s.apply_skill(ninja, _basic(ninja), [bamboo])
	check(bamboo.hp == 20, "Kunai Strike deals 10 (bamboo hp %d)" % bamboo.hp)
	check(ninja.ult == 25, "hitting charges the ultimate bar (%d)" % ninja.ult)
	ninja.ult = 100
	s.apply_skill(ninja, _ult(ninja), s.alive_units(BattleSim.NPC))
	check(bamboo.hp == 15 and bear.hp == 40 and bomber.hp == 25 and mage.hp == 30, "Shuriken Storm hits every enemy for 5")
	check(ninja.ult == 0, "ultimate empties the bar")

	s.apply_skill(flame, _basic(flame), [bear])
	check(bear.hp == 35 and bear.burn == 2, "Scorch deals 5 and burns 2 turns")
	s.apply_skill(flame, _basic(flame), [bear])
	check(bear.burn == 2, "burn does not stack (still 2 turns)")
	s.apply_skill(flame, _ult(flame), [bear])
	check(bear.hp == 15, "Explode deals 15 to a burning target (hp %d)" % bear.hp)
	s.apply_skill(flame, _ult(flame), [bomber])
	check(bomber.hp == 18, "Explode deals 7 to a non-burning target (hp %d)" % bomber.hp)
	var tick := s.begin_turn(BattleSim.NPC)
	check(bear.hp == 13 and bear.burn == 1 and tick.size() == 1, "burn ticks at the start of the side's turn and counts down")

	s.apply_skill(knight, _basic(knight), [mage])
	check(mage.hp == 27 and mage.stun == 0, "Bump at full HP: 3 damage, no stun")
	knight.hp = 20
	s.apply_skill(knight, _basic(knight), [mage])
	check(mage.hp == 24 and mage.stun == 1, "Bump under 50% HP also stuns")
	var npc_actions := s.legal_actions(BattleSim.NPC)
	var mage_can_act := npc_actions.any(func(a): return a.unit == mage.index)
	check(not mage_can_act, "a stunned unit cannot be chosen to act")
	s.end_turn(BattleSim.NPC)
	check(mage.stun == 0 and mage.stun_immune == 1, "stun wears off at the end of the stunned side's turn and grants 1 turn of immunity")
	var resisted := s.apply_skill(knight, _basic(knight), [mage])
	check(mage.stun == 0 and resisted.any(func(e): return e["type"] == "resist"), "a freshly un-stunned unit resists the next stun (no stun lock)")
	s.end_turn(BattleSim.NPC)
	s.apply_skill(knight, _basic(knight), [mage])
	check(mage.stun == 1, "immunity lasts one turn, then stun works again")
	mage.stun = 0
	mage.stun_immune = 0
	s.apply_skill(knight, _ult(knight), [ninja])
	check(ninja.shield == 10, "Guard gives 10 shield")
	s.apply_skill(bamboo, _ult(bamboo), [ninja])
	check(ninja.hp == 40 and ninja.shield == 3, "shield absorbs first (Harder Bump 7 -> shield 3)")
	s.apply_skill(bamboo, _basic(bamboo), [ninja])
	check(ninja.hp == 40 and ninja.shield == 0, "Bump 3 finishes the shield, no HP lost")

	s.apply_skill(monk, _basic(monk), [knight])
	check(knight.hp == 25, "Heal restores 5")
	flame.hp = 30
	s.apply_skill(monk, _ult(monk), s.alive_units(BattleSim.PLAYER))
	check(knight.hp == 35 and flame.hp == 35 and ninja.hp == 40, "Blessing heals all allies by 10, capped at max HP")

	s.apply_skill(bear, _ult(bear), [monk])
	check(monk.hp == 32 and monk.stun == 1, "Body Slam: 3 damage + stun 1")
	s.apply_skill(bomber, _basic(bomber), s.alive_units(BattleSim.PLAYER))
	check(ninja.hp == 37 and knight.hp == 32 and monk.hp == 29, "Bomb hits every ally for 3")
	s.apply_skill(mage, _ult(mage), [knight])
	check(knight.hp == 17 and knight.burn == 3, "Light Up: 15 damage + burn 3 turns")

	var hp_before := ninja.hp
	var ult_before := bamboo.ult
	var ev := s.apply_skill(bamboo, _basic(bamboo), [ninja], false)
	check(ninja.hp == hp_before and bamboo.ult == ult_before and ev.any(func(e): return e["type"] == "miss"), "a miss deals no damage and gives no charge")

	s.apply_skill(ninja, _basic(ninja), [bamboo])
	var death := s.apply_skill(ninja, _basic(ninja), [bamboo])
	check(not bamboo.is_alive() and bamboo.hp == 0 and death.any(func(e): return e["type"] == "death"), "unit dies at 0 HP")


func _test_turn_structure() -> void:
	print("[Turn structure]")
	var s := _sim()
	check(s.side_to_move == BattleSim.PLAYER and s.turn == 0, "player moves first")
	var actions := s.legal_actions()
	check(actions.size() == 3, "branching at full HP = 3 (Heal is useless, so it is not offered); got %d" % actions.size())
	var first := actions[0]
	check(first.unit == _u(s, "ninja").index and first.targets.size() == 1, "action = (unit, skill, rule-based target)")
	s.apply(first)
	check(s.side_to_move == BattleSim.NPC and s.turn == 1, "one action hands the turn to the other side")
	var bamboo_hp := _u(s, "evil_bamboo").hp
	var target_hp := s.units[first.targets[0]].hp
	check(target_hp == 20 or bamboo_hp == 20, "the attack went to the most wounded (first) enemy")

	# Ultimate modes
	var ninja := _u(s, "ninja")
	ninja.ult = 100
	s.side_to_move = BattleSim.PLAYER
	var count_auto := s.legal_actions().filter(func(a): return a.unit == ninja.index).size()
	s.ultimate_mode = BattleSim.UltimateMode.CHOICE
	var count_choice := s.legal_actions().filter(func(a): return a.unit == ninja.index).size()
	check(count_auto == 1 and count_choice == 2, "AUTO offers only the ultimate (1), CHOICE offers both (2)")
	s.ultimate_mode = BattleSim.UltimateMode.AUTO

	# Pass when every unit is stunned
	for u in s.alive_units(BattleSim.NPC):
		u.stun = 1
	s.side_to_move = BattleSim.NPC
	var npc_actions := s.legal_actions()
	check(npc_actions.size() == 1 and npc_actions[0].is_pass(), "a fully stunned side gets a Pass action")
	s.apply(npc_actions[0])
	check(s.alive_units(BattleSim.NPC).all(func(u): return u.stun == 0), "passing still ends the turn and clears the stuns")

	# Terminal test + utility
	check(not s.is_terminal(), "mid-game state is not terminal")
	for u in s.side_units(BattleSim.NPC):
		u.hp = 0
	check(s.is_terminal() and s.winner() == BattleSim.PLAYER, "all NPC units dead -> terminal, player wins")
	check(s.utility(BattleSim.PLAYER) > BattleSim.WIN_SCORE and s.utility(BattleSim.NPC) < -BattleSim.WIN_SCORE, "utility is +/-(WIN_SCORE + remaining HP)")
	var d := _sim()
	d.turn = d.max_turns
	check(d.is_terminal() and d.winner() == -1 and d.utility(BattleSim.NPC) == 0.0, "turn limit -> draw with utility 0")

	# Potions: basic heals consume the side's stock
	var ps := _sim()
	var monk := _u(ps, "monk")
	_u(ps, "knight").hp = 10
	check(ps.potions[BattleSim.PLAYER] == BattleSim.POTIONS_PER_SIDE, "each side starts with %d potions" % BattleSim.POTIONS_PER_SIDE)
	var heal_actions := ps.legal_actions().filter(func(a): return a.unit == monk.index)
	check(heal_actions.size() == 1, "Heal is offered while potions remain")
	ps.apply(heal_actions[0])
	check(ps.potions[BattleSim.PLAYER] == 2 and _u(ps, "knight").hp == 15, "Heal consumes one potion")
	ps.potions[BattleSim.PLAYER] = 0
	ps.side_to_move = BattleSim.PLAYER
	check(ps.legal_actions().all(func(a): return a.unit != monk.index), "no potions -> Heal is not offered")
	monk.ult = 100
	check(ps.legal_actions().any(func(a): return a.unit == monk.index and a.skill.is_ultimate), "Blessing (ultimate) needs no potion")

	# Full targeting enumerates every valid target
	var ft := _sim()
	var rule_count := ft.legal_actions().size()
	ft.full_targeting = true
	var full_count := ft.legal_actions().size()
	check(rule_count == 3 and full_count == 12, "rule targeting: 3 actions, full targeting: 3 units x 4 targets = 12 (got %d)" % full_count)

	# Threat model and threat targeting
	var ts := _sim()
	var t_ninja := ts.threat_of(_u(ts, "ninja"))
	var t_flame := ts.threat_of(_u(ts, "flame"))
	var t_monk := ts.threat_of(_u(ts, "monk"))
	check(t_ninja == 10.0 and t_flame == 9.0 and t_monk == 4.0, "threat: Ninja 10 (Kunai), Flame 9 (5 + burn 2x2), Monk 4 (heal 5 x 0.8); got %.1f/%.1f/%.1f" % [t_ninja, t_flame, t_monk])
	_u(ts, "ninja").ult = 100
	check(ts.threat_of(_u(ts, "ninja")) == 30.0, "a charged ultimate adds its value (Shuriken Storm 5 x 4 targets)")
	_u(ts, "ninja").ult = 0
	ts.side_to_move = BattleSim.NPC
	var weakest := ts.default_targets(_u(ts, "bear"), _basic(_u(ts, "bear")))
	ts.target_rule = BattleSim.TargetRule.THREAT
	var dangerous := ts.default_targets(_u(ts, "bear"), _basic(_u(ts, "bear")))
	check(weakest == [_u(ts, "flame").index] and dangerous == [_u(ts, "ninja").index], "WEAKEST rule aims at Flame (lowest HP), THREAT rule aims at Ninja")
	_u(ts, "monk").hp = 4
	check(ts.default_targets(_u(ts, "bear"), _basic(_u(ts, "bear"))) == [_u(ts, "monk").index], "THREAT rule still takes a kill when one is available")
	_u(ts, "monk").hp = 35
	ts.target_rule = BattleSim.TargetRule.TOUGHEST
	check(ts.default_targets(_u(ts, "bear"), _basic(_u(ts, "bear"))) == [_u(ts, "knight").index], "TOUGHEST rule aims at Knight (highest HP)")
	ts.target_rule = BattleSim.TargetRule.PER_UNIT
	var per_bamboo := ts.default_targets(_u(ts, "evil_bamboo"), _basic(_u(ts, "evil_bamboo")))
	var per_bear := ts.default_targets(_u(ts, "bear"), _basic(_u(ts, "bear")))
	var per_mage := ts.default_targets(_u(ts, "evil_fire_mage"), _basic(_u(ts, "evil_fire_mage")))
	check(per_bamboo == [_u(ts, "flame").index] and per_bear == [_u(ts, "ninja").index] and per_mage == [_u(ts, "knight").index],
		"PER_UNIT: Bamboo -> Flame (weakest), Bear -> Ninja (threat), Fire Mage -> Knight (toughest)")
	var dead_ninja := _sim()
	_u(dead_ninja, "ninja").hp = 0
	var dead_flame := _sim()
	_u(dead_flame, "flame").hp = 0
	var w := BattleEvaluator.personality("balanced")
	check(BattleEvaluator.eval_threat(dead_ninja, BattleSim.NPC, w) > BattleEvaluator.eval_threat(dead_flame, BattleSim.NPC, w), "threat evaluation prefers a dead Ninja over a dead Flame")

	# Clone independence
	var a := _sim()
	var b := a.clone()
	b.units[0].hp = 1
	b.potions[0] = 0
	b.target_rule = BattleSim.TargetRule.THREAT
	check(a.units[0].hp == 40 and a.potions[0] == BattleSim.POTIONS_PER_SIDE and a.target_rule == BattleSim.TargetRule.WEAKEST, "clone is independent of the original")


func _ai(algorithm: MinimaxAI.Algorithm, depth: int, ordering := MinimaxAI.Ordering.NONE) -> MinimaxAI:
	var ai := MinimaxAI.new()
	ai.side = BattleSim.NPC
	ai.algorithm = algorithm
	ai.depth = depth
	ai.ordering = ordering
	ai.eval_name = "tactical"
	return ai


func _best_score(r: MinimaxAI.SearchResult) -> float:
	var best := -INF
	for e in r.root_scores:
		best = maxf(best, e["score"])
	return best


func _test_search() -> void:
	print("[Search]")
	var s := _sim()
	s.side_to_move = BattleSim.NPC
	# A wounded target the NPC can finish.
	_u(s, "ninja").hp = 3
	var greedy := _ai(MinimaxAI.Algorithm.GREEDY, 1)
	var r := greedy.decide(s)
	var after := s.clone()
	after.apply(r.action)
	check(not _u(after, "ninja").is_alive(), "depth-1 search finishes the 3-HP hero (%s)" % r.action.describe(s))
	check(r.root_scores.size() == s.legal_actions(BattleSim.NPC).size(), "every root action gets a score")
	check(r.depth == 1 and r.nodes > 1, "search result carries depth and node count")

	var mid := _sim()
	mid.side_to_move = BattleSim.NPC
	_u(mid, "knight").hp = 25
	_u(mid, "bear").hp = 20
	_u(mid, "flame").ult = 75
	var mm := _ai(MinimaxAI.Algorithm.MINIMAX, 4).decide(mid)
	var ab := _ai(MinimaxAI.Algorithm.ALPHABETA, 4).decide(mid)
	check(is_equal_approx(_best_score(mm), _best_score(ab)), "alpha-beta returns the minimax value (%.1f vs %.1f)" % [_best_score(mm), _best_score(ab)])
	check(ab.action.same_as(mm.action), "alpha-beta picks the same action as minimax")
	check(ab.nodes < mm.nodes and ab.pruned > 0, "alpha-beta expands fewer nodes (%d < %d, pruned %d)" % [ab.nodes, mm.nodes, ab.pruned])
	var good := _ai(MinimaxAI.Algorithm.ALPHABETA, 4, MinimaxAI.Ordering.HEURISTIC).decide(mid)
	var bad := _ai(MinimaxAI.Algorithm.ALPHABETA, 4, MinimaxAI.Ordering.WORST).decide(mid)
	check(is_equal_approx(_best_score(good), _best_score(bad)), "move ordering does not change the value")
	check(good.nodes <= bad.nodes, "good ordering prunes at least as much as bad ordering (%d <= %d)" % [good.nodes, bad.nodes])

	var limited := _ai(MinimaxAI.Algorithm.ALPHABETA, 6)
	limited.node_limit = 40
	var lr := limited.decide(mid)
	check(lr.cutoff and lr.nodes < 100, "node budget stops the search early (%d nodes)" % lr.nodes)

	var chance := mid.clone()
	chance.hit_chance = 0.8
	var em := _ai(MinimaxAI.Algorithm.EXPECTIMAX, 1).decide(chance)
	var det := _ai(MinimaxAI.Algorithm.MINIMAX, 1).decide(chance)
	check(em.action != null and em.root_scores.size() > 0, "expectimax produces a decision")
	check(_best_score(em) < _best_score(det), "expectimax (depth 1) discounts the miss chance (%.1f < %.1f)" % [_best_score(em), _best_score(det)])
	check(em.nodes > det.nodes, "expectimax expands both outcomes of a chance node (%d > %d nodes)" % [em.nodes, det.nodes])

	var deep := _ai(MinimaxAI.Algorithm.ALPHABETA, 3)
	var before := mid.describe()
	deep.decide(mid)
	check(mid.describe() == before, "search never mutates the real state")


## Plays a whole fight through the real scene: the player side is an autopilot
## that clicks the first hero / skill / target, the NPC is the minimax AI.
func _test_full_battle() -> void:
	print("[Full battle autopilot]")
	Game.player_party = ["ninja", "flame", "knight", "monk"]
	Game.pending_enemy_party = ["evil_bamboo", "bear"]
	Game.party_hp = {}
	Game.ai_config["depth"] = 3
	var battle: Battle = load("res://battle.tscn").instantiate()
	battle.fast_mode = true
	get_tree().root.add_child(battle)
	await get_tree().process_frame
	var guard := 0
	while not battle.battle_over and guard < 4000:
		guard += 1
		await get_tree().process_frame
		if battle.state_machine.is_in(&"PlayerTurn"):
			var phase: Battle.PlayerTurn = battle.state_machine.current_state
			var selectable := battle.units.filter(func(u): return u.is_selectable())
			match phase.stage:
				Battle.PlayerTurn.Stage.PICK_HERO:
					if not selectable.is_empty():
						battle.unit_clicked.emit(selectable[0])
				Battle.PlayerTurn.Stage.PICK_SKILL:
					battle.ui.skill_chosen.emit(battle.sim.usable_skills(phase.hero.state)[0])
				Battle.PlayerTurn.Stage.PICK_TARGET:
					if not selectable.is_empty():
						battle.unit_clicked.emit(selectable[0])
	check(battle.battle_over, "battle reaches an end state (turns: %d)" % battle.sim.turn)
	check(battle.state_machine.is_in(&"Finished"), "state machine ends in Finished")
	check(battle.last_search != null and battle.last_search.root_scores.size() > 0, "NPC decisions were recorded for the overlay")
	print("      winner: %s" % ["player" if battle.victory else "npc/draw"])
	battle.queue_free()
	await get_tree().process_frame

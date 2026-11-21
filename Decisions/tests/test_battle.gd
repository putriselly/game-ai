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
	_test_probability_rules()
	_test_boss_rules()
	_test_plan_model()
	_test_turn_structure()
	_test_csp()
	_test_csp_assignment()
	_test_stage4_expected_utility()
	_test_search()
	await _test_full_battle()
	await _test_boss_battle()
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
	"evil_bamboo": 30, "bear": 45, "bomber": 30, "evil_fire_mage": 35, "giant_bamboo": 150}


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
	check(bamboo.hp == 15 and bear.hp == 35 and bomber.hp == 27 and mage.hp == 32,
		"Shuriken Storm hits every enemy for 5 with element multiplier: Wind x1 vs Bamboo (5), x2 vs Electric Bear (10), x0.5 vs Fire Bomber/Mage (2.5 -> 3)")
	check(ninja.ult == 0, "ultimate empties the bar")

	s.apply_skill(flame, _basic(flame), [bear])
	check(bear.hp == 30 and bear.burn == 2, "Scorch deals 5 (Fire vs Electric is neutral, x1) and burns 2 turns")
	s.apply_skill(flame, _basic(flame), [bear])
	check(bear.burn == 2, "burn does not stack (still 2 turns)")
	s.apply_skill(flame, _ult(flame), [bear])
	check(bear.hp == 10, "Explode deals 15 to a burning target (Fire vs Electric x1, hp %d)" % bear.hp)
	s.apply_skill(flame, _ult(flame), [bomber])
	check(bomber.hp == 20, "Explode deals 7 to a non-burning target (Fire vs Fire x1, hp %d)" % bomber.hp)
	var tick := s.begin_turn(BattleSim.NPC)
	check(bear.hp == 8 and bear.burn == 1 and tick.size() == 1, "burn ticks 2 at the start of the side's turn (no element multiplier) and counts down")

	s.apply_skill(knight, _basic(knight), [mage])
	check(mage.hp == 26 and mage.stun == 0, "Bump at full HP: 3 x2 (Water vs Fire) = 6 damage, no stun")
	knight.hp = 20
	s.apply_skill(knight, _basic(knight), [mage])
	check(mage.hp == 20 and mage.stun == 1, "Bump under 50% HP also stuns (another 6 damage)")
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
	check(monk.hp == 29 and monk.stun == 1, "Body Slam: 3 x2 (Electric vs Water) = 6 damage + stun 1")
	s.apply_skill(bomber, _basic(bomber), s.alive_units(BattleSim.PLAYER))
	check(ninja.hp == 34 and flame.hp == 32 and knight.hp == 33 and monk.hp == 27,
		"Bomb hits every ally for 3 with element multiplier: Fire x2 vs Wind Ninja (6), x1 vs Fire Flame (3), x0.5 vs Water Knight/Monk (1.5 -> 2)")
	s.apply_skill(mage, _ult(mage), [knight])
	check(knight.hp == 25 and knight.burn == 3, "Light Up: 15 x0.5 (Fire vs Water) = 7.5 -> 8 damage + burn 3 turns")

	var hp_before := ninja.hp
	var ult_before := bamboo.ult
	var ev := s.apply_skill(bamboo, _basic(bamboo), [ninja], false)
	check(ninja.hp == hp_before and bamboo.ult == ult_before and ev.any(func(e): return e["type"] == "miss"), "a miss deals no damage and gives no charge")

	s.apply_skill(ninja, _basic(ninja), [bamboo])
	var death := s.apply_skill(ninja, _basic(ninja), [bamboo])
	check(not bamboo.is_alive() and bamboo.hp == 0 and death.any(func(e): return e["type"] == "death"), "unit dies at 0 HP")


func _test_probability_rules() -> void:
	print("[Probability]")

	# Hit Chance must remain a valid probability.
	var bounds := _sim()
	bounds.hit_chance = 1.5
	var upper_clamped := is_equal_approx(bounds.hit_chance, 1.0)
	bounds.hit_chance = -0.2
	check(upper_clamped and is_equal_approx(bounds.hit_chance, 0.0),
		"Hit Chance is clamped to the 0.0-1.0 range")

	# Only damage-producing actions are probabilistic.
	var classifier := _sim()
	classifier.hit_chance = 0.5
	var classifier_flame := _u(classifier, "flame")
	var classifier_bear := _u(classifier, "bear")
	var classifier_monk := _u(classifier, "monk")
	var classifier_knight := _u(classifier, "knight")
	var attack_action := BattleAction.make(
		classifier_flame.index, _basic(classifier_flame), [classifier_bear.index]
	)
	var heal_action := BattleAction.make(
		classifier_monk.index, _basic(classifier_monk), [classifier_knight.index]
	)
	check(classifier.is_chance_action(attack_action),
		"A damage-producing attack is probabilistic when Hit Chance is below 100%")
	check(not classifier.is_chance_action(heal_action),
		"Healing remains deterministic when Hit Chance is below 100%")

	# Forced Miss through apply(): no HP, shield, Burn, or ultimate charge is lost/gained.
	var miss_sim := _sim()
	miss_sim.hit_chance = 0.3
	var miss_flame := _u(miss_sim, "flame")
	var miss_bear := _u(miss_sim, "bear")
	miss_bear.shield = 4
	var miss_hp_before := miss_bear.hp
	var miss_shield_before := miss_bear.shield
	var miss_events := miss_sim.apply(
		BattleAction.make(miss_flame.index, _basic(miss_flame), [miss_bear.index]), 0
	)
	check(
		_has_event(miss_events, "miss")
		and not _has_event(miss_events, "damage")
		and miss_bear.hp == miss_hp_before
		and miss_bear.shield == miss_shield_before
		and miss_bear.burn == 0,
		"Miss causes no damage, shield reduction, or Burn"
	)
	check(miss_flame.ult == 0, "Miss does not award ultimate charge")
	check(
		miss_sim.turn == 1 and miss_sim.side_to_move == BattleSim.NPC,
		"Miss still consumes the action and ends the turn"
	)

	# Forced Hit through apply(): damage and Burn apply. Burn then ticks at the
	# beginning of the NPC turn, which is part of the existing turn structure.
	var hit_sim := _sim()
	hit_sim.hit_chance = 0.3
	var hit_flame := _u(hit_sim, "flame")
	var hit_bear := _u(hit_sim, "bear")
	var hit_events := hit_sim.apply(
		BattleAction.make(hit_flame.index, _basic(hit_flame), [hit_bear.index]), 1
	)
	var direct_damage_event := hit_events.any(
		func(e): return e.get("type", "") == "damage" and e.get("amount", 0) == 5
	)
	var burn_applied_event := hit_events.any(
		func(e): return e.get("type", "") == "burn" and e.get("turns", 0) == 2
	)
	check(
		direct_damage_event and burn_applied_event and hit_bear.hp == 38 and hit_bear.burn == 1,
		"Hit applies damage and Burn; Burn ticks when the NPC turn begins"
	)
	check(hit_flame.ult == 25, "Hit awards ultimate charge")

	# A damage attack that can Stun must not apply that status on a Miss.
	var stun_sim := _sim()
	stun_sim.hit_chance = 0.3
	var stun_knight := _u(stun_sim, "knight")
	var stun_mage := _u(stun_sim, "evil_fire_mage")
	stun_knight.hp = 20  # Enables the Knight's conditional Stun.
	stun_mage.shield = 4
	var stun_hp_before := stun_mage.hp
	var stun_events := stun_sim.apply(
		BattleAction.make(stun_knight.index, _basic(stun_knight), [stun_mage.index]), 0
	)
	check(
		_has_event(stun_events, "miss")
		and stun_mage.hp == stun_hp_before
		and stun_mage.shield == 4
		and stun_mage.stun == 0
		and not _has_event(stun_events, "stun"),
		"Miss does not deal damage, reduce shield, or apply Stun"
	)

	# A missed ultimate is still consumed under the agreed skill rules.
	var ultimate_sim := _sim()
	ultimate_sim.hit_chance = 0.3
	var ultimate_ninja := _u(ultimate_sim, "ninja")
	ultimate_ninja.ult = BattleSim.ULT_MAX
	var ultimate_targets: Array[int] = []
	for target in ultimate_sim.alive_units(BattleSim.NPC):
		ultimate_targets.append(target.index)
	var ultimate_events := ultimate_sim.apply(
		BattleAction.make(ultimate_ninja.index, _ult(ultimate_ninja), ultimate_targets), 0
	)
	check(
		ultimate_ninja.ult == 0 and _has_event(ultimate_events, "miss"),
		"Miss still consumes the used ultimate"
	)

	# AoE must use one shared roll for all targets, not one roll per target.
	var aoe_sim := _sim()
	aoe_sim.side_to_move = BattleSim.NPC
	aoe_sim.hit_chance = 0.5
	var bomber := _u(aoe_sim, "bomber")
	var aoe_targets: Array[int] = []
	for target in aoe_sim.alive_units(BattleSim.PLAYER):
		aoe_targets.append(target.index)
	var aoe_action := BattleAction.make(bomber.index, _basic(bomber), aoe_targets)
	var aoe_seed := 20261121
	aoe_sim.rng.seed = aoe_seed
	var expected_rng := RandomNumberGenerator.new()
	expected_rng.seed = aoe_seed
	expected_rng.randf()  # The single roll expected inside apply().
	var expected_next_random := expected_rng.randf()
	var aoe_events := aoe_sim.apply(aoe_action)
	var aoe_damage_count := 0
	var aoe_miss_count := 0
	for event in aoe_events:
		if event.get("type", "") == "damage":
			aoe_damage_count += 1
		elif event.get("type", "") == "miss":
			aoe_miss_count += 1
	var actual_next_random := aoe_sim.rng.randf()
	check(
		(aoe_damage_count == aoe_targets.size() and aoe_miss_count == 0)
		or (aoe_miss_count == aoe_targets.size() and aoe_damage_count == 0),
		"AoE gives the same Hit/Miss result to every target"
	)
	check(
		is_equal_approx(actual_next_random, expected_next_random),
		"AoE performs exactly one random roll per action"
	)

	# Healing is deterministic and must not consume the random generator.
	var support_sim := _sim()
	support_sim.hit_chance = 0.3
	var monk := _u(support_sim, "monk")
	var ally := _u(support_sim, "knight")
	ally.hp -= 10
	var ally_hp_before := ally.hp
	var support_seed := 314159
	support_sim.rng.seed = support_seed
	var support_expected_rng := RandomNumberGenerator.new()
	support_expected_rng.seed = support_seed
	var support_expected_next := support_expected_rng.randf()
	var heal_events := support_sim.apply(
		BattleAction.make(monk.index, _basic(monk), [ally.index]), 0
	)
	var support_actual_next := support_sim.rng.randf()
	check(
		ally.hp == ally_hp_before + 5
		and _has_event(heal_events, "heal")
		and not _has_event(heal_events, "miss"),
		"Healing succeeds regardless of Hit Chance"
	)
	check(
		is_equal_approx(support_actual_next, support_expected_next),
		"Healing does not consume a Hit/Miss random roll"
	)


## Boss fixture: Giant Bamboo alone against the party, fixture HP for heroes.
func _boss_sim() -> BattleSim:
	var s := BattleSim.create(["ninja", "flame", "knight", "monk"], ["giant_bamboo"])
	for u in s.units:
		if FIXTURE_HP.has(u.data.id):
			u.data.max_hp = FIXTURE_HP[u.data.id]
			u.hp = u.data.max_hp
	return s


func _skill_of(u: UnitState, skill_id: String) -> SkillData:
	for sk in u.data.skills:
		if sk.id == skill_id:
			return sk
	return null


func _usable_ids(s: BattleSim, u: UnitState) -> Array:
	var ids := []
	for sk in s.usable_skills(u):
		ids.append(sk.id)
	return ids


func _has_event(events: Array[Dictionary], type: String, flag: String = "") -> bool:
	for e in events:
		if e["type"] == type and (flag == "" or e.get("flag", "") == flag):
			return true
	return false


## Skill PRECONDITIONS / EFFECTS (flags) on the Giant Bamboo boss.
func _test_boss_rules() -> void:
	print("[Boss rules]")
	var s := _boss_sim()
	var boss := _u(s, "giant_bamboo")
	var ninja := _u(s, "ninja")
	var flame := _u(s, "flame")
	var monk := _u(s, "monk")
	check(boss != null and boss.data.is_boss and boss.data.skills.size() == 7 and boss.data.element == "Wind",
		"Giant Bamboo exists: boss flag, 7 skills, Wind element")
	var spear := _skill_of(boss, "bamboo_spear")
	check(spear.consumes.size() == 1 and spear.consumes[0] == "enraged" and spear.consumes.is_typed() and spear.power_if_user_enraged == 24,
		"roster string lists became typed Array[String] (consumes %s)" % str(spear.consumes))

	check(_usable_ids(s, boss) == ["root_slam", "sap_surge", "bamboo_spear", "harden_bark"],
		"at full HP only skills without unmet preconditions are offered: %s" % str(_usable_ids(s, boss)))
	check(s.legal_actions(BattleSim.NPC).size() == 4, "boss alone: 4 legal actions under rule targeting (%d)" % s.legal_actions(BattleSim.NPC).size())

	# Sap Surge grants "enraged" and cannot be stacked.
	var events := s.apply_skill(boss, _skill_of(boss, "sap_surge"), [boss])
	check(boss.has_flag("enraged") and _has_event(events, "status", "enraged"), "Sap Surge grants the enraged flag (status event)")
	check(not _usable_ids(s, boss).has("sap_surge"), "Sap Surge is forbidden while already enraged")
	check(boss.ult == 25, "a self-buff still charges the ultimate bar (%d)" % boss.ult)

	# Bamboo Spear: 20 while enraged, spends the rage, 10 afterwards.
	events = s.apply_skill(boss, spear, [monk])
	check(monk.hp == 11, "enraged Bamboo Spear deals 24 to Monk (Water, neutral vs Wind): hp %d" % monk.hp)
	check(not boss.has_flag("enraged") and _has_event(events, "status_lost", "enraged"), "Bamboo Spear consumes the rage (status_lost event)")
	var knight := _u(s, "knight")
	s.apply_skill(boss, spear, [knight])
	check(knight.hp == 50, "calm Bamboo Spear deals 10 (knight hp %d)" % knight.hp)
	s.apply_skill(boss, spear, [flame])
	check(flame.hp == 30, "Wind is weak to Fire: Bamboo Spear deals 10 x0.5 = 5 to Flame (hp %d)" % flame.hp)
	check(s.base_damage(boss, spear, ninja) == 10, "base_damage reports the calm value (%d)" % s.base_damage(boss, spear, ninja))
	boss.set_flag("enraged")
	check(s.base_damage(boss, spear, ninja) == 24, "base_damage reports the enraged value (%d)" % s.base_damage(boss, spear, ninja))

	# Harden Bark only while unshielded. (Reset the bar: in AUTO mode a full
	# ultimate would be the only skill offered.)
	boss.ult = 0
	var harden := _skill_of(boss, "harden_bark")
	s.apply_skill(boss, harden, [boss])
	check(boss.shield == 15, "Harden Bark gives 15 shield (%d)" % boss.shield)
	check(not _usable_ids(s, boss).has("harden_bark"), "Harden Bark is forbidden while shielded (derived flag)")
	boss.shield = 0
	check(_usable_ids(s, boss).has("harden_bark"), "Harden Bark returns once the shield is gone")

	# Thorn Storm needs enraged AND phase 2; phase 2 is set at the boss's turn start under 50% HP.
	check(boss.has_flag("enraged") and not _usable_ids(s, boss).has("thorn_storm"), "Thorn Storm is locked before phase 2 even while enraged")
	check(not _usable_ids(s, boss).has("regrow"), "Regrow is locked above 50% HP")
	boss.hp = 60
	events = s.begin_turn(BattleSim.NPC)
	check(boss.has_flag("phase2") and _has_event(events, "status", "phase2"), "begin_turn puts a boss under 50%% HP into phase 2 (hp %d/%d)" % [boss.hp, boss.data.max_hp])
	check(_usable_ids(s, boss).has("thorn_storm"), "Thorn Storm is offered once enraged and in phase 2")
	var ninja_hp := ninja.hp
	events = s.apply_skill(boss, _skill_of(boss, "thorn_storm"), s.alive_units(BattleSim.PLAYER))
	check(ninja.hp == ninja_hp - 6 and flame.hp == 27 and ninja.burn == 2 and monk.burn == 2,
		"Thorn Storm: 6 damage (3 to Flame) and burn 2 on every hero (ninja %d, flame %d)" % [ninja.hp, flame.hp])
	check(not boss.has_flag("enraged"), "Thorn Storm consumes the rage")
	check(not _usable_ids(s, boss).has("thorn_storm"), "Thorn Storm is locked again without rage")

	# Regrow: below 50% HP, once, drinks a potion.
	boss.ult = 0
	var regrow := _skill_of(boss, "regrow")
	check(_usable_ids(s, boss).has("regrow"), "Regrow is offered below 50% HP")
	events = s.apply_skill(boss, regrow, [boss])
	check(boss.hp == 85 and s.potions[BattleSim.NPC] == 2 and _has_event(events, "potion"), "Regrow heals 25 and uses a potion (hp %d, potions %d)" % [boss.hp, s.potions[BattleSim.NPC]])
	check(boss.has_flag(regrow.used_flag()) and not _usable_ids(s, boss).has("regrow"), "Regrow is once per battle")
	boss.hp = 60
	check(not _usable_ids(s, boss).has("regrow"), "Regrow stays locked after use even below 50% HP")

	# Potion gate lives in legal_actions, not in skill_available.
	var s2 := _boss_sim()
	var boss2 := _u(s2, "giant_bamboo")
	boss2.hp = 60
	s2.potions[BattleSim.NPC] = 0
	var legal_ids := []
	for a in s2.legal_actions(BattleSim.NPC):
		legal_ids.append(a.skill.id)
	check(s2.skill_available(boss2, _skill_of(boss2, "regrow")) and not legal_ids.has("regrow"), "without potions Regrow is available but not legal")

	# Flags survive cloning and stay independent; describe shows them.
	var c := s.clone()
	var cboss := _u(c, "giant_bamboo")
	check(cboss.has_flag("phase2") and cboss.has_flag(regrow.used_flag()), "clone copies the flags")
	cboss.clear_flag("phase2")
	check(boss.has_flag("phase2"), "clone flags are independent of the original")
	check(s.describe().contains("phase2"), "describe() lists stored flags")
	check(s.threat_of(boss) > 0.0, "threat model handles the boss (%.1f)" % s.threat_of(boss))

	# The existing search plays a whole boss fight without tripping over the
	# new skills (self-targets, locked skills, flags in clones).
	var fight := _boss_sim()
	var npc := _ai(MinimaxAI.Algorithm.ALPHABETA, 2)
	var player := _ai(MinimaxAI.Algorithm.ALPHABETA, 2)
	player.side = BattleSim.PLAYER
	var used := {}
	while not fight.is_terminal():
		var r := (npc if fight.side_to_move == BattleSim.NPC else player).decide(fight)
		if fight.side_to_move == BattleSim.NPC and not r.action.is_pass():
			used[r.action.skill.id] = true
		fight.apply(r.action, 1)
	check(fight.is_terminal() and fight.turn <= fight.max_turns, "minimax plays a full boss fight to the end (%d turns, winner %d)" % [fight.turn, fight.winner()])
	check(used.has("sap_surge") or used.has("harden_bark"), "the boss used a status skill during the fight: %s" % str(used.keys()))


## Tahap 4 planning model tests live in tests/test_planning.gd.
func _test_plan_model() -> void:
	var script = load("res://tests/test_planning.gd")
	var planning = script.new() if script != null and script.can_instantiate() else null
	if planning == null:
		failures += 1
		print("  FAIL - tests/test_planning.gd failed to load (parse error?)")
		return
	planning.run()
	failures += planning.failures


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
	var expectiminimax := _ai(MinimaxAI.Algorithm.EXPECTIMAX, 1, MinimaxAI.Ordering.HEURISTIC)
	var em := expectiminimax.decide(chance)
	var em_unordered := _ai(MinimaxAI.Algorithm.EXPECTIMAX, 1, MinimaxAI.Ordering.NONE).decide(chance)
	var det := _ai(MinimaxAI.Algorithm.MINIMAX, 1).decide(chance)
	check(em.action != null and em.root_scores.size() > 0, "expectiminimax produces a decision")
	check(_best_score(em) < _best_score(det), "expectiminimax (depth 1) discounts the miss chance (%.1f < %.1f)" % [_best_score(em), _best_score(det)])
	check(em.nodes > det.nodes and em.chance_nodes > 0, "expectiminimax expands both outcomes of chance nodes (%d nodes, %d chance nodes)" % [em.nodes, em.chance_nodes])
	check(is_equal_approx(_best_score(em), _best_score(em_unordered)),
		"expected-value move ordering does not change the Expectiminimax result")

	# At least one root damaging action must expose its Hit/Miss branches.
	var inspected_root: Dictionary = {}
	for entry in em.root_scores:
		var detail: Dictionary = entry.get("chance", {})
		if detail.has("hit_value") and detail.has("miss_value"):
			inspected_root = entry
			break
	check(not inspected_root.is_empty(), "root chance action records Hit and Miss branch values")
	if not inspected_root.is_empty():
		var detail: Dictionary = inspected_root["chance"]
		var p_hit: float = detail["hit_probability"]
		var p_miss: float = detail["miss_probability"]
		var hit_value: float = detail["hit_value"]
		var miss_value: float = detail["miss_value"]
		var recomputed_eu: float = p_hit * hit_value + p_miss * miss_value
		check(is_equal_approx(p_hit + p_miss, 1.0), "Hit and Miss probabilities sum to 1")
		check(is_equal_approx(float(inspected_root["score"]), recomputed_eu)
			and is_equal_approx(float(detail["expected_utility"]), recomputed_eu),
			"Expected Utility uses P(Hit)*U(Hit) + P(Miss)*U(Miss)")
		# Independently rebuild both one-ply outcomes to verify the branch values.
		var inspected_action: BattleAction = inspected_root["action"]
		var reference_hit := chance.clone()
		reference_hit.apply(inspected_action, 1)
		var reference_miss := chance.clone()
		reference_miss.apply(inspected_action, 0)
		var balanced_weights := BattleEvaluator.personality("balanced")
		var reference_hit_value: float = reference_hit.utility(BattleSim.NPC) if reference_hit.is_terminal() else BattleEvaluator.evaluate(reference_hit, BattleSim.NPC, "tactical", balanced_weights)
		var reference_miss_value: float = reference_miss.utility(BattleSim.NPC) if reference_miss.is_terminal() else BattleEvaluator.evaluate(reference_miss, BattleSim.NPC, "tactical", balanced_weights)
		check(is_equal_approx(hit_value, reference_hit_value)
			and is_equal_approx(miss_value, reference_miss_value),
			"Hit/Miss branch utilities match independently simulated outcomes")

	# MEU: the selected action is the root action with the maximum expected score.
	var best_root_score := -INF
	var best_root_action: BattleAction = null
	for entry in em.root_scores:
		var score: float = entry["score"]
		if score > best_root_score:
			best_root_score = score
			best_root_action = entry["action"]
	check(best_root_action != null and em.action.same_as(best_root_action),
		"MEU selects the action with the highest Expected Utility")
	check(is_equal_approx(em.best_value, best_root_score),
		"SearchResult stores the best Expected Utility")

	# A deeper tree must contain both decision-node types plus chance nodes.
	var layered := BattleSim.create(["ninja"], ["evil_bamboo"])
	layered.side_to_move = BattleSim.NPC
	layered.hit_chance = 0.75
	layered.max_turns = 8
	var layered_result := _ai(MinimaxAI.Algorithm.EXPECTIMAX, 3).decide(layered)
	check(layered_result.max_nodes > 0 and layered_result.min_nodes > 0 and layered_result.chance_nodes > 0,
		"Expectiminimax tree contains MAX, MIN, and CHANCE nodes")

	# At 100% Hit Chance there is no uncertainty node to expand.
	var certain := chance.clone()
	certain.hit_chance = 1.0
	var certain_result := _ai(MinimaxAI.Algorithm.EXPECTIMAX, 1).decide(certain)
	check(certain_result.chance_nodes == 0, "100% Hit Chance collapses chance nodes")

	var deep := _ai(MinimaxAI.Algorithm.ALPHABETA, 3)
	var before := mid.describe()
	deep.decide(mid)
	check(mid.describe() == before, "search never mutates the real state")


func _stage4_state_value(sim: BattleSim, side: int) -> float:
	if sim.is_terminal():
		return sim.utility(side)
	return BattleEvaluator.evaluate(sim, side, "tactical", {})


func _test_stage4_expected_utility() -> void:
	print("[Stage 4: Expected Utility module + CSP/Local Search]")

	# 1. A damaging NPC action must expose both outcomes and the weighted EU.
	var chance_sim := _sim()
	chance_sim.side_to_move = BattleSim.NPC
	chance_sim.hit_chance = 0.75
	var attack: BattleAction = null
	for candidate in chance_sim.legal_actions(BattleSim.NPC):
		if chance_sim.is_chance_action(candidate):
			attack = candidate
			break
	check(attack != null, "fixture provides a probabilistic NPC attack")
	if attack != null:
		var original_description := chance_sim.describe()
		var original_rng_state: int = chance_sim.rng.state
		var details: Dictionary = ExpectedUtility.evaluate_action(
			chance_sim, attack, BattleSim.NPC, "tactical", {}
		)
		check(details.get("valid", false) and details.get("probabilistic", false),
			"ExpectedUtility recognises a damaging action as probabilistic")
		check(is_equal_approx(float(details["hit_probability"]), 0.75)
			and is_equal_approx(float(details["miss_probability"]), 0.25),
			"ExpectedUtility uses the configured Hit/Miss probabilities")

		var expected_hit := chance_sim.clone()
		expected_hit.side_to_move = BattleSim.NPC
		expected_hit.apply(attack, 1)
		var expected_miss := chance_sim.clone()
		expected_miss.side_to_move = BattleSim.NPC
		expected_miss.apply(attack, 0)
		var independent_hit_value := _stage4_state_value(expected_hit, BattleSim.NPC)
		var independent_miss_value := _stage4_state_value(expected_miss, BattleSim.NPC)
		var independently_computed_eu := 0.75 * independent_hit_value + 0.25 * independent_miss_value
		check(is_equal_approx(float(details["hit_value"]), independent_hit_value)
			and is_equal_approx(float(details["miss_value"]), independent_miss_value),
			"ExpectedUtility branch values match independent Hit/Miss simulations")
		check(is_equal_approx(float(details["expected_utility"]), independently_computed_eu),
			"ExpectedUtility computes P(Hit)*U(Hit) + P(Miss)*U(Miss)")
		check(chance_sim.describe() == original_description
			and chance_sim.rng.state == original_rng_state,
			"ExpectedUtility does not mutate the source state or its shared RNG")

	# 2. Healing remains deterministic even when the battle Hit Chance is low.
	var heal_sim := BattleSim.create(["ninja"], ["monk"])
	heal_sim.side_to_move = BattleSim.NPC
	heal_sim.hit_chance = 0.30
	var monk := _u(heal_sim, "monk")
	monk.hp -= 10
	var heal_action: BattleAction = null
	for candidate in heal_sim.legal_actions(BattleSim.NPC):
		if candidate.unit == monk.index and candidate.skill.heal > 0:
			heal_action = candidate
			break
	check(heal_action != null, "fixture provides a legal NPC healing action")
	if heal_action != null:
		var heal_rng_state: int = heal_sim.rng.state
		var heal_details: Dictionary = ExpectedUtility.evaluate_action(
			heal_sim, heal_action, BattleSim.NPC, "tactical", {}
		)
		check(heal_details.get("valid", false)
			and not heal_details.get("probabilistic", true)
			and heal_details.get("miss_value", null) == null,
			"ExpectedUtility evaluates healing as a deterministic action")
		check(heal_sim.rng.state == heal_rng_state,
			"deterministic action evaluation does not consume the RNG")

	# 3. evaluate_plan keeps the existing mean-per-action policy but obtains
	#    every action score from the separate ExpectedUtility module.
	var plan_sim := _sim()
	plan_sim.side_to_move = BattleSim.NPC
	plan_sim.hit_chance = 0.65
	var assignment: Dictionary = NpcCSP.build_initial_plan(plan_sim)
	var plan_details: Dictionary = NpcCSP.evaluate_plan_details(plan_sim, assignment)
	var plan_score: float = NpcCSP.evaluate_plan(plan_sim, assignment)
	check(not assignment.is_empty() and NpcCSP.is_assignment_consistent(plan_sim, assignment),
		"CSP still produces a legal assignment after Probability integration")
	check(plan_details.get("valid", false)
		and int(plan_details.get("action_count", 0)) > 0,
		"plan evaluation returns action-level Expected Utility details")
	check(is_equal_approx(plan_score, float(plan_details.get("score", -INF))),
		"evaluate_plan preserves its float API and returns the detailed EU score")

	# 4. Local Search retains the same Hill Climbing flow and exposes the
	#    evaluations for the selected plan to the Debug Overlay.
	var plan_rng_state: int = plan_sim.rng.state
	var best_plan: Dictionary = NpcCSP.local_search(plan_sim, 12)
	var local_stats: Dictionary = NpcCSP.last_local_search_stats
	check(not best_plan.is_empty() and NpcCSP.is_assignment_consistent(plan_sim, best_plan),
		"Local Search still returns a constraint-consistent plan")
	check(local_stats.has("best_action_details")
		and local_stats.has("probabilistic_action_count")
		and local_stats.get("score_method", "") == "mean_expected_utility_per_action",
		"Local Search records Expected Utility details for the Debug Overlay")
	check(plan_sim.rng.state == plan_rng_state,
		"CSP and Local Search evaluation do not advance the live BattleSim RNG")


## Regular encounter: CSP + local search + minimax drive the NPC side.
func _test_full_battle() -> void:
	print("[Full battle autopilot]")
	var battle := await _autopilot_battle(["evil_bamboo", "bear"])
	check(battle.battle_over, "battle reaches an end state (turns: %d)" % battle.sim.turn)
	check(battle.state_machine.is_in(&"Finished"), "state machine ends in Finished")
	check(battle.last_search != null and battle.last_search.root_scores.size() > 0, "NPC decisions were recorded for the overlay")
	print("      winner: %s" % ["player" if battle.victory else "npc/draw"])
	battle.queue_free()
	await get_tree().process_frame


## Tahap 4: the Giant Bamboo fights through the real scene with the planner brain.
func _test_boss_battle() -> void:
	print("[Boss battle autopilot (planner)]")
	Game.ai_config["boss_brain"] = BossBrain.Mode.PLANNER
	var battle := await _autopilot_battle(["giant_bamboo"])
	check(battle.battle_over and battle.state_machine.is_in(&"Finished"), "boss battle reaches an end state (turns: %d)" % battle.sim.turn)
	check(battle.has_boss() and battle.last_decision != null, "the brain decided for the boss")
	var brain := battle.brain
	check(brain.plans_made > 0 and brain.steps_executed > 0, "plans were made and executed: %s" % brain.stats_summary())
	var sources := {}
	for d in brain.history:
		sources[d.source] = true
	check(sources.has("plan"), "plan steps were played (sources: %s)" % str(sources.keys()))
	check(not battle.overlay._plan_info.is_empty(), "overlay shows the planning panel")
	print("      winner: %s, %s" % ["player" if battle.victory else "npc/draw", brain.stats_summary()])
	battle.queue_free()
	await get_tree().process_frame


## Plays a whole fight through the real scene: the player side is an autopilot
## that clicks the first hero / skill / target. Returns the finished battle.
func _autopilot_battle(enemy_party: Array[String]) -> Battle:
	Game.player_party = ["ninja", "flame", "knight", "monk"]
	Game.pending_enemy_party = enemy_party
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
	return battle


func _test_csp() -> void:
	print("[CSP]")
	var s := _sim()
	var domains: Dictionary = NpcCSP.build_domains(s)

	check(
		domains.size() == s.side_units(BattleSim.NPC).size(),
		"domain dibuat untuk setiap NPC"
	)

	var domains_valid := true

	for unit in s.side_units(BattleSim.NPC):
		if not domains.has(unit.index):
			domains_valid = false
			continue

		var options: Array = domains[unit.index]

		if not options.has(null):
			domains_valid = false

		for action in options:
			if action == null:
				continue

			if action.unit != unit.index:
				domains_valid = false

			if not NpcCSP.is_action_legal(s, unit.index, action):
				domains_valid = false

	check(
		domains_valid,
		"setiap domain memiliki null dan hanya action legal milik NPC tersebut"
	)
	

func _test_csp_assignment() -> void:
	print("[CSP assignment]")
	var s := _sim()
	var plan: Dictionary = NpcCSP.backtracking_search(s)

	check(
		not plan.is_empty(),
		"backtracking menghasilkan assignment"
	)

	check(
		NpcCSP.is_assignment_consistent(s, plan),
		"assignment memenuhi constraint CSP"
	)

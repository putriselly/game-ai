extends Node
## End-to-end run: world -> touch enemy -> battle (autopilot) -> back to world.
## Run:  godot --path . res://tests/e2e_runner.tscn   (add --headless to skip screenshots)
## Screenshots go to the folder given by the E2E_SHOTS env var (if set).

var shots_dir: String = OS.get_environment("E2E_SHOTS")
var failures := 0


func _ready() -> void:
	# Detach from the current scene so we survive scene changes.
	call_deferred("_start")


func _start() -> void:
	# Optional overrides for manual checks, e.g. E2E_TARGET_RULE=threat.
	if OS.get_environment("E2E_TARGET_RULE") == "threat":
		Game.ai_config["target_rule"] = BattleSim.TargetRule.THREAT
	var tree := get_tree()
	get_parent().remove_child(self)
	tree.root.add_child(self)
	tree.change_scene_to_file("res://main.tscn")
	_run()


func check(cond: bool, msg: String) -> void:
	print(("  ok   - " if cond else "  FAIL - ") + msg)
	if not cond:
		failures += 1


func wait_frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func wait_until(pred: Callable, max_frames: int) -> bool:
	for _i in range(max_frames):
		if pred.call():
			return true
		await get_tree().process_frame
	return false


func shot(file_name: String) -> void:
	if shots_dir == "" or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(shots_dir.path_join(file_name))
	print("  shot - " + file_name)


func _run() -> void:
	print("[E2E]")
	var ok := await wait_until(func(): return get_tree().current_scene != null and get_tree().current_scene.name == "World", 120)
	check(ok, "world scene loaded")
	var world := get_tree().current_scene
	await wait_frames(20)
	await shot("1_world.png")
	var pf: AStarPathfinder = world.pathfinder
	check(pf != null and pf.blocked_count() > 0, "pathfinder built from tilemap (%d blocked cells)" % (pf.blocked_count() if pf else -1))
	var enemies := get_tree().get_nodes_in_group("world_enemy")
	check(enemies.size() == 3, "3 encounters on the map")
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var bamboo: Node2D = world.get_node("Enemies/BambooPatrol")
	# Stand near the bamboo so it chases us, then wait for the battle.
	var fight_pos := bamboo.global_position + Vector2(40, 0)
	player.global_position = fight_pos
	var chased := await wait_until(func(): return bamboo.state_machine.is_in(&"Chase"), 120)
	check(chased, "enemy switches to Chase when player is close")
	await shot("2_chase.png")
	var in_battle := await wait_until(func(): return get_tree().current_scene is Battle, 600)
	check(in_battle, "touching the enemy starts a battle")
	var battle: Battle = get_tree().current_scene
	await wait_frames(30)
	await shot("3_battle_start.png")
	var foes := battle.sim.alive_units(BattleSim.NPC)
	check(foes.size() == 2 and foes[0].data.id == "evil_bamboo", "battle has the encounter's party")

	# Autopilot: first selectable hero, its first skill, first valid target.
	# The NPC is the real minimax AI (depth from Game.ai_config).
	var took_target_shot := false
	var guard := 0
	while not battle.battle_over and guard < 6000:
		guard += 1
		await get_tree().process_frame
		if battle.state_machine.is_in(&"PlayerTurn"):
			var phase: Battle.PlayerTurn = battle.state_machine.current_state
			var selectable := battle.units.filter(func(u): return u.is_selectable())
			match phase.stage:
				Battle.PlayerTurn.Stage.PICK_HERO:
					if not selectable.is_empty():
						if not took_target_shot:
							await shot("4_hero_pick.png")
						battle.unit_clicked.emit(selectable[0])
				Battle.PlayerTurn.Stage.PICK_SKILL:
					battle.ui.skill_chosen.emit(battle.sim.usable_skills(phase.hero.state)[0])
				Battle.PlayerTurn.Stage.PICK_TARGET:
					if not selectable.is_empty():
						if not took_target_shot:
							await wait_frames(2)
							await shot("5_targeting.png")
							took_target_shot = true
						battle.unit_clicked.emit(selectable[0])
		elif battle.state_machine.is_in(&"NpcTurn") and battle.last_search != null and not battle.overlay._root.visible:
			battle.overlay.toggle()
			await wait_frames(2)
			await shot("6_debug_overlay.png")
	check(battle.battle_over, "battle finished on autopilot (turns: %d, player won: %s)" % [battle.sim.turn, battle.victory])
	await wait_frames(10)
	await shot("7_result.png")
	var won := battle.victory
	battle.ui.continue_pressed.emit()
	var back := await wait_until(func(): return get_tree().current_scene != null and get_tree().current_scene.name == "World", 300)
	check(back, "returns to the world after the battle")
	await wait_frames(5)
	world = get_tree().current_scene
	check((world.get_node_or_null("Enemies/BambooPatrol") == null) == won, "encounter removed only when the player won")
	check(get_tree().get_nodes_in_group("world_enemy").size() == (2 if won else 3), "other encounters remain")
	player = get_tree().get_first_node_in_group("player")
	check(player.global_position.distance_to(fight_pos) < 24.0, "player position restored near where the fight started")
	check(Game.party_hp.size() == (4 if won else 0), "party HP carried over on a win, reset on a loss (%s)" % str(Game.party_hp))
	await wait_frames(10)
	await shot("8_back_in_world.png")
	print("\n%s" % ("E2E PASSED" if failures == 0 else "E2E %d FAILURE(S)" % failures))
	get_tree().quit(0 if failures == 0 else 1)

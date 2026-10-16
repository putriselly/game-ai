class_name Battle
extends Node2D
## Turn-based team duel driven by a [BattleSim] and searched by [MinimaxAI].
##
## Each turn ONE unit of the side to move acts. The player clicks a hero, a
## skill and (if needed) a target; the NPC runs a search on a clone of the
## simulation. Phases are states of the [StateMachine] core.

signal unit_clicked(unit: BattleUnit)

# Two staggered columns per side so labels/bars never overlap a neighbour.
const ALLY_POSITIONS: Array[Vector2] = [
	Vector2(104, 60), Vector2(56, 88), Vector2(104, 116), Vector2(56, 144),
]
const ENEMY_POSITIONS: Array[Vector2] = [
	Vector2(280, 60), Vector2(328, 88), Vector2(280, 116), Vector2(328, 144),
]
const DEFAULT_ENEMIES: Array[String] = ["evil_bamboo", "bear", "bomber"]

var sim: BattleSim
var units: Array[BattleUnit] = []   # index-aligned with sim.units
var ui: BattleUI
var overlay: DebugOverlay
var ai: MinimaxAI
var csp := NpcCSP.new()
var state_machine: StateMachine
var round_number := 0
var battle_over := false
var victory := false
var last_search: MinimaxAI.SearchResult

## Set to true to skip waits/animation delays (used by the automated tests).
var fast_mode := false


func _ready() -> void:
	ui = BattleUI.new()
	add_child(ui)

	var party: Array[String] = Game.player_party if Game.player_party.size() > 0 else ["ninja", "flame", "knight", "monk"]
	var foes: Array[String] = Game.pending_enemy_party if Game.pending_enemy_party.size() > 0 else DEFAULT_ENEMIES
	sim = BattleSim.create(party.slice(0, 4), foes.slice(0, 4), Game.party_hp)
	apply_ai_config()

	var holder := Node2D.new()
	holder.name = "Units"
	add_child(holder)
	var ally_i := 0
	var foe_i := 0
	for state in sim.units:
		var view := BattleUnit.new()
		if state.side == BattleSim.PLAYER:
			view.setup(state, ALLY_POSITIONS[ally_i])
			ally_i += 1
		else:
			view.setup(state, ENEMY_POSITIONS[foe_i])
			foe_i += 1
		holder.add_child(view)
		view.clicked.connect(func(u): unit_clicked.emit(u))
		units.append(view)

	overlay = DebugOverlay.new()
	overlay.setup(self)
	add_child(overlay)

	state_machine = StateMachine.new()
	state_machine.name = "StateMachine"
	add_child(state_machine)
	state_machine.add_state(&"PlayerTurn", PlayerTurn.new())
	state_machine.add_state(&"NpcTurn", NpcTurn.new())
	state_machine.add_state(&"Finished", Finished.new())
	ui.log_line("Battle start! One hero acts per turn. Press F1 for the AI debug overlay.")
	state_machine.start(&"PlayerTurn")


## Builds a MinimaxAI from the shared settings in Game.ai_config.
func make_ai() -> MinimaxAI:
	var cfg: Dictionary = Game.ai_config
	var new_ai := MinimaxAI.new()
	new_ai.side = BattleSim.NPC
	new_ai.algorithm = cfg["algorithm"]
	new_ai.depth = cfg["depth"]
	new_ai.eval_name = cfg["eval"]
	new_ai.personality = cfg["personality"]
	new_ai.ordering = cfg["ordering"]
	new_ai.node_limit = cfg["node_limit"]
	return new_ai


func apply_ai_config() -> void:
	ai = make_ai()
	if sim:
		sim.hit_chance = Game.ai_config["hit_chance"]
		sim.ultimate_mode = Game.ai_config["ultimate_mode"]
		sim.full_targeting = Game.ai_config["full_targeting"]
		sim.target_rule = Game.ai_config["target_rule"]


# --- Helpers ------------------------------------------------------------------

func view_of(state_index: int) -> BattleUnit:
	return units[state_index]


func views_of(states: Array[UnitState]) -> Array[BattleUnit]:
	var out: Array[BattleUnit] = []
	for s in states:
		out.append(units[s.index])
	return out


func wait(seconds: float) -> void:
	if fast_mode:
		await get_tree().process_frame
		return
	await get_tree().create_timer(seconds).timeout


func set_selectable(views: Array[BattleUnit]) -> void:
	for u in units:
		u.set_selectable(views.has(u))


func clear_selectable() -> void:
	set_selectable([])


func refresh_views() -> void:
	for u in units:
		u.refresh()


## Checks the terminal test and, if the battle is over, enters Finished.
func check_battle_end() -> bool:
	if battle_over:
		return true
	if sim.is_terminal():
		battle_over = true
		victory = sim.winner() == BattleSim.PLAYER
		state_machine.transition_to(&"Finished", {"winner": sim.winner()})
		return true
	return false


# --- Action presentation --------------------------------------------------------

## Applies [param action] to the live simulation with animation and log.
func perform(action: BattleAction) -> void:
	if action.is_pass():
		var side_name := "Your team" if sim.side_to_move == BattleSim.PLAYER else "The enemy"
		ui.log_line("%s cannot act (everyone stunned) and passes." % side_name)
		var pass_events := sim.apply(action)
		_present(pass_events)
		await wait(0.5)
		return
	var user := view_of(action.unit)
	ui.log_line("%s uses %s!" % [user.state.display_name(), action.skill.display_name])
	if not fast_mode:
		if action.skill.targets_enemies() and action.targets.size() == 1:
			await user.play_attack(view_of(action.targets[0]).global_position)
		else:
			await user.play_cast()
	var events := sim.apply(action)
	_present(events)
	await wait(0.5)


func _present(events: Array[Dictionary]) -> void:
	for e in events:
		match e["type"]:
			"damage":
				var target := view_of(e["target"])
				target.flash(Color(1, 0.3, 0.3))
				target.spawn_text("-%d" % e["amount"], Color(1, 0.35, 0.35) if e["lost"] > 0 else Color(0.6, 0.8, 1))
				var msg := "  %s takes %d damage" % [target.state.display_name(), e["lost"]]
				if e["absorbed"] > 0:
					msg += " (%d absorbed by shield)" % e["absorbed"]
				ui.log_line(msg + ".")
			"miss":
				var target := view_of(e["target"])
				target.spawn_text("Miss", Color(0.9, 0.9, 0.9))
				ui.log_line("  %s dodges!" % target.state.display_name())
			"heal":
				var target := view_of(e["target"])
				target.flash(Color(0.5, 1, 0.5))
				target.spawn_text("+%d" % e["amount"], Color(0.5, 1, 0.5))
				ui.log_line("  %s recovers %d HP." % [target.state.display_name(), e["amount"]])
			"shield":
				var target := view_of(e["target"])
				target.flash(Color(0.6, 0.8, 1))
				target.spawn_text("+%d shield" % e["amount"], Color(0.6, 0.8, 1))
				ui.log_line("  %s gains %d shield." % [target.state.display_name(), e["amount"]])
			"burn":
				var target := view_of(e["target"])
				target.spawn_text("Burn", Color(1, 0.6, 0.2))
				ui.log_line("  %s is burning (%d turns)." % [target.state.display_name(), e["turns"]])
			"stun":
				var target := view_of(e["target"])
				target.spawn_text("Stun", Color(1, 1, 0.4))
				ui.log_line("  %s is stunned (%d turns)." % [target.state.display_name(), e["turns"]])
			"burn_tick":
				var target := view_of(e["unit"])
				target.flash(Color(1, 0.5, 0.2))
				target.spawn_text("-%d burn" % e["amount"], Color(1, 0.6, 0.2))
				ui.log_line("%s takes %d burn damage." % [target.state.display_name(), e["amount"]])
			"death":
				ui.log_line("  %s is defeated!" % view_of(e["unit"]).state.display_name())
			"potion":
				ui.log_line("  Potion used (%d left)." % e["left"])
			"resist":
				var target := view_of(e["target"])
				target.spawn_text("Resist", Color(0.8, 0.8, 0.8))
				ui.log_line("  %s resists the stun." % target.state.display_name())
	refresh_views()


func surviving_hp() -> Dictionary:
	var out := {}
	for u in sim.side_units(BattleSim.PLAYER):
		out[u.data.id] = maxi(u.hp, 1)
	return out


# --- States -------------------------------------------------------------------

class PlayerTurn extends State:
	enum Stage { PICK_HERO, PICK_SKILL, PICK_TARGET }
	var stage: Stage = Stage.PICK_HERO
	var hero: BattleUnit
	var skill: SkillData
	var _busy := false

	func enter(_data: Dictionary = {}) -> void:
		var b: Battle = owner_node
		b.round_number += 1
		_busy = false
		hero = null
		skill = null
		if b.check_battle_end():
			return
		b.ui.skill_chosen.connect(_on_skill_chosen)
		b.ui.cancel_pressed.connect(_on_cancel)
		b.unit_clicked.connect(_on_unit_clicked)
		var actions := b.sim.legal_actions(BattleSim.PLAYER)
		if actions.size() == 1 and actions[0].is_pass():
			_execute(actions[0])
			return
		_show_hero_pick()

	func exit() -> void:
		var b: Battle = owner_node
		if b.ui.skill_chosen.is_connected(_on_skill_chosen):
			b.ui.skill_chosen.disconnect(_on_skill_chosen)
			b.ui.cancel_pressed.disconnect(_on_cancel)
			b.unit_clicked.disconnect(_on_unit_clicked)
		b.ui.hide_skills()
		b.clear_selectable()

	func _show_hero_pick() -> void:
		var b: Battle = owner_node
		stage = Stage.PICK_HERO
		hero = null
		skill = null
		var ready: Array[UnitState] = []
		for u in b.sim.alive_units(BattleSim.PLAYER):
			if not u.is_stunned():
				ready.append(u)
		b.set_selectable(b.views_of(ready))
		b.ui.show_hero_prompt(b.round_number, b.sim.potions[BattleSim.PLAYER])

	func _on_unit_clicked(view: BattleUnit) -> void:
		if _busy:
			return
		var b: Battle = owner_node
		match stage:
			Stage.PICK_HERO:
				if not view.is_selectable():
					return
				hero = view
				stage = Stage.PICK_SKILL
				b.clear_selectable()
				b.ui.show_skills(hero.state, b.sim.usable_skills(hero.state), b.sim.potions[BattleSim.PLAYER])
			Stage.PICK_TARGET:
				if not view.is_selectable():
					return
				_execute(BattleAction.make(hero.state.index, skill, [view.state.index]))

	func _on_skill_chosen(chosen: SkillData) -> void:
		if _busy or stage != Stage.PICK_SKILL:
			return
		var b: Battle = owner_node
		if chosen.is_ultimate and not hero.state.ult_ready():
			return
		skill = chosen
		if BattleSim.consumes_potion(chosen) and b.sim.potions[BattleSim.PLAYER] <= 0:
			return
		if chosen.needs_target_pick():
			stage = Stage.PICK_TARGET
			var views: Array[BattleUnit] = []
			for i in b.sim.candidate_targets(hero.state, chosen):
				views.append(b.view_of(i))
			if views.is_empty():
				b.ui.log_line("%s would have no effect right now." % chosen.display_name)
				return
			b.set_selectable(views)
			b.ui.show_targeting(chosen)
		else:
			var targets := b.sim.default_targets(hero.state, chosen)
			if targets.is_empty():
				b.ui.log_line("%s would have no effect right now." % chosen.display_name)
				return
			_execute(BattleAction.make(hero.state.index, chosen, targets))

	func _on_cancel() -> void:
		if _busy:
			return
		_show_hero_pick()

	func _execute(action: BattleAction) -> void:
		var b: Battle = owner_node
		_busy = true
		b.ui.hide_skills()
		b.clear_selectable()
		await b.perform(action)
		if b.state_machine.current_state == self and not b.check_battle_end():
			go_to(&"NpcTurn")


class NpcTurn extends State:
	func enter(_data: Dictionary = {}) -> void:
		_run()

	func _run() -> void:
		var b: Battle = owner_node
		b.ui.set_turn("Enemy turn", "The NPC is searching...")
		await b.wait(0.3)
		if b.battle_over:
			return
		var plan: Dictionary = b.csp.local_search(b.sim)
		var allowed_actions: Array[BattleAction] = []
		for unit_index in plan:
			var action = plan[unit_index]
			if action != null and b.csp.is_action_legal(b.sim, unit_index, action):
				allowed_actions.append(action)
		var result := b.ai.decide(b.sim, allowed_actions)
		b.last_search = result
		b.overlay.show_result(result, b.sim)
		var score := 0.0
		for entry in result.root_scores:
			if entry["action"] == result.action:
				score = entry["score"]
		b.ui.log_line("NPC picks %s (score %.1f, %d nodes, %.0f ms)." % [
			result.action.describe(b.sim), score, result.nodes, result.time_ms])
		await b.perform(result.action)
		if b.state_machine.current_state == self and not b.check_battle_end():
			go_to(&"PlayerTurn")


class Finished extends State:
	func enter(data: Dictionary = {}) -> void:
		var b: Battle = owner_node
		var w: int = data.get("winner", -1)
		var won := w == BattleSim.PLAYER
		if w == -1:
			b.ui.set_turn("Draw")
			b.ui.log_line("Turn limit reached: it's a draw.")
			b.ui.show_result("DRAW", Color(0.9, 0.9, 0.9))
		else:
			b.ui.set_turn("Victory!" if won else "Defeat")
			b.ui.log_line("Your party wins!" if won else "Your party was defeated...")
			b.ui.show_result("VICTORY!" if won else "DEFEAT...", Color(1, 0.9, 0.3) if won else Color(1, 0.4, 0.4))
		b.ui.continue_pressed.connect(func(): Game.end_battle(won, b.surviving_hp()), CONNECT_ONE_SHOT)

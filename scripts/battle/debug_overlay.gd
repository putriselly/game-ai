class_name DebugOverlay
extends CanvasLayer
## AI debug overlay (toggle with F1). Shows every root action the NPC
## considered with its score, the node statistics of the last search, running
## totals, live controls for the search settings, and a "compare" button that
## runs all algorithms on the current state to contrast their node counts.

var battle: Battle
var _root: PanelContainer
var _text: RichTextLabel
var _compare_text: RichTextLabel
var _controls: Dictionary = {}
var _total_nodes := 0
var _total_time := 0.0
var _decisions := 0
var _history: Array[String] = []


func setup(battle_node: Battle) -> void:
	battle = battle_node


func _ready() -> void:
	layer = 20
	_root = PanelContainer.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_root.offset_left = -470
	_root.offset_bottom = 520
	_root.visible = false
	add_child(_root)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	_root.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	margin.add_child(box)

	var title := Label.new()
	title.text = "AI DEBUG  (F1 to hide)"
	title.add_theme_font_size_override("font_size", 16)
	box.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	box.add_child(grid)
	_add_option(grid, "Algorithm", "algorithm", MinimaxAI.ALGORITHM_NAMES)
	_add_spin(grid, "Depth", "depth", 1, 8, 1)
	_add_option(grid, "Eval", "eval", BattleEvaluator.EVALUATIONS)
	_add_option(grid, "Personality", "personality", BattleEvaluator.PERSONALITIES)
	_add_option(grid, "Ordering", "ordering", MinimaxAI.ORDERING_NAMES)
	_add_spin(grid, "Node limit", "node_limit", 0, 100000, 50)
	_add_option(grid, "Ultimate", "ultimate_mode", ["auto", "choice"])
	_add_spin(grid, "Hit chance", "hit_chance", 0.3, 1.0, 0.05)
	_add_option(grid, "Target rule", "target_rule", ["weakest", "threat", "toughest", "per_unit"])
	_add_check(grid, "Full targeting", "full_targeting")

	var compare := Button.new()
	compare.text = "Compare algorithms on current state"
	compare.pressed.connect(compare_now)
	box.add_child(compare)

	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.custom_minimum_size = Vector2(0, 200)
	_text.add_theme_font_size_override("normal_font_size", 13)
	box.add_child(_text)
	_compare_text = RichTextLabel.new()
	_compare_text.bbcode_enabled = true
	_compare_text.fit_content = true
	_compare_text.add_theme_font_size_override("normal_font_size", 13)
	box.add_child(_compare_text)
	_render()


func _add_option(grid: GridContainer, label: String, key: String, names: Array) -> void:
	var l := Label.new()
	l.text = label
	grid.add_child(l)
	var opt := OptionButton.new()
	for n in names:
		opt.add_item(n)
	var current = Game.ai_config[key]
	opt.selected = names.find(current) if current is String else int(current)
	opt.item_selected.connect(func(i):
		Game.ai_config[key] = names[i] if current is String else i
		if battle:
			battle.apply_ai_config())
	grid.add_child(opt)
	_controls[key] = opt


func _add_spin(grid: GridContainer, label: String, key: String, min_v: float, max_v: float, step: float) -> void:
	var l := Label.new()
	l.text = label
	grid.add_child(l)
	var spin := SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = step
	spin.value = Game.ai_config[key]
	spin.value_changed.connect(func(v):
		Game.ai_config[key] = int(v) if step >= 1 else v
		if battle:
			battle.apply_ai_config())
	grid.add_child(spin)
	_controls[key] = spin


func _add_check(grid: GridContainer, label: String, key: String) -> void:
	var l := Label.new()
	l.text = label
	grid.add_child(l)
	var box := CheckBox.new()
	box.button_pressed = Game.ai_config[key]
	box.toggled.connect(func(on):
		Game.ai_config[key] = on
		if battle:
			battle.apply_ai_config())
	grid.add_child(box)
	_controls[key] = box


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		_root.visible = not _root.visible
		get_viewport().set_input_as_handled()


func toggle() -> void:
	_root.visible = not _root.visible


## Called by the battle after every NPC decision.
func show_result(result: MinimaxAI.SearchResult, sim: BattleSim) -> void:
	_decisions += 1
	_total_nodes += result.nodes
	_total_time += result.time_ms
	var lines: Array[String] = []
	lines.append("[b]Decision %d[/b]  %s" % [_decisions, result.summary()])
	var sorted := result.root_scores.duplicate()
	sorted.sort_custom(func(a, b): return a["score"] > b["score"])
	for entry in sorted:
		var action: BattleAction = entry["action"]
		var chosen := action == result.action
		var score := "%s%.1f" % ["<= " if entry["bound"] else "", entry["score"]]
		var line := "%s  [%s]" % [action.describe(sim), score]
		lines.append(("[color=yellow]> %s[/color]" if chosen else "   %s") % line)
	_history = lines
	_render()


func _render() -> void:
	var text := "\n".join(_history)
	if _decisions > 0:
		text += "\n[i]Totals: %d decisions, %d nodes, %.1f ms (avg %.0f nodes)[/i]" % [
			_decisions, _total_nodes, _total_time, float(_total_nodes) / _decisions]
	else:
		text = "[i]No NPC decision yet.[/i]"
	_text.text = text


## Runs every algorithm on a copy of the current state and lists node counts.
func compare_now() -> void:
	if battle == null or battle.sim == null:
		return
	var configs := [
		{"label": "minimax", "algorithm": MinimaxAI.Algorithm.MINIMAX, "ordering": MinimaxAI.Ordering.NONE, "node_limit": 0},
		{"label": "alpha-beta (no ordering)", "algorithm": MinimaxAI.Algorithm.ALPHABETA, "ordering": MinimaxAI.Ordering.NONE, "node_limit": 0},
		{"label": "alpha-beta + ordering", "algorithm": MinimaxAI.Algorithm.ALPHABETA, "ordering": MinimaxAI.Ordering.HEURISTIC, "node_limit": 0},
		{"label": "alpha-beta, budget 100", "algorithm": MinimaxAI.Algorithm.ALPHABETA, "ordering": MinimaxAI.Ordering.HEURISTIC, "node_limit": 100},
	]
	var lines: Array[String] = ["[b]Compare (depth %d, %s)[/b]" % [Game.ai_config["depth"], Game.ai_config["eval"]]]
	for c in configs:
		var ai := battle.make_ai()
		ai.algorithm = c["algorithm"]
		ai.ordering = c["ordering"]
		ai.node_limit = c["node_limit"]
		var sim := battle.sim.clone()
		sim.side_to_move = BattleSim.NPC
		var r := ai.decide(sim)
		lines.append("%s: nodes %d, pruned %d, %.1f ms -> %s (%.1f)%s" % [
			c["label"], r.nodes, r.pruned, r.time_ms, r.action.describe(sim),
			_score_of(r), " [budget]" if r.cutoff else ""])
	_compare_text.text = "\n".join(lines)


func _score_of(r: MinimaxAI.SearchResult) -> float:
	for entry in r.root_scores:
		if entry["action"] == r.action:
			return entry["score"]
	return 0.0

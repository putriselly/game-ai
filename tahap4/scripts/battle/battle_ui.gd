class_name BattleUI
extends CanvasLayer
## Bottom command panel + combat log + result overlay. Built in code so the
## battle scene stays small. Emits signals; [Battle] decides what they mean.

signal skill_chosen(skill: SkillData)
signal cancel_pressed
signal continue_pressed

const PANEL_HEIGHT := 120.0
const LOG_LINES := 5

var _panel: PanelContainer
var _turn_label: Label
var _hint_label: Label
var _skill_box: VBoxContainer
var _description: Label
var _log: RichTextLabel
var _cancel_button: Button
var _result: CenterContainer
var _result_label: Label
var _log_lines: PackedStringArray = []


func _ready() -> void:
	layer = 10
	_build_panel()
	_build_result_overlay()
	hide_skills()


func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_top = -PANEL_HEIGHT
	add_child(_panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	_panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	margin.add_child(row)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(220, 0)
	row.add_child(left)
	_turn_label = Label.new()
	_turn_label.add_theme_font_size_override("font_size", 20)
	left.add_child(_turn_label)
	_hint_label = Label.new()
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.modulate = Color(0.85, 0.85, 0.85)
	left.add_child(_hint_label)

	_skill_box = VBoxContainer.new()
	_skill_box.custom_minimum_size = Vector2(240, 0)
	_skill_box.add_theme_constant_override("separation", 6)
	row.add_child(_skill_box)
	_cancel_button = Button.new()
	_cancel_button.text = "Back"
	_cancel_button.pressed.connect(func(): cancel_pressed.emit())
	row.add_child(_cancel_button)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	_description = Label.new()
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.modulate = Color(1, 0.9, 0.6)
	right.add_child(_description)
	_log = RichTextLabel.new()
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.scroll_following = true
	_log.add_theme_font_size_override("normal_font_size", 13)
	right.add_child(_log)


func _build_result_overlay() -> void:
	_result = CenterContainer.new()
	_result.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_result.visible = false
	add_child(_result)
	var panel := PanelContainer.new()
	_result.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	_result_label = Label.new()
	_result_label.add_theme_font_size_override("font_size", 36)
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_result_label)
	var button := Button.new()
	button.text = "Continue"
	button.pressed.connect(func(): continue_pressed.emit())
	box.add_child(button)


# --- API used by Battle -------------------------------------------------------

func set_turn(text: String, hint: String = "") -> void:
	_turn_label.text = text
	_hint_label.text = hint


func show_hero_prompt(round_number: int, potions: int) -> void:
	hide_skills()
	_description.text = ""
	set_turn("Your turn (round %d)" % round_number,
		"Click the hero who acts this turn. One hero acts per turn. Potions left: %d." % potions)


## One button per usable skill of [param unit]. The ultimate button shows the
## charge and is disabled until the bar is full.
func show_skills(unit: UnitState, skills: Array[SkillData], potions: int) -> void:
	for child in _skill_box.get_children():
		child.queue_free()
	for skill in skills:
		var button := Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if skill.is_ultimate:
			button.text = "ULT  %s  (%d%%)" % [skill.display_name, unit.ult]
			button.disabled = not unit.ult_ready()
		elif BattleSim.consumes_potion(skill):
			button.text = "%s  (potion, %d left)" % [skill.display_name, potions]
			button.disabled = potions <= 0
		else:
			button.text = skill.display_name
		button.mouse_entered.connect(func(): _description.text = skill.description)
		button.pressed.connect(func(): skill_chosen.emit(skill))
		_skill_box.add_child(button)
	_skill_box.visible = true
	_cancel_button.visible = true
	_description.text = ""
	set_turn("%s acts" % unit.display_name(), "Choose a skill.")


func show_targeting(skill: SkillData) -> void:
	_skill_box.visible = false
	_cancel_button.visible = true
	_description.text = skill.description
	_hint_label.text = "Click a highlighted %s." % ("enemy" if skill.targets_enemies() else "ally")


func hide_skills() -> void:
	_skill_box.visible = false
	_cancel_button.visible = false


func log_line(text: String) -> void:
	_log_lines.append(text)
	while _log_lines.size() > LOG_LINES:
		_log_lines.remove_at(0)
	_log.text = "\n".join(_log_lines)


func show_result(text: String, color: Color) -> void:
	hide_skills()
	_result_label.text = text
	_result_label.modulate = color
	_result.visible = true

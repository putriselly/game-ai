class_name BattleUnit
extends Node2D
## On-screen view of one [UnitState]: sprite, name, HP / shield / ultimate
## bars, status text and the small animations. It never changes the state
## itself; [Battle] applies actions to the [BattleSim] and tells the view
## what happened.

signal clicked(unit: BattleUnit)

const SPRITE_SCALE := 2.0
## Labels are rasterized at this factor and scaled down, so text stays crisp
## under the battle camera's 3x zoom.
const TEXT_SCALE := 3.0

var state: UnitState
var home_position: Vector2
var sprite: CharacterSprite
var _name_label: Label
var _status_label: Label
var _highlight := false
var _selectable := false
var _dead_shown := false


func setup(unit_state: UnitState, pos: Vector2) -> void:
	state = unit_state
	position = pos
	name = "%s_%d" % [unit_state.data.id, unit_state.index]


func is_player_side() -> bool:
	return state.side == BattleSim.PLAYER


func _ready() -> void:
	home_position = position
	sprite = CharacterSprite.new()
	sprite.name = "Sprite"
	sprite.sprite_folder = state.data.sprite_folder
	sprite.scale = Vector2.ONE * SPRITE_SCALE
	add_child(sprite)
	sprite.direction = CharacterSprite.Dir.RIGHT if is_player_side() else CharacterSprite.Dir.LEFT

	var area := Area2D.new()
	area.name = "ClickArea"
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(20, 24) * SPRITE_SCALE
	shape.shape = rect
	area.add_child(shape)
	area.input_event.connect(_on_area_input)
	area.mouse_entered.connect(func(): if _selectable: _highlight = true; queue_redraw())
	area.mouse_exited.connect(func(): _highlight = false; queue_redraw())
	add_child(area)

	_name_label = _make_label(state.data.display_name, Vector2(-30, -27), 7)
	_status_label = _make_label("", Vector2(-30, -34), 6)
	_status_label.modulate = Color(1.0, 0.6, 0.2)
	refresh()


func _make_label(text: String, offset: Vector2, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.position = offset
	label.size = Vector2(60, 8) * TEXT_SCALE
	label.scale = Vector2.ONE / TEXT_SCALE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", int(size * TEXT_SCALE))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 2)
	add_child(label)
	return label


## Re-reads the state: bars, status text and death look.
func refresh() -> void:
	var parts: PackedStringArray = []
	if state.burn > 0:
		parts.append("Burn %d" % state.burn)
	if state.stun > 0:
		parts.append("Stun %d" % state.stun)
	_status_label.text = " ".join(parts)
	if not state.is_alive() and not _dead_shown:
		_dead_shown = true
		sprite.play(CharacterSprite.ANIM_DEAD)
		var tween := create_tween()
		tween.tween_property(sprite, "modulate:a", 0.35, 0.5)
	queue_redraw()


# --- Selection ----------------------------------------------------------------

func set_selectable(value: bool) -> void:
	_selectable = value
	if not value:
		_highlight = false
	queue_redraw()


func is_selectable() -> bool:
	return _selectable


func _on_area_input(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if not _selectable:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(self)


# --- Animations ---------------------------------------------------------------

## Lunges toward [param target_position] and back. Awaitable.
func play_attack(target_position: Vector2) -> void:
	sprite.play(CharacterSprite.ANIM_ATTACK)
	var dir := (target_position - global_position).normalized()
	var tween := create_tween()
	tween.tween_property(self, "position", home_position + dir * 14.0, 0.12)
	tween.tween_interval(0.1)
	tween.tween_property(self, "position", home_position, 0.15)
	await tween.finished
	sprite.play(CharacterSprite.ANIM_IDLE)


func play_cast() -> void:
	sprite.play(CharacterSprite.ANIM_ATTACK)
	var tween := create_tween()
	tween.tween_property(self, "position", home_position + Vector2(0, -6), 0.1)
	tween.tween_property(self, "position", home_position, 0.15)
	await tween.finished
	sprite.play(CharacterSprite.ANIM_IDLE)


func flash(color: Color) -> void:
	if sprite == null:
		return
	var tween := create_tween()
	sprite.modulate = color
	var back := Color.WHITE if state.is_alive() else Color(1, 1, 1, 0.35)
	tween.tween_property(sprite, "modulate", back, 0.3)


func spawn_text(text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.position = Vector2(-30, -22)
	label.size = Vector2(60, 10) * TEXT_SCALE
	label.scale = Vector2.ONE / TEXT_SCALE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.modulate = color
	label.add_theme_font_size_override("font_size", int(8 * TEXT_SCALE))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 2)
	add_child(label)
	var tween := create_tween()
	tween.tween_property(label, "position:y", -40.0, 0.7)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.7).set_delay(0.3)
	tween.tween_callback(label.queue_free)


# --- Bars ---------------------------------------------------------------------

func _draw() -> void:
	if state == null:
		return
	var w := 32.0
	var x := -w / 2.0
	var y := 18.0
	if _selectable:
		var ring_color := Color(1, 1, 0.3, 1.0 if _highlight else 0.6)
		draw_arc(Vector2(0, 12), 19.0, 0.0, TAU, 24, ring_color, 1.5)
	draw_rect(Rect2(x - 1, y - 1, w + 2, 6), Color.BLACK)
	draw_rect(Rect2(x, y, w, 4), Color(0.25, 0.1, 0.1))
	var hp_color := Color(0.3, 0.85, 0.3) if is_player_side() else Color(0.9, 0.3, 0.3)
	draw_rect(Rect2(x, y, w * state.hp_ratio(), 4), hp_color)
	if state.shield > 0:
		var shield_w := w * clampf(float(state.shield) / float(state.data.max_hp), 0.0, 1.0)
		draw_rect(Rect2(x, y, shield_w, 2), Color(0.6, 0.8, 1))
	var uy := y + 7
	draw_rect(Rect2(x - 1, uy - 1, w + 2, 5), Color.BLACK)
	draw_rect(Rect2(x, uy, w, 3), Color(0.15, 0.15, 0.25))
	var ult_color := Color(1, 0.85, 0.2) if state.ult_ready() else Color(0.5, 0.45, 0.9)
	draw_rect(Rect2(x, uy, w * float(state.ult) / float(BattleSim.ULT_MAX), 3), ult_color)

class_name Character
extends CharacterBody2D
## Base class for every actor that walks around the overworld.
##
## Provides: stats (HP), a [CharacterSprite] child, a [StateMachine] child and
## helpers to walk along an A* path produced by [AStarPathfinder].
## Player and enemies extend this and only add their own states.

signal hp_changed(current: int, maximum: int)
signal died

const TILE_SIZE := 16

@export var display_name: String = "Character"
@export_dir var sprite_folder: String = "res://assets/Actor/Character/NinjaGreen"
@export var speed: float = 96.0
@export var max_hp: int = 30

var hp: int
var facing: Vector2 = Vector2.DOWN

## Path (in tile cells) the character is currently following.
var path: Array[Vector2i] = []
var _path_index: int = 0

var sprite: CharacterSprite
var state_machine: StateMachine


func _ready() -> void:
	hp = max_hp
	sprite = get_node_or_null("Sprite") as CharacterSprite
	if sprite == null:
		sprite = CharacterSprite.new()
		sprite.name = "Sprite"
		add_child(sprite)
	sprite.sprite_folder = sprite_folder
	state_machine = get_node_or_null("StateMachine") as StateMachine
	if state_machine == null:
		state_machine = StateMachine.new()
		state_machine.name = "StateMachine"
		add_child(state_machine)
	_setup_states()


## Override to register states on [member state_machine] and start it.
func _setup_states() -> void:
	pass


# --- Stats -------------------------------------------------------------------

func take_damage(amount: int) -> void:
	hp = clampi(hp - amount, 0, max_hp)
	hp_changed.emit(hp, max_hp)
	if hp == 0:
		died.emit()


func heal(amount: int) -> void:
	hp = clampi(hp + amount, 0, max_hp)
	hp_changed.emit(hp, max_hp)


func is_alive() -> bool:
	return hp > 0


# --- Movement ----------------------------------------------------------------

func cell() -> Vector2i:
	return world_to_cell(global_position)


static func world_to_cell(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / TILE_SIZE), floori(pos.y / TILE_SIZE))


static func cell_to_world(c: Vector2i) -> Vector2:
	return Vector2(c) * TILE_SIZE + Vector2.ONE * (TILE_SIZE / 2.0)


func set_path(new_path: Array[Vector2i]) -> void:
	path = new_path
	_path_index = 0
	# The first cell is the one we are standing on; skip it.
	if path.size() > 1 and path[0] == cell():
		_path_index = 1


func has_path() -> bool:
	return _path_index < path.size()


## Walks one physics step along the current path.
## Returns true when the end of the path has been reached.
func follow_path(_delta: float) -> bool:
	if not has_path():
		stop()
		return true
	var target := cell_to_world(path[_path_index])
	if global_position.distance_to(target) < 2.0:
		_path_index += 1
		if not has_path():
			stop()
			return true
		target = cell_to_world(path[_path_index])
	move_towards(target)
	return false


## Sets velocity toward [param target] at [member speed] and moves.
func move_towards(target: Vector2) -> void:
	var dir := (target - global_position).normalized()
	move_in_direction(dir)


func move_in_direction(dir: Vector2) -> void:
	velocity = dir * speed
	if dir != Vector2.ZERO:
		facing = dir
		sprite.face(dir)
		sprite.play(CharacterSprite.ANIM_WALK)
	else:
		sprite.play(CharacterSprite.ANIM_IDLE)
	move_and_slide()


func stop() -> void:
	velocity = Vector2.ZERO
	sprite.play(CharacterSprite.ANIM_IDLE)

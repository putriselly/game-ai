class_name Player
extends Character
## Overworld player: keyboard driven, two states (Idle / Walk).


func _ready() -> void:
	add_to_group("player")
	super()


func _setup_states() -> void:
	state_machine.add_state(&"Idle", IdleState.new())
	state_machine.add_state(&"Walk", WalkState.new())
	state_machine.start(&"Idle")


static func input_direction() -> Vector2:
	return Input.get_vector("left", "right", "up", "down")


class IdleState extends State:
	func enter(_data: Dictionary = {}) -> void:
		owner_node.stop()

	func physics_update(_delta: float) -> void:
		if Player.input_direction() != Vector2.ZERO:
			go_to(&"Walk")


class WalkState extends State:
	func physics_update(_delta: float) -> void:
		var dir := Player.input_direction()
		if dir == Vector2.ZERO:
			go_to(&"Idle")
			return
		owner_node.move_in_direction(dir)

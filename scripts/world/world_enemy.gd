class_name WorldEnemy
extends Character
## Overworld enemy. Wanders around using A* paths, chases the player when
## they come close, and starts a battle when it touches them.
##
## States: Idle -> Wander -> Idle ... and Idle/Wander -> Chase -> Idle.

## Identifies this encounter so it stays gone after being beaten.
@export var encounter_id: String = "encounter_1"
## Unit ids (see [Roster]) that the player fights when touching this enemy.
@export var enemy_party: Array[String] = ["evil_bamboo", "bear"]
## Distance (px) at which the enemy notices the player.
@export var detect_radius: float = 80.0
## Distance (px) at which a chasing enemy gives up.
@export var lose_radius: float = 140.0
## How far (in tiles) a wander target may be from the current cell.
@export var wander_range: int = 4

var _battle_started := false


func _ready() -> void:
	add_to_group("world_enemy")
	super()
	var hitbox := get_node_or_null("Hitbox") as Area2D
	if hitbox:
		hitbox.body_entered.connect(_on_hitbox_body_entered)


func _setup_states() -> void:
	state_machine.add_state(&"Idle", IdleState.new())
	state_machine.add_state(&"Wander", WanderState.new())
	state_machine.add_state(&"Chase", ChaseState.new())
	state_machine.start(&"Idle")


func get_pathfinder() -> AStarPathfinder:
	var world := get_tree().get_first_node_in_group("world")
	return world.pathfinder if world else null


func get_player() -> Node2D:
	return get_tree().get_first_node_in_group("player") as Node2D


func distance_to_player() -> float:
	var player := get_player()
	return global_position.distance_to(player.global_position) if player else INF


func _on_hitbox_body_entered(body: Node) -> void:
	if _battle_started or not body.is_in_group("player"):
		return
	_battle_started = true
	stop()
	Game.start_battle(encounter_id, enemy_party, body.global_position)


class IdleState extends State:
	var _timer := 0.0

	func enter(_data: Dictionary = {}) -> void:
		owner_node.stop()
		_timer = randf_range(1.0, 2.5)

	func physics_update(delta: float) -> void:
		if owner_node.distance_to_player() < owner_node.detect_radius:
			go_to(&"Chase")
			return
		_timer -= delta
		if _timer <= 0.0:
			go_to(&"Wander")


class WanderState extends State:
	func enter(_data: Dictionary = {}) -> void:
		var finder: AStarPathfinder = owner_node.get_pathfinder()
		if finder == null:
			go_to(&"Idle")
			return
		var start: Vector2i = owner_node.cell()
		# Try a few random cells; give up and idle if none is walkable.
		for _i in range(8):
			var r: int = owner_node.wander_range
			var goal := start + Vector2i(randi_range(-r, r), randi_range(-r, r))
			if goal != start and finder.is_walkable(goal):
				var found := finder.find_path(start, goal)
				if found.size() > 1:
					owner_node.set_path(found)
					return
		go_to(&"Idle")

	func physics_update(delta: float) -> void:
		if owner_node.distance_to_player() < owner_node.detect_radius:
			go_to(&"Chase")
			return
		if owner_node.follow_path(delta):
			go_to(&"Idle")


class ChaseState extends State:
	const REPATH_INTERVAL := 0.3
	var _repath := 0.0

	func enter(_data: Dictionary = {}) -> void:
		_repath = 0.0

	func physics_update(delta: float) -> void:
		var enemy: WorldEnemy = owner_node
		var player := enemy.get_player()
		if player == null or enemy.distance_to_player() > enemy.lose_radius:
			go_to(&"Idle")
			return
		_repath -= delta
		if _repath <= 0.0:
			_repath = REPATH_INTERVAL
			var finder := enemy.get_pathfinder()
			if finder:
				enemy.set_path(finder.find_path(enemy.cell(), Character.world_to_cell(player.global_position)))
		# When adjacent, walk straight at the player so the hitbox connects.
		if enemy.distance_to_player() < Character.TILE_SIZE * 1.5:
			enemy.move_towards(player.global_position)
		else:
			enemy.follow_path(delta)

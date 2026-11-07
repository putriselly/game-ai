extends Node2D
## Overworld root: builds the pathfinding grid from the tile layers, restores
## the player after a battle and removes encounters that were already beaten.

@export var collision_layers: Array[TileMapLayer] = []

var pathfinder: AStarPathfinder


func _ready() -> void:
	add_to_group("world")
	if collision_layers.is_empty():
		for child in get_children():
			if child is TileMapLayer:
				collision_layers.append(child)
	pathfinder = AStarPathfinder.from_tilemap_layers(collision_layers)

	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player and Game.has_saved_position:
		player.global_position = Game.saved_player_position
		Game.has_saved_position = false

	for enemy in get_tree().get_nodes_in_group("world_enemy"):
		if Game.is_defeated(enemy.encounter_id):
			enemy.queue_free()

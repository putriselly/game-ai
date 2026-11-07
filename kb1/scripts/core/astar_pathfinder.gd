class_name AStarPathfinder
extends RefCounted
## Simple A* pathfinding on a rectangular grid of cells.
##
## The grid is described by a rectangle of cell coordinates plus a set of
## blocked cells. Movement is 4-directional (no diagonals) so a path never cuts
## through the corner of a wall. Heuristic: Manhattan distance, which is
## admissible for 4-directional movement, so the returned path is optimal.
##
## [codeblock]
## var finder := AStarPathfinder.new(Rect2i(0, 0, 40, 30))
## finder.set_blocked(Vector2i(5, 5), true)
## var path: Array[Vector2i] = finder.find_path(Vector2i(0, 0), Vector2i(9, 9))
## [/codeblock]

const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]

var region: Rect2i
var _blocked: Dictionary = {}  # Vector2i -> true


func _init(grid_region: Rect2i = Rect2i()) -> void:
	region = grid_region


func set_blocked(cell: Vector2i, blocked: bool) -> void:
	if blocked:
		_blocked[cell] = true
	else:
		_blocked.erase(cell)


func is_blocked(cell: Vector2i) -> bool:
	return _blocked.has(cell)


func is_walkable(cell: Vector2i) -> bool:
	return region.has_point(cell) and not _blocked.has(cell)


func blocked_count() -> int:
	return _blocked.size()


## Returns the list of cells from [param start] to [param goal] (both inclusive).
## Returns an empty array when no path exists. If [param goal] is blocked, the
## path goes to the closest reachable cell instead so chasers still approach.
func find_path(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not region.has_point(start) or not region.has_point(goal):
		return result
	if start == goal:
		result.append(start)
		return result

	var open: Array[Vector2i] = [start]      # cells still to examine
	var came_from: Dictionary = {}           # cell -> previous cell
	var g_score: Dictionary = {start: 0}     # cheapest known cost from start
	var f_score: Dictionary = {start: _heuristic(start, goal)}
	var closed: Dictionary = {}              # cells fully examined

	var best_cell := start                   # fallback when goal is unreachable
	var best_h := _heuristic(start, goal)

	while not open.is_empty():
		var current := _pop_lowest(open, f_score)
		if current == goal:
			return _reconstruct(came_from, current)
		closed[current] = true

		var h := _heuristic(current, goal)
		if h < best_h:
			best_h = h
			best_cell = current

		for dir in DIRECTIONS:
			var neighbor: Vector2i = current + dir
			if closed.has(neighbor):
				continue
			if not region.has_point(neighbor):
				continue
			# The goal itself may be blocked (an actor standing on it); we still
			# want to path right next to it, so only reject non-goal blocked cells.
			if _blocked.has(neighbor) and neighbor != goal:
				continue
			var tentative: int = g_score[current] + 1
			if tentative < g_score.get(neighbor, 1 << 30):
				came_from[neighbor] = current
				g_score[neighbor] = tentative
				f_score[neighbor] = tentative + _heuristic(neighbor, goal)
				if not open.has(neighbor):
					open.append(neighbor)

	# No path: return the route to the closest cell we could reach.
	if best_cell != start:
		return _reconstruct(came_from, best_cell)
	return result


func _heuristic(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


## Removes and returns the open cell with the lowest f score.
## A linear scan is plenty for maps of a few thousand cells.
func _pop_lowest(open: Array[Vector2i], f_score: Dictionary) -> Vector2i:
	var best_index := 0
	var best_f: int = f_score.get(open[0], 1 << 30)
	for i in range(1, open.size()):
		var f: int = f_score.get(open[i], 1 << 30)
		if f < best_f:
			best_f = f
			best_index = i
	var cell := open[best_index]
	open.remove_at(best_index)
	return cell


func _reconstruct(came_from: Dictionary, current: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [current]
	while came_from.has(current):
		current = came_from[current]
		path.push_front(current)
	return path


## Builds a pathfinder from TileMapLayers: every cell that has a physics
## collision polygon on any of the given layers is marked blocked.
static func from_tilemap_layers(layers: Array[TileMapLayer], physics_layer: int = 0) -> AStarPathfinder:
	var bounds := Rect2i()
	var first := true
	for layer in layers:
		var used := layer.get_used_rect()
		if used.size == Vector2i.ZERO:
			continue
		bounds = used if first else bounds.merge(used)
		first = false
	var finder := AStarPathfinder.new(bounds)
	for layer in layers:
		for cell in layer.get_used_cells():
			var data := layer.get_cell_tile_data(cell)
			if data and data.get_collision_polygons_count(physics_layer) > 0:
				finder.set_blocked(cell, true)
	return finder

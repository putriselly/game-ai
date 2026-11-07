extends Node2D


@onready var debug_label = $DebugLabel
@onready var ucs_button = $UCSButton
@onready var astar_button = $AStarButton


# =========================
# MAP CONFIGURATION
# =========================

const CELL_SIZE = 50
const ROWS = 10
const COLS = 15


var map = [
	[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
	[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
	[0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0],
	[0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0],
	[0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 1, 1, 0, 0, 0],
	[0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0],
	[0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0],
	[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
	[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
	[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
]


# =========================
# START, GOAL, AND PATH
# =========================

var start = Vector2i(1, 1)
var goal = Vector2i(13, 8)

var path = []
var expanded_nodes = 0
var expanded = []

var npc_position = Vector2(start.x, start.y)
var path_index = 0
var npc_speed = 3.0


# =========================
# GET NEIGHBORS
# =========================

func get_neighbors(position):
	var neighbors = []
	
	var directions = [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1)
	]
	
	for direction in directions:
		var neighbor = position + direction
		
		if neighbor.x >= 0 and neighbor.x < COLS:
			if neighbor.y >= 0 and neighbor.y < ROWS:
				if map[neighbor.y][neighbor.x] == 0:
					neighbors.append(neighbor)
	
	return neighbors


# =========================
# HEURISTIC
# =========================

func heuristic(position):
	return abs(position.x - goal.x) + abs(position.y - goal.y)
	
func heuristic_euclidean(position):
	return sqrt(
		(position.x - goal.x) * (position.x - goal.x) +
		(position.y - goal.y) * (position.y - goal.y)
	)


# =========================
# UNIFORM COST SEARCH
# =========================

func ucs():
	path = []
	expanded_nodes = 0
	expanded = []
	
	var frontier = []
	var cost_so_far = {}
	var came_from = {}
	
	frontier.append(start)
	cost_so_far[start] = 0
	came_from[start] = null
	
	while frontier.size() > 0:
		var current = frontier[0]
		
		for node in frontier:
			if cost_so_far[node] < cost_so_far[current]:
				current = node
		
		frontier.erase(current)
		expanded_nodes += 1
		expanded.append(current)
		
		if current == goal:
			break
		
		for neighbor in get_neighbors(current):
			var new_cost = cost_so_far[current] + 1
			
			if !cost_so_far.has(neighbor) or new_cost < cost_so_far[neighbor]:
				cost_so_far[neighbor] = new_cost
				came_from[neighbor] = current
				
				if !frontier.has(neighbor):
					frontier.append(neighbor)
	
	if !came_from.has(goal):
		return
	
	var current = goal
	
	while current != null:
		path.push_front(current)
		current = came_from[current]


# =========================
# A* SEARCH
# =========================

func astar():
	path = []
	expanded_nodes = 0
	expanded = []
	
	var frontier = []
	var cost_so_far = {}
	var came_from = {}
	
	frontier.append(start)
	cost_so_far[start] = 0
	came_from[start] = null
	
	while frontier.size() > 0:
		var current = frontier[0]
		
		for node in frontier:
			var current_f = cost_so_far[current] + heuristic_euclidean(current)
			var node_f = cost_so_far[node] + heuristic_euclidean(node)
			
			if node_f < current_f:
				current = node
		
		frontier.erase(current)
		expanded_nodes += 1
		expanded.append(current)
		
		if current == goal:
			break
		
		for neighbor in get_neighbors(current):
			var new_cost = cost_so_far[current] + 1
			
			if !cost_so_far.has(neighbor) or new_cost < cost_so_far[neighbor]:
				cost_so_far[neighbor] = new_cost
				came_from[neighbor] = current
				
				if !frontier.has(neighbor):
					frontier.append(neighbor)
	
	if !came_from.has(goal):
		return
	
	var current = goal
	
	while current != null:
		path.push_front(current)
		current = came_from[current]
		
func run_search(algorithm):
	path_index = 0
	npc_position = Vector2(start.x, start.y)
	
	if algorithm == "UCS":
		ucs()
	else:
		astar()
	
	debug_label.text = algorithm + "\nExpanded nodes: " + str(expanded_nodes) + "\nPath cost: " + str(path.size() - 1)
	
	queue_redraw()


# =========================
# INITIALIZATION
# =========================

func _ready():
	ucs_button.position = Vector2(850, 100)
	ucs_button.size = Vector2(120, 50)

	astar_button.position = Vector2(850, 170)
	astar_button.size = Vector2(120, 50)

	ucs_button.pressed.connect(run_search.bind("UCS"))
	astar_button.pressed.connect(run_search.bind("A*"))
	run_search("A*")


# =========================
# NPC MOVEMENT
# =========================

func _process(delta):
	if path_index < path.size():
		var target = path[path_index]
		
		npc_position = npc_position.move_toward(
			Vector2(target),
			npc_speed * delta
		)
		
		if npc_position.distance_to(Vector2(target)) < 0.01:
			npc_position = Vector2(target)
			path_index += 1
		
		queue_redraw()


# =========================
# DRAW MAP AND PATH
# =========================

func _draw():
	# Draw map
	for row in range(ROWS):
		for col in range(COLS):
			var position = Vector2(col * CELL_SIZE, row * CELL_SIZE)
			
			if map[row][col] == 1:
				draw_rect(
					Rect2(position, Vector2(CELL_SIZE, CELL_SIZE)),
					Color.DARK_GRAY
				)
			else:
				draw_rect(
					Rect2(position, Vector2(CELL_SIZE, CELL_SIZE)),
					Color.WHITE,
					false,
					1
				)
	
	# Draw expanded nodes
	for position in expanded:
		draw_rect(
			Rect2(
				position.x * CELL_SIZE + 8,
				position.y * CELL_SIZE + 8,
				CELL_SIZE - 16,
				CELL_SIZE - 16
			),
			Color.CORNFLOWER_BLUE
		)
	
	# Draw final path
	for position in path:
		draw_rect(
			Rect2(
				position.x * CELL_SIZE + 15,
				position.y * CELL_SIZE + 15,
				CELL_SIZE - 30,
				CELL_SIZE - 30
			),
			Color.YELLOW
		)
	
	# Draw NPC
	draw_circle(
		Vector2(
			npc_position.x * CELL_SIZE + 25,
			npc_position.y * CELL_SIZE + 25
		),
		15,
		Color.GREEN
	)
	
	# Draw goal
	draw_circle(
		Vector2(
			goal.x * CELL_SIZE + 25,
			goal.y * CELL_SIZE + 25
		),
		15,
		Color.RED
	)

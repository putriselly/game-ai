extends Node2D


@onready var debug_label = $DebugLabel
@onready var ucs_button = $UCSButton
@onready var astar_button = $AStarButton

var npc_sprite
var player_sprite


# MAP CONFIGURATION

const CELL_SIZE = 36
const ROWS = 18
const COLS = 32

var map = [
	[1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1], 
	[1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1], 
	[1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1], 
	[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], 

	[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], 
	[1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0], 
	[1, 1, 1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 1, 1, 1], 
	[1, 1, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 1, 1, 1, 1], 

	[1, 1, 1, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1], 
	[1, 1, 1, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 0, 0, 1, 1, 1, 1], 
	[1, 1, 1, 0, 0, 1, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 0, 0, 1, 1, 1, 1], 

	[0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 1, 1], 
	[0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0], 
	[1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0], 
	[1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0], 

	[1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0], 
	[1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1], 
	[1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1] 
]


# PLAYER AND NPC

var player_position = Vector2i(4, 4)
var start = Vector2i(4, 4)
var finish = Vector2i(29, 15)

var npc_position = Vector2(27, 15)


# SEARCH DATA

var path = []
var path_index = 0

var expanded = []
var expanded_nodes = 0

var npc_speed = 5.0


# ALGORITHM

var current_algorithm = "A*"
var current_heuristic = "Manhattan"

var game_over = false
var win = false


# GET NEIGHBORS

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


# MANHATTAN HEURISTIC

func heuristic_manhattan(position):

	return abs(
		position.x - player_position.x
	) + abs(
		position.y - player_position.y
	)


# EUCLIDEAN HEURISTIC

func heuristic_euclidean(position):

	return sqrt(
		(position.x - player_position.x) * (position.x - player_position.x) +
		(position.y - player_position.y) * (position.y - player_position.y)
	)


# CHEBYSHEV HEURISTIC

func heuristic_chebyshev(position):

	return max(
		abs(position.x - player_position.x),
		abs(position.y - player_position.y)
	)


# GET HEURISTIC

func get_heuristic(position):

	if current_heuristic == "Manhattan":

		return heuristic_manhattan(position)

	elif current_heuristic == "Euclidean":

		return heuristic_euclidean(position)

	else:

		return heuristic_chebyshev(position)


# UNIFORM COST SEARCH

func ucs():

	path = []
	expanded = []
	expanded_nodes = 0

	var frontier = []
	var cost_so_far = {}
	var came_from = {}

	var npc_start = Vector2i(
		int(round(npc_position.x)),
		int(round(npc_position.y))
	)

	frontier.append(npc_start)

	cost_so_far[npc_start] = 0

	came_from[npc_start] = null

	while frontier.size() > 0:

		var current = frontier[0]

		for node in frontier:

			if cost_so_far[node] < cost_so_far[current]:

				current = node

		frontier.erase(current)

		expanded_nodes += 1
		expanded.append(current)

		if current == player_position:

			break

		for neighbor in get_neighbors(current):

			var new_cost = cost_so_far[current] + 1

			if !cost_so_far.has(neighbor) or new_cost < cost_so_far[neighbor]:

				cost_so_far[neighbor] = new_cost
				came_from[neighbor] = current

				if !frontier.has(neighbor):

					frontier.append(neighbor)

	if !came_from.has(player_position):

		return

	var current = player_position

	while current != null:

		path.push_front(current)
		current = came_from[current]


# A* SEARCH

func astar():

	path = []
	expanded = []
	expanded_nodes = 0

	var frontier = []
	var cost_so_far = {}
	var came_from = {}

	var npc_start = Vector2i(
		int(round(npc_position.x)),
		int(round(npc_position.y))
	)

	frontier.append(npc_start)

	cost_so_far[npc_start] = 0

	came_from[npc_start] = null

	while frontier.size() > 0:

		var current = frontier[0]

		for node in frontier:

			var current_f = cost_so_far[current] + get_heuristic(current)
			var node_f = cost_so_far[node] + get_heuristic(node)

			if node_f < current_f:

				current = node

		frontier.erase(current)

		expanded_nodes += 1
		expanded.append(current)

		if current == player_position:

			break

		for neighbor in get_neighbors(current):

			var new_cost = cost_so_far[current] + 1

			if !cost_so_far.has(neighbor) or new_cost < cost_so_far[neighbor]:

				cost_so_far[neighbor] = new_cost
				came_from[neighbor] = current

				if !frontier.has(neighbor):

					frontier.append(neighbor)

	if !came_from.has(player_position):

		return

	var current = player_position

	while current != null:

		path.push_front(current)
		current = came_from[current]


# RUN SEARCH

func run_search(algorithm):

	current_algorithm = algorithm
	path_index = 0

	if algorithm == "UCS":

		ucs()

	else:

		astar()

	var path_cost = path.size() - 1

	debug_label.text = (
		"Algorithm: " + current_algorithm +
		"\nHeuristic: " + current_heuristic +
		"\nExpanded nodes: " + str(expanded_nodes) +
		"\nPath cost: " + str(path_cost) +
		"\n\nWASD / Arrow Keys = Move Player" +
		"\nM = Manhattan" +
		"\nE = Euclidean" +
		"\nC = Chebyshev"
	)

	queue_redraw()


# CHECK FINISH

func check_finish():

	if player_position == finish:

		game_over = true
		win = true

		debug_label.text = "YOU WIN!"

		print("YOU WIN!")

		queue_redraw()


# CHECK NPC CATCH PLAYER

func check_caught():

	var npc_grid_position = Vector2i(
		int(round(npc_position.x)),
		int(round(npc_position.y))
	)

	if npc_grid_position == player_position:

		game_over = true
		win = false

		debug_label.text = "GAME OVER!"

		print("GAME OVER!")

		queue_redraw()


# PLAYER MOVEMENT

func move_player(direction):

	if game_over:

		return

	var new_position = player_position + direction

	if new_position.x < 0 or new_position.x >= COLS:

		return

	if new_position.y < 0 or new_position.y >= ROWS:

		return

	print("Player: ", player_position)
	print("Mau ke: ", new_position)
	print("Map: ", map[new_position.y][new_position.x])

	if map[new_position.y][new_position.x] == 1:

		return

	player_position = new_position

	# Langsung pindahkan sprite Player

	if player_sprite != null:

		player_sprite.global_position = Vector2(
			player_position.x * CELL_SIZE + 18,
			player_position.y * CELL_SIZE + 18
		)

	check_finish()

	if game_over:

		return

	npc_position = Vector2(
		round(npc_position.x),
		round(npc_position.y)
	)

	run_search(current_algorithm)


# INITIALIZATION

func _ready():

	# Ambil NPC dari Scene Tree

	npc_sprite = get_node_or_null("NPC")

	if npc_sprite == null:

		print("ERROR: Node NPC tidak ditemukan!")

	else:

		npc_sprite.global_position = Vector2(
			npc_position.x * CELL_SIZE + 18,
			npc_position.y * CELL_SIZE + 18
		)


	# Ambil Player dari Scene Tree

	player_sprite = get_node_or_null("Player")

	if player_sprite == null:

		print("ERROR: Node Player tidak ditemukan!")

	else:

		player_sprite.global_position = Vector2(
			player_position.x * CELL_SIZE + 18,
			player_position.y * CELL_SIZE + 18
		)


	ucs_button.position = Vector2(950, 100)
	ucs_button.size = Vector2(120, 50)

	astar_button.position = Vector2(950, 170)
	astar_button.size = Vector2(120, 50)

	ucs_button.pressed.connect(run_search.bind("UCS"))
	astar_button.pressed.connect(run_search.bind("A*"))

	current_heuristic = "Manhattan"

	run_search("A*")


# INPUT

func _input(event):

	if event is InputEventKey:

		if event.pressed and !event.echo:

			# Move right

			if event.keycode == KEY_D or event.keycode == KEY_RIGHT:

				move_player(Vector2i(1, 0))


			# Move left

			elif event.keycode == KEY_A or event.keycode == KEY_LEFT:

				move_player(Vector2i(-1, 0))


			# Move down

			elif event.keycode == KEY_S or event.keycode == KEY_DOWN:

				move_player(Vector2i(0, 1))


			# Move up

			elif event.keycode == KEY_W or event.keycode == KEY_UP:

				move_player(Vector2i(0, -1))


			# Manhattan heuristic

			elif event.keycode == KEY_M:

				current_heuristic = "Manhattan"

				if current_algorithm == "A*":

					run_search("A*")


			# Euclidean heuristic

			elif event.keycode == KEY_E:

				current_heuristic = "Euclidean"

				if current_algorithm == "A*":

					run_search("A*")


			# Chebyshev heuristic

			elif event.keycode == KEY_C:

				current_heuristic = "Chebyshev"

				if current_algorithm == "A*":

					run_search("A*")


# NPC MOVEMENT

func _process(delta):

	if game_over:

		return

	if path_index < path.size():

		var target = path[path_index]

		npc_position = npc_position.move_toward(
			Vector2(target),
			npc_speed * delta
		)

		if npc_position.distance_to(Vector2(target)) < 0.01:

			npc_position = Vector2(target)

			path_index += 1

			check_caught()


	if npc_sprite != null:

		npc_sprite.global_position = Vector2(
			npc_position.x * CELL_SIZE + 18,
			npc_position.y * CELL_SIZE + 18
		)


	queue_redraw()


# DRAW

func _draw():

	# DRAW EXPANDED NODES

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


	# DRAW FINAL PATH

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


	# GAME RESULT

	if game_over:

		var result_text = "YOU WIN!"

		if !win:

			result_text = "GAME OVER!"

		draw_string(
			ThemeDB.fallback_font,
			Vector2(450, 300),
			result_text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			40,
			Color.WHITE
		)

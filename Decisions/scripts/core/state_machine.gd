class_name StateMachine
extends Node
## Minimal finite state machine.
##
## States are [State] nodes. They can be children of this node in the scene
## tree, or added at runtime with [method add_state]. Exactly one state is
## active; the machine forwards process / physics / input callbacks to it.
##
## [codeblock]
## var sm := StateMachine.new()
## add_child(sm)
## sm.add_state(&"Idle", IdleState.new())
## sm.add_state(&"Walk", WalkState.new())
## sm.start(&"Idle")
## sm.transition_to(&"Walk")
## [/codeblock]

signal state_changed(previous: StringName, current: StringName)

## Name of the state to enter automatically in [method _ready] (optional).
@export var initial_state: StringName = &""

var current_state: State
var current_state_name: StringName = &""
var _states: Dictionary = {}  # StringName -> State


func _ready() -> void:
	# Pick up states that were added as children in the editor.
	for child in get_children():
		if child is State:
			_register(child.name, child)
	if initial_state != &"" and current_state == null:
		start(initial_state)


## Registers a state under [param state_name]. The state becomes a child of the
## machine so it participates in the scene tree (timers, tweens, etc. work).
func add_state(state_name: StringName, state: State) -> void:
	state.name = String(state_name)
	add_child(state)
	_register(state_name, state)


func _register(state_name: StringName, state: State) -> void:
	_states[state_name] = state
	state.machine = self
	state.owner_node = get_parent()
	if not state.transition_requested.is_connected(transition_to):
		state.transition_requested.connect(transition_to)


## Enters the first state without calling exit on anything.
func start(state_name: StringName, data: Dictionary = {}) -> void:
	assert(_states.has(state_name), "Unknown state: %s" % state_name)
	current_state = _states[state_name]
	current_state_name = state_name
	current_state.enter(data)
	state_changed.emit(&"", state_name)


## Leaves the current state and enters [param state_name].
func transition_to(state_name: StringName, data: Dictionary = {}) -> void:
	assert(_states.has(state_name), "Unknown state: %s" % state_name)
	var previous := current_state_name
	if current_state:
		current_state.exit()
	current_state = _states[state_name]
	current_state_name = state_name
	current_state.enter(data)
	state_changed.emit(previous, state_name)


func has_state(state_name: StringName) -> bool:
	return _states.has(state_name)


func is_in(state_name: StringName) -> bool:
	return current_state_name == state_name


func _process(delta: float) -> void:
	if current_state:
		current_state.update(delta)


func _physics_process(delta: float) -> void:
	if current_state:
		current_state.physics_update(delta)


func _unhandled_input(event: InputEvent) -> void:
	if current_state:
		current_state.handle_input(event)

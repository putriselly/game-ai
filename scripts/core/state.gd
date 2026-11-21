class_name State
extends Node
## Base class for a single state inside a [StateMachine].
##
## Subclass this (or use an inner class) and override the hooks you need.
## [member owner_node] is the node the state machine belongs to (the character,
## the battle controller, ...), so states can reach the thing they control.

## Emitted by a state when it wants the machine to switch to another state.
signal transition_requested(target_state: StringName, data: Dictionary)

## The node that "owns" the state machine (set automatically by [StateMachine]).
var owner_node: Node
## The machine this state belongs to (set automatically by [StateMachine]).
var machine: StateMachine


## Called once when the machine switches into this state.
func enter(_data: Dictionary = {}) -> void:
	pass


## Called once when the machine leaves this state.
func exit() -> void:
	pass


## Called every frame while this state is active.
func update(_delta: float) -> void:
	pass


## Called every physics frame while this state is active.
func physics_update(_delta: float) -> void:
	pass


## Called with unhandled input while this state is active.
func handle_input(_event: InputEvent) -> void:
	pass


## Convenience wrapper so a state can request a transition with one line.
func go_to(target_state: StringName, data: Dictionary = {}) -> void:
	transition_requested.emit(target_state, data)

class_name RunStateMachine
extends RefCounted

signal state_changed(previous: State, current: State)

enum State { START, MAP, NODE, BATTLE, REWARD, VICTORY, DEFEAT }

const ALLOWED_TRANSITIONS := {
	State.START: [State.MAP, State.DEFEAT],
	State.MAP: [State.NODE, State.DEFEAT],
	State.NODE: [State.BATTLE, State.MAP, State.VICTORY, State.DEFEAT],
	State.BATTLE: [State.REWARD, State.VICTORY, State.DEFEAT],
	State.REWARD: [State.MAP, State.VICTORY],
	State.VICTORY: [State.START],
	State.DEFEAT: [State.START],
}

var current_state := State.START


func transition(next_state: State) -> bool:
	if next_state not in ALLOWED_TRANSITIONS.get(current_state, []):
		return false
	var previous := current_state
	current_state = next_state
	state_changed.emit(previous, current_state)
	return true


func reset() -> void:
	var previous := current_state
	current_state = State.START
	if previous != current_state:
		state_changed.emit(previous, current_state)

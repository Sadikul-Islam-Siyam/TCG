class_name TCGInputController
extends Node
## Phase 8 (T8.1-T8.5): Input State Machine & Safety Guard.
## States: IDLE -> CARD_SELECTED / SKILL_SELECTED -> TARGETING -> PAYING -> CONFIRMING -> LOCKED.
## Enforces 0.1s click-spam debounce and gates gameplay inputs while busy,
## while ALWAYS keeping read-only inspect clicks responsive (T1.2, T8.4).

enum State {
	IDLE,
	CARD_SELECTED,
	SKILL_SELECTED,
	TARGETING,
	PAYING,
	CONFIRMING,
	LOCKED,
}

signal state_changed(old_state: int, new_state: int)

var state: int = State.IDLE
var _pre_lock_state: int = State.IDLE
var debounce_ms: int = 100
var _last_action_ms: int = -1000
var selected_hand_index: int = -1
var selected_skill_index: int = -1
var pending_target_kind: String = ""
var allow_inspect_while_busy: bool = true


func reset() -> void:
	selected_hand_index = -1
	selected_skill_index = -1
	pending_target_kind = ""
	_pre_lock_state = State.IDLE
	_set_state(State.IDLE)


func set_busy_locked(busy: bool) -> void:
	if busy:
		if state != State.LOCKED:
			_pre_lock_state = state
			_set_state(State.LOCKED)
	else:
		if state == State.LOCKED:
			var restored := _pre_lock_state
			if restored == State.LOCKED:
				restored = State.IDLE
			_set_state(restored)


func is_locked() -> bool:
	return state == State.LOCKED


func can_accept_gameplay_input(now_ms: int = -1) -> bool:
	if state == State.LOCKED:
		return false
	var t: int = now_ms if now_ms >= 0 else int(Time.get_ticks_msec())
	return (t - _last_action_ms) >= debounce_ms


func record_action(now_ms: int = -1) -> void:
	_last_action_ms = now_ms if now_ms >= 0 else int(Time.get_ticks_msec())


func can_accept_inspect_input() -> bool:
	return true if allow_inspect_while_busy else (state != State.LOCKED)


func enter_idle() -> void:
	selected_hand_index = -1
	selected_skill_index = -1
	pending_target_kind = ""
	_set_state(State.IDLE)


func enter_card_selected(hand_idx: int) -> void:
	selected_hand_index = hand_idx
	selected_skill_index = -1
	pending_target_kind = ""
	_set_state(State.CARD_SELECTED)


func enter_skill_selected(skill_idx: int) -> void:
	selected_skill_index = skill_idx
	selected_hand_index = -1
	pending_target_kind = ""
	_set_state(State.SKILL_SELECTED)


func enter_targeting(kind: String) -> void:
	pending_target_kind = kind
	_set_state(State.TARGETING)


func enter_paying() -> void:
	_set_state(State.PAYING)


func enter_confirming() -> void:
	_set_state(State.CONFIRMING)


func cancel_one_step() -> String:
	## Step-by-step right-click / Escape unwind (T8.5). Returns action identifier taken.
	if state == State.LOCKED:
		return "none"
	if state == State.CONFIRMING:
		_set_state(State.IDLE)
		return "close_confirm"
	if state == State.PAYING:
		_set_state(State.IDLE)
		return "close_paying"
	if state == State.TARGETING:
		pending_target_kind = ""
		if selected_hand_index >= 0:
			_set_state(State.CARD_SELECTED)
		elif selected_skill_index >= 0:
			_set_state(State.SKILL_SELECTED)
		else:
			_set_state(State.IDLE)
		return "cancel_targeting"
	if state == State.CARD_SELECTED or state == State.SKILL_SELECTED:
		enter_idle()
		return "deselect"
	return "none"


func _set_state(next_state: int) -> void:
	if state == next_state:
		return
	var prev := state
	state = next_state
	state_changed.emit(prev, next_state)


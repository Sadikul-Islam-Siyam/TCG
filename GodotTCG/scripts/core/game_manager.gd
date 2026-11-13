extends Node
## GameManager (Autoload Singleton)
## Coordinates match creation, state access, TurnManager & RoundManager integration,
## and emits Godot signals so UI scenes and AI controllers stay cleanly decoupled.

signal match_started(state: TCGGameState)
signal state_updated(state: TCGGameState)
signal phase_changed(new_phase: String, round_number: int)
signal round_started(round_number: int)
signal turn_changed(actor_player: int)
signal action_applied(action: TCGGameState.ActionData, events: Array)
signal match_ended(winner: int)

var current_state: TCGGameState = null
var current_mode: String = "hvai"               # "hvai" | "hvh" | "aivai"
var ai_levels: PackedStringArray = ["normal", "normal"]


func create_new_state(
	chars_0: Array,
	deck_0: Array,
	chars_1: Array,
	deck_1: Array,
	seed_val: int = -1
) -> TCGGameState:
	## Initializes a new `TCGGameState` matching `engine/rules.py:new_game`.
	var rng := RandomNumberGenerator.new()
	if seed_val >= 0:
		rng.seed = seed_val
	else:
		rng.randomize()

	var s := TCGGameState.new(rng)
	s.players = [
		TCGPlayerSystem.PlayerState.new(chars_0, deck_0),
		TCGPlayerSystem.PlayerState.new(chars_1, deck_1),
	]
	for p_idx in range(2):
		TCGRoundManager.shuffle_strings(s.rng, s.players[p_idx].deck)
		TCGRoundManager.draw_cards(s, p_idx, CardDataSystem.HAND_START)

	s.first_player = s.rng.randi_range(0, 1)
	s.current = s.first_player
	return s


func start_new_match(
	chars_0: Array,
	deck_0: Array,
	chars_1: Array,
	deck_1: Array,
	seed_val: int = -1,
	mode: String = "hvai",
	levels: Array = ["normal", "normal"]
) -> TCGGameState:
	current_mode = mode
	ai_levels = PackedStringArray([str(levels[0]), str(levels[1] if levels.size() > 1 else levels[0])])
	current_state = create_new_state(chars_0, deck_0, chars_1, deck_1, seed_val)
	match_started.emit(current_state)
	state_updated.emit(current_state)
	turn_changed.emit(get_current_actor())
	return current_state


func get_current_actor() -> int:
	if current_state == null:
		return -1
	return TCGTurnManager.get_actor(current_state)


func notify_action_complete(action: TCGGameState.ActionData, prev_phase: String, prev_round: int) -> void:
	if current_state == null:
		return
	action_applied.emit(action, current_state.events)
	if current_state.round_number != prev_round:
		round_started.emit(current_state.round_number)
	if current_state.phase != prev_phase:
		phase_changed.emit(current_state.phase, current_state.round_number)
	state_updated.emit(current_state)
	if current_state.is_game_over():
		match_ended.emit(current_state.winner)
	else:
		turn_changed.emit(get_current_actor())


class_name TCGTurnManager
extends RefCounted
## TurnManager
## Translates turn-ordering, actor resolution, turn-passing, and forced-switch
## logic from Python `engine/rules.py` (`actor`, `_end_turn`, `_end_round`, `_check_win`).


static func get_actor(state: TCGGameState) -> int:
	## Returns the player index (0 or 1) who must act next, or -1 if none (`engine/rules.py:actor`).
	if state == null or state.phase == "over":
		return -1
	if not state.pending.is_empty():
		return state.pending[0]

	var order: Array[int] = [state.first_player, 1 - state.first_player]
	if state.phase == "setup":
		for p in order:
			if not state.players[p].mull_done:
				return p
		for p in order:
			if state.players[p].chosen < 0:
				return p
	elif state.phase == "roll":
		for p in order:
			if not state.players[p].roll_done:
				return p
	elif state.phase == "action":
		return state.current

	return -1


static func end_turn(state: TCGGameState, player_idx: int) -> void:
	## Passes the turn to the opponent if they have not yet ended the round (`engine/rules.py:_end_turn`).
	if state.phase == "action" and not state.players[1 - player_idx].ended:
		state.current = 1 - player_idx


static func declare_end_round(state: TCGGameState, player_idx: int) -> bool:
	## Marks `player_idx` as having ended the round.
	## Returns `true` if both players have now ended the round (triggering End Phase).
	var p := state.players[player_idx]
	p.ended = true
	if state.first_ender < 0:
		state.first_ender = player_idx
	state.add_event("end_round", {"player": player_idx})
	state.add_game_event(GameEvent.make(GameEvent.Type.ROUND_ENDED, player_idx, -1, "declare", "", state.round_number))
	if state.players[1 - player_idx].ended:
		return true
	state.current = 1 - player_idx
	return false


static func check_win(state: TCGGameState) -> bool:
	## Checks if either or both players have lost all characters (`engine/rules.py:_check_win`).
	if state.players.size() < 2:
		return false
	var lost_0: bool = state.players[0].get_alive_indices().is_empty()
	var lost_1: bool = state.players[1].get_alive_indices().is_empty()
	if lost_0 and lost_1:
		state.winner = -1
	elif lost_0:
		state.winner = 1
	elif lost_1:
		state.winner = 0

	if state.winner != -2:
		state.phase = "over"
		state.pending.clear()
		return true
	return false


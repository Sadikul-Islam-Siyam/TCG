class_name TCGMatchLifecycle
extends RefCounted
## MatchLifecycle
## Connects the Stage 3 rules engine (`TCGRulesEngine`), `TCGTurnManager`, `TCGRoundManager`,
## and `GameManager` into a complete, UI-independent match lifecycle controller and simulator.
## Mirrors Python `engine/rules.py` lifecycle and `simulate.py:play_game`.

const VALID_PHASES: PackedStringArray = ["setup", "roll", "action", "end", "over"]

var state: TCGGameState = null
var controllers: Array = ["human", "human"]  # Each element is "human" or an AI object with `.choose(state)`


func start_match(
	chars_0: Array,
	deck_0: Array,
	chars_1: Array,
	deck_1: Array,
	seed_val: int = -1,
	p_controllers: Array = ["human", "human"]
) -> TCGGameState:
	controllers = p_controllers.duplicate()
	state = TCGRulesEngine.new_game(chars_0, deck_0, chars_1, deck_1, seed_val)
	GameManager.current_state = state
	GameManager.match_started.emit(state)
	GameManager.state_updated.emit(state)
	GameManager.turn_changed.emit(get_actor())
	return state


func get_actor() -> int:
	return TCGRulesEngine.actor(state)


func get_legal_actions() -> Array[TCGGameState.ActionData]:
	if state == null:
		return []
	return TCGRulesEngine.legal_actions(state)


func is_game_over() -> bool:
	return state == null or state.phase == "over" or state.winner != -2


func submit_action(action: TCGGameState.ActionData) -> Dictionary:
	## Validates and applies `action` via `TCGRulesEngine.apply_action()`,
	## emitting `GameManager` lifecycle signals when valid.
	## Returns `{"ok": bool, "error": String, "events": Array[Dictionary], "phase": String, "round": int, "actor": int, "winner": int}`.
	if state == null:
		return {"ok": false, "error": "match not started", "events": [], "phase": "", "round": 0, "actor": -1, "winner": -2}

	var prev_phase: String = state.phase
	var prev_round: int = state.round_number

	TCGRulesEngine.apply_action(state, action)
	if not TCGRulesEngine.last_error.is_empty():
		return {
			"ok": false,
			"error": TCGRulesEngine.last_error,
			"events": [],
			"phase": state.phase,
			"round": state.round_number,
			"actor": get_actor(),
			"winner": state.winner,
		}

	GameManager.notify_action_complete(action, prev_phase, prev_round)
	return {
		"ok": true,
		"error": "",
		"events": state.events.duplicate(),
		"phase": state.phase,
		"round": state.round_number,
		"actor": get_actor(),
		"winner": state.winner,
	}


func step_ai_if_ready() -> Dictionary:
	## If the current actor is controlled by an AI object, queries `.choose(state)` and submits it.
	if is_game_over():
		return {"ok": false, "error": "game is over"}
	var act_p: int = get_actor()
	if act_p < 0 or act_p >= controllers.size():
		return {"ok": false, "error": "no active player"}
	var ctrl = controllers[act_p]
	if typeof(ctrl) == TYPE_STRING and str(ctrl) == "human":
		return {"ok": false, "error": "waiting for human player"}
	var chosen_action: TCGGameState.ActionData = ctrl.choose(state)
	return submit_action(chosen_action)


static func play_simulated_game(seed_val: int, max_steps: int = 3000) -> Dictionary:
	## Exact port of Python `simulate.py:play_game(seed, max_steps=3000)`.
	## Picks two preset decks deterministically from `seed_val`, runs two `TCGRandomAI` bots,
	## and returns `{"state": TCGGameState, "steps": int, "reactions": Dictionary}`.
	CardDataSystem.load_all_content()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val

	var presets := TCGDeckSystem.preset_decks()
	var preset_names: Array = presets.keys()
	preset_names.sort()
	var pick_0: Array = presets[preset_names[rng.randi_range(0, preset_names.size() - 1)]]
	var pick_1: Array = presets[preset_names[rng.randi_range(0, preset_names.size() - 1)]]

	var s := TCGRulesEngine.new_game(pick_0[0], pick_0[1], pick_1[0], pick_1[1], seed_val)
	var bots: Array[TCGRandomAI] = [
		TCGRandomAI.new(seed_val * 2),
		TCGRandomAI.new(seed_val * 2 + 1),
	]
	var reactions: Dictionary = {}
	var steps: int = 0

	while s.phase != "over" and steps < max_steps and s.round_number <= 40:
		var act_p: int = TCGRulesEngine.actor(s)
		var a := bots[act_p].choose(s)
		TCGRulesEngine.apply_action(s, a)
		if not TCGRulesEngine.last_error.is_empty():
			break
		for ev in s.events:
			if ev["kind"] == "damage" and ev.get("reaction") != null:
				var r_name: String = str(ev["reaction"])
				reactions[r_name] = int(reactions.get(r_name, 0)) + 1
		steps += 1

	return {"state": s, "steps": steps, "reactions": reactions}


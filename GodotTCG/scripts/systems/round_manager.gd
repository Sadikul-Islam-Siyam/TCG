class_name TCGRoundManager
extends RefCounted
## RoundManager
## Translates round lifecycle transitions from Python `engine/rules.py`:
## `_begin_round`, `_start_action`, `_end_phase`, `_tick`, `_reset_round`, `_draw`, and `roll`.


static func roll_dice(rng: RandomNumberGenerator, count: int) -> Array[String]:
	## Weighted dice roll matching Python `engine/dice.py:roll`.
	var out: Array[String] = []
	var faces := CardDataSystem.DICE_FACES
	var weights := CardDataSystem.DICE_WEIGHTS
	for _i in range(count):
		var r: float = rng.randf()
		var accum: float = 0.0
		var picked: String = faces[faces.size() - 1]
		for j in range(faces.size()):
			accum += weights[j]
			if r <= accum:
				picked = faces[j]
				break
		out.append(picked)
	return out


static func shuffle_strings(rng: RandomNumberGenerator, arr: Array[String]) -> void:
	## Deterministic Fisher-Yates shuffle using `state.rng`.
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: String = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


static func draw_cards(state: TCGGameState, player_idx: int, count: int) -> void:
	## Draws up to `count` cards from top of deck (end of array, matching Python `deck.pop()`).
	var p := state.players[player_idx]
	for _i in range(count):
		if not p.deck.is_empty():
			var before_hand: int = p.hand.size()
			var c: String = p.deck.pop_back()
			if p.hand.size() < CardDataSystem.MAX_HAND:
				p.hand.append(c)
				state.add_game_event(GameEvent.make(
					GameEvent.Type.CARD_DRAWN,
					player_idx,
					-1,
					c,
					"",
					1,
					before_hand,
					p.hand.size(),
					"draw"
				))
			else:
				state.add_game_event(GameEvent.make(
					GameEvent.Type.CARD_DISCARDED,
					player_idx,
					-1,
					c,
					"",
					1,
					before_hand,
					p.hand.size(),
					"burn"
				))


static func begin_round(state: TCGGameState, is_first: bool = false) -> void:
	## Starts a new round and enters the Roll Phase (`engine/rules.py:_begin_round`).
	if not is_first:
		state.add_game_event(GameEvent.make(GameEvent.Type.ROUND_ENDED, state.first_player, -1, "", "", state.round_number))
		state.round_number += 1
		if state.first_ender >= 0:
			state.first_player = state.first_ender
	state.first_ender = -1
	state.phase = "roll"
	state.add_log("-- Round %d --" % state.round_number)
	state.add_event("round", {"number": state.round_number})
	state.add_game_event(GameEvent.make(
		GameEvent.Type.ROUND_STARTED,
		state.first_player,
		-1,
		"",
		"",
		state.round_number,
		null,
		state.first_player
	))
	for pi in range(state.players.size()):
		var p := state.players[pi]
		var before_dice := p.dice.duplicate()
		p.dice = roll_dice(state.rng, CardDataSystem.DICE_PER_ROUND)
		p.rerolls = 1
		p.roll_done = false
		p.ended = false
		state.add_game_event(GameEvent.make(
			GameEvent.Type.DICE_ROLLED,
			pi,
			-1,
			"",
			"",
			p.dice.size(),
			before_dice,
			p.dice.duplicate()
		))


static func start_action_phase(state: TCGGameState, ctx_factory: Callable = Callable()) -> void:
	## Transitions from Roll Phase to Action Phase and fires support `action_start` hooks.
	state.phase = "action"
	state.current = state.first_player
	state.add_event("phase", {"name": "action", "first": state.first_player})
	state.add_game_event(GameEvent.make(GameEvent.Type.PHASE_CHANGED, state.first_player, -1, "action", "", state.round_number))

	var order: Array[int] = [state.first_player, 1 - state.first_player]
	for p_idx in order:
		var p := state.players[p_idx]
		for u in p.supports.duplicate():
			var cd = CardDataSystem.get_card_def(u.name)
			if cd != null and cd.action_start.is_valid():
				if ctx_factory.is_valid():
					cd.action_start.call(ctx_factory.call(state, p_idx))
				if u.usages > 0:
					u.usages -= 1
		var kept: Array[TCGPlayerSystem.UnitInstance] = []
		for u in p.supports:
			if u.usages < 0 or u.usages > 0:
				kept.append(u)
		p.supports = kept


static func tick_statuses(statuses: Array[TCGPlayerSystem.StatusInstance]) -> Array[TCGPlayerSystem.StatusInstance]:
	## Decrements round-based status durations (`engine/rules.py:_tick`).
	var out: Array[TCGPlayerSystem.StatusInstance] = []
	for st in statuses:
		if st.duration >= 0:
			st.duration -= 1
			if st.duration <= 0:
				continue
		out.append(st)
	return out


static func reset_round_usages(statuses: Array[TCGPlayerSystem.StatusInstance]) -> void:
	## Restores `per_round` status usages during End Phase (`engine/rules.py:_reset_round`).
	for st in statuses:
		var df = CardDataSystem.get_status_def(st.name)
		if df != null and df.per_round > 0:
			st.usages = df.per_round


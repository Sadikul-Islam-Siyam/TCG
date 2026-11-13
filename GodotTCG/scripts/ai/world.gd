class_name TCGWorld
extends RefCounted
## Imperfect-Information Determinization & Candidate Move Ordering
## Exact port of Python `genius_tcg/ai/world.py`.
## Neither `determinize` nor `candidates` inspects the opponent's true hand or either deck order.


static func determinize(state: TCGGameState, me: int, rng: RandomNumberGenerator) -> TCGGameState:
	## Clones `state` and replaces all hidden cards (opponent hand + both decks)
	## with a plausible random sample drawn from legal cards for the opponent's characters.
	var w: TCGGameState = state.clone()
	var w_rng := RandomNumberGenerator.new()
	w_rng.seed = rng.randi()
	w.rng = w_rng

	var foe: TCGPlayerSystem.PlayerState = w.players[1 - me]
	var foe_chars: Array[String] = []
	for c in foe.characters:
		foe_chars.append(c.name)

	var pool: Array[String] = []
	for n in TCGDeckSystem.allowed_cards(foe_chars):
		pool.append(n)
		pool.append(n)
	TCGRoundManager.shuffle_strings(rng, pool)

	var n_hand: int = foe.hand.size()
	var n_deck: int = foe.deck.size()

	var new_foe_hand: Array[String] = []
	for i in range(mini(n_hand, pool.size())):
		new_foe_hand.append(pool[i])
	foe.hand = new_foe_hand

	var rest: Array[String] = []
	for i in range(n_hand, pool.size()):
		rest.append(pool[i])
	var doubled: Array[String] = []
	doubled.append_array(rest)
	doubled.append_array(rest)

	var new_foe_deck: Array[String] = []
	for i in range(mini(n_deck, doubled.size())):
		new_foe_deck.append(doubled[i])
	foe.deck = new_foe_deck

	# We know which cards remain in our own deck, but not their order.
	var mine: Array[String] = w.players[me].deck.duplicate()
	mine.sort()
	TCGRoundManager.shuffle_strings(rng, mine)
	w.players[me].deck = mine
	return w


static func candidates(
	s: TCGGameState,
	me: int,
	allow_tune: bool = false
) -> Array[TCGGameState.ActionData]:
	## Legal actions pruned and ordered so search visits the most promising moves first.
	var a: int = TCGRulesEngine.actor(s)
	var acts: Array[TCGGameState.ActionData] = TCGRulesEngine.legal_actions(s)
	var filtered: Array[TCGGameState.ActionData] = []
	for x in acts:
		if not allow_tune and x.type == "tune":
			continue
		if a != me and x.type == "card":
			# Don't branch on sampled foe cards.
			continue
		filtered.append(x)

	if filtered.is_empty():
		return acts

	var rank: Dictionary = {
		"skill": 0,
		"card": 1,
		"switch": 2,
		"choose_active": 0,
		"end_round": 3,
	}

	var decorated: Array = []
	for idx in range(filtered.size()):
		var x: TCGGameState.ActionData = filtered[idx]
		var r: int = int(rank.get(x.type, 4))
		var sk_pri: int = -x.index if x.type == "skill" else 0
		decorated.append([r, sk_pri, idx, x])

	decorated.sort_custom(func(lhs: Array, rhs: Array) -> bool:
		if int(lhs[0]) != int(rhs[0]):
			return int(lhs[0]) < int(rhs[0])
		if int(lhs[1]) != int(rhs[1]):
			return int(lhs[1]) < int(rhs[1])
		return int(lhs[2]) < int(rhs[2])
	)

	var out: Array[TCGGameState.ActionData] = []
	for item in decorated:
		out.append(item[3])
	return out


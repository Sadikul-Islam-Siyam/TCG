class_name TCGPlanner
extends RefCounted
## A* Lethal Planner
## Exact port of Python `genius_tcg/ai/planner.py`.
## Informed A* search (`f(n) = g(n) + h(n)`) over actions inside ONE turn to find
## the cheapest way to defeat the opponent's active character (or win the game).

const BEST_DAMAGE_PER_DIE: float = 2.5   # Optimistic: keeps h(n) admissible


static func _spent(s0: TCGGameState, s: TCGGameState, me: int) -> float:
	var p0: TCGPlayerSystem.PlayerState = s0.players[me]
	var p: TCGPlayerSystem.PlayerState = s.players[me]
	return float(p0.dice.size() - p.dice.size()) + 0.3 * float(p0.hand.size() - p.hand.size())


static func _goal(s: TCGGameState, me: int, target: int) -> bool:
	var c: TCGPlayerSystem.CharacterInstance = s.players[1 - me].characters[target]
	return c.defeated or s.winner == me


static func _h(s: TCGGameState, me: int, target: int) -> float:
	var c: TCGPlayerSystem.CharacterInstance = s.players[1 - me].characters[target]
	if c.defeated:
		return 0.0
	return maxf(0.0, float(c.hp) / BEST_DAMAGE_PER_DIE - 0.5)


static func _state_key(c: TCGGameState, me: int) -> String:
	var sorted_dice: Array[String] = c.players[me].dice.duplicate()
	sorted_dice.sort()
	var sorted_hand: Array[String] = c.players[me].hand.duplicate()
	sorted_hand.sort()
	var foe_hps: Array[int] = []
	for ch in c.players[1 - me].characters:
		foe_hps.append(ch.hp)
	return "%s|%s|%s|%d" % [str(sorted_dice), str(sorted_hand), str(foe_hps), c.players[me].active]


static func _pop_min(open_list: Array) -> Array:
	var best_idx: int = 0
	var best_item: Array = open_list[0]
	for i in range(1, open_list.size()):
		var item: Array = open_list[i]
		if float(item[0]) < float(best_item[0]):
			best_idx = i
			best_item = item
		elif float(item[0]) == float(best_item[0]):
			if float(item[1]) < float(best_item[1]):
				best_idx = i
				best_item = item
			elif float(item[1]) == float(best_item[1]) and int(item[2]) < int(best_item[2]):
				best_idx = i
				best_item = item
	open_list.remove_at(best_idx)
	return best_item


static func plan_lethal(state: TCGGameState, me: int, max_expansions: int = 250) -> Variant:
	## Returns an `Array[TCGGameState.ActionData]` of the cheapest lethal line, or `null`.
	## `state` should already be determinized; our own deck is emptied so the plan never
	## counts on unseen draws.
	var foe: TCGPlayerSystem.PlayerState = state.players[1 - me]
	if foe.active < 0 or TCGRulesEngine.actor(state) != me or state.phase != "action":
		return null

	var target: int = foe.active
	var s0: TCGGameState = state.clone()
	var empty_deck: Array[String] = []
	s0.players[me].deck = empty_deck

	var tie: int = 0
	var init_path: Array[TCGGameState.ActionData] = []
	var open_list: Array = [[_h(s0, me, target), 0.0, tie, s0, init_path]]
	tie += 1

	var seen: Dictionary = {}
	var expansions: int = 0

	while not open_list.is_empty() and expansions < max_expansions:
		var node: Array = _pop_min(open_list)
		var s: TCGGameState = node[3]
		var path: Array[TCGGameState.ActionData] = node[4]

		if not path.is_empty() and _goal(s, me, target):
			return path
		if TCGRulesEngine.actor(s) != me or s.phase != "action" or s.winner != -2:
			# Turn ended without lethal: dead end
			continue

		expansions += 1
		for act in TCGWorld.candidates(s, me):
			if act.type == "end_round":
				continue
			var c: TCGGameState = s.clone(false, true)
			TCGRulesEngine.apply_action(c, act)
			var key: String = _state_key(c, me)
			if seen.has(key):
				continue
			seen[key] = true
			var g2: float = _spent(s0, c, me) + 0.05 * float(path.size())
			var next_path: Array[TCGGameState.ActionData] = path.duplicate()
			next_path.append(act)
			open_list.append([g2 + _h(c, me, target), g2, tie, c, next_path])
			tie += 1

	return null


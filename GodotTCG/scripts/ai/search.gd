class_name TCGSearcher
extends RefCounted
## Depth-Limited Alpha-Beta Search with Iterative Deepening
## Exact port of Python `genius_tcg/ai/search.py`.

var me: int = 0
var prof: Dictionary = {}
var deadline_usec: int = 0
var max_nodes: int = 6000
var nodes: int = 0
var aborted: bool = false


func _init(
	p_me: int,
	p_prof: Dictionary = {},
	time_limit: float = 0.5,
	p_max_nodes: int = 6000
) -> void:
	me = p_me
	prof = p_prof
	deadline_usec = Time.get_ticks_usec() + int(time_limit * 1_000_000.0)
	max_nodes = p_max_nodes
	nodes = 0
	aborted = false


func leaf(s: TCGGameState) -> bool:
	return s.winner != -2 or (s.phase != "action" and s.pending.is_empty())


static func cost(act: TCGGameState.ActionData) -> int:
	## Depth is counted in turn-ending moves: fast actions (cards, tuning, choosing a replacement)
	## are free, which avoids the horizon effect of preferring lines that stop before the opponent can reply.
	return 1 if act.type in ["skill", "switch", "end_round"] else 0


func end_penalty(s: TCGGameState, act: TCGGameState.ActionData) -> float:
	## Ending the round with dice left over wastes them; scaled by how rich we are.
	if act.type != "end_round":
		return 0.0
	var tempo_val: float = float(prof.get("tempo", 0.5))
	var waste: float = 0.014 * float(s.players[act.player].dice.size()) * (1.5 - tempo_val)
	var bonus: float = 0.03 if s.first_ender < 0 else 0.0   # Ending first = go first next round
	var sign_f: float = 1.0 if act.player == me else -1.0
	return (bonus - waste) * sign_f


func value(s: TCGGameState, depth: int, alpha: float, beta: float) -> float:
	nodes += 1
	if depth <= 0 or leaf(s):
		return TCGEvaluate.evaluate(s, me, prof)
	if nodes > max_nodes or Time.get_ticks_usec() > deadline_usec:
		aborted = true
		return TCGEvaluate.evaluate(s, me, prof)

	var maximizing: bool = (TCGRulesEngine.actor(s) == me)
	var best: float = -INF if maximizing else INF

	for act in TCGWorld.candidates(s, me):
		var c: TCGGameState = s.clone(false, true)
		TCGRulesEngine.apply_action(c, act)
		var v: float = value(c, depth - cost(act), alpha, beta) + end_penalty(s, act)
		if maximizing:
			best = maxf(best, v)
			alpha = maxf(alpha, v)
		else:
			best = minf(best, v)
			beta = minf(beta, v)
		if beta <= alpha or aborted:
			break
	return best


func root_scores(s: TCGGameState, depth: int = 4) -> Dictionary:
	## Value of every candidate move at a fixed depth (used to shortlist moves for MCTS).
	## Returns `{act.key(): {"score": float, "action": TCGGameState.ActionData}}`.
	var out: Dictionary = {}
	for act in TCGWorld.candidates(s, me):
		var c: TCGGameState = s.clone(false, true)
		TCGRulesEngine.apply_action(c, act)
		var v: float = value(c, depth - cost(act), -INF, INF) + end_penalty(s, act)
		out[act.key()] = {"score": v, "action": act}
	return out


func best_move(s: TCGGameState, max_depth: int = 4) -> TCGGameState.ActionData:
	var acts: Array[TCGGameState.ActionData] = TCGWorld.candidates(s, me)
	var best_act: TCGGameState.ActionData = acts[0]

	for depth in range(1, max_depth + 1):
		var scored: Array = []
		var alpha: float = -INF
		aborted = false
		for idx in range(acts.size()):
			var act: TCGGameState.ActionData = acts[idx]
			var c: TCGGameState = s.clone(false, true)
			TCGRulesEngine.apply_action(c, act)
			var v: float = value(c, depth - cost(act), alpha, INF) + end_penalty(s, act)
			scored.append([v, idx, act])
			alpha = maxf(alpha, v)
			if aborted:
				break

		if aborted and depth > 1:
			# Keep the last fully searched depth
			break

		var best_item: Array = scored[0]
		for item in scored:
			if float(item[0]) > float(best_item[0]):
				best_item = item
		best_act = best_item[2]

		var scored_sorted: Array = scored.duplicate()
		scored_sorted.sort_custom(func(lhs: Array, rhs: Array) -> bool:
			if float(lhs[0]) != float(rhs[0]):
				return float(lhs[0]) > float(rhs[0])
			return int(lhs[1]) < int(rhs[1])
		)

		var seen_keys: Dictionary = {}
		var reordered: Array[TCGGameState.ActionData] = []
		for item in scored_sorted:
			var a: TCGGameState.ActionData = item[2]
			seen_keys[a.key()] = true
			reordered.append(a)
		for a in acts:
			if not seen_keys.has(a.key()):
				reordered.append(a)
		acts = reordered

		if aborted:
			break

	return best_act


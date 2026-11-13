class_name TCGMcts
extends RefCounted
## Single-Observer Information-Set MCTS (UCT) with Determinization
## Exact port of Python `genius_tcg/ai/mcts.py`.
## Every iteration samples a fresh possible world (opponent hand / deck orders),
## walks the tree, plays a short biased rollout, and scores the end position.

const C: float = 0.9
const SCALE: float = 1.4


class MctsNode extends RefCounted:
	var action: TCGGameState.ActionData = null
	var children: Dictionary = {}     # key: String -> MctsNode
	var n: int = 0
	var w: float = 0.0
	var actor: int = -1

	func _init(p_action: TCGGameState.ActionData = null) -> void:
		action = p_action
		children = {}
		n = 0
		w = 0.0
		actor = -1


static func reward(s: TCGGameState, me: int, prof: Dictionary) -> float:
	if s.winner != -2:
		if s.winner == -1:
			return 0.5
		return 1.0 if s.winner == me else 0.0
	return 1.0 / (1.0 + exp(-TCGEvaluate.evaluate(s, me, prof) / SCALE))


static func _weighted_choice(
	rng: RandomNumberGenerator,
	acts: Array[TCGGameState.ActionData],
	weights: Array[int]
) -> TCGGameState.ActionData:
	var total: int = 0
	for w in weights:
		total += w
	if total <= 0:
		return acts[0]
	var pick: float = rng.randf() * float(total)
	var acc: float = 0.0
	for i in range(acts.size()):
		acc += float(weights[i])
		if pick < acc:
			return acts[i]
	return acts[acts.size() - 1]


static func rollout(
	s: TCGGameState,
	me: int,
	rng: RandomNumberGenerator,
	depth: int,
	prof: Dictionary
) -> float:
	for _step in range(depth):
		if s.winner != -2 or (s.phase != "action" and s.pending.is_empty()):
			break
		var acts: Array[TCGGameState.ActionData] = TCGWorld.candidates(s, me)
		var skills: Array[TCGGameState.ActionData] = []
		for a in acts:
			if a.type == "skill":
				skills.append(a)
		var act: TCGGameState.ActionData = null
		if not skills.is_empty() and rng.randf() < 0.8:
			if rng.randf() < 0.6:
				var best_sk: TCGGameState.ActionData = skills[0]
				for sk_a in skills:
					if sk_a.index > best_sk.index:
						best_sk = sk_a
				act = best_sk
			else:
				act = skills[rng.randi_range(0, skills.size() - 1)]
		else:
			var weights: Array[int] = []
			for a in acts:
				weights.append(1 if a.type == "end_round" else 2)
			act = _weighted_choice(rng, acts, weights)
		TCGRulesEngine.apply_action(s, act)
	return reward(s, me, prof)


static func best_action(
	state: TCGGameState,
	me: int,
	prof: Dictionary,
	rng: RandomNumberGenerator,
	time_limit: float = 1.0,
	iters: int = 400,
	rollout_depth: int = 10,
	shortlist_keys: Dictionary = {}
) -> TCGGameState.ActionData:
	var root := MctsNode.new()
	var deadline_usec: int = Time.get_ticks_usec() + int(time_limit * 1_000_000.0)

	for it in range(iters):
		if it >= 20 and Time.get_ticks_usec() > deadline_usec:
			break
		var s: TCGGameState = TCGWorld.determinize(state, me, rng)
		var s_rng := RandomNumberGenerator.new()
		s_rng.seed = rng.randi()
		s.rng = s_rng

		var node: MctsNode = root
		var path: Array[MctsNode] = [root]
		while s.winner == -2 and (s.phase == "action" or not s.pending.is_empty()):
			var acts: Array[TCGGameState.ActionData] = TCGWorld.candidates(s, me)
			if not shortlist_keys.is_empty() and node == root:
				var sl_acts: Array[TCGGameState.ActionData] = []
				for a in acts:
					if shortlist_keys.has(a.key()):
						sl_acts.append(a)
				if not sl_acts.is_empty():
					acts = sl_acts

			node.actor = TCGRulesEngine.actor(s)
			var untried: Array[TCGGameState.ActionData] = []
			for a in acts:
				if not node.children.has(a.key()):
					untried.append(a)

			if not untried.is_empty():
				var act: TCGGameState.ActionData = untried[0] if node.n < 3 else untried[rng.randi_range(0, untried.size() - 1)]
				var child := MctsNode.new(act)
				node.children[act.key()] = child
				TCGRulesEngine.apply_action(s, act)
				path.append(child)
				break

			var best: MctsNode = null
			var best_v: float = -1e9
			for a in acts:
				var ch: MctsNode = node.children[a.key()]
				var q: float = (ch.w / float(ch.n)) if ch.n > 0 else 0.5
				if node.actor != me:
					q = 1.0 - q
				var v: float = q + C * sqrt(log(float(node.n + 1)) / float(ch.n + 1))
				if v > best_v:
					best = ch
					best_v = v
			TCGRulesEngine.apply_action(s, best.action)
			path.append(best)
			node = best

		var r: float = rollout(s, me, rng, rollout_depth, prof)
		for p_node in path:
			p_node.n += 1
			p_node.w += r

	if root.children.is_empty():
		return TCGWorld.candidates(state, me)[0]

	var legal_map: Dictionary = {}
	for a in TCGWorld.candidates(state, me):
		legal_map[a.key()] = a

	var pool: Array[MctsNode] = []
	for k in root.children.keys():
		if legal_map.has(k):
			pool.append(root.children[k])
	if pool.is_empty():
		for k in root.children.keys():
			pool.append(root.children[k])

	var best_child: MctsNode = pool[0]
	for ch in pool:
		if ch.n > best_child.n:
			best_child = ch
	if legal_map.has(best_child.action.key()):
		return legal_map[best_child.action.key()]
	return best_child.action


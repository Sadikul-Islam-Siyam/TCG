class_name TCGAIPlayer
extends RefCounted
## Multi-Tier AI Opponent, Factory, & CSP Deck Generator
## Exact port of Python `genius_tcg/ai/players.py`, `factory.py`, and `deckgen.py`.
##
## Levels:
## - `easy`:   Fuzzy logic (style + evaluation weights) with a one-move look-ahead and epsilon noise
## - `normal`: A* lethal planner + iterative-deepening Alpha-Beta search (fuzzy-weighted evaluation)
## - `hard`:   A* lethal planner + Alpha-Beta shortlisting + Information-Set MCTS over sampled worlds
##
## CSP (`TCGDicePay.smart_pay`) selects which dice to pay with.
## `choose(state)` never modifies the `state` it is given.

const LEVELS: Dictionary = {
	"easy": {"eps": 0.18},
	"normal": {"depth": 4, "time": 0.6, "nodes": 6000},
	"hard": {"time": 1.6, "iters": 700},
}

var level: String = "normal"
var cfg: Dictionary = {}
var rng: RandomNumberGenerator
var time_scale: float = 1.0


func _init(
	p_level: String = "normal",
	seed_val: int = -1,
	p_time_scale: float = 1.0,
	p_iters: int = -1
) -> void:
	assert(LEVELS.has(p_level), "unknown AI level: %s" % p_level)
	level = p_level
	cfg = LEVELS[p_level].duplicate()
	rng = RandomNumberGenerator.new()
	if seed_val >= 0:
		rng.seed = seed_val
	else:
		rng.randomize()
	time_scale = p_time_scale
	if p_iters > 0:
		cfg["iters"] = p_iters


static func make(
	p_level: String = "normal",
	seed_val: int = -1,
	p_time_scale: float = 1.0,
	p_iters: int = -1
) -> TCGAIPlayer:
	## Mirrors Python `genius_tcg/ai/factory.py:make(level, seed)`.
	return TCGAIPlayer.new(p_level, seed_val, p_time_scale, p_iters)


static func random_deck(p_rng: RandomNumberGenerator = null) -> Array:
	## Mirrors Python `genius_tcg/ai/deckgen.py:random_deck(rng)`.
	## Picks 3 random characters from `ROSTER`, perturbs preset priorities by `uniform(-2.5, 2.5)`,
	## and fills the 30-card deck via CSP (`TCGDeckSystem.autofill`).
	## Returns `[chars: Array[String], cards: Array[String]]`.
	CardDataSystem.load_all_content()
	var local_rng: RandomNumberGenerator = p_rng
	if local_rng == null:
		local_rng = RandomNumberGenerator.new()
		local_rng.randomize()

	var roster: Array[String] = []
	for c in CardDataSystem.roster:
		roster.append(str(c))
	TCGRoundManager.shuffle_strings(local_rng, roster)
	var chars: Array[String] = [roster[0], roster[1], roster[2]]

	var base_pr: Dictionary = CardDataSystem.get_card_priorities()
	var pr: Dictionary = {}
	var sorted_keys: Array = base_pr.keys()
	sorted_keys.sort()
	for k in sorted_keys:
		pr[k] = float(base_pr[k]) + local_rng.randf_range(-2.5, 2.5)

	var cards: Array[String] = TCGDeckSystem.autofill(chars, [], pr)
	return [chars, cards]


# ------------------------------------------------------------------------------
# Public Entry Point (`choose(state) -> TCGGameState.ActionData`)
# ------------------------------------------------------------------------------
func choose(state: TCGGameState) -> TCGGameState.ActionData:
	var me: int = TCGRulesEngine.actor(state)
	var acts: Array[TCGGameState.ActionData] = TCGRulesEngine.legal_actions(state)
	if acts.size() == 1:
		return acts[0]
	if not state.pending.is_empty():
		return _best_by_eval(state, me, acts, level == "easy")
	if state.phase == "setup":
		return _setup(state, me, acts)
	if state.phase == "roll":
		for a in acts:
			if a.type == "reroll":
				return a
		return acts[0]
	return _act(state, me, acts)


# ------------------------------------------------------------------------------
# Setup / Roll / Pending
# ------------------------------------------------------------------------------
func _setup(
	s: TCGGameState,
	me: int,
	acts: Array[TCGGameState.ActionData]
) -> TCGGameState.ActionData:
	var p: TCGPlayerSystem.PlayerState = s.players[me]
	if acts[0].type == "mulligan":
		var swap: Array[int] = []
		for i in range(p.hand.size()):
			var n: String = p.hand[i]
			var cd: CardDataSystem.CardData = CardDataSystem.get_card_def(n)
			if cd == null:
				continue
			var total_cost: int = cd.cost.n + cd.cost.unaligned
			var prev_count: int = 0
			for j in range(i):
				if p.hand[j] == n:
					prev_count += 1
			if total_cost >= 4 or (prev_count >= 1 and cd.kind in ["weapon", "artifact"]):
				swap.append(i)
		if swap.size() > 3:
			swap = swap.slice(0, 3)
		return TCGGameState.ActionData.new("mulligan", me, -1, -1, [], swap)

	# Starting character: quick burst (low max energy) and a reaction partner on the team
	var best_act: TCGGameState.ActionData = acts[0]
	var best_score: float = -1e9
	for a in acts:
		var d: CardDataSystem.CharData = p.characters[a.index].get_defn()
		var friends: int = 0
		for c in p.characters:
			var cd: CardDataSystem.CharData = c.get_defn()
			if cd != null and d != null and cd.element != d.element:
				friends += 1
		var max_en: int = d.max_energy if d != null else 2
		var sc: float = -float(max_en) + 0.3 * float(friends) + rng.randf() * 0.2
		if sc > best_score:
			best_score = sc
			best_act = a
	return best_act


func _best_by_eval(
	s: TCGGameState,
	me: int,
	acts: Array[TCGGameState.ActionData],
	noise: bool = false
) -> TCGGameState.ActionData:
	if noise and rng.randf() < 0.3:
		return acts[rng.randi_range(0, acts.size() - 1)]
	var best: TCGGameState.ActionData = acts[0]
	var best_v: float = -1e9
	for a in acts:
		var c: TCGGameState = s.clone()
		TCGRulesEngine.apply_action(c, a)
		var v: float = TCGEvaluate.evaluate(c, me) + (rng.randf() * 0.05)
		if v > best_v:
			best = a
			best_v = v
	return best


# ------------------------------------------------------------------------------
# Action Phase
# ------------------------------------------------------------------------------
func _act(
	s: TCGGameState,
	me: int,
	_acts: Array[TCGGameState.ActionData]
) -> TCGGameState.ActionData:
	var prof: Dictionary = TCGFuzzy.profile(s, me)
	var tune_act: TCGGameState.ActionData = _tune(s, me)
	if tune_act != null:
		return tune_act

	var world: TCGGameState = TCGWorld.determinize(s, me, rng)
	if level != "easy":
		var plan = TCGPlanner.plan_lethal(world, me)
		if plan != null and not plan.is_empty():
			return _pay(s, me, plan[0])

	var act: TCGGameState.ActionData = null
	if level == "easy":
		act = _easy(world, me, prof)
	elif level == "normal":
		var sr := TCGSearcher.new(
			me,
			prof,
			float(cfg["time"]) * time_scale,
			int(cfg["nodes"])
		)
		act = sr.best_move(world, int(cfg["depth"]))
	else:
		var t: float = float(cfg["time"]) * time_scale
		var ab: Dictionary = TCGSearcher.new(me, prof, t * 0.35, 9000).root_scores(world, 4)
		var ab_items: Array = []
		for k in ab.keys():
			ab_items.append([float(ab[k]["score"]), str(k)])
		ab_items.sort_custom(func(lhs: Array, rhs: Array) -> bool:
			return float(lhs[0]) > float(rhs[0])
		)
		var top_keys: Dictionary = {}
		for i in range(mini(4, ab_items.size())):
			top_keys[str(ab_items[i][1])] = true
		act = TCGMcts.best_action(
			s,
			me,
			prof,
			rng,
			t * 0.65,
			int(cfg["iters"]),
			10,
			top_keys
		)
	return _pay(s, me, act)


func _easy(
	world: TCGGameState,
	me: int,
	prof: Dictionary
) -> TCGGameState.ActionData:
	var before: float = TCGEvaluate.evaluate(world, me, prof)
	var scored: Array = []
	for a in TCGWorld.candidates(world, me):
		var c: TCGGameState = world.clone()
		TCGRulesEngine.apply_action(c, a)
		var v: float = TCGEvaluate.evaluate(c, me, prof) - before
		if a.type == "skill" and a.index == 2:
			v += 0.15 * float(prof["burst"])
		elif a.type == "card":
			v += 0.04 * float(prof["cards"])
		elif a.type == "end_round":
			v += 0.25 * float(prof["tempo"]) - 0.012 * float(world.players[me].dice.size())
		elif a.type == "switch":
			v += 0.1 * float(prof["defence"]) - 0.05 * float(prof["aggression"])
		scored.append([v, rng.randf(), a])

	scored.sort_custom(func(lhs: Array, rhs: Array) -> bool:
		if float(lhs[0]) != float(rhs[0]):
			return float(lhs[0]) > float(rhs[0])
		return float(lhs[1]) > float(rhs[1])
	)

	if rng.randf() < float(cfg["eps"]) and scored.size() > 1:
		var k_top: int = mini(3, scored.size())
		return scored[rng.randi_range(0, k_top - 1)][2]
	return scored[0][2]


func _tune(s: TCGGameState, me: int) -> TCGGameState.ActionData:
	## If a skill is exactly one die short of its element, convert a die using the least useful card.
	var p: TCGPlayerSystem.PlayerState = s.players[me]
	var ch: TCGPlayerSystem.CharacterInstance = p.get_active_char()
	if ch == null or p.hand.is_empty() or TCGRulesEngine.stunned(ch):
		return null
	var acts: Array[TCGGameState.ActionData] = TCGRulesEngine.legal_actions(s)
	for a in acts:
		if a.type == "skill" and a.index >= 1:
			return null

	var defn: CardDataSystem.CharData = ch.get_defn()
	if defn == null:
		return null
	var el: String = defn.element
	for i in range(defn.skills.size()):
		var sk: CardDataSystem.SkillData = defn.skills[i]
		if i == 0 or (sk.cost.energy > 0 and ch.energy < sk.cost.energy):
			continue
		var have: int = 0
		for d in p.dice:
			if d == el or d == CardDataSystem.OMNI:
				have += 1
		if sk.cost.n - have == 1 and p.dice.size() >= sk.cost.n + sk.cost.unaligned:
			for j in range(p.dice.size()):
				var d: String = p.dice[j]
				if d != el and d != CardDataSystem.OMNI:
					return TCGGameState.ActionData.new("tune", me, _least_useful(p), j)
	return null


func _least_useful(p: TCGPlayerSystem.PlayerState) -> int:
	var pri: Dictionary = {
		"event": 1,
		"support": 2,
		"weapon": 3,
		"artifact": 3,
		"talent": 4,
	}
	var best_idx: int = 0
	var best_pri: int = 999
	var best_neg_cost: int = 999
	for i in range(p.hand.size()):
		var cd: CardDataSystem.CardData = CardDataSystem.get_card_def(p.hand[i])
		if cd == null:
			continue
		var p_val: int = int(pri.get(cd.kind, 1))
		var neg_cost: int = -(cd.cost.n + cd.cost.unaligned)
		if p_val < best_pri or (p_val == best_pri and neg_cost < best_neg_cost):
			best_pri = p_val
			best_neg_cost = neg_cost
			best_idx = i
	return best_idx


# ------------------------------------------------------------------------------
# Payment (CSP)
# ------------------------------------------------------------------------------
func _pay(
	s: TCGGameState,
	me: int,
	act: TCGGameState.ActionData
) -> TCGGameState.ActionData:
	var p: TCGPlayerSystem.PlayerState = s.players[me]
	var cost: CardDataSystem.CostData = null
	if act.type == "skill":
		var ch: TCGPlayerSystem.CharacterInstance = p.get_active_char()
		if ch != null and ch.get_defn() != null:
			cost = ch.get_defn().skills[act.index].cost
	elif act.type == "card":
		var cd: CardDataSystem.CardData = CardDataSystem.get_card_def(p.hand[act.index])
		if cd != null:
			cost = cd.cost
	elif act.type == "switch":
		cost = TCGRulesEngine.switch_cost(p)
	else:
		return act

	if cost == null:
		return act

	var keep_set: Dictionary = {}
	for c in p.characters:
		if not c.defeated and c.get_defn() != null:
			keep_set[c.get_defn().element] = true
	var keep: Array = keep_set.keys()

	var pay = TCGDicePay.smart_pay(p.dice, cost, keep)
	if pay != null:
		return act.with_dice(pay)
	return act

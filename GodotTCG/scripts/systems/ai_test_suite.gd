class_name TCGAITestSuite
extends RefCounted
## AITestSuite
## Verifies Fuzzy Logic, Heuristic Evaluation, CSP AllDiff & Smart Dice Payment
## (including Same-Element costs), Hidden-Information Determinization & No-Cheating,
## State Immutability, A* Lethal Planner, Iterative-Deepening Alpha-Beta Search,
## Information-Set MCTS, Full AI-vs-Random / AI-vs-AI Matches, and CSP Random Decks.


static func _start(
	c0: Array = ["Zuko", "Azula", "Aang"],
	c1: Array = ["Katara", "Toph", "Iroh"],
	seed_val: int = 1
) -> TCGGameState:
	var s := TCGRulesEngine.new_game(c0, CardDataSystem.starter_deck(c0), c1, CardDataSystem.starter_deck(c1), seed_val)
	while s.phase != "action":
		var acts := TCGRulesEngine.legal_actions(s)
		TCGRulesEngine.apply_action(s, acts[0])
	s.first_player = 0
	s.current = 0
	for p in s.players:
		var d: Array[String] = []
		for _i in range(12):
			d.append(CardDataSystem.OMNI)
		p.dice = d
	return s


static func _give(s: TCGGameState, p: int, cards: Array) -> void:
	var h: Array[String] = []
	for c in cards:
		h.append(str(c))
	s.players[p].hand = h


static func _make_rng(seed_val: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_val
	return r


static func _play(a, b, seed_val: int, max_steps: int = 3000) -> TCGGameState:
	var presets: Dictionary = TCGDeckSystem.preset_decks()
	var names: Array = presets.keys()
	names.sort()
	var rng := _make_rng(seed_val)
	var pair0: Array = presets[names[rng.randi_range(0, names.size() - 1)]]
	var pair1: Array = presets[names[rng.randi_range(0, names.size() - 1)]]
	var s := TCGRulesEngine.new_game(pair0[0], pair0[1], pair1[0], pair1[1], seed_val)
	var bots: Array = [a, b]
	var n: int = 0
	while s.phase != "over" and s.round_number <= 30 and n < max_steps:
		var act_p: int = TCGRulesEngine.actor(s)
		var act: TCGGameState.ActionData = bots[act_p].choose(s)
		TCGRulesEngine.apply_action(s, act)
		assert(TCGRulesEngine.last_error.is_empty(), "Illegal AI move: %s (%s)" % [str(act), TCGRulesEngine.last_error])
		n += 1
	return s


static func run_all_tests() -> Dictionary:
	CardDataSystem.load_all_content()
	var results: Array[Dictionary] = []

	var tests: Array[Array] = [
		["test_membership_shapes", Callable(TCGAITestSuite, "_test_membership_shapes")],
		["test_profile_reacts_to_health", Callable(TCGAITestSuite, "_test_profile_reacts_to_health")],
		["test_evaluation_is_zero_sum_and_sees_damage", Callable(TCGAITestSuite, "_test_evaluation_zero_sum_and_damage")],
		["test_alldiff_constraint", Callable(TCGAITestSuite, "_test_alldiff_constraint")],
		["test_smart_pay_spends_cheap_dice_and_keeps_omni", Callable(TCGAITestSuite, "_test_smart_pay_keeps_omni")],
		["test_smart_pay_always_valid", Callable(TCGAITestSuite, "_test_smart_pay_always_valid")],
		["test_determinize_resamples_hidden_cards_only", Callable(TCGAITestSuite, "_test_determinize_hidden_cards")],
		["test_ai_never_looks_at_opponents_hidden_cards", Callable(TCGAITestSuite, "_test_ai_never_peeks_hidden_cards")],
		["test_choose_leaves_state_untouched", Callable(TCGAITestSuite, "_test_choose_leaves_state_untouched")],
		["test_planner_finds_one_move_lethal", Callable(TCGAITestSuite, "_test_planner_one_move_lethal")],
		["test_planner_chains_equipment_then_attack", Callable(TCGAITestSuite, "_test_planner_chains_equipment_then_attack")],
		["test_planner_returns_none_when_no_lethal", Callable(TCGAITestSuite, "_test_planner_returns_none")],
		["test_alphabeta_takes_the_kill", Callable(TCGAITestSuite, "_test_alphabeta_takes_kill")],
		["test_mcts_is_deterministic_and_legal", Callable(TCGAITestSuite, "_test_mcts_deterministic_and_legal")],
		["test_mcts_prefers_a_winning_hit", Callable(TCGAITestSuite, "_test_mcts_prefers_winning_hit")],
		["test_each_level_finishes_games_against_random", Callable(TCGAITestSuite, "_test_each_level_finishes_against_random")],
		["test_levels_play_each_other", Callable(TCGAITestSuite, "_test_levels_play_each_other")],
		["test_ai_builds_legal_decks", Callable(TCGAITestSuite, "_test_ai_builds_legal_decks")],
	]

	var passed: int = 0
	for t in tests:
		var t_name: String = t[0]
		var fn: Callable = t[1]
		fn.call()
		passed += 1
		results.append({"name": t_name, "passed": true})

	return {
		"passed": passed,
		"total": tests.size(),
		"all_passed": passed == tests.size(),
		"results": results,
	}


# ------------------------------------------------------------------------------
# 1. Fuzzy Logic & Heuristic Evaluation
# ------------------------------------------------------------------------------
static func _test_membership_shapes() -> void:
	assert(is_equal_approx(TCGFuzzy.low(0.0), 1.0) and is_equal_approx(TCGFuzzy.low(0.9), 0.0))
	assert(is_equal_approx(TCGFuzzy.med(0.5), 1.0) and is_equal_approx(TCGFuzzy.med(0.1), 0.0))
	assert(is_equal_approx(TCGFuzzy.high(1.0), 1.0) and is_equal_approx(TCGFuzzy.high(0.2), 0.0))
	assert(TCGFuzzy.low(0.4) > 0.0 and TCGFuzzy.low(0.4) < 1.0)
	assert(TCGFuzzy.high(0.6) > 0.0 and TCGFuzzy.high(0.6) < 1.0)


static func _test_profile_reacts_to_health() -> void:
	var healthy := _start()
	var hurt := _start()
	for c in hurt.players[0].characters:
		c.hp = 2
	var ph: Dictionary = TCGFuzzy.profile(healthy, 0)
	var pu: Dictionary = TCGFuzzy.profile(hurt, 0)
	assert(float(pu["defence"]) > float(ph["defence"]) and float(pu["aggression"]) < float(ph["aggression"]))
	for k in ["aggression", "defence", "burst", "tempo", "cards"]:
		var v: float = float(ph[k])
		assert(v >= 0.0 and v <= 1.0)


static func _test_evaluation_zero_sum_and_damage() -> void:
	var s := _start()
	var base: float = TCGEvaluate.evaluate(s, 0)
	assert(absf(base + TCGEvaluate.evaluate(s, 1)) < 1e-6)
	s.players[1].characters[0].hp = 3
	assert(TCGEvaluate.evaluate(s, 0) > base)
	s.players[1].characters[0].hp = 0
	s.players[1].characters[0].defeated = true
	assert(TCGEvaluate.evaluate(s, 0) > base + 0.5)


# ------------------------------------------------------------------------------
# 2. CSP & Smart Dice Payment
# ------------------------------------------------------------------------------
static func _test_alldiff_constraint() -> void:
	var sol = TCGCspSolver.solve(
		{"a": [1, 2], "b": [1, 2], "c": [1, 2, 3]},
		[TCGCspSolver.AllDiff.new(["a", "b", "c"])]
	)
	assert(sol != null)
	var uniq: Dictionary = {}
	for k in sol.keys():
		uniq[sol[k]] = true
	assert(uniq.size() == 3)
	var impossible = TCGCspSolver.solve(
		{"a": [1], "b": [1]},
		[TCGCspSolver.AllDiff.new(["a", "b"])]
	)
	assert(impossible == null)


static func _test_smart_pay_keeps_omni() -> void:
	var dice: Array = [
		CardDataSystem.OMNI,
		CardDataSystem.PYRO,
		CardDataSystem.PYRO,
		CardDataSystem.HYDRO,
		CardDataSystem.PYRO,
		CardDataSystem.ANEMO,
	]
	var pay = TCGDicePay.smart_pay(dice, CardDataSystem.CostData.new(CardDataSystem.PYRO, 3), [CardDataSystem.PYRO])
	assert(pay != null and pay.size() == 3)
	for i in pay:
		assert(dice[i] == CardDataSystem.PYRO)

	var pay2 = TCGDicePay.smart_pay(dice, CardDataSystem.CostData.new(CardDataSystem.PYRO, 1, 2), [CardDataSystem.PYRO])
	assert(pay2 != null and pay2.size() == 3)
	for i in pay2:
		assert(dice[i] != CardDataSystem.OMNI)

	# "2 dice of the same type" cost should prefer non-Omni matching pair (two Geo or two Pyro) over Omni
	var same_dice: Array = [CardDataSystem.OMNI, CardDataSystem.GEO, CardDataSystem.GEO, CardDataSystem.PYRO]
	var pay_same = TCGDicePay.smart_pay(same_dice, CardDataSystem.CostData.new("", 2, 0), [CardDataSystem.PYRO])
	assert(pay_same != null and pay_same.size() == 2)
	for i in pay_same:
		assert(same_dice[i] == CardDataSystem.GEO)

	assert(TCGDicePay.smart_pay([CardDataSystem.PYRO], CardDataSystem.CostData.new(CardDataSystem.PYRO, 2)) == null)
	var pay_free = TCGDicePay.smart_pay(dice, CardDataSystem.CostData.new())
	assert(pay_free != null and pay_free.is_empty())


static func _test_smart_pay_always_valid() -> void:
	var rng := _make_rng(4)
	for _it in range(300):
		var n_dice: int = rng.randi_range(3, 12)
		var dice: Array[String] = TCGDiceSystem.roll(rng, n_dice)
		var use_same: bool = (_it % 5 == 0)
		var el: String = "" if use_same else CardDataSystem.ELEMENTS[rng.randi_range(0, CardDataSystem.ELEMENTS.size() - 1)]
		var cost := CardDataSystem.CostData.new(el, rng.randi_range(0, 4), rng.randi_range(0, 3))
		var keep: Array = [] if el.is_empty() else [el]
		var pay = TCGDicePay.smart_pay(dice, cost, keep)
		var greedy = TCGDiceSystem.auto_pay(dice, cost)
		assert((pay == null) == (greedy == null))
		if pay != null:
			assert(TCGDiceSystem.payment_ok(dice, cost, pay))


# ------------------------------------------------------------------------------
# 3. Hidden Information & State Immutability
# ------------------------------------------------------------------------------
static func _test_determinize_hidden_cards() -> void:
	var s := _start()
	var hand: Array[String] = s.players[1].hand.duplicate()
	var deckk: Array[String] = s.players[1].deck.duplicate()
	var mine: Array[String] = s.players[0].deck.duplicate()
	var w := TCGWorld.determinize(s, 0, _make_rng(5))
	assert(s.players[1].hand == hand and s.players[1].deck == deckk and s.players[0].deck == mine)
	assert(w.players[1].hand.size() == hand.size() and w.players[1].deck.size() == deckk.size())

	var sorted_w_mine: Array[String] = w.players[0].deck.duplicate()
	sorted_w_mine.sort()
	var sorted_mine: Array[String] = mine.duplicate()
	sorted_mine.sort()
	assert(sorted_w_mine == sorted_mine)
	assert(w.players[0].hand == s.players[0].hand and w.players[0].dice == s.players[0].dice)

	var foe_chars: Array[String] = []
	for c in s.players[1].characters:
		foe_chars.append(c.name)
	var allowed: Array[String] = TCGDeckSystem.allowed_cards(foe_chars)
	for card_name in w.players[1].hand:
		assert(allowed.has(card_name))


static func _test_ai_never_peeks_hidden_cards() -> void:
	for level in ["easy", "normal", "hard"]:
		var s := _start()
		var t := s.clone()

		var uniq_hand: Dictionary = {}
		for h_card in t.players[1].hand:
			uniq_hand[h_card] = true
		if uniq_hand.size() > 1:
			var rev_hand: Array[String] = t.players[1].hand.duplicate()
			rev_hand.reverse()
			t.players[1].hand = rev_hand
		else:
			var filler_hand: Array[String] = []
			for _i in range(t.players[1].hand.size()):
				filler_hand.append("Draw Cards")
			t.players[1].hand = filler_hand

		var rev_foe_deck: Array[String] = t.players[1].deck.duplicate()
		rev_foe_deck.reverse()
		t.players[1].deck = rev_foe_deck

		var rev_own_deck: Array[String] = t.players[0].deck.duplicate()
		rev_own_deck.reverse()
		t.players[0].deck = rev_own_deck

		var a: TCGGameState.ActionData = TCGAIPlayer.new(level, 11, 50.0, 60).choose(s)
		var b: TCGGameState.ActionData = TCGAIPlayer.new(level, 11, 50.0, 60).choose(t)
		assert(a.equals(b), "AI level '%s' depended on hidden card order: %s vs %s" % [level, str(a), str(b)])


static func _test_choose_leaves_state_untouched() -> void:
	for level in ["easy", "normal", "hard"]:
		var s := _start()
		var before_desc: String = TCGRulesEngine.describe(s)
		var before_h0: Array[String] = s.players[0].hand.duplicate()
		var before_h1: Array[String] = s.players[1].hand.duplicate()
		var before_d0: Array[String] = s.players[0].deck.duplicate()
		var before_rng_state: int = s.rng.state
		var before_dice0: Array[String] = s.players[0].dice.duplicate()
		var before_dice1: Array[String] = s.players[1].dice.duplicate()

		TCGAIPlayer.new(level, 3, 0.3, 40).choose(s)

		assert(TCGRulesEngine.describe(s) == before_desc)
		assert(s.players[0].hand == before_h0)
		assert(s.players[1].hand == before_h1)
		assert(s.players[0].deck == before_d0)
		assert(s.rng.state == before_rng_state)
		assert(s.players[0].dice == before_dice0)
		assert(s.players[1].dice == before_dice1)


# ------------------------------------------------------------------------------
# 4. A* Lethal Planner
# ------------------------------------------------------------------------------
static func _test_planner_one_move_lethal() -> void:
	var s := _start()
	_give(s, 0, ["Draw Cards", "Party Healing"])
	s.players[1].characters[0].hp = 3   # Zuko's Fire Whip deals 3 Pyro DMG
	var plan = TCGPlanner.plan_lethal(TCGWorld.determinize(s, 0, _make_rng(1)), 0)
	assert(plan != null and plan.size() == 1 and plan[0].type == "skill")
	TCGRulesEngine.apply_action(s, plan[0])
	assert(s.players[1].characters[0].defeated)


static func _test_planner_chains_equipment_then_attack() -> void:
	var s := _start()
	s.players[1].characters[0].hp = 4   # Zuko's Fire Whip does 3: needs Zuko's Dual Broadswords (+1 DMG)
	_give(s, 0, ["Zuko's Dual Broadswords", "Draw Cards"])
	var plan = TCGPlanner.plan_lethal(TCGWorld.determinize(s, 0, _make_rng(1)), 0)
	assert(plan != null and plan.size() == 2)
	assert(plan[0].type == "card" and plan[1].type == "skill")
	for a in plan:
		TCGRulesEngine.apply_action(s, a)
	assert(s.players[1].characters[0].defeated)


static func _test_planner_returns_none() -> void:
	var s := _start()
	assert(TCGPlanner.plan_lethal(TCGWorld.determinize(s, 0, _make_rng(1)), 0) == null)


# ------------------------------------------------------------------------------
# 5. Alpha-Beta & MCTS Searchers
# ------------------------------------------------------------------------------
static func _test_alphabeta_takes_kill() -> void:
	var s := _start()
	s.players[1].characters[0].hp = 3
	for _step in range(6):   # Free cards may come first, then the kill
		var w := TCGWorld.determinize(s, 0, _make_rng(2))
		var act := TCGSearcher.new(0, {}, 5.0).best_move(w, 3)
		TCGRulesEngine.apply_action(s, act)
		if s.players[1].characters[0].defeated or TCGRulesEngine.actor(s) != 0:
			break
	assert(s.players[1].characters[0].defeated)


static func _test_mcts_deterministic_and_legal() -> void:
	var s := _start()
	var r1 := TCGMcts.best_action(s, 0, TCGFuzzy.profile(s, 0), _make_rng(9), 60.0, 80)
	var r2 := TCGMcts.best_action(s, 0, TCGFuzzy.profile(s, 0), _make_rng(9), 60.0, 80)
	assert(r1.equals(r2))
	var is_legal: bool = false
	for a in TCGRulesEngine.legal_actions(s):
		if a.equals(r1):
			is_legal = true
			break
	assert(is_legal)


static func _test_mcts_prefers_winning_hit() -> void:
	var s := _start()
	for i in [1, 2]:
		s.players[1].characters[i].hp = 0
		s.players[1].characters[i].defeated = true
	s.players[1].characters[0].hp = 3
	var act := TCGMcts.best_action(s, 0, TCGFuzzy.profile(s, 0), _make_rng(3), 60.0, 150)
	assert(act.type == "skill")


# ------------------------------------------------------------------------------
# 6. Whole Games & Deck Generator
# ------------------------------------------------------------------------------
static func _test_each_level_finishes_against_random() -> void:
	for level in ["easy", "normal", "hard"]:
		for seed_val in [1, 2]:
			var s := _play(
				TCGAIPlayer.new(level, seed_val, 0.2, 40),
				TCGRandomAI.new(seed_val),
				seed_val
			)
			assert(s.phase == "over" or s.round_number > 30)


static func _test_levels_play_each_other() -> void:
	var s := _play(
		TCGAIPlayer.new("normal", 1, 0.2),
		TCGAIPlayer.new("hard", 2, 0.2, 40),
		5
	)
	assert(s.phase == "over" or s.round_number > 30)


static func _test_ai_builds_legal_decks() -> void:
	var rng := _make_rng(1)
	for _i in range(25):
		var pair: Array = TCGAIPlayer.random_deck(rng)
		var chars: Array = pair[0]
		var cards: Array = pair[1]
		var errs: Array[String] = TCGDeckSystem.validate_deck(chars, cards)
		assert(errs.is_empty(), "AI random_deck produced invalid deck: %s" % str(errs))

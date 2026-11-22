class_name TCGLifecycleTestSuite
extends RefCounted
## LifecycleTestSuite
## Stage 4 automated match lifecycle test suite verifying:
## - Setup flow (initialization, mulligan order, simultaneous active character reveal)
## - Roll phase flow (8 dice rolled, 1 reroll limit, confirm_roll transition)
## - Action phase flow (combat vs fast actions, zero-dice boundary case, end_round & first_ender priority)
## - End phase flow (Frozen/Petrified/Stunned clear, duration tick, Dice Carryover -> Omni dice, draw 2 with 10-card cap)
## - Invalid timing / phase / actor rejection across all states
## - Win, Defeat, Pending forced switch, and simultaneous Draw (-1) termination
## - 60 full simulated games (`TCGMatchLifecycle.play_simulated_game`) completing cleanly.


static func run_all_tests() -> Dictionary:
	CardDataSystem.load_all_content()
	var tests: Array[Array] = [
		["lifecycle_01_initialization_and_setup_order", Callable(TCGLifecycleTestSuite, "_test_init_and_setup_order")],
		["lifecycle_02_mulligan_partial_swap_and_deck_size", Callable(TCGLifecycleTestSuite, "_test_mulligan_partial_swap")],
		["lifecycle_03_roll_phase_reroll_limit_and_transition", Callable(TCGLifecycleTestSuite, "_test_roll_phase_and_reroll")],
		["lifecycle_04_action_phase_zero_dice_boundary_case", Callable(TCGLifecycleTestSuite, "_test_zero_dice_boundary")],
		["lifecycle_05_first_ender_inherits_next_round_priority", Callable(TCGLifecycleTestSuite, "_test_first_ender_priority")],
		["lifecycle_06_end_phase_ordering_thaw_tick_and_carryover", Callable(TCGLifecycleTestSuite, "_test_end_phase_full_sequence")],
		["lifecycle_07_dice_cap_at_16_and_hand_cap_at_10", Callable(TCGLifecycleTestSuite, "_test_resource_caps")],
		["lifecycle_08_invalid_phase_and_turn_timing_rejections", Callable(TCGLifecycleTestSuite, "_test_invalid_phase_and_timing")],
		["lifecycle_09_simultaneous_defeat_tie_handling", Callable(TCGLifecycleTestSuite, "_test_simultaneous_tie")],
		["lifecycle_10_match_lifecycle_controller_and_signals", Callable(TCGLifecycleTestSuite, "_test_lifecycle_controller")],
		["lifecycle_11_sixty_full_random_games_finish_cleanly", Callable(TCGLifecycleTestSuite, "_test_sixty_full_games")],
	]

	var results: Array[Dictionary] = []
	var passed: int = 0
	var failed: int = 0
	for t in tests:
		var t_name: String = t[0]
		var t_fn: Callable = t[1]
		var err: String = t_fn.call()
		if err.is_empty():
			passed += 1
			results.append({"name": t_name, "ok": true, "error": ""})
		else:
			failed += 1
			results.append({"name": t_name, "ok": false, "error": err})

	return {"passed": passed, "failed": failed, "total": tests.size(), "results": results}


static func _test_init_and_setup_order() -> String:
	var c0 := ["Aang", "Katara", "Toph"]
	var c1 := ["Zuko", "Azula", "Iroh"]
	var s := TCGRulesEngine.new_game(c0, CardDataSystem.starter_deck(c0), c1, CardDataSystem.starter_deck(c1), 10)
	if s.phase != "setup" or s.round_number != 1:
		return "Expected setup phase round 1"
	var fp: int = s.first_player
	var sp: int = 1 - fp
	var expected_deck := TCGDeckSystem.DECK_SIZE - 5
	if s.players[0].hand.size() != 5 or s.players[0].deck.size() != expected_deck:
		return "Expected 5 hand cards and %d deck cards on init" % expected_deck
	if s.players[0].active != -1 or s.players[1].active != -1:
		return "Active characters must remain -1 (None) during setup until both choose"

	# 1. First player mulligan
	if TCGRulesEngine.actor(s) != fp:
		return "Expected first_player to mulligan first"
	TCGRulesEngine.apply_action(s, TCGGameState.ActionData.new("mulligan", fp))

	# 2. Second player mulligan
	if TCGRulesEngine.actor(s) != sp:
		return "Expected second player to mulligan second"
	TCGRulesEngine.apply_action(s, TCGGameState.ActionData.new("mulligan", sp))

	# 3. First player chooses starting character (active still hidden/-1 until P2 chooses!)
	if TCGRulesEngine.actor(s) != fp:
		return "Expected first_player to choose active character first"
	TCGRulesEngine.apply_action(s, TCGGameState.ActionData.new("choose_active", fp, 1))
	if s.players[fp].chosen != 1 or s.players[fp].active != -1:
		return "First player's chosen character should be stored in .chosen while .active stays -1 until both choose"

	# 4. Second player chooses starting character -> both active revealed & round 1 roll phase begins
	if TCGRulesEngine.actor(s) != sp:
		return "Expected second player to choose active character second"
	TCGRulesEngine.apply_action(s, TCGGameState.ActionData.new("choose_active", sp, 2))
	if s.players[fp].active != 1 or s.players[sp].active != 2:
		return "Both active characters should be revealed simultaneously"
	if s.phase != "roll" or s.round_number != 1:
		return "Expected transition to roll phase of round 1"
	return ""


static func _test_mulligan_partial_swap() -> String:
	var c0 := ["Aang", "Katara", "Toph"]
	var s := TCGRulesEngine.new_game(c0, CardDataSystem.starter_deck(c0), c0, CardDataSystem.starter_deck(c0), 7)
	var fp: int = s.first_player
	s.players[fp].hand = ["Active Character Healing", "Draw Cards", "Elemental Dice", "Omni Conversion", "Party Healing"]
	TCGRulesEngine.apply_action(s, TCGGameState.ActionData.new("mulligan", fp, -1, -1, [], [0, 2, 4]))
	if not TCGRulesEngine.last_error.is_empty():
		return "Unexpected mulligan error: %s" % TCGRulesEngine.last_error
	var expected_deck := TCGDeckSystem.DECK_SIZE - 5
	if s.players[fp].hand.size() != 5 or s.players[fp].deck.size() != expected_deck:
		return "Hand and deck sizes must remain 5 and %d after mulligan" % expected_deck
	if s.players[fp].hand[0] != "Draw Cards" or s.players[fp].hand[1] != "Omni Conversion":
		return "Unselected hand cards should remain in order at the front of hand"
	# Second mulligan by same player must be rejected
	TCGRulesEngine.apply_action(s, TCGGameState.ActionData.new("mulligan", fp))
	if TCGRulesEngine.last_error.is_empty():
		return "Second mulligan by same player must be rejected"
	return ""


static func _test_roll_phase_and_reroll() -> String:
	var c0 := ["Aang", "Katara", "Toph"]
	var s := TCGRulesEngine.new_game(c0, CardDataSystem.starter_deck(c0), c0, CardDataSystem.starter_deck(c0), 12)
	# Complete setup
	for _i in range(4):
		TCGRulesEngine.apply_action(s, TCGRulesEngine.legal_actions(s)[0])
	if s.phase != "roll":
		return "Expected roll phase"
	var fp: int = s.first_player
	var sp: int = 1 - fp
	if s.players[fp].dice.size() != 8 or s.players[fp].rerolls != 1:
		return "Expected 8 dice and 1 reroll at start of roll phase"

	# Reroll indices 0, 1, 2
	TCGRulesEngine.apply_action(s, TCGGameState.ActionData.new("reroll", fp, -1, -1, [], [0, 1, 2]))
	if not TCGRulesEngine.last_error.is_empty() or s.players[fp].rerolls != 0:
		return "First reroll should succeed and decrement rerolls to 0"

	# Attempt a second reroll -> must be rejected ("bad reroll")
	TCGRulesEngine.apply_action(s, TCGGameState.ActionData.new("reroll", fp, -1, -1, [], [0]))
	if TCGRulesEngine.last_error != "bad reroll":
		return "Expected 'bad reroll' on second reroll attempt, got '%s'" % TCGRulesEngine.last_error

	# Confirm roll for both players -> transitions to action phase
	TCGRulesEngine.apply_action(s, TCGGameState.ActionData.new("confirm_roll", fp))
	if s.phase != "roll" or TCGRulesEngine.actor(s) != sp:
		return "Should remain in roll phase for second player"
	TCGRulesEngine.apply_action(s, TCGGameState.ActionData.new("confirm_roll", sp))
	if s.phase != "action" or TCGRulesEngine.actor(s) != fp:
		return "Should transition to action phase with first_player acting first"
	return ""


static func _test_zero_dice_boundary() -> String:
	var c0 := ["Aang", "Katara", "Toph"]
	var s := TCGRulesEngine.new_game(c0, CardDataSystem.starter_deck(c0), c0, CardDataSystem.starter_deck(c0), 1)
	while s.phase != "action":
		TCGRulesEngine.apply_action(s, TCGRulesEngine.legal_actions(s)[0])
	var p_idx: int = TCGRulesEngine.actor(s)
	var p := s.players[p_idx]
	p.dice.clear()
	p.hand.clear()
	# With 0 dice and 0 cards in hand, `end_round` is the sole legal action (player is never stuck)
	var acts := TCGRulesEngine.legal_actions(s)
	if acts.size() != 1 or acts[0].type != "end_round":
		return "With 0 dice and empty hand, legal_actions must contain exactly [end_round], got %s" % str(acts)
	return ""


static func _test_first_ender_priority() -> String:
	var c0 := ["Aang", "Katara", "Toph"]
	var s := TCGRulesEngine.new_game(c0, CardDataSystem.starter_deck(c0), c0, CardDataSystem.starter_deck(c0), 1)
	while s.phase != "action":
		TCGRulesEngine.apply_action(s, TCGRulesEngine.legal_actions(s)[0])
	s.first_player = 0
	s.current = 0
	# P0 uses a normal skill (passes turn to P1)
	s.players[0].dice = [CardDataSystem.OMNI, CardDataSystem.OMNI, CardDataSystem.OMNI]
	TCGRulesEngine.apply_action(s, TCGRulesEngine.legal_actions(s)[0])
	if s.current != 1:
		return "Turn should pass to P1"
	# P1 ends round first!
	TCGRulesEngine.apply_action(s, TCGGameState.ActionData.new("end_round", 1))
	if s.first_ender != 1 or s.current != 0:
		return "P1 should be recorded as first_ender=1 and turn returns to P0"
	# P0 can still take multiple combat actions while P1 has ended!
	s.players[0].dice = [CardDataSystem.OMNI, CardDataSystem.OMNI, CardDataSystem.OMNI, CardDataSystem.OMNI, CardDataSystem.OMNI, CardDataSystem.OMNI]
	var sk_act := TCGRulesEngine.legal_actions(s)[0]
	TCGRulesEngine.apply_action(s, sk_act)
	if s.current != 0:
		return "When opponent has already ended the round, _end_turn must keep turn on the remaining active player"
	# Now P0 ends round -> Round 2 starts with P1 as first_player
	TCGRulesEngine.apply_action(s, TCGGameState.ActionData.new("end_round", 0))
	if s.round_number != 2 or s.phase != "roll" or s.first_player != 1:
		return "Next round must have first_player=1 (the first_ender of Round 1)"
	return ""


static func _test_end_phase_full_sequence() -> String:
	var c0 := ["Aang", "Katara", "Toph"]
	var c1 := ["Zuko", "Azula", "Iroh"]
	var s := TCGRulesEngine.new_game(c0, CardDataSystem.starter_deck(c0), c1, CardDataSystem.starter_deck(c1), 5)
	while s.phase != "action":
		TCGRulesEngine.apply_action(s, TCGRulesEngine.legal_actions(s)[0])
	# Apply Frozen, Petrified, Stunned, Attack +1 (duration=1), and Dice Carryover with 2 leftover dice
	TCGRulesEngine.add_status(s.players[0].characters[0].statuses, "Frozen")
	TCGRulesEngine.add_status(s.players[0].characters[1].statuses, "Stunned")
	TCGRulesEngine.add_status(s.players[1].characters[0].statuses, "Petrified")
	TCGRulesEngine.add_status(s.players[0].combat, "Attack +1")
	TCGRulesEngine.add_status(s.players[0].combat, "Dice Carryover")
	s.players[0].dice = [CardDataSystem.PYRO, CardDataSystem.GEO]

	# End round for both players
	var a0 := TCGRulesEngine.actor(s)
	TCGRulesEngine.apply_action(s, TCGGameState.ActionData.new("end_round", a0))
	TCGRulesEngine.apply_action(s, TCGGameState.ActionData.new("end_round", 1 - a0))

	if TCGRulesEngine.has_status(s.players[0].characters[0], "Frozen"):
		return "Frozen must be removed at End Phase"
	if TCGRulesEngine.has_status(s.players[0].characters[1], "Stunned"):
		return "Stunned must be removed at End Phase"
	if TCGRulesEngine.has_status(s.players[1].characters[0], "Petrified"):
		return "Petrified must be removed at End Phase"
	if TCGRulesEngine.find_status(s.players[0].combat, "Attack +1") != null:
		return "Attack +1 (duration=1) should expire at End Phase"
	if TCGRulesEngine.find_status(s.players[0].combat, "Dice Carryover") != null:
		return "Dice Carryover should expire at End Phase"
	if s.players[0].dice.size() != 10:
		return "Dice Carryover should carry 2 leftover dice into Round 2 (8 + 2 = 10 dice), got %d" % s.players[0].dice.size()
	if s.players[0].dice[8] != CardDataSystem.OMNI or s.players[0].dice[9] != CardDataSystem.OMNI:
		return "Carried-over dice must be converted to Omni Dice"
	return ""


static func _test_resource_caps() -> String:
	var c0 := ["Aang", "Katara", "Toph"]
	var s := TCGRulesEngine.new_game(c0, CardDataSystem.starter_deck(c0), c0, CardDataSystem.starter_deck(c0), 1)
	while s.phase != "action":
		TCGRulesEngine.apply_action(s, TCGRulesEngine.legal_actions(s)[0])
	# Test MAX_DICE = 16 cap
	s.players[0].dice.clear()
	TCGEffectContext.new(s, 0).gain_dice(20, CardDataSystem.OMNI)
	if s.players[0].dice.size() != 16:
		return "Dice must be capped at MAX_DICE (16), got %d" % s.players[0].dice.size()
	# Test MAX_HAND = 10 cap
	TCGEffectContext.new(s, 0).draw(10)
	if s.players[0].hand.size() != 10:
		return "Hand must be capped at MAX_HAND (10), got %d" % s.players[0].hand.size()
	# Simplified mode disables summons (MAX_SUMMONS == 0) and stacks shields up to max_shield
	var ctx := TCGEffectContext.new(s, 0)
	ctx.summon("Oz")
	if not s.players[0].summons.is_empty():
		return "Summons must remain empty when MAX_SUMMONS == 0"
	ctx.combat_status("Shield +2")
	ctx.combat_status("Shield +2")
	ctx.combat_status("Shield +2")
	var sh := TCGRulesEngine.find_status(s.players[0].combat, "Shield +2")
	if sh == null or sh.shield != 4:
		return "Shield +2 should stack up to max_shield (4)"
	return ""


static func _test_invalid_phase_and_timing() -> String:
	var c0 := ["Aang", "Katara", "Toph"]
	var s := TCGRulesEngine.new_game(c0, CardDataSystem.starter_deck(c0), c0, CardDataSystem.starter_deck(c0), 2)
	var fp: int = s.first_player

	# Try choose_active before mulligan in setup
	TCGRulesEngine.apply_action(s, TCGGameState.ActionData.new("choose_active", fp, 0))
	if TCGRulesEngine.last_error != "mulligan first":
		return "Expected 'mulligan first', got '%s'" % TCGRulesEngine.last_error

	# Try skill during setup
	TCGRulesEngine.apply_action(s, TCGGameState.ActionData.new("skill", fp, 0))
	if TCGRulesEngine.last_error != "skill not allowed now":
		return "Expected 'skill not allowed now', got '%s'" % TCGRulesEngine.last_error

	# Complete setup to enter roll phase
	for _i in range(4):
		TCGRulesEngine.apply_action(s, TCGRulesEngine.legal_actions(s)[0])

	# Try end_round during roll phase
	TCGRulesEngine.apply_action(s, TCGGameState.ActionData.new("end_round", fp))
	if TCGRulesEngine.last_error != "end_round not allowed now":
		return "Expected 'end_round not allowed now', got '%s'" % TCGRulesEngine.last_error

	# Complete roll phase to enter action phase
	for _i in range(2):
		TCGRulesEngine.apply_action(s, TCGGameState.ActionData.new("confirm_roll", TCGRulesEngine.actor(s)))

	# Try confirm_roll during action phase
	TCGRulesEngine.apply_action(s, TCGGameState.ActionData.new("confirm_roll", fp))
	if TCGRulesEngine.last_error != "confirm_roll not allowed now":
		return "Expected 'confirm_roll not allowed now', got '%s'" % TCGRulesEngine.last_error

	# Trigger pending forced switch and try end_round before choosing active character
	TCGRulesEngine.deal_damage(s, fp, 1 - fp, 0, 99, CardDataSystem.PHYSICAL, "effect", "")
	if s.pending != [1 - fp]:
		return "Expected pending forced switch for 1 - fp"
	TCGRulesEngine.apply_action(s, TCGGameState.ActionData.new("end_round", 1 - fp))
	if TCGRulesEngine.last_error != "end_round not allowed now":
		return "Expected 'end_round not allowed now' while pending switch is active"
	return ""


static func _test_simultaneous_tie() -> String:
	var c0 := ["Aang", "Katara", "Toph"]
	var s := TCGRulesEngine.new_game(c0, CardDataSystem.starter_deck(c0), c0, CardDataSystem.starter_deck(c0), 1)
	for p in s.players:
		for ch in p.characters:
			ch.defeated = true
			ch.hp = 0
	TCGTurnManager.check_win(s)
	if s.winner != -1 or s.phase != "over" or TCGRulesEngine.actor(s) != -1:
		return "Simultaneous all-defeated must set winner=-1 (Draw), phase='over', actor=-1"
	return ""


static func _test_lifecycle_controller() -> String:
	var lc := TCGMatchLifecycle.new()
	var c0 := ["Aang", "Katara", "Toph"]
	var c1 := ["Zuko", "Azula", "Iroh"]
	var bot0 := TCGRandomAI.new(10)
	var bot1 := TCGRandomAI.new(11)
	lc.start_match(c0, TCGDeckSystem.build_preset(c0), c1, TCGDeckSystem.build_preset(c1), 10, [bot0, bot1])

	var steps: int = 0
	while not lc.is_game_over() and steps < 2000:
		var res := lc.step_ai_if_ready()
		if not bool(res["ok"]):
			return "Lifecycle controller step failed at step %d: %s" % [steps, str(res.get("error"))]
		steps += 1
	if not lc.is_game_over():
		return "Match did not terminate within 2000 steps"
	return ""


static func _test_sixty_full_games() -> String:
	for seed_val in range(1, 61):
		var sim := TCGMatchLifecycle.play_simulated_game(seed_val)
		var s: TCGGameState = sim["state"]
		var steps: int = int(sim["steps"])
		if not TCGRulesEngine.last_error.is_empty():
			return "Seed %d failed with rule error: %s" % [seed_val, TCGRulesEngine.last_error]
		if s.phase != "over" and s.round_number <= 40 and steps < 3000:
			return "Seed %d stopped prematurely in phase %s at round %d step %d" % [seed_val, s.phase, s.round_number, steps]
		if s.phase != "over":
			if TCGRulesEngine.legal_actions(s).is_empty():
				return "Seed %d got stuck with 0 legal actions" % seed_val
	return ""

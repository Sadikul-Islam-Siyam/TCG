class_name TCGCombatFeedbackTestSuite
extends RefCounted
## Stage 7 Test Suite: Dice, Elemental Indicators, and Combat Feedback
## Verifies:
## 1. Exact 6 implemented elements + Omni (Dendro strictly excluded).
## 2. All 8 canonical Genshin elemental reactions in `TCGTheme.REACT`.
## 3. Dice tray presentation, roll/tune tumbling animation state, and affordability.
## 4. Structured combat event ingestion without UI recalculation.
## 5. Reaction pills, floating numbers, and elemental coloring.
## 6. Action/skill/burst ribbons, lunges, and hit-flash shakes.
## 7. Non-blocking animation property (rules logic runs synchronously).
## 8. Turn & phase control gating.

const MATCH_SCENE_RES := preload("res://scenes/board/match_scene.tscn")


static func _make_board(seed_val: int = 42, auto_action: bool = true) -> TCGMatchScene:
	var board: TCGMatchScene = MATCH_SCENE_RES.instantiate() as TCGMatchScene
	board._build_board_components()
	board.start_interactive_match("pvp", 0, 1, seed_val, auto_action)
	if auto_action:
		var act_p: int = board.actor()
		if act_p >= 0:
			board.view_player = act_p
			board.human_flags[act_p] = true
	return board


static func run_all() -> Dictionary:
	var tests: Array[Array] = [
		["test_element_set_and_dice_preservation", Callable(TCGCombatFeedbackTestSuite, "_test_element_set_and_dice_preservation")],
		["test_reaction_definitions_and_pill_catalog", Callable(TCGCombatFeedbackTestSuite, "_test_reaction_definitions_and_pill_catalog")],
		["test_dice_tray_roll_and_tune_animation_state", Callable(TCGCombatFeedbackTestSuite, "_test_dice_tray_roll_and_tune_animation_state")],
		["test_skill_cost_indicators_and_affordability", Callable(TCGCombatFeedbackTestSuite, "_test_skill_cost_indicators_and_affordability")],
		["test_structured_combat_events_no_recalculation", Callable(TCGCombatFeedbackTestSuite, "_test_structured_combat_events_no_recalculation")],
		["test_skill_burst_and_defeat_ribbons", Callable(TCGCombatFeedbackTestSuite, "_test_skill_burst_and_defeat_ribbons")],
		["test_phase_and_round_banners", Callable(TCGCombatFeedbackTestSuite, "_test_phase_and_round_banners")],
		["test_character_lunge_and_hit_shake", Callable(TCGCombatFeedbackTestSuite, "_test_character_lunge_and_hit_shake")],
		["test_non_blocking_animation_lifecycle", Callable(TCGCombatFeedbackTestSuite, "_test_non_blocking_animation_lifecycle")],
		["test_turn_and_phase_gating", Callable(TCGCombatFeedbackTestSuite, "_test_turn_and_phase_gating")],
	]

	var passed: int = 0
	var failed: int = 0
	var details: Array[String] = []

	for t in tests:
		var t_name: String = t[0]
		var fn: Callable = t[1]
		var err: String = fn.call()
		if err.is_empty():
			passed += 1
			details.append("[PASS] %s" % t_name)
		else:
			failed += 1
			details.append("[FAIL] %s: %s" % [t_name, err])

	return {"passed": passed, "failed": failed, "total": tests.size(), "details": details}


static func _test_element_set_and_dice_preservation() -> String:
	# 1. Elements check: exactly 6 elements
	var expected_elements: Array[String] = ["Cryo", "Hydro", "Pyro", "Electro", "Anemo", "Geo"]
	if CardDataSystem.ELEMENTS.size() != 6:
		return "Expected 6 elements, got %d" % CardDataSystem.ELEMENTS.size()
	for el in expected_elements:
		if not CardDataSystem.ELEMENTS.has(el):
			return "Missing element: %s" % el
	for el in CardDataSystem.ELEMENTS:
		if String(el).to_lower() == "dendro":
			return "Dendro was reintroduced into ELEMENTS, which violates rule!"

	# 2. Dice faces check: 6 active faces (Cryo excluded from rolls; Omni + 5 elements)
	var expected_dice: Array[String] = ["Hydro", "Pyro", "Electro", "Anemo", "Geo", "Omni"]
	if CardDataSystem.DICE_FACES.size() != 6:
		return "Expected 6 active dice faces (Cryo excluded), got %d" % CardDataSystem.DICE_FACES.size()
	for df in expected_dice:
		if not CardDataSystem.DICE_FACES.has(df):
			return "Missing dice face: %s" % df
	for df in CardDataSystem.DICE_FACES:
		if String(df).to_lower() == "dendro" or String(df).to_lower() == "cryo":
			return "Excluded element %s found in DICE_FACES!" % df

	# 3. Weights check
	if CardDataSystem.DICE_WEIGHTS.size() != 6:
		return "Expected 6 weights, got %d" % CardDataSystem.DICE_WEIGHTS.size()
	var w_sum: float = 0.0
	for w in CardDataSystem.DICE_WEIGHTS:
		w_sum += w
	if absf(w_sum - 1.0) > 0.001:
		return "Dice weights do not sum to 1.0 (got %f)" % w_sum

	# 4. Theme colors check
	for el in ["Cryo", "Hydro", "Pyro", "Electro", "Anemo", "Geo", "Omni", "Physical", "Piercing"]:
		if not TCGTheme.ELEM_COL.has(el):
			return "Missing ELEM_COL entry for %s" % el
	return ""


static func _test_reaction_definitions_and_pill_catalog() -> String:
	var expected_reactions: Array[String] = [
		"Vaporize", "Melt", "Overloaded", "Superconduct",
		"Electro-Charged", "Frozen", "Swirl", "Crystallize"
	]
	if TCGTheme.REACT.size() != 8:
		return "Expected 8 canonical reactions, got %d" % TCGTheme.REACT.size()
	for rx in expected_reactions:
		if not TCGTheme.REACT.has(rx):
			return "Missing canonical reaction: %s" % rx
		var r_data: Dictionary = TCGTheme.REACT[rx]
		if not r_data.has("elements") or not r_data.has("desc"):
			return "Reaction %s missing 'elements' or 'desc'" % rx
		var els: Array = r_data["elements"]
		if els.is_empty():
			return "Reaction %s has empty elements list" % rx
		for el in els:
			if not CardDataSystem.ELEMENTS.has(String(el)):
				return "Reaction %s references unknown element: %s" % [rx, el]

	# Test Vaporize and Melt specifics
	if TCGTheme.REACT["Vaporize"]["desc"] != "+1 damage":
		return "Vaporize description mismatch: %s" % TCGTheme.REACT["Vaporize"]["desc"]
	if TCGTheme.REACT["Melt"]["desc"] != "+2 damage":
		return "Melt description mismatch: %s" % TCGTheme.REACT["Melt"]["desc"]
	return ""


static func _test_dice_tray_roll_and_tune_animation_state() -> String:
	var tray := TCGDiceTray.new()
	var test_dice: Array[String] = ["omni", "pyro", "hydro", "electro", "cryo", "anemo", "geo", "pyro"]
	tray.setup(test_dice, [], [], false, [])

	if tray.is_spinning():
		return "Tray should not be spinning initially"

	# Trigger roll on first 3 dice
	tray.trigger_roll([0, 1, 2], 0.5)
	if not tray.is_spinning():
		return "Tray should be spinning after trigger_roll"
	if not tray.spin_timers.has(0) or not tray.spin_timers.has(1) or not tray.spin_timers.has(2):
		return "Dice 0, 1, 2 should be in spin_timers"
	if tray.spin_timers.has(3):
		return "Die 3 should not be in spin_timers"

	# Advance time halfway
	tray._process(0.25)
	if not tray.is_spinning():
		return "Tray should still be spinning at t=0.25"

	# Advance time past duration
	tray._process(0.4)
	if tray.is_spinning():
		return "Tray should have finished spinning after duration"

	# Trigger tune on die 4
	tray.trigger_tune(4, 0.4)
	if not tray.is_spinning() or not tray.spin_timers.has(4):
		return "Die 4 should be spinning after trigger_tune"
	tray._process(0.45)
	if tray.is_spinning():
		return "Die 4 spin should have finished"

	tray.free()
	return ""


static func _test_skill_cost_indicators_and_affordability() -> String:
	CardDataSystem.load_all_content()
	var bar := TCGSkillBar.new()
	var ch := TCGPlayerSystem.CharacterInstance.new("Zuko", 10, 0)
	var d: CardDataSystem.CharData = ch.get_defn()
	if d == null:
		bar.free()
		return "Failed to load Zuko definition"

	# Setup with normal skill usable, but burst unusable (0 energy)
	var usable: Array[bool] = [true, true, false]
	var costs: Array[CardDataSystem.CostData] = [d.skills[0].cost, d.skills[1].cost, d.skills[2].cost]
	bar.setup(ch, usable, costs, -1)

	if not bar.usable_flags[0] or not bar.usable_flags[1]:
		bar.free()
		return "Expected skills 0 and 1 to be usable"
	if bar.usable_flags[2]:
		bar.free()
		return "Expected burst to be unusable with 0 energy"

	bar.free()
	return ""


static func _test_structured_combat_events_no_recalculation() -> String:
	CardDataSystem.load_all_content()
	var scene := _make_board(42, true)

	# Simulate damage event emitted by the rules engine
	var events: Array = [
		{
			"kind": "damage",
			"player": 1 - scene.view_player,
			"char": 0,
			"amount": 5,
			"dtype": "Pyro",
			"reaction": "Melt",
		},
		{
			"kind": "heal",
			"player": scene.view_player,
			"char": 0,
			"amount": 3,
		}
	]
	scene._present_events(events)

	# Verify damage floater uses exact amount and element color
	var found_dmg: bool = false
	for fl in scene._floaters:
		if fl["text"] == "-5":
			found_dmg = true
			if fl["col"] != TCGTheme.elem_color("Pyro"):
				scene.free()
				return "Damage floater color did not match Pyro element color"
	if not found_dmg:
		scene.free()
		return "Damage floater -5 was not created"

	# Verify reaction pill uses exact reaction name and description
	var found_rx: bool = false
	for rp in scene._reaction_pills:
		if rp["title"] == "Melt":
			found_rx = true
			if rp["sub"] != "+2 damage":
				scene.free()
				return "Melt reaction pill subtitle mismatch: %s" % rp["sub"]
			var els: Array = rp["elements"]
			if els != ["Cryo", "Pyro"]:
				scene.free()
				return "Melt reaction pill elements mismatch: %s" % str(els)
	if not found_rx:
		scene.free()
		return "Melt reaction pill was not created"

	# Verify heal floater uses exact amount and HEAL color
	var found_heal: bool = false
	for fl in scene._floaters:
		if fl["text"] == "+3":
			found_heal = true
			if fl["col"] != TCGTheme.HEAL:
				scene.free()
				return "Heal floater color did not match TCGTheme.HEAL"
	if not found_heal:
		scene.free()
		return "Heal floater +3 was not created"

	scene.free()
	return ""


static func _test_skill_burst_and_defeat_ribbons() -> String:
	CardDataSystem.load_all_content()
	var scene := _make_board(42, true)

	# Emit burst skill event
	var events: Array = [
		{
			"kind": "skill",
			"player": scene.view_player,
			"char": 0,
			"skill": "Dragon's Roar",
			"skill_kind": "burst",
		},
		{
			"kind": "defeat",
			"player": 1 - scene.view_player,
			"char": 0,
		}
	]
	scene._present_events(events)

	# Verify burst flash and ribbon
	if scene._burst_flash_alpha < 0.5:
		scene.free()
		return "Burst skill should trigger burst flash alpha"

	var found_burst_ribbon: bool = false
	for rb in scene._ribbons:
		if rb["title"] == "Dragon's Roar":
			found_burst_ribbon = true
			if not String(rb["sub"]).contains("Elemental Burst"):
				scene.free()
				return "Burst ribbon subtitle missing 'Elemental Burst': %s" % rb["sub"]
	if not found_burst_ribbon:
		scene.free()
		return "Burst ribbon for Dragon's Roar was not created"

	# Verify defeat ribbon
	var found_defeat_ribbon: bool = false
	for rb in scene._ribbons:
		if String(rb["title"]).contains("was defeated"):
			found_defeat_ribbon = true
			if rb["accent"] != TCGTheme.RED:
				scene.free()
				return "Defeat ribbon accent color must be RED"
	if not found_defeat_ribbon:
		scene.free()
		return "Defeat ribbon was not created"

	scene.free()
	return ""


static func _test_phase_and_round_banners() -> String:
	CardDataSystem.load_all_content()
	var scene := _make_board(42, true)

	var events: Array = [
		{"kind": "round", "number": 2},
		{"kind": "phase", "name": "action"},
	]
	scene._present_events(events)

	var found_round_banner: bool = false
	var found_action_banner: bool = false
	for b in scene._banners:
		if b["title"] == "Round 2":
			found_round_banner = true
		elif b["title"] == "Action Phase":
			found_action_banner = true

	if not found_round_banner:
		scene.free()
		return "Round 2 banner not created"
	if not found_action_banner:
		scene.free()
		return "Action Phase banner not created"

	scene.free()
	return ""


static func _test_character_lunge_and_hit_shake() -> String:
	CardDataSystem.load_all_content()
	var scene := _make_board(42, true)

	# Present skill and damage
	var events: Array = [
		{"kind": "skill", "player": scene.view_player, "char": 0, "skill": "Flame Slash", "skill_kind": "normal"},
		{"kind": "damage", "player": 1 - scene.view_player, "char": 0, "amount": 2, "dtype": "Physical", "reaction": null},
	]
	scene._present_events(events)

	# Verify attacking lunge registered for attacking char
	var l_key := "%d_0" % scene.view_player
	if not scene._lunges.has(l_key) or float(scene._lunges[l_key]) <= 0.0:
		scene.free()
		return "Lunge timer not registered for attacking character"

	# Verify hit flash registered for damaged char
	var h_key := "%d_0" % (1 - scene.view_player)
	if not scene._hit_flash.has(h_key) or float(scene._hit_flash[h_key]) <= 0.0:
		scene.free()
		return "Hit flash timer not registered for damaged character"

	# Step process slightly so animation timer advances along the sine curve
	scene._process(0.1)
	scene.sync_from_state()
	var slot_own: TCGCharacterSlot = scene.own_char_slots[0]
	if slot_own.lunge_offset == Vector2.ZERO:
		scene.free()
		return "Own character slot 0 did not receive lunge offset"

	var slot_foe: TCGCharacterSlot = scene.foe_char_slots[0]
	if slot_foe.hit_flash_alpha <= 0.0:
		scene.free()
		return "Foe character slot 0 did not receive hit flash alpha"

	scene.free()
	return ""


static func _test_non_blocking_animation_lifecycle() -> String:
	CardDataSystem.load_all_content()
	var scene := _make_board(42, false) # starts in setup mulligan

	# Populate active animations (floaters, reaction pills, ribbons, banners, dice spin)
	scene._floaters.append({"text": "-3", "pos": Vector2(640, 360), "col": TCGTheme.RED, "ttl": 1.2, "max_ttl": 1.2})
	scene._reaction_pills.append({"title": "Melt", "sub": "+2 damage", "elements": ["Cryo", "Pyro"], "pos": Vector2(640, 360), "t": 0.2, "dur": 2.4})
	scene._ribbons.append({"title": "Action", "sub": "", "accent": TCGTheme.GOLD, "pos": Vector2(640, 260), "t": 0.1, "dur": 1.6, "mine": true})
	scene.dice_tray.trigger_roll([0, 1, 2, 3])

	# Verify submitting match lifecycle action executes synchronously without blocking
	var fp: int = maxi(0, scene.actor())
	var mull_act := TCGGameState.ActionData.new("mulligan", fp, -1, -1, [0, 1])
	var res := scene.lifecycle.submit_action(mull_act)
	if not bool(res.get("ok", false)):
		scene.free()
		return "Submitting action while animations active failed: %s" % str(res.get("error", ""))

	# Confirm acting player mulligan completed in state
	if not scene.game_state.players[fp].mull_done:
		scene.free()
		return "Mulligan was blocked or not applied to state"

	scene.free()
	return ""


static func _test_turn_and_phase_gating() -> String:
	CardDataSystem.load_all_content()
	var scene := _make_board(42, false) # starts in setup mulligan

	# In Setup phase, calling begin_tune should be rejected
	var tune_ok: bool = scene.begin_tune(0)
	if tune_ok:
		scene.free()
		return "Elemental Tuning should be rejected during setup phase"

	# Switch actor to player 1 (opponent) and verify is_my_turn() is false
	scene.game_state.phase = "action"
	scene.game_state.current = 1 - scene.view_player
	scene.sync_from_state()

	if scene.is_my_turn():
		scene.free()
		return "is_my_turn() should be false when actor is opponent"

	# Attempting skill execution while not player's turn should fail
	var skill_act := TCGGameState.ActionData.new("skill", scene.view_player, 0, -1, [0, 1, 2])
	var res: Dictionary = scene.execute_action(skill_act)
	if bool(res.get("ok", false)):
		scene.free()
		return "Executing skill out of turn should be rejected"

	scene.free()
	return ""

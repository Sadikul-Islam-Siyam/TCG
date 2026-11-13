class_name TCGRulesTestSuite
extends RefCounted
## RulesTestSuite
## Comprehensive parity test suite porting all test cases from Python
## `tests/test_engine.py` and `tests/test_m3.py` to GDScript.


static func _start(
	c0: Array = ["Keqing", "Fischl", "Diluc"],
	c1: Array = ["Kaeya", "Ganyu", "Xingqiu"],
	seed_val: int = 1
) -> TCGGameState:
	## Matches `tests/test_engine.py:start()`: reaches action phase, P0 to act, 12 Omni dice each.
	var s := TCGRulesEngine.new_game(c0, CardDataSystem.starter_deck(), c1, CardDataSystem.starter_deck(), seed_val)
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


static func _hit(s: TCGGameState, ti: int, amount: int, dtype: String, tp: int = 1) -> void:
	s.events = []
	TCGRulesEngine.deal_damage(s, 1 - tp, tp, ti, amount, dtype, "effect", "")


static func _give(s: TCGGameState, p: int, cards: Array) -> void:
	var h: Array[String] = []
	for c in cards:
		h.append(str(c))
	s.players[p].hand = h


static func _play_card(s: TCGGameState, card_name: String, target: int = -1, p: int = 0) -> void:
	var pl := s.players[p]
	for a in TCGRulesEngine.legal_actions(s):
		if a.type == "card" and pl.hand[a.index] == card_name and a.target == target:
			TCGRulesEngine.apply_action(s, a)
			return


static func _find_skill_action(s: TCGGameState, skill_idx: int) -> TCGGameState.ActionData:
	for a in TCGRulesEngine.legal_actions(s):
		if a.type == "skill" and a.index == skill_idx:
			return a
	return null


static func run_all_tests() -> Dictionary:
	CardDataSystem.load_all_content()
	var results: Array[Dictionary] = []

	var tests: Array[Array] = [
		["test_auto_pay_prefers_exact_then_omni", Callable(TCGRulesTestSuite, "_test_auto_pay_prefers_exact_then_omni")],
		["test_auto_pay_fails_when_short", Callable(TCGRulesTestSuite, "_test_auto_pay_fails_when_short")],
		["test_payment_rejects_wrong_dice", Callable(TCGRulesTestSuite, "_test_payment_rejects_wrong_dice")],
		["test_omni_rate_is_one_eighth_and_elements_equal", Callable(TCGRulesTestSuite, "_test_omni_rate")],
		["test_setup_reaches_action_phase", Callable(TCGRulesTestSuite, "_test_setup_reaches_action_phase")],
		["test_skill_deals_damage_applies_aura_and_energy", Callable(TCGRulesTestSuite, "_test_skill_damage_aura_energy")],
		["test_fast_action_keeps_turn_and_tuning_changes_die", Callable(TCGRulesTestSuite, "_test_fast_action_tuning")],
		["test_burst_needs_full_energy", Callable(TCGRulesTestSuite, "_test_burst_needs_full_energy")],
		["test_illegal_actions_are_rejected", Callable(TCGRulesTestSuite, "_test_illegal_actions_rejected")],
		["test_end_round_flow_and_first_player", Callable(TCGRulesTestSuite, "_test_end_round_flow")],
		["test_switch_costs_one_die_and_passes_turn", Callable(TCGRulesTestSuite, "_test_switch_costs_one_die")],
		["test_all_8_reaction_bonuses_and_aura_consumed", Callable(TCGRulesTestSuite, "_test_all_reactions")],
		["test_same_element_keeps_aura_no_reaction", Callable(TCGRulesTestSuite, "_test_same_element_keeps_aura")],
		["test_overloaded_forces_switch", Callable(TCGRulesTestSuite, "_test_overloaded_forces_switch")],
		["test_superconduct_pierces_standby_characters", Callable(TCGRulesTestSuite, "_test_superconduct_pierces")],
		["test_frozen_blocks_skills_and_boosts_physical_then_thaws", Callable(TCGRulesTestSuite, "_test_frozen_shatter")],
		["test_swirl_spreads_element_to_other_characters", Callable(TCGRulesTestSuite, "_test_swirl_spreads")],
		["test_crystallize_gives_shield_to_attacker_side", Callable(TCGRulesTestSuite, "_test_crystallize_shield")],
		["test_piercing_ignores_shields_and_auras", Callable(TCGRulesTestSuite, "_test_piercing_ignores_shields")],
		["test_summon_attacks_in_end_phase_and_expires", Callable(TCGRulesTestSuite, "_test_summon_end_phase")],
		["test_defeat_forces_choice_and_win_detection", Callable(TCGRulesTestSuite, "_test_defeat_and_win")],
		["test_pyro_infusion_converts_physical", Callable(TCGRulesTestSuite, "_test_pyro_infusion")],
		["test_rain_sword_reduces_big_hits_twice", Callable(TCGRulesTestSuite, "_test_rain_sword")],
		["test_clone_is_independent_and_deterministic", Callable(TCGRulesTestSuite, "_test_clone_and_determinism")],
		["test_engine_announces_phases_and_rounds", Callable(TCGRulesTestSuite, "_test_phase_and_round_events")],
		["test_presets_are_legal_decks", Callable(TCGRulesTestSuite, "_test_presets_legal")],
		["test_validation_catches_each_rule", Callable(TCGRulesTestSuite, "_test_deck_validation")],
		["test_autofill_keeps_partial_and_rejects_illegal", Callable(TCGRulesTestSuite, "_test_autofill_csp")],
		["test_share_code_roundtrip", Callable(TCGRulesTestSuite, "_test_share_code_roundtrip")],
		["test_weapon_adds_damage_only_for_matching_type", Callable(TCGRulesTestSuite, "_test_weapon_damage")],
		["test_new_weapon_replaces_old_and_defeat_removes_equipment", Callable(TCGRulesTestSuite, "_test_weapon_replace_and_defeat")],
		["test_talent_equips_then_uses_skill_and_passes_turn", Callable(TCGRulesTestSuite, "_test_talent_equip_and_skill")],
		["test_talent_requires_its_active_character", Callable(TCGRulesTestSuite, "_test_talent_requires_active")],
		["test_fischl_talent_oz_follow_up_once_per_round", Callable(TCGRulesTestSuite, "_test_fischl_stellar_predator")],
		["test_gambler_earrings_gives_dice_once_per_round", Callable(TCGRulesTestSuite, "_test_gamblers_earrings")],
		["test_support_end_phase_effects", Callable(TCGRulesTestSuite, "_test_support_end_phase")],
		["test_paimon_gives_dice_at_action_start", Callable(TCGRulesTestSuite, "_test_paimon_action_start")],
		["test_changing_shifts_and_leave_it_to_me", Callable(TCGRulesTestSuite, "_test_changing_shifts_and_leave_it")],
		["test_resonance_card_and_reflection", Callable(TCGRulesTestSuite, "_test_resonance_and_reflection")],
	]

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


# ------------------------------------------------------------------------------
# Individual Test Implementations
# ------------------------------------------------------------------------------
static func _test_auto_pay_prefers_exact_then_omni() -> String:
	var dice: Array[String] = [CardDataSystem.OMNI, CardDataSystem.PYRO, CardDataSystem.PYRO, CardDataSystem.HYDRO, CardDataSystem.PYRO]
	var cost := CardDataSystem.CostData.new(CardDataSystem.PYRO, 3, 0, 0)
	var pay = TCGDiceSystem.auto_pay(dice, cost, [CardDataSystem.PYRO])
	if pay != [1, 2, 4]:
		return "Expected [1, 2, 4], got %s" % str(pay)
	if not TCGDiceSystem.payment_ok(dice, cost, pay):
		return "payment_ok returned false for [1, 2, 4]"
	return ""


static func _test_auto_pay_fails_when_short() -> String:
	var d1: Array[String] = [CardDataSystem.PYRO, CardDataSystem.HYDRO]
	if TCGDiceSystem.auto_pay(d1, CardDataSystem.CostData.new(CardDataSystem.PYRO, 2)) != null:
		return "Expected null when short on aligned dice"
	var d2: Array[String] = [CardDataSystem.PYRO]
	if TCGDiceSystem.auto_pay(d2, CardDataSystem.CostData.new(CardDataSystem.PYRO, 1, 2)) != null:
		return "Expected null when short on total dice"
	return ""


static func _test_payment_rejects_wrong_dice() -> String:
	var dice: Array[String] = [CardDataSystem.HYDRO, CardDataSystem.HYDRO, CardDataSystem.HYDRO]
	var cost := CardDataSystem.CostData.new(CardDataSystem.PYRO, 1, 2)
	if TCGDiceSystem.payment_ok(dice, cost, [0, 1, 2]):
		return "payment_ok accepted wrong element dice"
	return ""


static func _test_omni_rate() -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var total: int = 12000
	var rolls := TCGDiceSystem.roll(rng, total)
	var counts: Dictionary = {}
	for f in rolls:
		counts[f] = int(counts.get(f, 0)) + 1
	var omni_rate: float = float(counts.get(CardDataSystem.OMNI, 0)) / float(total)
	if absf(omni_rate - 0.125) > 0.015:
		return "Omni rate out of tolerance: %f" % omni_rate
	for el in CardDataSystem.ELEMENTS:
		var el_rate: float = float(counts.get(el, 0)) / float(total)
		if absf(el_rate - (7.0 / 48.0)) > 0.015:
			return "Element %s rate out of tolerance: %f" % [el, el_rate]
	return ""


static func _test_setup_reaches_action_phase() -> String:
	var s := _start()
	if s.phase != "action" or s.round_number != 1:
		return "Expected action phase round 1, got %s round %d" % [s.phase, s.round_number]
	for p in s.players:
		if p.active != 0 or p.hand.size() != 5:
			return "Expected active=0 and hand=5, got active=%d hand=%d" % [p.active, p.hand.size()]
	return ""


static func _test_skill_damage_aura_energy() -> String:
	var s := _start()
	TCGRulesEngine.apply_action(s, _find_skill_action(s, 1))
	var foe := s.players[1].characters[0]
	if foe.hp != 7 or foe.aura != CardDataSystem.ELECTRO:
		return "Expected foe hp=7 aura=Electro, got hp=%d aura=%s" % [foe.hp, foe.aura]
	if s.players[0].characters[0].energy != 1 or s.current != 1:
		return "Expected energy=1 and turn passed to P1"
	return ""


static func _test_fast_action_tuning() -> String:
	var s := _start()
	s.players[0].dice = [CardDataSystem.PYRO, CardDataSystem.OMNI]
	var tune_act: TCGGameState.ActionData = null
	for a in TCGRulesEngine.legal_actions(s):
		if a.type == "tune":
			tune_act = a
			break
	if tune_act == null:
		return "Expected a legal tune action"
	TCGRulesEngine.apply_action(s, tune_act)
	if s.current != 0 or s.players[0].dice[0] != CardDataSystem.ELECTRO:
		return "Expected fast action to keep turn and convert die to Electro"
	return ""


static func _test_burst_needs_full_energy() -> String:
	var s := _start()
	if _find_skill_action(s, 2) != null:
		return "Burst should not be legal at 0 energy"
	s.players[0].characters[0].energy = 3
	var burst_act := _find_skill_action(s, 2)
	if burst_act == null:
		return "Burst should be legal at 3 energy"
	TCGRulesEngine.apply_action(s, burst_act)
	if s.players[0].characters[0].energy != 0:
		return "Energy should be 0 after burst"
	var hps := [s.players[1].characters[0].hp, s.players[1].characters[1].hp, s.players[1].characters[2].hp]
	if hps != [6, 7, 7]:
		return "Expected foe HPs [6, 7, 7], got %s" % str(hps)
	return ""


static func _test_illegal_actions_rejected() -> String:
	var s := _start()
	TCGRulesEngine.apply_action(s, TCGGameState.ActionData.new("skill", 1, 0, -1, [0, 1, 2]))
	if TCGRulesEngine.last_error != "not this player's turn":
		return "Expected 'not this player's turn', got '%s'" % TCGRulesEngine.last_error
	TCGRulesEngine.apply_action(s, TCGGameState.ActionData.new("skill", 0, 0, -1, [0]))
	if TCGRulesEngine.last_error != "invalid dice payment":
		return "Expected 'invalid dice payment', got '%s'" % TCGRulesEngine.last_error
	return ""


static func _test_end_round_flow() -> String:
	var s := _start()
	TCGRulesEngine.apply_action(s, TCGGameState.ActionData.new("end_round", 0))
	if s.current != 1 or s.first_ender != 0:
		return "Expected current=1 and first_ender=0"
	TCGRulesEngine.apply_action(s, TCGGameState.ActionData.new("end_round", 1))
	if s.round_number != 2 or s.phase != "roll" or s.first_player != 0:
		return "Expected round 2 roll phase with first_player=0"
	for p in s.players:
		if p.dice.size() != 8 or p.hand.size() != 7:
			return "Expected 8 dice and 7 cards in hand"
	return ""


static func _test_switch_costs_one_die() -> String:
	var s := _start()
	var sw: TCGGameState.ActionData = null
	for a in TCGRulesEngine.legal_actions(s):
		if a.type == "switch" and a.index == 2:
			sw = a
			break
	TCGRulesEngine.apply_action(s, sw)
	if s.players[0].active != 2 or s.players[0].dice.size() != 11 or s.current != 1:
		return "Switch failed to update active/dice/turn"
	return ""


static func _test_all_reactions() -> String:
	var cases: Array[Array] = [
		[CardDataSystem.HYDRO, CardDataSystem.PYRO, 1, "Vaporize"],
		[CardDataSystem.PYRO, CardDataSystem.HYDRO, 1, "Vaporize"],
		[CardDataSystem.CRYO, CardDataSystem.PYRO, 2, "Melt"],
		[CardDataSystem.PYRO, CardDataSystem.CRYO, 2, "Melt"],
		[CardDataSystem.PYRO, CardDataSystem.ELECTRO, 2, "Overloaded"],
		[CardDataSystem.CRYO, CardDataSystem.ELECTRO, 1, "Superconduct"],
		[CardDataSystem.HYDRO, CardDataSystem.ELECTRO, 1, "Electro-Charged"],
		[CardDataSystem.CRYO, CardDataSystem.HYDRO, 1, "Frozen"],
	]
	for c in cases:
		var aura: String = c[0]
		var dtype: String = c[1]
		var bonus: int = c[2]
		var r_name: String = c[3]
		var s := _start()
		var tgt := s.players[1].characters[0]
		tgt.aura = aura
		_hit(s, 0, 2, dtype)
		if tgt.hp != 10 - 2 - bonus:
			return "%s: expected HP %d, got %d" % [r_name, 10 - 2 - bonus, tgt.hp]
		if s.events[0]["reaction"] != r_name or not tgt.aura.is_empty():
			return "%s: reaction event or aura consumption failed" % r_name
	return ""


static func _test_same_element_keeps_aura() -> String:
	var s := _start()
	s.players[1].characters[0].aura = CardDataSystem.PYRO
	_hit(s, 0, 2, CardDataSystem.PYRO)
	if s.players[1].characters[0].hp != 8 or s.players[1].characters[0].aura != CardDataSystem.PYRO:
		return "Same element should deal damage and preserve aura"
	return ""


static func _test_overloaded_forces_switch() -> String:
	var s := _start()
	s.players[1].characters[0].aura = CardDataSystem.PYRO
	_hit(s, 0, 1, CardDataSystem.ELECTRO)
	if s.players[1].active != 1:
		return "Overloaded should force switch to index 1, got %d" % s.players[1].active
	return ""


static func _test_superconduct_pierces() -> String:
	var s := _start()
	s.players[1].characters[0].aura = CardDataSystem.CRYO
	_hit(s, 0, 1, CardDataSystem.ELECTRO)
	var hps := [s.players[1].characters[0].hp, s.players[1].characters[1].hp, s.players[1].characters[2].hp]
	if hps != [8, 9, 9]:
		return "Expected HPs [8, 9, 9], got %s" % str(hps)
	return ""


static func _test_frozen_shatter() -> String:
	var s := _start()
	s.players[1].characters[0].aura = CardDataSystem.CRYO
	_hit(s, 0, 1, CardDataSystem.HYDRO)
	var foe := s.players[1].characters[0]
	if not TCGRulesEngine.has_status(foe, "Frozen"):
		return "Expected Frozen status"
	s.current = 1
	for a in TCGRulesEngine.legal_actions(s):
		if a.type == "skill":
			return "Frozen character should not have legal skill actions"
	_hit(s, 0, 1, CardDataSystem.PHYSICAL)
	if foe.hp != 5 or not foe.statuses.is_empty():
		return "Expected Frozen shatter to deal 3 damage (HP 5) and remove Frozen"
	return ""


static func _test_swirl_spreads() -> String:
	var s := _start()
	s.players[1].characters[0].aura = CardDataSystem.PYRO
	_hit(s, 0, 1, CardDataSystem.ANEMO)
	var hps := [s.players[1].characters[0].hp, s.players[1].characters[1].hp, s.players[1].characters[2].hp]
	if hps != [9, 9, 9]:
		return "Expected Swirl HPs [9, 9, 9], got %s" % str(hps)
	if s.players[1].characters[1].aura != CardDataSystem.PYRO or not s.players[1].characters[0].aura.is_empty():
		return "Expected Swirl to spread Pyro aura to standby and clear target aura"
	return ""


static func _test_crystallize_shield() -> String:
	var s := _start()
	s.players[1].characters[0].aura = CardDataSystem.HYDRO
	_hit(s, 0, 1, CardDataSystem.GEO)
	if s.players[1].characters[0].hp != 8:
		return "Expected Crystallize to deal 2 DMG (HP 8)"
	if s.players[0].combat.size() != 1 or s.players[0].combat[0].name != "Crystallize Shield" or s.players[0].combat[0].shield != 1:
		return "Expected Crystallize Shield (1) on P0"
	_hit(s, 0, 3, CardDataSystem.PHYSICAL, 0)
	if s.players[0].characters[0].hp != 8 or not s.players[0].combat.is_empty():
		return "Expected shield to absorb 1 damage and expire"
	return ""


static func _test_piercing_ignores_shields() -> String:
	var s := _start()
	s.players[1].combat.append(TCGPlayerSystem.StatusInstance.new("Jade Shield", -1, -1, 2))
	s.players[1].characters[0].aura = CardDataSystem.PYRO
	_hit(s, 0, 2, CardDataSystem.PIERCING)
	if s.players[1].characters[0].hp != 8 or s.players[1].characters[0].aura != CardDataSystem.PYRO:
		return "Piercing should ignore shields and auras"
	return ""


static func _test_summon_end_phase() -> String:
	var s := _start()
	TCGEffectContext.new(s, 0).summon("Oz")
	TCGRulesEngine.apply_action(s, TCGGameState.ActionData.new("end_round", 0))
	TCGRulesEngine.apply_action(s, TCGGameState.ActionData.new("end_round", 1))
	if s.players[1].characters[0].hp != 9 or s.players[0].summons[0].usages != 1:
		return "Oz should deal 1 damage and have 1 usage left"
	while s.phase != "action":
		TCGRulesEngine.apply_action(s, TCGRulesEngine.legal_actions(s)[0])
	TCGRulesEngine.apply_action(s, TCGGameState.ActionData.new("end_round", s.current))
	TCGRulesEngine.apply_action(s, TCGGameState.ActionData.new("end_round", s.current))
	if not s.players[0].summons.is_empty():
		return "Oz should expire after 2 usages"
	return ""


static func _test_defeat_and_win() -> String:
	var s := _start()
	_hit(s, 0, 99, CardDataSystem.PHYSICAL)
	if s.players[1].active != -1 or s.pending != [1] or TCGRulesEngine.actor(s) != 1:
		return "Defeat of active character should set active=-1 and pending=[1]"
	TCGRulesEngine.apply_action(s, TCGGameState.ActionData.new("choose_active", 1, 1))
	if s.players[1].active != 1 or not s.pending.is_empty():
		return "choose_active should resolve pending switch"
	_hit(s, 1, 99, CardDataSystem.PHYSICAL)
	_hit(s, 2, 99, CardDataSystem.PHYSICAL)
	if s.phase != "over" or s.winner != 0:
		return "Expected P0 win when all P1 characters defeated"
	return ""


static func _test_pyro_infusion() -> String:
	var s := _start()
	TCGRulesEngine.add_status(s.players[0].characters[2].statuses, "Pyro Infusion")
	s.players[0].active = 2
	TCGRulesEngine.apply_action(s, _find_skill_action(s, 0))
	if s.players[1].characters[0].aura != CardDataSystem.PYRO:
		return "Pyro Infusion should convert Physical normal attack to Pyro"
	return ""


static func _test_rain_sword() -> String:
	var s := _start(["Xingqiu", "Fischl", "Diluc"], ["Kaeya", "Ganyu", "Xingqiu"])
	TCGRulesEngine.apply_action(s, _find_skill_action(s, 1))
	TCGRulesEngine.apply_action(s, TCGGameState.ActionData.new("end_round", 1))
	_hit(s, 0, 3, CardDataSystem.PHYSICAL, 0)
	_hit(s, 0, 1, CardDataSystem.PHYSICAL, 0)
	_hit(s, 0, 3, CardDataSystem.PHYSICAL, 0)
	if s.players[0].characters[0].hp != 5 or not s.players[0].combat.is_empty():
		return "Rain Sword should reduce the two 3-damage hits by 1 each and expire"
	return ""


static func _test_clone_and_determinism() -> String:
	var s := _start()
	var c := s.clone()
	TCGRulesEngine.apply_action(c, _find_skill_action(c, 0))
	if s.players[1].characters[0].hp != 10 or c.players[1].characters[0].hp >= 10:
		return "Cloned state mutation leaked to original state"

	# Determinism check with identical seed
	var g1 := TCGRulesEngine.new_game(["Keqing", "Mona", "Zhongli"], CardDataSystem.starter_deck(), ["Diluc", "Sucrose", "Ganyu"], CardDataSystem.starter_deck(), 42)
	var g2 := TCGRulesEngine.new_game(["Keqing", "Mona", "Zhongli"], CardDataSystem.starter_deck(), ["Diluc", "Sucrose", "Ganyu"], CardDataSystem.starter_deck(), 42)
	for _step in range(25):
		if g1.phase == "over":
			break
		var a1 := TCGRulesEngine.legal_actions(g1)[0]
		var a2 := TCGRulesEngine.legal_actions(g2)[0]
		if not a1.equals(a2):
			return "Determinism mismatch in legal_actions"
		TCGRulesEngine.apply_action(g1, a1)
		TCGRulesEngine.apply_action(g2, a2)
	if TCGRulesEngine.describe(g1) != TCGRulesEngine.describe(g2):
		return "Determinism mismatch in final state description"
	return ""


static func _test_phase_and_round_events() -> String:
	var s := _start()
	TCGRulesEngine.apply_action(s, TCGGameState.ActionData.new("end_round", 0))
	TCGRulesEngine.apply_action(s, TCGGameState.ActionData.new("end_round", 1))
	var has_end_phase: bool = false
	var has_round_ev: bool = false
	for ev in s.events:
		if ev["kind"] == "phase" and ev.get("name") == "end":
			has_end_phase = true
		if ev["kind"] == "round":
			has_round_ev = true
	if not has_end_phase or not has_round_ev:
		return "Missing end phase or round event"
	return ""


static func _test_presets_legal() -> String:
	var presets := TCGDeckSystem.preset_decks()
	if presets.size() != 6:
		return "Expected 6 presets, got %d" % presets.size()
	for name in presets.keys():
		var pair: Array = presets[name]
		var errs := TCGDeckSystem.validate_deck(pair[0], pair[1])
		if not errs.is_empty():
			return "Preset '%s' failed validation: %s" % [name, str(errs)]
	return ""


static func _test_deck_validation() -> String:
	var chars := ["Keqing", "Fischl", "Diluc"]
	var good: Array[String] = TCGDeckSystem.autofill(chars)
	if not TCGDeckSystem.validate_deck(chars, good).is_empty():
		return "autofill deck should be valid"
	var short_deck := good.slice(0, 29)
	if TCGDeckSystem.validate_deck(chars, short_deck).is_empty():
		return "29-card deck should fail validation"
	var wrong_talent := good.duplicate()
	wrong_talent[0] = "Undivided Heart"
	if TCGDeckSystem.validate_deck(chars, wrong_talent).is_empty():
		return "Wrong character talent should fail validation"
	var wrong_weapon := good.duplicate()
	wrong_weapon[0] = "White Tassel"
	if TCGDeckSystem.validate_deck(chars, wrong_weapon).is_empty():
		return "Polearm without polearm user should fail validation"
	var wrong_res := good.duplicate()
	wrong_res[0] = "Elemental Resonance: Fervent Flames"
	if TCGDeckSystem.validate_deck(chars, wrong_res).is_empty():
		return "Pyro resonance with only 1 Pyro character should fail validation"
	return ""


static func _test_autofill_csp() -> String:
	var chars := ["Mona", "Sucrose", "Zhongli"]
	var partial := ["Magic Guide", "Magic Guide", "Chaotic Entropy"]
	var a = TCGDeckSystem.autofill(chars, partial)
	var b = TCGDeckSystem.autofill(chars, partial)
	if a == null or a != b or not TCGDeckSystem.validate_deck(chars, a).is_empty():
		return "autofill should be deterministic and produce a valid 30-card deck"
	if TCGDeckSystem.autofill(["Keqing", "Fischl", "Diluc"], ["Undivided Heart"]) != null:
		return "autofill should return null for illegal partial deck"
	if TCGDeckSystem.autofill(["Keqing", "Fischl", "Diluc"], ["Paimon", "Paimon", "Paimon"]) != null:
		return "autofill should return null for >2 copies in partial deck"
	return ""


static func _test_share_code_roundtrip() -> String:
	var presets := TCGDeckSystem.preset_decks()
	var melt: Array = presets["Melt Burst"]
	var code := TCGDeckSystem.encode(melt[0], melt[1])
	var decoded := TCGDeckSystem.decode(code)
	var sorted_cards: Array[String] = (melt[1] as Array[String]).duplicate()
	sorted_cards.sort()
	if decoded.size() != 2 or decoded[0] != melt[0] or decoded[1] != sorted_cards:
		return "Share code roundtrip mismatch"
	return ""


static func _test_weapon_damage() -> String:
	var s := _start()
	_give(s, 0, ["Traveler's Handy Sword", "Raven Bow"])
	var bow_targets: Array[int] = []
	for a in TCGRulesEngine.legal_actions(s):
		if a.type == "card" and s.players[0].hand[a.index] == "Raven Bow":
			bow_targets.append(a.target)
	if bow_targets != [1]:
		return "Only Fischl (index 1) should be a valid target for Raven Bow"
	_play_card(s, "Traveler's Handy Sword", 0)
	if s.current != 0:
		return "Equipping weapon should be a Fast Action"
	TCGRulesEngine.apply_action(s, _find_skill_action(s, 1))
	if s.players[1].characters[0].hp != 6:
		return "Expected weapon to add +1 skill damage (HP 6), got %d" % s.players[1].characters[0].hp
	return ""


static func _test_weapon_replace_and_defeat() -> String:
	var s := _start(["Keqing", "Xingqiu", "Diluc"])
	_give(s, 0, ["Traveler's Handy Sword"])
	_play_card(s, "Traveler's Handy Sword", 0)
	if s.players[0].characters[0].equipment.get("weapon") != "Traveler's Handy Sword":
		return "Weapon not equipped"
	_hit(s, 0, 99, CardDataSystem.PHYSICAL, 0)
	if not s.players[0].characters[0].equipment.is_empty() or not s.players[0].characters[0].statuses.is_empty():
		return "Defeat should clear equipment and statuses"
	return ""


static func _test_talent_equip_and_skill() -> String:
	var s := _start()
	s.players[0].active = 1
	_give(s, 0, ["Stellar Predator"])
	var dice_before: int = s.players[0].dice.size()
	_play_card(s, "Stellar Predator", 1)
	var p := s.players[0]
	if dice_before - p.dice.size() != 3:
		return "Talent should cost 3 dice"
	if p.characters[1].equipment.get("talent") != "Stellar Predator":
		return "Stellar Predator should be equipped"
	if p.summons.size() != 1 or p.summons[0].name != "Oz" or s.current != 1 or s.players[1].characters[0].hp != 9:
		return "Talent should immediately execute Nightrider and pass turn"
	return ""


static func _test_talent_requires_active() -> String:
	var s := _start()
	_give(s, 0, ["Stellar Predator", "Thundering Penance"])
	var playable: Array[String] = []
	for a in TCGRulesEngine.legal_actions(s):
		if a.type == "card":
			playable.append(s.players[0].hand[a.index])
	if playable != ["Thundering Penance"]:
		return "Only active character's talent should be playable, got %s" % str(playable)
	return ""


static func _test_fischl_stellar_predator() -> String:
	var s := _start()
	s.players[0].active = 1
	_give(s, 0, ["Stellar Predator"])
	_play_card(s, "Stellar Predator", 1)
	TCGRulesEngine.apply_action(s, TCGGameState.ActionData.new("end_round", 1))
	TCGRulesEngine.apply_action(s, _find_skill_action(s, 0))
	if s.players[1].characters[0].hp != 5 or s.players[1].characters[0].aura != CardDataSystem.ELECTRO:
		return "Expected Oz follow-up after normal attack (HP 5, Electro aura)"
	return ""


static func _test_gamblers_earrings() -> String:
	var s := _start()
	_give(s, 0, ["Gambler's Earrings"])
	_play_card(s, "Gambler's Earrings", 0)
	s.players[0].dice = []
	s.players[1].characters[0].hp = 1
	_hit(s, 0, 5, CardDataSystem.PHYSICAL, 1)
	_hit(s, 1, 1, CardDataSystem.PHYSICAL, 1)
	if s.players[0].dice.count(CardDataSystem.OMNI) != 2:
		return "Gambler's Earrings should grant 2 Omni dice once per round"
	return ""


static func _test_support_end_phase() -> String:
	var s := _start()
	_give(s, 0, ["Liyue Harbor Wharf", "Wangshu Inn"])
	s.players[0].characters[1].hp = 4
	_play_card(s, "Liyue Harbor Wharf")
	_play_card(s, "Wangshu Inn")
	var deck_before: int = s.players[0].deck.size()
	TCGRulesEngine.apply_action(s, TCGGameState.ActionData.new("end_round", 0))
	TCGRulesEngine.apply_action(s, TCGGameState.ActionData.new("end_round", 1))
	if s.players[0].characters[1].hp != 6:
		return "Wangshu Inn should heal most injured character by 2"
	if s.players[0].deck.size() != deck_before - 4:
		return "Liyue Harbor Wharf + End Phase should draw 4 cards total"
	return ""


static func _test_paimon_action_start() -> String:
	var s := _start()
	_give(s, 0, ["Paimon"])
	_play_card(s, "Paimon")
	TCGRulesEngine.apply_action(s, TCGGameState.ActionData.new("end_round", 0))
	TCGRulesEngine.apply_action(s, TCGGameState.ActionData.new("end_round", 1))
	while s.phase != "action":
		TCGRulesEngine.apply_action(s, TCGRulesEngine.legal_actions(s)[0])
	if s.players[0].dice.size() != 10 or s.players[0].dice.count(CardDataSystem.OMNI) < 2:
		return "Paimon should grant 2 Omni dice at Action Phase start (10 dice total)"
	return ""


static func _test_changing_shifts_and_leave_it() -> String:
	var s := _start()
	_give(s, 0, ["Changing Shifts", "Leave It to Me!"])
	_play_card(s, "Changing Shifts")
	_play_card(s, "Leave It to Me!")
	var n_dice: int = s.players[0].dice.size()
	for a in TCGRulesEngine.legal_actions(s):
		if a.type == "switch":
			TCGRulesEngine.apply_action(s, a)
			break
	if s.players[0].dice.size() != n_dice or s.current != 0:
		return "Switch with Changing Shifts + Leave It to Me! should be free and fast"
	return ""


static func _test_resonance_and_reflection() -> String:
	var s := _start()
	_give(s, 0, ["Elemental Resonance: Woven Thunder"])
	_play_card(s, "Elemental Resonance: Woven Thunder")
	if s.players[0].characters[0].energy != 1:
		return "Woven Thunder should grant 1 Energy"
	TCGEffectContext.new(s, 1).combat_status("Reflection")
	_hit(s, 0, 3, CardDataSystem.PHYSICAL, 1)
	if s.players[1].characters[0].hp != 8:
		return "Reflection should reduce damage by 1 (HP 8)"
	_hit(s, 0, 3, CardDataSystem.PHYSICAL, 1)
	if s.players[1].characters[0].hp != 5:
		return "Reflection should be spent after 1 hit"
	return ""


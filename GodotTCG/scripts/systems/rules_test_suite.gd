class_name TCGRulesTestSuite
extends RefCounted
## RulesTestSuite
## Comprehensive parity test suite porting all test cases from Python
## `tests/test_engine.py` and `tests/test_m3.py` to GDScript.


static func _start(
	c0: Array = ["Electro Ranger", "Pyro Vanguard", "Cryo Knight"],
	c1: Array = ["Cryo Knight", "Hydro Cleric", "Geo Guardian"],
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
		["test_buff_status_and_targeted_heal", Callable(TCGRulesTestSuite, "_test_summon_end_phase")],
		["test_defeat_forces_choice_and_win_detection", Callable(TCGRulesTestSuite, "_test_defeat_and_win")],
		["test_attack_boost_increases_skill_damage", Callable(TCGRulesTestSuite, "_test_pyro_infusion")],
		["test_guard_stance_reduces_big_hits_twice", Callable(TCGRulesTestSuite, "_test_rain_sword")],
		["test_clone_is_independent_and_deterministic", Callable(TCGRulesTestSuite, "_test_clone_and_determinism")],
		["test_engine_announces_phases_and_rounds", Callable(TCGRulesTestSuite, "_test_phase_and_round_events")],
		["test_presets_are_legal_decks", Callable(TCGRulesTestSuite, "_test_presets_legal")],
		["test_validation_catches_each_rule", Callable(TCGRulesTestSuite, "_test_deck_validation")],
		["test_autofill_keeps_partial_and_rejects_illegal", Callable(TCGRulesTestSuite, "_test_autofill_csp")],
		["test_share_code_roundtrip", Callable(TCGRulesTestSuite, "_test_share_code_roundtrip")],
		["test_power_boost_applies_next_attack_and_spends_usage", Callable(TCGRulesTestSuite, "_test_weapon_damage")],
		["test_defeat_clears_character_statuses", Callable(TCGRulesTestSuite, "_test_weapon_replace_and_defeat")],
		["test_battle_cry_and_skill_boost_stack_round_buffs", Callable(TCGRulesTestSuite, "_test_talent_equip_and_skill")],
		["test_heal_cards_targeted_and_most_injured", Callable(TCGRulesTestSuite, "_test_talent_requires_active")],
		["test_energy_charge_and_draw_events", Callable(TCGRulesTestSuite, "_test_fischl_stellar_predator")],
		["test_shield_cards_block_incoming_damage", Callable(TCGRulesTestSuite, "_test_gamblers_earrings")],
		["test_hydro_cleric_heals_most_injured_ally", Callable(TCGRulesTestSuite, "_test_support_end_phase")],
		["test_geo_guardian_shields_and_petrifies", Callable(TCGRulesTestSuite, "_test_paimon_action_start")],
		["test_anemo_scout_skill_forces_switch", Callable(TCGRulesTestSuite, "_test_changing_shifts_and_leave_it")],
		["test_quick_rally_zero_cost_draw_and_status_reduce", Callable(TCGRulesTestSuite, "_test_resonance_and_reflection")],
		["test_preview_skill_and_card_no_mutation", Callable(TCGRulesTestSuite, "_test_preview_skill_and_card_no_mutation")],
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
	var max_e: int = s.players[0].characters[0].get_defn().max_energy
	s.players[0].characters[0].energy = max_e
	var burst_act := _find_skill_action(s, 2)
	if burst_act == null:
		return "Burst should be legal at %d energy" % max_e
	TCGRulesEngine.apply_action(s, burst_act)
	if s.players[0].characters[0].energy != 0:
		return "Energy should be 0 after burst"
	var hps := [s.players[1].characters[0].hp, s.players[1].characters[1].hp, s.players[1].characters[2].hp]
	if hps != [6, 8, 8]:
		return "Expected foe HPs [6, 8, 8], got %s" % str(hps)
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
	s.players[1].combat.append(TCGPlayerSystem.StatusInstance.new("Shield +2", -1, -1, 2))
	s.players[1].characters[0].aura = CardDataSystem.PYRO
	_hit(s, 0, 2, CardDataSystem.PIERCING)
	if s.players[1].characters[0].hp != 8 or s.players[1].characters[0].aura != CardDataSystem.PYRO:
		return "Piercing should ignore shields and auras"
	return ""


static func _test_summon_end_phase() -> String:
	var s := _start()
	_give(s, 0, ["Power Boost", "Major Heal"])
	s.players[0].characters[1].hp = 7
	_play_card(s, "Major Heal", 1)
	if s.players[0].characters[1].hp != 9 or s.current != 0:
		return "Major Heal should heal char 1 from 7 to 9 as a Fast Action"
	_play_card(s, "Power Boost")
	if TCGRulesEngine.find_status(s.players[0].combat, "Next Attack +2") == null:
		return "Power Boost should attach Next Attack +2 status"
	TCGRulesEngine.apply_action(s, _find_skill_action(s, 0))
	if s.players[1].characters[0].hp != 6 or TCGRulesEngine.find_status(s.players[0].combat, "Next Attack +2") != null:
		return "Power Boost should deal +2 Normal Attack DMG (HP 6) and consume Next Attack +2"
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
	_give(s, 0, ["Battle Cry"])
	_play_card(s, "Battle Cry")
	TCGRulesEngine.apply_action(s, _find_skill_action(s, 1))
	if s.players[1].characters[0].hp != 6:
		return "Attack +1 should add +1 DMG to Shock Arrow (HP 6), got %d" % s.players[1].characters[0].hp
	TCGRulesEngine.apply_action(s, TCGGameState.ActionData.new("end_round", 1))
	TCGRulesEngine.apply_action(s, TCGGameState.ActionData.new("end_round", 0))
	if TCGRulesEngine.find_status(s.players[0].combat, "Attack +1") != null:
		return "Attack +1 should expire at End Phase"
	return ""


static func _test_rain_sword() -> String:
	var s := _start()
	TCGRulesEngine.add_status(s.players[0].combat, "Guard Stance")
	_hit(s, 0, 3, CardDataSystem.PHYSICAL, 0)
	_hit(s, 0, 3, CardDataSystem.PHYSICAL, 0)
	_hit(s, 0, 3, CardDataSystem.PHYSICAL, 0)
	if s.players[0].characters[0].hp != 3 or not s.players[0].combat.is_empty():
		return "Guard Stance should reduce two hits by 1 each (HP 3) and expire"
	return ""


static func _test_clone_and_determinism() -> String:
	var s := _start()
	var c := s.clone()
	TCGRulesEngine.apply_action(c, _find_skill_action(c, 0))
	if s.players[1].characters[0].hp != 10 or c.players[1].characters[0].hp >= 10:
		return "Cloned state mutation leaked to original state"

	# Determinism check with identical seed
	var g1 := TCGRulesEngine.new_game(["Electro Ranger", "Hydro Cleric", "Geo Guardian"], CardDataSystem.starter_deck(), ["Pyro Vanguard", "Anemo Scout", "Cryo Knight"], CardDataSystem.starter_deck(), 42)
	var g2 := TCGRulesEngine.new_game(["Electro Ranger", "Hydro Cleric", "Geo Guardian"], CardDataSystem.starter_deck(), ["Pyro Vanguard", "Anemo Scout", "Cryo Knight"], CardDataSystem.starter_deck(), 42)
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
	if presets.is_empty() or presets.size() != CardDataSystem.preset_defs.size():
		return "Expected %d presets, got %d" % [CardDataSystem.preset_defs.size(), presets.size()]
	for name in presets.keys():
		var pair: Array = presets[name]
		var errs := TCGDeckSystem.validate_deck(pair[0], pair[1])
		if not errs.is_empty():
			return "Preset '%s' failed validation: %s" % [name, str(errs)]
	return ""


static func _test_deck_validation() -> String:
	var chars := ["Pyro Vanguard", "Electro Ranger", "Cryo Knight"]
	var good: Array[String] = TCGDeckSystem.autofill(chars)
	if not TCGDeckSystem.validate_deck(chars, good).is_empty():
		return "autofill deck should be valid"
	var short_deck := good.slice(0, TCGDeckSystem.DECK_SIZE - 1)
	if TCGDeckSystem.validate_deck(chars, short_deck).is_empty():
		return "%d-card deck should fail validation" % (TCGDeckSystem.DECK_SIZE - 1)
	var too_many := good.duplicate()
	for idx in range(TCGDeckSystem.MAX_COPIES + 1):
		too_many[idx] = "Power Boost"
	if TCGDeckSystem.validate_deck(chars, too_many).is_empty():
		return "Exceeding MAX_COPIES should fail validation"
	if TCGDeckSystem.validate_deck(["UnknownHero", "Electro Ranger", "Cryo Knight"], good).is_empty():
		return "Unknown character should fail validation"
	return ""


static func _test_autofill_csp() -> String:
	var chars := ["Hydro Cleric", "Anemo Scout", "Geo Guardian"]
	var partial := ["Power Boost", "Power Boost", "Tactical Draw"]
	var a = TCGDeckSystem.autofill(chars, partial)
	var b = TCGDeckSystem.autofill(chars, partial)
	if a == null or a != b or not TCGDeckSystem.validate_deck(chars, a).is_empty():
		return "autofill should be deterministic and produce a valid %d-card deck" % TCGDeckSystem.DECK_SIZE
	if TCGDeckSystem.autofill(["Pyro Vanguard", "Electro Ranger", "Cryo Knight"], ["Nonexistent Card"]) != null:
		return "autofill should return null for illegal partial deck"
	var over_cap: Array[String] = []
	for _i in range(TCGDeckSystem.MAX_COPIES + 1):
		over_cap.append("Power Boost")
	if TCGDeckSystem.autofill(["Pyro Vanguard", "Electro Ranger", "Cryo Knight"], over_cap) != null:
		return "autofill should return null when exceeding MAX_COPIES in partial deck"
	return ""


static func _test_share_code_roundtrip() -> String:
	var presets := TCGDeckSystem.preset_decks()
	var key0: String = str(presets.keys()[0])
	var p0: Array = presets[key0]
	var code := TCGDeckSystem.encode(p0[0], p0[1])
	var decoded := TCGDeckSystem.decode(code)
	var sorted_cards: Array[String] = (p0[1] as Array[String]).duplicate()
	sorted_cards.sort()
	if decoded.size() != 2 or decoded[0] != p0[0] or decoded[1] != sorted_cards:
		return "Share code roundtrip mismatch"
	return ""


static func _test_weapon_damage() -> String:
	var s := _start()
	_give(s, 0, ["Power Boost"])
	_play_card(s, "Power Boost")
	if s.current != 0:
		return "Power Boost should be a Fast Action"
	TCGRulesEngine.apply_action(s, _find_skill_action(s, 0))
	if s.players[1].characters[0].hp != 6:
		return "Expected Power Boost to add +2 DMG to first Normal Attack (HP 6), got %d" % s.players[1].characters[0].hp
	TCGRulesEngine.apply_action(s, TCGGameState.ActionData.new("end_round", 1))
	TCGRulesEngine.apply_action(s, _find_skill_action(s, 0))
	if s.players[1].characters[0].hp != 4:
		return "Second Normal Attack should deal base 2 DMG (HP 4), got %d" % s.players[1].characters[0].hp
	return ""


static func _test_weapon_replace_and_defeat() -> String:
	var s := _start()
	TCGRulesEngine.add_status(s.players[0].characters[0].statuses, "Frozen")
	_hit(s, 0, 99, CardDataSystem.PHYSICAL, 0)
	if not s.players[0].characters[0].defeated or not s.players[0].characters[0].statuses.is_empty():
		return "Defeat should clear character statuses"
	return ""


static func _test_talent_equip_and_skill() -> String:
	var s := _start()
	_give(s, 0, ["Battle Cry"])
	_play_card(s, "Battle Cry")
	TCGRulesEngine.add_status(s.players[0].combat, "Skill Boost +2")
	TCGRulesEngine.apply_action(s, _find_skill_action(s, 1))
	if s.players[1].characters[0].hp != 4:
		return "Battle Cry (+1) + Skill Boost +2 should deal 6 Shock Arrow DMG (HP 4), got %d" % s.players[1].characters[0].hp
	return ""


static func _test_talent_requires_active() -> String:
	var s := _start()
	s.players[0].characters[0].hp = 9
	s.players[0].characters[2].hp = 4
	_give(s, 0, ["Minor Heal", "Team Tonic"])
	_play_card(s, "Minor Heal", 0)
	if s.players[0].characters[0].hp != 10:
		return "Minor Heal should heal targeted char 0 from 9 to 10"
	_play_card(s, "Team Tonic")
	if s.players[0].characters[2].hp != 7:
		return "Team Tonic should heal most injured char 2 from 4 to 7, got %d" % s.players[0].characters[2].hp
	return ""


static func _test_fischl_stellar_predator() -> String:
	var s := _start()
	_give(s, 0, ["Energy Charge", "Tactical Draw"])
	var deck_before: int = s.players[0].deck.size()
	_play_card(s, "Energy Charge")
	if s.players[0].characters[0].energy != 1:
		return "Energy Charge should grant 1 Energy"
	_play_card(s, "Tactical Draw")
	if s.players[0].deck.size() != deck_before - 2 or s.players[0].hand.size() != 2:
		return "Tactical Draw should draw 2 cards from deck"
	return ""


static func _test_gamblers_earrings() -> String:
	var s := _start()
	_give(s, 0, ["Iron Guard", "Fortify"])
	_play_card(s, "Iron Guard")
	_hit(s, 0, 5, CardDataSystem.PHYSICAL, 0)
	if s.players[0].characters[0].hp != 7 or TCGRulesEngine.find_status(s.players[0].combat, "Shield +2") != null:
		return "Iron Guard (Shield +2) should block 2 of 5 DMG (HP 7) and expire"
	_play_card(s, "Fortify")
	_hit(s, 0, 2, CardDataSystem.PHYSICAL, 0)
	if s.players[0].characters[0].hp != 7:
		return "Fortify (Shield +3) should fully block 2 DMG"
	return ""


static func _test_support_end_phase() -> String:
	var s := _start(["Hydro Cleric", "Pyro Vanguard", "Cryo Knight"], ["Pyro Vanguard", "Cryo Knight", "Geo Guardian"])
	s.players[0].characters[2].hp = 5
	TCGRulesEngine.apply_action(s, _find_skill_action(s, 1))
	if s.players[1].characters[0].hp != 8 or s.players[0].characters[2].hp != 7:
		return "Hydro Cleric Refreshing Mist should deal 2 Hydro DMG and heal most injured ally by 2"
	return ""


static func _test_paimon_action_start() -> String:
	var s := _start(["Geo Guardian", "Pyro Vanguard", "Cryo Knight"], ["Pyro Vanguard", "Cryo Knight", "Hydro Cleric"])
	s.players[0].characters[0].energy = 2
	TCGRulesEngine.apply_action(s, _find_skill_action(s, 1))
	if s.players[1].characters[0].hp != 8 or TCGRulesEngine.find_status(s.players[0].combat, "Shield +2") == null:
		return "Geo Guardian Aegis Slam should deal 2 DMG and grant Shield +2"
	TCGRulesEngine.apply_action(s, TCGGameState.ActionData.new("end_round", 1))
	TCGRulesEngine.apply_action(s, _find_skill_action(s, 2))
	if s.players[1].characters[0].hp != 5 or not TCGRulesEngine.has_status(s.players[1].characters[0], "Petrified"):
		return "Geo Guardian Earthen Bastion (Ult) should deal 3 Geo DMG and Petrify target"
	return ""


static func _test_changing_shifts_and_leave_it() -> String:
	var s := _start(["Anemo Scout", "Pyro Vanguard", "Cryo Knight"], ["Pyro Vanguard", "Cryo Knight", "Hydro Cleric"])
	TCGRulesEngine.apply_action(s, _find_skill_action(s, 1))
	if s.players[1].characters[0].hp != 7 or s.players[1].active != 1:
		return "Anemo Scout Cyclone Kick should deal 3 Anemo DMG and force opponent switch to index 1"
	return ""


static func _test_resonance_and_reflection() -> String:
	var s := _start()
	_give(s, 0, ["Quick Rally"])
	var dice_before: int = s.players[0].dice.size()
	var deck_before: int = s.players[0].deck.size()
	_play_card(s, "Quick Rally")
	if s.players[0].dice.size() != dice_before or s.players[0].deck.size() != deck_before - 1 or s.current != 0:
		return "Quick Rally should cost 0 dice, draw 1 card, and keep turn"
	TCGRulesEngine.add_status(s.players[0].combat, "Normal Boost +1")
	TCGRulesEngine.apply_action(s, _find_skill_action(s, 0))
	if s.players[1].characters[0].hp != 7:
		return "Normal Boost +1 should boost Volt Shot from 2 to 3 DMG (HP 7)"
	return ""


static func _test_preview_skill_and_card_no_mutation() -> String:
	var s := _start(["Electro Ranger", "Pyro Vanguard", "Cryo Knight"], ["Cryo Knight", "Hydro Cleric", "Geo Guardian"])
	# 1. Normal Attack preview (2 Physical DMG)
	var prev_na := TCGRulesEngine.preview_skill(s, 0, 0)
	if not bool(prev_na.get("ok", false)):
		return "preview_skill(0) failed"
	var f0_na: Dictionary = prev_na.get("foe_chars", {}).get(0, {})
	if int(f0_na.get("total_dmg", 0)) != 2 or int(f0_na.get("hp_after", -1)) != 8 or s.players[1].characters[0].hp != 10:
		return "Normal Attack preview mismatch or mutated state: " + str(f0_na)

	# 2. Overloaded + Crystallize Shield absorption + forced switch preview
	s.players[1].characters[0].aura = CardDataSystem.PYRO
	TCGRulesEngine.add_status(s.players[1].combat, "Crystallize Shield")
	var prev_sk := TCGRulesEngine.preview_skill(s, 0, 1)
	var f0_ov: Dictionary = prev_sk.get("foe_chars", {}).get(0, {})
	var f1_ov: Dictionary = prev_sk.get("foe_chars", {}).get(1, {})
	if int(f0_ov.get("total_dmg", 0)) != 5 or int(f0_ov.get("shield_dmg", 0)) != 1 or int(f0_ov.get("hp_after", -1)) != 6:
		return "Overloaded + shield preview mismatch: " + str(f0_ov)
	if String(f0_ov.get("reaction", "")) != "Overloaded" or not bool(f0_ov.get("forced_switch_out", false)) or not bool(f1_ov.get("forced_switch_in", false)):
		return "Overloaded forced-switch flags missing: " + str(f0_ov) + " / " + str(f1_ov)
	# Ensure live state completely untouched
	if s.players[1].characters[0].hp != 10 or s.players[1].characters[0].aura != CardDataSystem.PYRO or s.players[1].active != 0 or s.players[1].combat.size() != 1:
		return "preview_skill mutated live game state!"

	# 3. Electro-Charged + standby Piercing damage + targeted Heal card preview
	s.players[1].combat.clear()
	s.players[1].characters[0].aura = CardDataSystem.HYDRO
	var prev_ec := TCGRulesEngine.preview_skill(s, 0, 1)
	var f1_ec: Dictionary = prev_ec.get("foe_chars", {}).get(1, {})
	var f2_ec: Dictionary = prev_ec.get("foe_chars", {}).get(2, {})
	if String(prev_ec.get("foe_chars", {}).get(0, {}).get("reaction", "")) != "Electro-Charged":
		return "Expected Electro-Charged reaction in preview"
	if int(f1_ec.get("piercing_dmg", 0)) != 1 or int(f2_ec.get("piercing_dmg", 0)) != 1:
		return "Expected 1 Piercing DMG on standby foes for Electro-Charged"

	s.players[0].characters[1].hp = 6
	_give(s, 0, ["Major Heal"])
	var prev_card := TCGRulesEngine.preview_card(s, 0, 0, 1)
	var own1_heal: int = int(prev_card.get("own_chars", {}).get(1, {}).get("heal", 0))
	if not bool(prev_card.get("ok", false)) or own1_heal != 2 or s.players[0].characters[1].hp != 6 or s.players[0].hand.size() != 1:
		return "Heal card preview_card mismatch or mutated state: " + str(prev_card)
	return ""



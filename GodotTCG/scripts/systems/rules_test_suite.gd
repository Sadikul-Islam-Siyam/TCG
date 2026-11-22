class_name TCGRulesTestSuite
extends RefCounted
## RulesTestSuite
## Comprehensive rules & mechanics test suite verifying:
## - Dice rolling (no Cryo, 1/8 Omni, 7/40 each for Hydro/Pyro/Electro/Anemo/Geo)
## - Exact, Unaligned, and Same-Type ("2 dice of the same type") dice payment
## - All 6 Avatar characters (Aang, Zuko, Katara, Azula, Toph, Iroh) & Ultimates
## - All 15 Action Cards (6 Character Equipment + 9 Utility cards)
## - Elemental reactions, shields, piercing, stun/freeze, deck validation, and previews.


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


static func _hit(s: TCGGameState, ti: int, amount: int, dtype: String, tp: int = 1) -> void:
	s.events = []
	TCGRulesEngine.deal_damage(s, 1 - tp, tp, ti, amount, dtype, "effect", "")


static func _give(s: TCGGameState, p: int, cards: Array) -> void:
	var h: Array[String] = []
	for c in cards:
		h.append(str(c))
	s.players[p].hand = h


static func _play_card(s: TCGGameState, card_name: String, target: int = -1, p: int = 0, ids: Array = []) -> void:
	var pl := s.players[p]
	for a in TCGRulesEngine.legal_actions(s):
		if a.type == "card" and pl.hand[a.index] == card_name and a.target == target:
			var act := a if ids.is_empty() else a.with_ids(ids)
			TCGRulesEngine.apply_action(s, act)
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
		["test_same_type_dice_payment", Callable(TCGRulesTestSuite, "_test_same_type_dice_payment")],
		["test_omni_rate_no_cryo_and_five_elements_equal", Callable(TCGRulesTestSuite, "_test_omni_rate")],
		["test_setup_reaches_action_phase", Callable(TCGRulesTestSuite, "_test_setup_reaches_action_phase")],
		["test_skill_deals_damage_applies_aura_and_energy", Callable(TCGRulesTestSuite, "_test_skill_damage_aura_energy")],
		["test_fast_action_keeps_turn_and_tuning_changes_die", Callable(TCGRulesTestSuite, "_test_fast_action_tuning")],
		["test_burst_needs_full_energy_zuko_splash", Callable(TCGRulesTestSuite, "_test_burst_needs_full_energy")],
		["test_illegal_actions_are_rejected", Callable(TCGRulesTestSuite, "_test_illegal_actions_rejected")],
		["test_end_round_flow_and_first_player", Callable(TCGRulesTestSuite, "_test_end_round_flow")],
		["test_switch_costs_one_die_and_passes_turn", Callable(TCGRulesTestSuite, "_test_switch_costs_one_die")],
		["test_all_reaction_bonuses_and_aura_consumed", Callable(TCGRulesTestSuite, "_test_all_reactions")],
		["test_same_element_keeps_aura_no_reaction", Callable(TCGRulesTestSuite, "_test_same_element_keeps_aura")],
		["test_overloaded_forces_switch", Callable(TCGRulesTestSuite, "_test_overloaded_forces_switch")],
		["test_electro_charged_pierces_standby_characters", Callable(TCGRulesTestSuite, "_test_electro_charged_pierces")],
		["test_frozen_blocks_skills_and_boosts_physical_then_thaws", Callable(TCGRulesTestSuite, "_test_frozen_shatter")],
		["test_swirl_spreads_element_to_other_characters", Callable(TCGRulesTestSuite, "_test_swirl_spreads")],
		["test_crystallize_gives_shield_to_attacker_side", Callable(TCGRulesTestSuite, "_test_crystallize_shield")],
		["test_piercing_ignores_shields_and_auras", Callable(TCGRulesTestSuite, "_test_piercing_ignores_shields")],
		["test_defeat_forces_choice_and_win_detection", Callable(TCGRulesTestSuite, "_test_defeat_and_win")],
		["test_clone_is_independent_and_deterministic", Callable(TCGRulesTestSuite, "_test_clone_and_determinism")],
		["test_engine_announces_phases_and_rounds", Callable(TCGRulesTestSuite, "_test_phase_and_round_events")],
		["test_presets_are_legal_decks", Callable(TCGRulesTestSuite, "_test_presets_legal")],
		["test_validation_catches_each_rule_including_equipment", Callable(TCGRulesTestSuite, "_test_deck_validation")],
		["test_autofill_keeps_partial_and_rejects_illegal", Callable(TCGRulesTestSuite, "_test_autofill_csp")],
		["test_share_code_roundtrip", Callable(TCGRulesTestSuite, "_test_share_code_roundtrip")],
		["test_aang_ult_clears_self_aura", Callable(TCGRulesTestSuite, "_test_aang_ult")],
		["test_zuko_ult_active_reaction_and_no_bench_reaction", Callable(TCGRulesTestSuite, "_test_zuko_ult_reactions")],
		["test_katara_ult_and_spirit_water_ult_only_heal", Callable(TCGRulesTestSuite, "_test_katara_ult_and_spirit_water")],
		["test_azula_ult_stuns_target_for_round", Callable(TCGRulesTestSuite, "_test_azula_ult_stun")],
		["test_toph_ult_grants_shield_plus_2", Callable(TCGRulesTestSuite, "_test_toph_ult_shield")],
		["test_iroh_ult_teamwide_plus_1_dmg_for_round", Callable(TCGRulesTestSuite, "_test_iroh_ult_team_buff")],
		["test_equipment_damage_bonus_and_defeat_clear", Callable(TCGRulesTestSuite, "_test_equipment_damage_and_defeat")],
		["test_utility_reroll_elemental_dice_and_omni_conversion", Callable(TCGRulesTestSuite, "_test_utility_dice_cards")],
		["test_utility_draw_and_swap_cards", Callable(TCGRulesTestSuite, "_test_utility_draw_and_swap")],
		["test_utility_dice_carryover_to_next_round_omni", Callable(TCGRulesTestSuite, "_test_utility_dice_carryover")],
		["test_utility_healing_active_dual_and_party", Callable(TCGRulesTestSuite, "_test_utility_healing_cards")],
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
# Dice & Core Flow Tests
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


static func _test_same_type_dice_payment() -> String:
	var same_cost := CardDataSystem.CostData.new("", 2, 0)
	var mixed: Array[String] = [CardDataSystem.PYRO, CardDataSystem.HYDRO, CardDataSystem.GEO]
	if TCGDiceSystem.payment_ok(mixed, same_cost, [0, 1]):
		return "2 Same cost must reject Pyro + Hydro"
	if TCGDiceSystem.auto_pay(mixed, same_cost) != null:
		return "auto_pay should return null when no two dice share a type (and no Omni)"
	var pair: Array[String] = [CardDataSystem.PYRO, CardDataSystem.GEO, CardDataSystem.GEO]
	var pay = TCGDiceSystem.auto_pay(pair, same_cost)
	if pay == null or not TCGDiceSystem.payment_ok(pair, same_cost, pay):
		return "auto_pay failed for 2 Same with [Pyro, Geo, Geo]"
	var omni_pair: Array[String] = [CardDataSystem.PYRO, CardDataSystem.OMNI]
	if not TCGDiceSystem.payment_ok(omni_pair, same_cost, [0, 1]):
		return "2 Same cost should allow 1 element + 1 Omni"
	return ""


static func _test_omni_rate() -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var total: int = 12000
	var rolls := TCGDiceSystem.roll(rng, total)
	var counts: Dictionary = {}
	for f in rolls:
		counts[f] = int(counts.get(f, 0)) + 1
	if int(counts.get(CardDataSystem.CRYO, 0)) != 0:
		return "Cryo dice must never be rolled, got %d" % int(counts.get(CardDataSystem.CRYO, 0))
	var omni_rate: float = float(counts.get(CardDataSystem.OMNI, 0)) / float(total)
	if absf(omni_rate - 0.125) > 0.015:
		return "Omni rate out of tolerance: %f" % omni_rate
	for el in [CardDataSystem.HYDRO, CardDataSystem.PYRO, CardDataSystem.ELECTRO, CardDataSystem.ANEMO, CardDataSystem.GEO]:
		var el_rate: float = float(counts.get(el, 0)) / float(total)
		if absf(el_rate - (7.0 / 40.0)) > 0.015:
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
	# Zuko Fire Whip: 3 Pyro DMG, applies Pyro aura, +1 Energy (capped at max_energy=1)
	TCGRulesEngine.apply_action(s, _find_skill_action(s, 1))
	var foe := s.players[1].characters[0]
	if foe.hp != 7 or foe.aura != CardDataSystem.PYRO:
		return "Expected foe hp=7 aura=Pyro, got hp=%d aura=%s" % [foe.hp, foe.aura]
	if s.players[0].characters[0].energy != 1 or s.current != 1:
		return "Expected energy=1 and turn passed to P1"
	return ""


static func _test_fast_action_tuning() -> String:
	var s := _start()
	s.players[0].dice = [CardDataSystem.HYDRO, CardDataSystem.OMNI]
	var tune_act: TCGGameState.ActionData = null
	for a in TCGRulesEngine.legal_actions(s):
		if a.type == "tune":
			tune_act = a
			break
	if tune_act == null:
		return "Expected a legal tune action"
	TCGRulesEngine.apply_action(s, tune_act)
	if s.current != 0 or s.players[0].dice[0] != CardDataSystem.PYRO:
		return "Expected fast action to keep turn and convert die to Pyro (Zuko's element)"
	return ""


static func _test_burst_needs_full_energy() -> String:
	var s := _start()
	if _find_skill_action(s, 2) != null:
		return "Burst should not be legal at 0 energy"
	var max_e: int = s.players[0].characters[0].get_defn().max_energy
	if max_e != 1:
		return "Expected max_energy=1, got %d" % max_e
	s.players[0].characters[0].energy = max_e
	var burst_act := _find_skill_action(s, 2)
	if burst_act == null:
		return "Burst should be legal at %d energy" % max_e
	TCGRulesEngine.apply_action(s, burst_act)
	if s.players[0].characters[0].energy != 0:
		return "Energy should be 0 after burst"
	# Zuko Dragon's Roar: 3 Pyro to active + 1 Piercing to standby
	var hps := [s.players[1].characters[0].hp, s.players[1].characters[1].hp, s.players[1].characters[2].hp]
	if hps != [7, 9, 9]:
		return "Expected foe HPs [7, 9, 9], got %s" % str(hps)
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


# ------------------------------------------------------------------------------
# Elemental Reactions
# ------------------------------------------------------------------------------
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


static func _test_electro_charged_pierces() -> String:
	var s := _start()
	s.players[1].characters[0].aura = CardDataSystem.HYDRO
	_hit(s, 0, 1, CardDataSystem.ELECTRO)
	var hps := [s.players[1].characters[0].hp, s.players[1].characters[1].hp, s.players[1].characters[2].hp]
	if hps != [8, 9, 9]:
		return "Expected Electro-Charged HPs [8, 9, 9], got %s" % str(hps)
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
	# Generic non-Aang Swirl deals 1 damage to standby enemies
	var s := _start()
	s.players[1].characters[0].aura = CardDataSystem.PYRO
	_hit(s, 0, 1, CardDataSystem.ANEMO)
	var hps := [s.players[1].characters[0].hp, s.players[1].characters[1].hp, s.players[1].characters[2].hp]
	if hps != [9, 9, 9]:
		return "Expected generic Swirl HPs [9, 9, 9], got %s" % str(hps)

	# Aang's Swirl deals 2 damage to standby enemies and spreads aura
	var sa := _start(["Aang", "Katara", "Toph"], ["Zuko", "Azula", "Iroh"])
	sa.players[1].characters[0].aura = CardDataSystem.PYRO
	_hit(sa, 0, 1, CardDataSystem.ANEMO)
	var hps_a := [sa.players[1].characters[0].hp, sa.players[1].characters[1].hp, sa.players[1].characters[2].hp]
	if hps_a != [9, 8, 8]:
		return "Expected Aang Swirl HPs [9, 8, 8], got %s" % str(hps_a)
	if sa.players[1].characters[1].aura != CardDataSystem.PYRO or not sa.players[1].characters[0].aura.is_empty():
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


static func _test_clone_and_determinism() -> String:
	var s := _start()
	var c := s.clone()
	TCGRulesEngine.apply_action(c, _find_skill_action(c, 0))
	if s.players[1].characters[0].hp != 10 or c.players[1].characters[0].hp >= 10:
		return "Cloned state mutation leaked to original state"

	var c0 := ["Aang", "Katara", "Toph"]
	var c1 := ["Zuko", "Azula", "Iroh"]
	var g1 := TCGRulesEngine.new_game(c0, CardDataSystem.starter_deck(c0), c1, CardDataSystem.starter_deck(c1), 42)
	var g2 := TCGRulesEngine.new_game(c0, CardDataSystem.starter_deck(c0), c1, CardDataSystem.starter_deck(c1), 42)
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


# ------------------------------------------------------------------------------
# Deck System & Validation
# ------------------------------------------------------------------------------
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
	var chars := ["Aang", "Katara", "Toph"]
	var good: Array[String] = TCGDeckSystem.autofill(chars)
	if not TCGDeckSystem.validate_deck(chars, good).is_empty():
		return "autofill deck should be valid"
	var short_deck := good.slice(0, TCGDeckSystem.DECK_SIZE - 1)
	if TCGDeckSystem.validate_deck(chars, short_deck).is_empty():
		return "%d-card deck should fail validation" % (TCGDeckSystem.DECK_SIZE - 1)
	var too_many := good.duplicate()
	for idx in range(TCGDeckSystem.MAX_COPIES + 1):
		too_many[idx] = "Draw Cards"
	if TCGDeckSystem.validate_deck(chars, too_many).is_empty():
		return "Exceeding MAX_COPIES (2) should fail validation"
	var wrong_equip := good.duplicate()
	wrong_equip[0] = "Zuko's Dual Broadswords"
	if TCGDeckSystem.validate_deck(chars, wrong_equip).is_empty():
		return "Including Zuko's equipment without Zuko in roster must fail validation"
	if TCGDeckSystem.validate_deck(["UnknownHero", "Katara", "Toph"], good).is_empty():
		return "Unknown character should fail validation"
	return ""


static func _test_autofill_csp() -> String:
	var chars := ["Zuko", "Azula", "Iroh"]
	var partial := ["Zuko's Dual Broadswords", "Draw Cards", "Draw Cards"]
	var a = TCGDeckSystem.autofill(chars, partial)
	var b = TCGDeckSystem.autofill(chars, partial)
	if a == null or a != b or not TCGDeckSystem.validate_deck(chars, a).is_empty():
		return "autofill should be deterministic and produce a valid %d-card deck" % TCGDeckSystem.DECK_SIZE
	if TCGDeckSystem.autofill(chars, ["Nonexistent Card"]) != null:
		return "autofill should return null for illegal partial deck"
	var over_cap: Array[String] = []
	for _i in range(TCGDeckSystem.MAX_COPIES + 1):
		over_cap.append("Draw Cards")
	if TCGDeckSystem.autofill(chars, over_cap) != null:
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


# ------------------------------------------------------------------------------
# All 6 Avatar Character Ultimates & Equipment
# ------------------------------------------------------------------------------
static func _test_aang_ult() -> String:
	var s := _start(["Aang", "Katara", "Toph"], ["Zuko", "Azula", "Iroh"])
	s.players[0].characters[0].aura = CardDataSystem.PYRO
	s.players[0].characters[0].energy = 1
	var prev := TCGRulesEngine.preview_skill(s, 0, 2)
	var own0_prev: Dictionary = prev.get("own_chars", {}).get(0, {})
	if String(own0_prev.get("aura_cleared", "")) != CardDataSystem.PYRO:
		return "Aang Ult preview should report aura_cleared='Pyro', got %s" % str(own0_prev)
	TCGRulesEngine.apply_action(s, _find_skill_action(s, 2))
	if s.players[1].characters[0].hp != 6:
		return "Aang Ult should deal 4 Anemo DMG (HP 6), got %d" % s.players[1].characters[0].hp
	if not s.players[0].characters[0].aura.is_empty():
		return "Aang Ult should remove elemental aura from himself, still has '%s'" % s.players[0].characters[0].aura
	var has_cleanse_ev: bool = false
	for ev in s.events:
		if String(ev.get("kind", "")) == "cleanse" and String(ev.get("aura", "")) == CardDataSystem.PYRO:
			has_cleanse_ev = true
			break
	if not has_cleanse_ev:
		return "Aang Ult should emit 'cleanse' event when removing aura"
	return ""


static func _test_zuko_ult_reactions() -> String:
	var s := _start(["Zuko", "Azula", "Aang"], ["Katara", "Toph", "Iroh"])
	s.players[1].characters[0].aura = CardDataSystem.HYDRO   # Active CAN trigger Vaporize (+1 -> 4 DMG)
	s.players[1].characters[1].aura = CardDataSystem.HYDRO   # Standby takes 1 splash WITHOUT triggering reactions!
	s.players[0].characters[0].energy = 1
	TCGRulesEngine.apply_action(s, _find_skill_action(s, 2))
	if s.players[1].characters[0].hp != 6 or not s.players[1].characters[0].aura.is_empty():
		return "Zuko Ult should trigger Vaporize on active target (4 DMG -> HP 6, aura cleared)"
	if s.players[1].characters[1].hp != 9 or s.players[1].characters[1].aura != CardDataSystem.HYDRO:
		return "Zuko Ult splash should deal 1 non-reaction DMG to standby and preserve standby aura"
	if s.players[1].characters[2].hp != 9:
		return "Zuko Ult splash should deal 1 DMG to standby index 2"
	return ""


static func _test_katara_ult_and_spirit_water() -> String:
	var s := _start(["Katara", "Aang", "Toph"], ["Zuko", "Azula", "Iroh"])
	s.players[0].characters[0].hp = 4
	s.players[0].characters[1].hp = 5
	s.players[0].characters[2].hp = 6
	s.players[0].characters[0].energy = 1

	# 1. Without Spirit Water: Katara Ult deals 3 Hydro DMG and heals every living ally by 1 HP
	TCGRulesEngine.apply_action(s, _find_skill_action(s, 2))
	if s.players[1].characters[0].hp != 7:
		return "Katara Ult should deal 3 Hydro DMG (HP 7)"
	var hps1 := [s.players[0].characters[0].hp, s.players[0].characters[1].hp, s.players[0].characters[2].hp]
	if hps1 != [5, 6, 7]:
		return "Katara Ult without Spirit Water should heal all allies by 1 ([5, 6, 7]), got %s" % str(hps1)

	# 2. Equip Katara's Spirit Water -> Active Character Healing still heals ONLY 1 HP (Ult-only!)
	TCGRulesEngine.apply_action(s, TCGGameState.ActionData.new("end_round", 1))
	_give(s, 0, ["Katara's Spirit Water", "Active Character Healing"])
	_play_card(s, "Katara's Spirit Water", 0)
	_play_card(s, "Active Character Healing")
	if s.players[0].characters[0].hp != 6:
		return "Spirit Water must NOT boost non-Ult healing cards (expected Katara HP 6, got %d)" % s.players[0].characters[0].hp

	# 3. With Spirit Water equipped: Katara Ult heals 1 + 2 = 3 HP to every living ally!
	s.players[0].characters[0].energy = 1
	TCGRulesEngine.apply_action(s, _find_skill_action(s, 2))
	var hps2 := [s.players[0].characters[0].hp, s.players[0].characters[1].hp, s.players[0].characters[2].hp]
	if hps2 != [9, 9, 10]:
		return "Katara Ult with Spirit Water should heal all allies by 3 ([9, 9, 10]), got %s" % str(hps2)
	return ""


static func _test_azula_ult_stun() -> String:
	var s := _start(["Azula", "Zuko", "Iroh"], ["Katara", "Toph", "Aang"])
	s.players[0].characters[0].energy = 1
	TCGRulesEngine.apply_action(s, _find_skill_action(s, 2))
	var foe := s.players[1].characters[0]
	if foe.hp != 7 or not TCGRulesEngine.has_status(foe, "Stunned"):
		return "Azula Ult should deal 3 Electro DMG (HP 7) and apply Stunned"
	# On P1's turn, stunned Katara must have NO legal skill actions
	for a in TCGRulesEngine.legal_actions(s):
		if a.type == "skill":
			return "Stunned character must not have legal skill actions"
	# At End Phase, Stunned clears
	TCGRulesEngine.apply_action(s, TCGGameState.ActionData.new("end_round", 1))
	TCGRulesEngine.apply_action(s, TCGGameState.ActionData.new("end_round", 0))
	if TCGRulesEngine.has_status(foe, "Stunned"):
		return "Stunned should expire at End Phase"
	return ""


static func _test_toph_ult_shield() -> String:
	var s := _start(["Toph", "Aang", "Katara"], ["Zuko", "Azula", "Iroh"])
	s.players[0].characters[0].energy = 1
	TCGRulesEngine.apply_action(s, _find_skill_action(s, 2))
	if s.players[1].characters[0].hp != 7:
		return "Toph Ult should deal 3 Geo DMG (HP 7)"
	var sh := TCGRulesEngine.find_status(s.players[0].combat, "Shield +2")
	if sh == null or sh.shield != 2:
		return "Toph Ult should grant Shield +2"
	_hit(s, 0, 5, CardDataSystem.PHYSICAL, 0)
	if s.players[0].characters[0].hp != 7:
		return "Shield +2 should absorb 2 of 5 damage (HP 7), got %d" % s.players[0].characters[0].hp
	return ""


static func _test_iroh_ult_team_buff() -> String:
	var s := _start(["Iroh", "Zuko", "Azula"], ["Katara", "Toph", "Aang"])
	s.players[0].characters[0].energy = 1
	TCGRulesEngine.apply_action(s, _find_skill_action(s, 2))
	if s.players[1].characters[0].hp != 6:
		return "Iroh Ult should deal 4 Pyro DMG (HP 6), got %d" % s.players[1].characters[0].hp
	if TCGRulesEngine.find_status(s.players[0].combat, "Attack +1") == null:
		return "Iroh Ult should grant teamwide Attack +1 for the round"
	# Switch to Zuko and verify Zuko's Normal Attack (base 2) deals 3 DMG with teamwide buff
	TCGRulesEngine.apply_action(s, TCGGameState.ActionData.new("end_round", 1))
	s.players[0].active = 1
	TCGRulesEngine.apply_action(s, _find_skill_action(s, 0))
	if s.players[1].characters[0].hp != 3:
		return "Teamwide Attack +1 should boost Zuko's Normal Attack from 2 to 3 DMG (HP 3), got %d" % s.players[1].characters[0].hp
	TCGRulesEngine.apply_action(s, TCGGameState.ActionData.new("end_round", 0))
	if TCGRulesEngine.find_status(s.players[0].combat, "Attack +1") != null:
		return "Iroh's teamwide Attack +1 should expire at End Phase"
	return ""


static func _test_equipment_damage_and_defeat() -> String:
	var s := _start(["Zuko", "Azula", "Aang"], ["Katara", "Toph", "Iroh"])
	_give(s, 0, ["Zuko's Dual Broadswords"])
	# Must NOT be targetable on Azula (index 1)
	var cd := CardDataSystem.get_card_def("Zuko's Dual Broadswords")
	if TCGRulesEngine.card_targets(s.players[0], cd) != [0]:
		return "Zuko's Dual Broadswords should only target Zuko (index 0)"
	_play_card(s, "Zuko's Dual Broadswords", 0)
	if s.current != 0:
		return "Equipping should be a Fast Action"
	TCGRulesEngine.apply_action(s, _find_skill_action(s, 0))
	if s.players[1].characters[0].hp != 7:
		return "Broadswords should boost Zuko's Normal Attack from 2 to 3 DMG (HP 7), got %d" % s.players[1].characters[0].hp
	# Defeating Zuko clears character statuses
	_hit(s, 0, 99, CardDataSystem.PHYSICAL, 0)
	if not s.players[0].characters[0].defeated or not s.players[0].characters[0].statuses.is_empty():
		return "Defeat should clear equipped statuses"
	return ""


# ------------------------------------------------------------------------------
# All 9 Utility Cards
# ------------------------------------------------------------------------------
static func _test_utility_dice_cards() -> String:
	var s := _start(["Zuko", "Azula", "Aang"], ["Katara", "Toph", "Iroh"])
	_give(s, 0, ["Elemental Dice", "Reroll Dice", "Omni Conversion"])
	s.players[0].dice = [CardDataSystem.PYRO, CardDataSystem.HYDRO, CardDataSystem.GEO, CardDataSystem.ANEMO, CardDataSystem.OMNI]

	# 1. Elemental Dice (0 cost): adds 1 Pyro die (Zuko's element)
	_play_card(s, "Elemental Dice")
	if s.players[0].dice.size() != 6 or s.players[0].dice.count(CardDataSystem.PYRO) != 2:
		return "Elemental Dice should add 1 Pyro die without spending dice"

	# 2. Reroll Dice (0 cost): auto-rerolls only non-Pyro, non-Omni dice; keeps 2 Pyro + 1 Omni intact
	_play_card(s, "Reroll Dice")
	if s.players[0].dice.size() != 6 or s.players[0].dice.count(CardDataSystem.PYRO) < 2 or s.players[0].dice.count(CardDataSystem.OMNI) < 1:
		return "Reroll Dice must preserve matching Pyro and Omni dice"
	if s.players[0].dice.has(CardDataSystem.CRYO):
		return "Reroll Dice must never roll Cryo"

	# 3. Omni Conversion (1 Any cost): spends 1 die and converts up to 3 non-Omni dice into Omni
	s.players[0].dice = [CardDataSystem.HYDRO, CardDataSystem.GEO, CardDataSystem.ANEMO, CardDataSystem.ELECTRO, CardDataSystem.OMNI]
	_play_card(s, "Omni Conversion")
	if s.players[0].dice.size() != 4 or s.players[0].dice.count(CardDataSystem.OMNI) != 4:
		return "Omni Conversion should spend 1 die and convert 3 non-Omni dice into Omni (4 Omni total), got %s" % str(s.players[0].dice)
	return ""


static func _test_utility_draw_and_swap() -> String:
	var s := _start()
	# 1. Draw Cards (1 Any): draws 2 cards
	_give(s, 0, ["Draw Cards"])
	var deck_before: int = s.players[0].deck.size()
	_play_card(s, "Draw Cards")
	if s.players[0].deck.size() != deck_before - 2 or s.players[0].hand.size() != 2:
		return "Draw Cards should draw 2 cards"

	# 2. Swap Cards (0 cost) with explicit player selection `ids = [0, 2]`
	_give(s, 0, ["Swap Cards", "Reroll Dice", "Party Healing", "Elemental Dice"])
	s.players[0].deck = ["Omni Conversion", "Dice Carryover", "Draw Cards"]
	# Remember: Swap Cards (index 0) is removed first, so remaining hand is ["Reroll Dice", "Party Healing", "Elemental Dice"].
	# Swapping indices [0, 2] keeps "Party Healing" and swaps out "Reroll Dice" & "Elemental Dice".
	_play_card(s, "Swap Cards", -1, 0, [0, 2])
	if s.players[0].hand.size() != 3 or not s.players[0].hand.has("Party Healing"):
		return "Explicit Swap Cards should keep unselected Party Healing and draw 2 replacements"

	# 3. Swap Cards with empty ids (AI auto-swap)
	_give(s, 0, ["Swap Cards", "Reroll Dice", "Party Healing"])
	_play_card(s, "Swap Cards")
	if s.players[0].hand.size() != 2:
		return "Auto Swap Cards should maintain hand size of 2 after consuming Swap Cards"
	return ""


static func _test_utility_dice_carryover() -> String:
	var s := _start()
	_give(s, 0, ["Dice Carryover"])
	s.players[0].dice = [CardDataSystem.PYRO, CardDataSystem.HYDRO, CardDataSystem.GEO, CardDataSystem.ANEMO]
	_play_card(s, "Dice Carryover") # spends 1 die -> 3 unused dice left
	if s.players[0].dice.size() != 3:
		return "Dice Carryover should cost 1 die, leaving 3 unused dice"
	TCGRulesEngine.apply_action(s, TCGGameState.ActionData.new("end_round", 0))
	TCGRulesEngine.apply_action(s, TCGGameState.ActionData.new("end_round", 1))
	if s.players[0].dice.size() != 11:
		return "Dice Carryover should yield 8 rolled + 3 carried Omni = 11 dice, got %d" % s.players[0].dice.size()
	for idx in [8, 9, 10]:
		if s.players[0].dice[idx] != CardDataSystem.OMNI:
			return "Carried dice at index %d must be Omni" % idx
	return ""


static func _test_utility_healing_cards() -> String:
	var s := _start()
	# 1. Active Character Healing (0 cost): heals active by 1 HP and sets once-per-round healing limit
	s.players[0].characters[0].hp = 6
	_give(s, 0, ["Active Character Healing", "Dual Character Healing", "Party Healing"])
	var dice_before: int = s.players[0].dice.size()
	_play_card(s, "Active Character Healing")
	if s.players[0].characters[0].hp != 7 or s.players[0].dice.size() != dice_before:
		return "Active Character Healing should heal active by 1 HP for 0 dice"
	if not s.players[0].heal_card_used:
		return "Playing a healing action card must mark heal_card_used = true for the round"

	# 1b. Second healing action card in the SAME round must be illegal (both in legal_actions and apply_action)
	for a in TCGRulesEngine.legal_actions(s):
		if a.type == "card" and a.player == 0:
			var cn: String = s.players[0].hand[a.index]
			if cn == "Dual Character Healing" or cn == "Party Healing":
				return "Second healing action card '%s' must not be legal in the same round" % cn
	TCGRulesEngine.apply_action(s, TCGGameState.ActionData.new("card", 0, 0, -1, [0]))
	if TCGRulesEngine.last_error.is_empty():
		return "apply_action must reject a second healing action card in the same round"

	# Advance to next round -> healing card limit resets!
	TCGRulesEngine.apply_action(s, TCGGameState.ActionData.new("end_round", 0))
	TCGRulesEngine.apply_action(s, TCGGameState.ActionData.new("end_round", 1))
	if s.players[0].heal_card_used:
		return "heal_card_used must reset at the start of a new round"

	# 2a. Dual Character Healing (1 Any): heals active (+1) AND lowest-HP standby (+1)
	var s2 := _start()
	s2.players[0].characters[0].hp = 7
	s2.players[0].characters[1].hp = 4
	s2.players[0].characters[2].hp = 9
	_give(s2, 0, ["Dual Character Healing"])
	_play_card(s2, "Dual Character Healing")
	if s2.players[0].characters[0].hp != 8 or s2.players[0].characters[1].hp != 5 or s2.players[0].characters[2].hp != 9:
		return "Dual Character Healing should heal active (+1) and lowest-HP standby (+1)"

	# 2b. Dual Character Healing when active IS lowest HP -> heals active (+1) AND lowest of the OTHER TWO (+1), NOT active twice!
	var s3 := _start()
	s3.players[0].characters[0].hp = 3
	s3.players[0].characters[1].hp = 8
	s3.players[0].characters[2].hp = 6
	_give(s3, 0, ["Dual Character Healing"])
	_play_card(s3, "Dual Character Healing")
	if s3.players[0].characters[0].hp != 4 or s3.players[0].characters[1].hp != 8 or s3.players[0].characters[2].hp != 7:
		return "Dual Character Healing must heal active (3->4) and lowest-HP other ally (6->7), got [%d, %d, %d]" % [
			s3.players[0].characters[0].hp, s3.players[0].characters[1].hp, s3.players[0].characters[2].hp
		]

	# 2c. Dual Character Healing skips defeated standby character and heals the living damaged standby
	var s3b := _start()
	s3b.players[0].characters[0].hp = 4
	s3b.players[0].characters[1].hp = 0
	s3b.players[0].characters[1].defeated = true
	s3b.players[0].characters[2].hp = 7
	_give(s3b, 0, ["Dual Character Healing"])
	_play_card(s3b, "Dual Character Healing")
	if s3b.players[0].characters[0].hp != 5 or s3b.players[0].characters[1].hp != 0 or s3b.players[0].characters[2].hp != 8:
		return "Dual Character Healing should skip defeated standby and heal living standby (7->8)"

	# 3. Party Healing (2 Any): heals all living allies by 1 HP
	var s4 := _start()
	s4.players[0].characters[0].hp = 5
	s4.players[0].characters[1].hp = 6
	s4.players[0].characters[2].hp = 7
	_give(s4, 0, ["Party Healing"])
	_play_card(s4, "Party Healing")
	var hps := [s4.players[0].characters[0].hp, s4.players[0].characters[1].hp, s4.players[0].characters[2].hp]
	if hps != [6, 7, 8]:
		return "Party Healing should heal all living party members by 1 HP ([6, 7, 8]), got %s" % str(hps)
	return ""


# ------------------------------------------------------------------------------
# Non-Mutating Preview Test
# ------------------------------------------------------------------------------
static func _test_preview_skill_and_card_no_mutation() -> String:
	var s := _start(["Azula", "Zuko", "Aang"], ["Katara", "Toph", "Iroh"])
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
	# Azula Blue Arc = 2 Electro + Overloaded (+2) = 4 total, Crystallize Shield blocks 1 -> HP 7
	if int(f0_ov.get("total_dmg", 0)) != 4 or int(f0_ov.get("shield_dmg", 0)) != 1 or int(f0_ov.get("hp_after", -1)) != 7:
		return "Overloaded + shield preview mismatch: " + str(f0_ov)
	if String(f0_ov.get("reaction", "")) != "Overloaded" or not bool(f0_ov.get("forced_switch_out", false)) or not bool(f1_ov.get("forced_switch_in", false)):
		return "Overloaded forced-switch flags missing: " + str(f0_ov) + " / " + str(f1_ov)
	if s.players[1].characters[0].hp != 10 or s.players[1].characters[0].aura != CardDataSystem.PYRO or s.players[1].active != 0 or s.players[1].combat.size() != 1:
		return "preview_skill mutated live game state!"

	# 3. Electro-Charged + standby Piercing damage + Party Healing card preview
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
	_give(s, 0, ["Party Healing"])
	var prev_card := TCGRulesEngine.preview_card(s, 0, 0, -1)
	var own1_heal: int = int(prev_card.get("own_chars", {}).get(1, {}).get("heal", 0))
	if not bool(prev_card.get("ok", false)) or own1_heal != 1 or s.players[0].characters[1].hp != 6 or s.players[0].hand.size() != 1:
		return "Party Healing preview_card mismatch or mutated state: " + str(prev_card)
	return ""

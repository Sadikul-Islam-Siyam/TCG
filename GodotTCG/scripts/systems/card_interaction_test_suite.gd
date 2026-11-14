class_name TCGCardInteractionTestSuite
extends RefCounted
## Stage 6: Automated Test Suite for Card Display, Hand Synchronization, Selection,
## Targeting, Dice Payment, Elemental Tuning, and Rejection Feedback.
## Exercises `TCGMatchScene`, `TCGHandStrip`, `TCGActionCardView`, and `TCGCharacterSlot`
## directly against `TCGMatchLifecycle` and `TCGRulesEngine`.

const MATCH_SCENE_RES := preload("res://scenes/board/match_scene.tscn")


static func run_all_tests() -> Dictionary:
	CardDataSystem.load_all_content()
	var results: Array[Dictionary] = []

	var tests: Array[Callable] = [
		_test_01_card_view_populates_from_migrated_data,
		_test_02_hand_syncs_from_real_match_state,
		_test_03_mulligan_selection_and_swap_execution,
		_test_04_untargeted_event_and_support_card_play_and_payment,
		_test_05_zero_cost_card_executes_immediately,
		_test_06_targeted_weapon_and_food_selection_cancel_and_equip,
		_test_07_invalid_target_and_insufficient_dice_rejection,
		_test_08_support_zone_full_rejection,
		_test_09_talent_card_active_character_and_energy_checks,
		_test_10_elemental_tuning_flow_and_omni_matching_rejection,
		_test_11_skill_and_switch_payment_interaction_and_synchronization,
		_test_12_coin_intro_and_rematch_config_preserved,
		_test_13_hotseat_cover_and_first_player_setup_sync,
		_test_14_one_click_roll_and_drag_tune_on_tray,
		_test_15_mulligan_confirm_button_click_in_tree,
		_test_16_hover_shows_no_details_and_click_twice_plays,
		_test_17_choose_active_one_click_and_drawer_outside_click,
		_test_18_skill_and_card_damage_reaction_preview,
	]

	var passed: int = 0
	var failed: int = 0

	for t in tests:
		var res: Dictionary = t.call()
		results.append(res)
		if bool(res["ok"]):
			passed += 1
		else:
			failed += 1

	return {
		"passed": passed,
		"failed": failed,
		"total": tests.size(),
		"results": results,
	}


static func _make_board(seed_val: int = 42, auto_action: bool = true) -> TCGMatchScene:
	var board: TCGMatchScene = MATCH_SCENE_RES.instantiate() as TCGMatchScene
	board._build_board_components()
	board.start_interactive_match("pvp", 0, 1, seed_val, auto_action)
	if auto_action:
		var act_p: int = board.actor()
		if act_p >= 0:
			board.view_player = act_p
			board.sync_from_state()
	return board


static func _test_01_card_view_populates_from_migrated_data() -> Dictionary:
	var name := "01. Card scenes populate from migrated CardData & CharData"
	var view := TCGActionCardView.new()
	for cname in CardDataSystem.card_defs.keys():
		view.setup(String(cname), 0, false, true, false)
		var cd := CardDataSystem.get_card_def(String(cname))
		if cd == null or view.card_name != cd.name:
			view.free()
			return {"name": name, "ok": false, "error": "Failed to bind CardData for %s" % cname}
	view.free()

	var slot := TCGCharacterSlot.new()
	for ch_name in CardDataSystem.roster:
		var defn := CardDataSystem.get_char_def(String(ch_name))
		var ch_inst := TCGPlayerSystem.CharacterInstance.new(String(ch_name), defn.hp)
		slot.setup(0, 0, ch_inst, true)
		if slot.char_state.name != defn.name or slot.char_state.hp != defn.hp:
			slot.free()
			return {"name": name, "ok": false, "error": "Failed to bind CharData for %s" % ch_name}
	slot.free()

	return {"name": name, "ok": true, "error": ""}


static func _test_02_hand_syncs_from_real_match_state() -> Dictionary:
	var name := "02. Hand strip renders exact player hand from real match state"
	var board := _make_board(10, true)
	var p := board.me()
	if board.hand_strip.hand_cards.size() != p.hand.size():
		board.free()
		return {"name": name, "ok": false, "error": "Hand strip count mismatch"}
	for i in range(p.hand.size()):
		if board.hand_strip.hand_cards[i] != p.hand[i]:
			board.free()
			return {"name": name, "ok": false, "error": "Hand card mismatch at %d" % i}
	board.free()
	return {"name": name, "ok": true, "error": ""}


static func _test_03_mulligan_selection_and_swap_execution() -> Dictionary:
	var name := "03. Setup mulligan card toggle, SWAP marker, and confirm"
	var board := _make_board(15, false)
	var fp: int = maxi(0, board.actor())
	board.view_player = fp
	board.sync_from_state()
	if not board.is_mulligan_stage():
		board.free()
		return {"name": name, "ok": false, "error": "Expected match to start in mulligan stage"}
	# Toggle cards 0 and 2 for swap
	board.select_or_play_hand_card(0)
	board.select_or_play_hand_card(2)
	if board.mulligan_swap_indices != [0, 2]:
		board.free()
		return {"name": name, "ok": false, "error": "Expected swap indices [0, 2]"}
	# Toggle card 0 off
	board.select_or_play_hand_card(0)
	if board.mulligan_swap_indices != [2]:
		board.free()
		return {"name": name, "ok": false, "error": "Expected swap indices [2] after toggle off"}
	board._confirm_mulligan()
	var ok_flag: bool = board.game_state.players[fp].mull_done
	board.free()
	if not ok_flag:
		return {"name": name, "ok": false, "error": "Acting player mull_done should be true after confirm"}
	return {"name": name, "ok": true, "error": ""}


static func _test_04_untargeted_event_and_support_card_play_and_payment() -> Dictionary:
	var name := "04. Untargeted Buff & Draw Event card selection, payment modal, and board update"
	var board := _make_board(21, true)
	var p := board.me()
	p.hand.assign(["Tactical Draw", "Battle Cry"])
	p.dice.assign(["Omni", "Omni", "Pyro", "Cryo", "Hydro"])
	board.sync_from_state()

	# Click "Tactical Draw" once -> inspects details without opening payment yet
	var r1_inspect := board.select_or_play_hand_card(0, -2)
	if not bool(r1_inspect.get("inspected", false)) or not board.pay_pending.is_empty():
		board.free()
		return {"name": name, "ok": false, "error": "First click on Tactical Draw should inspect without opening payment"}
	# Click "Tactical Draw" twice -> opens payment modal
	var r1 := board.select_or_play_hand_card(0, -2)
	if not bool(r1.get("ok", false)) or board.pay_pending.is_empty():
		board.free()
		return {"name": name, "ok": false, "error": "Second click on Tactical Draw should open payment modal"}

	# Confirm payment -> Tactical Draw draws 2 cards
	var c1 := board.confirm_payment_modal()
	if not bool(c1.get("ok", false)):
		board.free()
		return {"name": name, "ok": false, "error": "Tactical Draw confirm failed: %s" % str(c1.get("error", ""))}

	# Now click "Battle Cry" twice (1st inspect, 2nd open payment for cost 2 Unaligned)
	var bc_idx: int = p.hand.find("Battle Cry")
	board.select_or_play_hand_card(bc_idx, -2)
	var r2 := board.select_or_play_hand_card(bc_idx, -2)
	if not bool(r2.get("ok", false)) or board.pay_pending.is_empty():
		board.free()
		return {"name": name, "ok": false, "error": "Expected payment modal for Battle Cry"}
	var c2 := board.confirm_payment_modal()
	if not bool(c2.get("ok", false)):
		board.free()
		return {"name": name, "ok": false, "error": "Battle Cry confirm failed"}
	var ok_buff: bool = false
	for st in p.combat:
		if st.name == "Attack +1":
			ok_buff = true
	board.free()
	if not ok_buff:
		return {"name": name, "ok": false, "error": "Combat status did not update with Attack +1"}
	return {"name": name, "ok": true, "error": ""}


static func _test_05_zero_cost_card_executes_immediately() -> Dictionary:
	var name := "05. Zero-cost card ('Quick Rally') executes immediately without modal"
	var board := _make_board(25, true)
	var p := board.me()
	p.hand.assign(["Quick Rally"])
	p.dice.assign(["Geo"])
	var deck_before: int = p.deck.size()
	board.sync_from_state()

	# Click 1 inspects Quick Rally; Click 2 executes 0-cost card immediately without payment modal
	var r_insp := board.select_or_play_hand_card(0, -2)
	if not bool(r_insp.get("inspected", false)) or p.hand.size() != 1:
		board.free()
		return {"name": name, "ok": false, "error": "First click should inspect 0-cost card without playing"}
	var r := board.select_or_play_hand_card(0, -2)
	var deck_after: int = p.deck.size()
	var pay_empty: bool = board.pay_pending.is_empty()
	board.free()
	if not bool(r.get("ok", false)) or not pay_empty:
		return {"name": name, "ok": false, "error": "0-cost card should execute on second click without leaving pay_pending open"}
	if deck_after != deck_before - 1:
		return {"name": name, "ok": false, "error": "Quick Rally should draw 1 card from deck"}
	return {"name": name, "ok": true, "error": ""}


static func _test_06_targeted_weapon_and_food_selection_cancel_and_equip() -> Dictionary:
	var name := "06. Targeted Heal cards ('Major Heal' & 'Minor Heal') select, cancel, and target heal"
	var board := _make_board(30, true)
	var p := board.me()
	p.characters[0].hp = 6
	p.characters[1].defeated = true
	p.characters[1].hp = 0
	p.hand.assign(["Major Heal", "Minor Heal"])
	p.dice.assign(["Omni", "Omni", "Omni"])
	board.sync_from_state()

	# 1. Click targeted Heal in hand -> enters awaiting_target state (alive slots 0 & 2 valid; defeated slot 1 invalid)
	var r_sel := board.select_or_play_hand_card(0, -2)
	if not bool(r_sel.get("awaiting_target", false)) or board.selected_hand_index != 0:
		board.free()
		return {"name": name, "ok": false, "error": "Expected Major Heal to await target selection"}

	if not board.own_char_slots[0].is_valid_target or board.own_char_slots[1].is_valid_target or not board.own_char_slots[2].is_valid_target:
		board.free()
		return {"name": name, "ok": false, "error": "Heal valid target highlights on character slots are incorrect"}

	# 2. Click same card again (keeps awaiting_target) & clear selection
	var r_again := board.select_or_play_hand_card(0, -2)
	if not bool(r_again.get("awaiting_target", false)):
		board.free()
		return {"name": name, "ok": false, "error": "Clicking selected targeted card again should keep awaiting_target"}
	board.selected_hand_index = -1
	board.sync_from_state()

	# 3. Select Major Heal again and click Character 0 (heals 2 HP: 6 -> 8)
	board.select_or_play_hand_card(0, -2)
	board._on_char_slot_clicked(0, 0)
	if board.pay_pending.is_empty():
		board.free()
		return {"name": name, "ok": false, "error": "Expected payment modal after clicking valid target character"}
	var c_maj := board.confirm_payment_modal()
	if not bool(c_maj.get("ok", false)) or p.characters[0].hp != 8:
		board.free()
		return {"name": name, "ok": false, "error": "Major Heal should heal Character 0 from 6 to 8 HP"}

	# 4. Play Minor Heal (0 dice, heals 1 HP) onto Character 0 (8 -> 9)
	var mh_idx: int = p.hand.find("Minor Heal")
	board.select_or_play_hand_card(mh_idx, 0)
	if not board.pay_pending.is_empty():
		board.confirm_payment_modal()
	var final_hp: int = p.characters[0].hp
	board.free()
	if final_hp != 9:
		return {"name": name, "ok": false, "error": "Expected Character 0 HP to heal from 8 to 9, got %d" % final_hp}

	return {"name": name, "ok": true, "error": ""}


static func _test_07_invalid_target_and_insufficient_dice_rejection() -> Dictionary:
	var name := "07. Invalid defeated target and insufficient dice rejection feedback"
	var board := _make_board(33, true)
	var p := board.me()
	p.characters[1].defeated = true
	p.characters[1].hp = 0
	p.hand.assign(["Major Heal", "Battle Cry"])
	p.dice.assign(["Pyro"]) # 1 die: cannot pay Battle Cry (costs 2 Unaligned)
	board.sync_from_state()

	# 1. Try playing Major Heal onto defeated character index 1 -> rejected
	var r_bad_tgt := board.select_or_play_hand_card(0, 1)
	if bool(r_bad_tgt.get("ok", false)):
		board.free()
		return {"name": name, "ok": false, "error": "Major Heal should be rejected on defeated character"}

	# 2. Try playing Battle Cry with only 1 die (Click 1 = inspect, Click 2 = reject with toast)
	board.select_or_play_hand_card(1, -2)
	var r_no_dice := board.select_or_play_hand_card(1, -2)
	var has_toast: bool = not board._toasts.is_empty()
	board.free()
	if bool(r_no_dice.get("ok", false)):
		return {"name": name, "ok": false, "error": "Battle Cry should be rejected when player has only 1 die"}
	if not has_toast:
		return {"name": name, "ok": false, "error": "Rejection should produce a user-facing toast"}

	return {"name": name, "ok": true, "error": ""}


static func _test_08_support_zone_full_rejection() -> Dictionary:
	var name := "08. Most-injured Heal ('Team Tonic') and Shield ('Iron Guard') card execution"
	var board := _make_board(35, true)
	var p := board.me()
	p.characters[0].hp = 9
	p.characters[1].hp = 4
	p.characters[2].hp = 8
	p.hand.assign(["Team Tonic", "Iron Guard"])
	p.dice.assign(["Omni", "Omni", "Omni"])
	board.sync_from_state()

	board.select_or_play_hand_card(0, -2)
	board.select_or_play_hand_card(0, -2)
	board.confirm_payment_modal()
	if p.characters[1].hp != 7:
		board.free()
		return {"name": name, "ok": false, "error": "Team Tonic should heal most injured character from 4 to 7"}

	board.select_or_play_hand_card(0, -2)
	board.select_or_play_hand_card(0, -2)
	board.confirm_payment_modal()
	var has_shield: bool = false
	for st in p.combat:
		if st.name == "Shield +2":
			has_shield = true
	board.free()
	if not has_shield:
		return {"name": name, "ok": false, "error": "Iron Guard should grant Shield +2 combat status"}
	return {"name": name, "ok": true, "error": ""}


static func _test_09_talent_card_active_character_and_energy_checks() -> Dictionary:
	var name := "09. Buff cards ('Power Boost' & 'Energy Charge') boost skill DMG and Energy"
	var board := _make_board(40, true)
	if board.input_controller != null:
		board.input_controller.debounce_ms = 0
	var p := board.me()
	var foe := board.game_state.players[1 - board.view_player]
	p.characters[0] = TCGPlayerSystem.CharacterInstance.new("Pyro Vanguard", 10)
	foe.characters[0] = TCGPlayerSystem.CharacterInstance.new("Cryo Knight", 10)
	p.active = 0
	foe.active = 0
	p.hand.assign(["Power Boost", "Energy Charge"])
	p.dice.assign(["Omni", "Omni", "Pyro", "Pyro", "Pyro"])
	board.sync_from_state()

	# 1. Play Energy Charge -> +1 Energy on Pyro Vanguard
	board.select_or_play_hand_card(1, -2)
	board.select_or_play_hand_card(1, -2)
	board.confirm_payment_modal()
	if p.characters[0].energy != 1:
		board.free()
		return {"name": name, "ok": false, "error": "Energy Charge should grant +1 Energy"}

	# 2. Play Power Boost -> Next Attack +2 boosts Normal Attack from 2 to 4 DMG
	board.select_or_play_hand_card(0, -2)
	board.select_or_play_hand_card(0, -2)
	board.confirm_payment_modal()
	if board.animation_queue != null:
		board.animation_queue.skip_all()
	board._busy_timer = 0.0
	board._on_skill_clicked(0)
	var preview_dmg: int = int(board.foe_char_slots[0].preview_info.get("total_dmg", 0))
	board._on_skill_clicked(0)
	board.confirm_payment_modal()
	var foe_hp: int = foe.characters[0].hp
	board.free()
	if preview_dmg != 4 or foe_hp != 6:
		return {"name": name, "ok": false, "error": "Expected Power Boost to preview 4 DMG and leave foe HP at 6, got preview=%d hp=%d" % [preview_dmg, foe_hp]}

	return {"name": name, "ok": true, "error": ""}


static func _test_10_elemental_tuning_flow_and_omni_matching_rejection() -> Dictionary:
	var name := "10. Elemental Tuning converts non-matching die and rejects Omni/matching dice"
	var board := _make_board(45, true)
	var p := board.me()
	var active_el: String = p.get_active_char().get_defn().element
	var other_el: String = CardDataSystem.PYRO if active_el != CardDataSystem.PYRO else CardDataSystem.CRYO
	p.hand.assign(["Tactical Draw"])
	p.dice.assign(["Omni", active_el])
	board.sync_from_state()

	# 1. With only Omni and matching element dice, Elemental Tuning must be rejected
	if board.begin_tune(0):
		board.free()
		return {"name": name, "ok": false, "error": "Tuning should be rejected when all dice are Omni or active element"}

	# 2. Add a non-matching die and tune Tactical Draw into active element
	p.dice.append(other_el)
	board.sync_from_state()
	if not board.begin_tune(0):
		board.free()
		return {"name": name, "ok": false, "error": "Tuning should open modal when a non-matching die exists"}
	var res := board.confirm_payment_modal()
	var ok_tuned: bool = p.hand.is_empty() and p.dice.count(active_el) == 2
	board.free()
	if not bool(res.get("ok", false)):
		return {"name": name, "ok": false, "error": "Elemental Tuning confirm failed"}
	if not ok_tuned:
		return {"name": name, "ok": false, "error": "Expected hand card consumed and %s die converted to %s" % [other_el, active_el]}

	return {"name": name, "ok": true, "error": ""}


static func _test_11_skill_and_switch_payment_interaction_and_synchronization() -> Dictionary:
	var name := "11. Skill & character switch payment modal and turn handoff"
	var board := _make_board(50, true)
	var p := board.me()
	p.characters[0] = TCGPlayerSystem.CharacterInstance.new("Electro Ranger", 10)
	p.active = 0
	p.dice.assign(["Electro", "Electro", "Electro", "Pyro"])
	board.sync_from_state()

	# Click Elemental Skill once -> inspects skill; click again -> opens payment modal
	var prev_actor: int = board.actor()
	board._on_skill_clicked(1)
	if String(board._inspected.get("kind", "")) != "skill" or not board.pay_pending.is_empty():
		board.free()
		return {"name": name, "ok": false, "error": "First skill click should inspect without opening payment"}
	board._on_skill_clicked(1)
	if board.pay_pending.is_empty():
		board.free()
		return {"name": name, "ok": false, "error": "Second skill click should open payment modal"}
	var res := board.confirm_payment_modal()
	var next_actor: int = board.actor()
	board.free()
	if not bool(res.get("ok", false)):
		return {"name": name, "ok": false, "error": "Skill payment confirm failed"}
	if next_actor == prev_actor:
		return {"name": name, "ok": false, "error": "Combat action (skill) should pass turn to opponent"}

	return {"name": name, "ok": true, "error": ""}


static func _test_12_coin_intro_and_rematch_config_preserved() -> Dictionary:
	var name := "12. Coin Toss intro skips cleanly & rematch preserves custom decks and AI levels"
	var board: TCGMatchScene = MATCH_SCENE_RES.instantiate() as TCGMatchScene
	board._build_board_components()
	var chars0: Array = ["Pyro Vanguard", "Cryo Knight", "Electro Ranger"]
	var deck0: Array = TCGDeckSystem.build_preset(chars0)
	var chars1: Array = ["Hydro Cleric", "Geo Guardian", "Anemo Scout"]
	var deck1: Array = TCGDeckSystem.build_preset(chars1)
	board.start_match_with_decks("pve", chars0, deck0, chars1, deck1, 77, false, "normal", "hard", true)

	if not board.intro_active():
		board.free()
		return {"name": name, "ok": false, "error": "Expected Coin Toss intro to be active on start with p_show_intro=true"}
	board.skip_intro()
	if board.intro_active():
		board.free()
		return {"name": name, "ok": false, "error": "skip_intro() should end Coin Toss intro"}

	board.game_state.phase = "over"
	board.restart_match()
	var kept_ok: bool = (
		board.game_state.players[0].characters[0].name == "Pyro Vanguard"
		and board.game_state.players[1].characters[2].name == "Anemo Scout"
		and board.player_labels[1] == "AI (Hard)"
	)
	board.free()
	if not kept_ok:
		return {"name": name, "ok": false, "error": "restart_match() lost custom deck or AI level configuration"}
	return {"name": name, "ok": true, "error": ""}


static func _test_13_hotseat_cover_and_first_player_setup_sync() -> Dictionary:
	var name := "13. Hotseat pass-device privacy cover & initial first_player sync"
	var board := _make_board(50, true)
	var p := board.me()
	p.characters[0] = TCGPlayerSystem.CharacterInstance.new("Electro Ranger", 10)
	p.active = 0
	p.dice.assign(["Omni", "Omni", "Omni", "Omni"])
	board.sync_from_state()

	# Turn-passing skill in pvp (Click 1 = inspect, Click 2 = pay) triggers hotseat cover & hides new active hand
	board._on_skill_clicked(0)
	board._on_skill_clicked(0)
	var res := board.confirm_payment_modal()
	if not bool(res.get("ok", false)):
		board.free()
		return {"name": name, "ok": false, "error": "PvP skill payment failed"}
	if board._hotseat_cover != board.view_player or not board.hand_strip.hidden_hand:
		board.free()
		return {"name": name, "ok": false, "error": "Expected hotseat privacy cover & hidden hand on turn switch"}
	board.dismiss_hotseat_cover()
	if board._hotseat_cover != -1 or board.hand_strip.hidden_hand:
		board.free()
		return {"name": name, "ok": false, "error": "dismiss_hotseat_cover() should reveal active hand"}
	board.free()

	# Find a seed whose first_player == 1 and verify p_show_intro=true syncs view_player to actor
	var board2: TCGMatchScene = MATCH_SCENE_RES.instantiate() as TCGMatchScene
	board2._build_board_components()
	var chars_a: Array = ["Electro Ranger", "Pyro Vanguard", "Cryo Knight"]
	var deck_a: Array = TCGDeckSystem.build_preset(chars_a)
	var found_p1_first: bool = false
	for s in range(1, 20):
		board2.start_match_with_decks("pvp", chars_a, deck_a, chars_a, deck_a, s, false, "normal", "normal", true)
		if board2.game_state.first_player == 1:
			found_p1_first = true
			if board2.view_player != 1 or not board2.is_mulligan_stage():
				board2.free()
				return {"name": name, "ok": false, "error": "PvP first_player==1 should focus view_player=1 at start"}
			break
	board2.free()
	if not found_p1_first:
		return {"name": name, "ok": false, "error": "Could not find first_player==1 test seed"}
	return {"name": name, "ok": true, "error": ""}


static func _test_14_one_click_roll_and_drag_tune_on_tray() -> Dictionary:
	var name := "14. One-click roll reroll+confirm and drag-to-tray elemental tuning"
	var board := _make_board(7, false)
	# Advance both players through setup (mulligan + choose_active)
	while board.game_state.phase == "setup":
		var ap: int = board.actor()
		if ap < 0:
			break
		board.view_player = ap
		if not board.game_state.players[ap].mull_done:
			board.execute_action(TCGGameState.ActionData.new("mulligan", ap))
		else:
			board.execute_action(TCGGameState.ActionData.new("choose_active", ap, 0))
		board.dismiss_hotseat_cover()

	if board.game_state.phase != "roll":
		board.free()
		return {"name": name, "ok": false, "error": "Expected roll phase after setup"}

	# 1-click reroll [0, 1] + confirm_roll
	var rp: int = board.actor()
	board.view_player = rp
	board.sync_from_state()
	board.roll_selected_dice = [0, 1]
	board._confirm_roll_phase()
	if not board.game_state.players[rp].roll_done:
		board.free()
		return {"name": name, "ok": false, "error": "_confirm_roll_phase should mark roll_done"}
	board.dismiss_hotseat_cover()
	# Second player confirms roll
	var rp2: int = board.actor()
	if rp2 >= 0 and board.game_state.phase == "roll":
		board.view_player = rp2
		board._confirm_roll_phase()
		board.dismiss_hotseat_cover()

	if board.game_state.phase != "action":
		board.free()
		return {"name": name, "ok": false, "error": "Expected action phase after both players confirm roll"}

	# Set tunable die + drag hand card 0 onto dice tray
	var ap_act: int = board.actor()
	board.view_player = ap_act
	var p := board.me()
	var active_el: String = p.get_active_char().get_defn().element
	var diff_el: String = CardDataSystem.PYRO if active_el != CardDataSystem.PYRO else CardDataSystem.CRYO
	p.dice.assign([diff_el, diff_el])
	var hand_before: int = p.hand.size()
	board.sync_from_state()

	board.drag_state = {"hand_index": 0, "card_name": p.hand[0], "pos": Vector2(1220, 180)}
	board._finish_card_drag(board.dice_tray.position + Vector2(34, 66))
	var ok_drag: bool = p.hand.size() == hand_before - 1 and p.dice[0] == active_el and board.dice_tray.is_spinning()
	board.free()
	if not ok_drag:
		return {"name": name, "ok": false, "error": "Drag-to-tray tune did not convert die & animate tray"}
	return {"name": name, "ok": true, "error": ""}


static func _test_15_mulligan_confirm_button_click_in_tree() -> Dictionary:
	var name := "15. Clicking Mulligan Confirm button over character slots submits mulligan"
	var board := _make_board(88, false)
	board.skip_intro()
	var p0_idx: int = board.actor()
	board.view_player = p0_idx
	board.sync_from_state()
	board.select_or_play_hand_card(0)

	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = board._mulligan_confirm_rect().get_center()
	board._input(click)

	var ok_mull: bool = board.game_state.players[p0_idx].mull_done
	board.free()
	if not ok_mull:
		return {"name": name, "ok": false, "error": "Clicking Mulligan Confirm button did not complete mulligan"}
	return {"name": name, "ok": true, "error": ""}


static func _test_16_hover_shows_no_details_and_click_twice_plays() -> Dictionary:
	var name := "16. Hover shows no description anywhere; 1st click inspects, 2nd click plays/switches"
	var board := _make_board(91, true)
	var p := board.me()
	p.hand.assign(["Quick Rally"])
	p.dice.assign(["Omni", "Omni", "Omni", "Omni"])
	var deck_before: int = p.deck.size()
	board.sync_from_state()

	# 1. Hovering char, skill, and card must NOT populate _inspected or select a card
	board._on_char_slot_hovered(0, 0, true)
	board._on_char_slot_hovered(1, 0, true)
	board._on_skill_hovered(0, true)
	board._on_hand_card_hovered(0, "Quick Rally", true)
	if not board._inspected.is_empty() or board.selected_hand_index != -1 or not board.pay_pending.is_empty():
		board.free()
		return {"name": name, "ok": false, "error": "Hovering must not open description/inspection"}

	# 2. Clicking opponent character once inspects it; clicking twice closes cleanly
	board._on_char_slot_clicked(1, 0)
	if String(board._inspected.get("kind", "")) != "char" or int(board._inspected.get("side", -1)) != 1:
		board.free()
		return {"name": name, "ok": false, "error": "1st click on opponent char should inspect"}
	board._on_char_slot_clicked(1, 0)
	if not board._inspected.is_empty():
		board.free()
		return {"name": name, "ok": false, "error": "2nd click on opponent char should close inspect"}

	# 3. Clicking own bench char 1 once inspects it; clicking twice opens switch payment
	board._on_char_slot_clicked(0, 1)
	if String(board._inspected.get("kind", "")) != "char" or int(board._inspected.get("index", -1)) != 1 or not board.pay_pending.is_empty():
		board.free()
		return {"name": name, "ok": false, "error": "1st click on own char should inspect without switching"}
	board._on_char_slot_clicked(0, 1)
	if board.pay_pending.is_empty():
		board.free()
		return {"name": name, "ok": false, "error": "2nd click on own char should open switch payment"}
	board.cancel_payment_modal()

	# 4. Clicking Normal Attack once inspects skill; clicking twice opens payment modal
	board._on_skill_clicked(0)
	if String(board._inspected.get("kind", "")) != "skill" or int(board._inspected.get("index", -1)) != 0 or not board.pay_pending.is_empty():
		board.free()
		return {"name": name, "ok": false, "error": "1st click on Normal Attack should inspect without using"}
	board._on_skill_clicked(0)
	if board.pay_pending.is_empty():
		board.free()
		return {"name": name, "ok": false, "error": "2nd click on Normal Attack should open payment modal"}
	board.cancel_payment_modal()

	# 5. Clicking 0-cost hand card once inspects; clicking twice plays it
	board.select_or_play_hand_card(0, -2)
	if board.selected_hand_index != 0 or p.deck.size() != deck_before:
		board.free()
		return {"name": name, "ok": false, "error": "1st click on hand card should inspect without playing"}
	board.select_or_play_hand_card(0, -2)
	if p.deck.size() != deck_before - 1:
		board.free()
		return {"name": name, "ok": false, "error": "2nd click on 0-cost hand card should play it and draw 1"}

	board.free()
	return {"name": name, "ok": true, "error": ""}


static func _test_17_choose_active_one_click_and_drawer_outside_click() -> Dictionary:
	var name := "17. Select Active Character takes 1 click; DetailDrawer forwards outside char clicks"
	# Part A: Setup choose_active accepts 1 left-click without opening details
	var setup_board := _make_board(93, false)
	setup_board.skip_intro()
	setup_board.hotseat = false
	setup_board.dismiss_hotseat_cover()
	setup_board._compute_board_layout(Vector2(1920, 1080))
	for _step in range(4):
		var cur_act := setup_board.actor()
		if cur_act >= 0:
			setup_board.view_player = cur_act
		setup_board.dismiss_hotseat_cover()
		setup_board.sync_from_state()
		if setup_board._is_choose_active_phase():
			break
		if setup_board.is_mulligan_stage():
			setup_board._confirm_mulligan()
	setup_board.dismiss_hotseat_cover()
	if setup_board.input_controller != null:
		setup_board.input_controller._last_action_ms = -1000
	setup_board.sync_from_state()
	var choosing_p: int = setup_board.view_player
	if not setup_board._is_choose_active_phase():
		setup_board.free()
		return {"name": name, "ok": false, "error": "Failed to reach setup choose_active phase"}

	# Right-click style char inspect still works during choose_active
	setup_board._on_status_icon_clicked({"kind": "char", "side": 0, "index": 2})
	if not setup_board.detail_drawer.is_open():
		setup_board.free()
		return {"name": name, "ok": false, "error": "Right-click inspect should still open DetailDrawer during choose_active"}

	# Single left-click (even while DetailDrawer is open!) must select active char immediately
	var char1_pos: Vector2 = setup_board.own_char_slots[1].position + Vector2(30, 30)
	var clk := InputEventMouseButton.new()
	clk.button_index = MOUSE_BUTTON_LEFT
	clk.pressed = true
	clk.position = char1_pos
	setup_board.detail_drawer._on_backdrop_input(clk)
	var first_chosen_ok: bool = (setup_board.game_state.players[choosing_p].chosen == 1 or setup_board.game_state.players[choosing_p].active == 1)
	if not first_chosen_ok or setup_board.detail_drawer.is_open():
		var dbg := "choosing_p=%d chosen=%d act=%d open=%s" % [
			choosing_p,
			setup_board.game_state.players[choosing_p].chosen,
			setup_board.game_state.players[choosing_p].active,
			str(setup_board.detail_drawer.is_open()),
		]
		setup_board.free()
		return {"name": name, "ok": false, "error": "1 click during choose_active failed: " + dbg}

	# Second player also chooses active in 1 click -> reveals active chars & starts Roll Phase
	var second_p: int = setup_board.actor()
	if second_p >= 0 and setup_board.game_state.phase == "setup":
		setup_board.view_player = second_p
		setup_board.dismiss_hotseat_cover()
		if setup_board.input_controller != null:
			setup_board.input_controller._last_action_ms = -1000
		setup_board.sync_from_state()
		setup_board._on_char_slot_clicked(0, 2)
		if setup_board.game_state.players[choosing_p].active != 1 or setup_board.game_state.players[second_p].active != 2 or setup_board.game_state.phase != "roll":
			setup_board.free()
			return {"name": name, "ok": false, "error": "Second choose_active 1-click did not reveal actives and enter roll phase"}
	setup_board.free()

	# Part B: Action phase Click-1 opens DetailDrawer, Click-2 on same char through backdrop opens Switch Payment
	var act_board := _make_board(94, true)
	act_board.skip_intro()
	act_board.hotseat = false
	act_board.dismiss_hotseat_cover()
	act_board._compute_board_layout(Vector2(1920, 1080))
	act_board.me().dice.assign(["Omni", "Omni", "Omni", "Omni"])
	act_board.sync_from_state()
	var bench_idx: int = 1 if act_board.me().active != 1 else 2
	act_board._on_char_slot_clicked(0, bench_idx)
	if not act_board.detail_drawer.is_open() or String(act_board._inspected.get("kind", "")) != "char":
		act_board.free()
		return {"name": name, "ok": false, "error": "Action phase 1st char click should open DetailDrawer"}
	var clk2 := InputEventMouseButton.new()
	clk2.button_index = MOUSE_BUTTON_LEFT
	clk2.pressed = true
	clk2.position = act_board.own_char_slots[bench_idx].position + Vector2(30, 30)
	act_board.detail_drawer._on_backdrop_input(clk2)
	var switch_opened: bool = not act_board.pay_pending.is_empty() and not act_board.detail_drawer.is_open()
	act_board.free()
	if not switch_opened:
		return {"name": name, "ok": false, "error": "Action phase 2nd click on inspected char via DetailDrawer backdrop must open Switch payment"}

	return {"name": name, "ok": true, "error": ""}


static func _test_18_skill_and_card_damage_reaction_preview() -> Dictionary:
	var name := "18. Clicking skill shows live DMG + Reaction preview on foe cards without mutating state"
	var board := _make_board(95, true)
	board.skip_intro()
	board.hotseat = false
	board.dismiss_hotseat_cover()
	var p := board.me()
	var f: TCGPlayerSystem.PlayerState = board.game_state.players[1 - board.view_player]
	p.characters[0] = TCGPlayerSystem.CharacterInstance.new("Electro Ranger", 10)
	p.active = 0
	p.dice.assign(["Electro", "Electro", "Electro", "Omni"])
	f.characters[0] = TCGPlayerSystem.CharacterInstance.new("Cryo Knight", 5)
	f.characters[0].aura = CardDataSystem.CRYO
	f.characters[1] = TCGPlayerSystem.CharacterInstance.new("Geo Guardian", 10)
	f.characters[2] = TCGPlayerSystem.CharacterInstance.new("Hydro Cleric", 10)
	f.active = 0
	board.sync_from_state()

	# Hovering skill must NOT trigger board preview overlays (click-driven only)
	board._on_skill_hovered(1, true)
	if not board.foe_char_slots[0].preview_info.is_empty():
		board.free()
		return {"name": name, "ok": false, "error": "Hovering skill should not populate character card preview overlays"}
	board._on_skill_hovered(1, false)

	# Click 1 on Normal Attack -> shows 2 Physical DMG (5->3 HP) on foe active card
	board._on_skill_clicked(0)
	var na_prev: Dictionary = board.foe_char_slots[0].preview_info
	if int(na_prev.get("total_dmg", 0)) != 2 or int(na_prev.get("hp_after", -1)) != 3 or f.characters[0].hp != 5:
		board.free()
		return {"name": name, "ok": false, "error": "Click-1 Normal Attack preview failed: " + str(na_prev)}

	# Click 1 on Elemental Skill -> shows 4 Electro DMG (Superconduct +1) + 1 Piercing on bench
	board._on_skill_clicked(1)
	var sk0: Dictionary = board.foe_char_slots[0].preview_info
	var sk1: Dictionary = board.foe_char_slots[1].preview_info
	var sk2: Dictionary = board.foe_char_slots[2].preview_info
	if int(sk0.get("total_dmg", 0)) != 4 or String(sk0.get("reaction", "")) != "Superconduct":
		board.free()
		return {"name": name, "ok": false, "error": "Click-1 Skill Superconduct preview failed: " + str(sk0)}
	if int(sk1.get("piercing_dmg", 0)) != 1 or int(sk2.get("piercing_dmg", 0)) != 1:
		board.free()
		return {"name": name, "ok": false, "error": "Click-1 Superconduct bench piercing preview missing"}

	# Click 2 on Elemental Skill -> Payment modal opens while preview remains visible until cancelled
	board._on_skill_clicked(1)
	if board.pay_pending.is_empty() or int(board.foe_char_slots[0].preview_info.get("total_dmg", 0)) != 4:
		board.free()
		return {"name": name, "ok": false, "error": "Click-2 payment modal should keep action preview visible"}
	board.cancel_payment_modal()
	if not board.foe_char_slots[0].preview_info.is_empty() or f.characters[0].hp != 5:
		board.free()
		return {"name": name, "ok": false, "error": "Cancelling payment modal should clear preview & keep HP untouched"}

	board.free()
	return {"name": name, "ok": true, "error": ""}


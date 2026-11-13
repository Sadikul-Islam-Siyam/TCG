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
	var ok_flag: bool = board.game_state.players[0].mull_done
	board.free()
	if not ok_flag:
		return {"name": name, "ok": false, "error": "Player 0 mull_done should be true after confirm"}
	return {"name": name, "ok": true, "error": ""}


static func _test_04_untargeted_event_and_support_card_play_and_payment() -> Dictionary:
	var name := "04. Untargeted Event & Support card selection, payment modal, and board update"
	var board := _make_board(21, true)
	var p := board.me()
	p.hand.assign(["Strategize", "Paimon"])
	p.dice.assign(["Omni", "Omni", "Pyro", "Cryo", "Hydro"])
	board.sync_from_state()

	# Click "Strategize" once -> inspects details without opening payment yet
	var r1_inspect := board.select_or_play_hand_card(0, -2)
	if not bool(r1_inspect.get("inspected", false)) or not board.pay_pending.is_empty():
		board.free()
		return {"name": name, "ok": false, "error": "First click on Strategize should inspect without opening payment"}
	# Click "Strategize" twice -> opens payment modal
	var r1 := board.select_or_play_hand_card(0, -2)
	if not bool(r1.get("ok", false)) or board.pay_pending.is_empty():
		board.free()
		return {"name": name, "ok": false, "error": "Second click on Strategize should open payment modal"}

	# Confirm payment -> Strategize draws 2 cards
	var c1 := board.confirm_payment_modal()
	if not bool(c1.get("ok", false)):
		board.free()
		return {"name": name, "ok": false, "error": "Strategize confirm failed: %s" % str(c1.get("error", ""))}

	# Now click "Paimon" twice (1st inspect, 2nd open payment for cost 3 Same)
	var paimon_idx: int = p.hand.find("Paimon")
	board.select_or_play_hand_card(paimon_idx, -2)
	var r2 := board.select_or_play_hand_card(paimon_idx, -2)
	if not bool(r2.get("ok", false)) or board.pay_pending.is_empty():
		board.free()
		return {"name": name, "ok": false, "error": "Expected payment modal for Paimon"}
	var c2 := board.confirm_payment_modal()
	if not bool(c2.get("ok", false)):
		board.free()
		return {"name": name, "ok": false, "error": "Paimon confirm failed"}
	var ok_paimon: bool = p.supports.size() == 1 and p.supports[0].name == "Paimon"
	board.free()
	if not ok_paimon:
		return {"name": name, "ok": false, "error": "Support zone did not update with Paimon"}
	return {"name": name, "ok": true, "error": ""}


static func _test_05_zero_cost_card_executes_immediately() -> Dictionary:
	var name := "05. Zero-cost card ('Changing Shifts' / 'Sweet Madame') executes immediately without modal"
	var board := _make_board(25, true)
	var p := board.me()
	p.hand.assign(["Changing Shifts"])
	p.dice.assign(["Geo"])
	board.sync_from_state()

	# Click 1 inspects Changing Shifts; Click 2 executes 0-cost card immediately without payment modal
	var r_insp := board.select_or_play_hand_card(0, -2)
	if not bool(r_insp.get("inspected", false)) or p.hand.size() != 1:
		board.free()
		return {"name": name, "ok": false, "error": "First click should inspect 0-cost card without playing"}
	var r := board.select_or_play_hand_card(0, -2)
	if not bool(r.get("ok", false)) or not board.pay_pending.is_empty():
		board.free()
		return {"name": name, "ok": false, "error": "0-cost card should execute on second click without leaving pay_pending open"}
	var has_cs: bool = false
	for st in p.combat:
		if st.name == "Changing Shifts":
			has_cs = true
	board.free()
	if not has_cs:
		return {"name": name, "ok": false, "error": "Combat status 'Changing Shifts' not created"}
	return {"name": name, "ok": true, "error": ""}


static func _test_06_targeted_weapon_and_food_selection_cancel_and_equip() -> Dictionary:
	var name := "06. Targeted card ('Traveler's Handy Sword' & 'Mondstadt Hash Browns') select, cancel, and target play"
	var board := _make_board(30, true)
	var p := board.me()
	# Deck 0 has Keqing (Sword), Fischl (Bow), Xingqiu (Sword)
	p.characters[0].hp = 7
	p.hand.assign(["Traveler's Handy Sword", "Mondstadt Hash Browns"])
	p.dice.assign(["Omni", "Omni", "Omni"])
	board.sync_from_state()

	# 1. Click Weapon in hand -> enters awaiting_target state
	var r_sel := board.select_or_play_hand_card(0, -2)
	if not bool(r_sel.get("awaiting_target", false)) or board.selected_hand_index != 0:
		board.free()
		return {"name": name, "ok": false, "error": "Expected weapon card to await target selection"}

	# Verify character slots 0 (Keqing, Sword) and 2 (Xingqiu, Sword) are marked valid targets, while 1 (Fischl, Bow) is not
	if not board.own_char_slots[0].is_valid_target or board.own_char_slots[1].is_valid_target or not board.own_char_slots[2].is_valid_target:
		board.free()
		return {"name": name, "ok": false, "error": "Weapon valid target highlights on character slots are incorrect"}

	# 2. Click same card again (now shows target prompt) & clear via Right-click/clear helper simulation
	var r_again := board.select_or_play_hand_card(0, -2)
	if not bool(r_again.get("awaiting_target", false)):
		board.free()
		return {"name": name, "ok": false, "error": "Clicking selected targeted card again should keep awaiting_target"}
	board.selected_hand_index = -1
	board.sync_from_state()

	# 3. Select Weapon again and click Character 0 (Keqing)
	board.select_or_play_hand_card(0, -2)
	board._on_char_slot_clicked(0, 0)
	if board.pay_pending.is_empty():
		board.free()
		return {"name": name, "ok": false, "error": "Expected payment modal after clicking valid Sword character"}
	var c_weap := board.confirm_payment_modal()
	if not bool(c_weap.get("ok", false)) or String(p.characters[0].equipment.get("weapon", "")) != "Traveler's Handy Sword":
		board.free()
		return {"name": name, "ok": false, "error": "Keqing should have Traveler's Handy Sword equipped"}

	# 4. Play Mondstadt Hash Browns (1 die, heals 2 HP) onto Character 0
	var hb_idx: int = p.hand.find("Mondstadt Hash Browns")
	board.select_or_play_hand_card(hb_idx, 0)
	board.confirm_payment_modal()
	var final_hp: int = p.characters[0].hp
	board.free()
	if final_hp != 9:
		return {"name": name, "ok": false, "error": "Expected Keqing HP to heal from 7 to 9, got %d" % final_hp}

	return {"name": name, "ok": true, "error": ""}


static func _test_07_invalid_target_and_insufficient_dice_rejection() -> Dictionary:
	var name := "07. Invalid weapon target and insufficient dice rejection feedback"
	var board := _make_board(33, true)
	var p := board.me()
	p.hand.assign(["Traveler's Handy Sword", "Paimon"])
	p.dice.assign(["Pyro", "Hydro"]) # Only 2 mismatched dice (Paimon needs 3 Same; Sword needs 2 Any)
	board.sync_from_state()

	# 1. Try playing Sword onto Fischl (index 1, Bow user) -> rejected
	var r_bad_tgt := board.select_or_play_hand_card(0, 1)
	if bool(r_bad_tgt.get("ok", false)):
		board.free()
		return {"name": name, "ok": false, "error": "Sword should be rejected on Bow character Fischl"}

	# 2. Try playing Paimon with only 2 dice (Click 1 = inspect, Click 2 = reject with toast)
	board.select_or_play_hand_card(1, -2)
	var r_no_dice := board.select_or_play_hand_card(1, -2)
	var has_toast: bool = not board._toasts.is_empty()
	board.free()
	if bool(r_no_dice.get("ok", false)):
		return {"name": name, "ok": false, "error": "Paimon should be rejected when player has only 2 dice"}
	if not has_toast:
		return {"name": name, "ok": false, "error": "Rejection should produce a user-facing toast"}

	return {"name": name, "ok": true, "error": ""}


static func _test_08_support_zone_full_rejection() -> Dictionary:
	var name := "08. Support card rejected when support zone has 4 cards"
	var board := _make_board(35, true)
	var p := board.me()
	p.supports.clear()
	for _i in range(4):
		p.supports.append(TCGPlayerSystem.UnitInstance.new("Paimon", 2))
	p.hand.assign(["Liben"])
	p.dice.assign(["Omni", "Omni"])
	board.sync_from_state()

	board.select_or_play_hand_card(0, -2)
	var r := board.select_or_play_hand_card(0, -2)
	board.free()
	if bool(r.get("ok", false)):
		return {"name": name, "ok": false, "error": "Support card should be rejected when support zone is full (4/4)"}
	return {"name": name, "ok": true, "error": ""}


static func _test_09_talent_card_active_character_and_energy_checks() -> Dictionary:
	var name := "09. Talent card ('Stellar Predator') active character & play validation"
	var board := _make_board(40, true)
	var p := board.me()
	# Ensure Player characters are Keqing (0), Fischl (1), Xingqiu (2)
	p.characters[0] = TCGPlayerSystem.CharacterInstance.new("Keqing", 10)
	p.characters[1] = TCGPlayerSystem.CharacterInstance.new("Fischl", 10)
	p.characters[2] = TCGPlayerSystem.CharacterInstance.new("Xingqiu", 10)
	p.active = 0
	p.hand.assign(["Stellar Predator"])
	p.dice.assign(["Electro", "Electro", "Electro", "Omni"])
	board.sync_from_state()

	# 1. While Keqing is active, Fischl's talent "Stellar Predator" must be rejected on 2nd click
	board.select_or_play_hand_card(0, -2)
	var r_wrong_active := board.select_or_play_hand_card(0, -2)
	if bool(r_wrong_active.get("ok", false)):
		board.free()
		return {"name": name, "ok": false, "error": "Stellar Predator should be rejected when Fischl is not active"}

	# 2. Switch active to Fischl (index 1) and play Stellar Predator
	p.active = 1
	board.sync_from_state()
	var r_ok := board.select_or_play_hand_card(0, 1)
	if not bool(r_ok.get("ok", false)) or board.pay_pending.is_empty():
		board.free()
		return {"name": name, "ok": false, "error": "Stellar Predator should be playable when Fischl is active"}
	var c_ok := board.confirm_payment_modal()
	var talent_str: String = String(p.characters[1].equipment.get("talent", ""))
	board.free()
	if not bool(c_ok.get("ok", false)):
		return {"name": name, "ok": false, "error": "Stellar Predator confirm failed: %s" % str(c_ok.get("error", ""))}
	if talent_str != "Stellar Predator":
		return {"name": name, "ok": false, "error": "Fischl should have Stellar Predator equipped"}

	return {"name": name, "ok": true, "error": ""}


static func _test_10_elemental_tuning_flow_and_omni_matching_rejection() -> Dictionary:
	var name := "10. Elemental Tuning converts non-matching die and rejects Omni/matching dice"
	var board := _make_board(45, true)
	var p := board.me()
	# Active is Keqing (Electro)
	p.hand.assign(["Strategize"])
	p.dice.assign(["Omni", "Electro"])
	board.sync_from_state()

	# 1. With only Omni and Electro dice, Elemental Tuning must be rejected
	if board.begin_tune(0):
		board.free()
		return {"name": name, "ok": false, "error": "Tuning should be rejected when all dice are Omni or active element"}

	# 2. Add a Pyro die (index 2) and tune Strategize into an Electro die
	p.dice.append("Pyro")
	board.sync_from_state()
	if not board.begin_tune(0):
		board.free()
		return {"name": name, "ok": false, "error": "Tuning should open modal when a non-matching die exists"}
	var res := board.confirm_payment_modal()
	var ok_tuned: bool = p.hand.is_empty() and p.dice.count("Electro") == 2
	board.free()
	if not bool(res.get("ok", false)):
		return {"name": name, "ok": false, "error": "Elemental Tuning confirm failed"}
	if not ok_tuned:
		return {"name": name, "ok": false, "error": "Expected hand card consumed and Pyro die converted to Electro"}

	return {"name": name, "ok": true, "error": ""}


static func _test_11_skill_and_switch_payment_interaction_and_synchronization() -> Dictionary:
	var name := "11. Skill & character switch payment modal and turn handoff"
	var board := _make_board(50, true)
	var p := board.me()
	p.characters[0] = TCGPlayerSystem.CharacterInstance.new("Keqing", 10)
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
	var chars0: Array = ["Diluc", "Kaeya", "Fischl"]
	var deck0: Array = TCGDeckSystem.build_preset(["Diluc", "Kaeya", "Fischl"])
	var chars1: Array = ["Keqing", "Mona", "Noelle"]
	var deck1: Array = TCGDeckSystem.build_preset(["Keqing", "Mona", "Noelle"])
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
		board.game_state.players[0].characters[0].name == "Diluc"
		and board.game_state.players[1].characters[2].name == "Noelle"
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
	p.characters[0] = TCGPlayerSystem.CharacterInstance.new("Keqing", 10)
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
	var chars_a: Array = ["Keqing", "Fischl", "Xingqiu"]
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
	p.hand.assign(["Changing Shifts"])
	p.dice.assign(["Omni", "Omni", "Omni", "Omni"])
	board.sync_from_state()

	# 1. Hovering char, skill, and card must NOT populate _inspected or select a card
	board._on_char_slot_hovered(0, 0, true)
	board._on_char_slot_hovered(1, 0, true)
	board._on_skill_hovered(0, true)
	board._on_hand_card_hovered(0, "Changing Shifts", true)
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
	if board.selected_hand_index != 0 or p.hand.size() != 1:
		board.free()
		return {"name": name, "ok": false, "error": "1st click on hand card should inspect without playing"}
	board.select_or_play_hand_card(0, -2)
	if p.hand.size() != 0:
		board.free()
		return {"name": name, "ok": false, "error": "2nd click on 0-cost hand card should play it"}

	board.free()
	return {"name": name, "ok": true, "error": ""}

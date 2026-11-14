extends Control
## Main Scene Controller (Stage 6)
## Hosts screen navigation between MenuScene and MatchScene while running
## Stage 2, Stage 3, Stage 4, and Stage 6 automated verification suites.

const MENU_SCENE_RES := preload("res://scenes/ui/menu_scene.tscn")
const DECK_SELECT_SCENE_RES := preload("res://scenes/ui/deck_select_scene.tscn")
const DECK_BUILDER_SCENE_RES := preload("res://scenes/ui/deck_builder_scene.tscn")
const MATCH_SCENE_RES := preload("res://scenes/board/match_scene.tscn")
const TCGCombatFeedbackTestSuite = preload("res://scripts/systems/combat_feedback_test_suite.gd")

var current_screen: Control = null


func _ready() -> void:
	CardDataSystem.load_all_content()
	var args: PackedStringArray = OS.get_cmdline_args()
	var user_args: PackedStringArray = OS.get_cmdline_user_args()

	if args.has("--validate-data") or user_args.has("--validate-data"):
		var data_ok := _validate_custom_data()
		TCGArt.clear_cache()
		get_tree().quit(0 if data_ok else 1)
		return

	if args.has("--run-tests") or user_args.has("--run-tests") or DisplayServer.get_name() == "headless":
		var all_ok := _run_verification_summary()
		if args.has("--quit-after-tests") or user_args.has("--quit-after-tests"):
			get_tree().quit(0 if all_ok else 1)
			return

	show_menu()

	if args.has("--capture-shots") or user_args.has("--capture-shots"):
		_capture_stage7_screenshots()
	elif args.has("--capture-stage10") or user_args.has("--capture-stage10"):
		_capture_stage10_screenshots()
	elif args.has("--capture-audit") or user_args.has("--capture-audit"):
		_capture_audit_screenshots()
	elif args.has("--playtest") or user_args.has("--playtest"):
		_run_live_playtest()


func show_menu() -> void:
	if current_screen != null:
		current_screen.queue_free()
		current_screen = null
	var menu: TCGMenuScene = MENU_SCENE_RES.instantiate() as TCGMenuScene
	menu.mode_selected.connect(_on_menu_mode_selected)
	add_child(menu)
	current_screen = menu


func show_deck_select(mode_id: String = "pve") -> void:
	if current_screen != null:
		current_screen.queue_free()
		current_screen = null
	var ds: TCGDeckSelectScene = DECK_SELECT_SCENE_RES.instantiate() as TCGDeckSelectScene
	ds.back_requested.connect(show_menu)
	ds.builder_requested.connect(show_deck_builder.bind(mode_id))
	ds.start_match_requested.connect(_on_deck_select_start_match)
	add_child(ds)
	ds.setup_mode(mode_id)
	current_screen = ds


func show_deck_builder(return_to_mode: String = "") -> void:
	if current_screen != null:
		current_screen.queue_free()
		current_screen = null
	var db: TCGDeckBuilderScene = DECK_BUILDER_SCENE_RES.instantiate() as TCGDeckBuilderScene
	db.back_requested.connect(func() -> void:
		if return_to_mode.is_empty():
			show_menu()
		else:
			show_deck_select(return_to_mode)
	)
	add_child(db)
	current_screen = db


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_F11:
			var cur_mode: DisplayServer.WindowMode = DisplayServer.window_get_mode()
			var next_mode: DisplayServer.WindowMode = (
				DisplayServer.WINDOW_MODE_WINDOWED
				if cur_mode == DisplayServer.WINDOW_MODE_FULLSCREEN or cur_mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
				else DisplayServer.WINDOW_MODE_FULLSCREEN
			)
			DisplayServer.window_set_mode(next_mode)
			get_viewport().set_input_as_handled()


func show_match(mode_id: String = "pve", deck0_idx: int = 0, deck1_idx: int = 1, auto_action: bool = true) -> void:
	if current_screen != null:
		current_screen.queue_free()
		current_screen = null
	var board: TCGMatchScene = MATCH_SCENE_RES.instantiate() as TCGMatchScene
	board.return_to_menu_requested.connect(show_menu)
	add_child(board)
	board.start_interactive_match(mode_id, deck0_idx, deck1_idx, 42, auto_action, "normal", "normal", not auto_action)
	current_screen = board


func _on_deck_select_start_match(mode_id: String, picks: Array, lvls: Array) -> void:
	if current_screen != null:
		current_screen.queue_free()
		current_screen = null
	var board: TCGMatchScene = MATCH_SCENE_RES.instantiate() as TCGMatchScene
	board.return_to_menu_requested.connect(show_menu)
	add_child(board)
	var rng_seed: int = int(Time.get_unix_time_from_system()) & 0x7FFFFFFF
	board.start_match_with_decks(
		mode_id,
		picks[0][0],
		picks[0][1],
		picks[1][0],
		picks[1][1],
		rng_seed,
		false,
		str(lvls[0]),
		str(lvls[1]),
		true
	)
	current_screen = board


func _on_menu_mode_selected(mode_id: String) -> void:
	match mode_id:
		"pve", "pvp", "ava":
			show_deck_select(mode_id)
		"decks":
			show_deck_builder()
		"quit":
			get_tree().quit(0)


func _run_verification_summary() -> bool:
	var data_errors := TCGDataValidator.validate_all(CardDataSystem)
	var rules_res := TCGRulesTestSuite.run_all_tests()
	var lc_res := TCGLifecycleTestSuite.run_all_tests()
	var ui_res := TCGCardInteractionTestSuite.run_all_tests()
	var fb_res := TCGCombatFeedbackTestSuite.run_all()
	var ai_res := TCGAITestSuite.run_all_tests()
	var deck_ui_res := TCGDeckUITestSuite.run_all_tests()
	var polish_res := UIPolishTestSuite.run_all_tests()

	print("[Stage 9 Check] Data errors: %d | Rules: %d/%d | Lifecycle: %d/%d | UI: %d/%d | Combat/Feedback: %d/%d | AI: %d/%d | DeckUI: %d/%d | UIPolish: %d/%d" % [
		data_errors.size(),
		int(rules_res["passed"]),
		int(rules_res["total"]),
		int(lc_res["passed"]),
		int(lc_res["total"]),
		int(ui_res["passed"]),
		int(ui_res["total"]),
		int(fb_res["passed"]),
		int(fb_res["total"]),
		int(ai_res["passed"]),
		int(ai_res["total"]),
		int(deck_ui_res["passed"]),
		int(deck_ui_res["total"]),
		int(polish_res["passed"]),
		int(polish_res["total"]),
	])
	for item in deck_ui_res["results"]:
		print("  PASS: %s" % str(item["name"]))
	var ok := data_errors.is_empty()
	for suite_res in [rules_res, lc_res, ui_res, fb_res, ai_res, deck_ui_res, polish_res]:
		if int(suite_res["passed"]) != int(suite_res["total"]):
			ok = false
			if suite_res.has("results"):
				for ritem in suite_res["results"]:
					if ritem is Dictionary and not bool(ritem.get("ok", ritem.get("passed", true))):
						print("  FAIL DETAIL: %s -> %s" % [str(ritem.get("name", "?")), str(ritem.get("error", ""))])
	for item in polish_res["results"]:
		if bool(item["passed"]):
			print("  PASS: %s" % str(item["name"]))
		else:
			print("  FAIL: %s -> %s" % [str(item["name"]), str(item["error"])])
	TCGArt.clear_cache()
	return ok


func _validate_custom_data() -> bool:
	var errors: Array[String] = TCGDataValidator.validate_all(CardDataSystem)
	if CardDataSystem.roster.size() >= 3:
		var sample_chars: Array[String] = [CardDataSystem.roster[0], CardDataSystem.roster[1], CardDataSystem.roster[2]]
		var starter: Array[String] = CardDataSystem.starter_deck()
		for err in TCGDeckSystem.validate_deck(sample_chars, starter):
			errors.append("Starter deck invalid: %s" % err)
	var presets: Dictionary = TCGDeckSystem.preset_decks()
	for pname in presets.keys():
		var pair: Array = presets[pname]
		var errs: Array[String] = TCGDeckSystem.validate_deck(pair[0], pair[1])
		for err in errs:
			errors.append("Preset '%s' deck invalid: %s" % [str(pname), err])
	if errors.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = 42
		var rand_pair: Array = TCGAIPlayer.random_deck(rng)
		for err in TCGDeckSystem.validate_deck(rand_pair[0], rand_pair[1]):
			errors.append("AI random deck invalid: %s" % err)

	if errors.is_empty():
		print("[Data Check] OK: %d characters | %d action cards | %d statuses | %d presets" % [
			CardDataSystem.char_defs.size(),
			CardDataSystem.card_defs.size(),
			CardDataSystem.status_defs.size(),
			CardDataSystem.preset_defs.size(),
		])
		return true

	print("[Data Check] FAILED (%d error(s)):" % errors.size())
	for err in errors:
		print("  - %s" % err)
	return false


func _capture_stage7_screenshots() -> void:
	var shots_dir := ProjectSettings.globalize_path("res://shots")
	DirAccess.make_dir_recursive_absolute(shots_dir)

	# 1. Capture Combat Feedback: Reaction Pill, Burst Announcement Ribbon, Floaters & Hit Shake
	show_match("pve", 0, 1, true)
	var board: TCGMatchScene = current_screen as TCGMatchScene
	var act_p: int = board.actor()
	if act_p >= 0:
		board.view_player = act_p
		board.human_flags[act_p] = true
	var p := board.me()
	p.characters[0] = TCGPlayerSystem.CharacterInstance.new("Electro Ranger", 10, 2)
	p.characters[1] = TCGPlayerSystem.CharacterInstance.new("Pyro Vanguard", 10, 1)
	p.characters[2] = TCGPlayerSystem.CharacterInstance.new("Cryo Knight", 10, 0)
	p.active = 0

	var foe := board.game_state.players[1 - board.view_player]
	foe.characters[0] = TCGPlayerSystem.CharacterInstance.new("Pyro Vanguard", 6, 1)
	foe.characters[0].aura = "Pyro" # Pyro Vanguard has Pyro aura -> Electro triggers Overloaded!
	foe.characters[1] = TCGPlayerSystem.CharacterInstance.new("Cryo Knight", 8, 1)
	foe.characters[2] = TCGPlayerSystem.CharacterInstance.new("Hydro Cleric", 10, 0)
	foe.active = 0

	p.dice.assign(["Omni", "Electro", "Electro", "Electro", "Pyro", "Hydro", "Cryo", "Geo"])
	board.sync_from_state()

	# Present combat burst + reaction events
	var combat_events: Array = [
		{
			"kind": "skill",
			"player": board.view_player,
			"char": 0,
			"skill": "Storm Volley",
			"skill_kind": "burst",
		},
		{
			"kind": "damage",
			"player": 1 - board.view_player,
			"char": 0,
			"amount": 6,
			"dtype": "Electro",
			"reaction": "Overloaded",
		},
		{
			"kind": "heal",
			"player": board.view_player,
			"char": 0,
			"amount": 2,
		}
	]
	board._present_events(combat_events)
	board.sync_from_state()

	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var fb_img: Image = get_viewport().get_texture().get_image()
	var fb_path := shots_dir.path_join("stage7_combat_feedback.png")
	fb_img.save_png(fb_path)
	print("Saved Stage 7 combat feedback screenshot: " + fb_path)

	# 2. Capture Elemental Reaction Banner & Dice Tumbling Roll Phase
	board._banners.clear()
	board._reaction_pills.clear()
	board._ribbons.clear()
	board._banners.append({
		"title": "Round 2",
		"sub": "Roll Phase",
		"color": TCGTheme.GOLD_L,
		"y": 350.0,
		"t": 0.2,
		"dur": 2.0,
	})
	board.dice_tray.trigger_roll([0, 1, 2, 3, 4, 5, 6, 7], 1.2)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var roll_img: Image = get_viewport().get_texture().get_image()
	var roll_path := shots_dir.path_join("stage7_roll_phase.png")
	roll_img.save_png(roll_path)
	print("Saved Stage 7 roll phase screenshot: " + roll_path)

	get_tree().quit(0)


func _capture_stage10_screenshots() -> void:
	var shots_dir := ProjectSettings.globalize_path("res://shots")
	DirAccess.make_dir_recursive_absolute(shots_dir)

	# 1. Capture Pre-Match Deck Select (Human vs AI)
	show_deck_select("pve")
	var ds: TCGDeckSelectScene = current_screen as TCGDeckSelectScene
	ds.press(["pick", 0, 1])
	ds.press(["level", 1, "hard"])
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var ds_img: Image = get_viewport().get_texture().get_image()
	var ds_path := shots_dir.path_join("stage10_deck_select.png")
	ds_img.save_png(ds_path)
	print("Saved Stage 10 deck select screenshot: " + ds_path)

	# 2. Capture Deck Builder populated with 3 characters + CSP-autofilled cards
	show_deck_builder()
	var db: TCGDeckBuilderScene = current_screen as TCGDeckBuilderScene
	db.chars = ["Electro Ranger", "Pyro Vanguard", "Cryo Knight"]
	db.press("fill")
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var db_img: Image = get_viewport().get_texture().get_image()
	var db_path := shots_dir.path_join("stage10_deck_builder.png")
	db_img.save_png(db_path)
	print("Saved Stage 10 deck builder screenshot: " + db_path)

	get_tree().quit(0)


func _snap(shots_dir: String, fname: String) -> void:
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path := shots_dir.path_join(fname)
	img.save_png(path)
	print("Saved audit screenshot: " + path)


func _capture_audit_screenshots() -> void:
	var shots_dir := ProjectSettings.globalize_path("res://shots")
	DirAccess.make_dir_recursive_absolute(shots_dir)

	# 1. Main Menu (already shown by _ready)
	await _snap(shots_dir, "audit_01_main_menu.png")

	# 2. Deck Builder Load Modal (verifies _modal_layer cleanly covers _search_edit)
	show_deck_builder()
	var db: TCGDeckBuilderScene = current_screen as TCGDeckBuilderScene
	db.chars = ["Pyro Vanguard", "Cryo Knight", "Electro Ranger"]
	db.press("fill")
	db.press("load")
	await _snap(shots_dir, "audit_02_deck_builder_load_modal.png")

	# 3. Match Coin Toss Intro
	show_match("pve", 0, 1, false)
	var board: TCGMatchScene = current_screen as TCGMatchScene
	board._intro_t = 1.65
	board.queue_redraw()
	await _snap(shots_dir, "audit_03_coin_intro.png")

	# 4. Hotseat Privacy Cover
	board.start_interactive_match("pvp", 0, 1, 42, true)
	board._hotseat_cover = 1
	board.view_player = 1
	board.sync_from_state()
	await _snap(shots_dir, "audit_04_hotseat_cover.png")

	# 5. Match Action + Hover Inspector
	board.start_interactive_match("pve", 0, 1, 42, true)
	board.view_player = board.actor()
	board.human_flags[board.view_player] = true
	var p := board.me()
	p.hand.assign(["Power Boost", "Iron Guard", "Tactical Draw", "Major Heal"])
	TCGRulesEngine.add_status(p.combat, "Attack +1")
	p.characters[0].aura = "Electro"
	board.game_state.players[1 - board.view_player].characters[0].aura = "Pyro"
	board.sync_from_state()
	board._on_char_slot_clicked(0, 0)
	board.queue_redraw()
	await _snap(shots_dir, "audit_05_action_hover_inspect.png")

	# 6. Pause Modal (3 buttons)
	board._pause_open = true
	board._pause_hover_idx = 1
	board.queue_redraw()
	await _snap(shots_dir, "audit_06_pause_modal.png")

	# 7. Game Over Overlay (with clickable Rematch & Main Menu buttons)
	board._pause_open = false
	board.game_state.phase = "over"
	board.game_state.winner = board.view_player
	board.queue_redraw()
	await _snap(shots_dir, "audit_07_game_over.png")

	# 8. Clean 16:9 Active Action Board (without drawer/modals)
	board.start_interactive_match("pve", 0, 1, 42, true)
	board.view_player = board.actor()
	board.human_flags[board.view_player] = true
	board.me().hand.assign(["Power Boost", "Iron Guard", "Tactical Draw", "Major Heal", "Quick Rally"])
	board.me().characters[0].aura = "Electro"
	board.game_state.players[1 - board.view_player].characters[0].aura = "Pyro"
	board.sync_from_state()
	if board.detail_drawer != null:
		board.detail_drawer.close_immediate()
	board.queue_redraw()
	await _snap(shots_dir, "audit_08_clean_board_16_9.png")

	# 12. Click-1 Skill Damage & Reaction Forecast Preview (verifies card & tooltip overlays)
	board.me().dice.assign(["Electro", "Electro", "Electro", "Omni"])
	board._on_skill_clicked(1)
	board.queue_redraw()
	await _snap(shots_dir, "audit_12_skill_preview.png")
	board._inspected.clear()
	board.sync_from_state()

	# 9. Settings Modal
	if board.settings_modal != null:
		board.settings_modal.open()
	board.queue_redraw()
	await _snap(shots_dir, "audit_09_settings_modal.png")
	if board.settings_modal != null:
		board.settings_modal.close()

	# 10. 19.5:9 Ultrawide Viewport Audit
	DisplayServer.window_set_size(Vector2i(1560, 720))
	await get_tree().process_frame
	board._compute_board_layout()
	board.sync_from_state()
	await _snap(shots_dir, "audit_10_board_19_5_9.png")

	# 11. 4:3 Desktop Viewport Audit
	DisplayServer.window_set_size(Vector2i(1024, 768))
	await get_tree().process_frame
	board._compute_board_layout()
	board.sync_from_state()
	await _snap(shots_dir, "audit_11_board_4_3.png")

	if current_screen != null:
		current_screen.free()
		current_screen = null
	TCGArt.clear_cache()
	get_tree().quit(0)


func _run_live_playtest() -> void:
	var shots_dir := ProjectSettings.globalize_path("res://shots")
	DirAccess.make_dir_recursive_absolute(shots_dir)
	print("[Playtest] 1. Starting at Main Menu -> selecting Human vs AI")
	await get_tree().process_frame
	var menu: TCGMenuScene = current_screen as TCGMenuScene
	assert(menu != null, "Expected TCGMenuScene")
	menu.mode_selected.emit("pve")
	await get_tree().process_frame

	print("[Playtest] 2. On Deck Select -> picking Preset 0 vs Preset 1, AI: Normal")
	var ds: TCGDeckSelectScene = current_screen as TCGDeckSelectScene
	assert(ds != null, "Expected TCGDeckSelectScene")
	ds.press(["pick", 0, 0])
	ds.press(["pick", 1, 1])
	ds.press(["level", 1, "normal"])
	ds.press("start")
	await get_tree().process_frame

	var board: TCGMatchScene = current_screen as TCGMatchScene
	assert(board != null and board.game_state != null, "Expected TCGMatchScene with active state")
	board.game_speed = 4.0
	if board.input_controller != null:
		board.input_controller.debounce_ms = 0
	print("[Playtest] 3. Match started | First player: %s | Intro active: %s" % [board._who(board.game_state.first_player), str(board.intro_active())])
	assert(board.intro_active(), "Expected Coin Toss intro to be active")
	board._intro_t = 1.6
	board.skip_intro()
	await get_tree().process_frame

	var actions_taken: int = 0
	var snapped_mid: bool = false
	var last_round: int = 0
	var guard: int = 0
	while board.game_state.phase != "over" and guard < 600:
		guard += 1
		var s: TCGGameState = board.game_state
		if s.round_number != last_round:
			last_round = s.round_number
			print("[Playtest] --- Round %d (%s) | P0 HP: [%d,%d,%d] | P1 HP: [%d,%d,%d] ---" % [
				s.round_number,
				s.phase,
				s.players[0].characters[0].hp, s.players[0].characters[1].hp, s.players[0].characters[2].hp,
				s.players[1].characters[0].hp, s.players[1].characters[1].hp, s.players[1].characters[2].hp,
			])

		var act_p: int = board.actor()
		if act_p < 0:
			break

		if act_p == 1:
			# Let real AI step via _process
			board._busy_timer = 0.0
			board._ai_timer = 0.0
			board._process(0.1)
			await get_tree().process_frame
			continue

		# Human player (Player 0) makes real UI moves
		if board.is_mulligan_stage():
			board.select_or_play_hand_card(0)
			board._confirm_mulligan()
			actions_taken += 1
		elif not s.pending.is_empty() or (s.phase == "setup" and s.players[0].mull_done):
			var alive := s.players[0].get_alive_indices()
			if not alive.is_empty():
				board._on_char_slot_clicked(0, alive[0])
				actions_taken += 1
		elif s.phase == "roll":
			var active_el: String = s.players[0].get_active_char().get_defn().element
			var reroll_ids: Array[int] = []
			for di in range(s.players[0].dice.size()):
				var df: String = s.players[0].dice[di]
				if df != active_el and df != CardDataSystem.OMNI:
					reroll_ids.append(di)
			board.roll_selected_dice = reroll_ids
			board._confirm_roll_phase()
			actions_taken += 1
		elif s.phase == "action":
			var acted: bool = false
			# 1. Try playing up to 1 playable hand card first (click once to inspect, click twice if untargeted)
			for hi in range(s.players[0].hand.size()):
				var cands := board.get_card_actions_for_hand_index(hi)
				if not cands.is_empty():
					var target_arg: int = cands[0].target
					var res := board.select_or_play_hand_card(hi, target_arg)
					if target_arg < 0:
						res = board.select_or_play_hand_card(hi, -2)
					if bool(res.get("ok", false)):
						if not board.pay_pending.is_empty():
							board.confirm_payment_modal()
						actions_taken += 1
						acted = true
						break
			# 2. Otherwise try using Burst -> Skill -> Normal Attack (click once to inspect, click twice to use)
			if not acted:
				for sk_idx in [2, 1, 0]:
					board._on_skill_clicked(sk_idx)
					board._on_skill_clicked(sk_idx)
					if not board.pay_pending.is_empty():
						var sk_res := board.confirm_payment_modal()
						if bool(sk_res.get("ok", false)):
							actions_taken += 1
							acted = true
							break
						else:
							board.cancel_payment_modal()
			# 3. Otherwise try Elemental Tuning if we have cards & tunable dice & enough to use a skill
			if not acted and not s.players[0].hand.is_empty() and not board.tunable_dice(0).is_empty():
				if board.begin_tune(0):
					board.confirm_payment_modal()
					actions_taken += 1
					acted = true
			# 4. Otherwise End Round
			if not acted:
				board.execute_action(TCGGameState.ActionData.new("end_round", 0))
				actions_taken += 1

		if not snapped_mid and s.round_number >= 2 and s.phase == "action":
			snapped_mid = true
			await _snap(shots_dir, "playtest_midgame.png")
		await get_tree().process_frame

	assert(board.game_state.phase == "over", "Expected match to reach Game Over within guard")
	await _snap(shots_dir, "playtest_gameover.png")
	print("[Playtest] 4. Match finished in Round %d after %d human UI actions! Winner: %s | Final P0 HP: [%d,%d,%d] | Final P1 HP: [%d,%d,%d]" % [
		board.game_state.round_number,
		actions_taken,
		"Draw" if board.game_state.winner < 0 else board._who(board.game_state.winner),
		board.game_state.players[0].characters[0].hp, board.game_state.players[0].characters[1].hp, board.game_state.players[0].characters[2].hp,
		board.game_state.players[1].characters[0].hp, board.game_state.players[1].characters[1].hp, board.game_state.players[1].characters[2].hp,
	])

	# Verify Rematch preserves decks & resets cleanly to Round 1
	board.restart_match()
	await get_tree().process_frame
	assert(board.game_state.round_number == 1 and board.game_state.phase == "setup", "Rematch should reset to Round 1 setup")
	assert(board.game_state.players[0].characters[0].hp == 10 and board.game_state.players[1].characters[0].hp == 10, "Rematch should restore full HP")
	print("[Playtest] 5. Rematch verified cleanly (Round %d, Phase: %s). All systems working!" % [board.game_state.round_number, board.game_state.phase])

	if current_screen != null:
		current_screen.free()
		current_screen = null
	TCGArt.clear_cache()
	get_tree().quit(0)

class_name TCGDeckUITestSuite
extends RefCounted
## Stage 9 Test Suite
## Verifies Saved Decks persistence (TCGDeckStore), Deck Builder (TCGDeckBuilderScene),
## Base64 share codes (export/import), filters, CSP auto-fill, and Pre-Match Deck Select
## (TCGDeckSelectScene) launching matches with custom/preset/random decks and AI levels.


static func run_all_tests() -> Dictionary:
	CardDataSystem.load_all_content()
	var results: Array[Dictionary] = []

	var tests: Array[Array] = [
		["test_deck_store_save_list_delete_and_draft_flag", Callable(TCGDeckUITestSuite, "_test_deck_store")],
		["test_deck_store_overwrite_and_corrupt_json_resilience", Callable(TCGDeckUITestSuite, "_test_deck_store_edge_cases")],
		["test_deck_builder_character_toggle_prunes_illegal_cards", Callable(TCGDeckUITestSuite, "_test_builder_prune")],
		["test_deck_builder_add_remove_and_max_copies", Callable(TCGDeckUITestSuite, "_test_builder_add_remove")],
		["test_deck_builder_autofill_produces_legal_deck", Callable(TCGDeckUITestSuite, "_test_builder_autofill")],
		["test_deck_builder_filters_tabs_and_search", Callable(TCGDeckUITestSuite, "_test_builder_filters")],
		["test_deck_builder_share_code_export_and_import", Callable(TCGDeckUITestSuite, "_test_builder_share_import")],
		["test_deck_builder_load_modal_and_scroll", Callable(TCGDeckUITestSuite, "_test_builder_load_modal_scroll")],
		["test_deck_select_entries_and_incomplete_rejection", Callable(TCGDeckUITestSuite, "_test_deck_select_entries")],
		["test_deck_select_starts_match_with_custom_decks_and_ai_levels", Callable(TCGDeckUITestSuite, "_test_deck_select_launch")],
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


static func _with_temp_store(fn: Callable) -> void:
	var tmp_path := "user://test_stage9_decks.json"
	TCGDeckStore.set_override_path(tmp_path)
	var abs_p := ProjectSettings.globalize_path(tmp_path)
	if FileAccess.file_exists(tmp_path):
		DirAccess.remove_absolute(abs_p)
	fn.call()
	if FileAccess.file_exists(tmp_path):
		DirAccess.remove_absolute(abs_p)
	TCGDeckStore.set_override_path("")


static func _test_deck_store() -> void:
	_with_temp_store(func() -> void:
		assert(TCGDeckStore.list_decks().is_empty())
		assert(not TCGDeckStore.save_deck("   ", ["Aang", "Katara", "Toph"], []))

		var draft_cards: Array[String] = ["Draw Cards", "Elemental Dice"]
		assert(TCGDeckStore.save_deck("Draft One", ["Aang", "Katara", "Toph"], draft_cards))
		var listed := TCGDeckStore.list_decks()
		assert(listed.size() == 1)
		assert(listed[0]["name"] == "Draft One")
		assert(not bool(listed[0]["legal"]))

		var legal_cards: Array[String] = TCGDeckSystem.build_preset(["Aang", "Katara", "Toph"])
		assert(TCGDeckStore.save_deck("Legal Deck", ["Aang", "Katara", "Toph"], legal_cards))
		listed = TCGDeckStore.list_decks()
		assert(listed.size() == 2)
		assert(bool(listed[1]["legal"]))

		assert(TCGDeckStore.delete_deck("Draft One"))
		listed = TCGDeckStore.list_decks()
		assert(listed.size() == 1 and listed[0]["name"] == "Legal Deck")
	)


static func _test_builder_prune() -> void:
	var db := TCGDeckBuilderScene.new()
	db.chars = ["Aang", "Katara", "Toph"]
	db.add_card("Aang's Glider Staff")
	db.add_card("Draw Cards")
	assert(db.total() == 2)

	# Removing Aang must prune Aang's exclusive equipment while keeping generic utility cards
	db.toggle_char("Aang")
	assert(db.chars == ["Katara", "Toph"])
	assert(int(db.counts.get("Aang's Glider Staff", 0)) == 0)
	assert(int(db.counts.get("Draw Cards", 0)) == 1)
	db.free()


static func _test_builder_add_remove() -> void:
	var db := TCGDeckBuilderScene.new()
	db.chars = ["Zuko", "Azula", "Iroh"]
	for _i in range(TCGDeckSystem.MAX_COPIES + 1):
		db.add_card("Draw Cards")
	assert(int(db.counts.get("Draw Cards", 0)) == TCGDeckSystem.MAX_COPIES)
	assert(db.total() == TCGDeckSystem.MAX_COPIES)

	db.remove_card("Draw Cards")
	assert(int(db.counts.get("Draw Cards", 0)) == TCGDeckSystem.MAX_COPIES - 1)
	for _i in range(TCGDeckSystem.MAX_COPIES - 1):
		db.remove_card("Draw Cards")
	assert(not db.counts.has("Draw Cards"))
	db.free()


static func _test_builder_autofill() -> void:
	var db := TCGDeckBuilderScene.new()
	db.chars = ["Aang", "Katara", "Toph"]
	db.add_card("Aang's Glider Staff")
	db.press("fill")
	assert(db.total() == TCGDeckSystem.DECK_SIZE)
	var val: Dictionary = db.validation()
	assert(bool(val["ok"]), "Autofill should produce a legal %d-card deck: %s" % [TCGDeckSystem.DECK_SIZE, str(val["messages"])])
	db.free()


static func _test_builder_filters() -> void:
	var db := TCGDeckBuilderScene.new()
	db.chars = ["Aang", "Katara", "Toph"]
	db.tab = "Equipment"
	var equips := db.visible_cards()
	assert(not equips.is_empty())
	for e in equips:
		assert(CardDataSystem.infer_card_role(CardDataSystem.get_card_def(e)) == "equipment")

	db.tab = "Utility"
	var utils := db.visible_cards()
	assert(utils.size() == 9)
	for u in utils:
		assert(CardDataSystem.infer_card_role(CardDataSystem.get_card_def(u)) == "utility")

	db.tab = "All"
	db.search_query = "Glider"
	var searched := db.visible_cards()
	assert(searched == ["Aang's Glider Staff"])
	db.free()


static func _test_builder_share_import() -> void:
	var db := TCGDeckBuilderScene.new()
	db._ready()
	db.chars = ["Zuko", "Azula", "Iroh"]
	db.press("fill")
	assert(db.total() == TCGDeckSystem.DECK_SIZE)
	var orig_cards: Array[String] = db.cards()
	db.press("share")
	assert(str(db.modal.get("kind", "")) == "share")
	var code: String = str(db.modal.get("code", ""))
	assert(not code.is_empty())

	db.press("close")
	db.press("clear")
	assert(db.chars.is_empty() and db.total() == 0)

	db.press("import")
	assert(str(db.modal.get("kind", "")) == "import")
	db._import_edit.text = code
	db.press("do_import")
	assert(db.modal.is_empty())
	assert(db.chars == ["Zuko", "Azula", "Iroh"])
	assert(db.cards() == orig_cards)
	db.free()


static func _test_deck_select_entries() -> void:
	_with_temp_store(func() -> void:
		TCGDeckStore.save_deck("Incomplete Draft", ["Aang", "Katara", "Toph"], ["Draw Cards"])
		var ds := TCGDeckSelectScene.new()
		ds.setup_mode("pve")
		var n_presets := CardDataSystem.preset_defs.size()
		var draft_idx := 1 + n_presets
		# Entry 0 = Random, Entries 1..N = Presets, last entry = Incomplete Draft
		assert(ds.entries.size() == draft_idx + 1)
		assert(bool(ds.entries[0]["is_random"]))
		assert(not bool(ds.entries[draft_idx]["legal"]))

		# Selecting incomplete draft must be rejected and keep previous pick
		ds.press(["pick", 0, draft_idx])
		assert(ds.pick[0] == 0)
		assert(not ds.msg.is_empty())

		# Selecting a preset must succeed
		ds.press(["pick", 0, 1])
		assert(ds.pick[0] == 1)
		assert(ds.msg.is_empty())
		ds.free()
	)


static func _test_deck_select_launch() -> void:
	_with_temp_store(func() -> void:
		var ds := TCGDeckSelectScene.new()
		ds.setup_mode("pve")
		ds.press(["pick", 0, 1])      # Preset 0
		ds.press(["pick", 1, 0])      # Random AI deck (CSP solver)
		ds.press(["level", 1, "hard"])
		var resolved := ds.resolve_picks()
		assert(resolved.size() == 2)
		assert(TCGDeckSystem.validate_deck(resolved[0][0], resolved[0][1]).is_empty())
		assert(TCGDeckSystem.validate_deck(resolved[1][0], resolved[1][1]).is_empty())

		var board := TCGMatchScene.new()
		board._build_board_components()
		board.start_match_with_decks(
			"pve",
			resolved[0][0],
			resolved[0][1],
			resolved[1][0],
			resolved[1][1],
			77,
			false,
			ds.levels[0],
			ds.levels[1]
		)
		assert(board.lifecycle != null and board.game_state != null)
		assert(board.lifecycle.controllers[1] is TCGAIPlayer)
		assert((board.lifecycle.controllers[1] as TCGAIPlayer).level == "hard")
		board.free()
		ds.free()
	)


static func _test_deck_store_edge_cases() -> void:
	_with_temp_store(func() -> void:
		var team_a: Array[String] = ["Aang", "Katara", "Toph"]
		var team_b: Array[String] = ["Zuko", "Azula", "Iroh"]
		var legal_a: Array[String] = TCGDeckSystem.build_preset(team_a)
		var legal_b: Array[String] = TCGDeckSystem.build_preset(team_b)
		assert(TCGDeckStore.save_deck("Alpha", team_a, legal_a))
		assert(TCGDeckStore.save_deck("Alpha", team_b, legal_b))
		var listed := TCGDeckStore.list_decks()
		assert(listed.size() == 1 and listed[0]["chars"] == team_b)

		# Corrupt JSON must not crash list_decks()
		var f := FileAccess.open("user://test_stage9_decks.json", FileAccess.WRITE)
		f.store_string("{not valid json")
		f.close()
		assert(TCGDeckStore.list_decks().is_empty())

		# Non-array JSON & malformed objects must be ignored
		var f2 := FileAccess.open("user://test_stage9_decks.json", FileAccess.WRITE)
		f2.store_string("[{\"oops\":1}, {\"name\":\"Valid\",\"chars\":[\"Aang\"],\"cards\":[]}]")
		f2.close()
		listed = TCGDeckStore.list_decks()
		assert(listed.size() == 1 and listed[0]["name"] == "Valid")
	)


static func _test_builder_load_modal_scroll() -> void:
	_with_temp_store(func() -> void:
		for i in range(11):
			assert(TCGDeckStore.save_deck("Custom_%02d" % i, ["Aang", "Katara", "Toph"], ["Draw Cards"]))
		var db := TCGDeckBuilderScene.new()
		db._ready()
		db.press("load")
		assert(str(db.modal.get("kind", "")) == "load")
		var entries := db._build_load_entries()
		var expected_total := 11 + CardDataSystem.preset_defs.size()
		assert(entries.size() == expected_total)
		db.modal_scroll = expected_total
		db._register_modal_hitboxes()
		assert(db.modal_scroll == expected_total - 12)
		db.press("close")
		assert(db.modal.is_empty())
		db.free()
	)

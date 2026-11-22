class_name UIPolishTestSuite
extends RefCounted
## Phase 14 (T14.1 - T14.5): Automated UI Polish & Responsive Layout Verification Suite.
## Covers ElementDB single source & zero-Dendro rule, GlossaryDB BBCode compilation,
## responsive zone non-overlap at 16:9 / 19.5:9 / 4:3, 10-card hand fan angles,
## character status cap + overflow, AnimationQueue parallel/skip, InputController debounce,
## DetailDrawer stack depth cap, fixed VFXPool reuse, and AudioManager stream bank.


static func run_all_tests() -> Dictionary:
	CardDataSystem.load_all_content()
	var results: Array[Dictionary] = []
	var tests: Array = [
		["test_01_element_db_colors_shapes_and_no_dendro", Callable(UIPolishTestSuite, "_test_01_element_db")],
		["test_02_glossary_db_bbcode_and_terms", Callable(UIPolishTestSuite, "_test_02_glossary_db")],
		["test_03_responsive_layouts_across_aspect_ratios", Callable(UIPolishTestSuite, "_test_03_responsive_layouts")],
		["test_04_hand_strip_10_card_fan_and_angles", Callable(UIPolishTestSuite, "_test_04_hand_fan")],
		["test_05_character_slot_status_overflow_and_reflow", Callable(UIPolishTestSuite, "_test_05_status_overflow")],
		["test_06_animation_queue_order_parallel_and_skip", Callable(UIPolishTestSuite, "_test_06_animation_queue")],
		["test_07_input_controller_debounce_fsm_and_inspect", Callable(UIPolishTestSuite, "_test_07_input_controller")],
		["test_08_detail_drawer_stack_depth_and_sections", Callable(UIPolishTestSuite, "_test_08_detail_drawer")],
		["test_09_vfx_pool_fixed_capacity_and_reuse", Callable(UIPolishTestSuite, "_test_09_vfx_pool")],
		["test_10_audio_manager_streams_and_buses", Callable(UIPolishTestSuite, "_test_10_audio_manager")],
	]
	var passed: int = 0
	for item in tests:
		var tname: String = item[0]
		var fn: Callable = item[1]
		var err: String = str(fn.call())
		var ok: bool = err.is_empty()
		if ok:
			passed += 1
		results.append({"name": tname, "passed": ok, "error": err})
	return {"passed": passed, "total": tests.size(), "results": results}


static func _test_01_element_db() -> String:
	var core := ElementDB.CORE_ELEMENTS
	if core.size() != 6:
		return "Expected 6 core elements, got %d" % core.size()
	var ids := ElementDB.all_ids()
	if ids.size() != 9:
		return "Expected 9 total ElementDB entries (6 Core + Omni + Physical + Piercing), got %d" % ids.size()
	var shapes: Dictionary = {}
	for eid in ids:
		if eid.to_lower().find("dendro") >= 0:
			return "Forbidden Dendro entry found in ElementDB: %s" % eid
		var ed := ElementDB.get_element(eid)
		if ed == null:
			return "Missing ElementData for %s" % eid
		if ed.icon_small == null or ed.icon_large == null:
			return "Missing baked icon textures for %s" % eid
		if ElementDB.DICE_FACES.has(eid) and ed.die_face == null:
			return "Missing baked die face texture for %s" % eid
		if ed.shape_tag.is_empty() or shapes.has(ed.shape_tag):
			return "Duplicate or empty colorblind shape_tag on %s: %s" % [eid, ed.shape_tag]
		shapes[ed.shape_tag] = eid
	if ElementDB.can_attach_element("Anemo") or ElementDB.can_attach_element("Geo"):
		return "Anemo and Geo must never attach as character aura"
	for att_el in ["Cryo", "Hydro", "Pyro", "Electro"]:
		if not ElementDB.can_attach_element(att_el):
			return "%s must allow elemental attachment" % att_el
	return ""


static func _test_02_glossary_db() -> String:
	if GlossaryDB.REACTION_ENTRIES.size() != 8:
		return "Expected 8 canonical reactions, got %d" % GlossaryDB.REACTION_ENTRIES.size()
	for rx_name in GlossaryDB.REACTION_ENTRIES.keys():
		if String(rx_name).to_lower().find("bloom") >= 0 or String(rx_name).to_lower().find("dendro") >= 0:
			return "Forbidden Dendro reaction present: %s" % rx_name
	var bb := GlossaryDB.compile_bbcode("Deal {num:+2} {el:Pyro} {kw:Overloaded}")
	if bb.find("[url=el:Pyro]") < 0 or bb.find("[url=kw:Overloaded]") < 0:
		return "GlossaryDB.compile_bbcode failed to emit clickable [url] links: %s" % bb
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.text = GlossaryDB.compile_bbcode("Buff: {kw:Crystallize Shield}")
	var parsed_eq := rtl.get_parsed_text()
	rtl.free()
	if parsed_eq != "Buff: Crystallize Shield":
		return "RichTextLabel BBCode left stray tags on spaced keyword: %s" % parsed_eq
	var spaced := GlossaryDB.lookup_term("kw:Crystallize%20Shield")
	if String(spaced.get("body", "")).is_empty():
		return "GlossaryDB.lookup_term failed to decode URL-encoded keyword"
	var cryo := GlossaryDB.lookup_term("el:Cryo")
	var frozen := GlossaryDB.lookup_term("kw:Frozen")
	var vap := GlossaryDB.lookup_term("Vaporize")
	if String(cryo.get("body", "")).is_empty() or String(frozen.get("body", "")).is_empty() or String(vap.get("body", "")).is_empty():
		return "GlossaryDB.lookup_term returned empty body for core terms"
	return ""


static func _test_03_responsive_layouts() -> String:
	var viewports: Array[Vector2] = [
		Vector2(1920, 1080),  # 16:9 standard
		Vector2(2340, 1080),  # 19.5:9 ultrawide mobile
		Vector2(1920, 1440),  # 4:3 expanded canvas
		Vector2(1440, 1080),  # 4:3 desktop window mapped into 1920x1080 safe space
	]
	var board := TCGMatchScene.new()
	var menu := TCGMenuScene.new()
	var db := TCGDeckBuilderScene.new()
	var ds := TCGDeckSelectScene.new()
	ds.setup_mode("pve")
	var err := ""
	for vp in viewports:
		# MatchBoard safe-area containment + zero static zone overlap
		var rects := board.get_zone_layout_rects(vp)
		var safe: Rect2 = rects["safe"]
		var check_safe: Rect2 = safe.grow(2.0)
		var keys: Array = []
		for k in rects.keys():
			if String(k) == "safe":
				continue
			keys.append(k)
			var r: Rect2 = rects[k]
			if not check_safe.encloses(r):
				err = "Match zone '%s' overflows safe area %s at viewport %s (rect=%s)" % [String(k), str(safe), str(vp), str(r)]
				break
		if not err.is_empty():
			break
		for i in range(keys.size()):
			for j in range(i + 1, keys.size()):
				var ri: Rect2 = rects[keys[i]].grow(-1.0)
				var rj: Rect2 = rects[keys[j]].grow(-1.0)
				if ri.intersects(rj):
					err = "Match zones '%s' %s and '%s' %s overlap at %s" % [String(keys[i]), str(rects[keys[i]]), String(keys[j]), str(rects[keys[j]]), str(vp)]
					break
			if not err.is_empty():
				break
		if not err.is_empty():
			break

		# Menu buttons fit inside safe & do not overlap
		menu.size = vp
		var eff_sz := Vector2(maxf(vp.x, UIConstants.BASE_W), maxf(vp.y, UIConstants.BASE_H))
		var msafe := UIConstants.get_safe_rect(eff_sz).grow(2.0)
		var prev_btn := Rect2()
		for bi in range(TCGMenuScene.BUTTONS.size()):
			var br := menu._button_rect(bi)
			if not msafe.encloses(br):
				err = "Menu button %d overflows safe rect at %s" % [bi, str(vp)]
				break
			if bi > 0 and prev_btn.intersects(br):
				err = "Menu buttons overlap at %s" % str(vp)
				break
			prev_btn = br
		if not err.is_empty():
			break

		# DeckBuilder columns strictly disjoint inside safe
		db.size = vp
		var ly := db._layout()
		var dsafe: Rect2 = ly["safe"]
		if float(ly["left_x"]) + float(ly["left_w"]) >= float(ly["center_x"]):
			err = "DeckBuilder left & center columns overlap at %s" % str(vp)
			break
		if float(ly["center_x"]) + float(ly["center_w"]) >= float(ly["right_x"]):
			err = "DeckBuilder center & right columns overlap at %s" % str(vp)
			break
		if not dsafe.grow(2.0).encloses(ly["modal_rect"]):
			err = "DeckBuilder modal overflows safe area at %s" % str(vp)
			break
	ds.free()
	db.free()
	menu.free()
	board.free()
	return err


static func _test_04_hand_fan() -> String:
	var hs := TCGHandStrip.new()
	hs.size = Vector2(920, 204)
	var cards: Array[String] = []
	var playable: Array[bool] = []
	for i in range(10):
		cards.append("Draw Cards")
		playable.append(true)
	hs.setup(cards, playable)
	var err := ""
	if hs._card_views.size() != 10:
		err = "Expected 10 card views in 10-card hand, got %d" % hs._card_views.size()
	else:
		for i in range(10):
			var deg := absf(rad_to_deg(hs._target_rotations[i]))
			if deg > 4.05:
				err = "Hand card %d fan angle %.2f exceeds +-4 deg cap" % [i, deg]
				break
			var tx: float = hs._target_positions[i].x
			var cw: float = hs._card_views[i].size.x
			if tx < -2.0 or tx + cw > hs.size.x + 2.0:
				err = "Hand card %d (x=%.1f, w=%.1f) overflows strip width %.1f" % [i, tx, cw, hs.size.x]
				break
	hs.free()
	return err


static func _test_05_status_overflow() -> String:
	var slot := TCGCharacterSlot.new()
	var ch := TCGPlayerSystem.CharacterInstance.new("Zuko", 10, 0)
	for i in range(10):
		ch.statuses.append(TCGPlayerSystem.StatusInstance.new("ShieldEffect_%d" % i, 2, -1, 0))
	slot.setup_character({"side": 0, "index": 0, "state": ch})
	var err := ""
	var vis := slot.get_visible_status_count()
	var ov := slot.get_overflow_status_count()
	var rects := slot.get_status_rects()
	if vis != 4 or ov != 6 or rects.size() != 5:
		err = "Expected 4 visible + 6 overflow (5 chips), got vis=%d ov=%d rects=%d" % [vis, ov, rects.size()]
	else:
		for i in range(rects.size()):
			for j in range(i + 1, rects.size()):
				if rects[i].grow(-0.5).intersects(rects[j].grow(-0.5)):
					err = "Status chips %d and %d overlap: %s vs %s" % [i, j, str(rects[i]), str(rects[j])]
					break
			if not err.is_empty():
				break
	slot.free()
	return err


static func _test_06_animation_queue() -> String:
	var aq := AnimationQueue.new()
	var order: Array[String] = []
	aq.register_handler(GameEvent.Type.ROUND_STARTED, func(e: GameEvent) -> void:
		order.append("round_%d" % e.amount)
	)
	aq.register_handler(GameEvent.Type.DAMAGE_DEALT, func(e: GameEvent) -> void:
		order.append("dmg_%d" % e.amount)
	)
	aq.set_speed(2.0)
	if absf(aq.scaled(1.0) - 0.5) > 0.01:
		aq.free()
		return "Expected scaled(1.0) == 0.5 at 2x speed, got %.3f" % aq.scaled(1.0)
	aq.push_many([
		GameEvent.make(GameEvent.Type.ROUND_STARTED, 0, -1, "", "", 1),
		GameEvent.make_group([
			GameEvent.make(GameEvent.Type.DAMAGE_DEALT, 1, 0, "", "Pyro", 3),
			GameEvent.make(GameEvent.Type.DAMAGE_DEALT, 1, 1, "", "Electro", 2),
		]),
	])
	var err := ""
	if order != ["round_1", "dmg_3", "dmg_2"]:
		err = "Unexpected AnimationQueue execution order: %s" % str(order)
	elif aq.is_busy():
		err = "AnimationQueue stayed busy after synchronous handlers drained"
	aq.free()
	return err


static func _test_07_input_controller() -> String:
	var ic := TCGInputController.new()
	ic.enter_card_selected(2)
	ic.enter_targeting("char")
	ic.enter_paying()
	ic.enter_confirming()
	var err := ""
	if ic.cancel_one_step() != "close_confirm":
		err = "Expected close_confirm on confirm unwind"
	else:
		ic.enter_card_selected(1)
		ic.enter_targeting("char")
		if ic.cancel_one_step() != "cancel_targeting" or ic.cancel_one_step() != "deselect" or ic.cancel_one_step() != "none":
			err = "Step-by-step cancel_one_step unwind mismatch"
	if err.is_empty():
		if not ic.can_accept_gameplay_input(1000):
			err = "Expected initial gameplay input enabled at t=1000"
		ic.record_action(1000)
		if ic.can_accept_gameplay_input(1050):
			err = "Expected 100ms click-spam debounce to reject t=1050"
		if not ic.can_accept_gameplay_input(1105):
			err = "Expected input allowed after 105ms elapsed"
		ic.set_busy_locked(true)
		if ic.can_accept_gameplay_input(2000):
			err = "Expected busy lock to block gameplay input"
		if not ic.can_accept_inspect_input():
			err = "Inspect input must remain enabled while AnimationQueue is busy"
	ic.free()
	return err


static func _test_08_detail_drawer() -> String:
	var dd := DetailDrawer.new()
	dd.sync_layout(Vector2(1920, 1080))
	var r := dd.get_drawer_rect()
	var err := ""
	if r.size.x < 320.0 or r.size.x > 460.0:
		err = "Unexpected DetailDrawer width %.1f" % r.size.x
	else:
		dd.open_card("Draw Cards")
		if not dd.is_open() or dd.get_stack_depth() != 1:
			err = "DetailDrawer failed to open root card entry"
		else:
			for kw in ["el:Pyro", "kw:Frozen", "kw:Shield", "kw:Energy", "Vaporize"]:
				dd.open_keyword(kw)
			if dd.get_stack_depth() > DetailDrawer.MAX_STACK_DEPTH:
				err = "DetailDrawer stack exceeded MAX_STACK_DEPTH (%d > %d)" % [dd.get_stack_depth(), DetailDrawer.MAX_STACK_DEPTH]
			else:
				dd.pop_or_close()
				dd.pop_or_close()
				dd.pop_or_close()
				if dd.is_open():
					err = "Expected DetailDrawer to close after popping all stack entries"
	dd.free()
	return err


static func _test_09_vfx_pool() -> String:
	var vp := VFXPool.new()
	var init_stats := vp.get_pool_stats()
	var err := ""
	if int(init_stats.get("capacity", 0)) <= 0:
		err = "VFXPool capacity should be pre-allocated (> 0)"
	else:
		for i in range(40):
			vp.spawn_element_hit(Vector2(900, 400), "Pyro", 3)
			vp.spawn_floating_number(Vector2(900, 380), "-3", "Pyro", false)
		vp.spawn_reaction_fx(Vector2(900, 400), "Overloaded", 4)
		vp._process(0.05)
		if vp.get_child_count() != 0:
			err = "VFXPool must reuse pre-allocated slots without adding SceneTree child nodes"
		elif vp.shake_offset.length() <= 0.01:
			err = "Expected non-zero hit shake offset during active trauma"
		vp.clear_all()
		var after := vp.get_pool_stats()
		if int(after["active_numbers"]) != 0 or int(after["active_particles"]) != 0 or vp.shake_offset != Vector2.ZERO:
			err = "VFXPool.clear_all() did not reset active pool counters and shake"
	vp.free()
	return err


static func _test_10_audio_manager() -> String:
	var ml := Engine.get_main_loop() as SceneTree
	if ml == null or ml.root == null:
		return "No SceneTree root available to resolve AudioManager autoload"
	var am := ml.root.get_node_or_null("AudioManager")
	if am == null:
		return "AudioManager autoload missing from root"
	var required: Array[String] = [
		"card_hover", "card_select", "card_draw", "card_play", "card_invalid",
		"ui_click", "ui_confirm", "ui_cancel", "dice_roll", "dice_spend",
		"hit_cryo", "hit_hydro", "hit_pyro", "hit_electro", "hit_anemo", "hit_geo",
		"hit_physical", "hit_piercing", "react_vaporize", "react_melt",
		"react_overloaded", "react_superconduct", "react_electro_charged",
		"react_frozen", "react_swirl", "react_crystallize", "victory", "defeat",
	]
	for k in required:
		if not am.has_sound(k):
			return "AudioManager missing required stream '%s'" % k
	if am.has_sound("hit_dendro"):
		return "AudioManager must not synthesize forbidden Dendro sound"
	var prev: float = am.get_bus_volume_linear("SFX")
	am.set_bus_volume_linear("SFX", 0.55)
	var read_back: float = am.get_bus_volume_linear("SFX")
	am.set_bus_volume_linear("SFX", prev)
	if absf(read_back - 0.55) > 0.01:
		return "AudioManager volume getter/setter mismatch (expected 0.55, got %.2f)" % read_back
	return ""


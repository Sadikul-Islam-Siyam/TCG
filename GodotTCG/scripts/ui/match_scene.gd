class_name TCGMatchScene
extends Control
## Stage 6: Match / Board Screen with Full Card, Hand, Selection, Targeting, Payment & Play Interactions
## Direct port of PythonTCG/ui/match.py (`MatchScene`).
## Drives all results strictly through `TCGMatchLifecycle` and `TCGRulesEngine`.

signal return_to_menu_requested()

const CW: float = 156.0
const CH: float = 266.0
const CHAR_X0: float = 656.0
const CHAR_STEP: float = 186.0
const FOE_Y: float = 88.0
const OWN_Y: float = 554.0

const REACT_DESC: Dictionary = {
	"Vaporize": "+1 DMG (Hydro + Pyro)",
	"Melt": "+2 DMG (Cryo + Pyro)",
	"Overloaded": "+2 DMG, forced switch (Pyro + Electro)",
	"Superconduct": "+1 DMG, 1 Piercing to others (Cryo + Electro)",
	"Electro-Charged": "+1 DMG, 1 Piercing to others (Hydro + Electro)",
	"Frozen": "+1 DMG, target Frozen (Cryo + Hydro)",
	"Swirl": "2 Elemental DMG to other characters (Anemo)",
	"Crystallize": "+1 DMG, 1 Crystallize Shield (Geo)",
}

const INTRO_DUR: float = 2.6

var match_mode: String = "pve"
var player_labels: Array[String] = ["You", "Opponent"]
var human_flags: Array[bool] = [true, false]
var hotseat: bool = false
var view_player: int = 0
var reveal_opponent_hand: bool = false
var game_speed: float = 1.0
var confirm_before_end_round: bool = false

var game_state: TCGGameState = null
var lifecycle: TCGMatchLifecycle = null
var legal_actions: Array[TCGGameState.ActionData] = []
var _last_match_config: Dictionary = {}

# Reusable Child Components
var own_hud: TCGPlayerHudBanner = null
var foe_hud: TCGPlayerHudBanner = null
var own_char_slots: Array[TCGCharacterSlot] = []
var foe_char_slots: Array[TCGCharacterSlot] = []
var own_combat_row: CombatStatusRow = null
var foe_combat_row: CombatStatusRow = null
var dice_tray: TCGDiceTray = null
var skill_bar: TCGSkillBar = null
var battle_log: TCGBattleLogPanel = null
var hand_strip: TCGHandStrip = null

# Phase 1, 8, 9, 10, 12 Architecture Subsystems
var animation_queue: AnimationQueue = null
var input_controller: TCGInputController = null
var vfx_pool: VFXPool = null
var detail_drawer: DetailDrawer = null
var settings_modal: SettingsModal = null

# Player Selection & Interaction States
var selected_hand_index: int = -1      # Selected hand card awaiting target click or play
var mulligan_swap_indices: Array[int] = []
var roll_selected_dice: Array[int] = []
var pay_pending: Dictionary = {}       # Empty when inactive; otherwise {"action", "cost", "title", "detail", "tune", "card_index", "selected_dice"}
var card_swap_pending: Dictionary = {} # Empty when inactive; otherwise {"action", "card_idx", "selected_ids", "max_pick"}
var drag_state: Dictionary = {}        # Empty when inactive; otherwise {"hand_index", "card_name", "pos"}

# Hover / Inspector States
var _hovered_char_side: int = -1
var _hovered_char_idx: int = -1
var _hovered_skill_idx: int = -1
var _hovered_card_name: String = ""
var _hovered_zone_info: Dictionary = {}
var _hovered_status_payload: Dictionary = {}
var _hover_mouse_pos: Vector2 = Vector2.ZERO
var _inspected: Dictionary = {}            # {"kind": "char"|"skill"|"zone"|"status", ...}
var _active_preview: Dictionary = {}       # Non-mutating expected DMG / reaction / heal preview
var _inspect_extra_open: bool = false
var _inspect_btn_hovered: bool = false
var _end_phase_hovered: bool = false
var _pause_hovered: bool = false
var _skip_hovered: bool = false
var _action_btn_hovered: bool = false
var _pay_btn_hovered: int = -1         # 0 = cancel, 1 = confirm
var _pay_die_hovered: int = -1
var _pause_open: bool = false
var _pause_hover_idx: int = -1
var _over_hover_idx: int = -1
var _intro_t: float = INTRO_DUR
var _hotseat_cover: int = -1
var _busy_timer: float = 0.0
var _turn_timer: float = 45.0
var _last_turn_actor: int = -1
var _clock: float = 0.0

# Lightweight Visual FX & Toasts (strictly separated from rules evaluation)
var _toasts: Array[Dictionary] = []    # {"text": String, "col": Color, "ttl": float}
var _floaters: Array[Dictionary] = []  # {"text": String, "pos": Vector2, "col": Color, "ttl": float, "max_ttl": float}
var _reaction_pills: Array[Dictionary] = [] # {"title": String, "sub": String, "elements": Array, "pos": Vector2, "t": float, "dur": float}
var _ribbons: Array[Dictionary] = []        # {"title": String, "sub": String, "accent": Color, "pos": Vector2, "t": float, "dur": float, "mine": bool}
var _banners: Array[Dictionary] = []        # {"title": String, "sub": String, "color": Color, "y": float, "t": float, "dur": float}
var _card_preview: Dictionary = {}          # {"card_name": String, "t": float, "dur": float}
var _burst_flash_alpha: float = 0.0
var _lunges: Dictionary = {}                # "p_i" -> float remaining seconds
var _flying_cards: Array[Dictionary] = [] # {"card_name": String, "from": Vector2, "to": Vector2, "t": float, "dur": float}
var _hit_flash: Dictionary = {}        # "p_i" -> float remaining seconds
var _ai_timer: float = 0.72
var _own_slot_targets: Array[Vector2] = []
var _foe_slot_targets: Array[Vector2] = []
var _hand_target_pos: Vector2 = Vector2(460, 840)
var _hand_tuck_y: float = 0.0
var _roll_stage_t: float = 0.0
var _roll_phase_seen_round: int = -1
var _roll_hover_die: int = -1
var _end_round_confirm_open: bool = false
var _end_round_pill_hovered: bool = false
var _impact_fx: Array[Dictionary] = []         # {"pos": Vector2, "dtype": String, "t": float, "dur": float, "amount": int}
var _draw_reveal_cards: Array[Dictionary] = [] # {"card_name": String, "t": float, "dur": float, "slot_idx": int, "total": int}
var _turn_banner_last_actor: int = -1
var _turn_banner_last_phase: String = ""
var _slots_initialized: bool = false
var _lay: Dictionary = {}

var _overlay_canvas: Control = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_build_board_components()
	if game_state == null:
		start_demo_match("pve", 0, 1, 42)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_compute_board_layout()
		if detail_drawer != null:
			detail_drawer.sync_layout(_vp_size())
		if settings_modal != null:
			settings_modal.sync_layout(_vp_size())
		if is_inside_tree() and game_state != null:
			sync_from_state()


func _vp_size() -> Vector2:
	if size.x > 64.0 and size.y > 64.0:
		return size
	return Vector2(float(UIConstants.BASE_W), float(UIConstants.BASE_H))


func _compute_board_layout(override_size: Vector2 = Vector2.ZERO) -> Dictionary:
	var vp := override_size if override_size.x > 64.0 else _vp_size()
	var safe := UIConstants.get_safe_rect(vp)
	var cx := safe.get_center().x
	var cy := safe.get_center().y
	var left_x := safe.position.x + 10.0

	var foe_hud_pos := Vector2(left_x, safe.position.y + 4.0)
	var own_hud_pos := Vector2(left_x, safe.end.y - 76.0)
	var battle_log_pos := Vector2(left_x, safe.position.y + 80.0)
	var foe_deck_rect := Rect2(left_x + 12.0, safe.position.y + 148.0, 82.0, 114.0)
	var end_round_rect := Rect2(left_x + 10.0, safe.position.y + 392.0, 114.0, 114.0)
	var own_deck_rect := Rect2(left_x + 12.0, safe.position.y + 628.0, 82.0, 114.0)

	var dice_tray_pos := Vector2(safe.end.x - 126.0, safe.position.y + 78.0)
	var pause_btn_rect := Rect2(safe.end.x - 58.0, safe.position.y + 6.0, 52.0, 52.0)
	var skip_btn_rect := Rect2(safe.end.x - 150.0, safe.position.y + 10.0, 84.0, 38.0)
	var skill_bar_pos := Vector2(safe.end.x - 328.0, safe.end.y - 166.0)

	var arena_left := left_x + 234.0
	var arena_right := dice_tray_pos.x - 16.0
	var arena_w := maxf(640.0, arena_right - arena_left)
	var gap := clampf((arena_w - CW * 3.0) * 0.25, 22.0, 58.0)
	var char_step := CW + gap
	var char_span_half := char_step + CW * 0.5
	var row_cx := clampf(cx, arena_left + char_span_half + 12.0, arena_right - char_span_half - 12.0)
	var char_x0 := row_cx - char_span_half

	var foe_y_base := safe.position.y + 74.0
	var own_y_base := safe.position.y + 540.0

	var foe_combat_pos := Vector2(row_cx - 120.0, safe.position.y + 374.0)
	var own_combat_pos := Vector2(row_cx - 120.0, safe.position.y + 466.0)

	var hand_left_bound := own_hud_pos.x + 306.0
	var hand_right_bound := skill_bar_pos.x - 16.0
	var hand_w := clampf(hand_right_bound - hand_left_bound - 12.0, 600.0, 1120.0)
	var hand_x := clampf(cx - hand_w * 0.5, hand_left_bound, hand_right_bound - hand_w)
	var hand_normal_pos := Vector2(hand_x, safe.end.y - 234.0)
	var hand_mull_pos := Vector2(cx - hand_w * 0.5, safe.position.y + 266.0)

	var top_banner := Rect2(cx - 230.0, safe.position.y + 4.0, 460.0, 56.0)

	_lay = {
		"vp": vp,
		"safe": safe,
		"cx": cx,
		"row_cx": row_cx,
		"cy": cy,
		"left_x": left_x,
		"foe_hud_pos": foe_hud_pos,
		"own_hud_pos": own_hud_pos,
		"battle_log_pos": battle_log_pos,
		"foe_deck_rect": foe_deck_rect,
		"own_deck_rect": own_deck_rect,
		"end_round_rect": end_round_rect,
		"dice_tray_pos": dice_tray_pos,
		"pause_btn_rect": pause_btn_rect,
		"skip_btn_rect": skip_btn_rect,
		"skill_bar_pos": skill_bar_pos,
		"char_x0": char_x0,
		"char_step": char_step,
		"foe_y_base": foe_y_base,
		"own_y_base": own_y_base,
		"active_offset": 28.0,
		"foe_combat_pos": foe_combat_pos,
		"own_combat_pos": own_combat_pos,
		"hand_w": hand_w,
		"hand_normal_pos": hand_normal_pos,
		"hand_mull_pos": hand_mull_pos,
		"hand_drop_cancel_y": hand_normal_pos.y - 24.0,
		"top_banner": top_banner,
		"foe_hand_cx": cx + 336.0,
		"mulligan_confirm_rect": Rect2(cx - 140.0, hand_mull_pos.y + 244.0, 280.0, 56.0),
		"roll_confirm_rect": Rect2(safe.end.x - 208.0, dice_tray_pos.y + 552.0, 200.0, 46.0),
		"card_detail_btn_rect": Rect2(safe.position.x + 18.0, safe.position.y + 566.0, 236.0, 40.0),
		"play_preview_center": Vector2(row_cx, safe.position.y + 438.0),
	}
	return _lay


func get_zone_layout_rects(override_size: Vector2 = Vector2.ZERO) -> Dictionary:
	## Returns non-empty zone Rect2 boundaries for responsive UI verification (T0.1 / Phase 14).
	var l := _compute_board_layout(override_size) if override_size.x > 64.0 else (_lay if not _lay.is_empty() else _compute_board_layout())
	var hw: float = float(l["hand_w"])
	var hpos: Vector2 = l["hand_normal_pos"]
	var rcx: float = float(l.get("row_cx", l["cx"]))
	var cstep: float = float(l["char_step"])
	var cx0: float = float(l["char_x0"])
	var fy: float = float(l["foe_y_base"])
	var oy: float = float(l["own_y_base"])
	return {
		"safe": l["safe"],
		"foe_hud": Rect2(l["foe_hud_pos"], Vector2(292, 70)),
		"own_hud": Rect2(l["own_hud_pos"], Vector2(292, 70)),
		"battle_log": Rect2(l["battle_log_pos"], Vector2(226, 52)),
		"foe_deck": l["foe_deck_rect"],
		"own_deck": l["own_deck_rect"],
		"end_round": l["end_round_rect"],
		"dice_tray": Rect2(l["dice_tray_pos"], Vector2(118, 540)),
		"pause_btn": l["pause_btn_rect"],
		"skill_bar": Rect2(l["skill_bar_pos"], Vector2(320, 138)),
		"hand_strip": Rect2(hpos, Vector2(hw, 232)),
		"top_banner": l["top_banner"],
		"foe_char_0": Rect2(Vector2(cx0, fy), Vector2(CW, CH)),
		"foe_char_1": Rect2(Vector2(cx0 + cstep, fy), Vector2(CW, CH)),
		"foe_char_2": Rect2(Vector2(cx0 + cstep * 2.0, fy), Vector2(CW, CH)),
		"own_char_0": Rect2(Vector2(cx0, oy), Vector2(CW, CH)),
		"own_char_1": Rect2(Vector2(cx0 + cstep, oy), Vector2(CW, CH)),
		"own_char_2": Rect2(Vector2(cx0 + cstep * 2.0, oy), Vector2(CW, CH)),
		"foe_combat": Rect2(l["foe_combat_pos"], Vector2(240, 36)),
		"own_combat": Rect2(l["own_combat_pos"], Vector2(240, 36)),
		"play_preview": Rect2(Vector2(rcx - 96.0, l["safe"].position.y + 416.0), Vector2(192, 44)),
	}


func _build_board_components() -> void:
	for child in get_children():
		child.queue_free()
	own_char_slots.clear()
	foe_char_slots.clear()
	_compute_board_layout()

	# 0. Phase 1 / 8 Logic-UI Bridge & Input Guard
	animation_queue = AnimationQueue.new()
	animation_queue.name = "AnimationQueue"
	add_child(animation_queue)
	animation_queue.busy_changed.connect(_on_anim_queue_busy_changed)
	animation_queue.resync_requested.connect(resync)
	_register_animation_handlers()

	input_controller = TCGInputController.new()
	input_controller.name = "InputController"
	add_child(input_controller)

	# 1. Player & Opponent Status Banners
	foe_hud = TCGPlayerHudBanner.new()
	foe_hud.position = _lay["foe_hud_pos"]
	foe_hud.z_index = UIConstants.Z_SKILL_BAR
	add_child(foe_hud)

	own_hud = TCGPlayerHudBanner.new()
	own_hud.position = _lay["own_hud_pos"]
	own_hud.z_index = UIConstants.Z_SKILL_BAR
	add_child(own_hud)

	# 3. Character Slots (3 Opponent + 3 Player)
	for i in range(3):
		var f_slot := TCGCharacterSlot.new()
		f_slot.z_index = UIConstants.Z_CHARACTERS
		f_slot.slot_clicked.connect(_on_char_slot_clicked)
		f_slot.slot_hovered.connect(_on_char_slot_hovered)
		f_slot.status_icon_hovered.connect(_on_status_icon_hovered)
		f_slot.status_icon_clicked.connect(_on_status_icon_clicked)
		add_child(f_slot)
		foe_char_slots.append(f_slot)

	for i in range(3):
		var o_slot := TCGCharacterSlot.new()
		o_slot.z_index = UIConstants.Z_CHARACTERS
		o_slot.slot_clicked.connect(_on_char_slot_clicked)
		o_slot.slot_hovered.connect(_on_char_slot_hovered)
		o_slot.status_icon_hovered.connect(_on_status_icon_hovered)
		o_slot.status_icon_clicked.connect(_on_status_icon_clicked)
		add_child(o_slot)
		own_char_slots.append(o_slot)

	# 3b. Combat Status Icon Rows (T4.3)
	foe_combat_row = CombatStatusRow.new()
	foe_combat_row.position = _lay["foe_combat_pos"]
	foe_combat_row.z_index = UIConstants.Z_STATUSES
	foe_combat_row.status_clicked.connect(_on_status_icon_clicked)
	add_child(foe_combat_row)

	own_combat_row = CombatStatusRow.new()
	own_combat_row.position = _lay["own_combat_pos"]
	own_combat_row.z_index = UIConstants.Z_STATUSES
	own_combat_row.status_clicked.connect(_on_status_icon_clicked)
	add_child(own_combat_row)

	# 4. Battle Log Drawer (left side)
	battle_log = TCGBattleLogPanel.new()
	battle_log.position = _lay["battle_log_pos"]
	battle_log.z_index = UIConstants.Z_PANEL - 5
	add_child(battle_log)

	# 5. Dice Tray (right side)
	dice_tray = TCGDiceTray.new()
	dice_tray.position = _lay["dice_tray_pos"]
	dice_tray.z_index = UIConstants.Z_HAND
	dice_tray.die_clicked.connect(_on_tray_die_clicked)
	add_child(dice_tray)

	# 6. Skill Buttons Bar (bottom-right)
	skill_bar = TCGSkillBar.new()
	skill_bar.position = _lay["skill_bar_pos"]
	skill_bar.z_index = UIConstants.Z_SKILL_BAR
	skill_bar.skill_clicked.connect(_on_skill_clicked)
	skill_bar.skill_hovered.connect(_on_skill_hovered)
	add_child(skill_bar)

	# 7. Hand Strip (bottom-center)
	hand_strip = TCGHandStrip.new()
	hand_strip.position = _lay["hand_normal_pos"]
	hand_strip.size = Vector2(float(_lay["hand_w"]), 232.0)
	hand_strip.custom_minimum_size = hand_strip.size
	hand_strip.z_index = UIConstants.Z_HAND
	hand_strip.hand_card_clicked.connect(_on_hand_card_clicked)
	hand_strip.hand_card_right_clicked.connect(_on_hand_card_right_clicked)
	hand_strip.hand_card_drag_started.connect(_on_hand_card_drag_started)
	hand_strip.hand_card_hovered.connect(_on_hand_card_hovered)
	hand_strip.hand_card_long_pressed.connect(_on_hand_card_long_pressed)
	add_child(hand_strip)

	# 8. Pooled VFX Overlay
	vfx_pool = VFXPool.new()
	vfx_pool.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vfx_pool.z_index = UIConstants.Z_PREVIEW + 10
	add_child(vfx_pool)

	# 9. Top Overlay Layer
	_overlay_canvas = Control.new()
	_overlay_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_overlay_canvas.z_index = UIConstants.Z_BANNERS
	_overlay_canvas.draw.connect(_draw_top_overlays)
	add_child(_overlay_canvas)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	# 10. Slide-In Detail & Glossary Drawer (T9.1 - T9.6)
	detail_drawer = DetailDrawer.new()
	detail_drawer.z_index = UIConstants.Z_PANEL
	detail_drawer.sync_layout(_vp_size())
	detail_drawer.outside_click_handler = Callable(self, "_on_detail_drawer_outside_click")
	detail_drawer.drawer_closed.connect(func() -> void:
		if not _inspected.is_empty():
			_inspected.clear()
			sync_from_state()
	)
	add_child(detail_drawer)

	# 11. Settings Modal (T12.3)
	game_speed = SettingsModal.saved_speed
	confirm_before_end_round = SettingsModal.saved_confirm_end_round
	if animation_queue != null:
		animation_queue.set_speed(0.0 if game_speed >= 8.0 else game_speed)
	if vfx_pool != null:
		vfx_pool.set_speed(game_speed)
	settings_modal = SettingsModal.new()
	settings_modal.set_menu_mode(false)
	settings_modal.z_index = UIConstants.Z_MODAL
	settings_modal.sync_layout(_vp_size())
	settings_modal.speed_changed.connect(set_animation_speed)
	settings_modal.confirm_end_round_changed.connect(func(on: bool) -> void:
		confirm_before_end_round = on
	)
	settings_modal.restart_requested.connect(restart_match)
	settings_modal.main_menu_requested.connect(func() -> void:
		return_to_menu_requested.emit()
	)
	settings_modal.closed.connect(func() -> void:
		_pause_open = false
		queue_redraw()
	)
	add_child(settings_modal)


# ------------------------------------------------------------------------------
# Match Setup & Lifecycle Synchronization
# ------------------------------------------------------------------------------
func start_match_with_decks(
	p_mode: String,
	chars_0: Array,
	deck_0: Array,
	chars_1: Array,
	deck_1: Array,
	rng_seed: int = 42,
	auto_advance_to_action: bool = false,
	ai_level_0: String = "normal",
	ai_level_1: String = "normal",
	p_show_intro: bool = false
) -> void:
	match_mode = p_mode
	CardDataSystem.load_all_content()
	_last_match_config = {
		"mode": p_mode,
		"chars_0": chars_0.duplicate(),
		"deck_0": deck_0.duplicate(),
		"chars_1": chars_1.duplicate(),
		"deck_1": deck_1.duplicate(),
		"rng_seed": rng_seed,
		"auto_advance_to_action": auto_advance_to_action,
		"ai_level_0": ai_level_0,
		"ai_level_1": ai_level_1,
		"show_intro": p_show_intro,
	}

	var ctrls: Array = ["human", TCGAIPlayer.make(ai_level_1, rng_seed * 2 + 1)]
	if p_mode == "pvp":
		ctrls = ["human", "human"]
		human_flags = [true, true]
		hotseat = true
		player_labels = ["Player 1", "Player 2"]
	elif p_mode == "ava":
		ctrls = [
			TCGAIPlayer.make(ai_level_0, rng_seed * 2),
			TCGAIPlayer.make(ai_level_1, rng_seed * 2 + 1),
		]
		human_flags = [false, false]
		hotseat = false
		player_labels = ["AI 1 (%s)" % ai_level_0.capitalize(), "AI 2 (%s)" % ai_level_1.capitalize()]
	else:
		ctrls = ["human", TCGAIPlayer.make(ai_level_1, rng_seed * 2 + 1)]
		human_flags = [true, false]
		hotseat = false
		player_labels = ["You", "AI (%s)" % ai_level_1.capitalize()]

	view_player = 0
	selected_hand_index = -1
	_inspected.clear()
	_inspect_extra_open = false
	mulligan_swap_indices.clear()
	roll_selected_dice.clear()
	pay_pending.clear()
	card_swap_pending.clear()
	drag_state.clear()
	_toasts.clear()
	_floaters.clear()
	_reaction_pills.clear()
	_ribbons.clear()
	_banners.clear()
	_card_preview.clear()
	_flying_cards.clear()
	_hit_flash.clear()
	_lunges.clear()
	_impact_fx.clear()
	_draw_reveal_cards.clear()
	_hand_tuck_y = 0.0
	_roll_stage_t = 0.0
	_roll_phase_seen_round = -1
	_roll_hover_die = -1
	_end_round_confirm_open = false
	_end_round_pill_hovered = false
	_turn_banner_last_actor = -1
	_turn_banner_last_phase = ""
	_slots_initialized = false
	_pause_open = false
	_pause_hover_idx = -1
	_over_hover_idx = -1
	_hotseat_cover = -1
	_busy_timer = 0.0
	_turn_timer = 45.0
	_last_turn_actor = -1
	_intro_t = 0.0 if (p_show_intro and not auto_advance_to_action) else INTRO_DUR
	if animation_queue != null:
		animation_queue.clear_queue()
	if input_controller != null:
		input_controller.reset()
	if vfx_pool != null:
		vfx_pool.clear_all()
	if detail_drawer != null:
		detail_drawer.close_immediate()
	if settings_modal != null and settings_modal.visible:
		settings_modal.close()

	lifecycle = TCGMatchLifecycle.new()
	lifecycle.start_match(chars_0, deck_0, chars_1, deck_1, rng_seed, ctrls)
	game_state = lifecycle.state

	if hotseat and not auto_advance_to_action and p_show_intro:
		var first_act: int = lifecycle.get_actor()
		if first_act >= 0:
			view_player = first_act

	if auto_advance_to_action:
		var guard: int = 0
		while lifecycle.state.phase != "action" and guard < 12:
			var act_p: int = lifecycle.get_actor()
			if act_p < 0:
				break
			var legal := lifecycle.get_legal_actions()
			if legal.is_empty():
				break
			lifecycle.submit_action(legal[0])
			guard += 1

	if is_inside_tree() and AudioManager != null:
		AudioManager.play_music(false)

	sync_from_state()


func restart_match() -> void:
	if _last_match_config.is_empty():
		start_interactive_match(match_mode, 0, 1, 42, false)
		return
	var next_seed: int = int(_last_match_config.get("rng_seed", 42)) + 1
	start_match_with_decks(
		String(_last_match_config.get("mode", "pve")),
		_last_match_config.get("chars_0", []),
		_last_match_config.get("deck_0", []),
		_last_match_config.get("chars_1", []),
		_last_match_config.get("deck_1", []),
		next_seed,
		false,
		String(_last_match_config.get("ai_level_0", "normal")),
		String(_last_match_config.get("ai_level_1", "normal")),
		bool(_last_match_config.get("show_intro", false))
	)


func intro_active() -> bool:
	return _intro_t < INTRO_DUR


func skip_intro() -> void:
	_intro_t = INTRO_DUR
	sync_from_state()
	queue_redraw()


func dismiss_hotseat_cover() -> void:
	if _hotseat_cover >= 0:
		_hotseat_cover = -1
		sync_from_state()
		queue_redraw()


func _who(p_idx: int) -> String:
	if p_idx >= 0 and p_idx < player_labels.size():
		return player_labels[p_idx]
	return "Player %d" % (p_idx + 1)


func start_interactive_match(
	p_mode: String = "pve",
	deck0_idx: int = 0,
	deck1_idx: int = 1,
	rng_seed: int = 42,
	auto_advance_to_action: bool = false,
	ai_level_0: String = "normal",
	ai_level_1: String = "normal",
	p_show_intro: bool = false
) -> void:
	CardDataSystem.load_all_content()
	var presets: Dictionary = TCGDeckSystem.preset_decks()
	var names: Array = presets.keys()
	names.sort()
	var name0: String = String(names[clampi(deck0_idx, 0, names.size() - 1)])
	var name1: String = String(names[clampi(deck1_idx, 0, names.size() - 1)])
	var pair0: Array = presets[name0]
	var pair1: Array = presets[name1]
	start_match_with_decks(
		p_mode,
		pair0[0],
		pair0[1],
		pair1[0],
		pair1[1],
		rng_seed,
		auto_advance_to_action,
		ai_level_0,
		ai_level_1,
		p_show_intro
	)


func start_demo_match(
	p_mode: String = "pve",
	deck0_idx: int = 0,
	deck1_idx: int = 1,
	rng_seed: int = 42
) -> void:
	start_interactive_match(p_mode, deck0_idx, deck1_idx, rng_seed, true)


func me() -> TCGPlayerSystem.PlayerState:
	return game_state.players[view_player]


func actor() -> int:
	if game_state == null:
		return -1
	return TCGRulesEngine.actor(game_state)


func is_my_turn() -> bool:
	var a: int = actor()
	return a >= 0 and a == view_player and human_flags[a] and game_state.phase != "over"


func is_mulligan_stage() -> bool:
	return game_state != null and game_state.phase == "setup" and not me().mull_done and is_my_turn()


func tunable_dice(p_idx: int = -1) -> Array[int]:
	var pi: int = view_player if p_idx < 0 else p_idx
	var p: TCGPlayerSystem.PlayerState = game_state.players[pi]
	var ch: TCGPlayerSystem.CharacterInstance = p.get_active_char()
	var out: Array[int] = []
	if ch == null:
		return out
	var el: String = ch.get_defn().element
	for j in range(p.dice.size()):
		var d: String = p.dice[j]
		if d != CardDataSystem.OMNI and d != el:
			out.append(j)
	return out


func show_toast(msg: String, col: Color = TCGTheme.GOLD_L, dur: float = 2.4) -> void:
	_toasts.append({"text": msg, "col": col, "ttl": dur})
	while _toasts.size() > 4:
		_toasts.pop_front()
	queue_redraw()


func resync() -> void:
	## Phase 1 (T1.3): Hard state-to-visual resync called automatically after AnimationQueue drains.
	sync_from_state()


func set_animation_speed(speed_mult: float) -> void:
	game_speed = speed_mult
	SettingsModal.saved_speed = speed_mult
	if animation_queue != null:
		animation_queue.set_speed(0.0 if speed_mult >= 8.0 else speed_mult)
	if vfx_pool != null:
		vfx_pool.set_speed(speed_mult)
	show_toast("Animation speed: %s" % ("Instant" if speed_mult >= 8.0 else ("%.1f×" % speed_mult).replace(".0", "")), TCGTheme.GOLD_L, 1.4)


func skip_animations() -> void:
	if animation_queue != null:
		animation_queue.skip_all()
	_busy_timer = 0.0
	_flying_cards.clear()
	_card_preview.clear()
	_impact_fx.clear()
	_draw_reveal_cards.clear()
	_end_round_confirm_open = false
	if vfx_pool != null:
		vfx_pool.clear_all()
	resync()


func _queue_draw_reveal(new_cards: Array[String]) -> void:
	if new_cards.is_empty() or not is_inside_tree() or intro_active():
		return
	var show_n: int = mini(2, new_cards.size())
	_draw_reveal_cards.clear()
	for i in range(show_n):
		_draw_reveal_cards.append({
			"card_name": new_cards[new_cards.size() - show_n + i],
			"t": 0.0,
			"dur": 0.72,
			"slot_idx": i,
			"total": show_n,
		})


func _check_draw_reveal(prev_hand: Array[String], prev_phase: String) -> void:
	if game_state == null or prev_phase == "setup" or not is_inside_tree() or intro_active():
		return
	var cur_hand: Array[String] = me().hand
	if cur_hand.size() > prev_hand.size():
		var gained: Array[String] = []
		for i in range(prev_hand.size(), cur_hand.size()):
			gained.append(cur_hand[i])
		_queue_draw_reveal(gained)


func _on_anim_queue_busy_changed(busy: bool) -> void:
	if input_controller != null:
		input_controller.set_busy_locked(busy)
	if hand_strip != null:
		hand_strip.set_busy_locked(busy)
	if skill_bar != null:
		skill_bar.set_interactable(not busy)
	queue_redraw()


func _register_animation_handlers() -> void:
	if animation_queue == null:
		return
	animation_queue.clear_handlers()
	var noop_wait := func(_ev: GameEvent) -> void:
		await animation_queue.wait_sec(0.05)
	for t in [
		GameEvent.Type.DAMAGE_DEALT,
		GameEvent.Type.HEAL_APPLIED,
		GameEvent.Type.SKILL_USED,
		GameEvent.Type.REACTION_TRIGGERED,
		GameEvent.Type.CHARACTER_SWITCHED,
		GameEvent.Type.CARD_PLAYED,
		GameEvent.Type.CHARACTER_DEFEATED,
		GameEvent.Type.ROUND_STARTED,
		GameEvent.Type.ROUND_ENDED,
	]:
		animation_queue.register_handler(t, noop_wait)


# ------------------------------------------------------------------------------
# Rules-Driven Action Execution & Event Presentation
# ------------------------------------------------------------------------------
func execute_action(action: TCGGameState.ActionData) -> Dictionary:
	## Submits an ActionData to TCGMatchLifecycle / TCGRulesEngine, records
	## lightweight visual feedback from `events`, and synchronizes the board.
	if input_controller != null:
		input_controller.record_action()
	var prev_hand: Array[String] = me().hand.duplicate() if game_state != null else []
	var prev_phase: String = game_state.phase if game_state != null else ""
	_end_round_confirm_open = false
	var res: Dictionary = lifecycle.submit_action(action)
	if not bool(res.get("ok", false)):
		var err_str: String = String(res.get("error", "Illegal action"))
		if is_inside_tree() and AudioManager != null:
			AudioManager.play_sfx("ui_error")
		show_toast("Can't do that: %s" % err_str, TCGTheme.RED)
		sync_from_state()
		return res

	_present_events(res.get("events", []))
	_check_draw_reveal(prev_hand, prev_phase)
	if game_state != null and is_inside_tree() and animation_queue != null and game_speed < 8.0:
		var ev_stream: Array = game_state.consume_game_events() if game_state.has_method("consume_game_events") else []
		if not ev_stream.is_empty():
			animation_queue.push_many(ev_stream)
	selected_hand_index = -1
	_inspected.clear()
	_inspect_extra_open = false
	if detail_drawer != null:
		detail_drawer.close_immediate()
	if input_controller != null:
		input_controller.enter_idle()
	mulligan_swap_indices.clear()
	roll_selected_dice.clear()
	pay_pending.clear()
	card_swap_pending.clear()
	drag_state.clear()

	# Hotseat view switching when active human player changes
	var next_actor: int = actor()
	if hotseat and next_actor >= 0 and next_actor != view_player:
		view_player = next_actor
		if game_state != null and game_state.phase != "over":
			_hotseat_cover = next_actor

	# Reset per-turn timer & tense music check (T11.5 / T13.3)
	if next_actor != _last_turn_actor:
		_last_turn_actor = next_actor
		_turn_timer = 45.0
	if is_inside_tree() and AudioManager != null and game_state != null:
		var low_hp := false
		for p in game_state.players:
			for c in p.characters:
				if not c.defeated and c.hp <= 4:
					low_hp = true
					break
		AudioManager.play_music(game_state.round_number >= 4 or low_hp)
		if game_state.phase == "over":
			AudioManager.play_sfx("victory" if game_state.winner == view_player else "defeat")

	sync_from_state()
	return res


func _present_events(events: Array) -> void:
	if _lay.is_empty():
		_compute_board_layout()
	var safe: Rect2 = _lay.get("safe", Rect2(0, 0, 1920, 1080))
	var cx: float = float(_lay.get("cx", 960.0))
	var cy: float = float(_lay.get("cy", 540.0))
	var ribbon_pos := Vector2(cx, cy - 110.0)
	var own_ribbon_pos := Vector2(safe.position.x + 250.0, cy - 116.0)
	var foe_ribbon_pos := Vector2(safe.end.x - 320.0, cy - 116.0)
	var banner_y: float = cy - 16.0

	for ev in events:
		var kind: String = String(ev.get("kind", ""))
		match kind:
			"damage":
				var tp: int = int(ev.get("player", 0))
				var ti: int = int(ev.get("char", 0))
				var amt: int = int(ev.get("amount", 0))
				var dtype: String = String(ev.get("dtype", "Physical"))
				var rx = ev.get("reaction", null)
				var pos := _char_slot_center(tp, ti)
				var slots := own_char_slots if tp == view_player else foe_char_slots
				if ti >= 0 and ti < slots.size() and is_instance_valid(slots[ti]):
					slots[ti].trigger_hp_delta(-amt)
				_floaters.append({
					"text": "-%d" % amt,
					"pos": pos + Vector2(0, -10),
					"vel_y": -76.0,
					"col": TCGTheme.elem_color(dtype),
					"ttl": 1.5,
					"max_ttl": 1.5,
					"kind": "damage",
				})
				_impact_fx.append({
					"pos": pos,
					"dtype": dtype,
					"t": 0.0,
					"dur": 0.36,
					"amount": amt,
				})
				if vfx_pool != null:
					vfx_pool.spawn_floating_number(pos + Vector2(0, -12), "-%d" % amt, dtype, false, 1.15 if amt >= 4 else 1.0)
					vfx_pool.spawn_element_hit(pos, dtype, amt)
				if is_inside_tree() and AudioManager != null:
					AudioManager.play_element_hit(dtype)
				if rx != null and not String(rx).is_empty():
					var rx_name: String = String(rx)
					if vfx_pool != null:
						vfx_pool.spawn_reaction_fx(pos, rx_name, amt)
						vfx_pool.spawn_element_flight(pos + Vector2(-28, -42), pos, dtype)
					if is_inside_tree() and AudioManager != null:
						AudioManager.play_reaction(rx_name)
					if TCGTheme.REACT.has(rx_name):
						var r_info: Dictionary = TCGTheme.REACT[rx_name]
						_reaction_pills.append({
							"title": rx_name,
							"sub": String(r_info["desc"]),
							"elements": (r_info["elements"] as Array).duplicate(),
							"pos": pos + Vector2(0, 16),
							"t": 0.0,
							"dur": 2.4,
						})
					else:
						_reaction_pills.append({
							"title": rx_name,
							"sub": "",
							"elements": [],
							"pos": pos + Vector2(0, 16),
							"t": 0.0,
							"dur": 2.2,
						})
				_hit_flash["%d_%d" % [tp, ti]] = 0.55
			"heal":
				var tp: int = int(ev.get("player", 0))
				var ti: int = int(ev.get("char", 0))
				var amt: int = int(ev.get("amount", 0))
				var pos := _char_slot_center(tp, ti)
				var slots_h := own_char_slots if tp == view_player else foe_char_slots
				if ti >= 0 and ti < slots_h.size() and is_instance_valid(slots_h[ti]):
					slots_h[ti].trigger_hp_delta(amt)
				_floaters.append({
					"text": "+%d" % amt,
					"pos": pos + Vector2(0, -14),
					"vel_y": -68.0,
					"col": TCGTheme.HEAL,
					"ttl": 1.4,
					"max_ttl": 1.4,
					"kind": "heal",
				})
				if vfx_pool != null:
					vfx_pool.spawn_floating_number(pos + Vector2(0, -16), "+%d" % amt, "Hydro", true)
				if is_inside_tree() and AudioManager != null:
					AudioManager.play_sfx("heal")
			"cleanse":
				var cp: int = int(ev.get("player", 0))
				var ci: int = int(ev.get("char", 0))
				var cl_aura: String = String(ev.get("aura", ""))
				var cpos := _char_slot_center(cp, ci)
				var cl_name: String = game_state.players[cp].characters[ci].name if (cp >= 0 and cp < game_state.players.size() and ci >= 0 and ci < game_state.players[cp].characters.size()) else "Character"
				_impact_fx.append({
					"pos": cpos,
					"dtype": "Anemo",
					"t": 0.0,
					"dur": 0.48,
					"amount": 0,
				})
				_floaters.append({
					"text": "CLEANSED %s" % cl_aura.to_upper() if not cl_aura.is_empty() else "CLEANSED",
					"pos": cpos + Vector2(0, -34),
					"vel_y": -52.0,
					"col": TCGTheme.elem_color("Anemo"),
					"ttl": 1.7,
					"max_ttl": 1.7,
					"kind": "cleanse",
				})
				show_toast("%s cleansed %s aura!" % [cl_name, cl_aura], TCGTheme.elem_color("Anemo"), 2.2)
				_busy_timer = maxf(_busy_timer, 1.15)
			"skill":
				var sp: int = int(ev.get("player", 0))
				var sc: int = int(ev.get("char", 0))
				var sk_name: String = String(ev.get("skill", ""))
				var sk_kind: String = String(ev.get("skill_kind", ""))
				if sk_kind.is_empty():
					var sk_defn: CardDataSystem.CharData = game_state.players[sp].characters[sc].get_defn()
					if sk_defn != null and sk_defn.skills.size() >= 3 and sk_defn.skills[2].name == sk_name:
						sk_kind = "burst"
				var is_burst: bool = (sk_kind == "burst")
				_lunges["%d_%d" % [sp, sc]] = 0.55
				var who: String = _who(sp)
				var ch_obj := game_state.players[sp].characters[sc]
				var elem_col: Color = TCGTheme.elem_color(ch_obj.get_defn().element) if ch_obj.get_defn() != null else TCGTheme.GOLD
				var is_mine: bool = (sp == view_player)
				_ribbons.append({
					"title": sk_name,
					"sub": "%s · %s%s" % [who, ch_obj.name, " · Elemental Burst" if is_burst else ""],
					"accent": elem_col,
					"pos": own_ribbon_pos if is_mine else foe_ribbon_pos,
					"t": 0.0,
					"dur": 1.55 if is_burst else 1.20,
					"mine": is_mine,
					"char_name": ch_obj.name,
					"align_right": not is_mine,
				})
				_busy_timer = maxf(_busy_timer, 0.86 if is_burst else 0.54)
				if is_burst:
					_burst_flash_alpha = 0.52
					if is_inside_tree() and AudioManager != null:
						AudioManager.play_sfx("burst")
				elif is_inside_tree() and AudioManager != null:
					AudioManager.play_sfx("dice_spend")
			"switch":
				var sw_p: int = int(ev.get("player", 0))
				var sw_c: int = int(ev.get("char", 0))
				var sw_ch := game_state.players[sw_p].characters[sw_c]
				var who: String = _who(sw_p)
				var elem_col: Color = TCGTheme.elem_color(sw_ch.get_defn().element) if sw_ch.get_defn() != null else TCGTheme.GOLD
				var sw_mine: bool = (sw_p == view_player)
				_ribbons.append({
					"title": "%s steps forward" % sw_ch.name,
					"sub": "%s switched active character" % who,
					"accent": elem_col,
					"pos": own_ribbon_pos if sw_mine else foe_ribbon_pos,
					"t": 0.0,
					"dur": 1.10,
					"mine": sw_mine,
					"char_name": sw_ch.name,
					"align_right": not sw_mine,
				})
				if is_inside_tree() and AudioManager != null:
					AudioManager.play_sfx("card_hover")
				_busy_timer = maxf(_busy_timer, 0.42)
			"card":
				# Single unified Genshin card-play showcase: Player plays left, AI plays right, dissolves in golden sparks
				var cname: String = String(ev.get("name", ""))
				var cplayer: int = int(ev.get("player", 0))
				var mine_card: bool = (cplayer == view_player)
				var start_p := Vector2(cx, safe.end.y - 60.0) if mine_card else Vector2(float(_lay.get("foe_hand_cx", cx + 320.0)), safe.position.y + 44.0)
				var dest_p := Vector2(safe.position.x + 240.0, cy - 22.0) if mine_card else Vector2(safe.end.x - 260.0, cy - 22.0)
				_card_preview.clear()
				_flying_cards.clear()
				_flying_cards.append({
					"card_name": cname,
					"from": start_p,
					"to": dest_p,
					"t": 0.0,
					"dur": 0.86,
					"mine": mine_card,
				})
				if is_inside_tree() and AudioManager != null:
					AudioManager.play_sfx("card_play")
				_busy_timer = maxf(_busy_timer, 0.44)
			"summon":
				if is_inside_tree() and AudioManager != null:
					AudioManager.play_sfx("ui_click")
				show_toast("Summoned %s" % String(ev.get("name", "")), TCGTheme.TEAL, 1.8)
			"defeat":
				var dp: int = int(ev.get("player", 0))
				var di: int = int(ev.get("char", 0))
				var dch := game_state.players[dp].characters[di]
				var dpos := _char_slot_center(dp, di)
				if vfx_pool != null:
					vfx_pool.spawn_defeat_seal(dpos)
				if is_inside_tree() and AudioManager != null:
					AudioManager.play_sfx("defeat")
				_ribbons.append({
					"title": "%s was defeated" % dch.name,
					"sub": "",
					"accent": TCGTheme.RED,
					"pos": ribbon_pos,
					"t": 0.0,
					"dur": 1.8,
					"mine": (dp == view_player),
					"char_name": dch.name,
					"align_right": (dp != view_player),
				})
				_busy_timer = maxf(_busy_timer, 0.95)
				show_toast("%s was defeated!" % dch.name, TCGTheme.RED, 2.2)
			"phase":
				var pname: String = String(ev.get("name", ""))
				if pname == "action":
					_banners.append({
						"title": "Action Phase",
						"sub": "",
						"color": TCGTheme.GOLD,
						"y": banner_y,
						"t": 0.0,
						"dur": 1.45,
					})
					_busy_timer = maxf(_busy_timer, 0.65)
				elif pname == "end":
					_banners.append({
						"title": "End Phase",
						"sub": "",
						"color": TCGTheme.GOLD,
						"y": banner_y,
						"t": 0.0,
						"dur": 1.45,
					})
					_busy_timer = maxf(_busy_timer, 0.70)
			"round":
				var rnum: int = int(ev.get("number", 1))
				_roll_stage_t = 0.0
				if dice_tray != null:
					dice_tray.trigger_roll([], 0.78)
				if is_inside_tree() and AudioManager != null:
					AudioManager.play_sfx("dice_roll")
				_banners.append({
					"title": "Round %d" % rnum,
					"sub": "Roll Phase",
					"color": TCGTheme.GOLD_L,
					"y": banner_y,
					"t": 0.0,
					"dur": 1.75,
				})
				_busy_timer = maxf(_busy_timer, 0.80)
			"end_round":
				var ep: int = int(ev.get("player", 0))
				var who: String = _who(ep)
				_ribbons.append({
					"title": "%s ended the round" % who,
					"sub": "",
					"accent": TCGTheme.DIM,
					"pos": own_ribbon_pos if ep == view_player else foe_ribbon_pos,
					"t": 0.0,
					"dur": 1.25,
					"mine": (ep == view_player),
					"char_name": "",
					"align_right": (ep != view_player),
				})
				_busy_timer = maxf(_busy_timer, 0.45)


func _char_slot_center(p_idx: int, c_idx: int) -> Vector2:
	var slots := own_char_slots if p_idx == view_player else foe_char_slots
	if c_idx >= 0 and c_idx < slots.size():
		return slots[c_idx].position + slots[c_idx].size * 0.5
	return Vector2(float(_lay.get("cx", 960.0)), float(_lay.get("cy", 540.0)))


# ------------------------------------------------------------------------------
# Payment & Elemental Tuning Modal Workflow (`begin_payment`, `begin_tune`)
# ------------------------------------------------------------------------------
func _card_swap_limit(hand_idx: int) -> int:
	if game_state == null:
		return 0
	var p := me()
	if hand_idx < 0 or hand_idx >= p.hand.size():
		return 0
	var cd := CardDataSystem.get_card_def(p.hand[hand_idx])
	if cd == null:
		return 0
	for st in cd.play_steps:
		if st.op == "swap_cards":
			return maxi(1, st.amount)
	return 0


func confirm_card_swap() -> Dictionary:
	if card_swap_pending.is_empty():
		return {"ok": false, "error": "no card swap pending"}
	var sel: Array = card_swap_pending.get("selected_ids", []).duplicate()
	if sel.is_empty():
		show_toast("Select 1 or 2 cards from your hand to swap (or Cancel)", TCGTheme.GOLD_L)
		return {"ok": false, "error": "no cards selected"}
	sel.sort()
	var card_idx: int = int(card_swap_pending.get("card_idx", -1))
	var adj: Array[int] = []
	for raw_i in sel:
		var idx: int = int(raw_i)
		if idx == card_idx:
			continue
		adj.append(idx - 1 if idx > card_idx else idx)
	var act: TCGGameState.ActionData = (card_swap_pending["action"] as TCGGameState.ActionData).with_ids(adj)
	card_swap_pending.clear()
	return execute_action(act)


func cancel_card_swap() -> void:
	card_swap_pending.clear()
	selected_hand_index = -1
	sync_from_state()


func begin_payment(
	action: TCGGameState.ActionData,
	cost: CardDataSystem.CostData,
	title: String,
	detail: String = ""
) -> bool:
	if action.type == "card" and action.ids.is_empty():
		var swap_max := _card_swap_limit(action.index)
		if swap_max > 0 and me().hand.size() > 1:
			var empty_ids: Array[int] = []
			card_swap_pending = {
				"action": action,
				"card_idx": action.index,
				"selected_ids": empty_ids,
				"max_pick": mini(swap_max, me().hand.size() - 1),
			}
			selected_hand_index = -1
			_inspected.clear()
			show_toast("Click up to %d card(s) in your hand to swap, then Confirm" % int(card_swap_pending["max_pick"]), TCGTheme.GOLD_L, 2.5)
			sync_from_state()
			return true

	var total_needed: int = cost.n + cost.unaligned
	if total_needed <= 0:
		var res := execute_action(action.with_dice([]))
		return bool(res.get("ok", false))

	# Pre-populate with the rules engine's suggested dice payment (`action.dice`)
	# so the player can either confirm immediately in 1 click or customize which dice to spend.
	var preselected: Array[int] = []
	for d_idx in action.dice:
		preselected.append(int(d_idx))

	pay_pending = {
		"action": action,
		"cost": cost,
		"title": title,
		"detail": detail,
		"tune": false,
		"card_index": action.index,
		"selected_dice": preselected,
	}
	sync_from_state()
	return true


func begin_tune(hand_idx: int) -> bool:
	if not is_my_turn() or game_state.phase != "action" or not game_state.pending.is_empty():
		show_toast("Cannot perform Elemental Tuning right now", TCGTheme.RED)
		return false
	var p := me()
	if hand_idx < 0 or hand_idx >= p.hand.size():
		show_toast("Invalid hand card for Elemental Tuning", TCGTheme.RED)
		return false
	var elig := tunable_dice(view_player)
	if elig.is_empty():
		show_toast("No dice to convert (Omni and matching dice stay as they are)", TCGTheme.RED)
		return false

	var cname: String = p.hand[hand_idx]
	pay_pending = {
		"action": null,
		"cost": null,
		"title": "Elemental Tuning",
		"detail": "Convert 1 die into %s by discarding %s." % [p.get_active_char().get_defn().element, cname],
		"tune": true,
		"card_index": hand_idx,
		"selected_dice": [elig[0]],
	}
	sync_from_state()
	return true


func confirm_payment_modal() -> Dictionary:
	if pay_pending.is_empty():
		return {"ok": false, "error": "no payment pending"}

	var sel_dice: Array = pay_pending["selected_dice"].duplicate()
	sel_dice.sort()

	if bool(pay_pending.get("tune", false)):
		if sel_dice.size() != 1 or not tunable_dice(view_player).has(int(sel_dice[0])):
			show_toast("Select one non-matching die to convert", TCGTheme.RED)
			return {"ok": false, "error": "invalid tune die"}
		var c_idx: int = int(pay_pending["card_index"])
		var d_idx: int = int(sel_dice[0])
		var cname: String = me().hand[c_idx]
		var tune_act := TCGGameState.ActionData.new("tune", view_player, c_idx, d_idx)
		var res := execute_action(tune_act)
		if bool(res.get("ok", false)):
			if dice_tray != null:
				dice_tray.trigger_tune(d_idx)
			show_toast("%s converted into a %s die" % [cname, me().get_active_char().get_defn().element], TCGTheme.GOLD_L)
		return res

	var cost: CardDataSystem.CostData = pay_pending["cost"]
	if not TCGDiceSystem.payment_ok(me().dice, cost, sel_dice):
		show_toast("Choose a valid set of dice for this cost", TCGTheme.RED)
		return {"ok": false, "error": "invalid dice payment"}

	var act: TCGGameState.ActionData = (pay_pending["action"] as TCGGameState.ActionData).with_dice(sel_dice)
	return execute_action(act)


func cancel_payment_modal() -> void:
	pay_pending.clear()
	selected_hand_index = -1
	sync_from_state()


# ------------------------------------------------------------------------------
# Card Selection, Target Selection & Play Flow
# ------------------------------------------------------------------------------
func get_card_actions_for_hand_index(hand_idx: int) -> Array[TCGGameState.ActionData]:
	var out: Array[TCGGameState.ActionData] = []
	var p := me()
	if hand_idx < 0 or hand_idx >= p.hand.size():
		return out
	var cname: String = p.hand[hand_idx]
	for a in legal_actions:
		if a.player == view_player and a.type == "card" and a.index >= 0 and a.index < p.hand.size():
			if p.hand[a.index] == cname:
				out.append(a.with_index(hand_idx))
	return out


func explain_card_unplayable(cname: String) -> String:
	var cd: CardDataSystem.CardData = CardDataSystem.get_card_def(cname)
	if cd == null:
		return "Unknown card: %s" % cname
	if not is_my_turn():
		return "Wait for your turn"
	if game_state.phase != "action":
		return "Cards can only be played during the Action Phase"
	if not game_state.pending.is_empty():
		return "You must choose an active character first"

	var p := me()
	if TCGRulesEngine.is_healing_action_card(cd) and p.heal_card_used:
		return "Only 1 healing action card can be used per round (drag to Dice Tray or right-click to Tune)"
	var targets := TCGRulesEngine.card_targets(p, cd)
	if targets.is_empty():
		if cd.kind == "talent":
			var ch := p.get_active_char()
			if ch == null or ch.name != cd.char_name:
				return "Requires %s to be your active character" % cd.char_name
			if TCGRulesEngine.stunned(ch):
				return "%s is Frozen/Petrified and cannot use Talent" % ch.name
			return "Not enough Energy on %s for %s" % [ch.name, cd.name]
		if cd.kind == "weapon":
			if not cd.char_name.is_empty():
				return "%s is defeated — drag to Dice Tray or right-click to Tune into a die" % cd.char_name
			return "No alive character uses a %s (drag to Dice Tray to Tune)" % cd.weapon
		if cd.kind == "support" and p.supports.size() >= CardDataSystem.MAX_SUPPORTS:
			return "Support zone is full (max 4)"
		return "No valid target for %s" % cname

	return "Not enough matching elemental dice for %s (drag to Dice Tray or right-click to Tune)" % cname


func select_or_play_hand_card(hand_idx: int, target_char_idx: int = -2) -> Dictionary:
	## Handles clicking or dropping a hand card (`hand_idx`).
	## - In Setup Mulligan: toggles the "SWAP" marker on that card.
	## - In Action Phase:
	##   - Validates via `legal_actions` from `TCGRulesEngine`.
	##   - If `target_char_idx == -2` (clicked in hand):
	##     - If card needs no target (`target == -1`) or only 1 target is legal and card is clicked a second time, opens payment/plays it.
	##     - If card requires a character target, selects the card and highlights legal target characters.
	##   - If `target_char_idx >= -1` (dropped on board/character or target clicked):
	##     - Matches against legal target and opens payment or executes immediately if 0-cost.
	var p := me()
	if hand_idx < 0 or hand_idx >= p.hand.size():
		show_toast("Invalid hand index", TCGTheme.RED)
		return {"ok": false, "error": "invalid hand index"}

	if is_mulligan_stage():
		if mulligan_swap_indices.has(hand_idx):
			mulligan_swap_indices.erase(hand_idx)
		else:
			mulligan_swap_indices.append(hand_idx)
		sync_from_state()
		return {"ok": true, "mulligan_toggled": true}

	if not card_swap_pending.is_empty():
		var src_idx: int = int(card_swap_pending.get("card_idx", -1))
		if hand_idx == src_idx:
			show_toast("Select other cards in your hand to swap", TCGTheme.DIM)
			return {"ok": false, "error": "cannot swap source card"}
		var sel_ids: Array[int] = card_swap_pending["selected_ids"]
		var max_pick: int = int(card_swap_pending.get("max_pick", 2))
		if sel_ids.has(hand_idx):
			sel_ids.erase(hand_idx)
		elif sel_ids.size() < max_pick:
			sel_ids.append(hand_idx)
		else:
			show_toast("You can swap at most %d cards (click one to deselect)" % max_pick, TCGTheme.GOLD_L)
		sync_from_state()
		return {"ok": true, "swap_toggled": true}

	# Case 1: Clicked a card in hand (`target_char_idx == -2`)
	# Click 1 = inspect details (and highlight valid targets); Click 2 on same card = try to play
	if target_char_idx == -2:
		if selected_hand_index != hand_idx:
			selected_hand_index = hand_idx
			_inspected.clear()
			_inspect_extra_open = false
			var is_tgt_ready: bool = false
			if is_my_turn() and game_state.phase == "action" and game_state.pending.is_empty():
				var pre_cands := get_card_actions_for_hand_index(hand_idx)
				var has_untargeted: bool = false
				for a in pre_cands:
					if a.target == -1:
						has_untargeted = true
						break
				is_tgt_ready = (not pre_cands.is_empty() and not has_untargeted)
				if is_tgt_ready:
					show_toast("Select a highlighted character for %s (Esc to cancel)" % p.hand[hand_idx], TCGTheme.GOLD_L)
			sync_from_state()
			return {"ok": true, "inspected": true, "awaiting_target": is_tgt_ready}

		if not is_my_turn() or game_state.phase != "action" or not game_state.pending.is_empty():
			var reason := explain_card_unplayable(p.hand[hand_idx])
			show_toast(reason, TCGTheme.RED)
			return {"ok": false, "error": reason}

		var cname2: String = p.hand[hand_idx]
		var cd2: CardDataSystem.CardData = CardDataSystem.get_card_def(cname2)
		var cands2 := get_card_actions_for_hand_index(hand_idx)
		if cands2.is_empty():
			var reason2 := explain_card_unplayable(cname2)
			show_toast(reason2, TCGTheme.RED)
			return {"ok": false, "error": reason2}

		var untargeted: TCGGameState.ActionData = null
		for a in cands2:
			if a.target == -1:
				untargeted = a
				break
		if untargeted != null:
			begin_payment(untargeted, cd2.cost, cd2.name, cd2.text)
			return {"ok": true, "payment_opened": not pay_pending.is_empty(), "awaiting_swap": not card_swap_pending.is_empty()}

		# Character-exclusive equipment has only 1 valid owner: 2nd click equips directly
		if cands2.size() == 1 and cd2 != null and not cd2.char_name.is_empty():
			begin_payment(cands2[0], cd2.cost, cd2.name, cd2.text)
			return {"ok": true, "payment_opened": not pay_pending.is_empty(), "awaiting_swap": not card_swap_pending.is_empty()}

		show_toast("Select a highlighted character for %s (Esc to cancel)" % cname2, TCGTheme.GOLD_L)
		return {"ok": true, "awaiting_target": true}

	if not is_my_turn() or game_state.phase != "action" or not game_state.pending.is_empty():
		var reason := explain_card_unplayable(p.hand[hand_idx])
		show_toast(reason, TCGTheme.RED)
		return {"ok": false, "error": reason}

	var cname: String = p.hand[hand_idx]
	var cd: CardDataSystem.CardData = CardDataSystem.get_card_def(cname)
	var cands := get_card_actions_for_hand_index(hand_idx)
	if cands.is_empty():
		var reason := explain_card_unplayable(cname)
		show_toast(reason, TCGTheme.RED)
		return {"ok": false, "error": reason}

	# Case 2: Specific target (`target_char_idx >= 0`) or board drop (`target_char_idx == -1`)
	var matched: TCGGameState.ActionData = null
	for a in cands:
		if a.target == target_char_idx:
			matched = a
			break
	if matched == null and target_char_idx >= 0:
		# Allow dropping an untargeted card onto a character slot as well
		for a in cands:
			if a.target == -1:
				matched = a
				break
	if matched == null and target_char_idx == -1 and cands.size() == 1 and cd != null and not cd.char_name.is_empty():
		# Allow dropping a character-exclusive equipment card anywhere on the play mat
		matched = cands[0]

	if matched == null:
		show_toast("Invalid target for %s" % cname, TCGTheme.RED)
		return {"ok": false, "error": "invalid target"}

	selected_hand_index = hand_idx
	begin_payment(matched, cd.cost, cd.name, cd.text)
	return {"ok": true, "payment_opened": not pay_pending.is_empty(), "awaiting_swap": not card_swap_pending.is_empty()}


# ------------------------------------------------------------------------------
# Board State Synchronization
# ------------------------------------------------------------------------------
func sync_from_state() -> void:
	if game_state == null:
		return

	_compute_board_layout()
	legal_actions = TCGRulesEngine.legal_actions(game_state)

	var p_own: TCGPlayerSystem.PlayerState = game_state.players[view_player]
	var p_foe: TCGPlayerSystem.PlayerState = game_state.players[1 - view_player]

	var c_own: TCGPlayerSystem.CharacterInstance = p_own.get_active_char()
	if c_own == null and not p_own.characters.is_empty():
		c_own = p_own.characters[0]
	var c_foe: TCGPlayerSystem.CharacterInstance = p_foe.get_active_char()
	if c_foe == null and not p_foe.characters.is_empty():
		c_foe = p_foe.characters[0]

	var act_actor: int = actor()
	var own_elem: String = c_own.get_defn().element if (c_own != null and c_own.get_defn() != null) else "Omni"
	var foe_elem: String = c_foe.get_defn().element if (c_foe != null and c_foe.get_defn() != null) else "Omni"

	# Position responsive child zones inside safe area
	if own_hud != null:
		own_hud.position = _lay["own_hud_pos"]
		own_hud.setup(
			0,
			player_labels[view_player],
			c_own.name if c_own != null else "None",
			own_elem,
			act_actor == view_player and game_state.phase == "action",
			p_own.ended,
			false,
			p_own.dice.size(),
			p_own.hand.size(),
			p_own.ended and not p_foe.ended
		)
	if foe_hud != null:
		foe_hud.position = _lay["foe_hud_pos"]
		foe_hud.setup(
			1,
			player_labels[1 - view_player],
			c_foe.name if c_foe != null else "None",
			foe_elem,
			act_actor == (1 - view_player) and game_state.phase == "action",
			p_foe.ended,
			true,
			p_foe.dice.size(),
			p_foe.hand.size(),
			p_foe.ended and not p_own.ended
		)

	# 2. Summons and Supports removed (streamlined 3v3 board)

	# 3. Determine valid character targets for selected/dragged card or switch/choose_active
	var valid_char_targets: Dictionary = {}
	var active_card_idx: int = int(drag_state.get("hand_index", selected_hand_index))
	if active_card_idx >= 0 and active_card_idx < p_own.hand.size():
		for a in get_card_actions_for_hand_index(active_card_idx):
			if a.target >= 0:
				valid_char_targets[a.target] = true

	var clickable_chars: Dictionary = {}
	if is_my_turn():
		for a in legal_actions:
			if a.player == view_player and (a.type == "choose_active" or a.type == "switch"):
				clickable_chars[a.index] = true
				if a.type == "choose_active":
					valid_char_targets[a.index] = true

	var own_team_shield := 0
	for cs in p_own.combat:
		own_team_shield += maxi(0, cs.shield)
	var foe_team_shield := 0
	for cs in p_foe.combat:
		foe_team_shield += maxi(0, cs.shield)

	# 3b. Compute non-mutating live preview of clicked/selected Skill, Card, or Pending Action
	_active_preview = _compute_active_action_preview(active_card_idx, valid_char_targets)
	var foe_prev_map: Dictionary = _active_preview.get("foe_chars", {}) if bool(_active_preview.get("ok", false)) else {}
	var own_prev_map: Dictionary = _active_preview.get("own_chars", {}) if bool(_active_preview.get("ok", false)) else {}

	# 4. Update Character Slots (T2.3 active offset +-34px, T3.8 shield totals, T3.11 invalid dim, combat forecast)
	_foe_slot_targets.resize(3)
	_own_slot_targets.resize(3)
	var snap_layout: bool = (not _slots_initialized) or (not is_inside_tree())
	var cx0: float = float(_lay["char_x0"])
	var cstep: float = float(_lay["char_step"])
	var fy_base: float = float(_lay["foe_y_base"])
	var oy_base: float = float(_lay["own_y_base"])
	var act_off: float = float(_lay["active_offset"])
	var has_target_mode: bool = (not valid_char_targets.is_empty())

	for i in range(3):
		var slot_idx_foe: int = 2 - i
		var x_foe: float = cx0 + float(slot_idx_foe) * cstep
		var is_act_foe: bool = (p_foe.active == i)
		var y_foe: float = fy_base + (act_off if is_act_foe else 0.0)
		_foe_slot_targets[i] = Vector2(x_foe, y_foe)
		if snap_layout:
			foe_char_slots[i].position = _foe_slot_targets[i]
		var f_flash: float = float(_hit_flash.get("%d_%d" % [1 - view_player, i], 0.0))
		var f_lunge_t: float = float(_lunges.get("%d_%d" % [1 - view_player, i], 0.0))
		var f_lunge_offset := Vector2(0.0, sin((1.0 - f_lunge_t / 0.55) * PI) * 24.0) if f_lunge_t > 0.0 else Vector2.ZERO
		var f_sh := foe_team_shield if is_act_foe else 0
		for fst in p_foe.characters[i].statuses:
			f_sh += maxi(0, fst.shield)
		foe_char_slots[i].setup(1, i, p_foe.characters[i], is_act_foe, false, false, false, -1, f_flash, f_lunge_offset, f_sh, false, foe_prev_map.get(i, {}))

		var x_own: float = cx0 + float(i) * cstep
		var is_act_own: bool = (p_own.active == i)
		var y_own: float = oy_base - (act_off if is_act_own else 0.0)
		_own_slot_targets[i] = Vector2(x_own, y_own)
		if snap_layout:
			own_char_slots[i].position = _own_slot_targets[i]
		var o_flash: float = float(_hit_flash.get("%d_%d" % [view_player, i], 0.0))
		var o_lunge_t: float = float(_lunges.get("%d_%d" % [view_player, i], 0.0))
		var o_lunge_offset := Vector2(0.0, -sin((1.0 - o_lunge_t / 0.55) * PI) * 24.0) if o_lunge_t > 0.0 else Vector2.ZERO
		var o_sh := own_team_shield if is_act_own else 0
		for ost in p_own.characters[i].statuses:
			o_sh += maxi(0, ost.shield)
		var dim_invalid := has_target_mode and not valid_char_targets.has(i)
		own_char_slots[i].setup(
			0,
			i,
			p_own.characters[i],
			is_act_own,
			false,
			valid_char_targets.has(i),
			clickable_chars.has(i),
			-1,
			o_flash,
			o_lunge_offset,
			o_sh,
			dim_invalid,
			own_prev_map.get(i, {})
		)

	# 4b. Combat Status Icon Rows (T4.3)
	if foe_combat_row != null:
		foe_combat_row.position = _lay["foe_combat_pos"]
		foe_combat_row.sync_statuses(p_foe.combat, foe_elem)
	if own_combat_row != null:
		own_combat_row.position = _lay["own_combat_pos"]
		own_combat_row.sync_statuses(p_own.combat, own_elem)

	# 5. Update Dice Tray (T6.1 - T6.7)
	if dice_tray != null:
		dice_tray.position = _lay["dice_tray_pos"]
	var hl_dice: Array[int] = []
	if is_my_turn() and _hovered_skill_idx >= 0:
		for a in legal_actions:
			if a.player == view_player and a.type == "skill" and a.index == _hovered_skill_idx:
				for d_i in a.dice:
					hl_dice.append(int(d_i))
				break
	elif is_my_turn() and not _hovered_card_name.is_empty():
		for a in legal_actions:
			if a.player == view_player and a.type == "card" and a.index >= 0 and a.index < p_own.hand.size() and p_own.hand[a.index] == _hovered_card_name:
				for d_i in a.dice:
					hl_dice.append(int(d_i))
				break

	var tray_selected: Array[int] = []
	if game_state.phase == "roll":
		tray_selected = roll_selected_dice.duplicate()
	var pay_need := 0
	if not pay_pending.is_empty():
		var pc: CardDataSystem.CostData = pay_pending.get("cost", null)
		pay_need = 1 if bool(pay_pending.get("tune", false)) else (pc.total_dice() if pc != null else 0)
	dice_tray.setup(
		p_own.dice,
		tray_selected,
		hl_dice,
		not drag_state.is_empty(),
		tunable_dice(view_player),
		own_elem,
		pay_need,
		p_own.rerolls if game_state.phase == "roll" else 0
	)

	# 6. Update Skill Bar
	if skill_bar != null:
		skill_bar.position = _lay["skill_bar_pos"]
	var skill_ok := [false, false, false]
	for a in legal_actions:
		if a.player == view_player and a.type == "skill" and a.index >= 0 and a.index < 3:
			skill_ok[a.index] = true

	var usable_skills: Array[bool] = [
		is_my_turn() and bool(skill_ok[0]),
		is_my_turn() and bool(skill_ok[1]),
		is_my_turn() and bool(skill_ok[2]),
	]
	var eff_costs: Array[CardDataSystem.CostData] = []
	if c_own != null and c_own.get_defn() != null:
		for s_idx in range(c_own.get_defn().skills.size()):
			eff_costs.append(c_own.get_defn().skills[s_idx].cost)
	skill_bar.visible = (game_state.phase == "action" and c_own != null)
	var sel_skill: int = int(_inspected.get("index", -1)) if String(_inspected.get("kind", "")) == "skill" else -1
	skill_bar.setup(c_own, usable_skills, eff_costs, sel_skill)

	# 7. Update Hand Strip (Mulligan center-screen vs normal bottom strip)
	var card_ok_by_name: Dictionary = {}
	for a in legal_actions:
		if a.player == view_player and a.type == "card" and a.index >= 0 and a.index < p_own.hand.size():
			card_ok_by_name[p_own.hand[a.index]] = true

	var playable_cards: Array[bool] = []
	for h_idx in range(p_own.hand.size()):
		var cname: String = p_own.hand[h_idx]
		playable_cards.append(is_my_turn() and game_state.phase == "action" and card_ok_by_name.has(cname))

	var in_mulligan: bool = is_mulligan_stage() and not intro_active()
	hand_strip.visible = not (intro_active() and game_state.phase != "over")
	hand_strip.z_index = (UIConstants.Z_BANNERS + 1) if (in_mulligan and not _pause_open and _hotseat_cover < 0) else UIConstants.Z_HAND
	hand_strip.size = Vector2(float(_lay["hand_w"]), 232.0)
	hand_strip.custom_minimum_size = hand_strip.size
	_hand_target_pos = _lay["hand_mull_pos"] if in_mulligan else _lay["hand_normal_pos"]
	if (not _slots_initialized) or (not is_inside_tree()):
		hand_strip.position = _hand_target_pos
		_slots_initialized = true
	var deck_r: Rect2 = _lay["own_deck_rect"]
	hand_strip.set_draw_origin(deck_r.get_center() - hand_strip.position)
	var swap_marks: Array[int] = mulligan_swap_indices if card_swap_pending.is_empty() else (card_swap_pending["selected_ids"] as Array[int])
	# Own bottom hand is ALWAYS face-up (just like Genshin TCG); only obscured during local PvP device handoff cover.
	hand_strip.setup(
		p_own.hand,
		playable_cards,
		selected_hand_index,
		swap_marks,
		in_mulligan,
		_hotseat_cover >= 0,
		int(drag_state.get("hand_index", -1)),
		is_my_turn() and game_state.phase == "action" and not in_mulligan and card_swap_pending.is_empty(),
		not card_swap_pending.is_empty()
	)

	# 8. Update Battle Log
	if battle_log != null:
		battle_log.position = _lay["battle_log_pos"]
		battle_log.setup(game_state.log)

	# 9. Sync Center Roll Stage entrance & Turn-Handoff Ribbons
	if _is_center_roll_stage() and _roll_phase_seen_round != game_state.round_number:
		_roll_phase_seen_round = game_state.round_number
		_roll_stage_t = 0.0
	if not is_my_turn() or game_state.phase != "action":
		_end_round_confirm_open = false
	if is_inside_tree() and not intro_active() and game_state.phase == "action":
		if _turn_banner_last_phase == "action" and act_actor >= 0 and act_actor != _turn_banner_last_actor and _banners.is_empty():
			var cy_b: float = float(_lay.get("cy", 540.0)) - 16.0
			var my_turn_now: bool = (act_actor == view_player and human_flags[act_actor])
			var t_title: String = "Your Turn" if my_turn_now else ("%s's Turn…" % _who(act_actor))
			_banners.append({
				"title": t_title,
				"sub": "",
				"color": TCGTheme.GOLD_L if my_turn_now else TCGTheme.TEXT,
				"y": cy_b,
				"t": 0.0,
				"dur": 1.05,
			})
		_turn_banner_last_actor = act_actor
		_turn_banner_last_phase = game_state.phase
	else:
		_turn_banner_last_phase = game_state.phase
		if game_state.phase != "action":
			_turn_banner_last_actor = -1

	queue_redraw()


func _compute_active_action_preview(active_card_idx: int, valid_char_targets: Dictionary) -> Dictionary:
	if game_state == null or game_state.phase == "over" or game_state.phase == "setup":
		return {}

	var res: Dictionary = {}
	if not pay_pending.is_empty() and not bool(pay_pending.get("tune", false)):
		var pact = pay_pending.get("action", null)
		if pact is TCGGameState.ActionData:
			var ad := pact as TCGGameState.ActionData
			if ad.type == "skill":
				res = TCGRulesEngine.preview_skill(game_state, view_player, ad.index)
			elif ad.type == "card":
				res = TCGRulesEngine.preview_card(game_state, view_player, ad.index, ad.target)
	elif String(_inspected.get("kind", "")) == "skill":
		var sk_idx: int = int(_inspected.get("index", -1))
		if sk_idx >= 0:
			res = TCGRulesEngine.preview_skill(game_state, view_player, sk_idx)
	elif active_card_idx >= 0 and active_card_idx < me().hand.size():
		var tgt_idx: int = _hovered_char_idx if (_hovered_char_side == 0 and valid_char_targets.has(_hovered_char_idx)) else -1
		res = TCGRulesEngine.preview_card(game_state, view_player, active_card_idx, tgt_idx)

	if bool(res.get("ok", false)) and not is_my_turn() and game_state.phase == "action":
		res["can_use_now"] = false
		if String(res.get("block_reason", "")).is_empty():
			res["block_reason"] = "Wait for your turn"
			var lines: Array = res.get("summary_lines", [])
			lines.append("Note: Wait for your turn")
			res["summary_lines"] = lines
	return res


# ------------------------------------------------------------------------------
# Process Loop (Animations & AI Turn Execution)
# ------------------------------------------------------------------------------
func _process(delta: float) -> void:
	_clock += delta
	var dirty: bool = false

	# Advance Turn Timer cleanly when human is acting in Action/Roll Phase (T11.5)
	if game_state != null and game_state.phase in ["action", "roll"] and is_my_turn() and not _pause_open and not intro_active() and _hotseat_cover < 0:
		var prev_sec := ceili(_turn_timer)
		_turn_timer = maxf(0.0, _turn_timer - delta)
		if ceili(_turn_timer) != prev_sec:
			dirty = true

	# Smoothly glide character slots and hand strip toward their layout targets
	var k_pos: float = 1.0 - exp(-12.0 * delta * game_speed)
	if _foe_slot_targets.size() == 3 and foe_char_slots.size() == 3:
		for i in range(3):
			if not foe_char_slots[i].position.is_equal_approx(_foe_slot_targets[i]):
				foe_char_slots[i].position = foe_char_slots[i].position.lerp(_foe_slot_targets[i], k_pos)
			if not own_char_slots[i].position.is_equal_approx(_own_slot_targets[i]):
				own_char_slots[i].position = own_char_slots[i].position.lerp(_own_slot_targets[i], k_pos)
	if hand_strip != null:
		var in_mull_p: bool = is_mulligan_stage() and not intro_active()
		var near_bottom: bool = (
			_hover_mouse_pos.y >= _hand_target_pos.y + 22.0
			and _hover_mouse_pos.x >= _hand_target_pos.x - 24.0
			and _hover_mouse_pos.x <= _hand_target_pos.x + hand_strip.size.x + 24.0
		)
		var hand_engaged: bool = (
			pay_pending.is_empty()
			and (
				in_mull_p
				or not card_swap_pending.is_empty()
				or selected_hand_index >= 0
				or not drag_state.is_empty()
				or hand_strip.is_engaged()
				or near_bottom
				or not is_inside_tree()
			)
		)
		var target_tuck: float = 112.0 if (not pay_pending.is_empty() and is_inside_tree()) else (0.0 if hand_engaged else 64.0)
		_hand_tuck_y = lerpf(_hand_tuck_y, target_tuck, k_pos)
		var desired_hand_pos := _hand_target_pos + Vector2(0.0, _hand_tuck_y)
		if not hand_strip.position.is_equal_approx(desired_hand_pos):
			hand_strip.position = hand_strip.position.lerp(desired_hand_pos, k_pos)

	# Center Roll Stage tumble timer
	if _is_center_roll_stage() and _roll_stage_t < 1.2:
		_roll_stage_t = minf(1.2, _roll_stage_t + delta * game_speed)
		dirty = true

	# Center End-Phase / Draw Cards reveal showcase
	for i in range(_draw_reveal_cards.size() - 1, -1, -1):
		_draw_reveal_cards[i]["t"] = float(_draw_reveal_cards[i]["t"]) + delta * game_speed
		if float(_draw_reveal_cards[i]["t"]) >= float(_draw_reveal_cards[i]["dur"]):
			_draw_reveal_cards.remove_at(i)
		dirty = true

	# Elemental slash/bolt impact VFX
	for i in range(_impact_fx.size() - 1, -1, -1):
		_impact_fx[i]["t"] = float(_impact_fx[i]["t"]) + delta * game_speed
		if float(_impact_fx[i]["t"]) >= float(_impact_fx[i]["dur"]):
			_impact_fx.remove_at(i)
		dirty = true

	# Center play card preview TTL (T5.9)
	if not _card_preview.is_empty():
		_card_preview["t"] = float(_card_preview["t"]) + delta * game_speed
		if float(_card_preview["t"]) >= float(_card_preview["dur"]):
			_card_preview.clear()
		dirty = true

	# Update toast timers
	for i in range(_toasts.size() - 1, -1, -1):
		_toasts[i]["ttl"] = float(_toasts[i]["ttl"]) - delta
		if float(_toasts[i]["ttl"]) <= 0.0:
			_toasts.remove_at(i)
		dirty = true

	# Update damage/heal floaters with smooth upward deceleration
	for i in range(_floaters.size() - 1, -1, -1):
		_floaters[i]["ttl"] = float(_floaters[i]["ttl"]) - delta
		var vy: float = float(_floaters[i].get("vel_y", -36.0))
		_floaters[i]["pos"] = (_floaters[i]["pos"] as Vector2) + Vector2(0, vy * delta)
		_floaters[i]["vel_y"] = vy * exp(-3.2 * delta)
		if float(_floaters[i]["ttl"]) <= 0.0:
			_floaters.remove_at(i)
		dirty = true

	# Update flying played cards
	for i in range(_flying_cards.size() - 1, -1, -1):
		_flying_cards[i]["t"] = float(_flying_cards[i]["t"]) + delta * game_speed
		if float(_flying_cards[i]["t"]) >= float(_flying_cards[i]["dur"]):
			_flying_cards.remove_at(i)
		dirty = true

	# Update reaction pills
	for i in range(_reaction_pills.size() - 1, -1, -1):
		_reaction_pills[i]["t"] = float(_reaction_pills[i]["t"]) + delta * game_speed
		if float(_reaction_pills[i]["t"]) >= float(_reaction_pills[i]["dur"]):
			_reaction_pills.remove_at(i)
		dirty = true

	# Update action ribbons
	for i in range(_ribbons.size() - 1, -1, -1):
		_ribbons[i]["t"] = float(_ribbons[i]["t"]) + delta * game_speed
		if float(_ribbons[i]["t"]) >= float(_ribbons[i]["dur"]):
			_ribbons.remove_at(i)
		dirty = true

	# Update phase announcement banners
	for i in range(_banners.size() - 1, -1, -1):
		_banners[i]["t"] = float(_banners[i]["t"]) + delta * game_speed
		if float(_banners[i]["t"]) >= float(_banners[i]["dur"]):
			_banners.remove_at(i)
		dirty = true

	# Update character hit flashes and lunges
	for k in _hit_flash.keys():
		var rem: float = float(_hit_flash[k]) - delta
		if rem <= 0.0:
			_hit_flash.erase(k)
		else:
			_hit_flash[k] = rem
		dirty = true

	for k in _lunges.keys():
		var rem: float = float(_lunges[k]) - delta * game_speed
		if rem <= 0.0:
			_lunges.erase(k)
		else:
			_lunges[k] = rem
		dirty = true

	# Push frame-by-frame hit-flash & attack lunge offsets to character slots
	if foe_char_slots.size() == 3 and own_char_slots.size() == 3:
		for i in range(3):
			var f_flash: float = float(_hit_flash.get("%d_%d" % [1 - view_player, i], 0.0))
			var f_lunge_t: float = float(_lunges.get("%d_%d" % [1 - view_player, i], 0.0))
			var f_lunge := Vector2(0.0, sin((1.0 - f_lunge_t / 0.55) * PI) * 24.0) if f_lunge_t > 0.0 else Vector2.ZERO
			foe_char_slots[i].set_anim_state(f_flash, f_lunge)

			var o_flash: float = float(_hit_flash.get("%d_%d" % [view_player, i], 0.0))
			var o_lunge_t: float = float(_lunges.get("%d_%d" % [view_player, i], 0.0))
			var o_lunge := Vector2(0.0, -sin((1.0 - o_lunge_t / 0.55) * PI) * 24.0) if o_lunge_t > 0.0 else Vector2.ZERO
			own_char_slots[i].set_anim_state(o_flash, o_lunge)

	if _burst_flash_alpha > 0.001:
		_burst_flash_alpha = maxf(0.0, _burst_flash_alpha - 2.5 * delta * game_speed)
		dirty = true

	if _intro_t < INTRO_DUR and not _pause_open:
		_intro_t = minf(INTRO_DUR, _intro_t + delta)
		if _intro_t >= INTRO_DUR:
			sync_from_state()
		dirty = true

	if _busy_timer > 0.0 and not _pause_open:
		_busy_timer = maxf(0.0, _busy_timer - delta * game_speed)

	# Step AI controller when active player is non-human
	if game_state != null and game_state.phase != "over" and not _pause_open and _hotseat_cover < 0 and not intro_active() and _busy_timer <= 0.0:
		var act_p: int = actor()
		if act_p >= 0 and not human_flags[act_p]:
			_ai_timer -= delta * game_speed
			if _ai_timer <= 0.0:
				_ai_timer = 0.72
				var ai_prev_hand: Array[String] = me().hand.duplicate()
				var ai_prev_phase: String = game_state.phase
				var ai_res := lifecycle.step_ai_if_ready()
				if bool(ai_res.get("ok", false)):
					_present_events(ai_res.get("events", []))
					_check_draw_reveal(ai_prev_hand, ai_prev_phase)
					sync_from_state()
					dirty = true

	if dirty:
		queue_redraw()


func _is_ui_modal_blocking() -> bool:
	return (
		_pause_open
		or (settings_modal != null and settings_modal.visible)
		or _hotseat_cover >= 0
		or intro_active()
		or (game_state != null and game_state.phase == "over")
		or not pay_pending.is_empty()
	)


func _is_gameplay_locked() -> bool:
	if animation_queue != null and animation_queue.is_busy():
		return true
	if input_controller != null and not input_controller.can_accept_gameplay_input():
		return true
	return false


# ------------------------------------------------------------------------------
# UI Component Signal Handlers & Input Events
# ------------------------------------------------------------------------------
func _on_hand_card_clicked(hand_idx: int, _card_name: String) -> void:
	if _is_ui_modal_blocking():
		return
	if selected_hand_index == hand_idx and _is_gameplay_locked():
		return
	if is_inside_tree() and AudioManager != null:
		AudioManager.play_sfx("ui_click")
	select_or_play_hand_card(hand_idx, -2)


func _on_hand_card_right_clicked(hand_idx: int, _card_name: String) -> void:
	if _is_ui_modal_blocking() or _is_gameplay_locked():
		return
	begin_tune(hand_idx)


func _on_hand_card_long_pressed(_hand_idx: int, c_name: String) -> void:
	if _is_ui_modal_blocking() or c_name.is_empty():
		return
	if detail_drawer != null:
		detail_drawer.open_card(c_name)


func _on_hand_card_drag_started(hand_idx: int, c_name: String, global_pos: Vector2) -> void:
	if _is_ui_modal_blocking() or is_mulligan_stage() or not card_swap_pending.is_empty() or _is_gameplay_locked():
		return
	if not is_my_turn() or game_state.phase != "action" or not game_state.pending.is_empty():
		if hand_strip != null:
			hand_strip.trigger_card_shake(hand_idx)
		if is_inside_tree() and AudioManager != null:
			AudioManager.play_sfx("ui_error")
		show_toast(explain_card_unplayable(c_name), TCGTheme.RED)
		return
	selected_hand_index = hand_idx
	if input_controller != null:
		input_controller.enter_card_selected(hand_idx)
	drag_state = {
		"hand_index": hand_idx,
		"card_name": c_name,
		"pos": global_pos - global_position,
	}
	sync_from_state()


func _finish_card_drag(local_pos: Vector2) -> void:
	if drag_state.is_empty():
		return
	var hand_idx: int = int(drag_state["hand_index"])
	drag_state.clear()

	# 1. Dropped onto the Dice Tray -> Elemental Tuning (`ui/match.py:548-551`)
	var tray_rect := Rect2(dice_tray.position, dice_tray.size).grow(12.0)
	if tray_rect.has_point(local_pos):
		var die_idx: int = dice_tray.get_die_at_global_pos(global_position + local_pos)
		if die_idx >= 0 and tunable_dice(view_player).has(die_idx):
			var cname: String = me().hand[hand_idx]
			var tune_act := TCGGameState.ActionData.new("tune", view_player, hand_idx, die_idx)
			var res := execute_action(tune_act)
			if bool(res.get("ok", false)):
				if dice_tray != null:
					dice_tray.trigger_tune(die_idx)
				if vfx_pool != null and dice_tray != null:
					vfx_pool.spawn_dice_spend_sparks(local_pos, dice_tray.get_die_global_center(die_idx) - global_position, me().get_active_char().get_defn().element)
				if is_inside_tree() and AudioManager != null:
					AudioManager.play_sfx("dice_tune")
				show_toast("%s converted into a %s die" % [cname, me().get_active_char().get_defn().element], TCGTheme.GOLD_L)
			return
		begin_tune(hand_idx)
		return

	# 2. Dropped back onto the hand region -> cancel drag cleanly using layout-aware Y threshold
	var cancel_y: float = float(_lay.get("hand_drop_cancel_y", 820.0))
	if local_pos.y > cancel_y:
		selected_hand_index = -1
		sync_from_state()
		return

	# 3. Dropped onto one of the player's 3 character slots
	for k in range(3):
		var c_rect := Rect2(own_char_slots[k].position, own_char_slots[k].size).grow(8.0)
		if c_rect.has_point(local_pos):
			select_or_play_hand_card(hand_idx, k)
			return

	# 4. Dropped onto the general play mat -> play untargeted card (`target == -1`)
	select_or_play_hand_card(hand_idx, -1)


func _is_choose_active_phase() -> bool:
	if game_state == null or not is_my_turn():
		return false
	for a in legal_actions:
		if a.player == view_player and a.type == "choose_active":
			return true
	return false


func _on_detail_drawer_outside_click(pos: Vector2) -> bool:
	if _is_ui_modal_blocking():
		return false
	for i in range(foe_char_slots.size()):
		var fslot := foe_char_slots[i]
		if fslot != null and fslot.visible and Rect2(fslot.position, fslot.size).has_point(pos):
			_on_char_slot_clicked(1, i)
			return true
	for i in range(own_char_slots.size()):
		var oslot := own_char_slots[i]
		if oslot != null and oslot.visible and Rect2(oslot.position, oslot.size).has_point(pos):
			_on_char_slot_clicked(0, i)
			return true
	return false


func _on_char_slot_clicked(p_side: int, p_idx: int) -> void:
	if _is_ui_modal_blocking():
		return

	# 1. If a hand card is currently selected for targeting, apply it to own character
	if selected_hand_index >= 0 and game_state.phase == "action" and p_side == 0 and is_my_turn():
		if _is_gameplay_locked():
			return
		select_or_play_hand_card(selected_hand_index, p_idx)
		return

	# 2. During active character selection (setup or forced switch), one left-click immediately selects
	if p_side == 0 and _is_choose_active_phase():
		_inspected.clear()
		selected_hand_index = -1
		_inspect_extra_open = false
		if detail_drawer != null:
			detail_drawer.close_immediate()
		if _is_gameplay_locked():
			sync_from_state()
			return
		for a in legal_actions:
			if a.player == view_player and a.type == "choose_active" and a.index == p_idx:
				if is_inside_tree() and AudioManager != null:
					AudioManager.play_sfx("ui_click")
				execute_action(a)
				return
		show_toast("Cannot select that character as active", TCGTheme.RED)
		sync_from_state()
		return

	# 3. Click 1 = inspect details (even while busy, T1.2/T8.4); Click 2 = act/switch (or close inspect)
	var already_inspected: bool = (
		String(_inspected.get("kind", "")) == "char"
		and int(_inspected.get("side", -1)) == p_side
		and int(_inspected.get("index", -1)) == p_idx
	)
	if not already_inspected:
		selected_hand_index = -1
		_inspect_extra_open = false
		_inspected = {"kind": "char", "side": p_side, "index": p_idx}
		if detail_drawer != null:
			var p_idx_owner := view_player if p_side == 0 else (1 - view_player)
			var own_p := game_state.players[p_idx_owner]
			if p_idx >= 0 and p_idx < own_p.characters.size():
				detail_drawer.open_character(own_p.characters[p_idx], own_p)
		if is_inside_tree() and AudioManager != null:
			AudioManager.play_sfx("ui_click")
		sync_from_state()
		return

	_inspected.clear()
	if detail_drawer != null:
		detail_drawer.close_immediate()
	if p_side != 0:
		sync_from_state()
		return

	if _is_gameplay_locked():
		sync_from_state()
		return
	if not is_my_turn():
		show_toast("Wait for your turn", TCGTheme.RED)
		sync_from_state()
		return

	# 4. Action Phase character switch
	if game_state.phase == "action":
		if me().active == p_idx:
			show_toast("%s is already your active character" % me().characters[p_idx].name, TCGTheme.DIM)
			sync_from_state()
			return
		for a in legal_actions:
			if a.player == view_player and a.type == "switch" and a.index == p_idx:
				var target_ch := me().characters[p_idx]
				begin_payment(
					a,
					TCGRulesEngine.switch_cost(me()),
					"Switch to %s" % target_ch.name,
					"Fast/Combat Action: Switch active character to %s." % target_ch.name
				)
				return
		if me().characters[p_idx].defeated:
			show_toast("%s has been defeated" % me().characters[p_idx].name, TCGTheme.RED)
		else:
			show_toast("Not enough dice to switch character", TCGTheme.RED)
	sync_from_state()


func _on_skill_clicked(skill_idx: int) -> void:
	if _is_ui_modal_blocking():
		return

	# Click 1 = inspect skill details & select (allowed even while busy); Click 2 = use
	var already_inspected: bool = (
		String(_inspected.get("kind", "")) == "skill"
		and int(_inspected.get("index", -1)) == skill_idx
	)
	if not already_inspected:
		selected_hand_index = -1
		_inspect_extra_open = false
		_inspected = {"kind": "skill", "index": skill_idx}
		if is_inside_tree() and AudioManager != null:
			AudioManager.play_sfx("ui_click")
		sync_from_state()
		return

	_inspected.clear()
	if _is_gameplay_locked():
		sync_from_state()
		return
	if not is_my_turn() or game_state.phase != "action" or not game_state.pending.is_empty():
		show_toast("Skills can only be used on your turn during the Action Phase", TCGTheme.RED)
		sync_from_state()
		return

	var ch := me().get_active_char()
	if ch == null:
		sync_from_state()
		return
	if TCGRulesEngine.stunned(ch):
		show_toast("%s is Frozen/Petrified and cannot use skills" % ch.name, TCGTheme.RED)
		sync_from_state()
		return

	var sk: CardDataSystem.SkillData = ch.get_defn().skills[skill_idx]
	for a in legal_actions:
		if a.player == view_player and a.type == "skill" and a.index == skill_idx:
			begin_payment(a, sk.cost, sk.name, sk.desc)
			return

	if is_inside_tree() and AudioManager != null:
		AudioManager.play_sfx("ui_error")
	if sk.cost.energy > 0 and ch.energy < sk.cost.energy:
		show_toast("Not enough Energy for %s (%d/%d)" % [sk.name, ch.energy, sk.cost.energy], TCGTheme.RED)
	else:
		show_toast("Not enough matching dice for %s" % sk.name, TCGTheme.RED)
	sync_from_state()


func _on_tray_die_clicked(die_idx: int) -> void:
	if _is_ui_modal_blocking() or _is_gameplay_locked():
		return
	if is_my_turn() and game_state.phase == "roll":
		if roll_selected_dice.has(die_idx):
			roll_selected_dice.erase(die_idx)
		else:
			roll_selected_dice.append(die_idx)
		if is_inside_tree() and AudioManager != null:
			AudioManager.play_sfx("ui_click")
		sync_from_state()
	elif is_my_turn() and game_state.phase == "action" and selected_hand_index >= 0:
		# If a card is selected and player clicks a die on the tray, convert that die via Elemental Tuning
		if tunable_dice(view_player).has(die_idx):
			var cname: String = me().hand[selected_hand_index]
			var tune_act := TCGGameState.ActionData.new("tune", view_player, selected_hand_index, die_idx)
			var res := execute_action(tune_act)
			if bool(res.get("ok", false)):
				if dice_tray != null:
					dice_tray.trigger_tune(die_idx)
				if is_inside_tree() and AudioManager != null:
					AudioManager.play_sfx("dice_tune")
				show_toast("%s converted into a %s die" % [cname, me().get_active_char().get_defn().element], TCGTheme.GOLD_L)
		else:
			show_toast("Matching and Omni dice cannot be converted", TCGTheme.RED)


func _ensure_lay() -> Dictionary:
	if _lay.is_empty():
		_compute_board_layout()
	return _lay


func _end_phase_rect() -> Rect2:
	return _ensure_lay()["end_round_rect"]


func _pause_btn_rect() -> Rect2:
	return _ensure_lay()["pause_btn_rect"]


func _skip_btn_rect() -> Rect2:
	return _ensure_lay()["skip_btn_rect"]


func _pause_option_rect(idx: int) -> Rect2:
	var safe: Rect2 = _ensure_lay()["safe"]
	var cx: float = safe.get_center().x
	var cy: float = safe.get_center().y
	return Rect2(cx - 170.0, cy - 72.0 + float(idx) * 66.0, 340.0, 52.0)


func _game_over_rect(idx: int) -> Rect2:
	var safe: Rect2 = _ensure_lay()["safe"]
	var cx: float = safe.get_center().x
	var cy: float = safe.get_center().y
	return Rect2(cx - 250.0 + float(idx) * 260.0, cy + 56.0, 240.0, 56.0)


func _mulligan_confirm_rect() -> Rect2:
	return _ensure_lay()["mulligan_confirm_rect"]


func _card_swap_confirm_rect() -> Rect2:
	var l := _ensure_lay()
	var cx: float = float(l["cx"])
	var safe: Rect2 = l["safe"]
	return Rect2(cx - 210.0, safe.position.y + 474.0, 210.0, 46.0)


func _card_swap_cancel_rect() -> Rect2:
	var l := _ensure_lay()
	var cx: float = float(l["cx"])
	var safe: Rect2 = l["safe"]
	return Rect2(cx + 16.0, safe.position.y + 474.0, 180.0, 46.0)


func _roll_confirm_rect() -> Rect2:
	if _is_center_roll_stage():
		var safe: Rect2 = _ensure_lay()["safe"]
		var cx: float = safe.get_center().x
		var cy: float = safe.get_center().y
		return Rect2(cx - 128.0, cy + 168.0, 256.0, 50.0)
	return _ensure_lay()["roll_confirm_rect"]


func _is_center_roll_stage() -> bool:
	return (
		game_state != null
		and game_state.phase == "roll"
		and is_my_turn()
		and not intro_active()
		and _hotseat_cover < 0
		and pay_pending.is_empty()
	)


func _center_roll_die_rect(idx: int, total: int) -> Rect2:
	var safe: Rect2 = _ensure_lay()["safe"]
	var cx: float = safe.get_center().x
	var cy: float = safe.get_center().y - 6.0
	var count: int = maxi(1, total)
	var rows: int = 1 if count <= 4 else 2
	var top_cols: int = count if rows == 1 else ceili(float(count) * 0.5)
	var bot_cols: int = count - top_cols
	var die_sz: float = 88.0 if top_cols <= 4 else clampf(760.0 / float(top_cols) - 20.0, 58.0, 82.0)
	var gap_x: float = 42.0 if top_cols <= 4 else 20.0
	var gap_y: float = 30.0
	var row: int = 0 if idx < top_cols else 1
	var col: int = idx if row == 0 else (idx - top_cols)
	var cols_in_row: int = top_cols if row == 0 else maxi(1, bot_cols)
	var row_w: float = float(cols_in_row) * die_sz + float(maxi(0, cols_in_row - 1)) * gap_x
	var x0: float = cx - row_w * 0.5 + float(col) * (die_sz + gap_x)
	var y0: float = (cy - die_sz * 0.5) if rows == 1 else (cy - die_sz - gap_y * 0.5 + float(row) * (die_sz + gap_y))
	return Rect2(x0, y0, die_sz, die_sz)


func _end_round_confirm_pill_rect() -> Rect2:
	var er := _end_phase_rect()
	return Rect2(er.end.x + 14.0, er.get_center().y - 24.0, 206.0, 48.0)


func _payment_panel_rects() -> Array[Rect2]:
	## Genshin inline payment layout: compact left detail box + warm right-side translucent dice drawer.
	var safe: Rect2 = _ensure_lay()["safe"]
	var lw: float = clampf(safe.size.x * 0.17, 260.0, 316.0)
	var left_r := Rect2(safe.position.x + 18.0, safe.position.y + 132.0, lw, 286.0)
	var rw: float = 258.0
	var right_r := Rect2(safe.end.x - rw - 14.0, safe.position.y + 72.0, rw, safe.size.y - 160.0)
	return [left_r, right_r]


func _pay_die_rect(idx: int) -> Rect2:
	var right: Rect2 = _payment_panel_rects()[1]
	var n_dice: int = maxi(1, me().dice.size() if game_state != null else 8)
	var rows: int = maxi(4, ceili(float(n_dice) * 0.5))
	var col: int = idx % 2
	var row: int = idx / 2
	var col_w: float = (right.size.x - 32.0) * 0.5
	var avail_h: float = maxf(240.0, right.size.y - 108.0)
	var row_step: float = clampf(avail_h / float(rows), 58.0, 96.0)
	var die_h: float = minf(76.0, row_step - 10.0)
	var die_w: float = minf(98.0, col_w - 10.0)
	var cx: float = right.position.x + 16.0 + col_w * (0.5 + float(col))
	var cy: float = right.position.y + 82.0 + row_step * (0.5 + float(row))
	return Rect2(cx - die_w * 0.5, cy - die_h * 0.5, die_w, die_h)


func _pay_cancel_rect() -> Rect2:
	var safe: Rect2 = _ensure_lay()["safe"]
	return Rect2(safe.end.x - 122.0, safe.position.y + 8.0, 48.0, 48.0)


func _pay_confirm_rect() -> Rect2:
	var safe: Rect2 = _ensure_lay()["safe"]
	var cx: float = safe.get_center().x
	return Rect2(cx - 126.0, safe.end.y - 126.0, 252.0, 50.0)


func _card_detail_btn_rect() -> Rect2:
	return _ensure_lay()["card_detail_btn_rect"]


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var kev: InputEventKey = event as InputEventKey
	if intro_active():
		if kev.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
			if _intro_t >= 0.4 or kev.keycode == KEY_ESCAPE:
				skip_intro()
		return

	if _hotseat_cover >= 0:
		if kev.keycode == KEY_ESCAPE:
			_pause_open = not _pause_open
			queue_redraw()
		elif kev.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER] and not _pause_open:
			dismiss_hotseat_cover()
		return

	if game_state != null and game_state.phase == "over":
		match kev.keycode:
			KEY_R:
				restart_match()
			KEY_ESCAPE:
				return_to_menu_requested.emit()
		return

	match kev.keycode:
		KEY_ESCAPE:
			if detail_drawer != null and detail_drawer.is_open():
				detail_drawer.pop_or_close()
			elif settings_modal != null and settings_modal.visible:
				settings_modal.close()
			elif not drag_state.is_empty():
				drag_state.clear()
				sync_from_state()
			elif not card_swap_pending.is_empty():
				cancel_card_swap()
			elif not pay_pending.is_empty():
				cancel_payment_modal()
			elif _end_round_confirm_open:
				_end_round_confirm_open = false
				queue_redraw()
			elif selected_hand_index >= 0 or not _inspected.is_empty():
				selected_hand_index = -1
				_inspected.clear()
				_inspect_extra_open = false
				sync_from_state()
			elif settings_modal != null and is_inside_tree():
				settings_modal.open()
			else:
				_pause_open = not _pause_open
				queue_redraw()
		KEY_ENTER, KEY_KP_ENTER:
			if _pause_open or (settings_modal != null and settings_modal.visible):
				return
			if not card_swap_pending.is_empty():
				confirm_card_swap()
			elif not pay_pending.is_empty():
				confirm_payment_modal()
			elif _end_round_confirm_open and is_my_turn() and game_state != null and game_state.phase == "action" and game_state.pending.is_empty():
				_end_round_confirm_open = false
				execute_action(TCGGameState.ActionData.new("end_round", view_player))
			elif is_mulligan_stage():
				_confirm_mulligan()
			elif is_my_turn() and game_state != null and game_state.phase == "roll":
				_confirm_roll_phase()
		KEY_SPACE:
			if animation_queue != null and animation_queue.is_busy():
				skip_animations()
		KEY_E:
			if not _pause_open and is_my_turn() and game_state.phase == "action" and game_state.pending.is_empty() and pay_pending.is_empty():
				if _end_round_confirm_open:
					_end_round_confirm_open = false
					execute_action(TCGGameState.ActionData.new("end_round", view_player))
				else:
					_end_round_confirm_open = true
					show_toast("Click End Round or press [E] again to confirm", TCGTheme.GOLD_L, 2.0)
					queue_redraw()
		KEY_T:
			if not _pause_open and is_my_turn() and game_state.phase == "action" and selected_hand_index >= 0 and pay_pending.is_empty():
				begin_tune(selected_hand_index)
		KEY_H:
			if not _pause_open:
				reveal_opponent_hand = not reveal_opponent_hand
				show_toast("Opponent hand reveal: %s" % ("ON" if reveal_opponent_hand else "OFF"), TCGTheme.GOLD)
				sync_from_state()
		KEY_F:
			if not _pause_open:
				var next_sp := 1.5 if is_equal_approx(game_speed, 1.0) else (2.0 if is_equal_approx(game_speed, 1.5) else 1.0)
				set_animation_speed(next_sp)
		KEY_1, KEY_2, KEY_3:
			if not _pause_open and is_my_turn() and game_state.phase == "action" and pay_pending.is_empty():
				var s_idx: int = int(kev.keycode) - int(KEY_1)
				_on_skill_clicked(s_idx)


func _confirm_mulligan() -> void:
	if not is_mulligan_stage():
		return
	var ids := mulligan_swap_indices.duplicate()
	ids.sort()
	execute_action(TCGGameState.ActionData.new("mulligan", view_player, -1, -1, [], ids))


func _confirm_roll_phase() -> void:
	if not is_my_turn() or game_state.phase != "roll":
		return
	var p := me()
	if not roll_selected_dice.is_empty() and p.rerolls > 0:
		var ids := roll_selected_dice.duplicate()
		ids.sort()
		lifecycle.submit_action(TCGGameState.ActionData.new("reroll", view_player, -1, -1, [], ids))
		if dice_tray != null:
			dice_tray.trigger_roll(ids)
	roll_selected_dice.clear()
	execute_action(TCGGameState.ActionData.new("confirm_roll", view_player))


func _input(event: InputEvent) -> void:
	if not visible or (is_inside_tree() and not is_visible_in_tree()):
		return
	if not drag_state.is_empty():
		var vp_drag := get_viewport()
		if event is InputEventMouseMotion:
			var dm := (make_input_local(event) if is_inside_tree() else event) as InputEventMouseMotion
			if dm != null:
				drag_state["pos"] = dm.position
				queue_redraw()
				if _overlay_canvas != null:
					_overlay_canvas.queue_redraw()
			if vp_drag != null:
				vp_drag.set_input_as_handled()
			return
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			var db := (make_input_local(event) if is_inside_tree() else event) as InputEventMouseButton
			var drop_pos: Vector2 = db.position if db != null else (drag_state.get("pos", Vector2.ZERO) as Vector2)
			_finish_card_drag(drop_pos)
			if vp_drag != null:
				vp_drag.set_input_as_handled()
			return
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			drag_state.clear()
			sync_from_state()
			if vp_drag != null:
				vp_drag.set_input_as_handled()
			return
	if event is InputEventMouseMotion:
		var m_ev := (make_input_local(event) if is_inside_tree() else event) as InputEventMouseMotion
		if m_ev == null:
			return
		var pos: Vector2 = m_ev.position
		_hover_mouse_pos = pos
		var prev_ab := _action_btn_hovered
		var prev_pi := _pause_hover_idx
		var prev_oi := _over_hover_idx
		var prev_pa := _pause_hovered
		var prev_sk := _skip_hovered
		var prev_ib := _inspect_btn_hovered
		var prev_rh := _roll_hover_die
		var prev_erp := _end_round_pill_hovered
		_pause_hovered = _pause_btn_rect().has_point(pos)
		_skip_hovered = (animation_queue != null and animation_queue.is_busy() and _skip_btn_rect().has_point(pos))
		_end_round_pill_hovered = _end_round_confirm_open and _end_round_confirm_pill_rect().has_point(pos)
		_roll_hover_die = -1
		if _is_center_roll_stage():
			var n_rd := me().dice.size()
			for i in range(n_rd):
				if _center_roll_die_rect(i, n_rd).has_point(pos):
					_roll_hover_die = i
					break
		_inspect_btn_hovered = (
			selected_hand_index >= 0
			and pay_pending.is_empty()
			and not _pause_open
			and not intro_active()
			and _card_detail_btn_rect().has_point(pos)
		)
		_action_btn_hovered = (
			(is_mulligan_stage() and _mulligan_confirm_rect().has_point(pos))
			or (is_my_turn() and game_state != null and game_state.phase == "roll" and _roll_confirm_rect().has_point(pos))
		)
		_pause_hover_idx = -1
		if _pause_open:
			for i in range(3):
				if _pause_option_rect(i).has_point(pos):
					_pause_hover_idx = i
					break
		_over_hover_idx = -1
		if game_state != null and game_state.phase == "over":
			for i in range(2):
				if _game_over_rect(i).has_point(pos):
					_over_hover_idx = i
					break
		if not pay_pending.is_empty():
			var prev_pb := _pay_btn_hovered
			var prev_pd := _pay_die_hovered
			_pay_btn_hovered = -1
			if _pay_cancel_rect().has_point(pos):
				_pay_btn_hovered = 0
			elif _pay_confirm_rect().has_point(pos):
				_pay_btn_hovered = 1
			_pay_die_hovered = -1
			for i in range(me().dice.size()):
				if _pay_die_rect(i).has_point(pos):
					_pay_die_hovered = i
					break
			if prev_pb != _pay_btn_hovered or prev_pd != _pay_die_hovered:
				queue_redraw()
		if prev_ab != _action_btn_hovered or prev_pi != _pause_hover_idx or prev_oi != _over_hover_idx or prev_pa != _pause_hovered or prev_sk != _skip_hovered or prev_ib != _inspect_btn_hovered or prev_rh != _roll_hover_die or prev_erp != _end_round_pill_hovered:
			queue_redraw()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var b_ev := (make_input_local(event) if is_inside_tree() else event) as InputEventMouseButton
		if b_ev == null:
			return
		var pos: Vector2 = b_ev.position
		var vp := get_viewport()

		if settings_modal != null and settings_modal.visible:
			return

		if _pause_open:
			if _pause_option_rect(0).has_point(pos):
				_pause_open = false
				queue_redraw()
			elif _pause_option_rect(1).has_point(pos):
				_pause_open = false
				return_to_menu_requested.emit()
			elif _pause_option_rect(2).has_point(pos):
				get_tree().quit(0)
			if vp != null:
				vp.set_input_as_handled()
			return

		if game_state != null and game_state.phase == "over":
			if _game_over_rect(0).has_point(pos):
				restart_match()
			elif _game_over_rect(1).has_point(pos):
				return_to_menu_requested.emit()
			if vp != null:
				vp.set_input_as_handled()
			return

		if animation_queue != null and animation_queue.is_busy() and _skip_btn_rect().has_point(pos):
			skip_animations()
			if vp != null:
				vp.set_input_as_handled()
			return

		if _pause_btn_rect().has_point(pos):
			if settings_modal != null and is_inside_tree():
				settings_modal.open()
			else:
				_pause_open = true
				queue_redraw()
			if vp != null:
				vp.set_input_as_handled()
			return

		if intro_active():
			if _intro_t >= 0.4:
				skip_intro()
			if vp != null:
				vp.set_input_as_handled()
			return

		if _hotseat_cover >= 0:
			dismiss_hotseat_cover()
			if vp != null:
				vp.set_input_as_handled()
			return

		if not pay_pending.is_empty():
			if _pay_cancel_rect().has_point(pos):
				cancel_payment_modal()
			elif _pay_confirm_rect().has_point(pos):
				confirm_payment_modal()
			else:
				for i in range(me().dice.size()):
					if _pay_die_rect(i).has_point(pos):
						_toggle_payment_die(i)
						break
			if vp != null:
				vp.set_input_as_handled()
			return

		if not card_swap_pending.is_empty():
			if _card_swap_confirm_rect().has_point(pos):
				confirm_card_swap()
				if vp != null:
					vp.set_input_as_handled()
				return
			if _card_swap_cancel_rect().has_point(pos):
				cancel_card_swap()
				if vp != null:
					vp.set_input_as_handled()
				return

		if is_mulligan_stage() and _mulligan_confirm_rect().has_point(pos):
			_confirm_mulligan()
			if vp != null:
				vp.set_input_as_handled()
			return

		if _is_center_roll_stage():
			if _roll_confirm_rect().has_point(pos):
				_confirm_roll_phase()
				if vp != null:
					vp.set_input_as_handled()
				return
			var n_rd := me().dice.size()
			for i in range(n_rd):
				if _center_roll_die_rect(i, n_rd).has_point(pos):
					_on_tray_die_clicked(i)
					if vp != null:
						vp.set_input_as_handled()
					return
			# Keep clicks on the dimmed center roll stage from leaking to character slots behind it
			if vp != null:
				vp.set_input_as_handled()
			return

		if _end_round_confirm_open:
			if _end_round_confirm_pill_rect().has_point(pos) or _end_phase_rect().has_point(pos):
				_end_round_confirm_open = false
				if is_my_turn() and game_state.phase == "action" and game_state.pending.is_empty():
					execute_action(TCGGameState.ActionData.new("end_round", view_player))
				if vp != null:
					vp.set_input_as_handled()
				return
			_end_round_confirm_open = false
			queue_redraw()
		elif _end_phase_rect().has_point(pos):
			if is_my_turn() and game_state != null and game_state.phase == "action" and game_state.pending.is_empty():
				if not confirm_before_end_round:
					execute_action(TCGGameState.ActionData.new("end_round", view_player))
				else:
					_end_round_confirm_open = true
					if is_inside_tree() and AudioManager != null:
						AudioManager.play_sfx("ui_click")
					queue_redraw()
			else:
				show_toast("You can only End Round on your turn in Action Phase", TCGTheme.RED)
			if vp != null:
				vp.set_input_as_handled()
			return


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if not drag_state.is_empty():
			drag_state["pos"] = event.position
			queue_redraw()
			return

		if not pay_pending.is_empty():
			_pay_btn_hovered = -1
			if _pay_cancel_rect().has_point(event.position):
				_pay_btn_hovered = 0
			elif _pay_confirm_rect().has_point(event.position):
				_pay_btn_hovered = 1
			_pay_die_hovered = -1
			for i in range(me().dice.size()):
				if _pay_die_rect(i).has_point(event.position):
					_pay_die_hovered = i
					break
			queue_redraw()
			return

		var prev_ep := _end_phase_hovered
		var prev_pa := _pause_hovered
		var prev_ab := _action_btn_hovered
		var prev_pi := _pause_hover_idx
		var prev_oi := _over_hover_idx
		_end_phase_hovered = _end_phase_rect().has_point(event.position)
		_pause_hovered = _pause_btn_rect().has_point(event.position)
		_action_btn_hovered = (
			(is_mulligan_stage() and _mulligan_confirm_rect().has_point(event.position))
			or (is_my_turn() and game_state != null and game_state.phase == "roll" and _roll_confirm_rect().has_point(event.position))
		)
		_pause_hover_idx = -1
		if _pause_open:
			for i in range(3):
				if _pause_option_rect(i).has_point(event.position):
					_pause_hover_idx = i
					break
		_over_hover_idx = -1
		if game_state != null and game_state.phase == "over":
			for i in range(2):
				if _game_over_rect(i).has_point(event.position):
					_over_hover_idx = i
					break
		if prev_ep != _end_phase_hovered or prev_pa != _pause_hovered or prev_ab != _action_btn_hovered or prev_pi != _pause_hover_idx or prev_oi != _over_hover_idx:
			queue_redraw()

	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			if not drag_state.is_empty():
				_finish_card_drag(event.position)
				return

		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if _pause_open or _hotseat_cover >= 0 or intro_active():
				return
			if not drag_state.is_empty():
				drag_state.clear()
				sync_from_state()
			elif not pay_pending.is_empty():
				cancel_payment_modal()
			elif _end_round_confirm_open:
				_end_round_confirm_open = false
				queue_redraw()
			elif selected_hand_index >= 0 or not _inspected.is_empty():
				selected_hand_index = -1
				_inspected.clear()
				_inspect_extra_open = false
				sync_from_state()
			return

		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			# 1. Pause Modal
			if _pause_open:
				if _pause_option_rect(0).has_point(event.position):
					_pause_open = false
					queue_redraw()
				elif _pause_option_rect(1).has_point(event.position):
					_pause_open = false
					return_to_menu_requested.emit()
				elif _pause_option_rect(2).has_point(event.position):
					get_tree().quit(0)
				return

			if game_state != null and game_state.phase == "over":
				if _game_over_rect(0).has_point(event.position):
					restart_match()
				elif _game_over_rect(1).has_point(event.position):
					return_to_menu_requested.emit()
				return

			if _pause_btn_rect().has_point(event.position):
				_pause_open = true
				queue_redraw()
				return

			if intro_active():
				if _intro_t >= 0.4:
					skip_intro()
				return

			if _hotseat_cover >= 0:
				dismiss_hotseat_cover()
				return

			# 2. Payment / Elemental Tuning Modal
			if not pay_pending.is_empty():
				if _pay_cancel_rect().has_point(event.position):
					cancel_payment_modal()
					return
				if _pay_confirm_rect().has_point(event.position):
					confirm_payment_modal()
					return
				for i in range(me().dice.size()):
					if _pay_die_rect(i).has_point(event.position):
						_toggle_payment_die(i)
						return
				return

			# 3. Mulligan Confirm Button
			if is_mulligan_stage() and _mulligan_confirm_rect().has_point(event.position):
				_confirm_mulligan()
				return

			# 4. Roll / Reroll Confirm Button
			if is_my_turn() and game_state.phase == "roll" and _roll_confirm_rect().has_point(event.position):
				_confirm_roll_phase()
				return

			# 5. End Round Hourglass Button (2-click confirmation: 1st click arms, 2nd click confirms)
			if _end_phase_rect().has_point(event.position):
				if is_my_turn() and game_state.phase == "action" and game_state.pending.is_empty():
					if _end_round_confirm_open:
						_end_round_confirm_open = false
						execute_action(TCGGameState.ActionData.new("end_round", view_player))
					else:
						_end_round_confirm_open = true
						if is_inside_tree() and AudioManager != null:
							AudioManager.play_sfx("ui_click")
						show_toast("Click End Round again to confirm", TCGTheme.GOLD_L, 2.0)
						queue_redraw()
				else:
					show_toast("You can only End Round on your turn in Action Phase", TCGTheme.RED)
				return

			# 6. Clicking empty board clears current selection / inspection
			if selected_hand_index >= 0 or not _inspected.is_empty():
				selected_hand_index = -1
				_inspected.clear()
				_inspect_extra_open = false
				sync_from_state()
				return


func _toggle_payment_die(die_idx: int) -> void:
	if pay_pending.is_empty():
		return
	var sel: Array = pay_pending["selected_dice"]
	if bool(pay_pending.get("tune", false)):
		var elig := tunable_dice(view_player)
		if not elig.has(die_idx):
			show_toast("Matching and Omni dice cannot be converted", TCGTheme.RED)
			return
		sel.clear()
		sel.append(die_idx)
		queue_redraw()
		return

	var cost: CardDataSystem.CostData = pay_pending["cost"]
	var limit: int = cost.n + cost.unaligned
	if sel.has(die_idx):
		sel.erase(die_idx)
	else:
		if sel.size() < limit:
			sel.append(die_idx)
		else:
			show_toast("This action requires %d dice (deselect one first)" % limit, TCGTheme.DIM)
	queue_redraw()


# ------------------------------------------------------------------------------
# Hover Inspector Callbacks
# ------------------------------------------------------------------------------
func _on_char_slot_hovered(p_side: int, p_idx: int, is_hovering: bool) -> void:
	if is_hovering:
		_hovered_char_side = p_side
		_hovered_char_idx = p_idx
	elif _hovered_char_side == p_side and _hovered_char_idx == p_idx:
		_hovered_char_side = -1
		_hovered_char_idx = -1
	sync_from_state()


func _on_skill_hovered(s_idx: int, is_hovering: bool) -> void:
	_hovered_skill_idx = s_idx if is_hovering else -1
	sync_from_state()


func _on_hand_card_hovered(_idx: int, c_name: String, is_hovering: bool) -> void:
	_hovered_card_name = c_name if is_hovering else ""
	sync_from_state()


func _on_status_icon_clicked(payload: Dictionary) -> void:
	if _is_ui_modal_blocking() or payload.is_empty():
		return
	var same: bool = (
		String(_inspected.get("kind", "")) == "status"
		and _inspected.get("payload", {}) == payload
	)
	selected_hand_index = -1
	_inspect_extra_open = false
	if same:
		_inspected.clear()
		if detail_drawer != null and detail_drawer.is_open():
			detail_drawer.close()
	else:
		_inspected = {"kind": "status", "payload": payload}
		if detail_drawer != null:
			var pkind := String(payload.get("kind", ""))
			if pkind == "aura":
				detail_drawer.open_keyword("el:" + String(payload.get("aura", "")))
			elif pkind == "equip":
				detail_drawer.open_card(String(payload.get("card_name", "")))
			elif pkind == "char":
				var c_side := int(payload.get("side", -1))
				var c_idx := int(payload.get("index", -1))
				var p_idx_owner := view_player if c_side == 0 else (1 - view_player)
				if p_idx_owner >= 0 and p_idx_owner < game_state.players.size():
					var own_p := game_state.players[p_idx_owner]
					if c_idx >= 0 and c_idx < own_p.characters.size():
						_inspected = {"kind": "char", "side": c_side, "index": c_idx}
						detail_drawer.open_character(own_p.characters[c_idx], own_p)
			else:
				var st_name := String(payload.get("name", ""))
				var st_inst: TCGPlayerSystem.StatusInstance = payload.get("status")
				var sdef := CardDataSystem.get_status_def(st_name)
				var st_txt: String = sdef.text if (sdef != null and not sdef.text.is_empty()) else ""
				var cnt := (st_inst.shield if st_inst.shield > 0 else st_inst.usages) if st_inst != null else int(payload.get("count", -1))
				detail_drawer.open_status(st_name, st_txt, cnt, pkind.capitalize())
	sync_from_state()


func _on_status_icon_hovered(payload: Dictionary, is_hovering: bool) -> void:
	if is_hovering:
		_hovered_status_payload = payload
	else:
		_hovered_status_payload.clear()
	queue_redraw()


# ------------------------------------------------------------------------------
# Custom Board Drawing (Mat, Piles, Banners, Modals, Dragged Card, FX, Inspector)
# ------------------------------------------------------------------------------
func _refresh_visuals() -> void:
	queue_redraw()
	if _overlay_canvas != null:
		_overlay_canvas.queue_redraw()


func _draw() -> void:
	var vp := _vp_size()
	var w: float = vp.x
	var h: float = vp.y
	var l := _ensure_lay()
	var safe: Rect2 = l["safe"]

	var shake_off := vfx_pool.shake_offset if vfx_pool != null else Vector2.ZERO
	draw_set_transform(shake_off, 0.0, Vector2.ONE)

	# 1. Dueling Mat Background w/ ambient shimmer (T2.2)
	TCGArt.draw_mat(self, Vector2(w, h), _clock)

	if game_state == null:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return

	var p_own: TCGPlayerSystem.PlayerState = game_state.players[view_player]
	var p_foe: TCGPlayerSystem.PlayerState = game_state.players[1 - view_player]

	# Subtle golden drop-zone halo ONLY while actively dragging an untargeted card
	if not drag_state.is_empty() and game_state.phase == "action":
		var drag_card_idx: int = int(drag_state.get("hand_index", -1))
		if drag_card_idx >= 0 and drag_card_idx < p_own.hand.size():
			for a in get_card_actions_for_hand_index(drag_card_idx):
				if a.target == -1:
					TCGTheme.draw_rounded_box(
						self,
						Rect2(safe.position.x + 190.0, safe.position.y + 64.0, safe.size.x - 310.0, safe.size.y - 280.0),
						Color(TCGTheme.GOLD_L.r, TCGTheme.GOLD_L.g, TCGTheme.GOLD_L.b, 0.04),
						Color(TCGTheme.GOLD_L.r, TCGTheme.GOLD_L.g, TCGTheme.GOLD_L.b, 0.65),
						16,
						2.2
					)
					break

	# 2. Deck Card-Back Piles (left side) + Card Counts
	_draw_deck_pile(l["foe_deck_rect"], p_foe.deck.size(), "")
	_draw_deck_pile(l["own_deck_rect"], p_own.deck.size(), "")

	# 3. Opponent Hand Fan (top-right of center banner)
	_draw_opponent_hand_fan(p_foe.hand)

	# 4. Top-Center Round / Phase / Turn Indicator Banner
	_draw_top_phase_banner()

	# 5. Left-Side "END ROUND" Hourglass Medallion Button + Turn Timer Ring (T7.2 / T11.5)
	_draw_end_phase_button()

	# 6. Top-Right Skip Pill (when animating) + Settings Gear Button
	if animation_queue != null and animation_queue.is_busy():
		_draw_skip_button()
	_draw_pause_button()

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _overlay_canvas != null:
		_overlay_canvas.queue_redraw()


func _draw_top_overlays() -> void:
	if game_state == null or _overlay_canvas == null:
		return
	var c: CanvasItem = _overlay_canvas
	var vp := _vp_size()
	var w: float = vp.x
	var h: float = vp.y

	# Burst flash radial vignette + expanding shockwave ring
	if _burst_flash_alpha > 0.001:
		var b_norm: float = clampf(_burst_flash_alpha / 0.65, 0.0, 1.0)
		c.draw_rect(Rect2(0, 0, w, h), Color(1.0, 0.95, 0.72, b_norm * 0.30))
		var ring_r: float = (1.0 - b_norm) * 520.0 + 70.0
		c.draw_arc(Vector2(w * 0.5, h * 0.5), ring_r, 0.0, TAU, 48, Color(1.0, 0.88, 0.48, b_norm * 0.65), 4.0)

	# 8. Phase-Specific Prompts (Setup Mulligan, Choose Active Character, Center Roll Stage)
	_draw_phase_prompts(c, w, h)

	# 8b. Genshin Inline End-Round Pill & "I'm ending my Round." Speech Bubble
	if pay_pending.is_empty() and not _pause_open and _hotseat_cover < 0 and not intro_active() and game_state.phase == "action":
		_draw_end_round_overlay(c)

	# 9. Flying Card Animations, Draw Reveal, Elemental Impact FX, Targeting Arrow & Damage/Reaction Floaters
	_draw_fx_layer(c)

	# 10. Dragged Card Follower
	if not drag_state.is_empty():
		_draw_dragged_card(c)

	# 11. Click-Driven Card/Skill Preview (Details drawer handles Char/Zone/Status when open)
	if pay_pending.is_empty() and drag_state.is_empty() and not _pause_open and _hotseat_cover < 0 and not intro_active() and game_state.phase != "over":
		_draw_inspect_tooltip(c)

	# 12. Action Payment / Elemental Tuning Modal
	if not pay_pending.is_empty():
		_draw_payment_modal(c, w, h)

	# 13. Hotseat Pass-Device Privacy Cover
	if _hotseat_cover >= 0 and game_state.phase != "over" and not _pause_open:
		_draw_hotseat_cover(c, w, h)

	# 14. Opening Coin Toss Intro Overlay
	if intro_active() and game_state.phase != "over" and not _pause_open:
		_draw_coin_intro(c, w, h)

	# 15. Toast Notification Stack (top-center)
	_draw_toasts(c, w)

	# 16. Match Over Overlay
	if game_state.phase == "over":
		_draw_game_over_overlay(c, w, h)

	# 17. Pause Modal Overlay
	if _pause_open:
		_draw_pause_modal(c, w, h)


func _draw_deck_pile(r: Rect2, count: int, label: String) -> void:
	if count > 4:
		TCGArt.draw_card_back(self, Rect2(r.position.x + 5, r.position.y + 5, r.size.x, r.size.y))
	if count > 1:
		TCGArt.draw_card_back(self, Rect2(r.position.x + 2.5, r.position.y + 2.5, r.size.x, r.size.y))
	if count > 0:
		TCGArt.draw_card_back(self, r)
	else:
		TCGTheme.draw_rounded_box(self, r, Color(0.05, 0.08, 0.13, 0.55), TCGTheme.GOLD_D, 8, 1)
	var badge_c := Vector2(r.end.x - 4, r.end.y - 6)
	draw_circle(badge_c + Vector2(0, 2), 16.0, Color(0, 0, 0, 0.45))
	draw_circle(badge_c, 16.0, Color(0.07, 0.11, 0.17, 0.96))
	draw_arc(badge_c, 16.0, 0.0, TAU, 24, TCGTheme.GOLD_L, 2.0)
	TCGTheme.draw_text_centered(self, str(count), badge_c, 15, TCGTheme.GOLD_L, true, true)
	if not label.is_empty():
		TCGTheme.draw_text_centered(self, label, Vector2(r.get_center().x, r.end.y + 15.0), 13, TCGTheme.DIM, true, true)


func _draw_opponent_hand_fan(foe_hand: Array[String]) -> void:
	var n_cards: int = foe_hand.size()
	if n_cards <= 0:
		return
	var l := _ensure_lay()
	var safe: Rect2 = l["safe"]
	var cw: float = 52.0
	var ch: float = 74.0
	var step: float = minf(34.0, 190.0 / float(maxi(1, n_cards)))
	var total_w: float = cw + step * float(n_cards - 1)
	var x0: float = float(l["foe_hand_cx"]) - total_w * 0.5
	for i in range(n_cards):
		var r := Rect2(x0 + float(i) * step, safe.position.y + 4.0, cw, ch)
		if reveal_opponent_hand:
			TCGActionCardView.draw_card_surface(self, r, foe_hand[i], false, false, true, false, false, false)
		else:
			TCGArt.draw_card_back(self, r)


func _draw_top_phase_banner() -> void:
	var banner: Rect2 = _ensure_lay()["top_banner"]
	TCGTheme.draw_gold_frame(self, banner, Color(0.05, 0.08, 0.14, 0.84), 14, false)

	var phase_str: String = "MATCH OVER" if game_state.phase == "over" else (game_state.phase.to_upper() + " PHASE")
	var round_txt := "ROUND %d  ·  %s" % [game_state.round_number, phase_str]
	TCGTheme.draw_text_centered(self, round_txt, banner.get_center(), 18, TCGTheme.GOLD_L, true, true)


func _draw_combat_status_ribbon(_side: int, center: Vector2, statuses: Array) -> void:
	if statuses.is_empty():
		return
	var total_w: float = float(statuses.size()) * 142.0
	var x0: float = center.x - total_w * 0.5
	for i in range(statuses.size()):
		var st: TCGPlayerSystem.StatusInstance = statuses[i]
		var pill := Rect2(x0 + float(i) * 142.0, center.y - 13.0, 134.0, 26.0)
		TCGTheme.draw_rounded_box(self, pill, Color(0.1, 0.16, 0.24, 0.9), TCGTheme.GOLD, 12, 1)
		var count_val: int = st.shield if st.shield > 0 else maxi(0, st.usages)
		var txt := "%s (%d)" % [st.name, count_val]
		if txt.length() > 16:
			txt = st.name.substr(0, 11) + "…(" + str(count_val) + ")"
		TCGTheme.draw_text_centered(self, txt, pill.get_center(), 13, TCGTheme.GOLD_L, true, true)


func _draw_end_phase_button() -> void:
	var r := _end_phase_rect()
	var c := r.get_center()
	var p_own := game_state.players[view_player]
	var p_foe := game_state.players[1 - view_player]
	var can_act: bool = (is_my_turn() and game_state.phase == "action" and game_state.pending.is_empty())
	var armed: bool = (_end_round_confirm_open and can_act)
	var rad: float = r.size.x * 0.5
	var pulse := 0.5 + 0.5 * sin(_clock * 4.5)

	# Genshin-style Dice Count badges directly above (Opponent) and below (Player) the End Round medallion
	_draw_end_round_dice_counter(Vector2(c.x, r.position.y - 30.0), p_foe.dice.size(), true)
	_draw_end_round_dice_counter(Vector2(c.x, r.end.y + 30.0), p_own.dice.size(), false)

	# T2.4 "1ST NEXT ROUND" tag cleanly above the opponent dice badge when player declared first
	if p_own.ended and not p_foe.ended:
		var tag_r := Rect2(r.position.x - 4.0, r.position.y - 78.0, r.size.x + 36.0, 24.0)
		TCGTheme.draw_rounded_box(self, tag_r, Color("#183652"), TCGTheme.TEAL, 12, 1.5)
		TCGTheme.draw_text_centered(self, "1ST NEXT ROUND", tag_r.get_center(), 12, TCGTheme.GOLD_L, true, false)

	var fill := Color8(92, 68, 28) if armed else (Color8(36, 58, 82) if can_act else Color8(24, 32, 44))
	if _end_phase_hovered and can_act and not armed:
		fill = Color8(52, 82, 112)
	elif _end_phase_hovered and armed:
		fill = Color8(116, 86, 36)
	var border := TCGTheme.GOLD_L if (armed or _end_phase_hovered or can_act) else TCGTheme.GOLD_D

	if can_act:
		draw_arc(c, rad + 5.0 + pulse * 2.5, 0.0, TAU, 36, Color(TCGTheme.GOLD_L.r, TCGTheme.GOLD_L.g, TCGTheme.GOLD_L.b, (0.50 if armed else 0.25) + 0.25 * pulse), 3.0 if armed else 2.5)

	draw_circle(c + Vector2(0, 3), rad, Color(0, 0, 0, 0.45))
	draw_circle(c, rad, fill)
	draw_arc(c, rad, 0.0, TAU, 36, border, 3.2 if armed else 3.0)
	draw_arc(c, rad - 5.0, 0.0, TAU, 30, TCGTheme.GOLD_L if armed else TCGTheme.GOLD_D, 1.2)

	# T11.5 Circular Turn Timer Ring around End Round medallion
	if is_my_turn() and game_state.phase in ["action", "roll"]:
		var frac := clampf(_turn_timer / 45.0, 0.0, 1.0)
		var ring_col := TCGTheme.TEAL if _turn_timer > 15.0 else (TCGTheme.GOLD_L if _turn_timer > 6.0 else TCGTheme.RED)
		draw_arc(c, rad + 2.0, -PI * 0.5, -PI * 0.5 + TAU * frac, 40, ring_col, 3.0)

	var hg_pts_top := PackedVector2Array([
		Vector2(c.x - 12, c.y - 26),
		Vector2(c.x + 12, c.y - 26),
		Vector2(c.x, c.y - 12),
	])
	var hg_pts_bot := PackedVector2Array([
		Vector2(c.x, c.y - 12),
		Vector2(c.x + 12, c.y + 2),
		Vector2(c.x - 12, c.y + 2),
	])
	draw_colored_polygon(hg_pts_top, Color8(255, 240, 190) if armed else (TCGTheme.GOLD_L if can_act else TCGTheme.DIM))
	draw_colored_polygon(hg_pts_bot, TCGTheme.GOLD_L if armed else (TCGTheme.GOLD if can_act else TCGTheme.DIM))

	if armed:
		TCGTheme.draw_text_centered(self, "CONFIRM", Vector2(c.x, c.y + 15.0), 14, Color8(255, 245, 210), true, true)
		TCGTheme.draw_text_centered(self, "END ROUND", Vector2(c.x, c.y + 32.0), 11, TCGTheme.GOLD_L, true, true)
	else:
		TCGTheme.draw_text_centered(self, "END", Vector2(c.x, c.y + 15.0), 15, TCGTheme.GOLD_L if can_act else TCGTheme.DIM, true, true)
		TCGTheme.draw_text_centered(self, "ROUND", Vector2(c.x, c.y + 32.0), 13, TCGTheme.TEXT if can_act else TCGTheme.DIM, true, true)


func _draw_end_round_dice_counter(center: Vector2, count: int, is_opponent: bool) -> void:
	var w: float = 82.0
	var h: float = 30.0
	var pr := Rect2(center.x - w * 0.5, center.y - h * 0.5, w, h)
	var border_col := Color8(216, 108, 102) if is_opponent else TCGTheme.TEAL
	var bg_col := Color(0.14, 0.07, 0.09, 0.90) if is_opponent else Color(0.06, 0.13, 0.19, 0.90)
	TCGTheme.draw_rounded_box(self, pr, bg_col, border_col, 14, 1.8, Vector2(0, 2), 75)
	# Subtle directional chevron pointing up (Opponent) or down (Player)
	var dir_y: float = -1.0 if is_opponent else 1.0
	var tip_y: float = (pr.position.y - 4.0) if is_opponent else (pr.end.y + 4.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(center.x, tip_y),
		Vector2(center.x - 5.0, tip_y - dir_y * 5.0),
		Vector2(center.x + 5.0, tip_y - dir_y * 5.0),
	]), border_col)
	TCGArt.draw_elem_symbol(self, "Omni", Vector2(pr.position.x + 20.0, center.y), 9.5, Color(0, 0, 0, 0), false)
	TCGTheme.draw_text_centered(self, str(count), Vector2(pr.position.x + 52.0, center.y), 17, TCGTheme.GOLD_L if count > 0 else TCGTheme.DIM, true, true)


func _draw_skip_button() -> void:
	var r := _skip_btn_rect()
	var border := TCGTheme.GOLD_L if _skip_hovered else TCGTheme.GOLD
	TCGTheme.draw_rounded_box(self, r, Color(0.09, 0.14, 0.22, 0.92), border, 10, 1.5)
	TCGTheme.draw_text_centered(self, "SKIP ⏭", r.get_center(), 14, TCGTheme.GOLD_L, true, true)


func _draw_pause_button() -> void:
	var r := _pause_btn_rect()
	var border := TCGTheme.GOLD_L if _pause_hovered else TCGTheme.GOLD
	TCGTheme.draw_rounded_box(self, r, TCGTheme.PANEL2, border, 12, 2, Vector2(0, 2), 80)
	var c := r.get_center()
	draw_arc(c, 10.5, 0.0, TAU, 16, border, 2.2)
	draw_circle(c, 4.2, border)
	for k in range(8):
		var a: float = float(k) * PI / 4.0
		var p1 := Vector2(c.x + cos(a) * 10.5, c.y + sin(a) * 10.5)
		var p2 := Vector2(c.x + cos(a) * 15.0, c.y + sin(a) * 15.0)
		draw_line(p1, p2, border, 2.2)


func _draw_end_round_overlay(c: CanvasItem) -> void:
	var l := _ensure_lay()
	var p_own := game_state.players[view_player]
	var p_foe := game_state.players[1 - view_player]

	# Genshin inline "End Round" ivory pill expanding cleanly from the left hourglass
	if _end_round_confirm_open and is_my_turn() and game_state.pending.is_empty():
		var pr := _end_round_confirm_pill_rect()
		if not p_foe.ended:
			var tag_r := Rect2(pr.position.x + 6.0, pr.position.y - 26.0, 194.0, 22.0)
			TCGTheme.draw_rounded_box(c, tag_r, Color(0.08, 0.21, 0.30, 0.94), TCGTheme.TEAL, 11, 1.4)
			TCGTheme.draw_text_centered(c, "Go First in Next Round", tag_r.get_center(), 12, TCGTheme.GOLD_L, true, false)
		TCGTheme.draw_genshin_pill(c, pr, "End Round", _end_round_pill_hovered, false, "confirm")

	# Subtle Genshin "I'm ending my Round." speech bubble beside whichever player ended first
	if p_foe.ended and not p_own.ended:
		var fpos: Vector2 = l["foe_hud_pos"]
		var br := Rect2(fpos.x + 300.0, fpos.y + 12.0, 206.0, 34.0)
		TCGTheme.draw_rounded_box(c, br, Color(0.95, 0.92, 0.85, 0.94), TCGTheme.GOLD, 16, 1.5, Vector2(0, 2), 60)
		TCGTheme.draw_text_centered(c, "I'm ending my Round.", br.get_center(), 13, Color8(48, 40, 32), true, false)
	elif p_own.ended and not p_foe.ended:
		var opos: Vector2 = l["own_hud_pos"]
		var br := Rect2(opos.x + 12.0, opos.y - 42.0, 206.0, 34.0)
		TCGTheme.draw_rounded_box(c, br, Color(0.95, 0.92, 0.85, 0.94), TCGTheme.GOLD, 16, 1.5, Vector2(0, 2), 60)
		TCGTheme.draw_text_centered(c, "I'm ending my Round.", br.get_center(), 13, Color8(48, 40, 32), true, false)


func _draw_phase_prompts(c: CanvasItem, w: float, h: float) -> void:
	if intro_active():
		return
	var l := _ensure_lay()
	var safe: Rect2 = l["safe"]
	var cx: float = float(l["cx"])
	var p := me()

	# 1. Genshin Starting Hand Mulligan (dimmed board + crisp header + ivory Confirm pill)
	if is_mulligan_stage():
		c.draw_rect(Rect2(0, 0, w, h), Color(0.02, 0.04, 0.07, 0.60))
		var hdr_y: float = safe.position.y + 174.0
		TCGTheme.draw_text_centered(c, "Starting Hand", Vector2(cx, hdr_y), 32, TCGTheme.GOLD_L, true, true)
		var line_w: float = 320.0
		c.draw_line(Vector2(cx - line_w * 0.5, hdr_y + 24.0), Vector2(cx + line_w * 0.5, hdr_y + 24.0), Color(TCGTheme.GOLD.r, TCGTheme.GOLD.g, TCGTheme.GOLD.b, 0.65), 1.4)
		var n_sel: int = mulligan_swap_indices.size()
		var sub_txt := "Select card(s) to switch" if n_sel == 0 else ("%d card(s) marked to switch" % n_sel)
		TCGTheme.draw_text_centered(c, sub_txt, Vector2(cx, hdr_y + 44.0), 16, TCGTheme.TEXT, false, true)
		var lbl := "Confirm" if n_sel == 0 else ("Switch %d  ·  Confirm" % n_sel)
		TCGTheme.draw_genshin_pill(c, _mulligan_confirm_rect(), lbl, _action_btn_hovered, false, "confirm")
		return

	# 2. Choose Active Character ribbon (Genshin sleek tapered strip)
	var center_band_y: float = safe.position.y + 414.0
	if not game_state.pending.is_empty() or (game_state.phase == "setup" and p.mull_done and is_my_turn()):
		var msg := "Select Starting Active Character" if game_state.phase == "setup" else "Choose your next active character"
		if not is_my_turn():
			msg = "%s is choosing an active character…" % _who(actor())
		TCGTheme.draw_phase_announcement(c, msg, "Click one of your characters below" if is_my_turn() else "", TCGTheme.GOLD_L, center_band_y + 24.0, 0.96)
		return

	if game_state.phase == "setup" and not is_my_turn() and actor() >= 0:
		TCGTheme.draw_phase_announcement(c, "%s is preparing…" % _who(actor()), "", TCGTheme.GOLD_L, center_band_y + 24.0, 0.90)
		return

	# 3. Full-Table Genshin Center Roll & Reroll Stage
	if _is_center_roll_stage():
		_draw_center_roll_stage(c, w, h)
		return

	# 3b. Interactive Swap Cards selection prompt
	if not card_swap_pending.is_empty():
		var sel_n: int = (card_swap_pending.get("selected_ids", []) as Array).size()
		var max_n: int = int(card_swap_pending.get("max_pick", 2))
		var band := Rect2(cx - 320.0, center_band_y - 26.0, 640.0, 68.0)
		TCGTheme.draw_gold_frame(c, band, Color(0.05, 0.09, 0.15, 0.95), 14, true)
		TCGTheme.draw_text_centered(c, "Swap Cards (%d/%d Selected)" % [sel_n, max_n], Vector2(cx, band.position.y + 22.0), 19, TCGTheme.GOLD_L, true, true)
		TCGTheme.draw_text_centered(c, "Click up to %d card(s) in your hand to switch" % max_n, Vector2(cx, band.position.y + 48.0), 14, TCGTheme.DIM, false, true)
		TCGTheme.draw_genshin_pill(c, _card_swap_confirm_rect(), "Confirm", _card_swap_confirm_rect().has_point(_hover_mouse_pos), sel_n == 0, "confirm")
		TCGTheme.draw_genshin_pill(c, _card_swap_cancel_rect(), "Cancel", _card_swap_cancel_rect().has_point(_hover_mouse_pos), false, "cancel")
		return

	# 4. Selected targeted card instruction banner (only for cards needing a character target)
	if selected_hand_index >= 0 and selected_hand_index < p.hand.size() and pay_pending.is_empty() and drag_state.is_empty():
		var cname: String = p.hand[selected_hand_index]
		var cd_sel: CardDataSystem.CardData = CardDataSystem.get_card_def(cname)
		if cd_sel != null and cd_sel.needs_char and is_my_turn() and game_state.phase == "action":
			var band := Rect2(cx - 280.0, center_band_y, 560.0, 42.0)
			TCGTheme.draw_rounded_box(c, band, Color(0.06, 0.10, 0.16, 0.92), TCGTheme.GOLD_L, 21, 1.8)
			TCGTheme.draw_text_centered(
				c,
				"Select %s to equip %s  ·  [Esc] Cancel" % [cd_sel.char_name if not cd_sel.char_name.is_empty() else "target", cname],
				band.get_center(),
				14,
				TCGTheme.GOLD_L,
				true,
				true
			)


func _draw_center_roll_stage(c: CanvasItem, w: float, h: float) -> void:
	var safe: Rect2 = _ensure_lay()["safe"]
	var cx: float = safe.get_center().x
	var cy: float = safe.get_center().y
	var p := me()
	var n_dice: int = p.dice.size()

	# Dramatic spotlight backdrop focusing attention on the center-table dice tray
	c.draw_rect(Rect2(0, 0, w, h), Color(0.02, 0.04, 0.07, 0.64))
	c.draw_circle(Vector2(cx, cy - 8.0), 275.0, Color(0.95, 0.80, 0.42, 0.06))
	c.draw_circle(Vector2(cx, cy - 8.0), 175.0, Color(0.98, 0.86, 0.50, 0.05))

	# Clean Genshin typography header
	var hdr_y: float = cy - 196.0
	var title_txt := "Reroll" if p.rerolls > 0 else "Roll Phase"
	var sub_txt := "Select dice to reroll (%d reroll left)" % p.rerolls if p.rerolls > 0 else "Review your Elemental Dice"
	TCGTheme.draw_text_centered(c, title_txt, Vector2(cx, hdr_y), 32, TCGTheme.GOLD_L, true, true)
	c.draw_line(Vector2(cx - 170.0, hdr_y + 24.0), Vector2(cx + 170.0, hdr_y + 24.0), Color(TCGTheme.GOLD.r, TCGTheme.GOLD.g, TCGTheme.GOLD.b, 0.60), 1.4)
	TCGTheme.draw_text_centered(c, sub_txt, Vector2(cx, hdr_y + 44.0), 16, TCGTheme.TEXT, false, true)

	# Large tumbling faceted dice settling into 2 neat rows
	var tumble_u: float = clampf(_roll_stage_t / 0.44, 0.0, 1.0)
	var ease_out: float = 1.0 - pow(1.0 - tumble_u, 3.0)
	for i in range(n_dice):
		var face: String = p.dice[i]
		var dst: Rect2 = _center_roll_die_rect(i, n_dice)
		var sel: bool = roll_selected_dice.has(i)
		var hov: bool = (_roll_hover_die == i)

		# Smooth energetic scatter-and-settle entrance from center table
		var start_ang: float = float(i) * 1.37 + 0.5
		var scatter_r: float = (1.0 - ease_out) * 90.0
		var scatter_off := Vector2(cos(start_ang) * scatter_r, sin(start_ang) * scatter_r - (1.0 - ease_out) * 32.0)
		var lift_y: float = -10.0 if sel else (-5.0 if hov else 0.0)
		var sc: float = lerpf(0.65, 1.0, ease_out) * (1.07 if sel else (1.04 if hov else 1.0))
		var cur_center := dst.get_center() + scatter_off + Vector2(0.0, lift_y)
		var cur_sz := dst.size * sc
		var draw_r := Rect2(cur_center - cur_sz * 0.5, cur_sz)

		# Golden diamond halo + pulse when selected for reroll
		if sel:
			var pulse := 0.5 + 0.5 * sin(_clock * 6.0 + float(i))
			var hr := cur_sz.x * 0.58 + pulse * 3.0
			var halo_pts := PackedVector2Array([
				Vector2(cur_center.x, cur_center.y - hr),
				Vector2(cur_center.x + hr, cur_center.y),
				Vector2(cur_center.x, cur_center.y + hr),
				Vector2(cur_center.x - hr, cur_center.y),
			])
			c.draw_colored_polygon(halo_pts, Color(1.0, 0.88, 0.45, 0.22 + 0.10 * pulse))
			c.draw_circle(cur_center, cur_sz.x * 0.56, Color(1.0, 0.90, 0.52, 0.16))
			c.draw_arc(cur_center, cur_sz.x * 0.56, 0.0, TAU, 32, TCGTheme.GOLD_L, 2.4)
		elif hov:
			c.draw_arc(cur_center, cur_sz.x * 0.54, 0.0, TAU, 28, Color(TCGTheme.GOLD_L.r, TCGTheme.GOLD_L.g, TCGTheme.GOLD_L.b, 0.65), 1.8)

		TCGArt.draw_die(c, face, draw_r, sel, hov)

		if sel:
			var badge_p := Vector2(draw_r.end.x - 8.0, draw_r.position.y + 8.0)
			c.draw_circle(badge_p, 11.0, Color8(212, 68, 62))
			c.draw_arc(badge_p, 11.0, 0.0, TAU, 18, TCGTheme.GOLD_L, 1.5)
			TCGTheme.draw_text_centered(c, "↻", badge_p, 13, Color.WHITE, true, false)

	# Centered Genshin ivory Confirm pill
	var n_reroll: int = roll_selected_dice.size()
	var btn_lbl := "Confirm" if (n_reroll == 0 or p.rerolls <= 0) else ("Reroll %d  ·  Confirm" % n_reroll)
	TCGTheme.draw_genshin_pill(c, _roll_confirm_rect(), btn_lbl, _action_btn_hovered, false, "confirm")


func _draw_dragged_card(c: CanvasItem) -> void:
	var c_name: String = String(drag_state.get("card_name", ""))
	var pos: Vector2 = drag_state.get("pos", Vector2(640, 360))
	var r := Rect2(pos.x - 64.0, pos.y - 90.0, 128.0, 180.0)
	TCGTheme.draw_rounded_box(c, r.grow(6.0), Color(0.95, 0.80, 0.42, 0.16), Color(0.95, 0.82, 0.45, 0.55), 14, 2, Vector2(0, 8), 90)
	TCGActionCardView.draw_card_surface(c, r, c_name, true, true, true, false, false, false)


func _draw_aim_arrow(c: CanvasItem, p0: Vector2, p2: Vector2) -> void:
	var ctrl_lift: float = clampf(absf(p2.y - p0.y) * 0.28 + 48.0, 48.0, 140.0)
	var p1: Vector2 = (p0 + p2) * 0.5 - Vector2(0.0, ctrl_lift)
	var pts := PackedVector2Array()
	var steps := 22
	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		var omt: float = 1.0 - t
		var pt: Vector2 = (omt * omt) * p0 + (2.0 * omt * t) * p1 + (t * t) * p2
		pts.append(pt)
	c.draw_polyline(pts, Color(0.95, 0.80, 0.38, 0.24), 9.0, true)
	c.draw_polyline(pts, Color(0.99, 0.88, 0.52, 0.92), 3.2, true)
	var dir: Vector2 = (p2 - p1).normalized()
	if dir.length_squared() < 0.01:
		dir = Vector2.UP
	var perp := Vector2(-dir.y, dir.x)
	var head := PackedVector2Array([
		p2 + dir * 6.0,
		p2 - dir * 14.0 + perp * 9.0,
		p2 - dir * 14.0 - perp * 9.0,
	])
	c.draw_colored_polygon(head, Color(0.99, 0.88, 0.52, 0.96))


func _draw_fx_layer(c: CanvasItem) -> void:
	# T8.2 Golden quadratic Bezier aiming arrow when dragging or targeting a character
	if game_state != null and game_state.phase == "action" and pay_pending.is_empty() and hand_strip != null:
		var arrow_idx: int = int(drag_state.get("hand_index", selected_hand_index))
		var target_pos: Vector2 = drag_state.get("pos", _hover_mouse_pos)
		if arrow_idx >= 0 and arrow_idx < me().hand.size() and target_pos != Vector2.ZERO:
			var cd_sel: CardDataSystem.CardData = CardDataSystem.get_card_def(me().hand[arrow_idx])
			var is_drag: bool = not drag_state.is_empty()
			var needs_tgt: bool = cd_sel != null and cd_sel.needs_char
			if is_drag or (needs_tgt and target_pos.y < hand_strip.position.y + 12.0):
				var origin_p: Vector2 = hand_strip.get_card_global_center(arrow_idx)
				if origin_p.distance_to(target_pos) > 28.0:
					_draw_aim_arrow(c, origin_p, target_pos)

	# Unified single smooth card-play showcase (player plays left, AI plays right -> golden sparkle dissolve)
	for fc in _flying_cards:
		var u: float = clampf(float(fc["t"]) / maxf(0.01, float(fc["dur"])), 0.0, 1.0)
		var move_u: float = clampf(u / 0.30, 0.0, 1.0)
		var ease_move: float = 1.0 - pow(1.0 - move_u, 4.0)
		var p_cur: Vector2 = (fc["from"] as Vector2).lerp(fc["to"] as Vector2, ease_move)
		var sc: float = lerpf(0.76, 1.15, ease_move)
		var alpha: float = 1.0
		var dissolve_u: float = 0.0
		if u > 0.68:
			dissolve_u = (u - 0.68) / 0.32
			alpha = 1.0 - dissolve_u
			sc = lerpf(1.15, 1.02, dissolve_u)
			p_cur.y -= dissolve_u * 22.0
		var cw: float = 152.0 * sc
		var ch: float = 212.0 * sc
		var r := Rect2(p_cur.x - cw * 0.5, p_cur.y - ch * 0.5, cw, ch)
		var glow_a: float = 0.48 * alpha
		TCGTheme.draw_rounded_box(c, r.grow(8.0), Color(0.95, 0.80, 0.42, glow_a * 0.30), Color(0.98, 0.86, 0.50, glow_a), 14, 2.2)
		if alpha > 0.06:
			TCGActionCardView.draw_card_surface(c, r, String(fc["card_name"]), true, false, true, false, false, false)
		# Warm golden dissolve sparks rising cleanly off the card
		if dissolve_u > 0.0:
			for sp_i in range(10):
				var seed_a: float = float(sp_i) * 1.17
				var sx: float = p_cur.x + sin(seed_a * 2.1) * (cw * 0.48)
				var sy: float = p_cur.y + cos(seed_a * 1.7) * (ch * 0.38) - dissolve_u * (48.0 + float(sp_i % 3) * 18.0)
				var sr: float = (4.8 - dissolve_u * 3.0)
				if sr > 0.5:
					var sp_col := Color(1.0, 0.90, 0.52, alpha * 0.92)
					c.draw_colored_polygon(PackedVector2Array([
						Vector2(sx, sy - sr), Vector2(sx + sr, sy), Vector2(sx, sy + sr), Vector2(sx - sr, sy)
					]), sp_col)

	# End-Phase / Draw Cards 2-card center face-up reveal before tucking down into hand
	if not _draw_reveal_cards.is_empty():
		var safe_dr: Rect2 = _ensure_lay()["safe"]
		var dcx: float = safe_dr.get_center().x
		var dcy: float = safe_dr.get_center().y + 116.0
		for dr in _draw_reveal_cards:
			var du: float = clampf(float(dr["t"]) / maxf(0.01, float(dr["dur"])), 0.0, 1.0)
			var s_idx: int = int(dr["slot_idx"])
			var tot: int = maxi(1, int(dr["total"]))
			var x_off: float = (float(s_idx) - float(tot - 1) * 0.5) * 156.0
			var show_pos := Vector2(dcx + x_off, dcy)
			var in_u: float = clampf(du / 0.25, 0.0, 1.0)
			var out_u: float = clampf((du - 0.68) / 0.32, 0.0, 1.0)
			var cur_p := show_pos + Vector2(0.0, (1.0 - pow(1.0 - in_u, 3.0)) * 30.0)
			cur_p = cur_p.lerp(Vector2(dcx + x_off * 0.5, safe_dr.end.y - 36.0), out_u * out_u)
			var sc_d: float = lerpf(0.75, 1.02, 1.0 - pow(1.0 - in_u, 3.0)) * lerpf(1.0, 0.68, out_u)
			var alpha_d: float = 1.0 - out_u
			if alpha_d > 0.06:
				var dr_w: float = 132.0 * sc_d
				var dr_h: float = 186.0 * sc_d
				var dr_r := Rect2(cur_p.x - dr_w * 0.5, cur_p.y - dr_h * 0.5, dr_w, dr_h)
				TCGTheme.draw_rounded_box(c, dr_r.grow(5.0), Color(0.95, 0.80, 0.42, 0.14 * alpha_d), Color(0.98, 0.86, 0.50, 0.60 * alpha_d), 12, 1.8)
				TCGActionCardView.draw_card_surface(c, dr_r, String(dr["card_name"]), true, false, true, false, false, false)

	# Crisp elemental slash / bolt / splash impact VFX across struck character cards
	for fx in _impact_fx:
		var fu: float = clampf(float(fx["t"]) / maxf(0.01, float(fx["dur"])), 0.0, 1.0)
		var fa: float = 1.0 - fu * fu
		var fp: Vector2 = fx["pos"]
		var dtype: String = String(fx["dtype"])
		var col: Color = TCGTheme.elem_color(dtype)
		var core_col := Color(1.0, 0.98, 0.92, fa)
		var glow_col := Color(col.r, col.g, col.b, fa * 0.85)
		var ring_r: float = lerpf(18.0, 86.0, 1.0 - pow(1.0 - fu, 3.0))
		c.draw_arc(fp, ring_r, 0.0, TAU, 36, glow_col, maxf(1.2, 4.5 * fa))
		if dtype == "Electro":
			var zpts := PackedVector2Array([
				fp + Vector2(-42.0, -54.0),
				fp + Vector2(-6.0, -14.0),
				fp + Vector2(-18.0, 4.0),
				fp + Vector2(18.0, 20.0),
				fp + Vector2(4.0, 32.0),
				fp + Vector2(40.0, 62.0),
			])
			c.draw_polyline(zpts, glow_col, 8.0 * fa, true)
			c.draw_polyline(zpts, core_col, 3.2 * fa, true)
		elif dtype == "Hydro":
			for drop_i in range(6):
				var ang: float = float(drop_i) * (TAU / 6.0) + 0.3
				var dp := fp + Vector2(cos(ang), sin(ang)) * (16.0 + fu * 58.0)
				c.draw_circle(dp, maxf(1.5, 6.5 * fa), glow_col)
				c.draw_circle(dp, maxf(0.8, 3.0 * fa), core_col)
		elif dtype == "Anemo":
			c.draw_arc(fp, ring_r * 0.72, fu * 4.0, fu * 4.0 + PI * 1.4, 24, core_col, maxf(1.2, 3.4 * fa))
			c.draw_arc(fp, ring_r * 0.46, -fu * 5.0, -fu * 5.0 + PI * 1.2, 20, glow_col, maxf(1.2, 3.0 * fa))
		elif dtype == "Geo":
			for sh_i in range(5):
				var ang: float = float(sh_i) * (TAU / 5.0) - 0.5
				var sp := fp + Vector2(cos(ang), sin(ang)) * (12.0 + fu * 52.0)
				var sr: float = maxf(2.0, 8.5 * fa)
				c.draw_colored_polygon(PackedVector2Array([
					sp + Vector2(0, -sr), sp + Vector2(sr * 0.75, 0), sp + Vector2(0, sr), sp + Vector2(-sr * 0.75, 0)
				]), glow_col)
		else:
			# Pyro & Physical crisp diagonal slash + cross flare
			var sl_len: float = lerpf(32.0, 64.0, fu)
			c.draw_line(fp + Vector2(-sl_len, -sl_len * 0.85), fp + Vector2(sl_len, sl_len * 0.85), glow_col, 9.0 * fa)
			c.draw_line(fp + Vector2(-sl_len, -sl_len * 0.85), fp + Vector2(sl_len, sl_len * 0.85), core_col, 3.2 * fa)
			c.draw_line(fp + Vector2(sl_len * 0.55, -sl_len * 0.45), fp + Vector2(-sl_len * 0.55, sl_len * 0.45), glow_col, 4.5 * fa)

	# Phase announcement banners
	for b in _banners:
		var u: float = float(b["t"]) / maxf(0.01, float(b["dur"]))
		var alpha: float = 1.0 if u < 0.72 else maxf(0.0, (1.0 - u) / 0.28)
		TCGTheme.draw_phase_announcement(c, String(b["title"]), String(b["sub"]), b["color"] as Color, float(b["y"]), alpha)

	# Action ribbons (Genshin side-mounted character portrait skill/switch/defeat banners)
	for r in _ribbons:
		var t_cur: float = float(r["t"])
		var dur: float = float(r["dur"])
		var alpha: float = 1.0 if t_cur < dur - 0.3 else maxf(0.0, (dur - t_cur) / 0.3)
		var slide: float = 1.0 - pow(1.0 - clampf(t_cur / 0.24, 0.0, 1.0), 3.0)
		var x_off: float = (1.0 - slide) * (46.0 if bool(r.get("align_right", false)) else -46.0)
		var pos: Vector2 = (r["pos"] as Vector2) + Vector2(x_off, 0.0)
		TCGTheme.draw_action_ribbon(
			c,
			String(r["title"]),
			String(r["sub"]),
			r["accent"] as Color,
			pos,
			alpha,
			String(r.get("char_name", "")),
			bool(r.get("align_right", false))
		)

	# Reaction Pills (Genshin-style elemental reactions)
	for p in _reaction_pills:
		var t_cur: float = float(p["t"])
		var dur: float = float(p["dur"])
		var alpha: float = minf(1.0, t_cur / 0.2) * (1.0 if t_cur < dur - 0.4 else maxf(0.0, (dur - t_cur) / 0.4))
		var float_y: float = (p["pos"] as Vector2).y - 18.0 * (1.0 - pow(1.0 - clampf(t_cur / 0.4, 0.0, 1.0), 2.0))
		var cur_pos := Vector2((p["pos"] as Vector2).x, float_y)
		TCGTheme.draw_reaction_pill(c, String(p["title"]), String(p["sub"]), p["elements"] as Array, cur_pos, alpha)

	# Genshin Circular Gold-Rimmed Damage / Heal Pop Badges + Cleanse Pill
	for fl in _floaters:
		var pos: Vector2 = fl["pos"]
		var col: Color = fl["col"]
		var ttl: float = float(fl["ttl"])
		var max_ttl: float = float(fl.get("max_ttl", 1.4))
		var elapsed: float = max_ttl - ttl
		var pop: float = 1.0 + 0.36 * maxf(0.0, 1.0 - elapsed / 0.16)
		var alpha: float = 1.0 if elapsed < max_ttl * 0.65 else maxf(0.0, ttl / (max_ttl * 0.35))
		var txt: String = String(fl["text"])
		if String(fl.get("kind", "")) == "cleanse":
			var pw: float = maxf(124.0, float(txt.length()) * 9.5 + 24.0) * minf(1.15, pop)
			var ph: float = 30.0 * minf(1.15, pop)
			var pr := Rect2(pos.x - pw * 0.5, pos.y - ph * 0.5, pw, ph)
			TCGTheme.draw_rounded_box(c, pr, Color(0.05, 0.22, 0.20, 0.94 * alpha), Color(col.r, col.g, col.b, alpha), int(ph * 0.5), 2.0, Vector2(0, 2), int(80.0 * alpha))
			TCGTheme.draw_text_centered(c, txt, pos, int(13.0 * minf(1.15, pop)), Color(0.88, 1.0, 0.96, alpha), true, true)
			continue
		var is_heal: bool = txt.begins_with("+")
		var badge_r: float = 22.0 * pop
		var bg_col := Color(0.11, 0.40, 0.28, 0.94 * alpha) if is_heal else Color(0.56, 0.14, 0.14, 0.94 * alpha)
		var rim_col := Color(col.r, col.g, col.b, alpha)
		c.draw_circle(pos + Vector2(0, 3.0), badge_r, Color(0.0, 0.0, 0.0, 0.42 * alpha))
		c.draw_circle(pos, badge_r, bg_col)
		c.draw_arc(pos, badge_r, 0.0, TAU, 28, rim_col, 2.8)
		c.draw_arc(pos, badge_r - 3.2, 0.0, TAU, 24, Color(TCGTheme.GOLD_L.r, TCGTheme.GOLD_L.g, TCGTheme.GOLD_L.b, 0.85 * alpha), 1.3)
		TCGTheme.draw_text_centered(c, txt, pos, int(21.0 * pop), Color(1.0, 0.98, 0.92, alpha), true, true)


func _draw_payment_modal(c: CanvasItem, w: float, h: float) -> void:
	## Genshin Inline Dice Payment Drawer: keeps the 3v3 battlefield & enemy -DMG previews clearly visible!
	c.draw_rect(Rect2(0, 0, w, h), Color(0.02, 0.04, 0.07, 0.36))

	var safe: Rect2 = _ensure_lay()["safe"]
	var cx: float = safe.get_center().x
	var prects := _payment_panel_rects()
	var left: Rect2 = prects[0]
	var right: Rect2 = prects[1]

	var is_tune: bool = bool(pay_pending.get("tune", false))
	var title: String = String(pay_pending.get("title", "Action"))
	var detail: String = String(pay_pending.get("detail", ""))
	var sel_dice: Array = pay_pending.get("selected_dice", []).duplicate()
	sel_dice.sort()
	var p := me()

	var valid: bool = false
	var total_needed: int = 1
	if is_tune:
		var elig := tunable_dice(view_player)
		valid = (sel_dice.size() == 1 and elig.has(int(sel_dice[0])))
	else:
		var cost: CardDataSystem.CostData = pay_pending["cost"]
		total_needed = cost.n + cost.unaligned
		valid = TCGDiceSystem.payment_ok(p.dice, cost, sel_dice)

	# 1. Left compact action/card details card (leaves the center 3v3 arena completely unobstructed)
	TCGTheme.draw_gold_frame(c, left, Color(0.05, 0.08, 0.14, 0.94), 12, true)
	TCGTheme.draw_text_pos(c, "ELEMENTAL TUNING" if is_tune else "ACTION DETAILS", Vector2(left.position.x + 14.0, left.position.y + 12.0), 12, TCGTheme.GOLD_L, true, true)
	var title_fsz: int = TCGTheme.fit_font_size(title, left.size.x - 28.0, 18, 13, true)
	TCGTheme.draw_text_pos(c, title, Vector2(left.position.x + 14.0, left.position.y + 32.0), title_fsz, TCGTheme.TEXT, true, true)
	c.draw_line(Vector2(left.position.x + 14.0, left.position.y + 60.0), Vector2(left.end.x - 14.0, left.position.y + 60.0), TCGTheme.GOLD_D, 1.0)

	if is_tune:
		TCGTheme.draw_wrapped(
			c,
			"Convert 1 non-matching die into %s.\n%s" % [p.get_active_char().get_defn().element, detail],
			Rect2(left.position.x + 14.0, left.position.y + 72.0, left.size.x - 28.0, left.size.y - 84.0),
			13,
			TCGTheme.TEXT,
			19,
			false
		)
	else:
		var cost: CardDataSystem.CostData = pay_pending["cost"]
		var pairs := TCGActionCardView.cost_to_pairs(cost)
		var gx: float = left.position.x + 28.0
		for pair in pairs:
			TCGArt.draw_cost_gem(c, String(pair[0]), int(pair[1]), Vector2(gx, left.position.y + 84.0), 12.0)
			gx += 32.0
		var prev_lines: Array = _active_preview.get("summary_lines", []) if bool(_active_preview.get("ok", false)) else []
		if not prev_lines.is_empty():
			TCGTheme.draw_wrapped(c, detail, Rect2(left.position.x + 14.0, left.position.y + 108.0, left.size.x - 28.0, 74.0), 13, TCGTheme.TEXT, 18, false)
			var imp_rect := Rect2(left.position.x + 12.0, left.position.y + 186.0, left.size.x - 24.0, left.end.y - (left.position.y + 198.0))
			TCGTheme.draw_rounded_box(c, imp_rect, Color(0.04, 0.07, 0.11, 0.94), TCGTheme.GOLD_D, 8, 1)
			TCGTheme.draw_text_pos(c, "EXPECTED IMPACT", Vector2(imp_rect.position.x + 10.0, imp_rect.position.y + 6.0), 11, TCGTheme.GOLD_L, true, true)
			TCGTheme.draw_wrapped(c, "\n".join(prev_lines), Rect2(imp_rect.position.x + 10.0, imp_rect.position.y + 24.0, imp_rect.size.x - 20.0, imp_rect.size.y - 28.0), 12, TCGTheme.HEAL, 16, false)
		else:
			TCGTheme.draw_wrapped(c, detail, Rect2(left.position.x + 14.0, left.position.y + 112.0, left.size.x - 28.0, left.size.y - 124.0), 13, TCGTheme.TEXT, 19, false)

	# 2. Right-side warm golden translucent Genshin Dice Drawer
	TCGTheme.draw_rounded_box(c, right, Color(0.24, 0.18, 0.11, 0.88), TCGTheme.GOLD_L, 14, 2, Vector2(-4, 4), 110)
	var inner_r := right.grow(-4.0)
	var isb := StyleBoxFlat.new()
	isb.bg_color = Color(0, 0, 0, 0)
	isb.border_color = Color(TCGTheme.GOLD_D.r, TCGTheme.GOLD_D.g, TCGTheme.GOLD_D.b, 0.65)
	isb.set_border_width_all(1)
	isb.set_corner_radius_all(10)
	c.draw_style_box(isb, inner_r)

	var drawer_hdr := "Select 1 Die" if is_tune else ("Elemental Dice (%d/%d)" % [sel_dice.size(), total_needed])
	TCGTheme.draw_text_centered(c, drawer_hdr, Vector2(right.get_center().x, right.position.y + 30.0), 16, TCGTheme.GOLD_L, true, true)
	c.draw_line(Vector2(right.position.x + 18.0, right.position.y + 54.0), Vector2(right.end.x - 18.0, right.position.y + 54.0), Color(TCGTheme.GOLD.r, TCGTheme.GOLD.g, TCGTheme.GOLD.b, 0.45), 1.0)

	var elig_tune := tunable_dice(view_player)
	for i in range(p.dice.size()):
		var face: String = p.dice[i]
		var tile := _pay_die_rect(i)
		var chosen: bool = sel_dice.has(i)
		var hov: bool = (_pay_die_hovered == i)
		var eligible: bool = true
		if is_tune:
			eligible = elig_tune.has(i)
		else:
			var cost: CardDataSystem.CostData = pay_pending["cost"]
			eligible = (face == CardDataSystem.OMNI or face == cost.element or cost.element.is_empty() or cost.unaligned > 0)

		var d_sz: float = minf(tile.size.x, tile.size.y) * (0.94 if chosen else 0.84)
		var dc := tile.get_center() + Vector2(0.0, -4.0 if chosen else (-2.0 if hov else 0.0))
		if chosen:
			c.draw_circle(dc, d_sz * 0.58, Color(1.0, 0.88, 0.44, 0.24))
			c.draw_arc(dc, d_sz * 0.56, 0.0, TAU, 28, TCGTheme.GOLD_L, 2.2)
		elif hov and eligible:
			c.draw_arc(dc, d_sz * 0.52, 0.0, TAU, 24, Color(TCGTheme.GOLD_L.r, TCGTheme.GOLD_L.g, TCGTheme.GOLD_L.b, 0.65), 1.6)

		var die_box := Rect2(dc.x - d_sz * 0.5, dc.y - d_sz * 0.5, d_sz, d_sz)
		TCGArt.draw_die(c, face, die_box, chosen, hov)
		if not eligible and not chosen:
			c.draw_circle(dc, d_sz * 0.44, Color(0.05, 0.06, 0.09, 0.52))
		if chosen:
			var chk_c := Vector2(die_box.end.x - 4.0, die_box.position.y + 4.0)
			c.draw_circle(chk_c, 9.5, Color8(242, 232, 206))
			c.draw_arc(chk_c, 9.5, 0.0, TAU, 16, TCGTheme.GOLD, 1.5)
			TCGTheme.draw_text_centered(c, "✓", chk_c, 12, Color8(46, 38, 28), true, false)

	# 3. Top-Right Circular Cancel (✕) Button
	var cancel_r := _pay_cancel_rect()
	var cancel_c := cancel_r.get_center()
	var cancel_rad := cancel_r.size.x * 0.5
	var c_hov: bool = (_pay_btn_hovered == 0)
	c.draw_circle(cancel_c + Vector2(0, 2), cancel_rad, Color(0, 0, 0, 0.45))
	c.draw_circle(cancel_c, cancel_rad, Color8(244, 236, 218) if c_hov else Color8(226, 218, 200))
	c.draw_arc(cancel_c, cancel_rad, 0.0, TAU, 28, TCGTheme.GOLD_L if c_hov else TCGTheme.GOLD, 2.2)
	var x_d: float = 8.5
	c.draw_line(cancel_c + Vector2(-x_d, -x_d), cancel_c + Vector2(x_d, x_d), Color8(58, 48, 38), 2.8)
	c.draw_line(cancel_c + Vector2(x_d, -x_d), cancel_c + Vector2(-x_d, x_d), Color8(58, 48, 38), 2.8)

	# 4. Center-Bottom Sleek Action Strip + Iconic Genshin Ivory Confirm Pill
	var conf_r := _pay_confirm_rect()
	var strip_y: float = conf_r.position.y - 36.0
	var strip_w: float = 520.0
	var strip_r := Rect2(cx - strip_w * 0.5, strip_y - 16.0, strip_w, 32.0)
	TCGTheme.draw_rounded_box(c, strip_r, Color(0.05, 0.08, 0.13, 0.84), Color(TCGTheme.GOLD.r, TCGTheme.GOLD.g, TCGTheme.GOLD.b, 0.65), 16, 1.2)
	var prompt_txt: String = title
	var status_col: Color = TCGTheme.GOLD_L
	if not valid:
		if sel_dice.size() < total_needed:
			prompt_txt = "%s  ·  Select %d more" % [title, total_needed - sel_dice.size()]
		else:
			prompt_txt = "Selected dice do not match required cost"
			status_col = TCGTheme.RED
	var p_fsz: int = TCGTheme.fit_font_size(prompt_txt, strip_w - 24.0, 15, 11, true)
	TCGTheme.draw_text_centered(c, prompt_txt, strip_r.get_center(), p_fsz, status_col, true, true)

	TCGTheme.draw_genshin_pill(c, conf_r, "Confirm", _pay_btn_hovered == 1, not valid, "confirm")


func _draw_inspect_tooltip(c: CanvasItem) -> void:
	# Strictly click-driven inspector: hovering never opens description popups.
	var l := _ensure_lay()
	var safe: Rect2 = l["safe"]
	var ikind: String = String(_inspected.get("kind", ""))

	# 1. Clicked Skill button (1st click = inspect, 2nd click = try to use)
	if ikind == "skill":
		var s_idx: int = int(_inspected.get("index", -1))
		var c0: TCGPlayerSystem.CharacterInstance = me().get_active_char()
		if c0 != null and s_idx >= 0:
			var skills: Array[CardDataSystem.SkillData] = c0.get_defn().skills
			if s_idx < skills.size():
				var sk: CardDataSystem.SkillData = skills[s_idx]
				var box_w: float = 400.0
				var can_use: bool = bool(_active_preview.get("can_use_now", true)) if bool(_active_preview.get("ok", false)) else true
				var box_h: float = 148.0 if can_use else 172.0
				var sb_pos: Vector2 = l.get("skill_bar_pos", Vector2(safe.end.x - 328.0, safe.end.y - 166.0))
				var bx: float = clampf(sb_pos.x - 92.0, safe.position.x + 12.0, safe.end.x - box_w - 12.0)
				var by: float = clampf(sb_pos.y - box_h - 12.0, safe.position.y + 72.0, safe.end.y - box_h - 14.0)
				var box := Rect2(bx, by, box_w, box_h)
				var kind_lbl := "ULT" if sk.kind == "burst" else sk.kind.to_upper()
				TCGTheme.draw_gold_frame(c, box, Color(0.06, 0.1, 0.16, 0.97), 10, true)
				TCGTheme.draw_text_pos(c, sk.name + "  [" + kind_lbl + "]", Vector2(box.position.x + 14, box.position.y + 10), 16, TCGTheme.GOLD_L, true, true)
				var pairs := TCGActionCardView.cost_to_pairs(sk.cost)
				var gx: float = box.position.x + 26.0
				for pair in pairs:
					TCGArt.draw_cost_gem(c, String(pair[0]), int(pair[1]), Vector2(gx, box.position.y + 44), 11.5)
					gx += 28.0
				TCGTheme.draw_wrapped(c, sk.desc, Rect2(box.position.x + 14, box.position.y + 64, box.size.x - 28, 72), 14, TCGTheme.TEXT, 18, true)
				if not can_use:
					var reason := String(_active_preview.get("block_reason", "Not currently usable"))
					TCGTheme.draw_text_pos(c, reason, Vector2(box.position.x + 14, box.end.y - 24), 13, TCGTheme.RED, true, false)
				return

	# 2. Clicked Hand Card — Genshin TCG side-by-side Full-Art Card + Dark Detail Panel
	if selected_hand_index >= 0 and selected_hand_index < me().hand.size():
		var cd: CardDataSystem.CardData = CardDataSystem.get_card_def(me().hand[selected_hand_index])
		if cd != null:
			var card_r := Rect2(safe.position.x + 20.0, safe.position.y + 150.0, 198.0, 282.0)
			TCGActionCardView.draw_card_surface(c, card_r, cd.name, true, false, true, false, false, false)

			var info_r := Rect2(card_r.end.x + 12.0, card_r.position.y, 268.0, 212.0)
			TCGTheme.draw_gold_frame(c, info_r, Color(0.05, 0.08, 0.14, 0.95), 12, true)
			TCGTheme.draw_wrapped(c, cd.name, Rect2(info_r.position.x + 14.0, info_r.position.y + 12.0, info_r.size.x - 28.0, 44.0), 17, TCGTheme.GOLD_L, 21, true)
			var pairs := TCGActionCardView.cost_to_pairs(cd.cost)
			var gx: float = info_r.position.x + 26.0
			if pairs.is_empty():
				TCGArt.draw_cost_gem(c, "Same", 0, Vector2(gx, info_r.position.y + 70.0), 11.5)
			else:
				for pair in pairs:
					TCGArt.draw_cost_gem(c, String(pair[0]), int(pair[1]), Vector2(gx, info_r.position.y + 70.0), 11.5)
					gx += 28.0
			var role_lbl := "%s Card" % CardDataSystem.infer_card_role(cd).capitalize()
			if not cd.char_name.is_empty():
				role_lbl += " · %s" % cd.char_name
			TCGTheme.draw_text_pos(c, role_lbl, Vector2(info_r.position.x + 14.0, info_r.position.y + 92.0), 13, TCGTheme.TEAL, true, false)
			TCGTheme.draw_wrapped(c, cd.text, Rect2(info_r.position.x + 14.0, info_r.position.y + 114.0, info_r.size.x - 28.0, 68.0), 13, TCGTheme.TEXT, 18, false)
			var can_play_sel: bool = not get_card_actions_for_hand_index(selected_hand_index).is_empty()
			var hint_txt := "Click again to play · Drag to Dice / [T] Tune" if (is_my_turn() and game_state.phase == "action" and can_play_sel) else ("Drag to Dice Tray, Right-click, or [T] to Tune" if (is_my_turn() and game_state.phase == "action") else "Inspecting card · [Esc] Close")
			TCGTheme.draw_text_pos(c, hint_txt, Vector2(info_r.position.x + 14.0, info_r.end.y - 22.0), 11, TCGTheme.GOLD_L if (is_my_turn() and game_state.phase == "action" and not can_play_sel) else TCGTheme.DIM, false, false)
			return

	# When Phase 9 DetailDrawer is open, it owns status/character inspection.
	if detail_drawer != null and detail_drawer.is_open():
		return

	# 3. Clicked Status / Aura Icon on a Character
	if ikind == "status":
		var payload: Dictionary = _inspected.get("payload", {})
		var pkind: String = String(payload.get("kind", ""))
		var box := Rect2(safe.position.x + 20.0, safe.position.y + 220.0, 300.0, 160.0)
		TCGTheme.draw_gold_frame(c, box, Color(0.06, 0.1, 0.16, 0.97), 10, true)
		if pkind == "aura":
			var aura_el: String = String(payload.get("aura", ""))
			TCGTheme.draw_text_pos(c, "%s Aura" % aura_el, Vector2(box.position.x + 12, box.position.y + 10), 15, TCGTheme.elem_color(aura_el), true, true)
			var body := "Applying a different element triggers an Elemental Reaction:\n• Vaporize (+1) · Melt (+2) · Overloaded (+2, switch)\n• Superconduct (+1, pierce) · Electro-Charged (+1, pierce)\n• Frozen (+1, stun) · Swirl · Crystallize"
			TCGTheme.draw_wrapped(c, body, Rect2(box.position.x + 12, box.position.y + 36, box.size.x - 24, 114), 11, TCGTheme.TEXT, 15, false)
		elif pkind == "equip":
			var eq_name: String = String(payload.get("card_name", ""))
			var eq_slot: String = String(payload.get("slot", "")).to_upper()
			var cdef := CardDataSystem.get_card_def(eq_name)
			TCGTheme.draw_text_pos(c, eq_name, Vector2(box.position.x + 12, box.position.y + 10), 15, TCGTheme.GOLD_L, true, true)
			TCGTheme.draw_text_pos(c, "EQUIPPED " + eq_slot, Vector2(box.position.x + 12, box.position.y + 32), 11, TCGTheme.TEAL, true, false)
			TCGTheme.draw_wrapped(c, cdef.text if cdef != null else "", Rect2(box.position.x + 12, box.position.y + 52, box.size.x - 24, 98), 12, TCGTheme.TEXT, 16, false)
		else:
			var st_name: String = String(payload.get("name", ""))
			var st_inst: TCGPlayerSystem.StatusInstance = payload.get("status")
			var sdef := CardDataSystem.get_status_def(st_name)
			TCGTheme.draw_text_pos(c, st_name, Vector2(box.position.x + 12, box.position.y + 10), 15, TCGTheme.GOLD_L, true, true)
			var st_txt: String = sdef.text if (sdef != null and not sdef.text.is_empty()) else "Active status effect."
			if st_inst != null:
				if st_inst.shield > 0:
					st_txt += "\nRemaining Shield: %d" % st_inst.shield
				elif st_inst.usages >= 0:
					st_txt += "\nRemaining Usages: %d" % st_inst.usages
				if st_inst.duration >= 0:
					st_txt += "\nDuration: %d round(s)" % st_inst.duration
			TCGTheme.draw_wrapped(c, st_txt, Rect2(box.position.x + 12, box.position.y + 36, box.size.x - 24, 114), 12, TCGTheme.TEXT, 16, false)
		return

	# 5. Clicked Character Card (1st click = inspect skills/stats, 2nd click = switch/choose active)
	if ikind == "char":
		var c_side: int = int(_inspected.get("side", -1))
		var c_idx: int = int(_inspected.get("index", -1))
		if c_side >= 0 and c_idx >= 0:
			var p_idx: int = view_player if c_side == 0 else (1 - view_player)
			var ch_st: TCGPlayerSystem.CharacterInstance = game_state.players[p_idx].characters[c_idx]
			var cd: CardDataSystem.CharData = ch_st.get_defn()
			if cd != null:
				var box := Rect2(safe.position.x + 18.0, safe.position.y + 120.0, 320.0, 420.0)
				TCGTheme.draw_gold_frame(c, box, Color(0.06, 0.1, 0.16, 0.97), 12, true)
				TCGTheme.draw_text_pos(
					c,
					"%s (%s · %s)" % [ch_st.name, cd.element, cd.weapon],
					Vector2(box.position.x + 14, box.position.y + 12),
					15,
					TCGTheme.GOLD_L,
					true,
					true
				)
				var info_lines := "HP: %d/%d   ·   Energy: %d/%d   ·   Aura: %s" % [
					ch_st.hp,
					cd.hp,
					ch_st.energy,
					cd.max_energy,
					ch_st.aura if not ch_st.aura.is_empty() else "None"
				]
				TCGTheme.draw_text_pos(c, info_lines, Vector2(box.position.x + 14, box.position.y + 36), 11, TCGTheme.TEAL, true, false)
				var y: float = box.position.y + 62.0
				for sk in cd.skills:
					var sk_box := Rect2(box.position.x + 10, y, box.size.x - 20, 96)
					TCGTheme.draw_rounded_box(c, sk_box, Color8(28, 42, 58), TCGTheme.GOLD_D, 7, 1)
					TCGTheme.draw_text_pos(c, sk.name, Vector2(sk_box.position.x + 10, sk_box.position.y + 6), 12, TCGTheme.TEXT, true, false)
					TCGTheme.draw_text_pos(c, sk.kind.to_upper(), Vector2(sk_box.position.x + 10, sk_box.position.y + 23), 9, TCGTheme.GOLD, true, false)
					var pairs := TCGActionCardView.cost_to_pairs(sk.cost)
					var gx: float = sk_box.end.x - 16.0 - float(pairs.size() - 1) * 20.0
					for pair in pairs:
						TCGArt.draw_cost_gem(c, String(pair[0]), int(pair[1]), Vector2(gx, sk_box.position.y + 16), 8.5)
						gx += 20.0
					TCGTheme.draw_wrapped(c, sk.desc, Rect2(sk_box.position.x + 10, sk_box.position.y + 40, sk_box.size.x - 20, 52), 10, TCGTheme.DIM, 13, false)
					y += 102.0

				var eq_list: PackedStringArray = []
				for slot_k in ch_st.equipment.keys():
					eq_list.append("%s: %s" % [String(slot_k).capitalize(), String(ch_st.equipment[slot_k])])
				for st in ch_st.statuses:
					eq_list.append(st.name)
				if not eq_list.is_empty():
					TCGTheme.draw_wrapped(
						c,
						"Active: " + " · ".join(eq_list),
						Rect2(box.position.x + 14, y + 4.0, box.size.x - 28, 32),
						10,
						TCGTheme.GOLD_L,
						13,
						false
					)
				var char_hint := "Click again to switch/select · Click elsewhere to close" if c_side == 0 else "Opponent character · Click again or elsewhere to close"
				TCGTheme.draw_text_pos(c, char_hint, Vector2(box.position.x + 14, box.end.y - 20), 10, TCGTheme.DIM, false, false)


func _draw_toasts(c: CanvasItem, _w: float) -> void:
	var safe: Rect2 = _ensure_lay()["safe"]
	var y: float = safe.position.y + 66.0
	for t in _toasts:
		var txt: String = String(t["text"])
		var col: Color = t["col"]
		var pill := Rect2(safe.get_center().x - 280.0, y, 560.0, 36.0)
		TCGTheme.draw_rounded_box(c, pill, Color(0.05, 0.08, 0.13, 0.94), col, 16, 1)
		TCGTheme.draw_text_centered(c, txt, pill.get_center(), 15, col, true, true)
		y += 40.0


func _draw_game_over_overlay(c: CanvasItem, w: float, h: float) -> void:
	## Minimal Genshin Golden Starlight Victory / Defeat Screen
	c.draw_rect(Rect2(0, 0, w, h), Color(0.02, 0.03, 0.05, 0.78))
	var safe: Rect2 = _ensure_lay()["safe"]
	var center := safe.get_center()
	var win_p: int = game_state.winner
	var is_win: bool = (win_p == view_player) or (not human_flags[view_player] and win_p >= 0)
	var msg := "Draw"
	var col := TCGTheme.TEXT
	if win_p >= 0:
		if human_flags[view_player] and not hotseat:
			msg = "Victory" if win_p == view_player else "Defeat"
			col = TCGTheme.GOLD_L if win_p == view_player else Color8(220, 120, 118)
		else:
			msg = "%s Wins" % player_labels[win_p]
			col = TCGTheme.GOLD_L

	# Celestial starlight burst behind title
	var title_c := Vector2(center.x, center.y - 84.0)
	var glow_col := TCGTheme.GOLD_L if is_win else Color8(190, 92, 92)
	c.draw_circle(title_c, 138.0, Color(glow_col.r, glow_col.g, glow_col.b, 0.08))
	c.draw_circle(title_c, 74.0, Color(glow_col.r, glow_col.g, glow_col.b, 0.12))
	c.draw_arc(title_c, 88.0, 0.0, TAU, 48, Color(glow_col.r, glow_col.g, glow_col.b, 0.35), 1.4)
	# 4-point starlight cross flare
	c.draw_colored_polygon(PackedVector2Array([
		title_c + Vector2(0, -118), title_c + Vector2(7, -10), title_c + Vector2(0, 118), title_c + Vector2(-7, -10)
	]), Color(glow_col.r, glow_col.g, glow_col.b, 0.18))
	c.draw_colored_polygon(PackedVector2Array([
		title_c + Vector2(-210, 0), title_c + Vector2(0, -5), title_c + Vector2(210, 0), title_c + Vector2(0, 5)
	]), Color(glow_col.r, glow_col.g, glow_col.b, 0.28))

	TCGTheme.draw_text_centered(c, msg, title_c, 68, col, true, true)

	# Delicate gold hairline divider with central diamond
	var div_y: float = center.y - 22.0
	c.draw_line(Vector2(center.x - 240.0, div_y), Vector2(center.x + 240.0, div_y), Color(glow_col.r, glow_col.g, glow_col.b, 0.65), 1.5)
	c.draw_colored_polygon(PackedVector2Array([
		Vector2(center.x, div_y - 5.0), Vector2(center.x + 5.0, div_y), Vector2(center.x, div_y + 5.0), Vector2(center.x - 5.0, div_y)
	]), glow_col)

	TCGTheme.draw_genshin_pill(c, _game_over_rect(0), "Rematch", _over_hover_idx == 0, false, "confirm")
	TCGTheme.draw_genshin_pill(c, _game_over_rect(1), "Main Menu", _over_hover_idx == 1, false, "cancel")


func _draw_coin_intro(c: CanvasItem, w: float, h: float) -> void:
	## Genshin 3v3 VS Lineup Showcase + Turn Order Reveal
	c.draw_rect(Rect2(0, 0, w, h), Color(0.02, 0.03, 0.06, 0.84))
	var safe: Rect2 = _ensure_lay()["safe"]
	var center: Vector2 = safe.get_center()
	var cx: float = center.x
	var cy: float = center.y - 24.0

	var slide_u: float = 1.0 - pow(1.0 - clampf(_intro_t / 0.42, 0.0, 1.0), 3.0)
	var p_own: TCGPlayerSystem.PlayerState = game_state.players[view_player]
	var p_foe: TCGPlayerSystem.PlayerState = game_state.players[1 - view_player]

	# Soft horizontal celestial band across the arena
	c.draw_rect(Rect2(0.0, cy - 170.0, w, 340.0), Color(0.06, 0.09, 0.15, 0.56))
	c.draw_line(Vector2(safe.position.x + 40.0, cy - 170.0), Vector2(safe.end.x - 40.0, cy - 170.0), Color(TCGTheme.GOLD.r, TCGTheme.GOLD.g, TCGTheme.GOLD.b, 0.55), 1.6)
	c.draw_line(Vector2(safe.position.x + 40.0, cy + 170.0), Vector2(safe.end.x - 40.0, cy + 170.0), Color(TCGTheme.GOLD.r, TCGTheme.GOLD.g, TCGTheme.GOLD.b, 0.55), 1.6)

	var cw: float = 136.0
	var ch: float = 228.0
	var gap: float = 16.0
	var team_w: float = cw * 3.0 + gap * 2.0

	# Left team (Player) sliding in from left
	var left_x0: float = cx - 96.0 - team_w - (1.0 - slide_u) * 140.0
	TCGTheme.draw_text_centered(c, _who(view_player).to_upper(), Vector2(left_x0 + team_w * 0.5, cy - ch * 0.5 - 24.0), 17, TCGTheme.GOLD_L, true, true)
	for i in range(mini(3, p_own.characters.size())):
		var ch_inst: TCGPlayerSystem.CharacterInstance = p_own.characters[i]
		var cd: CardDataSystem.CharData = ch_inst.get_defn()
		var elem: String = cd.element if cd != null else ""
		var cr := Rect2(left_x0 + float(i) * (cw + gap), cy - ch * 0.5, cw, ch)
		TCGTheme.draw_gold_frame(c, cr, TCGTheme.PANEL, 12, false)
		var tex := TCGArt.get_character_texture(ch_inst.name)
		if tex != null:
			TCGArt.draw_texture_cover(c, tex, cr.grow(-4.0), Color.WHITE, 0.16)
		var name_bar := Rect2(cr.position.x + 4.0, cr.end.y - 34.0, cr.size.x - 8.0, 30.0)
		c.draw_rect(name_bar, Color(0.04, 0.06, 0.10, 0.86))
		TCGTheme.draw_text_centered(c, ch_inst.name, name_bar.get_center(), 14, TCGTheme.GOLD_L, true, true)
		if not elem.is_empty():
			TCGArt.draw_elem_symbol(c, elem, Vector2(cr.position.x + 20.0, cr.position.y + 20.0), 10.5, Color(0, 0, 0, 0), true)

	# Right team (Opponent) sliding in from right
	var right_x0: float = cx + 96.0 + (1.0 - slide_u) * 140.0
	TCGTheme.draw_text_centered(c, _who(1 - view_player).to_upper(), Vector2(right_x0 + team_w * 0.5, cy - ch * 0.5 - 24.0), 17, TCGTheme.GOLD_L, true, true)
	for i in range(mini(3, p_foe.characters.size())):
		var ch_inst: TCGPlayerSystem.CharacterInstance = p_foe.characters[i]
		var cd: CardDataSystem.CharData = ch_inst.get_defn()
		var elem: String = cd.element if cd != null else ""
		var cr := Rect2(right_x0 + float(i) * (cw + gap), cy - ch * 0.5, cw, ch)
		TCGTheme.draw_gold_frame(c, cr, TCGTheme.PANEL, 12, false)
		var tex := TCGArt.get_character_texture(ch_inst.name)
		if tex != null:
			TCGArt.draw_texture_cover(c, tex, cr.grow(-4.0), Color.WHITE, 0.16)
		var name_bar := Rect2(cr.position.x + 4.0, cr.end.y - 34.0, cr.size.x - 8.0, 30.0)
		c.draw_rect(name_bar, Color(0.04, 0.06, 0.10, 0.86))
		TCGTheme.draw_text_centered(c, ch_inst.name, name_bar.get_center(), 14, TCGTheme.GOLD_L, true, true)
		if not elem.is_empty():
			TCGArt.draw_elem_symbol(c, elem, Vector2(cr.end.x - 20.0, cr.position.y + 20.0), 10.5, Color(0, 0, 0, 0), true)

	# Center glowing golden VS diamond emblem
	var vs_c := Vector2(cx, cy)
	var pulse := 0.5 + 0.5 * sin(_clock * 5.0)
	c.draw_circle(vs_c, 58.0 + pulse * 4.0, Color(1.0, 0.86, 0.45, 0.16))
	var dm := 48.0
	var d_pts := PackedVector2Array([
		vs_c + Vector2(0, -dm), vs_c + Vector2(dm, 0), vs_c + Vector2(0, dm), vs_c + Vector2(-dm, 0)
	])
	c.draw_colored_polygon(d_pts, Color(0.07, 0.10, 0.16, 0.96))
	var d_rim := d_pts.duplicate()
	d_rim.append(d_pts[0])
	c.draw_polyline(d_rim, TCGTheme.GOLD_L, 2.8, true)
	TCGTheme.draw_text_centered(c, "VS", vs_c, 36, TCGTheme.GOLD_L, true, true)

	# Bottom turn-order reveal banner
	var spinning: bool = _intro_t < 0.95
	var fp: int = game_state.first_player
	var who_fp: String = _who(fp)
	var first_txt: String = "You start first!" if who_fp == "You" else ("%s starts first!" % who_fp)
	var title: String = "Determining Turn Order…" if spinning else first_txt
	TCGTheme.draw_phase_announcement(c, title, "Click or press Space to begin" if not spinning else "", TCGTheme.GOLD_L, cy + 236.0, 1.0)


func _draw_hotseat_cover(c: CanvasItem, w: float, h: float) -> void:
	c.draw_rect(Rect2(0, 0, w, h), Color(0.03, 0.05, 0.09, 0.94))
	var safe: Rect2 = _ensure_lay()["safe"]
	var center: Vector2 = safe.get_center()
	var panel := Rect2(center.x - 270.0, center.y - 110.0, 540.0, 220.0)
	TCGTheme.draw_gold_frame(c, panel, TCGTheme.PANEL, 16, true)
	TCGTheme.draw_text_centered(c, "PASS DEVICE TO %s" % _who(_hotseat_cover).to_upper(), Vector2(panel.get_center().x, panel.position.y + 74.0), 26, TCGTheme.GOLD_L, true, true)
	TCGTheme.draw_text_centered(c, "Click anywhere or press Space / Enter to reveal your hand", Vector2(panel.get_center().x, panel.position.y + 132.0), 17, TCGTheme.TEXT, false, true)


func _draw_pause_modal(c: CanvasItem, w: float, h: float) -> void:
	c.draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.68))
	var safe: Rect2 = _ensure_lay()["safe"]
	var center: Vector2 = safe.get_center()
	var modal := Rect2(center.x - 230.0, center.y - 170.0, 460.0, 340.0)
	TCGTheme.draw_gold_frame(c, modal, TCGTheme.PANEL, 16, true)
	TCGTheme.draw_text_centered(c, "MATCH PAUSED", Vector2(modal.get_center().x, modal.position.y + 48.0), 28, TCGTheme.GOLD_L, true, true)
	TCGTheme.draw_plaque(c, _pause_option_rect(0), "Resume Match", TCGTheme.GREEN, _pause_hover_idx == 0)
	TCGTheme.draw_plaque(c, _pause_option_rect(1), "Return to Main Menu", TCGTheme.GOLD, _pause_hover_idx == 1)
	TCGTheme.draw_plaque(c, _pause_option_rect(2), "Quit Game", TCGTheme.RED, _pause_hover_idx == 2)

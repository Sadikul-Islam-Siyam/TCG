class_name TCGMatchScene
extends Control
## Stage 6: Match / Board Screen with Full Card, Hand, Selection, Targeting, Payment & Play Interactions
## Direct port of PythonTCG/ui/match.py (`MatchScene`).
## Drives all results strictly through `TCGMatchLifecycle` and `TCGRulesEngine`.

signal return_to_menu_requested()

const CW: float = 120.0
const CH: float = 190.0
const CHAR_X0: float = 440.0
const CHAR_STEP: float = 140.0
const FOE_Y: float = 100.0
const OWN_Y: float = 400.0

const REACT_DESC: Dictionary = {
	"Vaporize": "+1 DMG (Hydro + Pyro)",
	"Melt": "+2 DMG (Cryo + Pyro)",
	"Overloaded": "+2 DMG, forced switch (Pyro + Electro)",
	"Superconduct": "+1 DMG, 1 Piercing to others (Cryo + Electro)",
	"Electro-Charged": "+1 DMG, 1 Piercing to others (Hydro + Electro)",
	"Frozen": "+1 DMG, target Frozen (Cryo + Hydro)",
	"Swirl": "1 Elemental DMG to other characters (Anemo)",
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

var game_state: TCGGameState = null
var lifecycle: TCGMatchLifecycle = null
var legal_actions: Array[TCGGameState.ActionData] = []
var _last_match_config: Dictionary = {}

# Reusable Child Components
var own_hud: TCGPlayerHudBanner = null
var foe_hud: TCGPlayerHudBanner = null
var own_supports_grid: TCGZoneGrid = null
var own_summons_grid: TCGZoneGrid = null
var foe_supports_grid: TCGZoneGrid = null
var foe_summons_grid: TCGZoneGrid = null
var own_char_slots: Array[TCGCharacterSlot] = []
var foe_char_slots: Array[TCGCharacterSlot] = []
var dice_tray: TCGDiceTray = null
var skill_bar: TCGSkillBar = null
var battle_log: TCGBattleLogPanel = null
var hand_strip: TCGHandStrip = null

# Player Selection & Interaction States
var selected_hand_index: int = -1      # Selected hand card awaiting target click or play
var mulligan_swap_indices: Array[int] = []
var roll_selected_dice: Array[int] = []
var pay_pending: Dictionary = {}       # Empty when inactive; otherwise {"action", "cost", "title", "detail", "tune", "card_index", "selected_dice"}
var drag_state: Dictionary = {}        # Empty when inactive; otherwise {"hand_index", "card_name", "pos"}

# Hover / Inspector States
var _hovered_char_side: int = -1
var _hovered_char_idx: int = -1
var _hovered_skill_idx: int = -1
var _hovered_card_name: String = ""
var _hovered_zone_info: Dictionary = {}
var _hovered_status_payload: Dictionary = {}
var _inspected: Dictionary = {}            # {"kind": "char"|"skill"|"zone"|"status", ...}
var _inspect_extra_open: bool = false
var _inspect_btn_hovered: bool = false
var _end_phase_hovered: bool = false
var _pause_hovered: bool = false
var _action_btn_hovered: bool = false
var _pay_btn_hovered: int = -1         # 0 = cancel, 1 = confirm
var _pay_die_hovered: int = -1
var _pause_open: bool = false
var _pause_hover_idx: int = -1
var _over_hover_idx: int = -1
var _intro_t: float = INTRO_DUR
var _hotseat_cover: int = -1
var _busy_timer: float = 0.0

# Lightweight Visual FX & Toasts (strictly separated from rules evaluation)
var _toasts: Array[Dictionary] = []    # {"text": String, "col": Color, "ttl": float}
var _floaters: Array[Dictionary] = []  # {"text": String, "pos": Vector2, "col": Color, "ttl": float, "max_ttl": float}
var _reaction_pills: Array[Dictionary] = [] # {"title": String, "sub": String, "elements": Array, "pos": Vector2, "t": float, "dur": float}
var _ribbons: Array[Dictionary] = []        # {"title": String, "sub": String, "accent": Color, "pos": Vector2, "t": float, "dur": float, "mine": bool}
var _banners: Array[Dictionary] = []        # {"title": String, "sub": String, "color": Color, "y": float, "t": float, "dur": float}
var _burst_flash_alpha: float = 0.0
var _lunges: Dictionary = {}                # "p_i" -> float remaining seconds
var _flying_cards: Array[Dictionary] = [] # {"card_name": String, "from": Vector2, "to": Vector2, "t": float, "dur": float}
var _hit_flash: Dictionary = {}        # "p_i" -> float remaining seconds
var _ai_timer: float = 0.72
var _own_slot_targets: Array[Vector2] = []
var _foe_slot_targets: Array[Vector2] = []
var _hand_target_pos: Vector2 = Vector2(246, 544)
var _slots_initialized: bool = false


var _overlay_canvas: Control = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_build_board_components()
	if game_state == null:
		start_demo_match("pve", 0, 1, 42)


func _build_board_components() -> void:
	for child in get_children():
		child.queue_free()
	own_char_slots.clear()
	foe_char_slots.clear()

	# 1. Player & Opponent Status Banners
	foe_hud = TCGPlayerHudBanner.new()
	foe_hud.position = Vector2(24, 18)
	add_child(foe_hud)

	own_hud = TCGPlayerHudBanner.new()
	own_hud.position = Vector2(24, 658)
	add_child(own_hud)

	# 2. 2x2 Support & Summon Zone Grids (mirrored across sides)
	foe_summons_grid = TCGZoneGrid.new()
	foe_summons_grid.position = Vector2(208, 86)
	foe_summons_grid.unit_hovered.connect(func(is_sum: bool, idx: int, u: TCGPlayerSystem.UnitInstance, hov: bool): _on_zone_unit_hovered(1, is_sum, idx, u, hov))
	foe_summons_grid.unit_clicked.connect(func(is_sum: bool, idx: int, u: TCGPlayerSystem.UnitInstance): _on_zone_unit_clicked(1, is_sum, idx, u))
	add_child(foe_summons_grid)

	foe_supports_grid = TCGZoneGrid.new()
	foe_supports_grid.position = Vector2(934, 86)
	foe_supports_grid.unit_hovered.connect(func(is_sum: bool, idx: int, u: TCGPlayerSystem.UnitInstance, hov: bool): _on_zone_unit_hovered(1, is_sum, idx, u, hov))
	foe_supports_grid.unit_clicked.connect(func(is_sum: bool, idx: int, u: TCGPlayerSystem.UnitInstance): _on_zone_unit_clicked(1, is_sum, idx, u))
	add_child(foe_supports_grid)

	own_supports_grid = TCGZoneGrid.new()
	own_supports_grid.position = Vector2(208, 386)
	own_supports_grid.unit_hovered.connect(func(is_sum: bool, idx: int, u: TCGPlayerSystem.UnitInstance, hov: bool): _on_zone_unit_hovered(0, is_sum, idx, u, hov))
	own_supports_grid.unit_clicked.connect(func(is_sum: bool, idx: int, u: TCGPlayerSystem.UnitInstance): _on_zone_unit_clicked(0, is_sum, idx, u))
	add_child(own_supports_grid)

	own_summons_grid = TCGZoneGrid.new()
	own_summons_grid.position = Vector2(934, 386)
	own_summons_grid.unit_hovered.connect(func(is_sum: bool, idx: int, u: TCGPlayerSystem.UnitInstance, hov: bool): _on_zone_unit_hovered(0, is_sum, idx, u, hov))
	own_summons_grid.unit_clicked.connect(func(is_sum: bool, idx: int, u: TCGPlayerSystem.UnitInstance): _on_zone_unit_clicked(0, is_sum, idx, u))
	add_child(own_summons_grid)

	# 3. Character Slots (3 Opponent + 3 Player)
	for i in range(3):
		var f_slot := TCGCharacterSlot.new()
		f_slot.slot_clicked.connect(_on_char_slot_clicked)
		f_slot.slot_hovered.connect(_on_char_slot_hovered)
		f_slot.status_icon_hovered.connect(_on_status_icon_hovered)
		f_slot.status_icon_clicked.connect(_on_status_icon_clicked)
		add_child(f_slot)
		foe_char_slots.append(f_slot)

	for i in range(3):
		var o_slot := TCGCharacterSlot.new()
		o_slot.slot_clicked.connect(_on_char_slot_clicked)
		o_slot.slot_hovered.connect(_on_char_slot_hovered)
		o_slot.status_icon_hovered.connect(_on_status_icon_hovered)
		o_slot.status_icon_clicked.connect(_on_status_icon_clicked)
		add_child(o_slot)
		own_char_slots.append(o_slot)

	# 4. Battle Log Panel (left side)
	battle_log = TCGBattleLogPanel.new()
	battle_log.position = Vector2(14, 184)
	add_child(battle_log)

	# 5. Dice Tray (right side)
	dice_tray = TCGDiceTray.new()
	dice_tray.position = Vector2(1200, 96)
	dice_tray.die_clicked.connect(_on_tray_die_clicked)
	add_child(dice_tray)

	# 6. Skill Buttons Bar (bottom-right)
	skill_bar = TCGSkillBar.new()
	skill_bar.position = Vector2(974, 548)
	skill_bar.z_index = 10
	skill_bar.skill_clicked.connect(_on_skill_clicked)
	skill_bar.skill_hovered.connect(_on_skill_hovered)
	add_child(skill_bar)

	# 7. Hand Strip (bottom-center, separated from skill_bar so Normal Attack is never covered)
	hand_strip = TCGHandStrip.new()
	hand_strip.position = Vector2(174, 544)
	hand_strip.hand_card_clicked.connect(_on_hand_card_clicked)
	hand_strip.hand_card_right_clicked.connect(_on_hand_card_right_clicked)
	hand_strip.hand_card_drag_started.connect(_on_hand_card_drag_started)
	hand_strip.hand_card_hovered.connect(_on_hand_card_hovered)
	add_child(hand_strip)

	# 8. Top Overlay Layer (renders above all child controls: prompts, FX, dragged card, inspector, payment modal, toasts, pause/over)
	_overlay_canvas = Control.new()
	_overlay_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_canvas.z_index = 100
	_overlay_canvas.draw.connect(_draw_top_overlays)
	add_child(_overlay_canvas)


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
	drag_state.clear()
	_toasts.clear()
	_floaters.clear()
	_reaction_pills.clear()
	_ribbons.clear()
	_banners.clear()
	_flying_cards.clear()
	_hit_flash.clear()
	_lunges.clear()
	_slots_initialized = false
	_pause_open = false
	_pause_hover_idx = -1
	_over_hover_idx = -1
	_hotseat_cover = -1
	_busy_timer = 0.0
	_intro_t = 0.0 if (p_show_intro and not auto_advance_to_action) else INTRO_DUR

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


# ------------------------------------------------------------------------------
# Rules-Driven Action Execution & Event Presentation
# ------------------------------------------------------------------------------
func execute_action(action: TCGGameState.ActionData) -> Dictionary:
	## Submits an ActionData to TCGMatchLifecycle / TCGRulesEngine, records
	## lightweight visual feedback from `events`, and synchronizes the board.
	var res: Dictionary = lifecycle.submit_action(action)
	if not bool(res.get("ok", false)):
		var err_str: String = String(res.get("error", "Illegal action"))
		show_toast("Can't do that: %s" % err_str, TCGTheme.RED)
		sync_from_state()
		return res

	_present_events(res.get("events", []))
	selected_hand_index = -1
	_inspected.clear()
	_inspect_extra_open = false
	mulligan_swap_indices.clear()
	roll_selected_dice.clear()
	pay_pending.clear()
	drag_state.clear()

	# Hotseat view switching when active human player changes
	var next_actor: int = actor()
	if hotseat and next_actor >= 0 and next_actor != view_player:
		view_player = next_actor
		if game_state != null and game_state.phase != "over":
			_hotseat_cover = next_actor

	sync_from_state()
	return res


func _present_events(events: Array) -> void:
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
				_floaters.append({
					"text": "-%d" % amt,
					"pos": pos + Vector2(0, -10),
					"vel_y": -82.0,
					"col": TCGTheme.elem_color(dtype),
					"ttl": 1.5,
					"max_ttl": 1.5,
				})
				if rx != null and not String(rx).is_empty():
					var rx_name: String = String(rx)
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
				_floaters.append({
					"text": "+%d" % amt,
					"pos": pos + Vector2(0, -14),
					"vel_y": -74.0,
					"col": TCGTheme.HEAL,
					"ttl": 1.4,
					"max_ttl": 1.4,
				})
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
				_ribbons.append({
					"title": sk_name,
					"sub": "%s · %s%s" % [who, ch_obj.name, " · Elemental Burst" if is_burst else ""],
					"accent": elem_col,
					"pos": Vector2(640, 260),
					"t": 0.0,
					"dur": 2.4 if is_burst else 1.85,
					"mine": (sp == view_player),
				})
				_busy_timer = maxf(_busy_timer, 1.35 if is_burst else 0.90)
				if is_burst:
					_burst_flash_alpha = 0.65
			"switch":
				var sw_p: int = int(ev.get("player", 0))
				var sw_c: int = int(ev.get("char", 0))
				var sw_ch := game_state.players[sw_p].characters[sw_c]
				var who: String = _who(sw_p)
				var elem_col: Color = TCGTheme.elem_color(sw_ch.get_defn().element) if sw_ch.get_defn() != null else TCGTheme.GOLD
				_ribbons.append({
					"title": "%s steps forward" % sw_ch.name,
					"sub": "%s switched active character" % who,
					"accent": elem_col,
					"pos": Vector2(640, 260),
					"t": 0.0,
					"dur": 1.65,
					"mine": (sw_p == view_player),
				})
				_busy_timer = maxf(_busy_timer, 0.70)
			"card":
				var cname: String = String(ev.get("name", ""))
				var cplayer: int = int(ev.get("player", 0))
				var start_p := Vector2(640, 620) if cplayer == view_player else Vector2(640, 20)
				_flying_cards.append({
					"card_name": cname,
					"from": start_p,
					"to": Vector2(640, 320),
					"t": 0.0,
					"dur": 0.85,
				})
				_busy_timer = maxf(_busy_timer, 0.65)
			"summon":
				show_toast("Summoned %s" % String(ev.get("name", "")), TCGTheme.TEAL, 1.8)
			"defeat":
				var dp: int = int(ev.get("player", 0))
				var di: int = int(ev.get("char", 0))
				var dch := game_state.players[dp].characters[di]
				_ribbons.append({
					"title": "%s was defeated" % dch.name,
					"sub": "",
					"accent": TCGTheme.RED,
					"pos": Vector2(640, 260),
					"t": 0.0,
					"dur": 1.8,
					"mine": (dp == view_player),
				})
				_busy_timer = maxf(_busy_timer, 0.95)
				show_toast("%s was defeated!" % dch.name, TCGTheme.RED, 2.2)
			"phase":
				var pname: String = String(ev.get("name", ""))
				if pname == "action":
					_banners.append({
						"title": "Action Phase",
						"sub": "Take turns. Declare End Round when you are done.",
						"color": TCGTheme.GOLD,
						"y": 350.0,
						"t": 0.0,
						"dur": 1.85,
					})
					_busy_timer = maxf(_busy_timer, 0.75)
				elif pname == "end":
					_banners.append({
						"title": "End Phase",
						"sub": "Summons act, then both players draw 2 cards",
						"color": TCGTheme.GOLD,
						"y": 350.0,
						"t": 0.0,
						"dur": 1.85,
					})
					_busy_timer = maxf(_busy_timer, 0.85)
			"round":
				var rnum: int = int(ev.get("number", 1))
				if dice_tray != null:
					dice_tray.trigger_roll([], 0.78)
				_banners.append({
					"title": "Round %d" % rnum,
					"sub": "Roll Phase",
					"color": TCGTheme.GOLD_L,
					"y": 350.0,
					"t": 0.0,
					"dur": 1.9,
				})
				_busy_timer = maxf(_busy_timer, 0.85)
				if dice_tray != null:
					dice_tray.trigger_roll()
			"end_round":
				var ep: int = int(ev.get("player", 0))
				var who: String = _who(ep)
				_ribbons.append({
					"title": "%s ended the round" % who,
					"sub": "",
					"accent": TCGTheme.DIM,
					"pos": Vector2(640, 260),
					"t": 0.0,
					"dur": 1.4,
					"mine": (ep == view_player),
				})
				_busy_timer = maxf(_busy_timer, 0.5)


func _char_slot_center(p_idx: int, c_idx: int) -> Vector2:
	var slots := own_char_slots if p_idx == view_player else foe_char_slots
	if c_idx >= 0 and c_idx < slots.size():
		return slots[c_idx].position + slots[c_idx].size * 0.5
	return Vector2(640, 360)


# ------------------------------------------------------------------------------
# Payment & Elemental Tuning Modal Workflow (`begin_payment`, `begin_tune`)
# ------------------------------------------------------------------------------
func begin_payment(
	action: TCGGameState.ActionData,
	cost: CardDataSystem.CostData,
	title: String,
	detail: String = ""
) -> bool:
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
	show_toast("Confirm dice to spend (or click dice to change selection)", TCGTheme.GOLD_L, 2.0)
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
			return "No alive character uses a %s" % cd.weapon
		if cd.kind == "support" and p.supports.size() >= CardDataSystem.MAX_SUPPORTS:
			return "Support zone is full (max 4)"
		return "No valid target for %s" % cname

	return "Not enough matching elemental dice for %s" % cname


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
			return {"ok": true, "payment_opened": not pay_pending.is_empty()}

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

	if matched == null:
		show_toast("Invalid target for %s" % cname, TCGTheme.RED)
		return {"ok": false, "error": "invalid target"}

	selected_hand_index = hand_idx
	begin_payment(matched, cd.cost, cd.name, cd.text)
	return {"ok": true, "payment_opened": not pay_pending.is_empty()}


# ------------------------------------------------------------------------------
# Board State Synchronization
# ------------------------------------------------------------------------------
func sync_from_state() -> void:
	if game_state == null:
		return

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

	# 1. Update HUD Banners
	own_hud.setup(
		0,
		player_labels[view_player],
		c_own.name if c_own != null else "None",
		c_own.get_defn().element if c_own != null else "Omni",
		act_actor == view_player and game_state.phase == "action",
		p_own.ended,
		false,
		p_own.dice.size()
	)
	foe_hud.setup(
		1,
		player_labels[1 - view_player],
		c_foe.name if c_foe != null else "None",
		c_foe.get_defn().element if c_foe != null else "Omni",
		act_actor == (1 - view_player) and game_state.phase == "action",
		p_foe.ended,
		true,
		p_foe.dice.size()
	)

	# 2. Update Support & Summon Zones
	own_supports_grid.setup("SUPPORTS", false, p_own.supports)
	own_summons_grid.setup("SUMMONS", true, p_own.summons)
	foe_summons_grid.setup("SUMMONS", true, p_foe.summons)
	foe_supports_grid.setup("SUPPORTS", false, p_foe.supports)

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

	# 4. Update Character Slots (smoothly interpolated in _process when live)
	_foe_slot_targets.resize(3)
	_own_slot_targets.resize(3)
	var snap_layout: bool = (not _slots_initialized) or (not is_inside_tree())
	for i in range(3):
		var slot_idx_foe: int = 2 - i
		var x_foe: float = CHAR_X0 + float(slot_idx_foe) * CHAR_STEP
		var is_act_foe: bool = (p_foe.active == i)
		var y_foe: float = FOE_Y + (14.0 if is_act_foe else 0.0)
		_foe_slot_targets[i] = Vector2(x_foe, y_foe)
		if snap_layout:
			foe_char_slots[i].position = _foe_slot_targets[i]
		var f_flash: float = float(_hit_flash.get("%d_%d" % [1 - view_player, i], 0.0))
		var f_lunge_t: float = float(_lunges.get("%d_%d" % [1 - view_player, i], 0.0))
		var f_lunge_offset := Vector2(0.0, sin((1.0 - f_lunge_t / 0.55) * PI) * 20.0) if f_lunge_t > 0.0 else Vector2.ZERO
		foe_char_slots[i].setup(1, i, p_foe.characters[i], is_act_foe, false, false, false, -1, f_flash, f_lunge_offset)

		var x_own: float = CHAR_X0 + float(i) * CHAR_STEP
		var is_act_own: bool = (p_own.active == i)
		var y_own: float = OWN_Y - (14.0 if is_act_own else 0.0)
		_own_slot_targets[i] = Vector2(x_own, y_own)
		if snap_layout:
			own_char_slots[i].position = _own_slot_targets[i]
		var o_flash: float = float(_hit_flash.get("%d_%d" % [view_player, i], 0.0))
		var o_lunge_t: float = float(_lunges.get("%d_%d" % [view_player, i], 0.0))
		var o_lunge_offset := Vector2(0.0, -sin((1.0 - o_lunge_t / 0.55) * PI) * 20.0) if o_lunge_t > 0.0 else Vector2.ZERO
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
			o_lunge_offset
		)

	# 5. Update Dice Tray
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
	dice_tray.setup(
		p_own.dice,
		tray_selected,
		hl_dice,
		not drag_state.is_empty(),
		tunable_dice(view_player)
	)

	# 6. Update Skill Bar
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
	_hand_target_pos = Vector2(250, 250) if in_mulligan else Vector2(174, 544)
	if (not _slots_initialized) or (not is_inside_tree()):
		hand_strip.position = _hand_target_pos
		_slots_initialized = true
	hand_strip.setup(
		p_own.hand,
		playable_cards,
		selected_hand_index,
		mulligan_swap_indices,
		in_mulligan,
		(not human_flags[view_player] and not reveal_opponent_hand) or _hotseat_cover >= 0,
		int(drag_state.get("hand_index", -1))
	)

	# 8. Update Battle Log
	battle_log.setup(game_state.log)

	queue_redraw()


# ------------------------------------------------------------------------------
# Process Loop (Animations & AI Turn Execution)
# ------------------------------------------------------------------------------
func _process(delta: float) -> void:
	var dirty: bool = false

	# Smoothly glide character slots and hand strip toward their layout targets
	var k_pos: float = 1.0 - exp(-12.0 * delta * game_speed)
	if _foe_slot_targets.size() == 3 and foe_char_slots.size() == 3:
		for i in range(3):
			if not foe_char_slots[i].position.is_equal_approx(_foe_slot_targets[i]):
				foe_char_slots[i].position = foe_char_slots[i].position.lerp(_foe_slot_targets[i], k_pos)
			if not own_char_slots[i].position.is_equal_approx(_own_slot_targets[i]):
				own_char_slots[i].position = own_char_slots[i].position.lerp(_own_slot_targets[i], k_pos)
	if hand_strip != null and not hand_strip.position.is_equal_approx(_hand_target_pos):
		hand_strip.position = hand_strip.position.lerp(_hand_target_pos, k_pos)

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
			var f_lunge := Vector2(0.0, sin((1.0 - f_lunge_t / 0.55) * PI) * 20.0) if f_lunge_t > 0.0 else Vector2.ZERO
			foe_char_slots[i].set_anim_state(f_flash, f_lunge)

			var o_flash: float = float(_hit_flash.get("%d_%d" % [view_player, i], 0.0))
			var o_lunge_t: float = float(_lunges.get("%d_%d" % [view_player, i], 0.0))
			var o_lunge := Vector2(0.0, -sin((1.0 - o_lunge_t / 0.55) * PI) * 20.0) if o_lunge_t > 0.0 else Vector2.ZERO
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
				var ai_res := lifecycle.step_ai_if_ready()
				if bool(ai_res.get("ok", false)):
					_present_events(ai_res.get("events", []))
					sync_from_state()
					dirty = true

	if dirty:
		queue_redraw()


func _is_ui_modal_blocking() -> bool:
	return _pause_open or _hotseat_cover >= 0 or intro_active() or (game_state != null and game_state.phase == "over") or not pay_pending.is_empty()


# ------------------------------------------------------------------------------
# UI Component Signal Handlers & Input Events
# ------------------------------------------------------------------------------
func _on_hand_card_clicked(hand_idx: int, _card_name: String) -> void:
	if _is_ui_modal_blocking():
		return
	select_or_play_hand_card(hand_idx, -2)


func _on_hand_card_right_clicked(hand_idx: int, _card_name: String) -> void:
	if _is_ui_modal_blocking():
		return
	begin_tune(hand_idx)


func _on_hand_card_drag_started(hand_idx: int, c_name: String, global_pos: Vector2) -> void:
	if _is_ui_modal_blocking() or is_mulligan_stage():
		return
	if not is_my_turn() or game_state.phase != "action" or not game_state.pending.is_empty():
		show_toast(explain_card_unplayable(c_name), TCGTheme.RED)
		return
	selected_hand_index = hand_idx
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
				show_toast("%s converted into a %s die" % [cname, me().get_active_char().get_defn().element], TCGTheme.GOLD_L)
			return
		begin_tune(hand_idx)
		return

	# 2. Dropped back onto the hand region (`y > 520`) -> cancel drag
	if local_pos.y > 520.0:
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


func _on_char_slot_clicked(p_side: int, p_idx: int) -> void:
	if _is_ui_modal_blocking():
		return

	# 1. If a hand card is currently selected for targeting, apply it to own character
	if selected_hand_index >= 0 and game_state.phase == "action" and p_side == 0 and is_my_turn():
		select_or_play_hand_card(selected_hand_index, p_idx)
		return

	# 2. Click 1 = inspect details (for both own & opponent chars); Click 2 = act/switch (or close opponent inspect)
	var already_inspected: bool = (
		String(_inspected.get("kind", "")) == "char"
		and int(_inspected.get("side", -1)) == p_side
		and int(_inspected.get("index", -1)) == p_idx
	)
	if not already_inspected:
		selected_hand_index = -1
		_inspect_extra_open = false
		_inspected = {"kind": "char", "side": p_side, "index": p_idx}
		sync_from_state()
		return

	_inspected.clear()
	if p_side != 0:
		sync_from_state()
		return

	if not is_my_turn():
		show_toast("Wait for your turn", TCGTheme.RED)
		sync_from_state()
		return

	# 3. Forced active character choice (`pending`) or Setup active character selection
	if not game_state.pending.is_empty() or (game_state.phase == "setup" and me().mull_done):
		for a in legal_actions:
			if a.player == view_player and a.type == "choose_active" and a.index == p_idx:
				execute_action(a)
				return
		show_toast("Cannot select that character as active", TCGTheme.RED)
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

	# Click 1 = inspect skill details & select; Click 2 on same skill = automatically try to use
	var already_inspected: bool = (
		String(_inspected.get("kind", "")) == "skill"
		and int(_inspected.get("index", -1)) == skill_idx
	)
	if not already_inspected:
		selected_hand_index = -1
		_inspect_extra_open = false
		_inspected = {"kind": "skill", "index": skill_idx}
		sync_from_state()
		return

	_inspected.clear()
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

	if sk.cost.energy > 0 and ch.energy < sk.cost.energy:
		show_toast("Not enough Energy for %s (%d/%d)" % [sk.name, ch.energy, sk.cost.energy], TCGTheme.RED)
	else:
		show_toast("Not enough matching dice for %s" % sk.name, TCGTheme.RED)
	sync_from_state()


func _on_tray_die_clicked(die_idx: int) -> void:
	if _is_ui_modal_blocking():
		return
	if is_my_turn() and game_state.phase == "roll":
		if roll_selected_dice.has(die_idx):
			roll_selected_dice.erase(die_idx)
		else:
			roll_selected_dice.append(die_idx)
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
				show_toast("%s converted into a %s die" % [cname, me().get_active_char().get_defn().element], TCGTheme.GOLD_L)
		else:
			show_toast("Matching and Omni dice cannot be converted", TCGTheme.RED)


func _end_phase_rect() -> Rect2:
	return Rect2(32, 344, 84, 84)


func _pause_btn_rect() -> Rect2:
	return Rect2(1218, 12, 48, 48)


func _pause_option_rect(idx: int) -> Rect2:
	return Rect2(490, 260 + idx * 58, 300, 44)


func _game_over_rect(idx: int) -> Rect2:
	return Rect2(420 + idx * 230, 412, 210, 46)


func _mulligan_confirm_rect() -> Rect2:
	return Rect2(530, 500, 220, 46)


func _roll_confirm_rect() -> Rect2:
	return Rect2(1040, 514, 152, 36)


func _pay_die_rect(idx: int) -> Rect2:
	var col: int = idx % 2
	var row: int = idx / 2
	var cx: float = 890.0 + float(col) * 218.0
	var cy: float = 248.0 + float(row) * 70.0
	return Rect2(cx - 50.0, cy - 32.0, 100.0, 64.0)


func _pay_cancel_rect() -> Rect2:
	return Rect2(786, 536, 210, 48)


func _pay_confirm_rect() -> Rect2:
	return Rect2(1018, 536, 210, 48)


func _card_detail_btn_rect() -> Rect2:
	return Rect2(34, 464, 182, 28)


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
			if not drag_state.is_empty():
				drag_state.clear()
				sync_from_state()
			elif not pay_pending.is_empty():
				cancel_payment_modal()
			elif selected_hand_index >= 0 or not _inspected.is_empty():
				selected_hand_index = -1
				_inspected.clear()
				_inspect_extra_open = false
				sync_from_state()
			else:
				_pause_open = not _pause_open
				queue_redraw()
		KEY_ENTER, KEY_KP_ENTER:
			if _pause_open:
				return
			if not pay_pending.is_empty():
				confirm_payment_modal()
			elif is_mulligan_stage():
				_confirm_mulligan()
			elif is_my_turn() and game_state != null and game_state.phase == "roll":
				_confirm_roll_phase()
		KEY_E:
			if not _pause_open and is_my_turn() and game_state.phase == "action" and game_state.pending.is_empty() and pay_pending.is_empty():
				execute_action(TCGGameState.ActionData.new("end_round", view_player))
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
				game_speed = 2.0 if is_equal_approx(game_speed, 1.0) else 1.0
				show_toast("Game speed x%d" % int(game_speed), TCGTheme.GOLD)
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
		var prev_ab := _action_btn_hovered
		var prev_pi := _pause_hover_idx
		var prev_oi := _over_hover_idx
		var prev_pa := _pause_hovered
		var prev_ib := _inspect_btn_hovered
		_pause_hovered = _pause_btn_rect().has_point(pos)
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
		if prev_ab != _action_btn_hovered or prev_pi != _pause_hover_idx or prev_oi != _over_hover_idx or prev_pa != _pause_hovered or prev_ib != _inspect_btn_hovered:
			queue_redraw()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var b_ev := (make_input_local(event) if is_inside_tree() else event) as InputEventMouseButton
		if b_ev == null:
			return
		var pos: Vector2 = b_ev.position
		var vp := get_viewport()

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

		if _pause_btn_rect().has_point(pos):
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

		if is_mulligan_stage() and _mulligan_confirm_rect().has_point(pos):
			_confirm_mulligan()
			if vp != null:
				vp.set_input_as_handled()
			return

		if is_my_turn() and game_state != null and game_state.phase == "roll" and _roll_confirm_rect().has_point(pos):
			_confirm_roll_phase()
			if vp != null:
				vp.set_input_as_handled()
			return

		if selected_hand_index >= 0 and pay_pending.is_empty() and _card_detail_btn_rect().has_point(pos):
			_inspect_extra_open = not _inspect_extra_open
			queue_redraw()
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

			# 5. End Round Hourglass Button
			if _end_phase_rect().has_point(event.position):
				if is_my_turn() and game_state.phase == "action" and game_state.pending.is_empty():
					execute_action(TCGGameState.ActionData.new("end_round", view_player))
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


func _on_zone_unit_clicked(p_side: int, is_summon: bool, slot_idx: int, u: TCGPlayerSystem.UnitInstance) -> void:
	if _is_ui_modal_blocking() or u == null:
		return
	var same: bool = (
		String(_inspected.get("kind", "")) == "zone"
		and int(_inspected.get("side", -1)) == p_side
		and bool(_inspected.get("is_summon", false)) == is_summon
		and int(_inspected.get("slot", -1)) == slot_idx
	)
	selected_hand_index = -1
	_inspect_extra_open = false
	if same:
		_inspected.clear()
	else:
		_inspected = {"kind": "zone", "side": p_side, "is_summon": is_summon, "slot": slot_idx, "unit": u}
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
	else:
		_inspected = {"kind": "status", "payload": payload}
	sync_from_state()


func _on_zone_unit_hovered(p_side: int, is_summon: bool, slot_idx: int, u: TCGPlayerSystem.UnitInstance, is_hovering: bool) -> void:
	if is_hovering and u != null:
		_hovered_zone_info = {"side": p_side, "is_summon": is_summon, "slot": slot_idx, "unit": u}
	else:
		_hovered_zone_info.clear()
	queue_redraw()


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
	var w: float = maxf(size.x, float(TCGTheme.W))
	var h: float = maxf(size.y, float(TCGTheme.H))

	# 1. Dueling Mat Background
	TCGArt.draw_mat(self, Vector2(w, h))

	if game_state == null:
		return

	var p_own: TCGPlayerSystem.PlayerState = game_state.players[view_player]
	var p_foe: TCGPlayerSystem.PlayerState = game_state.players[1 - view_player]

	# Highlight mat border if dragging an untargeted card
	var active_card_idx: int = int(drag_state.get("hand_index", selected_hand_index))
	if active_card_idx >= 0 and active_card_idx < p_own.hand.size() and game_state.phase == "action":
		for a in get_card_actions_for_hand_index(active_card_idx):
			if a.target == -1:
				TCGTheme.draw_rounded_box(
					self,
					Rect2(180, 66, w - 360, h - 132),
					Color(0, 0, 0, 0),
					TCGTheme.GOLD_L,
					14,
					3
				)
				break

	# 2. Deck Card-Back Piles (left side) + Card Counts
	_draw_deck_pile(Rect2(38, 92, 58, 78), p_foe.deck.size(), "FOE DECK")
	_draw_deck_pile(Rect2(38, 488, 58, 78), p_own.deck.size(), "DECK")

	# 3. Opponent Hand Fan (top-right of center banner)
	_draw_opponent_hand_fan(p_foe.hand)

	# 4. Top-Center Round / Phase / Turn Indicator Banner
	_draw_top_phase_banner()

	# 5. Combat Status Ribbons below/above character rows
	_draw_combat_status_ribbon(1, Vector2(640, FOE_Y + CH + 14.0), p_foe.combat)
	_draw_combat_status_ribbon(0, Vector2(640, OWN_Y - 14.0), p_own.combat)

	# 6. Left-Side "END ROUND" Hourglass Medallion Button
	_draw_end_phase_button()

	# 7. Top-Right Pause Gear Button
	_draw_pause_button()

	if _overlay_canvas != null:
		_overlay_canvas.queue_redraw()


func _draw_top_overlays() -> void:
	if game_state == null or _overlay_canvas == null:
		return
	var c: CanvasItem = _overlay_canvas
	var w: float = maxf(size.x, float(TCGTheme.W))
	var h: float = maxf(size.y, float(TCGTheme.H))

	# Burst flash radial vignette + expanding shockwave ring
	if _burst_flash_alpha > 0.001:
		var b_norm: float = clampf(_burst_flash_alpha / 0.65, 0.0, 1.0)
		c.draw_rect(Rect2(0, 0, w, h), Color(1.0, 0.95, 0.72, b_norm * 0.30))
		var ring_r: float = (1.0 - b_norm) * 440.0 + 60.0
		c.draw_arc(Vector2(w * 0.5, h * 0.5), ring_r, 0.0, TAU, 48, Color(1.0, 0.88, 0.48, b_norm * 0.65), 4.0)

	# 8. Phase-Specific Prompts (Setup Mulligan, Choose Active Character, Roll Phase)
	_draw_phase_prompts(c, w, h)

	# 9. Flying Card Animations & Damage/Reaction Floaters
	_draw_fx_layer(c)

	# 10. Dragged Card Follower
	if not drag_state.is_empty():
		_draw_dragged_card(c)

	# 11. Hover Inspector Panel (Cards, Characters, Skills, Summons, Supports, Statuses)
	if pay_pending.is_empty() and drag_state.is_empty() and not _pause_open and _hotseat_cover < 0 and not intro_active() and game_state.phase != "over":
		_draw_inspect_tooltip(c)

	# 12. Action Payment / Elemental Tuning Modal (`draw_payment_select` port)
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

	# 16. Match Over Overlay (`draw_over` port)
	if game_state.phase == "over":
		_draw_game_over_overlay(c, w, h)

	# 17. Pause Modal Overlay
	if _pause_open:
		_draw_pause_modal(c, w, h)


func _draw_deck_pile(r: Rect2, count: int, label: String) -> void:
	if count > 1:
		TCGArt.draw_card_back(self, Rect2(r.position.x + 3, r.position.y + 3, r.size.x, r.size.y))
	TCGArt.draw_card_back(self, r)
	var badge_c := Vector2(r.end.x - 4, r.end.y - 6)
	draw_circle(badge_c, 12.0, TCGTheme.PANEL2)
	draw_arc(badge_c, 12.0, 0.0, TAU, 18, TCGTheme.GOLD_L, 2.0)
	TCGTheme.draw_text_centered(self, str(count), badge_c, 12, TCGTheme.GOLD_L, true, true)
	TCGTheme.draw_text_centered(self, label, Vector2(r.get_center().x, r.end.y + 11.0), 9, TCGTheme.DIM, true, true)


func _draw_opponent_hand_fan(foe_hand: Array[String]) -> void:
	var n_cards: int = foe_hand.size()
	if n_cards <= 0:
		return
	var cw: float = 44.0
	var ch: float = 62.0
	var step: float = minf(28.0, 140.0 / float(maxi(1, n_cards)))
	var total_w: float = cw + step * float(n_cards - 1)
	var x0: float = 890.0 - total_w * 0.5
	for i in range(n_cards):
		var r := Rect2(x0 + float(i) * step, 4.0, cw, ch)
		if reveal_opponent_hand:
			TCGActionCardView.draw_card_surface(self, r, foe_hand[i], false, false, true, false, false, false)
		else:
			TCGArt.draw_card_back(self, r)


func _draw_top_phase_banner() -> void:
	var banner := Rect2(470, 10, 320, 44)
	TCGTheme.draw_gold_frame(self, banner, Color(0.07, 0.12, 0.19, 0.92), 12, false)

	var phase_str: String = "MATCH OVER" if game_state.phase == "over" else (game_state.phase.to_upper() + " PHASE")
	var round_txt := "ROUND %d  ·  %s" % [game_state.round_number, phase_str]
	TCGTheme.draw_text_centered(self, round_txt, Vector2(banner.get_center().x, banner.position.y + 14.0), 14, TCGTheme.GOLD_L, true, true)

	var act_idx: int = maxi(0, actor())
	var act_p: TCGPlayerSystem.PlayerState = game_state.players[act_idx]
	var act_ch := act_p.get_active_char()
	var ch_name := act_ch.name if act_ch != null else "Choosing…"
	var turn_col := TCGTheme.GREEN if act_idx == view_player else TCGTheme.GOLD
	var sub_txt := "Active Turn: %s (%s)" % [player_labels[act_idx], ch_name]
	TCGTheme.draw_text_centered(self, sub_txt, Vector2(banner.get_center().x, banner.position.y + 32.0), 11, turn_col, true, true)


func _draw_combat_status_ribbon(_side: int, center: Vector2, statuses: Array) -> void:
	if statuses.is_empty():
		return
	var total_w: float = float(statuses.size()) * 116.0
	var x0: float = center.x - total_w * 0.5
	for i in range(statuses.size()):
		var st: TCGPlayerSystem.StatusInstance = statuses[i]
		var pill := Rect2(x0 + float(i) * 116.0, center.y - 10.0, 110.0, 20.0)
		TCGTheme.draw_rounded_box(self, pill, Color(0.1, 0.16, 0.24, 0.9), TCGTheme.GOLD, 10, 1)
		var count_val: int = st.shield if st.shield > 0 else maxi(0, st.usages)
		var txt := "%s (%d)" % [st.name, count_val]
		if txt.length() > 16:
			txt = st.name.substr(0, 11) + "…(" + str(count_val) + ")"
		TCGTheme.draw_text_centered(self, txt, pill.get_center(), 10, TCGTheme.GOLD_L, true, true)


func _draw_end_phase_button() -> void:
	var r := _end_phase_rect()
	var c := r.get_center()
	var can_act: bool = (is_my_turn() and game_state.phase == "action" and game_state.pending.is_empty())
	var rad: float = r.size.x * 0.5
	var fill := Color8(36, 58, 82) if can_act else Color8(24, 32, 44)
	if _end_phase_hovered and can_act:
		fill = Color8(52, 82, 112)
	var border := TCGTheme.GOLD_L if (_end_phase_hovered or can_act) else TCGTheme.GOLD_D

	draw_circle(c + Vector2(0, 3), rad, Color(0, 0, 0, 0.45))
	draw_circle(c, rad, fill)
	draw_arc(c, rad, 0.0, TAU, 32, border, 3.0)
	draw_arc(c, rad - 5.0, 0.0, TAU, 28, TCGTheme.GOLD_D, 1.0)

	var hg_pts_top := PackedVector2Array([
		Vector2(c.x - 10, c.y - 22),
		Vector2(c.x + 10, c.y - 22),
		Vector2(c.x, c.y - 10),
	])
	var hg_pts_bot := PackedVector2Array([
		Vector2(c.x, c.y - 10),
		Vector2(c.x + 10, c.y + 2),
		Vector2(c.x - 10, c.y + 2),
	])
	draw_colored_polygon(hg_pts_top, TCGTheme.GOLD_L if can_act else TCGTheme.DIM)
	draw_colored_polygon(hg_pts_bot, TCGTheme.GOLD if can_act else TCGTheme.DIM)

	TCGTheme.draw_text_centered(self, "END", Vector2(c.x, c.y + 13.0), 12, TCGTheme.GOLD_L if can_act else TCGTheme.DIM, true, true)
	TCGTheme.draw_text_centered(self, "ROUND", Vector2(c.x, c.y + 26.0), 10, TCGTheme.TEXT if can_act else TCGTheme.DIM, true, true)


func _draw_pause_button() -> void:
	var r := _pause_btn_rect()
	var border := TCGTheme.GOLD_L if _pause_hovered else TCGTheme.GOLD
	TCGTheme.draw_rounded_box(self, r, TCGTheme.PANEL2, border, 12, 2, Vector2(0, 2), 80)
	var c := r.get_center()
	draw_arc(c, 10.0, 0.0, TAU, 16, border, 2.0)
	draw_circle(c, 4.0, border)
	for k in range(8):
		var a: float = float(k) * PI / 4.0
		var p1 := Vector2(c.x + cos(a) * 10.0, c.y + sin(a) * 10.0)
		var p2 := Vector2(c.x + cos(a) * 14.0, c.y + sin(a) * 14.0)
		draw_line(p1, p2, border, 2.0)


func _draw_phase_prompts(c: CanvasItem, w: float, _h: float) -> void:
	if intro_active():
		return
	var p := me()
	# 1. Mulligan overlay banner & confirm button (`ui/match.py:661-670`)
	if is_mulligan_stage():
		var header_box := Rect2(w * 0.5 - 230.0, 140.0, 460.0, 74.0)
		TCGTheme.draw_gold_frame(c, header_box, Color(0.05, 0.09, 0.15, 0.94), 12, true)
		TCGTheme.draw_text_centered(c, "STARTING HAND MULLIGAN", Vector2(w * 0.5, 164.0), 20, TCGTheme.GOLD_L, true, true)
		TCGTheme.draw_text_centered(c, "Click cards to mark SWAP, then confirm", Vector2(w * 0.5, 192.0), 13, TCGTheme.DIM, false, true)
		var n_sel: int = mulligan_swap_indices.size()
		TCGTheme.draw_plaque(
			c,
			_mulligan_confirm_rect(),
			"Confirm  ·  %d selected" % n_sel,
			TCGTheme.GOLD,
			_action_btn_hovered
		)
		return

	# 2. Choose Active Character ribbon (`ui/match.py:934-945`)
	if not game_state.pending.is_empty() or (game_state.phase == "setup" and p.mull_done and is_my_turn()):
		var band := Rect2(320, 326, 640, 44)
		TCGTheme.draw_gold_frame(c, band, Color(0.18, 0.13, 0.10, 0.92), 10, true)
		var msg := "Choose your active character (click one of your characters)" if is_my_turn() else ("%s is choosing an active character…" % _who(actor()))
		TCGTheme.draw_text_centered(c, msg, band.get_center(), 16, TCGTheme.GOLD_L, true, true)
		return

	if game_state.phase == "setup" and not is_my_turn() and actor() >= 0:
		var band := Rect2(360, 328, 560, 40)
		TCGTheme.draw_rounded_box(c, band, Color(0.08, 0.13, 0.20, 0.88), TCGTheme.GOLD_D, 10, 1)
		TCGTheme.draw_text_centered(c, "%s is preparing opening setup…" % _who(actor()), band.get_center(), 14, TCGTheme.GOLD_L, true, true)
		return

	# 3. Roll Phase reroll prompt (`ui/match.py:966-969`)
	if is_my_turn() and game_state.phase == "roll":
		var n_reroll: int = roll_selected_dice.size()
		var lbl := "Confirm Roll" if (n_reroll == 0 or p.rerolls <= 0) else ("Reroll %d + Go" % n_reroll)
		TCGTheme.draw_plaque(c, _roll_confirm_rect(), lbl, TCGTheme.GREEN, _action_btn_hovered, false, true)
		TCGTheme.draw_text_centered(
			c,
			"Rerolls left: %d (click dice on right tray)" % p.rerolls,
			Vector2(_roll_confirm_rect().get_center().x, _roll_confirm_rect().end.y + 14.0),
			11,
			TCGTheme.GOLD_L,
			true,
			true
		)

	# 4. Selected hand card target instruction banner
	if selected_hand_index >= 0 and selected_hand_index < p.hand.size() and pay_pending.is_empty() and drag_state.is_empty():
		var cname: String = p.hand[selected_hand_index]
		var band := Rect2(360, 328, 560, 38)
		TCGTheme.draw_rounded_box(c, band, Color(0.08, 0.14, 0.22, 0.92), TCGTheme.GOLD_L, 10, 2)
		TCGTheme.draw_text_centered(
			c,
			"Playing %s — click a highlighted target, [T] to Tune, or [Esc]/Right-Click to cancel" % cname,
			band.get_center(),
			12,
			TCGTheme.GOLD_L,
			true,
			true
		)


func _draw_dragged_card(c: CanvasItem) -> void:
	var c_name: String = String(drag_state.get("card_name", ""))
	var pos: Vector2 = drag_state.get("pos", Vector2(640, 360))
	var r := Rect2(pos.x - 64.0, pos.y - 90.0, 128.0, 180.0)
	TCGTheme.draw_rounded_box(c, r.grow(6.0), Color(0.95, 0.80, 0.42, 0.16), Color(0.95, 0.82, 0.45, 0.55), 14, 2, Vector2(0, 8), 90)
	TCGActionCardView.draw_card_surface(c, r, c_name, true, true, true, false, false, false)


func _draw_fx_layer(c: CanvasItem) -> void:
	# Flying cards with cubic ease-out, scale pop, and golden aura
	for fc in _flying_cards:
		var u: float = clampf(float(fc["t"]) / maxf(0.01, float(fc["dur"])), 0.0, 1.0)
		var ease_u: float = 1.0 - pow(1.0 - u, 3.0)
		var p_cur: Vector2 = (fc["from"] as Vector2).lerp(fc["to"] as Vector2, ease_u)
		var sc: float = 0.72 + 0.40 * sin(minf(u * 1.4, 1.0) * PI * 0.5)
		if u > 0.75:
			sc = lerpf(1.12, 0.92, (u - 0.75) / 0.25)
		var cw: float = 118.0 * sc
		var ch: float = 168.0 * sc
		var r := Rect2(p_cur.x - cw * 0.5, p_cur.y - ch * 0.5, cw, ch)
		var glow_a: float = 0.38 * (1.0 - maxf(0.0, (u - 0.7) / 0.3))
		TCGTheme.draw_rounded_box(c, r.grow(8.0), Color(0.95, 0.80, 0.42, glow_a * 0.4), Color(0.95, 0.82, 0.45, glow_a), 14, 2)
		TCGActionCardView.draw_card_surface(c, r, String(fc["card_name"]), true, false, true, false, false, false)

	# Phase announcement banners
	for b in _banners:
		var u: float = float(b["t"]) / maxf(0.01, float(b["dur"]))
		var alpha: float = 1.0 if u < 0.72 else maxf(0.0, (1.0 - u) / 0.28)
		TCGTheme.draw_phase_announcement(c, String(b["title"]), String(b["sub"]), b["color"] as Color, float(b["y"]), alpha)

	# Action ribbons (skill/burst/switch/defeat announcements)
	for r in _ribbons:
		var t_cur: float = float(r["t"])
		var dur: float = float(r["dur"])
		var alpha: float = 1.0 if t_cur < dur - 0.3 else maxf(0.0, (dur - t_cur) / 0.3)
		var slide: float = 1.0 - pow(1.0 - clampf(t_cur / 0.25, 0.0, 1.0), 2.0)
		var y_off: float = (1.0 - slide) * (-30.0 if not bool(r["mine"]) else 30.0)
		var pos: Vector2 = (r["pos"] as Vector2) + Vector2(0.0, y_off)
		TCGTheme.draw_action_ribbon(c, String(r["title"]), String(r["sub"]), r["accent"] as Color, pos, alpha)

	# Reaction Pills (Genshin-style elemental reactions)
	for p in _reaction_pills:
		var t_cur: float = float(p["t"])
		var dur: float = float(p["dur"])
		var alpha: float = minf(1.0, t_cur / 0.2) * (1.0 if t_cur < dur - 0.4 else maxf(0.0, (dur - t_cur) / 0.4))
		var float_y: float = (p["pos"] as Vector2).y - 18.0 * (1.0 - pow(1.0 - clampf(t_cur / 0.4, 0.0, 1.0), 2.0))
		var cur_pos := Vector2((p["pos"] as Vector2).x, float_y)
		TCGTheme.draw_reaction_pill(c, String(p["title"]), String(p["sub"]), p["elements"] as Array, cur_pos, alpha)

	# Damage / Heal Floaters with scale pop and shadow
	for fl in _floaters:
		var pos: Vector2 = fl["pos"]
		var col: Color = fl["col"]
		var ttl: float = float(fl["ttl"])
		var max_ttl: float = float(fl.get("max_ttl", 1.4))
		var elapsed: float = max_ttl - ttl
		var pop: float = 1.0 + 0.35 * maxf(0.0, 1.0 - elapsed / 0.15)
		var alpha: float = 1.0 if elapsed < max_ttl * 0.65 else maxf(0.0, ttl / (max_ttl * 0.35))
		var text_col := Color(col.r, col.g, col.b, alpha)
		var shadow_col := Color(0.04, 0.02, 0.01, alpha * 0.85)
		TCGTheme.draw_text_centered(c, String(fl["text"]), pos + Vector2(2, 2), int(22.0 * pop), shadow_col, true, false)
		TCGTheme.draw_text_centered(c, String(fl["text"]), pos, int(22.0 * pop), text_col, true, false)


func _draw_payment_modal(c: CanvasItem, w: float, h: float) -> void:
	c.draw_rect(Rect2(0, 0, w, h), Color(0.02, 0.04, 0.07, 0.76))

	var left := Rect2(28, 138, 390, 456)
	var right := Rect2(752, 138, 500, 456)
	TCGTheme.draw_gold_frame(c, left, Color(0.07, 0.11, 0.16, 0.98), 16, true)
	TCGTheme.draw_gold_frame(c, right, Color(0.07, 0.11, 0.16, 0.98), 16, true)

	var is_tune: bool = bool(pay_pending.get("tune", false))
	var title: String = String(pay_pending.get("title", "Action"))
	var detail: String = String(pay_pending.get("detail", ""))
	var sel_dice: Array = pay_pending.get("selected_dice", []).duplicate()
	sel_dice.sort()

	TCGTheme.draw_text_pos(c, "ELEMENTAL TUNING" if is_tune else "ACTION PAYMENT", Vector2(left.position.x + 22, left.position.y + 18), 16, TCGTheme.GOLD_L, true, true)
	TCGTheme.draw_text_pos(c, title, Vector2(left.position.x + 22, left.position.y + 56), 20, TCGTheme.TEXT, true, true)
	c.draw_line(Vector2(left.position.x + 20, left.position.y + 92), Vector2(left.end.x - 20, left.position.y + 92), TCGTheme.GOLD_D, 1.0)

	var valid: bool = false
	var total_needed: int = 1
	var p := me()

	if is_tune:
		var elig := tunable_dice(view_player)
		valid = (sel_dice.size() == 1 and elig.has(int(sel_dice[0])))
		TCGTheme.draw_text_pos(c, "Choose 1 die to convert into %s." % p.get_active_char().get_defn().element, Vector2(left.position.x + 22, left.position.y + 114), 14, TCGTheme.TEXT, true, false)
		TCGTheme.draw_text_pos(c, "Matching and Omni dice cannot be converted.", Vector2(left.position.x + 22, left.position.y + 142), 12, TCGTheme.DIM, false, false)
		TCGTheme.draw_wrapped(c, detail, Rect2(left.position.x + 22, left.position.y + 180, left.size.x - 44, 180), 13, TCGTheme.TEXT, 18, false)
	else:
		var cost: CardDataSystem.CostData = pay_pending["cost"]
		total_needed = cost.n + cost.unaligned
		valid = TCGDiceSystem.payment_ok(p.dice, cost, sel_dice)
		TCGTheme.draw_text_pos(c, "REQUIRED COST", Vector2(left.position.x + 22, left.position.y + 108), 13, TCGTheme.GOLD_L, true, false)
		var pairs := TCGActionCardView.cost_to_pairs(cost)
		var gx: float = left.position.x + 36.0
		for pair in pairs:
			TCGArt.draw_cost_gem(c, String(pair[0]), int(pair[1]), Vector2(gx, left.position.y + 148), 13.0)
			gx += 34.0
		var align_txt := "%d %s / Omni  +  %d Any" % [
			cost.n,
			cost.element if not cost.element.is_empty() else "Same Element",
			cost.unaligned
		]
		TCGTheme.draw_text_pos(c, align_txt, Vector2(left.position.x + 22, left.position.y + 178), 13, TCGTheme.TEAL, true, false)
		TCGTheme.draw_wrapped(c, detail, Rect2(left.position.x + 22, left.position.y + 212, left.size.x - 44, 210), 13, TCGTheme.TEXT, 18, false)

	var status_msg: String = ""
	var status_col: Color = TCGTheme.GOLD_L
	if valid:
		status_msg = "READY — click Confirm or press Enter"
		status_col = TCGTheme.GREEN
	elif sel_dice.size() < total_needed:
		status_msg = "Select %d more die/dice" % (total_needed - sel_dice.size())
	else:
		status_msg = "Selected combination does not match cost"
		status_col = TCGTheme.RED
	TCGTheme.draw_text_pos(c, status_msg, Vector2(left.position.x + 22, left.end.y - 38), 14, status_col, true, true)

	# Right box: interactive dice grid
	TCGTheme.draw_text_pos(c, "SELECT DICE TO SPEND", Vector2(right.position.x + 22, right.position.y + 18), 17, TCGTheme.GOLD_L, true, true)
	TCGTheme.draw_text_pos(c, "Click each die to toggle selection", Vector2(right.position.x + 22, right.position.y + 46), 13, TCGTheme.DIM, false, false)

	var elig_tune := tunable_dice(view_player)
	for i in range(p.dice.size()):
		var face: String = p.dice[i]
		var tile := _pay_die_rect(i)
		var chosen: bool = sel_dice.has(i)
		var eligible: bool = true
		if is_tune:
			eligible = elig_tune.has(i)
		else:
			var cost: CardDataSystem.CostData = pay_pending["cost"]
			eligible = (face == CardDataSystem.OMNI or face == cost.element or cost.element.is_empty() or cost.unaligned > 0)

		var fill := Color8(83, 66, 38) if chosen else (Color8(38, 52, 68) if eligible else Color8(24, 30, 38))
		var edge := TCGTheme.GOLD_L if (chosen or _pay_die_hovered == i) else (TCGTheme.GOLD if eligible else TCGTheme.DIM)
		TCGTheme.draw_rounded_box(c, tile, fill, edge, 12, 3 if chosen else 1)

		var die_box := Rect2(tile.get_center().x - 20, tile.get_center().y - 22, 40, 38)
		TCGArt.draw_die(c, face, die_box, chosen, _pay_die_hovered == i)
		var tag := "SELECTED" if chosen else ("ELIGIBLE" if eligible else "OTHER")
		TCGTheme.draw_text_centered(c, tag, Vector2(tile.get_center().x, tile.end.y - 9.0), 9, TCGTheme.GOLD_L if chosen else TCGTheme.DIM, true, false)

	TCGTheme.draw_plaque(c, _pay_cancel_rect(), "Cancel [Esc]", TCGTheme.RED, _pay_btn_hovered == 0)
	TCGTheme.draw_plaque(c, _pay_confirm_rect(), "Confirm [Enter]", TCGTheme.GREEN, _pay_btn_hovered == 1, not valid)


func _draw_inspect_tooltip(c: CanvasItem) -> void:
	# Strictly click-driven inspector: hovering never opens description popups.
	var ikind: String = String(_inspected.get("kind", ""))

	# 1. Clicked Skill button (1st click = inspect, 2nd click = try to use)
	if ikind == "skill":
		var s_idx: int = int(_inspected.get("index", -1))
		var c0: TCGPlayerSystem.CharacterInstance = me().get_active_char()
		if c0 != null and s_idx >= 0:
			var skills: Array[CardDataSystem.SkillData] = c0.get_defn().skills
			if s_idx < skills.size():
				var sk: CardDataSystem.SkillData = skills[s_idx]
				var box := Rect2(860, 404, 320, 134)
				TCGTheme.draw_gold_frame(c, box, Color(0.06, 0.1, 0.16, 0.97), 10, true)
				TCGTheme.draw_text_pos(c, sk.name + "  [" + sk.kind.to_upper() + "]", Vector2(box.position.x + 12, box.position.y + 8), 13, TCGTheme.GOLD_L, true, true)
				var pairs := TCGActionCardView.cost_to_pairs(sk.cost)
				var gx: float = box.position.x + 22.0
				for pair in pairs:
					TCGArt.draw_cost_gem(c, String(pair[0]), int(pair[1]), Vector2(gx, box.position.y + 38), 9.5)
					gx += 24.0
				TCGTheme.draw_wrapped(c, sk.desc, Rect2(box.position.x + 12, box.position.y + 54, box.size.x - 24, 56), 11, TCGTheme.TEXT, 15, true)
				TCGTheme.draw_text_pos(c, "Click skill again to use", Vector2(box.position.x + 12, box.end.y - 18), 10, TCGTheme.GOLD, true, false)
				return

	# 2. Clicked Hand Card (1st click = preview card + optional Details toggle, 2nd click = try to play)
	if selected_hand_index >= 0 and selected_hand_index < me().hand.size():
		var cd: CardDataSystem.CardData = CardDataSystem.get_card_def(me().hand[selected_hand_index])
		if cd != null:
			var large_r := Rect2(20, 148, 210, 308)
			TCGActionCardView.draw_card_surface(c, large_r, cd.name, true, false, true, true, false, false)
			var dbtn := _card_detail_btn_rect()
			var d_lbl := "Hide Details ▾" if _inspect_extra_open else "Details ▸"
			TCGTheme.draw_plaque(c, dbtn, d_lbl, TCGTheme.GOLD, _inspect_btn_hovered, false, false)
			if _inspect_extra_open:
				var panel := Rect2(238, 148, 260, 260)
				TCGTheme.draw_gold_frame(c, panel, Color(0.06, 0.1, 0.16, 0.97), 12, true)
				TCGTheme.draw_text_pos(c, cd.name, Vector2(panel.position.x + 14, panel.position.y + 12), 15, TCGTheme.GOLD_L, true, true)
				var sub := cd.kind.to_upper()
				if not cd.weapon.is_empty():
					sub += " · " + cd.weapon.to_upper()
				elif not cd.char_name.is_empty():
					sub += " · " + cd.char_name.to_upper()
				elif not cd.resonance.is_empty():
					sub += " · " + cd.resonance.to_upper()
				TCGTheme.draw_text_pos(c, sub, Vector2(panel.position.x + 14, panel.position.y + 34), 11, TCGTheme.TEAL, true, false)
				c.draw_line(Vector2(panel.position.x + 12, panel.position.y + 56), Vector2(panel.end.x - 12, panel.position.y + 56), TCGTheme.GOLD_D, 1.0)
				TCGTheme.draw_wrapped(c, cd.text, Rect2(panel.position.x + 14, panel.position.y + 66, panel.size.x - 28, 140), 12, TCGTheme.TEXT, 16, false)
				var hint := "Click card again to play (or select target) · [Esc] to cancel."
				TCGTheme.draw_wrapped(c, hint, Rect2(panel.position.x + 14, panel.end.y - 44, panel.size.x - 28, 36), 10, TCGTheme.DIM, 14, false)
			return

	# 3. Clicked Support or Summon Tile
	if ikind == "zone" and _inspected.get("unit", null) != null:
		var u: TCGPlayerSystem.UnitInstance = _inspected["unit"]
		var is_sum: bool = bool(_inspected.get("is_summon", false))
		var box := Rect2(20, 210, 290, 170)
		TCGTheme.draw_gold_frame(c, box, Color(0.06, 0.1, 0.16, 0.97), 10, true)
		TCGTheme.draw_text_pos(c, u.name, Vector2(box.position.x + 12, box.position.y + 10), 15, TCGTheme.GOLD_L, true, true)
		if is_sum:
			var sdef := CardDataSystem.get_summon_def(u.name)
			var desc := "End Phase: Deal %d %s DMG to opposing active character.\nRemaining Usages: %d" % [
				sdef.damage if sdef != null else 1,
				sdef.element if sdef != null else "Elemental",
				u.usages
			]
			TCGTheme.draw_text_pos(c, "SUMMON", Vector2(box.position.x + 12, box.position.y + 32), 11, TCGTheme.TEAL, true, false)
			TCGTheme.draw_wrapped(c, desc, Rect2(box.position.x + 12, box.position.y + 52, box.size.x - 24, 108), 12, TCGTheme.TEXT, 16, false)
		else:
			var cdef := CardDataSystem.get_card_def(u.name)
			var desc := (cdef.text if cdef != null else "Support effect.") + ("\nRemaining Usages: %d" % u.usages if u.usages >= 0 else "")
			TCGTheme.draw_text_pos(c, "SUPPORT", Vector2(box.position.x + 12, box.position.y + 32), 11, TCGTheme.TEAL, true, false)
			TCGTheme.draw_wrapped(c, desc, Rect2(box.position.x + 12, box.position.y + 52, box.size.x - 24, 108), 12, TCGTheme.TEXT, 16, false)
		return

	# 4. Clicked Status / Aura / Equipment Icon on a Character
	if ikind == "status":
		var payload: Dictionary = _inspected.get("payload", {})
		var pkind: String = String(payload.get("kind", ""))
		var box := Rect2(20, 220, 300, 160)
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
				var box := Rect2(18, 120, 320, 420)
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


func _draw_toasts(c: CanvasItem, w: float) -> void:
	var y: float = 64.0
	for t in _toasts:
		var txt: String = String(t["text"])
		var col: Color = t["col"]
		var pill := Rect2(w * 0.5 - 240.0, y, 480.0, 28.0)
		TCGTheme.draw_rounded_box(c, pill, Color(0.05, 0.08, 0.13, 0.94), col, 14, 1)
		TCGTheme.draw_text_centered(c, txt, pill.get_center(), 12, col, true, true)
		y += 32.0


func _draw_game_over_overlay(c: CanvasItem, w: float, h: float) -> void:
	c.draw_rect(Rect2(0, 0, w, h), Color(0.02, 0.03, 0.05, 0.76))
	var win_p: int = game_state.winner
	var msg := "Draw"
	var col := TCGTheme.TEXT
	if win_p >= 0:
		if human_flags[view_player] and not hotseat:
			msg = "Victory!" if win_p == view_player else "Defeat"
			col = TCGTheme.GOLD_L if win_p == view_player else TCGTheme.RED
		else:
			msg = "%s Wins!" % player_labels[win_p]
			col = TCGTheme.GOLD_L
	TCGTheme.draw_text_centered(c, msg, Vector2(w * 0.5, 290.0), 56, col, true, true)
	TCGTheme.draw_text_centered(c, "Press [R] for Rematch   ·   Press [Esc] for Menu", Vector2(w * 0.5, 354.0), 17, TCGTheme.TEXT, false, true)
	TCGTheme.draw_plaque(c, _game_over_rect(0), "Rematch", TCGTheme.GREEN, _over_hover_idx == 0)
	TCGTheme.draw_plaque(c, _game_over_rect(1), "Main Menu", TCGTheme.GOLD, _over_hover_idx == 1)


func _draw_coin_intro(c: CanvasItem, w: float, h: float) -> void:
	c.draw_rect(Rect2(0, 0, w, h), Color(0.02, 0.03, 0.06, 0.72))
	var panel := Rect2(w * 0.5 - 230.0, h * 0.5 - 120.0, 460.0, 230.0)
	TCGTheme.draw_gold_frame(c, panel, TCGTheme.PANEL, 16, true)
	var cx: float = panel.get_center().x
	var cy: float = panel.position.y + 82.0
	var spinning: bool = _intro_t < 1.25
	var flip_scale: float = absf(cos(_intro_t * PI * 6.0)) if spinning else 1.0
	var rx: float = maxf(6.0, 38.0 * flip_scale)
	var pts := PackedVector2Array()
	for i in range(28):
		var ang: float = TAU * float(i) / 28.0
		pts.append(Vector2(cx + cos(ang) * rx, cy + sin(ang) * 38.0))
	var fp: int = game_state.first_player
	var coin_col := TCGTheme.GOLD_L if (fp == 0 or spinning) else TCGTheme.TEAL
	c.draw_colored_polygon(pts, coin_col)
	var rim := pts.duplicate()
	rim.append(pts[0])
	c.draw_polyline(rim, TCGTheme.GOLD, 3.0)
	if not spinning:
		TCGTheme.draw_text_centered(c, "I" if fp == 0 else "II", Vector2(cx, cy), 28, TCGTheme.PANEL2, true, false)
	var who_fp: String = _who(fp)
	var first_txt: String = "You go first!" if who_fp == "You" else ("%s goes first!" % who_fp)
	var title: String = "Flipping Coin…" if spinning else first_txt
	TCGTheme.draw_text_centered(c, title, Vector2(cx, panel.position.y + 150.0), 22, TCGTheme.GOLD_L, true, true)
	TCGTheme.draw_text_centered(c, "Click or press Space to continue" if not spinning else "Determining Turn Order", Vector2(cx, panel.position.y + 186.0), 13, TCGTheme.DIM, false, true)


func _draw_hotseat_cover(c: CanvasItem, w: float, h: float) -> void:
	c.draw_rect(Rect2(0, 0, w, h), Color(0.03, 0.05, 0.09, 0.94))
	var panel := Rect2(w * 0.5 - 240.0, h * 0.5 - 95.0, 480.0, 190.0)
	TCGTheme.draw_gold_frame(c, panel, TCGTheme.PANEL, 16, true)
	TCGTheme.draw_text_centered(c, "PASS DEVICE TO %s" % _who(_hotseat_cover).to_upper(), Vector2(panel.get_center().x, panel.position.y + 64.0), 22, TCGTheme.GOLD_L, true, true)
	TCGTheme.draw_text_centered(c, "Click anywhere or press Space / Enter to reveal your hand", Vector2(panel.get_center().x, panel.position.y + 114.0), 14, TCGTheme.TEXT, false, true)


func _draw_pause_modal(c: CanvasItem, w: float, h: float) -> void:
	c.draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.68))
	var modal := Rect2(440, 175, 400, 295)
	TCGTheme.draw_gold_frame(c, modal, TCGTheme.PANEL, 16, true)
	TCGTheme.draw_text_centered(c, "MATCH PAUSED", Vector2(modal.get_center().x, modal.position.y + 42.0), 24, TCGTheme.GOLD_L, true, true)
	TCGTheme.draw_plaque(c, _pause_option_rect(0), "Resume Match", TCGTheme.GREEN, _pause_hover_idx == 0)
	TCGTheme.draw_plaque(c, _pause_option_rect(1), "Return to Main Menu", TCGTheme.GOLD, _pause_hover_idx == 1)
	TCGTheme.draw_plaque(c, _pause_option_rect(2), "Quit Game", TCGTheme.RED, _pause_hover_idx == 2)

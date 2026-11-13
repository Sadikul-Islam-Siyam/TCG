class_name TCGDeckSelectScene
extends Control
## Stage 9: Pre-Match Deck Select Screen
## Direct port of PythonTCG/ui/decks.py (`DeckSelect`).
## Lets each player pick Random (CSP-built), a Preset Deck, or a Saved Deck,
## choose AI difficulty levels (`easy` / `normal` / `hard`), and launch the match.

signal back_requested()
signal builder_requested()
signal start_match_requested(mode_id: String, picks: Array, levels: Array)

const LEVELS: Array[String] = ["easy", "normal", "hard"]
const VISIBLE_ROWS: int = 9

var mode_id: String = "pve"
var entries: Array[Dictionary] = []  # {"name": String, "chars": Array[String], "cards": Array[String], "legal": bool, "is_random": bool}
var pick: Array[int] = [0, 0]
var scroll: Array[int] = [0, 0]
var levels: Array[String] = ["normal", "normal"]
var titles: Array[String] = ["Your deck", "AI opponent's deck"]
var msg: String = ""

var _hit_boxes: Array[Dictionary] = []  # {"rect": Rect2, "key": Variant, "enabled": bool}
var _hovered_key: Variant = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	setup_mode(mode_id)


func setup_mode(p_mode: String) -> void:
	mode_id = p_mode
	CardDataSystem.load_all_content()
	refresh_entries()
	pick = [0, 0]
	scroll = [0, 0]
	levels = ["normal", "normal"]
	msg = ""
	match mode_id:
		"pvp":
			titles = ["Player 1 deck", "Player 2 deck"]
		"ava":
			titles = ["AI 1 deck", "AI 2 deck"]
		_:
			titles = ["Your deck", "AI opponent's deck"]
	queue_redraw()


func refresh_entries() -> void:
	entries.clear()
	entries.append({
		"name": "Random deck (built by the AI)",
		"chars": [],
		"cards": [],
		"legal": true,
		"is_random": true,
	})
	var presets: Dictionary = TCGDeckSystem.preset_decks()
	var preset_names: Array = presets.keys()
	preset_names.sort()
	for pn in preset_names:
		var pair: Array = presets[pn]
		var ch_arr: Array[String] = []
		for c in pair[0]:
			ch_arr.append(str(c))
		var cd_arr: Array[String] = []
		for card in pair[1]:
			cd_arr.append(str(card))
		entries.append({
			"name": "%s  (preset)" % str(pn),
			"chars": ch_arr,
			"cards": cd_arr,
			"legal": true,
			"is_random": false,
		})
	for d in TCGDeckStore.list_decks():
		var ok: bool = bool(d["legal"])
		entries.append({
			"name": "%s%s" % [str(d["name"]), "" if ok else "  (incomplete)"],
			"chars": d["chars"],
			"cards": d["cards"],
			"legal": ok,
			"is_random": false,
		})


func resolve_picks(rng: RandomNumberGenerator = null) -> Array:
	## Resolves the two selected entries into `[[chars0, cards0], [chars1, cards1]]`,
	## generating CSP random decks for any seat that picked "Random deck".
	var out: Array = []
	for p in range(2):
		var e: Dictionary = entries[pick[p]]
		if bool(e["is_random"]):
			var r_pair: Array = TCGAIPlayer.random_deck(rng)
			out.append(r_pair)
		else:
			out.append([e["chars"].duplicate(), e["cards"].duplicate()])
	return out


func press(key: Variant) -> void:
	if typeof(key) == TYPE_STRING:
		var sk: String = str(key)
		if sk == "back":
			back_requested.emit()
		elif sk == "start":
			var resolved: Array = resolve_picks()
			start_match_requested.emit(mode_id, resolved, levels.duplicate())
		elif sk == "builder":
			builder_requested.emit()
	elif typeof(key) == TYPE_ARRAY and key.size() >= 3:
		var kind: String = str(key[0])
		if kind == "level":
			var p: int = int(key[1])
			levels[p] = str(key[2])
			queue_redraw()
		elif kind == "pick":
			var p: int = int(key[1])
			var idx: int = int(key[2])
			if idx >= 0 and idx < entries.size():
				if bool(entries[idx]["legal"]):
					pick[p] = idx
					msg = ""
				else:
					msg = "That deck is incomplete. Finish it in the Deck Builder."
				queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var prev = _hovered_key
		_hovered_key = null
		for item in _hit_boxes:
			if bool(item["enabled"]) and (item["rect"] as Rect2).has_point(event.position):
				_hovered_key = item["key"]
				break
		if str(prev) != str(_hovered_key):
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			for item in _hit_boxes:
				if bool(item["enabled"]) and (item["rect"] as Rect2).has_point(event.position):
					press(item["key"])
					accept_event()
					return
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var col: int = 0 if event.position.x < maxf(size.x, float(TCGTheme.W)) * 0.5 else 1
			var delta_s: int = -1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1
			var max_scroll: int = maxi(0, entries.size() - VISIBLE_ROWS)
			scroll[col] = clampi(scroll[col] + delta_s, 0, max_scroll)
			queue_redraw()
			accept_event()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			press("back")
			accept_event()


func _draw_mini_char(rect: Rect2, char_name: String, selected: bool) -> void:
	var cd: CardDataSystem.CharData = CardDataSystem.get_char_def(char_name)
	var elem: String = cd.element if cd != null else "Physical"
	TCGArt.draw_portrait(self, char_name, elem, rect, false)
	var border_col: Color = TCGTheme.GOLD if selected else TCGTheme.elem_color(elem)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = border_col
	sb.set_border_width_all(3 if selected else 1)
	sb.set_corner_radius_all(3)
	draw_style_box(sb, rect)


func _draw() -> void:
	_hit_boxes.clear()
	var w: float = maxf(size.x, float(TCGTheme.W))
	var h: float = maxf(size.y, float(TCGTheme.H))
	var safe := UIConstants.get_safe_rect(Vector2(w, h))
	TCGArt.draw_mat(self, Vector2(w, h))
	draw_rect(Rect2(0, 0, w, h), Color(0.03, 0.05, 0.09, 0.45))

	var mode_title: String = "Human vs AI"
	if mode_id == "pvp":
		mode_title = "Human vs Human"
	elif mode_id == "ava":
		mode_title = "AI vs AI"
	TCGTheme.draw_text_centered(self, mode_title, Vector2(safe.get_center().x, safe.position.y + 44.0), UIConstants.FONT_TITLE - 4, TCGTheme.GOLD, true, true)

	var col_w: float = clampf((safe.size.x - 140.0) * 0.5, 560.0, 820.0)
	var col_gap: float = maxf(44.0, safe.size.x - col_w * 2.0 - 40.0)
	var start_x: float = safe.get_center().x - col_w - col_gap * 0.5
	var top_y: float = safe.position.y + 98.0
	var row_h: float = 48.0
	var row_step: float = 54.0
	var preview_y: float = top_y + 48.0 + float(VISIBLE_ROWS) * row_step + 18.0
	var card_h: float = clampf(safe.end.y - 104.0 - preview_y, 140.0, 220.0)
	var card_w: float = roundf(card_h * 0.78)
	var card_gap: float = (col_w - card_w * 3.0) / 4.0

	for p in range(2):
		var x0: float = start_x + float(p) * (col_w + col_gap)
		TCGTheme.draw_text_pos(self, titles[p], Vector2(x0, top_y), UIConstants.FONT_HEADER + 2, TCGTheme.TEXT, true, true)

		if mode_id == "ava" or (mode_id == "pve" and p == 1):
			TCGTheme.draw_text_pos(self, "AI level", Vector2(x0 + col_w - 320.0, top_y + 6.0), 15, TCGTheme.DIM, false, true)
			for k in range(LEVELS.size()):
				var lv: String = LEVELS[k]
				var lv_col: Color = TCGTheme.GREEN if lv == "easy" else (TCGTheme.TEAL if lv == "normal" else TCGTheme.RED)
				var lv_rect := Rect2(x0 + col_w - 246.0 + float(k) * 82.0, top_y - 2.0, 76.0, 34.0)
				var lv_key := ["level", p, lv]
				var is_hov: bool = (typeof(_hovered_key) == TYPE_ARRAY and str(_hovered_key) == str(lv_key))
				var is_act: bool = (levels[p] == lv)
				TCGTheme.draw_plaque(self, lv_rect, lv.capitalize(), lv_col, is_hov or is_act, false, true)
				_hit_boxes.append({"rect": lv_rect, "key": lv_key, "enabled": true})

		var max_rows: int = mini(VISIBLE_ROWS, entries.size() - scroll[p])
		for i in range(max_rows):
			var idx: int = i + scroll[p]
			var e: Dictionary = entries[idx]
			var r := Rect2(x0, top_y + 44.0 + float(i) * row_step, col_w, row_h)
			var sel: bool = (pick[p] == idx)
			var ok: bool = bool(e["legal"])
			var fill_col: Color = TCGTheme.mix(TCGTheme.PANEL, TCGTheme.GOLD, 0.25) if sel else TCGTheme.PANEL
			var bdr_col: Color = TCGTheme.GOLD if sel else Color8(70, 80, 108)
			TCGTheme.draw_rounded_box(self, r, fill_col, bdr_col, 8, 2)
			TCGTheme.draw_text_pos(
				self,
				str(e["name"]),
				Vector2(r.position.x + 14.0, r.position.y + 11.0),
				17,
				TCGTheme.TEXT if ok else TCGTheme.DIM,
				sel,
				false
			)
			var chs: Array = e["chars"]
			for k in range(chs.size()):
				_draw_mini_char(Rect2(r.end.x - 122.0 + float(k) * 38.0, r.position.y + 4.0, 34.0, 34.0), str(chs[k]), false)
			_hit_boxes.append({"rect": r, "key": ["pick", p, idx], "enabled": true})

		var sel_entry: Dictionary = entries[pick[p]]
		var sel_chars: Array = sel_entry["chars"]
		if not sel_chars.is_empty():
			for k in range(sel_chars.size()):
				var cname: String = str(sel_chars[k])
				var cx_slot: float = x0 + card_gap + float(k) * (card_w + card_gap)
				var cr := Rect2(cx_slot, preview_y, card_w, card_h)
				_draw_mini_char(cr, cname, true)
				TCGTheme.draw_text_centered(self, cname, Vector2(cr.get_center().x, cr.end.y + 18.0), 17, TCGTheme.TEXT, true, true)
		else:
			TCGTheme.draw_text_centered(
				self,
				"The AI will build a random deck (CSP solver)",
				Vector2(x0 + col_w * 0.5, preview_y + card_h * 0.5),
				18,
				TCGTheme.DIM,
				false,
				true
			)

	if not msg.is_empty():
		TCGTheme.draw_text_centered(self, msg, Vector2(safe.get_center().x, safe.end.y - 84.0), 17, TCGTheme.GOLD, true, true)

	var bot_y: float = safe.end.y - 60.0
	var back_r := Rect2(safe.position.x + 20.0, bot_y, 130.0, 46.0)
	var start_r := Rect2(safe.get_center().x - 140.0, bot_y - 4.0, 280.0, 52.0)
	var builder_r := Rect2(safe.end.x - 260.0, bot_y, 240.0, 46.0)

	TCGTheme.draw_plaque(self, back_r, "< Back", TCGTheme.DIM, str(_hovered_key) == "back", false, false)
	TCGTheme.draw_plaque(self, start_r, "Start match", TCGTheme.GREEN, str(_hovered_key) == "start", false, false)
	TCGTheme.draw_plaque(self, builder_r, "Open Deck Builder", TCGTheme.TEAL, str(_hovered_key) == "builder", false, false)

	_hit_boxes.append({"rect": back_r, "key": "back", "enabled": true})
	_hit_boxes.append({"rect": start_r, "key": "start", "enabled": true})
	_hit_boxes.append({"rect": builder_r, "key": "builder", "enabled": true})

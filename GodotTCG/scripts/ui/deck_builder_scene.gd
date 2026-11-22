class_name TCGDeckBuilderScene
extends Control
## Stage 9: Deck Builder Scene
## Direct port of PythonTCG/ui/decks.py (`DeckBuilder`).
## Supports 3-character roster selection, CSP auto-fill, category/element/cost/search
## filters, 30-card deck editing, JSON save/load/delete, and Base64 share code export/import.

signal back_requested()

const CARD_W: float = 96.0
const CARD_H: float = 134.0
const COLS: int = 5
const ROWS: int = 3
const ROSTER_PER_PAGE: int = 10
const TABS: Array[String] = ["All", "Equipment", "Utility"]
const COST_FILTER_ORDER: Array[int] = [-1, 0, 1, 2, 3, 4]   # -1 = any

var chars: Array[String] = []
var counts: Dictionary = {}   # card_name: String -> int count
var deck_name: String = "My Deck"

var tab: String = "All"
var element_filter: String = ""   # "" = any
var cost_filter: int = -1         # -1 = any, 4 = 4+
var allowed_only: bool = true
var search_query: String = ""

var page: int = 0
var roster_page: int = 0
var scroll: int = 0
var modal_scroll: int = 0
var modal: Dictionary = {}        # Empty or {"kind": "load"|"share"|"import", "code": String}
var msg: String = ""
var msg_t: float = 0.0
var msg_ok: bool = false
var hover_card: String = ""

var _hit_boxes: Array[Dictionary] = []
var _hovered_key: Variant = null

var _name_edit: LineEdit = null
var _search_edit: LineEdit = null
var _modal_layer: Control = null
var _import_edit: LineEdit = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	CardDataSystem.load_all_content()
	_build_line_edits()
	_ui_redraw()


func _ui_redraw() -> void:
	queue_redraw()
	if _modal_layer != null:
		_modal_layer.queue_redraw()


func _style_line_edit(le: LineEdit) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = TCGTheme.PANEL2
	sb.border_color = TCGTheme.GOLD_D
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	le.add_theme_stylebox_override("normal", sb)
	var sb_focus := sb.duplicate() as StyleBoxFlat
	sb_focus.border_color = TCGTheme.GOLD
	sb_focus.set_border_width_all(2)
	le.add_theme_stylebox_override("focus", sb_focus)
	le.add_theme_color_override("font_color", TCGTheme.TEXT)
	le.add_theme_color_override("font_placeholder_color", TCGTheme.DIM)
	le.add_theme_font_size_override("font_size", 15)
	le.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventKey and ev.pressed and not ev.echo and (ev as InputEventKey).keycode == KEY_ESCAPE:
			if not modal.is_empty():
				press("close")
			elif is_inside_tree():
				grab_focus()
			le.accept_event()
	)


func _build_line_edits() -> void:
	_name_edit = LineEdit.new()
	_name_edit.position = Vector2(150, 14)
	_name_edit.size = Vector2(260, 36)
	_name_edit.max_length = 24
	_name_edit.placeholder_text = "Deck name"
	_style_line_edit(_name_edit)
	_name_edit.text = deck_name
	_name_edit.text_changed.connect(func(t: String) -> void:
		deck_name = t
	)
	add_child(_name_edit)

	_search_edit = LineEdit.new()
	_search_edit.position = Vector2(760, 118)
	_search_edit.size = Vector2(260, 32)
	_search_edit.max_length = 24
	_search_edit.placeholder_text = "Search by name…"
	_style_line_edit(_search_edit)
	_search_edit.text_changed.connect(func(t: String) -> void:
		search_query = t
		page = 0
		queue_redraw()
	)
	add_child(_search_edit)

	_modal_layer = Control.new()
	_modal_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal_layer.visible = false
	_modal_layer.z_index = 15
	_modal_layer.draw.connect(_draw_modal_layer)
	add_child(_modal_layer)

	_import_edit = LineEdit.new()
	_import_edit.position = Vector2(660, 360)
	_import_edit.size = Vector2(600, 38)
	_import_edit.max_length = 0
	_import_edit.placeholder_text = "Paste a share code (Ctrl+V)"
	_style_line_edit(_import_edit)
	_import_edit.visible = false
	_import_edit.z_index = 20
	_import_edit.text_changed.connect(func(_t: String) -> void:
		_ui_redraw()
	)
	_import_edit.text_submitted.connect(func(_t: String) -> void:
		press("do_import")
	)
	add_child(_import_edit)


func _layout() -> Dictionary:
	var w: float = maxf(size.x, float(TCGTheme.W))
	var h: float = maxf(size.y, float(TCGTheme.H))
	var safe := UIConstants.get_safe_rect(Vector2(w, h))
	var top_y: float = safe.position.y + 14.0
	var left_x: float = safe.position.x + 20.0
	var left_w: float = clampf(safe.size.x * 0.22, 310.0, 390.0)
	var right_w: float = clampf(safe.size.x * 0.25, 350.0, 460.0)
	var right_x: float = safe.end.x - right_w - 20.0
	var center_x: float = left_x + left_w + 24.0
	var center_w: float = right_x - center_x - 24.0
	var grid_top: float = top_y + 150.0
	var info_h: float = 82.0
	var grid_avail_h: float = maxf(360.0, safe.end.y - grid_top - info_h - 68.0)
	var max_cw: float = floorf((center_w - 48.0) / float(COLS))
	var max_ch: float = floorf((grid_avail_h - 24.0) / float(ROWS))
	var ch: float = minf(max_ch, floorf(max_cw * 1.42))
	var cw: float = floorf(ch / 1.42)
	var col_step: float = floorf(center_w / float(COLS))
	var row_step: float = ch + 14.0
	var modal_rect := Rect2(safe.get_center() - Vector2(330.0, 280.0), Vector2(660.0, 560.0))
	return {
		"w": w,
		"h": h,
		"safe": safe,
		"top_y": top_y,
		"left_x": left_x,
		"left_w": left_w,
		"center_x": center_x,
		"center_w": center_w,
		"right_x": right_x,
		"right_w": right_w,
		"grid_top": grid_top,
		"card_w": cw,
		"card_h": ch,
		"col_step": col_step,
		"row_step": row_step,
		"info_h": info_h,
		"modal_rect": modal_rect,
	}


func _process(delta: float) -> void:
	if msg_t > 0.0:
		msg_t = maxf(0.0, msg_t - delta)
		if msg_t == 0.0:
			_ui_redraw()


# ------------------------------------------------------------------------------
# State Helpers
# ------------------------------------------------------------------------------
static func tab_of(cd: CardDataSystem.CardData) -> String:
	return CardDataSystem.infer_card_role(cd).capitalize()


static func total_cost(cd: CardDataSystem.CardData) -> int:
	return cd.cost.n + cd.cost.unaligned


static func requirement(cd: CardDataSystem.CardData) -> String:
	if not cd.char_name.is_empty():
		return "Equipment: requires %s" % cd.char_name
	var role_lbl := CardDataSystem.infer_card_role(cd).capitalize()
	return "%s Card: usable in any deck" % role_lbl


func cards() -> Array[String]:
	var out: Array[String] = []
	var keys: Array = counts.keys()
	keys.sort()
	for n in keys:
		var c: int = int(counts[n])
		for _i in range(c):
			out.append(str(n))
	return out


func total() -> int:
	var sum_v: int = 0
	for k in counts.keys():
		sum_v += int(counts[k])
	return sum_v


func say(s: String, ok: bool = false) -> void:
	msg = s
	msg_t = 3.5
	msg_ok = ok
	_ui_redraw()


func allowed(card_name: String) -> bool:
	var cd: CardDataSystem.CardData = CardDataSystem.get_card_def(card_name)
	if cd == null:
		return false
	return TCGDeckSystem.card_allowed(cd, chars)


func visible_cards() -> Array[String]:
	var q: String = search_query.strip_edges().to_lower()
	var items: Array = []
	for n in CardDataSystem.card_defs.keys():
		var card_name: String = str(n)
		var cd: CardDataSystem.CardData = CardDataSystem.card_defs[n]
		if tab != "All" and tab_of(cd) != tab:
			continue
		if not element_filter.is_empty():
			var owner_el: String = ""
			if not cd.char_name.is_empty():
				var ch_def: CardDataSystem.CharData = CardDataSystem.get_char_def(cd.char_name)
				if ch_def != null:
					owner_el = ch_def.element
			if element_filter != cd.cost.element and element_filter != cd.resonance and element_filter != owner_el:
				continue
		if cost_filter >= 0:
			var tc: int = total_cost(cd)
			if cost_filter < 4:
				if tc != cost_filter:
					continue
			elif tc < 4:
				continue
		if not q.is_empty() and card_name.to_lower().find(q) == -1:
			continue
		if allowed_only and not allowed(card_name):
			continue
		items.append([total_cost(cd), card_name])

	items.sort_custom(func(lhs: Array, rhs: Array) -> bool:
		if int(lhs[0]) != int(rhs[0]):
			return int(lhs[0]) < int(rhs[0])
		return str(lhs[1]) < str(rhs[1])
	)
	var out: Array[String] = []
	for item in items:
		out.append(str(item[1]))
	return out


func prune() -> void:
	var gone: Array[String] = []
	for k in counts.keys():
		var kn: String = str(k)
		if not allowed(kn):
			gone.append(kn)
	for k in gone:
		counts.erase(k)
	if not gone.is_empty():
		say("Removed %d card type(s) that no longer fit these characters" % gone.size(), false)


func toggle_char(char_name: String) -> void:
	if chars.has(char_name):
		chars.erase(char_name)
		prune()
	elif chars.size() < 3:
		chars.append(char_name)
	else:
		say("Already 3 characters. Click one to remove it first.", false)
	queue_redraw()


func add_card(card_name: String) -> void:
	var cd: CardDataSystem.CardData = CardDataSystem.get_card_def(card_name)
	if cd == null:
		return
	if not allowed(card_name):
		var req: String = requirement(cd)
		var parts := req.split(": ", false, 1)
		var detail: String = parts[1] if parts.size() > 1 else req
		say("Not allowed: " + detail.replace("requires", "needs"), false)
	elif int(counts.get(card_name, 0)) >= TCGDeckSystem.MAX_COPIES:
		say("Max %d copies of a card" % TCGDeckSystem.MAX_COPIES, false)
	elif total() >= TCGDeckSystem.DECK_SIZE:
		say("Deck already has %d cards" % TCGDeckSystem.DECK_SIZE, false)
	else:
		counts[card_name] = int(counts.get(card_name, 0)) + 1
		queue_redraw()


func remove_card(card_name: String) -> void:
	var cur: int = int(counts.get(card_name, 0))
	if cur > 0:
		if cur == 1:
			counts.erase(card_name)
		else:
			counts[card_name] = cur - 1
		queue_redraw()


func validation() -> Dictionary:
	## Returns `{"messages": Array[String], "ok": bool}`.
	if chars.size() < 3:
		return {"messages": ["Pick %d more character(s)" % (3 - chars.size())], "ok": false}
	var errs: Array[String] = TCGDeckSystem.validate_deck(chars, cards())
	if errs.is_empty():
		return {"messages": ["Deck is legal"], "ok": true}
	return {"messages": errs, "ok": false}


func _sync_modal_widgets() -> void:
	var in_modal: bool = not modal.is_empty()
	if _name_edit != null:
		_name_edit.editable = not in_modal
	if _search_edit != null:
		_search_edit.editable = not in_modal
	if _modal_layer != null:
		_modal_layer.visible = in_modal
		if in_modal:
			_modal_layer.queue_redraw()
	if _import_edit != null:
		_import_edit.visible = in_modal and str(modal.get("kind", "")) == "import"
		if _import_edit.visible and _import_edit.is_inside_tree():
			_import_edit.grab_focus()


# ------------------------------------------------------------------------------
# Actions
# ------------------------------------------------------------------------------
func press(key: Variant) -> void:
	if typeof(key) == TYPE_STRING:
		var sk: String = str(key)
		match sk:
			"back":
				back_requested.emit()
			"clear":
				chars.clear()
				counts.clear()
				queue_redraw()
			"fill":
				if chars.size() < 3:
					say("Pick 3 characters first", false)
					return
				var res = TCGDeckSystem.autofill(chars, cards(), CardDataSystem.get_card_priorities())
				if res == null:
					say("Can't complete this deck", false)
					return
				counts.clear()
				for c in res:
					counts[str(c)] = int(counts.get(str(c), 0)) + 1
				say("Deck completed by the constraint solver", true)
			"save":
				if chars.size() != 3:
					say("Pick 3 characters before saving", false)
					return
				var cur_name: String = _name_edit.text if _name_edit != null else deck_name
				if not TCGDeckStore.save_deck(cur_name, chars, cards()):
					say("Could not save: %s" % TCGDeckStore.last_error, false)
					return
				var ok_flag: bool = bool(validation()["ok"])
				say("Saved '%s'%s" % [cur_name.strip_edges(), "" if ok_flag else " (draft: not yet playable)"], true)
			"load":
				modal = {"kind": "load"}
				modal_scroll = 0
				_sync_modal_widgets()
				_ui_redraw()
			"share":
				if chars.size() != 3:
					say("Pick 3 characters first", false)
					return
				var code: String = TCGDeckSystem.encode(chars, cards())
				DisplayServer.clipboard_set(code)
				modal = {"kind": "share", "code": code}
				_sync_modal_widgets()
				_ui_redraw()
			"import":
				if _import_edit != null:
					_import_edit.text = ""
				modal = {"kind": "import"}
				_sync_modal_widgets()
				_ui_redraw()
			"close":
				modal.clear()
				_sync_modal_widgets()
				_ui_redraw()
			"do_import":
				var code_in: String = _import_edit.text.strip_edges() if _import_edit != null else ""
				var decoded: Array = TCGDeckSystem.decode(code_in)
				if decoded.size() != 2:
					say("That share code is not valid", false)
					return
				var d_chars: Array = decoded[0]
				var d_cards: Array = decoded[1]
				if d_chars.size() != 3:
					say("That share code is not valid", false)
					return
				for c in d_chars:
					if not CardDataSystem.char_defs.has(str(c)):
						say("That share code is not valid", false)
						return
				for card in d_cards:
					if not CardDataSystem.card_defs.has(str(card)):
						say("That share code is not valid", false)
						return
				chars.clear()
				for c in d_chars:
					chars.append(str(c))
				counts.clear()
				for card in d_cards:
					counts[str(card)] = int(counts.get(str(card), 0)) + 1
				modal.clear()
				_sync_modal_widgets()
				say("Deck imported", true)
			"copy":
				if modal.has("code"):
					DisplayServer.clipboard_set(str(modal["code"]))
					say("Copied to clipboard", true)
			"allowed":
				allowed_only = not allowed_only
				page = 0
				queue_redraw()
			"element":
				var order: Array[String] = [""]
				for el in CardDataSystem.ELEMENTS:
					order.append(el)
				var cur_i: int = order.find(element_filter)
				element_filter = order[(cur_i + 1) % order.size()]
				page = 0
				queue_redraw()
			"costf":
				var cur_c: int = COST_FILTER_ORDER.find(cost_filter)
				cost_filter = COST_FILTER_ORDER[(cur_c + 1) % COST_FILTER_ORDER.size()]
				page = 0
				queue_redraw()
			"prev":
				page = maxi(0, page - 1)
				queue_redraw()
			"next":
				page += 1
				queue_redraw()
			"rprev":
				roster_page = maxi(0, roster_page - 1)
				queue_redraw()
			"rnext":
				roster_page += 1
				queue_redraw()
	elif typeof(key) == TYPE_ARRAY and not key.is_empty():
		var kind: String = str(key[0])
		match kind:
			"tab":
				tab = str(key[1])
				page = 0
				queue_redraw()
			"char":
				toggle_char(str(key[1]))
			"card":
				add_card(str(key[1]))
			"row":
				remove_card(str(key[1]))
			"loaddeck":
				var d: Dictionary = key[1]
				var saved: bool = bool(key[2])
				chars.clear()
				for c in d["chars"]:
					chars.append(str(c))
				counts.clear()
				for card in d["cards"]:
					counts[str(card)] = int(counts.get(str(card), 0)) + 1
				var loaded_name: String = str(d["name"])
				deck_name = loaded_name if saved else (loaded_name + " copy")
				if _name_edit != null:
					_name_edit.text = deck_name
				modal.clear()
				_sync_modal_widgets()
				say("Loaded '%s'" % loaded_name, true)
			"deldeck":
				TCGDeckStore.delete_deck(str(key[1]))
				_ui_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var prev_hov = _hovered_key
		var prev_card: String = hover_card
		_hovered_key = null
		hover_card = ""
		for item in _hit_boxes:
			if bool(item["enabled"]) and (item["rect"] as Rect2).has_point(event.position):
				_hovered_key = item["key"]
				if typeof(item["key"]) == TYPE_ARRAY and item["key"].size() >= 2 and str(item["key"][0]) in ["card", "row"]:
					hover_card = str(item["key"][1])
				break
		if str(prev_hov) != str(_hovered_key) or prev_card != hover_card:
			_ui_redraw()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			if has_focus() == false and is_inside_tree():
				grab_focus()
			for item in _hit_boxes:
				if bool(item["enabled"]) and (item["rect"] as Rect2).has_point(event.position):
					var k = item["key"]
					if event.button_index == MOUSE_BUTTON_RIGHT:
						if typeof(k) == TYPE_ARRAY and k.size() >= 2 and str(k[0]) == "card":
							remove_card(str(k[1]))
						accept_event()
						return
					press(k)
					accept_event()
					return
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var delta_s: int = -1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1
			var ly_w: Dictionary = _layout()
			if not modal.is_empty():
				if str(modal.get("kind", "")) == "load":
					modal_scroll = maxi(0, modal_scroll + delta_s)
					_ui_redraw()
			elif event.position.x > float(ly_w["right_x"]) - 10.0:
				scroll = maxi(0, scroll + delta_s)
				_ui_redraw()
			elif event.position.x > float(ly_w["center_x"]) - 10.0:
				page = maxi(0, page + delta_s)
				_ui_redraw()
			accept_event()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if not modal.is_empty():
				press("close")
			else:
				press("back")
			accept_event()


# ------------------------------------------------------------------------------
# Drawing
# ------------------------------------------------------------------------------
func _draw_mini_char(rect: Rect2, char_name: String, selected: bool, dim: bool = false) -> void:
	var cd: CardDataSystem.CharData = CardDataSystem.get_char_def(char_name)
	var elem: String = cd.element if cd != null else "Physical"
	TCGArt.draw_portrait(self, char_name, elem, rect, false)
	if dim:
		draw_rect(rect, Color(0.04, 0.05, 0.08, 0.67))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = TCGTheme.GOLD if selected else TCGTheme.elem_color(elem)
	sb.set_border_width_all(3 if selected else 1)
	sb.set_corner_radius_all(3)
	draw_style_box(sb, rect)


func _is_hov(key: Variant) -> bool:
	return _hovered_key != null and str(_hovered_key) == str(key)


func _draw() -> void:
	_hit_boxes.clear()
	var ly: Dictionary = _layout()
	var w: float = float(ly["w"])
	var h: float = float(ly["h"])
	var top_y: float = float(ly["top_y"])
	var left_x: float = float(ly["left_x"])
	var center_x: float = float(ly["center_x"])
	var center_w: float = float(ly["center_w"])
	var modal_rect: Rect2 = ly["modal_rect"]
	TCGArt.draw_mat(self, Vector2(w, h))
	draw_rect(Rect2(0, 0, w, h), Color(0.03, 0.05, 0.09, 0.45))

	var in_modal: bool = not modal.is_empty()

	# Top Bar
	var back_r := Rect2(left_x, top_y, 110.0, 38.0)
	TCGTheme.draw_plaque(self, back_r, "< Back", TCGTheme.DIM, _is_hov("back"), false, in_modal)
	_hit_boxes.append({"rect": back_r, "key": "back", "enabled": not in_modal})

	if _name_edit != null:
		_name_edit.position = Vector2(back_r.end.x + 14.0, top_y + 1.0)
		_name_edit.size = Vector2(maxf(200.0, float(ly["left_w"]) - 124.0), 36.0)
	if _search_edit != null:
		_search_edit.position = Vector2(center_x + center_w - 280.0, top_y + 98.0)
		_search_edit.size = Vector2(280.0, 34.0)
	if _import_edit != null:
		_import_edit.position = Vector2(modal_rect.position.x + 28.0, modal_rect.position.y + 110.0)
		_import_edit.size = Vector2(modal_rect.size.x - 56.0, 38.0)

	var top_buttons: Array = [
		["Save", "save", TCGTheme.GREEN, 96.0],
		["Load", "load", TCGTheme.TEAL, 96.0],
		["Auto-fill", "fill", TCGTheme.GOLD, 118.0],
		["Share", "share", TCGTheme.TEAL, 96.0],
		["Import", "import", TCGTheme.TEAL, 96.0],
		["Clear", "clear", TCGTheme.RED, 96.0],
	]
	var tx: float = center_x
	for tb in top_buttons:
		var bw: float = float(tb[3])
		var br := Rect2(tx, top_y, bw, 38.0)
		var bkey: String = str(tb[1])
		TCGTheme.draw_plaque(self, br, str(tb[0]), tb[2], _is_hov(bkey), false, in_modal)
		_hit_boxes.append({"rect": br, "key": bkey, "enabled": not in_modal})
		tx += bw + 10.0

	_draw_left(in_modal, ly)
	_draw_center(in_modal, ly)
	_draw_right(in_modal, ly)

	# Large Hover Card Preview
	if not hover_card.is_empty() and not in_modal:
		var preview_x: float = center_x if get_local_mouse_position().x > float(ly["right_x"]) - 10.0 else float(ly["right_x"]) + 20.0
		var preview_r := Rect2(preview_x, top_y + 64.0, 236.0, 346.0)
		TCGActionCardView.draw_card_surface(self, preview_r, hover_card, false, true, true, true)

	if in_modal:
		_register_modal_hitboxes()
		if _modal_layer != null:
			_modal_layer.queue_redraw()


func _draw_left(in_modal: bool, ly: Dictionary) -> void:
	var lx: float = float(ly["left_x"])
	var lw: float = float(ly["left_w"])
	var ty: float = float(ly["top_y"]) + 54.0
	TCGTheme.draw_text_pos(self, "Characters %d/3" % chars.size(), Vector2(lx, ty), 19, TCGTheme.GOLD, true, true)
	var slot_gap: float = 10.0
	var slot_w: float = floorf((lw - slot_gap * 2.0) / 3.0)
	var slot_h: float = roundf(slot_w * 1.28)
	for i in range(3):
		var r := Rect2(lx + float(i) * (slot_w + slot_gap), ty + 30.0, slot_w, slot_h)
		if i < chars.size():
			var cname: String = chars[i]
			var pr := Rect2(r.position.x, r.position.y, r.size.x, r.size.y - 24.0)
			_draw_mini_char(pr, cname, true, false)
			var pick_sz: int = TCGTheme.fit_font_size(cname, r.size.x - 4.0, 14, 10, true)
			TCGTheme.draw_text_centered(self, cname, Vector2(r.get_center().x, r.end.y - 10.0), pick_sz, TCGTheme.TEXT, true, true)
			_hit_boxes.append({"rect": pr, "key": ["char", cname], "enabled": not in_modal})
		else:
			TCGTheme.draw_rounded_box(self, r, Color8(24, 30, 48), Color8(60, 70, 98), 8, 2)
			TCGTheme.draw_text_centered(self, "empty", r.get_center(), 15, TCGTheme.DIM, false, true)

	var roster_y: float = ty + 30.0 + slot_h + 18.0
	var roster: PackedStringArray = CardDataSystem.roster
	var r_pages: int = maxi(1, ceili(float(roster.size()) / float(ROSTER_PER_PAGE)))
	roster_page = clampi(roster_page, 0, r_pages - 1)
	TCGTheme.draw_text_pos(self, "Roster (click to add / remove)", Vector2(lx, roster_y), 15, TCGTheme.DIM, false, true)
	if r_pages > 1:
		var rp_r := Rect2(lx + lw - 56.0, roster_y - 2.0, 26.0, 22.0)
		var rn_r := Rect2(lx + lw - 26.0, roster_y - 2.0, 26.0, 22.0)
		TCGTheme.draw_plaque(self, rp_r, "<", TCGTheme.DIM, _is_hov("rprev"), in_modal or roster_page <= 0, true)
		TCGTheme.draw_plaque(self, rn_r, ">", TCGTheme.DIM, _is_hov("rnext"), in_modal or roster_page >= r_pages - 1, true)
		_hit_boxes.append({"rect": rp_r, "key": "rprev", "enabled": not in_modal and roster_page > 0})
		_hit_boxes.append({"rect": rn_r, "key": "rnext", "enabled": not in_modal and roster_page < r_pages - 1})

	var r_start: int = roster_page * ROSTER_PER_PAGE
	var r_end: int = mini(roster.size(), r_start + ROSTER_PER_PAGE)
	var visible_roster_count: int = maxi(1, r_end - r_start)
	var r_step: float = floorf((lw + 6.0) / 5.0)
	var rw: float = r_step - 6.0
	var rh: float = roundf(rw * 1.18)
	for vi in range(r_end - r_start):
		var cname: String = roster[r_start + vi]
		var r := Rect2(lx + float(vi % 5) * r_step, roster_y + 24.0 + float(vi / 5) * (rh + 8.0), rw, rh)
		var picked: bool = chars.has(cname)
		_draw_mini_char(r, cname, picked, not picked and chars.size() >= 3)
		TCGTheme.draw_text_centered(self, cname.substr(0, 7), Vector2(r.get_center().x, r.end.y - 9.0), 12, TCGTheme.TEXT, true, true)
		_hit_boxes.append({"rect": r, "key": ["char", cname], "enabled": not in_modal})

	var comp_y: float = roster_y + 24.0 + float(ceili(float(visible_roster_count) / 5.0)) * (rh + 8.0) + 14.0
	# Composition + Cost Curve
	var kinds: Dictionary = {}
	var curve: Dictionary = {0: 0, 1: 0, 2: 0, 3: 0, 4: 0}
	var all_cards: Array[String] = cards()
	for n in all_cards:
		var cd: CardDataSystem.CardData = CardDataSystem.get_card_def(n)
		if cd != null:
			var t_name: String = tab_of(cd)
			kinds[t_name] = int(kinds.get(t_name, 0)) + 1
			var c_bucket: int = mini(total_cost(cd), 4)
			curve[c_bucket] = int(curve[c_bucket]) + 1

	TCGTheme.draw_text_pos(self, "Composition", Vector2(lx, comp_y), 16, TCGTheme.GOLD, true, true)
	var comp_parts: Array[String] = []
	var k_keys: Array = kinds.keys()
	k_keys.sort()
	for kk in k_keys:
		comp_parts.append("%s %d" % [str(kk), int(kinds[kk])])
	var comp_line: String = "  ".join(comp_parts) if not comp_parts.is_empty() else "no cards yet"
	TCGTheme.draw_wrapped(self, comp_line, Rect2(lx, comp_y + 24.0, lw, 44.0), 14, TCGTheme.DIM, 18, false)

	var curve_y: float = comp_y + 72.0
	TCGTheme.draw_text_pos(self, "Cost curve", Vector2(lx, curve_y), 16, TCGTheme.GOLD, true, true)
	var peak: int = 1
	for c in range(5):
		peak = maxi(peak, int(curve[c]))
	var b_step: float = floorf(lw / 5.0)
	for c in range(5):
		var cnt: int = int(curve[c])
		var bar_h: float = (78.0 * float(cnt) / float(peak)) if cnt > 0 else 0.0
		var br := Rect2(lx + 6.0 + float(c) * b_step, curve_y + 98.0 - bar_h, b_step - 16.0, bar_h)
		if bar_h > 0.0:
			TCGTheme.draw_rounded_box(self, br, TCGTheme.TEAL, Color(0, 0, 0, 0), 4, 0)
		TCGTheme.draw_text_centered(self, str(cnt), Vector2(br.position.x + br.size.x * 0.5, br.position.y - 10.0), 14, TCGTheme.TEXT, true, true)
		TCGTheme.draw_text_centered(self, "4+" if c == 4 else str(c), Vector2(br.position.x + br.size.x * 0.5, curve_y + 112.0), 14, TCGTheme.DIM, false, true)

	var val: Dictionary = validation()
	var msgs: Array = val["messages"]
	var ok: bool = bool(val["ok"])
	var stat_y: float = curve_y + 134.0
	TCGTheme.draw_text_pos(self, "Status", Vector2(lx, stat_y), 16, TCGTheme.GOLD, true, true)
	var msg_joined: Array[String] = []
	for m_i in range(mini(4, msgs.size())):
		msg_joined.append(str(msgs[m_i]))
	TCGTheme.draw_wrapped(self, "\n".join(msg_joined), Rect2(lx, stat_y + 24.0, lw, 110.0), 14, TCGTheme.GREEN if ok else TCGTheme.RED, 18, false)


func _draw_center(in_modal: bool, ly: Dictionary) -> void:
	var cx: float = float(ly["center_x"])
	var cw_tot: float = float(ly["center_w"])
	var top_y: float = float(ly["top_y"])
	var safe: Rect2 = ly["safe"]
	var tx: float = cx
	for t in TABS:
		var w: float = 86.0 if t != "Resonance" else 108.0
		var r := Rect2(tx, top_y + 54.0, w, 32.0)
		var tkey := ["tab", t]
		TCGTheme.draw_plaque(self, r, t, TCGTheme.TEAL, _is_hov(tkey) or (tab == t), in_modal, true)
		_hit_boxes.append({"rect": r, "key": tkey, "enabled": not in_modal})
		tx += w + 8.0

	var el_r := Rect2(cx, top_y + 98.0, 124.0, 34.0)
	var el_label: String = element_filter if not element_filter.is_empty() else "Element: any"
	var el_col: Color = TCGTheme.elem_color(element_filter) if not element_filter.is_empty() else TCGTheme.DIM
	TCGTheme.draw_plaque(self, el_r, el_label, el_col, _is_hov("element"), in_modal, true)
	_hit_boxes.append({"rect": el_r, "key": "element", "enabled": not in_modal})

	var cost_r := Rect2(el_r.end.x + 8.0, top_y + 98.0, 110.0, 34.0)
	var cost_label: String = "Cost: any" if cost_filter < 0 else ("Cost: %d%s" % [cost_filter, "+" if cost_filter == 4 else ""])
	TCGTheme.draw_plaque(self, cost_r, cost_label, TCGTheme.DIM, _is_hov("costf"), in_modal, true)
	_hit_boxes.append({"rect": cost_r, "key": "costf", "enabled": not in_modal})

	var allow_r := Rect2(cost_r.end.x + 8.0, top_y + 98.0, 138.0, 34.0)
	var allow_label: String = "Fits deck only" if allowed_only else "Show all"
	TCGTheme.draw_plaque(self, allow_r, allow_label, TCGTheme.GOLD, _is_hov("allowed") or allowed_only, in_modal, true)
	_hit_boxes.append({"rect": allow_r, "key": "allowed", "enabled": not in_modal})

	var names: Array[String] = visible_cards()
	var per_page: int = COLS * ROWS
	var pages: int = maxi(1, ceili(float(names.size()) / float(per_page)))
	page = mini(page, pages - 1)
	var start_i: int = page * per_page
	var end_i: int = mini(names.size(), start_i + per_page)
	var grid_top: float = float(ly["grid_top"])
	var card_w: float = float(ly["card_w"])
	var card_h: float = float(ly["card_h"])
	var col_step: float = float(ly["col_step"])
	var row_step: float = float(ly["row_step"])

	if names.is_empty():
		TCGTheme.draw_text_centered(self, "No cards match. Pick characters, or switch to 'Show all'.", Vector2(cx + cw_tot * 0.5, grid_top + row_step * 1.3), 18, TCGTheme.DIM, false, true)
	else:
		for i in range(end_i - start_i):
			var n: String = names[start_i + i]
			var r := Rect2(cx + float(i % COLS) * col_step, grid_top + float(i / COLS) * row_step, card_w, card_h)
			var cnt: int = int(counts.get(n, 0))
			var ok: bool = allowed(n) and cnt < TCGDeckSystem.MAX_COPIES
			var ckey := ["card", n]
			TCGActionCardView.draw_card_surface(self, r, n, cnt > 0, _is_hov(ckey), ok, false)
			if cnt > 0:
				var bc := Vector2(r.end.x - 4.0, r.position.y + 4.0)
				draw_circle(bc, 15.0, Color8(20, 24, 38))
				draw_arc(bc, 15.0, 0.0, TAU, 24, TCGTheme.GOLD, 2.0)
				TCGTheme.draw_text_centered(self, "x%d" % cnt, bc, 15, TCGTheme.GOLD, true, false)
			_hit_boxes.append({"rect": r, "key": ckey, "enabled": not in_modal})

	var pager_y: float = safe.end.y - float(ly["info_h"]) - 52.0
	var prev_r := Rect2(cx, pager_y, 96.0, 34.0)
	var next_r := Rect2(cx + cw_tot - 96.0, pager_y, 96.0, 34.0)
	TCGTheme.draw_plaque(self, prev_r, "< Prev", TCGTheme.DIM, _is_hov("prev"), in_modal or page <= 0, true)
	TCGTheme.draw_text_centered(self, "Page %d/%d   (%d cards)" % [page + 1, pages, names.size()], Vector2(cx + cw_tot * 0.5, pager_y + 17.0), 16, TCGTheme.DIM, false, true)
	TCGTheme.draw_plaque(self, next_r, "Next >", TCGTheme.DIM, _is_hov("next"), in_modal or page >= pages - 1, true)
	_hit_boxes.append({"rect": prev_r, "key": "prev", "enabled": not in_modal and page > 0})
	_hit_boxes.append({"rect": next_r, "key": "next", "enabled": not in_modal and page < pages - 1})

	var info := Rect2(cx, safe.end.y - float(ly["info_h"]) - 12.0, cw_tot, float(ly["info_h"]))
	TCGTheme.draw_rounded_box(self, info, TCGTheme.PANEL, Color(0, 0, 0, 0), 8, 0)
	if msg_t > 0.0:
		TCGTheme.draw_text_centered(self, msg, info.get_center(), 17, TCGTheme.GREEN if msg_ok else TCGTheme.GOLD, true, true)
	elif not hover_card.is_empty():
		var cd: CardDataSystem.CardData = CardDataSystem.get_card_def(hover_card)
		if cd != null:
			TCGTheme.draw_text_pos(self, cd.name, Vector2(info.position.x + 14.0, info.position.y + 10.0), 18, TCGTheme.GOLD, true, true)
			var pairs := TCGActionCardView.cost_to_pairs(cd.cost)
			for p_i in range(pairs.size()):
				TCGArt.draw_cost_gem(self, str(pairs[p_i][0]), int(pairs[p_i][1]), Vector2(info.position.x + 28.0 + float(p_i) * 26.0, info.position.y + 52.0), 11.0)
			TCGTheme.draw_text_pos(self, requirement(cd), Vector2(info.position.x + 132.0, info.position.y + 42.0), 15, TCGTheme.TEXT, false, true)
	else:
		TCGTheme.draw_text_centered(self, "Left click: add a copy    Right click: remove    Wheel: change page", info.get_center(), 15, TCGTheme.DIM, false, true)


func _draw_right(in_modal: bool, ly: Dictionary) -> void:
	var rx: float = float(ly["right_x"])
	var rw: float = float(ly["right_w"])
	var top_y: float = float(ly["top_y"]) + 52.0
	var safe: Rect2 = ly["safe"]
	var panel_h: float = safe.end.y - top_y - 12.0
	var n_total: int = total()
	TCGTheme.draw_rounded_box(self, Rect2(rx, top_y, rw, panel_h), TCGTheme.PANEL, Color(0, 0, 0, 0), 10, 0)
	TCGTheme.draw_text_pos(self, "Deck  %d/%d" % [n_total, TCGDeckSystem.DECK_SIZE], Vector2(rx + 16.0, top_y + 10.0), 22, TCGTheme.GREEN if n_total == TCGDeckSystem.DECK_SIZE else TCGTheme.GOLD, true, true)

	var rows: Array = []
	for k in counts.keys():
		var cname: String = str(k)
		var cd: CardDataSystem.CardData = CardDataSystem.get_card_def(cname)
		var tc: int = total_cost(cd) if cd != null else 0
		rows.append([tc, cname, int(counts[k])])
	rows.sort_custom(func(lhs: Array, rhs: Array) -> bool:
		if int(lhs[0]) != int(rhs[0]):
			return int(lhs[0]) < int(rhs[0])
		return str(lhs[1]) < str(rhs[1])
	)

	var row_step: float = 28.0
	var per: int = maxi(10, int(floorf((panel_h - 72.0) / row_step)))
	scroll = clampi(scroll, 0, maxi(0, rows.size() - per))
	var end_r: int = mini(rows.size(), scroll + per)
	for i in range(end_r - scroll):
		var row: Array = rows[scroll + i]
		var tc: int = int(row[0])
		var cname: String = str(row[1])
		var cnt: int = int(row[2])
		var r := Rect2(rx + 12.0, top_y + 46.0 + float(i) * row_step, rw - 24.0, row_step - 3.0)
		var cd: CardDataSystem.CardData = CardDataSystem.get_card_def(cname)
		var kcol: Color = TCGTheme.TEAL
		if cd != null:
			match cd.kind:
				"weapon": kcol = Color8(180, 90, 80)
				"artifact": kcol = Color8(200, 160, 70)
				"support": kcol = TCGTheme.TEAL
				"talent": kcol = Color8(170, 110, 220)
				_: kcol = Color8(90, 140, 210)
		var row_hovered: bool = _is_hov(["row", cname])
		var row_fill: Color = TCGTheme.mix(TCGTheme.PANEL2, kcol, 0.42 if row_hovered else 0.25)
		var row_border: Color = TCGTheme.GOLD if row_hovered else Color(0, 0, 0, 0)
		TCGTheme.draw_rounded_box(self, r, row_fill, row_border, 5, 1 if row_hovered else 0)
		TCGTheme.draw_text_centered(self, str(tc), Vector2(r.position.x + 14.0, r.get_center().y), 14, TCGTheme.GOLD, true, false)
		TCGTheme.draw_text_pos(self, cname, Vector2(r.position.x + 34.0, r.position.y + 4.0), 15, TCGTheme.TEXT, false, false)
		TCGTheme.draw_text_pos(self, "x%d" % cnt, Vector2(r.end.x - 34.0, r.position.y + 4.0), 15, TCGTheme.GOLD, true, false)
		_hit_boxes.append({"rect": r, "key": ["row", cname], "enabled": not in_modal})

	if rows.is_empty():
		TCGTheme.draw_text_centered(self, "Click cards to add them", Vector2(rx + rw * 0.5, top_y + panel_h * 0.45), 16, TCGTheme.DIM, false, true)
	elif rows.size() > per:
		TCGTheme.draw_text_centered(self, "scroll for more (%d)" % (rows.size() - per), Vector2(rx + rw * 0.5, safe.end.y - 24.0), 13, TCGTheme.DIM, false, true)


func _build_load_entries() -> Array:
	var load_entries: Array = []
	for d in TCGDeckStore.list_decks():
		load_entries.append([str(d["name"]), d["chars"], d["cards"], true, d])
	var presets: Dictionary = TCGDeckSystem.preset_decks()
	var pnames: Array = presets.keys()
	pnames.sort()
	for pn in pnames:
		var pair: Array = presets[pn]
		load_entries.append(["%s  (preset)" % str(pn), pair[0], pair[1], false, {"name": str(pn), "chars": pair[0], "cards": pair[1]}])
	return load_entries


func _register_modal_hitboxes() -> void:
	_hit_boxes.clear()
	var ly: Dictionary = _layout()
	var panel: Rect2 = ly["modal_rect"]
	var close_r := Rect2(panel.end.x - 110.0, panel.end.y - 50.0, 96.0, 34.0)
	_hit_boxes.append({"rect": close_r, "key": "close", "enabled": true})

	var mkind: String = str(modal.get("kind", ""))
	if mkind == "load":
		var load_entries: Array = _build_load_entries()
		var per_modal: int = 12
		modal_scroll = clampi(modal_scroll, 0, maxi(0, load_entries.size() - per_modal))
		var end_m: int = mini(load_entries.size(), modal_scroll + per_modal)
		for i in range(end_m - modal_scroll):
			var item: Array = load_entries[modal_scroll + i]
			var saved: bool = bool(item[3])
			var d_obj: Dictionary = item[4]
			var r := Rect2(panel.position.x + 20.0, panel.position.y + 56.0 + float(i) * 32.0, panel.size.x - 108.0, 28.0)
			_hit_boxes.append({"rect": r, "key": ["loaddeck", d_obj, saved], "enabled": true})
			if saved:
				var del_r := Rect2(r.end.x + 8.0, r.position.y, 56.0, 28.0)
				_hit_boxes.append({"rect": del_r, "key": ["deldeck", str(d_obj["name"])], "enabled": true})
	elif mkind == "share":
		var copy_r := Rect2(panel.position.x + 24.0, panel.end.y - 50.0, 160.0, 34.0)
		_hit_boxes.append({"rect": copy_r, "key": "copy", "enabled": true})
	elif mkind == "import":
		var can_imp: bool = _import_edit != null and not _import_edit.text.strip_edges().is_empty()
		var imp_r := Rect2(panel.position.x + 24.0, panel.end.y - 50.0, 120.0, 34.0)
		_hit_boxes.append({"rect": imp_r, "key": "do_import", "enabled": can_imp})


func _draw_modal_layer() -> void:
	if _modal_layer == null or modal.is_empty():
		return
	var ly: Dictionary = _layout()
	var c: CanvasItem = _modal_layer
	c.draw_rect(Rect2(0, 0, float(ly["w"]), float(ly["h"])), Color(0, 0, 0, 0.74))
	var panel: Rect2 = ly["modal_rect"]
	TCGTheme.draw_gold_frame(c, panel, TCGTheme.PANEL, 14, true)

	var close_r := Rect2(panel.end.x - 110.0, panel.end.y - 50.0, 96.0, 34.0)
	TCGTheme.draw_plaque(c, close_r, "Close", TCGTheme.DIM, _is_hov("close"), false, false)

	var mkind: String = str(modal.get("kind", ""))
	if mkind == "load":
		TCGTheme.draw_text_centered(c, "Load a deck", Vector2(panel.get_center().x, panel.position.y + 24.0), 22, TCGTheme.GOLD, true, true)
		var load_entries: Array = _build_load_entries()
		var per_modal: int = 12
		modal_scroll = clampi(modal_scroll, 0, maxi(0, load_entries.size() - per_modal))
		var end_m: int = mini(load_entries.size(), modal_scroll + per_modal)
		for i in range(end_m - modal_scroll):
			var item: Array = load_entries[modal_scroll + i]
			var nm: String = str(item[0])
			var chs: Array = item[1]
			var cds: Array = item[2]
			var saved: bool = bool(item[3])
			var d_obj: Dictionary = item[4]
			var r := Rect2(panel.position.x + 20.0, panel.position.y + 56.0 + float(i) * 31.0, 480.0, 28.0)
			var legal: bool = TCGDeckSystem.validate_deck(chs, cds).is_empty()
			var rkey := ["loaddeck", d_obj, saved]
			var hov: bool = _is_hov(rkey)
			TCGTheme.draw_rounded_box(c, r, TCGTheme.mix(TCGTheme.PANEL2, TCGTheme.GOLD, 0.16) if hov else TCGTheme.PANEL2, TCGTheme.GOLD if hov else Color(0, 0, 0, 0), 6, 1 if hov else 0)
			TCGTheme.draw_text_pos(c, nm + ("" if legal else "  (draft)"), Vector2(r.position.x + 10.0, r.position.y + 6.0), 15, TCGTheme.TEXT if legal else TCGTheme.GOLD, false, false)
			var ch_str_arr: PackedStringArray = []
			for ch in chs:
				ch_str_arr.append(str(ch))
			TCGTheme.draw_text_pos(c, ", ".join(ch_str_arr), Vector2(r.end.x - 165.0, r.position.y + 7.0), 12, TCGTheme.DIM, false, false)
			if saved:
				var del_r := Rect2(r.end.x + 8.0, r.position.y, 56.0, 28.0)
				var dkey := ["deldeck", str(d_obj["name"])]
				TCGTheme.draw_plaque(c, del_r, "Del", TCGTheme.RED, _is_hov(dkey), false, true)
		if load_entries.is_empty():
			TCGTheme.draw_text_centered(c, "No decks yet", panel.get_center(), 16, TCGTheme.DIM, false, true)
		elif load_entries.size() > per_modal:
			TCGTheme.draw_text_pos(c, "Scroll wheel: %d-%d of %d" % [modal_scroll + 1, end_m, load_entries.size()], Vector2(panel.position.x + 24.0, panel.end.y - 40.0), 13, TCGTheme.DIM, false, true)
	elif mkind == "share":
		TCGTheme.draw_text_centered(c, "Share code", Vector2(panel.get_center().x, panel.position.y + 24.0), 22, TCGTheme.GOLD, true, true)
		TCGTheme.draw_text_centered(c, "Anyone can paste this into Import to get your deck.", Vector2(panel.get_center().x, panel.position.y + 60.0), 14, TCGTheme.DIM, false, true)
		var code: String = str(modal.get("code", ""))
		var line_idx: int = 0
		var pos_idx: int = 0
		while pos_idx < code.length() and line_idx < 12:
			var chunk: String = code.substr(pos_idx, 62)
			TCGTheme.draw_text_pos(c, chunk, Vector2(panel.position.x + 24.0, panel.position.y + 90.0 + float(line_idx) * 22.0), 15, TCGTheme.TEXT, false, false)
			pos_idx += 62
			line_idx += 1
		var copy_r := Rect2(panel.position.x + 24.0, panel.end.y - 50.0, 160.0, 34.0)
		TCGTheme.draw_plaque(c, copy_r, "Copy to clipboard", TCGTheme.GREEN, _is_hov("copy"), false, false)
	elif mkind == "import":
		TCGTheme.draw_text_centered(c, "Import a deck", Vector2(panel.get_center().x, panel.position.y + 24.0), 22, TCGTheme.GOLD, true, true)
		TCGTheme.draw_text_centered(c, "Paste a share code below (Ctrl+V) and press Import.", Vector2(panel.get_center().x, panel.position.y + 60.0), 14, TCGTheme.DIM, false, true)
		var can_imp: bool = _import_edit != null and not _import_edit.text.strip_edges().is_empty()
		var imp_r := Rect2(panel.position.x + 24.0, panel.end.y - 50.0, 120.0, 34.0)
		TCGTheme.draw_plaque(c, imp_r, "Import", TCGTheme.GREEN, _is_hov("do_import"), not can_imp, false)

	if msg_t > 0.0 and not msg.is_empty():
		TCGTheme.draw_text_centered(c, msg, Vector2(panel.get_center().x, panel.end.y - 76.0), 15, TCGTheme.GREEN if msg_ok else TCGTheme.RED, true, true)

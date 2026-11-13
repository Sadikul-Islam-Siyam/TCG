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
const TABS: Array[String] = ["All", "Event", "Support", "Weapon", "Artifact", "Talent", "Resonance"]
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
	_name_edit.position = Vector2(130, 10)
	_name_edit.size = Vector2(230, 32)
	_name_edit.max_length = 24
	_name_edit.placeholder_text = "Deck name"
	_name_edit.text = deck_name
	_style_line_edit(_name_edit)
	_name_edit.text_changed.connect(func(t: String) -> void:
		deck_name = t
	)
	add_child(_name_edit)

	_search_edit = LineEdit.new()
	_search_edit.position = Vector2(660, 100)
	_search_edit.size = Vector2(240, 28)
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
	_import_edit.position = Vector2(364, 210)
	_import_edit.size = Vector2(552, 34)
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


func _process(delta: float) -> void:
	if msg_t > 0.0:
		msg_t = maxf(0.0, msg_t - delta)
		if msg_t == 0.0:
			_ui_redraw()


# ------------------------------------------------------------------------------
# State Helpers
# ------------------------------------------------------------------------------
static func tab_of(cd: CardDataSystem.CardData) -> String:
	return "Resonance" if not cd.resonance.is_empty() else cd.kind.capitalize()


static func total_cost(cd: CardDataSystem.CardData) -> int:
	return cd.cost.n + cd.cost.unaligned


static func requirement(cd: CardDataSystem.CardData) -> String:
	if cd.kind == "talent":
		return "Talent: requires %s in the deck" % cd.char_name
	if cd.kind == "weapon":
		return "Weapon: requires a %s user in the deck" % cd.weapon
	if not cd.resonance.is_empty():
		return "Resonance: requires 2 %s characters" % cd.resonance
	return "%s: usable in any deck" % cd.kind.capitalize()


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
		say("Deck already has 30 cards", false)
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
			if not modal.is_empty():
				if str(modal.get("kind", "")) == "load":
					modal_scroll = maxi(0, modal_scroll + delta_s)
					_ui_redraw()
			elif event.position.x > 910.0:
				scroll = maxi(0, scroll + delta_s)
				_ui_redraw()
			elif event.position.x > 310.0:
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
	var w: float = maxf(size.x, float(TCGTheme.W))
	var h: float = maxf(size.y, float(TCGTheme.H))
	TCGArt.draw_mat(self, Vector2(w, h))
	draw_rect(Rect2(0, 0, w, h), Color(0.03, 0.05, 0.09, 0.45))

	var in_modal: bool = not modal.is_empty()

	# Top Bar
	var back_r := Rect2(20.0, 10.0, 96.0, 32.0)
	TCGTheme.draw_plaque(self, back_r, "< Back", TCGTheme.DIM, _is_hov("back"), false, in_modal)
	_hit_boxes.append({"rect": back_r, "key": "back", "enabled": not in_modal})

	var top_buttons: Array = [
		["Save", "save", TCGTheme.GREEN, 84.0],
		["Load", "load", TCGTheme.TEAL, 84.0],
		["Auto-fill", "fill", TCGTheme.GOLD, 100.0],
		["Share", "share", TCGTheme.TEAL, 84.0],
		["Import", "import", TCGTheme.TEAL, 84.0],
		["Clear", "clear", TCGTheme.RED, 84.0],
	]
	var tx: float = 372.0
	for tb in top_buttons:
		var bw: float = float(tb[3])
		var br := Rect2(tx, 10.0, bw, 32.0)
		var bkey: String = str(tb[1])
		TCGTheme.draw_plaque(self, br, str(tb[0]), tb[2], _is_hov(bkey), false, in_modal)
		_hit_boxes.append({"rect": br, "key": bkey, "enabled": not in_modal})
		tx += bw + 8.0

	_draw_left(in_modal)
	_draw_center(in_modal)
	_draw_right(in_modal)

	# Large Hover Card Preview
	if not hover_card.is_empty() and not in_modal:
		var preview_x: float = 320.0 if get_local_mouse_position().x > 910.0 else 946.0
		var preview_r := Rect2(preview_x, 70.0, 210.0, 308.0)
		TCGActionCardView.draw_card_surface(self, preview_r, hover_card, false, true, true, true)

	if in_modal:
		_register_modal_hitboxes()
		if _modal_layer != null:
			_modal_layer.queue_redraw()


func _draw_left(in_modal: bool) -> void:
	TCGTheme.draw_text_pos(self, "Characters %d/3" % chars.size(), Vector2(20.0, 70.0), 17, TCGTheme.GOLD, true, true)
	for i in range(3):
		var r := Rect2(20.0 + float(i) * 94.0, 98.0, 88.0, 112.0)
		if i < chars.size():
			var cname: String = chars[i]
			var pr := Rect2(r.position.x, r.position.y, r.size.x, r.size.y - 22.0)
			_draw_mini_char(pr, cname, true, false)
			TCGTheme.draw_text_centered(self, cname, Vector2(r.get_center().x, r.end.y - 9.0), 13, TCGTheme.TEXT, true, true)
			_hit_boxes.append({"rect": pr, "key": ["char", cname], "enabled": not in_modal})
		else:
			TCGTheme.draw_rounded_box(self, r, Color8(24, 30, 48), Color8(60, 70, 98), 8, 2)
			TCGTheme.draw_text_centered(self, "empty", r.get_center(), 14, TCGTheme.DIM, false, true)

	TCGTheme.draw_text_pos(self, "Roster (click to add / remove)", Vector2(20.0, 226.0), 14, TCGTheme.DIM, false, true)
	var roster: PackedStringArray = CardDataSystem.roster
	for k in range(roster.size()):
		var cname: String = roster[k]
		var r := Rect2(20.0 + float(k % 5) * 56.0, 248.0 + float(k / 5) * 72.0, 52.0, 64.0)
		var picked: bool = chars.has(cname)
		_draw_mini_char(r, cname, picked, not picked and chars.size() >= 3)
		TCGTheme.draw_text_centered(self, cname.substr(0, 7), Vector2(r.get_center().x, r.end.y - 8.0), 11, TCGTheme.TEXT, true, true)
		_hit_boxes.append({"rect": r, "key": ["char", cname], "enabled": not in_modal})

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

	TCGTheme.draw_text_pos(self, "Composition", Vector2(20.0, 402.0), 15, TCGTheme.GOLD, true, true)
	var comp_parts: Array[String] = []
	var k_keys: Array = kinds.keys()
	k_keys.sort()
	for kk in k_keys:
		comp_parts.append("%s %d" % [str(kk), int(kinds[kk])])
	var comp_line: String = "  ".join(comp_parts) if not comp_parts.is_empty() else "no cards yet"
	TCGTheme.draw_wrapped(self, comp_line, Rect2(20.0, 424.0, 270.0, 40.0), 13, TCGTheme.DIM, 16, false)

	TCGTheme.draw_text_pos(self, "Cost curve", Vector2(20.0, 470.0), 15, TCGTheme.GOLD, true, true)
	var peak: int = 1
	for c in range(5):
		peak = maxi(peak, int(curve[c]))
	for c in range(5):
		var cnt: int = int(curve[c])
		var bar_h: float = (70.0 * float(cnt) / float(peak)) if cnt > 0 else 0.0
		var br := Rect2(26.0 + float(c) * 52.0, 546.0 - bar_h, 38.0, bar_h)
		if bar_h > 0.0:
			TCGTheme.draw_rounded_box(self, br, TCGTheme.TEAL, Color(0, 0, 0, 0), 4, 0)
		TCGTheme.draw_text_centered(self, str(cnt), Vector2(26.0 + float(c) * 52.0 + 19.0, br.position.y - 8.0), 13, TCGTheme.TEXT, true, true)
		TCGTheme.draw_text_centered(self, "4+" if c == 4 else str(c), Vector2(26.0 + float(c) * 52.0 + 19.0, 558.0), 13, TCGTheme.DIM, false, true)

	var val: Dictionary = validation()
	var msgs: Array = val["messages"]
	var ok: bool = bool(val["ok"])
	TCGTheme.draw_text_pos(self, "Status", Vector2(20.0, 584.0), 15, TCGTheme.GOLD, true, true)
	var msg_joined: Array[String] = []
	for m_i in range(mini(4, msgs.size())):
		msg_joined.append(str(msgs[m_i]))
	TCGTheme.draw_wrapped(self, "\n".join(msg_joined), Rect2(20.0, 606.0, 270.0, 96.0), 13, TCGTheme.GREEN if ok else TCGTheme.RED, 16, false)


func _draw_center(in_modal: bool) -> void:
	var tx: float = 320.0
	for t in TABS:
		var w: float = 76.0 if t != "Resonance" else 92.0
		var r := Rect2(tx, 64.0, w, 28.0)
		var tkey := ["tab", t]
		TCGTheme.draw_plaque(self, r, t, TCGTheme.TEAL, _is_hov(tkey) or (tab == t), in_modal, true)
		_hit_boxes.append({"rect": r, "key": tkey, "enabled": not in_modal})
		tx += w + 5.0

	var el_r := Rect2(320.0, 100.0, 104.0, 28.0)
	var el_label: String = element_filter if not element_filter.is_empty() else "Element: any"
	var el_col: Color = TCGTheme.elem_color(element_filter) if not element_filter.is_empty() else TCGTheme.DIM
	TCGTheme.draw_plaque(self, el_r, el_label, el_col, _is_hov("element"), in_modal, true)
	_hit_boxes.append({"rect": el_r, "key": "element", "enabled": not in_modal})

	var cost_r := Rect2(430.0, 100.0, 96.0, 28.0)
	var cost_label: String = "Cost: any" if cost_filter < 0 else ("Cost: %d%s" % [cost_filter, "+" if cost_filter == 4 else ""])
	TCGTheme.draw_plaque(self, cost_r, cost_label, TCGTheme.DIM, _is_hov("costf"), in_modal, true)
	_hit_boxes.append({"rect": cost_r, "key": "costf", "enabled": not in_modal})

	var allow_r := Rect2(532.0, 100.0, 120.0, 28.0)
	var allow_label: String = "Fits deck only" if allowed_only else "Show all"
	TCGTheme.draw_plaque(self, allow_r, allow_label, TCGTheme.GOLD, _is_hov("allowed") or allowed_only, in_modal, true)
	_hit_boxes.append({"rect": allow_r, "key": "allowed", "enabled": not in_modal})

	var names: Array[String] = visible_cards()
	var per_page: int = COLS * ROWS
	var pages: int = maxi(1, ceili(float(names.size()) / float(per_page)))
	page = mini(page, pages - 1)
	var start_i: int = page * per_page
	var end_i: int = mini(names.size(), start_i + per_page)

	if names.is_empty():
		TCGTheme.draw_text_centered(self, "No cards match. Pick characters, or switch to 'Show all'.", Vector2(620.0, 300.0), 16, TCGTheme.DIM, false, true)
	else:
		for i in range(end_i - start_i):
			var n: String = names[start_i + i]
			var r := Rect2(322.0 + float(i % COLS) * 114.0, 142.0 + float(i / COLS) * 148.0, CARD_W, CARD_H)
			var cnt: int = int(counts.get(n, 0))
			var ok: bool = allowed(n) and cnt < TCGDeckSystem.MAX_COPIES
			var ckey := ["card", n]
			TCGActionCardView.draw_card_surface(self, r, n, cnt > 0, _is_hov(ckey), ok, false)
			if cnt > 0:
				var bc := Vector2(r.end.x - 4.0, r.position.y + 4.0)
				draw_circle(bc, 14.0, Color8(20, 24, 38))
				draw_arc(bc, 14.0, 0.0, TAU, 24, TCGTheme.GOLD, 2.0)
				TCGTheme.draw_text_centered(self, "x%d" % cnt, bc, 14, TCGTheme.GOLD, true, false)
			_hit_boxes.append({"rect": r, "key": ckey, "enabled": not in_modal})

	var prev_r := Rect2(320.0, 596.0, 80.0, 28.0)
	var next_r := Rect2(820.0, 596.0, 80.0, 28.0)
	TCGTheme.draw_plaque(self, prev_r, "< Prev", TCGTheme.DIM, _is_hov("prev"), in_modal or page <= 0, true)
	TCGTheme.draw_text_centered(self, "Page %d/%d   (%d cards)" % [page + 1, pages, names.size()], Vector2(610.0, 610.0), 14, TCGTheme.DIM, false, true)
	TCGTheme.draw_plaque(self, next_r, "Next >", TCGTheme.DIM, _is_hov("next"), in_modal or page >= pages - 1, true)
	_hit_boxes.append({"rect": prev_r, "key": "prev", "enabled": not in_modal and page > 0})
	_hit_boxes.append({"rect": next_r, "key": "next", "enabled": not in_modal and page < pages - 1})

	var info := Rect2(320.0, 636.0, 580.0, 64.0)
	TCGTheme.draw_rounded_box(self, info, TCGTheme.PANEL, Color(0, 0, 0, 0), 8, 0)
	if msg_t > 0.0:
		TCGTheme.draw_text_centered(self, msg, info.get_center(), 16, TCGTheme.GREEN if msg_ok else TCGTheme.GOLD, true, true)
	elif not hover_card.is_empty():
		var cd: CardDataSystem.CardData = CardDataSystem.get_card_def(hover_card)
		if cd != null:
			TCGTheme.draw_text_pos(self, cd.name, Vector2(info.position.x + 12.0, info.position.y + 8.0), 17, TCGTheme.GOLD, true, true)
			var pairs := TCGActionCardView.cost_to_pairs(cd.cost)
			for p_i in range(pairs.size()):
				TCGArt.draw_cost_gem(self, str(pairs[p_i][0]), int(pairs[p_i][1]), Vector2(info.position.x + 24.0 + float(p_i) * 24.0, info.position.y + 44.0), 10.0)
			TCGTheme.draw_text_pos(self, requirement(cd), Vector2(info.position.x + 120.0, info.position.y + 36.0), 14, TCGTheme.TEXT, false, true)
	else:
		TCGTheme.draw_text_centered(self, "Left click: add a copy    Right click: remove    Wheel: change page", info.get_center(), 14, TCGTheme.DIM, false, true)


func _draw_right(in_modal: bool) -> void:
	var n_total: int = total()
	TCGTheme.draw_rounded_box(self, Rect2(920.0, 62.0, 340.0, 640.0), TCGTheme.PANEL, Color(0, 0, 0, 0), 10, 0)
	TCGTheme.draw_text_pos(self, "Deck  %d/30" % n_total, Vector2(936.0, 70.0), 20, TCGTheme.GREEN if n_total == 30 else TCGTheme.GOLD, true, true)

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

	var per: int = 25
	scroll = clampi(scroll, 0, maxi(0, rows.size() - per))
	var end_r: int = mini(rows.size(), scroll + per)
	for i in range(end_r - scroll):
		var row: Array = rows[scroll + i]
		var tc: int = int(row[0])
		var cname: String = str(row[1])
		var cnt: int = int(row[2])
		var r := Rect2(930.0, 102.0 + float(i) * 23.0, 320.0, 21.0)
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
		TCGTheme.draw_text_centered(self, str(tc), Vector2(r.position.x + 12.0, r.get_center().y), 13, TCGTheme.GOLD, true, false)
		TCGTheme.draw_text_pos(self, cname, Vector2(r.position.x + 30.0, r.position.y + 3.0), 14, TCGTheme.TEXT, false, false)
		TCGTheme.draw_text_pos(self, "x%d" % cnt, Vector2(r.end.x - 28.0, r.position.y + 3.0), 14, TCGTheme.GOLD, true, false)
		_hit_boxes.append({"rect": r, "key": ["row", cname], "enabled": not in_modal})

	if rows.is_empty():
		TCGTheme.draw_text_centered(self, "Click cards to add them", Vector2(1090.0, 300.0), 15, TCGTheme.DIM, false, true)
	elif rows.size() > per:
		TCGTheme.draw_text_centered(self, "scroll for more (%d)" % (rows.size() - per), Vector2(1090.0, 686.0), 12, TCGTheme.DIM, false, true)


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
	var panel := Rect2(340.0, 110.0, 600.0, 500.0)
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
			var r := Rect2(panel.position.x + 20.0, panel.position.y + 56.0 + float(i) * 31.0, 480.0, 28.0)
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
	var c: CanvasItem = _modal_layer
	c.draw_rect(Rect2(0, 0, maxf(size.x, float(TCGTheme.W)), maxf(size.y, float(TCGTheme.H))), Color(0, 0, 0, 0.74))
	var panel := Rect2(340.0, 110.0, 600.0, 500.0)
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

class_name DetailDrawer
extends Control
## Phase 9 (T9.1-T9.6): Left Slide-In Detail & Glossary Drawer.
## Anchored on the left (~19% width, ~11%-85% height within safe area), closes on outside
## click, × button, or Escape. Supports collapsible sections, custom scrollbar, clickable
## RichTextLabel keyword/element/reaction links, and stacked keyword glossary drilldown (<=3).

signal drawer_closed

const MAX_STACK_DEPTH := 3

var _is_open: bool = false
var _stack: Array[Dictionary] = []
var _collapsed_sections: Dictionary = {}
var _drawer_rect: Rect2 = Rect2(18, 120, 416, 790)
var outside_click_handler: Callable = Callable()

var _backdrop: ColorRect = null
var _panel: PanelContainer = null
var _header_title: Label = null
var _header_sub: Label = null
var _back_btn: Button = null
var _close_btn: Button = null
var _scroll: ScrollContainer = null
var _content_box: VBoxContainer = null
var _tween: Tween = null


func _init() -> void:
	name = "DetailDrawer"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build_ui()


func _build_ui() -> void:
	var app_theme := TCGTheme.build_app_theme()
	theme = app_theme

	# Fullscreen transparent click-catcher backdrop when open (T9.6)
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0.02, 0.04, 0.08, 0.22)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.gui_input.connect(_on_backdrop_input)
	add_child(_backdrop)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", TCGTheme.make_slate_panel_style(Color(0.06, 0.09, 0.15, 0.98), TCGTheme.GOLD, TCGTheme.GOLD_D, 14, 2))
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_panel.add_child(margin)

	var root_v := VBoxContainer.new()
	root_v.add_theme_constant_override("separation", 8)
	margin.add_child(root_v)

	# Header Row: [<-] Title [x]
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 6)
	root_v.add_child(hdr)

	_back_btn = Button.new()
	_back_btn.text = "◂ Back"
	_back_btn.custom_minimum_size = Vector2(64, 28)
	_back_btn.visible = false
	_back_btn.pressed.connect(_pop_stack)
	hdr.add_child(_back_btn)

	var title_v := VBoxContainer.new()
	title_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_v.add_theme_constant_override("separation", 1)
	hdr.add_child(title_v)

	_header_title = Label.new()
	_header_title.add_theme_font_size_override("font_size", 21)
	_header_title.add_theme_color_override("font_color", TCGTheme.GOLD_L)
	_header_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_v.add_child(_header_title)

	_header_sub = Label.new()
	_header_sub.add_theme_font_size_override("font_size", 13)
	_header_sub.add_theme_color_override("font_color", TCGTheme.DIM)
	title_v.add_child(_header_sub)

	_close_btn = Button.new()
	_close_btn.text = "×"
	_close_btn.custom_minimum_size = Vector2(30, 30)
	_close_btn.pressed.connect(close)
	hdr.add_child(_close_btn)

	var sep := HSeparator.new()
	root_v.add_child(sep)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_v.add_child(_scroll)

	_content_box = VBoxContainer.new()
	_content_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_box.add_theme_constant_override("separation", 10)
	_scroll.add_child(_content_box)


func sync_layout(viewport_size: Vector2) -> void:
	var safe := UIConstants.get_safe_rect(viewport_size)
	size = viewport_size
	if _backdrop != null:
		_backdrop.position = Vector2.ZERO
		_backdrop.size = viewport_size
	# T9.1: Left side ~19% width (clamped nicely for 4:3 -> 19.5:9), ~11%-85% vertical span
	var w := clampf(safe.size.x * 0.22, 340.0, 440.0)
	var top := safe.position.y + safe.size.y * 0.10
	var h := safe.size.y * 0.76
	_drawer_rect = Rect2(safe.position.x + 12.0, top, w, h)
	if _panel != null:
		_panel.size = _drawer_rect.size
		if _is_open and (_tween == null or not _tween.is_running()):
			_panel.position = _drawer_rect.position


func is_open() -> bool:
	return _is_open


func get_stack_depth() -> int:
	return _stack.size()


func get_drawer_rect() -> Rect2:
	return _drawer_rect


func open_character(ch: TCGPlayerSystem.CharacterInstance, owner_player: TCGPlayerSystem.PlayerState = null) -> void:
	if ch == null:
		return
	var entry := _build_character_entry(ch, owner_player)
	_open_root_entry(entry)


func open_card(card_name: String) -> void:
	if card_name.is_empty():
		return
	_open_root_entry(_build_card_entry(card_name))


func open_status(status_name: String, raw_desc: String = "", counters: int = -1, badge_kind: String = "Status") -> void:
	var g := GlossaryDB.lookup_term("status:" + status_name)
	var body := GlossaryDB.highlight_plain_text(raw_desc) if not raw_desc.is_empty() else String(g.get("body", status_name))
	var sections: Array = [{
		"id": "status_detail",
		"title": "Effect Details",
		"body": body,
		"meta": ("Remaining: %d" % counters) if counters >= 0 else "",
	}]
	_open_root_entry({
		"title": status_name,
		"sub": badge_kind.to_upper(),
		"sections": sections,
	})


func open_keyword(token: String) -> void:
	var g := GlossaryDB.lookup_term(token)
	var entry := {
		"title": String(g.get("title", token)),
		"sub": String(g.get("kind", "Glossary")).to_upper(),
		"sections": [{
			"id": "kw_" + token,
			"title": "Glossary Definition",
			"body": String(g.get("body", token)),
			"meta": "",
		}],
	}
	if not _is_open or _stack.is_empty():
		_open_root_entry(entry)
	else:
		_push_entry(entry)


func close_immediate() -> void:
	if _tween != null and _tween.is_running():
		_tween.kill()
	var was_open := _is_open
	_is_open = false
	_stack.clear()
	visible = false
	if was_open:
		drawer_closed.emit()


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	_stack.clear()
	if _tween != null and _tween.is_running():
		_tween.kill()
	if is_inside_tree():
		_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		_tween.tween_property(_panel, "position:x", -_drawer_rect.size.x - 24.0, 0.16)
		_tween.parallel().tween_property(_backdrop, "modulate:a", 0.0, 0.16)
		_tween.tween_callback(func() -> void:
			visible = false
		)
	else:
		visible = false
	drawer_closed.emit()


func _open_root_entry(entry: Dictionary) -> void:
	_stack.clear()
	_stack.append(entry)
	_render_top_entry()
	_animate_open()


func _push_entry(entry: Dictionary) -> void:
	# T9.5: Max nesting depth 3; replace top-most glossary if already at cap
	if _stack.size() >= MAX_STACK_DEPTH:
		_stack[_stack.size() - 1] = entry
	else:
		_stack.append(entry)
	_render_top_entry()


func _pop_stack() -> void:
	if _stack.size() <= 1:
		close()
		return
	_stack.pop_back()
	_render_top_entry()


func pop_or_close() -> void:
	if _stack.size() > 1:
		_pop_stack()
	else:
		close()


func _animate_open() -> void:
	visible = true
	_is_open = true
	sync_layout(get_viewport_rect().size if is_inside_tree() else size)
	if _panel == null:
		return
	if _tween != null and _tween.is_running():
		_tween.kill()
	if is_inside_tree():
		_panel.position = Vector2(-_drawer_rect.size.x - 20.0, _drawer_rect.position.y)
		_backdrop.modulate.a = 0.0
		_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_tween.tween_property(_panel, "position:x", _drawer_rect.position.x, 0.20)
		_tween.parallel().tween_property(_backdrop, "modulate:a", 1.0, 0.20)
	else:
		_panel.position = _drawer_rect.position


func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not Rect2(_panel.position, _panel.size).has_point(event.position):
			if outside_click_handler.is_valid():
				if bool(outside_click_handler.call(event.position)):
					if is_inside_tree() and get_viewport() != null:
						get_viewport().set_input_as_handled()
					return
			close()
			if is_inside_tree() and get_viewport() != null:
				get_viewport().set_input_as_handled()


func _render_top_entry() -> void:
	if _stack.is_empty():
		return
	var entry: Dictionary = _stack[_stack.size() - 1]
	_header_title.text = String(entry.get("title", "Details"))
	_header_sub.text = String(entry.get("sub", ""))
	_back_btn.visible = (_stack.size() > 1)
	if _scroll != null:
		_scroll.scroll_vertical = 0

	for c in _content_box.get_children():
		c.queue_free()

	var sections: Array = entry.get("sections", [])
	for sec in sections:
		_add_collapsible_section(sec)


func _add_collapsible_section(sec: Dictionary) -> void:
	var sec_id := String(sec.get("id", "sec"))
	var title := String(sec.get("title", "Section"))
	var body := String(sec.get("body", ""))
	var meta := String(sec.get("meta", ""))
	var default_open := bool(sec.get("open", true))
	var is_collapsed: bool = _collapsed_sections.get(sec_id, not default_open)

	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", TCGTheme.make_slate_panel_style(Color(0.08, 0.12, 0.20, 0.98), Color(0.75, 0.61, 0.31, 0.55), TCGTheme.GOLD_D, 10, 1))
	_content_box.add_child(box)

	var inner_m := MarginContainer.new()
	inner_m.add_theme_constant_override("margin_left", 10)
	inner_m.add_theme_constant_override("margin_right", 10)
	inner_m.add_theme_constant_override("margin_top", 8)
	inner_m.add_theme_constant_override("margin_bottom", 8)
	box.add_child(inner_m)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	inner_m.add_child(v)

	var hdr_btn := Button.new()
	hdr_btn.flat = true
	hdr_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	hdr_btn.text = "%s  %s" % ["▸" if is_collapsed else "▾", title]
	hdr_btn.add_theme_color_override("font_color", TCGTheme.GOLD_L)
	hdr_btn.add_theme_font_size_override("font_size", 16)
	v.add_child(hdr_btn)

	var body_wrap := VBoxContainer.new()
	body_wrap.visible = not is_collapsed
	body_wrap.add_theme_constant_override("separation", 4)
	v.add_child(body_wrap)

	if not meta.is_empty():
		var m_lbl := Label.new()
		m_lbl.text = meta
		m_lbl.add_theme_font_size_override("font_size", 13)
		m_lbl.add_theme_color_override("font_color", TCGTheme.TEAL)
		m_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body_wrap.add_child(m_lbl)

	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.scroll_active = false
	rtl.selection_enabled = false
	rtl.add_theme_font_size_override("normal_font_size", 15)
	rtl.add_theme_color_override("default_color", TCGTheme.TEXT)
	rtl.text = GlossaryDB.compile_bbcode(body)
	rtl.meta_clicked.connect(_on_meta_clicked)
	body_wrap.add_child(rtl)

	hdr_btn.pressed.connect(func() -> void:
		var now_coll := body_wrap.visible
		_collapsed_sections[sec_id] = now_coll
		body_wrap.visible = not now_coll
		hdr_btn.text = "%s  %s" % ["▸" if now_coll else "▾", title]
	)


func _on_meta_clicked(meta: Variant) -> void:
	open_keyword(String(meta))


func _build_character_entry(ch: TCGPlayerSystem.CharacterInstance, owner_p: TCGPlayerSystem.PlayerState) -> Dictionary:
	var d: CardDataSystem.CharData = ch.get_defn()
	if d == null:
		return {"title": ch.name, "sub": "CHARACTER", "sections": []}
	var sections: Array = []

	var aura_str := "None" if ch.aura.is_empty() else ch.aura
	var overview := "HP: {num:%d/%d}  ·  Energy: {num:%d/%d}  ·  Weapon: %s\nElement Aura: %s" % [
		ch.hp, d.hp, ch.energy, d.max_energy, d.weapon, aura_str
	]
	if d.element in ["Cryo", "Hydro", "Pyro", "Electro", "Anemo", "Geo"]:
		overview = ("{el:%s}  ·  " % d.element) + overview
	sections.append({
		"id": "char_overview",
		"title": "Overview",
		"body": overview,
		"meta": "",
		"open": true,
	})

	for idx in range(d.skills.size()):
		var sk: CardDataSystem.SkillData = d.skills[idx]
		sections.append({
			"id": "skill_%d" % idx,
			"title": "[%s] %s" % [sk.kind.to_upper(), sk.name],
			"body": sk.desc,
			"meta": "Cost: %s" % _cost_label(sk.cost),
			"open": true,
		})

	var eq_parts: Array[String] = []
	var wp := String(ch.equipment.get("weapon", ""))
	if not wp.is_empty():
		eq_parts.append("Weapon: {kw:%s} — %s" % [wp, _card_desc_or_name(wp)])
	var art := String(ch.equipment.get("artifact", ""))
	if not art.is_empty():
		eq_parts.append("Artifact: {kw:%s} — %s" % [art, _card_desc_or_name(art)])
	var tal := String(ch.equipment.get("talent", ""))
	if not tal.is_empty():
		eq_parts.append("Talent: {kw:%s} — %s" % [tal, _card_desc_or_name(tal)])
	if not eq_parts.is_empty():
		sections.append({
			"id": "char_equip",
			"title": "Equipment (%d)" % eq_parts.size(),
			"body": "\n".join(eq_parts),
			"meta": "",
			"open": true,
		})

	if not ch.statuses.is_empty():
		var st_lines: Array[String] = []
		for st in ch.statuses:
			var sname := String(st.name)
			var g := GlossaryDB.lookup_term("status:" + sname)
			var cnt := st.shield if st.shield > 0 else (st.usages if st.usages >= 0 else st.duration)
			var ctag := (" ({num:%d})" % cnt) if cnt >= 0 else ""
			var sdef := CardDataSystem.get_status_def(sname)
			var sdesc := GlossaryDB.highlight_plain_text(sdef.text) if (sdef != null and not sdef.text.is_empty()) else String(g.get("body", sname))
			st_lines.append("• %s%s — %s" % [sname, ctag, sdesc])
		sections.append({
			"id": "char_statuses",
			"title": "Character Statuses (%d)" % ch.statuses.size(),
			"body": "\n".join(st_lines),
			"meta": "",
			"open": true,
		})

	if owner_p != null and not owner_p.combat.is_empty():
		var cs_lines: Array[String] = []
		for cs in owner_p.combat:
			var cname := String(cs.name)
			var g := GlossaryDB.lookup_term("status:" + cname)
			var cnt := cs.shield if cs.shield > 0 else (cs.usages if cs.usages >= 0 else cs.duration)
			var ctag := (" ({num:%d})" % cnt) if cnt >= 0 else ""
			var sdef := CardDataSystem.get_status_def(cname)
			var sdesc := GlossaryDB.highlight_plain_text(sdef.text) if (sdef != null and not sdef.text.is_empty()) else String(g.get("body", cname))
			cs_lines.append("• %s%s — %s" % [cname, ctag, sdesc])
		sections.append({
			"id": "combat_statuses",
			"title": "Combat Statuses (%d)" % owner_p.combat.size(),
			"body": "\n".join(cs_lines),
			"meta": "",
			"open": true,
		})

	return {
		"title": d.name,
		"sub": "%s · %s" % [d.element.to_upper(), d.weapon.to_upper()],
		"sections": sections,
	}


func _build_card_entry(card_name: String) -> Dictionary:
	var cdef := CardDataSystem.get_card_def(card_name)
	if cdef == null:
		return {"title": card_name, "sub": "ACTION CARD", "sections": []}
	var tags: Array[String] = []
	if not cdef.weapon.is_empty():
		tags.append("Weapon: " + cdef.weapon)
	if not cdef.char_name.is_empty():
		tags.append("Character: " + cdef.char_name)
	if not cdef.resonance.is_empty():
		tags.append("Resonance: " + cdef.resonance)
	if cdef.usages >= 0:
		tags.append("Usages: %d" % cdef.usages)
	var sec_desc := {
		"id": "card_desc",
		"title": "Card Effect",
		"body": cdef.text,
		"meta": "Cost: %s  ·  Category: %s" % [_cost_label(cdef.cost), cdef.kind.capitalize()],
		"open": true,
	}
	var sections: Array = [sec_desc]
	if not tags.is_empty():
		sections.append({
			"id": "card_tags",
			"title": "Tags",
			"body": ", ".join(tags),
			"meta": "",
			"open": true,
		})
	return {
		"title": cdef.name,
		"sub": cdef.kind.to_upper(),
		"sections": sections,
	}


func _card_desc_or_name(card_name: String) -> String:
	var cdef := CardDataSystem.get_card_def(card_name)
	return cdef.text if (cdef != null and not cdef.text.is_empty()) else card_name


func _cost_label(c: CardDataSystem.CostData) -> String:
	if c == null:
		return "0 Dice"
	var parts: Array[String] = []
	if c.n > 0:
		var ename := c.element if not c.element.is_empty() else "Aligned"
		parts.append("%d %s" % [c.n, ename])
	if c.unaligned > 0:
		parts.append("%d Any" % c.unaligned)
	if c.energy > 0:
		parts.append("%d Energy" % c.energy)
	return "Free" if parts.is_empty() else " + ".join(parts)


func get_section_headers() -> Array[String]:
	var out: Array[String] = []
	if _stack.is_empty():
		return out
	var entry: Dictionary = _stack[_stack.size() - 1]
	for sec in entry.get("sections", []):
		out.append(String(sec.get("title", "")))
	return out

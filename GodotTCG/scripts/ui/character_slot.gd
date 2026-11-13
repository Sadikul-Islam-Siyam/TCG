class_name TCGCharacterSlot
extends Control
## Stage 6: Reusable Character Card Presentation & Interaction Component (120x190)
## Displays a character's portrait (real JPG or procedural fallback), HP badge,
## elemental crest, name plate, energy diamonds, frozen/petrified overlay,
## hit flash, lunge offset, and hoverable aura/equipment/status badges.

signal slot_clicked(side: int, char_index: int)
signal slot_hovered(side: int, char_index: int, is_hovering: bool)
signal status_icon_hovered(payload: Dictionary, is_hovering: bool)
signal status_icon_clicked(payload: Dictionary)

var side: int = 0
var char_index: int = 0
var char_state: TCGPlayerSystem.CharacterInstance = null
var is_active_char: bool = false
var is_clickable: bool = false
var is_selected_target: bool = false
var is_valid_target: bool = false
var hit_flash_alpha: float = 0.0
var lunge_offset: Vector2 = Vector2.ZERO
var shown_hp_override: int = -1
var _hovered: bool = false
var _hovered_icon_idx: int = -1
var _icon_rects: Array[Dictionary] = []  # {"rect": Rect2, "payload": Dictionary}


func _init() -> void:
	custom_minimum_size = Vector2(120, 190)
	size = Vector2(120, 190)
	mouse_filter = Control.MOUSE_FILTER_STOP


func setup(
	p_side: int,
	p_index: int,
	p_state: TCGPlayerSystem.CharacterInstance,
	p_active: bool,
	p_selected: bool = false,
	p_valid_target: bool = false,
	p_clickable: bool = false,
	p_shown_hp: int = -1,
	p_hit_flash: float = 0.0,
	p_lunge_offset: Vector2 = Vector2.ZERO
) -> void:
	side = p_side
	char_index = p_index
	char_state = p_state
	is_active_char = p_active
	is_selected_target = p_selected
	is_valid_target = p_valid_target
	is_clickable = p_clickable
	shown_hp_override = p_shown_hp
	hit_flash_alpha = p_hit_flash
	lunge_offset = p_lunge_offset
	queue_redraw()


func set_anim_state(p_hit_flash: float, p_lunge_offset: Vector2) -> void:
	if is_equal_approx(hit_flash_alpha, p_hit_flash) and lunge_offset.is_equal_approx(p_lunge_offset):
		return
	hit_flash_alpha = p_hit_flash
	lunge_offset = p_lunge_offset
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER:
		_hovered = true
		slot_hovered.emit(side, char_index, true)
		queue_redraw()
	elif what == NOTIFICATION_MOUSE_EXIT:
		_hovered = false
		if _hovered_icon_idx >= 0 and _hovered_icon_idx < _icon_rects.size():
			status_icon_hovered.emit(_icon_rects[_hovered_icon_idx]["payload"], false)
		_hovered_icon_idx = -1
		slot_hovered.emit(side, char_index, false)
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var found_idx: int = -1
		for idx in range(_icon_rects.size()):
			var entry: Dictionary = _icon_rects[idx]
			if (entry["rect"] as Rect2).has_point(event.position):
				found_idx = idx
				break
		if found_idx != _hovered_icon_idx:
			if _hovered_icon_idx >= 0 and _hovered_icon_idx < _icon_rects.size():
				status_icon_hovered.emit(_icon_rects[_hovered_icon_idx]["payload"], false)
			_hovered_icon_idx = found_idx
			if _hovered_icon_idx >= 0:
				status_icon_hovered.emit(_icon_rects[_hovered_icon_idx]["payload"], true)
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for entry in _icon_rects:
			if (entry["rect"] as Rect2).has_point(event.position):
				status_icon_clicked.emit(entry["payload"])
				return
		slot_clicked.emit(side, char_index)


func _draw() -> void:
	_icon_rects.clear()
	var shake_offset := Vector2(sin(hit_flash_alpha * 36.0) * hit_flash_alpha * 7.0, 0.0) if hit_flash_alpha > 0.01 else Vector2.ZERO
	var draw_pos := lunge_offset + shake_offset
	var r := Rect2(draw_pos, size)
	if char_state == null:
		TCGTheme.draw_gold_frame(self, r, TCGTheme.PANEL, 12, false)
		return

	var d: CardDataSystem.CharData = char_state.get_defn()
	if d == null:
		return
	var defeated: bool = char_state.defeated

	# Valid card/action target pulsing gold-green highlight
	if is_valid_target and not defeated:
		var tgt_rect := r.grow(6.0)
		TCGTheme.draw_rounded_box(
			self,
			tgt_rect,
			Color(0.5, 0.92, 0.62, 0.25),
			TCGTheme.GREEN if not _hovered else TCGTheme.GOLD_L,
			16,
			3
		)
	elif (is_active_char or is_clickable) and not defeated:
		var glow_col := TCGTheme.elem_color(d.element) if is_active_char else TCGTheme.GOLD
		var glow_rect := r.grow(4.0)
		TCGTheme.draw_rounded_box(
			self,
			glow_rect,
			Color(glow_col.r, glow_col.g, glow_col.b, 0.20),
			glow_col,
			15,
			2
		)

	var frame_fill := Color8(32, 34, 42) if defeated else TCGTheme.PANEL2
	TCGTheme.draw_gold_frame(
		self,
		r,
		frame_fill,
		12,
		is_active_char or _hovered or is_selected_target or is_valid_target or is_clickable
	)

	# Inner portrait art area
	var art_rect := Rect2(r.position.x + 6, r.position.y + 6, r.size.x - 12, r.size.y - 60)
	TCGArt.draw_portrait(self, char_state.name, d.element, art_rect, defeated)

	# Frozen / Petrified overlay matching PythonTCG ui/match.py:806-815
	var is_frozen: bool = TCGRulesEngine.has_status(char_state, "Frozen")
	var is_petrified: bool = TCGRulesEngine.has_status(char_state, "Petrified")
	if is_frozen or is_petrified:
		var ov_col := Color(0.67, 0.88, 1.0, 0.48) if is_frozen else Color(0.75, 0.63, 0.35, 0.52)
		draw_rect(art_rect, ov_col)
		var lbl := "FROZEN" if is_frozen else "PETRIFIED"
		TCGTheme.draw_text_centered(self, lbl, Vector2(r.get_center().x, art_rect.end.y - 12.0), 11, Color.WHITE, true, true)

	# Hit flash overlay
	if hit_flash_alpha > 0.01:
		draw_rect(art_rect, Color(1.0, 0.27, 0.24, clampf(hit_flash_alpha, 0.0, 0.75)))

	# Dark name banner across lower art
	var name_bar := Rect2(r.position.x + 6, r.position.y + r.size.y - 72, r.size.x - 12, 20)
	draw_rect(name_bar, Color(0.05, 0.08, 0.13, 0.85))
	draw_line(
		Vector2(r.position.x + 6, name_bar.position.y),
		Vector2(r.position.x + r.size.x - 6, name_bar.position.y),
		TCGTheme.GOLD_D,
		1.0
	)
	TCGTheme.draw_text_centered(
		self,
		char_state.name,
		name_bar.get_center(),
		13,
		TCGTheme.GOLD_L if is_active_char else TCGTheme.TEXT,
		true,
		true
	)

	# Energy row & label
	var e_bar := Rect2(r.position.x + 6, r.position.y + r.size.y - 52, r.size.x - 12, 22)
	draw_rect(e_bar, Color8(18, 28, 42))
	TCGTheme.draw_text_pos(self, "ENERGY", Vector2(r.position.x + 10, e_bar.position.y + 4), 10, TCGTheme.DIM, true, false)
	for k in range(d.max_energy):
		var ex: float = r.position.x + r.size.x - 16.0 - float(d.max_energy - 1 - k) * 15.0
		var ey: float = e_bar.get_center().y
		var filled: bool = k < char_state.energy
		var pts := PackedVector2Array([
			Vector2(ex, ey - 6),
			Vector2(ex + 5, ey),
			Vector2(ex, ey + 6),
			Vector2(ex - 5, ey),
		])
		draw_colored_polygon(pts, TCGTheme.GOLD_L if filled else Color8(40, 48, 62))
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, TCGTheme.GOLD if filled else TCGTheme.GOLD_D, 1.0)

	# Top-left HP badge
	var hp_c := Vector2(r.position.x + 20, r.position.y + 22)
	var hp_col := Color8(188, 52, 48) if not defeated else Color8(72, 74, 82)
	var disp_hp: int = shown_hp_override if shown_hp_override >= 0 else maxi(0, char_state.hp)
	draw_circle(hp_c, 15.0, Color8(24, 16, 20))
	draw_circle(hp_c, 13.0, hp_col)
	draw_arc(hp_c, 14.0, 0.0, TAU, 24, TCGTheme.GOLD_L, 2.0)
	TCGTheme.draw_text_centered(
		self,
		str(disp_hp),
		hp_c,
		14,
		Color.WHITE,
		true,
		true
	)

	# Top-right Elemental crest
	TCGArt.draw_elem_symbol(self, d.element, Vector2(r.position.x + r.size.x - 20, r.position.y + 20), 11.0)

	# Bottom status / aura / equipment bar (y = r.size.y - 26)
	var badge_y: float = r.position.y + r.size.y - 26.0
	var bx: float = r.position.x + 10.0

	# Elemental aura badge
	if not char_state.aura.is_empty():
		var aura_rect := Rect2(bx, badge_y, 18, 18)
		TCGArt.draw_elem_symbol(self, char_state.aura, Vector2(bx + 9, badge_y + 9), 8.0)
		_icon_rects.append({
			"rect": aura_rect.grow(3.0),
			"payload": {"kind": "aura", "aura": char_state.aura, "char_name": char_state.name}
		})
		bx += 22.0

	# Weapon / Artifact / Talent icons
	for eq_slot in ["weapon", "artifact", "talent"]:
		if char_state.equipment.has(eq_slot):
			var eq_rect := Rect2(bx, badge_y, 18, 18)
			var eq_kind: String = "weapon" if eq_slot == "weapon" else ("artifact" if eq_slot == "artifact" else "buff")
			TCGArt.draw_status_badge(self, eq_rect, eq_kind, d.element, 0)
			_icon_rects.append({
				"rect": eq_rect.grow(3.0),
				"payload": {"kind": "equip", "slot": eq_slot, "card_name": String(char_state.equipment[eq_slot])}
			})
			bx += 20.0

	# Character statuses (shields, freeze, buffs)
	for st in char_state.statuses:
		if bx + 18.0 > r.position.x + r.size.x - 6.0:
			break
		var sdef: CardDataSystem.StatusData = CardDataSystem.get_status_def(st.name)
		var kind := "buff"
		var elem := d.element
		if st.name == "Frozen" or st.name == "Petrified":
			kind = "freeze"
			elem = "Cryo" if st.name == "Frozen" else "Geo"
		elif st.shield > 0 or (sdef != null and sdef.shield > 0):
			kind = "shield"
		var count_val: int = st.shield if st.shield > 0 else maxi(0, st.usages)
		var st_rect := Rect2(bx, badge_y, 18, 18)
		TCGArt.draw_status_badge(self, st_rect, kind, elem, count_val)
		_icon_rects.append({
			"rect": st_rect.grow(3.0),
			"payload": {"kind": "status", "name": st.name, "status": st}
		})
		bx += 20.0

	# Defeated overlay banner
	if defeated:
		var ko_rect := Rect2(r.position.x + 8, r.position.y + r.size.y * 0.38, r.size.x - 16, 26)
		TCGTheme.draw_rounded_box(self, ko_rect, Color(0.08, 0.06, 0.08, 0.88), TCGTheme.RED, 6, 1)
		TCGTheme.draw_text_centered(self, "DEFEATED", ko_rect.get_center(), 12, TCGTheme.RED, true, true)

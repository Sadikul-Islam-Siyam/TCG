class_name TCGActionCardView
extends Control
## Phase 5 (T5.1, T5.5, T5.6, T5.10, T5.11): Action Card View.
## Supports cost gems, corner category emblem badge, unaffordable dim overlay,
## foil sheen sweep, 8px drag threshold, 0.45s long-press inspect, and unplayable shake.
## Never displays full card description on hover (User Rule #8/9).

signal card_clicked(card_name: String, hand_index: int)
signal card_right_clicked(card_name: String, hand_index: int)
signal card_drag_started(card_name: String, hand_index: int, global_pos: Vector2)
signal card_hovered(card_name: String, hand_index: int, is_hovering: bool)
signal card_long_pressed(card_name: String, hand_index: int)

var card_name: String = ""
var hand_index: int = -1
var selected: bool = false
var swap_marked: bool = false
var playable: bool = true
var dim_unusable: bool = false
var hidden_back: bool = false
var large_mode: bool = false
var interaction_locked: bool = false

var _hovered: bool = false
var _pressing: bool = false
var _press_pos: Vector2 = Vector2.ZERO
var _press_time: float = 0.0
var _long_fired: bool = false
var _shake_timer: float = 0.0
var _sheen_t: float = -1.0


func _init() -> void:
	custom_minimum_size = Vector2(96, 136)
	size = Vector2(146, 207)
	mouse_filter = Control.MOUSE_FILTER_STOP


func setup(
	p_card_name: String,
	p_hand_idx: int = -1,
	p_selected: bool = false,
	p_playable: bool = true,
	p_swap_marked: bool = false,
	p_hidden_back: bool = false,
	p_large: bool = false,
	p_dim_unusable: bool = false
) -> void:
	card_name = p_card_name
	hand_index = p_hand_idx
	selected = p_selected
	playable = p_playable
	swap_marked = p_swap_marked
	hidden_back = p_hidden_back
	large_mode = p_large
	dim_unusable = p_dim_unusable
	queue_redraw()


func trigger_unplayable_shake() -> void:
	_shake_timer = 0.28
	queue_redraw()


func _process(delta: float) -> void:
	var dirty := false
	if _shake_timer > 0.0:
		_shake_timer = maxf(0.0, _shake_timer - delta)
		dirty = true
	if _hovered and not hidden_back:
		if _sheen_t < 0.0:
			_sheen_t = 0.0
		_sheen_t = fmod(_sheen_t + delta * 0.9, 1.6)
		dirty = true
	elif _sheen_t >= 0.0:
		_sheen_t = -1.0
		dirty = true
	if _pressing and not _long_fired and not interaction_locked:
		_press_time += delta
		if _press_time >= 0.45:
			_long_fired = true
			_pressing = false
			card_long_pressed.emit(card_name, hand_index)
	if dirty:
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER:
		if interaction_locked:
			return
		_hovered = true
		_sheen_t = 0.0
		card_hovered.emit(card_name, hand_index, true)
		queue_redraw()
	elif what == NOTIFICATION_MOUSE_EXIT:
		if _pressing and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and playable and not hidden_back and not interaction_locked:
			_pressing = false
			card_drag_started.emit(card_name, hand_index, get_global_mouse_position())
			return
		_hovered = false
		_pressing = false
		card_hovered.emit(card_name, hand_index, false)
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_pressing = true
				_long_fired = false
				_press_time = 0.0
				_press_pos = mb.position
				accept_event()
			else:
				if _pressing:
					_pressing = false
					if not _long_fired:
						card_clicked.emit(card_name, hand_index)
					accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			card_right_clicked.emit(card_name, hand_index)
			accept_event()
	elif event is InputEventMouseMotion and _pressing and not interaction_locked:
		if (event as InputEventMouseMotion).position.distance_to(_press_pos) > 8.0:
			_pressing = false
			if playable and not hidden_back:
				card_drag_started.emit(card_name, hand_index, get_global_mouse_position())
				accept_event()


static func cost_to_pairs(c: CardDataSystem.CostData) -> Array:
	var out: Array = []
	if c == null:
		return out
	if c.n > 0:
		var elem_name: String = c.element
		if elem_name.is_empty():
			elem_name = "Same"
		out.append([elem_name, c.n])
	if c.unaligned > 0:
		out.append(["Any", c.unaligned])
	if c.energy > 0:
		out.append(["Energy", c.energy])
	return out


static func draw_card_surface(
	canvas: CanvasItem,
	r: Rect2,
	p_card_name: String,
	p_selected: bool = false,
	p_hovered: bool = false,
	p_playable: bool = true,
	p_large: bool = false,
	p_swap_marked: bool = false,
	p_hidden_back: bool = false,
	p_dim_unusable: bool = false,
	p_sheen_t: float = -1.0
) -> void:
	if p_hidden_back:
		TCGArt.draw_card_back(canvas, r)
		return

	var cd: CardDataSystem.CardData = CardDataSystem.get_card_def(p_card_name)
	if cd == null:
		TCGArt.draw_card_back(canvas, r)
		return

	var accent := TCGTheme.GOLD
	if not cd.resonance.is_empty():
		accent = ElementDB.get_color(cd.resonance)
	elif p_playable:
		accent = TCGTheme.GOLD_L

	if (p_playable and (p_selected or p_hovered)) or p_swap_marked:
		var glow_col := TCGTheme.RED if p_swap_marked else Color8(255, 210, 110)
		TCGTheme.draw_rounded_box(
			canvas,
			r.grow(3.5),
			Color(glow_col.r, glow_col.g, glow_col.b, 0.25),
			glow_col,
			12,
			2
		)

	TCGArt.draw_card_parchment(canvas, r, accent, p_selected, p_hovered)

	var ox: float = r.position.x
	var oy: float = r.position.y
	var w: float = r.size.x
	var h: float = r.size.y

	var compact: bool = (not p_large and h < 120.0)
	var art_h: float = 128.0 if p_large else (40.0 if compact else roundf(h * 0.44))
	var art_r := Rect2(ox + 7, oy + 7, w - 14, art_h)
	var cat_col := Color8(48, 72, 104)
	if cd.kind == "weapon":
		cat_col = Color8(92, 52, 46)
	elif cd.kind == "artifact":
		cat_col = Color8(92, 74, 38)
	elif cd.kind == "support":
		cat_col = Color8(44, 78, 86)
	elif cd.kind == "talent":
		cat_col = Color8(68, 48, 88)
	if not cd.resonance.is_empty():
		cat_col = ElementDB.get_dark_color(cd.resonance)

	TCGTheme.draw_rounded_box(canvas, art_r, cat_col, TCGTheme.GOLD_D, 7, 1)

	# Category / Element Emblem
	var ac := art_r.get_center()
	var rad: float = 32.0 if p_large else (14.0 if compact else 24.0)
	if not cd.resonance.is_empty():
		TCGArt.draw_elem_symbol(canvas, cd.resonance, ac, rad)
	elif cd.kind == "weapon":
		TCGArt.draw_status_badge(canvas, Rect2(ac.x - rad, ac.y - rad, rad * 2, rad * 2), "weapon", "Physical", 0)
	elif cd.kind == "artifact":
		TCGArt.draw_status_badge(canvas, Rect2(ac.x - rad, ac.y - rad, rad * 2, rad * 2), "artifact", "Geo", 0)
	elif cd.kind == "talent" and not cd.char_name.is_empty():
		var ch_d := CardDataSystem.get_char_def(cd.char_name)
		var el := ch_d.element if ch_d != null else "Omni"
		TCGArt.draw_elem_symbol(canvas, el, ac, rad)
	else:
		TCGArt.draw_elem_symbol(canvas, "Omni", ac, rad * 0.9)

	# Cost gems stacked top-left
	var gem_r: float = 15.0 if p_large else (8.0 if compact else 13.0)
	var gem_step: float = 31.0 if p_large else (16.0 if compact else 27.0)
	var cy: float = oy + 8.0 + gem_r
	var cost_pairs: Array = cost_to_pairs(cd.cost)
	if cost_pairs.is_empty():
		TCGArt.draw_cost_gem(canvas, "Same", 0, Vector2(ox + 8.0 + gem_r, cy), gem_r)
	else:
		for pair in cost_pairs:
			TCGArt.draw_cost_gem(canvas, String(pair[0]), int(pair[1]), Vector2(ox + 8.0 + gem_r, cy), gem_r)
			cy += gem_step

	# Support usages badge OR small subtype tag top-right (T5.1)
	if cd.usages > 0 and not compact:
		var ub_r: float = 13.0 if p_large else 11.5
		var ub_c := Vector2(ox + w - (ub_r + 8.0), oy + (ub_r + 8.0))
		canvas.draw_circle(ub_c, ub_r, Color8(24, 34, 48))
		canvas.draw_arc(ub_c, ub_r, 0.0, TAU, 16, TCGTheme.GOLD, 1.5)
		TCGTheme.draw_text_centered(canvas, str(cd.usages), ub_c, 14 if p_large else 12, TCGTheme.GOLD_L, true, false)
	elif cd.kind in ["weapon", "artifact", "talent"] and not compact:
		var tag_s := "WPN" if cd.kind == "weapon" else ("ART" if cd.kind == "artifact" else "TLN")
		var tr := Rect2(ox + w - 40.0, oy + 9.0, 32.0, 18.0)
		TCGTheme.draw_rounded_box(canvas, tr, Color(0.08, 0.11, 0.16, 0.90), TCGTheme.GOLD_D, 4, 1)
		TCGTheme.draw_text_centered(canvas, tag_s, tr.get_center(), 10, TCGTheme.GOLD_L, true, false)

	# Category / subtype banner
	var cat_y: float = art_r.end.y + 4.0
	var cat_txt: String = "RESONANCE" if not cd.resonance.is_empty() else cd.kind.to_upper()
	if not cd.weapon.is_empty():
		cat_txt += " · " + cd.weapon.to_upper()
	elif not cd.char_name.is_empty():
		cat_txt += " · " + cd.char_name.to_upper()
	if not compact:
		TCGTheme.draw_text_centered(
			canvas,
			cat_txt,
			Vector2(ox + w * 0.5, cat_y + 8.0),
			13 if p_large else 11,
			TCGTheme.GOLD_D,
			true,
			false
		)

	# Card Name
	var disp_title: String = cd.name.replace("Elemental Resonance: ", "") if not p_large else cd.name
	var name_rect := Rect2(ox + 8, cat_y + (2.0 if compact else 20.0), w - 16, 28 if compact else (54 if not p_large else 46))
	TCGTheme.draw_wrapped(
		canvas,
		disp_title,
		name_rect,
		17 if p_large else (9 if compact else 14),
		TCGTheme.INK,
		21 if p_large else (11 if compact else 17),
		false
	)

	if p_large:
		var desc_rect := Rect2(ox + 12, name_rect.end.y + 6.0, w - 24, oy + h - name_rect.end.y - 12.0)
		canvas.draw_line(
			Vector2(ox + 12, name_rect.end.y),
			Vector2(ox + w - 12, name_rect.end.y),
			TCGTheme.PARCH_D,
			1.0
		)
		TCGTheme.draw_wrapped(canvas, cd.text, desc_rect, 14, Color8(62, 52, 42), 18, false)

	# Diagonal foil sheen sweep on high-rarity / hovered card (T5.11)
	if p_sheen_t >= 0.0 and p_sheen_t <= 1.0:
		var sx: float = ox + lerpf(-20.0, w + 20.0, p_sheen_t)
		var sheen_pts := PackedVector2Array([
			Vector2(clampf(sx, ox + 4, ox + w - 4), oy + 4),
			Vector2(clampf(sx + 18.0, ox + 4, ox + w - 4), oy + 4),
			Vector2(clampf(sx - 18.0, ox + 4, ox + w - 4), oy + h - 4),
			Vector2(clampf(sx - 36.0, ox + 4, ox + w - 4), oy + h - 4),
		])
		canvas.draw_colored_polygon(sheen_pts, Color(1.0, 0.96, 0.80, 0.16))

	# Unaffordable dim veil (T5.10)
	if p_dim_unusable and not p_selected and not p_swap_marked:
		TCGTheme.draw_rounded_box(canvas, r, Color(0.05, 0.07, 0.11, 0.46), Color(0, 0, 0, 0), 10, 0)


func _draw() -> void:
	var shake_x: float = sin(_shake_timer * 56.0) * 7.0 * (_shake_timer / 0.28) if _shake_timer > 0.0 else 0.0
	draw_card_surface(
		self,
		Rect2(Vector2(shake_x, 0.0), size),
		card_name,
		selected,
		_hovered,
		playable,
		large_mode,
		swap_marked,
		hidden_back,
		dim_unusable or not playable,
		_sheen_t if (card_name != "" and (_hovered or selected)) else -1.0
	)

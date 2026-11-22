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
var _foil_mat: ShaderMaterial = null

const FOIL_SHADER_RES: Shader = preload("res://shaders/card_foil.gdshader")


func _init() -> void:
	custom_minimum_size = Vector2(96, 136)
	size = Vector2(146, 207)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if FOIL_SHADER_RES != null:
		_foil_mat = ShaderMaterial.new()
		_foil_mat.shader = FOIL_SHADER_RES
		material = _foil_mat


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
		_sheen_t = fmod(_sheen_t + delta * 0.72, 1.8)
		dirty = true
	elif _sheen_t >= 0.0:
		_sheen_t = -1.0
		dirty = true
	if _foil_mat != null:
		var active_foil := (_hovered or selected) and not hidden_back
		_foil_mat.set_shader_parameter("sheen_pos", lerpf(-0.3, 1.3, clampf(_sheen_t, 0.0, 1.0)) if active_foil and _sheen_t >= 0.0 else -0.5)
		_foil_mat.set_shader_parameter("sheen_strength", 0.22 if active_foil and _sheen_t >= 0.0 else 0.0)
		_foil_mat.set_shader_parameter("brightness_boost", 0.06 if active_foil else 0.0)
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
		if _pressing and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not hidden_back and not interaction_locked:
			_pressing = false
			var drag_pos: Vector2 = get_global_mouse_position() if is_inside_tree() else (global_position + size * 0.5)
			card_drag_started.emit(card_name, hand_index, drag_pos)
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
		var mm := event as InputEventMouseMotion
		if mm.position.distance_to(_press_pos) > 8.0:
			_pressing = false
			if not hidden_back:
				var drag_pos: Vector2 = get_global_mouse_position() if is_inside_tree() else (global_position + mm.position)
				card_drag_started.emit(card_name, hand_index, drag_pos)
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
	var card_tex: Texture2D = TCGArt.get_card_texture(cd.name)
	var is_full_portrait_art: bool = (
		not p_large
		and card_tex != null
		and card_tex.get_height() > card_tex.get_width()
	)
	var role_name: String = CardDataSystem.infer_card_role(cd)
	var is_heal_card: bool = (role_name == "heal")
	if not is_heal_card:
		for st in cd.play_steps:
			if st.op in ["heal", "heal_most_injured", "heal_all", "heal_dual"]:
				is_heal_card = true
				break

	var art_h: float = roundf(h * 0.54) if (p_large and card_tex != null and card_tex.get_height() > card_tex.get_width()) else (128.0 if p_large else (40.0 if compact else roundf(h * 0.44)))
	var art_r := Rect2(ox + 7, oy + 7, w - 14, art_h)

	if is_full_portrait_art:
		# Full-bleed vertical TCG art inside the gold card frame (matches 896x1200 portrait illustrations)
		var full_r := r.grow(-5.0)
		TCGArt.draw_texture_cover(canvas, card_tex, full_r, Color.WHITE, 0.48)
		# Subtle inner gold border over full-bleed art
		var frame_sb := StyleBoxFlat.new()
		frame_sb.bg_color = Color(0, 0, 0, 0)
		frame_sb.border_color = TCGTheme.GOLD_L if (p_selected or p_hovered) else TCGTheme.GOLD_D
		frame_sb.set_border_width_all(2 if (p_selected or p_hovered) else 1)
		frame_sb.set_corner_radius_all(6)
		canvas.draw_style_box(frame_sb, full_r)
		# Dark translucent bottom plate for crisp title readability
		var plate_h: float = 28.0 if compact else clampf(h * 0.27, 42.0, 56.0)
		var plate_r := Rect2(full_r.position.x, full_r.end.y - plate_h, full_r.size.x, plate_h)
		canvas.draw_rect(plate_r, Color(0.05, 0.07, 0.11, 0.84))
		canvas.draw_line(
			Vector2(plate_r.position.x, plate_r.position.y),
			Vector2(plate_r.end.x, plate_r.position.y),
			TCGTheme.GOLD_D,
			1.0
		)
	else:
		var cat_col: Color = Color8(72, 50, 38) if role_name == "equipment" else (Color8(36, 68, 52) if is_heal_card else Color8(40, 56, 78))
		TCGTheme.draw_rounded_box(canvas, art_r, cat_col, TCGTheme.GOLD_D, 7, 1)
		if card_tex != null:
			TCGArt.draw_texture_cover(canvas, card_tex, art_r.grow(-2.0), Color.WHITE, 0.5)
		else:
			# Category / Element Emblem
			var ac := art_r.get_center()
			var rad: float = 32.0 if p_large else (14.0 if compact else 24.0)
			var owner_el: String = ""
			if not cd.char_name.is_empty():
				var ch_d := CardDataSystem.get_char_def(cd.char_name)
				if ch_d != null:
					owner_el = ch_d.element
			if not cd.cost.element.is_empty():
				TCGArt.draw_elem_symbol(canvas, cd.cost.element, ac, rad)
			elif not owner_el.is_empty():
				TCGArt.draw_elem_symbol(canvas, owner_el, ac, rad)
			elif is_heal_card:
				# Crisp cross / heal emblem for Heal cards
				var arm: float = rad * 0.58
				var thick: float = maxf(4.0, rad * 0.28)
				canvas.draw_rect(Rect2(ac.x - arm, ac.y - thick * 0.5, arm * 2.0, thick), TCGTheme.HEAL)
				canvas.draw_rect(Rect2(ac.x - thick * 0.5, ac.y - arm, thick, arm * 2.0), TCGTheme.HEAL)
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

	# Minimal role pill on large inspection/deck cards only (no cluttered labels on hand cards)
	var cat_y: float = art_r.end.y + 4.0
	if p_large:
		var role_col: Color = TCGTheme.HEAL if role_name == "heal" else TCGTheme.GOLD
		TCGTheme.draw_text_centered(
			canvas,
			role_name.to_upper(),
			Vector2(ox + w * 0.5, cat_y + 8.0),
			13,
			role_col,
			true,
			false
		)

	# Card Name
	var disp_title: String = cd.name
	if is_full_portrait_art:
		var plate_h2: float = 28.0 if compact else clampf(h * 0.27, 42.0, 56.0)
		var name_rect_full := Rect2(ox + 8, oy + h - 5.0 - plate_h2 + 4.0, w - 16, plate_h2 - 6.0)
		TCGTheme.draw_wrapped(
			canvas,
			disp_title,
			name_rect_full,
			9 if compact else 13,
			TCGTheme.TEXT,
			11 if compact else 16,
			false
		)
	else:
		var name_y_off: float = 20.0 if p_large else (2.0 if compact else 8.0)
		var name_rect := Rect2(ox + 8, cat_y + name_y_off, w - 16, 28 if compact else (54 if not p_large else 42))
		TCGTheme.draw_wrapped(
			canvas,
			disp_title,
			name_rect,
			16 if p_large else (9 if compact else 14),
			TCGTheme.INK,
			20 if p_large else (11 if compact else 17),
			false
		)

		if p_large:
			var desc_rect := Rect2(ox + 12, name_rect.end.y + 4.0, w - 24, oy + h - name_rect.end.y - 10.0)
			canvas.draw_line(
				Vector2(ox + 12, name_rect.end.y),
				Vector2(ox + w - 12, name_rect.end.y),
				TCGTheme.PARCH_D,
				1.0
			)
			TCGTheme.draw_wrapped(canvas, cd.text, desc_rect, 13, Color8(62, 52, 42), 17, false)

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

	# Genshin-style red circular X "Switch" stamp when marked for Mulligan or Swap Cards
	if p_swap_marked:
		TCGTheme.draw_rounded_box(canvas, r.grow(-4.0), Color(0.06, 0.04, 0.06, 0.44), TCGTheme.RED, 8, 2)
		var sc := Vector2(ox + w * 0.5, oy + h * 0.45)
		var sr := minf(w, h) * 0.21
		canvas.draw_circle(sc, sr, Color8(216, 68, 56))
		canvas.draw_arc(sc, sr, 0.0, TAU, 24, Color.WHITE, 2.4)
		var arm := sr * 0.44
		canvas.draw_line(sc + Vector2(-arm, -arm), sc + Vector2(arm, arm), Color.WHITE, 3.2)
		canvas.draw_line(sc + Vector2(arm, -arm), sc + Vector2(-arm, arm), Color.WHITE, 3.2)
		TCGTheme.draw_text_centered(canvas, "Switch", Vector2(sc.x, sc.y + sr + 14.0), 13 if not compact else 10, Color.WHITE, true, true)

	# Unaffordable dim veil (subtle so card art stays crisp & readable)
	if p_dim_unusable and not p_selected and not p_swap_marked:
		TCGTheme.draw_rounded_box(canvas, r, Color(0.04, 0.06, 0.10, 0.28), Color(0, 0, 0, 0), 10, 0)


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
		dim_unusable,
		-1.0
	)

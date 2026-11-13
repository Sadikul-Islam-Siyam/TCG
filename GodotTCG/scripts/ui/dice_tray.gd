class_name TCGDiceTray
extends Control
## Phase 6 (T6.1 - T6.7): Collapsible Dice Drawer with canonical Omni -> active_element -> rest
## visual ordering, selected -12px lift, cost progress indicator, spend burst, and tune flip.

signal die_clicked(die_index: int)
signal die_hovered(die_index: int, is_hovering: bool)
signal drawer_toggled(is_open: bool)

var dice: Array[String] = []
var selected_indices: Array[int] = []
var highlighted_indices: Array[int] = []
var tunable_indices: Array[int] = []
var tuning_active: bool = false
var active_element: String = ""
var payment_needed: int = 0
var rerolls_left: int = 0

var is_open: bool = true
var slide_t: float = 0.0   # 0.0 = open, 1.0 = collapsed off-edge
var _slide_tween: Tween = null

var _display_order: Array[int] = []   # visual slot -> logical p.dice index
var _hovered_idx: int = -1            # logical die index
var _hover_chevron: bool = false
var spin_timers: Dictionary = {}
var spin_durations: Dictionary = {}
var _tune_flip_timers: Dictionary = {}
var _spend_sparks: Array[Dictionary] = []
var clock: float = 0.0


func _init() -> void:
	custom_minimum_size = Vector2(118, 540)
	size = Vector2(118, 540)
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_open(open_state: bool, animate: bool = true) -> void:
	if is_open == open_state:
		return
	is_open = open_state
	var target_s := 0.0 if is_open else 1.0
	if animate and is_inside_tree():
		if _slide_tween != null and _slide_tween.is_valid():
			_slide_tween.kill()
		_slide_tween = create_tween()
		_slide_tween.tween_property(self, "slide_t", target_s, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_slide_tween.parallel().tween_method(func(_v: float) -> void: queue_redraw(), 0.0, 1.0, 0.25)
	else:
		slide_t = target_s
	drawer_toggled.emit(is_open)
	queue_redraw()


func _process(delta: float) -> void:
	clock += delta
	var dirty: bool = false
	for k in spin_timers.keys():
		var rem: float = float(spin_timers[k]) - delta
		if rem <= 0.0:
			spin_timers.erase(k)
			spin_durations.erase(k)
		else:
			spin_timers[k] = rem
		dirty = true
	for tk in _tune_flip_timers.keys():
		var trem: float = float(_tune_flip_timers[tk]) - delta
		if trem <= 0.0:
			_tune_flip_timers.erase(tk)
		else:
			_tune_flip_timers[tk] = trem
		dirty = true
	if not _spend_sparks.is_empty():
		var kept: Array[Dictionary] = []
		for sp in _spend_sparks:
			sp["life"] = float(sp["life"]) - delta
			if float(sp["life"]) > 0.0:
				sp["pos"] = (sp["pos"] as Vector2) + (sp["vel"] as Vector2) * delta
				kept.append(sp)
		_spend_sparks = kept
		dirty = true
	if dirty:
		queue_redraw()


func trigger_roll(indices: Array[int] = [], duration: float = 0.65) -> void:
	var targets: Array[int] = indices
	if targets.is_empty():
		for i in range(dice.size()):
			targets.append(i)
	for i in targets:
		if i >= 0 and i < dice.size():
			var d: float = duration + float(i % 4) * 0.05
			spin_timers[i] = d
			spin_durations[i] = d
	queue_redraw()


func trigger_tune(die_idx: int, duration: float = 0.6) -> void:
	if die_idx >= 0 and die_idx < dice.size():
		spin_timers[die_idx] = duration
		spin_durations[die_idx] = duration
		_tune_flip_timers[die_idx] = 0.25
		queue_redraw()


func trigger_spend_fx(spent_ids: Array) -> void:
	for raw_id in spent_ids:
		var idx: int = int(raw_id)
		var vpos := _visual_slot_of(idx)
		var center := _die_rect(vpos if vpos >= 0 else 0).get_center()
		for k in range(4):
			var a := float(k) * PI * 0.5 + 0.3
			_spend_sparks.append({
				"pos": center,
				"vel": Vector2(cos(a), sin(a)) * 64.0,
				"col": ElementDB.get_color(dice[idx]) if idx >= 0 and idx < dice.size() else TCGTheme.GOLD_L,
				"life": 0.35,
			})
	queue_redraw()


func is_spinning() -> bool:
	return not spin_timers.is_empty()


func setup(
	p_dice: Array[String],
	p_selected: Array[int] = [],
	p_highlighted: Array[int] = [],
	p_tuning: bool = false,
	p_tunable: Array[int] = [],
	p_active_elem: String = "",
	p_payment_needed: int = 0,
	p_rerolls_left: int = 0
) -> void:
	dice = p_dice.duplicate()
	selected_indices = p_selected.duplicate()
	highlighted_indices = p_highlighted.duplicate()
	tuning_active = p_tuning
	tunable_indices = p_tunable.duplicate()
	active_element = p_active_elem
	payment_needed = p_payment_needed
	rerolls_left = p_rerolls_left
	_rebuild_display_order()
	queue_redraw()


func _rebuild_display_order() -> void:
	_display_order.clear()
	for i in range(dice.size()):
		_display_order.append(i)
	_display_order.sort_custom(func(a: int, b: int) -> bool:
		var ra := _elem_sort_rank(dice[a])
		var rb := _elem_sort_rank(dice[b])
		if ra != rb:
			return ra < rb
		if dice[a] != dice[b]:
			return dice[a] < dice[b]
		return a < b
	)


func _elem_sort_rank(el: String) -> int:
	if el == CardDataSystem.OMNI:
		return 0
	if not active_element.is_empty() and el == active_element:
		return 1
	return 2


func _visual_slot_of(logical_idx: int) -> int:
	return _display_order.find(logical_idx)


func _chevron_rect() -> Rect2:
	var ox: float = slide_t * (size.x - 36.0)
	return Rect2(ox - 30.0, size.y * 0.5 - 30.0, 30.0, 60.0)


func _die_rect(visual_pos: int) -> Rect2:
	var ox: float = slide_t * (size.x - 36.0)
	var use_two_cols: bool = dice.size() > 8
	var top_y: float = 64.0
	var avail_h: float = maxf(260.0, size.y - top_y - 16.0)
	if use_two_cols:
		var cols: int = 2
		var rows: int = ceili(float(dice.size()) / 2.0)
		var step_y: float = minf(52.0, avail_h / float(maxi(1, rows)))
		var r_sz: float = minf(44.0, step_y - 5.0)
		var col: int = visual_pos % cols
		var row: int = visual_pos / cols
		var gx: float = ox + (11.0 if col == 0 else size.x * 0.5 + 3.0)
		return Rect2(gx, top_y + float(row) * step_y, r_sz, r_sz)
	var step_y_single: float = minf(56.0, avail_h / 8.0)
	var dsz: float = minf(50.0, step_y_single - 5.0)
	return Rect2(ox + (size.x - dsz) * 0.5, top_y + float(visual_pos) * step_y_single, dsz, dsz)


func get_die_global_center(logical_idx: int) -> Vector2:
	var vp := _visual_slot_of(logical_idx)
	if vp < 0:
		vp = 0
	return global_position + _die_rect(vp).get_center()


func get_die_at_global_pos(global_pos: Vector2) -> int:
	if not is_open:
		return -1
	var local_pos: Vector2 = global_pos - global_position
	for vp in range(_display_order.size()):
		var li: int = _display_order[vp]
		var r := _die_rect(vp)
		if selected_indices.has(li) or highlighted_indices.has(li):
			r.position.x -= 12.0
		if r.grow(6.0).has_point(local_pos):
			return li
	return -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var prev := _hovered_idx
		var prev_chev := _hover_chevron
		_hover_chevron = _chevron_rect().has_point(event.position)
		_hovered_idx = -1
		if is_open and not _hover_chevron:
			for vp in range(_display_order.size()):
				var li: int = _display_order[vp]
				var r := _die_rect(vp)
				if selected_indices.has(li):
					r.position.x -= 12.0
				if r.has_point(event.position):
					_hovered_idx = li
					break
		if prev != _hovered_idx:
			if prev >= 0:
				die_hovered.emit(prev, false)
			if _hovered_idx >= 0:
				die_hovered.emit(_hovered_idx, true)
			queue_redraw()
		elif prev_chev != _hover_chevron:
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _chevron_rect().has_point(event.position):
			set_open(not is_open)
			accept_event()
			return
		if not is_open:
			set_open(true)
			accept_event()
			return
		for vp in range(_display_order.size()):
			var li: int = _display_order[vp]
			var r := _die_rect(vp)
			if selected_indices.has(li):
				r.position.x -= 12.0
			if r.has_point(event.position):
				die_clicked.emit(li)
				accept_event()
				break


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		if _hovered_idx >= 0:
			var prev := _hovered_idx
			_hovered_idx = -1
			die_hovered.emit(prev, false)
		_hover_chevron = false
		queue_redraw()


func _draw() -> void:
	var ox: float = slide_t * (size.x - 36.0)
	var tray := Rect2(Vector2(ox, 0.0), size)
	var border_col := TCGTheme.GOLD_L if tuning_active else TCGTheme.GOLD
	TCGTheme.draw_rounded_box(
		self,
		tray,
		Color(0.06, 0.09, 0.14, 0.88),
		border_col,
		14,
		3 if tuning_active else 2
	)

	# Collapsible Chevron Tab (T6.1)
	var chev_r := _chevron_rect()
	TCGTheme.draw_rounded_box(self, chev_r, TCGTheme.PANEL2, TCGTheme.GOLD_L if _hover_chevron else border_col, 8, 2)
	TCGTheme.draw_text_centered(self, "›" if is_open else "‹", chev_r.get_center(), 22, TCGTheme.GOLD_L, true, true)

	# Dice count badge / payment counter progress (T6.5)
	var badge_c := Vector2(ox + size.x * 0.5, 25.0)
	draw_circle(badge_c, 20.0, TCGTheme.PANEL2)
	draw_arc(badge_c, 20.0, 0.0, TAU, 24, TCGTheme.GOLD_L, 2.2)
	if payment_needed > 0:
		var prog_txt := "%d/%d" % [selected_indices.size(), payment_needed]
		var ok_p := selected_indices.size() >= payment_needed
		TCGTheme.draw_text_centered(self, prog_txt, badge_c, 13, TCGTheme.GREEN if ok_p else TCGTheme.GOLD_L, true, true)
	else:
		TCGTheme.draw_text_centered(self, str(dice.size()), badge_c, 17, TCGTheme.GOLD_L, true, true)

	if tuning_active:
		var can_tune: bool = not tunable_indices.is_empty()
		TCGTheme.draw_text_centered(
			self,
			"TUNE" if can_tune else "NO DIE",
			Vector2(ox + size.x * 0.5, 51.0),
			12,
			TCGTheme.GOLD_L if can_tune else TCGTheme.RED,
			true,
			false
		)
	elif rerolls_left > 0:
		TCGTheme.draw_text_centered(self, "REROLL", Vector2(ox + size.x * 0.5, 51.0), 12, TCGTheme.TEAL, true, false)
	else:
		TCGTheme.draw_text_centered(self, "DICE", Vector2(ox + size.x * 0.5, 51.0), 12, TCGTheme.DIM, true, false)

	if slide_t < 0.85:
		for vp in range(_display_order.size()):
			var li: int = _display_order[vp]
			if li < 0 or li >= dice.size():
				continue
			var dr := _die_rect(vp)
			var is_sel := selected_indices.has(li)
			var is_hl := highlighted_indices.has(li) or (tuning_active and tunable_indices.has(li))
			var is_hov := (_hovered_idx == li)
			var is_dim := (tuning_active and not tunable_indices.has(li))
			# T6.5 Lift selected payment dice 12px outward
			if is_sel:
				dr.position.x -= 12.0

			if spin_timers.has(li) and float(spin_timers[li]) > 0.0:
				var rem: float = float(spin_timers[li])
				var dur: float = float(spin_durations.get(li, 0.65))
				var u: float = 1.0 - clampf(rem / maxf(0.01, dur), 0.0, 1.0)
				var face: String = dice[li]
				if u < 0.65:
					var faces: Array = CardDataSystem.DICE_FACES
					var f_idx: int = int(clock * 24.0 + float(li) * 3.0) % faces.size()
					face = String(faces[f_idx])
				var bounce_y: float = -absf(cos(u * PI * 2.5)) * (1.0 - u) * 34.0
				var angle: float = (1.0 - u) * TAU * 1.8
				var scale_v: float = 1.0 + 0.24 * (1.0 - u)
				if _tune_flip_timers.has(li):
					scale_v = maxf(0.25, absf(cos((float(_tune_flip_timers[li]) / 0.25) * PI))) * 1.15
				var spin_rect := Rect2(dr.position.x, dr.position.y + bounce_y, dr.size.x, dr.size.y)
				TCGArt.draw_die(self, face, spin_rect, is_sel, is_hov or is_hl, angle, scale_v, is_dim)
			else:
				TCGArt.draw_die(self, dice[li], dr, is_sel, is_hov or is_hl, 0.0, 1.0, is_dim)

	for sp in _spend_sparks:
		var sa := clampf(float(sp["life"]) / 0.35, 0.0, 1.0)
		var c := sp["col"] as Color
		draw_circle(sp["pos"] as Vector2, 4.0 * sa, Color(c.r, c.g, c.b, sa))

class_name TCGHandStrip
extends Control
## Phase 5 (T5.2, T5.3, T5.7, T5.8): Curved Action Card Hand Strip.
## Caps fan rotation strictly within +-4 degrees, scales down cleanly to fit up to 10 cards,
## lifts/straightens hovered cards (suppressed while busy), and animates card draw fly-ins.

signal hand_card_clicked(hand_index: int, card_name: String)
signal hand_card_right_clicked(hand_index: int, card_name: String)
signal hand_card_drag_started(hand_index: int, card_name: String, global_pos: Vector2)
signal hand_card_hovered(hand_index: int, card_name: String, is_hovering: bool)
signal hand_card_long_pressed(hand_index: int, card_name: String)

const CARD_W: float = 146.0
const CARD_H: float = 207.0

var hand_cards: Array[String] = []
var playable_flags: Array[bool] = []
var selected_hand_index: int = -1
var swap_indices: Array[int] = []
var mulligan_mode: bool = false
var hidden_hand: bool = false
var dragged_index: int = -1
var busy_locked: bool = false

var _hovered_index: int = -1
var _card_views: Array[TCGActionCardView] = []
var _target_positions: Array[Vector2] = []
var _target_rotations: Array[float] = []
var _target_scales: Array[Vector2] = []
var _draw_origin_local: Vector2 = Vector2(-180.0, 20.0)
var _dim_unplayable: bool = false
var _swap_select_mode: bool = false


func _init() -> void:
	custom_minimum_size = Vector2(600, 204)
	size = Vector2(920, 232)
	mouse_filter = Control.MOUSE_FILTER_PASS


func set_busy_locked(locked: bool) -> void:
	busy_locked = locked
	if busy_locked:
		_hovered_index = -1
	for cv in _card_views:
		if is_instance_valid(cv):
			cv.interaction_locked = busy_locked
	_layout_cards()


func set_draw_origin(local_pos: Vector2) -> void:
	_draw_origin_local = local_pos


func setup(
	p_cards: Array[String],
	p_playable: Array[bool],
	p_selected_idx: int = -1,
	p_swap_indices: Array[int] = [],
	p_mulligan: bool = false,
	p_hidden: bool = false,
	p_dragged_idx: int = -1,
	p_dim_unplayable: bool = false,
	p_swap_select_mode: bool = false
) -> void:
	var prev_count: int = hand_cards.size()
	hand_cards = p_cards.duplicate()
	playable_flags = p_playable.duplicate()
	selected_hand_index = p_selected_idx
	swap_indices = p_swap_indices.duplicate()
	mulligan_mode = p_mulligan
	hidden_hand = p_hidden
	dragged_index = p_dragged_idx
	_dim_unplayable = p_dim_unplayable
	_swap_select_mode = p_swap_select_mode or p_mulligan

	var newly_added: Array[int] = []
	if hand_cards.size() > prev_count and prev_count > 0:
		for k in range(prev_count, hand_cards.size()):
			newly_added.append(k)

	_rebuild_cards()
	_layout_cards(newly_added)
	queue_redraw()


func get_card_global_center(idx: int) -> Vector2:
	if idx >= 0 and idx < _card_views.size() and is_instance_valid(_card_views[idx]):
		var cv := _card_views[idx]
		return cv.global_position + cv.size * 0.5
	return global_position + size * 0.5


func is_engaged() -> bool:
	return _hovered_index >= 0 or selected_hand_index >= 0 or mulligan_mode or not swap_indices.is_empty() or dragged_index >= 0


func trigger_card_shake(idx: int) -> void:
	if idx >= 0 and idx < _card_views.size() and is_instance_valid(_card_views[idx]):
		_card_views[idx].trigger_unplayable_shake()


func _card_dims() -> Vector2:
	var cw: float = clampf(size.y * 0.63, 128.0, 150.0)
	if hand_cards.size() >= 9:
		cw = minf(cw, 118.0)
	var ch: float = roundf(cw * 1.42)
	return Vector2(cw, ch)


func _rebuild_cards() -> void:
	var dims := _card_dims()
	while _card_views.size() > hand_cards.size():
		var popped: TCGActionCardView = _card_views.pop_back()
		if is_instance_valid(popped):
			popped.queue_free()

	while _card_views.size() < hand_cards.size():
		var cv := TCGActionCardView.new()
		cv.custom_minimum_size = dims
		cv.size = dims
		cv.pivot_offset = dims * 0.5
		cv.card_clicked.connect(_on_card_clicked)
		cv.card_right_clicked.connect(_on_card_right_clicked)
		cv.card_drag_started.connect(_on_card_drag_started)
		cv.card_hovered.connect(_on_card_hovered)
		cv.card_long_pressed.connect(_on_card_long_pressed)
		add_child(cv)
		_card_views.append(cv)

	for i in range(hand_cards.size()):
		var cv := _card_views[i]
		cv.custom_minimum_size = dims
		cv.size = dims
		cv.pivot_offset = dims * 0.5
		cv.interaction_locked = busy_locked
		cv.allow_drag = not _swap_select_mode
		var is_play: bool = playable_flags[i] if i < playable_flags.size() else true
		var is_sel: bool = (i == selected_hand_index)
		var is_swap: bool = swap_indices.has(i)
		cv.visible = (i != dragged_index)
		cv.setup(hand_cards[i], i, is_sel, is_play, is_swap, hidden_hand, false, _dim_unplayable and not is_play)


func _layout_cards(newly_added: Array[int] = []) -> void:
	var n: int = hand_cards.size()
	_target_positions.resize(n)
	_target_rotations.resize(n)
	_target_scales.resize(n)
	if n == 0:
		return

	var dims := _card_dims()
	var cw: float = dims.x
	var ch: float = dims.y
	var max_span: float = maxf(cw + 20.0, size.x - 40.0)
	var step: float = minf(cw + 12.0, max_span / maxf(1.0, float(n))) if n > 1 else 0.0
	var total_w: float = cw + float(maxi(0, n - 1)) * step
	var start_x: float = (size.x - total_w) * 0.5
	var base_y: float = maxf(18.0, size.y - ch - 12.0)

	var mid: float = float(n - 1) * 0.5
	for i in range(n):
		var offset_from_mid: float = float(i) - mid
		var hover_spread: float = 0.0
		var active_hov := _hovered_index if not busy_locked else -1
		if active_hov >= 0 and not hidden_hand:
			if i < active_hov:
				hover_spread = -10.0
			elif i > active_hov:
				hover_spread = 10.0

		var x: float = start_x + float(i) * step + hover_spread
		var arc_y: float = (offset_from_mid * offset_from_mid) * 1.4
		var is_sel: bool = (i == selected_hand_index)
		var is_hov: bool = (i == active_hov and not hidden_hand)
		var lift: float = -26.0 if is_hov else (-16.0 if is_sel else (-8.0 if swap_indices.has(i) else 0.0))
		var target_pos := Vector2(x, base_y + arc_y + lift)
		# T5.2 Fan rotation strictly capped within +-4 degrees
		var angle_deg: float = clampf(offset_from_mid * 0.9, -4.0, 4.0)
		var target_rot: float = 0.0 if (is_hov or is_sel) else deg_to_rad(angle_deg)
		var target_scale := Vector2(1.14, 1.14) if is_hov else (Vector2(1.06, 1.06) if is_sel else Vector2.ONE)

		_target_positions[i] = target_pos
		_target_rotations[i] = target_rot
		_target_scales[i] = target_scale

		var cv := _card_views[i]
		cv.z_index = 25 if is_hov else (18 if is_sel else i)
		if newly_added.has(i):
			cv.position = _draw_origin_local
			cv.modulate.a = 0.35
			cv.scale = Vector2(0.45, 0.45)
			cv.rotation = 0.0
		elif not is_inside_tree():
			cv.position = target_pos
			cv.rotation = target_rot
			cv.scale = target_scale
			cv.modulate.a = 1.0


func _process(delta: float) -> void:
	var speed: float = 1.0 - exp(-18.0 * delta)
	var fade_sp: float = 1.0 - exp(-14.0 * delta)
	for i in range(_card_views.size()):
		if i >= _target_positions.size():
			break
		var cv := _card_views[i]
		if not is_instance_valid(cv):
			continue
		cv.position = cv.position.lerp(_target_positions[i], speed)
		cv.rotation = lerpf(cv.rotation, _target_rotations[i], speed)
		cv.scale = cv.scale.lerp(_target_scales[i], speed)
		cv.modulate.a = lerpf(cv.modulate.a, 1.0, fade_sp)


func _on_card_clicked(c_name: String, idx: int) -> void:
	hand_card_clicked.emit(idx, c_name)


func _on_card_right_clicked(c_name: String, idx: int) -> void:
	hand_card_right_clicked.emit(idx, c_name)


func _on_card_drag_started(c_name: String, idx: int, global_pos: Vector2) -> void:
	if busy_locked:
		return
	hand_card_drag_started.emit(idx, c_name, global_pos)


func _on_card_long_pressed(c_name: String, idx: int) -> void:
	hand_card_long_pressed.emit(idx, c_name)


func _on_card_hovered(c_name: String, idx: int, is_hovering: bool) -> void:
	if is_hovering:
		_hovered_index = idx
	elif _hovered_index == idx:
		_hovered_index = -1
	_layout_cards()
	hand_card_hovered.emit(idx, c_name, is_hovering)

class_name TCGHandStrip
extends Control
## Stage 6: Reusable Hand Strip Component
## Direct port of PythonTCG/ui/match.py `draw_hand` and `hand_target`.
## Renders the player's action card hand from real match state, supporting:
## - Normal bottom fan & Mulligan center-screen enlarged fan
## - Hover elevation, selection elevation, and mulligan "SWAP" markers
## - Left-click, right-click (Elemental Tuning), and drag-start signals

signal hand_card_clicked(hand_index: int, card_name: String)
signal hand_card_right_clicked(hand_index: int, card_name: String)
signal hand_card_drag_started(hand_index: int, card_name: String, global_pos: Vector2)
signal hand_card_hovered(hand_index: int, card_name: String, is_hovering: bool)

const CARD_W: float = 118.0
const CARD_H: float = 168.0

var hand_cards: Array[String] = []
var playable_flags: Array[bool] = []
var selected_hand_index: int = -1
var swap_indices: Array[int] = []
var mulligan_mode: bool = false
var hidden_hand: bool = false
var dragged_index: int = -1
var _hovered_index: int = -1
var _card_views: Array[TCGActionCardView] = []
var _target_positions: Array[Vector2] = []
var _target_rotations: Array[float] = []
var _target_scales: Array[Vector2] = []


func _init() -> void:
	custom_minimum_size = Vector2(780, 210)
	size = Vector2(780, 210)
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_process(true)


func setup(
	p_cards: Array[String],
	p_playable: Array[bool] = [],
	p_selected_idx: int = -1,
	p_swap_indices: Array[int] = [],
	p_mulligan: bool = false,
	p_hidden: bool = false,
	p_dragged_idx: int = -1
) -> void:
	hand_cards = p_cards.duplicate()
	playable_flags = p_playable.duplicate()
	selected_hand_index = p_selected_idx
	swap_indices = p_swap_indices.duplicate()
	mulligan_mode = p_mulligan
	hidden_hand = p_hidden
	dragged_index = p_dragged_idx
	_rebuild_cards()


func get_card_global_center(idx: int) -> Vector2:
	if idx >= 0 and idx < _card_views.size():
		return _card_views[idx].global_position + _card_views[idx].size * 0.5
	return global_position + size * 0.5


func _rebuild_cards() -> void:
	while _card_views.size() > hand_cards.size():
		var old_view: TCGActionCardView = _card_views.pop_back()
		old_view.queue_free()

	var newly_added: Array[int] = []
	while _card_views.size() < hand_cards.size():
		var v := TCGActionCardView.new()
		v.pivot_offset = Vector2(CARD_W * 0.5, CARD_H * 0.5)
		v.card_clicked.connect(_on_card_clicked)
		v.card_right_clicked.connect(_on_card_right_clicked)
		v.card_drag_started.connect(_on_card_drag_started)
		v.card_hovered.connect(_on_card_hovered)
		add_child(v)
		newly_added.append(_card_views.size())
		_card_views.append(v)

	_layout_cards(newly_added)


func _layout_cards(newly_added: Array[int] = []) -> void:
	var n: int = hand_cards.size()
	_target_positions.clear()
	_target_rotations.clear()
	_target_scales.clear()
	if n == 0:
		return

	var step: float = 136.0 if mulligan_mode else minf(104.0, 580.0 / float(maxi(1, n)))
	var total_w: float = CARD_W + step * float(n - 1)
	var start_x: float = (size.x - total_w) * 0.5
	var mid: float = float(n - 1) * 0.5

	for i in range(n):
		var v: TCGActionCardView = _card_views[i]
		v.visible = (i != dragged_index)
		v.pivot_offset = Vector2(CARD_W * 0.5, CARD_H * 0.5)
		var can_play: bool = true if mulligan_mode else (i < playable_flags.size() and playable_flags[i])
		var is_sel: bool = (selected_hand_index == i)
		var is_swap: bool = swap_indices.has(i)
		var is_hov: bool = (_hovered_index == i)
		v.setup(hand_cards[i], i, is_sel, can_play, false, is_swap, hidden_hand)
		var lift: float = 0.0
		if is_sel or is_swap:
			lift = 30.0
		elif is_hov:
			lift = 22.0
		var offset_mid: float = float(i) - mid
		var fan_arc: float = 0.0 if (mulligan_mode or is_hov or is_sel) else (offset_mid * offset_mid * 2.2)
		var target_pos := Vector2(start_x + float(i) * step, 36.0 + fan_arc - lift)
		var target_rot: float = 0.0 if (mulligan_mode or is_hov or is_sel or is_swap) else clampf(offset_mid * 0.025, -0.10, 0.10)
		var target_scale := Vector2(1.07, 1.07) if (is_hov or is_sel) else (Vector2(1.03, 1.03) if is_swap else Vector2.ONE)

		_target_positions.append(target_pos)
		_target_rotations.append(target_rot)
		_target_scales.append(target_scale)

		if not is_inside_tree():
			v.position = target_pos
			v.rotation = target_rot
			v.scale = target_scale
			v.modulate.a = 1.0
		elif newly_added.has(i):
			v.position = target_pos + Vector2(-42.0, 26.0)
			v.rotation = target_rot - 0.12
			v.scale = Vector2(0.86, 0.86)
			v.modulate.a = 0.0
		v.z_index = 30 if (is_sel or is_hov) else i


func _process(delta: float) -> void:
	var k: float = 1.0 - exp(-14.0 * delta)
	var n: int = mini(_card_views.size(), _target_positions.size())
	for i in range(n):
		var v: TCGActionCardView = _card_views[i]
		v.position = v.position.lerp(_target_positions[i], k)
		v.rotation = lerpf(v.rotation, _target_rotations[i], k)
		v.scale = v.scale.lerp(_target_scales[i], k)
		v.modulate.a = lerpf(v.modulate.a, 1.0, k)


func _on_card_clicked(c_name: String, idx: int) -> void:
	hand_card_clicked.emit(idx, c_name)


func _on_card_right_clicked(c_name: String, idx: int) -> void:
	hand_card_right_clicked.emit(idx, c_name)


func _on_card_drag_started(c_name: String, idx: int, global_pos: Vector2) -> void:
	hand_card_drag_started.emit(idx, c_name, global_pos)


func _on_card_hovered(c_name: String, idx: int, is_hovering: bool) -> void:
	if is_hovering:
		_hovered_index = idx
	elif _hovered_index == idx:
		_hovered_index = -1
	_layout_cards()
	hand_card_hovered.emit(idx, c_name, is_hovering)

class_name TCGDiceTray
extends Control
## Stage 6: Reusable Dice Tray Component
## Direct port of PythonTCG/ui/match.py `draw_dice`.
## Renders the right-hand dice container, count badge, hexagonal elemental dice,
## hover/selection highlights, and Elemental Tuning drop-target indicator.

signal die_clicked(die_index: int)
signal die_hovered(die_index: int, is_hovering: bool)

var dice: Array[String] = []
var selected_indices: Array[int] = []
var highlighted_indices: Array[int] = []
var tunable_indices: Array[int] = []
var tuning_active: bool = false
var _hovered_idx: int = -1

var spin_timers: Dictionary = {}
var spin_durations: Dictionary = {}
var clock: float = 0.0


func _init() -> void:
	custom_minimum_size = Vector2(68, 420)
	size = Vector2(68, 420)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)


func _process(delta: float) -> void:
	clock += delta
	if not spin_timers.is_empty():
		var expired: Array = []
		for idx in spin_timers.keys():
			var rem: float = float(spin_timers[idx]) - delta
			if rem <= 0.0:
				expired.append(idx)
			else:
				spin_timers[idx] = rem
		for ex in expired:
			spin_timers.erase(ex)
			spin_durations.erase(ex)
		queue_redraw()


func trigger_roll(indices: Array[int] = [], duration: float = 0.65) -> void:
	var to_roll: Array[int] = indices.duplicate()
	if to_roll.is_empty():
		for i in range(dice.size()):
			to_roll.append(i)
	for i in to_roll:
		var dur: float = duration + 0.04 * float(i)
		spin_timers[i] = dur
		spin_durations[i] = dur
	queue_redraw()


func trigger_tune(die_idx: int, duration: float = 0.6) -> void:
	spin_timers[die_idx] = duration
	spin_durations[die_idx] = duration
	queue_redraw()


func is_spinning() -> bool:
	return not spin_timers.is_empty()


func setup(
	p_dice: Array[String],
	p_selected: Array[int] = [],
	p_highlighted: Array[int] = [],
	p_tuning_active: bool = false,
	p_tunable: Array[int] = []
) -> void:
	dice = p_dice.duplicate()
	selected_indices = p_selected.duplicate()
	highlighted_indices = p_highlighted.duplicate()
	tuning_active = p_tuning_active
	tunable_indices = p_tunable.duplicate()
	queue_redraw()


func _die_rect(idx: int) -> Rect2:
	var n: int = dice.size()
	if n <= 9:
		return Rect2(14, 52 + idx * 38, 40, 36)
	var col: int = idx % 2
	var row: int = idx / 2
	return Rect2(4 + col * 31, 52 + row * 34, 30, 30)


func get_die_at_global_pos(global_pos: Vector2) -> int:
	var local_pos: Vector2 = global_pos - global_position
	for i in range(dice.size()):
		if _die_rect(i).grow(6.0).has_point(local_pos):
			return i
	return -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var prev := _hovered_idx
		_hovered_idx = -1
		for i in range(dice.size()):
			if _die_rect(i).has_point(event.position):
				_hovered_idx = i
				break
		if prev != _hovered_idx:
			if prev >= 0:
				die_hovered.emit(prev, false)
			if _hovered_idx >= 0:
				die_hovered.emit(_hovered_idx, true)
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in range(dice.size()):
			if _die_rect(i).has_point(event.position):
				die_clicked.emit(i)
				break


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hovered_idx >= 0:
		var prev := _hovered_idx
		_hovered_idx = -1
		die_hovered.emit(prev, false)
		queue_redraw()


func _draw() -> void:
	var tray := Rect2(Vector2.ZERO, size)
	var border_col := TCGTheme.GOLD_L if tuning_active else TCGTheme.GOLD
	TCGTheme.draw_rounded_box(
		self,
		tray,
		Color(0.06, 0.09, 0.14, 0.86),
		border_col,
		14,
		3 if tuning_active else 2
	)

	# Dice count circle badge at top
	var badge_c := Vector2(size.x * 0.5, 22.0)
	draw_circle(badge_c, 15.0, TCGTheme.PANEL2)
	draw_arc(badge_c, 15.0, 0.0, TAU, 24, TCGTheme.GOLD_L, 2.0)
	TCGTheme.draw_text_centered(self, str(dice.size()), badge_c, 14, TCGTheme.GOLD_L, true, true)

	if tuning_active:
		var can_tune: bool = not tunable_indices.is_empty()
		TCGTheme.draw_text_centered(
			self,
			"TUNE" if can_tune else "NO DIE",
			Vector2(size.x * 0.5, 42.0),
			9,
			TCGTheme.GOLD_L if can_tune else TCGTheme.RED,
			true,
			false
		)
	else:
		TCGTheme.draw_text_centered(self, "DICE", Vector2(size.x * 0.5, 42.0), 9, TCGTheme.DIM, true, false)

	for i in range(dice.size()):
		var dr := _die_rect(i)
		var is_sel := selected_indices.has(i)
		var is_hl := highlighted_indices.has(i) or (tuning_active and tunable_indices.has(i))
		var is_hov := (_hovered_idx == i)
		var is_dim := (tuning_active and not tunable_indices.has(i))

		if spin_timers.has(i) and float(spin_timers[i]) > 0.0:
			var rem: float = float(spin_timers[i])
			var dur: float = float(spin_durations.get(i, 0.65))
			var u: float = 1.0 - clampf(rem / maxf(0.01, dur), 0.0, 1.0)
			var face: String = dice[i]
			if u < 0.65:
				var faces: Array = CardDataSystem.DICE_FACES
				var f_idx: int = int(clock * 24.0 + float(i) * 3.0) % faces.size()
				face = String(faces[f_idx])
			var bounce_y: float = -absf(cos(u * PI * 2.5)) * (1.0 - u) * 36.0
			var angle: float = (1.0 - u) * TAU * 1.8
			var scale: float = 1.0 + 0.25 * (1.0 - u)
			var spin_rect := Rect2(dr.position.x, dr.position.y + bounce_y, dr.size.x, dr.size.y)
			TCGArt.draw_die(self, face, spin_rect, is_sel, is_hov or is_hl, angle, scale, is_dim)
		else:
			TCGArt.draw_die(self, dice[i], dr, is_sel, is_hov or is_hl, 0.0, 1.0, is_dim)

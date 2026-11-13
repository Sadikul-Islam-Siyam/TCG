class_name TCGSkillBar
extends Control
## T7.1 / T7.4: Circular Skill Medallion Bar Component.
## Displays Normal Attack, Elemental Skill, and Elemental Burst as circular bronze medallions
## with rim cost gems, warm ember usability glow, full-energy Burst halo pulse, and [1][2][3] hints.

signal skill_clicked(skill_index: int)
signal skill_hovered(skill_index: int, is_hovering: bool)

const MEDALLION_SIZE := 92.0
const MEDALLION_STRIDE := 104.0

var active_char: TCGPlayerSystem.CharacterInstance = null
var usable_flags: Array[bool] = [false, false, false]
var effective_costs: Array[CardDataSystem.CostData] = []
var selected_skill_index: int = -1
var _hovered_idx: int = -1
var _interactable: bool = true

var _pulse_t: float = 0.0
var _scales: Array[float] = [1.0, 1.0, 1.0]
var _press_bump: Array[float] = [0.0, 0.0, 0.0]


func _init() -> void:
	custom_minimum_size = Vector2(320, 138)
	size = Vector2(320, 138)
	mouse_filter = Control.MOUSE_FILTER_STOP


func setup(
	p_char: TCGPlayerSystem.CharacterInstance,
	p_usable: Array[bool],
	p_costs: Array[CardDataSystem.CostData],
	p_selected_idx: int = -1
) -> void:
	active_char = p_char
	usable_flags = p_usable.duplicate()
	effective_costs = p_costs.duplicate()
	selected_skill_index = p_selected_idx
	queue_redraw()


func set_interactable(enabled: bool) -> void:
	_interactable = enabled
	queue_redraw()


func trigger_skill_press(idx: int) -> void:
	if idx >= 0 and idx < _press_bump.size():
		_press_bump[idx] = 0.14
		queue_redraw()


func get_skill_global_center(i: int) -> Vector2:
	var r := _skill_rect(i)
	return global_position + r.get_center()


func _skill_rect(i: int) -> Rect2:
	# Slight shallow arc offset: center skill slightly higher for tactile Genshin feel
	var arc_y: float = 6.0 if i == 1 else 14.0
	return Rect2(float(i) * MEDALLION_STRIDE + 4.0, arc_y, MEDALLION_SIZE, MEDALLION_SIZE + 18.0)


func _medallion_center(i: int) -> Vector2:
	var r := _skill_rect(i)
	return Vector2(r.position.x + MEDALLION_SIZE * 0.5, r.position.y + MEDALLION_SIZE * 0.5)


func _process(delta: float) -> void:
	_pulse_t += delta
	var dirty: bool = false
	for i in range(3):
		var target := 1.0
		if selected_skill_index == i:
			target = 1.06
		elif _hovered_idx == i and _interactable:
			target = 1.05
		if _press_bump[i] > 0.0:
			target += _press_bump[i]
			_press_bump[i] = maxf(0.0, _press_bump[i] - delta * 0.9)
		var next := lerpf(_scales[i], target, minf(1.0, delta * 14.0))
		if absf(next - _scales[i]) > 0.002:
			_scales[i] = next
			dirty = true
	# Keep redraw alive smoothly when burst ready or any skill usable for subtle ember shimmer
	if active_char != null and _is_burst_ready():
		dirty = true
	if dirty:
		queue_redraw()


func _is_burst_ready() -> bool:
	if active_char == null:
		return false
	var d: CardDataSystem.CharData = active_char.get_defn()
	if d == null or d.max_energy <= 0:
		return false
	return active_char.energy >= d.max_energy and (2 < usable_flags.size() and usable_flags[2])


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var prev := _hovered_idx
		_hovered_idx = -1
		for i in range(3):
			if _skill_rect(i).has_point(event.position):
				_hovered_idx = i
				break
		if prev != _hovered_idx:
			if prev >= 0:
				skill_hovered.emit(prev, false)
			if _hovered_idx >= 0:
				skill_hovered.emit(_hovered_idx, true)
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in range(3):
			if _skill_rect(i).has_point(event.position):
				trigger_skill_press(i)
				skill_clicked.emit(i)
				break


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hovered_idx >= 0:
		var prev := _hovered_idx
		_hovered_idx = -1
		skill_hovered.emit(prev, false)
		queue_redraw()


func _draw() -> void:
	if active_char == null:
		return

	var d: CardDataSystem.CharData = active_char.get_defn()
	if d == null:
		return
	var skills: Array[CardDataSystem.SkillData] = d.skills
	var short_labels: Array[String] = ["NORMAL", "SKILL", "BURST"]
	var bronze := Color("#C9A55A")
	var bronze_dark := Color("#6E542B")
	var ember := Color("#FFAC4D")

	for i in range(mini(3, skills.size())):
		var sk: CardDataSystem.SkillData = skills[i]
		var usable: bool = i < usable_flags.size() and usable_flags[i] and _interactable
		var is_sel: bool = (selected_skill_index == i)
		var is_hov: bool = (_hovered_idx == i)
		var sc: float = _scales[i] if i < _scales.size() else 1.0
		var ic := _medallion_center(i)
		var med_r: float = (MEDALLION_SIZE * 0.5) * sc

		var accent := TCGTheme.elem_color(d.element) if i > 0 else Color8(206, 216, 232)
		var alpha_dim: float = 1.0 if (usable or is_sel) else 0.50

		# Soft drop shadow
		draw_circle(ic + Vector2(0, 4), med_r + 1.0, Color(0, 0, 0, 0.36 * alpha_dim))

		# Usable warm ember outer aura (or golden halo pulse for ready Burst)
		if i == 2 and _is_burst_ready():
			var pulse := 0.5 + 0.5 * sin(_pulse_t * 4.2)
			draw_circle(ic, med_r + 9.0 + pulse * 4.0, Color(1.0, 0.80, 0.30, 0.16 + 0.14 * pulse))
			draw_arc(ic, med_r + 6.0 + pulse * 2.5, 0.0, TAU, 36, Color(1.0, 0.88, 0.44, 0.72), 2.5)
		elif usable:
			var glow_col := ember if is_sel else Color(ember.r, ember.g, ember.b, 0.42 if is_hov else 0.24)
			draw_circle(ic, med_r + (6.0 if is_sel else 4.0), Color(glow_col.r, glow_col.g, glow_col.b, 0.22 if is_sel else 0.12))

		if is_sel:
			draw_arc(ic, med_r + 5.0, 0.0, TAU, 36, Color(TCGTheme.GOLD_L.r, TCGTheme.GOLD_L.g, TCGTheme.GOLD_L.b, 0.92), 2.8)

		# Dark medallion backing + bronze outer rim
		var back_col := TCGTheme.elem_dark(d.element) if (usable and i > 0) else Color("#161D2B")
		if not usable:
			back_col = Color("#131823")
		draw_circle(ic, med_r, Color(back_col.r, back_col.g, back_col.b, alpha_dim))
		draw_circle(ic, med_r - 4.0, Color(0.06, 0.09, 0.15, 0.70 * alpha_dim))

		var rim_col := TCGTheme.GOLD_L if is_sel else (bronze if usable else bronze_dark)
		draw_arc(ic, med_r, 0.0, TAU, 36, Color(rim_col.r, rim_col.g, rim_col.b, alpha_dim), 2.8 if (is_sel or i == 2) else 2.2)
		draw_arc(ic, med_r - 4.0, 0.0, TAU, 32, Color(bronze_dark.r, bronze_dark.g, bronze_dark.b, 0.75 * alpha_dim), 1.2)

		# Center weapon/element emblem
		if i == 0:
			var wp_col := Color(0.88, 0.92, 0.97, alpha_dim)
			TCGArt.draw_elem_symbol(self, "Physical", ic, 18.0 * sc, wp_col, false)
		elif i == 1:
			TCGArt.draw_elem_symbol(self, d.element, ic, 19.0 * sc, Color(accent.r, accent.g, accent.b, alpha_dim), false)
		else:
			draw_arc(ic, med_r - 9.0, 0.0, TAU, 24, Color(TCGTheme.GOLD_L.r, TCGTheme.GOLD_L.g, TCGTheme.GOLD_L.b, 0.55 * alpha_dim), 1.4)
			TCGArt.draw_elem_symbol(self, d.element, ic, 21.0 * sc, Color(TCGTheme.GOLD_L.r, TCGTheme.GOLD_L.g, TCGTheme.GOLD_L.b, alpha_dim), false)

		# Circular cost gems arranged neatly along upper/bottom rim
		var cost_obj: CardDataSystem.CostData = effective_costs[i] if i < effective_costs.size() else sk.cost
		var pairs: Array = TCGActionCardView.cost_to_pairs(cost_obj)
		var n_gems: int = pairs.size()
		for g_idx in range(n_gems):
			var pair: Array = pairs[g_idx]
			# Fan gems smoothly around lower-left-to-top-right rim without colliding with label
			var span: float = minf(0.95, float(n_gems - 1) * 0.42)
			var ang: float = -PI * 0.72 + (0.0 if n_gems == 1 else span * (float(g_idx) / float(n_gems - 1) - 0.5))
			var gp := ic + Vector2(cos(ang), sin(ang)) * (med_r - 1.5)
			TCGArt.draw_cost_gem(self, String(pair[0]), int(pair[1]), gp, 12.5)

		# [1] [2] [3] shortcut keycap badge at top-right rim (T7.4)
		var kp := ic + Vector2(med_r * 0.68, -med_r * 0.68)
		TCGTheme.draw_rounded_box(
			self,
			Rect2(kp - Vector2(11, 10), Vector2(22, 20)),
			Color(0.08, 0.11, 0.17, 0.92 * alpha_dim),
			Color(rim_col.r, rim_col.g, rim_col.b, 0.75 * alpha_dim),
			5,
			1.0
		)
		TCGTheme.draw_text_centered(self, str(i + 1), kp + Vector2(0, 1), 12, Color(TCGTheme.TEXT.r, TCGTheme.TEXT.g, TCGTheme.TEXT.b, alpha_dim), true, false)

		# Short label below medallion
		var lbl_col := TCGTheme.GOLD_L if (usable or is_sel) else Color(TCGTheme.DIM.r, TCGTheme.DIM.g, TCGTheme.DIM.b, 0.65)
		TCGTheme.draw_text_centered(
			self,
			short_labels[i],
			Vector2(ic.x, ic.y + med_r + 14.0),
			14,
			lbl_col,
			true,
			true
		)

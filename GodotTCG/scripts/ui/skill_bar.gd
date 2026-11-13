class_name TCGSkillBar
extends Control
## Stage 5: Reusable Skill Buttons Bar Component
## Direct port of PythonTCG/ui/match.py `_draw_skill_buttons`.
## Displays the active character's 3 skills (Normal Attack, Elemental Skill, Elemental Burst)
## with weapon/element emblems, cost gems, and legal/usable highlight.

signal skill_clicked(skill_index: int)
signal skill_hovered(skill_index: int, is_hovering: bool)

var active_char: TCGPlayerSystem.CharacterInstance = null
var usable_flags: Array[bool] = [false, false, false]
var effective_costs: Array[CardDataSystem.CostData] = []
var selected_skill_index: int = -1
var _hovered_idx: int = -1


func _init() -> void:
	custom_minimum_size = Vector2(228, 108)
	size = Vector2(228, 108)
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


func _skill_rect(i: int) -> Rect2:
	return Rect2(i * 78.0, 0.0, 68.0, 92.0)


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

	for i in range(mini(3, skills.size())):
		var sk: CardDataSystem.SkillData = skills[i]
		var r := _skill_rect(i)
		var usable: bool = i < usable_flags.size() and usable_flags[i]
		var is_sel: bool = (selected_skill_index == i)
		var is_hov: bool = (_hovered_idx == i)

		var accent := TCGTheme.elem_color(d.element) if i > 0 else Color8(190, 200, 214)
		var fill := TCGTheme.elem_dark(d.element) if (usable and i > 0) else TCGTheme.PANEL2
		if not usable:
			fill = Color8(20, 26, 36)
		var border := TCGTheme.GOLD_L if (is_sel or is_hov) else (accent if usable else TCGTheme.GOLD_D)

		TCGTheme.draw_rounded_box(
			self,
			r,
			fill,
			border,
			12,
			3 if is_sel else 2,
			Vector2(0, 3),
			95
		)

		# Circular Skill Icon Medallion
		var ic := Vector2(r.get_center().x, r.position.y + 30.0)
		var med_r: float = 19.0
		draw_circle(ic, med_r, Color8(16, 24, 36))
		draw_arc(ic, med_r, 0.0, TAU, 24, border, 2.0 if i < 2 else 3.0)

		if i == 0:
			TCGArt.draw_elem_symbol(self, "Physical", ic, 11.0, Color8(225, 232, 242), false)
		elif i == 1:
			TCGArt.draw_elem_symbol(self, d.element, ic, 12.0, accent, false)
		else:
			draw_arc(ic, med_r - 3.0, 0.0, TAU, 20, TCGTheme.GOLD_L, 1.0)
			TCGArt.draw_elem_symbol(self, d.element, ic, 13.0, TCGTheme.GOLD_L, false)

		# Cost gems row at bottom of button
		var cost_obj: CardDataSystem.CostData = effective_costs[i] if i < effective_costs.size() else sk.cost
		var pairs: Array = TCGActionCardView.cost_to_pairs(cost_obj)
		var n_gems: int = pairs.size()
		var gx0: float = r.get_center().x - float(n_gems - 1) * 10.5
		var gy: float = r.end.y - 16.0
		for g_idx in range(n_gems):
			var pair: Array = pairs[g_idx]
			TCGArt.draw_cost_gem(
				self,
				String(pair[0]),
				int(pair[1]),
				Vector2(gx0 + float(g_idx) * 21.0, gy),
				9.5
			)

		# Short label below button
		var lbl_col := TCGTheme.GOLD_L if usable else TCGTheme.DIM
		TCGTheme.draw_text_centered(
			self,
			short_labels[i],
			Vector2(r.get_center().x, r.end.y + 8.0),
			10,
			lbl_col,
			true,
			true
		)

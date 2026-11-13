class_name TCGZoneGrid
extends Control
## Stage 6: Reusable 2x2 Support / Summon Zone Grid Component
## Direct port of PythonTCG/ui/match.py `_draw_zone_grid` and `_draw_unit_tile`.
## Displays 4 slots (70x96 each, 8px spacing) with hover inspection support.

signal unit_hovered(is_summon: bool, slot_index: int, unit: TCGPlayerSystem.UnitInstance, is_hovering: bool)
signal unit_clicked(is_summon: bool, slot_index: int, unit: TCGPlayerSystem.UnitInstance)

var zone_label: String = "SUPPORTS"
var is_summon_zone: bool = false
var units: Array = []
var _hovered_slot: int = -1


func _init() -> void:
	custom_minimum_size = Vector2(148, 224)
	size = Vector2(148, 224)
	mouse_filter = Control.MOUSE_FILTER_STOP


func setup(p_label: String, p_is_summon: bool, p_units: Array) -> void:
	zone_label = p_label
	is_summon_zone = p_is_summon
	units = p_units
	queue_redraw()


func _tile_rect(slot_idx: int) -> Rect2:
	var tile_w: float = 70.0
	var tile_h: float = 96.0
	var gap: float = 8.0
	var y_base: float = 20.0
	var col: int = slot_idx % 2
	var row: int = slot_idx / 2
	return Rect2(col * (tile_w + gap), y_base + row * (tile_h + gap), tile_w, tile_h)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var found: int = -1
		for i in range(mini(4, units.size())):
			if units[i] != null and _tile_rect(i).has_point(event.position):
				found = i
				break
		if found != _hovered_slot:
			if _hovered_slot >= 0 and _hovered_slot < units.size() and units[_hovered_slot] != null:
				unit_hovered.emit(is_summon_zone, _hovered_slot, units[_hovered_slot], false)
			_hovered_slot = found
			if _hovered_slot >= 0 and units[_hovered_slot] != null:
				unit_hovered.emit(is_summon_zone, _hovered_slot, units[_hovered_slot], true)
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in range(mini(4, units.size())):
			if units[i] != null and _tile_rect(i).has_point(event.position):
				unit_clicked.emit(is_summon_zone, i, units[i])
				break


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hovered_slot >= 0:
		if _hovered_slot < units.size() and units[_hovered_slot] != null:
			unit_hovered.emit(is_summon_zone, _hovered_slot, units[_hovered_slot], false)
		_hovered_slot = -1
		queue_redraw()


func _draw() -> void:
	TCGTheme.draw_text_centered(
		self,
		zone_label,
		Vector2(size.x * 0.5, 8.0),
		11,
		TCGTheme.DIM,
		true,
		true
	)

	for slot_idx in range(4):
		var tr := _tile_rect(slot_idx)
		if slot_idx < units.size() and units[slot_idx] != null:
			_draw_unit_tile(tr, units[slot_idx], _hovered_slot == slot_idx)
		else:
			TCGTheme.draw_rounded_box(
				self,
				tr,
				Color(0.06, 0.1, 0.15, 0.48),
				Color(0.87, 0.72, 0.41, 0.25),
				8,
				1
			)
			var c := tr.get_center()
			draw_arc(c, 10.0, 0.0, TAU, 16, Color(0.66, 0.71, 0.77, 0.20), 1.0)


func _draw_unit_tile(r: Rect2, u: TCGPlayerSystem.UnitInstance, hovered: bool) -> void:
	var elem := "Omni"
	var dmg: int = 0
	if is_summon_zone:
		var sdef: CardDataSystem.SummonData = CardDataSystem.get_summon_def(u.name)
		if sdef != null:
			if not sdef.element.is_empty():
				elem = sdef.element
			dmg = sdef.damage

	var accent := TCGTheme.GOLD_L if hovered else (TCGTheme.elem_color(elem) if is_summon_zone else TCGTheme.TEAL)
	var fill := TCGTheme.elem_dark(elem) if is_summon_zone else Color8(26, 44, 62)

	TCGTheme.draw_rounded_box(self, r, fill, accent, 8, 2, Vector2(0, 3), 85)

	# Center icon
	var ic := Vector2(r.get_center().x, r.position.y + 30.0)
	if is_summon_zone:
		TCGArt.draw_elem_symbol(self, elem, ic, 14.0)
	else:
		TCGArt.draw_elem_symbol(self, "Omni", ic, 13.0, TCGTheme.TEAL, true)

	# Unit Name
	var name_rect := Rect2(r.position.x + 4.0, r.position.y + 48.0, r.size.x - 8.0, 32.0)
	TCGTheme.draw_wrapped(self, u.name, name_rect, 10, TCGTheme.TEXT, 11, true)

	# Summon damage badge at bottom center (`ui/match.py:759-761`)
	if is_summon_zone and dmg > 0:
		var dc := Vector2(r.get_center().x, r.end.y - 12.0)
		draw_circle(dc, 9.0, Color8(24, 16, 12))
		draw_arc(dc, 9.0, 0.0, TAU, 16, accent, 1.5)
		TCGTheme.draw_text_centered(self, str(dmg), dc, 11, Color.WHITE, true, false)

	# Usages counter badge at top-right (if >= 0)
	if u.usages >= 0:
		var badge_c := Vector2(r.end.x - 13.0, r.position.y + 13.0)
		draw_circle(badge_c, 10.0, Color8(18, 26, 38))
		draw_arc(badge_c, 10.0, 0.0, TAU, 16, TCGTheme.GOLD_L, 2.0)
		TCGTheme.draw_text_centered(self, str(u.usages), badge_c, 11, TCGTheme.GOLD_L, true, true)

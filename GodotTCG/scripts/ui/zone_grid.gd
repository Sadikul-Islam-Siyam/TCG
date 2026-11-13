class_name TCGZoneGrid
extends Control
## Phase 4 (T4.1 - T4.2): Responsive 2x2 Summon / Support Grid.
## Summons & Supports share identical tile dimensions, faint empty placeholders,
## notched counter badge, summon damage orb, spawn drop/slide & trigger pulse FX.

signal unit_hovered(is_summon: bool, slot_index: int, unit: TCGPlayerSystem.UnitInstance, is_hovering: bool)
signal unit_clicked(is_summon: bool, slot_index: int, unit: TCGPlayerSystem.UnitInstance)

var zone_label: String = "SUPPORTS"
var is_summon_zone: bool = false
var units: Array = []
var _hovered_slot: int = -1

# Phase 4 animation caches
var _known_units: Dictionary = {}   # name -> usages
var _spawn_fx: Dictionary = {}      # name -> remaining sec
var _pulse_fx: Dictionary = {}      # name -> remaining sec
var _fading_units: Array[Dictionary] = []  # {"name", "rect", "elem", "life"}


func _init() -> void:
	custom_minimum_size = Vector2(246, 262)
	size = Vector2(246, 262)
	mouse_filter = Control.MOUSE_FILTER_STOP


func setup(p_label: String, p_is_summon: bool, p_units: Array) -> void:
	zone_label = p_label
	is_summon_zone = p_is_summon
	var prev_names: Array[String] = []
	for u_prev in units:
		if u_prev != null:
			prev_names.append(String(u_prev.name))
	units = p_units

	var cur_map: Dictionary = {}
	for i in range(mini(4, units.size())):
		var u = units[i]
		if u != null:
			var nm := String(u.name)
			cur_map[nm] = u.usages
			if not _known_units.has(nm) and prev_names.size() > 0 or (not _known_units.has(nm) and is_inside_tree()):
				_spawn_fx[nm] = 0.34
			elif int(_known_units.get(nm, u.usages)) != u.usages:
				_pulse_fx[nm] = 0.32
	for old_nm in _known_units.keys():
		if not cur_map.has(old_nm):
			_fading_units.append({
				"name": String(old_nm),
				"life": 0.25,
				"elem": _elem_of(String(old_nm)),
			})
	_known_units = cur_map
	queue_redraw()


func trigger_unit_pulse(unit_name: String) -> void:
	_pulse_fx[unit_name] = 0.36
	queue_redraw()


func _elem_of(u_name: String) -> String:
	if is_summon_zone:
		var sdef := CardDataSystem.get_summon_def(u_name)
		if sdef != null and not sdef.element.is_empty():
			return sdef.element
	return "Physical"


func _process(delta: float) -> void:
	var dirty := false
	for k in _spawn_fx.keys():
		var rem: float = float(_spawn_fx[k]) - delta
		if rem <= 0.0:
			_spawn_fx.erase(k)
		else:
			_spawn_fx[k] = rem
		dirty = true
	for k in _pulse_fx.keys():
		var rem_p: float = float(_pulse_fx[k]) - delta
		if rem_p <= 0.0:
			_pulse_fx.erase(k)
		else:
			_pulse_fx[k] = rem_p
		dirty = true
	if not _fading_units.is_empty():
		var kept: Array[Dictionary] = []
		for fd in _fading_units:
			fd["life"] = float(fd["life"]) - delta
			if float(fd["life"]) > 0.0:
				kept.append(fd)
		_fading_units = kept
		dirty = true
	if dirty:
		queue_redraw()


func _tile_rect(slot_idx: int) -> Rect2:
	var col: int = slot_idx % 2
	var row: int = slot_idx / 2
	var pad_top: float = 28.0
	var gap: float = 9.0
	var tile_w: float = maxf(76.0, (size.x - gap * 3.0) * 0.5)
	var tile_h: float = maxf(88.0, (size.y - pad_top - gap * 2.0) * 0.5)
	var sx: float = gap + float(col) * (tile_w + gap)
	var sy: float = pad_top + float(row) * (tile_h + gap)
	return Rect2(sx, sy, tile_w, tile_h)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var prev := _hovered_slot
		_hovered_slot = -1
		for i in range(4):
			if i < units.size() and _tile_rect(i).has_point(event.position):
				_hovered_slot = i
				break
		if prev != _hovered_slot:
			if prev >= 0 and prev < units.size():
				unit_hovered.emit(is_summon_zone, prev, units[prev], false)
			if _hovered_slot >= 0 and _hovered_slot < units.size():
				unit_hovered.emit(is_summon_zone, _hovered_slot, units[_hovered_slot], true)
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			for i in range(4):
				if i < units.size() and _tile_rect(i).has_point(event.position):
					unit_clicked.emit(is_summon_zone, i, units[i])
					accept_event()
					break


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hovered_slot >= 0:
		var prev := _hovered_slot
		_hovered_slot = -1
		if prev < units.size():
			unit_hovered.emit(is_summon_zone, prev, units[prev], false)
		queue_redraw()


func _draw() -> void:
	var frame := Rect2(Vector2.ZERO, size)
	TCGTheme.draw_rounded_box(self, frame, Color(0.05, 0.08, 0.13, 0.44), TCGTheme.GOLD_D, 10, 1)
	TCGTheme.draw_text_centered(self, zone_label, Vector2(size.x * 0.5, 15.0), 15, TCGTheme.DIM, true, true)

	for i in range(4):
		var r := _tile_rect(i)
		if i < units.size() and units[i] != null:
			_draw_unit_tile(r, units[i], _hovered_slot == i)
		else:
			# T2.1 Faint outlined placeholder so empty slots are always visible
			TCGTheme.draw_rounded_box(self, r, Color(0.07, 0.10, 0.15, 0.52), Color(TCGTheme.GOLD_D.r, TCGTheme.GOLD_D.g, TCGTheme.GOLD_D.b, 0.45), 8, 1)
			draw_arc(r.get_center(), minf(r.size.x, r.size.y) * 0.24, 0.0, TAU, 16, Color(TCGTheme.GOLD_D.r, TCGTheme.GOLD_D.g, TCGTheme.GOLD_D.b, 0.40), 1.2)


func _draw_unit_tile(r: Rect2, u: TCGPlayerSystem.UnitInstance, hovered: bool) -> void:
	var elem := "Physical"
	var dmg: int = 0
	if is_summon_zone:
		var sdef: CardDataSystem.SummonData = CardDataSystem.get_summon_def(u.name)
		if sdef != null:
			if not sdef.element.is_empty():
				elem = sdef.element
			dmg = sdef.damage

	var draw_r := r
	if _spawn_fx.has(u.name):
		var sp_u: float = 1.0 - clampf(float(_spawn_fx[u.name]) / 0.34, 0.0, 1.0)
		if is_summon_zone:
			draw_r.position.y -= (1.0 - sp_u) * 26.0
		else:
			draw_r.position.x -= (1.0 - sp_u) * 30.0
	if _pulse_fx.has(u.name):
		var pu: float = sin((float(_pulse_fx[u.name]) / 0.36) * PI)
		draw_r = draw_r.grow(pu * 5.0)

	var accent := TCGTheme.GOLD_L if hovered else (ElementDB.get_color(elem) if is_summon_zone else TCGTheme.TEAL)
	var fill := ElementDB.get_dark_color(elem) if is_summon_zone else Color8(26, 44, 62)

	TCGTheme.draw_rounded_box(self, draw_r, fill, accent, 8, 2, Vector2(0, 3), 85)

	# Center icon
	var ic := Vector2(draw_r.get_center().x, draw_r.position.y + draw_r.size.y * 0.32)
	if is_summon_zone:
		TCGArt.draw_elem_symbol(self, elem, ic, minf(draw_r.size.x, draw_r.size.y) * 0.19)
	else:
		TCGArt.draw_elem_symbol(self, "Omni", ic, minf(draw_r.size.x, draw_r.size.y) * 0.18, TCGTheme.TEAL, true)

	# Unit Name
	var name_rect := Rect2(draw_r.position.x + 6.0, draw_r.position.y + draw_r.size.y * 0.52, draw_r.size.x - 12.0, draw_r.size.y * 0.36)
	TCGTheme.draw_wrapped(self, u.name, name_rect, 13, TCGTheme.TEXT, 16, true)

	# Summon damage badge at bottom-left (T4.1)
	if is_summon_zone and dmg > 0:
		var dc := Vector2(draw_r.position.x + 15.0, draw_r.end.y - 14.0)
		draw_circle(dc, 12.0, Color8(24, 16, 12))
		draw_arc(dc, 12.0, 0.0, TAU, 16, accent, 1.8)
		TCGTheme.draw_text_centered(self, str(dmg), dc, 13, Color.WHITE, true, false)

	# Notched / Round usages counter badge at top-right (T4.1 & T4.2: only if has counter >= 0)
	if u.usages >= 0:
		var tab_r := Rect2(draw_r.end.x - 27.0, draw_r.position.y + 3.0, 24.0, 21.0)
		if is_summon_zone:
			TCGTheme.draw_rounded_box(self, tab_r, Color8(18, 26, 38), TCGTheme.GOLD_L, 5, 1)
			TCGTheme.draw_text_centered(self, str(u.usages), tab_r.get_center(), 13, TCGTheme.GOLD_L, true, true)
		else:
			var badge_c := Vector2(draw_r.end.x - 15.0, draw_r.position.y + 15.0)
			draw_circle(badge_c, 12.0, Color8(18, 26, 38))
			draw_arc(badge_c, 12.0, 0.0, TAU, 16, TCGTheme.GOLD_L, 2.0)
			TCGTheme.draw_text_centered(self, str(u.usages), badge_c, 13, TCGTheme.GOLD_L, true, true)

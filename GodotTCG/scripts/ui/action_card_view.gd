class_name TCGActionCardView
extends Control
## Stage 6: Reusable Action Card View & Interaction Component
## Direct port of PythonTCG/ui/art.py `_card_base` and `ui/match.py` card interactions.
## Displays migrated CardData fields: artwork, name, category/kind, weapon/resonance/char restriction,
## cost gems column, usages, and description text. Supports left-click, right-click (tune),
## drag-and-drop, and mulligan "SWAP" badge.

signal card_clicked(card_name: String, hand_index: int)
signal card_right_clicked(card_name: String, hand_index: int)
signal card_drag_started(card_name: String, hand_index: int, global_pos: Vector2)
signal card_hovered(card_name: String, hand_index: int, is_hovering: bool)

var card_name: String = ""
var hand_index: int = -1
var selected: bool = false
var swap_marked: bool = false
var playable: bool = true
var hidden_back: bool = false
var large_mode: bool = false
var _hovered: bool = false
var _pressing: bool = false
var _press_pos: Vector2 = Vector2.ZERO


func _init() -> void:
	custom_minimum_size = Vector2(118, 168)
	size = Vector2(118, 168)
	mouse_filter = Control.MOUSE_FILTER_STOP


func setup(
	p_card_name: String,
	p_hand_index: int = -1,
	p_selected: bool = false,
	p_playable: bool = true,
	p_large: bool = false,
	p_swap_marked: bool = false,
	p_hidden_back: bool = false
) -> void:
	card_name = p_card_name
	hand_index = p_hand_index
	selected = p_selected
	playable = p_playable
	large_mode = p_large
	swap_marked = p_swap_marked
	hidden_back = p_hidden_back
	if large_mode:
		custom_minimum_size = Vector2(210, 308)
		size = Vector2(210, 308)
	else:
		custom_minimum_size = Vector2(118, 168)
		size = Vector2(118, 168)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER:
		_hovered = true
		card_hovered.emit(card_name, hand_index, true)
		queue_redraw()
	elif what == NOTIFICATION_MOUSE_EXIT:
		_hovered = false
		if _pressing and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_pressing = false
			card_drag_started.emit(card_name, hand_index, get_global_mouse_position())
		else:
			_pressing = false
		card_hovered.emit(card_name, hand_index, false)
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_pressing = true
				_press_pos = event.global_position
			else:
				if _pressing:
					_pressing = false
					card_clicked.emit(card_name, hand_index)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			card_right_clicked.emit(card_name, hand_index)
	elif event is InputEventMouseMotion and _pressing:
		if event.global_position.distance_to(_press_pos) > 6.0:
			_pressing = false
			card_drag_started.emit(card_name, hand_index, event.global_position)


static func cost_to_pairs(c: CardDataSystem.CostData) -> Array:
	var out: Array = []
	if c == null:
		return out
	if c.n > 0:
		var k: String = c.element if not c.element.is_empty() else "Same"
		out.append([k, c.n])
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
	p_hidden_back: bool = false
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
		accent = TCGTheme.elem_color(cd.resonance)
	elif p_playable:
		accent = TCGTheme.GOLD_L

	# Outer playable or selected glow
	if (p_playable and (p_selected or p_hovered)) or p_swap_marked:
		var glow_col := TCGTheme.RED if p_swap_marked else Color8(255, 210, 110)
		TCGTheme.draw_rounded_box(
			canvas,
			r.grow(3.0),
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

	# Upper artwork header box
	var compact: bool = (not p_large and h < 150.0)
	var art_h: float = 118.0 if p_large else (54.0 if compact else 76.0)
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
		cat_col = TCGTheme.elem_dark(cd.resonance)

	TCGTheme.draw_rounded_box(canvas, art_r, cat_col, TCGTheme.GOLD_D, 7, 1)

	# Center Category / Element Emblem
	var ac := art_r.get_center()
	var rad: float = 19.0 if not p_large else 28.0
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

	# Cost gems along top-left
	var cy: float = oy + 20.0
	var cost_pairs: Array = cost_to_pairs(cd.cost)
	if cost_pairs.is_empty():
		TCGArt.draw_cost_gem(canvas, "Same", 0, Vector2(ox + 20, cy), 10.5)
	else:
		for pair in cost_pairs:
			TCGArt.draw_cost_gem(canvas, String(pair[0]), int(pair[1]), Vector2(ox + 20, cy), 10.5)
			cy += 23.0

	# Support usages badge in top-right if applicable
	if cd.usages > 0:
		var ub_c := Vector2(ox + w - 18.0, oy + 18.0)
		canvas.draw_circle(ub_c, 9.5, Color8(24, 34, 48))
		canvas.draw_arc(ub_c, 9.5, 0.0, TAU, 16, TCGTheme.GOLD, 1.5)
		TCGTheme.draw_text_centered(canvas, str(cd.usages), ub_c, 10, TCGTheme.GOLD_L, true, false)

	# Category / subtype pill
	var cat_y: float = art_r.end.y + 3.0
	var cat_txt: String = "RESONANCE" if not cd.resonance.is_empty() else cd.kind.to_upper()
	if not cd.weapon.is_empty():
		cat_txt += " · " + cd.weapon.to_upper()
	elif not cd.char_name.is_empty():
		cat_txt += " · " + cd.char_name.to_upper()
	TCGTheme.draw_text_centered(
		canvas,
		cat_txt,
		Vector2(ox + w * 0.5, cat_y + 7.0),
		9 if not p_large else 11,
		TCGTheme.GOLD_D,
		true,
		false
	)

	# Card Name plaque
	var disp_title: String = cd.name.replace("Elemental Resonance: ", "") if not p_large else cd.name
	var name_rect := Rect2(ox + 8, cat_y + 15.0, w - 16, 44 if compact else (32 if not p_large else 38))
	TCGTheme.draw_wrapped(
		canvas,
		disp_title,
		name_rect,
		11 if not p_large else 14,
		TCGTheme.INK,
		13 if not p_large else 17,
		false
	)

	# Description
	if p_large:
		var desc_rect := Rect2(ox + 10, name_rect.end.y + 4.0, w - 20, oy + h - name_rect.end.y - 12.0)
		canvas.draw_line(
			Vector2(ox + 12, name_rect.end.y),
			Vector2(ox + w - 12, name_rect.end.y),
			TCGTheme.PARCH_D,
			1.0
		)
		TCGTheme.draw_wrapped(canvas, cd.text, desc_rect, 12, Color8(62, 52, 42), 16, false)
	elif not compact:
		var short_rect := Rect2(ox + 8, oy + h - 35.0, w - 16, 29.0)
		canvas.draw_line(
			Vector2(ox + 10, short_rect.position.y - 2.0),
			Vector2(ox + w - 10, short_rect.position.y - 2.0),
			TCGTheme.PARCH_D,
			1.0
		)
		TCGTheme.draw_wrapped(canvas, cd.text, short_rect, 9, Color8(78, 68, 56), 11, false)

	# Dim overlay when card is not playable in current state
	if not p_playable and not p_swap_marked:
		TCGTheme.draw_rounded_box(canvas, r, Color(0.04, 0.06, 0.1, 0.42), Color(0, 0, 0, 0), 10, 0)

	# Mulligan SWAP badge overlay (`ui/match.py:1019-1021`)
	if p_swap_marked:
		var sw_rect := Rect2(ox + 16, oy + 8, w - 32, 22)
		TCGTheme.draw_rounded_box(canvas, sw_rect, Color(0.75, 0.18, 0.18, 0.92), TCGTheme.GOLD_L, 6, 1)
		TCGTheme.draw_text_centered(canvas, "SWAP", sw_rect.get_center(), 12, Color.WHITE, true, true)


func _draw() -> void:
	draw_card_surface(
		self,
		Rect2(Vector2.ZERO, size),
		card_name,
		selected,
		_hovered,
		playable,
		large_mode,
		swap_marked,
		hidden_back
	)

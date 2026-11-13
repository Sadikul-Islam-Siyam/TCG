class_name TCGTheme
extends RefCounted
## Stage 5: Visual Theme & Canvas Drawing Utilities
## Direct port of PythonTCG/ui/theme.py (color palette, element colors, shading,
## gold frames, parchment plaques, badges, and crisp outlined typography).

const W: int = 1280
const H: int = 720

const BG := Color8(12, 20, 32)
const PANEL := Color8(22, 34, 50)
const PANEL2 := Color8(31, 47, 67)
const PARCH := Color8(244, 235, 212)
const PARCH_D := Color8(220, 202, 166)
const INK := Color8(49, 42, 34)
const TEXT := Color8(245, 241, 230)
const DIM := Color8(169, 181, 196)
const GOLD := Color8(222, 185, 105)
const GOLD_L := Color8(255, 229, 165)
const GOLD_D := Color8(130, 94, 43)
const RED := Color8(231, 101, 94)
const GREEN := Color8(128, 218, 159)
const TEAL := Color8(98, 190, 208)
const HEAL := Color8(130, 235, 150)

const REACT: Dictionary = {
	"Vaporize": {"elements": ["Hydro", "Pyro"], "desc": "+1 damage"},
	"Melt": {"elements": ["Cryo", "Pyro"], "desc": "+2 damage"},
	"Overloaded": {"elements": ["Pyro", "Electro"], "desc": "+2 damage, forced switch"},
	"Superconduct": {"elements": ["Cryo", "Electro"], "desc": "+1 damage, 1 Piercing to others"},
	"Electro-Charged": {"elements": ["Hydro", "Electro"], "desc": "+1 damage, 1 Piercing to others"},
	"Frozen": {"elements": ["Cryo", "Hydro"], "desc": "+1 damage, target Frozen"},
	"Swirl": {"elements": ["Anemo"], "desc": "1 damage to the other characters"},
	"Crystallize": {"elements": ["Geo"], "desc": "+1 damage, shield gained"},
}

const ELEM_COL: Dictionary = {
	"Cryo": Color8(157, 224, 255),
	"Hydro": Color8(73, 166, 255),
	"Pyro": Color8(255, 115, 75),
	"Electro": Color8(194, 132, 255),
	"Anemo": Color8(112, 232, 195),
	"Geo": Color8(255, 202, 92),
	"Omni": Color8(244, 243, 255),
	"Physical": Color8(218, 222, 228),
	"Piercing": Color8(244, 244, 252),
}

const ELEM_DARK: Dictionary = {
	"Cryo": Color8(34, 66, 92),
	"Hydro": Color8(22, 48, 86),
	"Pyro": Color8(88, 30, 24),
	"Electro": Color8(58, 34, 88),
	"Anemo": Color8(24, 72, 64),
	"Geo": Color8(78, 56, 24),
	"Omni": Color8(58, 52, 74),
	"Physical": Color8(52, 56, 66),
	"Piercing": Color8(60, 60, 74),
}


static func elem_color(e: String) -> Color:
	return ELEM_COL.get(e, DIM)


static func elem_dark(e: String) -> Color:
	return ELEM_DARK.get(e, PANEL2)


static func mix(a: Color, b: Color, t: float) -> Color:
	return Color(
		clampf(a.r + (b.r - a.r) * t, 0.0, 1.0),
		clampf(a.g + (b.g - a.g) * t, 0.0, 1.0),
		clampf(a.b + (b.b - a.b) * t, 0.0, 1.0),
		clampf(a.a + (b.a - a.a) * t, 0.0, 1.0)
	)


static func shade(c: Color, k: float) -> Color:
	return Color(
		clampf(c.r * k, 0.0, 1.0),
		clampf(c.g * k, 0.0, 1.0),
		clampf(c.b * k, 0.0, 1.0),
		c.a
	)


static func with_alpha(c: Color, a_255: int) -> Color:
	return Color(c.r, c.g, c.b, clampf(float(a_255) / 255.0, 0.0, 1.0))


static func draw_rounded_box(
	canvas: CanvasItem,
	rect: Rect2,
	fill_col: Color,
	border_col: Color = Color(0, 0, 0, 0),
	radius: int = 10,
	border_width: int = 0,
	shadow_offset: Vector2 = Vector2.ZERO,
	shadow_alpha: int = 0
) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill_col
	sb.set_corner_radius_all(radius)
	if border_width > 0 and border_col.a > 0.0:
		sb.border_color = border_col
		sb.set_border_width_all(border_width)
	if shadow_alpha > 0:
		var sh := StyleBoxFlat.new()
		sh.bg_color = Color(0.0, 0.0, 0.0, float(shadow_alpha) / 255.0)
		sh.set_corner_radius_all(radius + 1)
		canvas.draw_style_box(sh, Rect2(rect.position + shadow_offset, rect.size))
	canvas.draw_style_box(sb, rect)


static func draw_gold_frame(
	canvas: CanvasItem,
	rect: Rect2,
	fill: Color = PANEL,
	rad: int = 12,
	hi: bool = false
) -> void:
	var outer := GOLD_L if hi else GOLD
	draw_rounded_box(
		canvas,
		rect,
		fill,
		outer,
		rad,
		3 if hi else 2,
		Vector2(0, 4),
		95
	)
	var inner_rect := rect.grow(-4.0)
	if inner_rect.size.x > 4.0 and inner_rect.size.y > 4.0:
		var inner_sb := StyleBoxFlat.new()
		inner_sb.bg_color = Color(0, 0, 0, 0)
		inner_sb.border_color = GOLD_D
		inner_sb.set_border_width_all(1)
		inner_sb.set_corner_radius_all(maxi(2, rad - 3))
		canvas.draw_style_box(inner_sb, inner_rect)

	# Four corner diamond ornaments matching PythonTCG theme.gold_frame
	var corners: Array[Vector2] = [
		Vector2(rect.position.x + 8, rect.position.y + 8),
		Vector2(rect.end.x - 8, rect.position.y + 8),
		Vector2(rect.position.x + 8, rect.end.y - 8),
		Vector2(rect.end.x - 8, rect.end.y - 8),
	]
	for p in corners:
		var pts := PackedVector2Array([
			Vector2(p.x, p.y - 3),
			Vector2(p.x + 3, p.y),
			Vector2(p.x, p.y + 3),
			Vector2(p.x - 3, p.y),
		])
		canvas.draw_colored_polygon(pts, outer)


static func draw_plaque(
	canvas: CanvasItem,
	rect: Rect2,
	label: String,
	accent: Color = GOLD,
	hovered: bool = false,
	disabled: bool = false,
	small: bool = false
) -> void:
	var fill := PANEL2 if not hovered else mix(PANEL2, accent, 0.22)
	if disabled:
		fill = Color8(26, 31, 40)
	var border := GOLD_L if hovered else (GOLD_D if disabled else accent)
	draw_rounded_box(
		canvas,
		rect,
		fill,
		border,
		10,
		2,
		Vector2(0, 3),
		90
	)
	var inner := rect.grow(-3.0)
	var inner_sb := StyleBoxFlat.new()
	inner_sb.bg_color = Color(0, 0, 0, 0)
	inner_sb.border_color = shade(border, 0.55)
	inner_sb.set_border_width_all(1)
	inner_sb.set_corner_radius_all(8)
	canvas.draw_style_box(inner_sb, inner)

	var col := DIM if disabled else (GOLD_L if hovered else TEXT)
	draw_text_centered(
		canvas,
		label,
		rect.get_center(),
		13 if small else 16,
		col,
		true,
		true
	)


static func draw_text_pos(
	canvas: CanvasItem,
	txt: String,
	pos: Vector2,
	size: int = 16,
	col: Color = TEXT,
	bold: bool = false,
	shadow: bool = true
) -> void:
	if txt.is_empty():
		return
	var f: Font = ThemeDB.fallback_font
	var ascent: float = f.get_ascent(size)
	var baseline := Vector2(pos.x, pos.y + ascent)
	if shadow:
		canvas.draw_string_outline(
			f,
			baseline + Vector2(0, 1),
			txt,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			size,
			3,
			Color(0.0, 0.0, 0.0, 0.85)
		)
	canvas.draw_string(f, baseline, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	if bold:
		canvas.draw_string(
			f,
			baseline + Vector2(0.6, 0.0),
			txt,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			size,
			col
		)


static func draw_text_centered(
	canvas: CanvasItem,
	txt: String,
	center: Vector2,
	size: int = 16,
	col: Color = TEXT,
	bold: bool = false,
	shadow: bool = true
) -> void:
	if txt.is_empty():
		return
	var f: Font = ThemeDB.fallback_font
	var str_size: Vector2 = f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var pos := Vector2(center.x - str_size.x * 0.5, center.y - str_size.y * 0.5 - 1.0)
	draw_text_pos(canvas, txt, pos, size, col, bold, shadow)


static func draw_text_right(
	canvas: CanvasItem,
	txt: String,
	top_right: Vector2,
	size: int = 16,
	col: Color = TEXT,
	bold: bool = false,
	shadow: bool = true
) -> void:
	if txt.is_empty():
		return
	var f: Font = ThemeDB.fallback_font
	var str_size: Vector2 = f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var pos := Vector2(top_right.x - str_size.x, top_right.y)
	draw_text_pos(canvas, txt, pos, size, col, bold, shadow)


static func draw_wrapped(
	canvas: CanvasItem,
	txt: String,
	rect: Rect2,
	size: int = 13,
	col: Color = TEXT,
	line_h: int = 17,
	shadow: bool = false
) -> int:
	var f: Font = ThemeDB.fallback_font
	var y: float = rect.position.y
	for para in txt.split("\n"):
		var words: PackedStringArray = para.split(" ", false)
		var line: String = ""
		for w in words:
			var test: String = (line + " " + w).strip_edges()
			var tw: float = f.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			if tw <= rect.size.x or line.is_empty():
				line = test
			else:
				if y + line_h <= rect.end.y:
					draw_text_pos(canvas, line, Vector2(rect.position.x, y), size, col, false, shadow)
				y += line_h
				line = w
		if not line.is_empty() and y + line_h <= rect.end.y:
			draw_text_pos(canvas, line, Vector2(rect.position.x, y), size, col, false, shadow)
			y += line_h
	return int(y)


static func draw_reaction_pill(
	canvas: CanvasItem,
	title: String,
	sub: String,
	elements: Array,
	center: Vector2,
	alpha: float = 1.0
) -> void:
	if alpha <= 0.01:
		return
	var a: float = clampf(alpha, 0.0, 1.0)
	var title_upper := title.to_upper()
	var f: Font = ThemeDB.fallback_font
	var tw: float = f.get_string_size(title_upper, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	var sw: float = f.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var n_els: int = elements.size()
	var w: float = maxf(170.0, maxf(tw + 70.0 + float(n_els) * 20.0, sw + 44.0 + float(n_els) * 20.0))
	var h: float = 52.0
	var rect := Rect2(center.x - w * 0.5, center.y - h * 0.5, w, h)

	draw_rounded_box(
		canvas,
		rect,
		Color(0.10, 0.08, 0.06, 0.94 * a),
		Color(GOLD.r, GOLD.g, GOLD.b, a),
		14,
		2,
		Vector2(0, 3),
		int(90.0 * a)
	)

	# Element gems on left
	var gx: float = rect.position.x + 22.0
	for el_raw in elements:
		var el := String(el_raw)
		var c_pt := Vector2(gx, center.y)
		var gem_col := elem_color(el)
		canvas.draw_circle(c_pt, 9.0, Color(gem_col.r, gem_col.g, gem_col.b, a))
		canvas.draw_arc(c_pt, 9.0, 0.0, TAU, 16, Color(GOLD_L.r, GOLD_L.g, GOLD_L.b, a), 1.5)
		gx += 20.0

	var text_cx: float = (rect.position.x + gx + w - 20.0) * 0.5
	if not sub.is_empty():
		draw_text_centered(canvas, title_upper, Vector2(text_cx, center.y - 9.0), 16, Color(GOLD_L.r, GOLD_L.g, GOLD_L.b, a), true, false)
		draw_text_centered(canvas, sub, Vector2(text_cx, center.y + 11.0), 12, Color(TEXT.r, TEXT.g, TEXT.b, a), false, false)
	else:
		draw_text_centered(canvas, title_upper, Vector2(text_cx, center.y), 18, Color(GOLD_L.r, GOLD_L.g, GOLD_L.b, a), true, false)


static func draw_action_ribbon(
	canvas: CanvasItem,
	title: String,
	sub: String,
	accent_col: Color,
	center: Vector2,
	alpha: float = 1.0
) -> void:
	if alpha <= 0.01:
		return
	var a: float = clampf(alpha, 0.0, 1.0)
	var f: Font = ThemeDB.fallback_font
	var tw: float = f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	var sw: float = f.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var w: float = maxf(380.0, maxf(tw, sw) + 84.0)
	var h: float = 56.0
	var rect := Rect2(center.x - w * 0.5, center.y - h * 0.5, w, h)

	draw_rounded_box(
		canvas,
		rect,
		Color(0.12, 0.14, 0.18, 0.95 * a),
		Color(GOLD_D.r, GOLD_D.g, GOLD_D.b, a),
		12,
		2,
		Vector2(0, 4),
		int(100.0 * a)
	)

	# Left colored accent bar
	var bar_rect := Rect2(rect.position.x + 8.0, rect.position.y + 8.0, 8.0, h - 16.0)
	canvas.draw_rect(bar_rect, Color(accent_col.r, accent_col.g, accent_col.b, a))

	var text_cx: float = center.x + 6.0
	if not sub.is_empty():
		draw_text_centered(canvas, title, Vector2(text_cx, center.y - 9.0), 18, Color(TEXT.r, TEXT.g, TEXT.b, a), true, false)
		draw_text_centered(canvas, sub, Vector2(text_cx, center.y + 11.0), 12, Color(GOLD_L.r, GOLD_L.g, GOLD_L.b, a), false, false)
	else:
		draw_text_centered(canvas, title, Vector2(text_cx, center.y), 19, Color(TEXT.r, TEXT.g, TEXT.b, a), true, false)


static func draw_phase_announcement(
	canvas: CanvasItem,
	title: String,
	sub: String,
	title_col: Color,
	center_y: float = 350.0,
	alpha: float = 1.0
) -> void:
	if alpha <= 0.01:
		return
	var a: float = clampf(alpha, 0.0, 1.0)
	var band_h: float = 90.0
	var band := Rect2(0.0, center_y - band_h * 0.5, float(W), band_h)
	canvas.draw_rect(band, Color(0.04, 0.06, 0.09, 0.85 * a))
	canvas.draw_line(Vector2(0.0, band.position.y), Vector2(float(W), band.position.y), Color(GOLD.r, GOLD.g, GOLD.b, a), 2.0)
	canvas.draw_line(Vector2(0.0, band.end.y), Vector2(float(W), band.end.y), Color(GOLD.r, GOLD.g, GOLD.b, a), 2.0)

	if not sub.is_empty():
		draw_text_centered(canvas, title, Vector2(float(W) * 0.5, center_y - 12.0), 34, Color(title_col.r, title_col.g, title_col.b, a), true, true)
		draw_text_centered(canvas, sub, Vector2(float(W) * 0.5, center_y + 22.0), 15, Color(TEXT.r, TEXT.g, TEXT.b, a), false, true)
	else:
		draw_text_centered(canvas, title, Vector2(float(W) * 0.5, center_y), 36, Color(title_col.r, title_col.g, title_col.b, a), true, true)



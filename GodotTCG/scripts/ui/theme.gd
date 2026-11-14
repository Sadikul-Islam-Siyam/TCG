class_name TCGTheme
extends RefCounted
## Stage 5: Visual Theme & Canvas Drawing Utilities
## Direct port of PythonTCG/ui/theme.py (color palette, element colors, shading,
## gold frames, parchment plaques, badges, and crisp outlined typography).

const W: int = 1920
const H: int = 1080

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

static var ELEM_COL: Dictionary = {}
static var ELEM_DARK: Dictionary = {}
static var _display_font: Font = null
static var _body_font: Font = null
static var _app_theme: Theme = null


static func _static_init() -> void:
	_sync_elem_maps()


static func _sync_elem_maps() -> void:
	if not ELEM_COL.is_empty():
		return
	for el_id in ElementDB.all_ids():
		ELEM_COL[el_id] = ElementDB.get_color(el_id)
		ELEM_DARK[el_id] = ElementDB.get_dark_color(el_id)


static func elem_color(e: String) -> Color:
	var ed := ElementDB.get_element(e)
	if ed != null and (String(ed.id) == e or String(ed.id) == e.capitalize()):
		return ed.color
	return DIM


static func elem_dark(e: String) -> Color:
	var ed := ElementDB.get_element(e)
	if ed != null and (String(ed.id) == e or String(ed.id) == e.capitalize()):
		return ed.dark_color
	return PANEL2


static func elem_light(e: String) -> Color:
	var ed := ElementDB.get_element(e)
	if ed != null and (String(ed.id) == e or String(ed.id) == e.capitalize()):
		return ed.light_color
	return GOLD_L


static func get_display_font() -> Font:
	if _display_font == null:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray(["Georgia", "Palatino Linotype", "Times New Roman", "Liberation Serif", "Noto Serif", "serif"])
		sf.font_weight = 600
		_display_font = sf
	return _display_font


static func get_body_font() -> Font:
	if _body_font == null:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray(["Segoe UI", "Inter", "Noto Sans", "DejaVu Sans", "sans-serif"])
		sf.font_weight = 400
		_body_font = sf
	return _body_font


static func make_slate_panel_style(
	fill: Color = PANEL,
	outer_border: Color = GOLD,
	inner_border: Color = GOLD_D,
	radius: int = 12,
	border_w: int = 2
) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = outer_border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.shadow_color = Color(0, 0, 0, 0.36)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 3)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	# Note: second inner border is drawn via draw_gold_frame or inner overlay panel where needed
	var _unused := inner_border
	return sb


static func make_gem_style(elem_id: String, radius: int = 14) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = elem_dark(elem_id)
	sb.border_color = elem_color(elem_id)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(radius)
	return sb


static func make_counter_pill_style(accent: Color = GOLD_D) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.11, 0.16, 0.94)
	sb.border_color = accent
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	return sb


static func make_button_style(hovered: bool = false, pressed: bool = false, disabled: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	if disabled:
		sb.bg_color = Color8(26, 31, 40)
		sb.border_color = GOLD_D
	elif pressed:
		sb.bg_color = mix(PANEL2, GOLD, 0.25)
		sb.border_color = GOLD_L
	elif hovered:
		sb.bg_color = mix(PANEL2, GOLD, 0.16)
		sb.border_color = GOLD_L
	else:
		sb.bg_color = PANEL2
		sb.border_color = GOLD
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


static func build_app_theme() -> Theme:
	if _app_theme != null:
		return _app_theme
	var t := Theme.new()
	t.default_font = get_body_font()
	t.default_font_size = UIConstants.FONT_BODY
	t.set_constant("title_size", "TCGTypography", UIConstants.FONT_TITLE)
	t.set_constant("header_size", "TCGTypography", UIConstants.FONT_HEADER)
	t.set_constant("body_size", "TCGTypography", UIConstants.FONT_BODY)
	t.set_constant("caption_size", "TCGTypography", UIConstants.FONT_CAPTION)
	t.set_constant("counter_size", "TCGTypography", UIConstants.FONT_COUNTER)
	t.set_font("display", "TCGTypography", get_display_font())
	t.set_font("body", "TCGTypography", get_body_font())
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "RichTextLabel", TEXT)
	t.set_stylebox("panel", "Panel", make_slate_panel_style())
	t.set_stylebox("panel", "PanelContainer", make_slate_panel_style())
	t.set_stylebox("normal", "Button", make_button_style(false, false, false))
	t.set_stylebox("hover", "Button", make_button_style(true, false, false))
	t.set_stylebox("pressed", "Button", make_button_style(false, true, false))
	t.set_stylebox("disabled", "Button", make_button_style(false, false, true))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", GOLD_L)
	t.set_color("font_disabled_color", "Button", DIM)
	t.set_stylebox("panel", "TooltipPanel", make_slate_panel_style(Color8(14, 21, 32), GOLD, GOLD_D, 8, 1))
	t.set_color("font_color", "TooltipLabel", TEXT)
	var scroll_bg := StyleBoxFlat.new()
	scroll_bg.bg_color = Color(0.08, 0.11, 0.16, 0.85)
	scroll_bg.set_corner_radius_all(4)
	var scroll_grab := StyleBoxFlat.new()
	scroll_grab.bg_color = GOLD_D
	scroll_grab.set_corner_radius_all(4)
	var scroll_grab_hi := StyleBoxFlat.new()
	scroll_grab_hi.bg_color = GOLD
	scroll_grab_hi.set_corner_radius_all(4)
	t.set_stylebox("scroll", "VScrollBar", scroll_bg)
	t.set_stylebox("grabber", "VScrollBar", scroll_grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", scroll_grab_hi)
	t.set_stylebox("grabber_pressed", "VScrollBar", scroll_grab_hi)
	_app_theme = t
	return _app_theme


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
		15 if small else 19,
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
	var f: Font = get_display_font() if bold else get_body_font()
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
			2,
			Color(0.0, 0.0, 0.0, 0.78)
		)
	canvas.draw_string(f, baseline, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


static func fit_font_size(
	txt: String,
	max_w: float,
	base_size: int,
	min_size: int = 11,
	bold: bool = false
) -> int:
	if txt.is_empty() or max_w <= 0.0:
		return base_size
	var f: Font = get_display_font() if bold else get_body_font()
	var sz: int = base_size
	while sz > min_size:
		if f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x <= max_w:
			break
		sz -= 1
	return sz


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
	var tw: float = f.get_string_size(title_upper, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
	var sw: float = f.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var n_els: int = elements.size()
	var w: float = maxf(210.0, maxf(tw + 76.0 + float(n_els) * 22.0, sw + 48.0 + float(n_els) * 22.0))
	var h: float = 60.0
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
	var gx: float = rect.position.x + 24.0
	for el_raw in elements:
		var el := String(el_raw)
		var c_pt := Vector2(gx, center.y)
		var gem_col := elem_color(el)
		canvas.draw_circle(c_pt, 10.0, Color(gem_col.r, gem_col.g, gem_col.b, a))
		canvas.draw_arc(c_pt, 10.0, 0.0, TAU, 16, Color(GOLD_L.r, GOLD_L.g, GOLD_L.b, a), 1.5)
		gx += 22.0

	var text_cx: float = (rect.position.x + gx + w - 20.0) * 0.5
	if not sub.is_empty():
		draw_text_centered(canvas, title_upper, Vector2(text_cx, center.y - 10.0), 19, Color(GOLD_L.r, GOLD_L.g, GOLD_L.b, a), true, false)
		draw_text_centered(canvas, sub, Vector2(text_cx, center.y + 12.0), 14, Color(TEXT.r, TEXT.g, TEXT.b, a), false, false)
	else:
		draw_text_centered(canvas, title_upper, Vector2(text_cx, center.y), 20, Color(GOLD_L.r, GOLD_L.g, GOLD_L.b, a), true, false)


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
	var tw: float = f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	var sw: float = f.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	var w: float = maxf(430.0, maxf(tw, sw) + 92.0)
	var h: float = 64.0
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
		draw_text_centered(canvas, title, Vector2(text_cx, center.y - 11.0), 21, Color(TEXT.r, TEXT.g, TEXT.b, a), true, false)
		draw_text_centered(canvas, sub, Vector2(text_cx, center.y + 12.0), 14, Color(GOLD_L.r, GOLD_L.g, GOLD_L.b, a), false, false)
	else:
		draw_text_centered(canvas, title, Vector2(text_cx, center.y), 22, Color(TEXT.r, TEXT.g, TEXT.b, a), true, false)


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
	var band_h: float = 104.0
	var band := Rect2(0.0, center_y - band_h * 0.5, float(W), band_h)
	canvas.draw_rect(band, Color(0.04, 0.06, 0.09, 0.85 * a))
	canvas.draw_line(Vector2(0.0, band.position.y), Vector2(float(W), band.position.y), Color(GOLD.r, GOLD.g, GOLD.b, a), 2.0)
	canvas.draw_line(Vector2(0.0, band.end.y), Vector2(float(W), band.end.y), Color(GOLD.r, GOLD.g, GOLD.b, a), 2.0)

	if not sub.is_empty():
		draw_text_centered(canvas, title, Vector2(float(W) * 0.5, center_y - 14.0), 38, Color(title_col.r, title_col.g, title_col.b, a), true, true)
		draw_text_centered(canvas, sub, Vector2(float(W) * 0.5, center_y + 24.0), 17, Color(TEXT.r, TEXT.g, TEXT.b, a), false, true)
	else:
		draw_text_centered(canvas, title, Vector2(float(W) * 0.5, center_y), 40, Color(title_col.r, title_col.g, title_col.b, a), true, true)



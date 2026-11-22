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
	"Swirl": {"elements": ["Anemo"], "desc": "2 damage to the other characters"},
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


static func draw_genshin_pill(
	canvas: CanvasItem,
	rect: Rect2,
	label: String,
	hovered: bool = false,
	disabled: bool = false,
	icon_kind: String = "confirm"
) -> void:
	## Iconic Genshin Genius Invokation ivory-and-gold pill button (Confirm, Play Card, End Round, etc.).
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var r: int = int(rect.size.y * 0.5)
	var fill := Color8(242, 234, 214) if not hovered else Color8(255, 249, 232)
	if disabled:
		fill = Color8(92, 94, 102)
	var border := GOLD_L if hovered else (GOLD_D if disabled else GOLD)
	if hovered and not disabled:
		draw_rounded_box(canvas, rect.grow(3.0), Color(GOLD_L.r, GOLD_L.g, GOLD_L.b, 0.18), Color(GOLD_L.r, GOLD_L.g, GOLD_L.b, 0.55), r + 2, 1)
	draw_rounded_box(canvas, rect, fill, border, r, 2, Vector2(0, 3), 105)
	var inner := rect.grow(-3.0)
	if inner.size.x > 6.0 and inner.size.y > 6.0:
		var isb := StyleBoxFlat.new()
		isb.bg_color = Color(0, 0, 0, 0)
		isb.border_color = Color(GOLD_D.r, GOLD_D.g, GOLD_D.b, 0.45 if not disabled else 0.25)
		isb.set_border_width_all(1)
		isb.set_corner_radius_all(maxi(4, r - 3))
		canvas.draw_style_box(isb, inner)

	var text_cx := rect.get_center().x
	if not icon_kind.is_empty() and rect.size.x >= 130.0:
		var ic := Vector2(rect.position.x + rect.size.y * 0.52, rect.get_center().y)
		var ir := rect.size.y * 0.30
		var badge_bg := Color8(48, 52, 62) if not disabled else Color8(62, 64, 70)
		canvas.draw_circle(ic, ir, badge_bg)
		canvas.draw_arc(ic, ir, 0.0, TAU, 20, GOLD_L if not disabled else DIM, 1.6)
		if icon_kind == "cancel":
			var d := ir * 0.42
			canvas.draw_line(ic + Vector2(-d, -d), ic + Vector2(d, d), RED, 2.0)
			canvas.draw_line(ic + Vector2(d, -d), ic + Vector2(-d, d), RED, 2.0)
		else:
			canvas.draw_circle(ic, ir * 0.44, GOLD_L if not disabled else DIM)
		text_cx = rect.get_center().x + 10.0

	var txt_col := Color8(46, 38, 30) if not disabled else Color8(186, 190, 198)
	var fsz := fit_font_size(label, rect.size.x - 46.0, 17 if rect.size.y >= 46.0 else 14, 12, true)
	draw_text_centered(canvas, label, Vector2(text_cx, rect.get_center().y), fsz, txt_col, true, false)


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
	var f: Font = get_display_font() if bold else get_body_font()
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
	var f: Font = get_display_font() if bold else get_body_font()
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
	var f: Font = get_body_font()
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
	var f_disp: Font = get_display_font()
	var f_body: Font = get_body_font()
	var tw: float = f_disp.get_string_size(title_upper, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	var sw: float = f_body.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var n_els: int = elements.size()
	var w: float = maxf(188.0, maxf(tw + 64.0 + float(n_els) * 24.0, sw + 44.0 + float(n_els) * 24.0))
	var h: float = 48.0 if not sub.is_empty() else 36.0
	var rect := Rect2(center.x - w * 0.5, center.y - h * 0.5, w, h)

	draw_rounded_box(
		canvas,
		rect,
		Color(0.06, 0.08, 0.13, 0.90 * a),
		Color(GOLD_L.r, GOLD_L.g, GOLD_L.b, 0.92 * a),
		int(h * 0.5),
		2,
		Vector2(0, 3),
		int(85.0 * a)
	)

	var gx: float = rect.position.x + 22.0
	for el_raw in elements:
		var el := String(el_raw)
		var ec := elem_color(el)
		TCGArt.draw_elem_symbol(canvas, el, Vector2(gx, center.y), 9.5, Color(ec.r, ec.g, ec.b, a), false)
		gx += 22.0

	var text_cx: float = (gx + rect.end.x - 14.0) * 0.5
	if not sub.is_empty():
		draw_text_centered(canvas, title_upper, Vector2(text_cx, center.y - 8.0), 17, Color(GOLD_L.r, GOLD_L.g, GOLD_L.b, a), true, true)
		draw_text_centered(canvas, sub, Vector2(text_cx, center.y + 10.0), 12, Color(TEXT.r, TEXT.g, TEXT.b, 0.92 * a), false, false)
	else:
		draw_text_centered(canvas, title_upper, Vector2(text_cx, center.y), 17, Color(GOLD_L.r, GOLD_L.g, GOLD_L.b, a), true, true)


static func draw_action_ribbon(
	canvas: CanvasItem,
	title: String,
	sub: String,
	accent_col: Color,
	center: Vector2,
	alpha: float = 1.0,
	char_name: String = "",
	align_right: bool = false
) -> void:
	## Genshin-style side-mounted Skill/Switch Banner with circular character portrait medallion.
	if alpha <= 0.01:
		return
	var a: float = clampf(alpha, 0.0, 1.0)
	var f_disp: Font = get_display_font()
	var f_body: Font = get_body_font()
	var tw: float = f_disp.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
	var sw: float = f_body.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var w: float = maxf(310.0, maxf(tw, sw) + 96.0)
	var h: float = 58.0
	var rect := Rect2(center.x - w * 0.5, center.y - h * 0.5, w, h)

	draw_rounded_box(
		canvas,
		rect,
		Color(0.06, 0.09, 0.14, 0.92 * a),
		Color(accent_col.r, accent_col.g, accent_col.b, 0.85 * a),
		29,
		2,
		Vector2(0, 4),
		int(95.0 * a)
	)

	var av_c := Vector2(rect.end.x - 31.0 if align_right else rect.position.x + 31.0, center.y)
	var av_r := 22.0
	canvas.draw_circle(av_c, av_r, Color(0.08, 0.11, 0.17, a))
	var ch_tex := TCGArt.get_character_texture(char_name) if not char_name.is_empty() else null
	if ch_tex != null:
		var pr := Rect2(av_c - Vector2(av_r - 3.0, av_r - 3.0), Vector2((av_r - 3.0) * 2.0, (av_r - 3.0) * 2.0))
		TCGArt.draw_texture_cover(canvas, ch_tex, pr, Color(1, 1, 1, a), 0.16)
		canvas.draw_arc(av_c, av_r - 1.5, 0.0, TAU, 28, Color(0.06, 0.09, 0.14, 0.96 * a), 4.0)
	else:
		canvas.draw_circle(av_c, av_r * 0.55, Color(accent_col.r, accent_col.g, accent_col.b, 0.78 * a))
	canvas.draw_arc(av_c, av_r, 0.0, TAU, 28, Color(GOLD_L.r, GOLD_L.g, GOLD_L.b, a), 2.2)

	var text_cx: float = (rect.position.x + 18.0 + av_c.x - av_r - 10.0) * 0.5 if align_right else (av_c.x + av_r + 12.0 + rect.end.x - 18.0) * 0.5
	if not sub.is_empty():
		draw_text_centered(canvas, title, Vector2(text_cx, center.y - 10.0), 19, Color(TEXT.r, TEXT.g, TEXT.b, a), true, true)
		draw_text_centered(canvas, sub, Vector2(text_cx, center.y + 11.0), 13, Color(GOLD_L.r, GOLD_L.g, GOLD_L.b, 0.92 * a), false, false)
	else:
		draw_text_centered(canvas, title, Vector2(text_cx, center.y), 19, Color(TEXT.r, TEXT.g, TEXT.b, a), true, true)


static func draw_phase_announcement(
	canvas: CanvasItem,
	title: String,
	sub: String,
	title_col: Color,
	center_y: float = 540.0,
	alpha: float = 1.0
) -> void:
	## Sleek Genshin horizontal translucent center ribbon with tapered edges & gold hairlines.
	if alpha <= 0.01:
		return
	var a: float = clampf(alpha, 0.0, 1.0)
	var band_h: float = 68.0 if not sub.is_empty() else 52.0
	var cx := float(W) * 0.5
	# Tapered horizontal segments for soft edge fade
	var segs: Array[Array] = [
		[1100.0, 0.78],
		[1460.0, 0.42],
		[1780.0, 0.16],
	]
	for sg in segs:
		var sw: float = float(sg[0])
		var sa: float = float(sg[1]) * a
		canvas.draw_rect(Rect2(cx - sw * 0.5, center_y - band_h * 0.5, sw, band_h), Color(0.05, 0.08, 0.13, sa))

	var line_w: float = 960.0
	var gcol := Color(GOLD_L.r, GOLD_L.g, GOLD_L.b, 0.78 * a)
	canvas.draw_line(Vector2(cx - line_w * 0.5, center_y - band_h * 0.5), Vector2(cx + line_w * 0.5, center_y - band_h * 0.5), gcol, 1.5)
	canvas.draw_line(Vector2(cx - line_w * 0.5, center_y + band_h * 0.5), Vector2(cx + line_w * 0.5, center_y + band_h * 0.5), gcol, 1.5)
	# Small diamond end ornaments
	for sx in [cx - line_w * 0.5, cx + line_w * 0.5]:
		for sy in [center_y - band_h * 0.5, center_y + band_h * 0.5]:
			canvas.draw_colored_polygon(PackedVector2Array([
				Vector2(sx, sy - 3.5), Vector2(sx + 3.5, sy), Vector2(sx, sy + 3.5), Vector2(sx - 3.5, sy)
			]), gcol)

	if not sub.is_empty():
		draw_text_centered(canvas, title, Vector2(cx, center_y - 10.0), 27, Color(title_col.r, title_col.g, title_col.b, a), true, true)
		draw_text_centered(canvas, sub, Vector2(cx, center_y + 16.0), 14, Color(TEXT.r, TEXT.g, TEXT.b, 0.92 * a), false, true)
	else:
		draw_text_centered(canvas, title, Vector2(cx, center_y), 28, Color(title_col.r, title_col.g, title_col.b, a), true, true)



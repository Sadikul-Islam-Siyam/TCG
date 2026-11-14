class_name TCGArt
extends RefCounted
## Stage 5: Procedural Vector Art & Asset Loader
## Direct port of PythonTCG/ui/art.py (elemental crests, hexagonal dice, cost gems,
## status/equipment badges, portrait loader + procedural character fallback art,
## parchment card frames, card backs, and dueling mat).

# Optional per-character procedural portrait accent overrides:
# "Character Name": [top_col, bot_col, glow_col, weapon_type, motif]
const CHAR_ACCENT: Dictionary = {}

static var _texture_cache: Dictionary = {}


static func clear_cache() -> void:
	_texture_cache.clear()


static func _get_named_texture(folder: String, item_name: String) -> Texture2D:
	if item_name.is_empty():
		return null
	var cache_key := "%s/%s" % [folder, item_name]
	if _texture_cache.has(cache_key):
		return _texture_cache[cache_key]
	var exts: Array[String] = ["png", "jpg", "jpeg", "webp"]
	for ext in exts:
		var res_path := "res://assets/%s/%s.%s" % [folder, item_name, ext]
		if ResourceLoader.exists(res_path):
			var tex := load(res_path) as Texture2D
			if tex != null:
				_texture_cache[cache_key] = tex
				return tex
		# Fallback to Image.load_from_file in case asset was copied before import
		var abs_path := ProjectSettings.globalize_path(res_path)
		if FileAccess.file_exists(abs_path):
			var img := Image.load_from_file(abs_path)
			if img != null and not img.is_empty():
				var tex := ImageTexture.create_from_image(img)
				_texture_cache[cache_key] = tex
				return tex
	_texture_cache[cache_key] = null
	return null


static func get_character_texture(name: String) -> Texture2D:
	return _get_named_texture("characters", name)


static func get_card_texture(name: String) -> Texture2D:
	return _get_named_texture("cards", name)


static func draw_texture_cover(
	canvas: CanvasItem,
	tex: Texture2D,
	rect: Rect2,
	mod: Color = Color.WHITE,
	y_bias: float = 0.5
) -> void:
	if tex == null or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var tw: float = tex.get_width()
	var th: float = tex.get_height()
	if tw <= 0.0 or th <= 0.0:
		return
	var scale_f: float = maxf(rect.size.x / tw, rect.size.y / th)
	var vis_w: float = rect.size.x / scale_f
	var vis_h: float = rect.size.y / scale_f
	var src_x: float = maxf(0.0, (tw - vis_w) * 0.5)
	var src_y: float = maxf(0.0, (th - vis_h) * y_bias)
	var src_rect := Rect2(src_x, src_y, vis_w, vis_h)
	canvas.draw_texture_rect_region(tex, rect, src_rect, mod)


static func draw_elem_symbol(
	canvas: CanvasItem,
	elem: String,
	center: Vector2,
	r: float,
	col: Color = Color(0, 0, 0, 0),
	bg: bool = true
) -> void:
	var c: Color = col if col.a > 0.0 else TCGTheme.elem_color(elem)
	if bg:
		canvas.draw_circle(center, r + 2.0, TCGTheme.elem_dark(elem))
		canvas.draw_arc(center, r + 2.0, 0.0, TAU, 24, TCGTheme.shade(c, 0.85), 2.0)

	match elem:
		"Pyro":
			var pts := PackedVector2Array([
				Vector2(center.x, center.y - r),
				Vector2(center.x + r * 0.72, center.y + r * 0.15),
				Vector2(center.x + r * 0.35, center.y + r * 0.9),
				Vector2(center.x, center.y + r * 0.45),
				Vector2(center.x - r * 0.35, center.y + r * 0.9),
				Vector2(center.x - r * 0.72, center.y + r * 0.15),
			])
			canvas.draw_colored_polygon(pts, c)
			var inner := PackedVector2Array([
				Vector2(center.x, center.y - r * 0.45),
				Vector2(center.x + r * 0.32, center.y + r * 0.2),
				Vector2(center.x, center.y + r * 0.65),
				Vector2(center.x - r * 0.32, center.y + r * 0.2),
			])
			canvas.draw_colored_polygon(inner, TCGTheme.GOLD_L)
		"Hydro":
			var pts := PackedVector2Array([
				Vector2(center.x, center.y - r),
				Vector2(center.x + r * 0.7, center.y + r * 0.1),
				Vector2(center.x + r * 0.5, center.y + r * 0.75),
				Vector2(center.x, center.y + r * 0.95),
				Vector2(center.x - r * 0.5, center.y + r * 0.75),
				Vector2(center.x - r * 0.7, center.y + r * 0.1),
			])
			canvas.draw_colored_polygon(pts, c)
			canvas.draw_circle(Vector2(center.x - r * 0.2, center.y + r * 0.1), maxf(1.0, r * 0.22), Color8(210, 240, 255))
		"Cryo":
			for k in range(6):
				var a: float = k * PI / 3.0
				var x2: float = center.x + cos(a) * r
				var y2: float = center.y + sin(a) * r
				canvas.draw_line(center, Vector2(x2, y2), c, 2.0)
			var d_pts := PackedVector2Array([
				Vector2(center.x, center.y - r * 0.45),
				Vector2(center.x + r * 0.45, center.y),
				Vector2(center.x, center.y + r * 0.45),
				Vector2(center.x - r * 0.45, center.y),
			])
			canvas.draw_colored_polygon(d_pts, Color8(230, 248, 255))
		"Electro":
			var pts := PackedVector2Array([
				Vector2(center.x + r * 0.2, center.y - r),
				Vector2(center.x - r * 0.55, center.y + r * 0.05),
				Vector2(center.x - r * 0.05, center.y + r * 0.05),
				Vector2(center.x - r * 0.3, center.y + r),
				Vector2(center.x + r * 0.6, center.y - r * 0.1),
				Vector2(center.x + r * 0.08, center.y - r * 0.1),
			])
			canvas.draw_colored_polygon(pts, c)
		"Anemo":
			for k in range(3):
				var a0: float = k * 2.0 * PI / 3.0
				var p1 := Vector2(center.x + cos(a0) * r * 0.2, center.y + sin(a0) * r * 0.2)
				var p2 := Vector2(center.x + cos(a0 + 0.55) * r * 0.95, center.y + sin(a0 + 0.55) * r * 0.95)
				var p3 := Vector2(center.x + cos(a0 + 1.05) * r * 0.55, center.y + sin(a0 + 1.05) * r * 0.55)
				canvas.draw_colored_polygon(PackedVector2Array([center, p1, p2, p3]), c)
			canvas.draw_circle(center, maxf(2.0, r * 0.25), Color8(225, 255, 244))
		"Geo":
			var pts := PackedVector2Array([
				Vector2(center.x, center.y - r),
				Vector2(center.x + r * 0.85, center.y),
				Vector2(center.x, center.y + r),
				Vector2(center.x - r * 0.85, center.y),
			])
			canvas.draw_colored_polygon(pts, c)
			var poly_line := PackedVector2Array([
				Vector2(center.x, center.y - r * 0.52),
				Vector2(center.x + r * 0.45, center.y),
				Vector2(center.x, center.y + r * 0.52),
				Vector2(center.x - r * 0.45, center.y),
				Vector2(center.x, center.y - r * 0.52),
			])
			canvas.draw_polyline(poly_line, Color8(90, 62, 18), 2.0)
		"Omni":
			var pts := PackedVector2Array()
			for k in range(8):
				var a: float = k * PI / 4.0 - PI / 2.0
				var rr: float = r if k % 2 == 0 else r * 0.45
				pts.append(Vector2(center.x + cos(a) * rr, center.y + sin(a) * rr))
			canvas.draw_colored_polygon(pts, TCGTheme.GOLD_L)
			canvas.draw_circle(center, maxf(2.0, r * 0.28), Color.WHITE)
		_:
			# Physical / Piercing star blade
			var pts := PackedVector2Array([
				Vector2(center.x, center.y - r),
				Vector2(center.x + r * 0.35, center.y - r * 0.35),
				Vector2(center.x + r, center.y),
				Vector2(center.x + r * 0.35, center.y + r * 0.35),
				Vector2(center.x, center.y + r),
				Vector2(center.x - r * 0.35, center.y + r * 0.35),
				Vector2(center.x - r, center.y),
				Vector2(center.x - r * 0.35, center.y - r * 0.35),
			])
			canvas.draw_colored_polygon(pts, c)


static func draw_die(
	canvas: CanvasItem,
	elem: String,
	rect: Rect2,
	selected: bool = false,
	hovered: bool = false,
	angle: float = 0.0,
	scale: float = 1.0,
	dim: bool = false
) -> void:
	var c := rect.get_center()
	var base_r: float = minf(rect.size.x, rect.size.y) * 0.5 - 2.0
	var r: float = base_r * scale
	var col := TCGTheme.elem_color(elem)
	var dark := TCGTheme.elem_dark(elem)
	var pts := PackedVector2Array()
	var sh_pts := PackedVector2Array()

	if selected or hovered:
		canvas.draw_circle(c, r * 1.15, Color(TCGTheme.GOLD_L.r, TCGTheme.GOLD_L.g, TCGTheme.GOLD_L.b, 0.22))

	for k in range(6):
		var a: float = k * PI / 3.0 - PI / 6.0 + angle
		var pt := Vector2(c.x + cos(a) * r, c.y + sin(a) * r)
		pts.append(pt)
		sh_pts.append(pt + Vector2(0, 3.0 * scale))

	canvas.draw_colored_polygon(sh_pts, Color(0, 0, 0, 0.45))
	var fill_col := dark if not selected else TCGTheme.mix(dark, col, 0.35)
	if dim:
		fill_col = Color(fill_col.r * 0.45, fill_col.g * 0.45, fill_col.b * 0.45, 0.75)
	canvas.draw_colored_polygon(pts, fill_col)

	var top_facet := PackedVector2Array([c, pts[4], pts[5], pts[0], pts[1]])
	var facet_col := TCGTheme.mix(dark, col, 0.22)
	if dim:
		facet_col = Color(facet_col.r * 0.45, facet_col.g * 0.45, facet_col.b * 0.45, 0.75)
	canvas.draw_colored_polygon(top_facet, facet_col)

	var border := TCGTheme.GOLD_L if (selected or hovered) else (col if not dim else TCGTheme.shade(col, 0.4))
	var closed_pts := pts.duplicate()
	closed_pts.append(pts[0])
	canvas.draw_polyline(closed_pts, border, (3.0 if selected else 2.0) * scale)

	var sym_col := col if not dim else TCGTheme.shade(col, 0.5)
	draw_elem_symbol(canvas, elem, c, maxf(4.0, r * 0.5), sym_col, false)


static func draw_cost_gem(
	canvas: CanvasItem,
	kind: String,
	val: int,
	center: Vector2,
	r: float = 12.0
) -> void:
	if kind == "Energy":
		var pts := PackedVector2Array([
			Vector2(center.x, center.y - r),
			Vector2(center.x + r * 0.85, center.y),
			Vector2(center.x, center.y + r),
			Vector2(center.x - r * 0.85, center.y),
		])
		canvas.draw_colored_polygon(pts, Color8(92, 60, 18))
		var closed := pts.duplicate()
		closed.append(pts[0])
		canvas.draw_polyline(closed, TCGTheme.GOLD_L, 2.0)
	elif kind == "Same":
		canvas.draw_circle(center, r, Color8(72, 66, 86))
		canvas.draw_arc(center, r, 0.0, TAU, 24, TCGTheme.GOLD_L, 2.0)
	elif kind == "Any":
		canvas.draw_circle(center, r, Color8(40, 46, 58))
		canvas.draw_arc(center, r, 0.0, TAU, 24, Color8(185, 195, 210), 2.0)
	else:
		canvas.draw_circle(center, r, TCGTheme.elem_dark(kind))
		canvas.draw_arc(center, r, 0.0, TAU, 24, TCGTheme.elem_color(kind), 2.0)
	TCGTheme.draw_text_centered(canvas, str(val), center, int(r * 1.08), Color.WHITE, true, true)


static func draw_status_badge(
	canvas: CanvasItem,
	rect: Rect2,
	kind: String,
	elem: String = "Physical",
	usages: int = 0
) -> void:
	var c := rect.get_center()
	var r: float = minf(rect.size.x, rect.size.y) * 0.5 - 1.0
	var ed := ElementDB.get_element(elem)
	var col := ed.color if (ed != null and String(ed.id) == elem) else TCGTheme.GOLD
	canvas.draw_circle(c, r, Color8(24, 34, 48))
	canvas.draw_arc(c, r, 0.0, TAU, 20, col, 2.0)

	match kind:
		"shield":
			var pts := PackedVector2Array([
				Vector2(c.x - r * 0.55, c.y - r * 0.45),
				Vector2(c.x + r * 0.55, c.y - r * 0.45),
				Vector2(c.x + r * 0.5, c.y + r * 0.15),
				Vector2(c.x, c.y + r * 0.68),
				Vector2(c.x - r * 0.5, c.y + r * 0.15),
			])
			canvas.draw_colored_polygon(pts, TCGTheme.GOLD_L)
		"weapon":
			canvas.draw_line(
				Vector2(c.x - r * 0.45, c.y + r * 0.45),
				Vector2(c.x + r * 0.45, c.y - r * 0.45),
				Color8(230, 236, 245),
				3.0
			)
			canvas.draw_line(
				Vector2(c.x - r * 0.35, c.y - r * 0.05),
				Vector2(c.x + r * 0.05, c.y + r * 0.35),
				TCGTheme.GOLD,
				2.0
			)
		"artifact":
			canvas.draw_arc(c, maxf(3.0, r * 0.52), 0.0, TAU, 16, TCGTheme.GOLD_L, 2.0)
			canvas.draw_circle(Vector2(c.x, c.y - r * 0.52), 3.0, col)
		"freeze":
			draw_elem_symbol(canvas, "Cryo", c, maxf(4.0, r * 0.55), TCGTheme.elem_color("Cryo"), false)
		"food":
			canvas.draw_circle(c, maxf(3.0, r * 0.45), Color8(235, 175, 105))
		_:
			var pts := PackedVector2Array([
				Vector2(c.x, c.y - r * 0.55),
				Vector2(c.x + r * 0.45, c.y + r * 0.1),
				Vector2(c.x + r * 0.2, c.y + r * 0.1),
				Vector2(c.x + r * 0.2, c.y + r * 0.55),
				Vector2(c.x - r * 0.2, c.y + r * 0.55),
				Vector2(c.x - r * 0.2, c.y + r * 0.1),
				Vector2(c.x - r * 0.45, c.y + r * 0.1),
			])
			canvas.draw_colored_polygon(pts, col)

	if usages > 0:
		var badge_c := Vector2(rect.end.x - 3.0, rect.end.y - 3.0)
		canvas.draw_circle(badge_c, 7.0, Color8(18, 22, 30))
		canvas.draw_arc(badge_c, 7.0, 0.0, TAU, 14, TCGTheme.GOLD, 1.0)
		TCGTheme.draw_text_centered(canvas, str(usages), badge_c, 10, TCGTheme.GOLD_L, true, false)


static func _draw_weapon_silhouette(
	canvas: CanvasItem,
	wtype: String,
	cx: float,
	cy: float,
	scale: float,
	col: Color
) -> void:
	var s := scale
	match wtype:
		"Sword":
			canvas.draw_line(Vector2(cx - 18 * s, cy + 20 * s), Vector2(cx + 20 * s, cy - 22 * s), col, maxf(2.0, 3.0 * s))
			canvas.draw_line(Vector2(cx - 14 * s, cy + 4 * s), Vector2(cx - 2 * s, cy + 16 * s), TCGTheme.GOLD_L, maxf(2.0, 3.0 * s))
		"Claymore":
			var pts := PackedVector2Array([
				Vector2(cx - 20 * s, cy + 22 * s),
				Vector2(cx - 12 * s, cy + 22 * s),
				Vector2(cx + 22 * s, cy - 16 * s),
				Vector2(cx + 22 * s, cy - 24 * s),
				Vector2(cx + 14 * s, cy - 24 * s),
				Vector2(cx - 20 * s, cy + 14 * s),
			])
			canvas.draw_colored_polygon(pts, col)
		"Bow":
			canvas.draw_arc(Vector2(cx, cy), 22.0 * s, -1.1, 1.1, 16, col, maxf(2.0, 3.0 * s))
			canvas.draw_line(Vector2(cx + 9 * s, cy - 19 * s), Vector2(cx + 9 * s, cy + 19 * s), TCGTheme.GOLD_L, 1.0)
		"Polearm":
			canvas.draw_line(Vector2(cx - 22 * s, cy + 22 * s), Vector2(cx + 18 * s, cy - 18 * s), col, maxf(2.0, 2.0 * s))
			var tip := PackedVector2Array([
				Vector2(cx + 24 * s, cy - 24 * s),
				Vector2(cx + 12 * s, cy - 20 * s),
				Vector2(cx + 20 * s, cy - 12 * s),
			])
			canvas.draw_colored_polygon(tip, TCGTheme.GOLD_L)
		_:
			# Catalyst
			canvas.draw_arc(Vector2(cx, cy), 16.0 * s, 0.0, TAU, 20, col, 2.0)
			canvas.draw_arc(Vector2(cx, cy), 9.0 * s, 0.0, TAU, 16, TCGTheme.GOLD_L, 1.0)


static func draw_portrait(
	canvas: CanvasItem,
	name: String,
	elem: String,
	rect: Rect2,
	defeated: bool = false
) -> void:
	var tex := get_character_texture(name)
	if tex != null:
		var mod := Color(0.35, 0.35, 0.38, 1.0) if defeated else Color.WHITE
		draw_texture_cover(canvas, tex, rect, mod, 0.2)
		return

	# Procedural portrait fallback matching PythonTCG art.portrait
	var info: Array = CHAR_ACCENT.get(
		name,
		[TCGTheme.elem_color(elem), TCGTheme.elem_dark(elem), Color.WHITE, "Sword", "hero"]
	)
	var top_col: Color = info[0]
	var bot_col: Color = info[1]
	var glow_col: Color = info[2]
	var wtype: String = info[3]

	# Vertical gradient strips
	var strips: int = 18
	for i in range(strips):
		var y0: float = rect.position.y + (rect.size.y * float(i) / float(strips))
		var y1: float = rect.position.y + (rect.size.y * float(i + 1) / float(strips))
		var c := TCGTheme.mix(top_col, bot_col, float(i) / float(strips - 1))
		if defeated:
			var g: float = (c.r + c.g + c.b) / 3.0 * 0.45
			c = Color(g, g, g, 1.0)
		canvas.draw_rect(Rect2(rect.position.x, y0, rect.size.x, y1 - y0 + 1.0), c)

	var cx: float = rect.position.x + rect.size.x * 0.5
	var cy: float = rect.position.y + rect.size.y * 0.43
	var halo_r: float = minf(rect.size.x, rect.size.y) * 0.36
	var ring_col := glow_col if not defeated else Color8(95, 98, 108)
	canvas.draw_arc(Vector2(cx, cy), halo_r, 0.0, TAU, 24, TCGTheme.shade(ring_col, 0.75), 2.0)
	canvas.draw_arc(Vector2(cx, cy), halo_r - 6.0, 0.0, TAU, 24, TCGTheme.shade(ring_col, 0.5), 1.0)

	# Stylized Bust & Hair Silhouette
	var bust_col := TCGTheme.mix(bot_col, Color8(245, 236, 224), 0.25)
	if defeated:
		bust_col = Color8(60, 62, 70)
	var shoulders := PackedVector2Array([
		Vector2(cx - rect.size.x * 0.38, rect.end.y),
		Vector2(cx - rect.size.x * 0.28, cy + halo_r * 0.45),
		Vector2(cx + rect.size.x * 0.28, cy + halo_r * 0.45),
		Vector2(cx + rect.size.x * 0.38, rect.end.y),
	])
	canvas.draw_colored_polygon(shoulders, bust_col)
	var collar := PackedVector2Array([
		Vector2(cx - rect.size.x * 0.14, cy + halo_r * 0.45),
		Vector2(cx, cy + halo_r * 0.85),
		Vector2(cx + rect.size.x * 0.14, cy + halo_r * 0.45),
	])
	canvas.draw_colored_polygon(collar, ring_col)

	var head_r: float = halo_r * 0.48
	var skin_col := Color8(244, 224, 204) if not defeated else Color8(115, 115, 122)
	canvas.draw_circle(Vector2(cx, cy - 2.0), head_r, skin_col)

	var hair_col := TCGTheme.mix(top_col, glow_col, 0.45) if not defeated else Color8(85, 88, 96)
	var hair_pts := PackedVector2Array([
		Vector2(cx - head_r * 1.15, cy - head_r * 0.1),
		Vector2(cx - head_r * 0.95, cy - head_r * 1.05),
		Vector2(cx, cy - head_r * 1.25),
		Vector2(cx + head_r * 0.95, cy - head_r * 1.05),
		Vector2(cx + head_r * 1.15, cy - head_r * 0.1),
		Vector2(cx + head_r * 0.7, cy - head_r * 0.45),
		Vector2(cx, cy - head_r * 0.3),
		Vector2(cx - head_r * 0.7, cy - head_r * 0.45),
	])
	canvas.draw_colored_polygon(hair_pts, hair_col)

	_draw_weapon_silhouette(
		canvas,
		wtype,
		rect.end.x - 22.0,
		rect.end.y - 26.0,
		0.55,
		TCGTheme.shade(ring_col, 0.9)
	)



static func draw_card_parchment(
	canvas: CanvasItem,
	rect: Rect2,
	accent: Color = TCGTheme.GOLD,
	selected: bool = false,
	hovered: bool = false
) -> void:
	var border := TCGTheme.GOLD_L if (selected or hovered) else accent
	TCGTheme.draw_rounded_box(
		canvas,
		rect,
		TCGTheme.PARCH,
		border,
		10,
		3 if (selected or hovered) else 2,
		Vector2(0, 4),
		95
	)
	var inner := rect.grow(-4.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = TCGTheme.GOLD_D
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(7)
	canvas.draw_style_box(sb, inner)


static func draw_card_back(canvas: CanvasItem, rect: Rect2) -> void:
	TCGTheme.draw_rounded_box(
		canvas,
		rect,
		Color8(26, 40, 62),
		TCGTheme.GOLD,
		8,
		2,
		Vector2(0, 3),
		90
	)
	var inner := rect.grow(-5.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = TCGTheme.GOLD_D
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(5)
	canvas.draw_style_box(sb, inner)
	var c := rect.get_center()
	var r: float = minf(rect.size.x, rect.size.y) * 0.24
	canvas.draw_arc(c, r + 4.0, 0.0, TAU, 20, TCGTheme.GOLD, 1.0)
	draw_elem_symbol(canvas, "Omni", c, r, TCGTheme.GOLD_L, false)


static func draw_mat(canvas: CanvasItem, size: Vector2, shimmer_t: float = 0.0, table_rect_override: Rect2 = Rect2()) -> void:
	var w: float = size.x
	var h: float = size.y
	# Outer dark wood / stone background
	var strips: int = 36
	for i in range(strips):
		var y0: float = h * float(i) / float(strips)
		var y1: float = h * float(i + 1) / float(strips)
		var t: float = absf((float(i) / float(strips - 1)) - 0.5) * 2.0
		var c := TCGTheme.mix(Color8(26, 42, 60), Color8(11, 18, 28), t * 0.85)
		canvas.draw_rect(Rect2(0, y0, w, y1 - y0 + 2.0), c)

	# Recessed playing table (scales responsively for 16:9, 19.5:9, 4:3)
	var safe: Rect2 = UIConstants.get_safe_rect(size)
	var pad_x: float = clampf(safe.size.x * 0.132, 180.0, 255.0)
	var table := table_rect_override if table_rect_override.size.x > 10.0 else Rect2(
		safe.position.x + pad_x,
		safe.position.y + safe.size.y * 0.056,
		maxf(520.0, safe.size.x - pad_x * 2.0),
		maxf(400.0, safe.size.y * 0.715)
	)
	TCGTheme.draw_rounded_box(
		canvas,
		table.grow(10),
		Color8(48, 34, 22),
		TCGTheme.GOLD_D,
		18,
		3,
		Vector2(0, 6),
		120
	)
	TCGTheme.draw_rounded_box(
		canvas,
		table,
		Color8(21, 36, 52),
		TCGTheme.GOLD,
		14,
		2
	)
	# Subtle double-bezel inner gold filigree
	var inner_frame := table.grow(-6.0)
	var inner_sb := StyleBoxFlat.new()
	inner_sb.bg_color = Color(0, 0, 0, 0)
	inner_sb.border_color = Color(TCGTheme.GOLD_D.r, TCGTheme.GOLD_D.g, TCGTheme.GOLD_D.b, 0.55)
	inner_sb.set_border_width_all(1)
	inner_sb.set_corner_radius_all(10)
	canvas.draw_style_box(inner_sb, inner_frame)

	# Ornamental felt diamond weave inside table
	var tile_col := Color8(26, 44, 63)
	var weave_col := Color(0.18, 0.28, 0.38, 0.24)
	var step_x: float = 72.0
	var step_y: float = 46.0
	var x: float = table.position.x + 32.0
	var row_shift: bool = false
	while x < table.end.x - 24.0:
		var y: float = table.position.y + 28.0 + (step_y * 0.5 if row_shift else 0.0)
		while y < table.end.y - 24.0:
			var pts := PackedVector2Array([
				Vector2(x, y - 11.0),
				Vector2(x + 17.0, y),
				Vector2(x, y + 11.0),
				Vector2(x - 17.0, y),
				Vector2(x, y - 11.0),
			])
			canvas.draw_polyline(pts, tile_col, 1.0)
			canvas.draw_circle(Vector2(x, y), 1.6, weave_col)
			y += step_y
		x += step_x
		row_shift = not row_shift

	# Slow ambient shimmer band drifting obliquely across the felt (T2.2)
	if shimmer_t > 0.0:
		var sweep: float = fmod(shimmer_t * 0.09, 1.4) - 0.2
		var sx: float = lerpf(table.position.x, table.end.x, sweep)
		var band_pts := PackedVector2Array([
			Vector2(sx - 90.0, table.position.y + 6.0),
			Vector2(sx + 40.0, table.position.y + 6.0),
			Vector2(sx - 60.0, table.end.y - 6.0),
			Vector2(sx - 190.0, table.end.y - 6.0),
		])
		canvas.draw_colored_polygon(band_pts, Color(0.85, 0.90, 1.0, 0.028))

	# Subtle perimeter vignette around felt edges
	var vig_w: float = 28.0
	canvas.draw_rect(Rect2(table.position.x + 2, table.position.y + 2, table.size.x - 4, vig_w), Color(0, 0, 0, 0.16))
	canvas.draw_rect(Rect2(table.position.x + 2, table.end.y - vig_w - 2, table.size.x - 4, vig_w), Color(0, 0, 0, 0.20))

	# Center elemental dueling line & Teyvat rosette emblem
	var mid_y: float = table.get_center().y
	canvas.draw_line(
		Vector2(table.position.x + 24, mid_y),
		Vector2(table.end.x - 24, mid_y),
		TCGTheme.GOLD_D,
		2.0
	)
	var center := Vector2(table.get_center().x, mid_y)
	canvas.draw_circle(center, 58.0, Color8(16, 28, 42))
	canvas.draw_arc(center, 58.0, 0.0, TAU, 40, TCGTheme.GOLD, 2.0)
	canvas.draw_arc(center, 46.0, 0.0, TAU, 36, TCGTheme.GOLD_D, 1.2)
	draw_elem_symbol(canvas, "Omni", center, 16.0, Color(TCGTheme.GOLD.r, TCGTheme.GOLD.g, TCGTheme.GOLD.b, 0.28), false)
	var elems: PackedStringArray = ElementDB.CORE_ELEMENTS
	for i in range(elems.size()):
		var a: float = float(i) * PI / 3.0 - PI / 2.0 + shimmer_t * 0.03
		var ep := Vector2(center.x + cos(a) * 34.0, center.y + sin(a) * 34.0)
		canvas.draw_circle(ep, 4.5, ElementDB.get_color(elems[i]))

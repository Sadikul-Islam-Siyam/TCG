class_name TCGArt
extends RefCounted
## Stage 5 + Enterprise Visual Upgrade: Asset Loader & Genshin-Style TCG Renderer
## Loads custom Board, Card Back, Menu BG, Character Portraits, Action Card Art,
## Element/Dice Logos, and Status/Buff/Debuff PNG Icons with crisp mipmapped rendering
## and clean vector fallbacks.

const CHAR_ACCENT: Dictionary = {}

static var _texture_cache: Dictionary = {}


static func clear_cache() -> void:
	_texture_cache.clear()


static func _load_path_cached(res_path: String) -> Texture2D:
	if _texture_cache.has(res_path):
		return _texture_cache[res_path]
	if ResourceLoader.exists(res_path):
		var tex := load(res_path) as Texture2D
		if tex != null:
			_texture_cache[res_path] = tex
			return tex
	var abs_path := ProjectSettings.globalize_path(res_path)
	if FileAccess.file_exists(abs_path):
		var img := Image.load_from_file(abs_path)
		if img != null and not img.is_empty():
			img.generate_mipmaps()
			var tex := ImageTexture.create_from_image(img)
			_texture_cache[res_path] = tex
			return tex
	_texture_cache[res_path] = null
	return null


static func _get_named_texture(folder: String, item_name: String) -> Texture2D:
	if item_name.is_empty():
		return null
	var cache_key := "%s/%s" % [folder, item_name]
	if _texture_cache.has(cache_key):
		return _texture_cache[cache_key]
	var exts: Array[String] = ["png", "jpg", "jpeg", "webp"]
	for ext in exts:
		var res_path := "res://assets/%s/%s.%s" % [folder, item_name, ext]
		var tex := _load_path_cached(res_path)
		if tex != null:
			_texture_cache[cache_key] = tex
			return tex
	_texture_cache[cache_key] = null
	return null


static func get_character_texture(name: String) -> Texture2D:
	return _get_named_texture("characters", name)


static func get_card_texture(name: String) -> Texture2D:
	return _get_named_texture("cards", name)


static func get_board_texture() -> Texture2D:
	return _get_named_texture("Board_CardBack_Menu", "board")


static func get_card_back_texture() -> Texture2D:
	return _get_named_texture("Board_CardBack_Menu", "card_back")


static func get_menu_bg_texture() -> Texture2D:
	return _get_named_texture("Board_CardBack_Menu", "menu_bg")


static func get_element_icon(elem: String) -> Texture2D:
	if elem.is_empty():
		return null
	return _get_named_texture("Element_Dice_Logos", elem)


static func get_status_icon(icon_key: String) -> Texture2D:
	if icon_key.is_empty():
		return null
	return _get_named_texture("Status_Icons", icon_key)


static func resolve_status_icon_key(status_name: String, kind: String = "") -> String:
	var low := status_name.to_lower()
	if low.find("stun") >= 0:
		return "Stunned"
	if low.find("spirit water") >= 0:
		return "SpiritWater"
	if low.find("carryover") >= 0 or low.find("carry over") >= 0:
		return "DiceCarryover"
	if low.find("shield") >= 0 or low.find("crystallize") >= 0 or kind == "shield":
		return "Shield"
	if low.find("equip") >= 0 or kind == "weapon" or kind == "artifact" or kind == "equipment":
		return "Equipment"
	if low.find("attack") >= 0 or low.find("boost") >= 0 or kind == "buff":
		return "AttackBuff"
	return ""


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
	var alpha: float = col.a if col.a > 0.0 else 1.0
	if bg:
		var dark_bg := TCGTheme.elem_dark(elem)
		canvas.draw_circle(center, r + 2.5, Color(dark_bg.r, dark_bg.g, dark_bg.b, 0.92 * alpha))
		canvas.draw_arc(center, r + 2.5, 0.0, TAU, 28, Color(c.r, c.g, c.b, 0.88 * alpha), 1.8)

	# Prefer crisp custom Element/Dice PNG logo whenever available
	var tex: Texture2D = get_element_icon(elem)
	if tex != null:
		var icon_sz: float = r * 2.15
		var dst := Rect2(center - Vector2(icon_sz * 0.5, icon_sz * 0.5), Vector2(icon_sz, icon_sz))
		var mod := Color(1.0, 1.0, 1.0, alpha)
		# Dim gracefully if caller passed a noticeably darkened tint
		if col.a > 0.0 and col.get_luminance() < 0.35:
			mod = Color(0.55, 0.58, 0.64, alpha)
		canvas.draw_texture_rect(tex, dst, false, mod)
		return

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
			# Crossed-blade Physical / Piercing emblem
			var b_col := Color(c.r, c.g, c.b, alpha)
			canvas.draw_line(center + Vector2(-r * 0.68, r * 0.68), center + Vector2(r * 0.68, -r * 0.68), b_col, maxf(2.2, r * 0.17))
			canvas.draw_line(center + Vector2(-r * 0.68, -r * 0.68), center + Vector2(r * 0.68, r * 0.68), b_col, maxf(2.2, r * 0.17))
			canvas.draw_line(center + Vector2(-r * 0.48, r * 0.16), center + Vector2(-r * 0.16, r * 0.48), TCGTheme.GOLD_L, maxf(1.8, r * 0.12))
			canvas.draw_line(center + Vector2(r * 0.48, r * 0.16), center + Vector2(r * 0.16, r * 0.48), TCGTheme.GOLD_L, maxf(1.8, r * 0.12))


static func _hex_points(center: Vector2, r: float, angle: float = 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in range(6):
		var a: float = k * PI / 3.0 - PI / 2.0 + angle
		pts.append(Vector2(center.x + cos(a) * r, center.y + sin(a) * r))
	return pts


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
	## Genshin-style faceted crystalline elemental die with custom element logo PNG.
	var c := rect.get_center()
	var base_r: float = minf(rect.size.x, rect.size.y) * 0.5 - 2.0
	var r: float = base_r * scale
	var col := TCGTheme.elem_color(elem)
	var dark := TCGTheme.elem_dark(elem)
	var pts := _hex_points(c, r, angle)
	var inner_pts := _hex_points(c, r * 0.80, angle)
	var sh_pts := PackedVector2Array()
	for p in pts:
		sh_pts.append(p + Vector2(0, 3.0 * scale))

	if selected or hovered:
		var halo_a := 0.28 if selected else 0.18
		canvas.draw_circle(c, r * 1.18, Color(TCGTheme.GOLD_L.r, TCGTheme.GOLD_L.g, TCGTheme.GOLD_L.b, halo_a))

	# Drop shadow
	canvas.draw_colored_polygon(sh_pts, Color(0, 0, 0, 0.48))

	# Faceted outer rim fill
	var rim_fill := TCGTheme.mix(dark, col, 0.34 if selected else 0.18)
	if dim:
		rim_fill = Color(rim_fill.r * 0.42, rim_fill.g * 0.42, rim_fill.b * 0.42, 0.72)
	canvas.draw_colored_polygon(pts, rim_fill)

	# Upper crystal specular facet
	var top_facet := PackedVector2Array([c, pts[5], pts[0], pts[1]])
	var spec_col := TCGTheme.mix(col, Color.WHITE, 0.30)
	canvas.draw_colored_polygon(top_facet, Color(spec_col.r, spec_col.g, spec_col.b, 0.14 if dim else 0.30))

	# Recessed dark jewel interior so the glowing PNG crest pops crisply
	var core_fill := TCGTheme.mix(Color8(12, 18, 28), dark, 0.55 if not selected else 0.72)
	if dim:
		core_fill = Color(core_fill.r * 0.55, core_fill.g * 0.55, core_fill.b * 0.55, 0.75)
	canvas.draw_colored_polygon(inner_pts, core_fill)

	# Crisp crystalline border
	var border := TCGTheme.GOLD_L if (selected or hovered) else (TCGTheme.mix(col, TCGTheme.GOLD_L, 0.25) if not dim else TCGTheme.shade(col, 0.40))
	var closed_pts := pts.duplicate()
	closed_pts.append(pts[0])
	canvas.draw_polyline(closed_pts, border, (2.8 if selected else 1.9) * scale, true)

	var inner_closed := inner_pts.duplicate()
	inner_closed.append(inner_pts[0])
	canvas.draw_polyline(inner_closed, Color(col.r, col.g, col.b, 0.25 if dim else 0.45), 1.0 * scale, true)

	var sym_col := Color(col.r, col.g, col.b, 0.45 if dim else 1.0)
	if dim:
		sym_col = Color(0.28, 0.30, 0.34, 0.55)
	draw_elem_symbol(canvas, elem, c, maxf(5.0, r * 0.62), sym_col, false)


static func draw_cost_gem(
	canvas: CanvasItem,
	kind: String,
	val: int,
	center: Vector2,
	r: float = 12.0
) -> void:
	## Genshin-style faceted hexagonal / diamond cost gem with shadow and crisp number.
	if kind == "Energy":
		var pts := PackedVector2Array([
			Vector2(center.x, center.y - r * 1.05),
			Vector2(center.x + r * 0.86, center.y),
			Vector2(center.x, center.y + r * 1.05),
			Vector2(center.x - r * 0.86, center.y),
		])
		var sh := PackedVector2Array()
		for p in pts:
			sh.append(p + Vector2(0, 2.0))
		canvas.draw_colored_polygon(sh, Color(0, 0, 0, 0.45))
		canvas.draw_colored_polygon(pts, Color8(116, 76, 20))
		canvas.draw_colored_polygon(PackedVector2Array([center, pts[3], pts[0], pts[1]]), Color(1.0, 0.88, 0.45, 0.22))
		var closed := pts.duplicate()
		closed.append(pts[0])
		canvas.draw_polyline(closed, TCGTheme.GOLD_L, 2.0, true)
	else:
		var pts := _hex_points(center, r, 0.0)
		var sh := PackedVector2Array()
		for p in pts:
			sh.append(p + Vector2(0, 2.0))
		canvas.draw_colored_polygon(sh, Color(0, 0, 0, 0.48))

		var fill := Color8(36, 42, 54)
		var edge := Color8(190, 198, 212)
		if kind == "Same":
			fill = Color8(64, 58, 82)
			edge = TCGTheme.GOLD_L
		elif kind == "Any":
			fill = Color8(36, 42, 54)
			edge = Color8(195, 202, 214)
		else:
			fill = TCGTheme.elem_dark(kind)
			edge = TCGTheme.elem_color(kind)

		canvas.draw_colored_polygon(pts, fill)
		canvas.draw_colored_polygon(PackedVector2Array([center, pts[5], pts[0], pts[1]]), Color(1, 1, 1, 0.14))
		# Subtle element crest watermark inside elemental cost gem
		var etex := get_element_icon(kind)
		if etex != null:
			var isz := r * 1.38
			canvas.draw_texture_rect(etex, Rect2(center - Vector2(isz * 0.5, isz * 0.5), Vector2(isz, isz)), false, Color(1, 1, 1, 0.42))
		var closed := pts.duplicate()
		closed.append(pts[0])
		canvas.draw_polyline(closed, edge, 2.0, true)

	TCGTheme.draw_text_centered(canvas, str(val), center + Vector2(0, 0.5), int(r * 1.12), Color.WHITE, true, true)


static func draw_status_badge(
	canvas: CanvasItem,
	rect: Rect2,
	kind: String,
	elem: String = "Physical",
	usages: int = 0,
	status_name: String = ""
) -> void:
	## Sculpted circular status medallion using custom transparent PNG icons from `Status_Icons/`.
	var c := rect.get_center()
	var r: float = minf(rect.size.x, rect.size.y) * 0.5 - 1.0
	var ed := ElementDB.get_element(elem)
	var col := ed.color if (ed != null and String(ed.id) == elem) else TCGTheme.GOLD

	# Soft drop shadow + dark medallion body
	canvas.draw_circle(c + Vector2(0, 1.5), r, Color(0, 0, 0, 0.45))
	canvas.draw_circle(c, r, Color8(16, 23, 35))

	var icon_key := resolve_status_icon_key(status_name, kind)
	var st_tex: Texture2D = get_status_icon(icon_key)
	if st_tex != null:
		var isz := r * 1.88
		canvas.draw_texture_rect(st_tex, Rect2(c - Vector2(isz * 0.5, isz * 0.5), Vector2(isz, isz)), false, Color.WHITE)
		canvas.draw_arc(c, r, 0.0, TAU, 24, Color(col.r, col.g, col.b, 0.85), 1.6)
	else:
		canvas.draw_arc(c, r, 0.0, TAU, 24, col, 1.8)
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
		canvas.draw_circle(badge_c, 7.0, Color8(16, 20, 28))
		canvas.draw_arc(badge_c, 7.0, 0.0, TAU, 14, TCGTheme.GOLD, 1.2)
		TCGTheme.draw_text_centered(canvas, str(usages), badge_c, 10, TCGTheme.GOLD_L, true, false)


static func _draw_weapon_silhouette(
	canvas: CanvasItem,
	wtype: String,
	cx: float,
	cy: float,
	s: float,
	col: Color
) -> void:
	match wtype:
		"Sword":
			canvas.draw_line(Vector2(cx - 18 * s, cy + 18 * s), Vector2(cx + 22 * s, cy - 22 * s), col, maxf(2.0, 4.0 * s))
			canvas.draw_line(Vector2(cx - 16 * s, cy + 4 * s), Vector2(cx - 4 * s, cy + 16 * s), TCGTheme.GOLD_L, maxf(2.0, 3.0 * s))
		"Claymore":
			var pts := PackedVector2Array([
				Vector2(cx - 18 * s, cy + 14 * s),
				Vector2(cx + 16 * s, cy - 24 * s),
				Vector2(cx + 24 * s, cy - 16 * s),
				Vector2(cx - 10 * s, cy + 22 * s),
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
		var mod := Color(0.36, 0.36, 0.40, 1.0) if defeated else Color.WHITE
		draw_texture_cover(canvas, tex, rect, mod, 0.22)
		return

	var info: Array = CHAR_ACCENT.get(
		name,
		[TCGTheme.elem_color(elem), TCGTheme.elem_dark(elem), Color.WHITE, "Sword", "hero"]
	)
	var top_col: Color = info[0]
	var bot_col: Color = info[1]
	var glow_col: Color = info[2]
	var wtype: String = info[3]

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
		Vector2(0, 5),
		110
	)
	var inner := rect.grow(-4.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = TCGTheme.GOLD_D
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(7)
	canvas.draw_style_box(sb, inner)


static func draw_card_back(canvas: CanvasItem, rect: Rect2) -> void:
	## Renders custom celestial gold-and-navy card_back.jpeg inside a crisp gold frame.
	var back_tex := get_card_back_texture()
	TCGTheme.draw_rounded_box(
		canvas,
		rect,
		Color8(18, 28, 48),
		TCGTheme.GOLD,
		8,
		2,
		Vector2(0, 4),
		105
	)
	if back_tex != null:
		draw_texture_cover(canvas, back_tex, rect.grow(-2.5), Color.WHITE, 0.5)
		var rim_sb := StyleBoxFlat.new()
		rim_sb.bg_color = Color(0, 0, 0, 0)
		rim_sb.border_color = Color(TCGTheme.GOLD_L.r, TCGTheme.GOLD_L.g, TCGTheme.GOLD_L.b, 0.78)
		rim_sb.set_border_width_all(1)
		rim_sb.set_corner_radius_all(6)
		canvas.draw_style_box(rim_sb, rect.grow(-2.0))
		return

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
	## Full-viewport Genshin TCG tabletop using custom `board.jpeg` with subtle living sheen.
	var w: float = size.x
	var h: float = size.y
	var full_rect := Rect2(0.0, 0.0, w, h)
	var board_tex := get_board_texture()
	if board_tex != null:
		draw_texture_cover(canvas, board_tex, full_rect, Color.WHITE, 0.5)
		# Very subtle horizontal battle divider line that harmonizes with the center compass
		var mid_y: float = h * 0.5
		var line_margin: float = clampf(w * 0.14, 140.0, 280.0)
		canvas.draw_line(
			Vector2(line_margin, mid_y),
			Vector2(w * 0.5 - 110.0, mid_y),
			Color(TCGTheme.GOLD_D.r, TCGTheme.GOLD_D.g, TCGTheme.GOLD_D.b, 0.26),
			1.5
		)
		canvas.draw_line(
			Vector2(w * 0.5 + 110.0, mid_y),
			Vector2(w - line_margin, mid_y),
			Color(TCGTheme.GOLD_D.r, TCGTheme.GOLD_D.g, TCGTheme.GOLD_D.b, 0.26),
			1.5
		)
		# Gentle ambient golden light sweep (subtle, tasteful)
		if shimmer_t > 0.0:
			var pulse := 0.5 + 0.5 * sin(shimmer_t * 1.1)
			canvas.draw_arc(Vector2(w * 0.5, mid_y), 96.0, 0.0, TAU, 48, Color(TCGTheme.GOLD_L.r, TCGTheme.GOLD_L.g, TCGTheme.GOLD_L.b, 0.05 + 0.05 * pulse), 1.5)
			var sweep: float = fmod(shimmer_t * 0.055, 1.6) - 0.3
			var sx: float = lerpf(0.0, w, sweep)
			var band_pts := PackedVector2Array([
				Vector2(sx - 110.0, 0.0),
				Vector2(sx + 50.0, 0.0),
				Vector2(sx - 80.0, h),
				Vector2(sx - 240.0, h),
			])
			canvas.draw_colored_polygon(band_pts, Color(0.95, 0.92, 0.80, 0.018))
		return

	# Procedural fallback if board.jpeg is absent
	var strips: int = 36
	for i in range(strips):
		var y0: float = h * float(i) / float(strips)
		var y1: float = h * float(i + 1) / float(strips)
		var t: float = absf((float(i) / float(strips - 1)) - 0.5) * 2.0
		var c := TCGTheme.mix(Color8(26, 42, 60), Color8(11, 18, 28), t * 0.85)
		canvas.draw_rect(Rect2(0, y0, w, y1 - y0 + 2.0), c)

	var safe: Rect2 = UIConstants.get_safe_rect(size)
	var pad_x: float = clampf(safe.size.x * 0.132, 180.0, 255.0)
	var table := table_rect_override if table_rect_override.size.x > 10.0 else Rect2(
		safe.position.x + pad_x,
		safe.position.y + safe.size.y * 0.056,
		maxf(520.0, safe.size.x - pad_x * 2.0),
		maxf(400.0, safe.size.y * 0.715)
	)
	TCGTheme.draw_rounded_box(canvas, table.grow(10), Color8(48, 34, 22), TCGTheme.GOLD_D, 18, 3, Vector2(0, 6), 120)
	TCGTheme.draw_rounded_box(canvas, table, Color8(21, 36, 52), TCGTheme.GOLD, 14, 2)

class_name ElementDB
extends RefCounted
## Phase 0 (T0.2 / T14.4): Single source of truth for ElementData resources.
## Covers the 6 core elements (Cryo, Hydro, Pyro, Electro, Anemo, Geo),
## plus Omni, Physical, and Piercing (zero Dendro entries).
## Generates distinct colorblind-safe geometric textures & die tokens on demand.

const CORE_ELEMENTS: PackedStringArray = ["Cryo", "Hydro", "Pyro", "Electro", "Anemo", "Geo"]
const DICE_FACES: PackedStringArray = ["Omni", "Cryo", "Hydro", "Pyro", "Electro", "Anemo", "Geo"]
const ATTACHABLE: PackedStringArray = ["Pyro", "Hydro", "Cryo", "Electro"]

const SPECS: Dictionary = {
	"Cryo": {
		"col": Color8(157, 224, 255),
		"light": Color8(218, 245, 255),
		"dark": Color8(34, 66, 92),
		"attach": true,
		"shape": "snowflake",
	},
	"Hydro": {
		"col": Color8(73, 166, 255),
		"light": Color8(186, 226, 255),
		"dark": Color8(22, 48, 86),
		"attach": true,
		"shape": "droplet",
	},
	"Pyro": {
		"col": Color8(255, 115, 75),
		"light": Color8(255, 198, 152),
		"dark": Color8(88, 30, 24),
		"attach": true,
		"shape": "flame",
	},
	"Electro": {
		"col": Color8(194, 132, 255),
		"light": Color8(232, 200, 255),
		"dark": Color8(58, 34, 88),
		"attach": true,
		"shape": "bolt",
	},
	"Anemo": {
		"col": Color8(112, 232, 195),
		"light": Color8(196, 252, 235),
		"dark": Color8(24, 72, 64),
		"attach": false,
		"shape": "swirl",
	},
	"Geo": {
		"col": Color8(255, 202, 92),
		"light": Color8(255, 234, 174),
		"dark": Color8(78, 56, 24),
		"attach": false,
		"shape": "hex_stone",
	},
	"Omni": {
		"col": Color8(244, 243, 255),
		"light": Color8(255, 255, 255),
		"dark": Color8(58, 52, 74),
		"attach": false,
		"shape": "star",
	},
	"Physical": {
		"col": Color8(218, 222, 228),
		"light": Color8(244, 246, 250),
		"dark": Color8(52, 56, 66),
		"attach": false,
		"shape": "slash",
	},
	"Piercing": {
		"col": Color8(244, 244, 252),
		"light": Color8(255, 255, 255),
		"dark": Color8(60, 60, 74),
		"attach": false,
		"shape": "beam",
	},
}

static var _cache: Dictionary = {}


static func ensure_loaded() -> void:
	if _cache.size() >= SPECS.size():
		return
	for el_name in SPECS.keys():
		var spec: Dictionary = SPECS[el_name]
		var res_path := "res://data/elements/%s.tres" % String(el_name).to_lower()
		var ed: ElementData = null
		if ResourceLoader.exists(res_path):
			ed = ResourceLoader.load(res_path) as ElementData
		if ed == null:
			ed = ElementData.new()
			ed.id = StringName(el_name)
			ed.display_name = String(el_name)
			ed.color = spec["col"]
			ed.light_color = spec["light"]
			ed.dark_color = spec["dark"]
			ed.can_attach = bool(spec["attach"])
			ed.shape_tag = String(spec["shape"])
		else:
			if ed.id == &"":
				ed.id = StringName(el_name)
			if ed.display_name.is_empty():
				ed.display_name = String(el_name)
			if ed.shape_tag.is_empty():
				ed.shape_tag = String(spec["shape"])
		if ed.icon_small == null:
			ed.icon_small = _bake_icon_texture(String(el_name), ed.color, ed.dark_color, 18)
		if ed.icon_large == null:
			ed.icon_large = _bake_icon_texture(String(el_name), ed.color, ed.dark_color, 48)
		ed.icon = ed.icon_large
		if ed.die_face == null and DICE_FACES.has(String(el_name)):
			ed.die_face = _bake_die_texture(String(el_name), ed.color, ed.light_color, ed.dark_color, 64)
		_cache[String(el_name)] = ed


static func get_element(elem_id: String) -> ElementData:
	ensure_loaded()
	if _cache.has(elem_id):
		return _cache[elem_id]
	var cap := elem_id.capitalize()
	if _cache.has(cap):
		return _cache[cap]
	return _cache.get("Physical", null)


static func get_color(elem_id: String) -> Color:
	var ed := get_element(elem_id)
	return ed.color if ed != null else Color8(169, 181, 196)


static func get_light_color(elem_id: String) -> Color:
	var ed := get_element(elem_id)
	return ed.light_color if ed != null else Color.WHITE


static func get_dark_color(elem_id: String) -> Color:
	var ed := get_element(elem_id)
	return ed.dark_color if ed != null else Color8(31, 47, 67)


static func can_attach_element(elem_id: String) -> bool:
	var ed := get_element(elem_id)
	return ed != null and ed.can_attach


static func all_ids() -> PackedStringArray:
	ensure_loaded()
	var out: PackedStringArray = []
	for k in SPECS.keys():
		out.append(String(k))
	return out


static func clear_cache() -> void:
	_cache.clear()


static func _bake_icon_texture(elem_id: String, col: Color, dark_col: Color, sz: int) -> ImageTexture:
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(float(sz) * 0.5, float(sz) * 0.5)
	var r: float = float(sz) * 0.44
	for y in range(sz):
		for x in range(sz):
			var p := Vector2(float(x) + 0.5, float(y) + 0.5) - c
			var d: float = p.length()
			if d <= r:
				var ring: float = d / r
				var px := dark_col.lerp(col, 0.28)
				if _inside_symbol(elem_id, p / maxf(1.0, r * 0.72)):
					px = col.lerp(Color.WHITE, 0.20)
				elif ring > 0.85:
					px = col
				img.set_pixel(x, y, px)
	return ImageTexture.create_from_image(img)


static func _bake_die_texture(elem_id: String, col: Color, light_col: Color, dark_col: Color, sz: int) -> ImageTexture:
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(float(sz) * 0.5, float(sz) * 0.5)
	var r: float = float(sz) * 0.45
	for y in range(sz):
		for x in range(sz):
			var p := Vector2(float(x) + 0.5, float(y) + 0.5) - c
			# Regular pointy-top hexagon SDF
			var q := Vector2(absf(p.x), absf(p.y))
			var hex_d: float = maxf(q.x * 0.8660254 + q.y * 0.5, q.y) / (r * 0.88)
			if hex_d <= 1.0:
				var px := dark_col
				if elem_id == "Omni":
					var t := clampf((p.x + p.y + float(sz) * 0.5) / float(sz), 0.0, 1.0)
					px = Color.from_hsv(t, 0.42, 0.34).lerp(dark_col, 0.25)
				if hex_d > 0.86:
					px = col.lerp(light_col, 0.35)
				elif _inside_symbol(elem_id, p / maxf(1.0, r * 0.56)):
					px = light_col if elem_id == "Omni" else col
				elif p.y < -r * 0.15:
					px = px.lightened(0.08)
				img.set_pixel(x, y, px)
	return ImageTexture.create_from_image(img)


static func _inside_symbol(elem_id: String, u: Vector2) -> bool:
	var d: float = u.length()
	if d > 1.05:
		return false
	match elem_id:
		"Pyro":
			# Tapered flame silhouette
			var y_n := (u.y + 0.9) / 1.8
			var w := sin(clampf(y_n, 0.0, 1.0) * PI) * 0.72
			return absf(u.x) < w and u.y > -0.9 and u.y < 0.85
		"Hydro":
			# Teardrop
			var width := 0.70 * clampf((u.y + 0.85) / 1.1, 0.05, 1.0)
			if u.y > 0.25:
				return Vector2(u.x, (u.y - 0.25) * 1.15).length() < 0.62
			return absf(u.x) < width and u.y > -0.85 and u.y <= 0.25
		"Cryo":
			# 6-spoke crystal
			var ang: float = atan2(u.y, u.x)
			var spoke: float = absf(sin(ang * 3.0))
			return d < 0.32 or (spoke < 0.22 and d < 0.95)
		"Electro":
			# Jagged lightning bolt
			return (absf(u.x - (-0.18 + u.y * 0.45)) < 0.24 and u.y < 0.12) or (absf(u.x - (0.18 + u.y * 0.45)) < 0.24 and u.y >= -0.12)
		"Anemo":
			# Spiral curl
			var ang: float = atan2(u.y, u.x)
			var arm: float = absf(sin(d * 5.0 - ang))
			return (d < 0.88 and d > 0.18 and arm < 0.42) or d < 0.18
		"Geo":
			# Diamond stone inside crest
			return absf(u.x) * 1.15 + absf(u.y) * 0.85 < 0.82
		"Omni":
			# 4-point prismatic star
			return pow(absf(u.x), 0.55) + pow(absf(u.y), 0.55) < 0.95
		"Physical":
			return absf(u.x + u.y) < 0.20 and d < 0.90
		"Piercing":
			return absf(u.y) < 0.16 and absf(u.x) < 0.92
	return d < 0.5

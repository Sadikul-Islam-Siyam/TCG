class_name VFXPool
extends Control
## Phase 10 (T10.1-T10.9) + T14.2: Pooled Combat VFX & Floating Damage Overlay.
## Pre-allocates fixed object pools for floating numbers, burst particles, slashes, rings,
## flying element orbs, and reaction callout pills so rapid multi-hit chains allocate zero nodes.

const MAX_NUMBERS := 36
const MAX_PARTICLES := 140
const MAX_RINGS := 28
const MAX_FLIGHTS := 18
const MAX_BANNERS := 12

var _numbers: Array[Dictionary] = []
var _particles: Array[Dictionary] = []
var _rings: Array[Dictionary] = []
var _flights: Array[Dictionary] = []
var _banners: Array[Dictionary] = []

var shake_offset: Vector2 = Vector2.ZERO
var _shake_trauma: float = 0.0
var _shake_amp: float = 0.0
var _speed: float = 1.0


func _init() -> void:
	name = "VFXPool"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_allocate_pools()


func _allocate_pools() -> void:
	_numbers.clear()
	for i in range(MAX_NUMBERS):
		_numbers.append({"active": false})
	_particles.clear()
	for i in range(MAX_PARTICLES):
		_particles.append({"active": false})
	_rings.clear()
	for i in range(MAX_RINGS):
		_rings.append({"active": false})
	_flights.clear()
	for i in range(MAX_FLIGHTS):
		_flights.append({"active": false})
	_banners.clear()
	for i in range(MAX_BANNERS):
		_banners.append({"active": false})


func set_speed(speed_mult: float) -> void:
	_speed = maxf(0.25, speed_mult)


func clear_all() -> void:
	for item in _numbers:
		item["active"] = false
	for item in _particles:
		item["active"] = false
	for item in _rings:
		item["active"] = false
	for item in _flights:
		item["active"] = false
	for item in _banners:
		item["active"] = false
	_shake_trauma = 0.0
	shake_offset = Vector2.ZERO
	queue_redraw()


func get_pool_stats() -> Dictionary:
	var active_n := 0
	var active_p := 0
	var active_r := 0
	var active_f := 0
	var active_b := 0
	for d in _numbers:
		if bool(d.get("active", false)): active_n += 1
	for d in _particles:
		if bool(d.get("active", false)): active_p += 1
	for d in _rings:
		if bool(d.get("active", false)): active_r += 1
	for d in _flights:
		if bool(d.get("active", false)): active_f += 1
	for d in _banners:
		if bool(d.get("active", false)): active_b += 1
	return {
		"capacity": MAX_NUMBERS + MAX_PARTICLES + MAX_RINGS + MAX_FLIGHTS + MAX_BANNERS,
		"active_numbers": active_n,
		"active_particles": active_p,
		"active_rings": active_r,
		"active_flights": active_f,
		"active_banners": active_b,
	}


func _acquire(pool: Array[Dictionary]) -> Dictionary:
	for d in pool:
		if not bool(d.get("active", false)):
			return d
	# Recycle oldest slot cleanly if saturated
	return pool[0]


func trigger_shake(damage_amount: int) -> Vector2:
	# T10.7: 2-5px subtle screen shake scaled by hit strength
	var strength := clampf(float(maxi(1, damage_amount)) / 6.0, 0.35, 1.0)
	_shake_amp = maxf(_shake_amp, lerpf(2.0, 5.2, strength))
	_shake_trauma = 0.24
	return Vector2(_shake_amp, 0.0)


func spawn_floating_number(pos: Vector2, text: String, element: String = "Physical", is_heal: bool = false, scale_boost: float = 1.0) -> void:
	var d := _acquire(_numbers)
	var col := TCGTheme.GREEN if is_heal else TCGTheme.elem_color(element)
	if element == "Piercing" and not is_heal:
		col = ElementDB.get_color("Piercing")
	d["active"] = true
	d["pos"] = pos + Vector2(randf_range(-10.0, 10.0), randf_range(-6.0, 4.0))
	d["vel"] = Vector2(randf_range(-16.0, 16.0), -64.0)
	d["text"] = text
	d["color"] = col
	d["age"] = 0.0
	d["dur"] = 0.90
	d["scale_boost"] = scale_boost
	queue_redraw()


func spawn_element_hit(pos: Vector2, element: String, damage: int = 1) -> void:
	var col := TCGTheme.elem_color(element)
	#Expanding shockwave ring
	var r := _acquire(_rings)
	r["active"] = true
	r["pos"] = pos
	r["color"] = col
	r["r0"] = 10.0
	r["r1"] = 48.0 + float(clampi(damage, 1, 6)) * 5.0
	r["age"] = 0.0
	r["dur"] = 0.36
	r["style"] = element

	var count := clampi(8 + damage * 2, 8, 22)
	for i in range(count):
		var p := _acquire(_particles)
		var ang := TAU * float(i) / float(count) + randf_range(-0.22, 0.22)
		var spd := randf_range(75.0, 175.0)
		p["active"] = true
		p["pos"] = pos
		p["vel"] = Vector2(cos(ang), sin(ang)) * spd
		p["color"] = col.lightened(randf_range(0.0, 0.35))
		p["size"] = randf_range(3.0, 6.2)
		p["age"] = 0.0
		p["dur"] = randf_range(0.26, 0.48)
		p["kind"] = "spark" if element in ["Pyro", "Electro", "Physical", "Piercing"] else "orb"
	trigger_shake(damage)
	queue_redraw()


func spawn_reaction_fx(pos: Vector2, reaction_name: String, damage: int = 0) -> void:
	var col := _reaction_color(reaction_name)
	# Twin concentric burst rings
	for k in range(2):
		var r := _acquire(_rings)
		r["active"] = true
		r["pos"] = pos
		r["color"] = col if k == 0 else TCGTheme.GOLD_L
		r["r0"] = 12.0 + float(k) * 8.0
		r["r1"] = 72.0 + float(k) * 18.0
		r["age"] = 0.0
		r["dur"] = 0.44 + float(k) * 0.08
		r["style"] = reaction_name

	for i in range(16):
		var p := _acquire(_particles)
		var ang := TAU * float(i) / 16.0
		p["active"] = true
		p["pos"] = pos
		p["vel"] = Vector2(cos(ang), sin(ang)) * randf_range(90.0, 210.0)
		p["color"] = col if (i % 2 == 0) else TCGTheme.GOLD_L
		p["size"] = randf_range(3.5, 6.5)
		p["age"] = 0.0
		p["dur"] = 0.48
		p["kind"] = "diamond"

	var b := _acquire(_banners)
	b["active"] = true
	b["pos"] = pos + Vector2(0, -34)
	b["text"] = reaction_name.to_upper()
	b["color"] = col
	b["age"] = 0.0
	b["dur"] = 1.05
	if damage > 0:
		trigger_shake(damage + 1)
	queue_redraw()


func spawn_element_flight(from_pos: Vector2, to_pos: Vector2, element: String) -> void:
	var f := _acquire(_flights)
	f["active"] = true
	f["from"] = from_pos
	f["to"] = to_pos
	f["element"] = element
	f["color"] = TCGTheme.elem_color(element)
	f["age"] = 0.0
	f["dur"] = 0.28
	queue_redraw()


func spawn_dice_spend_sparks(from_pos: Vector2, to_pos: Vector2, element: String) -> void:
	var f := _acquire(_flights)
	f["active"] = true
	f["from"] = from_pos
	f["to"] = to_pos
	f["element"] = element
	f["color"] = TCGTheme.elem_color(element)
	f["age"] = 0.0
	f["dur"] = 0.24
	queue_redraw()


func spawn_shield_shatter(pos: Vector2) -> void:
	for i in range(10):
		var p := _acquire(_particles)
		var ang := randf_range(-PI * 0.9, -PI * 0.1) + (PI if i >= 5 else 0.0)
		p["active"] = true
		p["pos"] = pos
		p["vel"] = Vector2(cos(ang), sin(ang)) * randf_range(65.0, 145.0)
		p["color"] = Color("#9FD8FF")
		p["size"] = randf_range(4.0, 6.5)
		p["age"] = 0.0
		p["dur"] = 0.42
		p["kind"] = "diamond"
	queue_redraw()


func spawn_defeat_seal(pos: Vector2) -> void:
	var r := _acquire(_rings)
	r["active"] = true
	r["pos"] = pos
	r["color"] = Color("#9F8548")
	r["r0"] = 18.0
	r["r1"] = 66.0
	r["age"] = 0.0
	r["dur"] = 0.55
	r["style"] = "Seal"
	var b := _acquire(_banners)
	b["active"] = true
	b["pos"] = pos
	b["text"] = "DEFEATED"
	b["color"] = TCGTheme.RED
	b["age"] = 0.0
	b["dur"] = 1.0
	queue_redraw()


func step(delta: float) -> bool:
	var dt := delta * _speed
	var any_active := false

	if _shake_trauma > 0.0:
		_shake_trauma = maxf(0.0, _shake_trauma - delta)
		var decay := _shake_trauma / 0.24
		shake_offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * (_shake_amp * decay * decay)
		any_active = true
	else:
		if shake_offset != Vector2.ZERO:
			shake_offset = Vector2.ZERO
			any_active = true

	for d in _numbers:
		if not bool(d.get("active", false)):
			continue
		d["age"] = float(d["age"]) + dt
		var vel: Vector2 = d["vel"]
		d["pos"] = Vector2(d["pos"]) + vel * dt
		d["vel"] = vel + Vector2(0.0, 125.0 * dt)
		if float(d["age"]) >= float(d["dur"]):
			d["active"] = false
		else:
			any_active = true

	for p in _particles:
		if not bool(p.get("active", false)):
			continue
		p["age"] = float(p["age"]) + dt
		var vel: Vector2 = p["vel"]
		p["pos"] = Vector2(p["pos"]) + vel * dt
		p["vel"] = vel * (1.0 - minf(0.9, dt * 3.8))
		if float(p["age"]) >= float(p["dur"]):
			p["active"] = false
		else:
			any_active = true

	for r in _rings:
		if not bool(r.get("active", false)):
			continue
		r["age"] = float(r["age"]) + dt
		if float(r["age"]) >= float(r["dur"]):
			r["active"] = false
		else:
			any_active = true

	for f in _flights:
		if not bool(f.get("active", false)):
			continue
		f["age"] = float(f["age"]) + dt
		if float(f["age"]) >= float(f["dur"]):
			f["active"] = false
		else:
			any_active = true

	for b in _banners:
		if not bool(b.get("active", false)):
			continue
		b["age"] = float(b["age"]) + dt
		if float(b["age"]) >= float(b["dur"]):
			b["active"] = false
		else:
			any_active = true

	if any_active:
		queue_redraw()
	return any_active


func _process(delta: float) -> void:
	step(delta)


func _draw() -> void:
	# 1. Shockwave rings
	for r in _rings:
		if not bool(r.get("active", false)):
			continue
		var t := clampf(float(r["age"]) / maxf(0.01, float(r["dur"])), 0.0, 1.0)
		var rad := lerpf(float(r["r0"]), float(r["r1"]), 1.0 - pow(1.0 - t, 3.0))
		var col: Color = r["color"]
		var a := (1.0 - t) * 0.85
		draw_arc(Vector2(r["pos"]), rad, 0.0, TAU, 36, Color(col.r, col.g, col.b, a), 3.0 * (1.0 - t * 0.6))
		if String(r.get("style", "")) == "Electro":
			for k in range(4):
				var ang := float(k) * (PI * 0.5) + t * 3.0
				var p1 := Vector2(r["pos"]) + Vector2(cos(ang), sin(ang)) * (rad * 0.45)
				var p2 := Vector2(r["pos"]) + Vector2(cos(ang + 0.35), sin(ang + 0.35)) * rad
				draw_line(p1, p2, Color(col.r, col.g, col.b, a), 2.2)

	# 2. Pooled particles
	for p in _particles:
		if not bool(p.get("active", false)):
			continue
		var t := clampf(float(p["age"]) / maxf(0.01, float(p["dur"])), 0.0, 1.0)
		var col: Color = p["color"]
		var a := 1.0 - t
		var pos: Vector2 = p["pos"]
		var sz: float = float(p["size"]) * (1.0 - t * 0.45)
		var kind := String(p.get("kind", "orb"))
		if kind == "diamond":
			var pts := PackedVector2Array([
				pos + Vector2(0, -sz),
				pos + Vector2(sz * 0.75, 0),
				pos + Vector2(0, sz),
				pos + Vector2(-sz * 0.75, 0),
			])
			draw_colored_polygon(pts, Color(col.r, col.g, col.b, a))
		else:
			draw_circle(pos, sz, Color(col.r, col.g, col.b, a))

	# 3. Flying element / dice spark orbs
	for f in _flights:
		if not bool(f.get("active", false)):
			continue
		var t := clampf(float(f["age"]) / maxf(0.01, float(f["dur"])), 0.0, 1.0)
		var ease_t := t * t * (3.0 - 2.0 * t)
		var p_from: Vector2 = f["from"]
		var p_to: Vector2 = f["to"]
		var mid := (p_from + p_to) * 0.5 + Vector2(0, -34.0)
		var cur := p_from.lerp(mid, ease_t).lerp(mid.lerp(p_to, ease_t), ease_t)
		var col: Color = f["color"]
		draw_circle(cur, 11.0 * (1.0 - t * 0.35), Color(col.r, col.g, col.b, 0.35))
		TCGArt.draw_elem_symbol(self, String(f["element"]), cur, 8.5 * (1.0 - t * 0.3), col, false)

	# 4. Reaction callout pills
	for b in _banners:
		if not bool(b.get("active", false)):
			continue
		var t := clampf(float(b["age"]) / maxf(0.01, float(b["dur"])), 0.0, 1.0)
		var a := clampf(minf(t * 6.0, (1.0 - t) * 3.0), 0.0, 1.0)
		var sc := lerpf(1.22, 1.0, minf(1.0, t * 5.0))
		var pos: Vector2 = Vector2(b["pos"]) + Vector2(0, -t * 16.0)
		var txt := String(b["text"])
		var bw := clampf(float(txt.length()) * 9.5 + 24.0, 96.0, 210.0) * sc
		var pill := Rect2(pos.x - bw * 0.5, pos.y - 13.0, bw, 24.0)
		var col: Color = b["color"]
		TCGTheme.draw_rounded_box(self, pill, Color(0.05, 0.08, 0.14, 0.92 * a), Color(col.r, col.g, col.b, a), 12, 2.0)
		TCGTheme.draw_text_centered(self, txt, pill.get_center(), 12, Color(1.0, 0.98, 0.92, a), true, true)

	# 5. Floating damage / heal numbers (topmost)
	for d in _numbers:
		if not bool(d.get("active", false)):
			continue
		var t := clampf(float(d["age"]) / maxf(0.01, float(d["dur"])), 0.0, 1.0)
		var a := 1.0 if t < 0.6 else clampf(1.0 - (t - 0.6) / 0.4, 0.0, 1.0)
		var sc := 1.38 - 0.38 * minf(1.0, t * 5.0)
		var fsize := int(round(22.0 * sc * float(d.get("scale_boost", 1.0))))
		var col: Color = d["color"]
		TCGTheme.draw_text_centered(self, String(d["text"]), Vector2(d["pos"]), fsize, Color(col.r, col.g, col.b, a), true, true)


func _reaction_color(rx: String) -> Color:
	var low := rx.to_lower()
	if low.contains("melt"):
		return Color("#FF9464")
	if low.contains("vaporize"):
		return Color("#61BAFF")
	if low.contains("overload"):
		return Color("#FF7396")
	if low.contains("superconduct"):
		return Color("#B3D9FF")
	if low.contains("electro"):
		return Color("#D084FF")
	if low.contains("frozen"):
		return TCGTheme.elem_color("Cryo")
	if low.contains("swirl"):
		return TCGTheme.elem_color("Anemo")
	if low.contains("crystal"):
		return TCGTheme.elem_color("Geo")
	return TCGTheme.GOLD_L


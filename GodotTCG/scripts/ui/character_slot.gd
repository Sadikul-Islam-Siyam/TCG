class_name TCGCharacterSlot
extends Control
## Phase 3 (T3.1 - T3.11): Character Card component with 4:7 frame, animated HP/Delta pill,
## Shield badge + shatter shards, left-edge EquipmentColumn, right-edge EnergyColumn w/ Burst pulse,
## top 4-element-only AttachmentPill, bottom 5-cap +N StatusRow w/ 0.15s smooth reflow,
## Frozen crystal overlay, Defeated desaturation + seal, and Select/Target/Invalid feedback.

signal slot_clicked(side: int, char_index: int)
signal slot_hovered(side: int, char_index: int, is_hovering: bool)
signal status_icon_hovered(payload: Dictionary, is_hovering: bool)
signal status_icon_clicked(payload: Dictionary)

var side: int = 0
var char_index: int = 0
var char_state: TCGPlayerSystem.CharacterInstance = null
var is_active_char: bool = false
var is_clickable: bool = false
var is_selected_target: bool = false
var is_valid_target: bool = false
var is_invalid_dim: bool = false
var shield_total: int = 0

var hit_flash_alpha: float = 0.0
var lunge_offset: Vector2 = Vector2.ZERO
var shown_hp_override: int = -1
var preview_info: Dictionary = {}

var _hovered: bool = false
var _hovered_icon_idx: int = -1
var _icon_rects: Array[Dictionary] = []

# Animated visual caches (T3.3 - T3.11)
var _last_char_name: String = ""
var _last_hp: int = -1
var _display_hp: float = 10.0
var _hp_tween: Tween = null
var _hp_delta: int = 0
var _hp_delta_timer: float = 0.0

var _last_energy: int = -1
var _energy_spark_timer: float = 0.0
var _last_aura: String = ""
var _aura_pop_timer: float = 0.0
var _last_shield: int = 0
var _shield_shake: float = 0.0
var _shield_shards: Array[Dictionary] = []
var _last_frozen: bool = false
var _freeze_shatter_timer: float = 0.0
var _last_eq_keys: Dictionary = {}
var _eq_pop_timers: Dictionary = {}

var _target_marker_scale: float = 0.0
var _target_tween: Tween = null
var _anim_t: float = 0.0
var _status_anim_x: Dictionary = {}  # status_key -> current x offset for 0.15s smooth reflow
var _status_rects_cache: Array[Rect2] = []
var _visible_status_count: int = 0
var _overflow_status_count: int = 0
var _defeat_status_slide: float = 0.0


func _init() -> void:
	custom_minimum_size = Vector2(156, 266)
	size = Vector2(156, 266)
	mouse_filter = Control.MOUSE_FILTER_STOP


func setup(
	p_side: int,
	p_index: int,
	p_state: TCGPlayerSystem.CharacterInstance,
	p_active: bool,
	p_selected: bool = false,
	p_valid_target: bool = false,
	p_clickable: bool = false,
	p_shown_hp: int = -1,
	p_hit_flash: float = 0.0,
	p_lunge_offset: Vector2 = Vector2.ZERO,
	p_shield_total: int = 0,
	p_invalid_dim: bool = false,
	p_preview: Dictionary = {}
) -> void:
	side = p_side
	char_index = p_index
	char_state = p_state
	is_active_char = p_active
	is_selected_target = p_selected
	is_clickable = p_clickable
	shown_hp_override = p_shown_hp
	hit_flash_alpha = p_hit_flash
	lunge_offset = p_lunge_offset
	is_invalid_dim = p_invalid_dim
	preview_info = p_preview
	modulate = Color(1, 1, 1, 0.50 if is_invalid_dim else 1.0)

	# Handle Target marker pop animation
	if p_valid_target != is_valid_target:
		is_valid_target = p_valid_target
		if is_inside_tree():
			if _target_tween != null and _target_tween.is_valid():
				_target_tween.kill()
			_target_tween = create_tween()
			_target_tween.tween_property(self, "_target_marker_scale", 1.0 if is_valid_target else 0.0, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			_target_tween.parallel().tween_method(func(_x: float) -> void: queue_redraw(), 0.0, 1.0, 0.22)
		else:
			_target_marker_scale = 1.0 if is_valid_target else 0.0

	if char_state != null:
		var same_char: bool = (_last_char_name == char_state.name)
		if not same_char:
			_last_char_name = char_state.name
			_last_hp = char_state.hp
			_display_hp = float(char_state.hp)
			_last_energy = char_state.energy
			_last_aura = char_state.aura
			_last_shield = p_shield_total
			_last_frozen = TCGRulesEngine.has_status(char_state, "Frozen")
			_last_eq_keys = char_state.equipment.duplicate()
			_hp_delta = 0
			_hp_delta_timer = 0.0
			_status_anim_x.clear()
		else:
			# HP change count tween + HPDeltaPill (T3.3)
			if char_state.hp != _last_hp:
				var delta_hp: int = char_state.hp - _last_hp
				_hp_delta = delta_hp
				_hp_delta_timer = 1.25
				if is_inside_tree():
					if _hp_tween != null and _hp_tween.is_valid():
						_hp_tween.kill()
					_hp_tween = create_tween()
					_hp_tween.tween_property(self, "_display_hp", float(char_state.hp), 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
					_hp_tween.parallel().tween_method(func(_v: float) -> void: queue_redraw(), 0.0, 1.0, 0.28)
				else:
					_display_hp = float(char_state.hp)
				_last_hp = char_state.hp

			# Energy gain sparkle
			if char_state.energy > _last_energy:
				_energy_spark_timer = 0.45
			_last_energy = char_state.energy

			# Element attach pop
			if char_state.aura != _last_aura:
				if not char_state.aura.is_empty():
					_aura_pop_timer = 0.35
				_last_aura = char_state.aura

			# Shield absorb / shatter
			if p_shield_total < _last_shield:
				_shield_shake = 0.30
				if p_shield_total == 0:
					_spawn_shield_shards()
			_last_shield = p_shield_total

			# Frozen thaw shatter
			var now_frozen := TCGRulesEngine.has_status(char_state, "Frozen")
			if _last_frozen and not now_frozen:
				_freeze_shatter_timer = 0.38
			_last_frozen = now_frozen

			# Equipment badge pop
			for eq_k in ["weapon", "artifact", "talent"]:
				var cur_v := String(char_state.equipment.get(eq_k, ""))
				var old_v := String(_last_eq_keys.get(eq_k, ""))
				if not cur_v.is_empty() and cur_v != old_v:
					_eq_pop_timers[eq_k] = 0.35
			_last_eq_keys = char_state.equipment.duplicate()

	shield_total = p_shield_total
	_update_status_metrics()
	queue_redraw()


func _update_status_metrics() -> void:
	_status_rects_cache.clear()
	_visible_status_count = 0
	_overflow_status_count = 0
	if char_state == null or char_state.statuses.is_empty():
		return
	var r := Rect2(lunge_offset, size)
	var row_y: float = r.end.y + 8.0 + _defeat_status_slide * 24.0
	var chip_sz: float = clampf(r.size.x * 0.21, 24.0, 30.0)
	var gap: float = 8.0
	var total_st: int = char_state.statuses.size()
	var show_overflow: bool = total_st > 5
	var max_vis: int = 4 if show_overflow else mini(5, total_st)
	_visible_status_count = max_vis
	_overflow_status_count = maxi(0, total_st - max_vis) if show_overflow else 0
	for idx in range(max_vis):
		var target_x: float = r.position.x + float(idx) * (chip_sz + gap)
		_status_rects_cache.append(Rect2(target_x, row_y, chip_sz, chip_sz))
	if show_overflow:
		var ov_x: float = r.position.x + float(max_vis) * (chip_sz + gap)
		_status_rects_cache.append(Rect2(ov_x, row_y, chip_sz, chip_sz))


func setup_character(data: Dictionary) -> void:
	## Phase 0 (T0.4) standard scene setup(data) convention wrapper.
	var st: TCGPlayerSystem.CharacterInstance = data.get("state", null)
	setup(
		int(data.get("side", 0)),
		int(data.get("index", 0)),
		st,
		bool(data.get("active", false)),
		bool(data.get("selected", false)),
		bool(data.get("valid_target", false)),
		bool(data.get("clickable", false)),
		int(data.get("shown_hp", -1)),
		float(data.get("hit_flash", 0.0)),
		data.get("lunge_offset", Vector2.ZERO),
		int(data.get("shield", 0)),
		bool(data.get("invalid_dim", false))
	)


func set_anim_state(p_hit_flash: float, p_lunge_offset: Vector2) -> void:
	hit_flash_alpha = p_hit_flash
	lunge_offset = p_lunge_offset
	# Subtle Genshin-style dynamic card tilt during attack lunge
	var tilt_dir: float = -1.0 if side == 0 else 1.0
	var lunge_norm: float = clampf(lunge_offset.length() / 28.0, 0.0, 1.0)
	pivot_offset = size * 0.5
	rotation = tilt_dir * deg_to_rad(5.5) * lunge_norm
	queue_redraw()


func trigger_hp_delta(delta_val: int) -> void:
	_hp_delta = delta_val
	_hp_delta_timer = 1.25
	queue_redraw()


func _spawn_shield_shards() -> void:
	_shield_shards.clear()
	for i in range(4):
		var a := float(i) * PI * 0.5 + 0.4
		_shield_shards.append({
			"pos": Vector2(46.0, 20.0),
			"vel": Vector2(cos(a), sin(a)) * 55.0 + Vector2(0, -20.0),
			"life": 0.40,
		})


func get_visible_status_count() -> int:
	return _visible_status_count


func get_overflow_status_count() -> int:
	return _overflow_status_count


func get_status_rects() -> Array[Rect2]:
	return _status_rects_cache.duplicate()


func _process(delta: float) -> void:
	_anim_t += delta
	var dirty := false
	if _hp_delta_timer > 0.0:
		_hp_delta_timer = maxf(0.0, _hp_delta_timer - delta)
		dirty = true
	if _energy_spark_timer > 0.0:
		_energy_spark_timer = maxf(0.0, _energy_spark_timer - delta)
		dirty = true
	if _aura_pop_timer > 0.0:
		_aura_pop_timer = maxf(0.0, _aura_pop_timer - delta)
		dirty = true
	if _shield_shake > 0.0:
		_shield_shake = maxf(0.0, _shield_shake - delta)
		dirty = true
	if _freeze_shatter_timer > 0.0:
		_freeze_shatter_timer = maxf(0.0, _freeze_shatter_timer - delta)
		dirty = true
	for k in _eq_pop_timers.keys():
		var rem: float = float(_eq_pop_timers[k]) - delta
		if rem <= 0.0:
			_eq_pop_timers.erase(k)
		else:
			_eq_pop_timers[k] = rem
		dirty = true
	if not _shield_shards.is_empty():
		var kept_shards: Array[Dictionary] = []
		for sh in _shield_shards:
			sh["life"] = float(sh["life"]) - delta
			if float(sh["life"]) > 0.0:
				sh["pos"] = (sh["pos"] as Vector2) + (sh["vel"] as Vector2) * delta
				kept_shards.append(sh)
		_shield_shards = kept_shards
		dirty = true
	if char_state != null:
		if char_state.defeated and _defeat_status_slide < 1.0:
			_defeat_status_slide = minf(1.0, _defeat_status_slide + delta * 4.0)
			dirty = true
		elif not char_state.defeated and _defeat_status_slide > 0.0:
			_defeat_status_slide = 0.0
		if is_valid_target:
			if int(_anim_t * 6.0) != int((_anim_t - delta) * 6.0):
				dirty = true
	if dirty:
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER:
		_hovered = true
		slot_hovered.emit(side, char_index, true)
		queue_redraw()
	elif what == NOTIFICATION_MOUSE_EXIT:
		_hovered = false
		if _hovered_icon_idx >= 0 and _hovered_icon_idx < _icon_rects.size():
			status_icon_hovered.emit(_icon_rects[_hovered_icon_idx]["payload"], false)
		_hovered_icon_idx = -1
		slot_hovered.emit(side, char_index, false)
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var found_idx: int = -1
		for idx in range(_icon_rects.size()):
			var entry: Dictionary = _icon_rects[idx]
			if (entry["rect"] as Rect2).has_point(event.position):
				found_idx = idx
				break
		if found_idx != _hovered_icon_idx:
			if _hovered_icon_idx >= 0 and _hovered_icon_idx < _icon_rects.size():
				status_icon_hovered.emit(_icon_rects[_hovered_icon_idx]["payload"], false)
			_hovered_icon_idx = found_idx
			if _hovered_icon_idx >= 0:
				status_icon_hovered.emit(_icon_rects[_hovered_icon_idx]["payload"], true)
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			for entry in _icon_rects:
				if (entry["rect"] as Rect2).has_point(event.position):
					status_icon_clicked.emit(entry["payload"])
					accept_event()
					return
			slot_clicked.emit(side, char_index)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT and char_state != null:
			for entry in _icon_rects:
				if (entry["rect"] as Rect2).has_point(event.position):
					status_icon_clicked.emit(entry["payload"])
					accept_event()
					return
			status_icon_clicked.emit({
				"kind": "char",
				"side": side,
				"char_index": char_index,
				"name": char_state.name,
			})
			accept_event()


func _draw() -> void:
	_icon_rects.clear()
	_status_rects_cache.clear()
	_visible_status_count = 0
	_overflow_status_count = 0
	if char_state == null:
		return

	var d: CardDataSystem.CharData = char_state.get_defn()
	if d == null:
		return

	var r := Rect2(lunge_offset, size)
	var defeated: bool = char_state.defeated

	# Selection / Valid Target Glow Aura (T3.11)
	if is_valid_target:
		var pulse_a: float = 0.20 + 0.14 * (0.5 + 0.5 * sin(_anim_t * 6.0))
		TCGTheme.draw_rounded_box(self, r.grow(7), Color(TCGTheme.GOLD_L.r, TCGTheme.GOLD_L.g, TCGTheme.GOLD_L.b, pulse_a), TCGTheme.GOLD_L, 16, 2)
	elif is_selected_target or is_active_char or _hovered:
		var glow_col := ElementDB.get_color(d.element) if is_active_char else TCGTheme.GOLD_L
		TCGTheme.draw_rounded_box(self, r.grow(4), Color(glow_col.r, glow_col.g, glow_col.b, 0.18), glow_col, 14, 2)

	# Main 4:7 Card Frame (T3.2)
	var card_bg := Color8(24, 30, 44) if not defeated else Color8(20, 22, 28)
	TCGTheme.draw_gold_frame(
		self,
		r,
		card_bg,
		12,
		is_active_char or _hovered or is_selected_target or is_valid_target or is_clickable
	)

	# Portrait art slot (full-bleed Genshin character card style)
	var art_rect := Rect2(r.position.x + 5, r.position.y + 5, r.size.x - 10, r.size.y - 10)
	TCGArt.draw_portrait(self, char_state.name, d.element, art_rect, defeated)
	# Subtle bottom gradient vignette so the character name reads cleanly without blocking art
	for g_i in range(4):
		var gh := 14.0
		var gy := art_rect.end.y - float(4 - g_i) * gh
		var ga := 0.16 + float(g_i) * 0.18
		draw_rect(Rect2(art_rect.position.x, gy, art_rect.size.x, gh + 1.0), Color(0.04, 0.06, 0.10, ga))

	# Frozen / Petrified / Stunned overlay + custom Stunned icon (T3.9)
	var is_frozen: bool = TCGRulesEngine.has_status(char_state, "Frozen")
	var is_petrified: bool = TCGRulesEngine.has_status(char_state, "Petrified")
	var is_stunned: bool = TCGRulesEngine.has_status(char_state, "Stunned")
	if is_frozen or is_petrified or is_stunned:
		var ov_col := Color(0.55, 0.86, 1.0, 0.36) if is_frozen else (Color(0.75, 0.63, 0.35, 0.42) if is_petrified else Color(0.46, 0.24, 0.72, 0.34))
		draw_rect(art_rect, ov_col)
		if is_stunned:
			var st_tex := TCGArt.get_status_icon("Stunned")
			if st_tex != null:
				var sc_c := art_rect.get_center()
				var s_sz := minf(art_rect.size.x, art_rect.size.y) * 0.56
				draw_texture_rect(st_tex, Rect2(sc_c - Vector2(s_sz * 0.5, s_sz * 0.5), Vector2(s_sz, s_sz)), false, Color(1, 1, 1, 0.92))
		else:
			var cr_col := Color(0.88, 0.97, 1.0, 0.72) if is_frozen else Color(0.92, 0.84, 0.58, 0.7)
			draw_line(art_rect.position + Vector2(14, 18), art_rect.get_center() + Vector2(-6, -4), cr_col, 1.5)
			draw_line(art_rect.get_center() + Vector2(-6, -4), art_rect.end - Vector2(16, 22), cr_col, 1.3)
			draw_line(art_rect.get_center() + Vector2(-6, -4), Vector2(art_rect.end.x - 18, art_rect.position.y + 34), cr_col, 1.2)
		var lbl := "FROZEN" if is_frozen else ("PETRIFIED" if is_petrified else "STUNNED")
		TCGTheme.draw_text_centered(self, lbl, Vector2(r.get_center().x, art_rect.end.y - 38.0), 14, Color.WHITE, true, true)
	elif _freeze_shatter_timer > 0.0:
		var sa: float = clampf(_freeze_shatter_timer / 0.38, 0.0, 1.0)
		for k in range(5):
			var ang := float(k) * 1.25
			var pt := art_rect.get_center() + Vector2(cos(ang), sin(ang)) * ((1.0 - sa) * 42.0)
			draw_circle(pt, 3.0 * sa, Color(0.75, 0.95, 1.0, sa))

	# Hit flash overlay
	if hit_flash_alpha > 0.01:
		draw_rect(art_rect, Color(1.0, 0.27, 0.24, clampf(hit_flash_alpha, 0.0, 0.70)))

	# Sleek bottom name plate blended cleanly over lower portrait
	var name_bar := Rect2(r.position.x + 6, r.end.y - 34, r.size.x - 12, 28)
	var name_sz: int = TCGTheme.fit_font_size(char_state.name, name_bar.size.x - 8.0, 16, 11, true)
	TCGTheme.draw_text_centered(
		self,
		char_state.name,
		name_bar.get_center(),
		name_sz,
		TCGTheme.GOLD_L if is_active_char else TCGTheme.TEXT,
		true,
		true
	)

	if not defeated:
		# Energy column on right edge (T3.5)
		var max_e: int = maxi(1, d.max_energy)
		var burst_ready := char_state.energy >= max_e
		var ex: float = r.end.x - 12.0
		for k in range(max_e):
			var ey: float = r.position.y + 56.0 + float(k) * 23.0
			var filled: bool = k < char_state.energy
			var pulse_s: float = 1.0 + (0.16 * (0.5 + 0.5 * sin(_anim_t * 5.0 - float(k) * 0.6)) if burst_ready else 0.0)
			var sr: float = 8.5 * pulse_s
			var pts := PackedVector2Array([
				Vector2(ex, ey - sr),
				Vector2(ex + sr * 0.82, ey),
				Vector2(ex, ey + sr),
				Vector2(ex - sr * 0.82, ey),
			])
			if filled:
				var e_glow := Color(TCGTheme.GOLD_L.r, TCGTheme.GOLD_L.g, TCGTheme.GOLD_L.b, 0.35 if burst_ready else 0.18)
				draw_circle(Vector2(ex, ey), sr * 1.45, e_glow)
			draw_colored_polygon(pts, TCGTheme.GOLD_L if filled else Color8(38, 44, 58))
			var closed := pts.duplicate()
			closed.append(pts[0])
			draw_polyline(closed, TCGTheme.GOLD if filled else TCGTheme.GOLD_D, 1.2)
		if _energy_spark_timer > 0.0:
			var ea := _energy_spark_timer / 0.45
			draw_circle(Vector2(ex, r.position.y + 56.0 + float(maxi(0, char_state.energy - 1)) * 23.0), 15.0 * (1.2 - ea * 0.4), Color(1.0, 0.92, 0.55, ea * 0.6))

		# Left-edge EquipmentColumn badges (T3.4) using custom Status_Icons PNGs
		var eq_y: float = r.position.y + 62.0
		for eq_slot in ["weapon", "artifact", "talent"]:
			if char_state.equipment.has(eq_slot):
				var eq_card_name := String(char_state.equipment[eq_slot])
				var pop_s: float = 1.0 + float(_eq_pop_timers.get(eq_slot, 0.0)) * 0.9
				var eq_sz: float = 30.0 * pop_s
				var eq_rect := Rect2(r.position.x + 14.0 - eq_sz * 0.5, eq_y - eq_sz * 0.5, eq_sz, eq_sz)
				var eq_kind: String = "weapon" if eq_slot == "weapon" else ("artifact" if eq_slot == "artifact" else "talent")
				TCGArt.draw_status_badge(self, eq_rect, eq_kind, d.element, 0, eq_card_name)
				_icon_rects.append({
					"rect": eq_rect.grow(5.0),
					"payload": {"kind": "equip", "slot": eq_slot, "card_name": eq_card_name}
				})
				eq_y += 34.0

		# Top-left HP Badge (~35% width footprint, shield shape, crimson <30% HP) (T3.3)
		var disp_hp: float = float(shown_hp_override) if shown_hp_override >= 0 else _display_hp
		var disp_hp_int: int = maxi(0, int(roundf(disp_hp)))
		var low_hp: bool = float(disp_hp_int) <= float(d.hp) * 0.30
		var hp_c := Vector2(r.position.x + 14.0, r.position.y + 16.0)
		var hp_r: float = clampf(r.size.x * 0.17, 20.0, 26.0)
		var hp_fill := TCGTheme.RED if low_hp else Color8(186, 56, 52)
		var shield_pts := PackedVector2Array([
			hp_c + Vector2(-hp_r * 0.85, -hp_r * 0.72),
			hp_c + Vector2(0, -hp_r),
			hp_c + Vector2(hp_r * 0.85, -hp_r * 0.72),
			hp_c + Vector2(hp_r * 0.72, hp_r * 0.45),
			hp_c + Vector2(0, hp_r * 1.02),
			hp_c + Vector2(-hp_r * 0.72, hp_r * 0.45),
		])
		draw_colored_polygon(shield_pts, hp_fill)
		var sh_closed := shield_pts.duplicate()
		sh_closed.append(shield_pts[0])
		draw_polyline(sh_closed, Color(1.0, 0.42, 0.42) if low_hp else TCGTheme.GOLD_L, 2.4)
		TCGTheme.draw_text_centered(self, str(disp_hp_int), hp_c + Vector2(0, -1), 19, Color.WHITE, true, true)

		# Shield Badge right beside HP (T3.8)
		if shield_total > 0 or _shield_shake > 0.0:
			var sh_off := Vector2(sin(_anim_t * 48.0) * 4.0 * (_shield_shake / 0.30), 0.0) if _shield_shake > 0.0 else Vector2.ZERO
			var sc := Vector2(hp_c.x + hp_r + 18.0, hp_c.y) + sh_off
			draw_circle(sc, 16.0, Color8(26, 44, 68))
			draw_arc(sc, 16.0, 0.0, TAU, 20, Color8(182, 224, 255), 2.2)
			TCGTheme.draw_text_centered(self, str(shield_total), sc, 15, Color.WHITE, true, true)

		for shard in _shield_shards:
			var sp: Vector2 = r.position + (shard["pos"] as Vector2)
			var sa: float = clampf(float(shard["life"]) / 0.40, 0.0, 1.0)
			draw_colored_polygon(PackedVector2Array([sp + Vector2(-4, -3), sp + Vector2(4, 0), sp + Vector2(0, 5)]), Color(0.75, 0.90, 1.0, sa))

		# HPDeltaPill beside HP badge (T3.3)
		if _hp_delta != 0 and _hp_delta_timer > 0.0:
			var da: float = clampf(_hp_delta_timer / 0.35, 0.0, 1.0)
			var is_heal: bool = _hp_delta > 0
			var d_txt := ("+%d" % _hp_delta) if is_heal else ("✕ %d" % absi(_hp_delta))
			var d_col := TCGTheme.GREEN if is_heal else TCGTheme.RED
			var pill_pos := Vector2(hp_c.x + hp_r + (38.0 if shield_total > 0 else 10.0), hp_c.y - 12.0)
			var d_rect := Rect2(pill_pos, Vector2(56.0, 24.0))
			TCGTheme.draw_rounded_box(self, d_rect, Color(0.06, 0.08, 0.12, 0.92 * da), Color(d_col.r, d_col.g, d_col.b, da), 9, 1)
			TCGTheme.draw_text_centered(self, d_txt, d_rect.get_center(), 14, Color(d_col.r, d_col.g, d_col.b, da), true, false)

		# Top-right Element Crest
		TCGArt.draw_elem_symbol(self, d.element, Vector2(r.end.x - 18.0, r.position.y + 20.0), 13.0)

		# Top-centered AttachmentPill (STRICTLY 4 attachable elements only; never Anemo/Geo/Dendro) (T3.6)
		if not char_state.aura.is_empty() and ElementDB.can_attach_element(char_state.aura):
			var aura_pop: float = 1.0 + (_aura_pop_timer / 0.35) * 0.35 if _aura_pop_timer > 0.0 else 1.0
			var pill_rect := Rect2(r.get_center().x - 20.0 * aura_pop, r.position.y - 15.0, 40.0 * aura_pop, 28.0 * aura_pop)
			TCGTheme.draw_rounded_box(self, pill_rect, Color(0.08, 0.11, 0.16, 0.94), ElementDB.get_color(char_state.aura), 12, 2)
			TCGArt.draw_elem_symbol(self, char_state.aura, pill_rect.get_center(), 10.5 * aura_pop)
			_icon_rects.append({
				"rect": pill_rect.grow(4.0),
				"payload": {"kind": "aura", "aura": char_state.aura, "char_name": char_state.name}
			})

	# StatusRow under card: left-aligned, 8px gap, cap 5 visible + "+N" chip, 0.15s reflow (T3.7)
	var row_y: float = r.end.y + 8.0 + _defeat_status_slide * 24.0
	if _defeat_status_slide < 0.95 and not char_state.statuses.is_empty():
		var chip_sz: float = clampf(r.size.x * 0.21, 28.0, 34.0)
		var gap: float = 8.0
		var total_st: int = char_state.statuses.size()
		var show_overflow: bool = total_st > 5
		var max_vis: int = 4 if show_overflow else mini(5, total_st)
		_visible_status_count = max_vis
		_overflow_status_count = maxi(0, total_st - max_vis) if show_overflow else 0

		for idx in range(max_vis):
			var st := char_state.statuses[idx]
			var target_x: float = r.position.x + float(idx) * (chip_sz + gap)
			var skey: String = "%d_%s" % [idx, st.name]
			var cur_x: float = float(_status_anim_x.get(skey, target_x))
			if absf(cur_x - target_x) > 0.5 and is_inside_tree():
				cur_x = lerpf(cur_x, target_x, clampf(get_process_delta_time() / 0.15, 0.0, 1.0))
			else:
				cur_x = target_x
			_status_anim_x[skey] = cur_x

			var st_rect := Rect2(cur_x, row_y, chip_sz, chip_sz)
			_status_rects_cache.append(st_rect)
			var sdef: CardDataSystem.StatusData = CardDataSystem.get_status_def(st.name)
			var skind := "buff"
			var elem := d.element
			if st.name == "Frozen" or st.name == "Petrified":
				skind = "freeze"
				elem = "Cryo" if st.name == "Frozen" else "Geo"
			elif st.name == "Stunned":
				skind = "debuff"
				elem = "Electro"
			elif st.shield > 0 or (sdef != null and sdef.shield > 0):
				skind = "shield"
			var count_val: int = st.shield if st.shield > 0 else maxi(0, st.usages)
			TCGArt.draw_status_badge(self, st_rect, skind, elem, count_val, st.name)
			if count_val > 0:
				var cr := Rect2(st_rect.end.x - 16.0, st_rect.end.y - 14.0, 17.0, 14.0)
				TCGTheme.draw_rounded_box(self, cr, Color(0.06, 0.09, 0.14, 0.96), TCGTheme.GOLD_D, 4, 1)
				TCGTheme.draw_text_centered(self, str(count_val), cr.get_center(), 12, Color.WHITE, true, false)
			_icon_rects.append({
				"rect": st_rect.grow(4.0),
				"payload": {"kind": "status", "name": st.name, "status": st}
			})

		if show_overflow:
			var ov_x: float = r.position.x + float(max_vis) * (chip_sz + gap)
			var ov_rect := Rect2(ov_x, row_y, chip_sz, chip_sz)
			_status_rects_cache.append(ov_rect)
			draw_circle(ov_rect.get_center(), chip_sz * 0.48, Color8(24, 38, 56))
			draw_arc(ov_rect.get_center(), chip_sz * 0.48, 0.0, TAU, 20, TCGTheme.TEAL, 2.0)
			TCGTheme.draw_text_centered(self, "+%d" % _overflow_status_count, ov_rect.get_center(), 13, Color.WHITE, true, true)
			_icon_rects.append({
				"rect": ov_rect.grow(4.0),
				"payload": {"kind": "status_overflow", "char_name": char_state.name, "statuses": char_state.statuses}
			})

	# Clean Genshin-style Defeated Overlay: dark veil + crimson lotus/diamond defeat seal
	if defeated:
		draw_rect(r.grow(-4), Color(0.05, 0.05, 0.07, 0.62))
		var seal_c := art_rect.get_center()
		var sr: float = 28.0
		var seal_pts := PackedVector2Array([
			seal_c + Vector2(0, -sr * 1.18),
			seal_c + Vector2(sr * 0.85, 0),
			seal_c + Vector2(0, sr * 1.18),
			seal_c + Vector2(-sr * 0.85, 0),
		])
		draw_colored_polygon(seal_pts, Color(0.46, 0.13, 0.16, 0.85))
		var sc_closed := seal_pts.duplicate()
		sc_closed.append(seal_pts[0])
		draw_polyline(sc_closed, Color(0.92, 0.42, 0.42, 0.90), 2.0, true)
		draw_line(seal_c + Vector2(-9, -9), seal_c + Vector2(9, 9), Color(0.96, 0.78, 0.78, 0.90), 2.4)
		draw_line(seal_c + Vector2(9, -9), seal_c + Vector2(-9, 9), Color(0.96, 0.78, 0.78, 0.90), 2.4)

	# Target Marker Checkmark scaling in with TRANS_BACK (T3.11)
	if _target_marker_scale > 0.04:
		var mc := Vector2(r.get_center().x, r.position.y + r.size.y * 0.42)
		var mr: float = 24.0 * _target_marker_scale
		draw_circle(mc, mr + 5.0, Color(TCGTheme.GOLD_L.r, TCGTheme.GOLD_L.g, TCGTheme.GOLD_L.b, 0.24))
		draw_circle(mc, mr, Color(0.95, 0.76, 0.24, 0.92))
		draw_arc(mc, mr, 0.0, TAU, 28, Color.WHITE, 2.4)
		draw_line(mc + Vector2(-8.0, 1.0) * _target_marker_scale, mc + Vector2(-1.5, 7.5) * _target_marker_scale, Color.WHITE, 3.4)
		draw_line(mc + Vector2(-1.5, 7.5) * _target_marker_scale, mc + Vector2(9.0, -6.5) * _target_marker_scale, Color.WHITE, 3.4)

	# Clean Genshin-style Combat / Action Forecast Overlay (inline HP badge + golden target check)
	_draw_action_preview(r, art_rect)


func _draw_action_preview(r: Rect2, art_rect: Rect2) -> void:
	if preview_info.is_empty():
		return

	var total_dmg: int = int(preview_info.get("total_dmg", 0))
	var shield_dmg: int = int(preview_info.get("shield_dmg", 0))
	var dtype: String = String(preview_info.get("dtype", ""))
	var reaction: String = String(preview_info.get("reaction", ""))
	var swirled: String = String(preview_info.get("swirled", ""))
	var new_aura: String = String(preview_info.get("new_aura", ""))
	var aura_cleared: String = String(preview_info.get("aura_cleared", ""))
	var defeated_now: bool = bool(preview_info.get("defeated", false))
	var forced_in: bool = bool(preview_info.get("forced_switch_in", false))
	var heal_amt: int = int(preview_info.get("heal", 0))
	var shield_gain: int = int(preview_info.get("shield_gain", 0))
	var switch_in: bool = bool(preview_info.get("switch_in", false))

	var impacted: bool = (total_dmg > 0 or defeated_now or not reaction.is_empty() or not aura_cleared.is_empty() or forced_in or heal_amt > 0 or shield_gain > 0 or switch_in)
	if not impacted:
		return

	# Clean luminous gold/element highlight rim around impacted card
	var ring_col := TCGTheme.RED if defeated_now else (
		TCGTheme.elem_color("Anemo") if (not aura_cleared.is_empty() and total_dmg == 0) else (
			TCGTheme.HEAL if (heal_amt > 0 and total_dmg == 0) else (
				TCGTheme.TEAL if (shield_gain > 0 and total_dmg == 0) else TCGTheme.GOLD_L
			)
		)
	)
	TCGTheme.draw_rounded_box(self, r.grow(2.5), Color(ring_col.r, ring_col.g, ring_col.b, 0.08), ring_col, 14, 2.5)

	# 1. Genshin-style crimson `-DMG` pill right beside top-left HP shield + golden target checkmark!
	if total_dmg > 0:
		var badge_w: float = 52.0 if not defeated_now else 66.0
		var badge_r := Rect2(r.position.x + 38.0, r.position.y + 4.0, badge_w, 26.0)
		var bg_c := Color8(186, 44, 42) if not defeated_now else Color8(142, 22, 26)
		TCGTheme.draw_rounded_box(self, badge_r, bg_c, TCGTheme.GOLD_L if not defeated_now else Color(1.0, 0.65, 0.65), 11, 1.8, Vector2(0, 2), 95)
		var txt := ("-%d KO" % total_dmg) if defeated_now else ("-%d" % total_dmg)
		TCGTheme.draw_text_centered(self, txt, badge_r.get_center(), 15 if not defeated_now else 13, Color.WHITE, true, true)

		# Centered golden target checkmark on primary struck card (non-piercing or active target)
		if dtype != CardDataSystem.PIERCING:
			var mc := art_rect.get_center()
			draw_circle(mc, 24.0, Color(0.96, 0.78, 0.24, 0.88))
			draw_arc(mc, 24.0, 0.0, TAU, 24, Color.WHITE, 2.4)
			draw_line(mc + Vector2(-8.0, 1.0), mc + Vector2(-1.5, 7.5), Color.WHITE, 3.4)
			draw_line(mc + Vector2(-1.5, 7.5), mc + Vector2(9.0, -6.5), Color.WHITE, 3.4)
		if shield_dmg > 0:
			var sh_r := Rect2(r.position.x + 38.0, r.position.y + 33.0, 56.0, 20.0)
			TCGTheme.draw_rounded_box(self, sh_r, Color(0.08, 0.16, 0.24, 0.94), TCGTheme.TEAL, 8, 1.2)
			TCGTheme.draw_text_centered(self, "Sh -%d" % shield_dmg, sh_r.get_center(), 11, Color.WHITE, true, false)

	# 2. Sleek Reaction / New Aura pill cleanly ABOVE the card (never blocking portrait)
	if not reaction.is_empty():
		var rx_els: Array = TCGTheme.REACT.get(reaction, {}).get("elements", [])
		var rx_col: Color = TCGTheme.elem_color(String(rx_els[rx_els.size() - 1])) if not rx_els.is_empty() else TCGTheme.GOLD_L
		var rx_title := ("SWIRL · %s" % swirled.to_upper()) if not swirled.is_empty() else reaction.to_upper()
		var rrect := Rect2(r.get_center().x - 68.0, r.position.y - 30.0, 136.0, 24.0)
		TCGTheme.draw_rounded_box(self, rrect, Color(0.08, 0.06, 0.04, 0.94), rx_col, 10, 1.8)
		TCGTheme.draw_text_centered(self, rx_title, rrect.get_center(), 12, TCGTheme.GOLD_L, true, true)
	elif not new_aura.is_empty() and total_dmg > 0:
		var acol := TCGTheme.elem_color(new_aura)
		var arect := Rect2(r.get_center().x - 46.0, r.position.y - 26.0, 92.0, 21.0)
		TCGTheme.draw_rounded_box(self, arect, Color(0.06, 0.09, 0.14, 0.92), acol, 9, 1.4)
		TCGTheme.draw_text_centered(self, "+ %s" % new_aura, arect.get_center(), 11, acol.lightened(0.3), true, false)

	# 3. Ally Heal / Shield / Forced-Switch compact pills beside HP shield
	if heal_amt > 0:
		var hrect := Rect2(r.position.x + 38.0, r.position.y + 4.0, 56.0, 26.0)
		TCGTheme.draw_rounded_box(self, hrect, Color(0.08, 0.34, 0.16, 0.96), TCGTheme.HEAL, 11, 1.8)
		TCGTheme.draw_text_centered(self, "+%d" % heal_amt, hrect.get_center(), 15, Color.WHITE, true, true)

	if shield_gain > 0:
		var sy: float = r.position.y + (34.0 if heal_amt > 0 else 4.0)
		var srect := Rect2(r.position.x + 38.0, sy, 66.0, 24.0)
		TCGTheme.draw_rounded_box(self, srect, Color(0.08, 0.20, 0.30, 0.96), TCGTheme.TEAL, 10, 1.6)
		TCGTheme.draw_text_centered(self, "+%d SHD" % shield_gain, srect.get_center(), 12, Color.WHITE, true, false)

	if not aura_cleared.is_empty():
		var cl_col := TCGTheme.elem_color("Anemo")
		var crect := Rect2(r.get_center().x - 62.0, r.position.y - 30.0, 124.0, 24.0)
		TCGTheme.draw_rounded_box(self, crect, Color(0.05, 0.16, 0.16, 0.96), cl_col, 10, 1.8)
		TCGTheme.draw_text_centered(self, "CLEANSE %s" % aura_cleared.to_upper(), crect.get_center(), 11, cl_col.lightened(0.3), true, true)

	if forced_in or switch_in:
		var wrect := Rect2(r.get_center().x - 54.0, r.position.y - 26.0, 108.0, 22.0)
		TCGTheme.draw_rounded_box(self, wrect, Color(0.14, 0.10, 0.05, 0.94), TCGTheme.GOLD_L, 9, 1.5)
		TCGTheme.draw_text_centered(self, "FORCED IN" if forced_in else "ACTIVE", wrect.get_center(), 11, TCGTheme.GOLD_L, true, false)

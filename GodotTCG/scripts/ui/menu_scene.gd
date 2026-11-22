class_name TCGMenuScene
extends Control
## Main Menu Scene — Upgraded with custom `menu_bg.jpeg` tavern backdrop,
## subtle drifting elemental crests, smooth hover elevation, and clean gold plaques.

signal mode_selected(mode_id: String)

var _t: float = 0.0
var _floaters: Array[Dictionary] = []
var _hovered_btn: int = -1
var _btn_hover_t: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var settings_modal: SettingsModal = null

const BUTTONS: Array[Dictionary] = [
	{"label": "Human vs AI", "id": "pve", "col": TCGTheme.GREEN},
	{"label": "Human vs Human (same device)", "id": "pvp", "col": TCGTheme.TEAL},
	{"label": "AI vs AI (spectate)", "id": "ava", "col": TCGTheme.TEAL},
	{"label": "Deck Builder", "id": "decks", "col": TCGTheme.GOLD},
	{"label": "Settings", "id": "settings", "col": TCGTheme.GOLD_L},
	{"label": "Quit", "id": "quit", "col": TCGTheme.RED},
]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_init_floaters()
	settings_modal = SettingsModal.new()
	settings_modal.set_menu_mode(true)
	settings_modal.z_index = UIConstants.Z_MODAL
	add_child(settings_modal)
	settings_modal.sync_layout(Vector2(maxf(size.x, float(TCGTheme.W)), maxf(size.y, float(TCGTheme.H))))


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and settings_modal != null:
		settings_modal.sync_layout(size)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_ESCAPE and settings_modal != null and settings_modal.visible:
			settings_modal.close()
			get_viewport().set_input_as_handled()


func open_settings() -> void:
	if settings_modal == null:
		settings_modal = SettingsModal.new()
		settings_modal.set_menu_mode(true)
		settings_modal.z_index = UIConstants.Z_MODAL
		add_child(settings_modal)
	settings_modal.open()


func _init_floaters() -> void:
	_floaters.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var elems: Array[String] = [
		CardDataSystem.PYRO,
		CardDataSystem.HYDRO,
		CardDataSystem.ANEMO,
		CardDataSystem.GEO,
		CardDataSystem.ELECTRO,
		CardDataSystem.OMNI,
	]
	for i in range(18):
		var el: String = elems[rng.randi_range(0, elems.size() - 1)]
		_floaters.append({
			"x": rng.randf_range(60.0, TCGTheme.W - 60.0),
			"y": rng.randf_range(40.0, TCGTheme.H - 40.0),
			"vy": rng.randf_range(8.0, 18.0),
			"r": rng.randi_range(10, 18),
			"el": el,
			"ph": rng.randf_range(0.0, TAU),
		})


func _process(delta: float) -> void:
	_t += delta
	for f in _floaters:
		f["y"] = float(f["y"]) - float(f["vy"]) * delta
		if float(f["y"]) < -36.0:
			f["y"] = float(TCGTheme.H + 36)
	var k := 1.0 - exp(-14.0 * delta)
	for i in range(_btn_hover_t.size()):
		var tgt := 1.0 if i == _hovered_btn else 0.0
		_btn_hover_t[i] = lerpf(_btn_hover_t[i], tgt, k)
	queue_redraw()


func _button_rect(idx: int) -> Rect2:
	var sz := Vector2(maxf(size.x, float(TCGTheme.W)), maxf(size.y, float(TCGTheme.H)))
	var safe := UIConstants.get_safe_rect(sz)
	var cx: float = safe.get_center().x
	var bw: float = clampf(safe.size.x * 0.26, 420.0, 520.0)
	var bh: float = clampf(safe.size.y * 0.060, 54.0, 68.0)
	var gap: float = clampf(safe.size.y * 0.016, 14.0, 18.0)
	var y0: float = safe.position.y + safe.size.y * 0.34
	return Rect2(cx - bw * 0.5, y0 + float(idx) * (bh + gap), bw, bh)


func _gui_input(event: InputEvent) -> void:
	if settings_modal != null and settings_modal.visible:
		return
	if event is InputEventMouseMotion:
		var prev := _hovered_btn
		_hovered_btn = -1
		for i in range(BUTTONS.size()):
			if _button_rect(i).has_point(event.position):
				_hovered_btn = i
				break
		if prev != _hovered_btn:
			if _hovered_btn >= 0 and is_inside_tree() and AudioManager != null:
				AudioManager.play_sfx("card_hover")
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in range(BUTTONS.size()):
			if _button_rect(i).has_point(event.position):
				if is_inside_tree() and AudioManager != null:
					AudioManager.play_sfx("ui_click")
				var btn_id := String(BUTTONS[i]["id"])
				if btn_id == "settings":
					open_settings()
				else:
					mode_selected.emit(btn_id)
				break


func _draw() -> void:
	var w: float = maxf(size.x, float(TCGTheme.W))
	var h: float = maxf(size.y, float(TCGTheme.H))

	# Custom tavern/celestial hall backdrop with subtle atmospheric vignette
	var bg_tex := TCGArt.get_menu_bg_texture()
	if bg_tex != null:
		TCGArt.draw_texture_cover(self, bg_tex, Rect2(0, 0, w, h), Color.WHITE, 0.5)
		draw_rect(Rect2(0, 0, w, h), Color(0.03, 0.05, 0.09, 0.44))
		# Soft vertical readability gradient behind center menu column
		var col_w: float = minf(w * 0.52, 820.0)
		draw_rect(Rect2((w - col_w) * 0.5, 0.0, col_w, h), Color(0.02, 0.04, 0.08, 0.28))
	else:
		TCGArt.draw_mat(self, Vector2(w, h))
		draw_rect(Rect2(0, 0, w, h), Color(0.03, 0.05, 0.09, 0.55))

	# Soft ambient floating elemental crests
	for f in _floaters:
		var fx: float = float(f["x"]) + sin(_t * 0.9 + float(f["ph"])) * 12.0
		var fy: float = float(f["y"])
		var fr: float = float(f["r"])
		var el: String = String(f["el"])
		var c := TCGTheme.elem_color(el)
		TCGArt.draw_elem_symbol(self, el, Vector2(fx, fy), fr, Color(c.r, c.g, c.b, 0.28), false)

	# Title Banner Plaque
	var safe := UIConstants.get_safe_rect(Vector2(w, h))
	var cx: float = safe.get_center().x
	var tb_w: float = clampf(safe.size.x * 0.52, 680.0, 920.0)
	var tb_h: float = clampf(safe.size.y * 0.18, 150.0, 195.0)
	var tb_y: float = safe.position.y + safe.size.y * 0.08
	var title_box := Rect2(cx - tb_w * 0.5, tb_y, tb_w, tb_h)
	TCGTheme.draw_gold_frame(self, title_box, Color(0.05, 0.08, 0.14, 0.86), 16, true)

	# Active 5 Element Crests + Omni centerpiece flanking the title
	var crest_elems: Array[String] = [
		CardDataSystem.ANEMO,
		CardDataSystem.HYDRO,
		CardDataSystem.PYRO,
		CardDataSystem.OMNI,
		CardDataSystem.ELECTRO,
		CardDataSystem.GEO,
	]
	for i in range(crest_elems.size()):
		var ex: float = cx - 150.0 + float(i) * 60.0
		var is_omni := (crest_elems[i] == CardDataSystem.OMNI)
		TCGArt.draw_elem_symbol(self, crest_elems[i], Vector2(ex, tb_y + 32.0), 13.5 if is_omni else 11.5, Color(0, 0, 0, 0), false)

	TCGTheme.draw_text_centered(
		self,
		"RESONANCE",
		Vector2(cx, tb_y + tb_h * 0.53),
		UIConstants.FONT_TITLE + 8,
		TCGTheme.GOLD_L,
		true,
		true
	)
	TCGTheme.draw_text_centered(
		self,
		"Genius Invokation Tactical Card Game · CSE 3210",
		Vector2(cx, tb_y + tb_h * 0.82),
		UIConstants.FONT_BODY + 2,
		TCGTheme.TEXT,
		false,
		true
	)

	# Mode / Navigation Buttons with smooth hover lift & gold aura
	for i in range(BUTTONS.size()):
		var b: Dictionary = BUTTONS[i]
		var r := _button_rect(i)
		var ht: float = _btn_hover_t[i] if i < _btn_hover_t.size() else 0.0
		var draw_r := r.grow(ht * 3.5)
		draw_r.position.y -= ht * 2.5
		var col: Color = b["col"]
		if ht > 0.02:
			TCGTheme.draw_rounded_box(self, draw_r.grow(3.0), Color(col.r, col.g, col.b, 0.14 * ht), Color(TCGTheme.GOLD_L.r, TCGTheme.GOLD_L.g, TCGTheme.GOLD_L.b, 0.55 * ht), 14, 1.5)
		TCGTheme.draw_plaque(self, draw_r, String(b["label"]), col, _hovered_btn == i, false, false)

	# Footer status strip
	CardDataSystem.load_all_content()
	var footer_txt := "%d Characters · %d Action Cards · %d Preset Decks · %d-Card Decks" % [
		CardDataSystem.char_defs.size(),
		CardDataSystem.card_defs.size(),
		CardDataSystem.preset_defs.size(),
		CardDataSystem.DECK_SIZE,
	]
	var foot_r := Rect2(cx - 280.0, h - 42.0, 560.0, 28.0)
	TCGTheme.draw_rounded_box(self, foot_r, Color(0.04, 0.07, 0.12, 0.72), Color(TCGTheme.GOLD_D.r, TCGTheme.GOLD_D.g, TCGTheme.GOLD_D.b, 0.45), 14, 1)
	TCGTheme.draw_text_centered(self, footer_txt, foot_r.get_center(), 14, TCGTheme.DIM, false, true)

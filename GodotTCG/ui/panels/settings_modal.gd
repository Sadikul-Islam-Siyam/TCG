class_name SettingsModal
extends Control
## T12.3: In-Match Settings Modal.
## Controls Master/Music/SFX/UI bus volumes (via AudioManager), animation speed
## multiplier (1x / 1.5x / 2x / Instant), confirm-before-End-Round toggle, language stub,
## plus quick match controls (Resume / Restart / Main Menu).

signal closed
signal speed_changed(speed_mult: float)
signal confirm_end_round_changed(enabled: bool)
signal restart_requested
signal main_menu_requested

var confirm_end_round: bool = false
var current_speed: float = 1.0
var selected_language: String = "English"

var _backdrop: ColorRect = null
var _panel: PanelContainer = null
var _speed_buttons: Array[Button] = []
var _confirm_chk: CheckButton = null
var _lang_btn: OptionButton = null
var _sliders: Dictionary = {}


func _init() -> void:
	name = "SettingsModal"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()


func _build_ui() -> void:
	theme = TCGTheme.build_app_theme()

	_backdrop = ColorRect.new()
	_backdrop.color = Color(0.02, 0.04, 0.08, 0.62)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			close()
	)
	add_child(_backdrop)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", TCGTheme.make_slate_panel_style(Color(0.06, 0.09, 0.15, 0.98), TCGTheme.GOLD, TCGTheme.GOLD_D, 16, 2))
	add_child(_panel)

	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 24)
	m.add_theme_constant_override("margin_right", 24)
	m.add_theme_constant_override("margin_top", 20)
	m.add_theme_constant_override("margin_bottom", 20)
	_panel.add_child(m)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	m.add_child(root)

	# Header
	var hdr := HBoxContainer.new()
	root.add_child(hdr)
	var title := Label.new()
	title.text = "MATCH SETTINGS"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", TCGTheme.GOLD_L)
	hdr.add_child(title)

	var x_btn := Button.new()
	x_btn.text = "×"
	x_btn.custom_minimum_size = Vector2(36, 36)
	x_btn.pressed.connect(close)
	hdr.add_child(x_btn)

	root.add_child(HSeparator.new())

	# Volume Sliders
	for bus in ["Master", "Music", "SFX", "UI"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		root.add_child(row)

		var lbl := Label.new()
		lbl.text = "%s Volume" % bus
		lbl.custom_minimum_size = Vector2(150, 0)
		lbl.add_theme_color_override("font_color", TCGTheme.TEXT)
		row.add_child(lbl)

		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.05
		sl.value = AudioManager.get_bus_volume_linear(bus) if AudioManager != null else 0.85
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.value_changed.connect(func(v: float) -> void:
			if AudioManager != null:
				AudioManager.set_bus_volume_linear(bus, v)
		)
		row.add_child(sl)
		_sliders[bus] = sl

	root.add_child(HSeparator.new())

	# Animation Speed Row (1x / 1.5x / 2x / Instant)
	var sp_row := HBoxContainer.new()
	sp_row.add_theme_constant_override("separation", 8)
	root.add_child(sp_row)

	var sp_lbl := Label.new()
	sp_lbl.text = "Animation Speed"
	sp_lbl.custom_minimum_size = Vector2(150, 0)
	sp_row.add_child(sp_lbl)

	var speeds := [
		{"label": "1×", "val": 1.0},
		{"label": "1.5×", "val": 1.5},
		{"label": "2×", "val": 2.0},
		{"label": "Instant", "val": 8.0},
	]
	for item in speeds:
		var b := Button.new()
		b.text = String(item["label"])
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(72, 36)
		var v: float = float(item["val"])
		b.pressed.connect(func() -> void:
			set_speed(v)
		)
		sp_row.add_child(b)
		_speed_buttons.append(b)

	# Confirm Before End Round Toggle
	_confirm_chk = CheckButton.new()
	_confirm_chk.text = "Confirm before End Round"
	_confirm_chk.button_pressed = confirm_end_round
	_confirm_chk.toggled.connect(func(on: bool) -> void:
		confirm_end_round = on
		confirm_end_round_changed.emit(on)
	)
	root.add_child(_confirm_chk)

	# Language Display Stub
	var lang_row := HBoxContainer.new()
	lang_row.add_theme_constant_override("separation", 10)
	root.add_child(lang_row)
	var lang_lbl := Label.new()
	lang_lbl.text = "Language"
	lang_lbl.custom_minimum_size = Vector2(150, 0)
	lang_row.add_child(lang_lbl)

	_lang_btn = OptionButton.new()
	_lang_btn.add_item("English")
	_lang_btn.add_item("English (Lore Compact)")
	_lang_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lang_btn.item_selected.connect(func(idx: int) -> void:
		selected_language = _lang_btn.get_item_text(idx)
	)
	lang_row.add_child(_lang_btn)

	root.add_child(HSeparator.new())

	# Action Buttons
	var act_row := HBoxContainer.new()
	act_row.add_theme_constant_override("separation", 10)
	act_row.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(act_row)

	var menu_btn := Button.new()
	menu_btn.text = "Main Menu"
	menu_btn.pressed.connect(func() -> void:
		close()
		main_menu_requested.emit()
	)
	act_row.add_child(menu_btn)

	var rst_btn := Button.new()
	rst_btn.text = "Restart Match"
	rst_btn.pressed.connect(func() -> void:
		close()
		restart_requested.emit()
	)
	act_row.add_child(rst_btn)

	var ok_btn := Button.new()
	ok_btn.text = "Resume"
	ok_btn.custom_minimum_size = Vector2(116, 40)
	ok_btn.pressed.connect(close)
	act_row.add_child(ok_btn)

	_refresh_speed_buttons()


func set_speed(val: float) -> void:
	current_speed = val
	_refresh_speed_buttons()
	speed_changed.emit(val)


func _refresh_speed_buttons() -> void:
	var vals := [1.0, 1.5, 2.0, 8.0]
	for i in range(mini(_speed_buttons.size(), vals.size())):
		_speed_buttons[i].button_pressed = is_equal_approx(current_speed, vals[i])


func sync_layout(viewport_size: Vector2) -> void:
	var safe := UIConstants.get_safe_rect(viewport_size)
	size = viewport_size
	if _backdrop != null:
		_backdrop.position = Vector2.ZERO
		_backdrop.size = viewport_size
	if _panel != null:
		var w := minf(540.0, safe.size.x - 40.0)
		var h := minf(480.0, safe.size.y - 40.0)
		_panel.size = Vector2(w, h)
		_panel.position = safe.position + (safe.size - _panel.size) * 0.5


func open() -> void:
	for bus in _sliders.keys():
		if AudioManager != null:
			(_sliders[bus] as HSlider).value = AudioManager.get_bus_volume_linear(String(bus))
	if _confirm_chk != null:
		_confirm_chk.button_pressed = confirm_end_round
	_refresh_speed_buttons()
	sync_layout(get_viewport_rect().size if is_inside_tree() else size)
	visible = true


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


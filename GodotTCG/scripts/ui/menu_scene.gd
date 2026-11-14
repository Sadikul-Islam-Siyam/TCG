class_name TCGMenuScene
extends Control
## Stage 5: Main Menu Scene
## Direct port of PythonTCG/ui/menu.py (`MenuScene`).
## Renders the drifting elemental crests background, gold title/subtitle,
## 5 mode/navigation plaque buttons, and footer status.

signal mode_selected(mode_id: String)

var _t: float = 0.0
var _floaters: Array[Dictionary] = []
var _hovered_btn: int = -1

const BUTTONS: Array[Dictionary] = [
	{"label": "Human vs AI", "id": "pve", "col": TCGTheme.GREEN},
	{"label": "Human vs Human (same device)", "id": "pvp", "col": TCGTheme.TEAL},
	{"label": "AI vs AI (spectate)", "id": "ava", "col": TCGTheme.TEAL},
	{"label": "Deck Builder", "id": "decks", "col": TCGTheme.GOLD},
	{"label": "Quit", "id": "quit", "col": TCGTheme.RED},
]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_init_floaters()


func _init_floaters() -> void:
	_floaters.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var elems: PackedStringArray = CardDataSystem.ELEMENTS
	for i in range(26):
		var el: String = elems[rng.randi_range(0, elems.size() - 1)]
		_floaters.append({
			"x": rng.randf_range(40.0, TCGTheme.W - 40.0),
			"y": rng.randf_range(40.0, TCGTheme.H - 40.0),
			"vy": rng.randf_range(12.0, 28.0),
			"r": rng.randi_range(10, 22),
			"el": el,
			"ph": rng.randf_range(0.0, TAU),
		})


func _process(delta: float) -> void:
	_t += delta
	for f in _floaters:
		f["y"] = float(f["y"]) - float(f["vy"]) * delta
		if float(f["y"]) < -30.0:
			f["y"] = float(TCGTheme.H + 30)
	queue_redraw()


func _button_rect(idx: int) -> Rect2:
	var sz := Vector2(maxf(size.x, float(TCGTheme.W)), maxf(size.y, float(TCGTheme.H)))
	var safe := UIConstants.get_safe_rect(sz)
	var cx: float = safe.get_center().x
	var bw: float = clampf(safe.size.x * 0.26, 420.0, 520.0)
	var bh: float = clampf(safe.size.y * 0.068, 60.0, 76.0)
	var y0: float = safe.position.y + safe.size.y * 0.36
	return Rect2(cx - bw * 0.5, y0 + float(idx) * (bh + 20.0), bw, bh)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var prev := _hovered_btn
		_hovered_btn = -1
		for i in range(BUTTONS.size()):
			if _button_rect(i).has_point(event.position):
				_hovered_btn = i
				break
		if prev != _hovered_btn:
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in range(BUTTONS.size()):
			if _button_rect(i).has_point(event.position):
				mode_selected.emit(String(BUTTONS[i]["id"]))
				break


func _draw() -> void:
	var w: float = maxf(size.x, float(TCGTheme.W))
	var h: float = maxf(size.y, float(TCGTheme.H))

	# Dueling mat background with dark translucent veil
	TCGArt.draw_mat(self, Vector2(w, h))
	draw_rect(Rect2(0, 0, w, h), Color(0.03, 0.05, 0.09, 0.55))

	# Drifting elemental symbols
	for f in _floaters:
		var fx: float = float(f["x"]) + sin(_t * 1.2 + float(f["ph"])) * 10.0
		var fy: float = float(f["y"])
		var fr: float = float(f["r"])
		var el: String = String(f["el"])
		TCGArt.draw_elem_symbol(self, el, Vector2(fx, fy), fr, TCGTheme.elem_color(el), false)

	# Title Banner Plaque
	var safe := UIConstants.get_safe_rect(Vector2(w, h))
	var cx: float = safe.get_center().x
	var tb_w: float = clampf(safe.size.x * 0.52, 680.0, 920.0)
	var tb_h: float = clampf(safe.size.y * 0.18, 150.0, 195.0)
	var tb_y: float = safe.position.y + safe.size.y * 0.08
	var title_box := Rect2(cx - tb_w * 0.5, tb_y, tb_w, tb_h)
	TCGTheme.draw_gold_frame(self, title_box, Color(0.07, 0.11, 0.18, 0.90), 16, true)

	# Six element gems flanking the title
	var elems: PackedStringArray = CardDataSystem.ELEMENTS
	for i in range(elems.size()):
		var ex: float = cx - 150.0 + float(i) * 60.0
		TCGArt.draw_elem_symbol(self, elems[i], Vector2(ex, tb_y + 30.0), 11.0)

	TCGTheme.draw_text_centered(
		self,
		"GENIUS INVOKATION",
		Vector2(cx, tb_y + tb_h * 0.52),
		UIConstants.FONT_TITLE + 6,
		TCGTheme.GOLD_L,
		true,
		true
	)
	TCGTheme.draw_text_centered(
		self,
		"a fan-made card game · Godot 4.7.2 + GDScript",
		Vector2(cx, tb_y + tb_h * 0.80),
		UIConstants.FONT_BODY + 2,
		TCGTheme.DIM,
		false,
		true
	)

	# Mode / Navigation Buttons
	for i in range(BUTTONS.size()):
		var b: Dictionary = BUTTONS[i]
		var r := _button_rect(i)
		var col: Color = b["col"]
		TCGTheme.draw_plaque(self, r, String(b["label"]), col, _hovered_btn == i, false, false)

	# Footer
	CardDataSystem.load_all_content()
	var footer_txt := "%d Characters · %d Action Cards · %d Preset Decks · %d-Card Decks" % [
		CardDataSystem.char_defs.size(),
		CardDataSystem.card_defs.size(),
		CardDataSystem.preset_defs.size(),
		CardDataSystem.DECK_SIZE,
	]
	TCGTheme.draw_text_centered(
		self,
		footer_txt,
		Vector2(cx, h - 28.0),
		15,
		TCGTheme.DIM,
		false,
		true
	)

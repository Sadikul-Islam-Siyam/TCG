class_name TCGBattleLogPanel
extends Control
## T12.1: Collapsible Combat Log Drawer Component.
## Shows a compact clickable summary pill by default; expands smoothly into a
## scrollable color-coded history list on click without cluttering the board.

signal toggled(expanded: bool)

var log_entries: Array[String] = []
var expanded: bool = false
var scroll_offset: int = 0

var _anim_open: float = 0.0
var _collapsed_size := Vector2(226, 52)
var _expanded_size := Vector2(316, 268)


func _init() -> void:
	custom_minimum_size = _collapsed_size
	size = _collapsed_size
	mouse_filter = Control.MOUSE_FILTER_STOP


func setup(p_logs: Array[String]) -> void:
	log_entries = p_logs.duplicate()
	scroll_offset = 0
	queue_redraw()


func set_expanded(val: bool) -> void:
	if expanded == val:
		return
	expanded = val
	toggled.emit(expanded)
	queue_redraw()


func _process(delta: float) -> void:
	var target := 1.0 if expanded else 0.0
	if absf(_anim_open - target) > 0.01:
		_anim_open = lerpf(_anim_open, target, minf(1.0, delta * 14.0))
		if absf(_anim_open - target) <= 0.01:
			_anim_open = target
		var next_sz: Vector2 = _collapsed_size.lerp(_expanded_size, _anim_open)
		custom_minimum_size = next_sz
		size = next_sz
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			# Header toggles expand/collapse
			if event.position.y <= 34.0 or not expanded:
				set_expanded(not expanded)
				get_viewport().set_input_as_handled()
		elif expanded and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			scroll_offset = mini(maxi(0, log_entries.size() - 8), scroll_offset + 1)
			queue_redraw()
			get_viewport().set_input_as_handled()
		elif expanded and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			scroll_offset = maxi(0, scroll_offset - 1)
			queue_redraw()
			get_viewport().set_input_as_handled()


func _entry_style(entry: String) -> Dictionary:
	var col := TCGTheme.TEXT
	var badge := "·"
	if entry.begins_with("==="):
		col = TCGTheme.GOLD_L
		badge = "◆"
	elif entry.contains(" triggers "):
		col = Color8(255, 196, 118)
		badge = "✦"
	elif entry.contains(" takes "):
		col = TCGTheme.RED
		badge = "⚔"
	elif entry.contains(" heals "):
		col = TCGTheme.GREEN
		badge = "+"
	elif entry.contains(" uses "):
		col = TCGTheme.TEAL
		badge = "◈"
	return {"color": col, "badge": badge}


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	TCGTheme.draw_rounded_box(
		self,
		r,
		Color(0.05, 0.09, 0.14, 0.90),
		TCGTheme.GOLD if expanded else TCGTheme.GOLD_D,
		10,
		1.4 if expanded else 1.0,
		Vector2(0, 3),
		70
	)

	var header_txt := "LOG (%d)" % log_entries.size()
	TCGTheme.draw_text_pos(self, header_txt, Vector2(12, 16 if _anim_open < 0.15 else 8), 14, TCGTheme.GOLD_L if expanded else TCGTheme.GOLD, true, true)
	var chev := "▾" if expanded else "▸"
	TCGTheme.draw_text_pos(self, chev, Vector2(r.size.x - 20, 15 if _anim_open < 0.15 else 7), 15, TCGTheme.GOLD_L, true, false)

	if _anim_open < 0.15:
		return

	draw_line(Vector2(8, 32), Vector2(r.size.x - 8, 32), TCGTheme.GOLD_D, 1.0)
	var max_lines: int = maxi(1, int((r.size.y - 40.0) / 24.0))
	var end_idx: int = maxi(0, log_entries.size() - scroll_offset)
	var start_idx: int = maxi(0, end_idx - max_lines)
	var y: float = 38.0
	for i in range(start_idx, end_idx):
		var entry: String = log_entries[i]
		var st := _entry_style(entry)
		var short_txt := entry
		if short_txt.length() > 36:
			short_txt = short_txt.substr(0, 35) + "…"
		TCGTheme.draw_text_pos(self, "%s %s" % [String(st["badge"]), short_txt], Vector2(12, y), 13, st["color"], false, false)
		y += 24.0

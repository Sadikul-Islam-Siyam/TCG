class_name StatusIcon
extends Control
## Phase 4 (T4.4): Reusable StatusIcon chip used for character statuses, combat statuses,
## equipment badges, and overflow counters. Hover shows a delayed single-line tag (never a large black
## card box); clicking or right-clicking emits `clicked` to open the Detail Drawer.

signal clicked(payload: Dictionary)
signal hover_changed(hovered: bool, payload: Dictionary)

var data: Dictionary = {}
var _count: int = 0
var _hovered: bool = false
var _hover_time: float = 0.0
var _show_tag: bool = false
var _scale_fx: float = 1.0
var _fade_fx: float = 1.0
var _tween: Tween = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(30, 30)


func setup(p_data: Dictionary) -> void:
	data = p_data.duplicate()
	var c_val: int = int(data.get("count", data.get("usages", data.get("shield", -1))))
	_count = c_val
	_fade_fx = 1.0
	_scale_fx = 1.0
	queue_redraw()


func set_count(new_val: int, animate: bool = true) -> void:
	if new_val == _count:
		return
	_count = new_val
	if animate and is_inside_tree():
		pulse()
	queue_redraw()


func pulse() -> void:
	if not is_inside_tree():
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_scale_fx = 1.28
	_tween = create_tween()
	_tween.tween_property(self, "_scale_fx", 1.0, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_method(func(_v: float) -> void: queue_redraw(), 0.0, 1.0, 0.22)


func remove_animated() -> void:
	if not is_inside_tree():
		queue_free()
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(self, "_scale_fx", 0.3, 0.18)
	_tween.tween_property(self, "_fade_fx", 0.0, 0.18)
	_tween.parallel().tween_method(func(_v: float) -> void: queue_redraw(), 0.0, 1.0, 0.18)
	await _tween.finished
	if is_instance_valid(self):
		queue_free()


func _process(delta: float) -> void:
	if _hovered and not _show_tag:
		_hover_time += delta
		if _hover_time >= 0.4:
			_show_tag = true
			queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER:
		_hovered = true
		_hover_time = 0.0
		_show_tag = false
		hover_changed.emit(true, data)
		queue_redraw()
	elif what == NOTIFICATION_MOUSE_EXIT:
		_hovered = false
		_hover_time = 0.0
		_show_tag = false
		hover_changed.emit(false, data)
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			clicked.emit(data)
			accept_event()


func _ring_color() -> Color:
	var kind := String(data.get("kind", "buff"))
	match kind:
		"debuff":
			return TCGTheme.RED
		"shield":
			return Color8(190, 212, 232)
		"special":
			return Color8(204, 152, 255)
		"weapon":
			return Color8(225, 130, 108)
		"artifact":
			return TCGTheme.GOLD
		"talent":
			return ElementDB.get_color(String(data.get("elem", "Pyro")))
		"overflow":
			return TCGTheme.TEAL
		_:
			return TCGTheme.GOLD


func _draw() -> void:
	if _fade_fx <= 0.02:
		return
	var prev_mod := modulate
	modulate = Color(1, 1, 1, _fade_fx)
	var center := size * 0.5
	if absf(_scale_fx - 1.0) > 0.005:
		draw_set_transform(center * (1.0 - _scale_fx), 0.0, Vector2(_scale_fx, _scale_fx))

	var rect := Rect2(Vector2.ZERO, size)
	var kind := String(data.get("kind", "buff"))
	var elem := String(data.get("elem", "Physical"))
	var ring := _ring_color()

	if kind == "overflow":
		var c := rect.get_center()
		var r: float = minf(size.x, size.y) * 0.46
		draw_circle(c, r, Color8(24, 38, 56))
		draw_arc(c, r, 0.0, TAU, 24, TCGTheme.GOLD_L if _hovered else ring, 2.0)
		TCGTheme.draw_text_centered(self, String(data.get("label", "+1")), c, 12, Color.WHITE, true, true)
	else:
		var badge_kind := kind
		if kind == "buff" or kind == "debuff" or kind == "special":
			var nm := String(data.get("name", ""))
			if nm == "Frozen" or nm == "Petrified":
				badge_kind = "freeze"
		TCGArt.draw_status_badge(self, rect, badge_kind, elem, _count)
		draw_arc(rect.get_center(), minf(size.x, size.y) * 0.5 - 1.0, 0.0, TAU, 24, TCGTheme.GOLD_L if _hovered else ring, 2.0 if _hovered else 1.6)
		if _count > 0:
			var pr := Rect2(size.x - 16.0, size.y - 14.0, 16.0, 14.0)
			TCGTheme.draw_rounded_box(self, pr, Color(0.06, 0.09, 0.14, 0.96), ring, 5, 1)
			TCGTheme.draw_text_centered(self, str(_count), pr.get_center(), 10, Color.WHITE, true, false)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	modulate = prev_mod

	# Delayed 1-line compact label tag (not a card box) for icon identification
	if _show_tag and _hovered:
		var title := String(data.get("name", data.get("label", "")))
		if not title.is_empty():
			var tag_txt := "%s (%d)" % [title, _count] if _count > 0 else title
			var f := ThemeDB.fallback_font
			var tw: float = f.get_string_size(tag_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 16.0
			var tag_rect := Rect2((size.x - tw) * 0.5, -24.0, tw, 20.0)
			TCGTheme.draw_rounded_box(self, tag_rect, Color(0.06, 0.09, 0.14, 0.95), ring, 6, 1)
			TCGTheme.draw_text_centered(self, tag_txt, tag_rect.get_center(), 12, Color.WHITE, false, false)


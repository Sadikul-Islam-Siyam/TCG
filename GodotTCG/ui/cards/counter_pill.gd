class_name CounterPill
extends Control
## Phase 4 (T4.5): Reusable CounterPill for usages, durations, shields, and damage badges.
## Features a dark rounded pill base, crisp white text, tick pop (scale 1.5 -> 1.0),
## and green/red color flash on change.

var value: int = 0
var prefix: String = ""
var accent: Color = TCGTheme.GOLD_D
var _flash_color: Color = Color.TRANSPARENT
var _flash_alpha: float = 0.0
var _pop_scale: float = 1.0
var _tween: Tween = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(24, 18)


func setup(p_value: int, p_accent: Color = TCGTheme.GOLD_D, p_prefix: String = "") -> void:
	value = p_value
	accent = p_accent
	prefix = p_prefix
	visible = p_value >= 0
	queue_redraw()


func set_value(new_val: int, animate: bool = true) -> void:
	if new_val == value:
		return
	var diff: int = new_val - value
	value = new_val
	visible = value >= 0
	if animate and is_inside_tree():
		_flash_color = TCGTheme.GREEN if diff > 0 else TCGTheme.RED
		_flash_alpha = 0.85
		_pop_scale = 1.5
		if _tween != null and _tween.is_valid():
			_tween.kill()
		_tween = create_tween()
		_tween.set_parallel(true)
		_tween.tween_property(self, "_pop_scale", 1.0, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_tween.tween_property(self, "_flash_alpha", 0.0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_tween.tween_method(func(_x: float) -> void: queue_redraw(), 0.0, 1.0, 0.35)
	queue_redraw()


func _draw() -> void:
	if value < 0:
		return
	var c := size * 0.5
	if _pop_scale != 1.0:
		draw_set_transform(c * (1.0 - _pop_scale), 0.0, Vector2(_pop_scale, _pop_scale))
	var r := Rect2(Vector2.ZERO, size)
	var bdr := accent if _flash_alpha <= 0.05 else accent.lerp(_flash_color, _flash_alpha)
	var fill := Color(0.08, 0.11, 0.16, 0.94)
	if _flash_alpha > 0.05:
		fill = fill.lerp(_flash_color, _flash_alpha * 0.40)
	TCGTheme.draw_rounded_box(self, r, fill, bdr, 7, 1)
	var txt := "%s%d" % [prefix, value]
	TCGTheme.draw_text_centered(self, txt, size * 0.5, maxi(10, int(size.y * 0.68)), Color.WHITE, true, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

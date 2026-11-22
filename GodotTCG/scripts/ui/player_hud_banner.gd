class_name TCGPlayerHudBanner
extends Control
## Genshin-Style Player Status Nameplate Component.
## Features active character circular portrait medallion, clear "Now Acting / Now Waiting"
## indicator, illuminated turn diamond gem, and compact hand/dice counters.

var side: int = 0
var player_label: String = "You"
var active_char_name: String = ""
var active_element: String = "Pyro"
var is_acting: bool = false
var round_ended: bool = false
var show_dice_badge: bool = false
var dice_count: int = 0
var hand_count: int = 0
var goes_first_next: bool = false

var _pulse_t: float = 0.0
var _focus_t: float = 0.0


func _init() -> void:
	custom_minimum_size = Vector2(292, 70)
	size = Vector2(292, 70)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(
	p_side: int,
	p_label: String,
	p_char_name: String,
	p_element: String,
	p_acting: bool,
	p_ended: bool,
	p_show_dice: bool = false,
	p_dice_count: int = 0,
	p_hand_count: int = -1,
	p_goes_first_next: bool = false
) -> void:
	side = p_side
	player_label = p_label
	active_char_name = p_char_name
	active_element = p_element
	is_acting = p_acting
	round_ended = p_ended
	show_dice_badge = p_show_dice
	dice_count = p_dice_count
	hand_count = p_hand_count
	goes_first_next = p_goes_first_next
	if not is_inside_tree():
		_focus_t = 1.0 if p_acting else 0.0
	queue_redraw()


func _process(delta: float) -> void:
	var dirty := false
	if is_acting and not round_ended:
		_pulse_t += delta
		dirty = true
	var target_focus := 1.0 if (is_acting and not round_ended) else 0.0
	if absf(_focus_t - target_focus) > 0.008:
		_focus_t = lerpf(_focus_t, target_focus, 1.0 - exp(-10.0 * delta))
		dirty = true
	if dirty:
		queue_redraw()


func _draw() -> void:
	var active_bright: float = lerpf(0.72, 1.0, _focus_t)
	var pill := Rect2(4, 3, 282, 62)
	var border := TCGTheme.GOLD_L if is_acting else Color(TCGTheme.GOLD_D.r, TCGTheme.GOLD_D.g, TCGTheme.GOLD_D.b, 0.78)
	var bg := Color(0.06, 0.10, 0.16, lerpf(0.76, 0.92, _focus_t))

	# Subtle Genshin-style active turn outer shimmer
	if is_acting and not round_ended:
		var pulse := 0.5 + 0.5 * sin(_pulse_t * 3.0)
		TCGTheme.draw_rounded_box(
			self,
			pill.grow(3.0),
			Color(TCGTheme.GOLD.r, TCGTheme.GOLD.g, TCGTheme.GOLD.b, 0.07 + 0.05 * pulse),
			Color(TCGTheme.GOLD_L.r, TCGTheme.GOLD_L.g, TCGTheme.GOLD_L.b, 0.35 + 0.25 * pulse),
			28,
			1.5
		)

	TCGTheme.draw_rounded_box(
		self,
		pill,
		bg,
		border,
		28,
		2.2 if is_acting else 1.4,
		Vector2(0, 3),
		100
	)

	# Circular Avatar Medallion (character portrait crop or element crest)
	var av_c := Vector2(35, 34)
	var av_r: float = 24.0
	var el_col := TCGTheme.elem_color(active_element)
	var el_dark := TCGTheme.elem_dark(active_element)
	draw_circle(av_c + Vector2(0, 2), av_r, Color(0, 0, 0, 0.45))
	draw_circle(av_c, av_r, Color(el_dark.r, el_dark.g, el_dark.b, active_bright))

	var ch_tex := TCGArt.get_character_texture(active_char_name)
	if ch_tex != null:
		# Soft framed portrait inside circular medallion ring
		var pr := Rect2(av_c - Vector2(av_r - 4.0, av_r - 4.0), Vector2((av_r - 4.0) * 2.0, (av_r - 4.0) * 2.0))
		TCGArt.draw_texture_cover(self, ch_tex, pr, Color(active_bright, active_bright, active_bright, 1.0), 0.16)
		# Mask outer square corners with subtle bezel ring
		draw_arc(av_c, av_r - 1.5, 0.0, TAU, 32, Color(0.06, 0.10, 0.16, 0.95), 4.5)
	else:
		TCGArt.draw_elem_symbol(self, active_element, av_c, 14.0, Color(el_col.r, el_col.g, el_col.b, active_bright), false)

	draw_arc(av_c, av_r, 0.0, TAU, 32, TCGTheme.GOLD_L if is_acting else Color(el_col.r, el_col.g, el_col.b, 0.9), 2.4 if is_acting else 1.8)

	# Player + Active Character Name
	var title_txt := player_label if active_char_name.is_empty() or active_char_name == "None" else ("%s · %s" % [player_label, active_char_name])
	if title_txt.length() > 24:
		title_txt = title_txt.substr(0, 23) + "…"
	TCGTheme.draw_text_pos(
		self,
		title_txt,
		Vector2(66, 11),
		15,
		Color(TCGTheme.TEXT.r, TCGTheme.TEXT.g, TCGTheme.TEXT.b, active_bright),
		true,
		true
	)

	# Clean Genshin-style status subtitle ("Now Acting" / "Now Waiting..." / "Round Ended")
	var sub_txt := "Round Ended" if round_ended else ("Now Acting" if is_acting else "Now Waiting…")
	var sub_col := TCGTheme.DIM if round_ended else (TCGTheme.GOLD_L if is_acting else Color(0.68, 0.74, 0.82, 0.85))
	TCGTheme.draw_text_pos(self, sub_txt, Vector2(66, 36), 12, sub_col, is_acting, false)

	# Optional "FIRST NEXT ROUND" tag
	if goes_first_next:
		var gp := Rect2(16, -15, 148, 19)
		TCGTheme.draw_rounded_box(self, gp, Color("#17314A"), TCGTheme.TEAL, 9, 1.0)
		TCGTheme.draw_text_centered(self, "FIRST NEXT ROUND", gp.get_center(), 10, TCGTheme.GOLD_L, true, false)

class_name TCGPlayerHudBanner
extends Control
## T2.4: Left Info Column / Player Status Nameplate Component.
## Active nameplate is brighter with an illuminated gold rim and subtle glow;
## waiting nameplate dims smoothly so turn ownership is unmistakable at a glance.

var side: int = 0
var player_label: String = "You"
var active_char_name: String = ""
var active_element: String = "Cryo"
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
	_focus_t = 1.0 if p_acting else 0.0
	queue_redraw()


func _process(delta: float) -> void:
	var dirty := false
	var target_focus := 1.0 if (is_acting and not round_ended) else 0.0
	if absf(_focus_t - target_focus) > 0.01:
		_focus_t = lerpf(_focus_t, target_focus, minf(1.0, delta * 9.0))
		dirty = true
	if dirty:
		queue_redraw()


func _draw() -> void:
	var active_bright: float = lerpf(0.62, 1.0, _focus_t)
	var pill := Rect2(0, 0, 286, 64)
	var border := TCGTheme.GOLD_L if is_acting else Color(TCGTheme.GOLD_D.r, TCGTheme.GOLD_D.g, TCGTheme.GOLD_D.b, active_bright)
	var bg := Color(0.08, 0.13, 0.21, lerpf(0.68, 0.94, _focus_t))

	if is_acting and not round_ended:
		var pulse := 0.5 + 0.5 * sin(_pulse_t * 3.8)
		draw_rect(
			pill.grow(3.0 + pulse * 1.5),
			Color(TCGTheme.GOLD.r, TCGTheme.GOLD.g, TCGTheme.GOLD.b, 0.12 + 0.08 * pulse),
			false,
			2.0
		)

	TCGTheme.draw_rounded_box(
		self,
		pill,
		bg,
		border,
		24,
		2.2 if is_acting else 1.2,
		Vector2(0, 3),
		90
	)

	# Avatar medallion with element color ring
	var av_c := Vector2(32, 32)
	var el_col := TCGTheme.elem_color(active_element)
	var el_dark := TCGTheme.elem_dark(active_element)
	draw_circle(av_c, 22.0, Color(el_dark.r, el_dark.g, el_dark.b, active_bright))
	draw_arc(av_c, 22.0, 0.0, TAU, 24, Color(el_col.r, el_col.g, el_col.b, active_bright), 2.4 if is_acting else 1.6)
	TCGArt.draw_elem_symbol(self, active_element, av_c, 13.0, Color(el_col.r, el_col.g, el_col.b, active_bright), false)

	# Player + Active Character Name
	var title_txt := "%s · %s" % [player_label, active_char_name]
	if title_txt.length() > 21:
		title_txt = title_txt.substr(0, 20) + "…"
	TCGTheme.draw_text_pos(
		self,
		title_txt,
		Vector2(62, 8),
		16,
		Color(TCGTheme.TEXT.r, TCGTheme.TEXT.g, TCGTheme.TEXT.b, active_bright),
		true,
		true
	)

	# Compact turn indicator / ended pill (decluttered)
	if round_ended:
		var chip := Rect2(62, 34, 68, 20)
		TCGTheme.draw_rounded_box(self, chip, Color(0.05, 0.08, 0.14, 0.85), Color(TCGTheme.DIM.r, TCGTheme.DIM.g, TCGTheme.DIM.b, 0.55), 9, 1.0)
		TCGTheme.draw_text_pos(self, "Ended", Vector2(72, 36), 12, TCGTheme.DIM, true, false)
	elif is_acting:
		draw_circle(Vector2(69, 43), 4.5, TCGTheme.GREEN)

	# Compact Hand / Dice counters on the right side of the pill
	var rx: float = pill.end.x - 12.0
	if show_dice_badge:
		var dp := Rect2(rx - 56.0, 32, 52, 22)
		TCGTheme.draw_rounded_box(self, dp, Color(0.06, 0.10, 0.17, 0.90), Color(TCGTheme.GOLD.r, TCGTheme.GOLD.g, TCGTheme.GOLD.b, 0.65), 10, 1.0)
		TCGArt.draw_elem_symbol(self, "Omni", Vector2(dp.position.x + 14, dp.get_center().y), 7.5)
		TCGTheme.draw_text_pos(self, str(dice_count), Vector2(dp.position.x + 26, dp.position.y + 2), 14, TCGTheme.GOLD_L, true, false)
		rx -= 58.0

	if hand_count >= 0:
		var hp := Rect2(rx - 48.0, 32, 44, 22)
		TCGTheme.draw_rounded_box(self, hp, Color(0.06, 0.10, 0.17, 0.88), TCGTheme.GOLD_D, 9, 1.0)
		draw_rect(Rect2(hp.position.x + 9, hp.position.y + 5, 8, 12), Color("#D9C598"), false, 1.4)
		TCGTheme.draw_text_pos(self, str(hand_count), Vector2(hp.position.x + 22, hp.position.y + 2), 13, TCGTheme.TEXT, true, false)

	# Optional "1st Next" badge if player ended round first
	if goes_first_next:
		var gp := Rect2(14, -16, 152, 20)
		TCGTheme.draw_rounded_box(self, gp, Color("#17314A"), TCGTheme.TEAL, 9, 1.0)
		TCGTheme.draw_text_centered(self, "FIRST NEXT ROUND", gp.get_center(), 11, TCGTheme.TEXT, true, false)

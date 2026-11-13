class_name TCGPlayerHudBanner
extends Control
## Stage 5: Reusable Player Status Banner Component
## Direct port of PythonTCG/ui/match.py `_draw_side_hud` player/opponent banner.
## Displays avatar medallion, player label, active character name, turn state
## ("Now Acting" / "Now Waiting" / "Round Ended"), active element crest, and optional opponent dice badge.

var side: int = 0
var player_label: String = "You"
var active_char_name: String = "Kaeya"
var active_element: String = "Cryo"
var is_acting: bool = false
var round_ended: bool = false
var show_dice_badge: bool = false
var dice_count: int = 0


func _init() -> void:
	custom_minimum_size = Vector2(360, 44)
	size = Vector2(360, 44)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(
	p_side: int,
	p_label: String,
	p_char_name: String,
	p_element: String,
	p_acting: bool,
	p_ended: bool,
	p_show_dice: bool = false,
	p_dice_count: int = 0
) -> void:
	side = p_side
	player_label = p_label
	active_char_name = p_char_name
	active_element = p_element
	is_acting = p_acting
	round_ended = p_ended
	show_dice_badge = p_show_dice
	dice_count = p_dice_count
	queue_redraw()


func _draw() -> void:
	var pill := Rect2(0, 0, 236, 44)
	var border := TCGTheme.GOLD_L if is_acting else TCGTheme.GOLD
	TCGTheme.draw_rounded_box(
		self,
		pill,
		Color(0.08, 0.13, 0.2, 0.88),
		border,
		22,
		2,
		Vector2(0, 3),
		90
	)

	# Avatar circle
	var av_c := Vector2(24, 22)
	draw_circle(av_c, 18.0, TCGTheme.elem_dark(active_element))
	draw_arc(av_c, 18.0, 0.0, TAU, 24, TCGTheme.elem_color(active_element), 2.0)
	TCGArt.draw_elem_symbol(self, active_element, av_c, 10.0, TCGTheme.elem_color(active_element), false)

	# Player name + Active Character (truncate if needed so it never overlaps the right element gem)
	var title_txt := "%s · %s" % [player_label, active_char_name]
	if title_txt.length() > 21:
		title_txt = title_txt.substr(0, 20) + "…"
	TCGTheme.draw_text_pos(self, title_txt, Vector2(48, 5), 13, TCGTheme.TEXT, true, true)

	# Turn status subtitle
	var status_txt := "Round Ended" if round_ended else ("Now Acting" if is_acting else "Now Waiting")
	var status_col := TCGTheme.DIM if round_ended else (TCGTheme.GREEN if is_acting else TCGTheme.GOLD)
	TCGTheme.draw_text_pos(self, status_txt, Vector2(50, 23), 11, status_col, true, true)

	# Element crest on right of pill
	TCGArt.draw_elem_symbol(self, active_element, Vector2(pill.end.x - 20, 22), 9.0)

	# Opponent dice counter pill when applicable
	if show_dice_badge:
		var dp := Rect2(246, 6, 104, 32)
		TCGTheme.draw_rounded_box(
			self,
			dp,
			Color(0.08, 0.13, 0.2, 0.86),
			TCGTheme.GOLD,
			16,
			1
		)
		TCGArt.draw_elem_symbol(self, "Omni", Vector2(dp.position.x + 16, dp.get_center().y), 8.0)
		TCGTheme.draw_text_pos(self, str(dice_count), Vector2(dp.position.x + 30, dp.position.y + 6), 14, TCGTheme.GOLD_L, true, true)
		TCGTheme.draw_text_pos(self, "DICE", Vector2(dp.position.x + 52, dp.position.y + 9), 10, TCGTheme.DIM, true, false)

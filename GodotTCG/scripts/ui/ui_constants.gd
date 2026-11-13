class_name UIConstants
extends Resource
## Phase 0 (T0.1 / T0.3 / T14.1 / T14.5):
## Single source of truth for base 1920x1080 layout metrics, safe-area computation,
## typography scale, z-order table, and animation durations.

const BASE_W: float = 1920.0
const BASE_H: float = 1080.0
const SAFE_PAD_MIN: float = 14.0

# Typography scale (T0.3: 5 constants)
const FONT_TITLE: int = 52
const FONT_HEADER: int = 28
const FONT_BODY: int = 18
const FONT_CAPTION: int = 15
const FONT_COUNTER: int = 17

# Z-Order table (T14.1: board < characters < statuses < hand < preview < banners < panel < modal)
const Z_BOARD: int = 0
const Z_CHARACTERS: int = 10
const Z_STATUSES: int = 20
const Z_HAND: int = 30
const Z_SKILL_BAR: int = 35
const Z_PREVIEW: int = 50
const Z_BANNERS: int = 70
const Z_PANEL: int = 90
const Z_MODAL: int = 110

# Tunable animation durations in seconds (T14.5)
@export var dur_active_offset: float = 0.25
@export var dur_status_reflow: float = 0.15
@export var dur_hand_reflow: float = 0.25
@export var dur_hand_hover: float = 0.12
@export var dur_card_shake: float = 0.20
@export var dur_card_play_fly: float = 0.30
@export var dur_card_play_hold: float = 0.72
@export var dur_card_opponent_hold: float = 0.95
@export var dur_draw_stagger: float = 0.10
@export var dur_dice_drawer_slide: float = 0.25
@export var dur_dice_roll: float = 0.70
@export var dur_dice_stagger: float = 0.05
@export var dur_die_flip: float = 0.25
@export var dur_attack_lunge_in: float = 0.15
@export var dur_attack_lunge_back: float = 0.20
@export var dur_hit_shake: float = 0.20
@export var dur_hit_stop: float = 0.055
@export var dur_reaction_banner: float = 0.85
@export var dur_switch_swap: float = 0.30
@export var dur_turn_banner: float = 1.00
@export var dur_panel_backdrop: float = 0.15
@export var dur_panel_slide: float = 0.20
@export var dur_tooltip_delay: float = 0.40
@export var dur_toast: float = 1.50
@export var debounce_click: float = 0.10
@export var long_press_inspect: float = 0.45
@export var drag_threshold_px: float = 8.0

static var _shared: UIConstants = null


static func get_shared() -> UIConstants:
	if _shared == null:
		_shared = UIConstants.new()
	return _shared


static func get_safe_rect(container_size: Vector2 = Vector2(BASE_W, BASE_H)) -> Rect2:
	## Returns a safe play area Rect2 respecting mobile notches / DisplayServer safe area
	## mapped smoothly into the 1920x1080 logical coordinate space (`T0.1`).
	var w: float = maxf(container_size.x, BASE_W)
	var h: float = maxf(container_size.y, BASE_H)
	var pad_l: float = SAFE_PAD_MIN
	var pad_r: float = SAFE_PAD_MIN
	var pad_t: float = SAFE_PAD_MIN
	var pad_b: float = SAFE_PAD_MIN

	if DisplayServer.get_name() != "headless":
		var win_sz: Vector2i = DisplayServer.window_get_size()
		var safe: Rect2i = DisplayServer.get_display_safe_area()
		if win_sz.x > 0 and win_sz.y > 0 and safe.size.x > 0 and safe.size.y > 0:
			var sx: float = w / float(win_sz.x)
			var sy: float = h / float(win_sz.y)
			pad_l = maxf(pad_l, float(safe.position.x) * sx)
			pad_t = maxf(pad_t, float(safe.position.y) * sy)
			pad_r = maxf(pad_r, float(maxi(0, win_sz.x - safe.end.x)) * sx)
			pad_b = maxf(pad_b, float(maxi(0, win_sz.y - safe.end.y)) * sy)

	return Rect2(pad_l, pad_t, maxf(640.0, w - pad_l - pad_r), maxf(480.0, h - pad_t - pad_b))


static func map_from_720(v: Vector2) -> Vector2:
	return v * 1.5


static func scale_f(v: float) -> float:
	return v * 1.5


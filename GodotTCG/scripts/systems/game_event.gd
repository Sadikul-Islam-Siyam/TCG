class_name GameEvent
extends RefCounted
## Phase 1 (T1.1): Pure-data event contract emitted by rules/lifecycle logic.
## Never references SceneTree nodes; carries complete before/after snapshots
## so AnimationQueue handlers never need to mutate or race live logic state.

enum Type {
	GAME_STARTED,
	HAND_SWAP_REQUESTED,
	ROUND_STARTED,
	DICE_ROLLED,
	DICE_REROLLED,
	TURN_CHANGED,
	CARD_DRAWN,
	CARD_PLAYED,
	CARD_DISCARDED,
	DIE_TUNED,
	DICE_SPENT,
	SKILL_USED,
	DAMAGE_DEALT,
	HEAL_APPLIED,
	REACTION_TRIGGERED,
	ELEMENT_ATTACHED,
	ELEMENT_REMOVED,
	SHIELD_CHANGED,
	STATUS_ADDED,
	STATUS_CHANGED,
	STATUS_REMOVED,
	SUMMON_ADDED,
	SUMMON_TRIGGERED,
	SUMMON_REMOVED,
	SUPPORT_ADDED,
	SUPPORT_REMOVED,
	ENERGY_CHANGED,
	CHARACTER_SWITCHED,
	CHARACTER_DEFEATED,
	FORCED_SWITCH_REQUESTED,
	ROUND_ENDED,
	GAME_OVER,
	PHASE_CHANGED,
	PARALLEL_GROUP,
}

var type: int = Type.TURN_CHANGED
var group_events: Array = []
var player: int = -1
var source_player: int = -1
var char_index: int = -1
var source_char: int = -1
var name: String = ""
var element: String = ""
var kind: String = ""
var amount: int = 0
var before: Variant = null
var after: Variant = null
var meta: Dictionary = {}


func _init(p_type: int = Type.TURN_CHANGED, p_meta: Dictionary = {}) -> void:
	type = p_type
	meta = p_meta


static func make(
	p_type: int,
	p_player: int = -1,
	p_char: int = -1,
	p_name: String = "",
	p_element: String = "",
	p_amount: int = 0,
	p_before: Variant = null,
	p_after: Variant = null,
	p_kind: String = "",
	p_source_player: int = -1,
	p_source_char: int = -1,
	p_meta: Dictionary = {}
) -> GameEvent:
	var ev := GameEvent.new(p_type, p_meta)
	ev.player = p_player
	ev.char_index = p_char
	ev.name = p_name
	ev.element = p_element
	ev.amount = p_amount
	ev.before = p_before
	ev.after = p_after
	ev.kind = p_kind
	ev.source_player = p_source_player
	ev.source_char = p_source_char
	return ev


static func make_group(events: Array) -> GameEvent:
	var ev := GameEvent.new(Type.PARALLEL_GROUP)
	ev.group_events = events.duplicate()
	return ev


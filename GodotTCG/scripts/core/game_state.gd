class_name TCGGameState
extends RefCounted
## GameState & ActionData
## Translates Python `engine/core.py:Action` and `engine/model.py:GameState`.
## Designed for deterministic execution and fast `.clone()` during AI search.


class ActionData extends RefCounted:
	## Represents an atomic player/AI action (`engine/core.py:Action`).
	## Types: "mulligan", "choose_active", "confirm_roll", "reroll",
	##        "skill", "switch", "card", "tune", "end_round"
	var type: String
	var player: int
	var index: int = -1
	var target: int = -1
	var dice: PackedInt32Array = PackedInt32Array()
	var ids: PackedInt32Array = PackedInt32Array()

	func _init(
		p_type: String,
		p_player: int,
		p_index: int = -1,
		p_target: int = -1,
		p_dice: Array = [],
		p_ids: Array = []
	) -> void:
		type = p_type
		player = p_player
		index = p_index
		target = p_target
		dice = PackedInt32Array(p_dice)
		ids = PackedInt32Array(p_ids)

	func with_dice(new_dice: Array) -> ActionData:
		return ActionData.new(type, player, index, target, new_dice, Array(ids))

	func with_index(new_index: int) -> ActionData:
		return ActionData.new(type, player, new_index, target, Array(dice), Array(ids))

	func key() -> String:
		## Canonical key for dictionary/set lookups (used in MCTS & Alpha-Beta shortlisting).
		return "%s|%d|%d|%d|%s|%s" % [
			type,
			player,
			index,
			target,
			str(Array(dice)),
			str(Array(ids)),
		]

	func equals(other: ActionData) -> bool:
		if other == null:
			return false
		return key() == other.key()

	func _to_string() -> String:
		return "Action(%s, P%d, idx=%d, tgt=%d, dice=%s, ids=%s)" % [
			type, player, index, target, str(Array(dice)), str(Array(ids))
		]


# ------------------------------------------------------------------------------
# GameState fields (aligned with engine/model.py:GameState)
# ------------------------------------------------------------------------------
var players: Array[TCGPlayerSystem.PlayerState] = []
var rng: RandomNumberGenerator

var phase: String = "setup"          # "setup" | "roll" | "action" | "end" | "over"
var round_number: int = 1
var current: int = 0
var first_player: int = 0
var first_ender: int = -1            # -1 corresponds to Python's `None`
var pending: Array[int] = []         # Players who must immediately choose a new active character
var winner: int = -2                 # -2 = None (ongoing), -1 = Draw, 0 = Player 0, 1 = Player 1

var log: Array[String] = []
var events: Array[Dictionary] = []   # Structured events for the UI to animate: {"kind": String, ...}


func _init(p_rng: RandomNumberGenerator = null) -> void:
	if p_rng != null:
		rng = p_rng
	else:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	players = []
	phase = "setup"
	round_number = 1
	current = 0
	first_player = 0
	first_ender = -1
	pending = []
	winner = -2
	log = []
	events = []


func is_game_over() -> bool:
	return winner != -2 or phase == "over"


func add_event(kind: String, info: Dictionary = {}) -> void:
	var ev := info.duplicate()
	ev["kind"] = kind
	events.append(ev)


func add_log(entry: String) -> void:
	log.append(entry)


func clone(keep_log: bool = false, share_rng: bool = false) -> TCGGameState:
	## Fast deep copy of the entire game state for AI search (`engine/model.py:GameState.clone`).
	var g := TCGGameState.new()
	g.players = []
	for p in players:
		g.players.append(p.clone())

	if share_rng:
		g.rng = rng
	else:
		var copied_rng := RandomNumberGenerator.new()
		copied_rng.seed = rng.seed
		copied_rng.state = rng.state
		g.rng = copied_rng

	g.phase = phase
	g.round_number = round_number
	g.current = current
	g.first_player = first_player
	g.first_ender = first_ender
	g.pending = pending.duplicate()
	g.winner = winner
	if keep_log:
		g.log = log.duplicate()
	else:
		g.log.clear()
	g.events.clear()
	return g


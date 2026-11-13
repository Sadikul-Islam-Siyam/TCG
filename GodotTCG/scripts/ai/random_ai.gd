class_name TCGRandomAI
extends RefCounted
## RandomAI
## Exact port of Python `ai/random_ai.py`: weighted random over legal actions.
## Weights: {"skill": 6, "card": 3, "switch": 1, "tune": 1, "end_round": 1},
## with a 2x weight multiplier when `a.type == "skill" and a.index == 2` (Elemental Burst).

const WEIGHTS: Dictionary = {
	"skill": 6.0,
	"card": 3.0,
	"switch": 1.0,
	"tune": 1.0,
	"end_round": 1.0,
}

var rng: RandomNumberGenerator


func _init(seed_val: int = -1) -> void:
	rng = RandomNumberGenerator.new()
	if seed_val >= 0:
		rng.seed = seed_val
	else:
		rng.randomize()


func choose(state: TCGGameState) -> TCGGameState.ActionData:
	var acts := TCGRulesEngine.legal_actions(state)
	if acts.is_empty():
		return null
	if acts.size() == 1:
		return acts[0]

	var weights: Array[float] = []
	var total_w: float = 0.0
	for a in acts:
		var base_w: float = float(WEIGHTS.get(a.type, 1.0))
		var mult: float = 2.0 if (a.type == "skill" and a.index == 2) else 1.0
		var w: float = base_w * mult
		weights.append(w)
		total_w += w

	var r: float = rng.randf() * total_w
	var accum: float = 0.0
	for i in range(acts.size()):
		accum += weights[i]
		if r <= accum:
			return acts[i]
	return acts[acts.size() - 1]


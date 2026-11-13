class_name TCGFuzzy
extends RefCounted
## Fuzzy Logic Style Profiler
## Exact port of Python `genius_tcg/ai/fuzzy.py`.
## Turns exact game numbers into fuzzy terms and fires Sugeno rules that set
## the AI's playing style (`aggression`, `defence`, `burst`, `tempo`, `cards`)
## and derived evaluation weights (`hp`, `energy`, `board`).


static func trap(x: float, a: float, b: float, c: float, d: float) -> float:
	## Trapezoid membership: 0 below a, rises to 1 at b, stays 1 until c, falls to 0 at d.
	if x <= a or x >= d:
		return 1.0 if (b <= x and x <= c) else 0.0
	if x < b:
		return (x - a) / (b - a)
	if x <= c:
		return 1.0
	return (d - x) / (d - c)


static func low(x: float) -> float:
	return trap(x, -1.0, -1.0, 0.25, 0.55)


static func med(x: float) -> float:
	return trap(x, 0.25, 0.5, 0.5, 0.75)


static func high(x: float) -> float:
	return trap(x, 0.45, 0.75, 2.0, 2.0)


static func _ratio(p: TCGPlayerSystem.PlayerState) -> float:
	var tot: int = 0
	var cur: int = 0
	for c in p.characters:
		var d: CardDataSystem.CharData = c.get_defn()
		if d != null:
			tot += d.hp
		if not c.defeated:
			cur += c.hp
	return float(cur) / float(tot) if tot > 0 else 0.0


static func _energy(p: TCGPlayerSystem.PlayerState) -> float:
	var ch: TCGPlayerSystem.CharacterInstance = p.get_active_char()
	if ch == null:
		return 0.0
	var d: CardDataSystem.CharData = ch.get_defn()
	if d == null or d.max_energy <= 0:
		return 0.0
	return float(ch.energy) / float(d.max_energy)


static func inputs(s: TCGGameState, me: int) -> Dictionary:
	var p: TCGPlayerSystem.PlayerState = s.players[me]
	var q: TCGPlayerSystem.PlayerState = s.players[1 - me]
	return {
		"hp_me": _ratio(p),
		"hp_foe": _ratio(q),
		"energy": _energy(p),
		"foe_energy": _energy(q),
		"dice": minf(float(p.dice.size()) / 8.0, 1.5),
		"hand": float(p.hand.size()) / 10.0,
	}


static func _defuzz(rules: Array, default_val: float) -> float:
	## Weighted average of rule outputs (Sugeno style). `rules = [[firing_strength, output], ...]`.
	var tot: float = 0.0
	var num: float = 0.0
	for r in rules:
		var w: float = float(r[0])
		var o: float = float(r[1])
		tot += w
		num += w * o
	return num / tot if tot > 1e-9 else default_val


static func profile(s: TCGGameState, me: int) -> Dictionary:
	var x: Dictionary = inputs(s, me)
	var hp_me: float = float(x["hp_me"])
	var hp_foe: float = float(x["hp_foe"])
	var energy: float = float(x["energy"])
	var foe_energy: float = float(x["foe_energy"])
	var dice_v: float = float(x["dice"])
	var hand_v: float = float(x["hand"])

	var aggression: float = _defuzz([
		[minf(high(hp_me), low(hp_foe)), 0.95],   # healthy and foe nearly dead: attack
		[minf(med(hp_me), med(hp_foe)), 0.55],
		[minf(low(hp_me), high(hp_foe)), 0.15],   # hurt and foe healthy: be careful
		[minf(high(hp_me), high(hp_foe)), 0.7],
		[minf(low(hp_me), low(hp_foe)), 0.5],
	], 0.5)

	var defence: float = _defuzz([
		[low(hp_me), 0.9],
		[med(hp_me), 0.5],
		[high(hp_me), 0.15],
		[high(foe_energy), 0.8],
	], 0.4)

	var burst: float = _defuzz([
		[high(energy), 0.95],
		[med(energy), 0.5],
		[low(energy), 0.15],
	], 0.5)

	var tempo: float = _defuzz([
		[low(dice_v), 0.85],
		[med(dice_v), 0.5],
		[high(dice_v), 0.1],
	], 0.5)

	var cards: float = _defuzz([
		[high(hand_v), 0.85],
		[med(hand_v), 0.55],
		[low(hand_v), 0.25],
	], 0.5)

	return {
		"aggression": aggression,
		"defence": defence,
		"burst": burst,
		"tempo": tempo,
		"cards": cards,
		# evaluation weights derived from the style
		"hp": 0.8 + 0.6 * defence,
		"energy": 0.8 + 0.6 * burst,
		"board": 1.0,
	}


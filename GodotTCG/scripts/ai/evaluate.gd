class_name TCGEvaluate
extends RefCounted
## Heuristic State Evaluation
## Exact port of Python `genius_tcg/ai/evaluate.py`.
## Zero-sum relative to `me`: `evaluate(s, 0) == -evaluate(s, 1)`.

const DEFAULT: Dictionary = {
	"hp": 1.0,
	"energy": 1.0,
	"board": 1.0,
	"defence": 0.5,
}


static func _side(
	p: TCGPlayerSystem.PlayerState,
	q: TCGPlayerSystem.PlayerState,
	w: Dictionary,
	action_phase: bool
) -> float:
	var v: float = 0.0
	var foe_els: Dictionary = {}
	for c in q.characters:
		if not c.defeated:
			var cd: CardDataSystem.CharData = c.get_defn()
			if cd != null:
				foe_els[cd.element] = true

	var w_hp: float = float(w.get("hp", 1.0))
	var w_energy: float = float(w.get("energy", 1.0))
	var w_board: float = float(w.get("board", 1.0))
	var w_defence: float = float(w.get("defence", 0.5))

	for i in range(p.characters.size()):
		var c: TCGPlayerSystem.CharacterInstance = p.characters[i]
		if c.defeated:
			continue
		var d: CardDataSystem.CharData = c.get_defn()
		if d == null:
			continue
		v += 0.45 + 0.7 * w_hp * (float(c.hp) / float(d.hp))
		v += w_energy * (float(c.energy) / float(d.max_energy)) * (0.25 if i == p.active else 0.12)
		v += 0.07 * float(c.equipment.size())
		if not c.aura.is_empty():
			var can_react: bool = false
			for e in foe_els.keys():
				var rx: Array = TCGRulesEngine._lookup_reaction(c.aura, str(e))
				if not str(rx[0]).is_empty():
					can_react = true
					break
			if can_react:
				v -= 0.08 * (0.5 + w_defence)
		if TCGRulesEngine.stunned(c):
			v -= 0.22

	for u in p.summons:
		var sd: CardDataSystem.SummonData = CardDataSystem.get_summon_def(u.name)
		if sd != null:
			v += 0.05 * float(sd.damage) * float(mini(u.usages, 3)) * w_board

	for st in p.combat:
		var u_val: int = maxi(0, st.usages)
		v += 0.06 * (float(st.shield) + 0.5 * float(u_val))

	v += 0.07 * float(p.supports.size()) + 0.02 * float(p.hand.size())
	if action_phase:
		v += 0.012 * float(p.dice.size())
	return v


static func evaluate(s: TCGGameState, me: int, w: Dictionary = {}) -> float:
	if s.winner != -2:
		if s.winner == -1:
			return 0.0
		return 6.0 if s.winner == me else -6.0
	var weights: Dictionary = DEFAULT if w.is_empty() else w
	var ap: bool = (s.phase == "action")
	return _side(s.players[me], s.players[1 - me], weights, ap) - _side(s.players[1 - me], s.players[me], weights, ap)


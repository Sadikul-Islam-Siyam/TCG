class_name TCGEffectContext
extends RefCounted
## EffectContext (`Ctx`)
## Exact port of Python `engine/rules.py:Ctx`.
## Used by character skills, action cards, supports, and status hooks to modify `TCGGameState`.

var s: TCGGameState
var pi: int
var kind: String = ""   # "" corresponds to Python `None`; otherwise "normal" | "skill" | "burst"


func _init(p_state: TCGGameState, p_pi: int, p_kind: String = "") -> void:
	s = p_state
	pi = p_pi
	kind = p_kind


func me() -> TCGPlayerSystem.PlayerState:
	return s.players[pi]


func foe() -> TCGPlayerSystem.PlayerState:
	return s.players[1 - pi]


func damage(n: int, dtype: String) -> void:
	var t: int = TCGRulesEngine.foe_target(s, pi)
	if t >= 0:
		var src: String = "skill" if not kind.is_empty() else "effect"
		TCGRulesEngine.deal_damage(s, pi, 1 - pi, t, n, dtype, src, kind)


func piercing_others(n: int) -> void:
	var f := foe()
	for i in range(f.characters.size()):
		var c := f.characters[i]
		if i != f.active and not c.defeated:
			TCGRulesEngine.deal_damage(s, pi, 1 - pi, i, n, CardDataSystem.PIERCING, "effect", "")


func heal(n: int, idx: int = -1) -> void:
	var p := me()
	var target_idx: int = p.active if idx < 0 else idx
	if target_idx < 0 or target_idx >= p.characters.size():
		return
	var c := p.characters[target_idx]
	if not c.defeated:
		var old_hp: int = c.hp
		var defn: CardDataSystem.CharData = c.get_defn()
		var max_hp: int = defn.hp if defn != null else 10
		c.hp = mini(max_hp, c.hp + n)
		s.add_event("heal", {"player": pi, "char": target_idx, "amount": n})
		s.add_game_event(GameEvent.make(
			GameEvent.Type.HEAL_APPLIED,
			pi,
			target_idx,
			c.name,
			"",
			n,
			old_hp,
			c.hp
		))


func summon(summon_name: String) -> void:
	var p := me()
	var d: CardDataSystem.SummonData = CardDataSystem.get_summon_def(summon_name)
	if d == null:
		return
	for u in p.summons:
		if u.name == summon_name:
			var old_u := u.usages
			u.usages = d.usages
			s.add_game_event(GameEvent.make(GameEvent.Type.STATUS_CHANGED, pi, -1, summon_name, d.element, d.usages, old_u, u.usages, "summon"))
			return
	if p.summons.size() >= CardDataSystem.MAX_SUMMONS:
		var evicted := p.summons[0]
		p.summons.pop_front()
		s.add_game_event(GameEvent.make(GameEvent.Type.SUMMON_REMOVED, pi, -1, evicted.name))
	p.summons.append(TCGPlayerSystem.UnitInstance.new(summon_name, d.usages))
	s.add_event("summon", {"player": pi, "name": summon_name})
	s.add_game_event(GameEvent.make(GameEvent.Type.SUMMON_ADDED, pi, -1, summon_name, d.element, d.damage, 0, d.usages))


func combat_status(status_name: String) -> void:
	var st := TCGRulesEngine.add_status(me().combat, status_name)
	if st != null:
		s.add_game_event(GameEvent.make(GameEvent.Type.STATUS_ADDED, pi, -1, status_name, "", st.usages, null, st.usages, "combat"))


func char_status(status_name: String, idx: int = -1) -> void:
	var p := me()
	var target_idx: int = p.active if idx < 0 else idx
	if target_idx >= 0 and target_idx < p.characters.size() and not p.characters[target_idx].defeated:
		var st := TCGRulesEngine.add_status(p.characters[target_idx].statuses, status_name)
		if st != null:
			s.add_game_event(GameEvent.make(GameEvent.Type.STATUS_ADDED, pi, target_idx, status_name, "", st.usages, null, st.usages, "char"))


func foe_char_status(status_name: String) -> void:
	var t: int = TCGRulesEngine.foe_target(s, pi)
	if t >= 0:
		var st := TCGRulesEngine.add_status(foe().characters[t].statuses, status_name)
		if st != null:
			s.add_game_event(GameEvent.make(GameEvent.Type.STATUS_ADDED, 1 - pi, t, status_name, "", st.usages, null, st.usages, "char"))


func force_switch_foe() -> void:
	TCGRulesEngine.force_switch(s, 1 - pi)


func draw(n: int) -> void:
	TCGRoundManager.draw_cards(s, pi, n)


func gain_energy(n: int) -> void:
	var p := me()
	var ch := p.get_active_char()
	if ch != null:
		var old_en := ch.energy
		var defn: CardDataSystem.CharData = ch.get_defn()
		var max_en: int = defn.max_energy if defn != null else 3
		ch.energy = mini(max_en, ch.energy + n)
		if ch.energy != old_en:
			s.add_game_event(GameEvent.make(GameEvent.Type.ENERGY_CHANGED, pi, p.active, ch.name, "", ch.energy - old_en, old_en, ch.energy, "", -1, -1, {"max": max_en}))


func heal_most_injured(n: int) -> void:
	var p := me()
	var best_missing: int = -1
	var best_idx: int = -1
	for i in range(p.characters.size()):
		var c := p.characters[i]
		var defn: CardDataSystem.CharData = c.get_defn()
		var max_hp: int = defn.hp if defn != null else 10
		if not c.defeated and c.hp < max_hp:
			var missing: int = max_hp - c.hp
			# Python `max(hurt)` on `(c.defn.hp - c.hp, i)` picks highest missing HP, breaking ties by highest index `i`.
			if missing > best_missing or (missing == best_missing and i > best_idx):
				best_missing = missing
				best_idx = i
	if best_idx >= 0:
		heal(n, best_idx)


func gain_dice(n: int, die: String) -> void:
	var p := me()
	for _i in range(n):
		if p.dice.size() < CardDataSystem.MAX_DICE:
			p.dice.append(die)


func execute_steps(steps: Array[CardDataSystem.EffectStepData], target_idx: int = -1) -> void:
	## Executes a sequence of declarative `EffectStepData` records.
	for st in steps:
		match st.op:
			"damage":
				damage(st.amount, st.dtype)
			"piercing_others":
				piercing_others(st.amount)
			"summon":
				summon(st.target_name)
			"combat_status":
				combat_status(st.target_name)
			"char_status":
				char_status(st.target_name)
			"foe_char_status":
				foe_char_status(st.target_name)
			"force_switch_foe":
				force_switch_foe()
			"heal":
				heal(st.amount, target_idx if st.use_target else -1)
			"heal_most_injured":
				heal_most_injured(st.amount)
			"draw":
				draw(st.amount)
			"gain_energy":
				gain_energy(st.amount)
			"gain_dice":
				gain_dice(st.amount, st.dtype)


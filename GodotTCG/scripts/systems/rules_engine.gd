class_name TCGRulesEngine
extends RefCounted
## RulesEngine
## Authoritative port of Python `engine/rules.py` and `content/statuses.py` callbacks.
## Public API matches Python:
##   new_game(chars0, deck0, chars1, deck1, seed_val) -> TCGGameState
##   actor(state)                                     -> int (-1 if None)
##   legal_actions(state)                             -> Array[TCGGameState.ActionData]
##   apply_action(state, action)                      -> TCGGameState (sets last_error on illegal action)

static var last_error: String = ""

const _PHASE_OF: Dictionary = {
	"mulligan": "setup",
	"reroll": "roll",
	"confirm_roll": "roll",
	"skill": "action",
	"switch": "action",
	"card": "action",
	"tune": "action",
	"end_round": "action",
}


# ------------------------------------------------------------------------------
# Reaction Table Lookup (`engine/rules.py:REACTIONS`)
# ------------------------------------------------------------------------------
static func _lookup_reaction(el_a: String, el_b: String) -> Array:
	## Returns `[reaction_name, bonus_damage]` for a pair of aura elements, or `["", 0]`.
	var pair: Array[String] = [el_a, el_b]
	pair.sort()
	var key: String = "%s+%s" % [pair[0], pair[1]]
	match key:
		"Hydro+Pyro":
			return ["Vaporize", 1]
		"Cryo+Pyro":
			return ["Melt", 2]
		"Electro+Pyro":
			return ["Overloaded", 2]
		"Cryo+Electro":
			return ["Superconduct", 1]
		"Electro+Hydro":
			return ["Electro-Charged", 1]
		"Cryo+Hydro":
			return ["Frozen", 1]
	return ["", 0]


# ------------------------------------------------------------------------------
# Helpers (`engine/rules.py:alive, has_status, remove_status, stunned, add_status, _spent...`)
# ------------------------------------------------------------------------------
static func alive(p: TCGPlayerSystem.PlayerState) -> Array[int]:
	return p.get_alive_indices()


static func has_status(ch: TCGPlayerSystem.CharacterInstance, status_name: String) -> bool:
	for s in ch.statuses:
		if s.name == status_name:
			return true
	return false


static func remove_status(ch: TCGPlayerSystem.CharacterInstance, status_name: String) -> void:
	var kept: Array[TCGPlayerSystem.StatusInstance] = []
	for s in ch.statuses:
		if s.name != status_name:
			kept.append(s)
	ch.statuses = kept


static func stunned(ch: TCGPlayerSystem.CharacterInstance) -> bool:
	return has_status(ch, "Frozen") or has_status(ch, "Petrified") or has_status(ch, "Stunned")


static func find_status(lst: Array[TCGPlayerSystem.StatusInstance], status_name: String) -> TCGPlayerSystem.StatusInstance:
	for st in lst:
		if st.name == status_name:
			return st
	return null


static func add_status(lst: Array[TCGPlayerSystem.StatusInstance], status_name: String) -> TCGPlayerSystem.StatusInstance:
	var df: CardDataSystem.StatusData = CardDataSystem.get_status_def(status_name)
	if df == null:
		return null
	for st in lst:
		if st.name == status_name:
			if df.usages >= 0:
				st.usages = df.usages
			if df.duration >= 0:
				st.duration = df.duration
			if df.shield > 0:
				st.shield = mini(df.max_shield, st.shield + df.shield)
			return st
	var new_st := TCGPlayerSystem.StatusInstance.new(status_name, df.usages, df.duration, df.shield)
	lst.append(new_st)
	return new_st


static func _spent(st: TCGPlayerSystem.StatusInstance) -> bool:
	var df: CardDataSystem.StatusData = CardDataSystem.get_status_def(st.name)
	if df == null:
		return false
	if df.per_round > 0:
		return false
	return (st.usages >= 0 and st.usages <= 0) or (df.shield > 0 and st.shield <= 0)


static func _next_alive(p: TCGPlayerSystem.PlayerState, idx: int) -> int:
	for k in [1, 2]:
		var j: int = (idx + k) % 3
		if not p.characters[j].defeated:
			return j
	return -1


static func foe_target(s: TCGGameState, pi: int) -> int:
	var f := s.players[1 - pi]
	if f.active >= 0 and not f.characters[f.active].defeated:
		return f.active
	var al := alive(f)
	return al[0] if not al.is_empty() else -1


static func force_switch(s: TCGGameState, pi: int) -> void:
	var p := s.players[pi]
	if p.active < 0:
		return
	var prev_active: int = p.active
	var n: int = _next_alive(p, p.active)
	if n >= 0:
		p.active = n
		s.add_event("switch", {"player": pi, "char": n, "forced": true})
		s.add_game_event(GameEvent.make(GameEvent.Type.CHARACTER_SWITCHED, pi, n, p.characters[n].name, "", 0, prev_active, n, "forced"))


# ------------------------------------------------------------------------------
# Status Callbacks (`content/statuses.py`) & Damage Pipeline (`engine/rules.py`)
# ------------------------------------------------------------------------------
static func _each_status(p: TCGPlayerSystem.PlayerState, ch: TCGPlayerSystem.CharacterInstance) -> Array[TCGPlayerSystem.StatusInstance]:
	var out: Array[TCGPlayerSystem.StatusInstance] = []
	if ch != null:
		for st in ch.statuses:
			out.append(st)
	for st in p.combat:
		out.append(st)
	return out


static func _apply_outgoing_rule(
	rule_name: String,
	_s: TCGGameState,
	_owner: int,
	st: TCGPlayerSystem.StatusInstance,
	d: Dictionary
) -> void:
	# Generic elemental infusion: "<element>_infusion" (e.g. "pyro_infusion")
	if rule_name.ends_with("_infusion"):
		if d["dtype"] == CardDataSystem.PHYSICAL:
			var el := rule_name.trim_suffix("_infusion").capitalize()
			if CardDataSystem.ELEMENTS.has(el):
				d["dtype"] = el
		return

	# Parameterized damage buffs: "bonus_<any|normal|skill|burst>_<N>" or "bonus_next_<kind>_<N>"
	if rule_name.begins_with("bonus_"):
		var parts := rule_name.split("_")
		var is_next: bool = (parts.size() >= 4 and parts[1] == "next")
		var target_kind: String = parts[2] if is_next else (parts[1] if parts.size() >= 3 else "")
		var bonus_val: int = int(parts[3]) if is_next and parts.size() >= 4 else (int(parts[2]) if parts.size() >= 3 else 0)
		var atk_kind: String = str(d.get("kind", ""))
		var matches_kind: bool = (not atk_kind.is_empty()) and (target_kind == "any" or target_kind == atk_kind)
		if bonus_val != 0 and matches_kind:
			if is_next:
				if st.usages > 0:
					d["amount"] = int(d["amount"]) + bonus_val
					st.usages -= 1
			else:
				d["amount"] = int(d["amount"]) + bonus_val
		return


static func _apply_after_skill_rule(
	_rule_name: String,
	_s: TCGGameState,
	_owner: int,
	_st: TCGPlayerSystem.StatusInstance,
	_skill_kind: String
) -> void:
	pass


static func _apply_on_kill_rule(
	_rule_name: String,
	_s: TCGGameState,
	_owner: int,
	_st: TCGPlayerSystem.StatusInstance
) -> void:
	pass


static func _outgoing(s: TCGGameState, sp: int, d: Dictionary) -> void:
	var p := s.players[sp]
	for st in _each_status(p, p.get_active_char()):
		var df: CardDataSystem.StatusData = CardDataSystem.get_status_def(st.name)
		if df != null:
			if not df.outgoing_rule.is_empty():
				_apply_outgoing_rule(df.outgoing_rule, s, sp, st, d)
			elif df.outgoing.is_valid():
				df.outgoing.call(s, sp, st, d)


static func _after_skill(s: TCGGameState, sp: int, kind: String) -> void:
	var p := s.players[sp]
	for st in _each_status(p, p.get_active_char()):
		var df: CardDataSystem.StatusData = CardDataSystem.get_status_def(st.name)
		if df != null:
			if not df.after_skill_rule.is_empty():
				_apply_after_skill_rule(df.after_skill_rule, s, sp, st, kind)
			elif df.after_skill.is_valid():
				df.after_skill.call(s, sp, st, kind)
	for c in p.characters:
		var kept_c: Array[TCGPlayerSystem.StatusInstance] = []
		for x in c.statuses:
			if not _spent(x):
				kept_c.append(x)
		c.statuses = kept_c
	var kept_combat: Array[TCGPlayerSystem.StatusInstance] = []
	for x in p.combat:
		if not _spent(x):
			kept_combat.append(x)
	p.combat = kept_combat


static func deal_damage(
	s: TCGGameState,
	sp: int,
	tp: int,
	ti: int,
	amount: int,
	dtype: String,
	source: String = "skill",
	kind: String = ""
) -> void:
	## Exact 6-step damage and elemental reaction pipeline (`engine/rules.py:deal_damage`):
	## 1) outgoing modifiers  2) frozen bonus  3) aura / reaction  4) shields  5) HP  6) side effects.
	var p := s.players[tp]
	var tgt := p.characters[ti]
	if tgt.defeated:
		return

	if source == "skill":
		var d := {"amount": amount, "dtype": dtype, "kind": kind}
		_outgoing(s, sp, d)
		amount = int(d["amount"])
		dtype = str(d["dtype"])

	var reaction: String = ""
	var swirled: String = ""

	# Step 2: Frozen bonus (+2 DMG from Physical or Pyro, then thaws)
	if (dtype == CardDataSystem.PHYSICAL or dtype == CardDataSystem.PYRO) and has_status(tgt, "Frozen"):
		amount += 2
		remove_status(tgt, "Frozen")
		s.add_game_event(GameEvent.make(GameEvent.Type.STATUS_REMOVED, tp, ti, "Frozen", "Cryo"))

	# Step 3: Elemental Aura & Reactions
	var prev_aura: String = tgt.aura
	if CardDataSystem.AURA_ELEMENTS.has(dtype):
		if tgt.aura.is_empty():
			tgt.aura = dtype
			s.add_game_event(GameEvent.make(GameEvent.Type.ELEMENT_ATTACHED, tp, ti, dtype, dtype, 1, "", dtype))
		elif tgt.aura != dtype:
			var r_pair: Array = _lookup_reaction(tgt.aura, dtype)
			reaction = str(r_pair[0])
			amount += int(r_pair[1])
			tgt.aura = ""
			s.add_game_event(GameEvent.make(GameEvent.Type.ELEMENT_REMOVED, tp, ti, prev_aura, prev_aura, 0, prev_aura, ""))
			s.add_game_event(GameEvent.make(GameEvent.Type.REACTION_TRIGGERED, tp, ti, reaction, dtype, int(r_pair[1]), prev_aura, dtype, source, sp, -1, {"swirled": swirled}))
	elif (dtype == CardDataSystem.ANEMO or dtype == CardDataSystem.GEO) and not tgt.aura.is_empty():
		swirled = tgt.aura
		tgt.aura = ""
		reaction = "Swirl" if dtype == CardDataSystem.ANEMO else "Crystallize"
		if dtype == CardDataSystem.GEO:
			amount += 1
		s.add_game_event(GameEvent.make(GameEvent.Type.ELEMENT_REMOVED, tp, ti, swirled, swirled, 0, swirled, ""))
		s.add_game_event(GameEvent.make(GameEvent.Type.REACTION_TRIGGERED, tp, ti, reaction, dtype, 1 if dtype == CardDataSystem.GEO else 0, swirled, dtype, source, sp, -1, {"swirled": swirled}))

	# Step 4: Damage Reduction & Shield Absorption (only on active character for non-Piercing)
	if dtype != CardDataSystem.PIERCING and ti == p.active:
		for st in p.combat.duplicate():
			var df: CardDataSystem.StatusData = CardDataSystem.get_status_def(st.name)
			if df != null and df.reduce > 0 and st.usages > 0 and amount >= df.reduce_min:
				var before_u: int = st.usages
				amount = maxi(0, amount - df.reduce)
				st.usages -= 1
				s.add_game_event(GameEvent.make(GameEvent.Type.STATUS_CHANGED, tp, ti, st.name, "", st.usages, before_u, st.usages, "combat"))
		for st in p.combat:
			if st.shield > 0 and amount > 0:
				var before_sh: int = st.shield
				var absorbed: int = mini(st.shield, amount)
				st.shield -= absorbed
				amount -= absorbed
				s.add_game_event(GameEvent.make(GameEvent.Type.SHIELD_CHANGED, tp, ti, st.name, "", absorbed, before_sh, st.shield))
		var kept_combat: Array[TCGPlayerSystem.StatusInstance] = []
		for x in p.combat:
			if not _spent(x):
				kept_combat.append(x)
			else:
				s.add_game_event(GameEvent.make(GameEvent.Type.STATUS_REMOVED, tp, ti, x.name, "", 0, 1, 0, "combat"))
		p.combat = kept_combat

	# Step 5: HP deduction & defeat
	var hp_before: int = tgt.hp
	tgt.hp = maxi(0, tgt.hp - amount)
	s.add_event("damage", {
		"player": tp,
		"char": ti,
		"amount": amount,
		"dtype": dtype,
		"reaction": null if reaction.is_empty() else reaction,
		"source": source,
	})
	s.add_game_event(GameEvent.make(
		GameEvent.Type.DAMAGE_DEALT,
		tp,
		ti,
		tgt.name,
		dtype,
		amount,
		hp_before,
		tgt.hp,
		source,
		sp,
		s.players[sp].active,
		{"reaction": reaction}
	))
	var log_line: String = "P%d->P%d.%s: %d %s" % [sp, tp, tgt.name, amount, dtype]
	if not reaction.is_empty():
		log_line += " [%s]" % reaction
	s.add_log(log_line)

	if tgt.hp == 0:
		_defeat(s, tp, ti, sp)

	# Step 6: Reaction side effects
	if reaction == "Overloaded" and not tgt.defeated and p.active == ti:
		force_switch(s, tp)
	elif reaction == "Superconduct" or reaction == "Electro-Charged":
		for j in range(p.characters.size()):
			var c := p.characters[j]
			if j != ti and not c.defeated:
				deal_damage(s, sp, tp, j, 1, CardDataSystem.PIERCING, "reaction", "")
	elif reaction == "Frozen" and not tgt.defeated:
		add_status(tgt.statuses, "Frozen")
		s.add_game_event(GameEvent.make(GameEvent.Type.STATUS_ADDED, tp, ti, "Frozen", "Cryo", 1, null, 1, "char"))
	elif reaction == "Swirl":
		var sw_attacker := s.players[sp].get_active_char()
		var swirl_dmg: int = 2 if (sw_attacker != null and sw_attacker.name == "Aang") else 1
		for j in range(p.characters.size()):
			var c := p.characters[j]
			if j != ti and not c.defeated:
				deal_damage(s, sp, tp, j, swirl_dmg, swirled, "swirl", "")
	elif reaction == "Crystallize":
		var sh_st := add_status(s.players[sp].combat, "Crystallize Shield")
		if sh_st != null:
			s.add_game_event(GameEvent.make(GameEvent.Type.SHIELD_CHANGED, sp, s.players[sp].active, "Crystallize Shield", "Geo", 1, maxi(0, sh_st.shield - 1), sh_st.shield))
			s.add_game_event(GameEvent.make(GameEvent.Type.STATUS_ADDED, sp, s.players[sp].active, "Crystallize Shield", "Geo", sh_st.shield, null, sh_st.shield, "combat"))


static func _defeat(s: TCGGameState, pi: int, ci: int, killer: int = -1) -> void:
	var p := s.players[pi]
	var c := p.characters[ci]
	c.hp = 0
	c.energy = 0
	c.aura = ""
	c.statuses = []
	c.defeated = true
	c.equipment = {}
	s.add_log("P%d.%s defeated" % [pi, c.name])
	s.add_event("defeat", {"player": pi, "char": ci})
	s.add_game_event(GameEvent.make(GameEvent.Type.CHARACTER_DEFEATED, pi, ci, c.name, "", 0, 1, 0, "", killer))
	if p.active == ci:
		p.active = -1
		if not alive(p).is_empty() and not s.pending.has(pi):
			s.pending.append(pi)
	TCGTurnManager.check_win(s)
	if killer >= 0 and s.winner == -2:
		var a := s.players[killer]
		for st in _each_status(a, a.get_active_char()):
			var df: CardDataSystem.StatusData = CardDataSystem.get_status_def(st.name)
			if df != null:
				if not df.on_kill_rule.is_empty():
					_apply_on_kill_rule(df.on_kill_rule, s, killer, st)
				elif df.on_kill.is_valid():
					df.on_kill.call(s, killer, st)


# ------------------------------------------------------------------------------
# Game Flow & Phase Transitions (`engine/rules.py`)
# ------------------------------------------------------------------------------
static func new_game(
	chars_0: Array,
	deck_0: Array,
	chars_1: Array,
	deck_1: Array,
	seed_val: int = -1
) -> TCGGameState:
	CardDataSystem.load_all_content()
	return GameManager.create_new_state(chars_0, deck_0, chars_1, deck_1, seed_val)


static func actor(s: TCGGameState) -> int:
	return TCGTurnManager.get_actor(s)


static func _start_action(s: TCGGameState) -> void:
	s.phase = "action"
	s.current = state_or_first(s)
	s.add_event("phase", {"name": "action", "first": s.first_player})
	s.add_game_event(GameEvent.make(GameEvent.Type.PHASE_CHANGED, s.first_player, -1, "action", "", s.round_number))
	var order: Array[int] = [s.first_player, 1 - s.first_player]
	for p_idx in order:
		var p := s.players[p_idx]
		for u in p.supports.duplicate():
			var cd: CardDataSystem.CardData = CardDataSystem.get_card_def(u.name)
			if cd != null and (not cd.action_start_steps.is_empty() or cd.action_start.is_valid()):
				var ctx := TCGEffectContext.new(s, p_idx)
				if not cd.action_start_steps.is_empty():
					ctx.execute_steps(cd.action_start_steps)
				elif cd.action_start.is_valid():
					cd.action_start.call(ctx)
				u.usages -= 1
		var kept: Array[TCGPlayerSystem.UnitInstance] = []
		for u in p.supports:
			if u.usages < 0 or u.usages > 0:
				kept.append(u)
			else:
				s.add_game_event(GameEvent.make(GameEvent.Type.SUPPORT_REMOVED, p_idx, -1, u.name))
		p.supports = kept


static func state_or_first(s: TCGGameState) -> int:
	return s.first_player


static func _end_phase(s: TCGGameState) -> void:
	s.phase = "end"
	s.add_event("phase", {"name": "end", "first": s.first_ender})
	s.add_game_event(GameEvent.make(GameEvent.Type.PHASE_CHANGED, s.first_ender, -1, "end", "", s.round_number))
	var order: Array[int] = [s.first_ender, 1 - s.first_ender]
	for p_idx in order:
		var p := s.players[p_idx]
		for u in p.summons.duplicate():
			var d: CardDataSystem.SummonData = CardDataSystem.get_summon_def(u.name)
			var before_u: int = u.usages
			s.add_game_event(GameEvent.make(
				GameEvent.Type.SUMMON_TRIGGERED,
				p_idx,
				-1,
				u.name,
				d.element if d != null else "",
				d.damage if d != null else 0,
				before_u,
				before_u - 1
			))
			var t: int = foe_target(s, p_idx)
			if t >= 0 and d != null:
				deal_damage(s, p_idx, 1 - p_idx, t, d.damage, d.element, "summon", "")
			u.usages -= 1
		var kept_sum: Array[TCGPlayerSystem.UnitInstance] = []
		for u in p.summons:
			if u.usages > 0:
				kept_sum.append(u)
			else:
				s.add_game_event(GameEvent.make(GameEvent.Type.SUMMON_REMOVED, p_idx, -1, u.name))
		p.summons = kept_sum

		for u in p.supports.duplicate():
			var cd: CardDataSystem.CardData = CardDataSystem.get_card_def(u.name)
			if cd != null and (not cd.end_phase_steps.is_empty() or cd.end_phase.is_valid()):
				var ctx := TCGEffectContext.new(s, p_idx)
				if not cd.end_phase_steps.is_empty():
					ctx.execute_steps(cd.end_phase_steps)
				elif cd.end_phase.is_valid():
					cd.end_phase.call(ctx)
				u.usages -= 1
		var kept_sup: Array[TCGPlayerSystem.UnitInstance] = []
		for u in p.supports:
			if u.usages < 0 or u.usages > 0:
				kept_sup.append(u)
			else:
				s.add_game_event(GameEvent.make(GameEvent.Type.SUPPORT_REMOVED, p_idx, -1, u.name))
		p.supports = kept_sup

		if s.winner != -2:
			return

	var carry_omni: Array[int] = [0, 0]
	for pi_c in range(s.players.size()):
		var p := s.players[pi_c]
		if find_status(p.combat, "Dice Carryover") != null:
			carry_omni[pi_c] = p.dice.size()
			var kept_c: Array[TCGPlayerSystem.StatusInstance] = []
			for st in p.combat:
				if st.name != "Dice Carryover":
					kept_c.append(st)
			p.combat = kept_c
		for c in p.characters:
			remove_status(c, "Frozen")
			remove_status(c, "Petrified")
			remove_status(c, "Stunned")
			c.statuses = TCGRoundManager.tick_statuses(c.statuses)
			TCGRoundManager.reset_round_usages(c.statuses)
		p.combat = TCGRoundManager.tick_statuses(p.combat)
		TCGRoundManager.reset_round_usages(p.combat)

	for p_idx in order:
		TCGRoundManager.draw_cards(s, p_idx, CardDataSystem.DRAW_END)

	TCGRoundManager.begin_round(s, false, carry_omni)


static func _use_combat(p: TCGPlayerSystem.PlayerState, status_name: String) -> bool:
	for st in p.combat:
		if st.name == status_name:
			st.usages -= 1
			var kept: Array[TCGPlayerSystem.StatusInstance] = []
			for x in p.combat:
				if not _spent(x):
					kept.append(x)
			p.combat = kept
			return true
	return false


static func switch_cost(_p: TCGPlayerSystem.PlayerState) -> CardDataSystem.CostData:
	return CardDataSystem.CostData.new("", 0, 1, 0)


static func is_healing_action_card(cd: CardDataSystem.CardData) -> bool:
	## True for Event action cards whose effect heals characters (subject to once-per-round cap).
	if cd == null or cd.kind != "event":
		return false
	if cd.role == "heal":
		return true
	for st in cd.play_steps:
		if st.op in ["heal", "heal_most_injured", "heal_all", "heal_dual"]:
			return true
	return false


static func card_targets(p: TCGPlayerSystem.PlayerState, cd: CardDataSystem.CardData) -> Array[int]:
	## Legal target character indices for `cd` (-1 = no target needed) (`engine/rules.py:_targets`).
	var al := alive(p)
	if cd.kind == "talent":
		var ch := p.get_active_char()
		if ch != null and ch.name == cd.char_name and not stunned(ch):
			var defn: CardDataSystem.CharData = ch.get_defn()
			if defn != null and ch.energy >= defn.skills[cd.skill_index].cost.energy:
				return [p.active]
		return []
	if cd.kind == "weapon":
		var out: Array[int] = []
		for i in al:
			var ch_i := p.characters[i]
			if not cd.char_name.is_empty():
				if ch_i.name == cd.char_name:
					out.append(i)
			else:
				var defn: CardDataSystem.CharData = ch_i.get_defn()
				if defn != null and defn.weapon == cd.weapon:
					out.append(i)
		return out
	if cd.kind == "artifact" or cd.needs_char:
		return al
	if cd.kind == "support" and p.supports.size() >= CardDataSystem.MAX_SUPPORTS:
		return []
	return [-1]


# ------------------------------------------------------------------------------
# Legal Actions (`engine/rules.py:legal_actions`)
# ------------------------------------------------------------------------------
static func legal_actions(s: TCGGameState) -> Array[TCGGameState.ActionData]:
	var p_idx: int = actor(s)
	var acts: Array[TCGGameState.ActionData] = []
	if p_idx < 0:
		return acts
	var p := s.players[p_idx]

	if not s.pending.is_empty():
		for i in alive(p):
			acts.append(TCGGameState.ActionData.new("choose_active", p_idx, i))
		return acts

	if s.phase == "setup":
		if not p.mull_done:
			acts.append(TCGGameState.ActionData.new("mulligan", p_idx))
			var all_ids: Array[int] = []
			for i in range(p.hand.size()):
				all_ids.append(i)
			acts.append(TCGGameState.ActionData.new("mulligan", p_idx, -1, -1, [], all_ids))
			return acts
		for i in range(3):
			acts.append(TCGGameState.ActionData.new("choose_active", p_idx, i))
		return acts

	var elems_dict: Dictionary = {}
	for i in alive(p):
		var defn: CardDataSystem.CharData = p.characters[i].get_defn()
		if defn != null:
			elems_dict[defn.element] = true
	var elems: Array = elems_dict.keys()

	if s.phase == "roll":
		acts.append(TCGGameState.ActionData.new("confirm_roll", p_idx))
		var junk: Array[int] = []
		for i in range(p.dice.size()):
			var d: String = p.dice[i]
			if d != CardDataSystem.OMNI and not elems_dict.has(d):
				junk.append(i)
		if p.rerolls > 0 and not junk.is_empty():
			acts.append(TCGGameState.ActionData.new("reroll", p_idx, -1, -1, [], junk))
		return acts

	# Action Phase
	var ch := p.get_active_char()
	if ch != null and not stunned(ch):
		var defn: CardDataSystem.CharData = ch.get_defn()
		if defn != null:
			for i in range(defn.skills.size()):
				var sk: CardDataSystem.SkillData = defn.skills[i]
				if sk.cost.energy > 0 and ch.energy < sk.cost.energy:
					continue
				var pay = TCGDiceSystem.auto_pay(p.dice, sk.cost, elems)
				if pay != null:
					acts.append(TCGGameState.ActionData.new("skill", p_idx, i, -1, pay))

	var sw_pay = TCGDiceSystem.auto_pay(p.dice, switch_cost(p), elems)
	if sw_pay != null:
		for i in alive(p):
			if i != p.active:
				acts.append(TCGGameState.ActionData.new("switch", p_idx, i, -1, sw_pay))

	var seen_cards: Dictionary = {}
	for hi in range(p.hand.size()):
		var c_name: String = p.hand[hi]
		if seen_cards.has(c_name):
			continue
		seen_cards[c_name] = true
		var cd: CardDataSystem.CardData = CardDataSystem.get_card_def(c_name)
		if cd == null:
			continue
		if is_healing_action_card(cd) and p.heal_card_used:
			continue
		var c_pay = TCGDiceSystem.auto_pay(p.dice, cd.cost, elems)
		if c_pay == null:
			continue
		for t in card_targets(p, cd):
			acts.append(TCGGameState.ActionData.new("card", p_idx, hi, t, c_pay))

	if ch != null:
		var ch_defn: CardDataSystem.CharData = ch.get_defn()
		var ch_el: String = ch_defn.element if ch_defn != null else ""
		var faces: Dictionary = {}
		for di in range(p.dice.size()):
			var d: String = p.dice[di]
			if d != CardDataSystem.OMNI and d != ch_el and not faces.has(d):
				faces[d] = true
				var seen_tune: Dictionary = {}
				for hi in range(p.hand.size()):
					var c_name: String = p.hand[hi]
					if not seen_tune.has(c_name):
						seen_tune[c_name] = true
						acts.append(TCGGameState.ActionData.new("tune", p_idx, hi, di))

	acts.append(TCGGameState.ActionData.new("end_round", p_idx))
	return acts


# ------------------------------------------------------------------------------
# Apply Action & Action Handlers (`engine/rules.py:apply_action, _mulligan, ...`)
# ------------------------------------------------------------------------------
static func _pay(p: TCGPlayerSystem.PlayerState, cost: CardDataSystem.CostData, idx: PackedInt32Array, s: TCGGameState = null, pi: int = -1) -> bool:
	var arr_idx := Array(idx)
	if not TCGDiceSystem.payment_ok(p.dice, cost, arr_idx):
		last_error = "invalid dice payment"
		return false
	var before_dice := p.dice.duplicate()
	var spent_faces: Array[String] = []
	for raw_i in arr_idx:
		spent_faces.append(p.dice[int(raw_i)])
	arr_idx.sort()
	arr_idx.reverse()
	for i in arr_idx:
		p.dice.remove_at(int(i))
	if s != null and not spent_faces.is_empty():
		s.add_game_event(GameEvent.make(GameEvent.Type.DICE_SPENT, pi, -1, "", "", spent_faces.size(), before_dice, p.dice.duplicate(), "", -1, -1, {"ids": arr_idx, "faces": spent_faces}))
	return true


static func _mulligan(s: TCGGameState, a: TCGGameState.ActionData) -> bool:
	var p := s.players[a.player]
	var uniq_set: Dictionary = {}
	for raw_i in a.ids:
		uniq_set[int(raw_i)] = true
	var ids: Array = uniq_set.keys()
	ids.sort()
	if p.mull_done:
		last_error = "bad mulligan"
		return false
	for i in ids:
		if int(i) < 0 or int(i) >= p.hand.size():
			last_error = "bad mulligan"
			return false

	var out: Array[String] = []
	for i in ids:
		out.append(p.hand[int(i)])
	if not out.is_empty():
		s.add_game_event(GameEvent.make(GameEvent.Type.CARD_DISCARDED, a.player, -1, "", "", out.size(), p.hand.size(), p.hand.size() - out.size(), "mulligan", -1, -1, {"names": out, "ids": ids}))
	var new_hand: Array[String] = []
	for i in range(p.hand.size()):
		if not uniq_set.has(i):
			new_hand.append(p.hand[i])
	p.hand = new_hand
	# Draw replacements BEFORE returning switched cards to the deck so you never immediately redraw what you switched out
	var to_draw: int = out.size()
	var avail: int = mini(to_draw, p.deck.size())
	if avail > 0:
		TCGRoundManager.draw_cards(s, a.player, avail)
	for c in out:
		p.deck.append(c)
	TCGRoundManager.shuffle_strings(s.rng, p.deck)
	if to_draw > avail:
		TCGRoundManager.draw_cards(s, a.player, to_draw - avail)
	p.mull_done = true
	return true


static func _choose_active(s: TCGGameState, a: TCGGameState.ActionData) -> bool:
	var p := s.players[a.player]
	if a.index < 0 or a.index >= 3 or p.characters[a.index].defeated:
		last_error = "bad character"
		return false
	if not s.pending.is_empty():
		var prev_act: int = p.active
		p.active = a.index
		s.pending.erase(a.player)
		s.add_event("switch", {"player": a.player, "char": a.index, "forced": true})
		s.add_game_event(GameEvent.make(GameEvent.Type.CHARACTER_SWITCHED, a.player, a.index, p.characters[a.index].name, "", 0, prev_act, a.index, "forced"))
		return true
	if not p.mull_done:
		last_error = "mulligan first"
		return false
	p.chosen = a.index
	if s.players[0].chosen >= 0 and s.players[1].chosen >= 0:
		for pi_init in range(s.players.size()):
			var pl := s.players[pi_init]
			pl.active = pl.chosen
			s.add_game_event(GameEvent.make(GameEvent.Type.CHARACTER_SWITCHED, pi_init, pl.active, pl.characters[pl.active].name, "", 0, -1, pl.active, "initial"))
		TCGRoundManager.begin_round(s, true)
	return true


static func _reroll(s: TCGGameState, a: TCGGameState.ActionData) -> bool:
	var p := s.players[a.player]
	if p.rerolls <= 0:
		last_error = "bad reroll"
		return false
	var uniq_set: Dictionary = {}
	for raw_i in a.ids:
		var i: int = int(raw_i)
		if i < 0 or i >= p.dice.size():
			last_error = "bad reroll"
			return false
		uniq_set[i] = true
	var ids: Array = uniq_set.keys()
	ids.sort()
	var before_dice := p.dice.duplicate()
	var new_rolls := TCGDiceSystem.roll(s.rng, ids.size())
	for k in range(ids.size()):
		p.dice[int(ids[k])] = new_rolls[k]
	p.rerolls -= 1
	s.add_game_event(GameEvent.make(GameEvent.Type.DICE_REROLLED, a.player, -1, "", "", ids.size(), before_dice, p.dice.duplicate(), "", -1, -1, {"ids": ids}))
	return true


static func _confirm_roll(s: TCGGameState, a: TCGGameState.ActionData) -> bool:
	s.players[a.player].roll_done = true
	if s.players[0].roll_done and s.players[1].roll_done:
		_start_action(s)
	return true


static func _skill(s: TCGGameState, a: TCGGameState.ActionData) -> bool:
	var p := s.players[a.player]
	var ch := p.get_active_char()
	if ch == null or stunned(ch):
		last_error = "cannot use skill"
		return false
	var defn: CardDataSystem.CharData = ch.get_defn()
	if defn == null or a.index < 0 or a.index >= defn.skills.size():
		last_error = "cannot use skill"
		return false
	var sk: CardDataSystem.SkillData = defn.skills[a.index]
	if sk.cost.energy > 0 and ch.energy < sk.cost.energy:
		last_error = "not enough energy"
		return false
	if not _pay(p, sk.cost, a.dice, s, a.player):
		return false
	_perform_skill(s, a.player, a.index)
	return true


static func _perform_skill(s: TCGGameState, pi: int, idx: int) -> void:
	var p := s.players[pi]
	var ch := p.get_active_char()
	var defn: CardDataSystem.CharData = ch.get_defn()
	var sk: CardDataSystem.SkillData = defn.skills[idx]
	var old_en: int = ch.energy
	if sk.kind == "burst":
		ch.energy -= sk.cost.energy
	else:
		ch.energy = mini(defn.max_energy, ch.energy + 1)
	s.add_event("skill", {"player": pi, "char": p.active, "skill": sk.name, "skill_kind": sk.kind})
	s.add_game_event(GameEvent.make(GameEvent.Type.SKILL_USED, pi, p.active, sk.name, defn.element, idx, null, null, sk.kind))
	if ch.energy != old_en:
		s.add_game_event(GameEvent.make(GameEvent.Type.ENERGY_CHANGED, pi, p.active, ch.name, defn.element, ch.energy - old_en, old_en, ch.energy, sk.kind, -1, -1, {"max": defn.max_energy}))
	s.add_log("P%d.%s uses %s" % [pi, ch.name, sk.name])
	var ctx := TCGEffectContext.new(s, pi, sk.kind)
	if not sk.steps.is_empty():
		ctx.execute_steps(sk.steps)
	elif sk.effect.is_valid():
		sk.effect.call(ctx)
	_after_skill(s, pi, sk.kind)
	TCGTurnManager.check_win(s)
	TCGTurnManager.end_turn(s, pi)


static func _switch(s: TCGGameState, a: TCGGameState.ActionData) -> bool:
	var p := s.players[a.player]
	if a.index < 0 or a.index >= 3 or a.index == p.active or p.characters[a.index].defeated:
		last_error = "bad switch target"
		return false
	var prev_active: int = p.active
	var cost := switch_cost(p)
	if not _pay(p, cost, a.dice, s, a.player):
		return false
	p.active = a.index
	s.add_event("switch", {"player": a.player, "char": a.index, "forced": false})
	s.add_game_event(GameEvent.make(GameEvent.Type.CHARACTER_SWITCHED, a.player, a.index, p.characters[a.index].name, "", 0, prev_active, a.index, "manual"))
	TCGTurnManager.end_turn(s, a.player)
	return true


static func _equip(ch: TCGPlayerSystem.CharacterInstance, cd: CardDataSystem.CardData, s: TCGGameState = null, pi: int = -1, ci: int = -1) -> void:
	var old_name: String = str(ch.equipment.get(cd.kind, ""))
	if not old_name.is_empty():
		var old_cd: CardDataSystem.CardData = CardDataSystem.get_card_def(old_name)
		if old_cd != null and not old_cd.status.is_empty():
			remove_status(ch, old_cd.status)
			if s != null:
				s.add_game_event(GameEvent.make(GameEvent.Type.STATUS_REMOVED, pi, ci, old_cd.status, "", 0, null, null, cd.kind))
	ch.equipment[cd.kind] = cd.name
	if not cd.status.is_empty():
		var st := add_status(ch.statuses, cd.status)
		if s != null and st != null:
			s.add_game_event(GameEvent.make(GameEvent.Type.STATUS_ADDED, pi, ci, cd.status, "", st.usages, null, st.usages, cd.kind))


static func _card(s: TCGGameState, a: TCGGameState.ActionData) -> bool:
	var p := s.players[a.player]
	if a.index < 0 or a.index >= p.hand.size():
		last_error = "bad card"
		return false
	var cd: CardDataSystem.CardData = CardDataSystem.get_card_def(p.hand[a.index])
	if cd == null or not card_targets(p, cd).has(a.target):
		last_error = "bad card target"
		return false
	if is_healing_action_card(cd) and p.heal_card_used:
		last_error = "only one healing card per round"
		return false
	if not _pay(p, cd.cost, a.dice, s, a.player):
		return false
	if is_healing_action_card(cd):
		p.heal_card_used = true
	p.hand.remove_at(a.index)
	s.add_event("card", {"player": a.player, "name": cd.name})
	s.add_game_event(GameEvent.make(GameEvent.Type.CARD_PLAYED, a.player, a.target, cd.name, cd.resonance, a.index, null, null, cd.kind))
	if cd.kind == "support":
		p.supports.append(TCGPlayerSystem.UnitInstance.new(cd.name, cd.usages))
		s.add_game_event(GameEvent.make(GameEvent.Type.SUPPORT_ADDED, a.player, -1, cd.name, cd.resonance, cd.usages, 0, cd.usages))
	elif cd.kind == "weapon" or cd.kind == "artifact":
		_equip(p.characters[a.target], cd, s, a.player, a.target)
	elif cd.kind == "talent":
		_equip(p.characters[a.target], cd, s, a.player, a.target)
		_perform_skill(s, a.player, cd.skill_index)
		return true
	else:
		var ctx := TCGEffectContext.new(s, a.player)
		if not cd.play_steps.is_empty():
			ctx.execute_steps(cd.play_steps, a.target, Array(a.ids))
		elif cd.play.is_valid():
			cd.play.call(ctx, a.target)
	TCGTurnManager.check_win(s)
	return true


static func _tune(s: TCGGameState, a: TCGGameState.ActionData) -> bool:
	var p := s.players[a.player]
	var ch := p.get_active_char()
	if ch == null or a.index < 0 or a.index >= p.hand.size() or a.target < 0 or a.target >= p.dice.size():
		last_error = "bad tune"
		return false
	var defn: CardDataSystem.CharData = ch.get_defn()
	var el: String = defn.element if defn != null else ""
	if p.dice[a.target] == CardDataSystem.OMNI or p.dice[a.target] == el:
		last_error = "die already matches"
		return false
	var discarded_name: String = p.hand[a.index]
	var prev_die: String = p.dice[a.target]
	p.hand.remove_at(a.index)
	p.dice[a.target] = el
	s.add_game_event(GameEvent.make(GameEvent.Type.CARD_DISCARDED, a.player, -1, discarded_name, "", 1, p.hand.size() + 1, p.hand.size(), "tune"))
	s.add_game_event(GameEvent.make(GameEvent.Type.DIE_TUNED, a.player, a.target, el, el, a.target, prev_die, el))
	return true


static func _end_round(s: TCGGameState, a: TCGGameState.ActionData) -> bool:
	s.add_event("end_round", {"player": a.player})
	if TCGTurnManager.declare_end_round(s, a.player):
		_end_phase(s)
	return true


static func apply_action(s: TCGGameState, a: TCGGameState.ActionData) -> TCGGameState:
	## Validates and applies `a` to `s` in-place (`engine/rules.py:apply_action`).
	## If illegal, sets `last_error` to the exact Python `IllegalAction` message and leaves `s` unchanged.
	last_error = ""
	if a == null:
		last_error = "null action"
		return s
	if actor(s) != a.player:
		last_error = "not this player's turn"
		return s
	var valid_types: PackedStringArray = [
		"mulligan", "choose_active", "reroll", "confirm_roll",
		"skill", "switch", "card", "tune", "end_round"
	]
	if not valid_types.has(a.type):
		last_error = "unknown action %s" % a.type
		return s

	if a.type == "choose_active":
		if s.pending.is_empty() and s.phase != "setup":
			last_error = "nothing to choose"
			return s
	elif not s.pending.is_empty() or str(_PHASE_OF.get(a.type, "")) != s.phase:
		last_error = "%s not allowed now" % a.type
		return s

	var prev_actor: int = actor(s)
	var prev_phase: String = s.phase
	var prev_winner: int = s.winner
	s.events = []
	s.game_events = []
	match a.type:
		"mulligan":
			_mulligan(s, a)
		"choose_active":
			_choose_active(s, a)
		"reroll":
			_reroll(s, a)
		"confirm_roll":
			_confirm_roll(s, a)
		"skill":
			_skill(s, a)
		"switch":
			_switch(s, a)
		"card":
			_card(s, a)
		"tune":
			_tune(s, a)
		"end_round":
			_end_round(s, a)
	if s.track_events:
		if s.winner != -2 and prev_winner == -2:
			s.add_game_event(GameEvent.make(GameEvent.Type.GAME_OVER, s.winner, -1, "", "", s.round_number, prev_winner, s.winner))
		elif not s.pending.is_empty():
			s.add_game_event(GameEvent.make(GameEvent.Type.FORCED_SWITCH_REQUESTED, s.pending[0]))
		else:
			var next_actor: int = actor(s)
			if next_actor >= 0 and (next_actor != prev_actor or s.phase != prev_phase):
				if s.phase == "setup" and not s.players[next_actor].mull_done:
					s.add_game_event(GameEvent.make(GameEvent.Type.HAND_SWAP_REQUESTED, next_actor))
				s.add_game_event(GameEvent.make(GameEvent.Type.TURN_CHANGED, next_actor, -1, s.phase, "", s.round_number, prev_actor, next_actor))
	return s


static func describe(s: TCGGameState) -> String:
	## Plain-text board summary matching `engine/rules.py:describe(s)`.
	var lines: PackedStringArray = [
		"Round %d  phase=%s  to act: %d  winner=%d" % [s.round_number, s.phase, actor(s), s.winner]
	]
	for i in range(s.players.size()):
		var p := s.players[i]
		var char_parts: PackedStringArray = []
		for j in range(p.characters.size()):
			var c := p.characters[j]
			var prefix: String = "*" if j == p.active else ""
			var aura_str: String = " [%s]" % c.aura if not c.aura.is_empty() else ""
			var def_str: String = " X" if c.defeated else ""
			char_parts.append("%s%s %dhp %de%s%s" % [prefix, c.name, c.hp, c.energy, aura_str, def_str])
		lines.append("P%d: %s" % [i, ", ".join(char_parts)])
		var sorted_dice := p.dice.duplicate()
		sorted_dice.sort()
		lines.append("    dice=%s hand=%d deck=%d summons=%d status=%d" % [
			str(sorted_dice), p.hand.size(), p.deck.size(), p.summons.size(), p.combat.size()
		])
	return "\n".join(lines)


# ------------------------------------------------------------------------------
# Live Action / Skill / Card Combat Preview Simulation
# ------------------------------------------------------------------------------
static func _total_char_shield(p: TCGPlayerSystem.PlayerState, ci: int) -> int:
	if p == null or ci < 0 or ci >= p.characters.size():
		return 0
	var total := 0
	if p.active == ci:
		for st in p.combat:
			total += maxi(0, st.shield)
	for st in p.characters[ci].statuses:
		total += maxi(0, st.shield)
	return total


static func _snapshot_preview_side(p: TCGPlayerSystem.PlayerState) -> Dictionary:
	var char_snaps: Array[Dictionary] = []
	for i in range(p.characters.size()):
		var c := p.characters[i]
		char_snaps.append({
			"name": c.name,
			"hp": c.hp,
			"shield": _total_char_shield(p, i),
			"aura": c.aura,
			"frozen": has_status(c, "Frozen") or has_status(c, "Petrified"),
			"defeated": c.defeated,
			"energy": c.energy,
		})
	var sum_names: Array[String] = []
	var sum_usages: Dictionary = {}
	for u in p.summons:
		sum_names.append(u.name)
		sum_usages[u.name] = u.usages
	return {
		"active": p.active,
		"hand_size": p.hand.size(),
		"dice_size": p.dice.size(),
		"chars": char_snaps,
		"summons": sum_names,
		"summon_usages": sum_usages,
	}


static func _player_elems(p: TCGPlayerSystem.PlayerState) -> Array:
	var elems_dict: Dictionary = {}
	for i in alive(p):
		var defn: CardDataSystem.CharData = p.characters[i].get_defn()
		if defn != null:
			elems_dict[defn.element] = true
	return elems_dict.keys()


static func _build_action_preview_diff(
	before_own: Dictionary,
	before_foe: Dictionary,
	sim: TCGGameState,
	pi: int,
	can_use_now: bool,
	block_reason: String
) -> Dictionary:
	var foe_pi: int = 1 - pi
	var sim_own := sim.players[pi]
	var sim_foe := sim.players[foe_pi]

	# Aggregate events emitted exclusively during simulation
	var foe_dealt_after_shield := [0, 0, 0]
	var foe_shield_absorbed := [0, 0, 0]
	var foe_piercing := [0, 0, 0]
	var foe_primary_dtype := ["", "", ""]
	var foe_reactions := [[], [], []]
	var foe_swirl_elements := ["", "", ""]
	var summons_added: Array[String] = []
	var supports_added: Array[String] = []
	var own_statuses_added: Array[String] = []
	var cards_drawn := 0

	for ev in sim.events:
		if String(ev.get("kind", "")) == "damage":
			var tp: int = int(ev.get("player", -1))
			var ti: int = int(ev.get("char", -1))
			var amt: int = int(ev.get("amount", 0))
			var dt: String = String(ev.get("dtype", ""))
			if tp == foe_pi and ti >= 0 and ti < 3:
				foe_dealt_after_shield[ti] += amt
				if dt == CardDataSystem.PIERCING:
					foe_piercing[ti] += amt
				elif String(foe_primary_dtype[ti]).is_empty() and not dt.is_empty():
					foe_primary_dtype[ti] = dt
				var rx = ev.get("reaction", null)
				if rx != null and not String(rx).is_empty():
					var rx_s := String(rx)
					if not foe_reactions[ti].has(rx_s):
						foe_reactions[ti].append(rx_s)

	for gev in sim.game_events:
		match gev.type:
			GameEvent.Type.SHIELD_CHANGED:
				if gev.player == foe_pi:
					var sh_before: int = int(gev.before) if gev.before != null else 0
					var sh_after: int = int(gev.after) if gev.after != null else 0
					if sh_after < sh_before:
						var sh_idx: int = gev.char_index if gev.char_index >= 0 else int(before_foe["active"])
						if sh_idx >= 0 and sh_idx < 3:
							foe_shield_absorbed[sh_idx] += (sh_before - sh_after)
			GameEvent.Type.REACTION_TRIGGERED:
				if gev.player == foe_pi and gev.char_index >= 0 and gev.char_index < 3:
					if not gev.name.is_empty() and not foe_reactions[gev.char_index].has(gev.name):
						foe_reactions[gev.char_index].append(gev.name)
					var sw := String(gev.meta.get("swirled", ""))
					if not sw.is_empty():
						foe_swirl_elements[gev.char_index] = sw
			GameEvent.Type.SUMMON_ADDED:
				if gev.player == pi and not gev.name.is_empty():
					summons_added.append(gev.name)
			GameEvent.Type.SUPPORT_ADDED:
				if gev.player == pi and not gev.name.is_empty():
					supports_added.append(gev.name)
			GameEvent.Type.STATUS_ADDED:
				if gev.player == pi and not gev.name.is_empty() and not own_statuses_added.has(gev.name):
					own_statuses_added.append(gev.name)
			GameEvent.Type.CARD_DRAWN:
				if gev.player == pi:
					cards_drawn += 1

	var foe_chars: Dictionary = {}
	var own_chars: Dictionary = {}
	var summary_lines: Array[String] = []
	var bf_act: int = int(before_foe["active"])
	var af_act: int = sim_foe.active
	var foe_forced_switch: bool = (bf_act >= 0 and af_act >= 0 and bf_act != af_act and not sim_foe.characters[bf_act].defeated)

	for i in range(3):
		var b: Dictionary = before_foe["chars"][i]
		var ac := sim_foe.characters[i]
		var hp_before: int = int(b["hp"])
		var hp_after: int = ac.hp
		var hp_dmg: int = maxi(0, hp_before - hp_after)
		var shield_dmg: int = int(foe_shield_absorbed[i])
		var dealt_hp_inc: int = int(foe_dealt_after_shield[i])
		var total_dmg: int = maxi(hp_dmg, dealt_hp_inc) + shield_dmg
		var piercing_dmg: int = int(foe_piercing[i])
		var rx_list: Array = foe_reactions[i]
		var rx_main: String = String(rx_list[0]) if not rx_list.is_empty() else ""
		var dtype_str: String = String(foe_primary_dtype[i])
		if dtype_str.is_empty() and piercing_dmg > 0:
			dtype_str = CardDataSystem.PIERCING
		var b_aura: String = String(b["aura"])
		var a_aura: String = ac.aura
		var new_aura: String = a_aura if (not a_aura.is_empty() and a_aura != b_aura) else ""
		var aura_consumed: bool = (not b_aura.is_empty() and a_aura.is_empty())
		var defeated_now: bool = ((not bool(b["defeated"])) and ac.defeated)
		var frozen_now: bool = ((not bool(b["frozen"])) and (has_status(ac, "Frozen") or has_status(ac, "Petrified")))
		var shattered_now: bool = (bool(b["frozen"]) and not has_status(ac, "Frozen"))
		var forced_out: bool = foe_forced_switch and bf_act == i
		var forced_in: bool = foe_forced_switch and af_act == i

		var any_foe_fx: bool = (
			total_dmg > 0 or not rx_main.is_empty() or not new_aura.is_empty()
			or frozen_now or shattered_now or defeated_now or forced_out or forced_in
		)
		if any_foe_fx:
			var entry := {
				"total_dmg": total_dmg,
				"hp_dmg": hp_dmg,
				"shield_dmg": shield_dmg,
				"piercing_dmg": piercing_dmg,
				"hp_before": hp_before,
				"hp_after": hp_after,
				"dtype": dtype_str,
				"reaction": rx_main,
				"reactions": rx_list,
				"swirled": String(foe_swirl_elements[i]),
				"new_aura": new_aura,
				"aura_consumed": aura_consumed,
				"frozen": frozen_now,
				"shattered": shattered_now,
				"defeated": defeated_now,
				"forced_switch_out": forced_out,
				"forced_switch_in": forced_in,
				"forced_switch_target": sim_foe.characters[af_act].name if forced_out else "",
			}
			foe_chars[i] = entry

			var parts: Array[String] = []
			if total_dmg > 0:
				var dmg_lbl := "%d %s DMG" % [total_dmg, dtype_str if not dtype_str.is_empty() else ""]
				dmg_lbl = dmg_lbl.replace("  ", " ")
				if shield_dmg > 0:
					parts.append("%s (%d Shield + %d HP)" % [dmg_lbl, shield_dmg, hp_dmg])
				else:
					parts.append("%s (%d -> %d HP)" % [dmg_lbl, hp_before, hp_after])
			if defeated_now:
				parts.append("DEFEATED")
			if not rx_main.is_empty():
				var rx_str := ", ".join(rx_list)
				if forced_out and af_act >= 0:
					parts.append("%s -> forces %s active" % [rx_str, sim_foe.characters[af_act].name])
				elif frozen_now:
					parts.append("%s (Frozen)" % rx_str)
				else:
					parts.append(rx_str)
			elif not new_aura.is_empty():
				parts.append("applies %s" % new_aura)
			if not parts.is_empty():
				summary_lines.append("%s: %s" % [ac.name, " · ".join(parts)])

	var bo_act: int = int(before_own["active"])
	var ao_act: int = sim_own.active
	var own_switched: bool = (bo_act >= 0 and ao_act >= 0 and bo_act != ao_act)
	for i in range(3):
		var ob: Dictionary = before_own["chars"][i]
		var oc := sim_own.characters[i]
		var heal_amt: int = maxi(0, oc.hp - int(ob["hp"]))
		var sh_after: int = _total_char_shield(sim_own, i)
		var sh_gain: int = maxi(0, sh_after - int(ob["shield"]))
		var en_gain: int = maxi(0, oc.energy - int(ob["energy"]))
		var ob_aura: String = String(ob["aura"])
		var oa_aura: String = oc.aura
		var own_new_aura: String = oa_aura if (not oa_aura.is_empty() and oa_aura != ob_aura) else ""
		var own_cleared_aura: String = ob_aura if (not ob_aura.is_empty() and oa_aura.is_empty()) else ""
		var sw_in_own: bool = own_switched and ao_act == i
		if heal_amt > 0 or sh_gain > 0 or not own_new_aura.is_empty() or not own_cleared_aura.is_empty() or sw_in_own:
			own_chars[i] = {
				"heal": heal_amt,
				"shield_gain": sh_gain,
				"energy_gain": en_gain,
				"new_aura": own_new_aura,
				"aura_cleared": own_cleared_aura,
				"switch_in": sw_in_own,
			}
			var oparts: Array[String] = []
			if heal_amt > 0:
				oparts.append("+%d HP (%d -> %d)" % [heal_amt, int(ob["hp"]), oc.hp])
			if sh_gain > 0:
				oparts.append("+%d Shield" % sh_gain)
			if not own_cleared_aura.is_empty():
				oparts.append("cleanses %s aura" % own_cleared_aura)
			if not own_new_aura.is_empty():
				oparts.append("%s aura" % own_new_aura)
			if sw_in_own:
				oparts.append("switches in")
			summary_lines.append("Ally %s: %s" % [oc.name, " · ".join(oparts)])

	for sname in summons_added:
		var sdef := CardDataSystem.get_summon_def(sname)
		if sdef != null:
			summary_lines.append("Summons %s (End Phase: %d %s DMG, %d uses)" % [sname, sdef.damage, sdef.element, sdef.usages])
		else:
			summary_lines.append("Summons %s" % sname)
	for sup in supports_added:
		summary_lines.append("Places Support: %s" % sup)
	if cards_drawn > 0:
		summary_lines.append("Draws %d card%s" % [cards_drawn, "s" if cards_drawn > 1 else ""])
	if not can_use_now and not block_reason.is_empty():
		summary_lines.append("Note: %s" % block_reason)

	return {
		"ok": true,
		"can_use_now": can_use_now,
		"block_reason": block_reason,
		"foe_chars": foe_chars,
		"own_chars": own_chars,
		"summons_added": summons_added,
		"supports_added": supports_added,
		"own_statuses_added": own_statuses_added,
		"cards_drawn": cards_drawn,
		"foe_forced_switch": foe_forced_switch,
		"own_switched": own_switched,
		"summary_lines": summary_lines,
	}


static func preview_skill(s: TCGGameState, pi: int, skill_idx: int) -> Dictionary:
	## Non-mutating clone simulation showing exact damage, reactions, shields, heals & summons for skill `skill_idx`.
	if s == null or pi < 0 or pi >= s.players.size():
		return {"ok": false}
	var p := s.players[pi]
	var ch := p.get_active_char()
	if ch == null or ch.defeated:
		return {"ok": false}
	var defn: CardDataSystem.CharData = ch.get_defn()
	if defn == null or skill_idx < 0 or skill_idx >= defn.skills.size():
		return {"ok": false}

	var sk: CardDataSystem.SkillData = defn.skills[skill_idx]
	var elems := _player_elems(p)
	var is_stunned := stunned(ch)
	var has_energy := (sk.cost.energy <= 0 or ch.energy >= sk.cost.energy)
	var has_dice := (TCGDiceSystem.auto_pay(p.dice, sk.cost, elems) != null)
	var can_use := (s.phase == "action" and s.pending.is_empty() and s.winner == -2 and not is_stunned and has_energy and has_dice)
	var reason := ""
	if s.phase != "action":
		reason = "Usable in Action Phase"
	elif is_stunned:
		reason = "Frozen / Petrified — cannot act"
	elif not has_energy:
		reason = "Needs %d Energy (have %d)" % [sk.cost.energy, ch.energy]
	elif not has_dice:
		reason = "Not enough matching dice"

	var sim := s.clone(false, true)
	sim.track_events = true
	sim.pending.clear()
	sim.events.clear()
	sim.game_events.clear()
	var sim_p := sim.players[pi]
	var sim_ch := sim_p.get_active_char()
	if sim_ch != null and sk.cost.energy > 0 and sim_ch.energy < sk.cost.energy:
		sim_ch.energy = sk.cost.energy

	var before_own := _snapshot_preview_side(sim_p)
	var before_foe := _snapshot_preview_side(sim.players[1 - pi])
	_perform_skill(sim, pi, skill_idx)
	return _build_action_preview_diff(before_own, before_foe, sim, pi, can_use, reason)


static func preview_card(s: TCGGameState, pi: int, hand_idx: int, target_idx: int = -1) -> Dictionary:
	## Non-mutating clone simulation showing exact effect & damage/reaction impact when playing a hand card.
	if s == null or pi < 0 or pi >= s.players.size():
		return {"ok": false}
	var p := s.players[pi]
	if hand_idx < 0 or hand_idx >= p.hand.size():
		return {"ok": false}
	var cd: CardDataSystem.CardData = CardDataSystem.get_card_def(p.hand[hand_idx])
	if cd == null:
		return {"ok": false}
	var legal_tgts := card_targets(p, cd)
	if legal_tgts.is_empty():
		return {"ok": false, "can_use_now": false, "block_reason": "No valid target"}
	var sim_tgt: int = target_idx if legal_tgts.has(target_idx) else int(legal_tgts[0])

	var elems := _player_elems(p)
	var real_pay = TCGDiceSystem.auto_pay(p.dice, cd.cost, elems)
	var has_dice := (real_pay != null)
	var heal_blocked := is_healing_action_card(cd) and p.heal_card_used
	var can_use := (s.phase == "action" and s.pending.is_empty() and s.winner == -2 and has_dice and not heal_blocked)
	var reason := ""
	if s.phase != "action":
		reason = "Playable in Action Phase"
	elif heal_blocked:
		reason = "Already used a healing card this round"
	elif not has_dice:
		reason = "Not enough matching dice"

	var sim := s.clone(false, true)
	sim.track_events = true
	sim.pending.clear()
	sim.events.clear()
	sim.game_events.clear()
	var sim_p := sim.players[pi]
	sim_p.heal_card_used = false
	var pay_arr: PackedInt32Array
	if real_pay != null:
		pay_arr = real_pay
	else:
		sim_p.dice.clear()
		var needed := cd.cost.total_dice()
		for _d in range(needed):
			sim_p.dice.append(CardDataSystem.OMNI)
		var fake_pay = TCGDiceSystem.auto_pay(sim_p.dice, cd.cost, elems)
		pay_arr = fake_pay if fake_pay != null else PackedInt32Array()

	var before_own := _snapshot_preview_side(sim_p)
	var before_foe := _snapshot_preview_side(sim.players[1 - pi])
	var act := TCGGameState.ActionData.new("card", pi, hand_idx, sim_tgt, pay_arr)
	var played_ok := _card(sim, act)
	if not played_ok:
		return {"ok": false}
	return _build_action_preview_diff(before_own, before_foe, sim, pi, can_use, reason)



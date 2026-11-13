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
	return has_status(ch, "Frozen") or has_status(ch, "Petrified")


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
	var n: int = _next_alive(p, p.active)
	if n >= 0:
		p.active = n
		s.add_event("switch", {"player": pi, "char": n, "forced": true})


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
	s: TCGGameState,
	owner: int,
	st: TCGPlayerSystem.StatusInstance,
	d: Dictionary
) -> void:
	match rule_name:
		"pyro_infusion":
			if d["dtype"] == CardDataSystem.PHYSICAL:
				d["dtype"] = CardDataSystem.PYRO
		"electro_infusion":
			if d["dtype"] == CardDataSystem.PHYSICAL:
				d["dtype"] = CardDataSystem.ELECTRO
		"inspiration_field":
			var ch := s.players[owner].get_active_char()
			if ch != null and ch.hp >= 7:
				d["amount"] = int(d["amount"]) + 2
		"fervent_flames":
			if st.usages > 0 and not str(d["kind"]).is_empty():
				d["amount"] = int(d["amount"]) + 2
				st.usages -= 1
		"bonus_any_1":
			d["amount"] = int(d["amount"]) + 1
		"bonus_skill_1":
			if d["kind"] == "skill":
				d["amount"] = int(d["amount"]) + 1
		"bonus_burst_1":
			if d["kind"] == "burst":
				d["amount"] = int(d["amount"]) + 1
		"bonus_normal_1":
			if d["kind"] == "normal":
				d["amount"] = int(d["amount"]) + 1


static func _apply_after_skill_rule(
	rule_name: String,
	s: TCGGameState,
	owner: int,
	st: TCGPlayerSystem.StatusInstance,
	skill_kind: String
) -> void:
	match rule_name:
		"inspiration_heal":
			var ch := s.players[owner].get_active_char()
			if ch != null and ch.hp <= 6:
				TCGEffectContext.new(s, owner).heal(2)
		"rainbow_bladework":
			if skill_kind == "normal" and st.usages > 0:
				var t: int = foe_target(s, owner)
				if t >= 0:
					deal_damage(s, owner, 1 - owner, t, 1, CardDataSystem.HYDRO, "status", "")
				st.usages -= 1
		"stellar_predator":
			var p := s.players[owner]
			var has_oz: bool = false
			for u in p.summons:
				if u.name == "Oz":
					has_oz = true
					break
			if skill_kind == "normal" and st.usages > 0 and has_oz:
				var t: int = foe_target(s, owner)
				if t >= 0:
					deal_damage(s, owner, 1 - owner, t, 2, CardDataSystem.ELECTRO, "status", "")
				st.usages -= 1
		"cold_blooded_strike":
			if skill_kind == "skill":
				TCGEffectContext.new(s, owner).heal(2)


static func _apply_on_kill_rule(
	rule_name: String,
	s: TCGGameState,
	owner: int,
	st: TCGPlayerSystem.StatusInstance
) -> void:
	match rule_name:
		"gamblers_earrings":
			if st.usages > 0:
				TCGEffectContext.new(s, owner).gain_dice(2, CardDataSystem.OMNI)
				st.usages -= 1


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

	# Step 3: Elemental Aura & Reactions
	if CardDataSystem.AURA_ELEMENTS.has(dtype):
		if tgt.aura.is_empty():
			tgt.aura = dtype
		elif tgt.aura != dtype:
			var r_pair: Array = _lookup_reaction(tgt.aura, dtype)
			reaction = str(r_pair[0])
			amount += int(r_pair[1])
			tgt.aura = ""
	elif (dtype == CardDataSystem.ANEMO or dtype == CardDataSystem.GEO) and not tgt.aura.is_empty():
		swirled = tgt.aura
		tgt.aura = ""
		reaction = "Swirl" if dtype == CardDataSystem.ANEMO else "Crystallize"
		if dtype == CardDataSystem.GEO:
			amount += 1

	# Step 4: Damage Reduction & Shield Absorption (only on active character for non-Piercing)
	if dtype != CardDataSystem.PIERCING and ti == p.active:
		for st in p.combat.duplicate():
			var df: CardDataSystem.StatusData = CardDataSystem.get_status_def(st.name)
			if df != null and df.reduce > 0 and st.usages > 0 and amount >= df.reduce_min:
				amount = maxi(0, amount - df.reduce)
				st.usages -= 1
		for st in p.combat:
			if st.shield > 0 and amount > 0:
				var absorbed: int = mini(st.shield, amount)
				st.shield -= absorbed
				amount -= absorbed
		var kept_combat: Array[TCGPlayerSystem.StatusInstance] = []
		for x in p.combat:
			if not _spent(x):
				kept_combat.append(x)
		p.combat = kept_combat

	# Step 5: HP deduction & defeat
	tgt.hp = maxi(0, tgt.hp - amount)
	s.add_event("damage", {
		"player": tp,
		"char": ti,
		"amount": amount,
		"dtype": dtype,
		"reaction": null if reaction.is_empty() else reaction,
		"source": source,
	})
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
	elif reaction == "Swirl":
		for j in range(p.characters.size()):
			var c := p.characters[j]
			if j != ti and not c.defeated:
				deal_damage(s, sp, tp, j, 1, swirled, "swirl", "")
	elif reaction == "Crystallize":
		add_status(s.players[sp].combat, "Crystallize Shield")


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
	s.current = s.first_player
	s.add_event("phase", {"name": "action", "first": s.first_player})
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
		p.supports = kept


static func _end_phase(s: TCGGameState) -> void:
	s.phase = "end"
	s.add_event("phase", {"name": "end", "first": s.first_ender})
	var order: Array[int] = [s.first_ender, 1 - s.first_ender]
	for p_idx in order:
		var p := s.players[p_idx]
		for u in p.summons.duplicate():
			var d: CardDataSystem.SummonData = CardDataSystem.get_summon_def(u.name)
			var t: int = foe_target(s, p_idx)
			if t >= 0 and d != null:
				deal_damage(s, p_idx, 1 - p_idx, t, d.damage, d.element, "summon", "")
			u.usages -= 1
		var kept_sum: Array[TCGPlayerSystem.UnitInstance] = []
		for u in p.summons:
			if u.usages > 0:
				kept_sum.append(u)
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
		p.supports = kept_sup

		if s.winner != -2:
			return

	for p in s.players:
		for c in p.characters:
			remove_status(c, "Frozen")
			remove_status(c, "Petrified")
			c.statuses = TCGRoundManager.tick_statuses(c.statuses)
			TCGRoundManager.reset_round_usages(c.statuses)
		p.combat = TCGRoundManager.tick_statuses(p.combat)
		TCGRoundManager.reset_round_usages(p.combat)

	for p_idx in order:
		TCGRoundManager.draw_cards(s, p_idx, CardDataSystem.DRAW_END)

	TCGRoundManager.begin_round(s, false)


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


static func switch_cost(p: TCGPlayerSystem.PlayerState) -> CardDataSystem.CostData:
	for st in p.combat:
		if st.name == "Changing Shifts":
			return CardDataSystem.CostData.new()
	return CardDataSystem.CostData.new("", 0, 1, 0)


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
			var defn: CardDataSystem.CharData = p.characters[i].get_defn()
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
static func _pay(p: TCGPlayerSystem.PlayerState, cost: CardDataSystem.CostData, idx: PackedInt32Array) -> bool:
	var arr_idx := Array(idx)
	if not TCGDiceSystem.payment_ok(p.dice, cost, arr_idx):
		last_error = "invalid dice payment"
		return false
	arr_idx.sort()
	arr_idx.reverse()
	for i in arr_idx:
		p.dice.remove_at(int(i))
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
	var new_hand: Array[String] = []
	for i in range(p.hand.size()):
		if not uniq_set.has(i):
			new_hand.append(p.hand[i])
	p.hand = new_hand
	for c in out:
		p.deck.append(c)
	TCGRoundManager.shuffle_strings(s.rng, p.deck)
	TCGRoundManager.draw_cards(s, a.player, out.size())
	p.mull_done = true
	return true


static func _choose_active(s: TCGGameState, a: TCGGameState.ActionData) -> bool:
	var p := s.players[a.player]
	if a.index < 0 or a.index >= 3 or p.characters[a.index].defeated:
		last_error = "bad character"
		return false
	if not s.pending.is_empty():
		p.active = a.index
		s.pending.erase(a.player)
		s.add_event("switch", {"player": a.player, "char": a.index, "forced": true})
		return true
	if not p.mull_done:
		last_error = "mulligan first"
		return false
	p.chosen = a.index
	if s.players[0].chosen >= 0 and s.players[1].chosen >= 0:
		for pl in s.players:
			pl.active = pl.chosen
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
	var new_rolls := TCGDiceSystem.roll(s.rng, ids.size())
	for k in range(ids.size()):
		p.dice[int(ids[k])] = new_rolls[k]
	p.rerolls -= 1
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
	if not _pay(p, sk.cost, a.dice):
		return false
	_perform_skill(s, a.player, a.index)
	return true


static func _perform_skill(s: TCGGameState, pi: int, idx: int) -> void:
	var p := s.players[pi]
	var ch := p.get_active_char()
	var defn: CardDataSystem.CharData = ch.get_defn()
	var sk: CardDataSystem.SkillData = defn.skills[idx]
	if sk.kind == "burst":
		ch.energy -= sk.cost.energy
	else:
		ch.energy = mini(defn.max_energy, ch.energy + 1)
	s.add_event("skill", {"player": pi, "char": p.active, "skill": sk.name, "skill_kind": sk.kind})
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
	var cost := switch_cost(p)
	var shifted: bool = cost.unaligned == 0
	if not _pay(p, cost, a.dice):
		return false
	if shifted:
		_use_combat(p, "Changing Shifts")
	p.active = a.index
	s.add_event("switch", {"player": a.player, "char": a.index, "forced": false})
	if not _use_combat(p, "Leave It to Me!"):
		TCGTurnManager.end_turn(s, a.player)
	return true


static func _equip(ch: TCGPlayerSystem.CharacterInstance, cd: CardDataSystem.CardData) -> void:
	var old_name: String = str(ch.equipment.get(cd.kind, ""))
	if not old_name.is_empty():
		var old_cd: CardDataSystem.CardData = CardDataSystem.get_card_def(old_name)
		if old_cd != null and not old_cd.status.is_empty():
			remove_status(ch, old_cd.status)
	ch.equipment[cd.kind] = cd.name
	if not cd.status.is_empty():
		add_status(ch.statuses, cd.status)


static func _card(s: TCGGameState, a: TCGGameState.ActionData) -> bool:
	var p := s.players[a.player]
	if a.index < 0 or a.index >= p.hand.size():
		last_error = "bad card"
		return false
	var cd: CardDataSystem.CardData = CardDataSystem.get_card_def(p.hand[a.index])
	if cd == null or not card_targets(p, cd).has(a.target):
		last_error = "bad card target"
		return false
	if not _pay(p, cd.cost, a.dice):
		return false
	p.hand.remove_at(a.index)
	s.add_event("card", {"player": a.player, "name": cd.name})
	if cd.kind == "support":
		p.supports.append(TCGPlayerSystem.UnitInstance.new(cd.name, cd.usages))
	elif cd.kind == "weapon" or cd.kind == "artifact":
		_equip(p.characters[a.target], cd)
	elif cd.kind == "talent":
		_equip(p.characters[a.target], cd)
		_perform_skill(s, a.player, cd.skill_index)
		return true
	else:
		var ctx := TCGEffectContext.new(s, a.player)
		if not cd.play_steps.is_empty():
			ctx.execute_steps(cd.play_steps, a.target)
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
	p.hand.remove_at(a.index)
	p.dice[a.target] = el
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

	s.events = []
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


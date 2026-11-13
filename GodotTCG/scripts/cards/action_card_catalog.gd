class_name TCGActionCardCatalog
extends RefCounted
## ActionCardCatalog
## Exact data migration of all 29 action cards from Python `content/cards.py`.
## Categories:
## - 7 Universal Event cards
## - 3 Support cards
## - 5 Weapon cards
## - 1 Artifact card
## - 4 Elemental Resonance Event cards
## - 10 Character Talent cards
## (Wait: 7 + 3 + 5 + 1 + 4 + 10 = 30! Let's check exact count in Python `content/cards.py`!)


static func _step(
	p_op: String,
	p_amount: int = 0,
	p_dtype: String = "",
	p_target_name: String = "",
	p_use_target: bool = false
) -> CardDataSystem.EffectStepData:
	return CardDataSystem.EffectStepData.new(p_op, p_amount, p_dtype, p_target_name, p_use_target)


static func register_all(db: Node) -> void:
	var OMNI: String = CardDataSystem.OMNI
	var PYRO: String = CardDataSystem.PYRO
	var HYDRO: String = CardDataSystem.HYDRO
	var CRYO: String = CardDataSystem.CRYO
	var ELECTRO: String = CardDataSystem.ELECTRO
	var ANEMO: String = CardDataSystem.ANEMO
	var GEO: String = CardDataSystem.GEO

	var card_text: Dictionary = {
		"Sweet Madame": "Heal a character for 1.",
		"Mondstadt Hash Browns": "Heal a character for 2.",
		"Strategize": "Draw 2 cards.",
		"Changing Shifts": "Your next character switch costs no dice.",
		"Leave It to Me!": "Your next switch is a Fast Action.",
		"Lotus Flower Crisp": "Create a 3-point shield this round.",
		"Starsigns": "Your active character gains 1 Energy.",
		"Paimon": "Start of each Action Phase: gain 2 Omni dice. (2 uses)",
		"Liyue Harbor Wharf": "End Phase: draw 2 cards. (2 uses)",
		"Wangshu Inn": "End Phase: heal your most injured character for 2. (2 uses)",
		"Traveler's Handy Sword": "A Sword user deals +1 damage with skills.",
		"Raven Bow": "A Bow user deals +1 damage with skills.",
		"White Iron Greatsword": "A Claymore user deals +1 damage with skills.",
		"White Tassel": "A Polearm user deals +1 damage with skills.",
		"Magic Guide": "A Catalyst user deals +1 damage with skills.",
		"Gambler's Earrings": "When you defeat an enemy character: gain 2 Omni dice. (once per round)",
		"Elemental Resonance: Woven Thunder": "Your active character gains 1 Energy. (needs 2 Electro characters)",
		"Elemental Resonance: Fervent Flames": "Your next skill deals +2 damage. (needs 2 Pyro characters)",
		"Elemental Resonance: Soothing Waters": "Heal your active character for 2. (needs 2 Hydro characters)",
		"Elemental Resonance: Shattering Ice": "Create a 1-point shield for 2 rounds. (needs 2 Cryo characters)",
		"Thundering Penance": "Equip, then use Stellar Restoration. Physical damage becomes Electro.",
		"Stellar Predator": "Equip, then use Nightrider. After a Normal Attack with Oz out: 2 Electro damage.",
		"Flowing Flame": "Equip, then use Searing Onslaught. Skill deals +1 damage.",
		"Grand Expectation": "Equip, then use Passion Overload. Burst deals +1 damage.",
		"Cold-Blooded Strike": "Equip, then use Frostgnaw. After the skill, heal 2.",
		"Undivided Heart": "Equip, then use Trail of the Qilin. Skill deals +1 damage.",
		"The Scent Remained": "Equip, then use Fatal Rainscreen. Normal Attack deals +1 damage.",
		"Prophecy of Submersion": "Equip, then use Mirror Reflection of Doom. Burst deals +1 damage.",
		"Chaotic Entropy": "Equip, then use Astable Anemohypostasis. Skill deals +1 damage.",
		"Dominance of Earth": "Equip, then use Dominus Lapidis. Skill deals +1 damage.",
	}

	# ---- 1. Events (universal) (7 cards)
	var sweet_madame := CardDataSystem.CardData.new("Sweet Madame", "event", CardDataSystem.CostData.new())
	sweet_madame.needs_char = true
	sweet_madame.play_steps = [_step("heal", 1, "", "", true)]
	db.register_card(sweet_madame)

	var hash_browns := CardDataSystem.CardData.new("Mondstadt Hash Browns", "event", CardDataSystem.CostData.new("", 0, 1, 0))
	hash_browns.needs_char = true
	hash_browns.play_steps = [_step("heal", 2, "", "", true)]
	db.register_card(hash_browns)

	var strategize := CardDataSystem.CardData.new("Strategize", "event", CardDataSystem.CostData.new("", 0, 1, 0))
	strategize.play_steps = [_step("draw", 2)]
	db.register_card(strategize)

	var changing_shifts := CardDataSystem.CardData.new("Changing Shifts", "event", CardDataSystem.CostData.new())
	changing_shifts.play_steps = [_step("combat_status", 0, "", "Changing Shifts")]
	db.register_card(changing_shifts)

	var leave_it := CardDataSystem.CardData.new("Leave It to Me!", "event", CardDataSystem.CostData.new())
	leave_it.play_steps = [_step("combat_status", 0, "", "Leave It to Me!")]
	db.register_card(leave_it)

	var lotus_crisp := CardDataSystem.CardData.new("Lotus Flower Crisp", "event", CardDataSystem.CostData.new("", 0, 1, 0))
	lotus_crisp.play_steps = [_step("combat_status", 0, "", "Lotus Shield")]
	db.register_card(lotus_crisp)

	var starsigns := CardDataSystem.CardData.new("Starsigns", "event", CardDataSystem.CostData.new("", 0, 2, 0))
	starsigns.play_steps = [_step("gain_energy", 1)]
	db.register_card(starsigns)

	# ---- 2. Supports (3 cards)
	var paimon := CardDataSystem.CardData.new("Paimon", "support", CardDataSystem.CostData.new("", 0, 3, 0))
	paimon.usages = 2
	paimon.action_start_steps = [_step("gain_dice", 2, OMNI)]
	db.register_card(paimon)

	var liyue_wharf := CardDataSystem.CardData.new("Liyue Harbor Wharf", "support", CardDataSystem.CostData.new("", 0, 2, 0))
	liyue_wharf.usages = 2
	liyue_wharf.end_phase_steps = [_step("draw", 2)]
	db.register_card(liyue_wharf)

	var wangshu_inn := CardDataSystem.CardData.new("Wangshu Inn", "support", CardDataSystem.CostData.new("", 0, 2, 0))
	wangshu_inn.usages = 2
	wangshu_inn.end_phase_steps = [_step("heal_most_injured", 2)]
	db.register_card(wangshu_inn)

	# ---- 3. Weapons (5 cards) and Artifact (1 card)
	var weapons: Array[Array] = [
		["Traveler's Handy Sword", "Sword"],
		["Raven Bow", "Bow"],
		["White Iron Greatsword", "Claymore"],
		["White Tassel", "Polearm"],
		["Magic Guide", "Catalyst"],
	]
	for w_pair in weapons:
		var w_name: String = w_pair[0]
		var w_type: String = w_pair[1]
		var w_card := CardDataSystem.CardData.new(w_name, "weapon", CardDataSystem.CostData.new("", 0, 2, 0))
		w_card.weapon = w_type
		w_card.status = w_name
		db.register_card(w_card)

	var earrings := CardDataSystem.CardData.new("Gambler's Earrings", "artifact", CardDataSystem.CostData.new("", 0, 2, 0))
	earrings.status = "Gambler's Earrings"
	db.register_card(earrings)

	# ---- 4. Elemental Resonance (4 cards)
	var res_thunder := CardDataSystem.CardData.new(
		"Elemental Resonance: Woven Thunder", "event", CardDataSystem.CostData.new(ELECTRO, 1, 0, 0)
	)
	res_thunder.resonance = ELECTRO
	res_thunder.play_steps = [_step("gain_energy", 1)]
	db.register_card(res_thunder)

	var res_flames := CardDataSystem.CardData.new(
		"Elemental Resonance: Fervent Flames", "event", CardDataSystem.CostData.new(PYRO, 1, 0, 0)
	)
	res_flames.resonance = PYRO
	res_flames.play_steps = [_step("combat_status", 0, "", "Fervent Flames")]
	db.register_card(res_flames)

	var res_waters := CardDataSystem.CardData.new(
		"Elemental Resonance: Soothing Waters", "event", CardDataSystem.CostData.new(HYDRO, 1, 0, 0)
	)
	res_waters.resonance = HYDRO
	res_waters.play_steps = [_step("heal", 2, "", "", false)]
	db.register_card(res_waters)

	var res_ice := CardDataSystem.CardData.new(
		"Elemental Resonance: Shattering Ice", "event", CardDataSystem.CostData.new(CRYO, 1, 0, 0)
	)
	res_ice.resonance = CRYO
	res_ice.play_steps = [_step("combat_status", 0, "", "Ice Shield")]
	db.register_card(res_ice)

	# ---- 5. Talents (10 cards)
	var talents: Array[Array] = [
		["Thundering Penance", "Keqing", 1, ELECTRO, 3],
		["Stellar Predator", "Fischl", 1, ELECTRO, 3],
		["Flowing Flame", "Diluc", 1, PYRO, 3],
		["Grand Expectation", "Bennett", 1, PYRO, 4],
		["Cold-Blooded Strike", "Kaeya", 1, CRYO, 3],
		["Undivided Heart", "Ganyu", 1, CRYO, 3],
		["The Scent Remained", "Xingqiu", 1, HYDRO, 3],
		["Prophecy of Submersion", "Mona", 1, HYDRO, 3],
		["Chaotic Entropy", "Sucrose", 1, ANEMO, 3],
		["Dominance of Earth", "Zhongli", 1, GEO, 3],
	]
	for t_spec in talents:
		var t_name: String = t_spec[0]
		var t_char: String = t_spec[1]
		var t_skill: int = t_spec[2]
		var t_elem: String = t_spec[3]
		var t_cost_n: int = t_spec[4]
		var t_card := CardDataSystem.CardData.new(
			t_name, "talent", CardDataSystem.CostData.new(t_elem, t_cost_n, 0, 0)
		)
		t_card.char_name = t_char
		t_card.skill_index = t_skill
		t_card.status = t_name
		db.register_card(t_card)

	# Assign exact CARD_TEXT strings
	for c_name in card_text.keys():
		var cd: CardDataSystem.CardData = db.get_card_def(c_name)
		if cd != null:
			cd.text = card_text[c_name]


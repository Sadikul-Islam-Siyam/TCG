class_name TCGStatusCatalog
extends RefCounted
## StatusCatalog
## Exact data migration of all 27 statuses and 5 summons from Python `content/statuses.py`.


static func _make_status(
	p_name: String,
	p_usages: int = -1,
	p_duration: int = -1,
	p_shield: int = 0,
	p_max_shield: int = 99,
	p_reduce: int = 0,
	p_reduce_min: int = 0,
	p_per_round: int = -1,
	p_outgoing_rule: String = "",
	p_after_skill_rule: String = "",
	p_on_kill_rule: String = "",
	p_text: String = ""
) -> CardDataSystem.StatusData:
	var st := CardDataSystem.StatusData.new()
	st.name = p_name
	st.usages = p_usages
	st.duration = p_duration
	st.shield = p_shield
	st.max_shield = p_max_shield
	st.reduce = p_reduce
	st.reduce_min = p_reduce_min
	st.per_round = p_per_round
	st.outgoing_rule = p_outgoing_rule
	st.after_skill_rule = p_after_skill_rule
	st.on_kill_rule = p_on_kill_rule
	st.text = p_text
	return st


static func register_all(db: Node) -> void:
	# --- 1. Crowd Control (2)
	db.register_status(_make_status(
		"Frozen", -1, -1, 0, 99, 0, 0, -1, "", "", "",
		"Cannot act. Takes +2 from Physical or Pyro (which thaws it)."
	))
	db.register_status(_make_status(
		"Petrified", -1, -1, 0, 99, 0, 0, -1, "", "", "",
		"Cannot use skills this round."
	))

	# --- 2. Shields and Damage Reduction (combat statuses) (7)
	db.register_status(_make_status(
		"Crystallize Shield", -1, -1, 1, 2, 0, 0, -1, "", "", "",
		"Shield: absorbs 1 damage (max 2)."
	))
	db.register_status(_make_status(
		"Jade Shield", -1, -1, 1, 2, 0, 0, -1, "", "", "",
		"Shield: absorbs 1 damage (max 2)."
	))
	db.register_status(_make_status(
		"Ice Lotus", 2, -1, 0, 99, 1, 0, -1, "", "", "",
		"Reduces damage taken by 1. (2 uses)"
	))
	db.register_status(_make_status(
		"Rain Sword", 2, -1, 0, 99, 1, 3, -1, "", "", "",
		"Reduces damage of 3 or more by 1. (2 uses)"
	))
	db.register_status(_make_status(
		"Reflection", 1, -1, 0, 99, 1, 0, -1, "", "", "",
		"Reduces damage taken by 1. (1 use)"
	))
	db.register_status(_make_status(
		"Lotus Shield", -1, 1, 3, 3, 0, 0, -1, "", "", "",
		"Shield: absorbs 3 damage this round."
	))
	db.register_status(_make_status(
		"Ice Shield", -1, 2, 1, 2, 0, 0, -1, "", "", "",
		"Shield: absorbs 1 damage for 2 rounds."
	))

	# --- 3. Damage Modifiers & Action Modifiers (5)
	db.register_status(_make_status(
		"Pyro Infusion", -1, 2, 0, 99, 0, 0, -1, "pyro_infusion", "", "",
		"Physical damage becomes Pyro. (2 rounds)"
	))
	db.register_status(_make_status(
		"Inspiration Field", -1, 2, 0, 99, 0, 0, -1, "inspiration_field", "inspiration_heal", "",
		"+2 damage if attacker has 7+ HP; heals 2 at 6 HP or less. (2 rounds)"
	))
	db.register_status(_make_status(
		"Fervent Flames", 1, 2, 0, 99, 0, 0, -1, "fervent_flames", "", "",
		"Next skill deals +2 damage."
	))
	db.register_status(_make_status(
		"Changing Shifts", 1, 1, 0, 99, 0, 0, -1, "", "", "",
		"Next switch costs no dice."
	))
	db.register_status(_make_status(
		"Leave It to Me!", 1, 1, 0, 99, 0, 0, -1, "", "", "",
		"Next switch is a Fast Action."
	))

	# --- 4. Reactions to Skills (1)
	db.register_status(_make_status(
		"Rainbow Bladework", 3, -1, 0, 99, 0, 0, -1, "", "rainbow_bladework", "",
		"After a Normal Attack: 1 Hydro damage. (3 uses)"
	))

	# --- 5. Summons (5) (`content/statuses.py:77-81`)
	db.register_summon(CardDataSystem.SummonData.new("Oz", CardDataSystem.ELECTRO, 1, 2))
	db.register_summon(CardDataSystem.SummonData.new("Icicle", CardDataSystem.CRYO, 2, 3))
	db.register_summon(CardDataSystem.SummonData.new("Sacred Cryo Pearl", CardDataSystem.CRYO, 1, 2))
	db.register_summon(CardDataSystem.SummonData.new("Large Wind Spirit", CardDataSystem.ANEMO, 2, 3))
	db.register_summon(CardDataSystem.SummonData.new("Stone Stele", CardDataSystem.GEO, 1, 2))

	# --- 6. Equipment Statuses: 5 Weapons + 1 Artifact (6)
	var weapon_names: PackedStringArray = [
		"Traveler's Handy Sword",
		"Raven Bow",
		"White Iron Greatsword",
		"White Tassel",
		"Magic Guide",
	]
	for w_name in weapon_names:
		db.register_status(_make_status(
			w_name, -1, -1, 0, 99, 0, 0, -1, "bonus_any_1", "", "",
			"+1 damage on this character's skills."
		))

	db.register_status(_make_status(
		"Gambler's Earrings", 1, -1, 0, 99, 0, 0, 1, "", "", "gamblers_earrings",
		""
	))

	# --- 7. Talent Statuses (10)
	db.register_status(_make_status(
		"Thundering Penance", -1, -1, 0, 99, 0, 0, -1, "electro_infusion", "", "", ""
	))
	db.register_status(_make_status(
		"Stellar Predator", 1, -1, 0, 99, 0, 0, 1, "", "stellar_predator", "", ""
	))
	db.register_status(_make_status(
		"Flowing Flame", -1, -1, 0, 99, 0, 0, -1, "bonus_skill_1", "", "", ""
	))
	db.register_status(_make_status(
		"Grand Expectation", -1, -1, 0, 99, 0, 0, -1, "bonus_burst_1", "", "", ""
	))
	db.register_status(_make_status(
		"Cold-Blooded Strike", -1, -1, 0, 99, 0, 0, -1, "", "cold_blooded_strike", "", ""
	))
	db.register_status(_make_status(
		"Undivided Heart", -1, -1, 0, 99, 0, 0, -1, "bonus_skill_1", "", "", ""
	))
	db.register_status(_make_status(
		"The Scent Remained", -1, -1, 0, 99, 0, 0, -1, "bonus_normal_1", "", "", ""
	))
	db.register_status(_make_status(
		"Prophecy of Submersion", -1, -1, 0, 99, 0, 0, -1, "bonus_burst_1", "", "", ""
	))
	db.register_status(_make_status(
		"Chaotic Entropy", -1, -1, 0, 99, 0, 0, -1, "bonus_skill_1", "", "", ""
	))
	db.register_status(_make_status(
		"Dominance of Earth", -1, -1, 0, 99, 0, 0, -1, "bonus_skill_1", "", "", ""
	))


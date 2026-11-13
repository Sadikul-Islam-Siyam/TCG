class_name TCGCharacterCatalog
extends RefCounted
## CharacterCatalog
## Exact data migration of the 10 launch characters and their 30 skills from Python `content/characters.py`.


static func _dmg(amount: int, dtype: String) -> CardDataSystem.EffectStepData:
	return CardDataSystem.EffectStepData.new("damage", amount, dtype, "")


static func _pierce(amount: int) -> CardDataSystem.EffectStepData:
	return CardDataSystem.EffectStepData.new("piercing_others", amount, CardDataSystem.PIERCING, "")


static func _summon(summon_name: String) -> CardDataSystem.EffectStepData:
	return CardDataSystem.EffectStepData.new("summon", 0, "", summon_name)


static func _combat(status_name: String) -> CardDataSystem.EffectStepData:
	return CardDataSystem.EffectStepData.new("combat_status", 0, "", status_name)


static func _self_status(status_name: String) -> CardDataSystem.EffectStepData:
	return CardDataSystem.EffectStepData.new("char_status", 0, "", status_name)


static func _foe_status(status_name: String) -> CardDataSystem.EffectStepData:
	return CardDataSystem.EffectStepData.new("foe_char_status", 0, "", status_name)


static func _swap_foe() -> CardDataSystem.EffectStepData:
	return CardDataSystem.EffectStepData.new("force_switch_foe", 0, "", "")


static func _make_char(
	db: Node,
	p_name: String,
	p_element: String,
	p_weapon: String,
	p_max_energy: int,
	p_normal_name: String,
	p_skill_name: String,
	p_skill_cost: CardDataSystem.CostData,
	p_skill_steps: Array[CardDataSystem.EffectStepData],
	p_burst_name: String,
	p_burst_cost: CardDataSystem.CostData,
	p_burst_steps: Array[CardDataSystem.EffectStepData],
	p_normal_type: String = CardDataSystem.PHYSICAL,
	p_normal_dmg: int = 2
) -> CardDataSystem.CharData:
	var normal_steps: Array[CardDataSystem.EffectStepData] = [_dmg(p_normal_dmg, p_normal_type)]
	var normal_skill := CardDataSystem.SkillData.new(
		p_normal_name,
		"normal",
		CardDataSystem.CostData.new(p_element, 1, 2, 0),
		normal_steps
	)
	var elem_skill := CardDataSystem.SkillData.new(
		p_skill_name,
		"skill",
		p_skill_cost,
		p_skill_steps
	)
	var burst_skill := CardDataSystem.SkillData.new(
		p_burst_name,
		"burst",
		p_burst_cost,
		p_burst_steps
	)
	var skills: Array[CardDataSystem.SkillData] = [normal_skill, elem_skill, burst_skill]
	return db.register_char(CardDataSystem.CharData.new(p_name, p_element, p_weapon, p_max_energy, skills, 10))


static func register_all(db: Node) -> void:
	var ELECTRO: String = CardDataSystem.ELECTRO
	var PYRO: String = CardDataSystem.PYRO
	var CRYO: String = CardDataSystem.CRYO
	var HYDRO: String = CardDataSystem.HYDRO
	var ANEMO: String = CardDataSystem.ANEMO
	var GEO: String = CardDataSystem.GEO

	# 1. Keqing
	_make_char(
		db, "Keqing", ELECTRO, "Sword", 3,
		"Yunlai Swordsmanship",
		"Stellar Restoration", CardDataSystem.CostData.new(ELECTRO, 3, 0, 0), [_dmg(3, ELECTRO)],
		"Starward Sword", CardDataSystem.CostData.new(ELECTRO, 3, 0, 3), [_dmg(4, ELECTRO), _pierce(3)]
	)

	# 2. Fischl
	_make_char(
		db, "Fischl", ELECTRO, "Bow", 3,
		"Bolts of Downfall",
		"Nightrider", CardDataSystem.CostData.new(ELECTRO, 3, 0, 0), [_dmg(1, ELECTRO), _summon("Oz")],
		"Midnight Phantasmagoria", CardDataSystem.CostData.new(ELECTRO, 3, 0, 3), [_dmg(4, ELECTRO), _pierce(2)]
	)

	# 3. Diluc
	_make_char(
		db, "Diluc", PYRO, "Claymore", 3,
		"Tempered Sword",
		"Searing Onslaught", CardDataSystem.CostData.new(PYRO, 3, 0, 0), [_dmg(3, PYRO)],
		"Dawn", CardDataSystem.CostData.new(PYRO, 4, 0, 3), [_dmg(8, PYRO), _self_status("Pyro Infusion")]
	)

	# 4. Bennett
	_make_char(
		db, "Bennett", PYRO, "Sword", 2,
		"Strike of Fortune",
		"Passion Overload", CardDataSystem.CostData.new(PYRO, 3, 0, 0), [_dmg(3, PYRO)],
		"Fantastic Voyage", CardDataSystem.CostData.new(PYRO, 4, 0, 2), [_dmg(2, PYRO), _combat("Inspiration Field")]
	)

	# 5. Kaeya
	_make_char(
		db, "Kaeya", CRYO, "Sword", 2,
		"Ceremonial Bladework",
		"Frostgnaw", CardDataSystem.CostData.new(CRYO, 3, 0, 0), [_dmg(3, CRYO)],
		"Glacial Waltz", CardDataSystem.CostData.new(CRYO, 3, 0, 2), [_dmg(1, CRYO), _summon("Icicle")]
	)

	# 6. Ganyu
	_make_char(
		db, "Ganyu", CRYO, "Bow", 2,
		"Liutian Archery",
		"Trail of the Qilin", CardDataSystem.CostData.new(CRYO, 3, 0, 0), [_dmg(1, CRYO), _combat("Ice Lotus")],
		"Celestial Shower", CardDataSystem.CostData.new(CRYO, 3, 0, 2), [_dmg(2, CRYO), _pierce(2), _summon("Sacred Cryo Pearl")]
	)

	# 7. Xingqiu
	_make_char(
		db, "Xingqiu", HYDRO, "Sword", 2,
		"Guhua Style",
		"Fatal Rainscreen", CardDataSystem.CostData.new(HYDRO, 3, 0, 0), [_dmg(2, HYDRO), _combat("Rain Sword")],
		"Raincutter", CardDataSystem.CostData.new(HYDRO, 3, 0, 2), [_dmg(1, HYDRO), _combat("Rainbow Bladework")]
	)

	# 8. Mona
	_make_char(
		db, "Mona", HYDRO, "Catalyst", 3,
		"Ripple of Fate",
		"Mirror Reflection of Doom", CardDataSystem.CostData.new(HYDRO, 3, 0, 0), [_dmg(1, HYDRO), _combat("Reflection")],
		"Stellaris Phantasm", CardDataSystem.CostData.new(HYDRO, 3, 0, 3), [_dmg(4, HYDRO)],
		HYDRO, 1
	)

	# 9. Sucrose
	_make_char(
		db, "Sucrose", ANEMO, "Catalyst", 2,
		"Wind Spirit Creation",
		"Astable Anemohypostasis", CardDataSystem.CostData.new(ANEMO, 3, 0, 0), [_dmg(3, ANEMO), _swap_foe()],
		"Forbidden Creation", CardDataSystem.CostData.new(ANEMO, 3, 0, 2), [_dmg(1, ANEMO), _summon("Large Wind Spirit")],
		ANEMO, 1
	)

	# 10. Zhongli
	_make_char(
		db, "Zhongli", GEO, "Polearm", 3,
		"Rain of Stone",
		"Dominus Lapidis", CardDataSystem.CostData.new(GEO, 3, 0, 0), [_dmg(1, GEO), _summon("Stone Stele"), _combat("Jade Shield")],
		"Planet Befall", CardDataSystem.CostData.new(GEO, 3, 0, 3), [_dmg(3, GEO), _foe_status("Petrified")]
	)


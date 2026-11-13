class_name TCGDataValidator
extends RefCounted
## DataValidator
## Validates all migrated static card/character/status/summon/preset data in `CardDataSystem`
## without silently altering any values. Reports any missing or invalid fields.


static func validate_all(db: Node) -> Array[String]:
	var errors: Array[String] = []

	# 1. Validate Element Set (6 elements, Dendro excluded)
	var expected_elements: PackedStringArray = ["Cryo", "Hydro", "Pyro", "Electro", "Anemo", "Geo"]
	if db.ELEMENTS != expected_elements:
		errors.append("Element set mismatch: expected %s, got %s" % [str(expected_elements), str(db.ELEMENTS)])
	if db.ELEMENTS.has("Dendro"):
		errors.append("Forbidden element 'Dendro' found in ELEMENTS")

	# 2. Validate Counts against Python source of truth
	if db.char_defs.size() != 10:
		errors.append("Expected 10 character definitions, got %d" % db.char_defs.size())
	if db.card_defs.size() != 30:
		errors.append("Expected 30 action card definitions, got %d" % db.card_defs.size())
	if db.status_defs.size() != 31:
		errors.append("Expected 31 status definitions, got %d" % db.status_defs.size())
	if db.summon_defs.size() != 5:
		errors.append("Expected 5 summon definitions, got %d" % db.summon_defs.size())
	if db.preset_defs.size() != 6:
		errors.append("Expected 6 preset deck definitions, got %d" % db.preset_defs.size())

	# 3. Validate Character Definitions & Skills
	for char_name in db.char_defs.keys():
		var c: CardDataSystem.CharData = db.char_defs[char_name]
		if c.name.is_empty() or c.name != char_name:
			errors.append("Character key/name mismatch: '%s' vs '%s'" % [char_name, c.name])
		if not db.ELEMENTS.has(c.element):
			errors.append("Character '%s' has invalid element '%s'" % [c.name, c.element])
		if not db.WEAPON_TYPES.has(c.weapon):
			errors.append("Character '%s' has invalid weapon '%s'" % [c.name, c.weapon])
		if c.hp <= 0:
			errors.append("Character '%s' has non-positive HP: %d" % [c.name, c.hp])
		if c.max_energy <= 0:
			errors.append("Character '%s' has non-positive max_energy: %d" % [c.name, c.max_energy])
		if c.skills.size() != 3:
			errors.append("Character '%s' must have 3 skills, found %d" % [c.name, c.skills.size()])
		for sk in c.skills:
			if sk.name.is_empty():
				errors.append("Character '%s' has a skill with empty name" % c.name)
			if not db.SKILL_KINDS.has(sk.kind):
				errors.append("Skill '%s' on '%s' has invalid kind '%s'" % [sk.name, c.name, sk.kind])
			if sk.cost == null:
				errors.append("Skill '%s' on '%s' is missing CostData" % [sk.name, c.name])
			elif not sk.cost.element.is_empty() and not db.ELEMENTS.has(sk.cost.element):
				errors.append("Skill '%s' on '%s' has invalid cost element '%s'" % [sk.name, c.name, sk.cost.element])
			if sk.desc.is_empty():
				errors.append("Skill '%s' on '%s' has empty description" % [sk.name, c.name])
			for step in sk.steps:
				if step.op == "summon" and not db.summon_defs.has(step.target_name):
					errors.append("Skill '%s' references unknown summon '%s'" % [sk.name, step.target_name])
				elif step.op in ["combat_status", "char_status", "foe_char_status"] and not db.status_defs.has(step.target_name):
					errors.append("Skill '%s' references unknown status '%s'" % [sk.name, step.target_name])

	# 4. Validate Action Card Definitions
	for card_name in db.card_defs.keys():
		var cd: CardDataSystem.CardData = db.card_defs[card_name]
		if cd.name.is_empty() or cd.name != card_name:
			errors.append("Card key/name mismatch: '%s' vs '%s'" % [card_name, cd.name])
		if not db.CARD_KINDS.has(cd.kind):
			errors.append("Card '%s' has invalid kind '%s'" % [cd.name, cd.kind])
		if cd.cost == null:
			errors.append("Card '%s' is missing CostData" % cd.name)
		elif not cd.cost.element.is_empty() and not db.ELEMENTS.has(cd.cost.element):
			errors.append("Card '%s' has invalid cost element '%s'" % [cd.name, cd.cost.element])
		if cd.text.is_empty():
			errors.append("Card '%s' is missing description text" % cd.name)
		if cd.kind == "talent":
			if not db.char_defs.has(cd.char_name):
				errors.append("Talent card '%s' references unknown character '%s'" % [cd.name, cd.char_name])
			if not db.status_defs.has(cd.status):
				errors.append("Talent card '%s' references unknown status '%s'" % [cd.name, cd.status])
		elif cd.kind == "weapon":
			if not db.WEAPON_TYPES.has(cd.weapon):
				errors.append("Weapon card '%s' has invalid weapon type '%s'" % [cd.name, cd.weapon])
			if not db.status_defs.has(cd.status):
				errors.append("Weapon card '%s' references unknown status '%s'" % [cd.name, cd.status])
		elif cd.kind == "artifact":
			if not db.status_defs.has(cd.status):
				errors.append("Artifact card '%s' references unknown status '%s'" % [cd.name, cd.status])
		elif cd.kind == "support":
			if cd.usages <= 0:
				errors.append("Support card '%s' must have positive usages, got %d" % [cd.name, cd.usages])
		if not cd.resonance.is_empty() and not db.ELEMENTS.has(cd.resonance):
			errors.append("Resonance card '%s' has invalid element '%s'" % [cd.name, cd.resonance])

	# 5. Validate Summons
	for sum_name in db.summon_defs.keys():
		var sd: CardDataSystem.SummonData = db.summon_defs[sum_name]
		if not db.ELEMENTS.has(sd.element):
			errors.append("Summon '%s' has invalid element '%s'" % [sd.name, sd.element])
		if sd.damage <= 0 or sd.usages <= 0:
			errors.append("Summon '%s' has invalid damage/usages (%d, %d)" % [sd.name, sd.damage, sd.usages])

	# 6. Validate Presets
	for preset_name in db.preset_defs.keys():
		var chars: PackedStringArray = db.preset_defs[preset_name]
		if chars.size() != 3:
			errors.append("Preset '%s' must have 3 characters, got %d" % [preset_name, chars.size()])
		for ch_name in chars:
			if not db.char_defs.has(ch_name):
				errors.append("Preset '%s' references unknown character '%s'" % [preset_name, ch_name])

	return errors


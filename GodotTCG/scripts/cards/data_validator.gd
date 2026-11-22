class_name TCGDataValidator
extends RefCounted
## DataValidator
## Validates all migrated static card/character/status/summon/preset data in `CardDataSystem`
## without silently altering any values. Reports any missing or invalid fields.


const VALID_OPS: PackedStringArray = [
	"damage", "piercing_others", "summon", "combat_status", "char_status",
	"foe_char_status", "force_switch_foe", "heal", "heal_most_injured",
	"heal_all", "heal_dual", "clear_self_aura", "reroll_off_element",
	"swap_cards", "gain_active_dice", "convert_to_omni",
	"draw", "gain_energy", "gain_dice",
]
const POSITIVE_AMOUNT_OPS: PackedStringArray = [
	"damage", "piercing_others", "heal", "heal_most_injured", "heal_all", "heal_dual",
	"swap_cards", "gain_active_dice", "convert_to_omni", "draw", "gain_energy", "gain_dice",
]


static func _validate_cost(db: Node, owner_label: String, cost: CardDataSystem.CostData, errors: Array[String]) -> void:
	if cost == null:
		errors.append("%s is missing CostData" % owner_label)
		return
	if cost.n < 0 or cost.unaligned < 0 or cost.energy < 0:
		errors.append("%s has negative cost value (%d, %d, %d)" % [owner_label, cost.n, cost.unaligned, cost.energy])
	if not cost.element.is_empty() and not db.ELEMENTS.has(cost.element):
		errors.append("%s has invalid cost element '%s'" % [owner_label, cost.element])


static func _validate_steps(db: Node, owner_label: String, steps: Array[CardDataSystem.EffectStepData], errors: Array[String]) -> void:
	for step in steps:
		if not VALID_OPS.has(step.op):
			errors.append("%s has unknown step op '%s'" % [owner_label, step.op])
			continue
		if POSITIVE_AMOUNT_OPS.has(step.op) and step.amount <= 0:
			errors.append("%s step '%s' must have positive amount, got %d" % [owner_label, step.op, step.amount])
		if step.op == "damage":
			var valid_dmg: bool = db.ELEMENTS.has(step.dtype) or step.dtype == db.PHYSICAL or step.dtype == db.PIERCING
			if not valid_dmg:
				errors.append("%s damage step has invalid element '%s'" % [owner_label, step.dtype])
		elif step.op == "gain_dice":
			if not step.dtype.is_empty() and step.dtype != db.OMNI and not db.ELEMENTS.has(step.dtype):
				errors.append("%s gain_dice step has invalid element '%s'" % [owner_label, step.dtype])
		elif step.op == "summon" and not db.summon_defs.has(step.target_name):
			errors.append("%s references unknown summon '%s'" % [owner_label, step.target_name])
		elif step.op in ["combat_status", "char_status", "foe_char_status"] and not db.status_defs.has(step.target_name):
			errors.append("%s references unknown status '%s'" % [owner_label, step.target_name])


static func validate_all(db: Node) -> Array[String]:
	var errors: Array[String] = []

	# 1. Validate Element Set (6 elements, Dendro excluded)
	var expected_elements: PackedStringArray = ["Cryo", "Hydro", "Pyro", "Electro", "Anemo", "Geo"]
	if db.ELEMENTS != expected_elements:
		errors.append("Element set mismatch: expected %s, got %s" % [str(expected_elements), str(db.ELEMENTS)])
	if db.ELEMENTS.has("Dendro"):
		errors.append("Forbidden element 'Dendro' found in ELEMENTS")

	# 2. Validate minimum playable pool (author-customizable via JSON)
	if db.char_defs.size() < 3:
		errors.append("Expected at least 3 character definitions, got %d" % db.char_defs.size())
	if db.card_defs.size() * CardDataSystem.MAX_COPIES < CardDataSystem.DECK_SIZE:
		errors.append("Need at least %d card copies (%d cards * %d max copies) for a %d-card deck" % [
			CardDataSystem.DECK_SIZE, db.card_defs.size(), CardDataSystem.MAX_COPIES, CardDataSystem.DECK_SIZE
		])
	if db.preset_defs.is_empty():
		errors.append("Expected at least 1 preset deck definition")

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
		var seen_kinds: Dictionary = {}
		for sk in c.skills:
			var sk_label := "Skill '%s' on '%s'" % [sk.name, c.name]
			if sk.name.is_empty():
				errors.append("Character '%s' has a skill with empty name" % c.name)
			if not db.SKILL_KINDS.has(sk.kind):
				errors.append("%s has invalid kind '%s'" % [sk_label, sk.kind])
			else:
				seen_kinds[sk.kind] = true
			_validate_cost(db, sk_label, sk.cost, errors)
			if sk.desc.is_empty():
				errors.append("%s has empty description" % sk_label)
			_validate_steps(db, sk_label, sk.steps, errors)
		if c.skills.size() == 3 and seen_kinds.size() != 3:
			errors.append("Character '%s' must have one each of normal, skill, and burst" % c.name)

	# 4. Validate Action Card Definitions
	for card_name in db.card_defs.keys():
		var cd: CardDataSystem.CardData = db.card_defs[card_name]
		var cd_label := "Card '%s'" % cd.name
		if cd.name.is_empty() or cd.name != card_name:
			errors.append("Card key/name mismatch: '%s' vs '%s'" % [card_name, cd.name])
		if not db.CARD_KINDS.has(cd.kind):
			errors.append("%s has invalid kind '%s'" % [cd_label, cd.kind])
		if not cd.role.is_empty() and not cd.role in ["equipment", "utility", "heal", "buff"]:
			errors.append("%s has invalid role '%s' (expected 'equipment' or 'utility')" % [cd_label, cd.role])
		_validate_cost(db, cd_label, cd.cost, errors)
		if cd.text.is_empty():
			errors.append("%s is missing description text" % cd_label)
		if cd.kind == "event" and cd.play_steps.is_empty():
			errors.append("%s has no effect steps" % cd_label)
		_validate_steps(db, cd_label, cd.play_steps, errors)
		_validate_steps(db, cd_label, cd.action_start_steps, errors)
		_validate_steps(db, cd_label, cd.end_phase_steps, errors)
		if cd.kind == "weapon":
			if not cd.char_name.is_empty() and not db.char_defs.has(cd.char_name):
				errors.append("Equipment %s references unknown character '%s'" % [cd_label, cd.char_name])
			if not cd.status.is_empty() and not db.status_defs.has(cd.status):
				errors.append("Equipment %s references unknown status '%s'" % [cd_label, cd.status])
		if cd.kind == "talent":
			if not db.char_defs.has(cd.char_name):
				errors.append("Talent %s references unknown character '%s'" % [cd_label, cd.char_name])
			if not db.status_defs.has(cd.status):
				errors.append("Talent %s references unknown status '%s'" % [cd_label, cd.status])
		elif cd.kind == "support":
			if cd.usages <= 0:
				errors.append("Support %s must have positive usages, got %d" % [cd_label, cd.usages])
		if not cd.resonance.is_empty() and not db.ELEMENTS.has(cd.resonance):
			errors.append("Resonance %s has invalid element '%s'" % [cd_label, cd.resonance])

	# 5. Validate Summons (if any exist)
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


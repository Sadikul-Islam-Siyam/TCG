extends Node
## CardDataSystem (Autoload Singleton)
## Data-driven schema and static content registry for Genius Invokation TCG.
## Strictly migrated from Python `engine/core.py`, `engine/registry.py`,
## `content/characters.py`, `content/cards.py`, `content/statuses.py`, and `content/presets.py`.
## Contains NO UI logic and NO combat execution logic.

# ------------------------------------------------------------------------------
# 1. Elements, Damage Types, Dice & Deck Constants (`engine/core.py`, `engine/deck.py`)
# ------------------------------------------------------------------------------
const CRYO: String = "Cryo"
const HYDRO: String = "Hydro"
const PYRO: String = "Pyro"
const ELECTRO: String = "Electro"
const ANEMO: String = "Anemo"
const GEO: String = "Geo"

## Exact 6-element set from Python `engine/core.py` (Dendro intentionally excluded).
const ELEMENTS: PackedStringArray = [CRYO, HYDRO, PYRO, ELECTRO, ANEMO, GEO]
## Only Cryo, Hydro, Pyro, Electro leave a persistent elemental aura.
const AURA_ELEMENTS: PackedStringArray = [CRYO, HYDRO, PYRO, ELECTRO]

const OMNI: String = "Omni"
const PHYSICAL: String = "Physical"
const PIERCING: String = "Piercing"

const WEAPON_TYPES: PackedStringArray = ["Sword", "Bow", "Claymore", "Polearm", "Catalyst"]
const SKILL_KINDS: PackedStringArray = ["normal", "skill", "burst"]
const CARD_KINDS: PackedStringArray = ["event", "support", "weapon", "artifact", "talent"]

const DICE_FACES: PackedStringArray = [CRYO, HYDRO, PYRO, ELECTRO, ANEMO, GEO, OMNI]
## Omni keeps 1/8 chance; the 6 elements share the remaining 7/8 equally (7/48 each).
const DICE_WEIGHTS: Array[float] = [
	7.0 / 48.0,
	7.0 / 48.0,
	7.0 / 48.0,
	7.0 / 48.0,
	7.0 / 48.0,
	7.0 / 48.0,
	1.0 / 8.0,
]

const DICE_PER_ROUND: int = 8
const MAX_DICE: int = 16
const MAX_HAND: int = 10
const MAX_SUMMONS: int = 0
const MAX_SUPPORTS: int = 0
const HAND_START: int = 5
const DRAW_END: int = 2
const DECK_SIZE: int = 12
const MAX_COPIES: int = 3

## Reaction definitions from `engine/rules.py:REACTIONS` + Anemo/Geo reactions
const REACTION_DEFS: Array[Dictionary] = [
	{"elements": [HYDRO, PYRO], "name": "Vaporize", "bonus": 1, "effect": "none"},
	{"elements": [CRYO, PYRO], "name": "Melt", "bonus": 2, "effect": "none"},
	{"elements": [PYRO, ELECTRO], "name": "Overloaded", "bonus": 2, "effect": "force_switch_active"},
	{"elements": [CRYO, ELECTRO], "name": "Superconduct", "bonus": 1, "effect": "pierce_others_1"},
	{"elements": [HYDRO, ELECTRO], "name": "Electro-Charged", "bonus": 1, "effect": "pierce_others_1"},
	{"elements": [CRYO, HYDRO], "name": "Frozen", "bonus": 1, "effect": "apply_frozen"},
	{"elements": [ANEMO], "name": "Swirl", "bonus": 0, "effect": "swirl_1_to_others"},
	{"elements": [GEO], "name": "Crystallize", "bonus": 1, "effect": "grant_crystallize_shield"},
]

# ------------------------------------------------------------------------------
# 2. Data Resource Classes (`Resource` subclasses)
# ------------------------------------------------------------------------------

class CostData extends Resource:
	## Represents dice and energy cost (`engine/core.py:Cost`).
	@export var element: String = ""        # "" corresponds to Python `None`
	@export var n: int = 0                  # Aligned element dice count (Omni also satisfies)
	@export var unaligned: int = 0          # Any-element dice count
	@export var energy: int = 0             # Required character energy (for bursts)

	func _init(
		p_element: String = "",
		p_n: int = 0,
		p_unaligned: int = 0,
		p_energy: int = 0
	) -> void:
		element = p_element
		n = p_n
		unaligned = p_unaligned
		energy = p_energy

	func total_dice() -> int:
		return n + unaligned


class EffectStepData extends Resource:
	## Declarative representation of a single effect operation in `content/characters.py` or `content/cards.py`.
	## Op types:
	## - "damage": amount (int), dtype (String)
	## - "piercing_others": amount (int)
	## - "summon": target_name (String)
	## - "combat_status": target_name (String)
	## - "char_status": target_name (String)
	## - "foe_char_status": target_name (String)
	## - "force_switch_foe": (no args)
	## - "heal": amount (int), use_target (bool)
	## - "heal_most_injured": amount (int)
	## - "draw": amount (int)
	## - "gain_energy": amount (int)
	## - "gain_dice": amount (int), dtype (String)
	@export var op: String = ""
	@export var amount: int = 0
	@export var dtype: String = ""
	@export var target_name: String = ""
	@export var use_target: bool = false

	func _init(
		p_op: String = "",
		p_amount: int = 0,
		p_dtype: String = "",
		p_target_name: String = "",
		p_use_target: bool = false
	) -> void:
		op = p_op
		amount = p_amount
		dtype = p_dtype
		target_name = p_target_name
		use_target = p_use_target


class SkillData extends Resource:
	## Represents a character skill (`engine/registry.py:SkillDef`).
	@export var name: String = ""
	@export var kind: String = "normal"     # "normal" | "skill" | "burst"
	@export var cost: CostData
	@export var steps: Array[EffectStepData] = []
	@export var desc: String = ""
	var effect: Callable = Callable()

	func _init(
		p_name: String = "",
		p_kind: String = "normal",
		p_cost: CostData = null,
		p_steps: Array[EffectStepData] = [],
		p_desc: String = ""
	) -> void:
		name = p_name
		kind = p_kind
		cost = p_cost if p_cost != null else CostData.new()
		steps = p_steps
		desc = p_desc if not p_desc.is_empty() else CardDataSystem.describe_skill_steps(p_steps)


class CharData extends Resource:
	## Represents a playable character card (`engine/registry.py:CharDef`).
	@export var name: String = ""
	@export var element: String = ""
	@export var weapon: String = ""
	@export var max_energy: int = 3
	@export var hp: int = 10
	@export var skills: Array[SkillData] = []

	func _init(
		p_name: String = "",
		p_element: String = "",
		p_weapon: String = "",
		p_max_energy: int = 3,
		p_skills: Array[SkillData] = [],
		p_hp: int = 10
	) -> void:
		name = p_name
		element = p_element
		weapon = p_weapon
		max_energy = p_max_energy
		skills = p_skills
		hp = p_hp


class StatusData extends Resource:
	## Represents a character or team combat status (`engine/registry.py:StatusDef`).
	## Note: -1 for usages, duration, or per_round corresponds to Python `None`.
	@export var name: String = ""
	@export var usages: int = -1
	@export var duration: int = -1
	@export var shield: int = 0
	@export var max_shield: int = 99
	@export var reduce: int = 0
	@export var reduce_min: int = 0
	@export var text: String = ""
	@export var per_round: int = -1
	# Data-driven hook descriptors matching `content/statuses.py` callbacks:
	@export var outgoing_rule: String = ""      # e.g. "pyro_infusion", "electro_infusion", "inspiration_field", "fervent_flames", "bonus_any_1", "bonus_skill_1", "bonus_burst_1", "bonus_normal_1"
	@export var after_skill_rule: String = ""   # e.g. "inspiration_heal", "rainbow_bladework", "stellar_predator", "cold_blooded_strike"
	@export var on_kill_rule: String = ""       # e.g. "gamblers_earrings"
	var outgoing: Callable = Callable()
	var after_skill: Callable = Callable()
	var on_kill: Callable = Callable()


class SummonData extends Resource:
	## Represents a board summon (`engine/registry.py:SummonDef`).
	@export var name: String = ""
	@export var element: String = ""
	@export var damage: int = 1
	@export var usages: int = 2

	func _init(
		p_name: String = "",
		p_element: String = "",
		p_damage: int = 1,
		p_usages: int = 2
	) -> void:
		name = p_name
		element = p_element
		damage = p_damage
		usages = p_usages


class CardData extends Resource:
	## Represents an action card definition (`engine/registry.py:CardDef`).
	@export var name: String = ""
	@export var kind: String = "event"          # "event" | "support" | "weapon" | "artifact" | "talent"
	@export var role: String = ""               # Simple category tag: "heal" | "buff"
	@export var cost: CostData
	@export var needs_char: bool = false
	@export var usages: int = -1                # -1 means None
	@export var char_name: String = ""          # Talent: required character name (`char` in Python)
	@export var skill_index: int = 1            # Talent: skill index used immediately (`skill` in Python)
	@export var weapon: String = ""             # Weapon: required weapon type
	@export var status: String = ""             # Equipment: status granted while equipped
	@export var resonance: String = ""          # Elemental resonance: needs 2 characters of this element
	@export var text: String = ""               # Exact effect text from `CARD_TEXT`
	@export var play_steps: Array[EffectStepData] = []
	@export var action_start_steps: Array[EffectStepData] = []
	@export var end_phase_steps: Array[EffectStepData] = []
	var play: Callable = Callable()
	var action_start: Callable = Callable()
	var end_phase: Callable = Callable()

	func _init(
		p_name: String = "",
		p_kind: String = "event",
		p_cost: CostData = null
	) -> void:
		name = p_name
		kind = p_kind
		cost = p_cost if p_cost != null else CostData.new()


# ------------------------------------------------------------------------------
# 3. Skill Text Recorder (exact port of `content/characters.py:_Recorder`)
# ------------------------------------------------------------------------------
static func describe_skill_steps(steps: Array[EffectStepData]) -> String:
	## Produces the exact human-readable skill description generated by Python `_Recorder`.
	var parts: PackedStringArray = []
	for st in steps:
		match st.op:
			"damage":
				parts.append("Deal %d %s DMG." % [st.amount, st.dtype])
			"piercing_others":
				parts.append("%d Piercing DMG to the other enemy characters." % st.amount)
			"summon":
				parts.append("Summon %s." % st.target_name)
			"combat_status":
				parts.append("Create %s." % st.target_name)
			"char_status":
				parts.append("Gain %s." % st.target_name)
			"foe_char_status":
				parts.append("Target gains %s." % st.target_name)
			"force_switch_foe":
				parts.append("The enemy must switch character.")
			"heal":
				parts.append("Heal %d HP." % st.amount)
			"heal_most_injured":
				parts.append("Heal most injured ally for %d HP." % st.amount)
			"gain_energy":
				parts.append("Gain %d Energy." % st.amount)
			"draw":
				parts.append("Draw %d card(s)." % st.amount)
			"gain_dice":
				parts.append("Gain %d %s die/dice." % [st.amount, st.dtype if not st.dtype.is_empty() else "Omni"])
	return " ".join(parts)


# ------------------------------------------------------------------------------
# 4. Global Registries & Preset Data
# ------------------------------------------------------------------------------
var char_defs: Dictionary = {}       # String -> CharData
var status_defs: Dictionary = {}     # String -> StatusData
var summon_defs: Dictionary = {}     # String -> SummonData
var card_defs: Dictionary = {}       # String -> CardData
var roster: PackedStringArray = []

var preset_defs: Dictionary = {}     # preset_name -> PackedStringArray (3 character names)
var base_priorities: Dictionary = {} # card_name -> int priority
var talent_boost: int = 10
var weapon_boost: int = 6
var resonance_boost: int = 7


func _ready() -> void:
	load_all_content()


func load_json_dict(res_path: String) -> Dictionary:
	## Loads and parses a JSON dictionary file from `res_path`, returning `{}` on failure.
	if not FileAccess.file_exists(res_path):
		push_warning("CardDataSystem: missing data file '%s'" % res_path)
		return {}
	var raw_text: String = FileAccess.get_file_as_string(res_path)
	var parsed = JSON.parse_string(raw_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("CardDataSystem: invalid JSON object in '%s'" % res_path)
		return {}
	return parsed


func parse_cost(d: Dictionary) -> CostData:
	return CostData.new(
		str(d.get("element", "")),
		int(d.get("n", 0)),
		int(d.get("unaligned", 0)),
		int(d.get("energy", 0))
	)


func parse_steps(arr: Array, default_heal_target: bool = false) -> Array[EffectStepData]:
	var out: Array[EffectStepData] = []
	for item in arr:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var sd: Dictionary = item
		var op_str: String = str(sd.get("op", ""))
		var dtype_str: String = str(sd.get("dtype", sd.get("element", "")))
		var target_str: String = str(sd.get("target_name", sd.get("status", "")))
		var step_use_target: bool = bool(sd.get("use_target", default_heal_target and op_str == "heal"))
		out.append(EffectStepData.new(
			op_str,
			int(sd.get("amount", 0)),
			dtype_str,
			target_str,
			step_use_target
		))
	return out


func infer_card_role(cd: CardData) -> String:
	if not cd.role.is_empty():
		return cd.role
	for st in cd.play_steps:
		if st.op == "heal" or st.op == "heal_most_injured":
			return "heal"
	return "buff"


func load_all_content() -> void:
	if not char_defs.is_empty():
		return
	var StatusCatalog := preload("res://scripts/cards/status_catalog.gd")
	var CharacterCatalog := preload("res://scripts/cards/character_catalog.gd")
	var ActionCardCatalog := preload("res://scripts/cards/action_card_catalog.gd")
	var PresetCatalog := preload("res://scripts/cards/preset_catalog.gd")

	StatusCatalog.register_all(self)
	CharacterCatalog.register_all(self)
	ActionCardCatalog.register_all(self)
	PresetCatalog.register_all(self)


func register_char(def: CharData) -> CharData:
	char_defs[def.name] = def
	if not roster.has(def.name):
		roster.append(def.name)
	return def


func register_status(def: StatusData) -> StatusData:
	status_defs[def.name] = def
	return def


func register_summon(def: SummonData) -> SummonData:
	summon_defs[def.name] = def
	return def


func register_card(def: CardData) -> CardData:
	card_defs[def.name] = def
	return def


func get_char_def(char_name: String) -> CharData:
	return char_defs.get(char_name, null)


func get_status_def(status_name: String) -> StatusData:
	return status_defs.get(status_name, null)


func get_summon_def(summon_name: String) -> SummonData:
	return summon_defs.get(summon_name, null)


func get_card_def(card_name: String) -> CardData:
	return card_defs.get(card_name, null)


func get_card_priorities() -> Dictionary:
	var pr := base_priorities.duplicate()
	for n in card_defs.keys():
		if not pr.has(n):
			pr[n] = 2
	return pr


func starter_deck() -> Array[String]:
	load_all_content()
	var out: Array[String] = []
	var names: Array = card_defs.keys()
	names.sort()
	for cname in names:
		var cd: CardData = card_defs[cname]
		if is_card_allowed_in_deck(cd, []):
			for _c in range(MAX_COPIES):
				out.append(str(cname))
				if out.size() >= DECK_SIZE:
					return out
	return out


func is_card_allowed_in_deck(cd: CardData, chars: Array) -> bool:
	## Exact port of `engine/deck.py:card_allowed(cd, chars)`.
	if cd == null:
		return false
	if cd.kind == "talent":
		return chars.has(cd.char_name)
	if cd.kind == "weapon":
		for c_name in chars:
			var c_def: CharData = get_char_def(str(c_name))
			if c_def != null and c_def.weapon == cd.weapon:
				return true
		return false
	if not cd.resonance.is_empty():
		var count: int = 0
		for c_name in chars:
			var c_def: CharData = get_char_def(str(c_name))
			if c_def != null and c_def.element == cd.resonance:
				count += 1
		return count >= 2
	return true

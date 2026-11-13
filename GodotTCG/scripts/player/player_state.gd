class_name TCGPlayerSystem
extends RefCounted
## PlayerSystem
## Translates the mutable runtime entity classes from Python `engine/model.py`:
## `Status`, `Unit`, `Character`, and `Player`.
## Every class provides a fast `.clone()` method for AI lookahead and tree search.


class StatusInstance extends RefCounted:
	## Runtime status attached to a character or a player's combat zone (`engine/model.py:Status`).
	## Note: -1 for usages or duration means None.
	var name: String
	var usages: int
	var duration: int
	var shield: int

	func _init(
		p_name: String,
		p_usages: int = -1,
		p_duration: int = -1,
		p_shield: int = 0
	) -> void:
		name = p_name
		usages = p_usages
		duration = p_duration
		shield = p_shield

	func clone() -> StatusInstance:
		return StatusInstance.new(name, usages, duration, shield)


class UnitInstance extends RefCounted:
	## A summon or a support card active on the board (`engine/model.py:Unit`).
	var name: String
	var usages: int # -1 means None

	func _init(p_name: String, p_usages: int = -1) -> void:
		name = p_name
		usages = p_usages

	func clone() -> UnitInstance:
		return UnitInstance.new(name, usages)


class CharacterInstance extends RefCounted:
	## Runtime state of one of a player's 3 characters (`engine/model.py:Character`).
	var name: String
	var hp: int
	var energy: int
	var aura: String = ""                 # Empty string means None
	var statuses: Array[StatusInstance] = []
	var defeated: bool = false
	var equipment: Dictionary = {}        # slot ("weapon"|"artifact"|"talent") -> card_name

	func _init(p_name: String = "", p_max_hp: int = 10, p_energy: int = 0) -> void:
		name = p_name
		hp = p_max_hp
		energy = p_energy
		aura = ""
		statuses = []
		defeated = false
		equipment = {}

	func get_defn():
		return CardDataSystem.get_char_def(name)

	func clone() -> CharacterInstance:
		var c := CharacterInstance.new(name, hp)
		c.hp = hp
		c.energy = energy
		c.aura = aura
		c.defeated = defeated
		c.statuses = []
		for st in statuses:
			c.statuses.append(st.clone())
		c.equipment = equipment.duplicate()
		return c


class PlayerState extends RefCounted:
	## Runtime state of one player (`engine/model.py:Player`).
	var characters: Array[CharacterInstance] = []
	var deck: Array[String] = []
	var hand: Array[String] = []
	var dice: Array[String] = []
	var summons: Array[UnitInstance] = []
	var supports: Array[UnitInstance] = []
	var combat: Array[StatusInstance] = []

	var active: int = -1                  # -1 corresponds to Python's `None`
	var ended: bool = false
	var mull_done: bool = false
	var roll_done: bool = false
	var chosen: int = -1                  # -1 corresponds to Python's `None`
	var rerolls: int = 0

	func _init(chars: Array = [], deck_cards: Array = []) -> void:
		characters = []
		for c_name in chars:
			var defn = CardDataSystem.get_char_def(str(c_name))
			var start_hp: int = defn.hp if defn != null else 10
			characters.append(CharacterInstance.new(str(c_name), start_hp))
		deck = []
		for card_name in deck_cards:
			deck.append(str(card_name))
		hand = []
		dice = []
		summons = []
		supports = []
		combat = []
		active = -1
		ended = false
		mull_done = false
		roll_done = false
		chosen = -1
		rerolls = 0

	func get_active_char() -> CharacterInstance:
		if active < 0 or active >= characters.size():
			return null
		return characters[active]

	func get_alive_indices() -> Array[int]:
		var out: Array[int] = []
		for i in range(characters.size()):
			if not characters[i].defeated:
				out.append(i)
		return out

	func clone() -> PlayerState:
		var p := PlayerState.new()
		p.characters = []
		for c in characters:
			p.characters.append(c.clone())
		p.deck = deck.duplicate()
		p.hand = hand.duplicate()
		p.dice = dice.duplicate()
		p.summons = []
		for u in summons:
			p.summons.append(u.clone())
		p.supports = []
		for u in supports:
			p.supports.append(u.clone())
		p.combat = []
		for st in combat:
			p.combat.append(st.clone())
		p.active = active
		p.ended = ended
		p.mull_done = mull_done
		p.roll_done = roll_done
		p.chosen = chosen
		p.rerolls = rerolls
		return p


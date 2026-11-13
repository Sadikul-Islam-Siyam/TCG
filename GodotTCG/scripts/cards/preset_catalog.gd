class_name TCGPresetCatalog
extends RefCounted
## PresetCatalog
## Exact data migration of `content/presets.py` (BASE priorities, boosts, and 6 preset character lineups).


static func register_all(db: Node) -> void:
	db.base_priorities = {
		"Paimon": 5,
		"Strategize": 4,
		"Sweet Madame": 3,
		"Changing Shifts": 3,
		"Mondstadt Hash Browns": 2,
		"Liyue Harbor Wharf": 2,
		"Wangshu Inn": 2,
		"Gambler's Earrings": 1,
	}
	db.talent_boost = 10
	db.weapon_boost = 6
	db.resonance_boost = 7

	db.preset_defs = {
		"Electro-Charged": PackedStringArray(["Keqing", "Fischl", "Xingqiu"]),
		"Melt Burst": PackedStringArray(["Diluc", "Bennett", "Kaeya"]),
		"Swirl Control": PackedStringArray(["Sucrose", "Mona", "Zhongli"]),
		"Frost and Stone": PackedStringArray(["Ganyu", "Kaeya", "Zhongli"]),
		"Vaporize Overload": PackedStringArray(["Diluc", "Xingqiu", "Fischl"]),
		"Freeze Superconduct": PackedStringArray(["Ganyu", "Mona", "Keqing"]),
	}


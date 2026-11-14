class_name TCGPresetCatalog
extends RefCounted
## PresetCatalog
## Loads starter team presets and autofill priorities from `res://data/presets.json`.


static func register_all(db: CardDataSystem) -> void:
	var data: Dictionary = db.load_json_dict("res://data/presets.json")
	var presets: Dictionary = data.get("presets", {})
	for pname in presets.keys():
		var arr: Array = presets[pname]
		var chars := PackedStringArray()
		for ch_name in arr:
			chars.append(str(ch_name))
		db.preset_defs[str(pname)] = chars

	var prio: Dictionary = data.get("priorities", {})
	for cname in prio.keys():
		db.base_priorities[str(cname)] = int(prio[cname])

class_name TCGCharacterCatalog
extends RefCounted
## CharacterCatalog
## Loads custom character definitions from `res://data/characters.json` into `CardDataSystem`.


static func register_all(db: CardDataSystem) -> void:
	var data: Dictionary = db.load_json_dict("res://data/characters.json")
	for item in data.get("characters", []):
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = item
		var cname := str(d.get("name", ""))
		if cname.is_empty():
			continue
		var skills: Array[CardDataSystem.SkillData] = []
		for sk_raw in d.get("skills", []):
			if typeof(sk_raw) != TYPE_DICTIONARY:
				continue
			var skd: Dictionary = sk_raw
			var cost := db.parse_cost(skd.get("cost", {}))
			var steps := db.parse_steps(skd.get("steps", []))
			skills.append(CardDataSystem.SkillData.new(
				str(skd.get("name", "")),
				str(skd.get("kind", "normal")),
				cost,
				steps,
				str(skd.get("desc", ""))
			))
		var cd := CardDataSystem.CharData.new(
			cname,
			str(d.get("element", "")),
			str(d.get("weapon", "Sword")),
			int(d.get("max_energy", 2)),
			skills,
			int(d.get("hp", 10))
		)
		db.register_char(cd)

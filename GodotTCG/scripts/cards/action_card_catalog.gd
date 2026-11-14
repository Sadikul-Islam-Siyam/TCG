class_name TCGActionCardCatalog
extends RefCounted
## ActionCardCatalog
## Loads custom action cards from `res://data/action_cards.json` into `CardDataSystem`.


static func register_all(db: CardDataSystem) -> void:
	var data: Dictionary = db.load_json_dict("res://data/action_cards.json")
	for item in data.get("cards", []):
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = item
		var cname := str(d.get("name", ""))
		if cname.is_empty():
			continue
		var cost := db.parse_cost(d.get("cost", {}))
		var cd := CardDataSystem.CardData.new(
			cname,
			str(d.get("kind", "event")),
			cost
		)
		cd.role = str(d.get("role", ""))
		cd.needs_char = bool(d.get("use_target", d.get("needs_char", false)))
		cd.usages = int(d.get("usages", -1))
		cd.text = str(d.get("text", ""))
		cd.play_steps = db.parse_steps(d.get("steps", d.get("play_steps", [])), cd.needs_char)
		if cd.role.is_empty():
			cd.role = db.infer_card_role(cd)
		db.register_card(cd)

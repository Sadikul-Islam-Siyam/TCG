class_name TCGStatusCatalog
extends RefCounted
## StatusCatalog
## Loads status definitions from `res://data/statuses.json` into `CardDataSystem`.


static func register_all(db: CardDataSystem) -> void:
	var data: Dictionary = db.load_json_dict("res://data/statuses.json")
	for item in data.get("statuses", []):
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = item
		var st := CardDataSystem.StatusData.new()
		st.name = str(d.get("name", ""))
		if st.name.is_empty():
			continue
		st.text = str(d.get("text", ""))
		st.usages = int(d.get("usages", -1))
		st.duration = int(d.get("duration", -1))
		st.shield = int(d.get("shield", 0))
		st.max_shield = int(d.get("max_shield", maxi(99, st.shield)))
		st.reduce = int(d.get("reduce", 0))
		st.reduce_min = int(d.get("reduce_min", 0))
		st.per_round = int(d.get("per_round", -1))
		st.outgoing_rule = str(d.get("outgoing_rule", ""))
		st.after_skill_rule = str(d.get("after_skill_rule", ""))
		st.on_kill_rule = str(d.get("on_kill_rule", ""))
		db.register_status(st)

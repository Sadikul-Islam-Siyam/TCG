class_name TCGDeckStore
extends RefCounted
## Saved Decks Persistence (JSON)
## Exact port of Python `genius_tcg/ui/store.py`.
## Default location: `user://decks.json`, or `$GENIUS_TCG_HOME/decks.json` if set.

static var _override_path: String = ""
static var last_error: String = ""


static func set_override_path(p_path: String) -> void:
	## Optional test hook to isolate saved-deck tests from user://decks.json.
	_override_path = p_path


static func _path() -> String:
	if not _override_path.is_empty():
		return _override_path
	var env_home: String = OS.get_environment("GENIUS_TCG_HOME").strip_edges()
	if not env_home.is_empty():
		return env_home.path_join("decks.json")
	return "user://decks.json"


static func _read() -> Array[Dictionary]:
	var p: String = _path()
	if not FileAccess.file_exists(p):
		return []
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return []
	var text_data: String = f.get_as_text()
	f.close()
	if text_data.strip_edges().is_empty():
		return []
	var json := JSON.new()
	if json.parse(text_data) != OK:
		return []
	var parsed = json.data
	if typeof(parsed) != TYPE_ARRAY:
		return []
	var out: Array[Dictionary] = []
	for item in parsed:
		if typeof(item) == TYPE_DICTIONARY and item.has("name") and item.has("chars") and item.has("cards"):
			if typeof(item["chars"]) == TYPE_ARRAY and typeof(item["cards"]) == TYPE_ARRAY:
				out.append(item)
	return out


static func _write(decks: Array[Dictionary]) -> bool:
	last_error = ""
	var p: String = _path()
	var dir_path: String = p.get_base_dir()
	if not dir_path.is_empty() and dir_path != "user:":
		var abs_dir: String = ProjectSettings.globalize_path(dir_path) if dir_path.begins_with("user://") or dir_path.begins_with("res://") else dir_path
		DirAccess.make_dir_recursive_absolute(abs_dir)

	var tmp_path: String = p + ".tmp"
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		last_error = "Could not open %s for writing" % tmp_path
		return false
	f.store_string(JSON.stringify(decks, " "))
	f.close()

	var abs_tmp: String = ProjectSettings.globalize_path(tmp_path) if tmp_path.begins_with("user://") or tmp_path.begins_with("res://") else tmp_path
	var abs_dst: String = ProjectSettings.globalize_path(p) if p.begins_with("user://") or p.begins_with("res://") else p
	var err: Error = DirAccess.rename_absolute(abs_tmp, abs_dst)
	if err != OK:
		# Fallback: write directly if atomic rename fails on a virtual path
		var f2 := FileAccess.open(p, FileAccess.WRITE)
		if f2 == null:
			last_error = "Could not write %s (error %d)" % [p, err]
			return false
		f2.store_string(JSON.stringify(decks, " "))
		f2.close()
	return true


static func list_decks() -> Array[Dictionary]:
	## Returns saved decks, each with a `legal` flag (drafts can be saved but not played).
	CardDataSystem.load_all_content()
	var out: Array[Dictionary] = []
	for d in _read():
		var chars: Array[String] = []
		for c in d["chars"]:
			chars.append(str(c))
		var cards: Array[String] = []
		for card in d["cards"]:
			cards.append(str(card))
		var errs: Array[String] = TCGDeckSystem.validate_deck(chars, cards)
		out.append({
			"name": str(d["name"]),
			"chars": chars,
			"cards": cards,
			"legal": errs.is_empty(),
		})
	return out


static func save_deck(deck_name: String, chars: Array, cards: Array) -> bool:
	last_error = ""
	var clean_name: String = deck_name.strip_edges()
	if clean_name.is_empty():
		last_error = "deck needs a name"
		return false

	var decks: Array[Dictionary] = []
	for d in _read():
		if str(d["name"]) != clean_name:
			decks.append(d)

	var c_arr: Array = []
	for c in chars:
		c_arr.append(str(c))
	var d_arr: Array = []
	for card in cards:
		d_arr.append(str(card))
	d_arr.sort()

	decks.append({"name": clean_name, "chars": c_arr, "cards": d_arr})
	return _write(decks)


static func delete_deck(deck_name: String) -> bool:
	var kept: Array[Dictionary] = []
	for d in _read():
		if str(d["name"]) != deck_name:
			kept.append(d)
	return _write(kept)


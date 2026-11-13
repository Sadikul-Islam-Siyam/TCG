class_name TCGDeckSystem
extends RefCounted
## DeckSystem
## Exact port of Python `engine/deck.py` and `content/presets.py`:
## `card_allowed`, `allowed_cards`, `validate_deck`, `autofill`, `encode`, `decode`, `preset_decks`.

const DECK_SIZE: int = CardDataSystem.DECK_SIZE
const MAX_COPIES: int = CardDataSystem.MAX_COPIES


static func card_allowed(cd: CardDataSystem.CardData, chars: Array) -> bool:
	## Can this card be in a deck with these three characters? (`engine/deck.py:card_allowed`)
	return CardDataSystem.is_card_allowed_in_deck(cd, chars)


static func allowed_cards(chars: Array) -> Array[String]:
	## Returns sorted list of allowed card names for `chars` (`engine/deck.py:allowed_cards`).
	var out: Array[String] = []
	for n in CardDataSystem.card_defs.keys():
		var cd: CardDataSystem.CardData = CardDataSystem.card_defs[n]
		if card_allowed(cd, chars):
			out.append(str(n))
	out.sort()
	return out


static func validate_deck(chars: Array, cards: Array) -> Array[String]:
	## Returns a list of rule violations; empty list = legal deck (`engine/deck.py:validate_deck`).
	var errs: Array[String] = []
	var uniq: Dictionary = {}
	var known_chars: bool = true
	for c in chars:
		var sc: String = str(c)
		uniq[sc] = true
		if not CardDataSystem.char_defs.has(sc):
			known_chars = false

	if chars.size() != 3 or uniq.size() != 3 or not known_chars:
		return ["a deck needs exactly 3 different, known characters"]

	if cards.size() != DECK_SIZE:
		errs.append("deck has %d cards, needs %d" % [cards.size(), DECK_SIZE])

	var counts: Dictionary = {}
	var order: Array[String] = []
	for raw_name in cards:
		var name: String = str(raw_name)
		if not counts.has(name):
			counts[name] = 0
			order.append(name)
		counts[name] = int(counts[name]) + 1

	var chars_str_list: PackedStringArray = []
	for c in chars:
		chars_str_list.append(str(c))

	for name in order:
		var n: int = int(counts[name])
		if not CardDataSystem.card_defs.has(name):
			errs.append("unknown card: %s" % name)
		elif n > MAX_COPIES:
			errs.append("%s: %d copies (max %d)" % [name, n, MAX_COPIES])
		elif not card_allowed(CardDataSystem.card_defs[name], chars):
			errs.append("%s cannot be used with %s" % [name, ", ".join(chars_str_list)])

	return errs


static func autofill(chars: Array, partial: Array = [], priority: Dictionary = {}) -> Variant:
	## Complete a partial deck into a legal 30-card deck with the CSP solver (`engine/deck.py:autofill`).
	## Returns `Array[String]` or `null` if impossible.
	var names: Array[String] = allowed_cards(chars)
	var allowed_set: Dictionary = {}
	for n in names:
		allowed_set[n] = true

	var have: Dictionary = {}
	for raw_c in partial:
		var cname: String = str(raw_c)
		have[cname] = int(have.get(cname, 0)) + 1

	for cname in have.keys():
		if not allowed_set.has(cname) or int(have[cname]) > MAX_COPIES:
			return null

	var domains: Dictionary = {}
	for n in names:
		var start_count: int = int(have.get(n, 0))
		var dom: Array[int] = []
		for c_val in range(start_count, MAX_COPIES + 1):
			dom.append(c_val)
		domains[n] = dom

	var sum_constraint := TCGCspSolver.SumEq.new(names, DECK_SIZE)
	var sol = TCGCspSolver.solve(
		domains,
		[sum_constraint],
		func(n: String) -> Array:
			return [-float(priority.get(n, 0)), n]
	)
	if sol == null:
		return null

	var sorted_keys: Array = sol.keys()
	sorted_keys.sort()
	var out: Array[String] = []
	for n in sorted_keys:
		var copies: int = int(sol[n])
		for _i in range(copies):
			out.append(str(n))
	return out


static func encode(chars: Array, cards: Array) -> String:
	## URL-safe Base64 JSON share code without padding (`engine/deck.py:encode`).
	var c_arr: Array = []
	for c in chars:
		c_arr.append(str(c))
	var d_arr: Array = []
	for card in cards:
		d_arr.append(str(card))
	d_arr.sort()

	var payload := {"c": c_arr, "d": d_arr}
	var raw_json: String = JSON.stringify(payload, "", true)
	var b64: String = Marshalls.utf8_to_base64(raw_json)
	b64 = b64.replace("+", "-").replace("/", "_").rstrip("=")
	return b64


static func decode(code: String) -> Array:
	## Decodes a URL-safe Base64 share code into `[chars_array, cards_array]` (`engine/deck.py:decode`).
	## Returns empty array `[]` if invalid.
	var trimmed: String = code.strip_edges()
	if trimmed.is_empty():
		return []
	var b64: String = trimmed.replace("-", "+").replace("_", "/")
	var pad: int = (4 - (b64.length() % 4)) % 4
	for _i in range(pad):
		b64 += "="
	var raw_json: String = Marshalls.base64_to_utf8(b64)
	if raw_json.is_empty():
		return []
	var parsed = JSON.parse_string(raw_json)
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("c") or not parsed.has("d"):
		return []
	var c_out: Array[String] = []
	for c in parsed["c"]:
		c_out.append(str(c))
	var d_out: Array[String] = []
	for d in parsed["d"]:
		d_out.append(str(d))
	return [c_out, d_out]


static func build_preset(chars: Array) -> Array[String]:
	## Builds a 30-card deck for `chars` using `content/presets.py:priority()`.
	var res = autofill(chars, [], CardDataSystem.get_card_priorities())
	if res == null:
		return []
	return res


static func preset_decks() -> Dictionary:
	## Returns `{preset_name: [chars, cards]}` matching `content/presets.py:preset_decks()`.
	var out: Dictionary = {}
	for preset_name in CardDataSystem.preset_defs.keys():
		var chars: Array[String] = []
		for c in CardDataSystem.preset_defs[preset_name]:
			chars.append(str(c))
		out[preset_name] = [chars, build_preset(chars)]
	return out


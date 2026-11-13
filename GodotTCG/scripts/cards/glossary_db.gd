class_name GlossaryDB
extends RefCounted
## Phase 9 (T9.4 - T9.5): Structured markup compiler ({num:}, {el:}, {kw:}) and
## comprehensive Genius Invokation TCG Glossary (6 Elements, 8 Reactions, Keywords, Statuses).
## Strictly zero Dendro entries; reads all element colors from ElementDB.

const REACTION_ENTRIES: Dictionary = {
	"Vaporize": {
		"title": "Vaporize (Pyro + Hydro)",
		"elements": ["Pyro", "Hydro"],
		"body": "Deals {num:+2} DMG for the triggering attack.\nTriggered when {el:Pyro} meets {el:Hydro}.",
	},
	"Melt": {
		"title": "Melt (Pyro + Cryo)",
		"elements": ["Pyro", "Cryo"],
		"body": "Deals {num:+2} DMG for the triggering attack.\nTriggered when {el:Pyro} meets {el:Cryo}.",
	},
	"Overloaded": {
		"title": "Overloaded (Pyro + Electro)",
		"elements": ["Pyro", "Electro"],
		"body": "Deals {num:+2} DMG for the triggering attack, and forcibly switches the target to their next surviving character.",
	},
	"Superconduct": {
		"title": "Superconduct (Cryo + Electro)",
		"elements": ["Cryo", "Electro"],
		"body": "Deals {num:+1} DMG to the target and {num:1} {el:Piercing} DMG to all other opposing characters.",
	},
	"Electro-Charged": {
		"title": "Electro-Charged (Hydro + Electro)",
		"elements": ["Hydro", "Electro"],
		"body": "Deals {num:+1} DMG to the target and {num:1} {el:Piercing} DMG to all other opposing characters.",
	},
	"Frozen": {
		"title": "Frozen (Cryo + Hydro)",
		"elements": ["Cryo", "Hydro"],
		"body": "Deals {num:+1} DMG and attaches {kw:Frozen} to the target.\n{kw:Frozen} prevents skills until End Phase and takes {num:+2} DMG from {el:Physical} or {el:Pyro} (which shatters the ice).",
	},
	"Swirl": {
		"title": "Swirl (Anemo + Aura)",
		"elements": ["Anemo"],
		"body": "Consumes {el:Pyro}, {el:Hydro}, {el:Cryo}, or {el:Electro} on the target and deals {num:1} Elemental DMG of the swirled type to all standby opposing characters.",
	},
	"Crystallize": {
		"title": "Crystallize (Geo + Aura)",
		"elements": ["Geo"],
		"body": "Consumes {el:Pyro}, {el:Hydro}, {el:Cryo}, or {el:Electro} on the target, deals {num:+1} DMG, and grants {kw:Crystallize Shield} ({num:1} Shield, max {num:2}).",
	},
}

const KEYWORD_ENTRIES: Dictionary = {
	"Combat Action": {
		"title": "Combat Action",
		"body": "Passes your turn to the opponent after resolving. Using skills and manual character switches are Combat Actions.",
	},
	"Fast Action": {
		"title": "Fast Action",
		"body": "Keeps your turn active so you can take another action immediately. Most Event, Support, and Equipment cards are Fast Actions.",
	},
	"Elemental Tuning": {
		"title": "Elemental Tuning",
		"body": "Discard 1 Action Card from your hand to convert 1 non-matching Die into the element of your current active character (Fast Action).",
	},
	"Frozen": {
		"title": "Frozen",
		"body": "Affected character cannot use skills until End Phase.\nTaking {el:Physical} or {el:Pyro} DMG increases that hit by {num:+2} and removes {kw:Frozen}.",
	},
	"Petrified": {
		"title": "Petrified",
		"body": "Affected character cannot use skills until the end of the round.",
	},
	"Piercing DMG": {
		"title": "Piercing DMG",
		"body": "Ignores Shields and DMG Reduction effects, and does not attach an element or trigger reactions.",
	},
	"Shield": {
		"title": "Shield",
		"body": "Absorbs incoming non-{kw:Piercing DMG} before the active character's HP is reduced.",
	},
	"Crystallize Shield": {
		"title": "Crystallize Shield",
		"body": "Provides {num:1} {kw:Shield} to your active character (stacks up to {num:2}).",
	},
	"Usage(s)": {
		"title": "Usage(s)",
		"body": "Remaining activations before this Summon, Support, or Combat Status expires.",
	},
	"Energy": {
		"title": "Energy",
		"body": "Gained (+1) from Normal Attacks and Elemental Skills. Spent to cast Elemental Bursts.",
	},
	"Omni": {
		"title": "Omni Element",
		"body": "Wildcard die usable to pay any elemental or unaligned die cost.",
	},
	"Same Element": {
		"title": "Aligned / Matching Dice",
		"body": "Requires dice of one identical element (or {kw:Omni}).",
	},
	"Unaligned": {
		"title": "Unaligned Element",
		"body": "Can be paid using any elemental die.",
	},
}


static func compile_bbcode(raw_text: String) -> String:
	var out: String = raw_text
	# Replace {num:VALUE}
	var num_rx := RegEx.new()
	num_rx.compile("\\{num:([^\\}]+)\\}")
	for m in num_rx.search_all(out):
		var val: String = m.get_string(1)
		out = out.replace(m.get_string(0), "[b][color=#ffe5a5]%s[/color][/b]" % val)

	# Replace {el:ELEMENT} using single-source ElementDB colors
	var el_rx := RegEx.new()
	el_rx.compile("\\{el:([^\\}]+)\\}")
	for m in el_rx.search_all(out):
		var el_name: String = m.get_string(1)
		var col: Color = ElementDB.get_color(el_name)
		var hex: String = "#" + col.to_html(false)
		out = out.replace(m.get_string(0), "[url=el:%s][b][color=%s]%s[/color][/b][/url]" % [el_name.uri_encode(), hex, el_name])

	# Replace {kw:KEYWORD} with clickable glossary links (uri-encode target to avoid spaces/quotes breaking BBCode)
	var kw_rx := RegEx.new()
	kw_rx.compile("\\{kw:([^\\}]+)\\}")
	for m in kw_rx.search_all(out):
		var kw: String = m.get_string(1)
		out = out.replace(m.get_string(0), "[url=kw:%s][u][color=#62bed0]%s[/color][/u][/url]" % [kw.uri_encode(), kw])

	return out


static func highlight_plain_text(text: String) -> String:
	## Auto-tags element names and canonical reaction/keyword terms in unformatted rule descriptions.
	var tagged: String = text
	for el in ["Pyro", "Hydro", "Cryo", "Electro", "Anemo", "Geo", "Physical", "Piercing", "Omni"]:
		var col_hex: String = "#" + ElementDB.get_color(el).to_html(false)
		var rx := RegEx.new()
		rx.compile("\\b%s\\b" % el)
		tagged = rx.sub(tagged, "[url=el:%s][b][color=%s]%s[/color][/b][/url]" % [el.uri_encode(), col_hex, el], true)

	for rx_name in REACTION_ENTRIES.keys():
		var rx2 := RegEx.new()
		rx2.compile("\\b%s\\b" % rx_name)
		tagged = rx2.sub(tagged, "[url=kw:%s][u][color=#ffe5a5]%s[/color][/u][/url]" % [String(rx_name).uri_encode(), rx_name], true)

	for kw in ["Frozen", "Petrified", "Shield", "Combat Action", "Fast Action", "Energy", "Usage(s)"]:
		var rx3 := RegEx.new()
		rx3.compile("\\b%s\\b" % kw.replace("(", "\\(").replace(")", "\\)"))
		tagged = rx3.sub(tagged, "[url=kw:%s][u][color=#62bed0]%s[/color][/u][/url]" % [kw.uri_encode(), kw], true)

	return tagged


static func lookup_term(term_ref: String) -> Dictionary:
	## Resolves either "el:Name", "kw:Name", "status:Name", or bare name into {title, body, color, kind}.
	var decoded := term_ref.uri_decode()
	var kind := ""
	var key := decoded
	if decoded.find(":") >= 0:
		var parts := decoded.split(":", false, 1)
		kind = parts[0]
		key = parts[1].uri_decode()

	if kind == "el" or ElementDB.SPECS.has(key):
		var ed := ElementDB.get_element(key)
		var attach_note := "Attaches as elemental aura on targets." if (ed != null and ed.can_attach) else "Triggers Swirl/Crystallize on auras without lingering."
		if key == "Omni" or key == "Physical" or key == "Piercing":
			attach_note = KEYWORD_ENTRIES.get("Piercing DMG" if key == "Piercing" else "Omni", {}).get("body", "Special combat channel.")
		return {
			"title": "%s Element" % key,
			"body": attach_note,
			"color": ed.color if ed != null else Color.WHITE,
			"kind": "element",
		}

	if REACTION_ENTRIES.has(key):
		var rec: Dictionary = REACTION_ENTRIES[key]
		return {
			"title": String(rec["title"]),
			"body": String(rec["body"]),
			"color": Color8(255, 229, 165),
			"kind": "reaction",
		}

	if KEYWORD_ENTRIES.has(key):
		var kw_rec: Dictionary = KEYWORD_ENTRIES[key]
		return {
			"title": String(kw_rec["title"]),
			"body": String(kw_rec["body"]),
			"color": Color8(98, 190, 208),
			"kind": "keyword",
		}

	CardDataSystem.load_all_content()
	var sdef := CardDataSystem.get_status_def(key)
	if sdef != null:
		var lines: PackedStringArray = []
		if not sdef.text.is_empty():
			lines.append(highlight_plain_text(sdef.text))
		if sdef.usages >= 0:
			lines.append("Starting Usages: {num:%d}" % sdef.usages)
		if sdef.duration >= 0:
			lines.append("Round Duration: {num:%d}" % sdef.duration)
		if sdef.shield > 0:
			lines.append("Shield: {num:%d} (max {num:%d})" % [sdef.shield, sdef.max_shield])
		if sdef.reduce > 0:
			lines.append("DMG Reduction: {num:%d} when hit >= {num:%d}" % [sdef.reduce, sdef.reduce_min])
		return {
			"title": sdef.name,
			"body": "\n".join(lines) if not lines.is_empty() else "Active status effect.",
			"color": Color8(128, 218, 159),
			"kind": "status",
		}

	var cdef := CardDataSystem.get_card_def(key)
	if cdef != null:
		return {
			"title": cdef.name,
			"body": highlight_plain_text(cdef.text),
			"color": Color8(222, 185, 105),
			"kind": "card",
		}

	return {}

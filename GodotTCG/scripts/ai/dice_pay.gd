class_name TCGDicePay
extends RefCounted
## CSP Smart Dice Payment
## Exact port of Python `genius_tcg/ai/dicepay.py`.
## Assigns each cost slot to a distinct die index (`AllDiff`),
## spending off-element dice first, useful elements next, and Omni last.


static func smart_pay(dice: Array, cost: CardDataSystem.CostData, keep: Array = []) -> Variant:
	## Returns a sorted `Array[int]` of die indices to spend, or `null` if impossible.
	if cost.n == 0 and cost.unaligned == 0:
		var empty: Array[int] = []
		return empty

	var n_dice: int = dice.size()
	var ok_el: Array[int] = []
	var all_idx: Array[int] = []
	for i in range(n_dice):
		all_idx.append(i)
		var d: String = str(dice[i])
		if d == cost.element or d == CardDataSystem.OMNI:
			ok_el.append(i)

	var slots: Dictionary = {}
	for k in range(cost.n):
		slots["e_%d" % k] = ok_el.duplicate()
	for k in range(cost.unaligned):
		slots["u_%d" % k] = all_idx.duplicate()

	if slots.size() > n_dice:
		return null

	var counts: Dictionary = {}
	for d in dice:
		var ds: String = str(d)
		counts[ds] = int(counts.get(ds, 0)) + 1

	var keep_set: Dictionary = {}
	for k_el in keep:
		keep_set[str(k_el)] = true

	var var_key := func(v: String) -> Array:
		# Elemental slots are tighter: assign them before unaligned slots.
		var grp: int = 0 if v.begins_with("e_") else 1
		var idx: int = int(v.substr(2))
		return [grp, idx]

	var value_key := func(i: int) -> Array:
		var d: String = str(dice[i])
		var w: float = 100.0
		if d != CardDataSystem.OMNI:
			var base: float = 3.0 if keep_set.has(d) else 1.0
			w = base / float(counts[d])
		return [w, i]

	var sol = TCGCspSolver.solve(
		slots,
		[TCGCspSolver.AllDiff.new(slots.keys())],
		var_key,
		value_key
	)
	if sol == null:
		return null

	var out: Array[int] = []
	for k in sol.keys():
		out.append(int(sol[k]))
	out.sort()
	return out


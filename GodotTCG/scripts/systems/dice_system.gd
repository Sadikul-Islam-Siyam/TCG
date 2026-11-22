class_name TCGDiceSystem
extends RefCounted
## DiceSystem
## Exact port of Python `engine/dice.py`: `roll`, `payment_ok`, and `auto_pay`.


static func roll(rng: RandomNumberGenerator, n: int) -> Array[String]:
	## Weighted dice roll (`engine/dice.py:roll`).
	return TCGRoundManager.roll_dice(rng, n)


static func payment_ok(dice: Array[String], cost: CardDataSystem.CostData, idx: Array) -> bool:
	## True if the dice indices in `idx` are distinct, in-bounds, and exactly pay `cost` (`engine/dice.py:payment_ok`).
	if cost == null:
		return idx.is_empty()
	var seen: Dictionary = {}
	for raw_i in idx:
		var i: int = int(raw_i)
		if seen.has(i) or i < 0 or i >= dice.size():
			return false
		seen[i] = true
	if idx.size() != cost.n + cost.unaligned:
		return false
	if cost.n <= 0:
		return true
	if cost.element.is_empty():
		# "N dice of the same type" (Omni counts as wild toward any chosen element)
		var omni_c: int = 0
		var elem_counts: Dictionary = {}
		var best_same: int = 0
		for raw_i in idx:
			var d: String = dice[int(raw_i)]
			if d == CardDataSystem.OMNI:
				omni_c += 1
			else:
				var next_c: int = int(elem_counts.get(d, 0)) + 1
				elem_counts[d] = next_c
				if next_c > best_same:
					best_same = next_c
		return (best_same + omni_c) >= cost.n
	var good: int = 0
	for raw_i in idx:
		var d: String = dice[int(raw_i)]
		if d == cost.element or d == CardDataSystem.OMNI:
			good += 1
	return good >= cost.n


static func auto_pay(dice: Array[String], cost: CardDataSystem.CostData, keep: Array = []) -> Variant:
	## Cheapest legal payment (`Array[int]` sorted ascending) or `null` if unaffordable (`engine/dice.py:auto_pay`).
	## Spends exact-element dice first, Omni last, and prefers elements the player has
	## no character for (and highest-count duplicates) when paying unaligned or same-type costs.
	if cost == null:
		return []
	if cost.n > 0 and cost.element.is_empty():
		# "N dice of the same type": try non-keep elements (highest count first), then keep elements, then Omni-only
		var el_counts: Dictionary = {}
		var omni_n: int = 0
		for d in dice:
			if d == CardDataSystem.OMNI:
				omni_n += 1
			else:
				el_counts[d] = int(el_counts.get(d, 0)) + 1
		var keep_map: Dictionary = {}
		for k_el in keep:
			keep_map[str(k_el)] = true
		var cand_els: Array[String] = []
		for el in el_counts.keys():
			if int(el_counts[el]) + omni_n >= cost.n:
				cand_els.append(str(el))
		cand_els.sort_custom(func(a: String, b: String) -> bool:
			var ka: int = 1 if keep_map.has(a) else 0
			var kb: int = 1 if keep_map.has(b) else 0
			if ka != kb:
				return ka < kb
			var ca: int = int(el_counts[a])
			var cb: int = int(el_counts[b])
			if ca != cb:
				return ca > cb
			return a < b
		)
		for el in cand_els:
			var sub: Variant = auto_pay(dice, CardDataSystem.CostData.new(el, cost.n, cost.unaligned, cost.energy), keep)
			if sub != null:
				return sub
		if omni_n >= cost.n:
			return auto_pay(dice, CardDataSystem.CostData.new(CardDataSystem.OMNI, cost.n, cost.unaligned, cost.energy), keep)
		return null
	var chosen: Array[int] = []
	var used: Dictionary = {}
	var need: int = cost.n

	for want in [cost.element, CardDataSystem.OMNI]:
		if want.is_empty():
			continue
		for i in range(dice.size()):
			if need > 0 and dice[i] == want and not used.has(i):
				chosen.append(i)
				used[i] = true
				need -= 1
	if need > 0:
		return null

	var rest: Array[int] = []
	for i in range(dice.size()):
		if not used.has(i):
			rest.append(i)
	if rest.size() < cost.unaligned:
		return null

	var counts: Dictionary = {}
	for i in rest:
		var d: String = dice[i]
		counts[d] = int(counts.get(d, 0)) + 1

	var keep_set: Dictionary = {}
	for k_el in keep:
		keep_set[str(k_el)] = true

	# Python priority(i):
	# (2, 0) if d == OMNI else (1 if d in keep else 0, -counts[d])
	# Note: Python `list.sort()` is stable, so ties preserve original index `i` ascending.
	rest.sort_custom(func(a: int, b: int) -> bool:
		var da: String = dice[a]
		var db: String = dice[b]
		var pa0: int = 2 if da == CardDataSystem.OMNI else (1 if keep_set.has(da) else 0)
		var pb0: int = 2 if db == CardDataSystem.OMNI else (1 if keep_set.has(db) else 0)
		if pa0 != pb0:
			return pa0 < pb0
		var pa1: int = 0 if da == CardDataSystem.OMNI else -int(counts.get(da, 0))
		var pb1: int = 0 if db == CardDataSystem.OMNI else -int(counts.get(db, 0))
		if pa1 != pb1:
			return pa1 < pb1
		return a < b
	)

	var out: Array[int] = chosen.duplicate()
	for k in range(cost.unaligned):
		out.append(rest[k])
	out.sort()
	return out


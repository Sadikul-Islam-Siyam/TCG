class_name TCGCspSolver
extends RefCounted
## CspSolver
## Exact port of Python `engine/csp.py`: `SumEq`, `AllDiff`, and `solve`
## (backtracking + Minimum Remaining Values (MRV) + forward checking).


class SumEq extends RefCounted:
	## Sum of the variables in `scope` must equal `target` (`engine/csp.py:SumEq`).
	var scope: Dictionary = {}
	var target: int = 0

	func _init(p_scope: Array, p_target: int) -> void:
		scope = {}
		for v in p_scope:
			scope[v] = true
		target = p_target

	func consistent(assign: Dictionary, domains: Dictionary) -> bool:
		var lo: int = 0
		var hi: int = 0
		for v in scope.keys():
			if assign.has(v):
				var val: int = int(assign[v])
				lo += val
				hi += val
			else:
				var dom: Array = domains[v]
				if dom.is_empty():
					return false
				var d_min: int = int(dom[0])
				var d_max: int = int(dom[0])
				for x in dom:
					var ix: int = int(x)
					if ix < d_min:
						d_min = ix
					if ix > d_max:
						d_max = ix
				lo += d_min
				hi += d_max
		return lo <= target and target <= hi


class AllDiff extends RefCounted:
	## All variables in `scope` must take different values (`engine/csp.py:AllDiff`).
	var scope: Dictionary = {}

	func _init(p_scope: Array) -> void:
		scope = {}
		for v in p_scope:
			scope[v] = true

	func consistent(assign: Dictionary, _domains: Dictionary) -> bool:
		var seen: Dictionary = {}
		for v in scope.keys():
			if assign.has(v):
				var val = assign[v]
				if seen.has(val):
					return false
				seen[val] = true
		return true


static func _compare_keys(ka: Variant, kb: Variant) -> int:
	## Lexicographical comparison supporting numbers, strings, and Arrays (tuples in Python).
	if typeof(ka) == TYPE_ARRAY and typeof(kb) == TYPE_ARRAY:
		var arr_a: Array = ka
		var arr_b: Array = kb
		var n: int = mini(arr_a.size(), arr_b.size())
		for i in range(n):
			var c: int = _compare_keys(arr_a[i], arr_b[i])
			if c != 0:
				return c
		if arr_a.size() < arr_b.size():
			return -1
		if arr_a.size() > arr_b.size():
			return 1
		return 0
	if typeof(ka) == TYPE_BOOL and typeof(kb) == TYPE_BOOL:
		var ba: int = 1 if bool(ka) else 0
		var bb: int = 1 if bool(kb) else 0
		return -1 if ba < bb else (1 if ba > bb else 0)
	if (typeof(ka) == TYPE_INT or typeof(ka) == TYPE_FLOAT) and (typeof(kb) == TYPE_INT or typeof(kb) == TYPE_FLOAT):
		var fa: float = float(ka)
		var fb: float = float(kb)
		return -1 if fa < fb else (1 if fa > fb else 0)
	var sa: String = str(ka)
	var sb: String = str(kb)
	return -1 if sa < sb else (1 if sa > sb else 0)


static func solve(
	raw_domains: Dictionary,
	constraints: Array,
	var_key: Callable = Callable(),
	value_key: Callable = Callable()
) -> Variant:
	## Solves the CSP (`engine/csp.py:solve`).
	## Returns a `Dictionary` `{var: value}` or `null` if unsatisfiable.
	var domains: Dictionary = {}
	for v in raw_domains.keys():
		domains[v] = (raw_domains[v] as Array).duplicate()

	var assign: Dictionary = {}
	var v_key: Callable = var_key if var_key.is_valid() else func(_v): return 0
	var val_key: Callable = value_key if value_key.is_valid() else func(x): return -float(x)

	var state := {
		"domains": domains,
		"assign": assign,
		"constraints": constraints,
		"v_key": v_key,
		"val_key": val_key,
	}

	if _backtrack(state):
		return assign.duplicate()
	return null


static func _forward_check(state: Dictionary, v_curr: Variant) -> Array:
	var domains: Dictionary = state["domains"]
	var assign: Dictionary = state["assign"]
	var constraints: Array = state["constraints"]
	var removed: Array = []

	for c in constraints:
		if not c.scope.has(v_curr):
			continue
		for u in c.scope.keys():
			if assign.has(u):
				continue
			var dom_u: Array = domains[u]
			for val in dom_u.duplicate():
				assign[u] = val
				var ok: bool = c.consistent(assign, domains)
				assign.erase(u)
				if not ok:
					dom_u.erase(val)
					removed.append([u, val])
			if dom_u.is_empty():
				return [removed, false]
	return [removed, true]


static func _backtrack(state: Dictionary) -> bool:
	var domains: Dictionary = state["domains"]
	var assign: Dictionary = state["assign"]
	var constraints: Array = state["constraints"]
	var v_key: Callable = state["v_key"]
	var val_key: Callable = state["val_key"]

	if assign.size() == domains.size():
		return true

	# MRV variable selection: min by (len(domains[v]), var_key(v))
	var chosen_var: Variant = null
	var chosen_tuple: Variant = null
	for v in domains.keys():
		if assign.has(v):
			continue
		var cand_tuple: Array = [domains[v].size(), v_key.call(v)]
		if chosen_var == null or _compare_keys(cand_tuple, chosen_tuple) < 0:
			chosen_var = v
			chosen_tuple = cand_tuple

	var vals: Array = (domains[chosen_var] as Array).duplicate()
	vals.sort_custom(func(a, b) -> bool:
		return _compare_keys(val_key.call(a), val_key.call(b)) < 0
	)

	for val in vals:
		assign[chosen_var] = val
		var all_ok: bool = true
		for c in constraints:
			if c.scope.has(chosen_var) and not c.consistent(assign, domains):
				all_ok = false
				break
		if all_ok:
			var fc: Array = _forward_check(state, chosen_var)
			var removed: Array = fc[0]
			var ok: bool = fc[1]
			if ok and _backtrack(state):
				return true
			for pair in removed:
				domains[pair[0]].append(pair[1])
		assign.erase(chosen_var)

	return false


"""Tiny generic constraint-satisfaction solver (backtracking + MRV + forward checking).
Used by the deck builder (auto-fill) and reusable by the AI (e.g. AI deck generation)."""


class SumEq:
    """sum of the variables in `scope` must equal `target`."""

    def __init__(self, scope, target):
        self.scope, self.target = set(scope), target

    def consistent(self, assign, domains):
        lo = hi = 0
        for v in self.scope:
            if v in assign:
                lo += assign[v]; hi += assign[v]
            else:
                lo += min(domains[v]); hi += max(domains[v])
        return lo <= self.target <= hi


class AllDiff:
    """all variables in `scope` must take different values."""

    def __init__(self, scope):
        self.scope = set(scope)

    def consistent(self, assign, domains):
        vals = [assign[v] for v in self.scope if v in assign]
        return len(vals) == len(set(vals))


def solve(domains, constraints, var_key=None, value_key=None):
    """domains: {var: iterable of values}. Returns {var: value} or None.
    MRV picks the variable with the smallest domain (ties broken by var_key);
    forward checking prunes neighbours' values that can no longer fit any constraint."""
    domains = {v: list(d) for v, d in domains.items()}
    assign = {}
    var_key = var_key or (lambda v: 0)
    value_key = value_key or (lambda x: -x)

    def forward_check(var):
        removed = []
        for c in constraints:
            if var not in c.scope:
                continue
            for u in c.scope:
                if u in assign:
                    continue
                for val in list(domains[u]):
                    assign[u] = val
                    ok = c.consistent(assign, domains)
                    del assign[u]
                    if not ok:
                        domains[u].remove(val)
                        removed.append((u, val))
                if not domains[u]:
                    return removed, False
        return removed, True

    def backtrack():
        if len(assign) == len(domains):
            return True
        var = min((v for v in domains if v not in assign), key=lambda v: (len(domains[v]), var_key(v)))
        for val in sorted(domains[var], key=value_key):
            assign[var] = val
            if all(c.consistent(assign, domains) for c in constraints if var in c.scope):
                removed, ok = forward_check(var)
                if ok and backtrack():
                    return True
                for u, x in removed:
                    domains[u].append(x)
            del assign[var]
        return False

    return dict(assign) if backtrack() else None

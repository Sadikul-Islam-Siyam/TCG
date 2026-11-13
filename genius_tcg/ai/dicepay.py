"""CSP dice payment: assign distinct dice to cost slots, spending the least valuable dice first."""
from collections import Counter

from engine import csp
from engine.core import OMNI


def smart_pay(dice, cost, keep=()):
    """Variables = cost slots; domains = compatible dice; constraint = all different.
    Value ordering spends duplicates and off-colour dice first and keeps Omni / useful elements."""
    slots = {}
    ok_el = [i for i, d in enumerate(dice) if d in (cost.element, OMNI)]
    for k in range(cost.n):
        slots[("e", k)] = list(ok_el)
    for k in range(cost.unaligned):
        slots[("u", k)] = list(range(len(dice)))
    if not slots:
        return ()
    counts = Counter(dice)

    def worth(i):
        d = dice[i]
        return 100.0 if d == OMNI else (3.0 if d in keep else 1.0) / counts[d]

    sol = csp.solve(slots, [csp.AllDiff(slots)], var_key=lambda v: (v[0] != "e", v[1]), value_key=worth)
    return tuple(sorted(sol.values())) if sol else None

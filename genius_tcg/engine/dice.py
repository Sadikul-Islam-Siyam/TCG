"""Dice rolling and payment (cost solving)."""
from collections import Counter
from .core import DICE_FACES, DICE_WEIGHTS, OMNI


def roll(rng, n):
    return rng.choices(DICE_FACES, weights=DICE_WEIGHTS, k=n)


def payment_ok(dice, cost, idx):
    """True if the dice at `idx` exactly pay `cost`."""
    if len(set(idx)) != len(idx) or any(not 0 <= i < len(dice) for i in idx):
        return False
    if len(idx) != cost.n + cost.unaligned:
        return False
    good = sum(1 for i in idx if dice[i] in (cost.element, OMNI))
    return good >= cost.n


def auto_pay(dice, cost, keep=()):
    """Cheapest legal payment (tuple of dice indices) or None.
    Spends exact-element dice first, Omni last, and prefers elements the player has
    no character for when paying unaligned costs."""
    chosen, used, need = [], set(), cost.n
    for want in (cost.element, OMNI):
        for i, d in enumerate(dice):
            if need and d == want and i not in used:
                chosen.append(i); used.add(i); need -= 1
    if need:
        return None
    rest = [i for i in range(len(dice)) if i not in used]
    if len(rest) < cost.unaligned:
        return None
    counts = Counter(dice[i] for i in rest)

    def priority(i):
        d = dice[i]
        return (2, 0) if d == OMNI else (1 if d in keep else 0, -counts[d])

    rest.sort(key=priority)
    return tuple(sorted(chosen + rest[:cost.unaligned]))

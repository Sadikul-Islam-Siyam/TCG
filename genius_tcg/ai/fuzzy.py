"""Fuzzy logic: turns exact game numbers into fuzzy terms and fires rules that set the AI's
playing style (aggression, defence, burst desire, tempo) and the evaluation weights."""


def trap(x, a, b, c, d):
    """Trapezoid membership: 0 below a, rises to 1 at b, stays 1 until c, falls to 0 at d."""
    if x <= a or x >= d:
        return 1.0 if (b <= x <= c) else 0.0
    if x < b:
        return (x - a) / (b - a)
    if x <= c:
        return 1.0
    return (d - x) / (d - c)


def low(x):
    return trap(x, -1.0, -1.0, 0.25, 0.55)


def med(x):
    return trap(x, 0.25, 0.5, 0.5, 0.75)


def high(x):
    return trap(x, 0.45, 0.75, 2.0, 2.0)


def _ratio(P):
    tot = sum(c.defn.hp for c in P.characters)
    return sum(c.hp for c in P.characters if not c.defeated) / tot


def _energy(P):
    ch = P.active_char
    return ch.energy / ch.defn.max_energy if ch else 0.0


def inputs(s, me):
    P, Q = s.players[me], s.players[1 - me]
    return {"hp_me": _ratio(P), "hp_foe": _ratio(Q), "energy": _energy(P), "foe_energy": _energy(Q),
            "dice": min(len(P.dice) / 8, 1.5), "hand": len(P.hand) / 10}


def _defuzz(rules, default):
    """Weighted average of rule outputs (Sugeno style). rules = [(firing strength, output)]."""
    tot = sum(w for w, _ in rules)
    return sum(w * o for w, o in rules) / tot if tot > 1e-9 else default


def profile(s, me):
    x = inputs(s, me)
    aggression = _defuzz([
        (min(high(x["hp_me"]), low(x["hp_foe"])), 0.95),     # healthy and foe nearly dead: attack
        (min(med(x["hp_me"]), med(x["hp_foe"])), 0.55),
        (min(low(x["hp_me"]), high(x["hp_foe"])), 0.15),     # hurt and foe healthy: be careful
        (min(high(x["hp_me"]), high(x["hp_foe"])), 0.7),
        (min(low(x["hp_me"]), low(x["hp_foe"])), 0.5)], 0.5)
    defence = _defuzz([
        (low(x["hp_me"]), 0.9), (med(x["hp_me"]), 0.5), (high(x["hp_me"]), 0.15),
        (high(x["foe_energy"]), 0.8)], 0.4)
    burst = _defuzz([(high(x["energy"]), 0.95), (med(x["energy"]), 0.5), (low(x["energy"]), 0.15)], 0.5)
    tempo = _defuzz([(low(x["dice"]), 0.85), (med(x["dice"]), 0.5), (high(x["dice"]), 0.1)], 0.5)
    cards = _defuzz([(high(x["hand"]), 0.85), (med(x["hand"]), 0.55), (low(x["hand"]), 0.25)], 0.5)
    return {"aggression": aggression, "defence": defence, "burst": burst, "tempo": tempo, "cards": cards,
            # evaluation weights derived from the style
            "hp": 0.8 + 0.6 * defence, "energy": 0.8 + 0.6 * burst, "board": 1.0}

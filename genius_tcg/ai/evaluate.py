"""Heuristic position evaluation (positive = good for `me`)."""
from engine.registry import SUMMON_DEFS
from engine.rules import REACTIONS

DEFAULT = {"hp": 1.0, "energy": 1.0, "board": 1.0, "defence": 0.5}


def _side(P, Q, w, action_phase):
    v = 0.0
    foe_els = {c.defn.element for c in Q.characters if not c.defeated}
    for i, c in enumerate(P.characters):
        if c.defeated:
            continue
        d = c.defn
        v += 0.45 + 0.7 * w["hp"] * c.hp / d.hp
        v += w["energy"] * (c.energy / d.max_energy) * (0.25 if i == P.active else 0.12)
        v += 0.07 * len(c.equipment)
        if c.aura and any(frozenset((c.aura, e)) in REACTIONS for e in foe_els):
            v -= 0.08 * (0.5 + w["defence"])                 # exposed to a reaction
        if any(s.name in ("Frozen", "Petrified") for s in c.statuses):
            v -= 0.22
    for u in P.summons:
        sd = SUMMON_DEFS[u.name]
        v += 0.05 * sd.damage * min(u.usages, 3) * w["board"]
    for st in P.combat:
        v += 0.06 * (st.shield + 0.5 * (st.usages or 0))
    v += 0.07 * len(P.supports) + 0.02 * len(P.hand)
    if action_phase:
        v += 0.012 * len(P.dice)
    return v


def evaluate(s, me, w=None):
    if s.winner is not None:
        return 0.0 if s.winner == -1 else (6.0 if s.winner == me else -6.0)
    w = w or DEFAULT
    ap = s.phase == "action"
    return _side(s.players[me], s.players[1 - me], w, ap) - _side(s.players[1 - me], s.players[me], w, ap)

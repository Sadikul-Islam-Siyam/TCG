"""Informed search: A* over the actions inside ONE turn to find the cheapest way to defeat
the opponent's active character (lethal). f(n) = g(n) + h(n)."""
import heapq
import itertools
import math

from engine import rules
from .world import candidates

BEST_DAMAGE_PER_DIE = 2.5          # optimistic: keeps h from over-estimating


def _spent(s0, s, me):
    P0, P = s0.players[me], s.players[me]
    return (len(P0.dice) - len(P.dice)) + 0.3 * (len(P0.hand) - len(P.hand))


def _goal(s, me, target):
    c = s.players[1 - me].characters[target]
    return c.defeated or s.winner == me


def _h(s, me, target):
    c = s.players[1 - me].characters[target]
    return 0.0 if c.defeated else max(0.0, c.hp / BEST_DAMAGE_PER_DIE - 0.5)


def plan_lethal(state, me, max_expansions=250):
    """Returns the action list of the cheapest lethal line, or None. `state` should already be
    determinized; our own deck is emptied so the plan never counts on unseen draws."""
    foe = state.players[1 - me]
    if foe.active is None or rules.actor(state) != me or state.phase != "action":
        return None
    target = foe.active
    s0 = state.clone()
    s0.players[me].deck = []
    tie = itertools.count()
    open_ = [(_h(s0, me, target), 0.0, next(tie), s0, [])]
    seen, expansions = set(), 0
    while open_ and expansions < max_expansions:
        f, g, _, s, path = heapq.heappop(open_)
        if path and _goal(s, me, target):
            return path
        if rules.actor(s) != me or s.phase != "action" or s.winner is not None:
            continue                                            # turn ended without lethal: dead end
        expansions += 1
        for act in candidates(s, me):
            if act.type == "end_round":
                continue
            c = s.clone(share_rng=True)
            rules.apply_action(c, act)
            key = (tuple(sorted(c.players[me].dice)), tuple(sorted(c.players[me].hand)),
                   tuple(ch.hp for ch in c.players[1 - me].characters), c.players[me].active)
            if key in seen:
                continue
            seen.add(key)
            g2 = _spent(s0, c, me) + 0.05 * len(path)
            heapq.heappush(open_, (g2 + _h(c, me, target), g2, next(tie), c, path + [act]))
    return None

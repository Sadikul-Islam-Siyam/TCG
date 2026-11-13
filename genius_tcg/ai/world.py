"""Hidden-information handling: the AI never reads the opponent's real hand or any deck order."""
import random

from engine import deck as deckrules
from engine import rules


def determinize(state, me, rng):
    """A plausible full state consistent with what `me` can see. Dice, board and HP are public in the
    real game. The opponent's hand and both deck orders are re-sampled; `state` is never modified."""
    w = state.clone()
    w.rng = random.Random(rng.random())
    foe = w.players[1 - me]
    pool = []
    for n in deckrules.allowed_cards([c.name for c in foe.characters]):
        pool += [n, n]
    rng.shuffle(pool)
    n_hand, n_deck = len(foe.hand), len(foe.deck)
    foe.hand = pool[:n_hand]
    foe.deck = (pool[n_hand:] * 2)[:n_deck]
    mine = sorted(w.players[me].deck)          # sorted first: the real draw order must not leak
    rng.shuffle(mine)
    w.players[me].deck = mine
    return w


def candidates(s, me, allow_tune=False):
    """Moves worth searching: ordered best-first; the opponent's cards are not modelled."""
    a = rules.actor(s)
    acts = rules.legal_actions(s)
    out = [x for x in acts if allow_tune or x.type != "tune"]
    if a != me:
        out = [x for x in out if x.type != "card"]
    rank = {"skill": 0, "card": 1, "switch": 2, "choose_active": 0, "end_round": 3}
    out.sort(key=lambda x: (rank.get(x.type, 4), -x.index if x.type == "skill" else 0))
    return out or acts

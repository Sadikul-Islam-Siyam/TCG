"""Baseline AI: weighted random over legal actions (placeholder for the M5 AI suite)."""
import random
from engine import rules

WEIGHTS = {"skill": 6, "card": 3, "switch": 1, "tune": 1, "end_round": 1}


class RandomAI:
    def __init__(self, seed=None):
        self.rng = random.Random(seed)

    def choose(self, state):
        acts = rules.legal_actions(state)
        w = [WEIGHTS.get(a.type, 1) * (2 if a.type == "skill" and a.index == 2 else 1) for a in acts]
        return self.rng.choices(acts, weights=w)[0]

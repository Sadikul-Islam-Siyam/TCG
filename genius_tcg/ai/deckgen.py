"""The AI builds its own deck: random characters, then the CSP solver fills the 30 cards."""
import random

import content
from engine import deck
from content.presets import priority


def random_deck(rng=None):
    rng = rng or random.Random()
    chars = rng.sample(content.ROSTER, 3)
    pr = {n: p + rng.uniform(-2.5, 2.5) for n, p in priority().items()}      # a little personality
    return chars, deck.autofill(chars, priority=pr)

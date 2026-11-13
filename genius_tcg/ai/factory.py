"""Creates the AI opponent for a difficulty level: 'easy', 'normal' or 'hard'."""
from .players import AIPlayer


def make(level="normal", seed=None, **kw):
    return AIPlayer(level, seed, **kw)

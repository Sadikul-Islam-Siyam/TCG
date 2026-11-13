"""Headless AI-vs-AI runner: crash hunting and rough balance stats.
Usage: python simulate.py [games] [seed]"""
import random
import sys
from collections import Counter

import content
from ai.random_ai import RandomAI
from engine import rules


def play_game(seed, max_steps=3000):
    rng = random.Random(seed)
    decks = list(content.preset_decks().values())
    (c0, d0), (c1, d1) = rng.choice(decks), rng.choice(decks)
    s = rules.new_game(c0, d0, c1, d1, seed)
    bots = [RandomAI(seed * 2), RandomAI(seed * 2 + 1)]
    reactions, steps = Counter(), 0
    while s.phase != "over" and steps < max_steps and s.round <= 40:
        a = bots[rules.actor(s)].choose(s)
        rules.apply_action(s, a)
        for kind, info in s.events:
            if kind == "damage" and info["reaction"]:
                reactions[info["reaction"]] += 1
        steps += 1
    return s, steps, reactions


if __name__ == "__main__":
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 200
    seed0 = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    wins, rounds, steps_total, reacts = Counter(), 0, 0, Counter()
    for g in range(n):
        s, steps, r = play_game(seed0 + g)
        wins[s.winner] += 1
        rounds += s.round
        steps_total += steps
        reacts += r
    print(f"{n} games | P0 wins {wins[0]}  P1 wins {wins[1]}  draws/unfinished {wins[-1] + wins[None]}")
    print(f"avg rounds {rounds / n:.1f} | avg actions {steps_total / n:.0f}")
    print("reactions:", dict(reacts.most_common()))

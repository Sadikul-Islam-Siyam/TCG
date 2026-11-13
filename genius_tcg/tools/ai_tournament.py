"""Round-robin strength test. Every deck pairing is played twice with the seats swapped.
    python tools/ai_tournament.py [games_per_pairing] [time_scale]"""
import os, random, sys, time
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import content
from ai.players import AIPlayer
from ai.random_ai import RandomAI
from engine import rules


def make(name, seed, ts):
    return RandomAI(seed) if name == "random" else AIPlayer(name, seed, time_scale=ts)


def play(a_name, b_name, deck_a, deck_b, seed, ts):
    """Returns 1 if A wins, 0 if B wins, 0.5 draw. A sits in seat (seed % 2)."""
    seat = seed % 2
    decks = [deck_a, deck_b] if seat == 0 else [deck_b, deck_a]
    s = rules.new_game(decks[0][0], decks[0][1], decks[1][0], decks[1][1], seed)
    bots = [make(a_name if seat == 0 else b_name, seed, ts), make(b_name if seat == 0 else a_name, seed + 1, ts)]
    steps = 0
    while s.phase != "over" and s.round <= 30 and steps < 4000:
        rules.apply_action(s, bots[rules.actor(s)].choose(s))
        steps += 1
    if s.winner in (None, -1):
        return 0.5
    return 1.0 if s.winner == seat else 0.0


if __name__ == "__main__":
    games = int(sys.argv[1]) if len(sys.argv) > 1 else 20
    ts = float(sys.argv[2]) if len(sys.argv) > 2 else 1.0
    presets = list(content.preset_decks().values())
    pairs = [("easy", "random"), ("normal", "random"), ("hard", "random"),
             ("normal", "easy"), ("hard", "easy"), ("hard", "normal")]
    if len(sys.argv) > 3:                                   # e.g.  hard:normal easy:random
        pairs = [tuple(x.split(":")) for x in sys.argv[3:]]
    for a, b in pairs:
        rng = random.Random(7)
        score, t0 = 0.0, time.time()
        for g in range(games):
            da, db = rng.choice(presets), rng.choice(presets)
            score += play(a, b, da, db, 1000 + g, ts)
        print(f"{a:>6} vs {b:<6}: {score:.1f}/{games} = {100 * score / games:.0f}%   ({time.time() - t0:.0f}s)", flush=True)

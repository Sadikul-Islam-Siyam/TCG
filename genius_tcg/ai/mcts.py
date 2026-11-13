"""Monte Carlo simulation: single-observer Information-Set MCTS (UCT) with determinization.
Every iteration samples a fresh possible world (opponent hand / deck orders), walks the tree,
then plays a short fast rollout and scores the end position."""
import math
import random
import time

from engine import rules
from .evaluate import evaluate
from .world import candidates, determinize

C = 0.9
SCALE = 1.4


class Node:
    __slots__ = ("parent", "action", "children", "n", "w", "actor")

    def __init__(self, parent=None, action=None):
        self.parent, self.action, self.children, self.n, self.w, self.actor = parent, action, {}, 0, 0.0, None


def reward(s, me, prof):
    if s.winner is not None:
        return 0.5 if s.winner == -1 else (1.0 if s.winner == me else 0.0)
    return 1.0 / (1.0 + math.exp(-evaluate(s, me, prof) / SCALE))


def rollout(s, me, rng, depth, prof):
    for _ in range(depth):
        if s.winner is not None or (s.phase != "action" and not s.pending):
            break
        acts = candidates(s, me)
        skills = [a for a in acts if a.type == "skill"]
        if skills and rng.random() < 0.8:
            act = max(skills, key=lambda a: a.index) if rng.random() < 0.6 else rng.choice(skills)
        else:
            weights = [1 if a.type == "end_round" else 2 for a in acts]
            act = rng.choices(acts, weights=weights)[0]
        rules.apply_action(s, act)
    return reward(s, me, prof)


def best_action(state, me, prof, rng, time_limit=1.0, iters=400, rollout_depth=10, shortlist=None):
    root = Node()
    deadline = time.perf_counter() + time_limit
    for it in range(iters):
        if it >= 20 and time.perf_counter() > deadline:
            break
        s = determinize(state, me, rng)
        s.rng = random.Random(rng.random())
        node = root
        while s.winner is None and (s.phase == "action" or s.pending):
            acts = candidates(s, me)
            if shortlist and node is root:
                acts = [a for a in acts if a in shortlist] or acts
            node.actor = rules.actor(s)
            untried = [a for a in acts if a not in node.children]
            if untried:
                act = untried[0] if node.n < 3 else rng.choice(untried)
                child = Node(node, act)
                node.children[act] = child
                rules.apply_action(s, act)
                node = child
                break
            best, best_v = None, -1e9
            for a in acts:
                ch = node.children[a]
                q = ch.w / ch.n if ch.n else 0.5
                q = q if node.actor == me else 1 - q
                v = q + C * math.sqrt(math.log(node.n + 1) / (ch.n + 1))
                if v > best_v:
                    best, best_v = ch, v
            rules.apply_action(s, best.action)
            node = best
        r = rollout(s, me, rng, rollout_depth, prof)
        while node is not None:
            node.n += 1
            node.w += r
            node = node.parent
    if not root.children:
        return candidates(state, me)[0]
    legal = set(candidates(state, me))
    pool = [ch for a, ch in root.children.items() if a in legal] or list(root.children.values())
    return max(pool, key=lambda ch: ch.n).action

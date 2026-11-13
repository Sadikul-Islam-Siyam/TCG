"""Adversarial search: depth-limited alpha-beta (minimax) with iterative deepening."""
import math
import time

from engine import rules
from .evaluate import evaluate
from .world import candidates


class Searcher:
    def __init__(self, me, prof=None, time_limit=0.5, max_nodes=6000):
        self.me, self.prof = me, prof
        self.deadline = time.perf_counter() + time_limit
        self.max_nodes, self.nodes, self.aborted = max_nodes, 0, False

    def leaf(self, s):
        return s.winner is not None or (s.phase != "action" and not s.pending)

    def value(self, s, depth, alpha, beta):
        self.nodes += 1
        if depth == 0 or self.leaf(s):
            return evaluate(s, self.me, self.prof)
        if self.nodes > self.max_nodes or time.perf_counter() > self.deadline:
            self.aborted = True
            return evaluate(s, self.me, self.prof)
        maximizing = rules.actor(s) == self.me
        best = -math.inf if maximizing else math.inf
        for act in candidates(s, self.me):
            c = s.clone(share_rng=True)
            rules.apply_action(c, act)
            v = self.value(c, depth - self.cost(act), alpha, beta) + self.end_penalty(s, act)
            if maximizing:
                best = max(best, v); alpha = max(alpha, v)
            else:
                best = min(best, v); beta = min(beta, v)
            if beta <= alpha or self.aborted:
                break
        return best

    @staticmethod
    def cost(act):
        """Depth is counted in turn-ending moves: fast actions (cards, tuning, choosing a replacement) are free, which avoids
        the horizon effect of preferring lines that stop before the opponent can reply."""
        return 1 if act.type in ("skill", "switch", "end_round") else 0

    def end_penalty(self, s, act):
        """Ending the round with dice left over wastes them; scaled by how rich we are."""
        if act.type != "end_round":
            return 0.0
        waste = 0.014 * len(s.players[act.player].dice) * (1.5 - (self.prof or {}).get("tempo", 0.5))
        bonus = 0.03 if s.first_ender is None else 0.0           # ending first = go first next round
        return (bonus - waste) * (1 if act.player == self.me else -1)

    def root_scores(self, s, depth=4):
        """Value of every candidate move at a fixed depth (used to shortlist moves for MCTS)."""
        out = {}
        for act in candidates(s, self.me):
            c = s.clone(share_rng=True)
            rules.apply_action(c, act)
            out[act] = self.value(c, depth - self.cost(act), -math.inf, math.inf) + self.end_penalty(s, act)
        return out

    def best_move(self, s, max_depth=4):
        acts = candidates(s, self.me)
        best_act = acts[0]
        for depth in range(1, max_depth + 1):
            scored, alpha = [], -math.inf
            self.aborted = False
            for act in acts:
                c = s.clone(share_rng=True)
                rules.apply_action(c, act)
                v = self.value(c, depth - self.cost(act), alpha, math.inf) + self.end_penalty(s, act)
                scored.append((v, act))
                alpha = max(alpha, v)
                if self.aborted:
                    break
            if self.aborted and depth > 1:
                break                                            # keep the last fully searched depth
            best_act = max(scored, key=lambda t: t[0])[1]
            acts = [a for _, a in sorted(scored, key=lambda t: -t[0])] + [a for a in acts if a not in {x for _, x in scored}]
            if self.aborted:
                break
        return best_act

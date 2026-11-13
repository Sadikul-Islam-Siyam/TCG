"""The AI opponents. All three use the same public interface:  choose(state) -> Action.

  easy   fuzzy logic (style + evaluation weights) with a one-move look-ahead and some mistakes
  normal A* lethal planner + alpha-beta search (fuzzy-weighted evaluation)
  hard   A* lethal planner + Monte Carlo tree search over sampled hidden information
CSP picks which dice to pay with. choose() never modifies the state it is given."""
import random
from dataclasses import replace

from engine import rules
from engine.core import Action, Cost, OMNI
from engine.registry import CARD_DEFS
from . import fuzzy, mcts, planner
from .dicepay import smart_pay
from .evaluate import evaluate
from .search import Searcher
from .world import candidates, determinize

LEVELS = {
    "easy": {"eps": 0.18},
    "normal": {"depth": 4, "time": 0.6, "nodes": 6000},
    "hard": {"time": 1.6, "iters": 700},
}


class AIPlayer:
    def __init__(self, level="normal", seed=None, time_scale=1.0, iters=None):
        if level not in LEVELS:
            raise ValueError(f"unknown AI level {level!r}")
        self.level, self.cfg = level, dict(LEVELS[level])
        self.rng = random.Random(seed)
        self.time_scale = time_scale
        if iters is not None:
            self.cfg["iters"] = iters

    # ------------------------------------------------------------------ entry point
    def choose(self, state):
        me = rules.actor(state)
        acts = rules.legal_actions(state)
        if len(acts) == 1:
            return acts[0]
        if state.pending:
            return self._best_by_eval(state, me, acts, noise=self.level == "easy")
        if state.phase == "setup":
            return self._setup(state, me, acts)
        if state.phase == "roll":
            return next((a for a in acts if a.type == "reroll"), acts[0])
        return self._act(state, me, acts)

    # ------------------------------------------------------------------ setup / roll / pending
    def _setup(self, s, me, acts):
        P = s.players[me]
        if acts[0].type == "mulligan":
            costs = [CARD_DEFS[n].cost.n + CARD_DEFS[n].cost.unaligned for n in P.hand]
            swap = [i for i, n in enumerate(P.hand) if costs[i] >= 4 or P.hand[:i].count(n) >= 1 and CARD_DEFS[n].kind in ("weapon", "artifact")]
            return Action("mulligan", me, ids=tuple(swap[:3]))
        # starting character: quick burst (low max energy) and a reaction partner on the team
        def score(a):
            d = P.characters[a.index].defn
            friends = sum(1 for c in P.characters if c.defn.element != d.element)
            return -d.max_energy + 0.3 * friends + self.rng.random() * 0.2
        return max(acts, key=score)

    def _best_by_eval(self, s, me, acts, noise=False):
        if noise and self.rng.random() < 0.3:
            return self.rng.choice(acts)
        best, best_v = acts[0], -1e9
        for a in acts:
            c = s.clone()
            rules.apply_action(c, a)
            v = evaluate(c, me) + (self.rng.random() * 0.05)
            if v > best_v:
                best, best_v = a, v
        return best

    # ------------------------------------------------------------------ action phase
    def _act(self, s, me, acts):
        prof = fuzzy.profile(s, me)
        tune = self._tune(s, me)
        if tune:
            return tune
        world = determinize(s, me, self.rng)
        if self.level != "easy":
            plan = planner.plan_lethal(world, me)
            if plan:
                return self._pay(s, me, plan[0])
        if self.level == "easy":
            act = self._easy(world, me, prof)
        elif self.level == "normal":
            sr = Searcher(me, prof, self.cfg["time"] * self.time_scale, self.cfg["nodes"])
            act = sr.best_move(world, self.cfg["depth"])
        else:
            t = self.cfg["time"] * self.time_scale
            ab = Searcher(me, prof, t * 0.35, 9000).root_scores(world, 4)      # alpha-beta shortlists the moves
            top = set(sorted(ab, key=ab.get, reverse=True)[:4])
            act = mcts.best_action(s, me, prof, self.rng, t * 0.65, self.cfg["iters"], shortlist=top)
        return self._pay(s, me, act)

    def _easy(self, world, me, prof):
        before = evaluate(world, me, prof)
        scored = []
        for a in candidates(world, me):
            c = world.clone()
            rules.apply_action(c, a)
            v = evaluate(c, me, prof) - before
            if a.type == "skill" and a.index == 2:
                v += 0.15 * prof["burst"]
            elif a.type == "card":
                v += 0.04 * prof["cards"]
            elif a.type == "end_round":
                v += 0.25 * prof["tempo"] - 0.012 * len(world.players[me].dice)
            elif a.type == "switch":
                v += 0.1 * prof["defence"] - 0.05 * prof["aggression"]
            scored.append((v, self.rng.random(), a))
        scored.sort(key=lambda t: t[:2], reverse=True)
        if self.rng.random() < self.cfg["eps"] and len(scored) > 1:
            return self.rng.choice(scored[: min(3, len(scored))])[2]
        return scored[0][2]

    def _tune(self, s, me):
        """If a skill is exactly one die short of its element, convert a die using the least useful card."""
        P = s.players[me]
        ch = P.active_char
        if not ch or not P.hand or rules.stunned(ch):
            return None
        acts = rules.legal_actions(s)
        if any(a.type == "skill" and a.index >= 1 for a in acts):
            return None
        el = ch.defn.element
        for i, sk in enumerate(ch.defn.skills):
            if i == 0 or (sk.cost.energy and ch.energy < sk.cost.energy):
                continue
            have = sum(1 for d in P.dice if d in (el, OMNI))
            if sk.cost.n - have == 1 and len(P.dice) >= sk.cost.n + sk.cost.unaligned:
                die = next((j for j, d in enumerate(P.dice) if d not in (el, OMNI)), None)
                if die is not None:
                    return Action("tune", me, index=self._least_useful(P), target=die)
        return None

    def _least_useful(self, P):
        pri = {"event": 1, "support": 2, "weapon": 3, "artifact": 3, "talent": 4}
        return min(range(len(P.hand)), key=lambda i: (pri[CARD_DEFS[P.hand[i]].kind], -(CARD_DEFS[P.hand[i]].cost.n + CARD_DEFS[P.hand[i]].cost.unaligned)))

    # ------------------------------------------------------------------ payment (CSP)
    def _pay(self, s, me, act):
        P = s.players[me]
        if act.type == "skill":
            cost = P.active_char.defn.skills[act.index].cost
        elif act.type == "card":
            cost = CARD_DEFS[P.hand[act.index]].cost
        elif act.type == "switch":
            cost = rules._switch_cost(P)
        else:
            return act
        keep = tuple({c.defn.element for c in P.characters if not c.defeated})
        pay = smart_pay(P.dice, cost, keep)
        return replace(act, dice=pay) if pay is not None else act

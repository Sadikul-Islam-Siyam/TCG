"""Mutable game-state classes. Everything has a fast clone() for AI search."""
import random
from .registry import CHAR_DEFS


class Status:
    __slots__ = ("name", "usages", "duration", "shield")

    def __init__(self, name, usages=None, duration=None, shield=0):
        self.name, self.usages, self.duration, self.shield = name, usages, duration, shield

    def clone(self):
        return Status(self.name, self.usages, self.duration, self.shield)


class Unit:
    """A summon or a support card on the board."""
    __slots__ = ("name", "usages")

    def __init__(self, name, usages=None):
        self.name, self.usages = name, usages

    def clone(self):
        return Unit(self.name, self.usages)


class Character:
    __slots__ = ("name", "hp", "energy", "aura", "statuses", "defeated", "equipment")

    def __init__(self, name):
        self.name, self.hp, self.energy = name, CHAR_DEFS[name].hp, 0
        self.aura, self.statuses, self.defeated, self.equipment = None, [], False, {}

    @property
    def defn(self):
        return CHAR_DEFS[self.name]

    def clone(self):
        c = Character.__new__(Character)
        c.name, c.hp, c.energy, c.aura, c.defeated = self.name, self.hp, self.energy, self.aura, self.defeated
        c.statuses = [s.clone() for s in self.statuses]
        c.equipment = dict(self.equipment)
        return c


class Player:
    def __init__(self, chars, deck):
        self.characters = [Character(c) for c in chars]
        self.deck, self.hand, self.dice = list(deck), [], []
        self.summons, self.supports, self.combat = [], [], []
        self.active = None
        self.ended = self.mull_done = self.roll_done = False
        self.chosen, self.rerolls = None, 0

    @property
    def active_char(self):
        return None if self.active is None else self.characters[self.active]

    def clone(self):
        p = Player.__new__(Player)
        p.characters = [c.clone() for c in self.characters]
        p.deck, p.hand, p.dice = list(self.deck), list(self.hand), list(self.dice)
        p.summons = [u.clone() for u in self.summons]
        p.supports = [u.clone() for u in self.supports]
        p.combat = [s.clone() for s in self.combat]
        p.active, p.ended, p.mull_done, p.roll_done = self.active, self.ended, self.mull_done, self.roll_done
        p.chosen, p.rerolls = self.chosen, self.rerolls
        return p


class GameState:
    def __init__(self, rng):
        self.players, self.rng = [], rng
        self.phase, self.round = "setup", 1          # setup roll action end over
        self.current = self.first_player = 0
        self.first_ender, self.pending, self.winner = None, [], None
        self.log, self.events = [], []              # events: structured, for the UI to animate

    def clone(self, keep_log=False, share_rng=False):
        """share_rng=True is for AI search on an already-determinized copy (never the live game)."""
        g = GameState.__new__(GameState)
        g.players = [p.clone() for p in self.players]
        if share_rng:
            g.rng = self.rng
        else:
            g.rng = random.Random(); g.rng.setstate(self.rng.getstate())
        g.phase, g.round, g.current, g.first_player = self.phase, self.round, self.current, self.first_player
        g.first_ender, g.pending, g.winner = self.first_ender, list(self.pending), self.winner
        g.log, g.events = (list(self.log) if keep_log else []), []
        return g

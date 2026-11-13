"""Game rules: setup, round flow, actions, and the damage / reaction pipeline.

Public API
    new_game(chars0, deck0, chars1, deck1, seed)  -> GameState
    legal_actions(state)                          -> list[Action]   (for state.actor)
    apply_action(state, action)                   -> state          (mutates; clone() first for search)
    actor(state)                                  -> player index who must act, or None
"""
from __future__ import annotations
from .core import *                      # noqa: F401,F403
from .core import (Action, Cost, IllegalAction, AURA_ELEMENTS, CRYO, HYDRO, PYRO, ELECTRO,
                   ANEMO, GEO, OMNI, PHYSICAL, PIERCING, DICE_FACES, DICE_PER_ROUND, MAX_DICE,
                   MAX_HAND, MAX_SUMMONS, MAX_SUPPORTS, HAND_START, DRAW_END)
from . import dice as D
from .model import Status, Unit, Player, GameState
from .registry import STATUS_DEFS, SUMMON_DEFS, CARD_DEFS

# pair of elements -> (reaction name, bonus damage)
REACTIONS = {
    frozenset((HYDRO, PYRO)): ("Vaporize", 1),
    frozenset((CRYO, PYRO)): ("Melt", 2),
    frozenset((PYRO, ELECTRO)): ("Overloaded", 2),
    frozenset((CRYO, ELECTRO)): ("Superconduct", 1),
    frozenset((HYDRO, ELECTRO)): ("Electro-Charged", 1),
    frozenset((CRYO, HYDRO)): ("Frozen", 1),
}


# ----------------------------------------------------------------------------- helpers
def alive(P):
    return [i for i, c in enumerate(P.characters) if not c.defeated]


def has_status(ch, name):
    return any(s.name == name for s in ch.statuses)


def remove_status(ch, name):
    ch.statuses = [s for s in ch.statuses if s.name != name]


def stunned(ch):
    return has_status(ch, "Frozen") or has_status(ch, "Petrified")


def add_status(lst, name):
    df = STATUS_DEFS[name]
    for st in lst:
        if st.name == name:
            if df.usages is not None:
                st.usages = df.usages
            if df.duration is not None:
                st.duration = df.duration
            if df.shield:
                st.shield = min(df.max_shield, st.shield + df.shield)
            return st
    st = Status(name, df.usages, df.duration, df.shield)
    lst.append(st)
    return st


def _spent(st):
    df = STATUS_DEFS[st.name]
    if df.per_round:
        return False
    return (st.usages is not None and st.usages <= 0) or (df.shield > 0 and st.shield <= 0)


def _next_alive(P, idx):
    for k in (1, 2):
        j = (idx + k) % 3
        if not P.characters[j].defeated:
            return j
    return None


def _foe_target(s, pi):
    F = s.players[1 - pi]
    if F.active is not None and not F.characters[F.active].defeated:
        return F.active
    a = alive(F)
    return a[0] if a else None


def _event(s, kind, /, **info):
    s.events.append((kind, info))


def _draw(s, pi, n):
    P = s.players[pi]
    for _ in range(n):
        if P.deck:
            c = P.deck.pop()
            if len(P.hand) < MAX_HAND:
                P.hand.append(c)


def force_switch(s, pi):
    P = s.players[pi]
    if P.active is None:
        return
    n = _next_alive(P, P.active)
    if n is not None:
        P.active = n
        _event(s, "switch", player=pi, char=n, forced=True)


# ----------------------------------------------------------------------------- effect context
class Ctx:
    """What skill / card effects use to change the game. `pi` is the acting player."""

    def __init__(self, state, pi, kind=None):
        self.s, self.pi, self.kind = state, pi, kind

    me = property(lambda self: self.s.players[self.pi])
    foe = property(lambda self: self.s.players[1 - self.pi])

    def damage(self, n, dtype):
        t = _foe_target(self.s, self.pi)
        if t is not None:
            deal_damage(self.s, self.pi, 1 - self.pi, t, n, dtype, "skill" if self.kind else "effect", self.kind)

    def piercing_others(self, n):
        F = self.foe
        for i, c in enumerate(F.characters):
            if i != F.active and not c.defeated:
                deal_damage(self.s, self.pi, 1 - self.pi, i, n, PIERCING, "effect")

    def heal(self, n, idx=None):
        P = self.me
        idx = P.active if idx is None else idx
        if idx is None:
            return
        c = P.characters[idx]
        if not c.defeated:
            c.hp = min(c.defn.hp, c.hp + n)
            _event(self.s, "heal", player=self.pi, char=idx, amount=n)

    def summon(self, name):
        P, d = self.me, SUMMON_DEFS[name]
        for u in P.summons:
            if u.name == name:
                u.usages = d.usages
                return
        if len(P.summons) >= MAX_SUMMONS:
            P.summons.pop(0)
        P.summons.append(Unit(name, d.usages))
        _event(self.s, "summon", player=self.pi, name=name)

    def combat_status(self, name):
        add_status(self.me.combat, name)

    def char_status(self, name, idx=None):
        P = self.me
        idx = P.active if idx is None else idx
        if idx is not None and not P.characters[idx].defeated:
            add_status(P.characters[idx].statuses, name)

    def foe_char_status(self, name):
        t = _foe_target(self.s, self.pi)
        if t is not None:
            add_status(self.foe.characters[t].statuses, name)

    def force_switch_foe(self):
        force_switch(self.s, 1 - self.pi)

    def draw(self, n):
        _draw(self.s, self.pi, n)

    def gain_energy(self, n):
        ch = self.me.active_char
        if ch:
            ch.energy = min(ch.defn.max_energy, ch.energy + n)

    def heal_most_injured(self, n):
        P = self.me
        hurt = [(c.defn.hp - c.hp, i) for i, c in enumerate(P.characters) if not c.defeated and c.hp < c.defn.hp]
        if hurt:
            self.heal(n, max(hurt)[1])

    def gain_dice(self, n, die):
        P = self.me
        for _ in range(n):
            if len(P.dice) < MAX_DICE:
                P.dice.append(die)


# ----------------------------------------------------------------------------- damage pipeline
def _each_status(P, ch):
    return list(ch.statuses if ch else []) + list(P.combat)


def _outgoing(s, sp, d):
    P = s.players[sp]
    for st in _each_status(P, P.active_char):
        df = STATUS_DEFS.get(st.name)
        if df and df.outgoing:
            df.outgoing(s, sp, st, d)


def _after_skill(s, sp, kind):
    P = s.players[sp]
    for st in _each_status(P, P.active_char):
        df = STATUS_DEFS.get(st.name)
        if df and df.after_skill:
            df.after_skill(s, sp, st, kind)
    for c in P.characters:
        c.statuses = [x for x in c.statuses if not _spent(x)]
    P.combat = [x for x in P.combat if not _spent(x)]


def deal_damage(s, sp, tp, ti, amount, dtype, source="skill", kind=None):
    """1) outgoing modifiers  2) frozen bonus  3) aura / reaction  4) shields  5) HP  6) side effects."""
    P = s.players[tp]
    tgt = P.characters[ti]
    if tgt.defeated:
        return
    if source == "skill":
        d = {"amount": amount, "dtype": dtype, "kind": kind}
        _outgoing(s, sp, d)
        amount, dtype = d["amount"], d["dtype"]

    reaction = swirled = None
    if dtype in (PHYSICAL, PYRO) and has_status(tgt, "Frozen"):
        amount += 2
        remove_status(tgt, "Frozen")
    if dtype in AURA_ELEMENTS:
        if tgt.aura is None:
            tgt.aura = dtype
        elif tgt.aura != dtype:
            reaction, bonus = REACTIONS[frozenset((tgt.aura, dtype))]
            amount += bonus
            tgt.aura = None
    elif dtype in (ANEMO, GEO) and tgt.aura:
        swirled, tgt.aura = tgt.aura, None
        reaction = "Swirl" if dtype == ANEMO else "Crystallize"
        if dtype == GEO:
            amount += 1

    if dtype != PIERCING and ti == P.active:
        for st in list(P.combat):
            df = STATUS_DEFS[st.name]
            if df.reduce and st.usages and amount >= df.reduce_min:
                amount = max(0, amount - df.reduce)
                st.usages -= 1
        for st in P.combat:
            if st.shield > 0 and amount > 0:
                absorbed = min(st.shield, amount)
                st.shield -= absorbed
                amount -= absorbed
        P.combat = [x for x in P.combat if not _spent(x)]

    tgt.hp = max(0, tgt.hp - amount)
    _event(s, "damage", player=tp, char=ti, amount=amount, dtype=dtype, reaction=reaction, source=source)
    s.log.append(f"P{sp}->P{tp}.{tgt.name}: {amount} {dtype}" + (f" [{reaction}]" if reaction else ""))
    if tgt.hp == 0:
        _defeat(s, tp, ti, sp)

    if reaction == "Overloaded" and not tgt.defeated and P.active == ti:
        force_switch(s, tp)
    elif reaction in ("Superconduct", "Electro-Charged"):
        for j, c in enumerate(P.characters):
            if j != ti and not c.defeated:
                deal_damage(s, sp, tp, j, 1, PIERCING, "reaction")
    elif reaction == "Frozen" and not tgt.defeated:
        add_status(tgt.statuses, "Frozen")
    elif reaction == "Swirl":
        for j, c in enumerate(P.characters):
            if j != ti and not c.defeated:
                deal_damage(s, sp, tp, j, 1, swirled, "swirl")
    elif reaction == "Crystallize":
        add_status(s.players[sp].combat, "Crystallize Shield")


def _defeat(s, pi, ci, killer=None):
    P = s.players[pi]
    c = P.characters[ci]
    c.hp, c.energy, c.aura, c.statuses, c.defeated, c.equipment = 0, 0, None, [], True, {}
    s.log.append(f"P{pi}.{c.name} defeated")
    _event(s, "defeat", player=pi, char=ci)
    if P.active == ci:
        P.active = None
        if alive(P) and pi not in s.pending:
            s.pending.append(pi)
    _check_win(s)
    if killer is not None and s.winner is None:
        A = s.players[killer]
        for st in _each_status(A, A.active_char):
            df = STATUS_DEFS.get(st.name)
            if df and df.on_kill:
                df.on_kill(s, killer, st)


def _check_win(s):
    lost = [all(c.defeated for c in P.characters) for P in s.players]
    if lost[0] and lost[1]:
        s.winner = -1
    elif lost[0]:
        s.winner = 1
    elif lost[1]:
        s.winner = 0
    if s.winner is not None:
        s.phase = "over"
        s.pending = []


# ----------------------------------------------------------------------------- game flow
def new_game(chars0, deck0, chars1, deck1, seed=None):
    import content  # noqa: F401  (registers characters / cards / statuses)
    import random
    s = GameState(random.Random(seed))
    s.players = [Player(chars0, deck0), Player(chars1, deck1)]
    for p in range(2):
        s.rng.shuffle(s.players[p].deck)
        _draw(s, p, HAND_START)
    s.first_player = s.rng.randrange(2)
    s.current = s.first_player
    return s


def actor(s):
    if s.phase == "over":
        return None
    if s.pending:
        return s.pending[0]
    order = (s.first_player, 1 - s.first_player)
    if s.phase == "setup":
        for p in order:
            if not s.players[p].mull_done:
                return p
        for p in order:
            if s.players[p].chosen is None:
                return p
    if s.phase == "roll":
        for p in order:
            if not s.players[p].roll_done:
                return p
    if s.phase == "action":
        return s.current
    return None


def _begin_round(s, first=False):
    if not first:
        s.round += 1
        s.first_player = s.first_ender
    s.first_ender, s.phase = None, "roll"
    for P in s.players:
        P.dice, P.rerolls, P.roll_done, P.ended = D.roll(s.rng, DICE_PER_ROUND), 1, False, False
    s.log.append(f"-- Round {s.round} --")
    _event(s, "round", number=s.round)


def _start_action(s):
    s.phase, s.current = "action", s.first_player
    _event(s, "phase", name="action", first=s.first_player)
    for p in (s.first_player, 1 - s.first_player):
        P = s.players[p]
        for u in list(P.supports):
            cd = CARD_DEFS[u.name]
            if cd.action_start:
                cd.action_start(Ctx(s, p))
                u.usages -= 1
        P.supports = [u for u in P.supports if u.usages is None or u.usages > 0]


def _tick(lst):
    out = []
    for st in lst:
        if st.duration is not None:
            st.duration -= 1
            if st.duration <= 0:
                continue
        out.append(st)
    return out


def _reset_round(lst):
    for st in lst:
        df = STATUS_DEFS[st.name]
        if df.per_round:
            st.usages = df.per_round


def _end_phase(s):
    s.phase = "end"
    _event(s, "phase", name="end", first=s.first_ender)
    order = (s.first_ender, 1 - s.first_ender)
    for p in order:
        P = s.players[p]
        for u in list(P.summons):
            d = SUMMON_DEFS[u.name]
            t = _foe_target(s, p)
            if t is not None:
                deal_damage(s, p, 1 - p, t, d.damage, d.element, "summon")
            u.usages -= 1
        P.summons = [u for u in P.summons if u.usages > 0]
        for u in list(P.supports):
            cd = CARD_DEFS[u.name]
            if cd.end_phase:
                cd.end_phase(Ctx(s, p))
                u.usages -= 1
        P.supports = [u for u in P.supports if u.usages is None or u.usages > 0]
        if s.winner is not None:
            return
    for P in s.players:
        for c in P.characters:
            remove_status(c, "Frozen")
            remove_status(c, "Petrified")
            c.statuses = _tick(c.statuses)
            _reset_round(c.statuses)
        P.combat = _tick(P.combat)
        _reset_round(P.combat)
    for p in order:
        _draw(s, p, DRAW_END)
    _begin_round(s)


def _end_turn(s, p):
    if s.phase == "action" and not s.players[1 - p].ended:
        s.current = 1 - p


def _use_combat(P, name):
    """Consume one usage of a combat status if present; True if it was there."""
    for st in P.combat:
        if st.name == name:
            st.usages -= 1
            P.combat = [x for x in P.combat if not _spent(x)]
            return True
    return False


def _switch_cost(P):
    return Cost() if any(st.name == "Changing Shifts" for st in P.combat) else Cost(unaligned=1)


def _targets(P, cd):
    """Legal target indices for a card (-1 = no target needed)."""
    al = alive(P)
    if cd.kind == "talent":
        ch = P.active_char
        if ch and ch.name == cd.char and not stunned(ch) and ch.energy >= ch.defn.skills[cd.skill].cost.energy:
            return [P.active]
        return []
    if cd.kind == "weapon":
        return [i for i in al if P.characters[i].defn.weapon == cd.weapon]
    if cd.kind == "artifact" or cd.needs_char:
        return al
    if cd.kind == "support" and len(P.supports) >= MAX_SUPPORTS:
        return []
    return [-1]


# ----------------------------------------------------------------------------- legal actions
def legal_actions(s):
    p = actor(s)
    if p is None:
        return []
    P = s.players[p]
    if s.pending:
        return [Action("choose_active", p, index=i) for i in alive(P)]
    if s.phase == "setup":
        if not P.mull_done:
            return [Action("mulligan", p), Action("mulligan", p, ids=tuple(range(len(P.hand))))]
        return [Action("choose_active", p, index=i) for i in range(3)]
    elems = tuple({P.characters[i].defn.element for i in alive(P)})
    if s.phase == "roll":
        acts = [Action("confirm_roll", p)]
        junk = tuple(i for i, d in enumerate(P.dice) if d != OMNI and d not in elems)
        if P.rerolls > 0 and junk:
            acts.append(Action("reroll", p, ids=junk))
        return acts

    acts, ch = [], P.active_char
    if ch and not stunned(ch):
        for i, sk in enumerate(ch.defn.skills):
            if sk.cost.energy and ch.energy < sk.cost.energy:
                continue
            pay = D.auto_pay(P.dice, sk.cost, elems)
            if pay is not None:
                acts.append(Action("skill", p, index=i, dice=pay))
    pay = D.auto_pay(P.dice, _switch_cost(P), elems)
    if pay is not None:
        acts += [Action("switch", p, index=i, dice=pay) for i in alive(P) if i != P.active]
    seen = set()
    for hi, name in enumerate(P.hand):
        if name in seen:
            continue
        seen.add(name)
        cd = CARD_DEFS[name]
        pay = D.auto_pay(P.dice, cd.cost, elems)
        if pay is None:
            continue
        acts += [Action("card", p, index=hi, target=t, dice=pay) for t in _targets(P, cd)]
    if ch:
        faces = set()
        for di, d in enumerate(P.dice):
            if d not in (OMNI, ch.defn.element) and d not in faces:
                faces.add(d)
                seen = set()
                for hi, name in enumerate(P.hand):
                    if name not in seen:
                        seen.add(name)
                        acts.append(Action("tune", p, index=hi, target=di))
    acts.append(Action("end_round", p))
    return acts


# ----------------------------------------------------------------------------- apply actions
def _pay(P, cost, idx):
    if not D.payment_ok(P.dice, cost, tuple(idx)):
        raise IllegalAction("invalid dice payment")
    for i in sorted(idx, reverse=True):
        del P.dice[i]


def _mulligan(s, a):
    P = s.players[a.player]
    ids = sorted(set(a.ids))
    if P.mull_done or any(not 0 <= i < len(P.hand) for i in ids):
        raise IllegalAction("bad mulligan")
    out = [P.hand[i] for i in ids]
    P.hand = [c for i, c in enumerate(P.hand) if i not in ids]
    P.deck.extend(out)
    s.rng.shuffle(P.deck)
    _draw(s, a.player, len(out))
    P.mull_done = True


def _choose_active(s, a):
    P = s.players[a.player]
    if not 0 <= a.index < 3 or P.characters[a.index].defeated:
        raise IllegalAction("bad character")
    if s.pending:
        P.active = a.index
        s.pending.remove(a.player)
        _event(s, "switch", player=a.player, char=a.index, forced=True)
        return
    if not P.mull_done:
        raise IllegalAction("mulligan first")
    P.chosen = a.index
    if all(p.chosen is not None for p in s.players):
        for p in s.players:
            p.active = p.chosen
        _begin_round(s, first=True)


def _reroll(s, a):
    P = s.players[a.player]
    if P.rerolls <= 0 or any(not 0 <= i < len(P.dice) for i in a.ids):
        raise IllegalAction("bad reroll")
    ids = sorted(set(a.ids))
    for i, d in zip(ids, D.roll(s.rng, len(ids))):
        P.dice[i] = d
    P.rerolls -= 1


def _confirm_roll(s, a):
    s.players[a.player].roll_done = True
    if all(p.roll_done for p in s.players):
        _start_action(s)


def _skill(s, a):
    P = s.players[a.player]
    ch = P.active_char
    if ch is None or stunned(ch) or not 0 <= a.index < len(ch.defn.skills):
        raise IllegalAction("cannot use skill")
    sk = ch.defn.skills[a.index]
    if sk.cost.energy and ch.energy < sk.cost.energy:
        raise IllegalAction("not enough energy")
    _pay(P, sk.cost, a.dice)
    _perform_skill(s, a.player, a.index)


def _perform_skill(s, pi, idx):
    """Resolve a skill (cost already paid): energy, effect, after-skill hooks, turn passes."""
    P = s.players[pi]
    ch = P.active_char
    sk = ch.defn.skills[idx]
    if sk.kind == "burst":
        ch.energy -= sk.cost.energy
    else:
        ch.energy = min(ch.defn.max_energy, ch.energy + 1)
    _event(s, "skill", player=pi, char=P.active, skill=sk.name, kind=sk.kind)
    s.log.append(f"P{pi}.{ch.name} uses {sk.name}")
    sk.effect(Ctx(s, pi, sk.kind))
    _after_skill(s, pi, sk.kind)
    _check_win(s)
    _end_turn(s, pi)


def _switch(s, a):
    P = s.players[a.player]
    if not 0 <= a.index < 3 or a.index == P.active or P.characters[a.index].defeated:
        raise IllegalAction("bad switch target")
    shifted = _switch_cost(P).unaligned == 0
    _pay(P, _switch_cost(P), a.dice)
    if shifted:
        _use_combat(P, "Changing Shifts")
    P.active = a.index
    _event(s, "switch", player=a.player, char=a.index, forced=False)
    if not _use_combat(P, "Leave It to Me!"):     # that card makes this switch a Fast Action
        _end_turn(s, a.player)


def _equip(ch, cd):
    old = ch.equipment.get(cd.kind)
    if old and CARD_DEFS[old].status:
        remove_status(ch, CARD_DEFS[old].status)
    ch.equipment[cd.kind] = cd.name
    if cd.status:
        add_status(ch.statuses, cd.status)


def _card(s, a):
    P = s.players[a.player]
    if not 0 <= a.index < len(P.hand):
        raise IllegalAction("bad card")
    cd = CARD_DEFS[P.hand[a.index]]
    if a.target not in _targets(P, cd):
        raise IllegalAction("bad card target")
    _pay(P, cd.cost, a.dice)
    del P.hand[a.index]
    _event(s, "card", player=a.player, name=cd.name)
    if cd.kind == "support":
        P.supports.append(Unit(cd.name, cd.usages))
    elif cd.kind in ("weapon", "artifact"):
        _equip(P.characters[a.target], cd)
    elif cd.kind == "talent":
        _equip(P.characters[a.target], cd)
        _perform_skill(s, a.player, cd.skill)      # Combat Action: equip, then use the skill at once
        return
    else:
        cd.play(Ctx(s, a.player), a.target)
    _check_win(s)


def _tune(s, a):
    P = s.players[a.player]
    ch = P.active_char
    if ch is None or not 0 <= a.index < len(P.hand) or not 0 <= a.target < len(P.dice):
        raise IllegalAction("bad tune")
    if P.dice[a.target] in (OMNI, ch.defn.element):
        raise IllegalAction("die already matches")
    del P.hand[a.index]
    P.dice[a.target] = ch.defn.element


def _end_round(s, a):
    P = s.players[a.player]
    P.ended = True
    if s.first_ender is None:
        s.first_ender = a.player
    _event(s, "end_round", player=a.player)
    if s.players[1 - a.player].ended:
        _end_phase(s)
    else:
        s.current = 1 - a.player


_HANDLERS = {"mulligan": _mulligan, "choose_active": _choose_active, "reroll": _reroll,
             "confirm_roll": _confirm_roll, "skill": _skill, "switch": _switch,
             "card": _card, "tune": _tune, "end_round": _end_round}

_PHASE_OF = {"mulligan": "setup", "reroll": "roll", "confirm_roll": "roll", "skill": "action",
             "switch": "action", "card": "action", "tune": "action", "end_round": "action"}


def apply_action(s, a):
    if actor(s) != a.player:
        raise IllegalAction("not this player's turn")
    h = _HANDLERS.get(a.type)
    if h is None:
        raise IllegalAction(f"unknown action {a.type}")
    if a.type == "choose_active":
        if not s.pending and s.phase != "setup":
            raise IllegalAction("nothing to choose")
    elif s.pending or _PHASE_OF[a.type] != s.phase:
        raise IllegalAction(f"{a.type} not allowed now")
    s.events = []
    h(s, a)
    return s


def describe(s):
    """Plain-text board summary (handy for debugging and a CLI)."""
    lines = [f"Round {s.round}  phase={s.phase}  to act: {actor(s)}  winner={s.winner}"]
    for i, P in enumerate(s.players):
        chars = ", ".join(f"{'*' if j == P.active else ''}{c.name} {c.hp}hp {c.energy}e"
                          + (f" [{c.aura}]" if c.aura else "") + (" X" if c.defeated else "")
                          for j, c in enumerate(P.characters))
        lines.append(f"P{i}: {chars}")
        lines.append(f"    dice={sorted(P.dice)} hand={len(P.hand)} deck={len(P.deck)} "
                     f"summons={[(u.name, u.usages) for u in P.summons]} "
                     f"status={[(x.name, x.usages, x.shield) for x in P.combat]}")
    return "\n".join(lines)

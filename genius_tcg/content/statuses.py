"""Statuses and summons. NOTE: numbers are first-pass and get verified against
official card data in milestone 3."""
from engine.core import PHYSICAL, PYRO, HYDRO, CRYO, ELECTRO, ANEMO, GEO, OMNI
from engine.registry import STATUS_DEFS, SUMMON_DEFS, StatusDef, SummonDef, register
from engine import rules


def _status(**kw):
    return register(STATUS_DEFS, StatusDef(**kw))


def _summon(name, element, damage, usages):
    return register(SUMMON_DEFS, SummonDef(name, element, damage, usages))


# --- crowd control (handled by name in the rules)
_status(name="Frozen")
_status(name="Petrified")


# --- shields and damage reduction (combat statuses)
_status(name="Crystallize Shield", shield=1, max_shield=2)
_status(name="Jade Shield", shield=1, max_shield=2)
_status(name="Ice Lotus", usages=2, reduce=1)
_status(name="Rain Sword", usages=2, reduce=1, reduce_min=3)
_status(name="Reflection", usages=1, reduce=1)
_status(name="Lotus Shield", shield=3, max_shield=3, duration=1)
_status(name="Ice Shield", shield=1, max_shield=2, duration=2)


# --- damage modifiers
def _pyro_infusion(state, owner, st, d):
    if d["dtype"] == PHYSICAL:
        d["dtype"] = PYRO


def _inspiration_field(state, owner, st, d):
    ch = state.players[owner].active_char
    if ch and ch.hp >= 7:
        d["amount"] += 2


_status(name="Pyro Infusion", duration=2, outgoing=_pyro_infusion)
def _inspiration_heal(state, owner, st, kind):
    ch = state.players[owner].active_char
    if ch and ch.hp <= 6:
        rules.Ctx(state, owner).heal(2)


_status(name="Inspiration Field", duration=2, outgoing=_inspiration_field, after_skill=_inspiration_heal)


def _fervent_flames(state, owner, st, d):
    if st.usages > 0 and d["kind"]:
        d["amount"] += 2
        st.usages -= 1


_status(name="Fervent Flames", usages=1, duration=2, outgoing=_fervent_flames)
_status(name="Changing Shifts", usages=1, duration=1)      # next switch costs no dice
_status(name="Leave It to Me!", usages=1, duration=1)      # next switch is a Fast Action


# --- reactions to skills
def _rainbow_bladework(state, owner, st, kind):
    if kind == "normal" and st.usages > 0:
        t = rules._foe_target(state, owner)
        if t is not None:
            rules.deal_damage(state, owner, 1 - owner, t, 1, HYDRO, "status")
        st.usages -= 1


_status(name="Rainbow Bladework", usages=3, after_skill=_rainbow_bladework)


# --- summons: (name, element, end-phase damage, usages)
_summon("Oz", ELECTRO, 1, 2)
_summon("Icicle", CRYO, 2, 3)
_summon("Sacred Cryo Pearl", CRYO, 1, 2)
_summon("Large Wind Spirit", ANEMO, 2, 3)
_summon("Stone Stele", GEO, 1, 2)


# --- equipment statuses (weapons: +1 skill damage while the wielder is active)
def _bonus(kind=None, n=1):
    def outgoing(state, owner, st, d):
        if kind is None or d["kind"] == kind:
            d["amount"] += n
    return outgoing


for _w in ("Traveler's Handy Sword", "Raven Bow", "White Iron Greatsword", "White Tassel", "Magic Guide"):
    _status(name=_w, outgoing=_bonus())


def _earrings(state, owner, st):
    if st.usages > 0:
        rules.Ctx(state, owner).gain_dice(2, OMNI)
        st.usages -= 1


_status(name="Gambler's Earrings", usages=1, per_round=1, on_kill=_earrings)


# --- talent statuses. Names are real; effects are simplified placeholders except Fischl's.
def _electro_infusion(state, owner, st, d):
    if d["dtype"] == PHYSICAL:
        d["dtype"] = ELECTRO


def _stellar_predator(state, owner, st, kind):
    P = state.players[owner]
    if kind == "normal" and st.usages > 0 and any(u.name == "Oz" for u in P.summons):
        t = rules._foe_target(state, owner)
        if t is not None:
            rules.deal_damage(state, owner, 1 - owner, t, 2, ELECTRO, "status")
        st.usages -= 1


def _cold_blooded(state, owner, st, kind):
    if kind == "skill":
        rules.Ctx(state, owner).heal(2)


_status(name="Thundering Penance", outgoing=_electro_infusion)
_status(name="Stellar Predator", usages=1, per_round=1, after_skill=_stellar_predator)
_status(name="Flowing Flame", outgoing=_bonus("skill"))
_status(name="Grand Expectation", outgoing=_bonus("burst"))
_status(name="Cold-Blooded Strike", after_skill=_cold_blooded)
_status(name="Undivided Heart", outgoing=_bonus("skill"))
_status(name="The Scent Remained", outgoing=_bonus("normal"))
_status(name="Prophecy of Submersion", outgoing=_bonus("burst"))
_status(name="Chaotic Entropy", outgoing=_bonus("skill"))
_status(name="Dominance of Earth", outgoing=_bonus("skill"))


STATUS_TEXT = {
    "Frozen": "Cannot act. Takes +2 from Physical or Pyro (which thaws it).", "Petrified": "Cannot use skills this round.",
    "Crystallize Shield": "Shield: absorbs 1 damage (max 2).", "Jade Shield": "Shield: absorbs 1 damage (max 2).",
    "Ice Lotus": "Reduces damage taken by 1. (2 uses)", "Rain Sword": "Reduces damage of 3 or more by 1. (2 uses)",
    "Reflection": "Reduces damage taken by 1. (1 use)", "Lotus Shield": "Shield: absorbs 3 damage this round.",
    "Ice Shield": "Shield: absorbs 1 damage for 2 rounds.", "Pyro Infusion": "Physical damage becomes Pyro. (2 rounds)",
    "Inspiration Field": "+2 damage if attacker has 7+ HP; heals 2 at 6 HP or less. (2 rounds)",
    "Rainbow Bladework": "After a Normal Attack: 1 Hydro damage. (3 uses)", "Fervent Flames": "Next skill deals +2 damage.",
    "Changing Shifts": "Next switch costs no dice.", "Leave It to Me!": "Next switch is a Fast Action.",
}
for _n, _t in STATUS_TEXT.items():
    STATUS_DEFS[_n].text = _t
for _n in ("Traveler's Handy Sword", "Raven Bow", "White Iron Greatsword", "White Tassel", "Magic Guide"):
    STATUS_DEFS[_n].text = "+1 damage on this character's skills."

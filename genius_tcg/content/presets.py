"""Preset decks, built by the CSP auto-fill from a priority list (so they are always legal)."""
from engine import deck

BASE = {"Paimon": 5, "Strategize": 4, "Sweet Madame": 3, "Changing Shifts": 3, "Mondstadt Hash Browns": 2,
        "Liyue Harbor Wharf": 2, "Wangshu Inn": 2, "Gambler's Earrings": 1}
TALENT_BOOST, WEAPON_BOOST, RESONANCE_BOOST = 10, 6, 7

PRESETS = {
    "Electro-Charged": ["Keqing", "Fischl", "Xingqiu"],
    "Melt Burst": ["Diluc", "Bennett", "Kaeya"],
    "Swirl Control": ["Sucrose", "Mona", "Zhongli"],
    "Frost and Stone": ["Ganyu", "Kaeya", "Zhongli"],
    "Vaporize Overload": ["Diluc", "Xingqiu", "Fischl"],
    "Freeze Superconduct": ["Ganyu", "Mona", "Keqing"],
}


def priority():
    """Card priorities used by CSP auto-fill (talents > resonance > weapons > staples)."""
    from engine.registry import CARD_DEFS
    pr = dict(BASE)
    for n, cd in CARD_DEFS.items():
        if cd.kind == "talent":
            pr[n] = TALENT_BOOST
        elif cd.kind == "weapon":
            pr[n] = WEAPON_BOOST
        elif cd.resonance:
            pr[n] = RESONANCE_BOOST
    return pr


def build(chars):
    return deck.autofill(chars, priority=priority())


def preset_decks():
    return {name: (chars, build(chars)) for name, chars in PRESETS.items()}

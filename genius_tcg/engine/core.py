"""Constants and small value types shared by the whole engine."""
from dataclasses import dataclass
from typing import Optional, Tuple

CRYO, HYDRO, PYRO, ELECTRO, ANEMO, GEO = "Cryo", "Hydro", "Pyro", "Electro", "Anemo", "Geo"
ELEMENTS = (CRYO, HYDRO, PYRO, ELECTRO, ANEMO, GEO)      # Dendro intentionally excluded
AURA_ELEMENTS = (CRYO, HYDRO, PYRO, ELECTRO)             # Anemo / Geo never leave an aura
OMNI, PHYSICAL, PIERCING = "Omni", "Physical", "Piercing"
DICE_FACES = ELEMENTS + (OMNI,)
# Omni keeps the original 1/8 chance; the six elements share the rest (7/48 each)
DICE_WEIGHTS = (7 / 48,) * 6 + (1 / 8,)

DICE_PER_ROUND, MAX_DICE, MAX_HAND = 8, 16, 10
MAX_SUMMONS, MAX_SUPPORTS = 4, 4
HAND_START, DRAW_END = 5, 2


@dataclass(frozen=True)
class Cost:
    element: Optional[str] = None   # element the matching dice must be (Omni also works)
    n: int = 0                      # how many dice of that element
    unaligned: int = 0              # any dice
    energy: int = 0                 # energy the character must have (bursts)


@dataclass(frozen=True)
class Action:
    type: str                       # mulligan choose_active confirm_roll reroll skill switch card tune end_round
    player: int
    index: int = -1                 # skill index / hand index / character index
    target: int = -1                # card target character, or die index for tuning
    dice: Tuple[int, ...] = ()      # indices of dice paid
    ids: Tuple[int, ...] = ()       # hand indices (mulligan) or dice indices (reroll)


class IllegalAction(Exception):
    pass

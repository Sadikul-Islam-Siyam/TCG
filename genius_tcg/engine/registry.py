"""Definition classes and global registries filled by the content package."""
from dataclasses import dataclass
from typing import Callable, Optional, Tuple
from .core import Cost

CHAR_DEFS, STATUS_DEFS, SUMMON_DEFS, CARD_DEFS = {}, {}, {}, {}


@dataclass
class SkillDef:
    name: str
    kind: str                # normal | skill | burst
    cost: Cost
    effect: Callable
    desc: str = ""                         # human-readable effect, filled in by content


@dataclass
class CharDef:
    name: str
    element: str
    weapon: str
    max_energy: int
    skills: Tuple[SkillDef, ...]
    hp: int = 10


@dataclass
class StatusDef:
    name: str
    usages: Optional[int] = None
    duration: Optional[int] = None
    shield: int = 0
    max_shield: int = 99
    reduce: int = 0                      # damage reduction per hit (uses a usage)
    reduce_min: int = 0                  # only when incoming damage >= this
    outgoing: Optional[Callable] = None      # (state, owner, status, dmg_dict)
    after_skill: Optional[Callable] = None   # (state, owner, status, skill_kind)
    text: str = ""                           # shown in tooltips
    on_kill: Optional[Callable] = None       # (state, owner, status) when the owner's attack defeats a character
    per_round: Optional[int] = None          # usages restored every End Phase


@dataclass
class SummonDef:
    name: str
    element: str
    damage: int
    usages: int


@dataclass
class CardDef:
    name: str
    kind: str                # event | support
    cost: Cost
    play: Optional[Callable] = None          # (ctx, target_index)
    needs_char: bool = False
    usages: Optional[int] = None
    action_start: Optional[Callable] = None  # supports: (ctx)
    end_phase: Optional[Callable] = None     # supports: (ctx)
    char: Optional[str] = None               # talent: required character name
    skill: int = 1                           # talent: skill index used immediately
    weapon: Optional[str] = None             # weapon: required weapon type
    status: Optional[str] = None             # equipment: status granted while equipped
    resonance: Optional[str] = None          # needs 2 characters of this element
    text: str = ""                           # effect text shown on the card in the deck


def register(registry, obj):
    registry[obj.name] = obj
    return obj

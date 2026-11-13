"""Importing this package registers all characters, statuses, summons and cards."""
from . import statuses, characters, cards  # noqa: F401
from .cards import starter_deck  # noqa: F401
from .presets import preset_decks  # noqa: F401
from .characters import ROSTER  # noqa: F401

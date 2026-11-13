"""Deck rules: validation, CSP auto-fill and share codes."""
import base64
import json
from collections import Counter

from . import csp
from .registry import CARD_DEFS, CHAR_DEFS

DECK_SIZE, MAX_COPIES = 30, 2


def card_allowed(cd, chars):
    """Can this card be in a deck with these three characters?"""
    defs = [CHAR_DEFS[c] for c in chars]
    if cd.kind == "talent":
        return cd.char in chars
    if cd.kind == "weapon":
        return any(d.weapon == cd.weapon for d in defs)
    if cd.resonance:
        return sum(d.element == cd.resonance for d in defs) >= 2
    return True


def allowed_cards(chars):
    return sorted(n for n, cd in CARD_DEFS.items() if card_allowed(cd, chars))


def validate_deck(chars, cards):
    """Returns a list of rule violations (empty list = legal deck)."""
    errs = []
    if len(chars) != 3 or len(set(chars)) != 3 or any(c not in CHAR_DEFS for c in chars):
        return ["a deck needs exactly 3 different, known characters"]
    if len(cards) != DECK_SIZE:
        errs.append(f"deck has {len(cards)} cards, needs {DECK_SIZE}")
    for name, n in Counter(cards).items():
        if name not in CARD_DEFS:
            errs.append(f"unknown card: {name}")
        elif n > MAX_COPIES:
            errs.append(f"{name}: {n} copies (max {MAX_COPIES})")
        elif not card_allowed(CARD_DEFS[name], chars):
            errs.append(f"{name} cannot be used with {', '.join(chars)}")
    return errs


def autofill(chars, partial=(), priority=None):
    """Complete a partial deck into a legal 30-card deck with the CSP solver, preferring
    high-priority cards. Returns a card list or None if impossible."""
    priority = priority or {}
    names = allowed_cards(chars)
    have = Counter(partial)
    if any(n not in names or c > MAX_COPIES for n, c in have.items()):
        return None
    domains = {n: range(have[n], MAX_COPIES + 1) for n in names}
    sol = csp.solve(domains, [csp.SumEq(names, DECK_SIZE)],
                    var_key=lambda n: (-priority.get(n, 0), n))
    if sol is None:
        return None
    return [n for n in sorted(sol) for _ in range(sol[n])]


def encode(chars, cards):
    raw = json.dumps({"c": list(chars), "d": sorted(cards)}, separators=(",", ":")).encode()
    return base64.urlsafe_b64encode(raw).decode().rstrip("=")


def decode(code):
    data = json.loads(base64.urlsafe_b64decode(code + "=" * (-len(code) % 4)))
    return data["c"], data["d"]

"""Saved decks on disk (JSON). Location: ~/.genius_tcg/decks.json, or $GENIUS_TCG_HOME."""
import json
import os
from pathlib import Path

from engine import deck as deckrules


def _path():
    return Path(os.environ.get("GENIUS_TCG_HOME", Path.home() / ".genius_tcg")) / "decks.json"


def _read():
    try:
        data = json.loads(_path().read_text())
        return [d for d in data if isinstance(d, dict) and {"name", "chars", "cards"} <= set(d)]
    except (OSError, ValueError):
        return []


def _write(decks):
    p = _path()
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_suffix(".tmp")
    tmp.write_text(json.dumps(decks, indent=1))
    tmp.replace(p)


def list_decks():
    """Saved decks, each with a 'legal' flag (drafts can be saved but not played)."""
    out = []
    for d in _read():
        d = dict(d)
        d["legal"] = not deckrules.validate_deck(d["chars"], d["cards"])
        out.append(d)
    return out


def save_deck(name, chars, cards):
    name = name.strip()
    if not name:
        raise ValueError("deck needs a name")
    decks = [d for d in _read() if d["name"] != name]
    decks.append({"name": name, "chars": list(chars), "cards": sorted(cards)})
    _write(decks)


def delete_deck(name):
    _write([d for d in _read() if d["name"] != name])

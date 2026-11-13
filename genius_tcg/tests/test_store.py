import json

import content
from engine import deck
from ui import store


def test_save_list_overwrite_delete(tmp_path, monkeypatch):
    monkeypatch.setenv("GENIUS_TCG_HOME", str(tmp_path))
    chars, cards = content.preset_decks()["Melt Burst"]
    store.save_deck("Mine", chars, cards)
    store.save_deck("Draft", chars, cards[:10])
    store.save_deck("Mine", chars, cards)                      # same name overwrites
    decks = {d["name"]: d for d in store.list_decks()}
    assert set(decks) == {"Mine", "Draft"}
    assert decks["Mine"]["legal"] and not decks["Draft"]["legal"]
    assert decks["Mine"]["chars"] == chars
    store.delete_deck("Mine")
    assert [d["name"] for d in store.list_decks()] == ["Draft"]


def test_corrupt_or_missing_file_is_ignored(tmp_path, monkeypatch):
    monkeypatch.setenv("GENIUS_TCG_HOME", str(tmp_path))
    assert store.list_decks() == []
    (tmp_path / "decks.json").write_text("{not json")
    assert store.list_decks() == []
    (tmp_path / "decks.json").write_text(json.dumps([{"name": "x"}, 5]))
    assert store.list_decks() == []


def test_blank_name_rejected(tmp_path, monkeypatch):
    monkeypatch.setenv("GENIUS_TCG_HOME", str(tmp_path))
    import pytest
    with pytest.raises(ValueError):
        store.save_deck("  ", ["Keqing", "Fischl", "Diluc"], [])

import random
from collections import Counter

import pytest

import content
from engine import deck, rules
from engine import dice as D
from engine.core import *
from engine.rules import apply_action, legal_actions
from tests.test_engine import start, hit


def give(s, p, *cards):
    s.players[p].hand = list(cards)


def play(s, name, target=-1, p=0):
    P = s.players[p]
    a = next(a for a in legal_actions(s) if a.type == "card" and P.hand[a.index] == name and a.target == target)
    apply_action(s, a)


# ---------------------------------------------------------------- dice odds
def test_omni_rate_is_one_eighth_and_elements_equal():
    rng = random.Random(3)
    faces = Counter(D.roll(rng, 80000))
    assert abs(faces[OMNI] / 80000 - 1 / 8) < 0.005
    assert all(abs(faces[e] / 80000 - 7 / 48) < 0.005 for e in ELEMENTS)


# ---------------------------------------------------------------- decks and CSP
def test_presets_are_legal_decks():
    presets = content.preset_decks()
    assert len(presets) == 6
    for name, (chars, cards) in presets.items():
        assert deck.validate_deck(chars, cards) == [], name


def test_validation_catches_each_rule():
    chars = ["Keqing", "Fischl", "Diluc"]
    good = deck.autofill(chars)
    assert deck.validate_deck(chars, good) == []
    assert any("needs 30" in e for e in deck.validate_deck(chars, good[:-1]))
    three = [c for c in good if c != "Paimon"][:27] + ["Paimon"] * 3
    assert any("3 copies" in e for e in deck.validate_deck(chars, three))
    wrong_talent = ["Undivided Heart"] * 2 + good[2:]
    assert any("cannot be used" in e for e in deck.validate_deck(chars, wrong_talent))
    no_polearm = ["White Tassel"] * 2 + good[2:]
    assert any("White Tassel" in e for e in deck.validate_deck(chars, no_polearm))
    assert any("Pyro" in e or "Fervent" in e for e in deck.validate_deck(chars, ["Elemental Resonance: Fervent Flames"] * 2 + good[2:]))
    assert deck.validate_deck(["Keqing", "Keqing", "Diluc"], good)


def test_autofill_keeps_partial_and_is_deterministic():
    chars = ["Mona", "Sucrose", "Zhongli"]
    partial = ["Magic Guide", "Magic Guide", "Chaotic Entropy"]
    a, b = deck.autofill(chars, partial), deck.autofill(chars, partial)
    assert a == b and deck.validate_deck(chars, a) == []
    assert Counter(a)["Magic Guide"] == 2 and Counter(a)["Chaotic Entropy"] >= 1


def test_autofill_rejects_illegal_partial():
    assert deck.autofill(["Keqing", "Fischl", "Diluc"], ["Undivided Heart"]) is None
    assert deck.autofill(["Keqing", "Fischl", "Diluc"], ["Paimon"] * 3) is None


def test_every_character_trio_can_be_filled():
    rng = random.Random(1)
    for _ in range(40):
        chars = rng.sample(content.ROSTER, 3)
        assert deck.validate_deck(chars, deck.autofill(chars)) == [], chars


def test_share_code_roundtrip():
    chars, cards = content.preset_decks()["Melt Burst"]
    assert deck.decode(deck.encode(chars, cards)) == (chars, sorted(cards))


# ---------------------------------------------------------------- equipment
def test_weapon_adds_damage_only_for_matching_type():
    s = start()
    give(s, 0, "Traveler's Handy Sword", "Raven Bow")
    targets = {a.target for a in legal_actions(s) if a.type == "card" and s.players[0].hand[a.index] == "Raven Bow"}
    assert targets == {1}                                   # only Fischl uses a bow
    play(s, "Traveler's Handy Sword", 0)
    assert s.current == 0                                   # equipping is a Fast Action
    apply_action(s, next(a for a in legal_actions(s) if a.type == "skill" and a.index == 1))
    assert s.players[1].characters[0].hp == 6               # 3 + 1


def test_new_weapon_replaces_old_and_defeat_removes_equipment():
    s = start(c0=("Keqing", "Xingqiu", "Diluc"))
    give(s, 0, "Traveler's Handy Sword")
    play(s, "Traveler's Handy Sword", 0)
    assert s.players[0].characters[0].equipment["weapon"] == "Traveler's Handy Sword"
    hit(s, 0, 99, PHYSICAL, tp=0)
    assert s.players[0].characters[0].equipment == {} and s.players[0].characters[0].statuses == []


def test_talent_equips_then_uses_skill_and_passes_turn():
    s = start()
    s.players[0].active = 1                                 # Fischl
    give(s, 0, "Stellar Predator")
    dice_before = len(s.players[0].dice)
    play(s, "Stellar Predator", 1)
    P = s.players[0]
    assert dice_before - len(P.dice) == 3                   # paid the talent cost only
    assert P.characters[1].equipment["talent"] == "Stellar Predator"
    assert [u.name for u in P.summons] == ["Oz"] and s.current == 1
    assert s.players[1].characters[0].hp == 9


def test_talent_requires_its_active_character():
    s = start()
    give(s, 0, "Stellar Predator", "Thundering Penance")
    names = {s.players[0].hand[a.index] for a in legal_actions(s) if a.type == "card"}
    assert names == {"Thundering Penance"}                  # Keqing is active, Fischl is not


def test_fischl_talent_oz_follow_up_once_per_round():
    s = start()
    s.players[0].active = 1
    give(s, 0, "Stellar Predator")
    play(s, "Stellar Predator", 1)
    apply_action(s, Action("end_round", 1))
    apply_action(s, next(a for a in legal_actions(s) if a.type == "skill" and a.index == 0))
    assert s.players[1].characters[0].hp == 9 - 2 - 2       # normal attack 2 + Oz follow-up 2 Electro
    assert s.players[1].characters[0].aura == ELECTRO


def test_gambler_earrings_gives_dice_once_per_round():
    s = start()
    give(s, 0, "Gambler's Earrings")
    play(s, "Gambler's Earrings", 0)
    s.players[0].dice = []
    s.players[1].characters[0].hp = 1
    hit(s, 0, 5, PHYSICAL, tp=1)
    hit(s, 1, 1, PHYSICAL, tp=1)
    assert s.players[0].dice.count(OMNI) == 2               # second kill same round gives nothing
    s.pending = []


# ---------------------------------------------------------------- supports and events
def test_support_end_phase_effects():
    s = start()
    s.players[0].hand = ["Liyue Harbor Wharf", "Wangshu Inn"]
    s.players[0].characters[1].hp = 4
    play(s, "Liyue Harbor Wharf"); play(s, "Wangshu Inn")
    deck_before = len(s.players[0].deck)
    apply_action(s, Action("end_round", 0)); apply_action(s, Action("end_round", 1))
    assert s.players[0].characters[1].hp == 6
    assert len(s.players[0].deck) == deck_before - 4          # 2 wharf + 2 end-phase draw
    assert [u.usages for u in s.players[0].supports] == [1, 1]


def test_paimon_gives_dice_at_action_start():
    s = start()
    give(s, 0, "Paimon")
    play(s, "Paimon")
    apply_action(s, Action("end_round", 0)); apply_action(s, Action("end_round", 1))
    while s.phase != "action":
        apply_action(s, legal_actions(s)[0])
    assert s.players[0].dice.count(OMNI) >= 2 and len(s.players[0].dice) >= 10


def test_changing_shifts_and_leave_it_to_me():
    s = start()
    give(s, 0, "Changing Shifts", "Leave It to Me!")
    play(s, "Changing Shifts"); play(s, "Leave It to Me!")
    n = len(s.players[0].dice)
    apply_action(s, next(a for a in legal_actions(s) if a.type == "switch"))
    assert len(s.players[0].dice) == n and s.current == 0     # free and fast


def test_resonance_card_and_reflection():
    s = start()
    give(s, 0, "Elemental Resonance: Woven Thunder")
    play(s, "Elemental Resonance: Woven Thunder")
    assert s.players[0].characters[0].energy == 1
    rules.Ctx(s, 1).combat_status("Reflection")
    hit(s, 0, 3, PHYSICAL, tp=1)
    assert s.players[1].characters[0].hp == 8               # Reflection absorbed 1
    hit(s, 0, 3, PHYSICAL, tp=1)
    assert s.players[1].characters[0].hp == 5               # used up after one hit


# ---------------------------------------------------------------- full games with legal decks
def test_random_games_with_preset_decks():
    from simulate import play_game
    for seed in range(40):
        s, steps, _ = play_game(seed)
        assert s.phase == "over" or s.round > 40

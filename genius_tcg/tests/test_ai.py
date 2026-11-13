import random

import pytest

import content
from ai import dicepay, fuzzy, mcts, planner
from ai.deckgen import random_deck
from ai.evaluate import evaluate
from ai.players import AIPlayer
from ai.random_ai import RandomAI
from ai.search import Searcher
from ai.world import candidates, determinize
from engine import csp, deck, rules
from engine import dice as D
from engine.core import *
from engine.rules import apply_action, legal_actions
from tests.test_engine import start
from tests.test_m3 import give


# ---------------------------------------------------------------- fuzzy logic
def test_membership_shapes():
    assert fuzzy.low(0.0) == 1 and fuzzy.low(0.9) == 0
    assert fuzzy.med(0.5) == 1 and fuzzy.med(0.1) == 0
    assert fuzzy.high(1.0) == 1 and fuzzy.high(0.2) == 0
    assert 0 < fuzzy.low(0.4) < 1 and 0 < fuzzy.high(0.6) < 1


def test_profile_reacts_to_health():
    healthy, hurt = start(), start()
    for c in hurt.players[0].characters:
        c.hp = 2
    ph, pu = fuzzy.profile(healthy, 0), fuzzy.profile(hurt, 0)
    assert pu["defence"] > ph["defence"] and pu["aggression"] < ph["aggression"]
    assert all(0 <= v <= 1.0 for k, v in ph.items() if k in ("aggression", "defence", "burst", "tempo", "cards"))


def test_evaluation_is_zero_sum_and_sees_damage():
    s = start()
    base = evaluate(s, 0)
    assert abs(base + evaluate(s, 1)) < 1e-9
    s.players[1].characters[0].hp = 3
    assert evaluate(s, 0) > base
    s.players[1].characters[0].hp = 0
    s.players[1].characters[0].defeated = True
    assert evaluate(s, 0) > base + 0.5


# ---------------------------------------------------------------- CSP
def test_alldiff_constraint():
    sol = csp.solve({"a": [1, 2], "b": [1, 2], "c": [1, 2, 3]}, [csp.AllDiff("abc")])
    assert sol and len(set(sol.values())) == 3
    assert csp.solve({"a": [1], "b": [1]}, [csp.AllDiff("ab")]) is None


def test_smart_pay_spends_cheap_dice_and_keeps_omni():
    dice = [OMNI, PYRO, PYRO, HYDRO, PYRO, ANEMO]
    pay = dicepay.smart_pay(dice, Cost(PYRO, 3), keep=(PYRO,))
    assert sorted(dice[i] for i in pay) == [PYRO, PYRO, PYRO]
    pay2 = dicepay.smart_pay(dice, Cost(PYRO, 1, 2), keep=(PYRO,))
    assert OMNI not in [dice[i] for i in pay2]
    assert dicepay.smart_pay([PYRO], Cost(PYRO, 2)) is None
    assert dicepay.smart_pay(dice, Cost()) == ()


def test_smart_pay_always_valid():
    rng = random.Random(4)
    for _ in range(300):
        dice = D.roll(rng, rng.randint(3, 12))
        cost = Cost(rng.choice(ELEMENTS), rng.randint(0, 4), rng.randint(0, 3))
        pay = dicepay.smart_pay(dice, cost, keep=(cost.element,))
        greedy = D.auto_pay(dice, cost)
        assert (pay is None) == (greedy is None)                 # same feasibility as the greedy solver
        if pay is not None:
            assert D.payment_ok(dice, cost, pay)


# ---------------------------------------------------------------- hidden information
def test_determinize_resamples_hidden_cards_only():
    s = start()
    hand, deckk, mine = list(s.players[1].hand), list(s.players[1].deck), list(s.players[0].deck)
    w = determinize(s, 0, random.Random(5))
    assert s.players[1].hand == hand and s.players[1].deck == deckk and s.players[0].deck == mine
    assert len(w.players[1].hand) == len(hand) and len(w.players[1].deck) == len(deckk)
    assert sorted(w.players[0].deck) == sorted(mine)
    assert w.players[0].hand == s.players[0].hand and w.players[0].dice == s.players[0].dice
    allowed = set(deck.allowed_cards([c.name for c in s.players[1].characters]))
    assert set(w.players[1].hand) <= allowed


@pytest.mark.parametrize("level", ["easy", "normal", "hard"])
def test_ai_never_looks_at_the_opponents_hidden_cards(level):
    s = start()
    t = s.clone()
    t.players[1].hand = list(reversed(t.players[1].hand)) if len(set(t.players[1].hand)) > 1 else ["Paimon"] * len(t.players[1].hand)
    t.players[1].deck = list(reversed(t.players[1].deck))
    t.players[0].deck = list(reversed(t.players[0].deck))        # nor its own draw order
    a = AIPlayer(level, 11, time_scale=50, iters=60).choose(s)
    b = AIPlayer(level, 11, time_scale=50, iters=60).choose(t)
    assert a == b


@pytest.mark.parametrize("level", ["easy", "normal", "hard"])
def test_choose_leaves_state_untouched(level):
    s = start()
    before = (rules.describe(s), list(s.players[0].hand), list(s.players[1].hand), list(s.players[0].deck),
              s.rng.getstate(), [list(p.dice) for p in s.players])
    AIPlayer(level, 3, time_scale=0.3, iters=40).choose(s)
    after = (rules.describe(s), list(s.players[0].hand), list(s.players[1].hand), list(s.players[0].deck),
             s.rng.getstate(), [list(p.dice) for p in s.players])
    assert before == after


# ---------------------------------------------------------------- A* planner
def test_planner_finds_one_move_lethal():
    s = start()
    s.players[1].characters[0].hp = 3
    plan = planner.plan_lethal(determinize(s, 0, random.Random(1)), 0)
    assert plan and len(plan) == 1 and plan[0].type == "skill"
    apply_action(s, plan[0])
    assert s.players[1].characters[0].defeated


def test_planner_chains_equipment_then_attack():
    s = start()
    s.players[1].characters[0].hp = 4                       # skill does 3: needs the weapon's +1
    give(s, 0, "Traveler's Handy Sword", "Strategize")
    plan = planner.plan_lethal(determinize(s, 0, random.Random(1)), 0)
    assert [a.type for a in plan] == ["card", "skill"]
    for a in plan:
        apply_action(s, a)
    assert s.players[1].characters[0].defeated


def test_planner_returns_none_when_no_lethal():
    s = start()
    assert planner.plan_lethal(determinize(s, 0, random.Random(1)), 0) is None


# ---------------------------------------------------------------- searchers
def test_alphabeta_takes_the_kill():
    s = start()
    s.players[1].characters[0].hp = 3
    for _ in range(6):                                           # free cards may come first, then the kill
        w = determinize(s, 0, random.Random(2))
        apply_action(s, Searcher(0, time_limit=5).best_move(w, 3))
        if s.players[1].characters[0].defeated or rules.actor(s) != 0:
            break
    assert s.players[1].characters[0].defeated


def test_mcts_is_deterministic_and_legal():
    s = start()
    r1 = mcts.best_action(s, 0, fuzzy.profile(s, 0), random.Random(9), 60, 80)
    r2 = mcts.best_action(s, 0, fuzzy.profile(s, 0), random.Random(9), 60, 80)
    assert r1 == r2 and r1 in legal_actions(s)


def test_mcts_prefers_a_winning_hit():
    s = start()
    for c in s.players[1].characters[1:]:
        c.hp, c.defeated = 0, True
    s.players[1].characters[0].hp = 3
    act = mcts.best_action(s, 0, fuzzy.profile(s, 0), random.Random(3), 60, 150)
    assert act.type == "skill"


# ---------------------------------------------------------------- whole games
def play(a, b, seed, max_steps=3000):
    chars = list(content.preset_decks().values())
    rng = random.Random(seed)
    (c0, d0), (c1, d1) = rng.choice(chars), rng.choice(chars)
    s = rules.new_game(c0, d0, c1, d1, seed)
    bots = [a, b]
    n = 0
    while s.phase != "over" and s.round <= 30 and n < max_steps:
        apply_action(s, bots[rules.actor(s)].choose(s))
        n += 1
    return s


@pytest.mark.parametrize("level", ["easy", "normal", "hard"])
def test_each_level_finishes_games_against_random(level):
    for seed in (1, 2):
        s = play(AIPlayer(level, seed, time_scale=0.2, iters=40), RandomAI(seed), seed)
        assert s.phase == "over" or s.round > 30


def test_levels_play_each_other():
    s = play(AIPlayer("normal", 1, time_scale=0.2), AIPlayer("hard", 2, time_scale=0.2, iters=40), 5)
    assert s.phase == "over" or s.round > 30


def test_ai_builds_legal_decks():
    rng = random.Random(1)
    for _ in range(25):
        chars, cards = random_deck(rng)
        assert deck.validate_deck(chars, cards) == []

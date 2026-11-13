import pytest

import content
from ai.random_ai import RandomAI
from engine import dice as D
from engine import rules
from engine.core import *
from engine.rules import apply_action, legal_actions, deal_damage, actor


def start(c0=("Keqing", "Fischl", "Diluc"), c1=("Kaeya", "Ganyu", "Xingqiu"), seed=1):
    """A game already in the action phase, player 0 to act, with plenty of Omni dice."""
    s = rules.new_game(list(c0), content.starter_deck(), list(c1), content.starter_deck(), seed)
    while s.phase != "action":
        apply_action(s, legal_actions(s)[0])
    s.first_player = s.current = 0
    for P in s.players:
        P.dice = [OMNI] * 12
    return s


def hit(s, ti, amount, dtype, tp=1):
    s.events = []
    deal_damage(s, 1 - tp, tp, ti, amount, dtype, source="effect")


# ---------------------------------------------------------------- dice
def test_auto_pay_prefers_exact_then_omni():
    dice = [OMNI, PYRO, PYRO, HYDRO, PYRO]
    pay = D.auto_pay(dice, Cost(PYRO, 3), keep=(PYRO,))
    assert pay == (1, 2, 4)
    assert D.payment_ok(dice, Cost(PYRO, 3), pay)


def test_auto_pay_fails_when_short():
    assert D.auto_pay([PYRO, HYDRO], Cost(PYRO, 2)) is None
    assert D.auto_pay([PYRO], Cost(PYRO, 1, 2)) is None


def test_payment_rejects_wrong_dice():
    assert not D.payment_ok([HYDRO, HYDRO, HYDRO], Cost(PYRO, 1, 2), (0, 1, 2))


# ---------------------------------------------------------------- setup and flow
def test_setup_reaches_action_phase():
    s = start()
    assert s.phase == "action" and s.round == 1
    assert all(P.active == 0 and len(P.hand) == 5 for P in s.players)


def test_skill_deals_damage_applies_aura_and_energy():
    s = start()
    apply_action(s, next(a for a in legal_actions(s) if a.type == "skill" and a.index == 1))
    foe = s.players[1].characters[0]
    assert foe.hp == 7 and foe.aura == ELECTRO
    assert s.players[0].characters[0].energy == 1
    assert s.current == 1                       # combat action passes the turn


def test_fast_action_keeps_turn_and_tuning_changes_die():
    s = start()
    s.players[0].dice = [PYRO, OMNI]
    tune = next(a for a in legal_actions(s) if a.type == "tune")
    apply_action(s, tune)
    assert s.current == 0 and s.players[0].dice[0] == ELECTRO


def test_burst_needs_full_energy():
    s = start()
    assert not any(a.type == "skill" and a.index == 2 for a in legal_actions(s))
    s.players[0].characters[0].energy = 3
    apply_action(s, next(a for a in legal_actions(s) if a.type == "skill" and a.index == 2))
    assert s.players[0].characters[0].energy == 0
    assert [c.hp for c in s.players[1].characters] == [6, 7, 7]  # 4 to active, 3 piercing to others


def test_illegal_actions_are_rejected():
    s = start()
    with pytest.raises(IllegalAction):
        apply_action(s, Action("skill", 1, index=0, dice=(0, 1, 2)))     # not their turn
    with pytest.raises(IllegalAction):
        apply_action(s, Action("skill", 0, index=0, dice=(0,)))          # wrong payment


def test_end_round_flow_and_first_player():
    s = start()
    apply_action(s, Action("end_round", 0))
    assert s.current == 1 and s.first_ender == 0
    apply_action(s, Action("end_round", 1))
    assert s.round == 2 and s.phase == "roll" and s.first_player == 0
    assert all(len(P.dice) == 8 for P in s.players)
    assert all(len(P.hand) == 7 for P in s.players)                      # drew 2


def test_switch_costs_one_die_and_passes_turn():
    s = start()
    apply_action(s, next(a for a in legal_actions(s) if a.type == "switch" and a.index == 2))
    assert s.players[0].active == 2 and len(s.players[0].dice) == 11 and s.current == 1


# ---------------------------------------------------------------- reactions
@pytest.mark.parametrize("aura,dtype,bonus,name", [
    (HYDRO, PYRO, 1, "Vaporize"), (PYRO, HYDRO, 1, "Vaporize"),
    (CRYO, PYRO, 2, "Melt"), (PYRO, CRYO, 2, "Melt"),
    (PYRO, ELECTRO, 2, "Overloaded"), (CRYO, ELECTRO, 1, "Superconduct"),
    (HYDRO, ELECTRO, 1, "Electro-Charged"), (CRYO, HYDRO, 1, "Frozen"),
])
def test_reaction_bonus_and_aura_consumed(aura, dtype, bonus, name):
    s = start()
    tgt = s.players[1].characters[0]
    tgt.aura = aura
    hit(s, 0, 2, dtype)
    assert tgt.hp == 10 - 2 - bonus
    assert s.events[0][1]["reaction"] == name
    assert tgt.aura is None


def test_same_element_keeps_aura_no_reaction():
    s = start()
    s.players[1].characters[0].aura = PYRO
    hit(s, 0, 2, PYRO)
    assert s.players[1].characters[0].hp == 8 and s.players[1].characters[0].aura == PYRO


def test_overloaded_forces_switch():
    s = start()
    s.players[1].characters[0].aura = PYRO
    hit(s, 0, 1, ELECTRO)
    assert s.players[1].active == 1


def test_superconduct_pierces_standby_characters():
    s = start()
    s.players[1].characters[0].aura = CRYO
    hit(s, 0, 1, ELECTRO)
    assert [c.hp for c in s.players[1].characters] == [8, 9, 9]


def test_frozen_blocks_skills_and_boosts_physical_then_thaws():
    s = start()
    s.players[1].characters[0].aura = CRYO
    hit(s, 0, 1, HYDRO)
    foe = s.players[1].characters[0]
    assert any(x.name == "Frozen" for x in foe.statuses)
    s.current = 1
    assert not any(a.type == "skill" for a in legal_actions(s))
    hit(s, 0, 1, PHYSICAL)
    assert foe.hp == 10 - 2 - 3 and not foe.statuses          # +2 physical, thawed


def test_swirl_spreads_element_to_other_characters():
    s = start()
    s.players[1].characters[0].aura = PYRO
    hit(s, 0, 1, ANEMO)
    assert [c.hp for c in s.players[1].characters] == [9, 9, 9]
    assert s.players[1].characters[1].aura == PYRO and s.players[1].characters[0].aura is None


def test_crystallize_gives_shield_to_attacker_side():
    s = start()
    s.players[1].characters[0].aura = HYDRO
    hit(s, 0, 1, GEO)                                          # attacker is player 0
    assert s.players[1].characters[0].hp == 8
    assert [(x.name, x.shield) for x in s.players[0].combat] == [("Crystallize Shield", 1)]
    hit(s, 0, 3, PHYSICAL, tp=0)
    assert s.players[0].characters[0].hp == 8 and not s.players[0].combat


def test_piercing_ignores_shields_and_auras():
    s = start()
    s.players[1].combat.append(rules.Status("Jade Shield", shield=2))
    s.players[1].characters[0].aura = PYRO
    hit(s, 0, 2, PIERCING)
    assert s.players[1].characters[0].hp == 8 and s.players[1].characters[0].aura == PYRO


# ---------------------------------------------------------------- statuses, summons, defeat
def test_summon_attacks_in_end_phase_and_expires():
    s = start()
    ctx = rules.Ctx(s, 0)
    ctx.summon("Oz")
    apply_action(s, Action("end_round", 0)); apply_action(s, Action("end_round", 1))
    assert s.players[1].characters[0].hp == 9 and s.players[0].summons[0].usages == 1
    s2 = s
    while s2.phase != "action":
        apply_action(s2, legal_actions(s2)[0])
    apply_action(s2, Action("end_round", s2.current)); apply_action(s2, Action("end_round", s2.current))
    assert not s2.players[0].summons


def test_defeat_forces_choice_and_win_detection():
    s = start()
    hit(s, 0, 99, PHYSICAL)
    assert s.players[1].active is None and s.pending == [1]
    assert {a.type for a in legal_actions(s)} == {"choose_active"} and actor(s) == 1
    apply_action(s, Action("choose_active", 1, index=1))
    assert s.players[1].active == 1 and not s.pending
    hit(s, 1, 99, PHYSICAL); hit(s, 2, 99, PHYSICAL)
    assert s.phase == "over" and s.winner == 0


def test_pyro_infusion_converts_physical():
    s = start()
    rules.add_status(s.players[0].characters[2].statuses, "Pyro Infusion")
    s.players[0].active = 2
    apply_action(s, next(a for a in legal_actions(s) if a.type == "skill" and a.index == 0))
    assert s.players[1].characters[0].aura == PYRO


def test_rain_sword_reduces_big_hits_twice():
    s = start(c0=("Xingqiu", "Fischl", "Diluc"), c1=("Kaeya", "Ganyu", "Xingqiu"))
    apply_action(s, next(a for a in legal_actions(s) if a.type == "skill" and a.index == 1))
    apply_action(s, Action("end_round", 1))
    hit(s, 0, 3, PHYSICAL, tp=0); hit(s, 0, 1, PHYSICAL, tp=0); hit(s, 0, 3, PHYSICAL, tp=0)
    assert s.players[0].characters[0].hp == 5      # hits of 3, 1, 3 -> 2, 1, 2 taken; sword used up
    assert not any(x.name == "Rain Sword" for x in s.players[0].combat)


# ---------------------------------------------------------------- engine properties
def test_clone_is_independent():
    s = start()
    c = s.clone()
    apply_action(c, next(a for a in legal_actions(c) if a.type == "skill"))
    assert s.players[1].characters[0].hp == 10 and c.players[1].characters[0].hp < 10


def test_same_seed_same_game():
    def run(seed):
        s = rules.new_game(["Keqing", "Mona", "Zhongli"], content.starter_deck(),
                           ["Diluc", "Sucrose", "Ganyu"], content.starter_deck(), seed)
        bots = [RandomAI(5), RandomAI(6)]
        while s.phase != "over" and s.round < 30:
            apply_action(s, bots[actor(s)].choose(s))
        return s.winner, s.round, [c.hp for P in s.players for c in P.characters]
    assert run(42) == run(42)


def test_many_random_games_finish_without_errors():
    from simulate import play_game
    for seed in range(60):
        s, steps, _ = play_game(seed)
        assert s.phase == "over" or s.round > 40 or steps >= 3000
        if s.phase != "over":
            assert legal_actions(s)           # never stuck without a legal move


def test_engine_announces_phases_and_rounds():
    s = start()
    apply_action(s, Action("end_round", 0))
    apply_action(s, Action("end_round", 1))
    kinds = [(k, e.get("name")) for k, e in s.events]
    assert ("phase", "end") in kinds and any(k == "round" for k, _ in kinds)
    while s.phase != "action":
        apply_action(s, legal_actions(s)[0])
    assert ("phase", "action") in [(k, e.get("name")) for k, e in s.events]

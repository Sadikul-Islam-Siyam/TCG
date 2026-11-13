"""Headless UI behaviour tests (SDL dummy video driver)."""
import os
import time

os.environ.setdefault("SDL_VIDEODRIVER", "dummy")
import pygame
import pytest

from engine import rules
from engine.core import Action
from main import build_scene
from ui.match import INTRO_DUR
from ui.theme import W, H

pygame.init()
SCREEN = pygame.display.set_mode((W, H))


def ev(kind, pos, button=1):
    return pygame.event.Event(kind, pos=pos, button=button)


def settle(scene, need_turn=True, limit=3000):
    for _ in range(limit):
        if scene.s.phase == "over" or (not scene.locked() and (scene.my_turn() or not need_turn)):
            return
        scene.update(0.1)
        time.sleep(0.0005)
    raise AssertionError(f"stuck in {scene.s.phase}")


def to_roll(scene):
    scene.intro_t = INTRO_DUR
    settle(scene)
    scene.press("mull_confirm")
    settle(scene)
    scene.click(scene.char_rect(scene.view, 0).center)
    for _ in range(300):
        if scene.s.phase == "roll" and scene.my_turn() and not scene.locked():
            return
        scene.update(0.1)
        time.sleep(0.0005)
    raise AssertionError("never reached the roll phase")


@pytest.fixture
def scene():
    s, _ = build_scene(SCREEN, "hvai", decks=(1, 0), seed=7, level="easy")
    return s


def test_coin_toss_blocks_play_until_it_ends(scene):
    assert scene.intro_t < INTRO_DUR and scene.locked()
    scene.click((640, 400))                              # too early to skip
    assert scene.intro_t < INTRO_DUR
    scene.intro_t = INTRO_DUR
    assert not scene.locked() or scene.fx.clock < scene.busy_until


def test_mulligan_confirm_goes_straight_to_character_choice(scene):
    scene.intro_t = INTRO_DUR
    settle(scene)
    assert scene.mulligan_stage()
    scene.sel_hand = {0}
    scene.press("mull_confirm")
    assert scene.me().mull_done and scene.s.phase == "setup"


def test_one_click_confirms_the_dice_and_starts_the_action_phase(scene):
    to_roll(scene)
    scene.sel_dice = {0, 1}
    scene.press("roll_confirm")                          # reroll + continue with a single click
    assert scene.me().roll_done and scene.me().rerolls == 0
    for _ in range(400):
        if scene.s.phase == "action":
            break
        scene.update(0.1)
        time.sleep(0.0005)
    assert scene.s.phase == "action"


def test_phase_events_are_announced(scene):
    to_roll(scene)
    scene.press("roll_confirm")
    for _ in range(400):
        if scene.s.phase == "action":
            break
        scene.update(0.1)
        time.sleep(0.0005)
    log = " ".join(t for t, _ in scene.log)
    assert "Round 1" in log and "Action Phase" in log


def go_action(scene):
    to_roll(scene)
    scene.press("roll_confirm")
    settle(scene)
    assert scene.s.phase == "action"


def test_played_move_locks_input_while_it_is_shown(scene):
    go_action(scene)
    scene.click(scene.skill_rect(0).center)
    assert scene.locked()
    hp = [c.hp for c in scene.s.players[1].characters]
    scene.click(scene.skill_rect(0).center)               # ignored while the last move is playing
    assert [c.hp for c in scene.s.players[1].characters] == hp


def test_card_drop_anywhere_on_dice_tray_converts_it(scene):
    go_action(scene)
    for _ in range(40):                                   # make sure some die can be converted
        if scene.tunable_dice():
            break
        scene.do(Action("end_round", scene.view)); settle(scene)
    assert scene.tunable_dice()
    n, dice = len(scene.me().hand), list(scene.me().dice)
    sp = scene.sprites[0]
    scene.handle(ev(pygame.MOUSEBUTTONDOWN, (int(sp["x"]), int(sp["y"]))))
    assert scene.drag
    scene.handle(ev(pygame.MOUSEBUTTONUP, (1190, 680)))   # empty part of the tray
    assert len(scene.me().hand) == n - 1 and scene.me().dice != dice


def test_right_click_converts_a_card(scene):
    go_action(scene)
    if not scene.tunable_dice():
        pytest.skip("no tunable die in this roll")
    n = len(scene.me().hand)
    scene.handle(ev(pygame.MOUSEBUTTONDOWN, scene.hand_rect(0).center, 3))
    assert len(scene.me().hand) == n - 1


def test_opponent_layout_is_a_180_degree_mirror(scene):
    for i in range(3):
        mine, theirs = scene.char_rect(0, i), scene.char_rect(1, 2 - i)
        assert mine.x == theirs.x and mine.size == theirs.size
    assert scene.zone_rect(0, "support", 0).x != scene.zone_rect(1, "support", 0).x   # mirrored sides
    assert scene.zone_rect(0, "support", 0).x == scene.zone_rect(1, "summon", 0).x
    top, bottom = scene.char_rect(1, 0), scene.char_rect(0, 0)
    assert abs((top.y + top.h / 2 - 256) + (bottom.y + bottom.h / 2 - 256)) < 1       # symmetric about the centre line

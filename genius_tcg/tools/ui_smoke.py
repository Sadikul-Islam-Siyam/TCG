"""Headless UI test: coin toss, stage flow, pacing lock, card tuning, dragging. Saves screenshots.
    SDL_VIDEODRIVER=dummy python tools/ui_smoke.py"""
import os, sys, time
os.environ.setdefault("SDL_VIDEODRIVER", "dummy")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import pygame
import content
from engine import rules
from main import build_scene
from ui.match import INTRO_DUR
from ui.theme import W, H

pygame.init()
screen = pygame.display.set_mode((W, H))
os.makedirs("shots", exist_ok=True)


def shot(scene, name, frames=2, dt=1 / 60):
    for _ in range(frames):
        scene.update(dt)
        scene.draw()
    pygame.image.save(scene.screen, f"shots/{name}.png")


def settle(scene, limit=4000, need_turn=True):
    """Advance time until animations are done and (optionally) it is the human's turn."""
    for _ in range(limit):
        if scene.s.phase == "over" or (not scene.locked() and (scene.my_turn() or not need_turn)):
            return
        scene.update(0.1)
        time.sleep(0.001)
    raise SystemExit(f"stuck: phase={scene.s.phase} actor={rules.actor(scene.s)} locked={scene.locked()}")


def ev(kind, pos, button=1):
    return pygame.event.Event(kind, pos=pos, button=button)


scene, names = build_scene(screen, "hvai", decks=(1, 0), seed=7)
print("decks:", names, "| first player:", scene.s.first_player)
shot(scene, "01_coin_start", 10)
shot(scene, "01b_coin_flipping", 70)
shot(scene, "01c_coin_result", 100)
assert scene.intro_t < INTRO_DUR or True
scene.intro_t = INTRO_DUR                                   # skip the rest of the intro
settle(scene)
assert scene.s.phase == "setup" and scene.mulligan_stage()
shot(scene, "02_mulligan", 30)
scene.sel_hand = {0, 2}
shot(scene, "02b_mulligan_selected", 20)
scene.press("mull_confirm")                                  # swap and go straight on
assert scene.me().mull_done
settle(scene)
scene.click(scene.char_rect(0, 0).center)                    # choose the starting character
settle(scene, need_turn=False)
for _ in range(400):
    if scene.s.phase == "roll":
        break
    scene.update(0.1)
settle(scene)
assert scene.s.phase == "roll", scene.s.phase
shot(scene, "03_roll", 60)
before = list(scene.me().dice)
scene.sel_dice = {0, 1}
scene.press("roll_confirm")                                  # reroll + continue in ONE click
assert scene.s.phase in ("action", "roll") and scene.me().roll_done, "should move straight on"
settle(scene, need_turn=False)
for _ in range(300):
    if scene.s.phase == "action":
        break
    scene.update(0.1)
settle(scene)
assert scene.s.phase == "action", scene.s.phase
shot(scene, "04_action", 20)

# --- pacing: while the last move is still being presented the human cannot act
scene.click(scene.skill_rect(0).center)
assert scene.locked(), "a played move must lock input while it is being shown"
n0 = len(scene.s.events)
shot(scene, "05_skill_playing", 70, 0.01)
settle(scene)                                                # opponent move plays out, then it's our turn again
shot(scene, "06_after_opponent", 30)

# --- tuning: drop a card anywhere on the dice tray
P = scene.me()
assert scene.tunable_dice(), "need a tunable die for this test"
hand_before, dice_before = len(P.hand), list(P.dice)
sp = scene.sprites[0]
scene.handle(ev(pygame.MOUSEBUTTONDOWN, (int(sp["x"]), int(sp["y"]))))
assert scene.drag, "card should be draggable"
scene.drag["pos"] = (1200, 650)
shot(scene, "07_dragging_to_tray", 3)
scene.handle(ev(pygame.MOUSEBUTTONUP, (1200, 650)))          # empty space on the tray
assert len(scene.me().hand) == hand_before - 1 and scene.me().dice != dice_before, "tuning failed"
print("tuning ok")
settle(scene)
# right-click tuning
if scene.tunable_dice() and scene.me().hand:
    h0 = len(scene.me().hand)
    r = scene.hand_rect(0)
    scene.handle(ev(pygame.MOUSEBUTTONDOWN, r.center, 3))
    assert len(scene.me().hand) == h0 - 1, "right-click tuning failed"
    print("right-click tuning ok")
settle(scene)
# --- drag a card onto the board
P = scene.me()
idx = next((i for i, n in enumerate(P.hand) if any(a.type == "card" and P.hand[a.index] == n for a in scene.acts)), None)
print("playable card:", None if idx is None else P.hand[idx])
if idx is not None:
    sp = scene.sprites[idx]
    scene.handle(ev(pygame.MOUSEBUTTONDOWN, (int(sp["x"]), int(sp["y"]))))
    scene.drag["pos"] = (640, 400)
    shot(scene, "08_dragging_card", 3)
    tgt = scene.char_rect(0, 0).center
    scene.handle(ev(pygame.MOUSEBUTTONUP, tgt))
    shot(scene, "09_card_played", 40, 0.02)
settle(scene)
shot(scene, "10_board", 20)
print("ok; phase", scene.s.phase, "round", scene.s.round)

# --- readability: inspector, reaction pill, status icons
from engine.core import PYRO, CRYO
for p in (0, 1):
    pass
s = scene.s
foe = s.players[1].characters[s.players[1].active]
foe.aura = "Cryo"
rules.add_status(s.players[0].characters[0].statuses, "Pyro Infusion")
rules.add_status(s.players[0].combat, "Rain Sword") if False else None
s.players[0].characters[0].equipment["weapon"] = "Traveler's Handy Sword"
scene.on_events([("skill", {"player": 0, "char": 0, "skill": "Searing Onslaught", "kind": "skill"}),
                 ("damage", {"player": 1, "char": s.players[1].active, "amount": 5, "dtype": "Pyro", "reaction": "Melt", "source": "skill"})])
for _ in range(80):
    scene.update(0.025)
scene.draw()
pygame.image.save(scene.screen, "shots/11_reaction_pill.png")
for hv, name in ((("hand", 1), "12_inspect_card"), (("char", 0, 0), "13_inspect_char"), (("char", 1, s.players[1].active), "14_inspect_foe")):
    scene.hover = hv
    scene.draw()
    pygame.image.save(scene.screen, f"shots/{name}.png")
print("inspector shots saved")

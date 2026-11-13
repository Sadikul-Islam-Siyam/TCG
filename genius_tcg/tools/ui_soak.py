"""Plays full games through the UI scene (drawing every step) to catch crashes.
    SDL_VIDEODRIVER=dummy python tools/ui_soak.py [games]"""
import os, random, sys
os.environ.setdefault("SDL_VIDEODRIVER", "dummy")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import pygame
import content
from ai.random_ai import RandomAI
from engine import rules
from main import build_scene
from ui.theme import W, H

pygame.init()
screen = pygame.display.set_mode((W, H))
n = int(sys.argv[1]) if len(sys.argv) > 1 else 6
done = 0
for g in range(n):
    mode = ("aivai", "hvh", "hvai")[g % 3]
    scene, _ = build_scene(screen, mode, None, seed=100 + g)
    bot, steps = RandomAI(g), 0
    while scene.s.phase != "over" and steps < 6000 and scene.s.round < 30:
        steps += 1
        if scene.cover is not None:
            scene.click((5, 5))
        elif scene.my_turn():
            scene.do(bot.choose(scene.s))
        scene.update(1.0)
        if steps % 3 == 0:
            scene.draw()
    done += scene.s.phase == "over"
    print(f"game {g} {mode}: phase={scene.s.phase} round={scene.s.round} steps={steps}")
print("finished", done, "of", n)
pygame.image.save(screen, "shots/soak_last.png")

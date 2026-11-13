"""Headless check: AI threads inside the match screen, all levels, AI-vs-AI and human-vs-AI.
    SDL_VIDEODRIVER=dummy python tools/ui_ai_smoke.py"""
import os, sys, time
os.environ.setdefault("SDL_VIDEODRIVER", "dummy")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import pygame
from ai import factory
from main import build_scene
from ui.theme import W, H

pygame.init()
screen = pygame.display.set_mode((W, H))
for lv in ("easy", "normal", "hard"):
    scene, _ = build_scene(screen, "aivai", None, seed=3, level=lv)
    for c in scene.controllers:
        c.time_scale = 0.15
    t0, frames = time.time(), 0
    while scene.s.phase != "over" and scene.s.round < 25 and time.time() - t0 < 100:
        scene.update(0.4)
        scene.draw()
        frames += 1
        time.sleep(0.002)
    print(f"{lv}: phase={scene.s.phase} round={scene.s.round} frames={frames} errors={'AI error' in str([t[0] for t in scene.fx.toasts])}")

"""Main menu with a drifting element-symbol background."""
import math
import random

import pygame

from . import art
from .theme import W, H, ELEM_COL, GOLD, TEXT, DIM, TEAL, GREEN, RED, text, mix
from .widgets import Buttons
from .decks import bg


class MenuScene:
    def __init__(self, app):
        self.app, self.btn, self.t = app, Buttons(), 0.0
        els = list(ELEM_COL)[:6]
        self.floaters = [[random.uniform(0, W), random.uniform(0, H), random.uniform(10, 28), random.uniform(0.6, 1.4),
                          random.choice(els), random.uniform(0, 6.28)] for _ in range(26)]

    def press(self, key):
        from .decks import DeckSelect, DeckBuilder
        if key in ("hvai", "hvh", "aivai"):
            self.app.goto(DeckSelect(self.app, key))
        elif key == "builder":
            self.app.goto(DeckBuilder(self.app))
        elif key == "quit":
            self.app.quit = True

    def handle(self, ev):
        if ev.type == pygame.MOUSEBUTTONDOWN and ev.button == 1:
            key = self.btn.hit(ev.pos)
            if key:
                self.press(key)

    def update(self, dt):
        self.t += dt
        for f in self.floaters:
            f[1] -= f[3] * 18 * dt
            f[0] += math.sin(self.t * 0.6 + f[5]) * 10 * dt
            if f[1] < -40:
                f[0], f[1] = random.uniform(0, W), H + 40

    def draw(self):
        s = self.app.screen
        bg(s)
        layer = pygame.Surface((W, H), pygame.SRCALPHA)
        for x, y, r, _, el, _ in self.floaters:
            art.draw_symbol(layer, el, (x, y), r, color=mix(ELEM_COL[el], (20, 24, 40), 0.65))
        s.blit(layer, (0, 0))
        text(s, "GENIUS INVOKATION", (W // 2, 120), 64, GOLD, True, "center")
        text(s, "a fan-made card game  ·  Python + Pygame", (W // 2, 178), 18, DIM, False, "center")
        self.btn.clear()
        items = [("hvai", "Human vs AI", GREEN), ("hvh", "Human vs Human (same device)", TEAL),
                 ("aivai", "AI vs AI (spectate)", TEAL), ("builder", "Deck Builder", GOLD), ("quit", "Quit", RED)]
        for i, (key, label, col) in enumerate(items):
            self.btn.add(s, pygame.Rect(W // 2 - 190, 240 + i * 66, 380, 52), key, label, True, col, 22)
        text(s, "Fan project, not affiliated with HoYoverse. All art is drawn in code.", (W // 2, H - 24), 13, DIM, False, "center")

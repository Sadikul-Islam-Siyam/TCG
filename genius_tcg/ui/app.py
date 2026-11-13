"""Scene manager: menu, deck screens, match, and the pause overlay."""
import math

import pygame

from ai import factory
from .match import MatchScene
from .menu import MenuScene
from .theme import W, H, GOLD, TEXT, DIM, TEAL, GREEN, RED, text
from .widgets import Buttons

PAUSE_RECT = pygame.Rect(1218, 11, 48, 48)


class App:
    def __init__(self, screen):
        self.screen, self.quit, self.paused = screen, False, False
        self.pause_btn = Buttons()
        self.scene = MenuScene(self)

    def goto(self, scene):
        self.scene, self.paused = scene, False

    def start_match(self, mode, picks, seed=None, levels=("normal", "normal")):
        s2 = None if seed is None else seed + 1
        ctrl = {"hvai": ("human", factory.make(levels[1], seed)), "hvh": ("human", "human"),
                "aivai": (factory.make(levels[0], seed), factory.make(levels[1], s2))}[mode]
        self.goto(MatchScene(self.screen, picks, ctrl, seed))
        self.mode = mode

    def handle(self, ev):
        if ev.type == pygame.QUIT:
            self.quit = True
            return
        if ev.type == pygame.KEYDOWN and ev.key == pygame.K_F11:
            pygame.display.toggle_fullscreen()
            return
        in_match = isinstance(self.scene, MatchScene)
        if in_match and ev.type == pygame.KEYDOWN and ev.key == pygame.K_ESCAPE:
            self.paused = not self.paused
            return
        if in_match and not self.paused and ev.type == pygame.MOUSEBUTTONDOWN and ev.button == 1 and PAUSE_RECT.collidepoint(ev.pos):
            self.paused = True
            return
        if self.paused:
            if ev.type == pygame.MOUSEBUTTONDOWN and ev.button == 1:
                key = self.pause_btn.hit(ev.pos)
                if key == "resume":
                    self.paused = False
                elif key == "menu":
                    self.goto(MenuScene(self))
                elif key == "quit":
                    self.quit = True
            return
        if isinstance(self.scene, MenuScene) and ev.type == pygame.KEYDOWN and ev.key == pygame.K_ESCAPE:
            self.quit = True
            return
        self.scene.handle(ev)

    def update(self, dt):
        if not self.paused:
            self.scene.update(dt)

    def draw(self):
        self.scene.draw()
        if isinstance(self.scene, MatchScene):
            c = self.screen
            center = PAUSE_RECT.center
            pygame.draw.circle(c, (71, 54, 39), center, 23)
            pygame.draw.circle(c, (228, 206, 164), center, 20, 2)
            pygame.draw.circle(c, (29, 39, 52), center, 15)
            for i in range(8):
                a = i * math.pi / 4
                start = (center[0] + int(12 * math.cos(a)), center[1] + int(12 * math.sin(a)))
                end = (center[0] + int(17 * math.cos(a)), center[1] + int(17 * math.sin(a)))
                pygame.draw.line(c, (228, 206, 164), start, end, 3)
            pygame.draw.circle(c, (228, 206, 164), center, 7, 2)
        if self.paused:
            dim = pygame.Surface((W, H), pygame.SRCALPHA)
            dim.fill((0, 0, 0, 185))
            self.screen.blit(dim, (0, 0))
            text(self.screen, "Paused", (W // 2, 230), 52, GOLD, True, "center")
            self.pause_btn.clear()
            for i, (key, label, col) in enumerate((("resume", "Resume", GREEN), ("menu", "Back to menu", TEAL), ("quit", "Quit game", RED))):
                self.pause_btn.add(self.screen, pygame.Rect(W // 2 - 140, 290 + i * 62, 280, 48), key, label, True, col, 20)

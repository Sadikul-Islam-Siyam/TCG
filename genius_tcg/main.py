"""Genius Invokation TCG clone: Pygame front end (milestone 4, part 1: the match board).

    python main.py                  main menu (modes, deck builder)
    python main.py --mode hvai      skip the menu: human vs AI (also hvh, aivai)
    python main.py --decks 0 3      with --mode: preset deck numbers (0-5) for player 1 and 2
    python main.py --mode hvai --ai hard      AI level: easy | normal | hard
    python main.py --windowed       start windowed (default is fullscreen)
Keys: Esc pause / back, F11 fullscreen, F game speed, H reveal hands (spectator), R rematch after a game.
"""
import argparse
import random

import pygame

import content
from ai import factory
from ui.app import App
from ui.match import MatchScene
from ui.theme import W, H


def build_scene(screen, mode, decks=None, seed=None, level="easy"):
    presets = list(content.preset_decks().items())
    rng = random.Random(seed)
    picks = [presets[d] if d is not None else rng.choice(presets) for d in (decks or (None, None))]
    ctrl = {"hvai": ("human", factory.make(level, seed)), "hvh": ("human", "human"),
            "aivai": (factory.make(level, seed), factory.make(level, None if seed is None else seed + 1))}[mode]
    return MatchScene(screen, [p[1] for p in picks], ctrl, seed), [p[0] for p in picks]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=("hvai", "hvh", "aivai"), help="skip the menu and start a match")
    ap.add_argument("--decks", type=int, nargs=2)
    ap.add_argument("--seed", type=int)
    ap.add_argument("--windowed", action="store_true", help="start in a window instead of fullscreen")
    ap.add_argument("--ai", choices=("easy", "normal", "hard"), nargs="+", default=["normal"],
                    help="AI level(s): one for both AIs, or two (player 1, player 2)")
    args = ap.parse_args()
    pygame.init()
    flags = pygame.SCALED | (0 if args.windowed else pygame.FULLSCREEN)       # scales the 1280x720 game to any screen
    screen = pygame.display.set_mode((W, H), flags)
    pygame.display.set_caption("Genius Invokation TCG (fan project)")
    app = App(screen)
    if args.mode:
        presets = list(content.preset_decks().values())
        rng = random.Random(args.seed)
        picks = [presets[d] if d is not None else rng.choice(presets) for d in (args.decks or (None, None))]
        lv = (args.ai * 2)[:2]
        app.start_match(args.mode, picks, args.seed, tuple(lv))
    clock = pygame.time.Clock()
    while not app.quit:
        dt = clock.tick(60) / 1000
        for ev in pygame.event.get():
            app.handle(ev)
        app.update(dt)
        app.draw()
        pygame.display.flip()
    pygame.quit()


if __name__ == "__main__":
    main()

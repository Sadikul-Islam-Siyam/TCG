"""Headless test of menu -> deck builder -> deck select -> match -> pause.
    SDL_VIDEODRIVER=dummy python tools/ui_menu_smoke.py"""
import os, sys, tempfile
os.environ.setdefault("SDL_VIDEODRIVER", "dummy")
os.environ["GENIUS_TCG_HOME"] = tempfile.mkdtemp()
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import pygame
import content
from engine import deck as deckrules
from ui import store
from ui.app import App
from ui.decks import DeckBuilder, DeckSelect
from ui.match import MatchScene
from ui.menu import MenuScene
from ui.theme import W, H

pygame.init()
screen = pygame.display.set_mode((W, H))
os.makedirs("shots", exist_ok=True)
app = App(screen)


def frame(n=2, name=None):
    for _ in range(n):
        app.update(1 / 60)
        app.draw()
    if name:
        pygame.image.save(screen, f"shots/{name}.png")


def click(key, button=1):
    frame(1)
    btn = app.scene.btn if not app.paused else app.pause_btn
    for rect, k, ok in btn.items:
        if k == key and ok:
            app.handle(pygame.event.Event(pygame.MOUSEBUTTONDOWN, pos=rect.center, button=button))
            return
    raise SystemExit(f"button {key!r} not found/enabled in {type(app.scene).__name__}")


frame(3, "m1_menu")
click("builder"); assert isinstance(app.scene, DeckBuilder)
b = app.scene
for name in ("Keqing", "Fischl", "Xingqiu"):
    click(("char", name))
assert b.chars == ["Keqing", "Fischl", "Xingqiu"]
click("fill"); assert b.total() == 30, b.total()
assert deckrules.validate_deck(b.chars, b.cards()) == []
frame(3, "m2_builder_full")
# remove a card (right click on a card) then verify partial deck + status
click(("card", "Paimon"), 3)
assert b.total() == 29
frame(2, "m3_builder_partial")
b.name_box.value = "Test Deck"
click("save"); assert [d["name"] for d in store.list_decks()] == ["Test Deck"]
click("clear"); assert b.total() == 0 and not b.chars
click("load")
frame(2, "m4_load_modal")
app.handle(pygame.event.Event(pygame.MOUSEBUTTONDOWN, pos=(400, 170), button=1))   # first row = saved deck
assert b.chars == ["Keqing", "Fischl", "Xingqiu"] and b.total() == 29, (b.chars, b.total())
click("share"); frame(2, "m5_share")
code = b.modal[1]
click("close")
click("clear"); click("import")
b.input.value = code
click("do_import"); assert b.total() == 29
# talents vanish when a character is removed
click(("char", "Keqing")); assert "Thundering Penance" not in b.counts
b.search.value = "para"
frame(2)
click("back"); assert isinstance(app.scene, MenuScene)
click("hvai"); assert isinstance(app.scene, DeckSelect)
frame(2, "m6_select")
click("start"); assert isinstance(app.scene, MatchScene)
frame(30, "m7_match")
app.handle(pygame.event.Event(pygame.KEYDOWN, key=pygame.K_ESCAPE, mod=0, unicode=""))
assert app.paused
frame(2, "m8_pause")
click("menu"); assert isinstance(app.scene, MenuScene)
click("hvh"); click("start"); assert isinstance(app.scene, MatchScene)
click if False else None
print("menu flow ok")

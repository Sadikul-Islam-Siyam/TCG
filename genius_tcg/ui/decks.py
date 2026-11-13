"""Deck builder and deck-selection screens."""
import random
from collections import Counter

import pygame

import content
from engine import deck as deckrules
from engine.core import ELEMENTS
from engine.registry import CARD_DEFS, CHAR_DEFS
from . import art, store
from .theme import (W, H, ELEM_COL, PANEL, PANEL2, TEXT, DIM, GOLD, RED, GREEN, TEAL, font, text, wrap, mix, shade)
from .widgets import Buttons, TextBox, copy, paste

CARD_W, CARD_H = 96, 134
COLS, ROWS = 5, 3
TABS = ["All", "Event", "Support", "Weapon", "Artifact", "Talent", "Resonance"]


def tab_of(cd):
    return "Resonance" if cd.resonance else cd.kind.title()


def total_cost(cd):
    return cd.cost.n + cd.cost.unaligned


def requirement(cd):
    if cd.kind == "talent":
        return f"Talent: requires {cd.char} in the deck"
    if cd.kind == "weapon":
        return f"Weapon: requires a {cd.weapon} user in the deck"
    if cd.resonance:
        return f"Resonance: requires 2 {cd.resonance} characters"
    return f"{cd.kind.title()}: usable in any deck"


def bg(surface):
    surface.blit(art.table(), (0, 0))


def mini_char(surf, rect, name, selected=False, dim=False):
    d = CHAR_DEFS[name]
    art.portrait(surf, rect, name, d.element, d.weapon)
    if dim:
        s = pygame.Surface(rect.size, pygame.SRCALPHA)
        s.fill((10, 12, 20, 170))
        surf.blit(s, rect)
    pygame.draw.rect(surf, GOLD if selected else ELEM_COL[d.element], rect, 3 if selected else 1, border_radius=3)


# =====================================================================================
class DeckBuilder:
    def __init__(self, app, chars=None, cards=None, name="My Deck"):
        self.app = app
        self.chars, self.counts = list(chars or []), Counter(cards or [])
        self.btn = Buttons()
        self.name_box = TextBox((130, 10, 230, 32), name, 24, "Deck name")
        self.search = TextBox((660, 100, 240, 28), "", 20, "Search by name…")
        self.input = TextBox((360, 330, 560, 34), "", 600, "Paste a share code (Ctrl+V)")
        self.tab, self.element, self.cost, self.allowed_only = "All", None, None, True
        self.page, self.scroll, self.modal, self.msg, self.msg_t = 0, 0, None, "", 0.0
        self.hover = None

    # ---------------------------------------------------------------- state helpers
    def cards(self):
        return [n for n, c in self.counts.items() for _ in range(c)]

    def total(self):
        return sum(self.counts.values())

    def say(self, s, ok=False):
        self.msg, self.msg_t, self.msg_ok = s, 3.5, ok

    def allowed(self, name):
        return deckrules.card_allowed(CARD_DEFS[name], self.chars)

    def visible_cards(self):
        out = []
        q = self.search.value.strip().lower()
        for n, cd in sorted(CARD_DEFS.items(), key=lambda kv: (total_cost(kv[1]), kv[0])):
            if self.tab != "All" and tab_of(cd) != self.tab:
                continue
            if self.element:
                owner = CHAR_DEFS[cd.char].element if cd.char else None
                if self.element not in (cd.cost.element, cd.resonance, owner):
                    continue
            if self.cost is not None and (total_cost(cd) != self.cost if self.cost < 4 else total_cost(cd) < 4):
                continue
            if q and q not in n.lower():
                continue
            if self.allowed_only and not self.allowed(n):
                continue
            out.append(n)
        return out

    def prune(self):
        gone = [n for n in list(self.counts) if not self.allowed(n)]
        for n in gone:
            del self.counts[n]
        if gone:
            self.say(f"Removed {sum(1 for _ in gone)} card type(s) that no longer fit these characters")

    def toggle_char(self, name):
        if name in self.chars:
            self.chars.remove(name)
            self.prune()
        elif len(self.chars) < 3:
            self.chars.append(name)
        else:
            self.say("Already 3 characters. Click one to remove it first.")

    def add_card(self, name):
        cd = CARD_DEFS[name]
        if not self.allowed(name):
            self.say("Not allowed: " + requirement(cd).split(": ", 1)[1].replace("requires", "needs"))
        elif self.counts[name] >= deckrules.MAX_COPIES:
            self.say(f"Max {deckrules.MAX_COPIES} copies of a card")
        elif self.total() >= deckrules.DECK_SIZE:
            self.say("Deck already has 30 cards")
        else:
            self.counts[name] += 1

    def remove_card(self, name):
        if self.counts[name] > 0:
            self.counts[name] -= 1
            if self.counts[name] == 0:
                del self.counts[name]

    def validation(self):
        if len(self.chars) < 3:
            return [f"Pick {3 - len(self.chars)} more character(s)"], False
        errs = deckrules.validate_deck(self.chars, self.cards())
        return (errs or ["Deck is legal"]), not errs

    # ---------------------------------------------------------------- actions
    def press(self, key):
        if key == "back":
            from .menu import MenuScene
            self.app.goto(MenuScene(self.app))
        elif key == "clear":
            self.chars, self.counts = [], Counter()
        elif key == "fill":
            if len(self.chars) < 3:
                return self.say("Pick 3 characters first")
            from content.presets import priority
            res = deckrules.autofill(self.chars, self.cards(), priority())
            if res is None:
                return self.say("Can't complete this deck")
            self.counts = Counter(res)
            self.say("Deck completed by the constraint solver", True)
        elif key == "save":
            if len(self.chars) != 3:
                return self.say("Pick 3 characters before saving")
            try:
                store.save_deck(self.name_box.value, self.chars, self.cards())
                self.say(f"Saved '{self.name_box.value.strip()}'" + ("" if self.validation()[1] else " (draft: not yet playable)"), True)
            except (ValueError, OSError) as e:
                self.say(f"Could not save: {e}")
        elif key == "load":
            self.modal = ("load",)
        elif key == "share":
            if len(self.chars) != 3:
                return self.say("Pick 3 characters first")
            code = deckrules.encode(self.chars, self.cards())
            self.modal = ("share", code, copy(code))
        elif key == "import":
            self.input.value, self.input.focus = "", True
            self.modal = ("import",)
        elif key == "close":
            self.modal = None
        elif key == "do_import":
            try:
                chars, cards = deckrules.decode(self.input.value.strip())
                if len(chars) != 3 or any(c not in CHAR_DEFS for c in chars) or any(c not in CARD_DEFS for c in cards):
                    raise ValueError
            except Exception:
                return self.say("That share code is not valid")
            self.chars, self.counts, self.modal = chars, Counter(cards), None
            self.say("Deck imported", True)
        elif key == "copy" and self.modal:
            self.say("Copied to clipboard" if copy(self.modal[1]) else "Clipboard unavailable: select the code manually", True)
        elif key == "allowed":
            self.allowed_only, self.page = not self.allowed_only, 0
        elif key == "element":
            order = [None] + list(ELEMENTS)
            self.element, self.page = order[(order.index(self.element) + 1) % len(order)], 0
        elif key == "costf":
            order = [None, 0, 1, 2, 3, 4]
            self.cost, self.page = order[(order.index(self.cost) + 1) % len(order)], 0
        elif key == "prev":
            self.page = max(0, self.page - 1)
        elif key == "next":
            self.page += 1
        elif isinstance(key, tuple):
            kind = key[0]
            if kind == "tab":
                self.tab, self.page = key[1], 0
            elif kind == "char":
                self.toggle_char(key[1])
            elif kind == "card":
                self.add_card(key[1])
            elif kind == "row":
                self.remove_card(key[1])
            elif kind == "loaddeck":
                d = key[1]
                self.chars, self.counts, self.modal = list(d["chars"]), Counter(d["cards"]), None
                self.name_box.value = d["name"] if key[2] else d["name"] + " copy"
                self.say(f"Loaded '{d['name']}'", True)
            elif kind == "deldeck":
                store.delete_deck(key[1])

    # ---------------------------------------------------------------- input
    def handle(self, ev):
        if ev.type == pygame.KEYDOWN:
            if self.modal and self.modal[0] == "import" and self.input.key(ev):
                return
            if self.name_box.key(ev) or self.search.key(ev):
                self.page = 0
                return
            if ev.key == pygame.K_ESCAPE:
                if self.modal:
                    self.modal = None
                else:
                    self.press("back")
        elif ev.type == pygame.MOUSEBUTTONDOWN and ev.button in (1, 3):
            if self.modal:
                self.input.click(ev.pos) if self.modal[0] == "import" else None
                key = self.btn.hit(ev.pos)
                if key is not None and ev.button == 1:
                    self.press(key)
                return
            self.name_box.click(ev.pos)
            self.search.click(ev.pos)
            key = self.btn.hit(ev.pos)
            if key is None:
                return
            if ev.button == 3:      # right click removes a copy
                if isinstance(key, tuple) and key[0] == "card":
                    self.remove_card(key[1])
                return
            self.press(key)
        elif ev.type == pygame.MOUSEWHEEL:
            x, y = pygame.mouse.get_pos()
            if x > 910:
                self.scroll = max(0, self.scroll - ev.y)
            elif x > 310:
                self.page = max(0, self.page - ev.y)

    def update(self, dt):
        self.msg_t = max(0.0, self.msg_t - dt)
        self.hover = None
        pos = pygame.mouse.get_pos()
        for rect, key, ok in self.btn.items:
            if rect.collidepoint(pos) and isinstance(key, tuple) and key[0] in ("card", "row"):
                self.hover = key[1]

    # ---------------------------------------------------------------- drawing
    def draw(self):
        s = self.app.screen
        bg(s)
        self.btn.clear()
        b = self.btn
        modal = self.modal is not None
        b.add(s, pygame.Rect(20, 10, 96, 32), "back", "< Back", not modal, DIM)
        self.name_box.draw(s)
        x = 372
        for label, key, col in (("Save", "save", GREEN), ("Load", "load", TEAL), ("Auto-fill", "fill", GOLD),
                                ("Share", "share", TEAL), ("Import", "import", TEAL), ("Clear", "clear", RED)):
            w = 100 if key == "fill" else 84
            b.add(s, pygame.Rect(x, 10, w, 32), key, label, not modal, col, 15)
            x += w + 8
        self.draw_left(s)
        self.draw_center(s)
        self.draw_right(s)
        if self.hover and not modal:
            x = 320 if pygame.mouse.get_pos()[0] > 910 else 946
            img = art.card_large(CARD_DEFS[self.hover])
            r = img.get_rect(topleft=(x, 70))
            art.add_glow(s, r.center, (255, 215, 130), 240, 0.3)
            s.blit(img, r)
        if modal:
            self.draw_modal(s)

    def draw_left(self, s):
        b, modal = self.btn, self.modal is not None
        text(s, f"Characters {len(self.chars)}/3", (20, 70), 17, GOLD, True)
        for i in range(3):
            r = pygame.Rect(20 + i * 94, 98, 88, 112)
            if i < len(self.chars):
                mini_char(s, r.inflate(0, -22).move(0, 0), self.chars[i])
                text(s, self.chars[i], (r.centerx, r.bottom - 2), 13, TEXT, True, "midbottom")
                b.items.append((pygame.Rect(r.x, r.y, r.w, r.h - 20), ("char", self.chars[i]), not modal))
            else:
                pygame.draw.rect(s, (24, 30, 48), r, border_radius=8)
                pygame.draw.rect(s, (60, 70, 98), r, 2, border_radius=8)
                text(s, "empty", r.center, 14, DIM, False, "center")
        text(s, "Roster (click to add / remove)", (20, 226), 14, DIM)
        for k, name in enumerate(content.ROSTER):
            r = pygame.Rect(20 + (k % 5) * 56, 248 + (k // 5) * 72, 52, 64)
            picked = name in self.chars
            mini_char(s, r, name, picked, dim=not picked and len(self.chars) >= 3)
            text(s, name[:7], (r.centerx, r.bottom - 1), 11, TEXT, True, "midbottom")
            b.items.append((r, ("char", name), not modal))
        # composition + cost curve
        cards = self.cards()
        kinds = Counter(tab_of(CARD_DEFS[n]) for n in cards)
        text(s, "Composition", (20, 402), 15, GOLD, True)
        line = "  ".join(f"{k} {v}" for k, v in sorted(kinds.items())) or "no cards yet"
        for i, ln in enumerate(wrap(line, 13, 270)):
            text(s, ln, (20, 424 + i * 16), 13, DIM)
        text(s, "Cost curve", (20, 470), 15, GOLD, True)
        curve = Counter(min(total_cost(CARD_DEFS[n]), 4) for n in cards)
        peak = max(curve.values(), default=1)
        for c in range(5):
            h = int(70 * curve[c] / peak) if curve[c] else 0
            r = pygame.Rect(26 + c * 52, 546 - h, 38, h)
            pygame.draw.rect(s, TEAL, r, border_radius=4)
            text(s, curve[c], (r.centerx, r.y - 2), 13, TEXT, True, "midbottom")
            text(s, "4+" if c == 4 else c, (r.centerx, 550), 13, DIM, False, "midtop")
        msgs, ok = self.validation()
        y = 606
        text(s, "Status", (20, y - 22), 15, GOLD, True)
        for m in msgs[:5]:
            for ln in wrap(m, 13, 270)[:2]:
                text(s, ln, (20, y), 13, GREEN if ok else RED)
                y += 16

    def draw_center(self, s):
        b, modal = self.btn, self.modal is not None
        x = 320
        for t in TABS:
            w = 76 if t != "Resonance" else 92
            b.add(s, pygame.Rect(x, 64, w, 28), ("tab", t), t, not modal, TEAL, 14, active=self.tab == t)
            x += w + 5
        b.add(s, pygame.Rect(320, 100, 104, 28), "element", self.element or "Element: any", not modal, ELEM_COL.get(self.element, DIM), 14)
        b.add(s, pygame.Rect(430, 100, 96, 28), "costf", "Cost: any" if self.cost is None else f"Cost: {self.cost}{'+' if self.cost == 4 else ''}", not modal, DIM, 14)
        b.add(s, pygame.Rect(532, 100, 120, 28), "allowed", "Fits deck only" if self.allowed_only else "Show all", not modal, GOLD, 14, active=self.allowed_only)
        self.search.draw(s, 15)
        names = self.visible_cards()
        pages = max(1, -(-len(names) // (COLS * ROWS)))
        self.page = min(self.page, pages - 1)
        shown = names[self.page * COLS * ROWS:(self.page + 1) * COLS * ROWS]
        if not names:
            text(s, "No cards match. Pick characters, or switch to 'Show all'.", (620, 300), 16, DIM, False, "center")
        for i, n in enumerate(shown):
            r = pygame.Rect(322 + (i % COLS) * 114, 142 + (i // COLS) * 148, CARD_W, CARD_H)
            cd = CARD_DEFS[n]
            ok = self.allowed(n) and self.counts[n] < deckrules.MAX_COPIES
            art.action_card(s, r, cd, glow=self.counts[n] > 0, dim=not ok)
            if self.counts[n]:
                pygame.draw.circle(s, (20, 24, 38), (r.right - 4, r.y + 4), 14)
                pygame.draw.circle(s, GOLD, (r.right - 4, r.y + 4), 14, 2)
                text(s, f"x{self.counts[n]}", (r.right - 4, r.y + 4), 14, GOLD, True, "center")
            b.items.append((r, ("card", n), not modal))
        b.add(s, pygame.Rect(320, 596, 80, 28), "prev", "< Prev", self.page > 0 and not modal, DIM, 14)
        text(s, f"Page {self.page + 1}/{pages}   ({len(names)} cards)", (610, 610), 14, DIM, False, "center")
        b.add(s, pygame.Rect(820, 596, 80, 28), "next", "Next >", self.page < pages - 1 and not modal, DIM, 14)
        # info strip
        info = pygame.Rect(320, 636, 580, 64)
        pygame.draw.rect(s, PANEL, info, border_radius=8)
        if self.msg_t > 0:
            text(s, self.msg, (info.centerx, info.centery), 16, GREEN if getattr(self, "msg_ok", False) else GOLD, True, "center")
        elif self.hover:
            cd = CARD_DEFS[self.hover]
            text(s, cd.name, (info.x + 12, info.y + 8), 17, GOLD, True)
            art.draw_cost(s, (info.x + 12, info.y + 34), cd.cost, 16)
            text(s, requirement(cd), (info.x + 120, info.y + 36), 14, TEXT)
        else:
            text(s, "Left click: add a copy    Right click: remove    Wheel: change page", (info.centerx, info.centery), 14, DIM, False, "center")

    def draw_right(self, s):
        b, modal = self.btn, self.modal is not None
        n = self.total()
        pygame.draw.rect(s, PANEL, (920, 62, 340, 640), border_radius=10)
        text(s, f"Deck  {n}/30", (936, 70), 20, GOLD if n != 30 else GREEN, True)
        rows = sorted(self.counts.items(), key=lambda kv: (total_cost(CARD_DEFS[kv[0]]), kv[0]))
        per = 25
        self.scroll = max(0, min(self.scroll, max(0, len(rows) - per)))
        for i, (name, c) in enumerate(rows[self.scroll:self.scroll + per]):
            r = pygame.Rect(930, 102 + i * 23, 320, 21)
            cd = CARD_DEFS[name]
            pygame.draw.rect(s, mix(PANEL2, art.KIND_COL[cd.kind], 0.25), r, border_radius=5)
            text(s, total_cost(cd), (r.x + 12, r.centery), 13, GOLD, True, "center", shadow=False)
            text(s, name, (r.x + 30, r.centery), 14, TEXT, False, "midleft", shadow=False)
            text(s, f"x{c}", (r.right - 8, r.centery), 14, GOLD, True, "midright", shadow=False)
            b.items.append((r, ("row", name), not modal))
        if not rows:
            text(s, "Click cards to add them", (1090, 300), 15, DIM, False, "center")
        elif len(rows) > per:
            text(s, f"scroll for more ({len(rows) - per})", (1090, 686), 12, DIM, False, "center")

    def draw_modal(self, s):
        dim = pygame.Surface((W, H), pygame.SRCALPHA)
        dim.fill((0, 0, 0, 190))
        s.blit(dim, (0, 0))
        b, kind = self.btn, self.modal[0]
        panel = pygame.Rect(340, 110, 600, 500)
        pygame.draw.rect(s, PANEL, panel, border_radius=14)
        pygame.draw.rect(s, GOLD, panel, 2, border_radius=14)
        b.items = [it for it in b.items if False]          # only modal buttons are clickable
        b.add(s, pygame.Rect(panel.right - 110, panel.bottom - 50, 96, 34), "close", "Close", True, DIM)
        if kind == "load":
            text(s, "Load a deck", (panel.centerx, panel.y + 14), 22, GOLD, True, "midtop")
            entries = [(d["name"], d["chars"], d["cards"], True, d) for d in store.list_decks()]
            entries += [(n + "  (preset)", c, cards, False, {"name": n, "chars": c, "cards": cards}) for n, (c, cards) in content.preset_decks().items()]
            for i, (nm, chars, cards, saved, d) in enumerate(entries[:13]):
                r = pygame.Rect(panel.x + 20, panel.y + 56 + i * 31, 480, 28)
                legal = not deckrules.validate_deck(chars, cards)
                pygame.draw.rect(s, PANEL2, r, border_radius=6)
                text(s, nm + ("" if legal else "  (draft)"), (r.x + 10, r.centery), 15, TEXT if legal else GOLD, False, "midleft", shadow=False)
                text(s, ", ".join(chars), (r.right - 8, r.centery), 12, DIM, False, "midright", shadow=False)
                b.items.append((r, ("loaddeck", d, saved), True))
                if saved:
                    b.add(s, pygame.Rect(r.right + 8, r.y, 56, 28), ("deldeck", d["name"]), "Del", True, RED, 13)
            if not entries:
                text(s, "No decks yet", panel.center, 16, DIM, False, "center")
        elif kind == "share":
            text(s, "Share code", (panel.centerx, panel.y + 14), 22, GOLD, True, "midtop")
            text(s, "Anyone can paste this into Import to get your deck.", (panel.centerx, panel.y + 52), 14, DIM, False, "midtop")
            code = self.modal[1]
            for i, ln in enumerate([code[j:j + 62] for j in range(0, len(code), 62)][:12]):
                text(s, ln, (panel.x + 24, panel.y + 90 + i * 22), 15, TEXT, False, "topleft", shadow=False)
            b.add(s, pygame.Rect(panel.x + 24, panel.bottom - 50, 160, 34), "copy", "Copy to clipboard", True, GREEN, 14)
        elif kind == "import":
            text(s, "Import a deck", (panel.centerx, panel.y + 14), 22, GOLD, True, "midtop")
            text(s, "Paste a share code below (Ctrl+V) and press Import.", (panel.centerx, panel.y + 52), 14, DIM, False, "midtop")
            self.input.rect = pygame.Rect(panel.x + 24, panel.y + 100, panel.w - 48, 34)
            self.input.draw(s, 14)
            b.add(s, pygame.Rect(panel.x + 24, panel.bottom - 50, 120, 34), "do_import", "Import", bool(self.input.value), GREEN)


# =====================================================================================
class DeckSelect:
    """Pick a deck for each player, then start the match."""

    def __init__(self, app, mode):
        self.app, self.mode = app, mode
        self.btn = Buttons()
        self.entries = [("Random deck (built by the AI)", None, None, True)]
        for n, (c, cards) in content.preset_decks().items():
            self.entries.append((n + "  (preset)", c, cards, True))
        for d in store.list_decks():
            self.entries.append((d["name"] + ("" if d["legal"] else "  (incomplete)"), d["chars"], d["cards"], d["legal"]))
        self.pick, self.scroll, self.levels = [0, 0], [0, 0], ["normal", "normal"]
        self.titles = {"hvai": ("Your deck", "AI opponent's deck"), "hvh": ("Player 1 deck", "Player 2 deck"),
                       "aivai": ("AI 1 deck", "AI 2 deck")}[mode]
        self.msg = ""

    def press(self, key):
        if key == "back":
            from .menu import MenuScene
            self.app.goto(MenuScene(self.app))
        elif key == "start":
            picks = []
            for p in range(2):
                name, chars, cards, ok = self.entries[self.pick[p]]
                if chars is None:
                    from ai.deckgen import random_deck
                    chars, cards = random_deck()
                picks.append((chars, cards))
            self.app.start_match(self.mode, picks, levels=tuple(self.levels))
        elif key == "builder":
            self.app.goto(DeckBuilder(self.app))
        elif isinstance(key, tuple) and key[0] == "level":
            self.levels[key[1]] = key[2]
        elif isinstance(key, tuple) and key[0] == "pick":
            if self.entries[key[2]][3]:
                self.pick[key[1]] = key[2]
            else:
                self.msg = "That deck is incomplete. Finish it in the Deck Builder."

    def handle(self, ev):
        if ev.type == pygame.MOUSEBUTTONDOWN and ev.button == 1:
            key = self.btn.hit(ev.pos)
            if key is not None:
                self.press(key)
        elif ev.type == pygame.MOUSEWHEEL:
            col = 0 if pygame.mouse.get_pos()[0] < W // 2 else 1
            self.scroll[col] = max(0, min(self.scroll[col] - ev.y, max(0, len(self.entries) - 9)))
        elif ev.type == pygame.KEYDOWN and ev.key == pygame.K_ESCAPE:
            self.press("back")

    def update(self, dt):
        pass

    def draw(self):
        s = self.app.screen
        bg(s)
        self.btn.clear()
        b = self.btn
        text(s, {"hvai": "Human vs AI", "hvh": "Human vs Human", "aivai": "AI vs AI"}[self.mode], (W // 2, 24), 34, GOLD, True, "midtop")
        for p in range(2):
            x0 = 60 + p * 600
            text(s, self.titles[p], (x0, 100), 22, TEXT, True)
            if self.mode == "aivai" or (self.mode == "hvai" and p == 1):
                for k, lv in enumerate(("easy", "normal", "hard")):
                    b.add(s, pygame.Rect(x0 + 330 + k * 76, 96, 72, 30), ("level", p, lv), lv.title(), True,
                          {"easy": GREEN, "normal": TEAL, "hard": RED}[lv], 14, active=self.levels[p] == lv)
                text(s, "AI level", (x0 + 322, 111), 14, DIM, False, "midright")
            for i, (nm, chars, cards, ok) in enumerate(self.entries[self.scroll[p]:self.scroll[p] + 9]):
                idx = i + self.scroll[p]
                r = pygame.Rect(x0, 136 + i * 40, 560, 36)
                sel = self.pick[p] == idx
                pygame.draw.rect(s, mix(PANEL, GOLD, 0.25) if sel else PANEL, r, border_radius=8)
                pygame.draw.rect(s, GOLD if sel else (70, 80, 108), r, 2, border_radius=8)
                text(s, nm, (r.x + 12, r.centery), 16, TEXT if ok else DIM, sel, "midleft", shadow=False)
                if chars:
                    for k, c in enumerate(chars):
                        mini_char(s, pygame.Rect(r.right - 108 + k * 34, r.y + 3, 30, 30), c)
                b.items.append((r, ("pick", p, idx), True))
            name, chars, cards, ok = self.entries[self.pick[p]]
            if chars:
                for k, c in enumerate(chars):
                    r = pygame.Rect(x0 + 40 + k * 170, 512, 120, 150)
                    mini_char(s, r, c, True)
                    text(s, c, (r.centerx, r.bottom + 6), 15, TEXT, True, "midtop")
            else:
                text(s, "The AI will build a random deck (CSP solver)", (x0 + 280, 580), 16, DIM, False, "center")
        if self.msg:
            text(s, self.msg, (W // 2, 480), 15, GOLD, True, "midtop")
        b.add(s, pygame.Rect(20, 676, 100, 34), "back", "< Back", True, DIM)
        b.add(s, pygame.Rect(W // 2 - 110, 676, 220, 38), "start", "Start match", True, GREEN, 20)
        b.add(s, pygame.Rect(W - 230, 676, 210, 34), "builder", "Open Deck Builder", True, TEAL, 15)

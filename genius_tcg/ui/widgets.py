"""Small immediate-mode widgets: buttons and a text box."""
import pygame

from .theme import PANEL, TEXT, DIM, GOLD, GOLD_L, TEAL, mix, shade, text


def paste():
    try:
        pygame.scrap.init()
        s = pygame.scrap.get_text()
        return s or ""
    except Exception:
        return ""


def copy(s):
    try:
        pygame.scrap.init()
        pygame.scrap.put_text(s)
        return True
    except Exception:
        return False


class Buttons:
    """Call add() while drawing; call hit(pos) on click."""

    def __init__(self):
        self.items = []

    def clear(self):
        self.items = []

    def add(self, surf, rect, key, label, enabled=True, col=TEAL, size=16, active=False):
        from . import art
        hov = enabled and rect.collidepoint(pygame.mouse.get_pos())
        if enabled and (hov or active):
            art.add_glow(surf, rect.center, GOLD, max(rect.w, rect.h) * 0.75, 0.45 if hov else 0.3)
        base = mix((78, 58, 40), col, 0.4)
        art.plaque(surf, rect, 9, shade(base, 1.25 if hov else (1.1 if active else 0.9)) if enabled else (58, 54, 50))
        if active:
            pygame.draw.rect(surf, GOLD_L, rect, 2, border_radius=9)
        text(surf, label, rect.center, size, TEXT if enabled else DIM, True, "center")
        self.items.append((pygame.Rect(rect), key, enabled))

    def hit(self, pos):
        for rect, key, ok in reversed(self.items):
            if ok and rect.collidepoint(pos):
                return key
        return None


class TextBox:
    def __init__(self, rect, value="", max_len=24, placeholder=""):
        self.rect, self.value, self.max_len, self.placeholder = pygame.Rect(rect), value, max_len, placeholder
        self.focus = False

    def click(self, pos):
        self.focus = self.rect.collidepoint(pos)
        return self.focus

    def key(self, ev):
        """Returns True if the key was consumed."""
        if not self.focus:
            return False
        if ev.key == pygame.K_BACKSPACE:
            self.value = self.value[:-1]
        elif ev.key in (pygame.K_RETURN, pygame.K_KP_ENTER, pygame.K_ESCAPE, pygame.K_TAB):
            self.focus = False
        elif ev.key == pygame.K_v and ev.mod & pygame.KMOD_CTRL:
            self.value = (self.value + paste().strip())[: self.max_len]
        elif ev.unicode and ev.unicode.isprintable():
            self.value = (self.value + ev.unicode)[: self.max_len]
        return True

    def draw(self, surf, size=17):
        pygame.draw.rect(surf, (14, 18, 30), self.rect, border_radius=7)
        pygame.draw.rect(surf, GOLD if self.focus else (80, 90, 118), self.rect, 2, border_radius=7)
        shown = self.value if self.value or self.focus else self.placeholder
        col = TEXT if self.value else DIM
        clip = surf.get_clip()
        surf.set_clip(self.rect.inflate(-10, 0))
        tail = shown[-40:] if self.rect.w < 300 else shown[-80:]
        r = text(surf, tail + ("|" if self.focus and (pygame.time.get_ticks() // 450) % 2 else ""), (self.rect.x + 8, self.rect.centery), size, col, False, "midleft", shadow=False)
        surf.set_clip(clip)

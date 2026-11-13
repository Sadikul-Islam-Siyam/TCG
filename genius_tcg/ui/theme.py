"""Palette, serif fonts and text helpers. Look: warm parchment cards, gold trim, deep teal table."""
import pygame

W, H = 1280, 720
ELEM_COL = {
    "Cryo": (157, 224, 255), "Hydro": (73, 166, 255), "Pyro": (255, 115, 75),
    "Electro": (194, 132, 255), "Anemo": (112, 232, 195), "Geo": (255, 202, 92),
    "Omni": (244, 243, 255), "Physical": (218, 222, 228), "Piercing": (244, 244, 252),
}
# Cool lacquer and restrained gold trim, with bright card stock for contrast.
BG, PANEL, PANEL2 = (12, 20, 32), (22, 34, 50), (31, 47, 67)
PARCH, PARCH_D, INK = (244, 235, 212), (220, 202, 166), (49, 42, 34)
TEXT, DIM = (245, 241, 230), (169, 181, 196)
GOLD, GOLD_L, GOLD_D = (222, 185, 105), (255, 229, 165), (130, 94, 43)
RED, GREEN, TEAL = (231, 101, 94), (128, 218, 159), (98, 190, 208)

_fonts = {}
SERIF = "georgia,cambria,times new roman,liberation serif,dejavuserif"


def font(size, bold=False):
    key = (size, bold)
    if key not in _fonts:
        _fonts[key] = pygame.font.SysFont(SERIF, size, bold=bold)
    return _fonts[key]


def text(surf, s, pos, size=16, color=TEXT, bold=False, anchor="topleft", shadow=True):
    f = font(size, bold)
    img = f.render(str(s), True, color)
    r = img.get_rect(**{anchor: pos})
    if shadow:
        sh = f.render(str(s), True, (12, 8, 4))
        surf.blit(sh, r.move(1, 2))
    surf.blit(img, r)
    return r


def wrap(s, size, width, bold=False):
    f, lines, cur = font(size, bold), [], ""
    for word in str(s).split():
        t = (cur + " " + word).strip()
        if f.size(t)[0] <= width or not cur:
            cur = t
        else:
            lines.append(cur)
            cur = word
    return lines + ([cur] if cur else [])


def lerp(a, b, t):
    return a + (b - a) * t


def mix(c1, c2, t):
    return tuple(int(lerp(a, b, t)) for a, b in zip(c1, c2))


def shade(c, k):
    return tuple(max(0, min(255, int(v * k))) for v in c)


def ease_out(t):
    return 1 - (1 - min(1.0, max(0.0, t))) ** 3


def ease_in_out(t):
    t = min(1.0, max(0.0, t))
    return t * t * (3 - 2 * t)

import math
import os
import random
import zlib

import pygame

from .theme import (ELEM_COL, PARCH, PARCH_D, INK, GOLD, GOLD_L, GOLD_D, TEXT, DIM, W, H,
                    font, text, wrap, mix, shade)

ASSETS_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets")


def _find_asset(subdir, name):
    folder = os.path.join(ASSETS_DIR, subdir) if subdir else ASSETS_DIR
    safe_name = "".join("_" if ch in '<>:\"/\\|?*' else ch for ch in name).strip(" .")
    for candidate in (name, safe_name):
        target = os.path.join(folder, candidate)
        for ext in ("", ".jpg", ".png", ".jpeg", ".webp"):
            p = target + ext
            if os.path.isfile(p):
                return p
    if folder not in _asset_index:
        try:
            _asset_index[folder] = {_asset_key(file): os.path.join(folder, file)
                                    for file in os.listdir(folder)
                                    if os.path.splitext(file)[1].lower() in (".jpg", ".png", ".jpeg", ".webp")}
        except OSError:
            _asset_index[folder] = {}
    p = _asset_index[folder].get(_asset_key(name))
    if p and os.path.isfile(p):
        return p
    return None


_cache = {}
_asset_index = {}


def _asset_key(value):
    """Normalize punctuation so Windows-safe filenames match the game's card names."""
    return "".join(ch.casefold() for ch in os.path.splitext(value)[0] if ch.isalnum())


def _cover_image(image, size, focus=(0.5, 0.5)):
    """Scale an image without distortion, then crop around its focal point."""
    w, h = size
    iw, ih = image.get_size()
    scale = max(w / iw, h / ih)
    nw, nh = max(w, int(round(iw * scale))), max(h, int(round(ih * scale)))
    scaled = pygame.transform.smoothscale(image, (nw, nh))
    left = int((nw - w) * focus[0])
    top = int((nh - h) * focus[1])
    return scaled.subsurface(pygame.Rect(left, top, w, h)).copy()


def _pts(c, r, rel):
    return [(c[0] + x * r, c[1] + y * r) for x, y in rel]


# ------------------------------------------------------------------ element symbols
def draw_symbol(surf, el, c, r, color=None):
    col = color or ELEM_COL.get(el, (230, 230, 230))
    light = mix(col, (255, 255, 255), 0.55)
    w = max(2, int(r * 0.16))
    if el == "Pyro":
        pygame.draw.polygon(surf, col, _pts(c, r, [(0.1, -1), (0.65, -0.1), (0.5, 0.65), (0, 1), (-0.5, 0.65), (-0.62, -0.05), (-0.2, -0.35)]))
        pygame.draw.polygon(surf, light, _pts(c, r * 0.55, [(0.1, -0.2), (0.6, 0.45), (0, 1), (-0.6, 0.45)]))
    elif el == "Hydro":
        pygame.draw.polygon(surf, col, _pts(c, r, [(0, -1), (0.62, 0.15), (-0.62, 0.15)]))
        pygame.draw.circle(surf, col, (c[0], c[1] + r * 0.3), r * 0.66)
        pygame.draw.circle(surf, light, (c[0] - r * 0.22, c[1] + r * 0.15), max(1, r * 0.17))
    elif el == "Cryo":
        for k in range(3):
            a = math.pi / 3 * k
            dx, dy = math.cos(a) * r, math.sin(a) * r
            pygame.draw.line(surf, col, (c[0] - dx, c[1] - dy), (c[0] + dx, c[1] + dy), w)
            for s in (-1, 1):
                ex, ey = c[0] + s * dx * 0.62, c[1] + s * dy * 0.62
                for t in (-1, 1):
                    b = a + t * 0.9
                    pygame.draw.line(surf, light, (ex, ey), (ex + s * math.cos(b) * r * 0.3, ey + s * math.sin(b) * r * 0.3), max(1, w - 1))
    elif el == "Electro":
        pygame.draw.polygon(surf, col, _pts(c, r, [(0.25, -1), (-0.55, 0.12), (-0.05, 0.12), (-0.3, 1), (0.55, -0.2), (0.05, -0.2)]))
        pygame.draw.polygon(surf, light, _pts(c, r * 0.5, [(0.25, -1), (-0.3, 0.1), (0.1, 0.1)]))
    elif el == "Anemo":
        for k, rr in enumerate((1.0, 0.7, 0.4)):
            rect = pygame.Rect(0, 0, 2 * r * rr, 2 * r * rr)
            rect.center = (c[0] + (1 - rr) * r * 0.25, c[1])
            pygame.draw.arc(surf, col if k != 1 else light, rect, 0.5 + k, 4.6 + k * 0.5, w)
    elif el == "Geo":
        pygame.draw.polygon(surf, col, _pts(c, r, [(0, -1), (0.8, 0), (0, 1), (-0.8, 0)]))
        pygame.draw.polygon(surf, light, _pts(c, r, [(0, -1), (0.8, 0), (0, 0), (-0.8, 0)]))
    elif el == "Omni":
        pygame.draw.polygon(surf, col, _pts(c, r, [(0, -1), (0.28, -0.28), (1, 0), (0.28, 0.28), (0, 1), (-0.28, 0.28), (-1, 0), (-0.28, -0.28)]))
        pygame.draw.circle(surf, (120, 190, 255), c, max(2, r * 0.25))
    elif el == "Piercing":
        pygame.draw.line(surf, col, (c[0] - r, c[1] + r * 0.6), (c[0] + r, c[1] - r * 0.6), w)
        pygame.draw.polygon(surf, col, _pts((c[0] + r * 0.9, c[1] - r * 0.55), r * 0.5, [(0.5, -0.5), (-0.7, -0.3), (0.3, 0.7)]))
    else:  # Physical
        pygame.draw.line(surf, col, (c[0] - r * 0.8, c[1] - r * 0.8), (c[0] + r * 0.8, c[1] + r * 0.8), w + 1)
        pygame.draw.line(surf, col, (c[0] + r * 0.8, c[1] - r * 0.8), (c[0] - r * 0.8, c[1] + r * 0.8), w + 1)


# ------------------------------------------------------------------ glow, textures, frames
def glow(color, radius):
    """Soft round light for additive blending (blit with BLEND_RGB_ADD)."""
    key = ("glow", tuple(color), int(radius))
    if key not in _cache:
        r = max(2, int(radius))
        s = pygame.Surface((r * 2, r * 2))
        s.fill((0, 0, 0))
        for i in range(r, 0, -1):
            k = (1 - i / r) ** 2
            pygame.draw.circle(s, tuple(int(c * k) for c in color), (r, r), i)
        _cache[key] = s
    return _cache[key]


def add_glow(surf, center, color, radius, strength=1.0):
    g = glow(tuple(int(c * strength) for c in color), radius)
    surf.blit(g, g.get_rect(center=(int(center[0]), int(center[1]))), special_flags=pygame.BLEND_RGB_ADD)


def parchment(size, tone=PARCH, seed=0):
    key = ("parch", size, tone, seed)
    if key not in _cache:
        w, h = size
        rng = random.Random(zlib.crc32(repr(key).encode()))
        s = pygame.Surface(size)
        for y in range(h):                                   # soft top-to-bottom shading
            pygame.draw.line(s, mix(shade(tone, 1.04), shade(tone, 0.9), y / h), (0, y), (w, y))
        ov = pygame.Surface(size, pygame.SRCALPHA)
        for _ in range(w * h // 70):                         # speckle
            x, y = rng.randrange(w), rng.randrange(h)
            pygame.draw.circle(ov, (110, 80, 40, rng.randint(6, 22)), (x, y), rng.choice((1, 1, 2)))
        for _ in range(w * h // 600):                        # fibres
            x, y = rng.randrange(w), rng.randrange(h)
            pygame.draw.line(ov, (120, 90, 50, 14), (x, y), (x + rng.randint(-8, 8), y + rng.randint(-5, 5)))
        for i in range(10):                                  # aged edges
            pygame.draw.rect(ov, (110, 70, 30, 10), pygame.Rect(0, 0, w, h).inflate(-2 * i, -2 * i), 2)
        s.blit(ov, (0, 0))
        _cache[key] = s
    return _cache[key]


def rounded(surface, radius, tl=-1, tr=-1, bl=-1, br=-1):
    """Return a per-pixel-alpha copy of `surface` clipped to a rounded rectangle."""
    out = pygame.Surface(surface.get_size(), pygame.SRCALPHA)
    out.blit(surface, (0, 0))
    mask = pygame.Surface(surface.get_size(), pygame.SRCALPHA)
    pygame.draw.rect(mask, (255, 255, 255, 255), mask.get_rect(), border_radius=radius,
                     border_top_left_radius=tl, border_top_right_radius=tr,
                     border_bottom_left_radius=bl, border_bottom_right_radius=br)
    out.blit(mask, (0, 0), special_flags=pygame.BLEND_RGBA_MULT)
    return out


def gold_frame(surf, rect, radius=10, width=3, corners=True):
    rect = pygame.Rect(rect)
    pygame.draw.rect(surf, (40, 26, 10), rect, 1, border_radius=radius)
    for i, col in enumerate((GOLD_D, GOLD, GOLD_L, GOLD)[:max(2, width)]):
        pygame.draw.rect(surf, col, rect.inflate(-2 * (i + 1), -2 * (i + 1)), 1, border_radius=max(1, radius - i - 1))
    pygame.draw.rect(surf, (70, 46, 16), rect.inflate(-2 * (width + 1), -2 * (width + 1)), 1, border_radius=max(1, radius - width - 1))
    if corners:
        for cx, cy, sx, sy in ((rect.left, rect.top, 1, 1), (rect.right - 1, rect.top, -1, 1),
                               (rect.left, rect.bottom - 1, 1, -1), (rect.right - 1, rect.bottom - 1, -1, -1)):
            cx, cy = cx + 5 * sx, cy + 5 * sy
            pts = [(cx, cy - 4), (cx + 4, cy), (cx, cy + 4), (cx - 4, cy)]
            pygame.draw.polygon(surf, GOLD_L, pts)
            pygame.draw.polygon(surf, GOLD_D, pts, 1)


def plaque(surf, rect, radius=8, base=(80, 58, 38)):
    """Dark wooden name plate with a gold edge."""
    rect = pygame.Rect(rect)
    tmp = pygame.Surface(rect.size, pygame.SRCALPHA)
    for i in range(rect.h):
        pygame.draw.line(tmp, mix(shade(base, 1.3), shade(base, 0.7), i / rect.h), (0, i), (rect.w, i))
    surf.blit(rounded(tmp, radius), rect)
    pygame.draw.rect(surf, GOLD, rect, 2, border_radius=radius)
    pygame.draw.rect(surf, (40, 26, 10), rect.inflate(2, 2), 1, border_radius=radius)


def table():
    """Full-screen background: deep teal wood with a soft vignette."""
    if "table" not in _cache:
        board_asset = _find_asset("", "board")
        if board_asset:
            try:
                raw = pygame.image.load(board_asset).convert()
                _cache["table"] = _cover_image(raw, (W, H))
                return _cache["table"]
            except Exception:
                pass
        s = pygame.Surface((W, H))
        for y in range(H):
            pygame.draw.line(s, mix((28, 50, 54), (12, 20, 24), y / H), (0, y), (W, y))
        ov = pygame.Surface((W, H), pygame.SRCALPHA)
        rng = random.Random(5)
        for x in range(-H, W, 46):                             # faint woven pattern
            pygame.draw.line(ov, (255, 235, 190, 7), (x, 0), (x + H, H), 1)
            pygame.draw.line(ov, (255, 235, 190, 7), (x + H, 0), (x, H), 1)
        for _ in range(900):
            pygame.draw.circle(ov, (255, 240, 200, rng.randint(4, 12)), (rng.randrange(W), rng.randrange(H)), 1)
        s.blit(ov, (0, 0))
        vig = pygame.Surface((64, 36))
        for y in range(36):
            for x in range(64):
                d = math.hypot((x - 31.5) / 32, (y - 17.5) / 18)
                k = int(255 * max(0.35, 1 - 0.55 * d * d))
                vig.set_at((x, y), (k, k, k))
        s.blit(pygame.transform.smoothscale(vig, (W, H)), (0, 0), special_flags=pygame.BLEND_RGB_MULT)
        _cache["table"] = s
    return _cache["table"]


def mat(size):
    """Full-screen teal dueling board with an inset stone field and carved wood trim."""
    key = ("mat", size)
    if key not in _cache:
        w, h = size
        s = pygame.Surface(size)
        s.fill((47, 35, 29))
        # Layered beveled timber surround, matching the broad carved frame in the references.
        for inset, col in ((3, (35, 25, 22)), (7, (99, 72, 52)), (12, (182, 146, 102)),
                           (17, (60, 44, 35)), (23, (125, 96, 68)), (29, (49, 40, 34)),
                           (35, (177, 151, 112))):
            pygame.draw.rect(s, col, pygame.Rect(inset, inset, w - 2 * inset, h - 2 * inset), 2, border_radius=22)
        board = pygame.Rect(40, 40, w - 80, h - 80)
        felt = pygame.Surface(board.size)
        for y in range(board.h):
            pygame.draw.line(felt, mix((128, 169, 164), (91, 135, 133), y / max(1, board.h)), (0, y), (board.w, y))
        s.blit(rounded(felt, 18), board)
        tiles = pygame.Surface(board.size, pygame.SRCALPHA)
        # The game board uses a restrained repeating diamond tile, rather than a crosshatch.
        for row, y in enumerate(range(-22, board.h + 22, 44)):
            offset = 28 if row % 2 else 0
            for x in range(-28 + offset, board.w + 28, 56):
                points = ((x, y - 22), (x + 28, y), (x, y + 22), (x - 28, y))
                pygame.draw.polygon(tiles, (220, 242, 223, 25), points, 1)
                pygame.draw.line(tiles, (235, 250, 230, 15), (x - 28, y), (x, y - 22), 1)
        s.blit(tiles, board)
        c = board.center
        emblem = pygame.Surface(size, pygame.SRCALPHA)
        ring_r = min(122, board.h // 3)
        for rr, alpha in ((ring_r, 25), (ring_r - 12, 16), (ring_r // 2, 14)):
            pygame.draw.circle(emblem, (237, 247, 226, alpha), c, rr, 2)
        pygame.draw.line(emblem, (237, 247, 226, 18), (board.x + 12, c[1]), (board.right - 12, c[1]), 2)
        pygame.draw.line(emblem, (237, 247, 226, 16), (c[0], board.y + 12), (c[0], board.bottom - 12), 1)
        for k, el in enumerate(("Pyro", "Hydro", "Anemo", "Electro", "Cryo", "Geo")):
            ang = math.tau * k / 6 - math.pi / 2
            draw_symbol(emblem, el, (c[0] + math.cos(ang) * (ring_r - 7), c[1] + math.sin(ang) * (ring_r - 7)), 9,
                        (236, 243, 221))
        s.blit(emblem, (0, 0))
        gold_frame(s, board.inflate(8, 8), 20, 3, corners=False)
        pygame.draw.rect(s, (220, 190, 133), pygame.Rect(37, 37, w - 74, h - 74), 1, border_radius=22)
        # Small ornamental diamonds repeat the frame language at the midpoints.
        for x, y in ((w // 2, 19), (w // 2, h - 19), (19, h // 2), (w - 19, h // 2)):
            pygame.draw.polygon(s, (243, 218, 165), ((x, y - 7), (x + 7, y), (x, y + 7), (x - 7, y)))
            pygame.draw.polygon(s, (90, 65, 42), ((x, y - 7), (x + 7, y), (x, y + 7), (x - 7, y)), 1)
        _cache[key] = s
    return _cache[key]


# ------------------------------------------------------------------ gems, dice, costs
def gem(surf, c, r, el=None, kind="el"):
    base = ELEM_COL.get(el, (150, 156, 170)) if kind == "el" else ((236, 196, 98) if kind == "en" else (150, 156, 170))
    pygame.draw.circle(surf, (24, 16, 8), c, r + 1.5)
    for i in range(int(r), 0, -1):
        pygame.draw.circle(surf, mix(shade(base, 0.55), mix(base, (255, 255, 255), 0.35), 1 - i / r), (c[0] - (r - i) * 0.12, c[1] - (r - i) * 0.18), i)
    pygame.draw.circle(surf, GOLD_L, c, r, 1)
    if kind == "el" and el:
        draw_symbol(surf, el, c, r * 0.58, (255, 255, 255))
    elif kind == "en":
        pygame.draw.polygon(surf, (255, 255, 235), _pts(c, r * 0.55, [(0, -1), (0.8, 0), (0, 1), (-0.8, 0)]))
    else:
        pygame.draw.circle(surf, (235, 238, 245), c, max(1, r * 0.28))


def die_surface(face, size, selected=False, dim=False, hl=False):
    key = ("die", face, size, selected, dim, hl)
    if key in _cache:
        return _cache[key]
    s = pygame.Surface((size, size), pygame.SRCALPHA)
    c, r = (size / 2, size / 2), size / 2 - 3
    col = ELEM_COL[face]
    for k in range(7):
        t = k / 6
        rr = r * (1 - 0.1 * t)
        hexa = [(c[0] + math.cos(math.radians(60 * i - 30)) * rr, c[1] - t * 2 + math.sin(math.radians(60 * i - 30)) * rr) for i in range(6)]
        pygame.draw.polygon(s, mix(shade(col, 0.28), shade(col, 0.82), t), hexa)
    hexa = [(c[0] + math.cos(math.radians(60 * i - 30)) * r, c[1] + math.sin(math.radians(60 * i - 30)) * r) for i in range(6)]
    pygame.draw.polygon(s, GOLD_L if hl else (GOLD if selected else GOLD_D), hexa, 3 if (selected or hl) else 2)
    pygame.draw.polygon(s, (30, 20, 8), hexa, 1)
    gl = pygame.Surface((size, size), pygame.SRCALPHA)
    pygame.draw.ellipse(gl, (255, 255, 255, 70), pygame.Rect(size * 0.2, size * 0.1, size * 0.5, size * 0.28))
    s.blit(gl, (0, 0))
    draw_symbol(s, face, c, r * 0.52)
    if dim:
        s.fill((255, 255, 255, 110), special_flags=pygame.BLEND_RGBA_MULT)
    _cache[key] = s
    return s


def draw_die(surf, center, size, face, angle=0.0, selected=False, dim=False, hl=False, scale=1.0):
    if selected or hl:
        add_glow(surf, center, (255, 210, 110) if selected else (255, 255, 255), size * 0.8, 0.55)
    img = die_surface(face, size, selected, dim, hl)
    if angle or scale != 1.0:
        img = pygame.transform.rotozoom(img, angle, scale)
    surf.blit(img, img.get_rect(center=center))


def draw_cost(surf, pos, cost, size=15):
    """Horizontal row of cost gems; returns the width."""
    x, y = pos
    items = [("el", cost.element)] * cost.n + [("un", None)] * cost.unaligned + [("en", None)] * cost.energy
    for kind, el in items:
        gem(surf, (x + size / 2, y + size / 2), size / 2 - 0.5, el, kind)
        x += size + 2
    return x - pos[0]


def draw_cost_col(surf, pos, cost, r):
    """Vertical column of cost gems at the left edge of a card."""
    x, y = pos
    for kind, el in [("el", cost.element)] * cost.n + [("un", None)] * cost.unaligned + [("en", None)] * cost.energy:
        gem(surf, (x, y), r, el, kind)
        y += r * 2 + 3


# ------------------------------------------------------------------ portraits
HAIR = [(60, 40, 30), (230, 210, 140), (40, 50, 90), (200, 80, 60), (235, 235, 240), (120, 60, 140), (70, 110, 80), (30, 30, 40)]
SKIN = [(245, 218, 190), (235, 200, 165), (250, 225, 205)]


def portrait(surf, rect, name, element, weapon):
    key = ("portrait", name, rect.size)
    if key not in _cache:
        w, h = rect.size
        s = pygame.Surface((w, h), pygame.SRCALPHA)
        asset_path = _find_asset("characters", name)
        loaded = False
        if asset_path:
            try:
                raw = pygame.image.load(asset_path).convert_alpha()
                s.blit(_cover_image(raw, (w, h), (0.5, 0.38)), (0, 0))
                vig = pygame.Surface((w, h), pygame.SRCALPHA)
                for i in range(8):
                    pygame.draw.rect(vig, (0, 0, 0, 8), pygame.Rect(0, 0, w, h).inflate(-2 * i, -2 * i), 2)
                s.blit(vig, (0, 0))
                loaded = True
            except Exception:
                loaded = False
        if not loaded:
            col = ELEM_COL[element]
            for y in range(h):
                pygame.draw.line(s, mix(mix(col, (255, 255, 255), 0.25), shade(col, 0.3), y / h), (0, y), (w, y))
            big = pygame.Surface((w, h), pygame.SRCALPHA)
            draw_symbol(big, element, (w * 0.5, h * 0.42), h * 0.46, color=mix(col, (255, 255, 255), 0.5))
            big.fill((255, 255, 255, 46), special_flags=pygame.BLEND_RGBA_MULT)
            s.blit(big, (0, 0))
            add_glow(s, (w * 0.5, h * 0.42), tuple(int(v * 0.5) for v in col), w * 0.6)
            seed = zlib.crc32(name.encode())
            hair, skin = HAIR[seed % len(HAIR)], SKIN[(seed >> 3) % len(SKIN)]
            cx, hy = w / 2, h * 0.40
            body = shade(col, 0.55)
            pygame.draw.polygon(s, body, [(cx - w * 0.30, h), (cx - w * 0.22, h * 0.62), (cx + w * 0.22, h * 0.62), (cx + w * 0.30, h)])
            pygame.draw.polygon(s, mix(body, (255, 255, 255), 0.35), [(cx - 6, h * 0.62), (cx + 6, h * 0.62), (cx, h * 0.78)])
            pygame.draw.polygon(s, GOLD, [(cx - w * 0.22, h * 0.62), (cx + w * 0.22, h * 0.62), (cx + w * 0.2, h * 0.66), (cx - w * 0.2, h * 0.66)])
            pygame.draw.circle(s, hair, (cx, hy - 2), w * 0.17)
            if seed & 4:
                pygame.draw.polygon(s, hair, [(cx - w * 0.17, hy), (cx + w * 0.17, hy), (cx + w * 0.2, hy + h * 0.26), (cx - w * 0.2, hy + h * 0.26)])
            pygame.draw.circle(s, skin, (cx, hy + 2), w * 0.135)
            pygame.draw.arc(s, hair, pygame.Rect(cx - w * 0.15, hy - w * 0.17, w * 0.30, w * 0.26), 0.2, 2.95, int(w * 0.07))
            for dx in (-0.055, 0.055):
                pygame.draw.circle(s, mix(col, (30, 30, 50), 0.4), (cx + w * dx, hy + 4), max(2, w * 0.018))
            wx, wy = cx + w * 0.30, h * 0.66
            wc = (232, 234, 242)
            if weapon == "Sword":
                pygame.draw.line(s, wc, (wx, wy + 22), (wx + 8, wy - 40), 4); pygame.draw.line(s, GOLD, (wx - 6, wy + 14), (wx + 12, wy + 18), 3)
            elif weapon == "Claymore":
                pygame.draw.polygon(s, wc, [(wx - 7, wy + 22), (wx + 9, wy + 22), (wx + 14, wy - 42), (wx + 1, wy - 48)]); pygame.draw.line(s, GOLD, (wx - 8, wy + 20), (wx + 12, wy + 20), 4)
            elif weapon == "Bow":
                pygame.draw.arc(s, (214, 174, 112), pygame.Rect(wx - 6, wy - 42, 30, 80), -1.4, 1.4, 4); pygame.draw.line(s, wc, (wx + 18, wy - 38), (wx + 18, wy + 34), 1)
            elif weapon == "Polearm":
                pygame.draw.line(s, (204, 174, 124), (wx, wy + 40), (wx + 6, wy - 40), 3); pygame.draw.polygon(s, wc, [(wx + 6, wy - 58), (wx + 1, wy - 38), (wx + 11, wy - 38)])
            else:
                pygame.draw.rect(s, (204, 154, 94), pygame.Rect(wx - 8, wy - 10, 24, 30), border_radius=3)
                draw_symbol(s, element, (wx + 4, wy + 5), 6)
            vig = pygame.Surface((w, h), pygame.SRCALPHA)           # soft edge darkening
            for i in range(10):
                pygame.draw.rect(vig, (0, 0, 0, 9), pygame.Rect(0, 0, w, h).inflate(-2 * i, -2 * i), 2)
            s.blit(vig, (0, 0))
        _cache[key] = s
    surf.blit(_cache[key], rect)


def char_base(name, element, weapon, size):
    """Full-art character card with a dark information footer and element crest."""
    key = ("charbase", name, size)
    if key not in _cache:
        w, h = size
        s = pygame.Surface(size, pygame.SRCALPHA)
        win = pygame.Rect(4, 4, w - 8, h - 8)
        pr = pygame.Surface(win.size, pygame.SRCALPHA)
        portrait(pr, pr.get_rect(), name, element, weapon)
        s.blit(rounded(pr, 10), win)
        footer = pygame.Surface((w - 8, 58), pygame.SRCALPHA)
        for y in range(footer.get_height()):
            a = int(205 * y / footer.get_height())
            pygame.draw.line(footer, (13, 24, 35, a), (0, y), (footer.get_width(), y))
        s.blit(footer, (4, h - 62))
        plate = pygame.Rect(9, h - 53, w - 18, 24)
        pygame.draw.rect(s, (23, 37, 49, 205), plate, border_radius=6)
        pygame.draw.line(s, (230, 202, 145), (plate.x + 7, plate.y), (plate.right - 7, plate.y), 1)
        size_f = 16
        while size_f > 10 and font(size_f, True).size(name)[0] > plate.w - 12:
            size_f -= 1
        text(s, name, plate.center, size_f, TEXT, True, "center")
        pygame.draw.rect(s, (42, 29, 24), pygame.Rect(0, 0, w, h), 2, border_radius=12)
        pygame.draw.rect(s, (242, 218, 166), pygame.Rect(2, 2, w - 4, h - 4), 1, border_radius=11)
        pygame.draw.rect(s, (159, 121, 71), pygame.Rect(5, 5, w - 10, h - 10), 1, border_radius=9)
        # Small raised corner studs and the side inlays echo the physical character cards.
        for px, py in ((8, 8), (w - 9, 8), (8, h - 9), (w - 9, h - 9)):
            pygame.draw.polygon(s, (246, 223, 175), ((px, py - 4), (px + 4, py), (px, py + 4), (px - 4, py)))
        for py in (h * 0.34, h * 0.49, h * 0.64):
            pygame.draw.polygon(s, (208, 182, 137), ((w - 5, py - 5), (w, py), (w - 5, py + 5), (w - 10, py)))
        cx, cy = w - 20, 20
        pygame.draw.circle(s, (27, 37, 47), (cx, cy), 15)
        pygame.draw.circle(s, ELEM_COL[element], (cx, cy), 12, 2)
        draw_symbol(s, element, (cx, cy), 8)
        _cache[key] = s
    return _cache[key]


# icon element for each status (so a status is recognisable at a glance)
STATUS_ELEM = {
    "Frozen": "Cryo", "Petrified": "Geo", "Pyro Infusion": "Pyro", "Thundering Penance": "Electro",
    "Ice Lotus": "Cryo", "Ice Shield": "Cryo", "Rain Sword": "Hydro", "Rainbow Bladework": "Hydro",
    "Reflection": "Hydro", "Jade Shield": "Geo", "Crystallize Shield": "Geo", "Inspiration Field": "Pyro",
    "Fervent Flames": "Pyro", "Stellar Predator": "Electro", "Lotus Shield": "Geo", "Changing Shifts": "Anemo",
    "Leave It to Me!": "Anemo",
}
SHIELD_LIKE = {"Ice Lotus", "Ice Shield", "Rain Sword", "Reflection", "Jade Shield", "Crystallize Shield", "Lotus Shield"}


def badge(surf, c, r, el, number=None, kind="status", ring=None):
    """Small round icon: a status, an aura, or equipment. Number = usages / shield value."""
    col = ELEM_COL.get(el, (236, 196, 98))
    pygame.draw.circle(surf, (24, 16, 8), c, r + 2)
    pygame.draw.circle(surf, shade(col, 0.5), c, r)
    pygame.draw.circle(surf, mix(col, (255, 255, 255), 0.25), (c[0] - r * 0.15, c[1] - r * 0.2), r * 0.72)
    pygame.draw.circle(surf, ring or (GOLD if kind != "aura" else col), c, r + 1, 2)
    if el:
        draw_symbol(surf, el, c, r * 0.58, (255, 255, 255))
    else:
        pygame.draw.polygon(surf, (255, 250, 230), _pts(c, r * 0.6, [(0, -1), (0.3, -0.3), (1, 0), (0.3, 0.3), (0, 1), (-0.3, 0.3), (-1, 0), (-0.3, -0.3)]))
    if number is not None:
        bx, by = c[0] + r * 0.75, c[1] + r * 0.75
        pygame.draw.circle(surf, (24, 16, 8), (bx, by), r * 0.62 + 1)
        pygame.draw.circle(surf, GOLD_D, (bx, by), r * 0.62)
        text(surf, int(number), (bx, by), max(9, int(r * 0.9)), (255, 244, 220), True, "center", shadow=False)


def equip_icon(surf, rect, slot, on):
    rect = pygame.Rect(rect)
    col = KIND_COL[slot]
    pygame.draw.rect(surf, (24, 16, 8), rect.inflate(2, 2), border_radius=6)
    pygame.draw.rect(surf, col if on else (150, 130, 96), rect, border_radius=5)
    pygame.draw.rect(surf, GOLD if on else (110, 92, 66), rect, 2, border_radius=5)
    c = rect.center
    r = rect.w * 0.3
    ink = (255, 250, 235) if on else (118, 98, 70)
    if slot == "weapon":
        pygame.draw.line(surf, ink, (c[0] - r, c[1] + r), (c[0] + r, c[1] - r), 3)
        pygame.draw.line(surf, ink, (c[0] - r, c[1]), (c[0], c[1] + r), 2)
    elif slot == "artifact":
        pygame.draw.circle(surf, ink, c, r, 3)
        pygame.draw.circle(surf, ink, (c[0], c[1] - r), 2)
    else:
        pygame.draw.polygon(surf, ink, _pts(c, r * 1.2, [(0, -1), (0.3, -0.3), (1, 0), (0.3, 0.3), (0, 1), (-0.3, 0.3), (-1, 0), (-0.3, -0.3)]))


# ------------------------------------------------------------------ action cards
KIND_COL = {"event": (74, 150, 160), "support": (200, 150, 70), "weapon": (150, 112, 204),
            "artifact": (206, 112, 124), "talent": (230, 134, 72)}


def kind_icon(surf, kind, c, r, el=None):
    col = (252, 248, 236)
    add_glow(surf, c, (150, 120, 60), r * 1.8, 0.6)
    if kind == "weapon":
        pygame.draw.line(surf, col, (c[0] - r * 0.7, c[1] + r * 0.7), (c[0] + r * 0.6, c[1] - r * 0.8), 5)
        pygame.draw.line(surf, GOLD, (c[0] - r * 0.7, c[1] + r * 0.1), (c[0] - r * 0.1, c[1] + r * 0.7), 4)
    elif kind == "artifact":
        pygame.draw.circle(surf, GOLD, c, r * 0.7, 5)
        pygame.draw.circle(surf, col, (c[0], c[1] - r * 0.7), r * 0.25)
    elif kind == "support":
        pygame.draw.polygon(surf, col, [(c[0] - r, c[1]), (c[0], c[1] - r), (c[0] + r, c[1])])
        pygame.draw.rect(surf, col, pygame.Rect(c[0] - r * 0.7, c[1], r * 1.4, r * 0.9))
    elif kind == "talent":
        pygame.draw.polygon(surf, GOLD_L, _pts(c, r, [(0, -1), (0.3, -0.3), (1, 0), (0.3, 0.3), (0, 1), (-0.3, 0.3), (-1, 0), (-0.3, -0.3)]))
    elif el:
        draw_symbol(surf, el, c, r * 0.85)
    else:
        pygame.draw.polygon(surf, col, _pts(c, r, [(0, -1), (0.3, -0.3), (1, -0.2), (0.4, 0.25), (0.6, 1), (0, 0.55), (-0.6, 1), (-0.4, 0.25), (-1, -0.2), (-0.3, -0.3)]))


def _card_base(cd, size):
    """Card face. Small sizes show cost, art, name and type only; the large size adds the effect text."""
    key = ("cardbase", cd.name, size)
    if key in _cache:
        return _cache[key]
    w, h = size
    large = w >= 200
    s = pygame.Surface(size, pygame.SRCALPHA)
    s.blit(rounded(parchment(size), 12 if large else 10), (0, 0))
    col = KIND_COL[cd.kind]
    r = 15 if large else (7 if w < 105 else 8)
    art_rect = pygame.Rect(2 * r + 12, 10, w - 2 * r - 22, int(h * (0.36 if large else 0.44)))
    pic = pygame.Surface(art_rect.size, pygame.SRCALPHA)
    card_asset = _find_asset("cards", cd.name)
    card_loaded = False
    if card_asset:
        try:
            raw = pygame.image.load(card_asset).convert_alpha()
            rw, rh = raw.get_size()
            scale = max(art_rect.w / rw, art_rect.h / rh)
            nw, nh = max(1, int(rw * scale)), max(1, int(rh * scale))
            scaled = pygame.transform.smoothscale(raw, (nw, nh))
            pic.blit(scaled, ((art_rect.w - nw) // 2, (art_rect.h - nh) // 2))
            card_loaded = True
        except Exception:
            card_loaded = False
    if not card_loaded:
        for y in range(art_rect.h):
            pygame.draw.line(pic, mix(mix(col, (255, 255, 255), 0.35), shade(col, 0.45), y / art_rect.h), (0, y), (art_rect.w, y))
        kind_icon(pic, cd.kind, (art_rect.w / 2, art_rect.h / 2), min(art_rect.w, art_rect.h) * 0.32, cd.resonance)
    s.blit(rounded(pic, 6), art_rect)
    pygame.draw.rect(s, GOLD_D, art_rect, 2, border_radius=6)
    plate = pygame.Rect(8, art_rect.bottom + 8, w - 16, 38 if large else 24)
    plaque(s, plate, 8)
    title = cd.name.replace("Elemental Resonance: ", "") if not large else cd.name
    fs = 21 if large else (13 if w >= 105 else 11)
    while fs > 8 and font(fs, True).size(title)[0] > plate.w - 12:
        fs -= 1
    text(s, title, plate.center, fs, TEXT, True, "center")
    label = ("RESONANCE" if cd.resonance else cd.kind.upper())
    if large:
        area = pygame.Rect(16, plate.bottom + 10, w - 32, h - plate.bottom - 52)
        body = getattr(cd, "text", "") or " "
        for fsz in range(17, 10, -1):
            lines = wrap(body, fsz, area.w)
            if len(lines) * (fsz + 4) <= area.h:
                break
        y0 = area.y + max(0, (area.h - len(lines) * (fsz + 4)) // 2)
        for i, ln in enumerate(lines):
            text(s, ln, (w / 2, y0 + i * (fsz + 4)), fsz, INK, False, "midtop", shadow=False)
    text(s, label, (w / 2, h - 10), 12 if large else 9, shade(col, 0.55), True, "midbottom", shadow=False)
    draw_cost_col(s, (r + 7, r + 12), cd.cost, r)
    gold_frame(s, pygame.Rect(0, 0, w, h), 12 if large else 10, 3)
    _cache[key] = s
    return s


def card_large(cd):
    return _card_base(cd, (268, 392))


def action_card(surf, rect, cd, glow=False, dim=False):
    rect = pygame.Rect(rect)
    img = _card_base(cd, rect.size)
    if dim:
        key = ("dim", cd.name, rect.size)
        if key not in _cache:
            d = img.copy()
            d.fill((150, 146, 140, 255), special_flags=pygame.BLEND_RGBA_MULT)
            _cache[key] = d
        img = _cache[key]
    if glow:
        add_glow(surf, rect.center, (255, 210, 110), max(rect.w, rect.h) * 0.75, 0.55)
    surf.blit(img, rect)


def card_image(cd, size):
    """Unrotated card surface (for flying / tilted cards)."""
    return _card_base(cd, size)


def card_back(surf, rect):
    rect = pygame.Rect(rect)
    surf.blit(back_image(rect.size), rect)


def back_image(size):
    key = ("back", size)
    if key not in _cache:
        w, h = size
        s = pygame.Surface(size, pygame.SRCALPHA)
        back_asset = _find_asset("", "card_back")
        back_loaded = False
        if back_asset:
            try:
                raw = pygame.image.load(back_asset).convert_alpha()
                s.blit(rounded(_cover_image(raw, size), 8), (0, 0))
                gold_frame(s, pygame.Rect(0, 0, w, h), 8, 2, corners=False)
                back_loaded = True
            except Exception:
                back_loaded = False
        if not back_loaded:
            base = pygame.Surface(size)
            for y in range(h):
                pygame.draw.line(base, mix((40, 64, 92), (22, 36, 58), y / h), (0, y), (w, y))
            s.blit(rounded(base, 8), (0, 0))
            c = (w / 2, h / 2)
            pygame.draw.circle(s, GOLD_D, c, w * 0.34, 2)
            pygame.draw.polygon(s, (90, 130, 200), _pts(c, w * 0.28, [(0, -1), (0.8, 0), (0, 1), (-0.8, 0)]))
            pygame.draw.polygon(s, GOLD, _pts(c, w * 0.16, [(0, -1), (0.8, 0), (0, 1), (-0.8, 0)]))
            gold_frame(s, pygame.Rect(0, 0, w, h), 8, 2, corners=False)
        _cache[key] = s
    return _cache[key]

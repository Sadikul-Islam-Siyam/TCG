"""Presentation helpers: announcement ribbons, phase banners, reaction pills, floating numbers,
flying cards and a small timeline. (No particle effects: clarity first.)"""
import math

import pygame

from . import art
from .theme import ELEM_COL, GOLD, GOLD_L, GOLD_D, TEXT, INK, text, mix, font, shade, ease_out

HEAL = (130, 235, 150)


class FX:
    def __init__(self):
        self.clock = 0.0                    # presentation time (scaled by the game-speed setting)
        self.floats, self.toasts, self.pills = [], [], []
        self.flights, self.banners, self.ribbons, self.timeline = [], [], [], []
        self.flash = 0.0
        self.shake = 0.0

    # ------------------------------------------------------------ scheduling
    def after(self, delay, fn):
        if delay <= 0:
            fn()
        else:
            self.timeline.append([delay, fn])

    # ------------------------------------------------------------ things to show
    def burst(self, *a, **k):               # kept so older call sites do nothing
        pass

    def float(self, s, x, y, color, size=28):
        self.floats.append([str(s), x, y, 0.0, 1.5, color, size])

    def toast(self, s, color=(255, 255, 255)):
        self.toasts.append([s, 2.2, 2.2, color])
        self.toasts = self.toasts[-3:]

    def banner(self, title, color=GOLD, sub=None, dur=1.6):
        self.banners.append([title, 0.0, dur, color, sub])

    def ribbon(self, title, sub=None, color=GOLD, dur=1.6, mine=True):
        self.ribbons.append([title, sub, color, 0.0, dur, mine])

    def pill(self, title, sub, els, x, y, dur=2.2):
        self.pills.append([title, sub, els, x, y, 0.0, dur])

    def fly(self, img, p0, p1, dur=0.45, hold=0.0, fade=0.35, s0=1.0, s1=1.0, on_land=None, spin=0.0):
        self.flights.append({"img": img, "p0": p0, "p1": p1, "t": 0.0, "dur": dur, "hold": hold, "fade": fade,
                             "s0": s0, "s1": s1, "land": on_land, "spin": spin, "landed": False})

    def busy(self):
        return bool(self.timeline or self.flights or self.banners or self.ribbons)

    # ------------------------------------------------------------ update
    def update(self, dt):
        self.clock += dt
        for f in self.floats:
            f[2] -= 26 * dt; f[3] += dt
        self.floats = [f for f in self.floats if f[3] < f[4]]
        for t in self.toasts:
            t[1] -= dt
        self.toasts = [t for t in self.toasts if t[1] > 0]
        for b in self.banners:
            b[1] += dt
        self.banners = [b for b in self.banners if b[1] < b[2]]
        for r in self.ribbons:
            r[3] += dt
        self.ribbons = [r for r in self.ribbons if r[3] < r[4]]
        for p in self.pills:
            p[5] += dt
        self.pills = [p for p in self.pills if p[5] < p[6]]
        for fl in self.flights:
            fl["t"] += dt
            if not fl["landed"] and fl["t"] >= fl["dur"]:
                fl["landed"] = True
                if fl["land"]:
                    fl["land"]()
        self.flights = [f for f in self.flights if f["t"] < f["dur"] + f["hold"] + f["fade"]]
        for tl in self.timeline:
            tl[0] -= dt
        due = [t for t in self.timeline if t[0] <= 0]
        self.timeline = [t for t in self.timeline if t[0] > 0]
        for _, fn in due:
            fn()
        self.flash = max(0.0, self.flash - 2.5 * dt)

    # ------------------------------------------------------------ draw
    def draw(self, surf):
        for fl in self.flights:
            t = fl["t"]
            k = ease_out(t / fl["dur"])
            x = fl["p0"][0] + (fl["p1"][0] - fl["p0"][0]) * k
            y = fl["p0"][1] + (fl["p1"][1] - fl["p0"][1]) * k - (math.sin(math.pi * k) * 50 if t < fl["dur"] else 0)
            sc = fl["s0"] + (fl["s1"] - fl["s0"]) * k
            alpha = 255
            if t > fl["dur"] + fl["hold"]:
                f = (t - fl["dur"] - fl["hold"]) / fl["fade"]
                alpha = int(255 * max(0.0, 1 - f))
            img = pygame.transform.rotozoom(fl["img"], fl["spin"] * (1 - k), sc)
            img.set_alpha(alpha)
            shadow = pygame.Surface(img.get_size(), pygame.SRCALPHA)
            pygame.draw.rect(shadow, (0, 0, 0, int(90 * alpha / 255)), shadow.get_rect().inflate(-10, -10), border_radius=16)
            surf.blit(shadow, shadow.get_rect(center=(x + 6, y + 10)))
            surf.blit(img, img.get_rect(center=(x, y)))
        for s, x, y, t, mx, col, size in self.floats:
            pop = 1 + 0.4 * max(0.0, 1 - t / 0.15)
            alpha = 1.0 if t < mx * 0.65 else max(0.0, (mx - t) / (mx * 0.35))
            img = font(int(size * pop), True).render(s, True, col)
            sh = font(int(size * pop), True).render(s, True, (10, 6, 2))
            for im in (sh, img):
                im.set_alpha(int(255 * alpha))
            r = img.get_rect(center=(x, y))
            surf.blit(sh, r.move(2, 3))
            surf.blit(img, r)
        for title, sub, els, x, y, t, dur in self.pills:
            alpha = min(1.0, t / 0.2) * (1.0 if t < dur - 0.4 else max(0.0, (dur - t) / 0.4))
            w = max(150, font(19, True).size(title.upper())[0] + 70, font(13).size(sub)[0] + 30)
            box = pygame.Surface((w, 52), pygame.SRCALPHA)
            pygame.draw.rect(box, (26, 20, 14, 240), box.get_rect(), border_radius=14)
            pygame.draw.rect(box, GOLD, box.get_rect(), 2, border_radius=14)
            for k, el in enumerate(els):
                art.gem(box, (22 + k * 22, 26), 9, el)
            text(box, title.upper(), (box.get_width() / 2 + 8 * len(els), 16), 19, GOLD_L, True, "center", shadow=False)
            text(box, sub, (box.get_width() / 2 + 8 * len(els), 38), 13, TEXT, False, "center", shadow=False)
            box.set_alpha(int(255 * alpha))
            surf.blit(box, box.get_rect(center=(x, y - 14 * ease_out(t / 0.4))))
        for b in self.banners:
            title, t, mx, col, sub = b
            k = t / mx
            slide = ease_out(min(1.0, t / 0.35))
            fade = 1.0 if k < 0.72 else max(0.0, (1 - k) / 0.28)
            band = pygame.Surface((1280, 100), pygame.SRCALPHA)
            band.fill((10, 10, 8, int(205 * fade)))
            for yy in (2, 97):
                pygame.draw.line(band, (*GOLD, int(255 * fade)), (0, yy), (1280, yy), 2)
            surf.blit(band, (0, 310))
            x = 640 + (1 - slide) * 600
            img = font(50, True).render(title, True, mix((20, 14, 8), col, fade))
            img.set_alpha(int(255 * fade))
            surf.blit(img, img.get_rect(center=(x, 346 if sub else 360)))
            if sub:
                img2 = font(20).render(sub, True, mix((20, 14, 8), TEXT, fade))
                img2.set_alpha(int(255 * fade))
                surf.blit(img2, img2.get_rect(center=(x, 388)))
        for title, sub, col, t, dur, mine in self.ribbons:
            slide = ease_out(min(1.0, t / 0.25))
            fade = 1.0 if t < dur - 0.3 else max(0.0, (dur - t) / 0.3)
            w = max(380, font(26, True).size(title)[0] + 90)
            box = pygame.Surface((w, 60), pygame.SRCALPHA)
            art.plaque(box, box.get_rect(), 14, (40, 34, 28))
            pygame.draw.rect(box, shade(col, 0.9), pygame.Rect(8, 8, 8, 44), border_radius=4)
            text(box, title, (w / 2 + 6, 21 if sub else 30), 25, TEXT, True, "center", shadow=False)
            if sub:
                text(box, sub, (w / 2 + 6, 44), 14, mix(GOLD_L, col, 0.35), False, "center", shadow=False)
            box.set_alpha(int(255 * fade))
            surf.blit(box, box.get_rect(center=(640, 256 + (1 - slide) * (-30 if not mine else 30))))

    def draw_toasts(self, surf, cx, y):
        for s, life, mx, col in self.toasts:
            img = font(15, True).render(s, True, col)
            box = pygame.Surface((img.get_width() + 28, 30), pygame.SRCALPHA)
            pygame.draw.rect(box, (24, 18, 12, 230), box.get_rect(), border_radius=15)
            pygame.draw.rect(box, (*GOLD, 255), box.get_rect(), 1, border_radius=15)
            box.blit(img, (14, 5))
            box.set_alpha(int(255 * min(1.0, life / 0.4)))
            surf.blit(box, box.get_rect(midtop=(min(max(cx, box.get_width() // 2 + 8), 1270 - box.get_width() // 2), y)))
            y += 34

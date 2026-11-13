"""The match screen: renders a GameState, turns mouse input into Actions and presents every event
step by step (announcement, action, result) so both players' moves can be followed."""
import math
import random
import threading
from collections import defaultdict
from dataclasses import replace

import pygame

from engine import dice as D
from engine import rules
from engine.core import Action, Cost, IllegalAction, DICE_FACES, OMNI
from engine.registry import CARD_DEFS, SUMMON_DEFS, STATUS_DEFS
from . import art
from .fx import FX, HEAL
from .theme import (W, H, ELEM_COL, PANEL, TEXT, DIM, GOLD, GOLD_L, GOLD_D, INK, RED, GREEN, TEAL,
                    font, text, wrap, mix, shade, ease_out)

CW, CH = 120, 190                 # illustrated character card
CARD_W, CARD_H = 118, 168         # hand card
FOE_Y, OWN_Y = 100, 400
CHAR_X0, CHAR_STEP = 440, 140
HAND_CX, HAND_Y = 640, 720
MAT = pygame.Rect(0, 0, W, H)
TRAY = pygame.Rect(1206, 96, 68, 420)
INTRO_DUR = 4.4

REACT = {
    "Vaporize": (("Hydro", "Pyro"), "+1 damage"),
    "Melt": (("Cryo", "Pyro"), "+2 damage"),
    "Overloaded": (("Pyro", "Electro"), "+2 damage, forced switch"),
    "Superconduct": (("Cryo", "Electro"), "+1 damage, 1 Piercing to others"),
    "Electro-Charged": (("Hydro", "Electro"), "+1 damage, 1 Piercing to others"),
    "Frozen": (("Cryo", "Hydro"), "+1 damage, target Frozen"),
    "Swirl": (("Anemo",), "1 damage to the other characters"),
    "Crystallize": (("Geo",), "+1 damage, shield gained"),
}
AURA_TEXT = "A different element hitting it triggers an elemental reaction."


class AIJob:
    """Runs an AI decision in a worker thread so the window stays responsive while it thinks."""

    def __init__(self, ctrl, state):
        self.result = self.error = None
        self.done = False
        self.thread = threading.Thread(target=self._run, args=(ctrl, state), daemon=True)
        self.thread.start()

    def _run(self, ctrl, state):
        try:
            self.result = ctrl.choose(state)
        except Exception as e:          # never let an AI bug freeze the game
            self.error = e
        self.done = True


class MatchScene:
    def __init__(self, screen, decks, controllers, seed=None):
        self.screen, self.decks, self.controllers, self.seed = screen, decks, controllers, seed
        self.canvas = pygame.Surface((W, H))
        self.fx = FX()
        self.speed = 1.0
        self.reset()

    # ------------------------------------------------------------------ setup
    def reset(self):
        (c0, d0), (c1, d1) = self.decks
        self.s = rules.new_game(c0, d0, c1, d1, self.seed)
        self.human = [c == "human" for c in self.controllers]
        self.hotseat = all(self.human)
        self.view = 0 if self.human[0] or not self.human[1] else 1
        self.cover = None
        self.sprites, self.hit_t, self.lunge, self.spin = [], {}, {}, [{}, {}]
        self.vis_hp, self.log, self.icons = {}, [], []
        self.drag = self.hover = None
        self.sel_dice, self.sel_hand, self.hl = set(), set(), set()
        self.pay_pending = None
        self.buttons, self.t_ai, self.reveal, self.clock = [], 0.6, False, 0.0
        self.acts, self.ai_job, self.fly_hint, self.last_actor = [], None, None, None
        self.mouse_v, self.last_mouse = 0.0, (0, 0)
        self.intro_t, self.busy_until = 0.0, 0.0
        first = self.s.first_player
        self.logline(f"Coin toss: {self.who(first)} go{'es' if self.who(first) not in ('You',) else ''} first.", GOLD_L)
        self.changed()

    def who(self, p):
        if self.hotseat or not any(self.human):
            return f"Player {p + 1}"
        return "You" if p == self.view else "Opponent"

    def possessive(self, p):
        w = self.who(p)
        return "Your" if w == "You" else (w + "'s")

    def logline(self, s, col=TEXT):
        self.log.append((s, col))
        self.log = self.log[-60:]

    def me(self):
        return self.s.players[self.view]

    def actor(self):
        return rules.actor(self.s)

    def locked(self):
        return self.intro_t < INTRO_DUR or self.fx.clock < self.busy_until

    def my_turn(self):
        a = self.actor()
        return a is not None and a == self.view and self.human[a] and self.cover is None

    def can_act(self):
        return self.my_turn() and not self.locked()

    def changed(self):
        a = self.actor()
        self.acts = rules.legal_actions(self.s) if a is not None else []
        self.sel_dice, self.sel_hand = set(), set()
        self.pay_pending = None
        if self.hotseat and a is not None and a != self.view and self.cover is None:
            self.cover = a
        self.last_actor = a
        self.sync_hand()

    def mulligan_stage(self):
        return self.s.phase == "setup" and not self.me().mull_done and self.my_turn()

    def hand_target(self, i, n):
        t = i - (n - 1) / 2
        if self.mulligan_stage():
            return HAND_CX + t * 152, 350, 0.0
        spacing = min(100.0, 640.0 / max(n, 1))
        return HAND_CX + t * spacing, HAND_Y + (abs(t) ** 1.6) * 4.5, -t * 3.2

    def sync_hand(self):
        hand, old, new = self.me().hand, list(self.sprites), []
        for i, name in enumerate(hand):
            sp = next((o for o in old if o["name"] == name), None)
            if sp:
                old.remove(sp)
            else:
                tx, ty, ta = self.hand_target(i, len(hand))
                sp = {"name": name, "x": 1180, "y": 700, "a": 35.0, "s": 0.55,
                      "d0": math.hypot(tx - 1180, ty - 700) + 1}
            new.append(sp)
        self.sprites = new

    # ------------------------------------------------------------------ geometry
    def side(self, p):
        return 0 if p == self.view else 1

    def char_rect(self, p, i):
        slot = i if self.side(p) == 0 else 2 - i               # the opponent's row is rotated 180 degrees
        return pygame.Rect(CHAR_X0 + CHAR_STEP * slot, OWN_Y if self.side(p) == 0 else FOE_Y, CW, CH)

    def char_center(self, p, i):
        return self.char_rect(p, i).center

    def zone_rect(self, p, kind, k):
        mine = self.side(p) == 0
        left = (kind == "support") == mine                      # own supports left, summons right; foe mirrored
        x0 = 208 if left else 934
        y0 = OWN_Y if mine else FOE_Y
        return pygame.Rect(x0 + (k % 2) * 78, y0 + (k // 2) * 100, 70, 96)

    def team_rects(self, p):
        n = len(self.s.players[p].combat)
        y = OWN_Y - 14 if self.side(p) == 0 else FOE_Y + CH + 12
        x0 = 640 - (n * 28) / 2
        return [pygame.Rect(x0 + k * 28, y - 11, 22, 22) for k in range(n)]

    def hand_rect(self, i):
        sp = self.sprites[i]
        w, h = CARD_W * sp["s"], CARD_H * sp["s"]
        return pygame.Rect(sp["x"] - w / 2, sp["y"] - h / 2, w, h)

    def die_pos(self, i):
        if self.pay_pending:
            return (900 + (i % 2) * 218, 260 + (i // 2) * 74)
        return 1240, 144 + i * 44

    def dice_rect(self):
        count = len(self.me().dice)
        return pygame.Rect(TRAY.x, TRAY.y, TRAY.w, min(TRAY.h, max(112, 58 + count * 44)))

    def skill_rect(self, i):
        return pygame.Rect(1030 + i * 78, 548, 68, 92)

    def end_btn(self):
        return pygame.Rect(32, 332, 82, 82)

    # ------------------------------------------------------------------ actions
    def begin_payment(self, action, cost, title, detail="", source=None):
        """Pause a payable action so the player can choose its exact dice."""
        count = cost.n + cost.unaligned
        if count == 0:
            if source is not None and action.type == "card":
                self.fly_hint = (source, None)
            return self.do(action)
        self.sel_dice.clear()
        self.pay_pending = {"action": action, "cost": cost, "title": title,
                            "detail": detail, "source": source, "tune": False}
        self.fx.toast("Select the dice to spend, then confirm", GOLD_L)
        return True

    def begin_tune(self, card_index, source=None):
        eligible = self.tunable_dice()
        if not eligible:
            self.fx.toast("No dice to convert (Omni and matching dice stay as they are)", RED)
            return False
        self.sel_dice.clear()
        self.pay_pending = {"action": None, "cost": None, "title": "Elemental Tuning",
                            "detail": f"Choose one die to convert with {self.me().hand[card_index]}.",
                            "source": source, "tune": True, "card_index": card_index}
        return True

    def do(self, a):
        try:
            rules.apply_action(self.s, a)
        except IllegalAction as e:
            self.fx.toast(f"Can't do that: {e}", RED)
            return False
        if a.type == "reroll":
            self.spin[a.player] = {i: 0.7 for i in a.ids}
        self.on_events(self.s.events)
        self.changed()
        return True

    # ---- event playback: every event is shown in order with time to read it
    def on_events(self, events):
        fx, s = self.fx, self.s
        net = defaultdict(int)
        for kind, e in events:
            if kind == "damage":
                net[(e["player"], e["char"])] += e["amount"]
            elif kind == "heal":
                net[(e["player"], e["char"])] -= e["amount"]
        for (p, i), tot in net.items():            # keep the old HP on screen until the hit lands
            c = s.players[p].characters[i]
            self.vis_hp[(p, i)] = [max(0, min(c.defn.hp, c.hp + tot)), 1e9]
        t = 0.0
        for n, (kind, e) in enumerate(events):
            if kind == "skill":
                P = s.players[e["player"]]
                ch = P.characters[e["char"]]
                col = ELEM_COL[ch.defn.element]
                burst = e["kind"] == "burst"
                who = self.who(e["player"])
                fx.after(t, lambda ch=ch, e=e, col=col, who=who, burst=burst:
                         fx.ribbon(e["skill"], f"{who} · {ch.name}" + ("  ·  Elemental Burst" if burst else ""), col, 2.0 if burst else 1.7, e["player"] == self.view))
                self.logline(f"{who}: {ch.name} uses {e['skill']}", col)
                if burst:
                    fx.after(t, lambda: setattr(fx, "flash", 0.5))
                key = (e["player"], e["char"])
                fx.after(t + 0.5, lambda key=key: self.lunge.__setitem__(key, fx.clock))
                t += 1.35 if burst else 1.05
            elif kind == "damage":
                key = (e["player"], e["char"])
                self.vis_hp.get(key, [0, 0])[1] = fx.clock + t
                fx.after(t, lambda e=e, key=key: self._hit(e, key))
                ch = s.players[e["player"]].characters[e["char"]]
                self.logline(f"   {ch.name} takes {e['amount']} {e['dtype']} damage" + (f"  [{e['reaction']}]" if e["reaction"] else ""), ELEM_COL.get(e["dtype"], TEXT))
                t += 1.25 if e["reaction"] else 0.75
            elif kind == "heal":
                key = (e["player"], e["char"])
                cx, cy = self.char_center(*key)
                self.vis_hp.get(key, [0, 0])[1] = fx.clock + t
                fx.after(t, lambda e=e, cx=cx, cy=cy: fx.float(f"+{e['amount']}", cx, cy - 20, HEAL, 34))
                self.logline(f"   {s.players[e['player']].characters[e['char']].name} heals {e['amount']}", HEAL)
                t += 0.7
            elif kind == "summon":
                fx.after(t, lambda e=e: fx.toast(f"Summoned {e['name']}", TEAL))
                self.logline(f"   {e['name']} is summoned", TEAL)
                t += 0.6
            elif kind == "switch":
                ch = s.players[e["player"]].characters[e["char"]]
                who = self.who(e["player"])
                fx.after(t, lambda ch=ch, who=who, e=e: fx.ribbon(f"{ch.name} steps forward", f"{who} switched active character", ELEM_COL[ch.defn.element], 1.3, e["player"] == self.view))
                self.logline(f"{who}: switches to {ch.name}", DIM)
                t += 1.1
            elif kind == "defeat":
                ch = s.players[e["player"]].characters[e["char"]]
                fx.after(t, lambda ch=ch: fx.ribbon(f"{ch.name} was defeated", None, RED, 1.4))
                self.logline(f"   {ch.name} is defeated!", RED)
                t += 1.2
            elif kind == "card":
                cd = CARD_DEFS[e["name"]]
                mine = e["player"] == self.view
                fx.after(t, lambda e=e, cd=cd, mine=mine: self._card_flight(e, cd, mine))
                self.logline(f"{self.who(e['player'])}: plays {cd.name}", (236, 228, 205))
                t += 1.4 if mine else 2.0
            elif kind == "phase":
                if e["name"] == "action":
                    fx.after(t, lambda: fx.banner("Action Phase", GOLD, "Take turns. Declare End Round when you are done.", 1.6))
                    self.logline("— Action Phase —", GOLD)
                    t += 1.6
                elif e["name"] == "end":
                    fx.after(t, lambda: fx.banner("End Phase", GOLD, "Summons act, then both players draw 2 cards", 1.6))
                    self.logline("— End Phase —", GOLD)
                    t += 1.6
            elif kind == "round":
                fx.after(t, lambda e=e: fx.banner(f"Round {e['number']}", GOLD_L, "Roll Phase", 1.8))
                fx.after(t + 0.8, lambda: setattr(self, "spin", [{i: 0.7 + 0.04 * i for i in range(16)} for _ in range(2)]))
                self.logline(f"— Round {e['number']} · Roll Phase —", GOLD)
                t += 2.1
            elif kind == "end_round":
                who = self.who(e["player"])
                fx.after(t, lambda who=who, e=e: fx.ribbon(f"{who} ended the round", None, DIM, 1.3, e["player"] == self.view))
                self.logline(f"{who}: ends the round", DIM)
                t += 1.2
        self.busy_until = max(self.busy_until, fx.clock + t + 0.2)

    def _hit(self, e, key):
        fx = self.fx
        cx, cy = self.char_center(*key)
        fx.float(f"-{e['amount']}", cx, cy - 10, ELEM_COL.get(e["dtype"], TEXT), 40)
        if e["reaction"] in REACT:
            els, sub = REACT[e["reaction"]]
            fx.pill(e["reaction"], sub, els, cx, cy + 10, 2.6)
        self.hit_t[key] = fx.clock + 0.45

    def _card_flight(self, e, cd, mine):
        img = art.card_large(cd)
        if mine and self.fly_hint:
            p0 = self.fly_hint[0]
            self.fx.fly(img, p0, (W / 2, 300), 0.4, 0.8, 0.35, 0.4, 0.82)
        elif mine:
            self.fx.fly(img, (HAND_CX, HAND_Y), (W / 2, 300), 0.4, 0.8, 0.35, 0.4, 0.82)
        else:
            self.fx.fly(img, (W / 2, -140), (W / 2, 300), 0.5, 1.3, 0.4, 0.45, 0.85)
        self.fly_hint = None

    # ------------------------------------------------------------------ input
    def hit(self, pos):
        if self.drag:
            return None
        if self.pay_pending:
            for i in range(len(self.me().dice)):
                cx, cy = self.die_pos(i)
                if pygame.Rect(cx - 50, cy - 34, 100, 68).collidepoint(pos):
                    return ("die", i)
            return None
        hov = [i for i in range(len(self.sprites)) if self.hover and self.hover[0] == "hand" and self.hover[1] == i]
        order = hov + [i for i in reversed(range(len(self.sprites))) if i not in hov]
        for i in order:
            if self.hand_rect(i).collidepoint(pos):
                return ("hand", i)
        for rect, payload in self.icons:
            if rect.collidepoint(pos):
                return ("icon", payload)
        for i in range(3):
            if self.char_rect(self.view, i).collidepoint(pos):
                return ("char", self.view, i)
            if self.char_rect(1 - self.view, i).collidepoint(pos):
                return ("char", 1 - self.view, i)
        for i in range(len(self.me().dice)):
            cx, cy = self.die_pos(i)
            if abs(pos[0] - cx) < 27 and abs(pos[1] - cy) < 22:
                return ("die", i)
        if self.my_turn() and self.s.phase == "action":
            for i in range(3):
                if self.skill_rect(i).collidepoint(pos):
                    return ("skill", i)
        for p in (self.view, 1 - self.view):
            for k, u in enumerate(self.s.players[p].summons):
                if self.zone_rect(p, "summon", k).collidepoint(pos):
                    return ("zone", "summon", p, k)
            for k, u in enumerate(self.s.players[p].supports):
                if self.zone_rect(p, "support", k).collidepoint(pos):
                    return ("zone", "support", p, k)
        return None

    def handle(self, ev):
        if ev.type == pygame.KEYDOWN:
            if ev.key == pygame.K_h:
                self.reveal = not self.reveal
            elif ev.key == pygame.K_f:
                self.speed = 2.0 if self.speed == 1.0 else 1.0
                self.fx.toast(f"Game speed x{self.speed:g}", GOLD)
            elif ev.key == pygame.K_r and self.s.phase == "over":
                self.reset()
        elif ev.type == pygame.MOUSEMOTION:
            self.hover = self.hit(ev.pos)
        elif ev.type == pygame.MOUSEBUTTONDOWN and ev.button == 1:
            self.click(ev.pos)
        elif ev.type == pygame.MOUSEBUTTONDOWN and ev.button == 3:
            self.right_click(ev.pos)
        elif ev.type == pygame.MOUSEBUTTONUP and ev.button == 1 and self.drag:
            self.drop(ev.pos)

    def click(self, pos):
        if self.intro_t < INTRO_DUR:
            if self.intro_t > 1.2:
                self.intro_t = INTRO_DUR
            return
        if self.cover is not None:
            self.view, self.cover = self.cover, None
            self.sprites = []
            self.sync_hand()
            for i, sp in enumerate(self.sprites):
                sp["x"], sp["y"], sp["a"] = self.hand_target(i, len(self.sprites))
                sp["s"] = 1.0
            return
        if not self.can_act():
            return
        if self.pay_pending:
            for rect, key, ok in self.buttons:
                if key in ("pay_confirm", "pay_cancel") and ok and rect.collidepoint(pos):
                    return self.press(key)
            h = self.hit(pos)
            if h and h[0] == "die":
                i = h[1]
                eligible = self.tunable_dice() if self.pay_pending["tune"] else range(len(self.me().dice))
                if i not in eligible:
                    self.fx.toast("That die cannot be used for this action", RED)
                elif i in self.sel_dice:
                    self.sel_dice.remove(i)
                else:
                    limit = 1 if self.pay_pending["tune"] else self.pay_pending["cost"].n + self.pay_pending["cost"].unaligned
                    if len(self.sel_dice) < limit:
                        self.sel_dice.add(i)
                    else:
                        self.fx.toast(f"This action needs {limit} dice", DIM)
                return
            return
        for rect, key, ok in self.buttons:
            if ok and rect.collidepoint(pos):
                return self.press(key)
        h, s, p = self.hit(pos), self.s, self.view
        if h is None:
            return
        phase = s.phase
        if h[0] == "die" and phase == "roll":
            self.sel_dice ^= {h[1]}
        elif h[0] == "hand":
            if phase == "setup" and not self.me().mull_done:
                self.sel_hand ^= {h[1]}
            elif phase == "action" and not s.pending:
                sp = self.sprites[h[1]]
                self.drag = {"i": h[1], "off": (pos[0] - sp["x"], pos[1] - sp["y"]), "pos": pos}
        elif h[0] == "skill":
            a = next((x for x in self.acts if x.type == "skill" and x.index == h[1]), None)
            if a:
                sk = self.me().active_char.defn.skills[h[1]]
                self.begin_payment(a, sk.cost, sk.name, sk.desc)
            else:
                self.fx.toast("Not enough dice or energy", RED)
        elif h[0] == "char" and h[1] == p:
            if s.pending or (phase == "setup" and self.me().mull_done):
                a = next((x for x in self.acts if x.type == "choose_active" and x.index == h[2]), None)
                if a:
                    self.do(a)
            elif phase == "action":
                a = next((x for x in self.acts if x.type == "switch" and x.index == h[2]), None)
                if a:
                    target = self.me().characters[h[2]]
                    self.begin_payment(a, rules._switch_cost(self.me()), f"Switch to {target.name}",
                                       "Choose dice to pay the switching cost.")

    def right_click(self, pos):
        """Right-click a hand card: convert it into an element die (Elemental Tuning)."""
        if not self.can_act() or self.s.phase != "action" or self.s.pending or self.pay_pending:
            return
        h = self.hit(pos)
        if h and h[0] == "hand":
            self.tune(h[1])

    def tunable_dice(self):
        P = self.me()
        ch = P.active_char
        if not ch:
            return []
        return [j for j, d in enumerate(P.dice) if d not in (OMNI, ch.defn.element)]

    def tune(self, i, prefer=None):
        cand = self.tunable_dice()
        if not cand:
            self.fx.toast("No dice to convert (Omni and matching dice stay as they are)", RED)
            return False
        sp = self.sprites[i]
        start = (sp["x"], sp["y"])
        if prefer is None:
            return self.begin_tune(i, start)
        if prefer not in cand:
            self.fx.toast("Choose a non-matching die to convert", RED)
            return False
        return self._execute_tune(i, prefer, start)

    def _execute_tune(self, i, j, start=None):
        P = self.me()
        if j not in self.tunable_dice():
            self.fx.toast("Choose a non-matching die to convert", RED)
            return False
        sp = self.sprites[i]
        start = start or (sp["x"], sp["y"])
        tgt, name = self.die_pos(j), P.hand[i]
        if self.do(Action("tune", self.view, index=i, target=j)):
            self.fx.fly(art.card_image(CARD_DEFS[name], (CARD_W, CARD_H)), start, tgt, 0.35, 0.0, 0.25, 1.0, 0.3)
            self.spin[self.view][j] = 0.6
            self.fx.toast(f"{name} converted into a {P.active_char.defn.element} die", GOLD)
            self.logline(f"{self.who(self.view)}: converts {name} into a die", DIM)
            return True
        return False

    def press(self, key):
        p, P = self.view, self.me()
        if key == "pay_cancel":
            self.pay_pending = None
            self.sel_dice.clear()
        elif key == "pay_confirm":
            pending = self.pay_pending
            if pending is None:
                return
            ids = tuple(sorted(self.sel_dice))
            if pending["tune"]:
                if len(ids) != 1:
                    self.fx.toast("Select one die to convert", RED)
                    return
                self.pay_pending = None
                self._execute_tune(pending["card_index"], ids[0], pending["source"])
            elif D.payment_ok(P.dice, pending["cost"], ids):
                action = replace(pending["action"], dice=ids)
                if pending["source"] is not None and action.type == "card":
                    self.fly_hint = (pending["source"], None)
                self.pay_pending = None
                self.do(action)
            else:
                self.fx.toast("Choose a valid set of dice for this cost", RED)
        elif key == "end_round":
            self.do(Action("end_round", p))
        elif key == "mull_confirm":
            self.do(Action("mulligan", p, ids=tuple(sorted(self.sel_hand))))
        elif key == "roll_confirm":
            if self.sel_dice and P.rerolls > 0:
                self.do(Action("reroll", p, ids=tuple(sorted(self.sel_dice))))
            self.do(Action("confirm_roll", p))             # straight on to the next stage

    def drop(self, pos):
        d, self.drag = self.drag, None
        P, i = self.me(), d["i"]
        if i >= len(P.hand) or not self.can_act():
            return
        sp = self.sprites[i]
        start = (sp["x"], sp["y"])
        name = P.hand[i]
        if self.dice_rect().collidepoint(pos):                   # anywhere on the visible dice tray converts the card
            j = next((k for k in range(len(P.dice)) if abs(pos[0] - self.die_pos(k)[0]) < 34 and abs(pos[1] - self.die_pos(k)[1]) < 26), None)
            self.tune(i, j)
            return
        if pos[1] > 520:
            return                                               # dropped back on the hand
        tgt = next((k for k in range(3) if self.char_rect(self.view, k).collidepoint(pos)), None)
        cands = [a for a in self.acts if a.type == "card" and P.hand[a.index] == name]
        a = next((a for a in cands if a.target == tgt), None) if tgt is not None else None
        a = a or next((a for a in cands if a.target == -1), None)
        if a is None:
            self.fx.toast("Can't play that here" if cands else "You can't play that card right now", RED)
            return
        a = replace(a, index=i)
        if not self.begin_payment(a, CARD_DEFS[name].cost, name, CARD_DEFS[name].text, start):
            self.fly_hint = None

    def update_mouse(self, dt):
        pos = pygame.mouse.get_pos()
        vx = (pos[0] - self.last_mouse[0]) / max(dt, 1e-3)
        self.mouse_v += (vx - self.mouse_v) * min(1.0, 10 * dt)
        self.last_mouse = pos
        if self.drag:
            self.drag["pos"] = pos
        self.hover = self.hit(pos)
        self.hl = set()
        if self.hover and self.can_act():
            h = self.hover
            a = None
            if h[0] == "skill":
                a = next((x for x in self.acts if x.type == "skill" and x.index == h[1]), None)
            elif h[0] == "hand" and h[1] < len(self.me().hand):
                a = next((x for x in self.acts if x.type == "card" and self.me().hand[x.index] == self.me().hand[h[1]]), None)
            if a:
                self.hl = set(a.dice)

    # ------------------------------------------------------------------ update
    def update(self, dt):
        self.clock += dt
        self.intro_t += dt
        self.fx.update(dt * self.speed)
        self.update_mouse(dt)
        now = self.fx.clock
        for k in [k for k, v in self.hit_t.items() if v < now]:
            del self.hit_t[k]
        for k in [k for k, v in self.lunge.items() if v + 0.5 < now]:
            del self.lunge[k]
        for sp_ in self.spin:
            for k in list(sp_):
                sp_[k] -= dt
                if sp_[k] <= 0:
                    del sp_[k]
        for key in list(self.vis_hp):                           # count the HP number down after the hit
            val, rel = self.vis_hp[key]
            if now >= rel:
                real = self.s.players[key[0]].characters[key[1]].hp
                step = max(0.12, abs(val - real) * 5 * dt)
                val = val - step if val > real else val + step
                if abs(val - real) < 0.2:
                    del self.vis_hp[key]
                else:
                    self.vis_hp[key][0] = val
        n = len(self.sprites)
        k = 1 - math.exp(-13 * dt)
        mull = self.mulligan_stage()
        for i, sp in enumerate(self.sprites):
            if self.drag and self.drag["i"] == i:
                continue
            tx, ty, ta = self.hand_target(i, n)
            ts = 1.25 if mull else 1.0
            if self.sel_hand and i in self.sel_hand:
                ty -= 36
            elif self.hover and self.hover[0] == "hand" and self.hover[1] == i and self.can_act() and not mull:
                ty, ta, ts = HAND_Y - 64, 0.0, 1.12
            sp["x"] += (tx - sp["x"]) * k
            sp["y"] += (ty - sp["y"]) * k
            sp["a"] += (ta - sp["a"]) * k
            sp["s"] += (ts - sp["s"]) * k
        a = self.actor()
        self.t_ai -= dt
        if a is None or self.human[a] or self.cover is not None or self.intro_t < INTRO_DUR:
            return
        if self.ai_job is None:
            self.ai_job = AIJob(self.controllers[a], self.s)          # it thinks while the last move is still shown
        elif self.ai_job.done and self.t_ai <= 0 and self.fx.clock >= self.busy_until:
            job, self.ai_job = self.ai_job, None
            act = job.result
            if job.error is not None or act is None:
                self.fx.toast("AI error, playing a fallback move", RED)
                act = random.choice(rules.legal_actions(self.s))
            self.do(act)
            self.t_ai = 0.8 / self.speed

    # ------------------------------------------------------------------ drawing
    def draw(self):
        c = self.canvas
        c.blit(art.table(), (0, 0))
        self.buttons, self.icons = [], []
        if self.cover is not None:
            c.fill((10, 14, 16))
            text(c, f"Player {self.cover + 1}'s turn", (W / 2, 300), 46, GOLD, True, "center")
            text(c, "Pass the device, then click to continue", (W / 2, 362), 22, DIM, False, "center")
        else:
            c.blit(art.mat(MAT.size), MAT)
            self.draw_zones()
            for p in (1 - self.view, self.view):
                for i in range(3):
                    self.draw_char(p, i)
                self.draw_team(p)
            self.draw_side_info()
            self.draw_middle()
            self.draw_dice()
            self.draw_skills()
            if self.mulligan_stage():
                dim = pygame.Surface((W, H), pygame.SRCALPHA)
                dim.fill((6, 11, 18, 128))
                c.blit(dim, (0, 0))
                text(c, "Starting Hand", (W / 2, 116), 38, TEXT, True, "center")
                text(c, "Select card(s) to switch", (W / 2, 158), 18, DIM, False, "center")
            self.draw_hand()
            if self.mulligan_stage():
                n = len(self.sel_hand)
                self.button(pygame.Rect(535, 620, 210, 46), f"Confirm  ·  {n} selected", "mull_confirm", True, (220, 190, 128))
            if self.drag:
                self.draw_dragged()
            self.draw_inspector()
            if self.pay_pending:
                self.draw_payment_select()
            self.fx.draw(c)
            self.fx.draw_toasts(c, 102, 146)
            if self.fx.flash > 0:
                fl = pygame.Surface((W, H))
                fl.fill((255, 244, 215))
                fl.set_alpha(int(110 * self.fx.flash))
                c.blit(fl, (0, 0))
            if self.s.phase == "over":
                self.draw_over()
            if self.intro_t < INTRO_DUR:
                self.draw_intro()
        self.screen.blit(c, (0, 0))

    # ---- coin toss
    def draw_intro(self):
        c, t = self.canvas, self.intro_t
        dim = pygame.Surface((W, H), pygame.SRCALPHA)
        dim.fill((6, 8, 8, 215 if t < INTRO_DUR - 0.5 else int(215 * (INTRO_DUR - t) / 0.5)))
        c.blit(dim, (0, 0))
        first = self.s.first_player
        a_is_view = first == self.view if not (self.hotseat or not any(self.human)) else first == 0
        faces = ("YOU", "OPPONENT") if not (self.hotseat or not any(self.human)) else ("PLAYER 1", "PLAYER 2")
        flips = 8 if a_is_view else 9
        fl_t = min(1.0, max(0.0, (t - 0.5) / 2.3))
        theta = ease_out(fl_t) * math.pi * flips
        lift = math.sin(math.pi * fl_t) * 130
        R = 70
        cx, cy = W / 2, 330 - lift
        sx = abs(math.cos(theta))
        face = faces[0] if math.cos(theta) >= 0 else faces[1]
        coin = pygame.Surface((R * 2, R * 2), pygame.SRCALPHA)
        pygame.draw.circle(coin, GOLD_D, (R, R), R)
        pygame.draw.circle(coin, GOLD, (R, R), R - 5)
        pygame.draw.circle(coin, GOLD_L, (R, R), R - 14, 3)
        text(coin, face, (R, R), 17 if len(face) > 4 else 26, INK, True, "center", shadow=False)
        coin = pygame.transform.smoothscale(coin, (max(4, int(2 * R * sx)), 2 * R))
        art.add_glow(c, (cx, cy), GOLD, 150, 0.4)
        c.blit(coin, coin.get_rect(center=(cx, cy)))
        text(c, "COIN TOSS", (W / 2, 140), 40, GOLD_L, True, "center")
        if t < 0.5 + 2.3:
            text(c, "Deciding who plays first…", (W / 2, 190), 22, TEXT, False, "center")
        else:
            w = self.who(first)
            msg = "You go first!" if w == "You" else (f"{w} goes first" if w != "Opponent" else "Opponent goes first")
            text(c, msg, (W / 2, 520), 44, GOLD_L, True, "center")
            text(c, "The first player acts first in every Action Phase until someone ends the round first.", (W / 2, 568), 18, DIM, False, "center")
            if t > 1.2 + 2.3:
                text(c, "click to continue", (W / 2, 610), 15, DIM, False, "center")

    # ---- board pieces
    def draw_zones(self):
        c = self.canvas
        for p in (0, 1):
            P = self.s.players[p]
            for kind, items in (("support", P.supports), ("summon", P.summons)):
                zr = self.zone_rect(p, kind, 0)
                ly = zr.y + 200 + 3 if self.side(p) == 0 else zr.y - 14
                text(c, "SUPPORTS" if kind == "support" else "SUMMONS", (zr.x + 74, ly), 10, GOLD_D, True, "midtop", shadow=False)
                for k in range(4):
                    r = self.zone_rect(p, kind, k)
                    if k < len(items):
                        self.draw_tile(r, kind, items[k], p)
                    else:
                        pygame.draw.rect(c, (255, 235, 180, 40), r, 1, border_radius=8)
                        pygame.draw.rect(c, (90, 120, 118), r.inflate(-6, -6), 1, border_radius=8)

    def draw_tile(self, r, kind, u, p):
        c = self.canvas
        if kind == "support":
            key = ("supp", u.name)
            if key not in art._cache:
                art._cache[key] = pygame.transform.smoothscale(art.card_image(CARD_DEFS[u.name], (CARD_W, CARD_H)), (70, 96))
            c.blit(art._cache[key], r)
            val = u.usages
        else:
            sd = SUMMON_DEFS[u.name]
            col = ELEM_COL[sd.element]
            tile = pygame.Surface(r.size, pygame.SRCALPHA)
            tile.blit(art.rounded(art.parchment(r.size), 8), (0, 0))
            pygame.draw.rect(tile, shade(col, 0.7), pygame.Rect(4, 4, r.w - 8, 38), border_radius=6)
            art.draw_symbol(tile, sd.element, (r.w / 2, 23), 15)
            for k, ln in enumerate(wrap(u.name, 11, r.w - 8, True)[:2]):
                text(tile, ln, (r.w / 2, 46 + k * 12), 11, INK, True, "midtop", shadow=False)
            pygame.draw.circle(tile, (24, 16, 8), (r.w // 2, 78), 12)
            pygame.draw.circle(tile, shade(col, 0.55), (r.w // 2, 78), 11)
            text(tile, sd.damage, (r.w // 2, 78), 15, (255, 250, 235), True, "center", shadow=False)
            art.gold_frame(tile, pygame.Rect(0, 0, r.w, r.h), 8, 2, corners=False)
            c.blit(tile, r)
            val = u.usages
        if val is not None:
            pygame.draw.circle(c, (24, 16, 8), (r.right - 8, r.y + 10), 12)
            pygame.draw.circle(c, GOLD_D, (r.right - 8, r.y + 10), 11)
            pygame.draw.circle(c, GOLD, (r.right - 8, r.y + 10), 11, 1)
            text(c, int(val), (r.right - 8, r.y + 10), 14, (255, 244, 220), True, "center", shadow=False)

    def draw_team(self, p):
        c = self.canvas
        for rect, st in zip(self.team_rects(p), self.s.players[p].combat):
            num = st.shield if st.shield else (st.usages if st.usages is not None else st.duration)
            art.badge(c, rect.center, 10, art.STATUS_ELEM.get(st.name), num)
            self.icons.append((rect.inflate(6, 6), ("status", st.name, st)))

    def shown_hp(self, p, i):
        v = self.vis_hp.get((p, i))
        return int(round(v[0])) if v else self.s.players[p].characters[i].hp

    def draw_char(self, p, i):
        c, P = self.canvas, self.s.players[p]
        ch = P.characters[i]
        r = self.char_rect(p, i)
        active = P.active == i
        now = self.fx.clock
        if active:
            r = r.move(0, -12 if self.side(p) == 0 else 12)
        lg = self.lunge.get((p, i))
        if lg is not None and 0 <= now - lg <= 0.5:
            r = r.move(0, (-1 if self.side(p) == 0 else 1) * int(math.sin(math.pi * (now - lg) / 0.5) * 30))
        t = max(0.0, self.hit_t.get((p, i), 0) - now)
        d = ch.defn
        clickable = self.can_act() and p == self.view and (
            (self.s.pending and not ch.defeated) or (self.s.phase == "setup" and self.me().mull_done) or
            (self.s.phase == "action" and not active and not ch.defeated and any(a.type == "switch" and a.index == i for a in self.acts)))
        sh = pygame.Surface((CW + 16, CH + 16), pygame.SRCALPHA)
        pygame.draw.rect(sh, (0, 0, 0, 90), sh.get_rect().inflate(-6, -6), border_radius=16)
        c.blit(sh, (r.x - 5, r.y))
        if active or clickable:
            pulse = 0.55 + 0.25 * math.sin(self.clock * 5) if clickable else 0.5
            art.add_glow(c, r.center, GOLD, 125, pulse)
        c.blit(art.char_base(ch.name, d.element, d.weapon, (CW, CH)), r)
        win = pygame.Rect(r.x + 4, r.y + 4, CW - 8, CH - 8)
        frozen = any(s_.name == "Frozen" for s_ in ch.statuses)
        petri = any(s_.name == "Petrified" for s_ in ch.statuses)
        if frozen or petri:
            ice = pygame.Surface(win.size, pygame.SRCALPHA)
            ice.fill((170, 225, 255, 130) if frozen else (190, 160, 90, 140))
            for k in range(7):
                x0 = 10 + k * 19
                pygame.draw.polygon(ice, (240, 250, 255, 170), [(x0, win.h), (x0 + 6, win.h - 30 - (k % 3) * 12), (x0 + 12, win.h)])
            c.blit(ice, win)
            text(c, "FROZEN" if frozen else "PETRIFIED", (win.centerx, win.bottom - 14), 14, (20, 40, 70) if frozen else (60, 40, 10), True, "center", shadow=False)
        if t > 0:
            f = pygame.Surface(win.size, pygame.SRCALPHA)
            f.fill((255, 70, 60, int(170 * t / 0.45)))
            c.blit(f, win)
        hp = self.shown_hp(p, i)
        pygame.draw.circle(c, (28, 16, 8), (r.x + 20, r.y + 22), 20)
        pygame.draw.circle(c, (150, 36, 44), (r.x + 20, r.y + 22), 17)
        pygame.draw.circle(c, GOLD, (r.x + 20, r.y + 22), 18, 2)
        text(c, hp, (r.x + 20, r.y + 22), 20, (255, 244, 230), True, "center")
        # state row: aura, equipment, statuses (each is hoverable)
        x = r.x + 16
        y = r.y + CH - 24
        if ch.aura:
            art.badge(c, (x, y), 11, ch.aura, None, "aura", ELEM_COL[ch.aura])
            self.icons.append((pygame.Rect(x - 13, y - 13, 26, 26), ("aura", ch.aura)))
            x += 28
        for slot in ("weapon", "artifact", "talent"):
            if slot in ch.equipment:
                rect = pygame.Rect(x - 11, y - 11, 22, 22)
                art.equip_icon(c, rect, slot, True)
                self.icons.append((rect, ("equip", slot, ch.equipment[slot])))
                x += 26
        for st in ch.statuses:
            if st.name in ch.equipment.values() or x > r.right - 16:
                continue
            num = st.shield if st.shield else (st.usages if st.usages is not None else st.duration)
            art.badge(c, (x, y), 11, art.STATUS_ELEM.get(st.name), num)
            self.icons.append((pygame.Rect(x - 13, y - 13, 26, 26), ("status", st.name, st)))
            x += 28
        for k in range(d.max_energy):
            cx, cy = r.x + 20 + k * 20, r.y + CH - 9
            if k < ch.energy:
                art.add_glow(c, (cx, cy), GOLD, 13, 0.6)
                art.gem(c, (cx, cy), 7, None, "en")
            else:
                pygame.draw.polygon(c, (110, 92, 66), [(cx, cy - 7), (cx + 6, cy), (cx, cy + 7), (cx - 6, cy)], 2)
        text(c, "ENERGY", (r.right - 12, r.y + CH - 9), 9, (255, 239, 201), True, "midright", shadow=False)
        if ch.defeated:
            g = pygame.Surface(r.size, pygame.SRCALPHA)
            pygame.draw.rect(g, (12, 10, 10, 205), g.get_rect(), border_radius=12)
            c.blit(g, r)
            text(c, "DEFEATED", r.center, 20, RED, True, "center")

    def draw_side_info(self):
        c = self.canvas
        for p in (0, 1):
            P = self.s.players[p]
            mine = self.side(p) == 0
            acting = self.actor() == p
            active = P.active_char or (P.characters[0] if P.characters else None)
            title = active.name if active else self.who(p)
            status = "Now Acting" if acting else "Now Waiting"
            if mine:
                banner = pygame.Rect(24, 654, 236, 44)
                avatar = pygame.Rect(27, 655, 42, 42)
                text_y = banner.y + 8
                pile_pos = (38, 488)
                if P.ended:
                    status = "Round Ended"
            else:
                banner = pygame.Rect(24, 24, 236, 44)
                avatar = pygame.Rect(27, 25, 42, 42)
                text_y = banner.y + 7
                pile_pos = (38, 112)
                if P.ended:
                    status = "Round Ended"
            panel = pygame.Surface(banner.size, pygame.SRCALPHA)
            pygame.draw.rect(panel, (51, 73, 96, 225), panel.get_rect(), border_radius=22)
            pygame.draw.rect(panel, (219, 197, 157), panel.get_rect(), 2, border_radius=22)
            c.blit(panel, banner)
            if active:
                thumb = pygame.Surface(avatar.size, pygame.SRCALPHA)
                art.portrait(thumb, thumb.get_rect(), active.name, active.defn.element, active.defn.weapon)
                c.blit(art.rounded(thumb, 19), avatar)
                pygame.draw.circle(c, (230, 211, 169), avatar.center, 20, 2)
            text(c, title, (avatar.right + 7, text_y), 15, TEXT, True, shadow=False)
            text(c, status, (avatar.right + 8, text_y + 19), 10, GOLD_L if acting else (205, 216, 226), True, shadow=False)
            if active:
                art.gem(c, (banner.right - 17, banner.centery), 11, active.defn.element)
            self.draw_pile(pile_pos, len(P.deck), "CARDS")
        # The opponent's hidden hand is fanned along the top edge, as in the reference HUD.
        F = self.s.players[1 - self.view]
        n = min(len(F.hand), 5)
        for k in range(n):
            img = pygame.transform.rotozoom(art.back_image((48, 68)), (k - (n - 1) / 2) * 2, 1.0)
            c.blit(img, img.get_rect(topleft=(510 + k * 44, -25)))

    def draw_pile(self, pos, n, label):
        c = self.canvas
        for k in range(min(3, max(1, n // 8 + 1))):
            art.card_back(c, pygame.Rect(pos[0] + k * 3, pos[1] - k * 3, 72, 98))
        badge = pygame.Rect(pos[0] + 47, pos[1] + 72, 40, 28)
        pygame.draw.ellipse(c, (227, 203, 150), badge)
        pygame.draw.ellipse(c, (112, 82, 49), badge, 2)
        text(c, str(n), badge.center, 16, (48, 42, 34), True, "center", shadow=False)
        text(c, label, (pos[0] + 36, pos[1] + 102), 10, DIM, True, "midtop", shadow=False)

    def draw_log(self):
        c = self.canvas
        lines = []
        for s_, col in self.log[-30:]:
            for k, ln in enumerate(wrap(s_.strip(), 13, 152)):
                lines.append((("   " if k else "") + ln, col))
        lines = lines[-6:]
        if not lines:
            return
        box = pygame.Rect(14, 234, 176, 38 + 17 * len(lines))
        panel = pygame.Surface(box.size, pygame.SRCALPHA)
        pygame.draw.rect(panel, (13, 24, 38, 222), panel.get_rect(), border_radius=12)
        pygame.draw.rect(panel, (190, 158, 97, 150), panel.get_rect(), 1, border_radius=12)
        c.blit(panel, box)
        text(c, "BATTLE LOG", (box.x + 12, box.y + 8), 12, GOLD_L, True, shadow=False)
        for i, (line, col) in enumerate(lines):
            text(c, line, (box.x + 12, box.y + 27 + i * 17), 13, col, False, shadow=False)

    def draw_middle(self):
        c, s = self.canvas, self.s
        v = self.view
        if s.pending:
            msg, col = ("Choose your next character", GOLD) if s.pending[0] == v else ("Opponent is choosing a character…", DIM)
        else:
            msg, col = "", TEXT
        if msg and not self.fx.ribbons:
            band = pygame.Surface((W - 80, 42), pygame.SRCALPHA)
            pygame.draw.rect(band, (55, 39, 30, 170), band.get_rect())
            pygame.draw.line(band, (211, 178, 121, 175), (0, 1), (band.get_width(), 1), 1)
            pygame.draw.line(band, (211, 178, 121, 175), (0, band.get_height() - 2),
                             (band.get_width(), band.get_height() - 2), 1)
            c.blit(band, (40, 330))
            text(c, msg, (W / 2, 351), 20, col, True, "center", shadow=False)
        if self.can_act():
            P = self.me()
            if s.phase == "action" and not s.pending:
                r = self.end_btn()
                center = (r.centerx, r.y + 34)
                hov = r.collidepoint(pygame.mouse.get_pos())
                if hov:
                    art.add_glow(c, center, GOLD_L, 58, 0.7)
                pygame.draw.circle(c, (83, 59, 37), center, 34)
                pygame.draw.circle(c, (238, 200, 118) if hov else (205, 164, 91), center, 30, 3)
                pygame.draw.circle(c, (227, 188, 105), center, 24, 1)
                # hourglass emblem
                pygame.draw.line(c, (255, 239, 192), (center[0] - 9, center[1] - 12), (center[0] + 9, center[1] - 12), 2)
                pygame.draw.line(c, (255, 239, 192), (center[0] - 9, center[1] + 12), (center[0] + 9, center[1] + 12), 2)
                pygame.draw.line(c, (255, 239, 192), (center[0] - 8, center[1] - 11), (center[0] + 8, center[1] + 11), 2)
                pygame.draw.line(c, (255, 239, 192), (center[0] + 8, center[1] - 11), (center[0] - 8, center[1] + 11), 2)
                text(c, "END PHASE", (center[0], r.bottom - 8), 10, TEXT, True, "center", shadow=False)
                self.buttons.append((r, "end_round", True))
            if s.phase == "setup" and not P.mull_done:
                pass
            if s.phase == "roll":
                n = len(self.sel_dice)
                self.button(pygame.Rect(1114, 514, 148, 30), "Roll" if n == 0 else f"Reroll {n} + Go", "roll_confirm", True, (74, 115, 91))
                text(c, f"Rerolls: {P.rerolls}", (1188, 549), 12, GOLD_L, True, "center")

    def button(self, rect, label, key, enabled, base):
        c = self.canvas
        hov = enabled and rect.collidepoint(pygame.mouse.get_pos())
        if hov:
            art.add_glow(c, rect.center, GOLD_L, rect.w * 0.72, 0.48)
        pygame.draw.rect(c, (13, 18, 24), rect.move(0, 5), border_radius=15)
        frame = GOLD_L if hov else (152, 119, 72) if enabled else (83, 91, 101)
        pygame.draw.rect(c, frame, rect, border_radius=15)
        face = mix(base, (255, 246, 222), 0.18 if hov else 0.0) if enabled else (103, 111, 119)
        pygame.draw.rect(c, face, rect.inflate(-4, -4), border_radius=12)
        if enabled:
            pygame.draw.line(c, (255, 250, 231), (rect.x + 20, rect.y + 5), (rect.right - 20, rect.y + 5), 2)
        text(c, label, rect.center, 17, (48, 51, 57) if enabled else (183, 189, 195), True, "center", shadow=False)
        self.buttons.append((rect, key, enabled))

    def draw_hand(self):
        c, P = self.canvas, self.me()
        show = self.human[self.view] or self.reveal
        hov = self.hover[1] if self.hover and self.hover[0] == "hand" else None
        order = [i for i in range(len(self.sprites)) if i != hov] + ([hov] if hov is not None else [])
        for i in order:
            sp = self.sprites[i]
            if self.drag and self.drag["i"] == i:
                continue
            if show:
                cd = CARD_DEFS[sp["name"]]
                playable = self.can_act() and any(x.type == "card" and P.hand[x.index] == sp["name"] for x in self.acts)
                dim = self.can_act() and self.s.phase == "action" and not playable
                img = art.card_image(cd, (CARD_W, CARD_H))
                if dim:
                    img = art._cache.setdefault(("dimhand", sp["name"]), self._dimmed(img))
            else:
                img = art.back_image((CARD_W, CARD_H))
                playable = False
            rot = pygame.transform.rotozoom(img, sp["a"], sp["s"])
            x, y = sp["x"], sp["y"]
            if "d0" in sp:                                         # drawn cards arc in from the deck
                tx, ty, _ = self.hand_target(i, len(self.sprites))
                dist = math.hypot(tx - sp["x"], ty - sp["y"])
                y -= math.sin(math.pi * (1 - min(1.0, dist / sp["d0"]))) * 80
                if dist < 4:
                    del sp["d0"]
            shadow = pygame.Surface(rot.get_size(), pygame.SRCALPHA)
            pygame.draw.ellipse(shadow, (0, 0, 0, 80), shadow.get_rect().inflate(-10, -18))
            c.blit(shadow, shadow.get_rect(center=(x + 4, y + 10)))
            if playable or i in self.sel_hand:
                art.add_glow(c, (x, y), (255, 210, 110), CARD_H * 0.62 * sp["s"], 0.55)
            c.blit(rot, rot.get_rect(center=(x, y)))
            if i in self.sel_hand:
                text(c, "SWAP", (x, y - CARD_H * sp["s"] / 2 + 14), 16, (255, 255, 255), True, "center")
                pygame.draw.rect(c, RED, rot.get_rect(center=(x, y)).inflate(-6, -6), 3, border_radius=10)

    @staticmethod
    def _dimmed(img):
        d = img.copy()
        d.fill((150, 146, 140, 255), special_flags=pygame.BLEND_RGBA_MULT)
        return d

    def draw_dice(self):
        c, P = self.canvas, self.me()
        if self.pay_pending:
            return
        spin = self.spin[self.view]
        tray_rect = self.dice_rect()
        tuning = self.drag is not None
        if tuning:
            pulse = 0.5 + 0.5 * math.sin(self.clock * 7)
            art.add_glow(c, (tray_rect.centerx, tray_rect.centery), GOLD, 55, 0.18 + 0.16 * pulse)
        pygame.draw.circle(c, (76, 55, 37), (tray_rect.centerx, 66), 20)
        pygame.draw.circle(c, (237, 205, 145), (tray_rect.centerx, 66), 17, 2)
        text(c, len(P.dice), (tray_rect.centerx, 66), 16, GOLD_L, True, "center", shadow=False)
        text(c, "DICE", (tray_rect.centerx, tray_rect.y + 8), 10, GOLD_L, True, "midtop", shadow=False)
        if tuning:
            ok = bool(self.tunable_dice())
            text(c, "DROP", (tray_rect.centerx, tray_rect.y + 26), 9, GOLD_L if ok else RED, True, "midtop", shadow=False)
        elif not P.dice:
            text(c, "Dice appear after the roll", (tray_rect.centerx, tray_rect.centery + 7), 12, DIM, False, "center", shadow=False)
        for i, face in enumerate(P.dice):
            x, y = self.die_pos(i)
            selecting = self.pay_pending is not None
            if selecting and self.pay_pending["tune"]:
                eligible = i in self.tunable_dice()
                dim = not eligible
            elif selecting:
                eligible = True
                limit = self.pay_pending["cost"].n + self.pay_pending["cost"].unaligned
                dim = len(self.sel_dice) >= limit and i not in self.sel_dice
            else:
                eligible, dim = False, bool(tuning and i not in self.tunable_dice())
            if i in spin:
                u = 1 - spin[i] / 0.7
                if u < 0.65:
                    face = DICE_FACES[int(self.clock * 22 + i * 3) % len(DICE_FACES)]
                art.draw_die(c, (x, y - abs(math.cos(u * math.pi * 2.5)) * (1 - u) * 46), 46, face,
                             angle=(1 - u) * 640, scale=1 + 0.2 * (1 - u))
            else:
                art.draw_die(c, (x, y), 46, face, selected=i in self.sel_dice,
                             hl=(i in self.hl) or (selecting and eligible), dim=dim)

    def draw_payment_select(self):
        pending = self.pay_pending
        if not pending:
            return
        c = self.canvas
        # Focus attention on the payment choice while keeping the match visible.
        scrim = pygame.Surface((W, H), pygame.SRCALPHA)
        scrim.fill((5, 9, 16, 174))
        c.blit(scrim, (0, 0))

        left = pygame.Rect(28, 138, 390, 456)
        right = pygame.Rect(752, 138, 500, 456)
        for box in (left, right):
            pygame.draw.rect(c, (0, 0, 0, 150), box.move(0, 8), border_radius=18)
            pygame.draw.rect(c, (18, 27, 39), box, border_radius=16)
            pygame.draw.rect(c, (201, 166, 101), box, 2, border_radius=16)
            pygame.draw.rect(c, (36, 49, 65), pygame.Rect(box.x + 5, box.y + 5, box.w - 10, 54), border_radius=12)

        text(c, "ACTION PAYMENT", (left.x + 22, left.y + 18), 17, GOLD_L, True, shadow=False)
        title_size = 26
        while title_size > 17 and font(title_size, True).size(pending["title"])[0] > left.w - 44:
            title_size -= 1
        text(c, pending["title"], (left.x + 22, left.y + 82), title_size, TEXT, True, shadow=False)
        pygame.draw.line(c, (92, 111, 130), (left.x + 22, left.y + 124), (left.right - 22, left.y + 124), 2)

        if pending["tune"]:
            total = 1
            valid = len(self.sel_dice) == 1 and next(iter(self.sel_dice)) in self.tunable_dice()
            text(c, "ELEMENTAL TUNING", (left.x + 22, left.y + 148), 14, GOLD_L, True, shadow=False)
            text(c, "Choose one die to convert", (left.x + 22, left.y + 178), 19, TEXT, True, shadow=False)
            text(c, f"It will become {self.me().active_char.defn.element}.",
                 (left.x + 22, left.y + 210), 16, (184, 205, 221), False, shadow=False)
            text(c, "Matching and Omni dice cannot be converted.",
                 (left.x + 22, left.y + 248), 14, (157, 178, 197), False, shadow=False)
        else:
            cost = pending["cost"]
            total = cost.n + cost.unaligned
            chosen = tuple(sorted(self.sel_dice))
            valid = D.payment_ok(self.me().dice, cost, chosen)
            text(c, "REQUIRED COST", (left.x + 22, left.y + 148), 14, GOLD_L, True, shadow=False)
            art.draw_cost(c, (left.x + 28, left.y + 194), cost, 27)
            pygame.draw.line(c, (69, 86, 104), (left.x + 22, left.y + 238), (left.right - 22, left.y + 238), 1)
            alignment = f"{cost.n} {cost.element} / Omni  +  {cost.unaligned} any"
            text(c, alignment, (left.x + 22, left.y + 260), 15, (184, 205, 221), True, shadow=False)
            detail = pending["detail"] or "Choose the exact dice you want to spend."
            for i, line in enumerate(wrap(detail, 15, left.w - 44)[:6]):
                text(c, line, (left.x + 22, left.y + 302 + i * 22), 15, (222, 229, 236), False, shadow=False)

        selected = len(self.sel_dice)
        if valid:
            status, status_col = "READY — confirm your selection", (155, 231, 181)
        elif selected == 0:
            status, status_col = (f"Choose {total} die" if total == 1 else f"Choose {total} dice"), (238, 214, 164)
        elif selected < total:
            status, status_col = f"Choose {total - selected} more", (238, 214, 164)
        else:
            status, status_col = "That combination does not meet the cost", (255, 151, 137)
        text(c, status, (left.x + 22, left.bottom - 44), 15, status_col, True, shadow=False)

        text(c, "SELECT DICE", (right.x + 22, right.y + 17), 19, TEXT, True, shadow=False)
        text(c, "Click each die you want to spend", (right.x + 22, right.y + 72), 15,
             (185, 202, 218), False, shadow=False)
        P = self.me()
        for i, face in enumerate(P.dice):
            cx, cy = self.die_pos(i)
            tile = pygame.Rect(cx - 50, cy - 34, 100, 68)
            chosen = i in self.sel_dice
            if pending["tune"]:
                eligible = i in self.tunable_dice()
            else:
                # Required elemental dice and Omni are the preferred aligned payment;
                # unaligned cost can use any remaining face.
                eligible = face == OMNI or face == pending["cost"].element or pending["cost"].unaligned > 0
            fill = (83, 66, 38) if chosen else ((48, 61, 75) if eligible else (34, 40, 49))
            edge = GOLD_L if chosen else ((151, 176, 195) if eligible else (79, 88, 99))
            pygame.draw.rect(c, (0, 0, 0, 100), tile.move(0, 4), border_radius=13)
            pygame.draw.rect(c, fill, tile, border_radius=13)
            pygame.draw.rect(c, edge, tile, 3 if chosen else 2, border_radius=13)
            if chosen:
                art.add_glow(c, tile.center, GOLD_L, 58, 0.46)
            art.draw_die(c, (cx, cy), 48, face, selected=chosen, hl=eligible and not chosen,
                         dim=not eligible)
            text(c, "SELECTED" if chosen else ("MATCH" if eligible else "OTHER"),
                 (cx, tile.bottom - 2), 9, GOLD_L if chosen else (172, 194, 210) if eligible else DIM,
                 True, "midbottom", shadow=False)

        self.button(pygame.Rect(786, 536, 218, 48), "Cancel", "pay_cancel", True, (174, 176, 181))
        self.button(pygame.Rect(1018, 536, 210, 48), "Confirm", "pay_confirm", valid, (220, 190, 128))

    def draw_skills(self):
        c, P = self.canvas, self.me()
        ch = P.active_char
        if not ch or not self.human[self.view] or self.s.phase != "action":
            return
        for i, sk in enumerate(ch.defn.skills):
            r = self.skill_rect(i)
            ok = self.my_turn() and any(a.type == "skill" and a.index == i for a in self.acts)
            col = ELEM_COL[ch.defn.element]
            hov = ok and r.collidepoint(pygame.mouse.get_pos())
            center = (r.centerx, r.y + 31)
            if ok and hov:
                art.add_glow(c, center, col, 54, 0.62)
            pygame.draw.circle(c, (29, 36, 46), center, 29)
            pygame.draw.circle(c, (218, 194, 146) if ok else (113, 111, 105), center, 26, 2)
            pygame.draw.circle(c, mix((54, 59, 67), col, 0.3 if ok else 0.12), center, 22)
            if sk.kind == "normal":
                art.kind_icon(c, "weapon", center, 13, ch.defn.element)
            else:
                art.draw_symbol(c, ch.defn.element, center, 15)
            label = {"normal": "NORMAL", "skill": "SKILL", "burst": "BURST"}[sk.kind]
            text(c, label, (r.centerx, r.y + 62), 9, GOLD_L if ok else DIM, True, "center", shadow=False)
            w = art.draw_cost(c, (0, -99), sk.cost, 12)
            art.draw_cost(c, (r.centerx - w / 2, r.y + 76), sk.cost, 12)

    def draw_dragged(self):
        d = self.drag
        P = self.me()
        if d["i"] >= len(P.hand):
            return
        name = P.hand[d["i"]]
        pos = d["pos"]
        ok_t = {a.target for a in self.acts if a.type == "card" and P.hand[a.index] == name}
        pulse = 0.5 + 0.5 * math.sin(self.clock * 7)
        for k in range(3):
            if k in ok_t:
                art.add_glow(self.canvas, self.char_center(self.view, k), GOLD, 125, 0.35 + 0.35 * pulse)
                pygame.draw.rect(self.canvas, GOLD_L, self.char_rect(self.view, k).inflate(8, 8), 3, border_radius=14)
        if -1 in ok_t:
            pygame.draw.rect(self.canvas, GOLD, MAT.inflate(-6, -6), 3, border_radius=16)
        tilt = max(-14.0, min(14.0, -self.mouse_v * 0.012))
        img = art.card_image(CARD_DEFS[name], (CARD_W, CARD_H))
        rot = pygame.transform.rotozoom(img, tilt, 1.12)
        cx, cy = pos[0] - d["off"][0], pos[1] - d["off"][1]
        shadow = pygame.Surface(rot.get_size(), pygame.SRCALPHA)
        pygame.draw.ellipse(shadow, (0, 0, 0, 90), shadow.get_rect().inflate(-8, -16))
        self.canvas.blit(shadow, shadow.get_rect(center=(cx + 10, cy + 24)))
        art.add_glow(self.canvas, (cx, cy), (255, 215, 120), 100, 0.5)
        self.canvas.blit(rot, rot.get_rect(center=(cx, cy)))

    # ---- inspector: a big, readable description of whatever the mouse is over
    def skill_block(self, sk):
        return [("kv", sk.name, {"normal": "Normal Attack", "skill": "Elemental Skill", "burst": "Elemental Burst"}[sk.kind]),
                ("cost", sk.cost), ("para", sk.desc)]

    def inspect_content(self):
        h = self.hover
        if not h or self.drag or self.pay_pending or self.cover is not None or self.intro_t < INTRO_DUR:
            return None
        if h[0] == "hand" and h[1] < len(self.sprites) and (self.human[self.view] or self.reveal):
            cd = CARD_DEFS[self.sprites[h[1]]["name"]]
            return ("card", cd, "Drag it onto the board to play it, or onto the dice tray (or right-click) to convert it into a die.")
        if h[0] == "zone":
            _, kind, p, k = h
            P = self.s.players[p]
            if kind == "support":
                cd = CARD_DEFS[P.supports[k].name]
                return ("card", cd, f"Remaining uses: {P.supports[k].usages}")
            u = P.summons[k]
            sd = SUMMON_DEFS[u.name]
            return ("panel", u.name, [("sub", "Summon"), ("para", f"End Phase: deals {sd.damage} {sd.element} damage to the opposing active character."),
                                      ("para", f"Remaining uses: {u.usages}")])
        if h[0] == "icon":
            pl = h[1]
            if pl[0] == "aura":
                return ("panel", f"{pl[1]} aura", [("para", AURA_TEXT), ("para", "Cryo+Hydro: Frozen · Cryo+Pyro: Melt · Cryo+Electro: Superconduct · Hydro+Pyro: Vaporize · Hydro+Electro: Electro-Charged · Pyro+Electro: Overloaded.")])
            if pl[0] == "equip":
                cd = CARD_DEFS[pl[2]]
                return ("card", cd, f"Equipped {pl[1]}")
            name, st = pl[1], pl[2]
            tx = STATUS_DEFS[name].text if name in STATUS_DEFS else ""
            if name in CARD_DEFS and CARD_DEFS[name].text:
                tx = CARD_DEFS[name].text
            blocks = [("para", tx or "Active effect.")]
            num = st.shield if st.shield else st.usages
            if num is not None:
                blocks.append(("kv", "Remaining", str(num) + (" (shield)" if st.shield else " uses")))
            if st.duration is not None:
                blocks.append(("kv", "Lasts", f"{st.duration} more round(s)"))
            return ("panel", name, blocks)
        if h[0] == "char":
            ch = self.s.players[h[1]].characters[h[2]]
            d = ch.defn
            b = [("sub", f"{d.element} · {d.weapon}"), ("kv", "HP", f"{ch.hp} / {d.hp}"), ("kv", "Energy", f"{ch.energy} / {d.max_energy}")]
            if ch.aura:
                b.append(("kv", "Aura", f"{ch.aura}. {AURA_TEXT}"))
            for slot, nm in ch.equipment.items():
                b.append(("kv", slot.title(), f"{nm}: {CARD_DEFS[nm].text}"))
            for st in ch.statuses:
                if st.name not in ch.equipment.values():
                    b.append(("kv", st.name, STATUS_DEFS[st.name].text or "Active effect."))
            b.append(("gap",))
            for sk in d.skills:
                b += self.skill_block(sk)
            return ("character", ch)
        if h[0] == "skill":
            sk = self.me().active_char.defn.skills[h[1]]
            return ("panel", sk.name, self.skill_block(sk)[1:])
        return None

    def draw_inspector(self):
        info = self.inspect_content()
        if not info:
            return
        mx = pygame.mouse.get_pos()[0]
        x = W - 292 - 14 if mx < 640 else 14
        c = self.canvas
        if info[0] == "card":
            cd, note = info[1], info[2]
            left = 22 if mx > W / 2 else W - 22 - 500
            card = pygame.transform.smoothscale(art.card_large(cd), (210, 308))
            card_rect = card.get_rect(topleft=(left, 148))
            panel = pygame.Rect(left + 224, 148, 276, 360)
            pygame.draw.rect(c, (0, 0, 0, 90), panel.move(4, 6), border_radius=12)
            pygame.draw.rect(c, (27, 39, 52), panel, border_radius=10)
            pygame.draw.rect(c, (106, 130, 153), panel, 2, border_radius=10)
            pygame.draw.rect(c, (39, 53, 68), pygame.Rect(panel.x + 5, panel.y + 5, panel.w - 10, 46), border_radius=7)
            title_size = 19
            while title_size > 12 and font(title_size, True).size(cd.name)[0] > panel.w - 28:
                title_size -= 1
            text(c, cd.name, (panel.x + 14, panel.y + 15), title_size, TEXT, True, shadow=False)
            text(c, cd.kind.title(), (panel.x + 14, panel.y + 60), 13, GOLD_L, True, shadow=False)
            art.draw_cost(c, (panel.x + 14, panel.y + 82), cd.cost, 17)
            pygame.draw.line(c, (103, 122, 139), (panel.x + 12, panel.y + 116), (panel.right - 12, panel.y + 116), 1)
            body = getattr(cd, "text", "") or "No additional effect."
            for k, ln in enumerate(wrap(body, 14, panel.w - 28)[:9]):
                text(c, ln, (panel.x + 14, panel.y + 128 + 19 * k), 14, (220, 227, 235), False, shadow=False)
            foot_y = panel.bottom - 48
            pygame.draw.line(c, (103, 122, 139), (panel.x + 12, foot_y), (panel.right - 12, foot_y), 1)
            for k, ln in enumerate(wrap(note, 12, panel.w - 28)[:2]):
                text(c, ln, (panel.x + 14, foot_y + 8 + 15 * k), 12, (172, 194, 213), False, shadow=False)
            art.add_glow(c, card_rect.center, (255, 215, 130), 145, 0.22)
            c.blit(card, card_rect)
            return
        if info[0] == "character":
            ch = info[1]
            d = ch.defn
            left = 18 if mx > W / 2 else W - 18 - 532
            portrait = art.char_base(ch.name, d.element, d.weapon, (176, 300))
            portrait_rect = portrait.get_rect(topleft=(left, 190))
            panel = pygame.Rect(left + 188, 92, 344, 536)
            pygame.draw.rect(c, (0, 0, 0, 105), panel.move(5, 6), border_radius=12)
            pygame.draw.rect(c, (24, 34, 47), panel, border_radius=10)
            pygame.draw.rect(c, (102, 127, 151), panel, 2, border_radius=10)
            pygame.draw.rect(c, (34, 48, 64), pygame.Rect(panel.x + 4, panel.y + 4, panel.w - 8, 50), border_radius=7)
            title_size = 22
            while title_size > 15 and font(title_size, True).size(ch.name)[0] > panel.w - 30:
                title_size -= 1
            text(c, ch.name, (panel.x + 14, panel.y + 10), title_size, TEXT, True, shadow=False)
            text(c, f"{d.element}  ·  {d.weapon}", (panel.x + 15, panel.y + 34), 12,
                 (160, 194, 216), False, shadow=False)
            text(c, f"HP  {ch.hp}/{d.hp}     ENERGY  {ch.energy}/{d.max_energy}",
                 (panel.x + 15, panel.y + 66), 13, GOLD_L, True, shadow=False)
            y = panel.y + 94
            if ch.aura:
                text(c, f"Aura: {ch.aura}", (panel.x + 15, y), 12, (165, 218, 236), True, shadow=False)
                y += 21
            for sk in d.skills:
                box = pygame.Rect(panel.x + 10, y, panel.w - 20, 102)
                pygame.draw.rect(c, (31, 45, 60), box, border_radius=7)
                pygame.draw.rect(c, (75, 97, 118), box, 1, border_radius=7)
                label = {"normal": "NORMAL ATTACK", "skill": "ELEMENTAL SKILL", "burst": "ELEMENTAL BURST"}[sk.kind]
                name_size = 15
                while name_size > 11 and font(name_size, True).size(sk.name)[0] > box.w - 114:
                    name_size -= 1
                text(c, sk.name, (box.x + 12, box.y + 8), name_size, TEXT, True, shadow=False)
                text(c, label, (box.x + 12, box.y + 29), 9, (154, 182, 204), True, shadow=False)
                art.draw_cost(c, (box.right - 106, box.y + 8), sk.cost, 13)
                for i, ln in enumerate(wrap(sk.desc, 11, box.w - 24)[:3]):
                    text(c, ln, (box.x + 12, box.y + 51 + i * 14), 11, (215, 224, 233), False, shadow=False)
                y += 108
            tail = [f"{slot.title()}: {name}" for slot, name in ch.equipment.items()]
            tail.extend(status.name for status in ch.statuses if status.name not in ch.equipment.values())
            if tail:
                footer_y = min(y + 2, panel.bottom - 49)
                text(c, "EQUIPMENT / STATUS", (panel.x + 14, footer_y), 10, (154, 182, 204), True, shadow=False)
                for i, ln in enumerate(wrap(" · ".join(tail), 10, panel.w - 30)[:2]):
                    text(c, ln, (panel.x + 14, min(footer_y + 16 + i * 13, panel.bottom - 32 + i * 13)),
                         10, (213, 222, 231), False, shadow=False)
            art.add_glow(c, portrait_rect.center, ELEM_COL[d.element], 150, 0.2)
            c.blit(portrait, portrait_rect)
            return
        title, blocks = info[1], info[2]
        for fs in (14, 13, 12, 11):
            ops, y = [], 80
            for b in blocks:
                kind = b[0]
                if kind == "sub":
                    ops.append(("t", b[1], y, fs, GOLD_L, True)); y += fs + 8
                elif kind == "para":
                    for ln in wrap(b[1], fs, 262):
                        ops.append(("t", ln, y, fs, (219, 226, 234), False)); y += fs + 4
                    y += 4
                elif kind == "kv":
                    if len(b[2]) <= 16:                            # short value: keep it on one line
                        ops.append(("t", b[1], y, fs + 1, (151, 188, 211), True))
                        ops.append(("tx", b[2], y, fs + 1, TEXT, False, 110)); y += fs + 7
                    else:
                        ops.append(("t", b[1], y, fs + 1, (151, 188, 211), True)); y += fs + 5
                        for ln in wrap(b[2], fs, 262):
                            ops.append(("t", ln, y, fs, (219, 226, 234), False)); y += fs + 4
                        y += 3
                elif kind == "cost":
                    ops.append(("cost", b[1], y)); y += 24
                else:
                    y += 8
            if y < 600:
                break
        r = pygame.Rect(x, 40, 292, min(660, y - 20))
        sh = pygame.Surface((r.w + 14, r.h + 14), pygame.SRCALPHA)
        pygame.draw.rect(sh, (0, 0, 0, 110), sh.get_rect(), border_radius=14)
        c.blit(sh, (r.x - 3, r.y))
        pygame.draw.rect(c, (24, 34, 47), r, border_radius=10)
        pygame.draw.rect(c, (102, 127, 151), r, 2, border_radius=10)
        pygame.draw.rect(c, (34, 48, 64), pygame.Rect(r.x + 4, r.y + 4, r.w - 8, 42), border_radius=7)
        text(c, title, (r.x + 16, r.y + 12), 21, TEXT, True, shadow=False)
        for op in ops:
            if op[0] == "t":
                text(c, op[1], (r.x + 16, r.y + op[2] - 40 + 6), op[3], op[4], op[5], shadow=False)
            elif op[0] == "tx":
                text(c, op[1], (r.x + 16 + op[6], r.y + op[2] - 40 + 6), op[3], op[4], op[5], shadow=False)
            elif op[0] == "rule":
                yy = r.y + op[1] - 40 + 3
                pygame.draw.line(c, (77, 98, 119), (r.x + 14, yy), (r.right - 14, yy), 1)
            else:
                art.draw_cost(c, (r.x + 16, r.y + op[2] - 40 + 4), op[1], 18)

    def draw_over(self):
        c = self.canvas
        dim = pygame.Surface((W, H), pygame.SRCALPHA)
        dim.fill((6, 8, 8, 175))
        c.blit(dim, (0, 0))
        w = self.s.winner
        msg = "Draw" if w == -1 else (("Victory!" if w == self.view else "Defeat") if self.human[self.view] and not self.hotseat else f"Player {w + 1} wins")
        col = GOLD_L if msg == "Victory!" or "wins" in msg else (RED if msg == "Defeat" else TEXT)
        art.add_glow(c, (W / 2, 300), col, 260, 0.35)
        text(c, msg, (W / 2, 300), 70, col, True, "center")
        text(c, "R: rematch      Esc: menu", (W / 2, 372), 22, TEXT, False, "center")

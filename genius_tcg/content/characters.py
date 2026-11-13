"""The 10 launch characters. Skill numbers are first-pass (verified in milestone 3)."""
from engine.core import (Cost, PHYSICAL, CRYO, HYDRO, PYRO, ELECTRO, ANEMO, GEO)
from engine.registry import CHAR_DEFS, CharDef, SkillDef, register


def _seq(*steps):
    def run(ctx):
        for st in steps:
            st(ctx)
    return run


dmg = lambda n, t: (lambda c: c.damage(n, t))
pierce = lambda n: (lambda c: c.piercing_others(n))
summon = lambda nm: (lambda c: c.summon(nm))
combat = lambda nm: (lambda c: c.combat_status(nm))
self_status = lambda nm: (lambda c: c.char_status(nm))
foe_status = lambda nm: (lambda c: c.foe_char_status(nm))
swap_foe = lambda c: c.force_switch_foe()


class _Recorder:
    """Stands in for the effect context to turn an effect into readable text."""

    def __init__(self):
        self.parts = []

    def damage(self, n, dtype):
        self.parts.append(f"Deal {n} {dtype} DMG.")

    def piercing_others(self, n):
        self.parts.append(f"{n} Piercing DMG to the other enemy characters.")

    def summon(self, name):
        self.parts.append(f"Summon {name}.")

    def combat_status(self, name):
        self.parts.append(f"Create {name}.")

    def char_status(self, name, idx=None):
        self.parts.append(f"Gain {name}.")

    def foe_char_status(self, name):
        self.parts.append(f"Target gains {name}.")

    def force_switch_foe(self):
        self.parts.append("The enemy must switch character.")


def describe(effect):
    r = _Recorder()
    effect(r)
    return " ".join(r.parts)


def char(name, element, weapon, max_energy, normal, skill, burst, normal_type=PHYSICAL, normal_dmg=2):
    """normal / skill / burst = (skill name, cost, effect steps...)"""
    def mk(kind, spec):
        nm, cost, *steps = spec
        run = _seq(*steps)
        return SkillDef(nm, kind, cost, run, describe(run))
    skills = (mk("normal", (normal[0], Cost(element, 1, 2), dmg(normal_dmg, normal_type))),
              mk("skill", skill), mk("burst", burst))
    return register(CHAR_DEFS, CharDef(name, element, weapon, max_energy, skills))


char("Keqing", ELECTRO, "Sword", 3, ("Yunlai Swordsmanship",),
     ("Stellar Restoration", Cost(ELECTRO, 3), dmg(3, ELECTRO)),
     ("Starward Sword", Cost(ELECTRO, 3, 0, 3), dmg(4, ELECTRO), pierce(3)))

char("Fischl", ELECTRO, "Bow", 3, ("Bolts of Downfall",),
     ("Nightrider", Cost(ELECTRO, 3), dmg(1, ELECTRO), summon("Oz")),
     ("Midnight Phantasmagoria", Cost(ELECTRO, 3, 0, 3), dmg(4, ELECTRO), pierce(2)))

char("Diluc", PYRO, "Claymore", 3, ("Tempered Sword",),
     ("Searing Onslaught", Cost(PYRO, 3), dmg(3, PYRO)),
     ("Dawn", Cost(PYRO, 4, 0, 3), dmg(8, PYRO), self_status("Pyro Infusion")))

char("Bennett", PYRO, "Sword", 2, ("Strike of Fortune",),
     ("Passion Overload", Cost(PYRO, 3), dmg(3, PYRO)),
     ("Fantastic Voyage", Cost(PYRO, 4, 0, 2), dmg(2, PYRO), combat("Inspiration Field")))

char("Kaeya", CRYO, "Sword", 2, ("Ceremonial Bladework",),
     ("Frostgnaw", Cost(CRYO, 3), dmg(3, CRYO)),
     ("Glacial Waltz", Cost(CRYO, 3, 0, 2), dmg(1, CRYO), summon("Icicle")))

char("Ganyu", CRYO, "Bow", 2, ("Liutian Archery",),
     ("Trail of the Qilin", Cost(CRYO, 3), dmg(1, CRYO), combat("Ice Lotus")),
     ("Celestial Shower", Cost(CRYO, 3, 0, 2), dmg(2, CRYO), pierce(2), summon("Sacred Cryo Pearl")))

char("Xingqiu", HYDRO, "Sword", 2, ("Guhua Style",),
     ("Fatal Rainscreen", Cost(HYDRO, 3), dmg(2, HYDRO), combat("Rain Sword")),
     ("Raincutter", Cost(HYDRO, 3, 0, 2), dmg(1, HYDRO), combat("Rainbow Bladework")))

char("Mona", HYDRO, "Catalyst", 3, ("Ripple of Fate",),
     ("Mirror Reflection of Doom", Cost(HYDRO, 3), dmg(1, HYDRO), combat("Reflection")),
     ("Stellaris Phantasm", Cost(HYDRO, 3, 0, 3), dmg(4, HYDRO)),
     normal_type=HYDRO, normal_dmg=1)

char("Sucrose", ANEMO, "Catalyst", 2, ("Wind Spirit Creation",),
     ("Astable Anemohypostasis", Cost(ANEMO, 3), dmg(3, ANEMO), swap_foe),
     ("Forbidden Creation", Cost(ANEMO, 3, 0, 2), dmg(1, ANEMO), summon("Large Wind Spirit")),
     normal_type=ANEMO, normal_dmg=1)

char("Zhongli", GEO, "Polearm", 3, ("Rain of Stone",),
     ("Dominus Lapidis", Cost(GEO, 3), dmg(1, GEO), summon("Stone Stele"), combat("Jade Shield")),
     ("Planet Befall", Cost(GEO, 3, 0, 3), dmg(3, GEO), foe_status("Petrified")))

ROSTER = list(CHAR_DEFS)

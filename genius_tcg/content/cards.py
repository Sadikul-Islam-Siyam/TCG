"""Action cards. Names are real; effect numbers marked 'approx' are placeholders until
checked against official data."""
from engine.core import Cost, OMNI, PYRO, HYDRO, CRYO, ELECTRO
from engine.registry import CARD_DEFS, CardDef, register
from engine.rules import Ctx  # noqa: F401  (type hint only)


def card(name, kind, cost, **kw):
    return register(CARD_DEFS, CardDef(name, kind, cost, **kw))


# ---- events (universal)
card("Sweet Madame", "event", Cost(), needs_char=True, play=lambda c, t: c.heal(1, t))
card("Mondstadt Hash Browns", "event", Cost(unaligned=1), needs_char=True, play=lambda c, t: c.heal(2, t))
card("Strategize", "event", Cost(unaligned=1), play=lambda c, t: c.draw(2))
card("Changing Shifts", "event", Cost(), play=lambda c, t: c.combat_status("Changing Shifts"))
card("Leave It to Me!", "event", Cost(), play=lambda c, t: c.combat_status("Leave It to Me!"))
card("Lotus Flower Crisp", "event", Cost(unaligned=1), play=lambda c, t: c.combat_status("Lotus Shield"))  # approx
card("Starsigns", "event", Cost(unaligned=2), play=lambda c, t: c.gain_energy(1))                          # approx

# ---- supports
card("Paimon", "support", Cost(unaligned=3), usages=2, action_start=lambda c: c.gain_dice(2, OMNI))
card("Liyue Harbor Wharf", "support", Cost(unaligned=2), usages=2, end_phase=lambda c: c.draw(2))
card("Wangshu Inn", "support", Cost(unaligned=2), usages=2, end_phase=lambda c: c.heal_most_injured(2))

# ---- weapons (one basic weapon per weapon type) and an artifact
for _name, _type in (("Traveler's Handy Sword", "Sword"), ("Raven Bow", "Bow"),
                     ("White Iron Greatsword", "Claymore"), ("White Tassel", "Polearm"),
                     ("Magic Guide", "Catalyst")):
    card(_name, "weapon", Cost(unaligned=2), weapon=_type, status=_name)
card("Gambler's Earrings", "artifact", Cost(unaligned=2), status="Gambler's Earrings")

# ---- elemental resonance (needs 2 characters of that element) — approx effects
card("Elemental Resonance: Woven Thunder", "event", Cost(ELECTRO, 1), resonance=ELECTRO,
     play=lambda c, t: c.gain_energy(1))
card("Elemental Resonance: Fervent Flames", "event", Cost(PYRO, 1), resonance=PYRO,
     play=lambda c, t: c.combat_status("Fervent Flames"))
card("Elemental Resonance: Soothing Waters", "event", Cost(HYDRO, 1), resonance=HYDRO,
     play=lambda c, t: c.heal(2))
card("Elemental Resonance: Shattering Ice", "event", Cost(CRYO, 1), resonance=CRYO,
     play=lambda c, t: c.combat_status("Ice Shield"))

# ---- talents: (card, character, skill index used when equipped). Cost = that skill's cost.
for _card, _char, _skill, _cost in (
        ("Thundering Penance", "Keqing", 1, Cost(ELECTRO, 3)),
        ("Stellar Predator", "Fischl", 1, Cost(ELECTRO, 3)),
        ("Flowing Flame", "Diluc", 1, Cost(PYRO, 3)),
        ("Grand Expectation", "Bennett", 1, Cost(PYRO, 4)),
        ("Cold-Blooded Strike", "Kaeya", 1, Cost(CRYO, 3)),
        ("Undivided Heart", "Ganyu", 1, Cost(CRYO, 3)),
        ("The Scent Remained", "Xingqiu", 1, Cost(HYDRO, 3)),
        ("Prophecy of Submersion", "Mona", 1, Cost(HYDRO, 3)),
        ("Chaotic Entropy", "Sucrose", 1, Cost("Anemo", 3)),
        ("Dominance of Earth", "Zhongli", 1, Cost("Geo", 3))):
    card(_card, "talent", _cost, char=_char, skill=_skill, status=_card)


CARD_TEXT = {
    "Sweet Madame": "Heal a character for 1.",
    "Mondstadt Hash Browns": "Heal a character for 2.",
    "Strategize": "Draw 2 cards.",
    "Changing Shifts": "Your next character switch costs no dice.",
    "Leave It to Me!": "Your next switch is a Fast Action.",
    "Lotus Flower Crisp": "Create a 3-point shield this round.",
    "Starsigns": "Your active character gains 1 Energy.",
    "Paimon": "Start of each Action Phase: gain 2 Omni dice. (2 uses)",
    "Liyue Harbor Wharf": "End Phase: draw 2 cards. (2 uses)",
    "Wangshu Inn": "End Phase: heal your most injured character for 2. (2 uses)",
    "Traveler's Handy Sword": "A Sword user deals +1 damage with skills.",
    "Raven Bow": "A Bow user deals +1 damage with skills.",
    "White Iron Greatsword": "A Claymore user deals +1 damage with skills.",
    "White Tassel": "A Polearm user deals +1 damage with skills.",
    "Magic Guide": "A Catalyst user deals +1 damage with skills.",
    "Gambler's Earrings": "When you defeat an enemy character: gain 2 Omni dice. (once per round)",
    "Elemental Resonance: Woven Thunder": "Your active character gains 1 Energy. (needs 2 Electro characters)",
    "Elemental Resonance: Fervent Flames": "Your next skill deals +2 damage. (needs 2 Pyro characters)",
    "Elemental Resonance: Soothing Waters": "Heal your active character for 2. (needs 2 Hydro characters)",
    "Elemental Resonance: Shattering Ice": "Create a 1-point shield for 2 rounds. (needs 2 Cryo characters)",
    "Thundering Penance": "Equip, then use Stellar Restoration. Physical damage becomes Electro.",
    "Stellar Predator": "Equip, then use Nightrider. After a Normal Attack with Oz out: 2 Electro damage.",
    "Flowing Flame": "Equip, then use Searing Onslaught. Skill deals +1 damage.",
    "Grand Expectation": "Equip, then use Passion Overload. Burst deals +1 damage.",
    "Cold-Blooded Strike": "Equip, then use Frostgnaw. After the skill, heal 2.",
    "Undivided Heart": "Equip, then use Trail of the Qilin. Skill deals +1 damage.",
    "The Scent Remained": "Equip, then use Fatal Rainscreen. Normal Attack deals +1 damage.",
    "Prophecy of Submersion": "Equip, then use Mirror Reflection of Doom. Burst deals +1 damage.",
    "Chaotic Entropy": "Equip, then use Astable Anemohypostasis. Skill deals +1 damage.",
    "Dominance of Earth": "Equip, then use Dominus Lapidis. Skill deals +1 damage.",
}
for _n, _t in CARD_TEXT.items():
    CARD_DEFS[_n].text = _t


def starter_deck():
    """30 arbitrary cards for engine tests (not a legal deck; see content.presets)."""
    return (["Sweet Madame"] * 8 + ["Mondstadt Hash Browns"] * 8 +
            ["Strategize"] * 8 + ["Paimon"] * 6)

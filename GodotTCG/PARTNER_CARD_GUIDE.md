# Custom Card & Character Authoring Guide

The engine, UI, AI, and Deck Builder are ready. All characters, **Equipment / Utility** action cards, team presets, and statuses are loaded directly from the JSON files in `data/` — no GDScript code edits needed.

---

## 1. Folder Layout

- `data/characters.json` — Playable character cards (**Aang, Zuko, Katara, Azula, Toph, Iroh** — each with **Normal**, **Skill**, and **Ult**).
- `data/action_cards.json` — 15 action cards (**6 Character Equipment** + **9 Utility** cards).
- `data/statuses.json` — Reusable Buff, Shield, Equipment, Carryover, and Control (`Stunned`, `Frozen`, `Petrified`) statuses.
- `data/presets.json` — Starter 3-character preset teams (`Team Avatar`, `Fire Nation Royals`, `Lotus & Rebels`) and AI/Autofill priority weights.
- `assets/characters/` — Character portrait images (`.png`, `.jpg`, `.jpeg`, or `.webp`) named `<Character Name>.png` / `.jpg` (for example `assets/characters/Aang.png`, `assets/characters/Zuko.jpg`). If omitted, procedural art is rendered automatically.
- `assets/cards/` — Optional custom action card artwork named `<Card Name>.png`. If omitted, Equipment / Utility emblems are rendered automatically.

> Deck Rules: `DECK_SIZE = 20`, `MAX_COPIES = 2` (at most 1 duplicate copy of any action card). Active dice pool rolls **Hydro, Pyro, Electro, Anemo, Geo** (`7/40` each) and **Omni** (`1/8`); **Cryo** is excluded from dice rolls.

---

## 2. Adding or Editing Characters (`data/characters.json`)

Each character has `hp: 10`, `max_energy: 1`, and 3 skills (`normal`, `skill`, `burst` / Ult):
- **Normal Attack:** `1 matching + 2 any` (`Physical`)
- **Elemental Skill:** `2 matching + 1 any` (`Elemental`)
- **Ultimate (`burst`):** `3 matching + 1 Energy` (`Elemental`)

```json
{
  "name": "Aang",
  "element": "Anemo",
  "hp": 10,
  "max_energy": 1,
  "skills": [
    {
      "name": "Air Jab",
      "kind": "normal",
      "cost": { "element": "Anemo", "n": 1, "unaligned": 2, "energy": 0 },
      "steps": [{ "op": "damage", "amount": 2, "element": "Physical" }]
    },
    {
      "name": "Air Gust",
      "kind": "skill",
      "cost": { "element": "Anemo", "n": 2, "unaligned": 1, "energy": 0 },
      "steps": [{ "op": "damage", "amount": 2, "element": "Anemo" }]
    },
    {
      "name": "Avatar Cleansing",
      "kind": "burst",
      "cost": { "element": "Anemo", "n": 3, "unaligned": 0, "energy": 1 },
      "steps": [
        { "op": "damage", "amount": 4, "element": "Anemo" },
        { "op": "clear_self_aura" }
      ]
    }
  ]
}
```

---

## 3. Adding Equipment & Utility Cards (`data/action_cards.json`)

### Equipment Card (character-assigned, Same-type or Any-type dice cost)
```json
{
  "name": "Aang's Glider Staff",
  "kind": "weapon",
  "role": "equipment",
  "char_name": "Aang",
  "status": "Equip +1 DMG",
  "cost": { "element": "", "n": 2, "unaligned": 0 },
  "use_target": true,
  "text": "Equip to Aang: Aang's attacks deal +1 DMG."
}
```
- Setting `"element": ""` and `"n": 2` enforces **2 dice of the same element** (Omni dice act as wildcards).
- Setting `"char_name"` restricts both deck building and in-match targeting to that specific character.

### Utility Card
```json
{
  "name": "Dual Character Healing",
  "kind": "event",
  "role": "utility",
  "cost": { "n": 0, "unaligned": 1 },
  "use_target": false,
  "text": "Heal the most damaged character and your active character for 1 HP each.",
  "steps": [{ "op": "heal_dual", "amount": 1 }]
}
```

---

## 4. Available Effect Step Operations (`steps`)

| `op` | Fields | Effect |
| --- | --- | --- |
| `damage` | `amount`, `element` | Deals `amount` elemental/Physical damage to foe active character. |
| `piercing_others` | `amount` | Deals `amount` Piercing damage (no reactions, ignores Shield) to all standby foe characters. |
| `clear_self_aura` | — | Removes any elemental aura currently on the active character. |
| `heal` | `amount` | Heals the targeted ally (or active character) for `amount` HP. |
| `heal_all` | `amount` | Heals every living party member by `amount` HP (adds `+2` during Katara's Ult if `Spirit Water` is equipped). |
| `heal_dual` | `amount` | Heals the most damaged living ally by `amount` HP and the active character by `amount` HP. |
| `heal_most_injured` | `amount` | Heals the most injured living ally for `amount` HP. |
| `reroll_off_element` | — | Automatically rerolls all non-matching, non-Omni dice. |
| `swap_cards` | `amount` | Swaps up to `amount` hand cards with the deck (interactive selector for human players, smart auto-pick for AI). |
| `gain_active_dice` | `amount` | Gains `amount` dice matching the active character's element. |
| `convert_to_omni` | `amount` | Converts up to `amount` non-Omni dice into Omni Dice. |
| `combat_status` | `status` | Adds a team-wide status (e.g. `"Shield +2"`, `"Attack +1"`, `"Dice Carryover"`). |
| `char_status` | `status` | Adds a status to your active/targeted character. |
| `foe_char_status` | `status` | Adds a status to the enemy active character (e.g. `"Stunned"`, `"Frozen"`, `"Petrified"`). |
| `force_switch_foe` | — | Forces the opponent to switch to their next character. |
| `draw` | `amount` | Draws `amount` action cards. |
| `gain_energy` | `amount` | Active/targeted character gains `amount` Energy. |
| `gain_dice` | `amount`, `element` | Gains `amount` dice of `element` (e.g. `"Omni"`, `"Pyro"`). |

---

## 5. Testing Your Changes

Run Godot's JSON card validator and full regression test suite from PowerShell inside `GodotTCG/`:

```powershell
& "$env:USERPROFILE\OneDrive\Desktop\Godot_v4.7.2-stable_win64_console.exe" --headless --path "." -- --validate-data --quit-after-tests
& "$env:USERPROFILE\OneDrive\Desktop\Godot_v4.7.2-stable_win64_console.exe" --headless --path "." -- --run-tests --quit-after-tests
```

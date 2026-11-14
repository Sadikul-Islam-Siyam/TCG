# Custom Card & Character Authoring Guide

The engine, UI, AI, and Deck Builder are ready. All custom characters, simple **Heal / Buff** action cards, team presets, and buff statuses are loaded directly from the JSON files in `data/` — no GDScript code edits needed.

---

## 1. Folder Layout

- `data/characters.json` — Playable character cards (each with **Normal**, **Skill**, and **Ult**).
- `data/action_cards.json` — Simple action cards (**Heal**, **Buff**, Draw, Energy, Shield).
- `data/statuses.json` — Reusable Buff, Shield, and Control statuses referenced by cards/skills.
- `data/presets.json` — Starter 3-character preset teams and AI/Autofill priority weights.
- `assets/characters/` — Optional custom portrait images (`.png`, `.jpg`, `.jpeg`, or `.webp`) named `<Character Name>.png` (for example `assets/characters/Pyro Vanguard.png`). If omitted, procedural art is rendered automatically.
- `assets/cards/` — Optional custom action card artwork (`.png`, `.jpg`, `.jpeg`, or `.webp`) named `<Card Name>.png` (for example `assets/cards/Major Heal.png`). If omitted, clean Heal / Buff emblems are rendered automatically.

> Keep at least **3 characters** in `characters.json` and enough action cards so `card_count * MAX_COPIES >= DECK_SIZE` (defaults: `DECK_SIZE = 12`, `MAX_COPIES = 3`, so at least **4 unique action cards**).

---

## 2. Adding or Editing Characters (`data/characters.json`)

Each character needs 3 skills with `kind`: `"normal"`, `"skill"`, and `"burst"` (displayed as **Ult** in-game):

```json
{
  "name": "My Hero",
  "element": "Pyro",
  "hp": 10,
  "max_energy": 2,
  "skills": [
    {
      "name": "Quick Slash",
      "kind": "normal",
      "cost": { "element": "Pyro", "n": 1, "unaligned": 2, "energy": 0 },
      "steps": [
        { "op": "damage", "amount": 2, "element": "Physical" }
      ]
    },
    {
      "name": "Fire Wave",
      "kind": "skill",
      "cost": { "element": "Pyro", "n": 3, "unaligned": 0, "energy": 0 },
      "steps": [
        { "op": "damage", "amount": 3, "element": "Pyro" }
      ]
    },
    {
      "name": "Phoenix Ult",
      "kind": "burst",
      "cost": { "element": "Pyro", "n": 3, "unaligned": 0, "energy": 2 },
      "steps": [
        { "op": "damage", "amount": 5, "element": "Pyro" },
        { "op": "combat_status", "status": "Attack +1" }
      ]
    }
  ]
}
```

Valid `element` values: `"Pyro"`, `"Hydro"`, `"Cryo"`, `"Electro"`, `"Anemo"`, `"Geo"`.
For damage `element`, you can also use `"Physical"` or `"Piercing"`.

---

## 3. Adding Simple Action Cards (`data/action_cards.json`)

Set `"kind": "event"` and `"role": "heal"` or `"buff"` (controls the Deck Builder filter tabs and card icon):

```json
{
  "name": "Healing Herb",
  "kind": "event",
  "role": "heal",
  "cost": { "n": 0, "unaligned": 1 },
  "use_target": true,
  "text": "Heal a chosen character for 2 HP.",
  "steps": [
    { "op": "heal", "amount": 2 }
  ]
}
```

- Set `"use_target": true` when the player clicks a character to target (e.g., healing a specific ally).
- Set `"use_target": false` for immediate global/active buffs (`Attack +1`, `Shield +2`, `draw`, `gain_energy`, `heal_most_injured`, `gain_dice`).
- For elemental-costed cards, include `"element": "Pyro"` and `"n": 1` in `"cost"`. For zero-cost cards, use `{ "n": 0, "unaligned": 0 }`.

---

## 4. Available Effect Step Operations (`steps`)

| `op` | Fields | Effect |
| --- | --- | --- |
| `damage` | `amount`, `element` | Deals `amount` elemental/Physical damage to foe active character. |
| `piercing_others` | `amount` | Deals `amount` Piercing damage (ignores Shield) to all standby foe characters. |
| `heal` | `amount` | Heals the targeted ally (or active character) for `amount` HP. |
| `heal_most_injured` | `amount` | Heals the most injured living ally for `amount` HP. |
| `combat_status` | `status` | Adds a team-wide status (e.g. `"Shield +2"`, `"Attack +1"`, `"Next Attack +2"`). |
| `char_status` | `status` | Adds a status to your active/targeted character. |
| `foe_char_status` | `status` | Adds a status to the enemy active character (e.g. `"Frozen"`, `"Petrified"`). |
| `force_switch_foe` | — | Forces the opponent to switch to their next character. |
| `draw` | `amount` | Draws `amount` action cards. |
| `gain_energy` | `amount` | Active/targeted character gains `amount` Energy. |
| `gain_dice` | `amount`, `element` | Gains `amount` dice of `element` (e.g. `"Omni"`, `"Pyro"`). |

---

## 5. Custom Buff Status Rules (`data/statuses.json`)

The rules engine parses flexible buff strings in `"outgoing_rule"` automatically — no GDScript needed:

- `"bonus_any_N"` — All skills (`normal`, `skill`, `burst`) deal `+N` DMG while active.
- `"bonus_normal_N"` / `"bonus_skill_N"` / `"bonus_burst_N"` — Only that skill kind deals `+N` DMG.
- `"bonus_next_any_N"` / `"bonus_next_normal_N"` / `"bonus_next_skill_N"` / `"bonus_next_burst_N"` — Deals `+N` DMG once and consumes 1 usage.

Set `"usages"` (`-1` for unlimited within `"duration"` rounds, or `1`, `2`, ...) and `"duration"` (`1` = expires at End Phase, `-1` = no round limit).

---

## 6. Testing Your Changes

Run Godot's JSON card validator from PowerShell inside the project root after editing or replacing any characters, action cards, statuses, or presets:

```powershell
& "$env:USERPROFILE\OneDrive\Desktop\Godot_v4.7.2-stable_win64_console.exe" --headless --path "." -- --validate-data --quit-after-tests
```

This checks every character, skill, action card step, status reference, preset team, starter deck, and AI deck generation against your JSON files.

> Note: `--run-tests --quit-after-tests` runs the full 117-test engine regression suite built around the starter roster/cards (`Pyro Vanguard`, `Power Boost`, etc.); use `--validate-data` once you customize or replace starter cards.

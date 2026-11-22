# Resonance (CSE 3210) — Godot 4 Card Game

A 3v3 elemental tactical card game built with Godot 4.7 featuring 6 Avatar characters (**Aang, Zuko, Katara, Azula, Toph, Iroh**), 15 Equipment & Utility action cards, a Deck Builder, and multi-algorithm AI opponents (Fuzzy Logic, CSP Dice Payment, A* Lethal Planner, Alpha-Beta Search, and Information-Set MCTS).

## How to Run

1. Open **Godot 4.7+** and import/open `project.godot`, then press **F5** (Play).
2. Or run from PowerShell:

```powershell
& "$env:USERPROFILE\OneDrive\Desktop\Godot_v4.7.2-stable_win64_console.exe" --path "."
```

## Card & Character Data

See [PARTNER_CARD_GUIDE.md](PARTNER_CARD_GUIDE.md) for the complete JSON guide:

- `data/characters.json` — 6 Playable Avatar characters (Normal, Skill, and Ult; `max_energy = 1`)
- `data/action_cards.json` — 6 Character Equipment cards & 9 Utility action cards (`DECK_SIZE = 20`, `MAX_COPIES = 2`)
- `data/statuses.json` — Buff, Shield, Equipment, Carryover, and Control (`Stunned`, `Frozen`, `Petrified`) statuses
- `data/presets.json` — 3 Starter preset teams (`Team Avatar`, `Fire Nation Royals`, `Lotus & Rebels`) & AI deck priorities
- `assets/characters/` & `assets/cards/` — Character portraits and optional custom card artwork

## Validating & Testing

```powershell
& "$env:USERPROFILE\OneDrive\Desktop\Godot_v4.7.2-stable_win64_console.exe" --headless --path "." -- --validate-data --quit-after-tests
& "$env:USERPROFILE\OneDrive\Desktop\Godot_v4.7.2-stable_win64_console.exe" --headless --path "." -- --run-tests --quit-after-tests
```

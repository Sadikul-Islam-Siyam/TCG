# Resonance (CSE 3210) — Godot 4 Card Game

A simplified 3v3 elemental tactical card game built with Godot 4.7. The core game engine, UI board, Deck Builder, and AI opponents are complete and data-driven so characters and cards can be authored purely through JSON.

## How to Run

1. Open **Godot 4.7+** and import/open `project.godot`, then press **F5** (Play).
2. Or run from PowerShell:

```powershell
& "$env:USERPROFILE\OneDrive\Desktop\Godot_v4.7.2-stable_win64_console.exe" --path "."
```

## Adding Custom Cards & Characters

See [PARTNER_CARD_GUIDE.md](PARTNER_CARD_GUIDE.md) for the complete JSON guide:

- `data/characters.json` — Playable characters (Normal, Skill, and Ult)
- `data/action_cards.json` — Heal & Buff action cards
- `data/statuses.json` — Reusable Buff, Shield, and Control statuses
- `data/presets.json` — Starter 3-character preset teams & AI deck priorities
- `assets/characters/` & `assets/cards/` — Optional custom artwork (`.png`, `.jpg`, `.jpeg`, `.webp`)

## Validating Custom Cards

After editing JSON files, run the custom data validator:

```powershell
& "$env:USERPROFILE\OneDrive\Desktop\Godot_v4.7.2-stable_win64_console.exe" --headless --path "." -- --validate-data --quit-after-tests
```

# Genius Invokation TCG clone (Python / Pygame) — fan project, non-commercial

Status: **Milestones 1 to 3 done**, **Milestones 1-5 done** (engine, content, Pygame UI, deck builder, AI suite).
Visual overhaul done (parchment cards, gold frames, animated hand). Next: sound, replays, more AI tuning.

## Run
    pip install pygame-ce pytest
    python main.py                 # main menu
    python main.py --mode hvai --ai hard   # skip the menu, pick AI level (also hvh, aivai; --decks 0 3, --seed N)
    pip install pytest
    python -m pytest -q          # 77 tests
    python simulate.py 300 1     # 300 random AI-vs-AI games, prints reaction stats

## Layout
    engine/   core.py dice.py registry.py model.py rules.py csp.py deck.py   (no UI imports)
    content/  statuses.py characters.py cards.py presets.py   (10 characters, 29 cards, 6 preset decks)
    ui/       theme.py art.py fx.py match.py menu.py decks.py app.py store.py widgets.py
    tools/    ui_smoke.py ui_soak.py (headless UI tests + screenshots)
    ai/       players.py fuzzy.py evaluate.py search.py planner.py mcts.py world.py dicepay.py deckgen.py factory.py random_ai.py                                    (baseline; M5 adds the real AIs)
    tests/    test_engine.py

## Engine API
    s = rules.new_game(chars0, deck0, chars1, deck1, seed)
    rules.actor(s)            # who must act
    rules.legal_actions(s)    # list[Action]
    rules.apply_action(s, a)  # mutates; s.events = structured events for the UI to animate
    s.clone()                 # cheap copy for AI search

## Deck builder API (engine/deck.py)
    deck.validate_deck(chars, cards)           # list of rule violations, [] = legal
    deck.autofill(chars, partial, priority)    # CSP completes a partial deck to 30 cards
    deck.encode / deck.decode                  # share codes

## Data status
- Dice: Omni 1/8 (as in the original); the 6 elements share the rest (7/48 each).
- Confirmed against card sites: Keqing and Fischl bursts (3 element + 3 energy), Fischl Nightrider/Oz and
  Stellar Predator, Ganyu burst (3 Cryo + 2 energy), Bennett's Inspiration Field heal, Reflection.
- Still approximate (flagged with `approx` in content/cards.py): most skill damage numbers, 9 talent effects,
  the 4 resonance effects, Lotus Flower Crisp and Starsigns. Card names are real.
- Setup is processed sequentially (mulligan, then choose active); the UI will hide the first pick.
- A full summon zone replaces the oldest summon.

## Controls (match screen)
- Drag a card from your hand onto a character or the board to play it; drag it onto a die to tune that die.
- Click a skill button to attack (dice are paid automatically, or click dice first to choose them).
- Click a benched character to switch. Click End Round when done. H reveals hands in spectator mode.
- Setup: click cards to swap, then confirm; pick your starting character. Roll: click dice to reroll.

## Deck builder
Pick 3 characters, click cards to add (right click removes), Auto-fill completes the deck with the CSP solver.
Filters: category tabs, element, cost, name search, and 'fits deck only'. Save / Load / Share code / Import.
Decks are saved to ~/.genius_tcg/decks.json (override with the GENIUS_TCG_HOME environment variable).
Incomplete decks can be saved as drafts but only legal decks can be played.

## AI (milestone 5)
Levels: easy, normal, hard. All expose `choose(state) -> Action`, never modify the state, and never read the
opponent's hidden hand or any deck order (tests check this). AI moves run in a worker thread inside the UI.

| Technique | Where |
|---|---|
| Fuzzy logic (ai/fuzzy.py) | HP / energy / dice / hand become low-med-high terms; rules set aggression, defence, burst desire, tempo and the evaluation weights. Easy's main brain. |
| Adversarial search (ai/search.py) | Alpha-beta with iterative deepening; depth counts turn-ending moves so free cards cause no horizon effect. Normal. |
| Informed search (ai/planner.py) | A* over the actions of one turn to find the cheapest lethal line (f = g + h). Normal and Hard. |
| Monte Carlo (ai/mcts.py) | Information-set MCTS over sampled hidden cards, with alpha-beta shortlisting the root moves. Hard. |
| Constraint satisfaction (ai/dicepay.py, ai/deckgen.py, engine/deck.py) | Dice payment, AI deck building, deck auto-fill. |

Measured with `python tools/ai_tournament.py` (small samples, seats and decks swapped):
easy beat random 83% (24 games), normal 100% (24), hard 100% (16); normal beat easy 83% (24), hard beat easy 88% (16);
hard vs normal was 50% over 14 games, so no clear difference yet (more games and tuning planned for M6).

## Look, layout and pacing
- Fullscreen by default (1280x720 scaled to any screen). `--windowed` or F11 to switch. F = double game speed.
- Board is symmetrical like the original: supports | 3 characters | summons for each side, the opponent's row
  rotated 180 degrees, your dice tray bottom right, the opponent's dice count top left.
- Every move is presented in order: an announcement ribbon (who, which skill/card), the attack, the damage number,
  a reaction pill (e.g. MELT +2 damage), then a pause before the next move. Input is locked while a move is shown.
- Match start: coin toss. Then swap cards (one Confirm), pick a character, Round banner, Roll Phase (one Confirm
  rerolls and continues), Action Phase / End Phase banners.
- Everything is explained on hover: a large readable card for cards, a full panel for characters (HP, energy, aura,
  equipment, statuses, all skills) and for every icon. Auras, equipment and statuses are icons on the character card.
- Turn a card into a die by dragging it onto the dice tray (anywhere on it) or right-clicking it.
- A battle log on the left lists every action in plain text.

---
name: auto-battler-pivot
description: zorx is now an auto-battler (squad of 3 from 4 class cards, fully automatic wave fights on a floating goblin-camp island); full context in docs/handoff/auto_battler_handoff.md
metadata:
  type: project
---

Boss (2026-11-10/11) pivoted zorx to an auto-battler (TFT-like). The full decision log, current state, next steps and new-machine setup are in `docs/handoff/auto_battler_handoff.md`. Read it at session start along with PROGRESS.md.

- One shared body (test05 Studio character, `client/characters/studio05_character_model.gd`); a class = an animation set (`data/classes/<id>.json`). 4 classes: sword_shield, greatsword, longbow, magic. Only the `blade` weapon exists in the rules.
- Squad of 1-3 cards chosen from one class card per class (`logic/card_deck.gd`, `Profile.card_deck`); every card is customised separately (hair/outfit/eyes/skin/makeup; skills later).
- Fights: no manual control (`logic/auto_pilot.gd`), landscape small arena, 12 waves with the boss last (`data/journeys/goblin_waves.json`).
- The campfire hub is being replaced by the Class Card screen; the UI team builds it from `docs/ui/class_card_ui_handoff.md` (cartoon look; Boss rejected the brass look and the portrait layout).
- The repo moved to github.com/noofzaa-ai/game-05 (single fresh commit, no art_source/; the full history is in grislyhub/zorx). Work on branch `game05-main` → `origin/main`.

**Why:** Boss said "stop asking, I've explained enough": decide by sensible defaults and keep going; ask only for big irreversible choices.
**How to apply:** don't re-add manual controls, portals or old weapons; new classes and options are data files; hide (don't delete) old hub features until Boss says otherwise. See [[boss-communication-rules]].

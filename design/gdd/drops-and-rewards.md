# Drops and Rewards (end-of-run loot)

**Status**: Draft (standard rigor: Overview, Detailed Rules, Formulas, Edge Cases, Dependencies, Acceptance Criteria; Tuning Knobs kept short) · **Date**: 2026-11-11 · **Author**: economy-designer, for the PO/Boss
**Race gear (2026-11-13)**: a share of the dropped pieces become race set pieces; see 3.8 and `design/gdd/race-gear-sets.md` 3.12. · **Scope**: what a 12-wave goblin run (`data/journeys/goblin_waves.json`) pays out, where it lands, what the summary screen shows. Quests, the magic-class unlock and new stages are out of scope.
**Every number below is a PLACEHOLDER** until the Boss plays a run (project rule). Anything marked `OPEN` needs a Boss call; the doc states the default used meanwhile.

## 1. Overview

A run is one fight of 12 waves, the last a boss (Goblin Chief). Rewards are RPG-style and **permanent**: equipment pieces (existing 4 rarity tiers), fashion cosmetics, and boss drops. They are rolled by pure logic from the journey seed, collected into a **haul** during the run, and committed to the player's profile when the run ends, **win or lose** (loss keeps what was already earned; the boss reward needs the boss kill). Afterwards the loot lives in the stash and is worn from the class card screen; fashion goes into the wardrobe the card screen already dresses from.

Design intent, in economy terms: the faucet is small and steady (about 5 gear pieces per winning run) so every run ends with something to look at, with one big "boss moment" at the end (variable-ratio chase for legendaries, softened by a pity counter). There is no bag, no extraction, no loss of loot on defeat, so there is no loss aversion to manage, only anticipation.

## 2. What the code already supports (reuse, do not rebuild)

| Existing piece | What it does | Reuse |
|---|---|---|
| `logic/loot.gd` `Loot.roll_piece(rules, id, tier, level, weapon_types, rng)` | Builds one catalog piece of a given tier; only pieces with a model drop (`ItemCatalog.droppable`, gated by the catalog item's `drop_level`) | Yes, the core of every gear reward |
| `Loot._roll_tier(weights, rng)` | Weighted pick over the 4 tiers (private; make it public or copy 8 lines) | Yes |
| `data/loot/loot.json` + `logic/loot_data*.gd` | Per-monster tables: gold, materials, item chance, level-bracket tier weights | Pattern reused; its per-kill tables are NOT used for wave mode (see 3.1) |
| `data/items/rules.json` tiers | `normal / rare / epic / legendary` (1-4 substats, colors white/blue/purple/gold) | Yes, no new tiers |
| `data/items/catalog.json` | 52 droppable entries (`drop_level`), 150 matches of drop_level/set/slot keys | Yes; `Profile.ensure_starter_*` grants the starter sets already |
| `Journey.treasure_item` and `data.treasure.tier_weights` (rare 70 / epic 25 / legendary 5) | A guaranteed rare+ piece | Same numbers reused for the milestone chest |
| `Profile.stash` (`Inventory`), `Profile.equip_from_stash`, `unequip_to_stash`, `loadout` | Storage and wearing | Yes |
| `Run.death()` pattern | Secures loot even when the stash is full by raising `stash.capacity` | Same rule for the haul (no loss) |
| `Mall.owns(profile, part, id)` and `Profile.mall_owned` (`"part:id"` strings) | Fashion ownership | Fashion drops append the same key (no diamonds involved) |
| `logic/cosmetic_options.gd` parts `fashion`, `fashion_back` (data/cosmetics/*.json) | The fashion catalog | Fashion pool references ids that exist here. `fashion_hat` is deferred by the Boss (2026-10-23): never dropped |
| `game_sim._give_drop` + `Run.loot_into_bag` | Per-kill drop into a run bag (camp-era) | Not used in wave mode (3.1) |
| `client/journey_screen.gd` end states `WON/LOST/RETREATED/ABANDONED` | Ending screen, "back to cards" | Extended (section 5) |

Gaps found: (a) wave mode has no end-of-run reward at all; the over-screen shows only a one-line result. (b) `Profile.loadout` is one loadout for the player, not per class card (see OPEN Q2). (c) `Run` needs `CampData` (bag size from camp) which is being cut. (d) gold and materials have no confirmed sink once camp/shop are cut (see OPEN Q1).

## 3. Detailed Rules

### 3.1 Sources (per run)
1. **Wave drop**: after each wave is cleared (waves 1-11), one roll: with chance `p(wave)` a gear piece drops, tier from that wave bracket's weights.
2. **Milestone chests**: clearing wave 4 and wave 8 grants one guaranteed piece of tier rare or better. Wave 8's chest also has a fashion chance.
3. **Boss drop** (wave 12 boss killed): one guaranteed piece, epic or legendary; one fashion roll; a **first-clear** guaranteed fashion piece (once per journey per profile); optional boss `signature_items` (OPEN Q4).
4. **Per-kill drops are disabled in wave mode.** Otherwise the old `loot.json` item/gold/material rolls would double the faucet. Implementation: wave-mode skips `_give_drop` (one condition in `game_sim`), data stays untouched for the old road mode and tests.

Gold and materials: **not paid in v1** (no sink). The data shape keeps room for them (`extras`), see OPEN Q1.

### 3.2 Rarity tiers
Existing 4 tiers, weights as arrays indexed by tier `[normal, rare, epic, legendary]` (same convention as `loot.json`).

| Source | Tier weights `[N, R, E, L]` | Total | Notes |
|---|---|---|---|
| Wave drop, waves 1-4 | 70, 25, 5, 0 | 100 | chance per wave: 0.15 (w1-3), 0.20 (w4) |
| Wave drop, waves 5-8 | 45, 38, 14, 3 | 100 | chance 0.20 |
| Wave drop, waves 9-11 | 25, 40, 27, 8 | 100 | chance 0.25 |
| Milestone wave 4 | 0, 70, 25, 5 | 100 | guaranteed 1 piece; fashion chance 0 |
| Milestone wave 8 | 0, 55, 35, 10 | 100 | guaranteed 1 piece; fashion chance 0.15 |
| Boss | 0, 0, 80, 20 | 100 | guaranteed 1 piece; fashion chance 0.35; pity (3.4) |

Slot, weapon type, and catalog item are drawn by `Loot.roll_piece` from what the catalog allows at the item level (3.3). Accessories and fists never drop (existing rule). Weapon types are limited to the three launch classes' weapon types (blade, greatsword, longbow) so no drop is dead weight; magic weapons are excluded until the unlock exists (OPEN Q3).

### 3.3 Item level
`roll_piece` filters by catalog `drop_level <= level`. Each reward entry has `item_level`; default = the wave's stage `level` (1-4 in `goblin_waves.json`). Boss and milestone entries may raise it (placeholder: milestone 4 = 3, milestone 8 = 4, boss = 5) so late pieces are not limited to level-1 gear. **Before shipping, check how many catalog items are droppable at each level** (the catalog has `drop_level` on 52 entries; a tiny pool makes repeats too frequent).

### 3.4 Pity (floor)
Profile counter `boss_legendary_misses`: the boss piece is forced to legendary when the counter is >= `legendary_after` (3), i.e. at most the 4th winning boss kill. Reset to 0 on any legendary boss piece, +1 otherwise. Other legendaries (waves, chests) do not touch it. No ceiling mechanic needed (no duplicate gear is a problem: gear has no uniqueness).

### 3.5 Fashion
- Pool: `fashion_pool.fashion` and `fashion_pool.fashion_back` (ids from `data/cosmetics/fashion.json` and `fashion_back.json`). Never `fashion_hat`.
- A fashion roll succeeds with its chance, then picks uniformly among pool entries **not yet owned** (`Mall.owns` / `mall_owned`). If everything is owned the roll is replaced by one extra gear piece of the source's own tier weights (so the pool exhausting is a designed, visible end state, not a dead roll).
- Granting appends `"part:id"` to `profile.mall_owned`. It does not change equipped fashion; the player dresses it on the card screen. Fashion never changes stats or equipment identity (Boss rule 2026-10-23: fashion overlays equipment, thumbnails stay combat art).
- First-clear fashion: guaranteed, fixed id from data (`first_clear_fashion`), granted once; if already owned (e.g. bought in a mall), it falls back to the random unowned pick.

### 3.6 Timing and persistence
- Rewards are rolled when the wave is cleared (inside the journey, deterministic from the seed, independent of the combat RNG: `rng_for("wave_reward", wave)`), appended to `Journey.haul`, and shown only at the end.
- On `WON`: the full haul commits. On `LOST`: everything from waves already cleared commits; the wave in progress and the boss pay nothing. On `RETREATED/ABANDONED` (player leaves): same as `LOST`, nothing is forfeited (no bag any more).
- Commit is once-only (`haul.committed` flag saved in the journey), so a double "end run" never doubles loot. Online: the server rolls and commits when it saves the run result; the client only displays.
- Overflow: pieces never vanish. If the stash is full the commit raises `stash.capacity` (same as `Run.death()`); the card screen shows "stash over capacity" until the player discards.

### 3.7 Where loot lives
- **Gear**: `profile.stash`; worn via the class card screen's gear panel (`Profile.equip_from_stash`). Items keep their instance id, tier, substats, `item_id` (model/icon).
- **Fashion**: `profile.mall_owned`; selectable in the card's look editor (the part lists in `cosmetic_options` already filter by ownership where the mall exists; if not, card UI must filter by `Mall.owns`).
- The card screen shows a **NEW** badge on pieces from the last run until first viewed (client-only flag, `profile.new_item_ids`, optional).

### 3.8 Race gear pieces (as built 2026-11-13; rules owned by `design/gdd/race-gear-sets.md` 3.12)
Race pieces are not an extra source. After a gear piece has rolled its tier and slot it may **become** a race set piece: the same slot and tier, the race × class piece of one card of the squad that played (uniform pick). Data: `data/loot/race_drops.json`; rule: `logic/race_drops.gd`. It hooks in at three places:
- per-kill drops: `GameSim._give_drop`;
- the road treasure and wave chest: `Journey.treasure_drop`;
- the online wave chest: `server/rooms/room.gd`.

| Source (wave mode as built) | Race share by rolled tier |
|---|---|
| Kill drops, waves 1-4 | none |
| Kill drops, waves 5-8 | rare 0.30 |
| Kill drops, waves 9-11 | rare 0.40, epic 0.40 |
| Wave chest after wave 3 | rare 0.30 |
| Wave chests after waves 6, 9 | rare 0.50, epic 0.50 |
| Boss (`boss_types` kills: Goblin Chief) | rare 0.50, epic 0.50, **legendary 1.0** |

- **Gold race pieces come only from the boss**, and every boss legendary in a race slot (weapon, shirt, pants, armband, shoes) is a race piece. Wave and chest legendaries stay generic.
- White pieces never convert; the white race outfit is starter-only.
- The faucet size and the tier mix are unchanged; only the identity of some pieces changes.
- Determinism: own seeded generator per item id, so the same seed gives the same haul.
- Note: the build pays gear through per-kill drops (loot.json) and chests after waves 3/6/9, not yet through the wave/milestone/boss table of 3.1-3.4. When that table lands, the same shares apply to its sources (milestone = chest rows, boss piece = boss row).

## 4. Formulas

Let waves 1..11 have per-wave chance `p_w`; milestones `M = {4, 8}`; one boss piece.

- Expected gear pieces per winning run: `E_items = sum(p_w, w=1..11) + |M| + 1`.
  Worked: `3 * 0.15 + 0.20 (w4) + 4 * 0.20 + 3 * 0.25 = 0.45 + 0.20 + 0.80 + 0.75 = 2.20`; `E_items = 2.20 + 2 + 1 = 5.20`. If the run is lost at wave `k`: `sum(p_w, w<=k) + (k >= 4) + (k >= 8)`; e.g. lost at wave 6: `0.45 + 0.20 + 0.40 + 1 = 2.05` pieces, which is the intended consolation.
- Tier probability for a source: `P(t) = weight_t / sum(weights)`.
- Legendary per winning run: `E_leg = sum(p_w * L_w) + 0.05 + 0.10 + 0.20`.
  Wave part: `w5-8: 4 * 0.20 * 0.03 = 0.024`; `w9-11: 3 * 0.25 * 0.08 = 0.06`; so `E_leg = 0.084 + 0.35 = 0.434` before pity.
  P(at least one legendary) = `1 - 0.95 * 0.90 * 0.80 * 0.994^4 * 0.98^3 = 1 - 0.684 * 0.976 * 0.941 = 1 - 0.628 = 0.37` (chest 4, chest 8, boss, then waves 5-8 at 0.2*0.03 = 0.006 each, waves 9-11 at 0.25*0.08 = 0.02 each).
- Pity: boss legendary on win `k` of a streak: `0.2` for k=1..3, `1.0` at k=4. Expected winning boss kills per boss legendary: `1 + 0.8 + 0.64 + 0.512 = 2.95` (worst case 4). Without pity it is 5.0.
- Fashion per winning run (after the first clear): `P(>=1 roll hits) = 1 - (1 - 0.35)(1 - 0.15) = 0.4475`, so ~0.45 pieces/run. Because rolls pick only unowned entries, a pool of `N` is completed in about `N / 0.45` winning runs (N = 10 -> ~22 runs, plus the first-clear piece). The pool is a finite sink-less faucet: once complete the fashion faucet turns into extra gear (3.5).
- Gear stockpile over time: faucet 5.2 pieces/win vs sink = player discards (no automatic sink). After 20 wins ~104 pieces; the stash has finite capacity so the player must discard. **A salvage/refine sink is not designed here (OPEN Q1); until it exists the game relies on manual discard**, which is acceptable at hobby scope but is the main economy hole.
- Boss pity/legendary probabilities are all data (3.2, 3.4), so the table can be retuned without code.

## 5. End-of-run summary screen (`client/journey_screen.gd`, `over` states)

Display only; reads the committed haul from the result, never rolls.
1. **Header**: result text (existing), waves cleared `n/12`, "Boss defeated" marker.
2. **Boss drops row** (WON only): large tiles, tier-colored border (white/blue/purple/gold from `rules.json`), item icon from the catalog, name, slot. Legendary gets a stronger reveal (skippable; respects reduced-motion).
3. **Wave / chest drops**: a grid of tiles grouped by source ("Wave 4 chest", "Wave 8 chest", "Drops"). Each tile: icon, tier color, slot, main stat value, and an up/down arrow when its main stat beats what is worn in that slot (`Stats` totals; display only).
4. **Fashion row**: new cosmetics with a "NEW" badge and the part name; "First clear" tag where relevant.
5. **Footer counters**: `X pieces added to the stash (stash n/cap)`; warning line if over capacity; pity hint is NOT shown (keeps it honest but simple; OPEN: show "legendary guaranteed soon"?).
6. **Buttons**: "Back to the cards" (existing, `GameState.end_journey`) and "Equip now" which opens the card screen's gear panel focused on the best new upgrade. On `LOST`: same layout with only the earned items and the line "what you earned is kept". When the server has not saved yet, buttons stay disabled (existing behaviour).
UI rules: strings through the localization path, keyboard/gamepad focus, colorblind-safe (tier is also shown as text and icon frame shape, not color only).

## 6. Edge Cases

| Case | Rule |
|---|---|
| `roll_piece` finds no droppable item for a slot/level | existing fallback to `_plain_piece` only if catalog is empty; otherwise it picks another slot. Test must assert no null items. |
| Stash full at commit | capacity raised; never lost; card screen warns |
| Fashion pool fully owned | roll becomes an extra gear piece with that source's tier weights |
| `fashion_pool` id missing in `cosmetic_options` | skipped at load, error recorded (`errors`), run continues (same pattern as other loaders) |
| Player already owns the first-clear fashion | falls back to a random unowned pick; if none, an epic piece |
| Run ends twice / save retried | `haul.committed` prevents double grant |
| Loss before wave 4 | only the per-wave drops already earned; no chest |
| Boss killed but a squad member dies in the same tick | boss reward still pays (boss kill = WON) |
| Same seed, same run | identical haul (rolls depend only on seed + wave index + pity counter at start) |
| Pity counter at start differs between online/offline | counter lives in the profile (server-owned); client display only |
| Old profile without new fields | `boss_legendary_misses = 0`, `first_clears = {}` via `from_dict` defaults |
| Two-slot items (rings, earrings) | `Profile.equip_from_stash(slot_index)` handles; not special-cased here |
| Reward ids/tier index out of range | clamp to `rules.tiers.size() - 1` (existing behaviour in `_roll_item`) |

## 7. Dependencies

- `logic/loot.gd`, `logic/item_catalog.gd`, `logic/item_system.gd`, `logic/item_rules.gd`: gear creation (reused, depended on)
- `logic/journey.gd` / `journey_data.gd`: wave-clear hook, `Journey.haul`, saved in `to_dict/from_dict`
- `logic/profile.gd`: new fields `boss_legendary_misses`, `first_clears`; commit target `stash`, `mall_owned`
- `logic/mall.gd` (ownership key format only), `logic/cosmetic_options.gd` (fashion ids)
- `client/journey_screen.gd` (summary), class card screen (`client/card_deck_screen.gd`, gear panel + wardrobe filter)
- Pending: camp removal (stash capacity currently comes from `CampData`); `game_sim._give_drop` wave-mode skip
- `design/gdd/race-gear-sets.md` (3.12, 4.5): race piece shares per source, race from the squad, boss-only gold; `data/loot/race_drops.json`, `logic/race_drops.gd`
- Related GDD still to write: class card screen (gear panel), wave mode

## 8. Tuning Knobs (all in `data/loot/wave_rewards.json`)
Per-wave chances and tier weights, milestone waves, `item_level` per entry, boss tier weights, `legendary_after` pity, fashion chances, `fashion_pool`, `first_clear_fashion`, `signature_items`, `extras` (gold/materials, empty by default).

## 9. Minimal first implementation plan

**Data file `data/loot/wave_rewards.json`** (snake_case, `_comment` documents numbers, one file per journey id; `version` for schema breaks):
```json
{
  "version": 1,
  "journey": "goblin_waves",
  "_comment": "Tier weights are [normal, rare, epic, legendary]. Chances are 0..1 per wave. All values placeholders.",
  "wave_drops": [
    {"from_wave": 1, "to_wave": 3, "chance": 0.15, "tier_weights": [70, 25, 5, 0]},
    {"from_wave": 4, "to_wave": 4, "chance": 0.20, "tier_weights": [70, 25, 5, 0]},
    {"from_wave": 5, "to_wave": 8, "chance": 0.20, "tier_weights": [45, 38, 14, 3]},
    {"from_wave": 9, "to_wave": 11, "chance": 0.25, "tier_weights": [25, 40, 27, 8]}
  ],
  "milestones": [
    {"wave": 4, "pieces": 1, "item_level": 3, "tier_weights": [0, 70, 25, 5], "fashion_chance": 0.0},
    {"wave": 8, "pieces": 1, "item_level": 4, "tier_weights": [0, 55, 35, 10], "fashion_chance": 0.15}
  ],
  "boss": {
    "pieces": 1, "item_level": 5, "tier_weights": [0, 0, 80, 20],
    "pity": {"tier": "legendary", "after_misses": 3},
    "fashion_chance": 0.35,
    "first_clear_fashion": {"part": "fashion", "id": "<set by Boss/art>"},
    "signature_items": []
  },
  "fashion_pool": {"fashion": [], "fashion_back": []},
  "weapon_types": ["blade", "greatsword", "longbow"],
  "extras": {"gold": [0, 0], "materials": {}}
}
```
Rule-file check: ids in `fashion_pool` / `signature_items` must exist (loader validates, no orphan entries). Do not ship empty `fashion_pool`; fill from the real `data/cosmetics/*.json` lists (parity rule: never invent ids).

**Logic** (no nodes, no client):
- `logic/wave_rewards_data.gd` + `logic/wave_rewards_data_loader.gd` (same split as `loot_data*.gd`, `errors` array)
- `logic/wave_rewards.gd`: `static roll_wave(rules, data, wave, stage_level, rng)`, `roll_boss(rules, data, rng, pity_misses, owned_fashion)`, `commit(profile, haul)`. Calls `Loot.roll_piece` and a public tier-roll helper.
- `Journey`: on wave clear call `roll_wave`, append to `haul`; on end (WON/LOST/RETREATED/ABANDONED) call `commit` once; save/restore `haul`.
- `Profile`: add the two fields with defaults in `to_dict/from_dict`.
- Tests `tests/test_wave_rewards.gd`: determinism, tier weights sum, loss-at-wave-k counts, pity forces legendary on the 4th boss, no double commit, stash overflow raises capacity, fashion never repeats an owned id.

**Client**: `client/journey_screen.gd` over-state gets the summary (section 5), reads `haul` from the result; card screen gains a gear panel (stash list, equip/unequip, discard) and the wardrobe ownership filter. UI art for tier frames goes through the Codex image workflow (art team).

**Order**: data + loader + tests -> Journey hook + Profile fields -> summary screen -> card-screen gear panel -> fashion pool fill and balance pass.

## 10. Acceptance Criteria

1. A full simulated run (3 seeds) produces a haul of 4-7 gear pieces on a win with expected value inside 5.2 +/- 0.5 over 500 simulated seeds.
2. A run lost at wave 6 commits 1-4 pieces and no boss reward; nothing earned before the loss is lost.
3. Same seed + same profile pity state gives an identical haul.
4. The boss piece is epic or legendary every time; with pity counter 3 it is legendary 100%.
5. Over 10,000 simulated boss rolls, legendary share is 20% +/- 2% (pity off) and mean wins per legendary is 2.95 +/- 0.15 (pity on).
6. Ending a run twice, or reloading the saved result, never grants twice.
7. A full stash accepts the haul (capacity raised), no piece lost; the summary shows the warning.
8. Fashion drops never include an owned id or `fashion_hat`; with a fully owned pool the roll yields a gear piece.
9. Summary screen shows boss, chest, wave and fashion tiles with tier text + color, a better-than-worn marker, "Back to the cards" and "Equip now"; works with keyboard/gamepad; animation is skippable.
10. Loot appears afterwards in the card screen's gear panel and can be equipped; fashion appears in the look editor.
12. Race gear (3.8): over many seeds the race shares per source/tier match `data/loot/race_drops.json`; no wave/chest legendary is a race piece; every boss legendary in a race slot is one; races come only from the squad (tests/test_race_drops.gd).
11. Existing tests are unaffected (old-road mode and `loot.json` tables unchanged); full suite shows no new failures vs the baseline.

## 11. OPEN QUESTIONS (for the Boss, via PO)

**Q1. Gold and materials: do they still exist?** The camp, shop and bag are cut, so no sink exists; `data/items/shop.json` and `mall.gd` (diamonds) are the only old spenders.
- A. No gold/materials in v1; only gear and fashion (default used here). Zero inflation risk, simplest.
- B. Keep gold/materials, add a **salvage** sink: discard a gear piece for materials, spend materials/gold to refine (reuse existing refine/wear systems if they survive).
- C. Gold only as a score number on the summary (no spending).
Recommendation: A for v1, B later once the gear stockpile (5.2 pieces/win) becomes annoying.

**Q2. Is gear per player or per class card?** Today `Profile.loadout` is one set for the whole player; the cards only hold looks.
- A. One shared loadout for all 3 squad members (no schema change, default).
- B. One loadout per class card (clear fantasy: "my Great Sword's gear"; changes profile shape and server save).
- C. Shared armor, per-class weapon.
Recommendation: C (weapon type is class-bound anyway, armor stays easy). This changes the profile structure, so it is a Boss decision before the gear panel is built.

**Q3. Magic class drops before it unlocks?** Until the quest unlock, magic weapons should not drop (default: excluded).
- A. Exclude magic items until unlocked (default).
- B. Drop them, they wait in the stash, which doubles as a hint.
Recommendation: A (no dead drops).

**Q4. Boss-signature gear and first-clear fashion.** The Chief should drop something only it drops.
- A. A small set of Goblin Chief signature pieces (needs ids chosen from the catalog/sets or new art) in `signature_items`, e.g. 25% chance replacing the boss piece.
- B. Only generic epic/legendary pieces (default).
- C. Chief-themed fashion only.
Recommendation: A if the catalog already has a goblin-looking set (check `data/items/sets.json`); otherwise B now and A later.

**Q5. Relics.** `logic/relics.gd` and `Run.relic_loot` already give boss collectibles in the old flow. Fold them into the boss drop (a 4th reward kind) or leave them out of wave mode (default: left out)?
Recommendation: leave out until Boss confirms relics stay in the auto-battler.

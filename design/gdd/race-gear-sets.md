# Race Gear Sets (and the class starter kits that come first)

**Status**: Draft (standard rigor), implemented 2026-11-13 (d1c7569 + race drops) · **Date**: 2026-11-13 · **Author**: game-designer, for the PO/Boss
**Source decisions (Boss 2026-11-13, authoritative, not reopened here)**: (1) each race has its own armour set; anyone can wear any piece, but the **set option** works only when the card's race matches the set's race; (2) the set option **boosts that race's passive** for the card's class, data-only; (3) a separate look for every class × race (16), made by the Studio team; (4) race sets come in blue / purple / gold (`rare` / `epic` / `legendary`), gold drops **only from bosses**; (5) basic white **starter equipment for every class first**, implementable on its own; (6) **final shape (Boss 2026-11-13, supersedes the earlier draft wherever they differ)**: a race set = the race **weapon** + 4 armour (shirt, pants, armband, shoes) = 5 pieces, steps 2/4/5; the head/hat armour slot is **removed from the game**; any card can wear any race's pieces, the option needs a matching race; gold race pieces drop only from bosses; every class has an outfit per race (16 looks) made by the Studio team; a new card starts in its race's **white** outfit.
**Reads with**: `races-and-classes.md` (passives 3.4, vocabulary 3.6, caps 4.2-4.4), `skill-tree.md` (`cell_mod` 3.5, race branch 3.9, cell-mod math 4.6), `drops-and-rewards.md` (sources and tier weights 3.1-3.4).
**Every number is a PLACEHOLDER** until `tools/balance/class_sim.gd` measures it and the Boss plays it. HP is being rescaled by another agent, so every value here is a % or a multiplier, never an absolute HP number.

---

## 1. Overview

Two deliverables, in order:

**Part A, Starter kits (build first, stands alone).** Every class card starts wearing a full white (`normal`) kit: its class weapon plus the 4 armour slots (shirt, pants, armband, shoes), and the round shield for Sword & Shield. **As built (2026-11-13):** a new card wears the **white race outfit of its own race** (its 5 race pieces at `normal`, `data/items/starter_kits.json`), so the set option is live at white strength (`tier_mul` normal 0.75). Until the Studio files exist the pieces show the class starter look (fallback, `docs/art/race_gear_handoff.md` 4). Sections 3.1-3.4 below are the earlier plan, kept for history; where they mention a hat or 5 armour slots, read 4 armour slots.

**Part B, Race gear sets.** Four sets, one per race (`race_human`, `race_viking`, `race_elf`, `race_runeborn`). Each has 5 pieces: the race weapon of the class + shirt, pants, armband, shoes. They come in white (starter outfit only), blue, purple and gold. A piece always gives its normal main stat and substats to whoever wears it. The **set option** is extra: at 2, 4 and 5 pieces it strengthens the wearer's **race passive**, and it is written with the existing `cell_mod` vocabulary in data. It switches on only when the card's race equals the set's race. Each race set looks different on each class (16 looks). Gold race pieces drop only from the boss.

## 2. Player Fantasy

- **"Dressed as what I am" (Fantasy, Expression).** A Viking greatsword in Viking war gear fights *more* like a Viking: Berserker rage kicks in earlier and harder. The armour turns the race into a costume and an identity, not only a stat line.
- **A chase with a visible end (Achievement).** Blue pieces come early, purple mid-run, gold only from the Chief. "Two more gold Viking pieces" is a clear reason to run again (macro-loop).
- **A real choice (Autonomy, MDA Challenge-as-strategy).** A generic gear set gives flat stats to anyone. A race set gives a themed boost only to the matching race. A card can go full race set, mix 2 + 3 with a generic set, or wear the best raw stats. Switching race is free (races-and-classes.md 3.9), so a lucky gold Elf drop can pull a card toward Elf: the gear feeds back into the race choice.
- **Fair to everyone who plays a different race (Competence).** A mismatched piece is never dead: its stats still work. The item card says clearly why the option is off ("needs Viking").

## 3. Detailed Rules

### Part A: Starter kits

#### 3.1 What exists today (checked 2026-11-13)

| Piece | Today | Problem |
|---|---|---|
| `logic/profile.gd` `new_player` | Sword & Shield wears `blade_01` (tier 1 = **rare**), `scout_vest` -> `armor_ash_steel_shirt` (tier 2 = **epic**), `scout_boots` -> `armor_ash_steel_shoes` (tier 0) | Not white; only 3 slots; the shirt and shoes carry the `armor_ash_steel` set |
| `ensure_starter_cards` | Other classes get weapon `<family>_01` (rare), the same shirt (epic) and shoes (normal) | Every class's family is `blade`, so greatsword/longbow/magic hold a **sword item** |
| `ensure_starter_shields` | `round_shield` (normal) on Sword & Shield | OK, kept |
| `ensure_starter_weapons` | a spare `blade_01` (rare) in the stash | Blade only |
| `ensure_starter_armor` (`starter_armor_sets` in `data/items/sets.json`) | Puts all 15 **rare** pieces of Obsidian Heavy, Sun King Heavy and Ash Heavy into the stash | Makes any white starter kit obsolete on day one; heavy only, so it ignores light/cloth classes |
| `data/items/catalog.json` | weapons: `blade_01..07` only; armour: 45 pieces (obsidian/royal/ash × gold-or-steel/leather/cloth × 5 slots), all in a set; `round_shield` | **No greatsword, longbow or magic weapon items**; **no set-free armour** |
| `data/classes/*.json` `weapon_families` | `["blade"]` for all 4 (marked placeholder) | Must name each class's own family |
| Class armour look | `art/characters/studio05/v1111/outfits/armor_<class>.glb` (4 files) shown when `outfit` = `"none"` | OK, this is the starter look |
| "Aegis" set | Not a set. `aegis_*` ids are aliases in `data/items/armor_migration.json` that map to `armor_ash_steel_*` | The only live sets are the 9 in `sets.json` |

#### 3.2 The starter kit per class (all `normal` / white, race-neutral, `set: ""`)

| Class | Weapon (new catalog item) | Armour weight (`armor_class`) | Hat / Shirt / Pants / Armband / Shoes (new catalog items, set-free) | Offhand | Look on the body |
|---|---|---|---|---|---|
| sword_shield | `starter_blade` (family `blade`, reuses `weapon_blade_01` asset) | heavy | `starter_heavy_<slot>` (reuse `ash_steel` meshes/icons) | `round_shield` (existing) | `armor_sword_shield.glb` (class armour) |
| greatsword | `starter_greatsword` (family `greatsword`) | heavy | `starter_heavy_<slot>` | - (slot closed) | `armor_greatsword.glb` |
| longbow | `starter_longbow` (family `longbow`) | light | `starter_light_<slot>` (reuse `ash_leather`) | - | `armor_longbow.glb` |
| magic | `starter_staff` (family `magic`) | cloth | `starter_cloth_<slot>` (reuse `ash_cloth`) | - | `armor_magic.glb` |

Slots: weapon + hat, shirt, pants, armband, shoes (6 items; 7 for Sword & Shield). Accessories (necklace, earrings, bracelets, rings, back) start **empty**: they are the first upgrades a player sees drop.
Stats: white main stat from `main_stat_by_tier[stat][0]`, 1 substat (`substat_count` 1), rolled with a fixed seed per class and slot (same pattern as `ensure_starter_cards`), so every authority makes the same items.
The armour pieces are **15 new catalog entries** (3 weights × 5 slots), not 20: two classes share heavy. The look on the body stays the class armour because the Boss rule is that fashion/outfit overlays equipment; the item icon is the reused Ash icon of that weight (real combat item art, Boss rule 2026-10-23).

#### 3.3 Granting (one-time, versioned)
- New `starter_kit_version` 2 in the profile. `ensure_starter_kit_v2` gives each class card the pieces of 3.2 **only for empty slots**. It never replaces or downgrades worn gear, so old saves keep their rare/epic starter items.
- New players: `new_player` builds the v2 kit directly (white, all slots) instead of the 3-piece rare/epic one.
- `ensure_starter_armor` (the 15-rare-piece stash gift): **not granted to new players** (default taken, OQ1). Old players keep what they got.
- `weapon_families` become `["blade"]`, `["greatsword"]`, `["longbow"]`, `["magic"]`. Old saves where a greatsword/longbow/magic card holds a `blade` weapon: that weapon is moved to the stash and the class starter weapon is equipped in the same migration (otherwise `card_can_wear` would reject what the card is wearing).
- Drops: `drops-and-rewards.md` `weapon_types` already lists `blade, greatsword, longbow`; with the new families those drops become wearable.

#### 3.4 Missing for Part A (implementation list)
1. Catalog: `starter_blade`, `starter_greatsword`, `starter_longbow`, `starter_staff` (slot `weapon`, `weapon_type`, `drop_level` 99 so they never drop) and 15 `starter_<weight>_<slot>` entries (`set: ""`, `drop_level` 99, asset/icon paths of the Ash weight).
2. Weapon visuals for the 3 new families: the class armour GLB already holds the class weapon meshes (`| Sword/Shield/Bow/Quiver/Staff/Spellbook`); mark the 3 new weapons `procedural: true` like `round_shield` so the client shows the class weapon. **Art ask: 3 weapon icons** (`art/items/icons/weapon_starter_greatsword.png`, `_longbow.png`, `_staff.png`), Codex workflow, Boss review.
3. `data/classes/*.json` `weapon_families` per class; `logic/profile.gd` kit v2 + migration; `data/items/sets.json` stops listing `starter_armor_sets` for new players (or the profile skips it).
4. Tests: new player has 6/7 white items per card, all set-free; old save keeps its items; greatsword card no longer holds a blade; same seed = same items.

### Part B: Race gear sets

#### 3.5 Items
- One set per race: `race_<race>` (`race_human`, `race_viking`, `race_elf`, `race_runeborn`). For each class it has 5 pieces, `race_<race>_<class>_<slot>` with slot `weapon`, `shirt`, `pants`, `armband`, `shoes`. That makes **80 catalog items** (4 races × 4 classes × 5). The weapon is in the class's weapon family (sword, greatsword, longbow, staff). Offhand and accessories are never race pieces. There is no hat slot (removed 2026-11-13).
- Any card can wear any race's armour pieces, and their stats always count. The weapon follows the normal weapon-family rule (`card_can_wear`). A piece's armour weight is its class's (heavy, light or cloth). Each class × race piece has its own look (3.11).
- Tiers: `normal` (white, **starter outfit only**, never dropped), `rare` (blue), `epic` (purple), `legendary` (gold). Tier changes the main stat value and the substat count exactly like every other item (`rules.json`), and the strength of the set option (3.7).
- Main stat per slot: unchanged (`rules.json` `slots[].main_stat`). Race pieces are not stronger or weaker in raw stats than generic pieces of the same tier.

#### 3.6 When the set option is active
`active(step) = card.race == set.race AND count(worn pieces of the set) >= step.pieces`.
- Counted on the card's worn loadout; destroyed pieces (durability) still count while worn; a piece at low durability still counts (durability scales stats only).
- Race mismatch: the piece gives main stat + substats; **no set option**. There is no partial or "off-race" bonus.
- Evaluated at **run start** (the sim snapshots it with the tree and race, skill-tree.md 3.11) and live in the hub for preview. Changing race (`card_race`) switches the option on or off **at once** in the hub; nothing changes mid-run because race cannot change mid-run.

#### 3.7 Set steps (2 / 4 / 5 pieces)

Every race uses the same 3 steps; the effects of steps 4 and 5 differ per class (the passives differ):

| Step | What it does | Form |
|---|---|---|
| **2 pieces** "Kindled" | The passive's numbers +10% | `cell_mod` `cell: passive`, `scale_add: 0.10` |
| **4 pieces** "Attuned" | A class-specific tweak to the passive's hinge (threshold, cooldown, count, duration) | one `cell_mod` field (table 3.8) |
| **5 pieces** "Awakened" | A small new behaviour on the passive | `cell_mod` `extra_actions` or `extra_effects` (table 3.8) |

**Tier of a step.** Each step takes its strength from the **lowest tier among the N best race pieces worn** (N = the step's pieces). Tier multiplier `m`: normal 0.75 (white starter outfit), rare 1.0, epic 1.25, legendary 1.5 (`tier_mul` in data). Example: gold weapon + gold shirt + purple pants + blue armband + blue shoes -> step 2 uses gold (m 1.5), step 4 uses the 4th best = blue (1.0), step 5 = blue (1.0). Upgrading the weakest piece is always the next goal (a readable chase).
What `m` scales: the bonus part of `scale_add` and of `*_mul` fields, `hp_threshold_add`, and the numbers (fractions, `duration`, `atk_mul`, `seconds`) inside `extra_actions`/`extra_effects`. Integer fields (`charges_max_add`, `every_n_add`, `charges_reset_to`) and costs are **not** scaled (formula 4.2).

#### 3.8 The 16 set options (steps 4 and 5; step 2 is `scale_add 0.10` for all)

Numbers at blue (m = 1.0). The passive names are from races-and-classes.md 3.4.

| Race × Class (passive) | 4 pieces | 5 pieces |
|---|---|---|
| Human × S&S (Rallying Drill) | `icd_mul` 0.85 (cooldown 10 -> 8.5 s) | `extra_actions`: `skill_refresh` `allies_all` `seconds` 0.5 (the drill also trims every ally's skill cooldowns) |
| Human × GS (Wide Arcs) | `extra_effects`: `skill_mod radius_mul` 1.10 | `extra_effects`: `trigger on skill_hit`, `min_targets` 3, `cooldown_ticks` 120 -> `skill_refresh self seconds 0.5` |
| Human × Bow (Trained Eye) | `extra_effects`: `skill_mod crit_add` 10 | `extra_effects`: `trigger on kill` -> `skill_refresh self seconds 1.0` |
| Human × Magic (Archmage) | `extra_effects`: `skill_mod cooldown_mul` 0.95 | `extra_effects`: `trigger on skill_cast`, `every_n` 4 -> `skill_refresh self fraction 0.25` |
| Viking × S&S (Unbroken) | `hp_threshold_add` +0.05 (35% -> 40%) | `extra_actions`: `apply_status fortify self` 240 ticks |
| Viking × GS (Berserker) | `hp_threshold_add` +0.05 (full bonus at 25% HP instead of 20%) | `extra_effects`: `trigger on self_low_hp`, `hp_below` 0.5, `once_per_wave` -> `apply_status rage self` 360 ticks ("Blood Up") |
| Viking × Bow (Headhunter) | `duration_mul` 1.25 (rage 8 -> 10 s, haste 4 -> 5 s) | `extra_actions`: `heal self fraction_of max_hp` 0.03 |
| Viking × Magic (Blood Rite) | `extra_effects`: `trigger on kill` -> `heal self max_hp` 0.03 (refunds some blood) | `extra_effects`: `low_hp_scaling stat SKILL_DMG max_mul 0.15 below 0.5` |
| Elf × S&S (Warden's Grove) | `icd_mul` 0.75 (1 -> 0.75 s) | `extra_actions`: `heal self max_hp` 0.01 |
| Elf × GS (Living Bark) | `duration_mul` 1.25 (regen lasts longer) | `extra_effects`: `trigger on kill` -> `heal ally_most_hurt max_hp` 0.03 |
| Elf × Bow (Moonlit Arrow) | `every_n_add` -1 (every 5th -> every 4th shot) | `extra_actions`: `apply_status regen ally_most_hurt` 180 ticks |
| Elf × Magic (Bloomcaster) | `heal_mul` 1.15 (cap 8% unchanged) | `extra_actions`: `shield ally_most_hurt fraction_of damage 0.10 cap_max_hp 0.05` |
| Runeborn × S&S (Rune Aegis) | `charges_max_add` -1 (5 -> 4 runes) | `extra_actions`: `shield ally_most_hurt fraction_of source_max_hp 0.08` |
| Runeborn × GS (Runic Edge) | `charges_max_add` -1 (4 -> 3) | `extra_actions`: `apply_status haste self` 180 ticks |
| Runeborn × Bow (Glyph Shot) | `charges_max_add` -1 (6 -> 5) | `extra_actions`: `burst center target radius 1.5 atk_mul 0.6` |
| Runeborn × Magic (Runeweaver) | `charges_reset_to` 1 | `extra_actions`: `apply_status focus allies_all` 180 ticks |

`default_class` (a future class with no cell): step 4 = `scale_add` +0.05 more, step 5 = nothing; the data test warns (same rule as races-and-classes.md 3.7).

#### 3.9 Vocabulary additions (data-only; unknown word = load error)
- `cell_mod.scale_add` (new): additive passive scale, so set and tree scales add instead of multiplying (4.3). Tree nodes keep `scale`; the engine treats a node's `scale: 1.25` as `scale_add: 0.25`.
- `cell_mod.extra_effects` [effects] (new): appends whole effects (any races-and-classes.md 3.6 type) to the cell. Needed because several passives are `skill_mod` or `low_hp_scaling`, which have no `actions` list to extend.
- `scale` on a `skill_mod` cell scales the **bonus** part (`damage_mul` 1.40 -> bonus 0.40) and never scales costs (`hp_cost`, `min_hp`) or thresholds (`hp_below`, `full_at_hp`); thresholds move only through `hp_threshold_add`.
- Everything else reuses existing words (`icd_mul`, `duration_mul`, `heal_mul`, `hp_threshold_add`, `every_n_add`, `charges_max_add`, `charges_reset_to`, `extra_actions`, the `trigger` filters `min_targets`, `every_n`, `once_per_wave`).

#### 3.10 Data shape (`data/items/sets.json`, same file, new kind)
```json
"race_viking": {
  "name": "Viking War Gear", "kind": "race", "race": "viking",
  "tier_mul": {"normal": 0.75, "rare": 1.0, "epic": 1.25, "legendary": 1.5},
  "steps": [
    {"pieces": 2, "name": "Kindled", "all": [{"type": "cell_mod", "cell": "passive", "scale_add": 0.10}]},
    {"pieces": 4, "name": "Attuned", "by_class": {
       "greatsword": [{"type": "cell_mod", "cell": "passive", "hp_threshold_add": 0.05}]}},
    {"pieces": 5, "name": "Awakened", "by_class": {
       "greatsword": [{"type": "cell_mod", "cell": "passive", "extra_effects": [
         {"type": "trigger", "on": "self_low_hp", "hp_below": 0.5, "once_per_wave": true,
          "actions": [{"action": "apply_status", "status": "rage", "target": "self", "duration": 360}]}]}]}}
  ],
  "bonuses": []
}
```
(`by_class` holds all 4 classes in the real file; `default_class` key for unknown classes.) `bonuses` stays empty so `ItemCatalog.set_bonus` (flat stats) ignores race sets; the race engine reads `steps`. Catalog items (as built): `"set": "race_viking"`, `race`, `class`, `drop_level` 99 (never in the generic pool; they drop only through the race conversion of 3.12), `asset_path`, `icon_path`, `fallback_asset_path`, `fallback_icon_path`. Each step block also carries a per-class `text` for the item detail line. Generated by `tools/items/build_race_gear.py`.

#### 3.11 Looks (16) and the asset list (Studio team; no art made here)
Exact paths and the rig rule are in **`docs/art/race_gear_handoff.md`** (the Studio handoff; its paths are read from `data/items/catalog.json`).
- Each class × race has its own outfit: **16 outfits**, each = **4 armour meshes** (shirt, pants, armband, shoes) + **1 race weapon**. Each slot is its own GLB on the Studio rig, with no new joints, so pieces of different races can be mixed on one body.
- Asset list:
  - **64 armour GLBs**: `art/armor/race_<race>/<class>/<slot>.glb`
  - **16 weapon GLBs**: `art/weapons/race_<race>/<class>.glb`
  - **64 armour icons**: `art/armor/race_<race>/<class>/icon-<slot>.png`
  - **16 weapon icons**: `art/weapons/race_<race>/icon-<class>.png`
  - Icons are 80 in total, 192 × 192, made with the Codex 2D workflow and reviewed by the Boss before import.
- Tiers share the mesh. The tier shows through the item frame colour and the existing refine aura; there is no per-tier mesh.
- **Interim look (2026-11-13):** the Studio delivered one starter look per race (`race_outfits.glb`, split into `art/armor/race_shared/<race>_<slot>.glb`). Every class's race piece shows it at every tier until the class's own file lands. The 16 race × class looks and 16 race weapons stay the target. Race weapons arrive in batches (greatsword first).
- Fallback chain until a file exists: armour = race × class file → the race's shared interim file → the class starter look (Ash); weapon = race × class file → the class weapon (procedural). The set works before the art lands. Details: `docs/art/race_gear_handoff.md` 4.
- Set emblem (optional): reuse the 4 race emblems asked in races-and-classes.md 3.8.
- Fashion still overlays equipment (Boss rule). Visual acceptance stays OPEN per the parity rule until compared.

#### 3.12 Tiers and drop sources (as built: `data/loot/race_drops.json`, `logic/race_drops.gd`)

Race pieces add **no new rolls**: they replace a share of the armour and weapon pieces that already drop. Wave mode pays gear in two ways (see drops-and-rewards.md 3.8):
- the per-kill item drops (`data/loot/loot.json`, tier by monster level);
- the wave chests after waves 3, 6 and 9 (`logic/goblin_wave_progress.gd`, tier from the journey `treasure` weights).

After such a piece has rolled its tier and slot, with the share below it **becomes** the race piece of the same slot and tier.

| Source | Tier weights (unchanged) | Race share by tier rolled |
|---|---|---|
| Kill drops, waves 1-4 | loot.json by monster level | 0 (starter-level gear only) |
| Kill drops, waves 5-8 | loot.json | rare **0.30**; epic/legendary 0 |
| Kill drops, waves 9-11 | loot.json | rare **0.40**, epic **0.40**; legendary 0 |
| Wave chest after wave 3 | treasure 70/25/5 (rare+) | rare 0.30; epic/legendary 0 |
| Wave chests after waves 6 and 9 | treasure 70/25/5 | rare 0.50, epic 0.50; legendary 0 |
| **Boss** (drops of a `boss_types` monster: the Goblin Chief) | loot.json `brute` table | rare 0.50, epic 0.50, **legendary 1.0** |

Rules:
- Slots: `weapon`, `shirt`, `pants`, `armband`, `shoes` only. Accessories, back and offhand never convert. White (`normal`) pieces never convert (the white race outfit is starter-only).
- **Which race and class**: one card of the squad that played the run, picked uniformly. The piece is that card's race × class piece, so the weapon always fits a squad card. A Trio always gets its own race; a mixed squad spreads over its races. A run with no squad card (old single-profile runs) converts nothing.
- **Gold**: only the boss has a legendary share. A gold race piece therefore comes **only from the boss**, and every boss gold piece in a race slot is a race piece. Wave kills and chests never give gold race pieces; a gold piece from them stays generic.
- Determinism: the conversion uses its own generator seeded from the item id, source and wave. The sim's combat and loot stream is identical with or without it, and the same seed gives the same haul. The online room passes the wave it spawned (`GameSim.reward_wave`).
- Gold slot protection (pick an unowned gold slot first) is **not built** (deferred). The slot follows the rolled piece.

#### 3.13 Other gear sets (stack or replace)
- An item has **one** `set`. A race piece never counts toward Obsidian/Sun King/Ash, and a generic piece never counts toward a race set.
- Sets **stack**: 2 race + 3 Ash gives race step 2 **and** Ash steps 2-3. 4 race + 1 other gives race step 4 only.
- With only 5 armour slots, a **full race set (5) leaves no slot for another set**, so the 5-piece race option always costs every other set bonus. That is the intended trade.
- Generic sets keep their flat-stat `bonuses`; race sets have none (their whole value is the passive boost). A mismatched race piece is therefore weaker than a generic piece of the same tier when the generic set is active; that is the reason to match the race.

#### 3.14 Skill tree race branch and synergies (no double-dipping)
- Set and tree both use `cell_mod` on `passive`. They combine by the caps in 4.3: scales **add** (never multiply), capped; thresholds add, capped; cooldown multipliers multiply but floor at `cooldown_mul_floor` (0.60); rune max cannot drop below 2; `every_n` cannot drop below 2.
- races-and-classes.md caps still apply after both: shield <= 30% max HP (50% with an ultimate part), passive healing <= 6% max HP per second, cooldown floor 0.60.
- The set option touches **only the passive**. It never touches the ultimate, the gauge or synergies, so a set cannot stack with Pair/Trio on the ultimate budget (races-and-classes.md 3.5 keeps synergies off the gauge too).
- Combo capstones that rewrite the passive (Moonwell Arrows every 3rd; Spring Rite cap 12%) apply first; the set's field then applies within the caps (Moonlit Arrow: combo 3 + set -1 = 2, the floor).

#### 3.15 UI (display only; `ux-ui-designer` to spec)
Item details (Equipment tab, stash, drop summary):
- Set line: `Viking War Gear  3/5` with the race badge, then each step on its own line with the effect text **for this card's class**, the tier it would use (coloured), and active steps bright, others grey.
- Mismatch: the whole set block is grey with `Set option inactive: needs Viking` (localised key `set_needs_race`, race name from the race file). Stats above it stay normal.
- The card's passive tooltip shows the boosted numbers and a small "+ Viking War Gear (4)" source line, so the player sees where the change comes from.
- Race picker: when switching race, a preview line "Set option on/off" for each race set the card wears.
- Colourblind: tier and active/inactive are also shown as text, not colour only.

## 4. Formulas

**4.1 Step tier.** `tier_of_step(N) = sort_desc(tiers of worn pieces of the set)[N-1]`; `m = tier_mul[tier_of_step(N)]` (1.0 / 1.25 / 1.5).

**4.2 Scaled step values.**
- `scale_add_eff = scale_add × m` (2-piece: 0.10 / 0.125 / 0.15).
- multiplier field `f` (e.g. `icd_mul` 0.85): `f_eff = 1 - (1 - f) × m` (0.85 -> 0.85 / 0.8125 / 0.775). Same for `duration_mul`, `heal_mul` (`1 + (f-1)×m`).
- `hp_threshold_add_eff = value × m` (0.05 -> 0.05 / 0.0625 / 0.075).
- `extra_*` actions: fractions, `duration`, `seconds`, `atk_mul`, `max_mul` × m; integers unchanged.

**4.3 Combining with the tree (no double-dip).**
- `passive_scale = min(1 + Σ scale_add (set + tree), passive_scale_cap)`, `passive_scale_cap` = 1.50.
- `hp_threshold_add_total = min(Σ, hp_threshold_add_cap)`, cap 0.15.
- `cooldown_or_icd = base × Π mul`, floored at `base × 0.60`.
- `charges_max = max(base_max + Σ charges_max_add, 2)` (Overcharge's +2 applies after).
- `every_n = max(base + Σ every_n_add, 2)`.

**4.4 Worked example: Viking greatsword (Berserker).** Base: ATK bonus `0.40 × clamp((1.0 - h)/(1.0 - 0.20), 0, 1)`, kill heals 6% max HP.

| Setup | max_mul | full_at_hp | ATK bonus at 50% HP | at 30% HP | kill heal | extra |
|---|---|---|---|---|---|---|
| No set | 0.40 | 0.20 | 0.40 × 0.5/0.8 = **0.250** | 0.40 × 0.7/0.8 = 0.350 | 6% | - |
| 2 blue | 0.44 | 0.20 | 0.44 × 0.625 = **0.275** | 0.385 | 6.6% | - |
| 4 blue | 0.44 | 0.25 | 0.44 × 0.5/0.75 = **0.293** | 0.44 × 0.7/0.75 = 0.411 | 6.6% | - |
| 5 blue | 0.44 | 0.25 | **0.293** | 0.411 | 6.6% | below 50% once per wave: `rage` 6 s (ATK +30%, DEF -15%) |
| 5 gold (m 1.5) | 0.46 | 0.275 | 0.46 × 0.5/0.725 = **0.317** | 0.46 × 0.7/0.725 = 0.444 | 6.9% | `rage` 9 s |
| 5 gold + tree Thick Blood (vk_1, +0.10) | 0.46 | 0.20 + min(0.075+0.10, 0.15) = 0.35 | 0.46 × 0.5/0.65 = **0.354** | 0.46 (full) | 6.9% | `rage` 9 s |
| 4 Viking pieces on an **Elf** greatsword | - | - | Living Bark unchanged; pieces give stats only | | | |

Reading: a full gold set moves the mid-fight bonus from +25% to about +32% ATK and adds one rage window per wave. With the tree it reaches +35%, and the threshold cap (0.15) stops the stack from going further.

**4.5 Drop expectations per winning run** (squad of 3, `loot_by_squad` 1.0).

`E_race = Σ_w I_w · r · Σ_t P(t|w) · s(t) + chests + boss`, where:
- `I_w`: expected kill items in wave bracket `w`
- `P(t|w)`: the tier mix there (loot.json by monster level: levels 2-3 in waves 5-8, levels 3-4 in waves 9-11, mostly `[60,30,9,1]`)
- `r`: the share of drops that land in a race slot (≈ 0.5: weapon, shirt, pants, armband and shoes out of the droppable slots)
- `s(t)`: the share in 3.12

Worked example, with ~10 kill items per run (loot.json `_tuning`), ~4 of them in waves 5-8 and ~3 in waves 9-11:
- Waves 5-8: `4 × 0.5 × 0.30 × 0.30 ≈ 0.18` blue.
- Waves 9-11: `3 × 0.5 × (0.30 × 0.40 + 0.09 × 0.40) ≈ 0.23` (0.18 blue, 0.05 purple).
- Chests: `3 × 0.5 × ≈0.45 ≈ 0.7`.
- Boss: the Chief's `brute` table has a 0.70 item chance at level 4 (`[60,30,9,1]`), so `0.70 × 0.5 × (0.30 × 0.5 + 0.09 × 0.5 + 0.01 × 1.0) ≈ 0.07`. Of that, **gold ≈ 0.0035 per win**.
- Total ≈ **1.2 race pieces per win**, mostly blue.

**Gold is very rare with today's Chief table** (1% legendary at level 4). Raising it is a tuning knob, not a rule change: the Chief's table or level, or the guaranteed boss piece that drops-and-rewards 3.1 plans. Every boss gold is a race piece whatever its rate. The shares are tested (tests/test_race_drops.gd); the per-run totals stay placeholders until class_sim logs loot per source. OPEN for the Boss, see 9.9.

**4.6 Power budget (targets, verify by sim).**
- Race passive cell ≈ +8-10% card power (races-and-classes.md 4.5).
- Set option: 2 pcs ≈ +1%, 4 pcs ≈ +2-3%, 5 pcs blue ≈ +3-4%, **5 pcs gold ≤ +6%** card power (on top of the pieces' raw stats, which equal any same-tier set).
- Race tree branch (13 points) ≈ +15-20%. The set at most ≈ **one third** of the race branch, so the tree stays the main race investment and the set is the gear chase.
- Compared with a generic 5-piece set at the same tier (flat stats ≈ +3-5% today): matched gold race ≈ +6% vs generic ≈ +4%. The race set wins only when matched, by a small margin.

## 5. Edge Cases

- **Race changed in the hub**: the option recomputes at once (preview shows on/off); the server stores nothing extra (it is derived). Race and combo tree points are refunded as today; the set is untouched.
- **Mixed races** (2 Viking + 3 Elf on an Elf card): Elf set 3 pieces -> step 2 active; Viking pieces give stats only.
- **2 of one race set + 2 of another race set**: only the matching race counts; the other never activates.
- **Duplicate slot pieces**: impossible (one item per armour slot), so the max count is 5.
- **Piece at 0 durability**: still counts; its stats fall to `broken_factor` as usual.
- **Normal-tier race piece** (should never roll; a data or old-save error): counts as a piece with m = 1.0; the loader logs a warning.
- **Class with no `by_class` entry**: uses `default_class` (3.8); data test warns.
- **Passive with nothing to modify** (e.g. `every_n_add` on a passive with no `every_n`): load error in the data test (each `by_class` entry is checked against its target cell). Never a silent no-op.
- **Caps reached**: extra set value is lost silently in combat but the tooltip shows "(capped)" next to the capped number.
- **Snapshot**: changes in the hub never alter a running journey; online rooms receive the validated loadout and race; the sim derives the option itself (never trusts a client flag).
- **Solo card**: works the same; sets have nothing to do with squad size.
- **Squad of 3 different races and a gold drop**: the race is one of the three squad races even if that card later switches race; it is just an item in the stash.
- **All 5 gold slots of a race owned**: the slot draw is uniform (duplicates allowed); further protection is not needed.
- **Determinism**: drop draws come from the wave reward RNG; set evaluation has no randomness.

## 6. Dependencies (both ways)

| System | Direction | Contract |
|---|---|---|
| `design/gdd/races-and-classes.md` / `data/races/*.json` | sets -> races | Reads the 16 passives. Needs `extra_effects`, `scale_add` and the bonus-only rule for `scale` on `skill_mod` (3.9). **That doc should list race sets** as a passive modifier source next to the tree. |
| `design/gdd/skill-tree.md` / `logic/skill_tree.gd`, `logic/race_passives.gd` | shared | Same `cell_mod` application path; caps 4.3 are applied once over set + tree. Tree `scale` read as `scale_add`. **That doc's 4.6 should point here for the shared caps.** |
| `design/gdd/drops-and-rewards.md` (3.8) / `data/loot/race_drops.json` / `logic/race_drops.gd` (called from `logic/game_sim.gd` `_give_drop`, `logic/journey.gd` `treasure_drop`, `server/rooms/room.gd` wave chest) | drops <-> sets | Per-source race share by tier, race from the squad, boss-only gold (3.12). drops-and-rewards.md 3.8 states the same rules and links back here. The faucet size is unchanged. |
| `data/items/sets.json`, `data/items/catalog.json`, `logic/item_catalog.gd`, `logic/race_sets.gd` | data | `kind: race` sets with `steps`; 80 race items; `set_bonus` skips race sets (empty `bonuses`); `RaceSets.status` / `active_mods`; `ItemCatalog.race_piece(race, class, slot)` |
| `logic/stats.gd` | unchanged | still adds generic set bonuses only |
| `logic/profile.gd`, `logic/card_deck.gd`, `data/classes/*.json` | Part A | starter kit v2, `weapon_families`, migration (3.3) |
| `logic/game_sim.gd` (run start) | sets -> sim | snapshot of active steps per card with race and tree |
| `tools/balance/class_sim.gd` | measures | section 7.1 |
| Client: Equipment tab (`client/gear_panel.gd` through `client/item_text.gd` `race_set_lines`), stash, drop summary, passive tooltip, race picker | display | 3.15 |
| Studio team (3D) + Codex (2D) | assets | 3.11, 3.4, `docs/art/race_gear_handoff.md` |

## 7. Tuning Knobs

| Knob | Default | Safe range | Category | Affects |
|---|---|---|---|---|
| step pieces | 2 / 4 / 5 | fixed shape; 2/3/5 allowed | gate | how early the set pays |
| 2-piece `scale_add` | 0.10 | 0.05-0.15 | curve | entry value |
| 4- and 5-piece values (3.8) | per cell | each step ≤ +3% card power | curve | per-class feel |
| `tier_mul` | 0.75 / 1.0 / 1.25 / 1.5 | 0.5-1.0 / 1.0 / 1.1-1.3 / 1.2-1.6 | curve | white starter strength, gold vs blue gap |
| `passive_scale_cap` | 1.50 | 1.35-1.75 | gate | set + tree ceiling |
| `hp_threshold_add_cap` | 0.15 | 0.10-0.20 | gate | Viking threshold stacking |
| race-set share per source/tier (`data/loot/race_drops.json`) | 3.12 | 0-1 | gate | blue/purple/gold arrival rate |
| boss legendary race share | 1.0 | 0.5-1.0 | gate | full gold set time (15-44 wins) |
| gold slot protection | not built (deferred) | on/off | gate | dupes |
| starter kit tier | normal | normal only | gate | onboarding ladder |

### 7.1 Balance measurement plan (class_sim)
- New arg `gear=race:<tier>:<pieces>` (and `gear=none`, `gear=generic:<tier>:5`), applied to every squad card with its own race.
- `only=race_sets`: the 16 cells solo, each at pieces 0/2/4/5 × tier blue/gold, × tree race branch off / preset on. 40 seeds each.
- Flags: any 5-gold lift > **+4 pts** solo win rate or > **+6%** card power; matched 5-gold vs generic 5-gold lift > **+3 pts**; set + tree passive bonus beyond the caps (assert); mismatched race set lift ≠ 0 vs the same stats with no set (must be exactly 0).
- Squad check: starter squad (H/V/E) with full blue matched sets stays within the race-mix ±5 pts rule (races-and-classes.md 8); report the change so the HP/difficulty re-tune can include gear.
- Log per card: set step active, passive trigger counts and value with/without set (e.g. Berserker average ATK bonus, Moonlit heals, rune discharges).

## 8. Acceptance Criteria

**Part A**
1. A new player's 4 cards each wear weapon + 5 armour pieces (+ round shield on S&S), all `normal`, all with `set` empty; the greatsword, longbow and magic weapons have their own family and pass `card_can_wear`.
2. An old save keeps every item it wore; empty slots are filled once (`starter_kit_version` 2); a greatsword/longbow/magic card holding a blade gets its class weapon and the blade goes to the stash. Running the migration twice changes nothing.
3. The card shows its class armour look with the starter kit; item icons are the reused Ash icons and the 3 new weapon icons.
4. Same seed gives the same starter items on client and server.

**Part B (as built 2026-11-13; numbers 16-21 are the final-shape criteria)**
16. Each race set has 5 pieces per class (race weapon + shirt, pants, armband, shoes), 80 catalog items, steps 2/4/5; no hat slot exists anywhere (rules, catalog, starter kit, UI). (tests/test_race_sets.gd, test_starter_kit.gd)
17. A new card wears its own race's white outfit (5 pieces, `normal`); its 5-piece option is active at `m` 0.75. (test_starter_kit.gd)
18. Any card can wear another race's armour pieces; their stats count and the option stays off ("Set option inactive: needs <Race>" in the item detail). (test_race_sets.gd; screenshot `build/race_sets/`)
19. Over 3000 seeds per case the race share per source/wave/tier matches `data/loot/race_drops.json` within ±0.03; no wave or chest legendary ever becomes a race piece; every boss legendary in a race slot is a race piece; race and class come only from the squad's cards, evenly per card. (tests/test_race_drops.gd)
20. The item detail shows "<Set> n/5" and one line per step with on/off and the tier as words, in English and Thai (card_tokens `set_race_*`, `set_needs_race`).
21. Every piece has an asset and icon path from the handoff (`docs/art/race_gear_handoff.md`) and shows the class starter look until the file exists.
5. A Viking greatsword wearing 2/4/5 blue Viking pieces gets the 4.4 values (0.275 / 0.293 / 0.293 + rage) at 50% HP, within rounding; an Elf greatsword wearing the same pieces gets the same raw stats and an unchanged passive.
6. Changing the card's race in the hub turns the option on/off immediately in the preview and in the next run; never mid-run.
7. Mixed tiers use the lowest tier of the N best pieces (3.7 example) in a unit test.
8. Set + tree never exceed `passive_scale_cap`, `hp_threshold_add_cap`, the cooldown floor, the rune floor 2 or the `every_n` floor 2 (unit tests with Thick Blood, Drilled Ranks, Quick Glyphs, Moonwell Arrows).
9. A race set and a generic set stack at 2 + 3; a 5-piece race set leaves no generic bonus; race pieces never feed `ItemCatalog.set_bonus`.
10. Over 10,000 simulated winning runs: race pieces ≈ 1.55 / win (±0.1), gold race pieces come only from the boss, ≈ 0.20 / win without pity; no wave/chest ever yields a gold race piece; race draws only use squad races.
11. Adding a 5th race with a `race_<id>` set needs only data (sets.json, catalog, art paths), zero code.
12. The item detail shows the set line with per-class step text, tier per step, and "Set option inactive: needs <Race>" on a mismatch, readable without colour.
13. class_sim 7.1 flags are clean, or every flag has a tuning note.
14. Playtest (experiential): a tester can tell from the tooltip and the fight that the full set changed the passive (e.g. "my Viking enrages earlier"), and can say why an off-race piece shows its option greyed.
15. `tests/run_all.gd` passes.

## 9. Open questions / defaults taken (PO default rule: recommended option picked)

1. **Old 15-piece rare armour gift (`ensure_starter_armor`)**: A. stop giving it to new players, old players keep theirs (**default**; otherwise the white kit is obsolete on minute one); B. keep giving it; C. give white versions instead. **Boss should confirm (it changes what new players receive).**
2. **Which pieces form a race set**: the 5 armour slots only (**default**); alternatives (adding back/accessories) would make sets 8-11 pieces.
3. **Tier effect on the set option**: tier scales the option via the lowest tier of the N best pieces (**default**) vs option identical across tiers.
4. **Race of a dropped race piece**: uniform among the squad's races (**default**) vs any race.
5. **Gold race share of the boss legendary**: 1.0 (**default**; every boss legendary is a race piece) vs 0.5 (keeps generic gold from the boss).
6. **Starter armour pieces**: 15 set-free catalog entries that reuse the Ash meshes/icons by weight (**default**) vs no starter armour items (look only).
7. **`extra_effects` and `scale_add`**: added as two new `cell_mod` fields (**default**) vs one-off `mechanic` ids per cell (more code).
8. **drops-and-rewards.md edit**: done 2026-11-13 (its 3.8 and dependencies link back here).
9. **Gold race rate**: with today's Chief loot table a gold race piece is ~0.4% of winning runs. A. keep it as is and raise the rate later with the planned guaranteed boss piece (**default**); B. raise the Chief's legendary weight now; C. add a guaranteed boss piece now (drops-and-rewards 3.1). Boss call.
10. **Gold slot protection** (3.12): not built (**default**: deferred until gold drops are common enough to repeat).

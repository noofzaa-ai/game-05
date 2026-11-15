# Campaign Spine — Player Experience and Screen Framing

Status: DRAFT for PO merge (game-designer, 2026-11-16). This is not an approved system change and it changes no code. Canon level: Boss locks = Established; everything else = Provisional.
Inputs: the agreed story draft (Boss decisions 2026-11-15/16), `design/gdd/tutorial.md`, `client/card_deck_screen.gd`, `client/journey_screen.gd::_build_wave_summary`, `data/journeys/`, `data/tutorial/unlocks.json`, `logic/unlocks.gd`, `docs/ui/world_map.md`.
Merge partners: the narrative-director owns the words, and the combat-designer owns fight pressure per region. This file owns where the words appear, what state backs them, and what each chapter unlocks.

**Locked by Boss (used as given):** a card holds the warrior's soul and skill, while race and body form are changeable and the hero stays the same person. The player is an apprentice summoner who inherited 4 cards and a route journal. The first 3 cards answer through the tutorial race picks. Magic unseals after Goblin Chief wave 12, which returns the stolen journal, and Magic's first form is Runeborn. The goblin base is chapter 1, with about 10 more regions after it.

---

## 1. Player fantasy and motivation loop

**One-line fantasy:** "I lead a band of summoned heroes who chose to travel with me, and we are reopening a cut-off road one promise at a time."

| Layer | What the player does | What the player feels they are doing (story) | Need served (SDT) | Visible answer to "why?" |
|---|---|---|---|---|
| Micro (30 s) | Watches the squad fight on its own | "My team carries out the plan I set." | Competence (reading their own build) | Ult and skill callouts, wave counter |
| Meso (one run, 5–15 min) | FIGHT → waves → summary | "We went out to keep promise X." | Competence and relatedness (squad lines) | Mission line before FIGHT, story result in the summary |
| Session | Loot → Blacksmith/Tailor → swap races or cards → retry | "I prepared my team better for the promise we haven't kept yet." | Autonomy (which card, which race) | Hub mission line, plus "Next:" in the summary |
| Campaign | Clear a chapter → new region on the map | "The road is opening, and the journal shows how far we've come." | Achievement and discovery | Journal or map: route drawn, regions lit |

**Story goals mapped onto the existing loop** (no new loop; each existing step gets a story reason):

| Existing loop step | Story meaning | Rule that keeps it honest |
|---|---|---|
| Fight | Carry out this chapter's promise | The squad always speaks from the cards actually fielded |
| Loot | What we recovered or salvaged on the road | Loot text never claims the people were helped. Only a chapter win says that. |
| Gear (Blacksmith, Storage) | Equipping the band for the road ahead | No story text needed. The hub mission line keeps the purpose in view. |
| Stronger cards (skills, race swap) | The same hero takes a better-suited form | Race swap never changes the hero's identity lines (Boss lock) |
| Next region | Kept promise → new route on the journal map | Unlocks only on a server-confirmed chapter win |

A failed run is "we withdrew; they are still waiting". It is never a story success, and it does not add a new beat beyond one line.

---

## 2. Mission framing UX

Rule: the **current mission plus the next goal fit in 2 lines** and are visible on the hub at all times. Everything longer lives in one new screen, the **Route Journal**, and can be re-read there.

### 2.1 Placement

| Where | Element | Content (max) | Existing hook | New? |
|---|---|---|---|---|
| Hub, above FIGHT | Stage strip (already shows `CardTokens.stage_name()`, e.g. "Goblin Base · 12 Waves") | Line 1: region name. Line 2 (new): mission line, e.g. "Take back the journal from the Goblin Chief" | `_stage_strip` / `_stage_label` near `FightButton` | Second line only |
| Hub, side menu | Route Journal entry (book icon) with a `!` badge when an unread beat exists | none on the hub | `service_badges`, `Menu_<id>` pattern; Quests is already a side-menu id with no logic | New entry (or repurpose Quests, see Q2) |
| Before FIGHT (tap FIGHT) | No blocking popup. The mission line is already on screen. The first run of a chapter shows a 1-line "promise" toast from a fielded card portrait (≤ 2 s, tap to dismiss). | 1 speaker plus 1 line | `_start_fight` | Small |
| Loading | Optional tip only (load time varies) | 1 line | `fight_loading.gd` | No change needed |
| Battle | Nothing new. Don't interrupt the waves. | — | — | — |
| Results summary | Insert a **story block** under the stage name and above Loot: win → outcome line + "Next: …"; loss → "Withdrew. They're still waiting." + "Next: try again (gear up)"; replay → patrol line | 2 lines + "Next:" line | `_build_wave_summary`, between `summary_waves` and the divider | New block |
| Unlock ceremony (wave 12, chapter 1) | Existing card reveal. Before it, one line: "The journal is ours again. A seal page glows…" After "The seal breaks!", one Magic line ("I'm free. I'll walk with you.") | Uses existing steps; text only, ≤ 60 chars | `tutorial_ceremony.gd`, steps `unlock_ceremony`/`unlock_pick` | Text only (PO holds tutorial; ids/order unchanged) |
| Route Journal screen | Tab A **Road** (map): regions as nodes, done = inked, current = pulsing, locked = fogged. Tab B **Entries**: per chapter → Promise / Outcome / What we learned. Each entry has a "Read again" option. | Entry ≤ 3 short paragraphs | New screen; reuse `world_map_screen.gd` art/fog approach from `docs/ui/world_map.md` if that source returns | The one new screen |

**Journal before wave 12:** the entry is visible, but the book shows "Pages torn out — taken by the Goblin Chief". Only the chapter 1 mission page is readable. Winning wave 12 restores the book, so the story reward is literally the screen (see §3). The tutorial stays unchanged: the tour never targets the Journal.

### 2.2 Phone constraints

| Constraint | Value | Why |
|---|---|---|
| Test sizes | 390×844 portrait (tutorial spec) and 844×390 landscape (world-map doc) and 1920×1080 | Both orientations exist in current specs |
| Hub mission line | 1 line, ≤ 36 chars EN / ≤ 30 chars TH. Truncate with "…"; never wrap onto the FIGHT art. | 390 px width at the ≥ 16 px floor scaled by `s` |
| Summary story block | ≤ 3 lines total, each ≤ 60 chars, so the Back button stays visible without scrolling at 844 px height | Same 60-char cap as tutorial tests; Back stays reachable |
| Speaker toast | Portrait ≤ 48 px plus 1 line, top safe area, never over the FIGHT button or squad tray | Tutorial overlay and tray stay targetable |
| Journal tap targets | ≥ `CardTokens.tap()` min; region nodes ≥ 44 pt and spaced so a thumb can't hit two | Phone thumbs |
| Journal landscape | Map left, entry right. Portrait: map top 45%, entry below, scrollable. | One layout for both |
| Fonts | Thai glyph font required on every new label (the ping label already hit "font has no Thai") | Known pitfall |
| All text | Localization keys (`HubLook.t`/`CardTokens.t`) with th/en, data in `data/story/chapters.json` | `.claude/rules/ui-code.md` |

---

## 3. Progression gates per region (story reward = gameplay reward)

Constraint: there are only 4 classes and 4 races, and all of them are open after chapter 1. Later chapters therefore can't hand out cards. They give **routes, features, and depth**. Rows 2–11 use placeholder themes for the narrative-director and Boss to name. Each later reward is a candidate that needs a systems or economy check before it is locked.

| # | Region (status) | Story promise → outcome | Gameplay unlock (= story reward) | Fight pressure hint (for combat-designer) |
|---|---|---|---|---|
| 1 | Goblin Base (**ready**, `goblin_waves`, 12 waves) | Take back the stolen supplies and the journal from the Chief → medicine delivered, a letter from beyond the closed pass | **Magic card + Runeborn form** (existing gate), **Route Journal screen restored**, route to region 2 drawn | Mixed goblin roles (archer w3, mage w5, knight w6, Chief w12) |
| 2 | Tomb / mummy grounds (**preview**, `mummy_arena_a/b/c`) | Learn the pass route and the history of the seals → a guardian's testimony | **Region select on the map** (2 destinations, choose which to farm). Region 1 becomes replay or patrol. | Attrition, so sustain matters (Elf heal, Runeborn shields) |
| 3 | Orc country (**data only**, `ink_road`, world-map "central Orc") | Negotiate or win passage rights → passage granted with conditions | **Second gear tier** in Shop/Blacksmith drops (region loot table) | Heavy frontline, so burst matters (Viking low-HP) |
| 4 | Placeholder: river crossing town | The price of protection → town chooses its own guard | **Quests board** (route tasks; uses the existing `quests` side-menu id) | Fast swarms |
| 5 | Placeholder: highland pass | Rescue the scouts → map of the commander's lines | **Race skill-tree tier 2** for all races | Ranged-heavy enemies |
| 6 | Placeholder: occupied road (mid-campaign turn) | The road we opened was used to hurt people → own the consequence | **Formation choice** (front/back order) if combat supports it; otherwise squad presets | Counter-composition: punishes single-race squads |
| 7 | Placeholder: forest community | Earn trust without changing form (Boss lock: form ≠ culture) | **Tailor region outfits** (cosmetic only) + refine cap +1 | Debuffs |
| 8 | Placeholder: ruined archive | Truth about who sealed the cards (optional reveal) | **Alliance/Pair/Trio synergy tier 2** | Shields / armor |
| 9 | Placeholder: commander's outpost | Free a captured band → allies pledge help | **Ally support strike** (1 per run, from earlier regions), if feasible | Elite waves |
| 10 | Placeholder: border fortress | Hold the opened road → allies hold the flanks | **Hard mode for regions 1–9** (replay depth) | Endurance |
| 11 | The crossing (finale) | Face the commander's army; the road connects again | **Ending + post-game "news from the reconnected world"** route; all regions get post-game variants | Boss army composed of all prior pressures |

Rules for the table:
- Each region has ≥ 1 *gameplay* unlock and ≥ 1 *journal* entry. A pure-text chapter reward is not allowed.
- The unlock fires from the same server hook pattern as `Unlocks.on_battle_result` (journey id + cleared target). It is data-driven and lives next to `data/tutorial/unlocks.json`, for example as `data/story/chapters.json`.
- Region N+1 becomes playable when chapter N is done. Previous regions stay open for farming.
- Regions don't have to be 12 waves. Each region's chapter clear condition is per-region data (draft agreement).

---

## 4. Replay and fail rules, plus minimum server state

| Situation | What the player sees | State change |
|---|---|---|
| First clear (win) | Story block "outcome + Next:", ceremony if the chapter has one, journal `!` | `chapters_done += id`; the chapter's unlock fires once |
| Loss / abandon | "Withdrew. Still waiting." + Next: retry | None. Never shows success. |
| Replay after clear | Patrol/road-keeping line, normal loot | None; no story reward again |
| Race or squad change between tries | Lines speak from the cards currently fielded | None (identity is per card, not per race) |
| Win recorded but client lost connection (current staging bug) | On next hub load: the unshown win beat plays from the journal badge plus a one-time summary card | Derived: `chapter in chapters_done and "win" not in story_seen[chapter]` |
| Skipped text | Mission line and journal still show it | Dismiss or skip marks it as seen. Reading never grants rewards. |

**Minimum server-side profile fields** (server-authoritative like `unlocks`; the client never sets `chapters_done`):

| Field | Type | Set by | Meaning |
|---|---|---|---|
| `story.chapters_done` | Array[String] | Server battle-result hook | Chapters cleared; drives region unlocks and "current chapter" |
| `story.seen` | Dictionary chapter_id → Array[String] of beat ids (`pre`, `win`, `ceremony`) | Client command `story_seen {chapter, beat}`, server-validated (beat must exist; `win` only if chapter done) | Which beats were dismissed; badges only |
| `story.version` | int | Server | `chapters.json` version for later text migrations |

The current chapter is **derived** (the first chapter in data order not in `chapters_done`), not stored. Migration: an existing profile with `unlocks.magic_runeborn = true` gets `chapters_done = ["goblin"]` and `seen.goblin = ["pre","win","ceremony"]`. This is idempotent.

---

## 5. Risks

| Risk | Example | Mitigation |
|---|---|---|
| Text the auto-battle can't back up | "Elf kept us alive" when the Elf died on wave 2 | Pre-fight lines state *intent*. Post-fight lines use only facts the result has: win/lose, wave reached, loot, squad list. Per-hero praise needs an event log, which is out of scope for now. |
| Speaker who wasn't fielded | Magic speaks but isn't in the squad | Speaker = a random fielded card; fallback lines for 1-, 2- and 3-card squads |
| Players skip all text | Mashes Back on the summary | Mission line always on the hub; "Next:" on the summary sits above the button; journal re-read; the playtest checks that the player can name the next goal |
| Text promises a mechanic that isn't there | "Supplies lost" when no items are deducted | Narrative lines are reviewed against the fight rules (draft rule) |
| Mixed progress in online rooms | Host on region 3, guest on region 1 | Each account sees text from its own progress. Chapter credit goes only to players whose current chapter = room region **and** who are present at the server-recorded win. No room ever pauses for reading. Join rule is open, see Q3. |
| Disconnect ≠ win | Staging "connection lost" after a win | Only a server-recorded win counts. A derived unseen-win beat heals the story on next load (§4). The PO's bug fix must land first. |
| Tutorial collision | New mission line overlaps tutorial cut-outs | The mission line hides while `tutorial.step` is before `fight`. Journal isn't in the tour. Tutorial ids and order stay unchanged. |
| Thai font or length overflow | Thai lines are longer and clip | Char caps in §2.2 enforced by a data test like the 60-char tutorial test |
| Scope creep on 11 regions | Rows 4–11 rewards need new systems | Lock region 1–2 rewards only. Each later reward needs a systems/economy check before it is approved. |

---

## Open decisions (for PO → Boss)

**Q1. Where does the re-readable story live?**
- Route Journal as a new side-menu screen with map + entries, restored at wave 12 (Recommended). The story reward is a real screen, and it's the single new screen allowed.
- Journal text only (no map) for now: cheaper, but region choice has no home later.
- Only the summary and the hub line, no journal: cheapest, but players can't re-read anything.

**Q2. Journal entry placement**
- New "Journal" side-menu entry; Quests stays separate for later route tasks (Recommended)
- Repurpose the logic-less Quests entry as the Journal: no new menu slot, but the name doesn't match

**Q3. Online room with mixed progress**
- Anyone can join; only players on that chapter get chapter credit (Recommended): social play is never blocked
- Joiners must have the room's region unlocked: no spoilers, but friends get split

**Q4. Later-region reward lock-in**
- Lock regions 1–2 now and treat rows 3–11 as candidates pending a systems check (Recommended)
- Lock the whole table now: clearer roadmap, but high risk of rework

# Races and Classes (race x class passives, squad synergies)

**Status**: Draft (standard rigor) · **Date**: 2026-11-13 · **Author**: game-designer, for the PO/Boss
**Source decisions**: Boss 2026-11-13 (PROGRESS.md): any card can be any race; abilities differ per race x class pair, axes clearly separated; 4 races (Human, Viking, Elf, Runeborn); TFT-style race synergies; new races/classes are data only.
**Every number below is a PLACEHOLDER** until `tools/balance/class_sim.gd` measures it and the Boss plays it. `OPEN` items have a default the PO may apply (docs/po_defaults.md rule).

## 1. Overview

A card today is a class (one card per class, `logic/card_deck.gd`). This system adds a second axis: **race**. Each card carries one race. The class says *what the card does in the fight* (role, position, auto-pilot behaviour, skills). The race says *how it does it*. Each race has one theme. That theme turns into one concrete passive per class, so the game has 4 x 4 = 16 distinct passives. A squad of 3 then gets **one** race synergy from its race mix: a pair, a trio or "three different races". This gives the player a real squad-building puzzle before every run. Example: "Elf bow plus Elf mage for the pair heal, or a Viking greatsword for the Alliance bonus?" Races, passives and synergies live only in `data/races/`. A small fixed set of effect types, read by one rules module in `logic/`, runs them.

## 2. Player Fantasy

- **Squad-builder fantasy (Expression, Challenge-as-strategy)**: "I built this team." In an auto-battler the player's agency is almost all *before* the fight, so the choices must be readable and must change the fight in ways you can see.
- **Identity fantasy (Fantasy)**: a Viking greatsword that gets more dangerous as it bleeds is a different character from an Elf greatsword that never seems to go down, even with the same class and skills.
- **SDT**: Autonomy (16 cells x synergy choice, several viable squads), Competence (the synergy and passive triggers show on screen, so the player learns *why* a squad won), Relatedness (the race look on the card makes each card a character, not a stat block).
- **Bartle/QF**: Achievers chase all 16 cells. Explorers find combos (Viking + Elf healer). Strategists (Mastery) optimise synergies.

## 3. Detailed Rules

### 3.1 Two axes, kept apart

| Axis | Owns | Never owns |
|---|---|---|
| **Class** (`data/classes/<id>.json` + `data/combat/weapons.json` style) | role, front/back line, base stat profile, auto-pilot profile, weapon moves, 4 class skills, signature mechanic | healing/shields/fury/runes (race themes) |
| **Race** (`data/races/<id>.json`) | one theme, its 4 class passives, its synergy bonuses, its look | stat profile of the class, targeting, weapons |

Rule of thumb for reviewers: if you cover the race name, the passive still reads as the race's theme. If you cover the class name, the passive still makes sense only for that class's role.

### 3.2 Class identities (sharper than now)

Today the classes differ mainly by weapon move numbers. The auto-pilot treats them almost the same: walk to the nearest enemy, swing, try skills in turn, and stand off at 6 m if the class shoots. Solo win rates are within 72-85% and greatsword = sword & shield (77.5%). The proposal below gives each class a **stat profile**, a **pilot profile** and a **signature mechanic**, all in data.

| Class | Role | Line | Stat profile (`class_stats`, mul on base unless `add`) | Pilot profile (what the auto-pilot does differently) | Signature mechanic |
|---|---|---|---|---|---|
| **sword_shield** | Tank / protector | Front | HP x1.30, DEF x1.40, ATK x0.85, EFFECT_RES +15 | `target: peel`: attacks the enemy nearest the most-hurt ally. Guard reaction 0.95 (others 0.85). Walks ahead of the squad at wave start. | **Bulwark (taunt)**: every 8 s, enemies within 5 m switch their target to this card for 3 s. NEW (enemy_ai target override). |
| **greatsword** | Bruiser / cleave | Front | HP x1.15, ATK x1.10, ATKSPD -10 | `target: densest`: walks to the enemy with the most other enemies within 2.5 m. Heavy every 3rd swing (others 4th). | **Cleave**: a heavy hit deals +15% damage per extra enemy it hits (max +45%). NEW (multi-hit count). Keeps its fortify/regen self-buffs (PO default 2026-11-12). |
| **longbow** | Ranged single-target DPS | Back | HP x0.80, DEF x0.80, ATK x1.15, CRIRATE +15, CRIDMG +20 | `target: lowest_hp` (finisher), but the boss is always the target while it is alive. Shoots from 7 m. **Kites**: steps back when an enemy is within 3 m and the dodge is off cooldown. | **Hunter's Mark**: the first hit on a new target applies `sunder` (existing status, DEF -40%). The other cards' pilots prefer a marked target when it is within their engage range, so the squad focus-fires. REUSE status + NEW pilot rule. |
| **magic** | AoE / control / support | Back | HP x0.75, DEF x0.75, STAREGEN x1.40, EFFECT_ACC +20. Basic bolt `power` 1.1 -> 0.9 | Shoots from 7 m. **Holds damage skills** until 2+ enemies are inside the skill radius (or the target is the boss). Casts `frost_armor` on the most-hurt ally below 60% HP. | **Spellweave**: most of the damage comes from skills (higher stamina regen, weaker bolts). REUSE (stats + skill system); the hold rule is NEW pilot logic. |

The pilot profile replaces the auto-pilot's current constants (`REACH`, `SHOOT_RANGE`, `HEAVY_EVERY`, `reaction`). Those constants become the **defaults** when a class file has no `pilot` block. That keeps old behaviour for any class without one.

```json
"pilot": {"line": "front", "target": "peel", "engage_range": 0, "shoot_range": 0, "kite_distance": 0,
          "heavy_every": 4, "reaction": 0.95, "skill_min_targets": 1, "support_skill": "", "support_below": 0.0},
"class_stats": [{"type": "stat_mod", "stat": "HP", "mul": 0.30}, {"type": "stat_mod", "stat": "DEF", "mul": 0.40}],
"signature": [{"type": "aggro", "radius": 5.0, "every_ticks": 480, "duration_ticks": 180}]
```
`target` is one of a fixed set: `nearest | peel | densest | lowest_hp | marked_first`. `engage_range: 0` = derive from the weapon (today's rule).

### 3.3 Race identities (one theme each)

| Race | Theme | One-line identity | Look |
|---|---|---|---|
| **Human** | **Mastery**: skill power and efficiency | "Trained, disciplined: their skills hit harder and come back sooner." | Baseline |
| **Viking** | **Fury**: power grows as HP falls; kills feed it | "Most dangerous when nearly dead." | Braids, beard, war paint |
| **Elf** | **Lifebloom**: healing that flows to allies | "The squad that will not stay down." | Long ears |
| **Runeborn** | **Runes**: charges build up, then discharge as shields or power | "A rhythm of build-up and release; arcane wards." | Glowing rune skin marks |

Speed and evasion (from the brief's Elf line) are **dropped** to keep Elf to one theme. Gear efficiency (Human) is **dropped** for the same reason; it would also tie races to the item system.

### 3.4 The 16 cells

Legend: **R** = reuses existing statuses/skills/stats only (needs only the passive engine). **N** = needs a new rule feature (named).
Statuses referenced exist in `data/combat/effects.json`: fortify, haste, regen, focus, rage, sunder, weaken, slow, stun, shock.

| | sword_shield (tank) | greatsword (bruiser) | longbow (ranged DPS) | magic (AoE/support) |
|---|---|---|---|---|
| **Human** (Mastery) | **Rallying Drill**: every skill cast gives `fortify` (DEF +50%) to **all allies** for 3 s; internal cooldown 10 s. **R** | **Wide Arcs**: skill radius +25%, skill damage +10%. **N** (skill_mod radius) | **Trained Eye**: skill hits apply `sunder` to the target (100%) and skill crit rate +20. **R** + **N** (skill crit) | **Archmage**: skill damage +30%, skill cooldowns x0.85. *(Boss example: stronger skills)* **N** (skill_mod) |
| **Viking** (Fury) | **Unbroken**: the first time each wave HP drops below 35%, gain a shield = 25% max HP and pulse Bulwark at once. **N** (shield, self_low_hp event) | **Berserker**: ATK +0% at full HP, rising to +40% at 20% HP or less. A kill heals 6% max HP. **N** (low_hp_scaling) + **R** heal | **Headhunter**: a kill grants `rage` (ATK +30%, DEF -15%) for 8 s and `haste` for 4 s. **R** | **Blood Rite**: each skill costs 5% of current HP but deals +40% damage. Cannot cast below 10% HP. **N** (skill_mod hp_cost) |
| **Elf** (Lifebloom) | **Warden's Grove**: each blocked hit heals the most-hurt ally for 2% of that ally's max HP; cooldown 1 s. **N** (guard_block event) | **Living Bark**: gains `regen` (3% max HP/s) at wave start, and each kill refreshes it. **R** | **Moonlit Arrow**: every 5th basic shot also heals the most-hurt ally for 6% of their max HP. **N** (every_n counter) | **Bloomcaster**: skill hits heal the most-hurt ally for 25% of the damage dealt (cap 8% of their max HP per cast). *(Boss example: gains healing)* **N** (heal from damage) |
| **Runeborn** (Runes) | **Rune Aegis**: +1 rune per hit taken or blocked (max 5). At 5: shield self 20% max HP + `fortify` 4 s, runes reset. **N** (charges, shield) | **Runic Edge**: +1 rune per heavy hit (max 4). At 4: rune burst 80% ATK in 3 m + `shock` (cannot move) on all hit. **N** (charges, burst) | **Glyph Shot**: +1 rune per basic hit (max 6). At 6: `focus` (stamina regen +30, ult regen) for 8 s + shield self 8% max HP. **N** (charges, shield) + **R** focus | **Runeweaver**: +1 rune per skill cast (max 3). At 3: shield **all allies** for 10% of the caster's max HP. **N** (charges, shield) |

Distinctness check: no two cells share both a trigger and an outcome. Human = *skills* in 4 ways (team buff, size, debuff, raw power). Viking = *HP threshold or kill* in 4 ways (shield, scaling ATK, kill buff, HP as fuel). Elf = *healing* from 4 sources (blocks, kills, shot count, skill damage). Runeborn = *charges* fed by 4 class actions (being hit, heavies, shots, casts) that release 4 different payloads.

Count: 3 cells are pure **R** (Human S&S, Viking bow, Elf GS). They need only the passive engine and the existing statuses. The other 13 need at least one of these new features: Fighter shield, low-HP scaling, skill_mod, charges, burst, and the new events guard_block / self_low_hp / every_n.

### 3.5 Squad synergies

A squad of 3 has exactly **one** active synergy, chosen by its race mix (first match wins):

| Mix | Name | Bonus (applies to all squad members) |
|---|---|---|
| 3 of one race | **Trio** | that race's `synergy.3` (strong, themed) |
| 2 of one race (+1 other) | **Pair** | that race's `synergy.2` (moderate, themed) |
| 3 different races | **Alliance** | +8% max HP and +8% ATK (generic, from `data/races/rules.json`) |

Squads of 1-2 cards: 2 of a race -> Pair. A solo card has no synergy. Every full squad gets *something*, so no mix is a "dead" choice. The choice is themed depth (Pair/Trio) against flexibility (Alliance).

| Race | Pair (2) | Trio (3) |
|---|---|---|
| Human | all skill damage +10% | skill damage +20%, skill cooldowns x0.90 |
| Viking | all allies: ATK +15% while below 50% HP | ATK +20% below 50% HP, and every kill heals the killer 4% max HP |
| Elf | all healing received +20% (`HEALING` pseudo-stat) | healing received +30%, and `regen` on every ally at wave start |
| Runeborn | shield every ally for 8% of their max HP at wave start | 12% at wave start, and the squad's rune gains are +1 |

Power budget (target, to verify by sim): Pair ~ Alliance ~ +6% squad power; Trio ~ +10% but narrower (one theme, and with 4 races and one card per class, a Trio is always reachable but forces race choices on all three cards).

### 3.6 Effect types (the whole vocabulary)

Passives, signatures, class stat profiles and synergies are **lists of effects**. The engine (`logic/race_passives.gd`, new, pure logic) knows exactly six types. An unknown `type`, action, event or target is a **load error** (the data test fails). It is never ignored silently at runtime.

| # | `type` | Fields | Why it exists |
|---|---|---|---|
| 1 | `stat_mod` | `stat`, `mul` or `add` | Always-on stats (class profiles, Alliance, Elf pair HEALING). Feeds the existing stats pipeline; no new rule. |
| 2 | `low_hp_scaling` | `stat`, `max_mul`, `from_hp` (1.0), `full_at_hp` (0.2), `below` (optional gate) | Fury needs a value that moves with HP. One formula (4.1) covers Berserker and the Viking pair/trio. |
| 3 | `skill_mod` | `damage_mul`, `cooldown_mul`, `radius_mul`, `crit_add`, `hp_cost` | Human and Blood Rite change skill-build casts. One hook in `logic/skills/` where a cast resolves. |
| 4 | `trigger` | `on` (event), `actions` [ ], `chance`, `every_n`, `cooldown_ticks`, `once_per_wave` | The general "when X, do Y". Replaces one-off types like on_kill_heal or shield_on_wave_start with one tested dispatcher. |
| 5 | `charges` | `gain_on` (event), `gain` (1), `max`, `actions` [ ] | Runes: count events, fire `actions` at `max`, reset. Separate from `trigger` because it keeps state between events. |
| 6 | `aggro` | `radius`, `every_ticks`, `duration_ticks` | Tank taunt. Only a class signature uses it; it is the one effect that writes to enemy AI. |

**Events** (`on` / `gain_on`), fixed list: `wave_start, hit, heavy_hit, skill_cast, skill_hit, kill, hurt, guard_block, self_low_hp` (threshold in `hp_below`).
**Actions**, fixed list: `apply_status {status, target, duration?}` (any id in effects.json), `heal {target, fraction_of: max_hp|damage, fraction, cap_max_hp?}`, `shield {target, fraction_of_source_max_hp, duration_ticks}`, `burst {atk_mul, radius, status?}`, `pulse_aggro`.
**Targets**, fixed list: `self, target, allies_all, ally_most_hurt, enemies_in_radius`.

Example: Elf + magic:
```json
{"type": "trigger", "on": "skill_hit",
 "actions": [{"action": "heal", "target": "ally_most_hurt", "fraction_of": "damage", "fraction": 0.25, "cap_max_hp": 0.08}]}
```

### 3.7 Data model

**`data/races/<id>.json`** (one file per race; the folder listing *is* the race list, same pattern as `data/classes/`):
```json
{
  "id": "elf", "name": "Elf", "order": 3, "theme": "lifebloom",
  "summary": "Healing that flows to allies.",
  "look": {"ears": "elf_long", "hair_extra": "", "beard": "", "face_paint": "", "skin_decal": "", "emblem": "res://art/ui/races/elf.png"},
  "class_passives": {
    "sword_shield": {"name": "Warden's Grove", "text": "Blocking heals the most-hurt ally 2% max HP (1 s).", "effects": [ ... ]},
    "greatsword":   {"name": "Living Bark", "text": "...", "effects": [ ... ]},
    "longbow":      {"name": "Moonlit Arrow", "text": "...", "effects": [ ... ]},
    "magic":        {"name": "Bloomcaster", "text": "...", "effects": [ ... ]}
  },
  "default_passive": {"name": "Lifebloom", "text": "Healing received +15%.", "effects": [{"type": "stat_mod", "stat": "HEALING", "mul": 0.15}]},
  "synergy": {"2": {"text": "...", "effects": [ ... ]}, "3": {"text": "...", "effects": [ ... ]}}
}
```
`default_passive` is used when a class has no entry. A **new class** then works with every race at once (data only). The data test *warns* (does not fail) about missing cells, so the team knows a cell still needs designing.

**`data/races/rules.json`**: the shared numbers: `alliance` effects, `shield_cap_max_hp` (0.30), `heal_cap_per_second_max_hp` (0.06), `cooldown_mul_floor` (0.60), `starter_races` {class: race}, `default_race` ("human").

**Card** (`logic/card_deck.gd`): new part `race` on every card (`card.race = "elf"`). It is added to `LATER_PARTS` with the value from `starter_races` for that class (fallback `default_race`), so old saves stay valid. `validate_card` checks that the race file exists. Race changes go through a new server-validated command `card_race` (`logic/commands.gd`), like `card_look`. Online sync carries the field in the deck it already sends.

**Classes**: `data/classes/<id>.json` gains `class_stats`, `pilot`, `signature` (3.2). The auto-pilot reads `pilot` instead of constants.

**Adding a race** = add `data/races/<id>.json` (+ art). **Adding a class** = add `data/classes/<id>.json` with its blocks; it then gets each race's `default_passive` until its cells are written. No code changes either way, as long as the new content uses the six effect types.

### 3.8 Visual identity (no rig changes; Studio 102-joint rig)

| Race | Art asks | Method (no new joints) |
|---|---|---|
| Human | none (baseline) | - |
| Elf | long pointed ears (2 shapes) | Prefer a morph on the head mesh if the Studio has one; else a rigid ear piece weighted 100% to the existing head joint |
| Viking | 2 braid hair variants, 2 beards, 3 war-paint face decals | Braids as new hair-only files like `hair_g.glb` (same hair pipeline); beard weighted to head/jaw; paint as a face texture overlay |
| Runeborn | rune skin-decal set (arms, neck, face), emissive with a slow pulse; optional glow tint on the eyes | Overlay texture + emissive material parameter on the existing skin material; pulse in the client shader |
| All | 4 race emblems + 3 synergy icons (Pair/Trio/Alliance) for card and squad bar | 2D via the Codex workflow (`docs/tech/codex_image_workflow.md`), Boss review before import |

Race looks are **game additions** beyond the Studio source. Under the Studio-parity directive they need an explicit Boss OK (Q4). They layer on top of the card's look choices (hair colour, eyes, makeup) and never replace them.

### 3.9 Acquisition (two options)

- **A. Free race choice (recommended for v1)**: every card can switch to any race at any time in the hub (Tailor or Character screen). It is free, like changing a look, and squad building stays a pure decision. New cards start with `starter_races`: sword_shield Human, greatsword Viking, longbow Elf, magic Runeborn. The starter squad (S&S/GS/bow) is then H/V/E = **Alliance**, which shows the synergy system on day one.
- **B. Race awakening**: cards start with their starter race. A "Race Sigil" (boss/chest drop) unlocks one race on one card for good, and the card can then switch freely among its unlocked races. This adds a chase, but locks squad building behind drops early on.

Recommendation: **A now**. Keep an optional `unlock` key in the race file schema (unused) so B can be layered on later without a save migration.

## 4. Formulas

**4.1 Low-HP scaling.** `h` = current HP / max HP (0..1). `bonus = max_mul * clamp((from_hp - h) / (from_hp - full_at_hp), 0, 1)`.
Berserker (max 0.40, from 1.0, full 0.2): h=1.0 -> 0; h=0.6 -> 0.20; h=0.5 -> 0.25; h<=0.2 -> 0.40. A `below` gate (Viking pair 0.5) makes it a step: 0 above, full value below.

**4.2 Heal from damage.** `heal = min(fraction * damage_dealt, cap_max_hp * target_max_hp) * target.heal_factor()`. Bloomcaster: a 300-damage skill hit, ally max 1000 -> min(75, 80) = 75. `heal_factor` already includes `wound` and the `HEALING` stat. Global safety: total race healing into one target in one second is <= `heal_cap_per_second_max_hp` (6%).

**4.3 Shield.** `amount = fraction * source_max_hp`. The target's total shield is <= `shield_cap_max_hp * target_max_hp` (30%). Shields absorb before HP, last `duration_ticks` (default 600), and are cleared at wave end. Runeweaver: mage max HP 750 -> 75 per ally per discharge.

**4.4 Skill mods.** Several `skill_mod`s multiply: `cooldown = base * product(cooldown_mul)`, floored at `base * cooldown_mul_floor` (0.60). Human Magic + Human Trio = 0.85 * 0.90 = 0.765 (above the floor). `damage = base * product(damage_mul)`. Human mage in a Human Trio = 1.30 * 1.20 = 1.56x.

**4.5 Power budget (design target, verify by sim).** Cell value ~ +8-10% effective power of that card (EHP x DPS). Pair/Alliance ~ +6% squad. Trio ~ +10% squad. A full race layer adds about +15% squad power, so `goblin_waves.json` `wave_power_by_squad[2]` must be re-tuned to bring the starter squad back to **72-75%**. The knob is steep (+0.02 per step; 1.20 ~ 85-90%, 1.35 ~ 55%).

## 5. Edge Cases

- **Card with a race file that was removed**: on load the race falls back to `default_race` (the `repaired()` path) and the profile still loads. The server rejects `card_race` with an unknown id.
- **Class with no cell in a race**: `default_passive` is used and the data test warns.
- **Unknown effect type / event / action / target / status id**: data load error. `tests/` fails. Never a silent no-op.
- **Healing at full HP / dead allies**: `ally_most_hurt` skips dead and full-HP allies. If nobody is hurt, the heal is lost (no overheal into shields).
- **Shield stacking (Runeborn trio + Runeweaver + Rune Aegis)**: capped at 30% of max HP (4.3).
- **Viking + Elf "sweet spot"**: Elf heals pull a Viking out of low HP. This is accepted as self-balancing. `self_low_hp` triggers `once_per_wave` so heal and drop cycles cannot farm Unbroken.
- **Blood Rite at low HP**: cannot cast below 10% HP (no suicide). The HP cost is not damage: it does not trigger `hurt`, runes or lifesteal.
- **Taunt on the boss**: `aggro` works on the Goblin Chief too, but `control_immunity_ticks` does not apply because taunt is not a control effect. Bulwark's 8 s cycle with 3 s up keeps the boss free 5 of every 8 s.
- **Two longbows' marks / no longbow**: marks are per target. `marked_first` falls back to the class's normal target rule when nothing is marked.
- **Charges at wave end**: runes carry across waves within a run and reset at run end. This rewards long fights without snowballing between runs.
- **Solo / duo**: synergies count only living squad members at **run start**, not alive ones. A death does not switch the bonus off mid-wave (readability).
- **Determinism**: `chance` rolls use the fighter's sim RNG. Replays and online prediction stay exact.

## 6. Dependencies

| System | Direction | Contract |
|---|---|---|
| `logic/card_deck.gd` | race system -> deck | new `race` part, validate, repair, starter races |
| `logic/commands.gd` / server | deck -> server | `card_race` command validated like `card_look` |
| `logic/game_sim.gd`, `fighter.gd` | engine <-> sim | sim emits the event list (3.6). Fighter gains `shield` (today only `logic/skills/actor.gd` has shields: bridge or move) |
| `logic/skills/` (skill system) | engine -> skills | `skill_mod` hook at cast resolve; `skill_cast`/`skill_hit` events |
| `logic/auto_pilot.gd` | class data -> pilot | reads `pilot` block; marked-target preference |
| `logic/enemy_ai.gd` | engine -> AI | `aggro` override of target pick (today: nearest player) |
| `data/combat/effects.json` | reused | statuses referenced by id |
| `tools/balance/class_sim.gd` | measures | race modes (section 8) |
| Card/character screens, squad bar (client) | display | race picker, passive text, synergy banner and trigger VFX (UX spec to write) |
| Art (Blender + Codex 2D) | assets | 3.8 asks |
| `design/gdd/drops-and-rewards.md` | only if option B | Race Sigil would be a new drop |

## 7. Tuning Knobs

All in `data/races/*.json`, `data/races/rules.json`, `data/classes/*.json`.
- **Curve**: every cell number (safe range: each cell +5..12% card power), Pair/Trio/Alliance values (Alliance 5-10%), class stat profiles (HP 0.7-1.4x, DEF 0.7-1.5x).
- **Gate**: `shield_cap_max_hp` 0.2-0.4, `heal_cap_per_second_max_hp` 0.04-0.10, `cooldown_mul_floor` 0.5-0.75, aggro cycle (every 6-10 s, up 2-4 s), rune `max`.
- **Feel**: pilot `reaction`, `heavy_every`, `shoot_range` 6-8 m, `kite_distance` 2-4 m.
- Global difficulty: `wave_power_by_squad` (retune after races land).

## 8. Balance plan

**Targets**: starter squad 72-75% (Boss). For a fixed class trio, every race mix within **±5 pts** of the mean of all mixes. No single cell lifts a solo card more than **+12 pts**. Pair, Trio and Alliance mean win rates within **±4 pts** of each other.

**Role targets** (prove the classes now differ; class_sim prints per class): sword_shield takes >= 40% of squad damage taken. Longbow deals the most single-target (boss) damage. Magic has the most hits per cast plus healing/shield given. Greatsword has the highest average enemies per heavy. Solo win rates can spread (tank safest, mage most fragile). The squad number is what is held to 72-75%.

**class_sim additions** (`tools/balance/class_sim.gd`; the tool is measurement only):
- `only=cells`: 16 solo scenarios (`solo greatsword:viking`).
- `only=races`: the starter class trio x all 4^3 = 64 race mixes. Default `seeds=6` (~384 runs), grouped by synergy kind.
- `only=mono_race`: each of the 4 class trios x 4 Trios plus 1 Alliance mix.
- Arg `races=elf,elf,viking` to run one mix. Output adds per-card passive trigger counts, shield absorbed and race healing done.
- Flag lines: any mix > mean + 8 pts, any race in > 50% of the top-10 mixes.

**Dominant-combo risks**: (1) Elf Trio heal stacking -> near-unkillable. Mitigations: heal cap per second, `wound` from goblin mages. (2) Runeborn shields -> 30% cap. (3) Human Trio + Human mage skill spam -> cooldown floor. (4) Viking needs the tank to *let* HP drop; with an Elf healer it may never reach the scaling. Watch for Viking being a trap rather than broken. (5) Bulwark taunt + Elf S&S block-heals could make the tank the whole strategy; check the S&S damage-taken share.

## 9. Implementation phases (small steps, each with tests)

1. **Data + card field**: `data/races/` (4 files + rules.json), loader `logic/race_data.gd`, `card.race` + migration + `card_race` command. *Tests*: every race file loads; unknown type/event/status fails; old save gets its starter race; server rejects bad race id.
2. **Engine core (R cells)**: `logic/race_passives.gd` with `stat_mod`, `trigger` (apply_status, heal) and the sim events. *Tests*: each event fires once; Viking bow kill -> rage+haste; Elf GS wave start -> regen; determinism (same seed = same replay).
3. **Class identity**: `class_stats`, `pilot`, `signature` in class files; auto_pilot reads `pilot`; Hunter's Mark preference. *Tests*: classes without `pilot` behave as today; kite steps back; peel picks the right target. class_sim role metrics.
4. **New features**: Fighter shield (+cap), `low_hp_scaling`, `skill_mod`, `charges`, `burst`, `aggro`. One feature per step, each with its unit test and formula examples from section 4.
5. **Synergies**: compute at run start, show in the run result. *Tests*: AAA -> Trio, AAB -> Pair(A), ABC -> Alliance, solo -> none, duo AA -> Pair.
6. **class_sim race modes + tuning pass**, then re-tune `wave_power_by_squad`.
7. **UI** (ux spec first): race picker, cell text, synergy banner on the squad bar, trigger feedback (rune pips, shield bar).
8. **Art** (3.8) and **online rooms** (shared logic, so only the deck field and server check).

## 10. Acceptance Criteria

- Adding a 5th race file (test fixture) appears in the race list and works in a sim run with **zero code changes**. Adding a test class without cells gives it every race's `default_passive`.
- All 16 cells fire in a scripted sim (trigger count > 0 per run) and match their section-4 example numbers within rounding.
- Old saves load with `race` set from `starter_races`. Changing a race only works through the validated command.
- Starter squad (default races) wins 72-75% over 40 seeds after re-tuning. Balance targets in section 8 hold.
- Role metrics in section 8 hold (the tank takes >= 40% of the squad's damage taken, etc.).
- Playtest (experiential): from the fight alone, a tester can say which card is the tank, the cleaver, the sniper and the caster, and name the squad's synergy and what it did.
- Full test suite (`tests/run_all.gd`) passes.

## 11. OPEN QUESTIONS (for the Boss, via PO)

1. **How do cards get a race?** A. Free switch any time, all races open (**default**). B. Awakening drops unlock races per card.
2. **Starter races**: A. S&S Human, GS Viking, Bow Elf, Magic Runeborn, so the starter squad shows Alliance (**default**). B. All Human. C. Random per new player.
3. **"Three different races" bonus (Alliance)**: A. Yes, +8% HP and ATK, so every full squad gets a synergy (**default**). B. No, same-race synergies only (TFT-pure, makes mixed squads weaker).
4. **Race looks beyond the Studio source (ears, braids/beards/war paint, rune decals)**: A. Approved as game additions on the existing rig (**default**). B. Race shown only by emblem/card frame for now; the 3D looks come later.

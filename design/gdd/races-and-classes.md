# Races and Classes (race x class passives, race ultimates, squad synergies)

**Status**: Draft v2 (standard rigor) · **Date**: 2026-11-13 · **Author**: game-designer, for the PO/Boss
**Source decisions**: Boss 2026-11-13 (PROGRESS.md): any card can be any race; abilities differ per race x class pair, axes clearly separated; 4 races (Human, Viking, Elf, Runeborn); TFT-style race synergies; new races/classes are data only. **v2 (Boss 2026-11-13)**: each race gives a card a passive **and** a race ULTIMATE, both specific to the race x class pair (16 + 16, all distinct). The ultimate uses the existing ultimate gauge (charge, fire when full) and replaces the paused weapon ultimates. The 4 class skills per class stay as they are. Section 12 records the Boss answers to the 4 earlier questions.
**Every number below is a PLACEHOLDER** until `tools/balance/class_sim.gd` measures it and the Boss plays it. `OPEN` items have a default the PO may apply (docs/po_defaults.md rule).

## 1. Overview

A card today is a class (one card per class, `logic/card_deck.gd`). This system adds a second axis: **race**. Each card carries one race. The class says *what the card does in the fight* (role, position, auto-pilot behaviour, 4 class skills). The race says *how it does it*. Each race has one theme. The theme turns into two things per class: one **passive** (always on) and one **race ultimate** (charges a gauge, fires when full). That gives 4 x 4 = 16 passives and 16 ultimates, all distinct. A squad of 3 then gets **one** race synergy from its race mix: a pair, a trio or "three different races". This gives the player a real squad-building puzzle before every run. Example: "Elf mage for the revive ultimate, or a Viking greatsword for the whirl and the Alliance bonus?" Races, passives, ultimates and synergies live only in `data/races/`. A small fixed set of effect types and actions, read by one rules module in `logic/`, runs them.

## 2. Player Fantasy

- **Squad-builder fantasy (Expression, Challenge-as-strategy)**: "I built this team." In an auto-battler the player's agency is almost all *before* the fight, so the choices must be readable and must change the fight in ways you can see.
- **Identity fantasy (Fantasy)**: a Viking greatsword that gets more dangerous as it bleeds is a different character from an Elf greatsword that never seems to go down, even with the same class and skills.
- **Climax moments (Sensation)**: the ultimate is the payoff beat of each fight. The gauge builds tension, then a big name callout, a race-coloured flash and a large effect release it. Each card gets about one of these per 25 s of combat, so a wave has several small climaxes. This is the sawtooth rhythm inside a wave.
- **SDT**: Autonomy (16 cells x synergy choice, several viable squads), Competence (the synergy, passive and ultimate triggers show on screen, so the player learns *why* a squad won), Relatedness (the race look on the card makes each card a character, not a stat block).
- **Bartle/QF**: Achievers chase all 16 cells. Explorers find combos (Viking + Elf healer, Runeborn ultimates that fire their own passives). Strategists (Mastery) optimise synergies.

## 3. Detailed Rules

### 3.1 Two axes, kept apart

| Axis | Owns | Never owns |
|---|---|---|
| **Class** (`data/classes/<id>.json` + `data/combat/weapons.json` style) | role, front/back line, base stat profile, auto-pilot profile, weapon moves, 4 class skills, signature mechanic, **gauge fill rates**, the **animation clip** the ultimate plays | healing/shields/fury/runes (race themes) |
| **Race** (`data/races/<id>.json`) | one theme, its 4 class passives, its **4 class ultimates** (effect, pilot fire rule, VFX colour), its synergy bonuses, its look | stat profile of the class, targeting, weapons |

Rule of thumb for reviewers: if you cover the race name, the passive and the ultimate still read as the race's theme. If you cover the class name, they still make sense only for that class's role.

### 3.2 Class identities (sharper than now)

Today the classes differ mainly by weapon move numbers. The auto-pilot treats them almost the same: walk to the nearest enemy, swing, try skills in turn, and stand off at 6 m if the class shoots. Solo win rates are within 72-85% and greatsword = sword & shield (77.5%). The proposal below gives each class a **stat profile**, a **pilot profile** and a **signature mechanic**, all in data.

| Class | Role | Line | Stat profile (`class_stats`, mul on base unless `add`) | Pilot profile (what the auto-pilot does differently) | Signature mechanic |
|---|---|---|---|---|---|
| **sword_shield** | Tank / protector | Front | HP x1.30, DEF x1.40, ATK x0.85, EFFECT_RES +15 | `target: peel`: attacks the enemy nearest the most-hurt ally. Guard reaction 0.95 (others 0.85). Walks ahead of the squad at wave start. | **Bulwark (taunt)**: every 8 s, enemies within 5 m switch their target to this card for 3 s. NEW (enemy_ai target override). |
| **greatsword** | Bruiser / cleave | Front | HP x1.15, ATK x1.10, ATKSPD -10 | `target: densest`: walks to the enemy with the most other enemies within 2.5 m. Heavy every 3rd swing (others 4th). | **Cleave**: a heavy hit deals +15% damage per extra enemy it hits (max +45%). NEW (multi-hit count). Keeps its fortify/regen self-buffs (PO default 2026-11-12). |
| **longbow** | Ranged single-target DPS | Back | HP x0.80, DEF x0.80, ATK x1.15, CRIRATE +15, CRIDMG +20 | `target: lowest_hp` (finisher), but the boss is always the target while it is alive. Shoots from 7 m. **Kites**: steps back when an enemy is within 3 m and the dodge is off cooldown. | **Hunter's Mark**: the first hit on a new target applies `sunder` (existing status, DEF -40%). The other cards' pilots prefer a marked target when it is within their engage range, so the squad focus-fires. REUSE status + NEW pilot rule. |
| **magic** | AoE / control / support | Back | HP x0.75, DEF x0.75, STAREGEN x1.40, EFFECT_ACC +20. Basic bolt `power` 1.1 -> 0.9 | Shoots from 7 m. **Holds damage skills** until 2+ enemies are inside the skill radius (or the target is the boss). Casts `frost_armor` on the most-hurt ally below 60% HP. | **Spellweave**: most of the damage comes from skills (higher stamina regen, weaker bolts). REUSE (stats + skill system); the hold rule is NEW pilot logic. |

The pilot profile replaces the auto-pilot's current constants (`REACH`, `SHOOT_RANGE`, `HEAVY_EVERY`, `reaction`, `ULTIMATE_RANGE`). Those constants become the **defaults** when a class file has no `pilot` block. That keeps old behaviour for any class without one.

```json
"pilot": {"line": "front", "target": "peel", "engage_range": 0, "shoot_range": 0, "kite_distance": 0,
          "heavy_every": 4, "reaction": 0.95, "skill_min_targets": 1, "support_skill": "", "support_below": 0.0},
"gauge": {"dealt": 0.8, "taken": 1.4, "support": 1.0},
"class_stats": [{"type": "stat_mod", "stat": "HP", "mul": 0.30}, {"type": "stat_mod", "stat": "DEF", "mul": 0.40}],
"signature": [{"type": "aggro", "radius": 5.0, "every_ticks": 480, "duration_ticks": 180}]
```
`target` is one of a fixed set: `nearest | peel | densest | lowest_hp | marked_first`. `engage_range: 0` = derive from the weapon (today's rule). `gauge` = this class's multipliers on the shared gauge rule (3.10.2).

### 3.3 Race identities (one theme each)

| Race | Theme | One-line identity | Ultimate colour | Real look (Studio team) | Mockup until then (3.8) |
|---|---|---|---|---|---|
| **Human** | **Mastery**: skill power and efficiency | "Trained, disciplined: their skills hit harder and come back sooner." | Gold `#ffc23a` | Baseline | Gold name plate + gold rim |
| **Viking** | **Fury**: power grows as HP falls; kills feed it | "Most dangerous when nearly dead." | Blood red `#e0302a` | Braids, beard, war paint | Red name plate + ember aura |
| **Elf** | **Lifebloom**: healing that flows to allies | "The squad that will not stay down." | Leaf green `#4fe07a` | Long ears | Green name plate + leaf motes |
| **Runeborn** | **Runes**: charges build up, then discharge as shields or power | "A rhythm of build-up and release; arcane wards." | Cyan `#3fe6ff` + violet `#9a5cff` | Glowing rune skin marks | Cyan/violet name plate + rune ring |

Speed and evasion (from the brief's Elf line) are **dropped** to keep Elf to one theme. Gear efficiency (Human) is **dropped** for the same reason; it would also tie races to the item system.

### 3.4 The 16 passives

Legend: **R** = reuses existing statuses/skills/stats only (needs only the passive engine). **N** = needs a new rule feature (named).
Statuses referenced exist in `data/combat/effects.json`: fortify, haste, regen, focus, rage, sunder, weaken, slow, stun, shock.

| | sword_shield (tank) | greatsword (bruiser) | longbow (ranged DPS) | magic (AoE/support) |
|---|---|---|---|---|
| **Human** (Mastery) | **Rallying Drill**: every skill cast gives `fortify` (DEF +50%) to **all allies** for 3 s; internal cooldown 10 s. **R** | **Wide Arcs**: skill radius +25%, skill damage +10%. **N** (skill_mod radius) | **Trained Eye**: skill hits apply `sunder` to the target (100%) and skill crit rate +20. **R** + **N** (skill crit) | **Archmage**: skill damage +30%, skill cooldowns x0.85. *(Boss example: stronger skills)* **N** (skill_mod) |
| **Viking** (Fury) | **Unbroken**: the first time each wave HP drops below 35%, gain a shield = 25% max HP and pulse Bulwark at once. **N** (shield, self_low_hp event) | **Berserker**: ATK +0% at full HP, rising to +40% at 20% HP or less. A kill heals 6% max HP. **N** (low_hp_scaling) + **R** heal | **Headhunter**: a kill grants `rage` (ATK +30%, DEF -15%) for 8 s and `haste` for 4 s. **R** | **Blood Rite**: each skill costs 5% of current HP but deals +40% damage. Cannot cast below 10% HP. **N** (skill_mod hp_cost) |
| **Elf** (Lifebloom) | **Warden's Grove**: each blocked hit heals the most-hurt ally for 2% of that ally's max HP; cooldown 1 s. **N** (guard_block event) | **Living Bark**: gains `regen` (3% max HP/s) at wave start, and each kill refreshes it. **R** | **Moonlit Arrow**: every 5th basic shot also heals the most-hurt ally for 6% of their max HP. **N** (every_n counter) | **Bloomcaster**: skill hits heal the most-hurt ally for 25% of the damage dealt (cap 8% of their max HP per cast). *(Boss example: gains healing)* **N** (heal from damage) |
| **Runeborn** (Runes) | **Rune Aegis**: +1 rune per hit taken or blocked (max 5). At 5: shield self 20% max HP + `fortify` 4 s, runes reset. **N** (charges, shield) | **Runic Edge**: +1 rune per heavy hit (max 4). At 4: rune burst 80% ATK in 3 m + `shock` (cannot move) on all hit. **N** (charges, burst) | **Glyph Shot**: +1 rune per basic hit (max 6). At 6: `focus` (stamina regen +30) for 8 s + shield self 8% max HP. **N** (charges, shield) + **R** focus | **Runeweaver**: +1 rune per skill cast (max 3). At 3: shield **all allies** for 10% of the caster's max HP. **N** (charges, shield) |

Distinctness check: no two cells share both a trigger and an outcome. Human = *skills* in 4 ways (team buff, size, debuff, raw power). Viking = *HP threshold or kill* in 4 ways (shield, scaling ATK, kill buff, HP as fuel). Elf = *healing* from 4 sources (blocks, kills, shot count, skill damage). Runeborn = *charges* fed by 4 class actions (being hit, heavies, shots, casts) that release 4 different payloads.

Count: 3 cells are pure **R** (Human S&S, Viking bow, Elf GS). They need only the passive engine and the existing statuses. The other 13 need at least one of these new features: Fighter shield, low-HP scaling, skill_mod, charges, burst, and the new events guard_block / self_low_hp / every_n.

Runeborn and the ultimate: every Runeborn passive's `charges` also gains on the `ultimate_cast` event with `gain: "max"`. So **every Runeborn ultimate discharges that card's passive at once**: the race's "build-up, release" rhythm doubled. This is the only passive/ultimate link, and it is written in data (`gain_on` is a list).

### 3.5 Squad synergies

A squad of 3 has exactly **one** active synergy, chosen by its race mix (first match wins):

| Mix | Name | Bonus (applies to all squad members) |
|---|---|---|
| 3 of one race | **Trio** | that race's `synergy.3` (strong, themed) |
| 2 of one race (+1 other) | **Pair** | that race's `synergy.2` (moderate, themed) |
| 3 different races | **Alliance** | +8% max HP and +8% ATK (generic, from `data/races/rules.json`). DECIDED (Boss 2026-11-13). |

Squads of 1-2 cards: 2 of a race -> Pair. A solo card has no synergy. Every full squad gets *something*, so no mix is a "dead" choice. The choice is themed depth (Pair/Trio) against flexibility (Alliance).

| Race | Pair (2) | Trio (3) |
|---|---|---|
| Human | all skill damage +10% | skill damage +20%, skill cooldowns x0.90 |
| Viking | all allies: ATK +15% while below 50% HP | ATK +20% below 50% HP, and every kill heals the killer 4% max HP |
| Elf | all healing received +20% (`HEALING` pseudo-stat) | healing received +30%, and `regen` on every ally at wave start |
| Runeborn | shield every ally for 8% of their max HP at wave start | 12% at wave start, and the squad's rune gains are +1 |

Synergies do **not** touch the ultimate gauge (keeps the ultimate budget per card readable; 3.10.2).

Power budget (target, to verify by sim): Pair ~ Alliance ~ +6% squad power; Trio ~ +10% but narrower (one theme, and with 4 races and one card per class, a Trio is always reachable but forces race choices on all three cards).

### 3.6 Effect types and actions (the whole vocabulary)

Passives, signatures, class stat profiles, synergies **and ultimates** are built from one vocabulary. The engine (`logic/race_passives.gd`, new, pure logic) knows exactly six effect types. An unknown `type`, action, event, target, condition or status id is a **load error** (the data test fails). It is never ignored silently at runtime.

| # | `type` | Fields | Why it exists |
|---|---|---|---|
| 1 | `stat_mod` | `stat`, `mul` or `add` | Always-on stats (class profiles, Alliance, Elf pair HEALING). Feeds the existing stats pipeline; no new rule. |
| 2 | `low_hp_scaling` | `stat`, `max_mul`, `from_hp` (1.0), `full_at_hp` (0.2), `below` (optional gate) | Fury needs a value that moves with HP. One formula (4.1) covers Berserker and the Viking pair/trio. |
| 3 | `skill_mod` | `damage_mul`, `cooldown_mul`, `radius_mul`, `crit_add`, `hp_cost` | Human and Blood Rite change skill-build casts. One hook in `logic/skills/` where a cast resolves. |
| 4 | `trigger` | `on` (event), `actions` [ ], `chance`, `every_n`, `cooldown_ticks`, `once_per_wave` | The general "when X, do Y". Replaces one-off types like on_kill_heal or shield_on_wave_start with one tested dispatcher. |
| 5 | `charges` | `gain_on` (event or list of events), `gain` (int, or `"max"`), `max`, `actions` [ ] | Runes: count events, fire `actions` at `max`, reset. Separate from `trigger` because it keeps state between events. |
| 6 | `aggro` | `radius`, `every_ticks`, `duration_ticks` | Tank taunt. Only a class signature uses it; it is the one effect that writes to enemy AI. |

An **ultimate is not a seventh effect type**: it is an `actions` list that runs once when the gauge fires (3.10.3). So ultimates use the same actions as triggers and charges.

**Events** (`on` / `gain_on`), fixed list: `wave_start, hit, heavy_hit, skill_cast, skill_hit, kill, hurt, guard_block, self_low_hp` (threshold in `hp_below`), **`ultimate_cast`** (new in v2).

**Actions**, fixed list (v1 five + **two new** in v2):

| Action | Fields | Notes |
|---|---|---|
| `apply_status` | `status`, `target`, `duration?` | any id in effects.json |
| `heal` | `target`, `fraction_of: max_hp \| damage \| source_max_hp`, `fraction`, `cap_max_hp?`, `split?` | `split: true` = the amount is shared evenly across the targets. Healing a **downed** ally (target `ally_downed`) revives it at that amount (3.10.5). |
| `shield` | `target`, `fraction_of: source_max_hp \| damage`, `fraction`, `duration_ticks`, `cap_max_hp?`, `split?` | |
| `burst` | `atk_mul`, `radius`, `center`, `status?`, `hits?` (1), `interval_ticks?`, `force_crit?`, `bonus_target_below_hp?` + `bonus_mul?`, `chain_on_kill?`, `fury?`, `delayed?` {`ticks`, `atk_mul`, `radius`, `status?`} | v2 adds **fields** only: repeat hits, target-HP bonus, chain on kill, Fury scaling (4.6), a delayed detonation on each hit target |
| `pulse_aggro` | `radius?` (5), `duration_ticks?` (180) | v2 adds the two fields (v1 used the Bulwark values) |
| **`zone`** (NEW) | `center`, `radius`, `duration_ticks`, `every_ticks`, `follow?`, `extend_on_kill_ticks?` + `extend_max_ticks?`, `pulse` [actions], `on_end?` [actions] | A lasting area that re-runs its `pulse` actions on whatever is inside it every `every_ticks`. |
| **`skill_refresh`** (NEW) | `target`, `fraction?` (of remaining cooldown), `seconds?` (flat), `cap_seconds?` | Cuts the remaining cooldowns of the target's 4 class skills. |

Why the two new actions are needed:
- **`zone`**: 6 of the 16 ultimates are "for N seconds, in this area" (a grove, a whirl, a blood moon, a vortex). One-shot actions cannot express time, and a chain of triggers cannot either (triggers need an event). The skill system's ground zones live inside skill Resources (`data/skill_system/skills/*.tres`) and cannot run race actions. One generic zone action is smaller than four special cases.
- **`skill_refresh`**: Human's theme is skills. 3 of the 4 Human ultimates must touch skill cooldowns, and no existing action can reach the skill-build caster's cooldowns. It needs one hook in `logic/skills/` (the same module `skill_mod` already touches).

No third action was added. Revive is a `heal` on the new target `ally_downed`. Fury is a `burst` field. Delayed glyphs are a `burst` field. The HP cost is an ultimate field (3.10.3).

**Targets**, fixed list: `self, target, allies_all, ally_most_hurt, enemies_in_radius`, plus v2: `ally_downed` (all downed allies), `allies_in_zone`, `enemies_in_zone`, `enemy_lowest_hp_pct`, `enemy_highest_hp`.
**Centers** (where a burst/zone sits), fixed list: `self, target, densest` (the point within `cast_range` that has the most enemies within `radius`), `boss_or_highest_hp`, `ally_most_hurt`.

Example: Elf + magic passive:
```json
{"type": "trigger", "on": "skill_hit",
 "actions": [{"action": "heal", "target": "ally_most_hurt", "fraction_of": "damage", "fraction": 0.25, "cap_max_hp": 0.08}]}
```

### 3.7 Data model

**`data/races/<id>.json`** (one file per race; the folder listing *is* the race list, same pattern as `data/classes/`). Each class block now holds `passive` and `ultimate`. Full example, Elf:

```json
{
  "id": "elf", "name": "Elf", "order": 3, "theme": "lifebloom",
  "summary": "Healing that flows to allies.",
  "color": "#4fe07a", "color_2": "",
  "look": {"ears": "elf_long", "hair_extra": "", "beard": "", "face_paint": "", "skin_decal": "", "emblem": "res://art/ui/races/elf.png"},
  "mockup": {"plate_color": "#4fe07a", "rim_color": "#4fe07a", "aura_vfx": "race_aura/elf", "badge_text": "E"},
  "classes": {
    "sword_shield": {
      "passive": {"name": "Warden's Grove", "text": "Blocking heals the most-hurt ally 2% max HP (1 s).",
        "effects": [{"type": "trigger", "on": "guard_block", "cooldown_ticks": 60,
          "actions": [{"action": "heal", "target": "ally_most_hurt", "fraction_of": "max_hp", "fraction": 0.02}]}]},
      "ultimate": {"name": "Heartwood Bastion", "text": "A grove for 6 s: allies inside heal 2.5%/s, enemies are slowed and taunted.",
        "clip": "ultimate", "cast_ticks": 48, "recover_ticks": 24, "charge_mul": 1.0, "vfx": "race_ult/elf_sword_shield",
        "actions": [
          {"action": "pulse_aggro", "radius": 5.0, "duration_ticks": 180},
          {"action": "zone", "center": "self", "radius": 5.0, "duration_ticks": 360, "every_ticks": 30, "follow": false,
           "pulse": [{"action": "heal", "target": "allies_in_zone", "fraction_of": "max_hp", "fraction": 0.0125},
                     {"action": "apply_status", "status": "slow", "target": "enemies_in_zone", "duration": 60}]}],
        "use": {"any_of": [{"if": "ally_hurt", "below": 0.65, "allies_within": 5.0, "min_allies": 2},
                           {"if": "squad_hp_below", "below": 0.70, "enemies_within": 5.0, "min": 2}],
                "max_hold_ticks": 360}}
    },
    "greatsword": {
      "passive": {"name": "Living Bark", "text": "Regen at wave start; each kill refreshes it.",
        "effects": [{"type": "trigger", "on": "wave_start", "actions": [{"action": "apply_status", "status": "regen", "target": "self"}]},
                    {"type": "trigger", "on": "kill", "actions": [{"action": "apply_status", "status": "regen", "target": "self"}]}]},
      "ultimate": {"name": "Thornbloom Cleave", "text": "A 180% sweep; 40% of the damage heals the squad.",
        "clip": "ultimate", "cast_ticks": 30, "recover_ticks": 30, "charge_mul": 1.0, "vfx": "race_ult/elf_greatsword",
        "actions": [
          {"action": "burst", "center": "self", "radius": 3.5, "atk_mul": 1.8, "status": "slow"},
          {"action": "heal", "target": "allies_all", "fraction_of": "damage", "fraction": 0.40, "split": true, "cap_max_hp": 0.12}],
        "use": {"any_of": [{"if": "enemies_near", "radius": 3.5, "min": 3, "and_ally_hurt_below": 0.75},
                           {"if": "enemies_near", "radius": 3.5, "min": 4}],
                "max_hold_ticks": 360}}
    },
    "longbow": {
      "passive": {"name": "Moonlit Arrow", "text": "Every 5th shot heals the most-hurt ally 6% max HP.",
        "effects": [{"type": "trigger", "on": "hit", "every_n": 5,
          "actions": [{"action": "heal", "target": "ally_most_hurt", "fraction_of": "max_hp", "fraction": 0.06}]}]},
      "ultimate": {"name": "Guardian Seedshot", "text": "Heals the most-hurt ally 15% + regen, then 4 arrows at the enemies on them.",
        "clip": "ultimate", "cast_ticks": 42, "recover_ticks": 20, "charge_mul": 1.0, "vfx": "race_ult/elf_longbow",
        "actions": [
          {"action": "heal", "target": "ally_most_hurt", "fraction_of": "max_hp", "fraction": 0.15},
          {"action": "apply_status", "status": "regen", "target": "ally_most_hurt", "duration": 360},
          {"action": "burst", "center": "ally_most_hurt", "radius": 4.0, "atk_mul": 1.0, "hits": 4, "interval_ticks": 15, "status": "slow"}],
        "use": {"any_of": [{"if": "ally_hurt", "below": 0.50},
                           {"if": "ally_hurt", "below": 0.65, "targeted_by_min": 2}],
                "max_hold_ticks": 360}}
    },
    "magic": {
      "passive": {"name": "Bloomcaster", "text": "Skill hits heal the most-hurt ally 25% of damage (cap 8%).",
        "effects": [{"type": "trigger", "on": "skill_hit",
          "actions": [{"action": "heal", "target": "ally_most_hurt", "fraction_of": "damage", "fraction": 0.25, "cap_max_hp": 0.08}]}]},
      "ultimate": {"name": "Rebirth Bloom", "text": "Revives downed allies at 35% HP, heals the squad 20%, regen for all.",
        "clip": "ultimate", "cast_ticks": 54, "recover_ticks": 24, "charge_mul": 0.85, "vfx": "race_ult/elf_magic",
        "actions": [
          {"action": "heal", "target": "ally_downed", "fraction_of": "max_hp", "fraction": 0.35},
          {"action": "heal", "target": "allies_all", "fraction_of": "max_hp", "fraction": 0.20},
          {"action": "apply_status", "status": "regen", "target": "allies_all", "duration": 360}],
        "use": {"any_of": [{"if": "ally_downed"},
                           {"if": "squad_hp_below", "below": 0.55},
                           {"if": "ally_hurt", "below": 0.50, "min_allies": 2}],
                "max_hold_ticks": 600}}
    }
  },
  "default_class": {
    "passive": {"name": "Lifebloom", "text": "Healing received +15%.", "effects": [{"type": "stat_mod", "stat": "HEALING", "mul": 0.15}]},
    "ultimate": {"name": "Lifebloom Surge", "text": "Heals all allies 15% max HP.", "clip": "ultimate", "cast_ticks": 40, "recover_ticks": 20,
      "charge_mul": 1.0, "vfx": "race_ult/elf_default",
      "actions": [{"action": "heal", "target": "allies_all", "fraction_of": "max_hp", "fraction": 0.15}],
      "use": {"any_of": [{"if": "squad_hp_below", "below": 0.65}], "max_hold_ticks": 360}}
  },
  "synergy": {
    "2": {"text": "Healing received +20%.", "effects": [{"type": "stat_mod", "stat": "HEALING", "mul": 0.20}]},
    "3": {"text": "Healing received +30%; regen on every ally at wave start.",
          "effects": [{"type": "stat_mod", "stat": "HEALING", "mul": 0.30},
                      {"type": "trigger", "on": "wave_start", "actions": [{"action": "apply_status", "status": "regen", "target": "self"}]}]}
  },
  "unlock": null
}
```

Ultimate block fields: `name`, `text` (card tooltip), `clip` (a key of the class file's `moves` map: `ultimate`, `special` or `charge`, so the clip follows the class), `cast_ticks` (wind-up before the actions run), `recover_ticks`, `charge_mul` (gauge fill multiplier for this cell, 0.7-1.2), `self_hp_cost?` + `min_hp?` (Viking magic), `vfx` (a `data/combat/vfx.json` key), `actions` [ ], `use` (pilot fire rule, 3.10.4).
`use` conditions, fixed list: `enemies_near {radius, min}`, `enemies_at_point {cast_range, radius, min}`, `ally_hurt {below, min_allies?, allies_within?, targeted_by_min?}`, `squad_hp_below {below}`, `ally_downed`, `self_hurt {below}`, `boss_near {radius}`, `elite_near {radius}`, `execute_ready {range, below}`, `skills_on_cooldown {min, allies?}`, `boss_telegraph {radius}`. `any_of` = fire when any matches. `max_hold_ticks` = fire anyway after holding a full gauge this long while any enemy is within the class engage range (no ultimate is ever wasted by a pilot that waits forever).

`default_class` replaces v1's `default_passive`: used when a class has no entry, so a **new class** gets a passive and an ultimate from every race at once (data only). The data test *warns* (does not fail) about missing cells.

**`data/races/rules.json`**: shared numbers: `alliance` effects, `shield_cap_max_hp` (0.30), `ult_shield_cap_max_hp` (0.50), `heal_cap_per_second_max_hp` (0.06, ultimates exempt, 4.2), `cooldown_mul_floor` (0.60), `starter_races` {class: race}, `default_race` ("human"), `ultimates_enabled` (true), and the `gauge` block (3.10.2).

**New statuses** (data only, `data/combat/effects.json`): `valor` (ATK +20%, DEF +20%, 360 ticks), `unbowed` (ATK +30%, DEF +40%, 360 ticks), `recital` (SKILL_DMG +30%, STAREGEN +40, 360 ticks). `SKILL_DMG` is a new pseudo-stat read by the `skill_mod` hook, the same pattern as `HEALING`.

**Card** (`logic/card_deck.gd`): new part `race` on every card (`card.race = "elf"`). It is added to `LATER_PARTS` with the value from `starter_races` for that class (fallback `default_race`), so old saves stay valid. `validate_card` checks that the race file exists. Race changes go through a new server-validated command `card_race` (`logic/commands.gd`), like `card_look`. Online sync carries the field in the deck it already sends.

**Classes**: `data/classes/<id>.json` gains `class_stats`, `pilot`, `gauge`, `signature` (3.2). The auto-pilot reads `pilot` instead of constants.

**Adding a race** = add `data/races/<id>.json` (+ art or mockup colours). **Adding a class** = add `data/classes/<id>.json` with its blocks; it then gets each race's `default_class` until its cells are written. No code changes either way, as long as the new content uses this vocabulary.

### 3.8 Visual identity: mockups now, Studio art later (no rig changes; Studio 102-joint rig)

DECIDED (Boss 2026-11-13): the Studio art team makes the real race looks. Until then the game ships **mockups** that need no new model and no rig/material change to the Studio character.

**Mockups (build now, client only, all colours from the race file `mockup` block):**

| Where | Human | Viking | Elf | Runeborn |
|---|---|---|---|---|
| Card (hub, character screen) | gold name plate + letter badge "H" | red plate + "V" | green plate + "E" | cyan-to-violet plate + "R" |
| Squad panel | small coloured race badge next to the card name; synergy line under the squad (Pair/Trio/Alliance + race badges) | same | same | same |
| Battle: ground marker | thin gold ring at the feet | red ring | green ring | cyan ring with the existing `ground` layer `mode: glyph` |
| Battle: aura (`race_aura/<race>` in vfx.json, looping, low count) | none (baseline) | 3-4 slow red ember `mote`s rising | 3-4 green `mote`s drifting up | glyph ring pulse every 2 s |
| Battle: name tag / HP bar tint | gold | red | green | cyan |

All mockup layers use **existing** vfx layer types (`ground` ring/glyph, `burst` mote), so they need zero new art files. The badge letters are text, so they need no image until the emblems exist. A coloured toon rim/outline on the body was considered and **not** chosen: it would touch the Studio character material (parity rule). The ground ring gives the same "whose race is this" read without that risk.

**Real art (hand-off spec for the Studio team, unchanged from v1):**

| Race | Art asks | Method (no new joints) |
|---|---|---|
| Human | none (baseline) | - |
| Elf | long pointed ears (2 shapes) | Prefer a morph on the head mesh if the Studio has one; else a rigid ear piece weighted 100% to the existing head joint |
| Viking | 2 braid hair variants, 2 beards, 3 war-paint face decals | Braids as new hair-only files like `hair_g.glb` (same hair pipeline); beard weighted to head/jaw; paint as a face texture overlay |
| Runeborn | rune skin-decal set (arms, neck, face), emissive with a slow pulse; optional glow tint on the eyes | Overlay texture + emissive material parameter on the existing skin material; pulse in the client shader |
| All | 4 race emblems + 3 synergy icons (Pair/Trio/Alliance) for card and squad bar | 2D via the Codex workflow (`docs/tech/codex_image_workflow.md`), Boss review before import. They replace the letter badges. |

Real race looks layer on top of the card's look choices (hair colour, eyes, makeup) and never replace them. When they land, the battle aura stays (it is the ultimate-colour language), and the ground ring may be dropped.

### 3.9 Acquisition (DECIDED)

- **Free race choice** (Boss 2026-11-13): every card can switch to any race at any time in the hub (Tailor or Character screen), free, like changing a look. All 4 races exist from the start.
- **Starter races** (Boss 2026-11-13): sword_shield Human, greatsword Viking, longbow Elf, magic Runeborn. The 3-card starter squad (S&S/GS/bow) is H/V/E = **Alliance**, which shows the synergy system on day one.
- The race file schema keeps an optional `unlock` key (unused, `null`) so a drop-based unlock could be layered on later without a save migration.

### 3.10 Race ultimates

#### 3.10.1 The 16 ultimates

Every damage figure is % of the caster's ATK through the normal damage rule (DEF, crit). Heals/shields name their base. All cast from the class's `moves.ultimate` clip unless noted. Each is **one** full gauge.

| | sword_shield (tank) | greatsword (bruiser) | longbow (ranged DPS) | magic (AoE/support) |
|---|---|---|---|---|
| **Human** (gold) | **Commander's Call**: "Hold the line, then strike as one." | **Masterstroke**: "Three perfect arcs; every hit sharpens the next skill." | **Called Shot**: "One breath, one arrow." | **Grand Recital**: "Every spell, ready at once." |
| **Viking** (red) | **Unbowed Roar**: "Come at me. All of you." | **Ragnarok Whirl**: "Spin until nothing stands." | **Executioner's Volley**: "Finish them, one after another." | **Blood Moon**: "Pay in blood; the sky pays back." |
| **Elf** (green) | **Heartwood Bastion**: "Stand in my grove and you will not fall." | **Thornbloom Cleave**: "Every wound I deal heals my kin." | **Guardian Seedshot**: "An arrow that heals, then defends." | **Rebirth Bloom**: "The squad that will not stay down." |
| **Runeborn** (cyan/violet) | **Bastion Glyph**: "Every rune becomes a wall." | **Runebreaker**: "Shatter the ground with stored power." | **Glyph Barrage**: "Mark them all, then detonate." | **Arcane Singularity**: "Gather the power, return it as wards." |

Theme check: Human = skill cooldowns/skill power in 4 ways (team refresh, refresh per hit, refresh on kill, self full refresh). Viking = HP/kills in 4 ways (Fury-scaled taunt burst, kill-extended whirl, execute chain, HP-cost nuke). Elf = healing in 4 shapes (zone, damage-to-heal, single target + guard, revive). Runeborn = release in 4 shapes (team shield, slam + lingering zone, delayed glyphs, damage-to-shield), and every one also fires the card's rune passive.

**Mechanics, pilot rule and reuse per cell** (cast = `cast_ticks` at 60 ticks/s):

**Human**
- **H/S&S Commander's Call** — cast 0.8 s. `pulse_aggro` r5 m, 3 s. `skill_refresh` on `allies_all`, fraction 0.5 (halves every ally's remaining skill cooldowns). `valor` on `allies_all` 6 s (ATK +20%, DEF +20%). *Pilot*: 2+ allies each have 2+ skills on cooldown and 2+ enemies within 5 m; or the boss within 5 m. *Reuse*: `windup/ultimate` + `skill_cast/war_cry` (gold tint), `status/buff`. Clip `attack_2`.
- **H/GS Masterstroke** — cast 0.5 s. `burst` center self, r3.5 m, 110% x 3 hits, 0.4 s apart. The 3rd hit applies `stun` (75 ticks; control immunity applies, so bosses are not chain-locked). Each enemy hit: `skill_refresh` self 1 s flat, cap 4 s per cast. *Pilot*: 3+ enemies within 3.5 m, or the boss within 3 m. *Reuse*: `swing/blade_ultimate` trail x3, `skill_burst/shatter_smash` on hit 3. Clip `gs_high_spin_attack`.
- **H/Bow Called Shot** — aim 1.2 s (cannot be staggered while aiming). One shot at `boss_or_highest_hp` within 12 m: 450%, `force_crit`, `sunder` 7 s. If it kills: `skill_refresh` self fraction 1.0. *Pilot*: boss within 12 m; or an elite (knight/chief/brute) within 12 m; else `max_hold_ticks` 6 s. *Reuse*: `skill_cast/piercing_shot`, `skill_trail/piercing_shot` (already gold), `hit/crit`. Clip `lb_aim_overdraw`.
- **H/Magic Grand Recital** — cast 0.7 s. `skill_refresh` self fraction 1.0 (all 4 skills ready). `recital` self 6 s (SKILL_DMG +30%, STAREGEN +40). The class pilot then spends the skills on its normal rules. *Pilot*: 3+ of its 4 skills on cooldown and 2+ enemies within 7 m (or the boss). *Reuse*: `windup/ultimate` + a gold `ground` glyph ring (new vfx key, existing layers). Clip `mg_spell_2h_magic_area_attack_02`.

**Viking** (`fury`: damage x (1 + 1.5 x the caster's missing HP fraction), 4.6)
- **V/S&S Unbowed Roar** — cast 0.6 s. `pulse_aggro` r7 m, 4 s. `unbowed` self 6 s (ATK +30%, DEF +40%). `burst` center self r3 m, 100%, `fury`. *Pilot*: 3+ enemies within 7 m; or a back-line ally below 60% HP is targeted by an enemy; or self below 50% with 2+ enemies within 3 m. *Reuse*: `skill_cast/blood_shield` (crimson already), `swing/hammer_ultimate` ground layers. Clip `attack_2`.
- **V/GS Ragnarok Whirl** — cast 0.3 s. `zone` center self, `follow: true`, r3 m, 3 s, pulse every 0.5 s: 55% `fury` on `enemies_in_zone`. Each kill during the zone adds 0.5 s (max +2 s). The pilot walks toward `densest` at half speed while it spins. *Pilot*: 3+ enemies within 3 m. *Reuse*: `skill_burst/storm_blades` (crimson) per pulse, `swing/blade_ultimate`. Clip `gs_high_spin_attack` looped.
- **V/Bow Executioner's Volley** — aim 0.6 s. `burst` at `enemy_lowest_hp_pct` within 12 m, r0.6 m, 220%; x2 if the target is below 30% HP (`bonus_target_below_hp`). `chain_on_kill` 3: each kill fires a new arrow at the next lowest-HP% enemy. *Pilot*: an enemy within 12 m below 30% HP; or 3+ enemies below 50%; or the boss below 30%. *Reuse*: `skill_trail/piercing_shot` (red tint), `hit/crit`, `death`. Clip `lb_aim_overdraw`.
- **V/Magic Blood Moon** — `self_hp_cost` 15% current HP, `min_hp` 0.25 (cannot fire below 25%). Cast 0.9 s. `zone` at `densest` within 9 m, r4 m, 4 s, pulse every 0.5 s: 45% on `enemies_in_zone`, `fury` with factor 2.0 (the HP cost counts, so it pays for itself). `rage` on `allies_in_zone` 6 s (on the first pulse). *Pilot*: 3+ enemies inside r4 of a point within 9 m, and own HP >= 25%. *Reuse*: `skill_burst/fire_ring` (crimson tint) per pulse, `skill_burst/eruption` on cast. Clip `mg_spell_2h_magic_area_attack_02`.

**Elf** (full data in 3.7)
- **E/S&S Heartwood Bastion** — cast 0.8 s. `pulse_aggro` r5 m 3 s (pulls enemies into the grove). `zone` self r5 m 6 s: allies inside heal 2.5% max HP/s, enemies inside `slow`. *Pilot*: 2+ allies within 5 m and one below 65%; or squad average HP below 70% with 2+ enemies within 5 m. *Reuse*: `skill_burst/thorn_trap` (green tint), `skill_gem/regen` on healed allies. Clip `attack_2`.
- **E/GS Thornbloom Cleave** — cast 0.5 s. `burst` self r3.5 m, 180%, `slow`. Then `heal` `allies_all`, 40% of the damage the burst dealt, `split`, cap 12% max HP each. *Pilot*: 3+ enemies within 3.5 m and an ally below 75%; or 4+ enemies within 3.5 m. *Reuse*: `swing/blade_ultimate` (green), `skill_gem/regen`. Clip `gs_high_spin_attack`.
- **E/Bow Guardian Seedshot** — cast 0.7 s. `heal` the most-hurt ally 15% max HP + `regen` 6 s. Then `burst` centered on that ally, r4 m, 100% x 4 hits 0.25 s apart, each on the nearest enemy to the ally, `slow`. *Pilot*: an ally below 50%; or an ally below 65% targeted by 2+ enemies. *Reuse*: `skill_trail/ice_lance` (green tint) for the seed, `skill_trail/piercing_shot` arrows. Clip `lb_aim_overdraw`.
- **E/Magic Rebirth Bloom** — cast 0.9 s, `charge_mul` 0.85. Revive every downed ally at 35% max HP (once per ally per wave). `heal` all living allies 20% max HP. `regen` all 6 s. *Pilot*: any ally downed (fire at once); or squad average HP below 55%; or 2 allies below 50%. *Reuse*: `skill_cast/frost_armor` (green tint), `getup` on revived allies, `skill_gem/regen`. Clip `mg_spell_2h_magic_area_attack_02`.

**Runeborn** (every cast also fires `ultimate_cast` -> the card's rune passive discharges at once, 3.4)
- **R/S&S Bastion Glyph** — cast 0.7 s. `shield` `allies_all` 15% of the caster's max HP, 8 s. `pulse_aggro` r5 m 3 s. Then Rune Aegis fires (self shield 20% + `fortify`). *Pilot*: 3+ enemies within 5 m; or 2+ allies below 70%; or a boss telegraphed move within 4 m (`boss_telegraph`). *Reuse*: `skill_cast/frost_armor` (cyan), `block`. Clip `attack_2`.
- **R/GS Runebreaker** — cast 0.6 s. `burst` at `densest` within 4 m, r3 m, 200%, `shock`. `zone` there r3 m 3 s, pulse every 0.5 s 35%. Then Runic Edge fires (80% burst in 3 m + `shock`; shock immunity limits stacking). *Pilot*: 3+ enemies inside r3 of a point within 4 m. *Reuse*: `skill_burst/ground_slam` (violet tint), `ground` glyph layer for the zone. Clip `gs_slide_attack` (`clip: "charge"`, a leap).
- **R/Bow Glyph Barrage** — 6 arrows over 1.2 s, spread over distinct enemies within 12 m (the rest repeat on the boss, else the nearest). 70% each. Each hit leaves a glyph: `delayed` 2 s, 60% r1.5 m + `sunder`. Then Glyph Shot fires (`focus` + self shield). *Pilot*: 3+ enemies within 12 m; or the boss within 12 m. *Reuse*: `skill_trail/piercing_shot` (cyan), `skill_burst/chain_lightning` for detonations. Clip `lb_aim_overdraw`.
- **R/Magic Arcane Singularity** — cast 0.8 s. `zone` at `densest` within 9 m, r4 m, 4 s, pulse every 0.5 s 45%, `shock` on the first pulse. `on_end`: `shield` `allies_all` 30% of the zone's total damage, `split`, cap 15% max HP each. Then Runeweaver fires (shield all 10%). *Pilot*: 3+ enemies inside r4 of a point within 9 m. *Reuse*: `skill_burst/lightning_strike` (violet tint) per pulse, `skill_cast/frost_armor` for the shields. Clip `mg_spell_2h_magic_area_attack_02`.

#### 3.10.2 The gauge (one rule for all, class-tuned rates)

The gauge is `Fighter.gauge`, max `ultimate_gauge_max` (100, `data/combat/combat.json`). An ultimate costs the **full** gauge. It fills from four sources (formula 4.7):
- **Time**: 1.5 per second while the wave is in combat (so every card fires eventually, even a card that is losing).
- **Damage dealt** (basic, heavy, class skills, passives): 2.0 per 100% of the card's own ATK dealt. Normalising by own ATK means a high-ATK card does not fill faster just because its numbers are bigger.
- **Damage taken** (after shields): 1.2 per 1% of own max HP taken. The tank's main source.
- **Support given** (heal + shield given to allies, not self): 2.0 per 100% of own ATK.
- **Kill**: +4.

Each class scales those sources with its `gauge` block (S&S dealt 0.8 / taken 1.4; GS 1.0 / 1.0; bow 1.0 / 0.6; magic dealt 1.0 / taken 0.6 / support 1.2). Each ultimate can scale the whole gain with `charge_mul` (default 1.0; Rebirth Bloom 0.85).
- **No gain** while the ultimate is casting or from damage/heal/shield the ultimate itself does (no chaining).
- Overflow above 100 is lost. The pilot fires on its `use` rule or after `max_hold_ticks`.
- The gauge starts at **0** at run start, **carries across waves** within a run, and is cleared at run end.
- Synergies, statuses and the old `ULTREGEN` stat do not touch it in v1 (`focus` keeps its ULTREGEN line but the race gauge ignores ULTREGEN; see 3.10.6).

Target cadence: the first ultimate at about **20-25 s** of combat, then one every **22-28 s** per card.

#### 3.10.3 How a cast runs (rules)

1. The pilot (or, later, a player tap) sets `input.ultimate` on a tick when the gauge is full and the fighter is IDLE, grounded and not controlled (stun/sleep/shock).
2. The sim starts a synthetic move `<race>_<class>_ultimate` (built at load from the race file: startup = `cast_ticks`, recovery = `recover_ticks`, power 0, poise unbreakable, **no** i-frames). The gauge drops to 0 and the `ultimate_cast` event fires. Because the move id ends with `ultimate`, the existing `attack_started` event, the client clip mapping and class_sim's ultimate counter all work as they do for the old weapon ultimates.
3. At the end of the wind-up the race engine runs `actions` in order. `self_hp_cost` is taken first (not damage: no `hurt`, no runes, no gauge).
4. If the caster is killed or stunned during the wind-up, the cast is **lost** (the gauge stays at 0). This is the counterplay for enemies with interrupts and a reason to keep the tank alive.
5. The client shows the callout and race-coloured VFX (3.10.7) on the `attack_started` event.

#### 3.10.4 Auto-pilot fire rule

In `logic/auto_pilot.gd`, the ultimate check moves to **before** skills (as today) and becomes: gauge full AND IDLE AND the cell's `use` matches (or the gauge has been full for `max_hold_ticks` and an enemy is within the class engage range). `ULTIMATE_RANGE` (3.4 m) is no longer used for race ultimates; each `use` rule names its own ranges. Conditions are the fixed list in 3.7. Evaluation is cheap (it runs only when the gauge is full) and deterministic (no RNG).

#### 3.10.5 Revive rule (Rebirth Bloom)

`heal` on target `ally_downed` revives a downed squad member at `fraction` of max HP. It uses the same "downed -> alive" path the co-op revive uses (`revive_invulnerable_ticks` apply). Each ally can be revived by an ultimate **once per wave**. An ally who is fully dead (not downed, e.g. a mode without downed) cannot be targeted. If nobody is downed, that action does nothing and the rest of the ultimate still runs.

#### 3.10.6 Turning the gauge back on safely (logic touch points)

The skill-build system (`SkillBuild.enabled()`, `data/skill_system/integration.json`) stays **on**. The race ultimate is a separate switch: `data/races/rules.json` `ultimates_enabled`. Touch points (implementation by the programmers; listed for scope):

| File | Today | Change |
|---|---|---|
| `logic/game_sim.gd` ~l.219-222 | when SkillBuild is on, the player/squad input path clears `input.special` and `input.ultimate` | keep clearing `special`; when `ultimates_enabled` and the card has a race ultimate, **pass `input.ultimate` on to the race engine** (start the synthetic move) instead of dropping it |
| `logic/skills/system.gd` l.215 | `sim.fighters[id].gauge = 0` on every view publish ("retired gauge") | remove when `ultimates_enabled` (else every tick wipes the gauge) |
| `logic/skills/motion_prediction.gd` l.63 | `fighter.gauge = 0` for prediction | same switch, so online prediction and authority agree |
| `logic/combat.gd` l.369-373, l.480-483 | gauge += `gauge_per_hit_dealt` per melee hit; += ULTREGEN/60 per tick | race mode: the race engine owns the gain (4.7). Set `gauge_per_hit_dealt` 0 for the auto-battler or skip this branch when `ultimates_enabled`, so melee hits are not counted twice. Skill hits do not fill the gauge today; the race engine counts them from `skill_hit` / `skill_dot` events. |
| `logic/combat.gd` l.510-515 | `input.ultimate` starts the weapon style's `ultimate` move (blade skill packs from `data/combat/ultimates.json`) | race mode: never reached (game_sim routes the press). The weapon ultimates and their packs stay on disk, unused by the auto-battler |
| `logic/combat_data_loader.gd` | builds moves from weapons + ultimates.json | add the synthetic `<race>_<class>_ultimate` moves from the race files (or the race loader registers them into `CombatData.moves`) |
| `logic/auto_pilot.gd` l.109-113 | ultimate only when `not SkillBuild.enabled()` and within `ULTIMATE_RANGE` | the 3.10.4 rule, reading the cell's `use` |
| `logic/journey.gd` l.38/244, `logic/coop_journey.gd` | one gauge carried per player between stages | squad mode: the gauge lives on each card's Fighter and carries across waves; check that the journey carry does not overwrite squad members' gauges with the primary's |
| `logic/sim_input.gd`, `logic/net_wire.gd`, `logic/net/input_inbox.gd` | the `ultimate` bit is already encoded | no change expected; verify with an online test |
| `client/squad_panel.gd` l.12 | `SHOW_ULTIMATE := false` | read `ultimates_enabled` from data instead of a constant; show the fill and a "READY" pulse |
| new `logic/race_passives.gd` (+ `logic/race_data.gd`) | - | gauge gain from events, cast resolve, the 7 actions |

#### 3.10.7 Readability and art asks

- **Name callout**: on cast, a large banner with the ultimate name in the race colour over the caster (screen-space, 1.2 s, slides in). Only one callout on screen at a time; if two ultimates start within 0.5 s, the second callout queues 0.4 s (the effects themselves are not delayed).
- **Race colour on every ultimate effect**: Human gold `#ffc23a`, Viking red `#e0302a`, Elf green `#4fe07a`, Runeborn cyan `#3fe6ff` with violet `#9a5cff` secondary. Add these 5 to the `vfx.json` palette (`race_human`, `race_viking`, `race_elf`, `race_rune`, `race_rune_2`).
- **One vfx key per cell**, `race_ult/<race>_<class>`, built with `base` from the reused keys above plus layers of existing types. Needed client feature: a colour override so a `base` key plays in the race colour instead of its own `skill_colors` entry (today `weapon` colour in skill keys = `skill_colors[skill]`).
- **Gauge feedback**: squad panel fill bar in the race colour; a short glow + sound when full; the card plays its ultimate within a few seconds, so "full" should never sit long.

| Art ask | Who | New art? |
|---|---|---|
| 16 `race_ult/*` vfx keys + 4 `race_aura/*` keys + 5 palette colours | technical-artist (data in vfx.json) | No (existing layer types) |
| Colour override for `base` vfx keys | ui-programmer / technical-artist | Small client code |
| Callout banner: 4 race frames (gold/red/green/cyan-violet), text drawn by the game | ux-ui-designer via Codex, Boss review | Yes, 4 small 2D images |
| Ultimate-ready icon on the squad panel (1, tinted per race) | ux-ui-designer via Codex | Yes, 1 image |
| Race emblems + synergy icons (3.8) | via Codex | Yes, 7 images (replace mockup letters) |
| Distinct ultimate animation per race | - | **Not asked** in v1: each class uses its own existing ultimate clip for all 4 races; race reads through colour, callout and effect shape. A per-race clip would be a later Studio ask. |

## 4. Formulas

**4.1 Low-HP scaling.** `h` = current HP / max HP (0..1). `bonus = max_mul * clamp((from_hp - h) / (from_hp - full_at_hp), 0, 1)`.
Berserker (max 0.40, from 1.0, full 0.2): h=1.0 -> 0; h=0.6 -> 0.20; h=0.5 -> 0.25; h<=0.2 -> 0.40. A `below` gate (Viking pair 0.5) makes it a step: 0 above, full value below.

**4.2 Heal from damage.** `heal = min(fraction * damage_dealt, cap_max_hp * target_max_hp) * target.heal_factor()`. Bloomcaster: a 300-damage skill hit, ally max 1000 -> min(75, 80) = 75. `heal_factor` already includes `wound` and the `HEALING` stat. Global safety for passives: total race healing into one target in one second is <= `heal_cap_per_second_max_hp` (6%). **Ultimate heals are exempt** from that per-second cap (they are rare and are the payoff), but still pass through `heal_factor`.
With `split`: `each = min(fraction * damage_dealt / n_targets, cap_max_hp * target_max_hp)`. Thornbloom: 4 enemies x 250 = 1000 damage, 40% = 400 over 3 allies = 133 each; ally max 1000, cap 120 -> 120.

**4.3 Shield.** `amount = fraction * source_max_hp`. The target's total shield is <= `shield_cap_max_hp * target_max_hp` (30%), or <= `ult_shield_cap_max_hp` (50%) while any part of it came from an ultimate. Shields absorb before HP, last `duration_ticks` (default 600), and are cleared at wave end. Runeweaver: mage max HP 750 -> 75 per ally per discharge.

**4.4 Skill mods.** Several `skill_mod`s multiply: `cooldown = base * product(cooldown_mul)`, floored at `base * cooldown_mul_floor` (0.60). Human Magic + Human Trio = 0.85 * 0.90 = 0.765 (above the floor). `damage = base * product(damage_mul) * (1 + SKILL_DMG)`. Human mage in a Human Trio with `recital` = 1.30 * 1.20 * 1.30 = 2.03x for 6 s.
**Skill refresh**: `remaining' = max(0, remaining * (1 - fraction) - seconds)`. The floor does not apply (refresh is a one-off, not a rate).

**4.5 Power budget (design target, verify by sim).** Passive cell ~ +8-10% effective power of that card (EHP x DPS). Pair/Alliance ~ +6% squad. Trio ~ +10% squad. **Ultimate** ~ worth 4-5 s of that card's own sustained output per cast; at one cast per ~25 s that is ~ +15-20% card output. A full race layer (passives + ultimates + synergy) adds about +30% squad power, so `goblin_waves.json` `wave_power_by_squad[2]` must be re-tuned to bring the starter squad back to **72-75%**. The knob is steep (+0.02 per step; 1.20 ~ 85-90%, 1.35 ~ 55%), so expect a much larger step than v1 assumed; re-tune once with both layers on, not twice.

**4.6 Fury.** `damage = base_damage * (1 + fury_factor * m)`, `m` = caster missing HP fraction at the moment of the hit (0..1). `fury_factor` 1.5 (Blood Moon 2.0). Unbowed burst at 60% HP: 100% x (1 + 1.5 x 0.4) = 160%. Blood Moon: caster at 80% pays 12% -> 68% HP, m = 0.32 -> each pulse 45% x 1.64 = 74%; 8 pulses = 590% total on each enemy that stays in.

**4.7 Gauge gain.** Per tick for card `c`:
`gain = charge_mul * ( T/60 + Gd*md * dealt/ATK_c + Gt*mt * 100*taken/maxHP_c + Gs*ms * support/ATK_c ) + Gk * kills`
| Var | Meaning | Default | Range |
|---|---|---|---|
| T | time per second | 1.5 | 0.5-3 |
| Gd | per 100% own ATK dealt | 2.0 | 1-4 |
| Gt | per 1% own max HP taken | 1.2 | 0.5-2 |
| Gs | per 100% own ATK healed/shielded to allies | 2.0 | 1-4 |
| Gk | per kill | 4 | 0-10 |
| md, mt, ms | class multipliers (3.10.2) | 1.0 | 0.5-1.5 |
Examples: greatsword ATK 150 dealing 1.3x ATK/s -> 1.5 + 2.6 = 4.1/s + kills -> full in ~22-24 s. Tank taking 1.5% max HP/s, dealing 0.6x ATK/s -> 1.5 + 0.8*2.0*0.6 + 1.4*1.2*1.5 = 1.5 + 0.96 + 2.52 = 5.0/s -> 20 s. Bow dealing 1.6x ATK/s, taking little -> 1.5 + 3.2 = 4.7/s -> 21 s. Mage dealing 1.2x + healing 0.3x ATK/s -> 1.5 + 2.4 + 0.72 = 4.6/s -> 22 s. All inside the 20-28 s target.

## 5. Edge Cases

- **Card with a race file that was removed**: on load the race falls back to `default_race` (the `repaired()` path) and the profile still loads. The server rejects `card_race` with an unknown id.
- **Class with no cell in a race**: `default_class` (passive + ultimate) is used and the data test warns.
- **Unknown effect type / event / action / target / center / condition / status id / clip key**: data load error. `tests/` fails. Never a silent no-op.
- **Healing at full HP / dead allies**: `ally_most_hurt` skips dead and full-HP allies. If nobody is hurt, the heal is lost (no overheal into shields).
- **Shield stacking (Runeborn trio + Runeweaver + Rune Aegis + Bastion Glyph)**: capped at 30% of max HP, 50% while an ultimate shield is part of it (4.3).
- **Viking + Elf "sweet spot"**: Elf heals pull a Viking out of low HP, which lowers Fury. This is accepted as self-balancing. `self_low_hp` triggers `once_per_wave` so heal and drop cycles cannot farm Unbroken.
- **Blood Rite / Blood Moon at low HP**: Blood Rite cannot cast below 10% HP; Blood Moon cannot fire below 25% (the pilot waits; at `max_hold_ticks` it still does not fire below 25%). HP costs are not damage: no `hurt`, runes, lifesteal or gauge.
- **Taunt on the boss**: `aggro`/`pulse_aggro` work on the Goblin Chief too, but `control_immunity_ticks` does not apply because taunt is not a control effect. Bulwark's 8 s cycle with 3 s up keeps the boss free 5 of every 8 s; a tank ultimate taunt can overlap Bulwark but does not stack duration (the longer remaining one wins).
- **Stun/shock from ultimates on the boss**: normal control rules: EFFECT_RES and `control_immunity_ticks` apply, so Masterstroke and Runebreaker cannot chain-lock the boss.
- **Ultimate interrupted** (caster killed/stunned in the wind-up): cast lost, gauge stays 0 (3.10.3).
- **Ultimate with no valid target when it resolves** (enemies died during the wind-up): damage actions do nothing; heals/shields/statuses on allies still apply; a `zone` at `densest` falls back to the caster's position.
- **Two ultimates at once**: both resolve in fighter-id order on the same tick (deterministic). Callouts queue (3.10.7).
- **Called Shot / Executioner with nothing in 12 m**: the pilot does not fire (no `use` match; `max_hold_ticks` also needs an enemy in engage range).
- **Executioner chain**: max 3 extra arrows; a chain arrow never targets an enemy already hit by this cast.
- **Ragnarok Whirl extension**: +0.5 s per kill, total cap +2 s; the zone ends early if the caster is stunned or dies.
- **Rebirth Bloom with nobody downed**: revive part does nothing; the 20% heal and regen still apply. Revive is once per ally per wave.
- **Runeborn ultimate with runes already near max**: `gain: "max"` simply fills and discharges once; no double discharge.
- **Gauge at wave end**: carried into the next wave. Gauge at run end: cleared.
- **Skill-build off** (old mode / tests): race ultimates still work; `skill_refresh` has no skills to refresh and does nothing; Grand Recital still grants `recital`.
- **Two longbows' marks / no longbow**: marks are per target. `marked_first` falls back to the class's normal target rule when nothing is marked.
- **Charges at wave end**: runes carry across waves within a run and reset at run end.
- **Solo / duo**: synergies count only squad members at **run start**. A death does not switch the bonus off mid-wave (readability).
- **Determinism**: `chance` rolls use the fighter's sim RNG; `use` rules have no randomness. Replays and online prediction stay exact.

## 6. Dependencies

| System | Direction | Contract |
|---|---|---|
| `logic/card_deck.gd` | race system -> deck | new `race` part, validate, repair, starter races |
| `logic/commands.gd` / server | deck -> server | `card_race` command validated like `card_look` |
| `logic/game_sim.gd`, `fighter.gd` | engine <-> sim | sim emits the event list (3.6). Fighter gains `shield` (today only `logic/skills/actor.gd` has shields: bridge or move). Ultimate input routing (3.10.6) |
| `logic/combat.gd`, `logic/combat_data_loader.gd` | engine <-> combat | gauge gain owner, synthetic ultimate moves (3.10.6) |
| `logic/skills/` (skill system) | engine -> skills | `skill_mod` hook at cast resolve; `skill_refresh` hook on caster cooldowns; `SKILL_DMG`; `skill_cast`/`skill_hit` events; stop wiping the gauge |
| `logic/auto_pilot.gd` | class + race data -> pilot | reads `pilot`; marked-target preference; ultimate `use` rule |
| `logic/enemy_ai.gd` | engine -> AI | `aggro`/`pulse_aggro` override of target pick (today: nearest player) |
| `logic/coop.gd` (downed/revive) | engine -> co-op rules | revive path for `ally_downed` |
| `data/combat/effects.json` | reused + 3 new statuses | statuses referenced by id |
| `data/combat/vfx.json` | client display | `race_ult/*`, `race_aura/*`, 5 palette colours |
| `data/classes/*.json` | read | `moves.ultimate/special/charge` clips, `gauge` block |
| `tools/balance/class_sim.gd` | measures | race modes + ultimate logging (section 8) |
| Card/character screens, squad bar (client) | display | race picker, passive/ultimate text, synergy banner, gauge, callout (UX spec to write) |
| Art (Studio team + Codex 2D) | assets | 3.8 real looks; 3.10.7 asks |

## 7. Tuning Knobs

All in `data/races/*.json`, `data/races/rules.json`, `data/classes/*.json`, `data/combat/effects.json`.
- **Curve**: every passive cell number (each cell +5..12% card power); every ultimate number (each ultimate worth 3-6 s of that card's output); Pair/Trio/Alliance values (Alliance 5-10%); class stat profiles (HP 0.7-1.4x, DEF 0.7-1.5x); `fury_factor` 1.0-2.0.
- **Gate**: `shield_cap_max_hp` 0.2-0.4, `ult_shield_cap_max_hp` 0.4-0.6, `heal_cap_per_second_max_hp` 0.04-0.10, `cooldown_mul_floor` 0.5-0.75, aggro cycle (every 6-10 s, up 2-4 s), rune `max`, gauge sources T/Gd/Gt/Gs/Gk (4.7 ranges), class `gauge` multipliers 0.5-1.5, `charge_mul` 0.7-1.2, `max_hold_ticks` 240-600, revive HP 0.25-0.5.
- **Feel**: pilot `reaction`, `heavy_every`, `shoot_range` 6-8 m, `kite_distance` 2-4 m, ultimate `cast_ticks` 18-72 (longer = more readable, more interruptible), callout length 0.8-1.5 s.
- Global difficulty: `wave_power_by_squad` (retune once after races and ultimates land).

## 8. Balance plan

**Targets**: starter squad 72-75% (Boss). For a fixed class trio, every race mix within **±5 pts** of the mean of all mixes. No single passive cell lifts a solo card more than **+12 pts**. No single ultimate lifts a solo card more than **+10 pts** over the same card with ultimates off. Pair, Trio and Alliance mean win rates within **±4 pts** of each other.

**Ultimate share targets** (squad totals over a run):
- Ultimates deal **10-18%** of squad damage. Above 25% = the fight is "wait for ultimates", flag it.
- For Elf and Runeborn cards, ultimate heal/shield = **25-40%** of that card's total heal/shield (the passive should still matter).
- Each card fires **1 ultimate per 22-28 s** of combat; first fire 18-30 s. Fewer than 1 per 40 s = gauge too slow for that class, check the class `gauge` block.
- No ultimate's `use` rule leaves it unfired for more than `max_hold_ticks` in more than 20% of its full-gauge moments (pilot rule too strict).

**Role targets** (prove the classes now differ; class_sim prints per class): sword_shield takes >= 40% of squad damage taken. Longbow deals the most single-target (boss) damage. Magic has the most hits per cast plus healing/shield given. Greatsword has the highest average enemies per heavy. Solo win rates can spread (tank safest, mage most fragile). The squad number is what is held to 72-75%.

**class_sim additions** (`tools/balance/class_sim.gd`; the tool is measurement only):
- `only=cells`: 16 solo scenarios (`solo greatsword:viking`), each run twice: `ults=on` and `ults=off`, so passive and ultimate lifts are measured apart.
- `only=races`: the starter class trio x all 4^3 = 64 race mixes. Default `seeds=6` (~384 runs), grouped by synergy kind.
- `only=mono_race`: each of the 4 class trios x 4 Trios plus 1 Alliance mix.
- Arg `races=elf,elf,viking` to run one mix.
- **Per card, per run**, the output adds: ultimates fired (already counted from `attack_started` moves ending in `ultimate`; keep, and key it by race:class), first-fire tick, mean seconds between fires, ultimates lost to interrupt, full-gauge hold ticks, gauge gained by source (time/dealt/taken/support/kill), damage / heal / shield / revives done by the ultimate, passive trigger counts, shield absorbed, race healing done.
- Squad summary line: ultimate share of squad damage and of squad heal+shield.
- Flag lines: any mix > mean + 8 pts; any race in > 50% of the top-10 mixes; any ultimate share > 25%; any card with < 1 ultimate per 40 s.

**Dominant-combo risks**: (1) Elf Trio heal stacking + Rebirth Bloom -> near-unkillable. Mitigations: heal cap per second (passives), `wound` from goblin mages, revive once per ally per wave, Rebirth `charge_mul` 0.85. (2) Runeborn shields -> 30%/50% caps. (3) Human Trio + Human mage skill spam, Grand Recital refresh -> cooldown floor on rates, `recital` is 6 s only; watch Human mage ultimate damage share. (4) Viking needs the tank to *let* HP drop; with an Elf healer it may never reach the scaling. Watch for Viking being a trap rather than broken; Blood Moon pays its own Fury. (5) Bulwark + Commander's Call / Unbowed Roar / Heartwood / Bastion Glyph taunts: tank ultimates all taunt, so check the S&S damage-taken share and that the boss is not taunted more than ~60% of the time. (6) Masterstroke + Runebreaker stun/shock on the boss: control immunity must hold (test).

## 9. Implementation phases (small steps, each with tests)

1. **Data + card field**: `data/races/` (4 files + rules.json, incl. ultimate blocks and mockup colours), loader `logic/race_data.gd`, `card.race` + migration + `card_race` command. *Tests*: every race file loads; unknown type/event/action/condition/status/clip fails; old save gets its starter race; server rejects bad race id.
2. **Engine core (R cells)**: `logic/race_passives.gd` with `stat_mod`, `trigger` (apply_status, heal) and the sim events. *Tests*: each event fires once; Viking bow kill -> rage+haste; Elf GS wave start -> regen; determinism (same seed = same replay).
3. **Class identity**: `class_stats`, `pilot`, `gauge`, `signature` in class files; auto_pilot reads `pilot`; Hunter's Mark preference. *Tests*: classes without `pilot` behave as today; kite steps back; peel picks the right target. class_sim role metrics.
4. **New features**: Fighter shield (+caps), `low_hp_scaling`, `skill_mod` (+`SKILL_DMG`), `charges` (list `gain_on`, `gain: max`), `burst` (+v2 fields), `aggro`/`pulse_aggro`. One feature per step, each with its unit test and the formula examples from section 4.
5. **Gauge back on** (3.10.6): `ultimates_enabled`, stop the two gauge wipes, race-engine gauge gain (4.7), input routing in game_sim, synthetic ultimate moves. *Tests*: with skill-build on, the gauge fills from each source by the 4.7 example numbers; it is not wiped by a view publish; class skills still cast; old weapon ultimate never starts; online prediction matches authority on the gauge.
6. **Ultimate actions**: `zone`, `skill_refresh`, `ally_downed` revive, `self_hp_cost`, `fury`, `chain_on_kill`, `delayed`, `split`. *Tests*: one per action with the section-4 numbers; interrupt loses the cast; revive once per wave; zone follow/extend caps.
7. **Pilot fire rules** (3.10.4) for all 16 `use` blocks + `max_hold_ticks`. *Tests*: a scripted scene per condition (e.g. ally downed -> Rebirth fires that tick; 2 enemies -> Whirl holds; 3 -> fires).
8. **Synergies**: compute at run start, show in the run result. *Tests*: AAA -> Trio, AAB -> Pair(A), ABC -> Alliance, solo -> none, duo AA -> Pair.
9. **class_sim race + ultimate modes + one tuning pass**, then re-tune `wave_power_by_squad` once.
10. **UI + mockups** (ux spec first): race picker, passive/ultimate text, race badges/plates, synergy banner, gauge bar, ultimate callout, `race_aura/*` + `race_ult/*` vfx keys with race colour override, rune pips, shield bar.
11. **Real art** (Studio team, 3.8) and **online rooms** (shared logic, so only the deck field, the ultimate bit check and the server check).

## 10. Acceptance Criteria

- Adding a 5th race file (test fixture) appears in the race list and works in a sim run (passive and ultimate fire) with **zero code changes**. Adding a test class without cells gives it every race's `default_class` passive and ultimate.
- All 16 passive cells fire in a scripted sim (trigger count > 0 per run) and match their section-4 example numbers within rounding.
- All 16 ultimates fire in a scripted sim (fired count > 0 per run), each `use` rule fires in its scripted scene and holds in its negative scene, and their numbers match section 4 within rounding.
- With the skill-build system on and `ultimates_enabled`, the gauge fills, the ultimate fires, and the 4 class skills still cast in the same run. With `ultimates_enabled` false, behaviour equals today's (gauge retired).
- Old saves load with `race` set from `starter_races`. Changing a race only works through the validated command.
- Starter squad (default races) wins 72-75% over 40 seeds after re-tuning. Balance targets and ultimate share targets in section 8 hold.
- Role metrics in section 8 hold (the tank takes >= 40% of the squad's damage taken, etc.).
- Playtest (experiential): from the fight alone, a tester can say which card is the tank, the cleaver, the sniper and the caster, name the squad's synergy, and for each ultimate they saw, say which race cast it (from colour/callout) and what it did.
- Full test suite (`tests/run_all.gd`) passes.

## 11. OPEN QUESTIONS (for the Boss, via PO)

1. **Who fires the ultimate?** A. Fully automatic by the pilot rules (**default**; pure auto-battler, simplest). B. Player taps a card's ready ultimate; the pilot never fires it. C. Automatic, but the player may tap to fire early (more agency, needs touch UI on the squad panel).
2. **Revive in an ultimate (Elf Magic Rebirth Bloom)?** A. Yes: revive downed allies at 35%, once per ally per wave (**default**; strongest Elf fantasy, sim watches it). B. No revive: a bigger heal instead (30% + regen), safer for balance.

## 12. DECIDED (Boss 2026-11-13)

1. **Race acquisition**: free switch any time; all 4 races available from the start (3.9).
2. **Starter races**: Sword & Shield Human, Greatsword Viking, Longbow Elf, Magic Runeborn; the 3-card starter squad shows 3 different races (Alliance) (3.9).
3. **Alliance bonus** (3 different races): yes, +8% max HP and ATK (3.5).
4. **Race looks**: the Studio art team makes the real looks (Elf ears, Viking braids/beard/war paint, Runeborn glowing runes). Until then the game uses the mockups in 3.8 (plates, badges, ground rings, auras; no new models). The real-art table in 3.8 is the hand-off spec.
5. **Race ultimates**: each race gives each class a distinct ultimate on the existing gauge; it replaces the paused weapon ultimates; class skills stay (3.10).

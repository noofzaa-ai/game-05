# Skill Tree (per card: Class / Race / Combo branches)

**Status**: Draft (standard rigor) · **Date**: 2026-11-13 · **Author**: game-designer, for the PO/Boss
**Source decisions**: Boss 2026-11-13 (PROGRESS.md): the skill tree is rebuilt from scratch with new art in the hub's look. Each card has one tree with 3 branches (class / race / combo), about 20-25 nodes, and every node changes how the card plays. Skill points are permanent and come from card level. The old gems become tree nodes. Changing race resets the race and combo branches for free. New races and classes need only data.
**Reads with**: `design/gdd/races-and-classes.md` (v2: 16 passives in 3.4, 16 race ultimates in 3.10, effect vocabulary in 3.6). That doc owns the passives and ultimates. This doc only **modifies** them and does not restate them.
**Every number is a PLACEHOLDER** until `tools/balance/class_sim.gd` measures it and the Boss plays it.

---

## 1. Overview

Each card (sword_shield, greatsword, longbow, magic) owns a **skill tree**. The card earns its points itself, as card XP after runs. The points never expire. The tree has three branches:
- **Class branch** (16 nodes): lives in the class data. It upgrades the card's 4 class skills and gives each skill one of two modifiers. These modifiers replace the old shape and effect gems (wide, pierce, chain, echo, multishot, quickcast, ignite, bleed...). It also strengthens the class signature (Bulwark, Cleave, Hunter's Mark, Spellweave).
- **Race branch** (8 nodes): lives in the race data and uses the race colour. It strengthens the card's race passive and upgrades its race ultimate (gauge speed, size, heal, shield, Fury...).
- **Combo branch** (1 capstone): unique to the card's class × race pair (16 in total).

One tree has **25 nodes** and costs **35 points** at most if the player takes every reachable node. A max-level card has **26 points**, so the player must choose. With 26 points a card can reach the class capstone or the race capstone, plus the combo capstone. It can never own both branch capstones (16 + 11 = 27 > 26). The tree replaces the old 54-node weapon chart (`data/skill_system/tree/chart54.json`), the old per-run point rules and the gem sockets.

## 2. Player Fantasy

- **"My card is growing into someone" (Fantasy, Expression)**. A level-20 Viking greatsword plays differently from a level-20 Elf greatsword, and differently from another player's Viking greatsword that took the other capstone. The tree turns the card from a class into a character.
- **Pre-fight agency (Challenge-as-strategy)**. In an auto-battler the player's hands are off during the fight. Before it, they choose. So every node must make a change the player can *see in the fight*: a trap dropped while kiting, a slam that pulls enemies in, an ultimate that fires twice. Pure +8% filler is banned.
- **Long-term goal with visible milestones (Achievement)**. A level-up after almost every early run, a capstone around level 15-18, and the full build at level 25. This is the macro-loop's reason to return.
- **SDT**: Autonomy (exclusive pairs and capstone choices, 3+ viable builds per card). Competence (each node names the visible change, and the fight shows it). Relatedness (race colour and combo capstones make the card "an Elf ranger", not "bow #2").
- **Bartle/QF**: Achievers fill trees and levels. Explorers find combo capstones and node interactions (Kiting Snare + Bleeding Thorns). Strategists (Mastery) plan a 26-point budget across three squad cards.

## 3. Detailed Rules

### 3.1 Tree shape (same shape for every card)

| Branch | Tier | Gate (points spent **in this branch** before nodes of this tier can be learned) | Nodes | Type / cost | Choice rule |
|---|---|---|---|---|---|
| Class | T1 | 0 | 4 (one per class skill: "upgrade") | minor, 1 | free |
| Class | T2 | 3 | 8 (two per class skill: modifier A / B) | major, 2 | **exclusive pair per skill** (take A or B, not both) |
| Class | T3 | 8 | 2 (signature) | major, 2 | free |
| Class | T4 | 13 | 2 (class capstones) | capstone, 3 | **exclusive pair** |
| Race | T1 | 0 | 2 | minor, 1 | free |
| Race | T2 | 2 | 2 | major, 2 | free |
| Race | T3 | 6 | 2 | major, 2 | free |
| Race | T4 | 8 | 2 (race capstones) | capstone, 3 | **exclusive pair** |
| Combo | - | class branch >= 8 **and** race branch >= 6 | 1 | capstone, 3 | - |

**Counts**: class 16 + race 8 + combo 1 = **25 nodes per tree**. The most a player can take is class 4·1 + 4·2 + 2·2 + 3 = **19**, race 2·1 + 4·2 + 3 = **13**, combo **3** = **35 points**.

**Gating**: the gate counts only points spent in that branch. A node also requires nothing else: no path or adjacency rule inside a tier. This keeps the tree readable on a phone. Tiers are the paths.

**Node types**:
- **Minor** (1 pt): a clear upgrade to one skill or to the passive. It must change a number by at least 25% or add a behaviour.
- **Major** (2 pts): a modifier that changes shape (more projectiles, bigger area, a status) or a new rule.
- **Capstone** (3 pts, bigger icon): changes the card's role or rhythm.

**Exclusive pairs** are drawn as a forked ink path with an "OR" wax seal (section 9). Learning one locks the other until a reset.

### 3.2 Points, levels and XP (permanent, per card)

- Each card has `level` (1..`max_level` 25) and `xp`. Both are stored per card in `profile.card_gear[card].progress = {"level", "xp"}`.
- **Points earned** = `level - 1` + 1 bonus point at each milestone level (10, 20). At level 25: 24 + 2 = **26 points** (formula 4.1). Points spent = the sum of the costs of the nodes taken. Unspent points carry over with no limit.
- **XP source**: end of run only (section 3.7). Every card in the squad gets the same XP, whether it is downed or not.
- **XP to next level**: `xp_req(L) = round(100 * L^1.2)` (formula 4.2). At max level, XP stops (the bar shows MAX) and extra XP is discarded.
- **Old per-run points are gone**: `points_per_room`, `boss_bonus_points` and `max_points` in `data/skill_system/integration.json` are retired. Only `max_points` is read by code today (`logic/skill_build.gd` l.36, l.43). Points are never earned mid-run, and the tree cannot change mid-run.

### 3.3 Learning and respec

- Editing happens only in the hub, in the Skills tab. The player edits a **draft**: learning and un-learning in the draft is free and checked client-side for preview. **Confirm** sends the whole draft to the server (one command). The server re-validates it and saves it, or rejects it as a whole.
- A confirmed node can only be removed by a **branch reset**:
  - **Class branch reset**: costs gold (`class_reset_gold_per_point` × points refunded, default 50, so a full class branch is about 950 gold, under one run's gold). OPEN Q1.
  - **Race branch reset**: free. It also resets the combo branch, because the combo gate needs race points.
  - **Full reset**: class price only.
- **Race change** (`card_race` command, races-and-classes.md 3.7): the server resets the race and combo branches and refunds their points **for free**, in the same command. The class branch is kept. The new race's branch starts empty.
- Draft rules the server enforces: every node id exists in this card's class/race/combo data; costs ≤ points earned; each tier's gate is met **after** removing that tier's own nodes (no gate can be met using points spent in the same or a deeper tier); at most one node per exclusive pair; the combo node is only valid with its class+race pair.

### 3.4 Where the data lives (data-only rule)

- **Class branch**: a `tree` block in `data/classes/<id>.json`, holding nodes T1..T4.
- **Race branch + combo**: a `tree` block in `data/races/<id>.json` with `nodes` (race branch, T1..T4) and `combo` {class_id: node}. A new race brings its own combos. A new class with no combo entry in a race gets that race's `default_combo` (the data test warns, same as `default_class`).
- **Shared numbers**: `data/skill_tree/rules.json`: tier gates, node costs, `max_level`, `milestone_levels`, the XP curve, `xp_rewards`, reset prices, and caps (4.6).
- The node schema (all branches):
```json
{"id": "lb_t1_trap", "tier": 1, "type": "minor", "cost": 1, "excl": "",
 "name": "Kiting Snare", "text": "When it kites, the card drops Thorn Trap at its feet. Root 1 s -> 1.5 s.",
 "icon": "res://art/ui/skill_tree/icons/lb_t1_trap.png",
 "effects": [ {"type": "skill_upgrade", "skill": "thorn_trap", "mods": [{"stat": "root_time", "op": 1, "value": 1.5}]},
              {"type": "pilot_mod", "kite_drop_skill": "thorn_trap"} ]}
```
`excl` = an exclusive-group id, the same for both nodes of a pair. The list of `effects` uses the races-and-classes.md vocabulary (3.6) plus the four node-only types in 3.5.

### 3.5 Effect vocabulary for nodes

Reused as they are (races-and-classes.md 3.6): `stat_mod`, `low_hp_scaling`, `skill_mod`, `trigger`, `charges`, and all actions (`apply_status`, `heal`, `shield`, `burst`, `pulse_aggro`, `zone`, `skill_refresh`), with their events, targets and centers.

**New node-only effect types** (an unknown type is a load error, same rule):

| Type | Fields | What it does |
|---|---|---|
| `skill_upgrade` | `skill`, `mods` [{stat, op, value}] (the existing `stat_mod.gd` ops and `build_calc.gd` stat names), `status?` (a skill-system status id: burn, bleed, chill, shock, stun, freeze), `behavior?` (an existing gem behaviour: echo, remote, leech) | Changes one class skill. **This is how the old gems live on**: a gem's `mods`/`status_id`/`behavior` move into a node. `build_calc.calc_skill` applies the node mods in the same order the gems used, so the math is unchanged. |
| `cell_mod` | `cell`: `passive` or `ultimate`; any of `scale` (all numbers in the cell's actions ×), `radius_mul`, `duration_mul`, `heal_mul`, `shield_mul`, `atk_mul`, `icd_mul`, `charges_max_add`, `charges_reset_to`, `hp_threshold_add`, `every_n_add`, `fury_add`, `refresh_add`, `extra_actions` [actions] | Modifies the race cell (passive or ultimate) of whatever class the card is. This is what keeps the race branch class-agnostic: one Viking node works on all 4 Viking cells. |
| `gauge_mod` | `start` (gauge at run start), `charge_mul`, `kill_add`, `support_mul`, `skill_mul`, `low_hp_mul` + `below`, `fire_at` + `fire_below_hp`, `after_cast` (gauge left after a cast) | Changes this card's ultimate gauge (races-and-classes.md 4.7). |
| `signature_mod` | `every_mul`, `radius_add`, `duration_add`, `per_target_add`, `max_add`, `mark_duration_add`, `extra_actions` [actions] | Changes the class signature (Bulwark / Cleave / Hunter's Mark / Spellweave). |
| `pilot_mod` | fixed keys: `kite_drop_skill`, `cast_center` (`densest`), `kite_distance`, `hold_min_targets_add` | The few nodes that change auto-pilot behaviour say so in data (section 6.4). |
| `mechanic` | `id` (one of `data/skill_tree/rules.json` `vocabulary.mechanics`) + its own params | A one-off node rule the generic words cannot express (Deadeye, Twin Ultimate, World Tree, the combo capstones...). Each id is listed with a one-line description in the rules file; an unknown id is a load error; the engine implements it by id (PO default 2026-11-13, accepted). |

`gauge_mod` also takes `discharge_add` (gauge per rune discharge, Stored Power).

**New events / targets / actions the node list needs** (beyond races-and-classes.md v2):
- Events: `signature_pulse` (Bulwark pulse / Cleave heavy / Mark applied), `dodge`, `kite`, `block` (an alias of the existing `guard_block`), `overheal`, `rune_discharge`, `lethal_hit`.
- Trigger filters: `skill` (the trigger fires only for one skill id), `min_targets` (a hit that touched N+ enemies), `target_has` (a status id on the target), `self_below_hp`.
- Actions: `pull` {radius, distance}, `cleanse` {target, statuses}, `skill_status` {status, stacks} (applies a *skill-system* status from the race engine), `death_save` {duration_ticks, atk_mul, survive_if_kill}, `reflect` {fraction, while}.
- Stats: `CONTROL_IMMUNE` (flag), `DMG_TAKEN_AURA` {radius, mul}, `heavy_arc` (degrees, a move field).
- Targets: `allies_in_radius` {radius} (allies within radius of the card, Rallying Wall).
- Action fields: `heal` takes `per_target` (amount × enemies the hit touched) and `cap_max_hp` (cap per trigger, Unstoppable, Red Harvest); `skill_refresh` takes `others` (refresh every skill but the one that fired, Overload).

### 3.6 Skill slots (no gem slotting)

- Each card always has its class's 4 skills (`integration.json` `class_skills`, keyed by class style). The skill set is fixed. The tree changes *how* they work. The old `skills[{skill, shape, effect}]` rows are gone. So are gem ownership, gem compatibility checks (`build_calc.can_equip`) and Merchant gem unlocks, as far as this build is concerned.
- A skill's effective stats = base `.tres` stats → the T1 upgrade mods → the chosen T2 modifier mods → race `skill_mod`s (races-and-classes.md 4.4). The order is fixed so results are deterministic.

### 3.7 XP rewards (end of run)

Paid when the journey commits its haul (drops-and-rewards.md 3.6), once only, to every card that started the run:
- Per wave cleared: `20 + 5 * w` (w = wave number 1..11).
- Boss killed: +100. Win: +50.
- Full win: (20+25 ... +75) = 550 + 100 + 50 = **700 XP**. A loss at wave 6 (waves 1-5 cleared) = 25+30+35+40+45 = 175.
- Lost, retreated and abandoned runs pay for waves already cleared (same rule as loot). XP is **not** scaled by squad size: a solo run levels one card, a squad run levels three.

### 3.8 Full node lists: class branches

Notation: **cost** in brackets. Mod numbers on T2 modifiers are the old gem values (`data/skill_system/gems/*.tres`) unless marked *new*. "Pilot:" = what the auto-pilot does differently.

> **Superseded for class nodes (2026-11-13):** the skill ids and fields below (storm_blades, `parry_window`, `counter_mul`, `root_time`, `trail_width`, `shocked_mul`, Kiting Snare's `kite_drop_skill` …) are the pre-v2 skills. The live node list is `design/gdd/class-skills.md` 3.6 and `data/classes/*.json`; every mod stat used there has runtime code. Node ids, tiers and costs below still match.

#### 3.8.1 sword_shield (tank · Bulwark) · skills: storm_blades, riposte, blood_shield, flame_dash

| Id | Tier | Name | Effect |
|---|---|---|---|
| ss_t1_storm | T1 [1] | Tempest Step | Storm Blades also taunts: `pulse_aggro` r3 m, 2 s at the end of the dash. The tank's dash now pulls attention off the back line. |
| ss_t1_riposte | T1 [1] | Iron Answer | Riposte `parry_window` 0.5 → 0.8 s. A successful counter gives self `fortify` 3 s. |
| ss_t1_blood | T1 [1] | Shared Blood | Blood Shield also shields the most-hurt ally for 50% of the amount. |
| ss_t1_flame | T1 [1] | Ward Line | Flame Dash trail duration 3 → 5 s. Enemies crossing it get `slow`. |
| ss_t2_storm_a / _b | T2 [2] | **Echo Edge** / **Shield Bash** | A: echo gem (`repeat` +1 at 50%, cooldown ×1.3). B: knockback gem (knockback 3, dmg ×0.9) + stun gem (`stun`). |
| ss_t2_riposte_a / _b | T2 [2] | **Heavy Counter** / **Bleeding Riposte** | A: `counter_mul` 3 → 4.5 (*new*). B: bleed gem (`bleed`, dmg ×0.9). |
| ss_t2_blood_a / _b | T2 [2] | **Thorned Shell** / **Mending Shell** | A: thorns gem (reflect 30%, duration ×0.8). B: regen gem (2% max HP/s while it lasts, cooldown ×1.2). |
| ss_t2_flame_a / _b | T2 [2] | **Wide Trail** / **Quick Step** | A: wide gem (`trail_width` ×1.5, dmg ×0.8). B: quickcd gem (cooldown ×0.75, dmg ×0.85). |
| ss_t3_a | T3 [2] | Unyielding Bulwark | Bulwark cycle every 8 → 6 s. While a Bulwark taunt is up, the card takes −15% damage. |
| ss_t3_b | T3 [2] | Rallying Wall | Each Bulwark pulse also gives `fortify` 3 s to allies within 4 m (`signature_pulse` trigger). |
| ss_t4_a | T4 [3] | **Spiked Bastion** | While a Bulwark taunt is up, 25% of damage taken is reflected to the attacker (`reflect`). The tank becomes a damage source. |
| ss_t4_b | T4 [3] | **Immovable** | `CONTROL_IMMUNE` (no stun, knockback or stagger) and Bulwark radius 5 → 8 m. The tank becomes a wall that never breaks. |

#### 3.8.2 greatsword (bruiser · Cleave) · skills: ground_slam, shatter_smash, eruption, war_cry

| Id | Tier | Name | Effect |
|---|---|---|---|
| gs_t1_slam | T1 [1] | Faultline | Ground Slam first `pull`s enemies within 5 m 1.5 m toward the card, then hits. It gathers the pack for Cleave. |
| gs_t1_shatter | T1 [1] | Cold Iron | Shatter Smash applies 2 `chill` stacks. Two casts set up its own `frozen_mul`. |
| gs_t1_eruption | T1 [1] | Banked Embers | Heavy hits apply 1 `burn` stack (`skill_status`), so Eruption always has fuel to consume. |
| gs_t1_cry | T1 [1] | Battle Hymn | War Cry radius 4 → 7 m and duration 5 → 7 s. Its buff reaches every ally inside. |
| gs_t2_slam_a / _b | T2 [2] | **Wide Quake** / **Aftershock** | A: wide gem (radius ×1.5, dmg ×0.8). B: echo gem. |
| gs_t2_shatter_a / _b | T2 [2] | **Dense Impact** / **Shock Shatter** | A: dense gem (radius ×0.7, dmg ×1.4). B: shock gem (`shock`, dmg ×0.9). |
| gs_t2_eruption_a / _b | T2 [2] | **Wide Eruption** / **Charged Eruption** | A: wide gem. B: charge gem (dmg ×1.5, cast time ×1.6). |
| gs_t2_cry_a / _b | T2 [2] | **Long Hymn** / **Thorn Hymn** | A: longer gem (duration ×1.5, cooldown ×1.2). B: thorns gem on every buffed ally. |
| gs_t3_a | T3 [2] | Executioner's Arc | Cleave +15% → +20% per extra enemy, max +45% → +60%. |
| gs_t3_b | T3 [2] | Momentum | A heavy that hits 3+ enemies gives `haste` 2 s and makes the next heavy come one swing earlier (once). |
| gs_t4_a | T4 [3] | **Titan's Swing** | Every heavy is a full 360° sweep (`heavy_arc` 360, radius 2.5 m). The bruiser fights in the middle of the pack. |
| gs_t4_b | T4 [3] | **Unstoppable** | `CONTROL_IMMUNE` during skill casts and heavies. Each heavy heals 2% max HP per enemy hit (cap 8%). |

*Class-axis note*: the healing in Unstoppable is self-only and comes from the bruiser fantasy. Ally healing stays Elf-only.

#### 3.8.3 longbow (ranged DPS · Hunter's Mark) · skills: piercing_shot, thorn_trap, ice_lance, chain_lightning

| Id | Tier | Name | Effect |
|---|---|---|---|
| lb_t1_pierce | T1 [1] | Marked Line | Every enemy that Piercing Shot passes through gets Hunter's Mark (`sunder`), not just the first. |
| lb_t1_trap | T1 [1] | Kiting Snare | When it kites (an enemy within 3 m), the card drops Thorn Trap at its feet if the trap is ready (`pilot_mod kite_drop_skill`). `root_time` 1 → 1.5 s. |
| lb_t1_lance | T1 [1] | Frostbite | Ice Lance `status_stacks` 2 → 3 chill. |
| lb_t1_chain | T1 [1] | Arc Seeker | Chain Lightning jumps to marked targets first. `chain` 3 → 4. |
| lb_t2_pierce_a / _b | T2 [2] | **Split Volley** / **Heavy Draw** | A: multishot gem (+2 projectiles, dmg ×0.7). B: charge gem (dmg ×1.5, cast ×1.6). |
| lb_t2_trap_a / _b | T2 [2] | **Briar Field** / **Bleeding Thorns** | A: wide gem. B: bleed gem. |
| lb_t2_lance_a / _b | T2 [2] | **Glacier Pierce** / **Quickdraw** | A: pierce gem (+2 pierce, dmg ×0.9). B: quickcast gem (cast ×0.7, dmg ×0.85). |
| lb_t2_chain_a / _b | T2 [2] | **Forked Storm** / **Stunning Bolt** | A: chain gem (+2 chain, dmg ×0.85). B: stun gem. |
| lb_t3_a | T3 [2] | Deep Mark | Hunter's Mark lasts +3 s and also applies `weaken`. |
| lb_t3_b | T3 [2] | Pack Hunt | Allies deal +10% damage to marked targets (the squad focus-fires harder). |
| lb_t4_a | T4 [3] | **Deadeye** | Every 4th basic shot on a marked target is a forced crit that also pierces. |
| lb_t4_b | T4 [3] | **Skirmisher** | `kite_distance` 3 → 5 m and dodge cooldown ×0.6. After each dodge, the next skill casts instantly (cast time 0). |

#### 3.8.4 magic (AoE/control · Spellweave) · skills: fireball, fire_ring, lightning_strike, frost_armor

| Id | Tier | Name | Effect |
|---|---|---|---|
| mg_t1_fireball | T1 [1] | Kindling | Fireball applies 2 `burn` stacks. |
| mg_t1_ring | T1 [1] | Repelling Ring | Fire Ring knocks enemies 1.5 m back (it protects the caster's spot). |
| mg_t1_strike | T1 [1] | Conductor | Lightning Strike applies `shock`. `shocked_mul` 2 → 2.5. |
| mg_t1_armor | T1 [1] | Biting Frost | Melee attackers of a Frost Armor wearer get 1 `chill` stack. |
| mg_t2_fireball_a / _b | T2 [2] | **Triple Fireball** / **Echo Fireball** | A: multishot gem. B: echo gem. |
| mg_t2_ring_a / _b | T2 [2] | **Remote Ring** / **Dense Ring** | A: remote gem (cast at the densest point within 7 m, dmg ×0.9; `pilot_mod cast_center: densest`). B: dense gem. |
| mg_t2_strike_a / _b | T2 [2] | **Wide Strike** / **Quick Strike** | A: wide gem. B: quickcd gem. |
| mg_t2_armor_a / _b | T2 [2] | **Long Frost** / **Thorned Frost** | A: longer gem. B: thorns gem. |
| mg_t3_a | T3 [2] | Weave Rhythm | Every 3rd skill cast costs no stamina and deals +25%. |
| mg_t3_b | T3 [2] | Overload | A skill hit on 3+ enemies cuts the other 3 skills' remaining cooldowns by 1 s (`skill_refresh` seconds 1, `min_targets` 3). |
| mg_t4_a | T4 [3] | **Elemental Convergence** | An enemy carrying burn + chill + shock at once takes +40% skill damage. If it dies like that, it explodes (r2.5 m, 100% ATK). |
| mg_t4_b | T4 [3] | **Blink Caster** | When an enemy comes within 2.5 m: blink 5 m away (cooldown 6 s) and leave a Fire Ring (no cooldown cost) where it stood. |

**Old gems → nodes (all 20 accounted for)**: wide, dense, echo, multishot, chain, pierce, knockback, charge, quickcast, quickcd, longer, remote (shape: 12) and ignite→Kindling/Banked Embers (burn), bleed, chill (Cold Iron/Frostbite/Biting Frost), shock, stun, thorns, regen (effect: 7) are in the lists above. **leech** is dropped: lifesteal on skills overlaps the Viking/Elf themes. Its `behavior` stays in code for future nodes.

### 3.9 Full node lists: race branches

Each race node works on whichever class the card is (`cell_mod` on `passive`/`ultimate`). The examples name the affected cell. Numbers are added on top of races-and-classes.md 3.4 / 3.10.

#### 3.9.1 Human (Mastery · gold `#ffc23a`)

| Id | Tier | Name | Effect |
|---|---|---|---|
| hu_1 | T1 [1] | Drilled Ranks | Passive `scale` 1.25 and `icd_mul` 0.75. (Rallying Drill cooldown 10 → 7.5 s; Archmage +30% → +37.5% skill dmg.) |
| hu_2 | T1 [1] | Ready Stance | `gauge_mod start` 40: the first ultimate comes about 9 s sooner. |
| hu_3 | T2 [2] | Disciplined Casting | After an ultimate, the card's next 2 skill casts cost no stamina. |
| hu_4 | T2 [2] | Grand Command | Ultimate `radius_mul` 1.3 and `refresh_add` +0.25 (Commander's Call halves → refunds 75%; Masterstroke 1 s → 1.25 s per hit). |
| hu_5 | T3 [2] | Field Command | `gauge_mod charge_mul` 1.2 (ultimates about 17% more often). |
| hu_6 | T3 [2] | Scholar's Edge | Skill crit +15. A skill crit cuts that skill's cooldown by 1 s. |
| hu_7 | T4 [3] | **Twin Ultimate** | Each ultimate re-casts itself 2 s later at 50% of its numbers. The echo gives no gauge and does not echo again. |
| hu_8 | T4 [3] | **Mastery Overflow** | `gauge_mod after_cast` 35. For 8 s after an ultimate the passive's numbers are ×1.25 more. |

#### 3.9.2 Viking (Fury · red `#e0302a`)

| Id | Tier | Name | Effect |
|---|---|---|---|
| vk_1 | T1 [1] | Thick Blood | Passive `hp_threshold_add` +0.10 (Unbroken at 45%; Berserker full at 30%; Blood Rite floor unchanged). |
| vk_2 | T1 [1] | Battle Scent | `gauge_mod kill_add` +6 (a kill gives 10 gauge instead of 4). |
| vk_3 | T2 [2] | Blood Price | Ultimate `fury_add` +0.5 (fury 1.5 → 2.0; Blood Moon 2.0 → 2.5). |
| vk_4 | T2 [2] | Red Harvest | Ultimate `extra_actions`: heal self 3% max HP per enemy it hits (cap 15%). |
| vk_5 | T3 [2] | Red Mist | `gauge_mod low_hp_mul` 1.5 below 50% HP. |
| vk_6 | T3 [2] | Trophy Hunter | A kill extends this card's active `rage`/`haste` by 2 s and heals 2% max HP. |
| vk_7 | T4 [3] | **Valhalla's Call** | Once per wave, a lethal hit triggers `death_save`: 4 s at 1 HP minimum with ATK +50%. If the card gets a kill in that time it survives at 20% HP; otherwise it goes down. |
| vk_8 | T4 [3] | **Berserkergang** | Below 35% HP, the ultimate can fire at 60 gauge (`fire_at` 60, `fire_below_hp` 0.35). |

#### 3.9.3 Elf (Lifebloom · green `#4fe07a`)

| Id | Tier | Name | Effect |
|---|---|---|---|
| el_1 | T1 [1] | Deep Roots | Passive `heal_mul` 1.3. |
| el_2 | T1 [1] | Sap Flow | `gauge_mod support_mul` 1.5 (healing allies fills the gauge faster). |
| el_3 | T2 [2] | Overgrowth | Ultimate `heal_mul` 1.3 and `radius_mul` 1.25. |
| el_4 | T2 [2] | Cleansing Dew | A race heal on an ally below 30% HP also `cleanse`s stun/slow/shock on it. |
| el_5 | T3 [2] | Kin Bond | This card heals itself for 25% of the healing it gives to allies. |
| el_6 | T3 [2] | Evergreen | Ultimate `extra_actions`: a grove `zone` r3 m for 4 s where it was cast; allies inside heal 1.5% max HP/s. |
| el_7 | T4 [3] | **World Tree** | Once per wave, the first ally to go down is revived at 25% HP after 3 s if this card is alive. It shares the "revived this wave" flag with Rebirth Bloom. |
| el_8 | T4 [3] | **Bloom Cascade** | Overheal from this card's race heals bounces once to the next most-hurt ally (`overheal` event). |

#### 3.9.4 Runeborn (Runes · cyan `#3fe6ff` / violet `#9a5cff`)

| Id | Tier | Name | Effect |
|---|---|---|---|
| rb_1 | T1 [1] | Quick Glyphs | Passive `charges_max_add` −1 (S&S 5→4, GS 4→3, bow 6→5, magic 3→2). |
| rb_2 | T1 [1] | Stored Power | Each rune discharge gives +8 gauge. |
| rb_3 | T2 [2] | Empowered Discharge | Passive `scale` 1.3 (shields, bursts and focus from runes are 30% stronger). |
| rb_4 | T2 [2] | Runic Ultimate | Ultimate `scale` 1.25 and `duration_mul` 1.25 on its zones. |
| rb_5 | T3 [2] | Rune Battery | After a discharge, runes reset to 1 instead of 0 (`charges_reset_to` 1). |
| rb_6 | T3 [2] | Warding Sigil | This card's shields last +4 s. When one breaks, it `shock`s enemies within 2 m. |
| rb_7 | T4 [3] | **Overcharge** | Runes may go 2 past max. A discharge spends all of them and scales its payload by runes/max (1.33× for bow up to 1.67× for magic). |
| rb_8 | T4 [3] | **Resonance** | Each discharge also gives +1 rune to every other Runeborn ally. It feeds the Pair/Trio. |

### 3.10 Combo capstones (16) · gate: class ≥ 8 and race ≥ 6 · cost 3

| Pair | Id | Name | Effect |
|---|---|---|---|
| Human × S&S | combo_hu_ss | Drillmaster's Wall | Each skill cast halves Bulwark's remaining cycle. Rallying Drill cooldown 10 → 6 s. |
| Human × GS | combo_hu_gs | Perfect Form | A heavy that hits 3+ enemies fully refreshes the shortest skill cooldown (internal cooldown 4 s). |
| Human × Bow | combo_hu_lb | Called Target | Marked targets take +20% *skill* damage from the whole squad. Called Shot always picks a marked boss when there is one. |
| Human × Magic | combo_hu_mg | Grand Archmage | Every 4th skill cast fires twice (the copy is free and deals 70%). |
| Viking × S&S | combo_vk_ss | Wall of Fury | Below 50% HP: Bulwark radius +3 m, and enemies the tank hits get `weaken`. |
| Viking × GS | combo_vk_gs | Blood Cyclone | Cleave bonus ×(1 + missing HP), cap +90%. Ragnarok Whirl gains +1 s per kill (cap +3 s). |
| Viking × Bow | combo_vk_lb | Trophy Volley | Each skill kill fires a free 80% arrow at the lowest-HP enemy (max 3 per cast). |
| Viking × Magic | combo_vk_mg | Blood Sorcery | A skill kill heals 5% max HP (refunds Blood Rite). Skills cast below 50% HP get +20% radius. |
| Elf × S&S | combo_el_ss | Grove Warden | While Bulwark is up, Warden's Grove heals **all** allies within 5 m (2% each, same 1 s cooldown). |
| Elf × GS | combo_el_gs | Bark and Blade | While Living Bark `regen` is on, each extra enemy a heavy hits heals the most-hurt ally 1.5% (cap 6% per heavy). |
| Elf × Bow | combo_el_lb | Moonwell Arrows | Moonlit Arrow every 5th → every 3rd shot. On a marked target it also roots 1 s. |
| Elf × Magic | combo_el_mg | Spring Rite | Bloomcaster heal cap 8% → 12%. Its overheal becomes `regen` 3 s on that ally. |
| Runeborn × S&S | combo_rb_ss | Runic Bulwark | Each Bulwark pulse gives +1 rune per taunted enemy (max +3). |
| Runeborn × GS | combo_rb_gs | Shatterglyph | The Runic Edge burst counts as a heavy for Cleave and leaves a 2 s `shock` zone (r3 m). |
| Runeborn × Bow | combo_rb_lb | Glyph Arrows | Each Glyph Shot discharge applies Hunter's Mark to all enemies within 6 m of the target. |
| Runeborn × Magic | combo_rb_mg | Grand Runeweaver | Skill hits on 3+ enemies also give a rune. Runeweaver's shields also give `focus` 3 s. |

### 3.11 Race switching and the tree

- Switching race (hub only, never during a run): race and combo nodes are removed, their points return to the pool, and the new race's branch is empty. This costs nothing. Class nodes stay.
- The UI warns before confirming: "Race and Combo points (N) will be returned." There is no confirm if those branches are empty.
- If the class branch stays above 8, the combo gate needs only race points, so a switch costs at most 9 race points to reach the new combo.
- A run snapshots the tree at run start (the sim reads the validated tree once). Nothing in the hub changes a running journey.

## 4. Formulas

**4.1 Points.** `points(L) = (L - 1) + count(m in milestone_levels, m <= L)`. Defaults: `milestone_levels` [10, 20], `max_level` 25.
L=1 → 0 · L=2 → 1 · L=9 → 8 · L=10 → 10 · L=12 → 12 (first capstone: race cap needs 11) · L=16 → 16 (class cap possible) · L=17 → 17 (combo possible) · L=20 → 21 · L=25 → **26**.
Share of the tree at max level: 26 / 35 = **74%**.

**4.2 XP curve.** `xp_req(L) = round(xp_base * L^xp_exp)` to go from L to L+1. Defaults `xp_base` 100, `xp_exp` 1.2.
| L | 1 | 2 | 3 | 4 | 5 | 10 | 15 | 20 | 24 |
|---|---|---|---|---|---|---|---|---|---|
| xp_req | 100 | 230 | 374 | 528 | 690 | 1585 | 2580 | 3641 | 4530 |
Cumulative (approx., integral of 100·x^1.2): to level 5 ≈ 1,230 (≈ 2 wins) · to level 10 ≈ 6,400 (≈ 9 wins) · to level 25 ≈ 51,700 (≈ **74 wins**). A level-up after almost every early run, then the curve stretches (the sawtooth the macro-loop needs). Exact sums come from the data test, not this table.

**4.3 Run XP.** `xp_run = sum(20 + 5*w for each cleared wave w in 1..11) + 100*boss_killed + 50*won`. Full win = 700. Loss at wave 6 (5 cleared) = 25+30+35+40+45 = 175.

**4.4 Build budgets (why choice is forced).** Minimum cost to reach each capstone:
- Class T4: the gate is 13 points in T1-T3. The cheapest is 3 T1 (3) + 5 majors from T2/T3 (10) = 13 → capstone (3) = **16**.
- Race T4: 2 T1 (2) + 2 T2 (4) = 6 → one T3 (2) = 8 → capstone (3) = **11**.
- Combo alone: class 8 + race 6 + 3 = **17**.
At 26 points: class cap + combo = 16 + 6 + 3 = 25 ✓ (1 spare). Race cap + combo = 8 + 11 + 3 = 22 ✓ (4 spare). Class cap + race cap = 27 ✗. All three = 30 ✗. So every max-level card picks a side.

**4.5 Skill modifier math** (the `build_calc` order: add ops, then multipliers). Examples:
- Echo Edge (Storm Blades dmg 12, cd 5): one cast = 12 + 12·0.5 = 18 every 6.5 s → 2.77 dmg/s vs 2.40 = **+15%** single-target DPS, plus a second hit window.
- Triple Fireball (dmg 16): 3 × 16 × 0.7 = 33.6 if all 3 hit (**+110%** on a pack), 11.2 if 1 hits (**−30%** single target). That is why the pilot's hold rule (6.4) matters.
- Dense Impact (Shatter Smash 22, r2.5): 30.8 dmg in r1.75. Frozen ×2.5 → 77.
- Wide Quake (Ground Slam r3 dmg 15): r4.5 (area ×2.25), 12 dmg.

**4.6 Cell mods.** `value' = value × scale × field_mul` (`heal_mul` only on heal amounts, etc.). Caps from races-and-classes.md still hold after mods: shield ≤ 30% (50% with an ultimate part), passive heal ≤ 6%/s, cooldown floor 0.60. Examples:
- Drilled Ranks on Rallying Drill: icd 10 × 0.75 = 7.5 s.
- Thick Blood on Berserker (`full_at_hp` 0.2 → 0.3): at 50% HP, bonus = 0.40 × (1 − 0.5)/(1 − 0.3) = **0.286** (was 0.25).
- Blood Price on Unbowed Roar at 60% HP: 100% × (1 + 2.0 × 0.4) = **180%** (was 160%).
- Overcharge, Runeweaver (max 3) at 5 runes: 10% × 5/3 = **16.7%** shield per ally.

**4.7 Gauge mods** (on top of races-and-classes.md 4.7). `gain' = gain × charge_mul_node × (low_hp_mul if HP < below) ` · kill gain `Gk + kill_add` · support term × `support_mul`. Ready Stance: a card gaining 4.5/s fires at 100/4.5 = 22 s; with `start` 40 at 60/4.5 = **13 s**. Field Command: 22 s → 18.5 s.

**4.8 Power budget (verify by sim).** Full 26-point tree ≈ **+35-40%** card power (EHP × DPS) over level 1. Per tier: T1 upgrades ≈ +3-4% each, T2 modifiers ≈ +4-6% (situational), signatures ≈ +5%, capstones ≈ +8-12%, combo ≈ +8-10%. No single node above +12%.

## 5. Edge Cases

- **Old saves (v1 `skill_build`: `{v:1, start, allocated, skills[{skill,shape,effect}]}`)**: migrated once on profile load (`card_gear[card]`). Old allocated nodes are dropped. The card gets `level = 1 + n`, where n = old allocated nodes excluding the free start node (0..12), and `xp = 0`. So old effort becomes free points to spend (OPEN Q3). Gem slot choices are dropped. Gold paid for gem unlocks at the Merchant (if any was charged) is refunded once. The migration writes `skill_tree {v:2, class:[], race:[], combo:[]}` and a marker `tree_migration_version: 2`, so it never runs twice.
- **Per-run points in old in-flight journeys**: a saved journey checkpoint holding the old tree keeps its old build until that run ends (the sim reads the snapshot). The next run uses v2.
- **Card at level 1**: 0 points. Every T1 node shows as *available* but greyed "need 1 point". The 4 class skills work at base stats. The pilot plays exactly as it does today.
- **Points earned but nothing learnable** (all reachable nodes taken, max level): the tab shows "Tree complete" on the branch header. No error.
- **Unspent points**: kept with no limit. The hub shows a badge on the card and the Skills tab.
- **Draft rejected by the server** (stale client, cheat, data changed): nothing is saved, and the client reloads the server tree. Reasons: `unknown_node`, `not_enough_points`, `gate_not_met`, `exclusive_conflict`, `combo_mismatch`, `in_run`.
- **Data change removes a node someone owns**: on load, unknown node ids are dropped and their cost refunded. A gate no longer met after a data change refunds the deepest invalid tiers first (deterministic: highest tier, then id order).
- **Reset with no gold**: rejected (`cannot_afford`). Race reset is free, so a player can always rebuild race/combo.
- **Race file removed**: the card falls back to `default_race` (races-and-classes.md 5). Its race/combo nodes are refunded as in a race change.
- **New class with no combo in a race**: `default_combo` from that race is used, and the data test warns.
- **Exclusive pair data error** (a pair with 1 or 3 nodes): load error.
- **Mods that conflict**: two `pilot_mod cast_center` values cannot exist on one card (one per skill). Node `CONTROL_IMMUNE` + an enemy stun: the stun is ignored, and taunt still works on the enemy side.
- **Death save + revive on the same card** (Valhalla's Call, then World Tree from an Elf ally): the death save runs first. If it ends with the card down, the revive may then run. Each is once per wave.
- **Twin Ultimate on a revive ultimate (Rebirth Bloom)**: the echo can't revive anyone already revived this wave (shared flag), so it only heals and regens.
- **Overcharge with Rune Battery**: reset to 1 after a scaled discharge. Payload scale is capped at (max+2)/max.
- **Online**: tree edits are server commands, validated like `card_look`. Built as four commands (PO default 2026-11-13, docs/po_defaults.md): `tree_learn` {card, node}, `tree_save` {card, draft} (the whole draft, saved or rejected as a whole), `tree_reset_class` {card}, `tree_reset_race` {card}; `card_race` returns the refunded race/combo points. Rooms receive each card's validated tree in the deck they already send. The sim never trusts client node lists. Determinism: chance-based nodes use the fighter's sim RNG; replays and prediction stay exact.
- **XP double pay**: XP is granted inside the once-only haul commit (`haul.committed`), so a double "end run" never doubles XP.

## 6. Dependencies (both ways)

### 6.1 Table

| System | Direction | Contract |
|---|---|---|
| `design/gdd/races-and-classes.md` | tree → races | Reads the 16 passives (3.4), 16 ultimates (3.10), gauge (4.7), vocabulary (3.6). Adds `cell_mod`/`gauge_mod`/`signature_mod` and the events/actions in 3.5. **That doc should add**: a `tree` block in `data/races/<id>.json` and `data/classes/<id>.json` (3.7), the `card_race` side effect "reset race+combo branches", and a link back here. |
| `logic/skill_build.gd` | replaced | v1 rules (start node, `allocated`, gem rows, `max_points`, `reskill_gold`) are replaced by a new `logic/skill_tree.gd` (pure logic: load, validate, points, resets). `skill_build.gd` keeps only migration helpers until old saves are gone. |
| `data/skill_system/scripts/build_calc.gd` | reused | `calc_skill(skill, mods, ...)` takes the node mods instead of gems. The chart/tree passives (`full_tree.tres`, `chart54.json`) are no longer read. |
| `logic/skills/system.gd` | sim ↔ tree | `attach(id, build)` receives the v2 tree. The caster gets per-skill computed stats from node mods. It hooks `skill_mod`, `skill_refresh`, the `skill_cast`/`skill_hit` events, and the new `skill` trigger filter. The caster's pattern comes from the class, not `build.start`. |
| `logic/card_deck.gd` / `logic/profile.gd` | tree → card | `card_gear[card].progress {level, xp}` and `card_gear[card].skill_tree`. Repair and migration (5). |
| `logic/commands.gd` / server | client → server | `skill_tree` command, XP grant at haul commit, `card_race` reset side effect. |
| `logic/auto_pilot.gd` | tree → pilot | 6.4. |
| `design/gdd/drops-and-rewards.md` | rewards → tree | XP is a new faucet paid at the same haul commit (3.6 there). **That doc should add** "card XP" to its sources and summary screen. |
| `logic/journey.gd` / `coop_journey.gd` | journey → tree | Wave/boss/win counts for 4.3. Tree snapshot at run start. |
| `tools/balance/class_sim.gd` | measures | `tree=` arg (preset builds per card), 8. |
| Client: card character screen | display | Skills tab (section 9), XP bar on the card, run summary "+XP / LEVEL UP". |
| `data/combat/effects.json` + skill statuses | reused | Statuses by id. |

### 6.2 What this system provides
Per card: effective skill stats per slot, the list of active effects (passive/ultimate/signature mods), the gauge mods, pilot mods, and level/points for UI.

### 6.3 What it requires
The race engine (`logic/race_passives.gd`, races-and-classes.md phase 2+) for `cell_mod`/`gauge_mod`. Without it, race and combo nodes are inert, so their implementation waits for that phase (section 10).

### 6.4 Auto-pilot and modifiers (how the AI uses unlocked nodes)
- The pilot **never reads node ids**. It reads the *effective* skill stats from the tree calc (radius, range, projectile count, pierce, chain, cast center, cooldown, stamina). Its existing rules (`skill_min_targets`, hold until 2+ enemies in radius, support skill below X% HP) then use those numbers. Example: with Wide Quake, the slam's radius is 4.5, so "2+ enemies in radius" is checked at 4.5 m.
- Multi-projectile / pierce / chain skills count targets along the shot. For multishot the cone is ±15°, for pierce the line to the target ±0.8 m wide, for chain the chain range from the first target. The hold rule fires when the count is at least `skill_min_targets + hold_min_targets_add`.
- `cast_center: densest` (Remote Ring) makes the pilot cast at the densest point within the skill range instead of at itself.
- `kite_drop_skill` (Kiting Snare): when the kite step starts and that skill is ready, it is cast at the card's feet first.
- Echo / charge / quickcast / quickcd need no pilot change. Charge's longer cast is accepted. The pilot doesn't cancel.
- Ultimate-related nodes (`fire_at`, Berserkergang) change only the gauge threshold the existing `use` rule checks (races-and-classes.md 3.10.4).

## 7. Tuning Knobs

All in `data/skill_tree/rules.json` unless noted.

| Knob | Default | Safe range | Category | Affects |
|---|---|---|---|---|
| `max_level` | 25 | 20-30 | gate | length of the macro-loop |
| `milestone_levels` | [10, 20] | 0-3 entries | curve | bonus points, level-up excitement |
| `xp_base`, `xp_exp` | 100, 1.2 | 60-150, 1.0-1.5 | curve | runs to max (≈ 40-150 wins) |
| `xp_rewards` (wave 20+5w, boss 100, win 50) | - | ±50% | curve | XP per run; loss vs win share |
| tier gates class [0,3,8,13] / race [0,2,6,8] | - | ±2 each | gate | how early majors/capstones arrive |
| node costs minor/major/capstone | 1/2/3 | 1-2 / 2-3 / 3-5 | gate | % of the tree affordable (target 70-80%) |
| combo gate (class 8, race 6) | - | 6-10 / 4-8 | gate | whether combo + class cap fits |
| `class_reset_gold_per_point` | 50 | 0-200 | gate | cost of experimenting (OPEN Q1) |
| node numbers (in class/race files) | per node | each node +3-12% card power | curve | build strength |
| `pilot_mod` cone/line widths | 15°, 0.8 m | 10-25°, 0.5-1.2 m | feel | how often modified skills fire |

## 8. Acceptance Criteria

Functional (testable):
1. Every class and race file's `tree` loads. An unknown effect type, event, action, stat, skill id or status id fails `tests/run_all.gd`. Each tree has exactly 25 nodes, and each exclusive group has exactly 2 nodes.
2. `points(L)` matches 4.1 for L = 1, 2, 10, 20, 25 (0, 1, 10, 21, 26). XP from a scripted full win = 700, a loss after 5 waves = 175.
3. Server validation: each reason in section 5 is produced by a scripted bad draft. A valid draft round-trips (save → load → same tree).
4. Race change: race and combo nodes are cleared, points refunded, class nodes unchanged, gold unchanged.
5. Migration: a v1 save with 7 allocated nodes (+ start) loads as level 8, 7 points, empty v2 tree, and runs once only.
6. Each T2 modifier gives the same effective stats as the old gem it replaces (`build_calc` comparison test, 19 gems).
7. Each node shows its effect in a scripted sim: trigger count > 0 or a stat difference matching section 4 within rounding.
8. Adding a test race file with 8 nodes + 4 combos, and a test class with 16 nodes, works with **zero code changes**.
9. Budget: a solver test confirms that no 26-point build holds both branch capstones (4.4).
10. Full suite passes.

Experiential (playtest):
- Shown two fights of the same card with two different builds, a tester can name at least 2 visible differences (trap at feet, pulled pack, double ultimate...).
- New players hit level 2 after their first run (win or lose past wave 3) and spend the point without help.
- Balance (class_sim): the starter squad at levels 1-3 wins 72-75% on goblin_waves (Boss target). A max-level squad wins 90%+ (outgrowing content is the reward; harder stages are a content dependency). For each card at max level, its 2 capstone routes (class+combo vs race+combo) are within ±5 pts win rate of each other. No exclusive pair choice has a > 70/30 pick split among class_sim's best builds.

## 9. UI / Art brief (ux-ui-designer + Codex)

### 9.1 The Skills tab (inside the card character screen)
- **Place**: the third tab of the card character screen (Equipment · Outfit · **Skills**). The card portrait stays at the left (as in Equipment). The tree fills the centre-right. A detail panel docks at the right edge.
- **Header strip**: card level + XP bar (stitched leather bar, gold fill), "Points: N" coin, branch point counters (Class n · Race n · Combo n), buttons **Reset Class (gold)**, **Reset Race (free)**, **Confirm** (only active with draft changes) and **Cancel draft**.
- **Tree canvas**: a sheet of aged **parchment** pinned on brown stitched leather, drawn like an **inked campaign map**:
  - The class branch is a road climbing from the bottom-left (T1) to a mountain-top fort (T4 capstones). Each skill's T1 → T2 fork is an ink road splitting into two paths with an "OR" wax seal.
  - The race branch is a river or ley-line in the race colour climbing from the bottom-right to a race shrine (T4).
  - The **combo capstone** sits at the top centre where road and river meet, framed as a large compass rose.
  - Tier bands are faint contour lines labelled with the gate in ink numerals ("3", "8", "13").
- **Landscape and phone**: fits 1280×720 and 960×540 without scrolling at the "Fit" zoom. Pinch/drag pan with a Fit button. Node hit area ≥ 96 px on phones (minor icons drawn at 96 px, majors 112 px, capstones 144 px, combo 160 px). Tap selects; the detail panel shows name, text, cost, gate, and **Learn** / **Unlearn (draft)**. No hover-only info. Double-tap = learn (same as gear double-tap, po_defaults 2026-11-12).
- **Feedback**: learning a node draws the ink path filling with colour (0.3 s) and a wax-stamp thud. Confirm plays a quill-scratch, and the tree "dries" (a short sheen).

### 9.2 Node states
| State | Look |
|---|---|
| **Locked** (gate not met or exclusive partner taken) | icon in sepia/greyscale ink wash, frame dull, small wax padlock; exclusive-locked shows the partner's seal crossed |
| **Available** (gate met, can afford) | full-colour icon at 70% brightness, frame rim softly pulsing in its class/race colour, ink path to it dashed |
| **Available, no points** | as Available without pulse, cost numeral in red ink |
| **Taken** | full-bright icon, gilded frame with the class/race enamel lit, solid coloured ink path, small ribbon tick |
| **Draft (unconfirmed)** | Taken look with a wet-ink shimmer and a dashed outline until Confirm |

### 9.3 Frames
Painted round frames, metal and leather, matching the hub's leather card frames:
- **Class frames** (one per class, art-director to confirm hues): S&S **burnished steel, cold blue-grey enamel** · GS **blackened iron with copper rivets, ember-orange enamel** · Longbow **carved antler/bone, moss-brown enamel** · Magic **dark silver filigree, deep ink-blue enamel**.
- **Race frames**: Human **gold** `#ffc23a` · Viking **blood red** `#e0302a` with knotwork · Elf **leaf green** `#4fe07a` with vine relief · Runeborn **cyan `#3fe6ff` rim with violet `#9a5cff` glyph inlay**.
- **Capstone frames**: same set, ~1.5× size with a crown/spike ring (8: 4 class + 4 race). **Combo frame**: a compass-rose frame split half class metal, half race enamel (one frame drawn with two tint masks).
- Frame asset count: 4 class + 4 race + 8 capstone + 1 combo (2 masks) + state overlays (padlock seal, OR seal, ribbon tick, wet-ink outline) = **21 UI pieces**.

### 9.4 Icon style (for every Codex prompt)
> Painterly dark-fantasy game icon, hand-painted on a warm parchment-toned background, strong silhouette readable at 64 px, limited palette with one accent colour, soft rim light, visible brush texture, no text, no frame (the frame is a separate asset), centred subject, 512×512, transparent outside a circle of 480 px.

Accent colour = class colour for class nodes, race colour for race nodes, both for combos.

### 9.5 Icon list (112 node icons)

**sword_shield (16)**
- ss_t1_storm Tempest Step: a knight mid-dash trailing steel blade-ghosts, enemies' eyes turning toward him.
- ss_t1_riposte Iron Answer: a round shield deflecting a blade with a spark burst, a faint stone-armour sheen.
- ss_t1_blood Shared Blood: two red-glass shields linked by a thread of blood light.
- ss_t1_flame Ward Line: a burning line on the ground with a heavy boot stepping over it.
- ss_t2_storm_a Echo Edge: one sword slash with a translucent second slash echoing behind.
- ss_t2_storm_b Shield Bash: a shield rim slamming into a goblin's face, stars and dust.
- ss_t2_riposte_a Heavy Counter: a parry turning into a huge downward cleave, cracked ground.
- ss_t2_riposte_b Bleeding Riposte: a thin crimson cut arcing off a parried blade.
- ss_t2_blood_a Thorned Shell: a red crystal shield bristling with thorns.
- ss_t2_blood_b Mending Shell: a red shield with a soft pulse of green-gold light inside.
- ss_t2_flame_a Wide Trail: a broad river of flame trailing a sprinting knight.
- ss_t2_flame_b Quick Step: a boot with motion lines over small embers, an hourglass shadow.
- ss_t3_a Unyielding Bulwark: a tower shield planted in the ground, a ring of red taunt runes around it.
- ss_t3_b Rallying Wall: a raised shield with a banner, faint fortify shields above three silhouettes.
- ss_t4_a Spiked Bastion: a spiked shield wall where incoming arrows rebound as red streaks.
- ss_t4_b Immovable: a knight anchored like a statue as a shockwave breaks around him.

**greatsword (16)**
- gs_t1_slam Faultline: a greatsword striking earth, cracks pulling small figures inward.
- gs_t1_shatter Cold Iron: a blade coated in frost, ice crystals on the edge.
- gs_t1_eruption Banked Embers: glowing embers caught in the fuller of a greatsword.
- gs_t1_cry Battle Hymn: an open-mouthed warrior helm with orange sound rings.
- gs_t2_slam_a Wide Quake: a wide circular shockwave across stone.
- gs_t2_slam_b Aftershock: two concentric quake rings, the second fainter.
- gs_t2_shatter_a Dense Impact: a narrow, intensely bright impact point, compressed debris.
- gs_t2_shatter_b Shock Shatter: an ice block splitting with blue lightning inside.
- gs_t2_eruption_a Wide Eruption: a broad fan of lava bursting from the ground.
- gs_t2_eruption_b Charged Eruption: a sword raised over a swelling magma glow.
- gs_t2_cry_a Long Hymn: a war horn with a long trailing banner.
- gs_t2_cry_b Thorn Hymn: a war horn wrapped in thorny vines.
- gs_t3_a Executioner's Arc: a massive arc cutting through three silhouettes.
- gs_t3_b Momentum: a spinning greatsword with speed streaks and a rising arrow.
- gs_t4_a Titan's Swing: a top-down full-circle blade sweep ring.
- gs_t4_b Unstoppable: a charging warrior with chains snapping off.

**longbow (16)**
- lb_t1_pierce Marked Line: an arrow passing through three targets, each tagged with a red mark.
- lb_t1_trap Kiting Snare: a ranger stepping back while a thorn snare springs at her feet.
- lb_t1_lance Frostbite: an ice spear with three frost rings.
- lb_t1_chain Arc Seeker: lightning arcing to a mark sigil.
- lb_t2_pierce_a Split Volley: three arrows fanning from one bow.
- lb_t2_pierce_b Heavy Draw: a bow drawn to its limit, glowing string.
- lb_t2_trap_a Briar Field: a wide circle of thorn briars.
- lb_t2_trap_b Bleeding Thorns: thorns dripping crimson.
- lb_t2_lance_a Glacier Pierce: an ice lance through two blocks of ice.
- lb_t2_lance_b Quickdraw: a hand releasing an arrow with blur lines.
- lb_t2_chain_a Forked Storm: a lightning bolt splitting into many forks.
- lb_t2_chain_b Stunning Bolt: a bolt hitting a helmet with dizzy stars.
- lb_t3_a Deep Mark: a hunter's mark sigil burned deep, slowly dripping.
- lb_t3_b Pack Hunt: three arrows converging on one mark.
- lb_t4_a Deadeye: a narrowed eye reflected in an arrowhead.
- lb_t4_b Skirmisher: a ranger mid-backflip loosing an arrow.

**magic (16)**
- mg_t1_fireball Kindling: a fireball trailing two flame tongues.
- mg_t1_ring Repelling Ring: a fire ring pushing figures outward.
- mg_t1_strike Conductor: a lightning rod staff tip crackling.
- mg_t1_armor Biting Frost: a frost-armoured arm with a goblin hand freezing on contact.
- mg_t2_fireball_a Triple Fireball: three fireballs in a spread.
- mg_t2_fireball_b Echo Fireball: a fireball with a ghost fireball behind it.
- mg_t2_ring_a Remote Ring: a fire ring far away, a pointing staff in the foreground.
- mg_t2_ring_b Dense Ring: a small, white-hot fire circle.
- mg_t2_strike_a Wide Strike: a broad lightning column with a wide ground scorch.
- mg_t2_strike_b Quick Strike: a quick zigzag bolt with an hourglass.
- mg_t2_armor_a Long Frost: frost armour with icicles growing long.
- mg_t2_armor_b Thorned Frost: ice armour with spikes.
- mg_t3_a Weave Rhythm: three spell circles in a row, the third glowing gold.
- mg_t3_b Overload: a spell tome crackling with three cooldown runes breaking.
- mg_t4_a Elemental Convergence: fire, ice and lightning spirals meeting in a burst.
- mg_t4_b Blink Caster: a mage vanishing in sparks, a fire ring where she stood.

**Human (8, gold)**
- hu_1 Drilled Ranks: a row of gold-trimmed helmets in perfect order.
- hu_2 Ready Stance: a gauge vial already half full of gold light.
- hu_3 Disciplined Casting: an open training manual with gold glyphs lifting off.
- hu_4 Grand Command: a commander's baton raised, a wide gold circle below.
- hu_5 Field Command: a war-table map with a gold hourglass.
- hu_6 Scholar's Edge: a quill crossed with a sword, a gold spark on the tip.
- hu_7 Twin Ultimate: two gold suns, the second fainter.
- hu_8 Mastery Overflow: a gold chalice overflowing with light.

**Viking (8, red)**
- vk_1 Thick Blood: a beating heart wrapped in knotwork, dark red.
- vk_2 Battle Scent: a wolf's snout with red mist.
- vk_3 Blood Price: an axe dripping red into a runic bowl.
- vk_4 Red Harvest: a sickle-axe with red droplets flowing back to the wielder.
- vk_5 Red Mist: a war-painted face in a red haze.
- vk_6 Trophy Hunter: a belt of goblin-tooth trophies.
- vk_7 Valhalla's Call: a winged helm before a gate of light.
- vk_8 Berserkergang: a bear pelt hood with burning eyes.

**Elf (8, green)**
- el_1 Deep Roots: tree roots glowing green under soil.
- el_2 Sap Flow: green sap flowing up a bark channel into a vial.
- el_3 Overgrowth: a flower blooming wide with healing motes.
- el_4 Cleansing Dew: a dewdrop falling on a broken chain.
- el_5 Kin Bond: two elven hands touching, a green glow between.
- el_6 Evergreen: a small grove circle of saplings on the ground.
- el_7 World Tree: a vast tree with a figure rising from its roots.
- el_8 Bloom Cascade: petals spilling from one flower into the next.

**Runeborn (8, cyan/violet)**
- rb_1 Quick Glyphs: a short rune chain of four cyan stones.
- rb_2 Stored Power: a rune stone feeding light into a gauge vial.
- rb_3 Empowered Discharge: a rune stone exploding in violet light.
- rb_4 Runic Ultimate: a large cyan sigil with a violet core.
- rb_5 Rune Battery: a ring of runes with one still lit after a burst.
- rb_6 Warding Sigil: a cyan ward cracking and spitting violet sparks.
- rb_7 Overcharge: rune stones stacked past a brim, glowing white-hot.
- rb_8 Resonance: three rune stones humming in sync, wave lines between.

**Combo (16, class colour + race colour)**
- combo_hu_ss Drillmaster's Wall: a gold-trimmed tower shield with a drill-sergeant whistle.
- combo_hu_gs Perfect Form: a greatsword arc drawn as a perfect gold circle.
- combo_hu_lb Called Target: a gold crosshair sigil over a boss silhouette.
- combo_hu_mg Grand Archmage: two identical spell circles, gold filigree.
- combo_vk_ss Wall of Fury: a red war-painted shield with snarling knotwork.
- combo_vk_gs Blood Cyclone: a red whirlwind of blades.
- combo_vk_lb Trophy Volley: arrows fletched with red feathers chasing a fleeing goblin.
- combo_vk_mg Blood Sorcery: a staff drawing a red moon from a cut palm.
- combo_el_ss Grove Warden: a shield sprouting leaves, green light around three allies.
- combo_el_gs Bark and Blade: a greatsword with a bark-wrapped grip, leaves on the swing.
- combo_el_lb Moonwell Arrows: a crescent moon reflected in a well, arrows rising.
- combo_el_mg Spring Rite: a staff planting a blossom that bursts in petals.
- combo_rb_ss Runic Bulwark: a shield face covered in glowing cyan runes.
- combo_rb_gs Shatterglyph: a greatsword driving a violet glyph into cracked ground.
- combo_rb_lb Glyph Arrows: an arrow trailing a chain of cyan glyphs.
- combo_rb_mg Grand Runeweaver: a mage weaving a violet web of runes over allies.

Total art ask: **112 node icons + 21 frame/state pieces + 1 parchment-map background per class (4) with race river overlay (4 tints)**. All via Codex (`docs/tech/codex_image_workflow.md`), Boss review before import, under `art_source/ui/skill_tree/` → `art/ui/skill_tree/`. Suggested batch order: frames and states → 16 icons for the starter card (S&S + Human) → the rest.

## 10. Implementation Phases and Tests

1. **Data + rules** (`data/skill_tree/rules.json`, `tree` blocks in 4 class files and 4 race files, `logic/skill_tree.gd`: load, points, validate, resets). *Tests*: AC 1, 2, 3, 9; loading every node; gate math cases.
2. **Card progress + XP**: `card_gear[card].progress`, XP at haul commit, `skill_tree` command, `card_race` reset side effect, v1 → v2 migration. *Tests*: AC 2, 4, 5; double commit pays once; in-run edit rejected.
3. **Class branch in the sim**: `skill_upgrade` through `build_calc` (gem parity, AC 6), `signature_mod`, `pilot_mod`, the new class mechanics (`pull`, `reflect`, `CONTROL_IMMUNE`, `heavy_arc`, `skill` trigger filter, `skill_status`, blink). *Tests*: one per class node (AC 7), the pilot hold rule with modified radius, Kiting Snare cast on kite.
4. **Race branch + combo** (after races-and-classes.md phases 2-6): `cell_mod`, `gauge_mod`, `death_save`, `cleanse`, `overheal`, `rune_discharge`. *Tests*: one per race node and combo (section 4 numbers); revive flag shared; Twin Ultimate gives no gauge.
5. **UI** (ux spec `design/ux/skill-tree.md` first, then Codex art): Skills tab, states, draft/confirm, level-up on the run summary. *Tests*: 960×540 and 1280×720 captures, 96 px hit areas.
6. **class_sim tree presets + tuning pass**: presets per card (L1, L10 class-heavy, L25 class-cap+combo, L25 race-cap+combo). Re-check the goblin_waves target at levels 1-3. *Tests*: balance targets in section 8.
7. **Online**: rooms read the validated tree from the deck. Server-only XP grant. *Tests*: tree identical on authority and prediction, bad draft rejected online.
8. **Retire v1**: remove the gem UI, `chart54`/`full_tree` reads and per-run point keys once the migration has run on live profiles.

## 11. OPEN QUESTIONS (for the Boss, via PO)

1. **Price to reset the class branch?** A. Free any time (more experimenting, choices weigh less). B. **Gold: 50 per point refunded (~950 for a full class branch, under one run's gold)** (**default**). C. Only with a rare item.
2. **How much of the tree can a max-level card own?** A. **26 of 35 points (~74%) at level 25, so both branch capstones never fit together** (**default**). B. Almost all (level 30, 31 points). C. Stricter, about 60% (level 20).
3. **Old saves**: A. **Old tree points become card levels (n old nodes → level 1+n) on that card, gems dropped, any gem gold refunded** (**default**). B. Everyone restarts at level 1.

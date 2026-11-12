# Class Skills (4 per class, 16 total) — v2 replacement set

> Status: DRAFT v1 (game-designer, 2026-11-13). Replaces every skill in `data/skill_system/integration.json` `class_skills`.
> Tier: standard (Overview, Detailed Rules, Formulas, Edge Cases, Dependencies, Tuning Knobs, Acceptance Criteria).
> Related: `design/gdd/races-and-classes.md` (roles, pilot profiles, effect vocabulary 3.6, race ultimates 3.10), `design/gdd/skill-tree.md` (class branch 3.8).

## 1. Overview

Each class card casts 4 class skills automatically, chosen by its auto-pilot. The old set (16 skills borrowed from the gem-based skill system) mixed element themes (fire on sword_shield, ice and lightning on the longbow, fire and lightning on magic), did not follow the class roles, and was not linked to the races or the new skill tree. This document defines 16 new skills, 4 per class, built only from **class material** (shield, greatsword, bow, raw arcane force), with **no elements and no healing or ally shields**. Elements are gone; race themes (healing, shields, fury, runes) stay on the race axis (races-and-classes.md 3.1). Each skill names its clip on the Studio character (studio05), a short VFX brief for the separate VFX tool, and an SFX line. Section 3.6 maps every old skill to its replacement so the skill-tree nodes in `data/classes/*.json` can be re-pointed.

## 2. Player Fantasy (short)

- **sword_shield**: "Nothing reaches my friends." It crashes into whatever threatens the back line, braces, and takes hits for allies.
- **greatsword**: "The bigger the pack, the better." It hooks enemies together and reaps them in wide arcs.
- **longbow**: "Pick one, drop it." It marks, pins and executes single targets while it stays out of reach.
- **magic**: "Control the field." It blasts packs, pushes away anyone who gets close, and protects the most threatened ally.

MDA aesthetics: Challenge (reading the pilot's good choices), Fantasy (class roles you can tell apart at a glance), Sensation (heavy, readable impacts). SDT Competence: every skill has one clear job, so a player can say why a fight was won.

## 3. Detailed Rules

### 3.1 Design rules for all 16 skills

1. **One job per skill.** Each class has 4 jobs: a main damage skill, a control/positioning skill, a defensive or utility skill, and a "situational burst" skill.
2. **Race-agnostic.** No skill heals allies, shields allies, scales with missing HP or uses charges. Those belong to the races. Self-only defence (damage reduction, poise) is allowed because it belongs to the tank/bruiser role.
3. **No overlap with race ultimates.** No class skill is a lasting zone, a team cooldown refresh, a revive, or a multi-target execute chain. Nearest risks are checked in 5.4.
4. **No elements.** Statuses come only from `data/combat/effects.json`: `stun`, `shock` (cannot move), `slow`, `weaken`, `sunder`, `haste`, `fortify`. Skill-system element statuses (burn, chill, freeze, bleed) are not used by the base skills. Tree nodes may still add bleed/stun as before (3.6).
5. **Damage = % of the caster's ATK** through the normal damage rule (DEF, crit). All numbers are first-pass; combat-designer tunes them (section 7).
6. **Timing.** Skills run at 60 ticks/s. "Cast" = time from the start of the clip to the release (damage) frame. The caster cannot act until "recover" ends. If the caster is stunned or killed before release, the skill is lost but its cooldown still starts (same rule as the old skills: no free retry).
7. **Clips.** Only clips that exist on studio05 (`art/characters/studio05/clips.json` for sword_shield, `classes/<class>_clips.json` for the others). A window `a–b` means: start the clip at `a` s, blend out at `b` s. "Release" is the time inside the clip when the effect happens. Most release times are the clip's `windup_end`..`strike_end` marks. Where a mark looks auto-generated (see 5.3) the row says "verify".
8. **Skill ids** are new; no old id is reused (so old saves and old `.tres` files cannot be confused with the new set).

### 3.2 sword_shield — Tank / Guard (pilot target: `peel`)

| # | id | Name | Player text | Job |
|---|---|---|---|---|
| S1 | `shield_rush` | Shield Rush | "Crash shield-first into the enemy threatening your allies and stun it." | Peel / main damage |
| S2 | `iron_guard` | Iron Guard | "Brace behind the shield: take half damage and strike back at every attacker." | Self defence + counter damage |
| S3 | `intercept` | Intercept | "Leap to a hurt ally and take a share of every blow meant for them." | Ally protection |
| S4 | `breaker_slam` | Breaker Slam | "Slam the shield into the ground; nearby enemies hit weaker." | AoE control |

**S1 Shield Rush** — cooldown 8 s. Target: the enemy nearest the most-hurt ally (the `peel` target) within 7 m; if none, the current target. The caster dashes in a straight line to 1 m from it (max 6 m, stops on the first enemy in the path) and hits it for **70% ATK** + `stun` 0.8 s (48 ticks; control immunity applies). Invulnerable during the dash travel (not the wind-up or recovery).
- AI rule: cast when the peel target is attacking an ally other than self and is 2-7 m away; otherwise cast on the current target when it is ready and within 3 m (do not waste it at range).
- Motion: `attack_3` window 1.417–2.40, dash during 1.417–1.817, release 1.817 (`windup_end`). Blend out at 2.40 (the rest of the clip to 3.6 is a slow recovery, cut it).
- VFX: steel-white streak along the dash path; on impact a flat silver shield-shaped shockwave (cone forward, 1 m) and stun stars on the target. Cast 0 s / travel 0.4 s / impact 0.1 s.
- SFX: heavy footsteps into a metal shield "clang-thud" with a short dull ring.

**S2 Iron Guard** — cooldown 12 s. Self stance for **3 s**: damage taken ×0.5 from all sides, the card cannot move or attack, and cannot be staggered. Each melee hit it takes during the stance triggers a counter on that attacker for **50% ATK** (max 4 counters per stance, at most one counter per 0.3 s). Ranged hits are reduced but not countered.
- AI rule: cast when 2+ enemies within 3 m are attacking this card, or a boss telegraphed move targets a point within 4 m (`boss_telegraph`), or own HP below 50% with 1+ enemy within 3 m. Never cast with no enemy within 3 m.
- Motion: `block` 0.0–0.60 (raise shield) → `block_idle` loop for the rest of the 3 s → each counter plays `attack_4` window 0.25–1.10, release 0.65, at 1.5× speed (about 0.57 s), then returns to `block_idle`. Exit with `block_2` 0.0–0.8.
- VFX: a pale steel half-dome in front of the card while the stance lasts; each blocked hit flashes a spark on the shield rim; each counter a short silver arc.
- SFX: shield raise "thunk"; each block a bright metal "ting"; counter a short swing whoosh.

**S3 Intercept** — cooldown 14 s. Target: the most-hurt ally within 8 m whose HP is below 60% and who is being attacked. The caster leaps to 1 m from that ally (max 8 m, 0.5 s travel, invulnerable in the air). On landing: `pulse_aggro` r3 m for 2 s, and a **link** for 6 s: 40% of all damage that ally takes (before the ally's own DEF) is taken by the caster instead (the caster's DEF and damage-taken modifiers apply to its share). The link breaks early if the two are more than 10 m apart or the caster goes down.
- AI rule: cast when the target condition above holds and the caster's own HP is at least 40%. Skip if the hurt ally is already linked.
- Motion: `jump` (base clip, length 2.125) window 0.10–1.60, take-off ~0.35, landing ~1.10 (verify visually: `jump` has no attack marks). Then `block` 0.0–0.45 on landing. Fallback if the jump reads badly: `crouching_2` + root-motion-free lerp.
- VFX: a silver arc trail through the air; on landing a ring of dust r3 m; a thin silver tether line from the caster to the linked ally for 6 s that pulses when damage is redirected.
- SFX: grunt + armour rattle on take-off, heavy landing thump, a soft metallic "hum" on each redirected hit.

**S4 Breaker Slam** — cooldown 9 s. Self-centred circle r3 m: **90% ATK** to every enemy inside + `weaken` 4 s (ATK −30%).
- AI rule: 2+ enemies within 3 m, or the boss within 3 m.
- Motion: `slash_4` window 3.00–4.22, release 3.40–3.62 (`windup_end`..`strike_end`). The first 3 s of the clip are not played.
- VFX: shield rim hits the ground: a grey stone crack ring r3 m with a dust burst; weakened enemies get a dull grey downward-arrow icon.
- SFX: deep ground "boom" with a short gravel scatter.

### 3.3 greatsword — Bruiser / Cleave (pilot target: `densest`)

| # | id | Name | Player text | Job |
|---|---|---|---|---|
| G1 | `reaping_arc` | Reaping Arc | "A huge forward sweep. Counts as a heavy hit, so Cleave grows with every enemy." | Main damage |
| G2 | `crater_leap` | Crater Leap | "Leap into the thickest pack and crash down, staggering everything around you." | Gap closer + AoE |
| G3 | `hook_sweep` | Hook Sweep | "Drag nearby enemies into a tight knot, then cut through them." | Grouping / control |
| G4 | `battle_trance` | Battle Trance | "Swing faster, refuse to flinch, and land heavies every other swing." | Self power window |

**G1 Reaping Arc** — cooldown 5 s. Frontal arc 240°, radius 3 m: **140% ATK** to every enemy inside. It **counts as a heavy hit** for the Cleave signature (+15% per extra enemy hit, max +45%) and for every `heavy_hit` event (Runic Edge, Momentum...).
- AI rule: 2+ enemies inside the arc, or the boss in the arc. Otherwise hold up to 3 s, then cast on whatever is in front.
- Motion: `gs_slash_3` window 0.233–1.453, release 0.633–0.853.
- VFX: a wide pale steel crescent (240°) on the ground plane, slight motion blur; small dust kicks where it touches enemies. Cast 0.4 s / impact 0.2 s.
- SFX: long low "whoom" of a heavy blade, layered flesh/armour hits per enemy.

**G2 Crater Leap** — cooldown 10 s. Target point: the `densest` point within 7 m (most enemies within 2.5 m). The caster leaps there (0.5 s air time, cannot be hit in the air) and lands: circle r2.5 m, **160% ATK** + `stun` 0.4 s (24 ticks, a stagger).
- AI rule: the densest point has 3+ enemies; or it has 2+ enemies and is more than 3 m away (gap closer); or the boss is 3-7 m away.
- Motion: `gs_jump_attack` window 0.0–1.60, release ~0.85 (landing) — **verify**: the clip marks say `windup_end` 0.05 which is not the landing frame; set the release from the visual landing frame. Movement lerp from take-off (~0.2) to landing.
- VFX: on landing, a stone crater decal r2.5 m with cracks and flying rocks; brown-grey dust ring outward. Cast 0.2 s / travel 0.5 s / impact 0.3 s.
- SFX: rising whoosh, then a ground-shaking crash with debris.

**G3 Hook Sweep** — cooldown 9 s. First a `pull`: every enemy within 5 m is pulled 2 m toward the caster (never past 1 m from it; bosses and elites are not pulled). Then a circle r2.5 m: **90% ATK** + `slow` 2 s.
- AI rule: 3+ enemies within 5 m but fewer than 2 within 2.5 m (the pack is loose); never if all enemies in 5 m are bosses/elites.
- Motion: `gs_slash_4` window 0.0–0.987; pull runs over 0.0–0.167, release 0.167–0.387.
- VFX: a low swirl of dust drawn inward toward the caster (reads as "pulled in"), then a flat steel ring cut r2.5 m.
- SFX: rushing air inhale, then a short heavy swipe.

**G4 Battle Trance** — cooldown 18 s. Self only, 6 s: `haste` (ATKSPD +25, MOVESPD +25), cannot be staggered (poise unbreakable on its normal attacks), and `heavy_every` becomes 2 (every 2nd swing is a heavy) for the duration. No healing, no team effect (old War Cry's team buff is gone: team buffs are a Human-passive theme).
- AI rule: 2+ enemies within 3 m, or the boss within 3 m. Do not cast with no enemy within 3 m.
- Motion: `gs_power_up` window 0.017–1.237, release 0.417 (the buff starts there). The rest of the clip (to 3.517) is cut.
- VFX: on release a heat-haze shimmer burst around the body (colourless distortion + white sparks), then a faint pale aura on the blade for 6 s.
- SFX: deep battle shout and a heartbeat-like low pulse.

### 3.4 longbow — Ranged single-target / Marks (pilot target: `lowest_hp`, boss first)

| # | id | Name | Player text | Job |
|---|---|---|---|---|
| L1 | `heartseeker_shot` | Heartseeker | "A fully drawn arrow that deals bonus damage to marked targets." | Main single-target damage |
| L2 | `pinning_shot` | Pinning Shot | "Nail an enemy to the ground before it reaches your friends." | Control / peel |
| L3 | `rapid_fire` | Rapid Fire | "Loose four quick arrows into one target." | Sustained single-target |
| L4 | `vault_shot` | Vault Shot | "Flip away from an attacker and shoot it as you land." | Escape / kite |

**L1 Heartseeker** — cooldown 6 s. Range 12 m, one arrow at the pilot's target: **260% ATK**, crit rate +25 for this hit, and ×1.5 if the target has `sunder` (Hunter's Mark).
- AI rule: target the boss if alive and in range, else an elite in range, else the pilot target. Cast when ready; prefer a marked target.
- Motion: `lb_draw_arrow` window 0.0–1.033 (slow draw), then `lb_aim_recoil` 0.0–0.70, release 0.10 (`windup_end`). Cast ≈ 1.13 s.
- VFX: a thin white light gathers on the arrow tip during the draw; the arrow leaves a straight silver streak; impact is a sharp white star burst (bigger on crit).
- SFX: long creaking bow draw, sharp "thwip", hard impact crack.

**L2 Pinning Shot** — cooldown 8 s. Range 12 m. Target: the enemy nearest a back-line ally (or nearest to self if no back-line ally is threatened). **120% ATK** + `shock` 1.5 s (cannot move; it may still attack in reach).
- AI rule: an enemy within 3 m of a back-line ally (magic/longbow) or of self; else the fastest-closing enemy within 8 m. Never on a target already shocked.
- Motion: `lb_aim_recoil` 0.0–0.70, release 0.10, played at 0.8× speed (about 0.88 s) so it reads as more deliberate than a basic shot.
- VFX: a heavy arrow with a short silver trail; on hit the arrow sticks in the ground at the target's feet with a small circle of pale cracks for 1.5 s.
- SFX: heavier "thunk" of an arrow into earth, a short rope-tight twang.

**L3 Rapid Fire** — cooldown 7 s. 4 arrows at the current target, 0.25 s apart, **55% ATK each** (220% total). If the target dies, the remaining arrows go to the next pilot target within 12 m. Each arrow is a skill hit (not a basic hit, see 5.2).
- AI rule: cast when ready on the pilot target within 12 m.
- Motion: `lb_aim_recoil` window 0.0–0.32, release 0.10, played 4 times back to back at 1.28× speed (0.25 s each).
- VFX: four short silver tracers; small spark per hit.
- SFX: four fast "thwip" sounds with slight pitch variation.

**L4 Vault Shot** — cooldown 9 s. The caster flips 4 m directly away from the nearest enemy (0.4 s, invulnerable during the flip), then shoots that enemy: **90% ATK** + `slow` 3 s. If the landing spot is blocked, it moves as far as it can (min 1 m).
- AI rule: an enemy within 3 m. This is the kite rule (pilot `kite_distance`); when Vault Shot is ready the pilot uses it instead of the plain dodge.
- Motion: `lb_dodge_backward` window 0.0–1.20 (movement over 0.0–0.6), then `lb_aim_recoil` 0.0–0.70 release 0.10. Total ≈ 1.3 s.
- VFX: a pale dust puff at the take-off spot, a silver arrow streak on the shot, slowed enemy gets a grey trailing smear.
- SFX: cloth whoosh and boot scuff, then a "thwip".

### 3.5 magic — AoE / control / support caster (pilot hold rule: 2+ targets)

| # | id | Name | Player text | Job |
|---|---|---|---|---|
| M1 | `arcane_orb` | Arcane Orb | "A slow orb of raw force that bursts on impact." | Main AoE damage |
| M2 | `repulse_nova` | Repulse Nova | "Blast everything near you away." | Self-defence / control |
| M3 | `starfall` | Starfall | "Call a falling star onto the thickest pack." | Big AoE burst |
| M4 | `warding_veil` | Warding Veil | "Wrap a threatened ally in a veil that dulls blows and quickens them." | Ally support (no heal/shield) |

**M1 Arcane Orb** — cooldown 3.5 s. Projectile, speed 12 m/s, range 12 m, aimed at the target; it bursts on the first enemy hit or at max range: circle r2 m, **100% ATK**.
- AI rule (class hold rule): 2+ enemies within 2 m of the target, or the target is the boss; else hold, max 4 s, then cast anyway.
- Motion: `mg_spell_1h_cast_spell_01` window 0.033–1.253, release 0.433–0.653.
- VFX: a white-core orb with a deep blue rim (`#3a5cff`, the class tone), slight trail; a round white-blue shockwave burst r2 m. Cast 0.4 s / travel ~0.6 s / impact 0.25 s.
- SFX: rising hum during the cast, low "whum" pop on burst.

**M2 Repulse Nova** — cooldown 8 s. Self-centred circle r3 m: **90% ATK**, knockback 2.5 m away from the caster, `slow` 2 s. Bosses and elites take damage and slow but no knockback.
- AI rule: 1+ enemy within 2.5 m of the caster (self-defence; the hold rule does not apply), or 2+ enemies within 3 m.
- Motion: `mg_spell_2h_magic_area_attack_01` window 0.767–1.987, release 1.167–1.387.
- VFX: a flat expanding ring of blue-white force r3 m at waist height, ground ripple.
- SFX: sharp air "fwoomp" with a deep sub-bass push.

**M3 Starfall** — cooldown 10 s. Target point: the densest point within 9 m (most enemies within 2.5 m). A 0.8 s telegraph circle appears, then impact: circle r2.5 m, **220% ATK** + `stun` 0.3 s (18 ticks, a stagger). One impact only (not a lasting zone).
- AI rule: 3+ enemies inside r2.5 of a point within 9 m; or 2+ and one of them is an elite; or the boss within 9 m.
- Motion: `mg_spell_2h_magic_attack_05` window 1.533–2.753, release 1.933 (the telegraph starts here); impact lands 0.8 s later while the caster is already in recovery.
- VFX: a thin blue-white telegraph ring on the ground for 0.8 s, then a white streak falling from above and a bright blue-white crater flash r2.5 m with sparks.
- SFX: a rising whistle during the telegraph, then a heavy crystalline boom.

**M4 Warding Veil** — cooldown 14 s. Target: the most-hurt ally within 9 m whose HP is below 60% (self allowed). For 5 s: damage taken ×0.7, plus `haste` for 3 s (so a melee ally fights back faster or a ranged ally can step away). This is damage reduction, not a shield and not a heal (race themes stay clean).
- AI rule: support rule (`support_skill: warding_veil`, `support_below: 0.6`); if two allies qualify, pick the one with more enemies attacking it.
- Motion: `mg_spell_2h_cast_spell_01` window 0.70–1.92, release 1.10–1.32.
- VFX: a translucent blue-white veil that wraps the ally like cloth and stays as a faint shimmer for 5 s; a thin beam from caster to ally on release.
- SFX: soft glassy chime and a cloth-like whisper.

### 3.6 Old → new skill map and skill-tree node changes

| Old id (deleted) | New id | Class | Why this pairing |
|---|---|---|---|
| `storm_blades` | `shield_rush` | sword_shield | both are the dash attack |
| `riposte` | `iron_guard` | sword_shield | both are the counter stance |
| `blood_shield` | `intercept` | sword_shield | both are the defensive slot |
| `flame_dash` | `breaker_slam` | sword_shield | the area-control slot |
| `ground_slam` | `crater_leap` | greatsword | both are the stun-slam |
| `shatter_smash` | `reaping_arc` | greatsword | both are the main heavy damage |
| `eruption` | `hook_sweep` | greatsword | the "set up the pack" slot |
| `war_cry` | `battle_trance` | greatsword | both are the buff slot |
| `piercing_shot` | `heartseeker_shot` | longbow | main shot |
| `thorn_trap` | `vault_shot` | longbow | both serve kiting (Kiting Snare node) |
| `ice_lance` | `pinning_shot` | longbow | status shot → control shot |
| `chain_lightning` | `rapid_fire` | longbow | multi-hit damage slot |
| `fireball` | `arcane_orb` | magic | main projectile |
| `fire_ring` | `repulse_nova` | magic | self-centred ring |
| `lightning_strike` | `starfall` | magic | big single burst |
| `frost_armor` | `warding_veil` | magic | support / damage reduction |

`data/skill_system/integration.json` `class_skills` (or its replacement) becomes:
`blade: [shield_rush, iron_guard, intercept, breaker_slam]`, `greatsword: [reaping_arc, crater_leap, hook_sweep, battle_trance]`, `longbow: [heartseeker_shot, pinning_shot, rapid_fire, vault_shot]`, `magic: [arcane_orb, repulse_nova, starfall, warding_veil]`. The magic pilot's `support_skill` changes `frost_armor` → `warding_veil`.

**Node re-pointing** (node ids stay; `skill` fields, names and texts change where the meaning shifted). Element nodes are rewritten to class material. Numbers are placeholders for combat-designer.

sword_shield:
| Node | New name | New text |
|---|---|---|
| ss_t1_storm | Tempest Step → **Bulldozer** | Shield Rush also taunts: `pulse_aggro` r3 m, 2 s on impact. (unchanged effect, new skill) |
| ss_t1_riposte | Iron Answer (keep) | Iron Guard lasts 3 → 4 s. Each counter gives self `fortify` 3 s. |
| ss_t1_blood | Shared Blood → **Bodyguard** | Intercept link 40% → 55%. (The old ally shield is dropped: shields are race theme.) |
| ss_t1_flame | Ward Line → **Crushing Rim** | Breaker Slam radius 3 → 4 m and also applies `slow` 2 s. |
| ss_t2_storm_a/b | Echo Edge / Shield Bash (keep) | A: Shield Rush hits a second time at 50% (cooldown ×1.3). B: knockback 3 m, dmg ×0.9, stun 0.8 → 1.2 s. |
| ss_t2_riposte_a/b | Heavy Counter / Bleeding Riposte | A: counter 50% → 75% ATK. B: counters apply `bleed`, dmg ×0.9. |
| ss_t2_blood_a/b | Thorned Shell → **Thorned Link** / Mending Shell → **Long Watch** | A: while linked, the tank reflects 30% of the redirected damage to the attacker. B: link 6 → 9 s, cooldown ×1.2. (No regen: healing is race theme.) |
| ss_t2_flame_a/b | Wide Trail → **Wide Slam** / Quick Step → **Quick Slam** | A: radius ×1.5, dmg ×0.8. B: cooldown ×0.75, dmg ×0.85. |

greatsword:
| Node | New name | New text |
|---|---|---|
| gs_t1_slam | Faultline (keep) | Crater Leap first `pull`s enemies within 4 m 1.5 m toward the landing point. |
| gs_t1_shatter | Cold Iron → **Long Reach** | Reaping Arc radius 3 → 3.75 m. |
| gs_t1_eruption | Banked Embers → **Iron Hook** | Hook Sweep pull 2 → 3 m and range 5 → 6 m. |
| gs_t1_cry | Battle Hymn → **Deep Trance** | Battle Trance 6 → 8 s. (No ally reach: the skill is self-only now.) |
| gs_t2_slam_a/b | Wide Quake / Aftershock (keep) | A: landing radius ×1.5, dmg ×0.8. B: a second shockwave 0.5 s later at 50%. |
| gs_t2_shatter_a/b | Dense Impact → **Full Circle** / Shock Shatter → **Rending Arc** | A: arc 240° → 360°, dmg ×0.85. B: applies `sunder` 3 s to all hit, dmg ×0.9. |
| gs_t2_eruption_a/b | Wide Eruption → **Wide Hook** / Charged Eruption → **Heavy Hook** | A: radius ×1.5, dmg ×0.8. B: the cut counts as a heavy hit (Cleave) and dmg ×1.3, cast ×1.4. |
| gs_t2_cry_a/b | Long Hymn → **Long Trance** / Thorn Hymn → **Thorned Trance** | A: duration ×1.5, cooldown ×1.2. B: while active, reflect 20% of melee damage taken. |

longbow:
| Node | New name | New text |
|---|---|---|
| lb_t1_pierce | Marked Line (keep) | Heartseeker pierces, and every enemy it passes through gets Hunter's Mark (`sunder`). |
| lb_t1_trap | Kiting Snare → **Light Feet** | Vault Shot distance 4 → 5 m and `slow` 3 → 4 s. (`pilot_mod kite_drop_skill` is no longer needed; Vault Shot is the kite skill.) |
| lb_t1_lance | Frostbite → **Deep Pin** | Pinning Shot `shock` 1.5 → 2.25 s. |
| lb_t1_chain | Arc Seeker → **Hunter's Rhythm** | Rapid Fire 4 → 5 arrows. Arrows retarget to marked enemies first. |
| lb_t2_pierce_a/b | Split Volley / Heavy Draw (keep) | A: +2 arrows in a ±15° cone, dmg ×0.7. B: dmg ×1.5, cast ×1.6. |
| lb_t2_trap_a/b | Briar Field → **Smoke Vault** / Bleeding Thorns → **Parting Shot** | A: the take-off spot leaves a 2 s `slow` cloud r2 m (one-shot apply, not a damage zone). B: the landing shot applies `bleed`, dmg ×1.2. |
| lb_t2_lance_a/b | Glacier Pierce → **Through Pin** / Quickdraw (keep) | A: Pinning Shot pierces +2 and pins each target hit, dmg ×0.9. B: cast ×0.7, dmg ×0.85. |
| lb_t2_chain_a/b | Forked Storm → **Spread Fire** / Stunning Bolt → **Staggering Fire** | A: arrows alternate between the target and the next nearest enemy, dmg ×0.85. B: the last arrow applies `stun` 0.5 s. |

magic:
| Node | New name | New text |
|---|---|---|
| mg_t1_fireball | Kindling → **Dense Core** | Arcane Orb burst radius 2 → 2.5 m. |
| mg_t1_ring | Repelling Ring → **Far Push** | Repulse Nova knockback 2.5 → 3.5 m. |
| mg_t1_strike | Conductor → **Gravity Crush** | Starfall stagger 0.3 → 0.8 s on non-boss enemies. |
| mg_t1_armor | Biting Frost → **Thorned Veil** | Melee attackers of a veiled ally get `slow` 2 s. |
| mg_t2_fireball_a/b | Triple / Echo Fireball → **Triple Orb** / **Echo Orb** | A: 3 orbs in a cone, dmg ×0.7. B: a second orb 0.4 s later at 50%. |
| mg_t2_ring_a/b | Remote Ring → **Remote Nova** / Dense Ring → **Dense Nova** | A: cast at the densest point within 7 m (`pilot_mod cast_center: densest`), dmg ×0.9, no knockback. B: radius ×0.7, dmg ×1.4. |
| mg_t2_strike_a/b | Wide / Quick Strike → **Wide Starfall** / **Quick Starfall** | A: radius ×1.5, dmg ×0.8. B: cooldown ×0.75, dmg ×0.85. |
| mg_t2_armor_a/b | Long Frost → **Long Veil** / Thorned Frost → **Spiked Veil** | A: duration ×1.5, cooldown ×1.2. B: veiled ally reflects 25% of melee damage. |
| mg_t4_a | Elemental Convergence → **needs rewrite** | burn+chill+shock no longer come from base skills. Suggested **Arcane Convergence**: an enemy hit by 3 different magic skills within 4 s takes +40% skill damage; if it dies then, it bursts (r2.5 m, 100% ATK). |
| mg_t4_b | Blink Caster (keep) | ...leave a **Repulse Nova** (no cooldown cost) where it stood. |
| combo_hu_lb | Called Target (keep) | no skill id in it, unchanged. |

Other nodes (T3/T4 signatures, race nodes, combos) name no old skill id except `mg_t4_b` and Overload-style `skill` filters; grep `data/classes/*.json` and `data/races/*.json` for the 16 old ids when re-pointing.

### 3.7 Pilot summary (what `logic/auto_pilot.gd` must read)

Each skill's AI rule above is data: a `use` block per skill in the new skill data, written with the races-and-classes.md 3.7 condition list plus these skill-only conditions: `enemies_in_arc` {angle, radius}, `peel_target_attacking_ally`, `ally_below_hp_attacked` {hp, range}, `enemy_near_backline` {distance}, `self_attacked_by` {count, radius}. Priority inside a class when several are ready: defensive/utility first (S3, S2, L4, L2, M2, M4), then burst (S1, G2, M3), then main damage (S4, G1, G3, L1, L3, M1), then self-buff (G4) — G4 is cast first only when the boss is in range.

## 4. Formulas

**4.1 Damage.** `dmg = atk_pct × ATK × status_bonus × crit × (1 − DEF rule)`, using the existing damage rule. `status_bonus` = 1.5 for Heartseeker vs `sunder`, else 1. Cleave on Reaping Arc: `× (1 + min(0.15 × (n − 1), 0.45))`, n = enemies hit.
Example: ATK 100, Reaping Arc hits 3 enemies: 140 × 1.30 = **182** each before DEF (546 total).

**4.2 Intercept link.** For a hit of raw damage D on the linked ally: ally takes `0.6 × D` through its own DEF; caster takes `0.4 × D` through the caster's DEF and modifiers (Iron Guard ×0.5 applies). Example: D = 200, tank DEF rule reduces 30%, tank in Iron Guard: tank takes 0.4 × 200 × 0.7 × 0.5 = **28**; ally takes 0.6 × 200 × its rule.

**4.3 Pull.** Final distance to caster = `max(1.0, d − pull)`. Example: enemy at 4.5 m, pull 2 → 2.5 m (inside the 2.5 m cut).

**4.4 Skill DPS (single target, % ATK per second, all hits land)** — `rate = total_atk_pct / cooldown`.

| Class | Skill | Total % | CD s | %/s single | Typical targets | %/s at typical |
|---|---|---|---|---|---|---|
| S&S | Shield Rush | 70 | 8 | 8.8 | 1 | 8.8 |
| | Iron Guard (4 counters max, 2 typical) | 100 | 12 | 8.3 | — | 8.3 |
| | Intercept | 0 | 14 | 0 | — | utility |
| | Breaker Slam | 90 | 9 | 10.0 | 2.5 | 25 |
| | **total** | | | **27** | | **42** |
| GS | Reaping Arc (+Cleave at 3) | 140 (182) | 5 | 28 | 3 | 109 |
| | Crater Leap | 160 | 10 | 16 | 3 | 48 |
| | Hook Sweep | 90 | 9 | 10 | 3 | 30 |
| | Battle Trance | 0 | 18 | buff ~+25% basic DPS for 6 s | — | ≈ 8 equiv. |
| | **total** | | | **62** | | **195** |
| LB | Heartseeker (marked ×1.5) | 260 (390) | 6 | 43 (65) | 1 | 65 |
| | Pinning Shot | 120 | 8 | 15 | 1 | 15 |
| | Rapid Fire | 220 | 7 | 31 | 1 | 31 |
| | Vault Shot | 90 | 9 | 10 | 1 | 10 (situational) |
| | **total** | | | **99** | | **121** |
| Magic | Arcane Orb | 100 | 3.5 | 29 | 2.5 | 71 |
| | Repulse Nova | 90 | 8 | 11 | 2 | 22 |
| | Starfall | 220 | 10 | 22 | 3 | 66 |
| | Warding Veil | 0 | 14 | utility (−30% dmg on 1 ally 5 s) | — | — |
| | **total** | | | **62** | | **159** |

**Old set for comparison** (rough, old `.tres` damage ÷ `reference_atk` 20 ÷ cooldown, single target): S&S ≈ 12 (storm 60%/5 s) + 7 (flame dash) + 15 (riposte, only on a parry) ≈ **34 %/s**; GS ≈ 12.5 (slam) + 22 (shatter 110%/5 s) + 13 (eruption) ≈ **48 %/s**; LB ≈ 33 (piercing) + 12 (trap) + 28 (lance) + 20 (chain first target) ≈ **93 %/s**; magic ≈ 27 (fireball) + 25 (ring) + 21 (strike) ≈ **73 %/s**. These are estimates for direction only; class_sim gives the real baseline. The new single-target totals are within about ±30% of these (S&S lower on purpose, GS higher because Cleave/heavy now matter more). Combat-designer must re-baseline before tuning.

**4.5 Balance intent (skill share of each class's total output, combat-designer to verify with class_sim):**

| Class | Skill share of damage | Split inside the kit |
|---|---|---|
| sword_shield | 20-25% (lower than old: the dash-trail fire damage is gone; offset by Intercept/Iron Guard survival value) | Slam 45%, Rush 25%, Guard 30%; Intercept 0% damage, target: tank takes ≥ 40% of squad damage (race doc 8) |
| greatsword | 35-40% | Arc 55%, Leap 25%, Hook 15%, Trance (raises basic/heavy) |
| longbow | 35-40%, highest **single-target/boss** share of the squad | Heartseeker 50%, Rapid 30%, Pin 12%, Vault 8% |
| magic | 55-65% (Spellweave: most damage from skills) | Orb 45%, Starfall 40%, Nova 15%; Veil = utility |

Rule: per class, new skill DPS at typical targets within ±15% of the old set before tuning; S&S is deliberately −15% damage / + utility. No single skill above 60% of its class's skill damage.

## 5. Edge Cases

**5.1 Targeting**
- No valid target (all dead, out of range): the skill is not cast and no cooldown is spent (the pilot keeps trying).
- Shield Rush / Crater Leap / Intercept / Vault Shot path blocked by terrain: travel stops at the obstacle; the effect still fires at the stop point (Intercept: the link still starts if within 10 m).
- Intercept on an ally who dies or is downed during the leap: the leap finishes, `pulse_aggro` fires, no link starts, cooldown is spent.
- Intercept when two S&S cards link the same ally: the second cast is skipped by the AI rule ("already linked"). If forced, links do not stack: the newest replaces the oldest.
- Intercept and a linked ally inside Iron Guard: both modifiers apply as in 4.2. A downed caster breaks the link at once (no damage goes to a downed card).
- Warding Veil on an ally already veiled: refresh the duration, no stacking of ×0.7.
- Hook Sweep pull on bosses/elites: not pulled (still hit). Pull never moves an enemy through walls or into another enemy's spot (stops at the first collision).
- Repulse Nova knockback into a wall: the enemy stops at the wall, no extra damage.
- Rapid Fire target dies after arrow 2: arrows 3-4 go to the next pilot target within 12 m; if none, they are lost.

**5.2 Event bookkeeping (race passives / tree)**
- Every skill fires `skill_cast` once at release and `skill_hit` once per enemy per hit. Rapid Fire = 4 `skill_hit`s on its target; it does **not** fire `hit` (basic) events, so Elf Moonlit Arrow and Runeborn Glyph Shot do not count it. Iron Guard counters fire `skill_hit`.
- Reaping Arc fires `heavy_hit` once per cast (not once per enemy) so Runic Edge gains 1 rune per cast, same as a basic heavy.
- Hunter's Mark (signature) applies on the first hit on a new target from basic **or** skill hits (unchanged rule).
- Damage redirected by Intercept counts as damage taken by the S&S (gauge "taken", Rune Aegis "hurt") and not by the ally.

**5.3 Motion**
- `gs_jump_attack` and `lb_aim_overdraw` marks (`windup_end` 0.05) look auto-generated and do not match a real release frame. Crater Leap sets its landing time from a visual check; until then use 0.85 s. Flag OPEN for the animator.
- `jump` (base) has no marks; Intercept landing at 1.10 s is an estimate. OPEN until checked in a viewport capture.
- Clips longer than their window are cut with a 0.12 s blend out to the class idle; no clip plays its full length except `lb_draw_arrow` and `gs_slash_4`.
- Rapid Fire plays a 0.32 s window 4 times; if the restart pops visually, use a 0.05 s cross-fade.
- If a skill is cancelled (stun/death) mid-clip, play the class `hurt` state clip; no special handling.

**5.4 Overlap with race ultimates (checked)**
- Heartseeker vs Called Shot (Human bow ult 450% force-crit): Heartseeker is smaller (260%), not forced crit, no refresh. OK.
- Rapid Fire vs Glyph Barrage/Executioner's Volley: Rapid Fire stays on one target, no chain, no delayed hit. OK.
- Starfall vs Blood Moon / Arcane Singularity: Starfall is one instant hit, no zone. OK.
- Reaping Arc / Crater Leap vs Masterstroke / Ragnarok Whirl / Runebreaker: no spin, no zone, no multi-hit; the clips differ (ultimates use `gs_high_spin_attack` / `gs_slide_attack`). OK.
- Intercept vs Heartwood Bastion / Bastion Glyph: Intercept neither heals nor shields; it redirects damage on one ally. OK.
- Warding Veil vs race shields/heals: damage reduction only. OK.

**5.5 Degenerate strategies**
- Two S&S cards chain-casting Iron Guard: each card is immobile 3 s per 12 s; the boss's telegraphs still land on allies. Watch in sim: S&S uptime of Iron Guard should stay ≤ 30%.
- Repulse Nova pushing enemies out of the greatsword's Hook Sweep: accepted friction; magic's AI casts Nova only on enemies near itself (back line), the greatsword fights in front.
- Stun lock (Shield Rush 0.8 + Crater Leap 0.4 + Starfall 0.3 + tree upgrades): the existing control immunity window after a stun applies to all skill stuns; bosses are never stun-locked.

## 6. Dependencies

| System | Direction | Contract |
|---|---|---|
| `design/gdd/races-and-classes.md` | skills → races | Uses class roles/pilot profiles (3.2) and statuses; must not overlap ultimates (3.10). Races read `skill_cast` / `skill_hit` / `heavy_hit` events (5.2). Human `skill_mod` (damage, cooldown, radius, crit) applies to all 16. **That doc should add** a link here and change magic `support_skill` to `warding_veil` in 3.2. |
| `design/gdd/skill-tree.md` | tree → skills | Class T1/T2 nodes are re-pointed by 3.6. **That doc should update** 3.8 headings (skill lists) and node texts. |
| `data/classes/<class>.json` | data | `skill_tree.skills` list and node `skill` fields re-pointed (3.6); magic `pilot.support_skill`. Other agents own these files: change them in their task, not here. |
| `data/skill_system/integration.json` `class_skills`, `stamina`, `impact.tiers` | replaced | The old system is deleted. The new skill data needs per skill: id, name, cooldown, stamina cost, impact tier, kind, numbers, statuses, `use` rule, clip window + release. |
| `logic/skills/*` (old engine) | replaced | Reference for what exists today: dash (`storm`, `trail`), parry (`parry`), self buff (`shield`, `armor`, `cry`), area (`area`, `slam`), projectiles (`fireball`, `piercing`, `lance`), status bonus (`strike` `shocked_mul`), `blink`. |
| `logic/auto_pilot.gd` | pilot → skills | Reads `use` rules (3.7) and the priority order. |
| `logic/race_passives.gd` | shared actions | `pulse_aggro`, `pull` (tree vocab), `apply_status` reused by skills. |
| `data/combat/effects.json` | statuses | stun, shock, slow, weaken, sunder, haste (existing). New buff ids needed: `iron_guard` (DMG_TAKEN ×0.5, no move), `warding_veil` (DMG_TAKEN ×0.7), `intercept_link`. |
| Client (`client/` skill visuals, clip player) | display | Plays the clip window per skill (3.2-3.5); VFX keys `class_skill/<id>` from the VFX tool later; placeholder: reuse the nearest existing vfx key in a neutral tint. |
| `tools/balance/class_sim.gd` | measures | Per-skill casts, damage, targets per cast, Intercept damage redirected, Veil damage prevented. |

### 6.1 New engine needs (flag for lead-programmer)

| # | Need | Used by | Note |
|---|---|---|---|
| E1 | **Damage link** (redirect a fraction of an ally's incoming damage to the caster) | Intercept | New. One hook in incoming damage. |
| E2 | **Ally-targeted travel** (leap/dash to an ally, not an enemy) | Intercept | Extend the dash/blink movement with an ally target. |
| E3 | **Stance** (timed self state: DR, no move, counter on melee hit with ICD) | Iron Guard | Generalise old `parry` behaviour. |
| E4 | **Arc area** (angle + radius) | Reaping Arc | Old `slam` is a circle; add `arc_deg`. Also used by tree "Full Circle". |
| E5 | **Skill counts as heavy** (Cleave + `heavy_hit` event) | Reaping Arc, Heavy Hook | Flag on the skill. |
| E6 | **Leap to densest point** | Crater Leap | Movement to the `densest` center (race vocab center). |
| E7 | **Pull** before damage | Hook Sweep (+ Faultline node) | Same as the tree's `pull` action. |
| E8 | **Self power window**: `haste` + poise + temporary `heavy_every` override | Battle Trance | `heavy_every` override is new (pilot reads it). |
| E9 | **Status bonus multiplier** vs a combat status (`sunder`) | Heartseeker | Old `strike` has this for `shock`; generalise to any status id. |
| E10 | **Skills apply combat statuses** (`stun`, `shock`, `slow`, `weaken`, `sunder`, `haste`) from effects.json | most skills | Old skills only apply skill-system statuses (burn/chill...). Needed bridge. |
| E11 | **Repeat shots with retarget** | Rapid Fire | Old `repeat` exists; add retarget on kill. |
| E12 | **Retreat move away from nearest enemy** + shot | Vault Shot | Blink-like movement with direction "away"; pilot uses it as the kite step. |
| E13 | **Delayed area with telegraph** | Starfall | Old engine schedules hits; add a telegraph visual event. |
| E14 | **Ally-targeted DR buff** | Warding Veil | Old `armor` is self-only. |
| E15 | **Skill `use` conditions** (3.7 list) | all | Pilot data, cheap and deterministic. |
| E16 | **Clip window + release per skill** | all | Client plays `clip` from `start` to `end`, sim release at `release`. |

## 7. Tuning Knobs

All per skill in the new skill data file (owner: combat-designer). Category: **feel** (timing), **curve** (numbers), **gate** (cooldowns).

| Knob | Default | Safe range | Category | Affects |
|---|---|---|---|---|
| `atk_pct` per skill | see 3.2-3.5 | ±40% | curve | skill damage share (4.5) |
| `cooldown` per skill | 3.5-18 s | ×0.6-×1.5 (floor 0.60 incl. race mods) | gate | cast rate, pilot rhythm |
| stun durations (Rush 0.8, Leap 0.4, Starfall 0.3 s) | — | 0.2-1.2 s | curve | control power, stun lock risk |
| Iron Guard DR / duration / max counters | 0.5 / 3 s / 4 | 0.3-0.7 / 2-5 s / 2-6 | curve | tank survival vs. lost action time |
| Intercept link fraction / duration | 0.40 / 6 s | 0.25-0.6 / 4-9 s | curve | how much the tank shields squishies |
| Hook Sweep pull distance | 2 m | 1-3.5 m | feel | how tight packs get for Cleave |
| Heartseeker marked bonus | ×1.5 | ×1.2-×2.0 | curve | focus-fire payoff |
| Rapid Fire arrows × % | 4 × 55% | 3-6 × 40-70% | curve | sustained single target |
| Vault distance / trigger range | 4 m / 3 m | 3-6 m / 2-4 m | feel | kiting success |
| Starfall telegraph | 0.8 s | 0.5-1.2 s | feel | readability vs. enemies walking out |
| Warding Veil DR / duration / threshold | 0.7 / 5 s / 60% HP | 0.6-0.85 / 3-7 s / 40-75% | curve | support value |
| Battle Trance duration / `heavy_every` | 6 s / 2 | 4-8 s / 2-3 | curve | bruiser burst window |
| Clip play speed per skill | 1.0 (Pin 0.8, Rapid 1.28, Guard counter 1.5) | 0.7-1.6 | feel | cast feel |

## 8. Acceptance Criteria

Functional:
1. `class_skills` lists exactly the 16 new ids (4 per class); no old id appears in any data file (`data/classes`, `data/races`, `data/skill_tree`, pilot `support_skill`). A data test fails on any old id.
2. Every new skill loads with: cooldown, stamina, impact tier, numbers, `use` rule, clip id that exists in its class clip file, `start < release < end ≤ clip length`. A wrong clip name or time fails the data test.
3. Scripted sim per skill: cast count > 0 in its positive scene, 0 in its negative scene (e.g. Repulse Nova with no enemy within 3 m does not cast; Intercept with all allies above 60% does not cast).
4. Numbers match section 4 within rounding: Reaping Arc on 3 enemies at ATK 100 = 182 each before DEF; Intercept example 4.2 = 28; pull example 4.3 = 2.5 m.
5. Events: Reaping Arc fires 1 `heavy_hit`; Rapid Fire fires 4 `skill_hit` and 0 basic `hit`; redirected damage counts as the S&S's damage taken.
6. Determinism: same seed = same replay; online prediction matches authority for the movement skills (Rush, Intercept, Leap, Vault).
7. Every skill-tree node that named an old skill now names its new skill (3.6), and `tests/run_all.gd` passes.

Experiential (playtest / class_sim):
- From one fight, a tester can describe each class's skills by job ("the tank jumped to save the archer", "the big sword pulled them together") without reading text.
- No element colour (fire orange, ice blue-white crystals, lightning yellow) appears on class skills; race colours appear only on ultimates and race effects.
- class_sim: squad win rate stays at 72-75% after one tuning pass; role metrics in races-and-classes.md 8 hold (tank ≥ 40% of damage taken, longbow highest boss damage, magic most hits per cast, greatsword most enemies per heavy); each class's skill share is inside 4.5.
- Bosses are never stunned more than ~25% of the time by class skills alone.

## 9. Open questions / defaults taken

| # | Question | Default taken (recommended) | Alternative |
|---|---|---|---|
| D1 | Class skill colour | Neutral class tones (S&S steel silver, GS stone/dust grey-brown, LB silver-white, magic white + deep blue `#3a5cff`), so they never read as a race | Tint class skills in the card's race colour |
| D2 | Old War Cry's team buff | Dropped; Battle Trance is self-only (team buffs are the Human passive theme) | Keep a small team ATK buff |
| D3 | Old Blood Shield's ally shield / Mending Shell regen nodes | Rewritten to Bodyguard / Long Watch (no shields or regen on the class axis) | Keep them as exceptions |
| D4 | Element tree nodes (Cold Iron, Banked Embers, Frostbite, Kindling, Conductor, Biting Frost, Elemental Convergence) | Rewritten to class-material effects (3.6); `mg_t4_a` becomes Arcane Convergence | Keep the element nodes as optional flavour |
| D5 | Rapid Fire counts as basic hits? | No (skill hits only) to avoid double-feeding Elf/Runeborn bow passives | Yes, as basic hits |
| D6 | Thorn Trap's kite-drop node | Vault Shot is the kite skill; `kite_drop_skill` no longer used | Keep a trap on the bow |
| D7 | Intercept and Iron Guard clips | `jump` + `block` (estimates, OPEN until a viewport check) | Ask for a new "shield leap" clip if `jump` reads badly |
| D8 | `gs_jump_attack` landing frame | 0.85 s estimate, verify | — |
| D9 | `design/gdd/systems-index.md` | Does not exist yet; not created here (the PO/producer owns `/map-systems`) | Create it |

No new animation clips are required for v1; D7 is the only likely clip ask.

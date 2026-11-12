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
7. **Clips.** Only clips that exist on studio05 (`art/characters/studio05/clips.json` for sword_shield, `classes/<class>_clips.json` for the others). A window `a–b @ s×` means: play the clip from `a` s to `b` s (clip time) at speed `s` (default 1×); a chain `X → Y` plays the windows back to back with a 0.12 s cross-fade unless stated. "Release" is the clip time when the effect happens; "skill t" is the same moment in seconds from the start of the cast (= the cast time, 60 ticks/s). Every window edge was chosen so the pose is within 15 cm (worst body joint) of the class idle or of the next window's first pose, so nothing pops (animator check 2026-11-13, `tools/shots/skill_window_pops.py`; one documented exception, Rapid Fire 15.4 cm). The machine-readable copy of every window is `tools/shots/skill_windows_v2.json`; previews in `build/skill_motion_preview_v2/`.
8. **Skill ids** are new; no old id is reused (so old saves and old `.tres` files cannot be confused with the new set).
9. **Root motion (Boss 2026-11-13: the sim follows the clip's travel frames).** The client keeps the hips in place, so any skill that moves the caster must move the body in the sim **only during the clip's travel frames**, listed per skill as "Travel". Outside those frames the body stays still; otherwise the planted feet visibly slide. Travel is given in clip time and in skill time (seconds from cast start). Skills without a Travel line do not move the caster.

### 3.2 sword_shield — Tank / Guard (pilot target: `peel`)

| # | id | Name | Player text | Job |
|---|---|---|---|---|
| S1 | `shield_rush` | Shield Rush | "Crash shield-first into the enemy threatening your allies and stun it." | Peel / main damage |
| S2 | `iron_guard` | Iron Guard | "Brace behind the shield: take half damage and strike back at every attacker." | Self defence + counter damage |
| S3 | `intercept` | Intercept | "Leap to a hurt ally and take a share of every blow meant for them." | Ally protection |
| S4 | `breaker_slam` | Breaker Slam | "Slam the shield into the ground; nearby enemies hit weaker." | AoE control |

**S1 Shield Rush** — cooldown 16 s (tuned 2026-11-13, 4.6). Target: the enemy nearest the most-hurt ally (the `peel` target) within 7 m; if none, the current target. The caster dashes in a straight line to 1 m from it (max 6 m, stops on the first enemy in the path) and hits it for **110% ATK** + `stun` 0.8 s (48 ticks; control immunity applies). Invulnerable during the dash travel (not the wind-up or recovery).
- AI rule: cast when the peel target is attacking an ally other than self and is 2-7 m away; otherwise cast on the current target when it is ready and within 3 m (do not waste it at range).
- Motion: `attack_4` 0.30–0.62 @ 0.8× (crouch behind the shield and drive in) → `attack_4` 0.62–1.98 @ 1.5× (sword follow-through and recover). Release at clip 0.62 = **skill t 0.40 s** (shield punch, left hand fully out). Total 1.31 s. (`attack_3`, the old choice, starts mid-lunge and ends in a deep lunge: 46-54 cm pops; it has no idle-clean edge before 4.15 s.)
- Travel: clip 0.30–0.62 = skill t 0.00–0.40 (the dash). The 0.4 s VFX travel matches.
- VFX: steel-white streak along the dash path; on impact a flat silver shield-shaped shockwave (cone forward, 1 m) and stun stars on the target. Cast 0 s / travel 0.4 s / impact 0.1 s (impact at skill t 0.40).
- SFX: heavy footsteps into a metal shield "clang-thud" with a short dull ring.

**S2 Iron Guard** — cooldown 18 s (tuned 2026-11-13, 4.6). Self stance for **3 s**: damage taken ×0.5 from all sides, the card cannot move or attack, and cannot be staggered. Each melee hit it takes during the stance triggers a counter on that attacker for **200% ATK** (max 2 counters per stance, PO default; at most one counter per 0.3 s). Ranged hits are reduced but not countered.
- AI rule: cast when 2+ enemies within 3 m are attacking this card, or a boss telegraphed move targets a point within 4 m (`boss_telegraph`), or own HP below 50% with 1+ enemy within 3 m. Never cast with no enemy within 3 m.
- Motion: enter `block` 0.0–1.45 @ 1.6× (0.91 s, raise shield) → `block_idle` loop for the rest of the stance → each counter: `block_2` 0.0–0.60 @ 4× (0.15 s, bridge) → `attack_4` 0.0–2.20 @ 2.5× (0.88 s; shield-punch release at clip 0.62 = **0.40 s after the counter starts**) → `block` 0.0–1.45 @ 4× (0.36 s, back behind the shield) → `block_idle`. One counter takes 1.39 s, so only about 2 counter animations fit in the 3 s stance. OPEN for combat-designer: either cap counters at 2, or let counters 3-4 deal damage on a shorter visual (shield punch only, `attack_4` 0.0–0.85 @ 2.5× then `block` @ 4×, 0.70 s; not pop-checked yet). Exit with `block_2` 0.0–1.70 @ 1.4× (1.21 s). (A direct `block_idle` ↔ `attack_4` join popped 16-17 cm; the bridges keep every join at or under 9.4 cm.)
- VFX: a pale steel half-dome in front of the card while the stance lasts; each blocked hit flashes a spark on the shield rim; each counter a short silver arc.
- SFX: shield raise "thunk"; each block a bright metal "ting"; counter a short swing whoosh.

**S3 Intercept** — cooldown 14 s. Target: the most-hurt ally within 8 m whose HP is below 60% and who is being attacked. The caster leaps to 1 m from that ally (max 8 m, 0.5 s travel, invulnerable in the air). On landing: `pulse_aggro` r3 m for 2 s, and a **link** for 6 s: 40% of all damage that ally takes (before the ally's own DEF) is taken by the caster instead (the caster's DEF and damage-taken modifiers apply to its share). The link breaks early if the two are more than 10 m apart or the caster goes down.
- AI rule: cast when the target condition above holds and the caster's own HP is at least 40%. Skip if the hurt ally is already linked.
- Motion: `jump_2` (standing shield jump, shield held in front throughout; Boss 2026-11-13) 0.33–0.50 @ 1× (crouch, 0.17 s) → 0.50–1.97 @ 2.94× (air, 0.50 s) → 1.97–2.45 @ 1.2× (land and settle, 0.40 s) → `block` 0.0–0.45 (0.45 s). Landing (release: `pulse_aggro` + link start) at clip 1.97 = **skill t 0.67 s**. Total 1.52 s. (Base `jump` was a running jump: legs cycling, 36-43 cm pops, landing at 1.87 not 1.10.)
- Travel: clip 0.50–1.97 = skill t 0.17–0.67 (the 0.5 s leap).
- VFX: a silver arc trail through the air; on landing a ring of dust r3 m; a thin silver tether line from the caster to the linked ally for 6 s that pulses when damage is redirected.
- SFX: grunt + armour rattle on take-off, heavy landing thump, a soft metallic "hum" on each redirected hit.

**S4 Breaker Slam** — cooldown 16 s (tuned 2026-11-13, 4.6). Self-centred circle r3 m: **130% ATK** to every enemy inside + `weaken` 4 s (ATK −30%).
- AI rule: 2+ enemies within 3 m, or the boss within 3 m.
- Motion: `slash_4` 0.43–5.38 @ 2.5× (1.98 s: guard, jump, shield slam into the ground, rise). Release (the ground hit) at clip 3.58 = **skill t 1.26 s**. (The old window 3.00–4.22 started in mid-air and ended crouched: 61/84 cm pops. The `windup_end` 3.40 mark is the feet landing; the ground hit is 3.58.)
- Travel: clip 3.00–3.35 = skill t 1.03–1.17 (a short forward hop, about 30 cm).
- VFX: shield rim hits the ground: a grey stone crack ring r3 m with a dust burst; weakened enemies get a dull grey downward-arrow icon.
- SFX: deep ground "boom" with a short gravel scatter.

### 3.3 greatsword — Bruiser / Cleave (pilot target: `densest`)

| # | id | Name | Player text | Job |
|---|---|---|---|---|
| G1 | `reaping_arc` | Reaping Arc | "A huge forward sweep. Counts as a heavy hit, so Cleave grows with every enemy." | Main damage |
| G2 | `crater_leap` | Crater Leap | "Leap into the thickest pack and crash down, staggering everything around you." | Gap closer + AoE |
| G3 | `hook_sweep` | Hook Sweep | "Drag nearby enemies into a tight knot, then cut through them." | Grouping / control |
| G4 | `battle_trance` | Battle Trance | "Swing faster, refuse to flinch, and land heavies every other swing." | Self power window |

**G1 Reaping Arc** — cooldown 14 s (tuned 2026-11-13, 4.6). Frontal arc 240°, radius 3 m: **550% ATK** to every enemy inside. It **counts as a heavy hit** for the Cleave signature (+15% per extra enemy hit, max +45%) and for every `heavy_hit` event (Runic Edge, Momentum...).
- AI rule: 2+ enemies inside the arc, or the boss in the arc. Otherwise hold up to 3 s, then cast on whatever is in front.
- Motion: `gs_slash_3` 0.167–1.533 @ 1× (1.37 s). Release (the blade sweeps through the front arc) at clip 0.82 = **skill t 0.65 s**; the old 0.633 is still the overhead wind-up.
- Travel: clip 0.27–0.75 = skill t 0.10–0.58 (a step of about 22 cm into the swing; the clip steps back afterwards, so net travel is about 0).
- VFX: a wide pale steel crescent (240°) on the ground plane, slight motion blur; small dust kicks where it touches enemies. Cast 0.65 s / impact 0.2 s.
- SFX: long low "whoom" of a heavy blade, layered flesh/armour hits per enemy.

**G2 Crater Leap** — cooldown 26 s (tuned 2026-11-13, 4.6). Target point: the `densest` point within 7 m (most enemies within 2.5 m). The caster leaps there (0.5 s air time, cannot be hit in the air) and lands: circle r2.5 m, **350% ATK** + `stun` 0.4 s (24 ticks, a stagger).
- AI rule: the densest point has 3+ enemies; or it has 2+ enemies and is more than 3 m away (gap closer); or the boss is 3-7 m away.
- Motion: `gs_jump_attack` 0.067–0.63 @ 1× (wind-up, 0.56 s) → 0.63–1.00 @ 0.74× (air, 0.50 s) → 1.00–1.25 @ 1× (land and slam) → 1.25–2.00 @ 1.5× (recover). The front foot lands at clip 1.00; the blade hits the ground at clip **1.22 = skill t 1.28 s** (release). Total 1.81 s. Clip marks fixed to `windup_end` 1.00 / `strike_end` 1.25 (were auto-generated 0.05/0.153).
- Travel: clip 0.63–1.00 = skill t 0.56–1.06 (the 0.5 s leap; take-off is the rear foot leaving the ground at 0.63).
- VFX: on landing, a stone crater decal r2.5 m with cracks and flying rocks; brown-grey dust ring outward. Cast 0.56 s / travel 0.5 s / impact 0.3 s (impact at skill t 1.28).
- SFX: rising whoosh, then a ground-shaking crash with debris.

**G3 Hook Sweep** — cooldown 22 s (tuned 2026-11-13, 4.6). First a `pull`: every enemy within 5 m is pulled 2 m toward the caster (never past 1 m from it; bosses and elites are not pulled). Then a circle r2.5 m: **300% ATK** + `slow` 2 s.
- AI rule: 3+ enemies within 5 m but fewer than 2 within 2.5 m (the pack is loose); never if all enemies in 5 m are bosses/elites.
- Motion: `gs_slash_4` 0.117–1.433 @ 1× (1.32 s). Pull over clip 0.20–0.45 (the back-swing, skill t 0.08–0.33); release (the sweep) at clip 0.74 = **skill t 0.62 s**. The old release 0.167–0.387 was the back-swing.
- Travel: clip 0.27–0.80 = skill t 0.15–0.68 (a step of about 24 cm into the sweep).
- VFX: a low swirl of dust drawn inward toward the caster (reads as "pulled in"), then a flat steel ring cut r2.5 m.
- SFX: rushing air inhale, then a short heavy swipe.

**G4 Battle Trance** — cooldown 24 s (tuned 2026-11-13, 4.6). Self only, 6 s: `haste` (ATKSPD +25, MOVESPD +25), cannot be staggered (poise unbreakable on its normal attacks), and `heavy_every` becomes 2 (every 2nd swing is a heavy) for the duration. No healing, no team effect (old War Cry's team buff is gone: team buffs are a Human-passive theme).
- AI rule: 2+ enemies within 3 m, or the boss within 3 m. Do not cast with no enemy within 3 m.
- Motion: `gs_power_up` 1.30–3.00 @ 1.4× (1.21 s: the head-back roar). Release (buff starts) at the roar peak, clip 2.05 = **skill t 0.54 s**. The old window 0.017–1.237 was only a slow sword raise, nearly invisible from the board camera.
- VFX: on release a heat-haze shimmer burst around the body (colourless distortion + white sparks), then a faint pale aura on the blade for 6 s.
- SFX: deep battle shout and a heartbeat-like low pulse.

### 3.4 longbow — Ranged single-target / Marks (pilot target: `lowest_hp`, boss first)

| # | id | Name | Player text | Job |
|---|---|---|---|---|
| L1 | `heartseeker_shot` | Heartseeker | "A fully drawn arrow that deals bonus damage to marked targets." | Main single-target damage |
| L2 | `pinning_shot` | Pinning Shot | "Nail an enemy to the ground before it reaches your friends." | Control / peel |
| L3 | `rapid_fire` | Rapid Fire | "Loose four quick arrows into one target." | Sustained single-target |
| L4 | `vault_shot` | Vault Shot | "Flip away from an attacker and shoot it as you land." | Escape / kite |

**L1 Heartseeker** — cooldown 16 s (tuned 2026-11-13, 4.6). Range 12 m, one arrow at the pilot's target: **950% ATK**, crit rate +25 for this hit, and ×1.5 if the target has `sunder` (Hunter's Mark).
- AI rule: target the boss if alive and in range, else an elite in range, else the pilot target. Cast when ready; prefer a marked target.
- Motion: `lb_draw_arrow` 0.0–1.017 @ 1.2× (draw) → `lb_aim_recoil` 0.0–0.70 @ 1.2×. Release (string let go) at `lb_aim_recoil` 0.18 = **skill t 1.00 s**. Total 1.43 s (bow segments +20%, 4.6; was 1×, release 1.20, total 1.72). (`lb_aim_recoil` 0.10 is still at full draw; the loose is 0.18. Clip marks fixed to `windup_end` 0.18 / `strike_end` 0.25.)
- VFX: a thin white light gathers on the arrow tip during the draw; the arrow leaves a straight silver streak; impact is a sharp white star burst (bigger on crit).
- SFX: long creaking bow draw, sharp "thwip", hard impact crack.

**L2 Pinning Shot** — cooldown 20 s (tuned 2026-11-13, 4.6). Range 12 m. Target: the enemy nearest a back-line ally (or nearest to self if no back-line ally is threatened). **275% ATK** + `shock` 1.5 s (cannot move; it may still attack in reach).
- AI rule: an enemy within 3 m of a back-line ally (magic/longbow) or of self; else the fastest-closing enemy within 8 m. Never on a target already shocked.
- Motion: `lb_draw_arrow` 0.0–1.017 @ 1.8× (0.57 s) → `lb_aim_recoil` 0.0–0.70 @ 0.96× (0.73 s, deliberate). Release at `lb_aim_recoil` 0.18 = **skill t 0.75 s**. Total 1.29 s (+20%, 4.6; was 1.5×/0.8×, release 0.90, total 1.55). (Starting straight in `lb_aim_recoil` snapped the bow up from idle: a 36 cm pop.)
- VFX: a heavy arrow with a short silver trail; on hit the arrow sticks in the ground at the target's feet with a small circle of pale cracks for 1.5 s.
- SFX: heavier "thunk" of an arrow into earth, a short rope-tight twang.

**L3 Rapid Fire** — cooldown 19 s (tuned 2026-11-13, 4.6). 4 arrows at the current target, 0.21 s apart, **155% ATK each** (620% total). If the target dies, the remaining arrows go to the next pilot target within 12 m. Each arrow is a skill hit (not a basic hit, see 5.2).
- AI rule: cast when ready on the pilot target within 12 m.
- Motion: `lb_draw_arrow` 0.0–1.017 @ 2.4× (0.42 s) → `lb_aim_recoil` 0.0–0.18 @ 1.2× (arrow 1) → three re-nocks, each `lb_aim_recoil` 0.18–0.233 then 0.15–0.18 @ 0.398× with a 0.05 s cross-fade at the 0.233 → 0.15 seam (0.21 s per arrow) → `lb_aim_recoil` 0.18–0.70 @ 1.2× (recover). Releases at **skill t 0.57 / 0.78 / 0.99 / 1.20 s** (0.21 s apart). Total 1.63 s (all segments +20%, 4.6; was 2×/1×/0.332×, releases 0.69/0.94/1.19/1.44, total 1.96). The re-nock seam is 15.4 cm, the only edge in the 16 skills over the 15 cm target (the clip has no closer loop); it reads as a small bow jerk per arrow. A dedicated "rapid nock" clip would remove it (not requested for v1).
- VFX: four short silver tracers; small spark per hit.
- SFX: four fast "thwip" sounds with slight pitch variation.

**L4 Vault Shot** — cooldown 20 s (tuned 2026-11-13, 4.6). The caster flips 4 m directly away from the nearest enemy (0.4 s, invulnerable during the flip), then shoots that enemy: **225% ATK** + `slow` 3 s. If the landing spot is blocked, it moves as far as it can (min 1 m).
- AI rule: an enemy within 3 m. This is the kite rule (pilot `kite_distance`); when Vault Shot is ready the pilot uses it instead of the plain dodge.
- Motion: `lb_dodge_backward` 0.0–0.95 @ 1.8× (0.53 s) → `lb_draw_arrow` 0.0–1.017 @ 2.4× (0.42 s) → `lb_aim_recoil` 0.0–0.70 @ 1.2×. Release at `lb_aim_recoil` 0.18 = **skill t 1.10 s**. Total 1.53 s (+20%, 4.6; was 1.5×/2×/1×, release 1.32, total 1.84). The clip is a backward step-hop, not a flip; a backflip-shot clip would match the name better (not requested for v1).
- Travel: clip 0.25–0.85 of `lb_dodge_backward` = skill t 0.14–0.47 (the 0.33 s move; was 0.17–0.57 before the +20% speed).
- VFX: a pale dust puff at the take-off spot, a silver arrow streak on the shot, slowed enemy gets a grey trailing smear.
- SFX: cloth whoosh and boot scuff, then a "thwip".

### 3.5 magic — AoE / control / support caster (pilot hold rule: 2+ targets)

| # | id | Name | Player text | Job |
|---|---|---|---|---|
| M1 | `arcane_orb` | Arcane Orb | "A slow orb of raw force that bursts on impact." | Main AoE damage |
| M2 | `repulse_nova` | Repulse Nova | "Blast everything near you away." | Self-defence / control |
| M3 | `starfall` | Starfall | "Call a falling star onto the thickest pack." | Big AoE burst |
| M4 | `warding_veil` | Warding Veil | "Wrap a threatened ally in a veil that dulls blows and quickens them." | Ally support (no heal/shield) |

**M1 Arcane Orb** — cooldown 7 s (tuned 2026-11-13, 4.6). Projectile, speed 12 m/s, range 12 m, aimed at the target; it bursts on the first enemy hit or at max range: circle r2 m, **2100% ATK**.
- AI rule (class hold rule): 2+ enemies within 2 m of the target, or the target is the boss; else hold, max 4 s, then cast anyway.
- Motion: `mg_spell_1h_cast_spell_01` 0.167–1.55 @ 1× (1.38 s). Release (the throw) at clip 0.58 = **skill t 0.41 s**.
- VFX: a white-core orb with a deep blue rim (`#3a5cff`, the class tone), slight trail; a round white-blue shockwave burst r2 m. Cast 0.41 s / travel ~0.6 s / impact 0.25 s.
- SFX: rising hum during the cast, low "whum" pop on burst.

**M2 Repulse Nova** — cooldown 14 s (tuned 2026-11-13, 4.6). Self-centred circle r3 m: **650% ATK**, knockback 2.5 m away from the caster, `slow` 2 s. Bosses and elites take damage and slow but no knockback.
- AI rule: 1+ enemy within 2.5 m of the caster (self-defence; the hold rule does not apply), or 2+ enemies within 3 m.
- Motion: `mg_spell_2h_magic_area_attack_01` 0.10–2.683 @ 1.5× (1.72 s). Release (the staff slams the ground) at clip 1.32 = **skill t 0.81 s**. (The old window started with the staff already raised: a 55 cm pop.)
- VFX: a flat expanding ring of blue-white force r3 m at waist height, ground ripple.
- SFX: sharp air "fwoomp" with a deep sub-bass push.

**M3 Starfall** — cooldown 12 s (tuned 2026-11-13, 4.6). Target point: the densest point within 9 m (most enemies within 2.5 m). A 0.8 s telegraph circle appears, then impact: circle r2.5 m, **1450% ATK** + `stun` 0.3 s (18 ticks, a stagger). One impact only (not a lasting zone).
- AI rule: 3+ enemies inside r2.5 of a point within 9 m; or 2+ and one of them is an elite; or the boss within 9 m.
- Motion (swapped with M4, animator 2026-11-13): `mg_spell_2h_cast_spell_01` 0.167–1.967 @ 1× (1.80 s: bow, then raise the staff to the sky). Release (the telegraph starts) at the hand flick, clip 1.25 = **skill t 1.08 s**; impact lands 0.8 s later while the caster is in recovery.
- VFX: a thin blue-white telegraph ring on the ground for 0.8 s, then a white streak falling from above and a bright blue-white crater flash r2.5 m with sparks.
- SFX: a rising whistle during the telegraph, then a heavy crystalline boom.

**M4 Warding Veil** — cooldown 14 s. Target: the most-hurt ally within 9 m whose HP is below 60% (self allowed). For 5 s: damage taken ×0.7, plus `haste` for 3 s (so a melee ally fights back faster or a ranged ally can step away). This is damage reduction, not a shield and not a heal (race themes stay clean).
- AI rule: support rule (`support_skill: warding_veil`, `support_below: 0.6`); if two allies qualify, pick the one with more enemies attacking it.
- Motion (swapped with M3): `mg_spell_2h_magic_attack_05` 0.267–3.067 @ 1.6× (1.75 s: gather, then point the staff at the ally). Release (the beam to the ally) at the staff thrust, clip 2.03 = **skill t 1.10 s**.
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
Example: ATK 100, Reaping Arc hits 3 enemies: 550 × 1.30 = **715** each before DEF (2145 total). (Was 140% → 182 before the 4.6 tuning.)

**4.2 Intercept link.** For a hit of raw damage D on the linked ally: ally takes `0.6 × D` through its own DEF; caster takes `0.4 × D` through the caster's DEF and modifiers (Iron Guard ×0.5 applies). Example: D = 200, tank DEF rule reduces 30%, tank in Iron Guard: tank takes 0.4 × 200 × 0.7 × 0.5 = **28**; ally takes 0.6 × 200 × its rule.

**4.3 Pull.** Final distance to caster = `max(1.0, d − pull)`. Example: enemy at 4.5 m, pull 2 → 2.5 m (inside the 2.5 m cut).

**4.4 Skill DPS (single target, % ATK per second, all hits land)** — `rate = total_atk_pct / cooldown`. Tuned numbers (4.6). Skill % look large because a basic weapon hit is ATK × move power (0.8-3.0) on a fast loop; a skill must beat the basic attacks it replaces during its clip (4.6).

| Class | Skill | Total % | CD s | %/s single | Typical targets (class_sim) | %/s at typical |
|---|---|---|---|---|---|---|
| S&S | Shield Rush | 110 | 16 | 6.9 | 0.7 | 4.8 |
| | Iron Guard (2 counters max, ~1 typical) | 400 | 18 | 22 | ~1 | ~11 |
| | Intercept | 0 | 14 | 0 | — | utility |
| | Breaker Slam | 130 | 16 | 8.1 | 1.4 | 11 |
| | **total** | | | **37** | | **~27** |
| GS | Reaping Arc (+Cleave) | 550 | 14 | 39 | 1.25 | 49+ |
| | Crater Leap | 350 | 26 | 13 | 2.5 | 34 |
| | Hook Sweep | 300 | 22 | 14 | 2.3 | 31 |
| | Battle Trance | 0 | 24 | buff ~+25% basic DPS for 6 s | — | — |
| | **total** | | | **66** | | **~114** |
| LB | Heartseeker (marked ×1.5) | 950 (1425) | 16 | 59 (89) | 0.75 | 45-67 |
| | Pinning Shot | 275 | 20 | 14 | 0.9 | 12 |
| | Rapid Fire | 620 | 19 | 33 | 1 (4 arrows) | 33 |
| | Vault Shot | 225 | 20 | 11 | 0.9 | 10 |
| | **total** | | | **117** | | **~100-120** |
| Magic | Arcane Orb | 2100 | 7 | 300 | 1.0 | 300 |
| | Repulse Nova | 650 | 14 | 46 | 1.7 | 79 |
| | Starfall | 1450 | 12 | 121 | 1.55 | 187 |
| | Warding Veil | 0 | 14 | utility (−30% dmg on 1 ally 5 s) | — | — |
| | **total** | | | **467** | | **~566** |

**Old set for comparison** (rough, old `.tres` damage ÷ `reference_atk` 20 ÷ cooldown, single target): S&S ≈ 12 (storm 60%/5 s) + 7 (flame dash) + 15 (riposte, only on a parry) ≈ **34 %/s**; GS ≈ 12.5 (slam) + 22 (shatter 110%/5 s) + 13 (eruption) ≈ **48 %/s**; LB ≈ 33 (piercing) + 12 (trap) + 28 (lance) + 20 (chain first target) ≈ **93 %/s**; magic ≈ 27 (fireball) + 25 (ring) + 21 (strike) ≈ **73 %/s**. These are estimates for direction only; class_sim gives the real baseline. The first-pass new totals were within about ±30% of these; class_sim then showed that scale was far too low (each skill clip blocks more basic-attack damage than it dealt), so the 4.6 tuning replaced them.

**4.5 Balance intent (skill share of each class's total output, combat-designer to verify with class_sim):**

| Class | Skill share of damage | Split inside the kit |
|---|---|---|
| sword_shield | 20-25% (lower than old: the dash-trail fire damage is gone; offset by Intercept/Iron Guard survival value) | Slam 45%, Rush 25%, Guard 30%; Intercept 0% damage, target: tank takes ≥ 40% of squad damage (race doc 8) |
| greatsword | 35-40% | Arc 55%, Leap 25%, Hook 15%, Trance (raises basic/heavy) |
| longbow | 35-40%, highest **single-target/boss** share of the squad | Heartseeker 50%, Rapid 30%, Pin 12%, Vault 8% |
| magic | 55-65% (Spellweave: most damage from skills) | Orb 45%, Starfall 40%, Nova 15%; Veil = utility |

Rule: no single skill above 60% of its class's skill damage. (The old "±15% of the old set" rule is retired: the old %/s figures were ÷ an old `reference_atk` and do not compare with the class_sim ATK; class_sim is the baseline now.)

**4.6 Tuning pass 1 (combat-designer, 2026-11-13, class_sim 30 seeds, same difficulty, `wave_power_by_squad` not touched).**
Problem: with the first-pass numbers the starter squad did worse with skills than without (90% vs 100% win, 267 s vs 179 s clear, 11.2k vs 7.3k damage taken). Every skill clip blocks basic attacks, and basic attacks are fast (a light hit loops in ~0.3 s at ATK × 0.8-1.2); the bow spent 71% of its alive time in skill clips. Fix (Boss: tune numbers + play bow clips faster within ±20%; clip choices and windows unchanged): fewer casts (cooldowns ×1.2-×2.7) that each hit much harder, and every longbow skill segment played +20% faster (total clip time −17%).

| Measure (class_sim, 30 seeds) | no skills | first pass | tuned |
|---|---|---|---|
| starter squad win / clear s / dmg taken | 100% / 176 / 7.1k | 90% / 267 / 11.2k (10 seeds) | 100% / 154 / 6.2k |
| magic squad (S&S + LB + magic) win / clear s / dmg taken | 100% / 123 / 4.0k | 100% / 209 / 8.2k (10 seeds) | 100% / 110 / 3.8k |
| skill share S&S / GS / LB / magic | — | 32% / 30% / 53% / 21% | 26% (21% in magic squad) / 39% / 37% / 59% |
| largest single skill share of its class's skill damage | — | 60.0% (Breaker Slam, magic squad) | 52.5% Slam, 50.8% Arc, 51.6% Heartseeker, 49.9% Orb |
| time in skill clips S&S / GS / LB / magic | — | 36% / 35% / 71% / 41% | 24% / 24% / 33% / 33% |

Targets locked by this pass: skills must be a power gain over no skills at the same difficulty (faster clear and less damage taken); skill share per class inside the first table of 4.5; no skill above 60% of its class's skill damage. The 72-75% squad win rate (section 8) is reached later by the difficulty pass (`wave_power_by_squad`), not by weakening skills.


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
- Timings verified in viewport captures (animator 2026-11-13, `build/skill_motion_preview/timing/`): `gs_jump_attack` front foot lands at 1.00 and the blade hits the ground at 1.22 (marks now 1.00/1.25); `jump_2` lands at 1.97; `lb_aim_recoil` looses at 0.18 (marks now 0.18/0.25); `lb_aim_overdraw` never looses (a 3.8 s held aim), so the longbow heavy/charge/ultimate moves in `data/classes/longbow.json` now use `lb_aim_recoil`. CLOSED.
- Window edges sit at poses near the class idle, so the 0.12 s blend in/out to the class idle never pops more than 15 cm (exception: the Rapid Fire seam, 15.4 cm, see L3).
- Root motion: the sim moves the body only inside each skill's Travel frames (3.1 rule 9).
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
| `atk_pct` per skill | see 3.2-3.5 (tuned 4.6) | ±40% | curve | skill damage share (4.5) |
| `cooldown` per skill | 7-26 s (tuned 4.6) | ×0.6-×1.5 (floor 0.60 incl. race mods) | gate | cast rate, pilot rhythm, time lost to clips (skills block basic attacks) |
| stun durations (Rush 0.8, Leap 0.4, Starfall 0.3 s) | — | 0.2-1.2 s | curve | control power, stun lock risk |
| Iron Guard DR / duration / max counters / counter % | 0.5 / 3 s / 2 / 200% | 0.3-0.7 / 2-5 s / 2-6 / ±40% | curve | tank survival vs. lost action time |
| Intercept link fraction / duration | 0.40 / 6 s | 0.25-0.6 / 4-9 s | curve | how much the tank shields squishies |
| Hook Sweep pull distance | 2 m | 1-3.5 m | feel | how tight packs get for Cleave |
| Heartseeker marked bonus | ×1.5 | ×1.2-×2.0 | curve | focus-fire payoff |
| Rapid Fire arrows × % | 4 × 155% | 3-6 × ±40% | curve | sustained single target |
| Vault distance / trigger range | 4 m / 3 m | 3-6 m / 2-4 m | feel | kiting success |
| Starfall telegraph | 0.8 s | 0.5-1.2 s | feel | readability vs. enemies walking out |
| Warding Veil DR / duration / threshold | 0.7 / 5 s / 60% HP | 0.6-0.85 / 3-7 s / 40-75% | curve | support value |
| Battle Trance duration / `heavy_every` | 6 s / 2 | 4-8 s / 2-3 | curve | bruiser burst window |
| Clip play speed per skill | per segment in 3.2-3.5 (0.74-4.0; 2.5-4.0 only on short bridge/recover segments); longbow segments already at +20% (4.6), so they have no faster headroom left | ±20% of the first-pass value | feel | cast feel; changing a speed moves the skill t of release and travel, so recompute them (and `tools/shots/skill_windows_v2.json`) |

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
| D7 | Intercept and Iron Guard clips | CLOSED (Boss 2026-11-13): existing clips only; Intercept uses `jump_2`, Iron Guard uses `block`/`block_idle`/`attack_4` with bridges | New "shield bash charge", "rapid nock", "vault backflip shot" clips (not requested) |
| D8 | `gs_jump_attack` landing frame | CLOSED: lands at 1.00, release (ground hit) at 1.22 | — |
| D10 | Root motion | CLOSED (Boss 2026-11-13): the sim moves the body only in each skill's Travel frames (3.1 rule 9) | Client applies clip root motion; accept foot slide |
| D9 | `design/gdd/systems-index.md` | Does not exist yet; not created here (the PO/producer owns `/map-systems`) | Create it |

No new animation clips are required for v1.

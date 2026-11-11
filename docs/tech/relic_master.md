# Relic Master / slots — deployed, 2026-10-30

Boss requested an NPC using relic_master.fbx, three relic slots with only the first unlocked, and selection from owned boss drops.

## Implemented locally

- Original NPC converted under assets_spec; camp interaction opens Relic panel.
- Profile `relics` v1: owned instance records `{id,relic}` and exactly three equipped instance IDs. Old profiles default empty.
- `relic_equip` passes through normal authoritative profile command runner, camp only. Slot0 only; unowned IDs and slots1/2 rejected. Empty ID unequips.
- Profile serialization/cache include relic state. Public room profiles expose equipped relic instances only.
- UI lists owned instances, supports equip/unequip, and shows disabled future slots. No speculative ownership changes.

## Goblin content decision — 2026-10-30

Boss selected only `gobbin_relic.fbx`; Set1/Set2 remain inactive. The supplied asset has two complete pieces: goblin_medallion and goblin_lantern. `data/relics/catalog.json` defines only these two. Baseline drop tuning: Goblin Chief (`goblin_chief`) grants one uniformly random piece at100% chance; other enemy types grant none. This is the only chief boss type in the current Goblin journey. Each eligible co-op player receives a separate server roll. No client grant command exists.

Relics travel in Run.relic_loot, survive checkpoint/serialization, and become owned when returning to camp (or death securing existing carried loot rules). Abandon discards them. Duplicate monster-death events cannot pay twice, including solo. Public/private run serialization includes pending relics. Camp equips only owned instances into slot0; slots1/2 remain locked. No relic stat bonuses invented.

Icons use actual two source models, native-rendered transparent128px. Only icons are introduced into runtime; the full-detail source models(50,000tri total) remain outside export. No floating relic model behaviour introduced in this UI/drop scope. Source FBX and Set1/Set2 untouched.

No Relic build/deployment yet; live remains shared-invite3b78467c3d65. Profile worker, Room worker and Web must ship together for the additive schema. Browser gameplay acceptance remains OPEN.

## Evidence

`tests/relic_slots.gd` PASS: migration, strict schema, own/equip/unequip/replace, locked/unowned/out-of-range/stage rejection, serialization and snapshot cache invalidation.

`tools/shots/relic_master_review.gd` native rendered PASS: actual NPC, PC1280x720/mobile844x390 panel bounds, 3slots/1unlocked, equip/unequip through LocalSession using disposable fixture. Fixture is NOT boss-drop/live account evidence. Images in build/relic-*.png.

Full tests attempted with45s timeout; did not pass/complete, existing profile/login and cleanup fixtures report errors. Log `/tmp/relic-master-full-suite.log`. Actual browser gameplay unverified; Work browser controls disabled. Live remains shared-invite release3b78467c3d65.

Goblin follow-up: tests/relic_boss_drops.gd PASS100 seed-stream boss rolls, all other known enemy types excluded, unique IDs, repeat grant protection, ownership securing/death/abandon, equipped ownership, actual co-op GameSim kill fanout and checkpoint restore. Updated actual-icon PC/mobile rendered review PASS. Fullsuite rerun log /tmp/relic-goblin-full-suite.log; independent repository fixture errors remain, not an all-green release gate.

## Goblin effects and orbit — local implementation, 2026-10-30

Boss approved two effects. Catalog remains the authoritative config: medallion earns one charge per landed basic/heavy hit at most once30ticks, five charges empower the NEXT basic hit1.25x (not the fifth), then reset. Blocked/filtered hits, skills, DOT never charge/consume it. Lantern arms only after successful server skill cast,240tick window,480tick cooldown beginning on that cast; next landed basic/heavy adds one180tick poison with total30%sourceATK. Poison replaces/refreshes one instance; exact fractional DOT avoids exceeding30%at lowATK. Poison kill goes through existing Effects killed event/economy. No new grant command, unchanged chief drop configuration. Timers/charge are transient per combat scene, reset on new scene/trainingreset/death(charge/armedwindow), retained by full simulation checkpoint. Effects and cooldowns are authority-only; prediction does not run them. Added Fighter.relic_state to automatic checkpoint and appended to wire fighter fields: coordinated server/client release required.

Current one-active-slot policy retained. Client orbit loads only known equipped IDs, supports maximum3visual instances for future slots,15cm height,.64m radius,world-up and camera-facing yaw; no network orbital positions, particles, lights, shadow casting or collision. Actual model handles own hub/training/combat; remote combat reads authoritative fighter state; plaza projects only equipped IDs from stored profile at membership and sends them with appearance once per second. Does not send private ownership list. Training mirrors read-only ownedloadout and resets effects, never saves/rewards. Description displayed in RelicMaster, can scroll on mobile.

### Geometry trials (not yet art accepted)

Original models19178/30822tri. First preserved-seam pass1710/2984tri was too high per Boss.600trial592/598tri was visually rejected: loss of detail and UV appearance. Boss requested1000trial; current candidates998tri each (1996total),57976/59508bytes rawGLB,shared colour512/normal256/MR256 PNG620591bytes. All high-detail originals and previous trials retained outside export. Current1000shape improves but lantern texture still visibly distorts after seam collapses; NOT final visual acceptance, requires UV rebake/retopology before claiming source parity. Native comparison build/relic-1000-comparison.png. No600or1000deployment. No webdownload/FPS claim. Packlayout includes art/relics in items, GPUformats remain separate.

### Verification

- tests/relic_effects.gd PASS actualCombat hits,5+1/.5s,blocked/skill exclusions,successful/failedcast,30%poison including lowATK,4s/8stimers,noDOTrecursion,singlepoisonkill,charge/poisonJSONrestore,wire roundtrip,unknown/unworn excluded,forgedproccommand rejected.
- relic_slots, relic_boss_drops, training_ground, training_floor PASS after effects hooks. Native orbit15cm and source0/90/180review rendered. Native isolated panel PC/mobile equip/unequip PASS.
- TypeScript build PASS. npmtest blocked by pre-existing fixture initializer.registerMatch missing. FullGodot45s runFAIL+timeout(profile/online/combatfixtures); not an all-green release gate.
- Scope local only. Profile/room/Web/Nakama coordinated release remains required. No build/push/deploy performed for this feature. Live account ownership untouched.

2026-10-30 rebake follow-up: current998tri-per-piece candidates use fresh UV+high-source BVH-projected colour512/normal256/MR256 rather than old seam-distorted UVs. Final colour conversion corrected after washed-out first trial. Native source comparison build/relic-1000-baked-comparison.png; coarse silhouettes/faceting remain, user acceptance pending. See runtime.json for actualsizes. Pipeline tools/art/{prepare_relic_rebake.py,bake_relic_surface.py,finish_relic_rebake.py}; no Blender geometry export, no deployment. Obsolete sharedUVtextures archived outside runtime.

## Current release (supersedes earlier trial/pending notes)

Boss approved the rebaked998tri models. Coordinated deployment complete: **2103e952a30f**. See [release evidence](../releases/relic-20261030.md) and [Relic specification](../../relic_spec.md). Earlier unbaked UV warnings and pending/deploy statements above describe historical trials, not the active asset. Silhouette simplification remains intentional and accepted. Current1active slot retained.

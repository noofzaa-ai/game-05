# Skill System migration — work in progress, 2026-10-26

## Boss decisions

- All 20 skills / 20 Gems unlocked initially; present their catalog in Merchant.
- Edit Build only at camp through new Skill menu.
- Skills cost stamina AND cooldown. Remove the player ultimate gauge.
- Disable fists. Equipped weapon family must match tree start. A different family requires a paid full reskill BEFORE switching; swapping items within one family is allowed.
- Retain equipment, fashion, refine aura, normal attacks, movement, economy and existing NPC attacks.
- Initial tuning in data/skill_system/integration.json: reskill 100 Gold; per-skill stamina 10–18. These are editable initial values, not balance approval.

## Activation gate

`integration.json.enabled=false` intentionally. Do not flip or deploy until remaining integration and gameplay acceptance below are complete. This document does NOT mark the system playable or migrated.

## Implemented locally

- Namespaced copy of Lab data/calculator/tree resources under data/skill_system. Presentation PackedScene references removed from simulation resources. Source Lab is untouched.
- Pure RefCounted extraction of Lab caster, actor, targets and full runtime under logic/skills. Scene creation replaced by structured presentation events; target identity uses simulation entity IDs instead of process instance IDs.
- ID-only build validation, 4 unique skills, Gem compatibility, connected tree allocation and 12-point budget. Paid reset and additive allocation rules are authoritative Commands operations, camp-only. Client cannot supply price, damage, costs or resource paths.
- Profile save/migration/read views and snapshot ownership cache carry skill_build. Existing profile IDs/items/gold preserved. Old profiles derive their initial start from their equipped weapon.
- Weapon equip/unequip restrictions are gated with the feature. Reset unlocks cross-family switching; saving relocks to currently equipped family.
- Camp Skill editor draft + save/reset through Session.command. Four slots, compatible Gems and tree allocation list; pinned save/reset actions. Existing Camp tab indices preserved; new Skill tab appended at index4.
- Optional fixed-tick system adapter; attach_run/tick/checkpoint hooks gated by activation. Pure target/resource reference checkpoint encoding; deterministic caster RNG seeded from match and entity ID.
- Input codec supports four slots and bounded aim distance (7 bytes when enabled; legacy 5 while disabled). Room input validation uses the same size.
- Authority profile command allowlist extended narrowly for skill_build.
- Compile inspection of all19 touched/new entry scripts passed, including profile worker, room/snapshot, account/remote sessions, pure runtime and camp/Merchant panels. Sandbox logs still report OS certificate/user-log access warnings; no script parse errors in the final compile log. No behavioral, network, visual, mobile or performance tests run for this migration.

## Required before activation (OPEN)

1. Finish baseline attack/status interaction: frozen critical, bleed leech cap, all-hit burn, kill/consume event ordering, damage scaling with actual equipment, reflect/armor/parry, max HP/movement/dodge/heal passives. No double DEF/vulnerability/damage/death or duplicate loot.
2. Complete death/revive/reset/disconnect cleanup and avoid strong-reference cycles in simulation adapters. Share target status advancement once per tick across all casters; bound proc/jobs/projectile/construct fan-out.
3. Publish and restore Skill runtime in room state/prediction, including late join/reconnect, entity removals, deterministic RNG, frozen aim, and stale/duplicate command handling. Current local checkpoint hook alone is NOT online integration.
4. Bind PC1–4 and mobile four buttons/aim; hide old player Special/Ultimate/gauge and obsolete camera triggers. Preserve movement/guard/dodge ownership and pinch/free camera.
5. Complete HUD read state, cooldown/stamina feedback and skill labels. Current pure system does not yet populate final skill_view.
6. Import native 100 casting clips and MCP effects as production client derivatives; immutable donor rig/material/secondary motion parity; 4-view and interpolation acceptance. Stream effects on demand and respect combat VFX preferences.
7. Merchant read-only skill/Gem catalog is locally wired; final camp graphical tree presentation remains. UI icon source was being populated concurrently; only19 PNG existed at copy time, not a complete40-icon acceptance.
8. Decide/implement run progression boundary for passive point rewards (room/boss, idempotent), match entry with reset tree, missing weapon and disabled weapon families. Current validator uses the 12-point Lab planning budget, not earned room rewards.
9. Reconcile client/server rollout protocol, configuration mount and content hash. Remove obsolete player skill routes/assets ONLY after new paths are accepted. Do not remove authored source or NPC-only skill dependencies.
10. User-authorized verification/release gate: complete regression + authoritative rejection/idempotency + actual landscape/mobile/co-op + performance/export size. No deploy requested in this new scope yet.

## Evidence boundary

Source Lab v3 reports are source evidence only, not evidence that this port passes. Godot compile inspection does not prove gameplay correctness, all20 effects, deterministic replay, device usability or anti-cheat coverage. Keep this feature disabled until proven integrated.

## 2026-10-26 — Online/presentation wiring milestone (still disabled)

Implemented additional production paths locally:
- Binary wire protocol2 carries skill_view; optional 7-byte inputs contain slot and bounded aim distance. Old neutral-frame constants removed. Both Web and room images must roll out together.
- Authoritative-only skill simulation: peers receive bounded slot/pose/status/projectile/construct/zone/buff views. Client predicts ordinary locomotion, interpolates server skill movement, and never computes skill damage. Transient visual/hit/DoT events have dedicated consumers, avoiding legacy move/effect lookups.
- PC1–4, four touch buttons, HUD cooldown/stamina feedback, mouse-ground aim on PC, nearest-enemy assist for touch/UI. Old Special/Ultimate controls and gauge are hidden when enabled; old ultimate prewarming is disabled.
- Native100-clip library and MCP20 effect derivatives imported. Native secondary hair/wing sampling remains on the reference library during external casting clips. VFX follow source recipient scopes. Late-join persistent effects rebuild from public views; client VFX toggle clears them.
- VRAM/mipmap policy applied to128px VFX inputs; copied review thumbnails omitted. GLB material blend modes extracted into small JSON sidecars for exported PCKs (raw GLBs are remapped by Godot). New asset folder participates in content packs and JSON inclusion.
- Base attack hooks now cover passive burn, bleeding leech budget, vulnerability, frozen critical and range/crit modifiers. Dodge applies cold passive and adjusted CD. HP/movement/heal passives feed existing equipment stats. Reflection/armor/parry go through actor incoming hooks. New skill damage/DoT scales by ATK/reference_atk20; source Lab base values remain unmodified.
- New skill kills set combat DEAD and emit the existing single economy kill path; basic-attack passive kills suppress duplicate kill events. Cooldown remaining seconds persist in Run across maps; new runs start fresh. Removed entities are pruned; simulation back-reference is weak.
- Solo entry/party departure require valid matching tree+weapon. Empty reset tree must be saved after selecting the new weapon before departing. All54 tree nodes, including ring/hybrid, are available in the allocation list.
- Minimal headless image preparers now include data/skill_system and generate only the copied scripts' global-class registry. Native compile-only check passed for the minimal room worker without client/art dependencies.

Current verification: editor import and compile-only checks passed for game/UI/room/profile entry scripts. No gameplay regression, two-client session, reconnect replay, physical-mobile acceptance, performance measurement or Web release build has been run for this migration. This is implemented-but-unaccepted integration, NOT evidence of online playability. Existing source-Lab test results do not transfer.

Remaining release gates:
1. Behavior checks of all20 skills/Gem cases/54 passives with real equipment, plus lifecycle/order/loot/refund/rejection cases.
2. Real local two-client authoritative room, join/rejoin/reconnect/death/revive/map transitions and protocol mismatch; inspect packet sizes/CPU and reconciliation.
3. Landscape phone/PC visual/controls acceptance, native grip/secondary motion under all100 clips, performance and Web export asset-size audit.
4. Complete Web/profile/room image builds, remove obsolete player-only export payload after dependency audit, coordinated protocol2 rollout and feature activation. No images pushed or cluster changed.

The first playable tuning continues to use the Lab12-point Build budget; room-earned passive progression is not enabled. Initial reskill100Gold and stamina costs remain config tuning values, not final balance approval.

## Staging release — 2026-10-26

Boss explicitly requested build+deploy and continuation. Activation enabled in staging Web59919b8dd183 with matching profile/room images skill-system-20261026-1. Startup cast applied damage; checkpoint serialize/restore and next tick completed. StateCodec now normalizes StringName fields to string. Public15/15assetsHTTP200; both workers ready. Nakama existing image retained (unchanged runtime rebuild hit upstream429). Earlier disabled milestones above are history. Behavioral/multiplayer/physical-mobile/performance acceptance gates remain unclaimed; this is a staging playtest release, not final acceptance. Rollback and image digests in build/skill-system-release.json.

2026-10-26 — Skill UI follow-up (LOCAL, not deployed): Boss approved mockup. Camp now has a direct Skill shortcut in addition to Menu > Skill. Replaced passive text list with connected Lab tree using actual source positions/links, selectable descriptions, guarded draft allocation and pan/zoom/Fit. Four loadout rows expose Shape/Effect sockets; active slot edits compatible gems and shows computed cast/cooldown/stamina. Existing authoritative save/reset commands unchanged; footer actions stay outside scroll areas. Combat skill buttons now scale to ~55% of actual mobile primary attack and form an arc above the existing combat cluster, with cooldown/stamina feedback. Entry scripts compile; actual Skill panel rendered at landscape1280x720 and960x540. No physical touch, two-client or full regression acceptance, no deploy in this follow-up.

2026-10-26 — skill-ui-20261026-1 DEPLOYED by Boss approval: Web50e910539d57, digest8b81dd13594536b2758340d07a9ca291312546eba10490f2c4f16d294795485e. Direct camp Skill shortcut, actual connected tree/pan/zoom/details,4loadoutslots+Gem, pinned save/reset, round gold mobile skill buttons at55%primaryattack. PC physical key input1–4 checked individually in Godot: correct slots, legacy special/ultimatefalse. Web export/image/rollout/public manifest passed;15/15assetsHTTP200. Web only, room/profile/DB unchanged; no physicalmobile/onlinecombat acceptance claimed. Release/rollback:build/skill-ui-release.json,build/skill-ui-rollback.json.

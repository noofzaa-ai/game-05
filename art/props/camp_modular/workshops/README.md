# Prepared Refine / Upgrade workshops — Lv1–3

Local preparation approved 2026-10-21. All six prop-only GLBs and corresponding Godot prefabs exist. The UpgradeLv1 prefab is now available; earlier visual studies that omit it are historical.

## Use

- Open `res://scenes/workshops/review.tscn` and run the scene. Buttons select Lv1/Lv2/Lv3.
- Instances: `res://scenes/workshops/refine_lv1.tscn` through `refine_lv3.tscn`, and `upgrade_lv1.tscn` through `upgrade_lv3.tscn`.
- `client/workshop.gd`: chooses the prop model and adds the matching NPC in front at local Godot `(0,0,3)`.
- `client/workshop_npc.gd`: gentle in-place Idle/Walk; patrol x±0.9m at0.33m/s in the fixed front lane, pause1.5s at each end. `set_talking(true)` pauses movement for future interaction integration.
- NPC assets: `art/npcs/workshops/bs_refine.glb`, `bs_upgrade.glb`, each **1.50m total standing mesh height** (includes headgear). User-supplied28-bone rigs/weights retained. No player rig replacement.
- FBXs had no clips. New Idle2.0s and Walk1.667s are light procedural FK animations, in place. They do not include foot-contact IK; close-up motion/feet need artistic acceptance before production use.

## Art and dependencies

Shared original Blacksmith color palette/UVs retained. Upgrade uses source benches/anvil/rack/crates/paving, with more tools/work surfaces at higher levels. GLBs reference `../blacksmith/` PNGs; keep the folder relationship. New NPCs share their own external albedo1024/normal512/metallic-roughness512 maps per character, GPU compression and mipmaps for PC/mobile.

Fused-source spatial component boundaries remain a draft limitation documented in the parent README. These are prepared visual prefabs: no collision/navigation mesh, server facility-level costs/unlocks, live Hub placement or separate NPC menu routing have been added. NPC movement is local presentation and never issues inventory/economy commands. Main game startup is unchanged. No deployment.

Builders: `tools/blender/export_workshop_levels.py`, `tools/blender/prepare_workshop_npcs.py`.
Editable NPC sources: `art_source/npcs/workshops/`; original user FBX files remain untouched.
Native preview capture: `tools/shots/workshop_preview.gd`, outputs excluded from game exports under `art_source/props/camp_modular/review/prepared/`.

## Live Hub integration (2026-10-21)

Hub now places Refine at `(8,0,-6.2)` and Upgrade at `(8,0,-0.4)` with their NPC front lanes at z-3.2/2.6. Visual levels read existing profile facility levels `workbench`/`armory`, clamped1–3. The UpgradeLv1 visual is present even before an armory is built; this is presentation, not a new server unlock. Menus route the two NPC roles separately, and development continues through the existing authoritative upgrade commands. Talking pauses that NPC and closing resumes it.

NPCs now independently randomize starting pause0.3–5s, each walking segment1.1–4.8s, speed0.25–0.40m/s, local target inside±0.9m and each pause1–5.5s. They remain in the front lane. No synchronized seed or shared timing.

Development menu shows one selected facility at a time with cost and effects from CampData. Campfire/Refine/Upgrade next-level art is256×192; levels above3 are explicitly labelled as a Lv3 reference. Other facilities without authored level art display an explicit missing-preview label. This does not change costs/effects or implement the future farm/area system.

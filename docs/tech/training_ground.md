# Camp training ground — local implementation, 2026-10-29

Boss approved a west-side training clearing with five straw targets in a straight, evenly spaced row. Existing camp, shops, shared northern plaza, and Lv2 farm remain in place. Entrance is west of the quest board near(-11,0,5.8); yard center(-18,0,4),14×13m. Existing southwest corner blocker requires the entrance north of z7: the final native walking test covers this rather than teleporting across a collider.

## Behavior

Walking into the yard activates the current equipped weapon, saved skill/Gem/passive build, actual GameSim combat and the existing mobile controls/four skill buttons. PC retains normal attack keys and1–4. PC aims at the ground mouse ray; mobile selects nearest dummy. Targets are stationary; each receives its own hits and statuses through the existing skill system. The ordinary status presenter shows those statuses. Five target IDs901–905 span8.4m at2.1m spacing.

TrainingGround is disposable logic with NO Run, item rules, loot data, reward commands or profile reference. Configure copies stats/style/build. Consequently practice does not wear equipment, award money/items/points or save a run result. It is a local preview of the equipped build, not an authoritative online PvE match. Dummies have1e9HP and are refilled/pinned after every tick; normal knockback cannot move them away permanently. HP is not mathematically infinite; deliberately extreme modified client damage is outside this visual sandbox's acceptance.

Reset clears target statuses, skill cooldowns, projectiles/constructs and counters, and refills stamina. Exit cancels practice combat/statuses and restores camp walking/shortcuts. Build opens the existing authority-backed skill screen; saving still uses its normal server command path. No ability is purchased or unlocked by training. Missing weapon/valid build displays a setup hint. Practice resets on equipment/build refresh. Skill/status graph disposal prevents repeat Reset from accumulating subscribed graphs.

## Files

- logic/training_ground.gd: non-persistent simulation wrapper and zone/targets.
- client/training_arena.gd / training_dummy.gd: native procedural yard/targets, combat presentation, Reset/Build controls.
- hub.gd / mobile_controls.gd: automatic control ownership and exit restoration.
- hub_world.gd: west boundary opening and new map derivative, preserving farm level locks.
- tools/maps/prepare_training_camp.py: derives camp_training.glb from existing camp_hub.glb. Generic optional rect/group arguments added to split_farm_trees.py preserve its existing defaults. Original camp/farm source stays intact.

## Art and cost

No new texture downloads: painted low-poly dummy uses1material surface,1180tri; five targets5900tri. Fence/yard boxes batched by material, shadowless point lights. Existing camp terrain/pines are split by connected components:32complete west pines plus small props1064tri moved into a hidden TrainingBoundaryTrees group. Camp source and existing FarmBoundaryTrees remain preserved; no scene/gameplay generator content is replaced globally. Floor sits15mm above the flat terrain to avoid z-fighting; dirt patches sit above it.

Native PC1440×810 and mobile844×390 review images: build/training-hub-1440.png,training-hub-844.png,training-aoe-844.png. These are actual Godot images, not the generated concept. The procedural yard is simpler than the concept illustration.

## Verification and limits

- tests/training_ground.gd PASS: actual area skill hits at least3separate targets, actual burn observed, targets fixed/alive, reset cooldown/stamina/status, exit disables combat, no Run/loot/wear interfaces.
- tests/training_hub_touch.gd PASS: actual camp collider entrance walk, mobile combat activation, skill button via ordinary input queue hits3targets, full actual profile.to_dict unchanged incl wallet/build/gear/wear, reset and exit restore original controls. Native invocation passed before final floor-only adjustment; final headless viewport invocation passed after adjustment. Teardown reports a small resource/ObjectDB warning, not a full leak-free acceptance.
- tools/shots/farm_tree_clearance_review.gd PASS: Lv1/Lv2 vegetation visibility and all four farm plots retained.
- Full run_all attempted60s; existing profile/online/legacy skill failures and timeout remain. No full-suite pass, physical-phone/Web combat, online account save or FPS benchmark claim.

NOT built, pushed or deployed as part of this local feature task. Live remains VFX buildc11ef07e658a until a release is requested/prepared. No server worker/account data changes.
